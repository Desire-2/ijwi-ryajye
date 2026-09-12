import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../i18n/i18n_provider.dart';
import '../storage/token_store.dart';
import '../theme/design_system.dart';
import 'media_models.dart';
import 'media_repository.dart';

enum MediaPickAction { camera, gallery, video, document, voice, shareListing }

/// Bottom sheet offering every capture/selection path, permission-aware.
Future<MediaPickAction?> showMediaPickerSheet(
  BuildContext context, {
  List<MediaPickAction> actions = const [
    MediaPickAction.camera,
    MediaPickAction.gallery,
    MediaPickAction.video,
    MediaPickAction.document,
    MediaPickAction.voice,
  ],
}) {
  return showModalBottomSheet<MediaPickAction>(
    context: context,
    builder: (context) => Consumer(builder: (context, ref, _) {
      final tr = ref.watch(trProvider);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(tr('add_media'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 18,
              runSpacing: 18,
              children: [
                for (final a in actions)
                  _ActionTile(
                    icon: _iconFor(a),
                    label: _labelFor(a, tr),
                    onTap: () => Navigator.pop(context, a),
                  ),
              ],
            ),
            const SizedBox(height: 18),
          ],
        ),
      );
    }),
  );
}

IconData _iconFor(MediaPickAction a) {
  switch (a) {
    case MediaPickAction.camera:
      return Icons.photo_camera_outlined;
    case MediaPickAction.gallery:
      return Icons.photo_library_outlined;
    case MediaPickAction.video:
      return Icons.videocam_outlined;
    case MediaPickAction.document:
      return Icons.description_outlined;
    case MediaPickAction.voice:
      return Icons.mic_outlined;
    case MediaPickAction.shareListing:
      return Icons.storefront_outlined;
  }
}

String _labelFor(MediaPickAction a, String Function(String) tr) {
  switch (a) {
    case MediaPickAction.camera:
      return tr('camera');
    case MediaPickAction.gallery:
      return tr('gallery');
    case MediaPickAction.video:
      return tr('video');
    case MediaPickAction.document:
      return tr('document');
    case MediaPickAction.voice:
      return tr('voice');
    case MediaPickAction.shareListing:
      return tr('share_product');
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: IjwiColors.greenLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Icon(icon, color: IjwiColors.green, size: 30),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}

/// Auth-aware cached image for served backend files.
class IjwiImage extends ConsumerStatefulWidget {
  const IjwiImage({
    super.key,
    this.url,
    this.thumnailOrUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius = 10,
    this.errorIcon = Icons.image_not_supported_outlined,
  });

  final String? url;
  final String? thumnailOrUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double borderRadius;
  final IconData errorIcon;

  @override
  ConsumerState<IjwiImage> createState() => _IjwiImageState();
}

class _IjwiImageState extends ConsumerState<IjwiImage> {
  Map<String, String> _headers = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _fetchHeaders();
  }

  Future<void> _fetchHeaders() async {
    final access = await ref.read(tokenStoreProvider).readAccess();
    if (mounted && access != null) {
      setState(() => _headers = {'Authorization': 'Bearer $access'});
    }
    _loaded = true;
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url ?? widget.thumnailOrUrl;
    if (url == null || !_loaded) return _placeholder(boxFit: widget.fit);
    final key = ValueKey('ij${_headers.isEmpty ? 0 : 1}_$url');
    return CachedNetworkImage(
      key: key,
      imageUrl: url,
      httpHeaders: _headers,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      placeholder: (context, progress) => _placeholder(boxFit: widget.fit),
      errorWidget: (context, error, stackTrace) => Container(
        width: widget.width,
        height: widget.height,
        alignment: Alignment.center,
        color: IjwiColors.surface,
        child: Icon(widget.errorIcon, color: IjwiColors.muted),
      ),
      imageBuilder: (context, imageProvider) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          image: DecorationImage(image: imageProvider, fit: widget.fit),
        ),
      ),
    );
  }

  Widget _placeholder({required BoxFit boxFit}) {
    return Container(
      width: widget.width,
      height: widget.height,
      alignment: Alignment.center,
      color: IjwiColors.surface,
      child: const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
    );
  }
}

/// Inline video playback for served media.
class MediaVideoPlayer extends ConsumerStatefulWidget {
  const MediaVideoPlayer(
      {super.key, required this.remote, this.autoplay = false});

  final RemoteMedia remote;
  final bool autoplay;

