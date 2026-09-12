import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/media/media_models.dart';
import '../../core/media/media_picker.dart';
import '../../core/media/media_upload_queue.dart';
import '../../core/media/media_voice.dart';
import '../../core/media/media_widgets.dart';
import '../../core/network/api_client.dart';
import '../../core/realtime/socket_service.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import '../auth/auth_controller.dart';
import 'chat_models.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

enum _ComposerMode { text, reply }

class _ChatScreenState extends ConsumerState<ChatScreen> {
  List<ChatMessage>? _messages;
  String? _error;
  String? _myUserId;
  String? _conversationTitle;
  bool _isGroup = false;
  String? _partnerTyping;
  Timer? _typingTimer;

  final _composer = TextEditingController();
  ChatMessage? _replyTo;
  _ComposerMode _mode = _ComposerMode.text;
  SocketService? _socket;

  /// Media the user selected this session, awaiting upload → send.
  final List<LocalMediaItem> _pendingMedia = [];
  final Map<String, List<LocalMediaItem>> _localPreview = {};
  bool _sendingMedia = false;

  static const REACTIONS = ['❤️', '👍', '😂', '😮', '🙏', '👏', '🌱', '🌾'];

  Future<void> _load() async {
    try {
      final me = ref.read(authProvider).valueOrNull;
      final api = ref.read(apiClientProvider);
      final convRes =
          await api.getJson('/conversations/${widget.conversationId}');
      final conv = convRes['conversation'] as Map<String, dynamic>;
      final res = await api.getJson(
          '/conversations/${widget.conversationId}/messages',
          query: {'limit': '100'});
      setState(() {
        _myUserId = me?.id;
        _conversationTitle = (conv['title'] as String?)?.isNotEmpty == true
            ? conv['title'] as String
            : 'Chat';
        _isGroup = (conv['conversation_type'] as String?) == 'GROUP';
        _messages = (res['messages'] as List? ?? const [])
            .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>,
                myUserId: me?.id))
            .toList();
        _error = null;
      });
      // Mark conversation read server-side.
      try {
        await api.postJson('/conversations/${widget.conversationId}/read', {});
      } catch (_) {}
    } catch (e) {
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  Future<void> _connectSocket() async {
    try {
      final socket = await ref.read(socketServiceProvider.future);
      socket.joinConversation(widget.conversationId);
      socket.on('message.new', (data) {
        if (data['conversation_id'] != widget.conversationId) return;
        final msg = ChatMessage.fromJson(
            (data['message'] as Map<String, dynamic>? ?? data),
            myUserId: _myUserId);
        setState(() {
          // Replace optimistic echo or append.
          final idx = _messages?.indexWhere((m) =>
              m.id == msg.id || (m.body == msg.body && m.mine && msg.mine));
          if (_messages != null && idx != null && idx >= 0) {
            _messages![idx] = msg;
          } else {
            _messages?.add(msg);
          }
          _localPreview.remove(msg.id);
        });
      });
      socket.on('typing', (data) {
        if (data['conversation_id'] != widget.conversationId) return;
        if ((data['user_id'] ?? '') == _myUserId) return;
        setState(() => _partnerTyping =
            (data['name'] as String?)?.isNotEmpty == true
                ? data['name'] as String
                : 'Someone');
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _partnerTyping = null);
        });
      });
      _socket = socket;
    } catch (_) {}
  }

  void _onComposerChanged(String _) {
    _socket?.sendTyping(widget.conversationId,
        ref.read(authProvider).valueOrNull?.fullName ?? 'User');
  }

  Future<List<ListingRef>> _fetchShareableListings() async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .getJson('/listings', query: {'per_page': '20'});
      return (res['items'] as List? ?? const [])
          .map((j) => ListingRef.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Attachment sheet: share a live marketplace listing as a card message.
  Future<void> _openAttachSheet() async {
    final listings = await _fetchShareableListings();
    if (!mounted) return;
    showModalBottomSheet<ListingRef>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('Share a product',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          if (listings.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No active listings to share yet.',
                  style: TextStyle(color: IjwiColors.muted)),
            )
          else
            ...listings.map((l) => ListTile(
                  leading: Text(l.emoji ?? '🌱',
                      style: const TextStyle(fontSize: 24)),
                  title: Text(l.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${formatRwf(l.priceMinor)} / ${l.unit}'),
                  onTap: () => Navigator.pop(context, l),
                )),
        ]),
      ),
    ).then((picked) {
      if (picked is ListingRef) _sendListingCard(picked);
    });
  }

  Future<void> _sendListingCard(ListingRef l) async {
    final clientId = 'm-${DateTime.now().microsecondsSinceEpoch}';
    final payload = <String, dynamic>{
      'client_message_id': clientId,
      'message_type': 'listing_card',
      'body_text': '',
      'entity_ref_type': 'listing',
      'entity_ref_id': l.id,
      'entity_snapshot': {
        'listing_id': l.id,
        'title': l.title,
        'price_minor': l.priceMinor,
        'unit_code': l.unit,
        'emoji': l.emoji,
      },
    };
    await _postMessage(payload,
        optimisticBody: '${l.emoji ?? "🌱"} ${l.title}');
  }

  Future<void> _shareUrl(String url) async {
    await SharePlus.instance.share(ShareParams(text: url));
  }

  Future<void> _react(ChatMessage m, String emoji) async {
    try {
      await ref
          .read(apiClientProvider)
          .postJson('/messages/${m.id}/react', {'emoji': emoji});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Reacted $emoji'),
            duration: const Duration(milliseconds: 900)));
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------- media

  Future<void> _openMediaPicker() async {
    final action = await showMediaPickerSheet(context);
    if (action == null || !mounted) return;
    switch (action) {
      case MediaPickAction.camera:
        final perm = await ref.read(mediaPermissionsProvider).camera();
        if (perm != PermissionState.granted) {
          _permissionSnack(perm);
          return;
        }
        final photo = await ref.read(mediaPickerProvider).takePhoto();
        if (photo != null) _addPending([photo]);
      case MediaPickAction.gallery:
        final images = await ref.read(mediaPickerProvider).pickImages(limit: 5);
        _addPending(images);
      case MediaPickAction.video:
        final video = await ref.read(mediaPickerProvider).pickVideo();
        if (video != null) _addPending([video]);
      case MediaPickAction.document:
        final docs =
            await ref.read(mediaPickerProvider).pickDocuments(limit: 3);
        _addPending(docs);
      case MediaPickAction.voice:
        // Tap-to-record fallback for accessibility (hold works from the mic).
        await _startVoiceFromSheet();
      case MediaPickAction.shareListing:
        _openAttachSheet();
    }
  }

  void _permissionSnack(PermissionState p) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(p == PermissionState.permanentlyDenied
          ? 'Permission blocked. Enable it in Settings.'
          : 'Permission required for this action.'),
      action: p == PermissionState.permanentlyDenied
          ? SnackBarAction(
              label: 'Settings',
              onPressed: () =>
                  ref.read(mediaPermissionsProvider).openSettings())
          : null,
    ));
  }

  void _addPending(List<LocalMediaItem> items) {
    final queue = ref.read(mediaUploadQueueProvider.notifier);
    setState(() => _pendingMedia.addAll(items));
    queue.enqueue(items);
  }

  void _removePending(LocalMediaItem item) {
    setState(() => _pendingMedia.removeWhere((e) => e.id == item.id));
    ref.read(mediaUploadQueueProvider.notifier).remove(item.id);
  }

  // ----------------------------------------------------------- voice (hold)

  /// Tap on the mic while idle does nothing; holding records (WhatsApp style:
  /// release to send, drag up to cancel). The picker sheet's "voice" option
  /// starts the same recorder and the composer mic turns into Stop/Send.

  Future<void> _startVoiceFromSheet() async {
    final perm = await ref.read(mediaPermissionsProvider).microphone();
    if (perm != PermissionState.granted) {
      _permissionSnack(perm);
      return;
    }
    await _beginVoiceRecording(fromHold: false);
  }

  Future<void> _beginVoiceRecording({bool fromHold = true}) async {
    if (_recordingVoice) return;
    final perm = await ref.read(mediaPermissionsProvider).microphone();
    if (perm != PermissionState.granted) {
      _permissionSnack(perm);
      return;
    }
    HapticFeedback.mediumImpact();
    await ref.read(voiceRecorderProvider).start();
    if (mounted) {
      setState(() {
        _recordingVoice = true;
        _holdRecording = fromHold;
        _cancelHold = false;
      });
    }
    _voiceCapTimer?.cancel();
    _voiceCapTimer = Timer(_voiceCap, _finishVoiceRecording);
  }

  void _updateHoldCancel(bool armed) {
    if (_cancelHold == armed) return;
    setState(() => _cancelHold = armed);
  }

  Future<void> _endHoldRecording() async {
    _voiceCapTimer?.cancel();
    _voiceCapTimer = null;
    if (!_recordingVoice) return;
    if (_cancelHold) {
      await _cancelVoiceRecording();
      return;
    }
    await _finishVoiceRecording();
  }

  Future<void> _abortHoldRecording() async {
    if (!_recordingVoice) return;
    await _cancelVoiceRecording();
  }

  Future<void> _cancelVoiceRecording() async {
    _voiceCapTimer?.cancel();
    _voiceCapTimer = null;
    await ref.read(voiceRecorderProvider).cancel();
    if (mounted) {
      setState(() {
        _recordingVoice = false;
        _holdRecording = false;
        _cancelHold = false;
      });
    }
  }

  Future<void> _finishVoiceRecording() async {
    _voiceCapTimer?.cancel();
    _voiceCapTimer = null;
    if (!_recordingVoice) return;
    final rec = ref.read(voiceRecorderProvider);
    if (rec.duration.inMilliseconds < _minVoiceMs) {
      await _cancelVoiceRecording();
      return;
    }
    final item = await rec.stopAndCreate();
    if (mounted && item != null) {
      _addPending([item]);
      _sendPendingMedia(); // voice sends immediately on stop
      setState(() {
        _recordingVoice = false;
        _holdRecording = false;
        _cancelHold = false;
      });
    } else if (mounted) {
      setState(() {
        _recordingVoice = false;
        _holdRecording = false;
        _cancelHold = false;
      });
    }
  }

  Future<void> _sendPendingMedia() async {
    if (_sendingMedia || _pendingMedia.isEmpty) return;
    setState(() => _sendingMedia = true);
    try {
      final ids = _pendingMedia.map((e) => e.id).toList();
      // Wait for uploads (bounded).
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (DateTime.now().isBefore(deadline)) {
        final tasks = ref.read(mediaUploadQueueProvider);
        final allReady = ids.every(
            (id) => tasks.any((t) => t.localId == id && t.result != null));
        if (allReady) break;
        await Future.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
      }

      final tasks = ref.read(mediaUploadQueueProvider);
      final ready = <String, ({LocalMediaItem item, RemoteMedia media})>{};
      for (final id in ids) {
        final t = tasks.where((x) => x.localId == id).firstOrNull;
        final item = _pendingMedia.where((e) => e.id == id).firstOrNull;
        if (t?.result != null && item != null) {
          ready[id] = (item: item, media: t!.result!);
        }
      }

      if (ready.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Uploading is taking longer than expected. Retry when online.')));
        }
        return;
      }

      final ordered = <({LocalMediaItem item, RemoteMedia media})>[
        for (final id in ids)
          if (ready.containsKey(id)) ready[id]!,
      ];

      final attachments = <Map<String, dynamic>>[];
      for (final e in ordered) {
        final item = e.item;
        final media = e.media;
        attachments.add({
          'storage_key': media.storageKey,
          'type': mediaKindToCategory(item.kind),
          'file_name': item.fileName,
          'mime_type': item.mimeType ?? '',
          'size_bytes': item.sizeBytes,
          if (item.durationMs > 0) 'duration_ms': item.durationMs,
        });
      }

      final primary = ordered.first.item.kind;
      final msgType = switch (primary) {
        MediaKind.image => 'image',
        MediaKind.video => 'video',
        MediaKind.audio => 'voice',
        MediaKind.document => 'document',
      };
      final text = _composer.text.trim();
      final clientId = 'm-${DateTime.now().microsecondsSinceEpoch}';
      final totalDurationMs =
          ordered.fold<int>(0, (sum, e) => sum + e.item.durationMs);

      final payload = {
        'client_message_id': clientId,
        'message_type': msgType,
        'body_text': text,
        'attachments': attachments,
        if (_replyTo != null) 'reply_to_message_id': _replyTo!.id,
        if (primary == MediaKind.audio) ...{
          'voice_duration_ms': totalDurationMs,
          if (ref.read(voiceRecorderProvider).lastWaveform.isNotEmpty)
            'waveform': ref.read(voiceRecorderProvider).lastWaveform,
        },
      };

      final preview = ordered.map((e) => e.item).toList();
      _composer.clear();
      setState(() {
        _localPreview[clientId] = preview;
        _pendingMedia.removeWhere((e) => ids.contains(e.id));
        _replyTo = null;
        _mode = _ComposerMode.text;
      });
      await _postMessage(payload, optimisticBody: text, preview: preview);
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  void _clearPending() {
    for (final p in _pendingMedia) {
      ref.read(mediaUploadQueueProvider.notifier).remove(p.id);
    }
    setState(() => _pendingMedia.clear());
  }

  bool _recordingVoice = false;
  bool _holdRecording = false;
  bool _cancelHold = false;
  Timer? _voiceCapTimer;

  static const _minVoiceMs = 700;
  static const _voiceCap = Duration(minutes: 5);

  // ------------------------------------------------------------- sending

  Future<void> _sendText() async {
    final text = _composer.text.trim();
    if (_pendingMedia.isNotEmpty) {
      await _sendPendingMedia();
      return;
    }
    if (text.isEmpty) return;
    _composer.clear();
    final payload = <String, dynamic>{
      'client_message_id': 'm-${DateTime.now().microsecondsSinceEpoch}',
      'message_type': 'text',
      'body_text': text,
      if (_replyTo != null) 'reply_to_message_id': _replyTo!.id,
    };
    setState(() {
      _replyTo = null;
      _mode = _ComposerMode.text;
    });
    await _postMessage(payload, optimisticBody: text);
  }

  Future<void> _postMessage(Map<String, dynamic> payload,
      {required String optimisticBody, List<LocalMediaItem>? preview}) async {
    final clientId = payload['client_message_id'] as String;
    setState(() {
      (_messages ??= []).add(ChatMessage.fromJson({
        'id': clientId,
        'sender_id': _myUserId,
        'message_type': payload['message_type'] as String? ?? 'text',
        'body_text': optimisticBody,
        'created_at': DateTime.now().toIso8601String(),
      }, myUserId: _myUserId));
    });
    try {
      await ref.read(apiClientProvider).postJson(
          '/conversations/${widget.conversationId}/messages', payload);
    } catch (_) {
      // Offline-safe: queue for the sync engine; server dedupes by id.
      await ref.read(syncEngineProvider.future).then((s) => s.enqueue(
          'message.send',
          {...payload, 'conversation_id': widget.conversationId}));
    }
  }

  void _setReply(ChatMessage m) {
    setState(() {
      _replyTo = m;
      _mode = _ComposerMode.reply;
    });
  }

  void _showMessageActions(ChatMessage m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: REACTIONS
                  .map((e) => GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _react(m, e);
                        },
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ))
                  .toList(),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.reply_outlined),
            title: const Text('Reply'),
            onTap: () {
              Navigator.pop(context);
              _setReply(m);
            },
          ),
          if (!m.isCard && m.body.isNotEmpty && !m.mine)
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('View in market'),
              onTap: () {
                Navigator.pop(context);
                context.go('/market');
              },
            ),
        ]),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
    _connectSocket();
    _composer.addListener(() => _onComposerChanged(_composer.text));
  }

  @override
  void dispose() {
    _voiceCapTimer?.cancel();
    if (_recordingVoice) {
      ref.read(voiceRecorderProvider).cancel();
    }
    _composer.dispose();
    _typingTimer?.cancel();
    _socket?.leaveConversation(widget.conversationId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    final msgs = _messages;
    final queueTasks = ref.watch(mediaUploadQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_conversationTitle ?? tr('tab_chat'),
              overflow: TextOverflow.ellipsis),
          if (_partnerTyping != null)
            Text('$_partnerTyping is typing…',
                style: const TextStyle(fontSize: 11, color: Colors.white70))
          else if (_isGroup)
            const Text('Group',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: msgs == null && _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: IjwiColors.red)))
              : msgs == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final m = msgs[msgs.length - 1 - i];
                        final mine = m.mine || m.senderId == _myUserId;
                        return GestureDetector(
                          onLongPress: () => _showMessageActions(m),
                          onDoubleTap: () => _setReply(m),
                          child: Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 13, vertical: 9),
                              constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.78),
                              decoration: BoxDecoration(
                                color: mine ? IjwiColors.green : Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(mine ? 16 : 4),
                                  bottomRight: Radius.circular(mine ? 4 : 16),
                                ),
                              ),
                              child: m.isCard
                                  ? _cardContent(m, dark: mine)
                                  : Builder(builder: (context) {
                                      final mediaW =
                                          _bubbleMedia(m, mine: mine);
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (m.replyTo != null)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                  bottom: 5),
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: mine
                                                    ? IjwiColors.greenDark
                                                        .withOpacity(0.5)
                                                    : IjwiColors.surface,
                                                borderRadius:
                                                    BorderRadius.circular(7),
                                              ),
                                              child: Text(
                                                  '↩ replied to a message',
                                                  style: TextStyle(
                                                      fontSize: 10.5,
                                                      color: mine
                                                          ? Colors.white70
                                                          : IjwiColors.muted)),
                                            ),
                                          if (mediaW != null) mediaW,
                                          if (m.body.isNotEmpty)
                                            Padding(
                                              padding: EdgeInsets.only(
                                                  top: mediaW != null ? 6 : 0),
                                              child: Text(m.body,
                                                  style: TextStyle(
                                                      height: 1.35,
                                                      color: mine
                                                          ? Colors.white
                                                          : Colors.black87)),
                                            ),
                                        ],
                                      );
                                    }),
                            ),
                          ),
                        );
                      },
                    ),
        ),
        if (_mode == _ComposerMode.reply && _replyTo != null)
          Container(
            color: IjwiColors.surface,
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
            child: Row(children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    border: const Border(
                        left: BorderSide(color: IjwiColors.green, width: 3)),
                    color: Colors.white,
                  ),
                  child: Text(
                    '↩ ${_replyTo!.body.isEmpty ? "message" : _replyTo!.body}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, color: IjwiColors.muted),
                  ),
                ),
              ),
              IconButton(
                  onPressed: () => setState(() {
                        _replyTo = null;
                        _mode = _ComposerMode.text;
                      }),
                  icon: const Icon(Icons.close, size: 18)),
            ]),
          ),
        if (_pendingMedia.isNotEmpty)
          _PendingMediaStrip(
            items: _pendingMedia,
            tasks: queueTasks,
            onRemove: _removePending,
            onClear: _clearPending,
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              _VoiceHoldButton(
                recording: _recordingVoice,
                onTap: _recordingVoice ? _finishVoiceRecording : null,
                onLongPressStart: (_) => _beginVoiceRecording(fromHold: true),
                onLongPressMoveUpdate: (d) =>
                    _updateHoldCancel(d.localPosition.dy <= -70),
                onLongPressEnd: (_) => _endHoldRecording(),
                onLongPressCancel: _abortHoldRecording,
              ),
              if (_recordingVoice)
                Expanded(
                  child: _RecordingBar(
                    holdMode: _holdRecording,
                    cancelArmed: _cancelHold,
                    onStop: _finishVoiceRecording,
                    onCancel: _cancelVoiceRecording,
                  ),
                )
              else ...[
                IconButton(
                    tooltip: 'Attach',
                    onPressed: _openMediaPicker,
                    icon: const Icon(Icons.add_circle_outline,
                        color: IjwiColors.green, size: 28)),
                Expanded(
                  child: TextField(
                    controller: _composer,
                    onSubmitted: (_) => _sendText(),
                    decoration: InputDecoration(hintText: tr('type_message')),
                  ),
                ),
                if (_sendingMedia)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton.filled(
                    onPressed: _sendText,
                    icon: const Icon(Icons.send),
                  ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  Widget? _bubbleMedia(ChatMessage m, {required bool mine}) {
    final preview = _localPreview[m.id];
    if (preview != null && preview.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: _LocalPreviewGrid(items: preview, mine: mine),
      );
    }
    if (m.mediaAttachments.isEmpty) return null;
    final media = m.mediaAttachments;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final mm in media) ..._renderOne(mm, mine: mine),
        ],
      ),
    );
  }

  List<Widget> _renderOne(RemoteMedia mm, {required bool mine}) {
    if (mm.isImage) {
      final h = (mm.height ?? 200).clamp(120, 320);
      return [
        GestureDetector(
          onTap: () => showFullscreenMediaViewer(context, [mm]),
          child: Stack(children: [
            Container(
              width: double.infinity,
              height: h.toDouble(),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.black12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: IjwiImage(
                  url: mm.url,
                  borderRadius: 0,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                    color: Colors.black45, shape: BoxShape.circle),
                child:
                    const Icon(Icons.fullscreen, color: Colors.white, size: 15),
              ),
            ),
          ]),
        ),
      ];
    }
    if (mm.isVideo) {
      return [
        Container(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10), color: Colors.black),
          clipBehavior: Clip.antiAlias,
          child: MediaVideoPlayer(remote: mm),
        ),
      ];
    }
    if (mm.isAudio) {
      return [
        VoicePlayerWidget(
          source: mm.url,
          duration: mm.durationMs != null
              ? Duration(milliseconds: mm.durationMs!)
              : null,
          color: mine ? Colors.white : IjwiColors.green,
        ),
      ];
    }
    return [
      InkWell(
        onTap: () async {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Opening ${mm.fileName ?? "document"}…'),
            duration: const Duration(seconds: 1),
          ));
          await _shareUrl(mm.url);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: mine
                ? IjwiColors.greenDark.withOpacity(0.5)
                : IjwiColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.insert_drive_file_outlined, size: 18),
            const SizedBox(width: 6),
            Text(
              mm.fileName ?? 'Document',
              style: TextStyle(
                  fontSize: 12.5,
                  color: mine ? Colors.white : IjwiColors.ink,
                  fontWeight: FontWeight.w600),
            ),
          ]),
        ),
      ),
    ];
  }

  Widget _cardContent(ChatMessage m, {required bool dark}) {
    final e = m.entity ?? {};
    final title =
        e['title'] as String? ?? m.body.replaceFirst(RegExp(r'^[^ ]+ '), '');
    final price = (e['price_minor'] as num?)?.toInt();
    final unit = e['unit_code'] as String? ?? 'kg';
    final listingId =
        e['listing_id'] as String? ?? m.attachments.firstOrNull?['storage_key'];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: listingId != null ? () => context.go('/listing/$listingId') : null,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: dark ? Colors.white.withOpacity(0.12) : IjwiColors.greenLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.storefront_outlined, size: 15),
            const SizedBox(width: 5),
            Text('MARKETPLACE',
                style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: dark ? Colors.white70 : IjwiColors.greenDark)),
          ]),
          const SizedBox(height: 6),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: dark ? Colors.white : Colors.black87)),
          if (price != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${formatRwf(price)} / $unit · tap to open',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: dark ? Colors.white70 : IjwiColors.muted)),
            ),
        ]),
      ),
    );
  }
}

