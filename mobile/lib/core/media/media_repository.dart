import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../network/api_client.dart';
import '../storage/token_store.dart';
import 'media_models.dart';

/// Single place that talks to the backend `/api/v1/media/*` backbone and
/// builds media URLs for display. No widget should hardcode `/uploads/…`.
class MediaRepository {
  MediaRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  /// Absolute URL for fetching a served file (needs auth header).
  String assetUrl(String storageKey) =>
      '${AppConfig.apiBaseUrl}/media/serve/${Uri.encodeComponent(storageKey)}';

  String thumbnailUrlOf(RemoteMedia m) =>
      m.thumbnailUrl != null && m.thumbnailUrl!.isNotEmpty
          ? _absolute(m.thumbnailUrl!)
          : '';

  /// Resolves a backend-relative media URL (e.g. `media/serve/<key>` or
  /// `api/...`) into an absolute display URL. Returns '' for null/empty.
  String resolveUrl(String? partial) =>
      partial == null || partial.isEmpty ? '' : _absolute(partial);

  String _absolute(String partial) {
    if (partial.startsWith('http')) return partial;
    final cleaned = partial.replaceFirst(RegExp(r'^/+'), '');
    // Serve + API media routes live at the host root, not under /api/v1.
    if (cleaned.startsWith('api/') || cleaned.startsWith('media/')) {
      return '${AppConfig.apiBaseUrl.split('/api/v1').first}/$cleaned';
    }
    return '${AppConfig.apiBaseUrl}/$cleaned';
  }

  /// Request headers needed by cacheable image widgets (anonymous
  /// CachedNetworkImage can't send the JWT).
  Future<Map<String, String>> authHeaders() async {
    final access = await _tokens.readAccess();
    return access == null ? const {} : {'Authorization': 'Bearer $access'};
  }

  /// Uploads one local media item to `/api/v1/media/upload`.
  ///
  /// Streams the file from disk (in-memory captures use their held bytes) so
  /// large photos/documents don't spike RAM and uploads start immediately.
  Future<RemoteMedia> upload(
    LocalMediaItem item, {
    String? category,
    String? contextType,
    String? contextId,
    int? durationMs,
    String? mimeType,
    void Function(double fraction)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final fileName = item.fileName.isEmpty ? 'file' : item.fileName;
    final contentType =
        DioMediaType.parse(mimeType ?? item.mimeType ?? _guessMime(fileName));
    final filePart = item.bytes != null
        ? MultipartFile.fromBytes(
            item.bytes!,
            filename: fileName,
            contentType: contentType,
          )
        : MultipartFile.fromFile(
            item.path,
            filename: fileName,
            contentType: contentType,
          );
    final form = FormData.fromMap({
      'category': category ?? mediaKindToCategory(item.kind),
      if (contextType != null) 'context_type': contextType,
      if (contextId != null) 'context_id': contextId,
      if (durationMs != null) 'duration_ms': durationMs,
      'file': filePart,
    });
    final response = await _api.dio.post(
      '/media/upload',
      data: form,
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent / total);
      },
      cancelToken: cancelToken,
    );
    return RemoteMedia.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(String assetId) async {
    if (assetId.isEmpty) return;
    await _api.delete('/media/$assetId');
  }

  Future<RemoteMedia> attach(
      String assetId, String contextType, String contextId) async {
    final res = await _api.postJson('/media/$assetId/attach',
        {'context_type': contextType, 'context_id': contextId});
    return RemoteMedia.fromJson(res);
  }

  String _guessMime(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.m4a') || lower.endsWith('.mp4a')) return 'audio/mp4';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }
}

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(
      ref.watch(apiClientProvider), ref.watch(tokenStoreProvider));
});