  @override
  ConsumerState<MediaVideoPlayer> createState() => _MediaVideoPlayerState();
}

class _MediaVideoPlayerState extends ConsumerState<MediaVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initError = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final access = await ref.read(tokenStoreProvider).readAccess();
      final c = VideoPlayerController.networkUrl(
        Uri.parse(widget.remote.url),
        httpHeaders:
            access == null ? const {} : {'Authorization': 'Bearer $access'},
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
      if (widget.autoplay) await c.play();
    } catch (_) {
      if (mounted) setState(() => _initError = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_initError) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        color: IjwiColors.surface,
        child: const Icon(Icons.videocam_off_outlined, color: IjwiColors.muted),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        color: IjwiColors.surface,
        child: const CircularProgressIndicator(),
      );
    }
    return AspectRatio(
      aspectRatio: c.value.aspectRatio,
      child: GestureDetector(
        onTap: () {
          setState(() => c.value.isPlaying ? c.pause() : c.play());
        },
        child: Stack(fit: StackFit.expand, children: [
          VideoPlayer(c),
          if (!c.value.isPlaying)
            Container(
              decoration: const BoxDecoration(color: Colors.black26),
              alignment: Alignment.center,
              child:
                  const Icon(Icons.play_arrow, color: Colors.white, size: 56),
            ),
        ]),
      ),
    );
  }
}

/// Grid of locally selected media with remove + add affordance.
class MediaGridEditor extends StatelessWidget {
  const MediaGridEditor({
    super.key,
    required this.items,
    required this.onRemove,
    required this.onAdd,
    this.cellSize = 92,
  });

  final List<LocalMediaItem> items;
  final void Function(LocalMediaItem item) onRemove;
  final VoidCallback onAdd;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          SizedBox(
            width: cellSize,
            height: cellSize,
            child: Stack(children: [
              Positioned.fill(
                child: _LocalThumb(item: item),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: InkWell(
                  onTap: () => onRemove(item),
                  child: const CircleAvatar(
                    radius: 11,
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, size: 13, color: Colors.white),
                  ),
                ),
              ),
            ]),
          ),
        SizedBox(
          width: cellSize,
          height: cellSize,
          child: InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: IjwiColors.green.withOpacity(0.6)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add_a_photo_outlined,
                  color: IjwiColors.green),
            ),
          ),
        ),
      ],
    );
  }
}

class _LocalThumb extends StatelessWidget {
  const _LocalThumb({required this.item});

  final LocalMediaItem item;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(fit: StackFit.expand, children: [
        switch (item.kind) {
          MediaKind.image => Image.file(File(item.path), fit: BoxFit.cover),
          MediaKind.video => Stack(fit: StackFit.expand, children: [
              Image.file(File(item.path),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.videocam_outlined)),
              const Center(
                  child: Icon(Icons.play_circle_outline,
                      color: Colors.white, size: 28)),
            ]),
          MediaKind.audio => Container(
              color: IjwiColors.greenLight,
              child: const Icon(Icons.mic, color: IjwiColors.green)),
          MediaKind.document => Container(
              color: IjwiColors.greenLight,
              child: const Icon(Icons.description_outlined,
                  color: IjwiColors.green)),
        },
      ]),
    );
  }
}

/// Fullscreen viewer for a list of remote media (used by chat + listings).
Future<void> showFullscreenMediaViewer(
  BuildContext context,
  List<RemoteMedia> media, {
  int initialIndex = 0,
}) async {
  if (media.isEmpty) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) =>
          _FullscreenViewer(media: media, initialIndex: initialIndex),
    ),
  );
}

class _FullscreenViewer extends ConsumerStatefulWidget {
  const _FullscreenViewer({required this.media, required this.initialIndex});

  final List<RemoteMedia> media;
  final int initialIndex;

  @override
  ConsumerState<_FullscreenViewer> createState() => _FullscreenViewerState();
}

class _FullscreenViewerState extends ConsumerState<_FullscreenViewer> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
    _index = widget.initialIndex;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(mediaRepositoryProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: PageView.builder(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        itemCount: widget.media.length,
        itemBuilder: (context, i) {
          final m = widget.media[i];
          if (m.isImage) {
            return InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                child: IjwiImage(
                  url: repo.assetUrl(m.storageKey),
                  fit: BoxFit.contain,
                ),
              ),
            );
          }
          return MediaVideoPlayer(remote: m, autoplay: true);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text('${_index + 1} / ${widget.media.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
      ),
    );
  }
}
