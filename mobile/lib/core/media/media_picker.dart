import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import 'media_models.dart';

enum PermissionState { granted, denied, permanentlyDenied, unavailable }

/// Wraps platform permissions with a helpful state machine.
class MediaPermissions {
  Future<PermissionState> _map(PermissionStatus s) async {
    if (s.isGranted || s.isLimited) return PermissionState.granted;
    if (s.isPermanentlyDenied) return PermissionState.permanentlyDenied;
    if (s.isRestricted) return PermissionState.unavailable;
    return PermissionState.denied;
  }

  Future<PermissionState> camera() async {
    if (await Permission.camera.isGranted) return PermissionState.granted;
    final status = await Permission.camera.request();
    return _map(status);
  }

  Future<PermissionState> microphone() async {
    if (await Permission.microphone.isGranted) return PermissionState.granted;
    final status = await Permission.microphone.request();
    return _map(status);
  }

  Future<PermissionState> photos() async =>
      _map(await Permission.photos.status);

  Future<void> openSettings() async => openAppSettings();
}

final mediaPermissionsProvider = Provider<MediaPermissions>((ref) {
  return MediaPermissions();
});

/// Picks media from the device (gallery/camera/video/documents) and normalizes
/// everything into [LocalMediaItem]s for the shared upload queue.
class MediaPickerService {
  final ImagePicker _imagePicker = ImagePicker();
  static const _maxImageDimension = 1920.0;
  static const _imageQuality = 85;

  Future<List<LocalMediaItem>> pickImages({int limit = 5}) async {
    final List<XFile> files;
    try {
      files = await _imagePicker.pickMultiImage(
        maxWidth: _maxImageDimension,
        maxHeight: _maxImageDimension,
        imageQuality: _imageQuality,
      );
    } catch (e) {
      // E.g. picker cancelled/permission race on some devices: treat as no pick.
      debugPrint('picker.pickImages failed: $e');
      return [];
    }
    if (files.isEmpty) return [];
    return [
      for (final f in files.take(limit)) await _fromXFile(f, MediaKind.image),
    ];
  }

  Future<LocalMediaItem?> takePhoto() async {
    final XFile? file;
    try {
      file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: _maxImageDimension,
        maxHeight: _maxImageDimension,
        imageQuality: _imageQuality,
      );
    } catch (e) {
      debugPrint('picker.takePhoto failed: $e');
      return null;
    }
    if (file == null) return null;
    return _fromXFile(file, MediaKind.image);
  }

  Future<LocalMediaItem?> pickVideo({bool fromCamera = false}) async {
    final XFile? file;
    try {
      file = await _imagePicker.pickVideo(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
    } catch (e) {
      debugPrint('picker.pickVideo failed: $e');
      return null;
    }
    if (file == null || file.path.isEmpty) return null;
    final size = await File(file.path).length();
    return LocalMediaItem(
      id: const Uuid().v4(),
      kind: MediaKind.video,
      path: file.path,
      fileName: file.name,
      mimeType: 'video/mp4',
      sizeBytes: size,
    );
  }

  Future<List<LocalMediaItem>> pickDocuments({int limit = 3}) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: false,
      );
    } catch (e) {
      debugPrint('picker.pickDocuments failed: $e');
      return [];
    }
    if (result == null || result.files.isEmpty) return [];
    final out = <LocalMediaItem>[];
    for (final f in result.files.take(limit)) {
      if (f.path == null) continue;
      out.add(LocalMediaItem(
        id: const Uuid().v4(),
        kind: MediaKind.document,
        path: f.path!,
        fileName: f.name,
        sizeBytes: f.size,
        mimeType: _mimeFromName(f.name),
      ));
    }
    return out;
  }

  Future<LocalMediaItem> _fromXFile(XFile f, MediaKind kind) async {
    final size = await File(f.path).length();
    return LocalMediaItem(
      id: const Uuid().v4(),
      kind: kind,
      path: f.path,
      fileName: f.name,
      sizeBytes: size,
      mimeType: _mimeFromName(f.name),
    );
  }

  String _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  }
}

final mediaPickerProvider = Provider<MediaPickerService>((ref) {
  return MediaPickerService();
});
