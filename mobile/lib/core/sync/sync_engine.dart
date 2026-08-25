import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../storage/local_db.dart';

/// Offline-first sync engine.
///
/// - Every user mutation goes through [enqueue] and is applied locally
///   immediately (optimistic), then pushed to the server when online.
/// - The server deduplicates pushes by `client_op_id`, so retries are safe.
/// - [pull] refreshes cached collections using incremental cursors.
class SyncEngine {
  SyncEngine(this._ref, this._db, this._api);

  final Ref _ref;
  final LocalDb _db;
  final ApiClient _api;
  final Random _random = Random();

  static const syncableCollections = [
    'listings',
    'conversations',
    'orders',
    'notifications',
    'market_prices',
    'advisory',
  ];

  Timer? _timer;

  void startPeriodicSync({Duration every = const Duration(minutes: 2)}) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => syncAll());
  }

  String newOpId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      _random.nextInt(0x7fffffff).toRadixString(36);

  Future<void> enqueue(String opType, Map<String, dynamic> payload) async {
    await _db.enqueueOp(
      clientOpId: newOpId(),
      opType: opType,
      payload: payload,
    );
    unawaited(pushOutbox());
  }

  /// Drains the outbox. Server returns per-op results; DUPLICATE entries are
  /// treated as success (idempotency), REJECTED are dropped (poison-pill
  /// guard), anything else retries later.
  Future<int> pushOutbox() async {
    var delivered = 0;
    while (true) {
      final ops = await _db.pendingOps(limit: 25);
      if (ops.isEmpty) break;
      try {
        final res = await _api.postJson('/sync/push', {
          'operations': [
            for (final o in ops)
              {
                'client_op_id': o['client_op_id'],
                'op_type': o['op_type'],
                'payload':
                    Map<String, dynamic>.from(jsonDecode(o['payload'] as String)),
              }
          ],
        });
        final results = (res['results'] as List?) ?? const [];
        for (final result in results) {
          final r = result as Map<String, dynamic>;
          switch (r['status'] as String?) {
            case 'OK':
            case 'DUPLICATE':
            case 'REJECTED':
              await _db.removeOp(r['client_op_id'] as String);
              if (r['status'] != 'REJECTED') delivered++;
              break;
            default:
              await _db.incrementAttempts(r['client_op_id'] as String);
          }
        }
        if (results.length < ops.length) break;
      } catch (_) {
        for (final o in ops) {
          await _db.incrementAttempts(o['client_op_id'] as String);
        }
        break; // offline; retry on next trigger
      }
    }
    return delivered;
  }

  Future<void> pull({List<String>? collections}) async {
    final wanted = collections ?? syncableCollections;
    final cursors = <String, String>{};
    for (final c in wanted) {
      final cursor = await _db.readCursor(c);
      if (cursor != null) cursors[c] = cursor;
    }
    try {
      final res = await _api.getJson('/sync/pull', query: {
        'collections': wanted.join(','),
        // Backend reads cursors as "<collection>_cursor" query params.
        for (final e in cursors.entries) '${e.key}_cursor': e.value,
      });
      final body = (res['collections'] as Map<String, dynamic>);
      final newCursors =
          (res['cursors'] as Map<String, dynamic>?) ?? const {};
      for (final entry in body.entries) {
        final collection = entry.key;
        final payload = entry.value;
        if (payload is! Map<String, dynamic>) continue;
        for (final item in (payload['items'] as List? ?? const [])) {
          final entity = item as Map<String, dynamic>;
          await _db.upsertCache(
            collection,
            entity['id'] as String? ?? newOpId(),
            entity,
            updatedAt: entity['updated_at'] as String?,
          );
        }
        final cursor = newCursors[collection];
        if (cursor is String) await _db.saveCursor(collection, cursor);
      }
    } catch (_) {
      // offline: cache stays as-is
    }
  }

  Future<void> syncAll() async {
    await pushOutbox();
    await pull();
  }

  void dispose() {
    _timer?.cancel();
  }
}

final syncEngineProvider = FutureProvider.autoDispose<SyncEngine>((ref) async {
  final db = await ref.watch(localDbProvider.future);
  final engine = SyncEngine(ref, db, ref.watch(apiClientProvider));
  ref.keepAlive();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Exposes outbox pending count for UI badges.
final pendingSyncCountProvider = StreamProvider<int>((ref) async* {
  while (true) {
    final db = await ref.watch(localDbProvider.future);
    yield await db.pendingCount();
    await Future<void>.delayed(const Duration(seconds: 5));
  }
});
