import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
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
        _conversationTitle =
            (conv['title'] as String?)?.isNotEmpty == true
                ? conv['title'] as String
                : 'Chat';
        _isGroup = (conv['conversation_type'] as String?) == 'GROUP';
        _messages = ((res['messages'] as List? ?? const []) as List)
            .map((j) =>
                ChatMessage.fromJson(j as Map<String, dynamic>, myUserId: me?.id))
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
              m.id == msg.id ||
              (m.body == msg.body && m.mine && msg.mine));
          if (_messages != null && idx != null && idx >= 0) {
            _messages![idx] = msg;
          } else {
            _messages?.add(msg);
          }
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
    showModalBottomSheet<void>(
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
                  subtitle:
                      Text('${formatRwf(l.priceMinor)} / ${l.unit}'),
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
    await _postMessage(payload, optimisticBody: '${l.emoji ?? "🌱"} ${l.title}');
  }

  Future<void> _react(ChatMessage m, String emoji) async {
    try {
      await ref
          .read(apiClientProvider)
          .postJson('/messages/${m.id}/react', {'emoji': emoji});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reacted $emoji'), duration:
                const Duration(milliseconds: 900)));
      }
    } catch (_) {}
  }

  Future<void> _sendText() async {
    final text = _composer.text.trim();
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
      {required String optimisticBody}) async {
    final clientId = payload['client_message_id'] as String;
    setState(() {
      (_messages ??= []).add(ChatMessage.fromJson({
        'id': clientId,
        'sender_id': _myUserId,
        'message_type':
            payload['message_type'] as String? ?? 'text',
        'body_text': optimisticBody,
        'created_at': DateTime.now().toIso8601String(),
      }, myUserId: _myUserId));
    });
    try {
      await ref
          .read(apiClientProvider)
          .postJson('/conversations/${widget.conversationId}/messages',
              payload);
    } catch (_) {
      // Offline-safe: queue for the sync engine; server dedupes by id.
      await ref.read(syncEngineProvider.future).then((s) => s.enqueue(
          'message.send', {...payload, 'conversation_id': widget.conversationId}));
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
                        child: Text(e,
                            style: const TextStyle(fontSize: 26)),
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
    _typingTimer?.cancel();
    _socket?.leaveConversation(widget.conversationId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    final msgs = _messages;

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                              margin:
                                  const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 13, vertical: 9),
                              constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context)
                                          .size
                                          .width *
                                      0.78),
                              decoration: BoxDecoration(
                                color: mine
                                    ? IjwiColors.green
                                    : Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft:
                                      Radius.circular(mine ? 16 : 4),
                                  bottomRight:
                                      Radius.circular(mine ? 4 : 16),
                                ),
                              ),
                              child: m.isCard
                                  ? _cardContent(m, dark: mine)
                                  : Column(
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
                                                        : IjwiColors
                                                            .muted)),
                                          ),
                                        Text(m.body,
                                            style: TextStyle(
                                                height: 1.35,
                                                color: mine
                                                    ? Colors.white
                                                    : Colors.black87)),
                                      ],
                                    ),
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
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              IconButton(
                  tooltip: 'Attach',
                  onPressed: _openAttachSheet,
                  icon: const Icon(Icons.add_circle_outline,
                      color: IjwiColors.green, size: 28)),
              Expanded(
                child: TextField(
                  controller: _composer,
                  onSubmitted: (_) => _sendText(),
                  decoration:
                      InputDecoration(hintText: tr('type_message')),
                ),
              ),
              IconButton.filled(
                onPressed: _sendText,
                icon: const Icon(Icons.send),
              ),
            ]),
          ),
        ),
      ]),
    );
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
      onTap: listingId != null
          ? () => context.go('/listing/$listingId')
          : null,
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

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