/// Horizontal strip of selected media above the composer with live progress.
class _PendingMediaStrip extends ConsumerWidget {
  const _PendingMediaStrip({
    required this.items,
    required this.tasks,
    required this.onRemove,
    required this.onClear,
  });

  final List<LocalMediaItem> items;
  final List<UploadTask> tasks;
  final void Function(LocalMediaItem item) onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: IjwiColors.surface,
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
      child: Row(children: [
        Expanded(
          child: SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final item in items) ...[
                  _PendingTile(item: item, tasks: tasks, onRemove: onRemove),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: onClear,
          icon: const Icon(Icons.delete_sweep_outlined, size: 20),
        ),
      ]),
    );
  }
}

class _PendingTile extends ConsumerWidget {
  const _PendingTile(
      {required this.item, required this.tasks, required this.onRemove});

  final LocalMediaItem item;
  final List<UploadTask> tasks;
  final void Function(LocalMediaItem item) onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = tasks.where((t) => t.localId == item.id).firstOrNull;
    final status = task?.status;
    final progress = task?.progress ?? 0;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: item.kind == MediaKind.audio
                ? Container(
                    color: IjwiColors.greenLight,
                    alignment: Alignment.center,
                    child: const Icon(Icons.mic, color: IjwiColors.green),
                  )
                : Image.file(File(item.path),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                        color: IjwiColors.greenLight,
                        child: const Icon(Icons.insert_drive_file_outlined))),
          ),
        ),
        if (status == UploadStatus.ready)
          Positioned.fill(
              child: Container(
            color: IjwiColors.green.withOpacity(0.25),
            alignment: Alignment.center,
            child: const Icon(Icons.check_circle,
                color: IjwiColors.green, size: 26),
          )),
        if (status == UploadStatus.uploading || status == UploadStatus.queued)
          Positioned.fill(
              child: Container(
            color: Colors.black38,
            alignment: Alignment.center,
            child: CircularProgressIndicator(
                value: status == UploadStatus.queued ? null : progress / 100,
                strokeWidth: 2,
                color: Colors.white),
          )),
        if (status == UploadStatus.failed)
          Positioned.fill(
              child: GestureDetector(
            onTap: () =>
                ref.read(mediaUploadQueueProvider.notifier).retry(item.id),
            child: Container(
              color: IjwiColors.red.withOpacity(0.35),
              alignment: Alignment.center,
              child: const Icon(Icons.refresh, color: IjwiColors.red, size: 22),
            ),
          )),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: () => onRemove(item),
            child: const CircleAvatar(
              radius: 8,
              backgroundColor: Colors.black54,
              child: Icon(Icons.close, size: 10, color: Colors.white),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Inline recording controls while a voice note is being captured. In hold
/// mode it shows a "Release to send" / "Cancel" hint instead of a Send button.
class _RecordingBar extends ConsumerWidget {
  const _RecordingBar({
    required this.holdMode,
    required this.cancelArmed,
    required this.onStop,
    required this.onCancel,
  });

  final bool holdMode;
  final bool cancelArmed;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = ref.watch(voiceRecorderProvider);
    return Container(
      margin: const EdgeInsets.only(left: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: cancelArmed
            ? IjwiColors.amber.withOpacity(0.15)
            : IjwiColors.greenLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(children: [
        const Icon(Icons.fiber_manual_record, color: IjwiColors.red, size: 16),
        const SizedBox(width: 6),
        Text(_fmtDuration(rec.duration),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 10),
        Expanded(child: _MiniWaveform(amplitudes: rec.amplitudes)),
        const SizedBox(width: 10),
        if (holdMode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                cancelArmed ? Icons.keyboard_arrow_up : Icons.arrow_upward,
                size: 14,
                color: cancelArmed ? IjwiColors.amber : IjwiColors.muted,
              ),
              const SizedBox(width: 4),
              Text(
                cancelArmed ? 'Cancel' : 'Release to send',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cancelArmed ? IjwiColors.amber : IjwiColors.muted,
                ),
              ),
            ]),
          )
        else ...[
          IconButton(
            tooltip: 'Cancel',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onCancel,
            icon: const Icon(Icons.close, size: 18),
          ),
          FilledButton.tonal(
            onPressed: onStop,
            child: const Text('Send'),
          ),
        ],
      ]),
    );
  }

  static String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds - m * 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Mic button that supports WhatsApp-style hold-and-release recording. When
