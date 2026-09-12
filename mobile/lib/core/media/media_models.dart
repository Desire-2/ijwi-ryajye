import 'dart:io';
import 'dart:typed_data';

/// Kinds of media supported by the shared backbone. Maps onto backend
/// upload categories (image/video/voice/document).
enum MediaKind { image, video, audio, document }

MediaKind mediaKindFromString(String? s) {
  switch ((s ?? '').toLowerCase()) {
    case 'image':
    case 'IMAGE':
      return MediaKind.image;
    case 'video':
    case 'VIDEO':
      return MediaKind.video;
    case 'audio':
    case 'voice':
    case 'AUDIO':
    case 'VOICE':
      return MediaKind.audio;
    default:
      return MediaKind.document;
  }
}

String mediaKindToCategory(MediaKind kind) {
  switch (kind) {
    case MediaKind.image:
      return 'image';
    case MediaKind.video:
      return 'video';
    case MediaKind.audio:
      return 'voice';
    case MediaKind.document:
      return 'document';
  }
}

/// A file selected/created on the device, before upload.
class LocalMediaItem {
  LocalMediaItem({
    required this.id,
    required this.kind,
    required this.path,
    required this.fileName,
    this.mimeType,
    this.sizeBytes = 0,
    this.width,
    this.height,
    this.durationMs = 0,
    this.thumbnailPath,
    this.bytes,
  });

  final String id;
  final MediaKind kind;
  final String path;
  final String fileName;
  final String? mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int durationMs;
  final String? thumbnailPath;
  final Uint8List? bytes;

  LocalMediaItem copyWith({
    int? sizeBytes,
    int? width,
    int? height,
    int? durationMs,
    String? mimeType,
  }) {
    return LocalMediaItem(
      id: id,
      kind: kind,
      path: path,
      fileName: fileName,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      mimeType: mimeType ?? this.mimeType,
      thumbnailPath: thumbnailPath,
      bytes: bytes,
    );
  }

  /// The raw file bytes for upload: from memory when captured (camera),
  /// otherwise read from disk.
  Future<Uint8List> readBytes() async {
    if (bytes != null) return bytes!;
    return File(path).readAsBytes();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'path': path,
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        'durationMs': durationMs,
        'mimeType': mimeType,
      };

  factory LocalMediaItem.fromJson(Map<String, dynamic> j) => LocalMediaItem(
        id: j['id'] as String,
        kind: mediaKindFromString(j['kind'] as String?),
        path: j['path'] as String,
        fileName: j['fileName'] as String? ?? '',
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        mimeType: j['mimeType'] as String?,
      );
}

/// A media asset as returned by the backend `/api/v1/media/*` endpoints.
class RemoteMedia {
  RemoteMedia({
    required this.id,
    required this.storageKey,
    required this.url,
    required this.mediaType,
    this.thumbnailUrl,
    this.fileName,
    this.width,
    this.height,
    this.durationMs,
    this.sizeBytes,
    this.contextType,
    this.contextId,
  });

  final String id;
  final String storageKey;
  final String url;
  final String mediaType;
  final String? thumbnailUrl;
  final String? fileName;
  final int? width;
  final int? height;
  final int? durationMs;
  final int? sizeBytes;
  final String? contextType;
  final String? contextId;

  bool get isImage =>
      mediaType.startsWith('IMAGE') ||
      (url.contains('/serve/') && (mediaType == 'image'));
  bool get isVideo => mediaType.startsWith('VIDEO');
  bool get isAudio => mediaType.startsWith('AUDIO');
  bool get isDocument => mediaType.startsWith('DOCUMENT');

  factory RemoteMedia.fromJson(Map<String, dynamic> j) => RemoteMedia(
        id: j['id'] as String? ?? '',
        storageKey: j['storage_key'] as String? ?? '',
        url: j['url'] as String? ?? '',
        mediaType: j['media_type'] as String? ?? 'IMAGE',
        thumbnailUrl: j['thumbnail_url'] as String?,
        fileName: j['file_name'] as String?,
        width: (j['width'] as num?)?.toInt(),
        height: (j['height'] as num?)?.toInt(),
        durationMs: (j['duration_ms'] as num?)?.toInt(),
        sizeBytes: (j['size_bytes'] as num?)?.toInt(),
        contextType: j['context_type'] as String?,
        contextId: j['context_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'storage_key': storageKey,
        'url': url,
        'media_type': mediaType,
        'thumbnail_url': thumbnailUrl,
        'file_name': fileName,
        'width': width,
        'height': height,
        'duration_ms': durationMs,
        'size_bytes': sizeBytes,
        'context_type': contextType,
        'context_id': contextId,
      };
}

enum UploadStatus { queued, uploading, processing, ready, failed, cancelled }

/// One queued/uploading upload in the shared [MediaUploadQueue].
class UploadTask {
  UploadTask({
    required this.localId,
    required this.item,
    required this.category,
    this.contextType,
    this.contextId,
    this.status = UploadStatus.queued,
    this.progress = 0,
    this.error,
    this.result,
    this.retryCount = 0,
  });

  final String localId;
  final LocalMediaItem item;
  final String category;
  final String? contextType;
  final String? contextId;
  UploadStatus status;
  double progress;
  String? error;
  RemoteMedia? result;
  int retryCount;

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'item': item.toJson(),
        'category': category,
        'contextType': contextType,
        'contextId': contextId,
        'status': status.name,
        'retryCount': retryCount,
        'result': result?.toJson(),
      };

  factory UploadTask.fromJson(Map<String, dynamic> j) => UploadTask(
        localId: j['localId'] as String? ?? '',
        item: LocalMediaItem.fromJson(j['item'] as Map<String, dynamic>),
        category: j['category'] as String? ?? 'image',
        contextType: j['contextType'] as String?,
        contextId: j['contextId'] as String?,
        status: UploadStatus.values
                .where((s) => s.name == j['status'])
                .firstOrNull ??
            UploadStatus.queued,
        retryCount: (j['retryCount'] as num?)?.toInt() ?? 0,
        result: j['result'] != null
            ? RemoteMedia.fromJson(j['result'] as Map<String, dynamic>)
            : null,
      );
}
