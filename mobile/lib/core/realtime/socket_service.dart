import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config.dart';
import '../storage/token_store.dart';

/// Realtime layer over socket.io.
///
/// Rooms used by the backend:
///   user:{id}            personal events (notifications, wallet, offers)
///   conversation:{id}    chat messages / typing / read receipts
///   product:{id}         price alerts for a product
///   alerts               broadcast emergency advisories
class SocketService {
  SocketService(this._tokens);

  final TokenStore _tokens;
  io.Socket? _socket;
  final _controllers = <String, List<EventCallback>>{};

  bool _connected = false;
  bool get isConnected => _connected;

  Future<void> connect() async {
    if (_socket != null) return;
    final access = await _tokens.readAccess();
    if (access == null) return;

    final completer = Completer<void>();
    _socket = io.io(
      AppConfig.realtimeUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': access})
          .enableReconnection()
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(30000)
          .build(),
    );

    _socket!.onConnect((_) {
      _connected = true;
      if (!completer.isCompleted) completer.complete();
      _dispatch('connected', {});
    });
    _socket!.onDisconnect((_) {
      _connected = false;
      _dispatch('disconnected', {});
    });
    _socket!.onConnectError((data) {
      if (!completer.isCompleted) completer.complete();
    });

    // Generic fan-out: backend emits named events; we mirror them locally.
    for (final event in [
      'notification',
      'notification.created',
      'message.new',
      'message.read',
      'typing',
      'conversation.updated',
      // Marketplace events
      'listing.created',
      'offer.created',
      'offer.updated',
      'offer.accepted',
      'order.created',
      'order.updated',
      'delivery.updated',
      'bid.placed',
      'bid.accepted',
      'market.price_updated',
      'wallet.updated',
      'price.alert',
      'emergency.alert',
      'call.signal',
      'group.member_joined',
      'group.member_removed',
      'group.announcement',
      'sync.pushed',
    ]) {
      _socket!.on(event, (data) => _dispatch(event, data));
    }

    await completer.future.timeout(const Duration(seconds: 8),
        onTimeout: () {});
  }

  void on(String event, EventCallback handler) {
    _controllers.putIfAbsent(event, () => []).add(handler);
  }

  void off(String event, EventCallback handler) {
    _controllers[event]?.remove(handler);
  }

  void emit(String event, Map<String, dynamic> data) {
    _socket?.emit(event, data);
  }

  void joinConversation(String conversationId) =>
      emit('conversation.join', {'conversation_id': conversationId});

  void leaveConversation(String conversationId) =>
      emit('conversation.leave', {'conversation_id': conversationId});

  void sendTyping(String conversationId, String userName) =>
      emit('typing', {'conversation_id': conversationId, 'name': userName});

  void markRead(String conversationId, int serverSequence) =>
      emit('message.read',
          {'conversation_id': conversationId, 'server_sequence': serverSequence});

  void subscribeProduct(String productId) =>
      emit('product.subscribe', {'product_id': productId});

  void subscribeAlerts() => emit('alerts.subscribe', {});

  void signalCall(Map<String, dynamic> payload) => emit('call.signal', payload);

  void _dispatch(String event, dynamic data) {
    final handlers = _controllers[event];
    if (handlers == null) return;
    final payload = data is Map<String, dynamic>
        ? data
        : {'raw': data};
    for (final h in List<EventCallback>.from(handlers)) {
      try {
        h(payload);
      } catch (_) {}
    }
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _connected = false;
  }
}

typedef EventCallback = void Function(Map<String, dynamic> data);

final socketServiceProvider = FutureProvider.autoDispose<SocketService>(
    (ref) async {
  final service = SocketService(ref.watch(tokenStoreProvider));
  ref.keepAlive();
  ref.onDispose(service.disconnect);
  await service.connect();
  return service;
});
