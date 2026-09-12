import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/media/media_models.dart';
import '../../core/media/media_picker.dart';
import '../../core/media/media_upload_queue.dart';
import '../../core/media/media_widgets.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import 'community_service.dart';

/// Status/story composer. A status is a short-lived update with optional
/// caption + images/video uploaded through the shared media backbone.
class StatusComposerScreen extends ConsumerStatefulWidget {
  const StatusComposerScreen({super.key});

  @override
  ConsumerState<StatusComposerScreen> createState() =>
      _StatusComposerScreenState();
}

class _StatusComposerScreenState extends ConsumerState<StatusComposerScreen> {
  final _bodyCtl = TextEditingController();
  final List<LocalMediaItem> _media = [];
  bool _publishing = false;

  @override
  void dispose() {
    _bodyCtl.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final action = await showMediaPickerSheet(context, actions: const [
      MediaPickAction.camera,
      MediaPickAction.gallery,
      MediaPickAction.video,
    ]);
    if (action == null || !mounted) return;
    final picker = ref.read(mediaPickerProvider);
    List<LocalMediaItem>? picked;
    switch (action) {
      case MediaPickAction.camera:
        final perm = await ref.read(mediaPermissionsProvider).camera();
        if (perm != PermissionState.granted) break;
        final photo = await picker.takePhoto();
        if (photo != null) picked = [photo];
      case MediaPickAction.gallery:
        picked = await picker.pickImages(limit: 3);
      case MediaPickAction.video:
        final v = await picker.pickVideo();
        if (v != null) picked = [v];
      case MediaPickAction.document:
      case MediaPickAction.voice:
      case MediaPickAction.shareListing:
        break;
    }
    if (picked != null && picked.isNotEmpty) {
      setState(() => _media.addAll(picked!));
      ref.read(mediaUploadQueueProvider.notifier).enqueue(picked);
    }
  }

  /// Waits for every selected media item to finish uploading and returns
  /// their storage keys in selection order.
  Future<List<String>> _uploadedKeys() async {
    final ids = _media.map((e) => e.id).toList();
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      final tasks = ref.read(mediaUploadQueueProvider);
      final ready = ids
          .every((id) => tasks.any((t) => t.localId == id && t.result != null));
      if (ready) break;
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return [];
    }
    final keys = <String>[];
    for (final id in ids) {
      final t = ref
          .read(mediaUploadQueueProvider)
          .where((x) => x.localId == id)
          .firstOrNull;
      if (t?.result != null) keys.add(t!.result!.storageKey);
    }
    return keys;
  }

  Future<void> _publish() async {
    if (_bodyCtl.text.trim().isEmpty && _media.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add a caption or some media')));
      return;
    }
    setState(() => _publishing = true);
    final svc = ref.read(communityServiceProvider);
    try {
      final mediaKeys =
          _media.isEmpty ? const <String>[] : await _uploadedKeys();
      if (_media.isNotEmpty && mediaKeys.length < _media.length) {
        if (mounted) {
          setState(() => _publishing = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Some media is still uploading. Retry when online.')));
        }
        return;
      }
      await svc.createStatus(
        statusType: 'text',
        bodyText: _bodyCtl.text.trim().isEmpty ? null : _bodyCtl.text.trim(),
        mediaKeys: mediaKeys.isEmpty ? null : mediaKeys,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Status shared')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _publishing = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share an update'),
        actions: [
          TextButton(
            onPressed: _publishing ? null : _publish,
            child: _publishing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Post'),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _bodyCtl,
          maxLines: 4,
          maxLength: 600,
          decoration: InputDecoration(
            hintText: 'What is happening on your farm today?',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        MediaGridEditor(
          items: _media,
          onRemove: (item) => setState(() => _media.remove(item)),
          onAdd: _pickMedia,
        ),
        const SizedBox(height: 16),
        Row(children: [
          Icon(Icons.schedule,
              size: 16, color: IjwiColors.muted.withOpacity(0.8)),
          const SizedBox(width: 6),
          const Text('Visible for 24 hours',
              style: TextStyle(fontSize: 12, color: IjwiColors.muted)),
          const Spacer(),
          TextButton.icon(
            onPressed: _pickMedia,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Add photo or video'),
          ),
        ]),
      ]),
    );
  }
}
