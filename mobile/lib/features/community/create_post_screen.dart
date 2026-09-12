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
import 'community_widgets.dart';

/// Post composer with agricultural post types, topic tags, and optional
/// deep-link into the marketplace listing flow.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({
    this.groupId,
    this.communityId,
    this.initialType = 'text',
    super.key,
  });

  final String? groupId;
  final String? communityId;
  final String initialType;

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _bodyCtl = TextEditingController();
  final _titleCtl = TextEditingController();
  final _topicCtl = TextEditingController();
  final _locationCtl = TextEditingController();

  late String _type = widget.initialType;
  bool _publishing = false;

  final List<LocalMediaItem> _media = [];

  @override
  void initState() {
    super.initState();
    _restoreDraft();
  }

  void _restoreDraft() {
    final draft = CommunityServiceProvider.pendingDraft;
    if (draft != null && draft.isNotEmpty) {
      _bodyCtl.text = draft;
    }
  }

  @override
  void dispose() {
    // Autosave draft so it survives navigation.
    CommunityServiceProvider.pendingDraft = _bodyCtl.text;
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final action = await showMediaPickerSheet(context, actions: const [
      MediaPickAction.camera,
      MediaPickAction.gallery,
      MediaPickAction.video,
      MediaPickAction.document,
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
        picked = await picker.pickImages(limit: 5);
      case MediaPickAction.video:
        final v = await picker.pickVideo();
        if (v != null) picked = [v];
      case MediaPickAction.document:
        picked = await picker.pickDocuments(limit: 3);
      case MediaPickAction.shareListing:
        break;
      case MediaPickAction.voice:
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
    final body = _bodyCtl.text.trim();
    if (body.isEmpty && _media.isEmpty && _type != 'poll') {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Write something to post')));
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
      final topics = _topicCtl.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      await svc.createPost(
        postType: _type,
        title: _titleCtl.text.trim(),
        bodyText: body,
        mediaKeys: mediaKeys,
        groupId: widget.groupId,
        communityId: widget.communityId,
        topicTags: topics,
        location:
            _locationCtl.text.trim().isEmpty ? null : _locationCtl.text.trim(),
      );
      CommunityServiceProvider.pendingDraft = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Posted to your community')));
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
        title: const Text('Create post'),
        actions: [
          TextButton(
            onPressed: _publishing ? null : _publish,
            child: const Text('Post',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Choose post type',
              style: TextStyle(
                  color: IjwiColors.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _typeSelector(),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtl,
            decoration: const InputDecoration(hintText: 'Title (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtl,
            maxLines: 6,
            minLines: 4,
            decoration: InputDecoration(
              hintText: _type == 'question'
                  ? 'Ask the community…'
                  : "What's happening on your farm?",
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _topicCtl,
            decoration: const InputDecoration(
              hintText: 'Add topics, comma separated (e.g. Coffee, Organic)',
              prefixIcon: Icon(Icons.tag, color: IjwiColors.muted),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationCtl,
            decoration: const InputDecoration(
              hintText: 'Location (optional)',
              prefixIcon: Icon(Icons.place_outlined, color: IjwiColors.muted),
            ),
          ),
          if (_media.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Media',
                style: TextStyle(
                    color: IjwiColors.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            MediaGridEditor(
              items: _media,
              onRemove: (item) {
                setState(() => _media.removeWhere((e) => e.id == item.id));
                ref.read(mediaUploadQueueProvider.notifier).remove(item.id);
              },
              onAdd: _pickMedia,
            ),
          ] else ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickMedia,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add photos or files'),
            ),
          ],
          if (_type == 'harvest') _harvestBridge(),
        ],
      ),
    );
  }

  Widget _typeSelector() {
    final types = {
      'text': ('Notes', PostTypeStyle.icon('text')),
      'question': ('Question', PostTypeStyle.icon('question')),
      'poll': ('Poll', PostTypeStyle.icon('poll')),
      'farm_update': ('Farm update', PostTypeStyle.icon('farm_update')),
      'harvest': ('Harvest', PostTypeStyle.icon('harvest')),
      'product': ('Product', PostTypeStyle.icon('product')),
      'opportunity': ('Opportunity', PostTypeStyle.icon('opportunity')),
      'event': ('Event', PostTypeStyle.icon('event')),
    };
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final entry in types.entries)
        ChoiceChip(
          label: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(entry.value.$2,
                size: 14, color: PostTypeStyle.color(entry.key)),
            const SizedBox(width: 4),
            Text(entry.value.$1),
          ]),
          selected: _type == entry.key,
          onSelected: (_) => setState(() => _type = entry.key),
        ),
    ]);
  }

  Widget _harvestBridge() {
    return Card(
      color: IjwiColors.greenLight,
      child: ListTile(
        leading: const Icon(Icons.storefront_outlined, color: IjwiColors.green),
        title: const Text('Also list this harvest?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('Create a marketplace listing to reach buyers'),
        trailing: OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(90, 36)),
          onPressed: () => context.push('/sell/new'),
          child: const Text('Add listing'),
        ),
      ),
    );
  }
}
