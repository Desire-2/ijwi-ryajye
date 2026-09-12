import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../network/api_client.dart';
import 'media_models.dart';
import 'media_repository.dart';

/// Shared upload manager: enqueue local media, upload sequentially with
/// progress/retry/cancel, survive restarts (queue persisted to disk) and
/// pause/resume based on connectivity.
///
/// Every feature (chat, community, listings, status, profile) pushes media
/// here instead of owning its own upload code.
class MediaUploadQueue extends Notifier<List<UploadTask>> {
  static const _fileName = 'media_upload_queue.json';
  final Map<String, CancelToken> _cancelTokens = {};
  bool _pumping = false;
  bool _running = false;
  DateTime _nextAllowedAttempt = DateTime.now();
  final _retryBackoff = Duration(seconds: 4);
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  @override
  List<UploadTask> build() {
    _running = true;
    _restore();
    _watchConnectivity();
    ref.onDispose(() {
      _running = false;
      _connSub?.cancel();
    });
    return [];
  }

  Future<void> _restore() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
        final tasks = raw
            .map((e) => UploadTask.fromJson(e as Map<String, dynamic>))
            .where((t) =>
                t.status == UploadStatus.queued ||
                t.status == UploadStatus.failed)
            .map((t) {
          t.status = UploadStatus.queued;
          return t;
        }).toList();
        if (tasks.isNotEmpty) {
          state = [...tasks];
          _pump();
        }
      }
    } catch (_) {}
  }

  void _watchConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        _nextAllowedAttempt = DateTime.now();
        _pump();
      }
    });
  }

  /// Add media to the queue.
  void enqueue(
    List<LocalMediaItem> items, {
    String? category,
    String? contextType,
    String? contextId,
  }) {
    if (items.isEmpty) return;
    final tasks = items.map((item) => UploadTask(
          localId: item.id,
          item: item,
          category: category ?? mediaKindToCategory(item.kind),
          contextType: contextType,
          contextId: contextId,
        ));
    state = [...state, ...tasks];
    _persist();
    _pump();
  }

  void cancel(String localId) {
    final token = _cancelTokens.remove(localId);
    if (token != null) token.cancel();
    state = [
      for (final t in state)
        if (t.localId == localId)
          (t
            ..status = UploadStatus.cancelled
            ..error = 'Cancelled')
        else
          t,
    ];
    _persist();
  }

  void retry(String localId) {
    state = [
      for (final t in state)
        if (t.localId == localId)
          (t
            ..status = UploadStatus.queued
            ..error = null
            ..retryCount = (t.retryCount) + 1)
        else
          t,
    ];
    _cancelTokens.remove(localId);
    _persist();
    _pump();
  }

  void markDone(String localId) {
    state = [
      for (final t in state)
        if (t.localId == localId) (t..status = UploadStatus.ready) else t,
    ];
  }

  void remove(String localId) {
    _cancelTokens.remove(localId);
    state = state.where((t) => t.localId != localId).toList();
    _persist();
  }

  /// Successful remote media for a given context (used at publish time).
  List<RemoteMedia> readyFor(String? contextId) => [
        for (final t in state)
          if (t.status == UploadStatus.ready &&
              t.result != null &&
              (contextId == null || t.contextId == contextId))
            t.result!,
      ];

  /// Storage keys of everything ready (for backward-compatible payloads).
  List<String> readyStorageKeys(String? contextId) =>
      readyFor(contextId).map((r) => r.storageKey).toList();

  void clearFinished() {
    state = state
        .where((t) =>
            t.status == UploadStatus.uploading ||
            t.status == UploadStatus.queued)
        .toList();
    _persist();
  }

  static UploadTask? _nextTask(List<UploadTask> tasks) {
    UploadTask? queued;
    UploadTask? failed;
    for (final t in tasks) {
      if (t.status == UploadStatus.queued) {
        queued ??= t;
      } else if (t.status == UploadStatus.failed && failed == null) {
        failed = t;
      }
    }
    return queued ?? failed;
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    while (_running) {
      final next = _nextTask(state);
      if (next == null) break;

      final waitMs =
          _nextAllowedAttempt.difference(DateTime.now()).inMilliseconds;
      if (waitMs > 0) {
        await Future.delayed(Duration(milliseconds: waitMs.clamp(0, 20000)));
      }
      if (!_running) break;

      final token = CancelToken();
      _cancelTokens[next.localId] = token;
      final idx = state.indexWhere((t) => t.localId == next.localId);
      if (idx < 0) {
        _cancelTokens.remove(next.localId);
        continue;
      }
      this.state = [
        for (final t in state)
          if (t.localId == next.localId)
            (t
              ..status = UploadStatus.uploading
              ..progress = 0)
          else
            t,
      ];
      _persist();

      try {
        final media = await ref.read(mediaRepositoryProvider).upload(
          next.item,
          category: next.category,
          contextType: next.contextType,
          contextId: next.contextId,
          durationMs: next.item.durationMs > 0 ? next.item.durationMs : null,
          mimeType: next.item.mimeType,
          onProgress: (fraction) {
            if (!_running) return;
            final i = state.indexWhere((t) => t.localId == next.localId);
            if (i >= 0) {
              this.state = [
                for (final t in state)
                  if (t.localId == next.localId)
                    (t
                      ..progress = (fraction * 100).clamp(0, 100)
                      ..status = UploadStatus.uploading)
                  else
                    t,
              ];
            }
          },
          cancelToken: token,
        );
        _cancelTokens.remove(next.localId);
        this.state = [
          for (final t in state)
            if (t.localId == next.localId)
              (t
                ..status = UploadStatus.ready
                ..progress = 100
                ..result = media
                ..error = null)
            else
              t,
        ];
        _nextAllowedAttempt = DateTime.now();
      } on DioException catch (e) {
        final cancelled = e.type == DioExceptionType.cancel;
        _cancelTokens.remove(next.localId);
        if (!_running || cancelled) {
          if (cancelled) {
            this.state = [
              for (final t in state)
                if (t.localId == next.localId)
                  (t
                    ..status = UploadStatus.cancelled
                    ..error = 'Cancelled')
                else
                  t,
            ];
          }
          continue;
        }
        final offline = ApiClient.isOfflineError(e);
        this.state = [
          for (final t in state)
            if (t.localId == next.localId)
              (t
                ..status = offline ? UploadStatus.queued : UploadStatus.failed
                ..error = offline
                    ? 'Offline — waiting for network'
                    : ApiClient.errorMessage(e)
                ..retryCount = (t.retryCount) + 1)
            else
              t,
        ];
        // Backoff for server errors; offline waits for connectivity re-fires.
        if (offline) {
          _nextAllowedAttempt = DateTime.now().add(const Duration(minutes: 2));
        } else {
          final factor = next.retryCount == 0 ? 1 : next.retryCount;
          _nextAllowedAttempt = DateTime.now().add(Duration(
              seconds: (factor.clamp(1, 6)) * _retryBackoff.inSeconds));
        }
      } catch (e) {
        _cancelTokens.remove(next.localId);
        this.state = [
          for (final t in state)
            if (t.localId == next.localId)
              (t
                ..status = UploadStatus.failed
                ..error = ApiClient.errorMessage(e))
            else
              t,
        ];
        _nextAllowedAttempt = DateTime.now().add(_retryBackoff);
      }
      _persist();
    }
    _pumping = false;
  }

  void _persist() {
    final done = state
        .where((t) => t.status != UploadStatus.ready)
        .toList(growable: false);
    Future(() async {
      try {
        final dir = await getApplicationSupportDirectory();
        final file = File('${dir.path}/$_fileName');
        await file
            .writeAsString(jsonEncode(done.map((t) => t.toJson()).toList()));
      } catch (_) {}
    });
  }
}

final mediaUploadQueueProvider =
    NotifierProvider<MediaUploadQueue, List<UploadTask>>(MediaUploadQueue.new);
