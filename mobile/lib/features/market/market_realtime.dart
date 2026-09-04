import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/realtime/socket_service.dart';

/// Realtime subscription helper for marketplace screens.
///
/// Screens mix this in and call [attachMarketRealtime] from `initState` with
/// the socket events they care about. Events that arrive in bursts (e.g.
/// several `bid.placed` in a row) are coalesced by a debounce before the
/// screen's reload runs, so we never hammer the API for every tiny event.
mixin MarketRealtime<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  SocketService? _rtSocket;
  final Map<String, EventCallback> _rtHandlers = {};
  final Map<String, Timer> _rtDebounces = {};
  bool _rtAttached = false;

  /// Attach [events] (socket event name → handler). Handlers are wrapped in a
  /// per-event debounce of [debounceMs]; set `debounceMs` to 0 to fire
  /// immediately on every event.
  void attachMarketRealtime(
    Map<String, void Function(Map<String, dynamic>)> events, {
    int debounceMs = 600,
  }) {
    if (_rtAttached) return;
    _rtAttached = true;
    _subscribeRealtime(events, debounceMs);
  }

  Future<void> _subscribeRealtime(
    Map<String, void Function(Map<String, dynamic>)> events,
    int debounceMs,
  ) async {
    SocketService? socket;
    try {
      socket = await ref.read(socketServiceProvider.future);
    } catch (_) {
      return; // not signed in / socket unavailable: screens still pull
    }
    if (!mounted || !_rtAttached || socket == null) return;
    _rtSocket = socket;
    for (final entry in events.entries) {
      final name = entry.key;
      final rawHandler = entry.value;
      final handler = (Map<String, dynamic> data) {
        if (!mounted) return;
        if (debounceMs <= 0) {
          rawHandler(data);
          return;
        }
        _rtDebounces[name]?.cancel();
        _rtDebounces[name] =
            Timer(Duration(milliseconds: debounceMs), () => rawHandler(data));
      };
      _rtHandlers[name] = handler;
      socket.on(name, handler);
    }
  }

  /// Cancel any coalesced reload still waiting and drop all subscriptions.
  void detachMarketRealtime() {
    _rtAttached = false;
    for (final t in _rtDebounces.values) {
      t.cancel();
    }
    _rtDebounces.clear();
    final socket = _rtSocket;
    _rtSocket = null;
    if (socket == null) return;
    _rtHandlers.forEach(socket.off);
    _rtHandlers.clear();
  }
}