/// idle, a long press arms the recorder and sliding above the button cancels.
class _VoiceHoldButton extends StatelessWidget {
  const _VoiceHoldButton({
    required this.recording,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
  });

  final bool recording;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;
  final GestureLongPressCancelCallback? onLongPressCancel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      onLongPressEnd: onLongPressEnd,
      onLongPressCancel: onLongPressCancel,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: recording ? IjwiColors.greenLight : Colors.transparent,
        ),
        child: Icon(
          recording ? Icons.square : Icons.mic_outlined,
          color: recording ? IjwiColors.greenDark : IjwiColors.green,
          size: 26,
        ),
      ),
    );
  }
}

/// Live pulse of the last ~24 amplitude samples while recording.
class _MiniWaveform extends StatelessWidget {
  const _MiniWaveform({required this.amplitudes});

  final List<double> amplitudes;

  @override
  Widget build(BuildContext context) {
    final bars = amplitudes.length > 24
        ? amplitudes.sublist(amplitudes.length - 24)
        : amplitudes;
    return SizedBox(
      height: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final a in bars)
            Container(
              width: 2,
              height: (a.clamp(0.0, 1.0) * 14 + 3),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: IjwiColors.greenDark,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}

/// Grid of local thumbs for the optimistic media bubble.
class _LocalPreviewGrid extends StatelessWidget {
  const _LocalPreviewGrid({required this.items, required this.mine});

  final List<LocalMediaItem> items;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final shown = items.take(4).toList();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final item in shown)
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: item.kind == MediaKind.image
                  ? Image.file(File(item.path),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.image_outlined))
                  : Container(
                      color:
                          (mine ? IjwiColors.greenDark : IjwiColors.greenLight)
                              .withOpacity(0.8),
                      alignment: Alignment.center,
                      child: Icon(
                        switch (item.kind) {
                          MediaKind.video => Icons.videocam_outlined,
                          MediaKind.audio => Icons.mic,
                          MediaKind.document =>
                            Icons.insert_drive_file_outlined,
                          MediaKind.image => Icons.image_outlined,
                        },
                        color: mine ? Colors.white : IjwiColors.greenDark,
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}
