import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../shared/widgets/ui.dart';
import 'community_models.dart';
import 'community_service.dart';

/// Structured status/story viewer with tap-next and progress indicators.
class StatusViewerScreen extends ConsumerStatefulWidget {
  const StatusViewerScreen({super.key});

  @override
  ConsumerState<StatusViewerScreen> createState() =>
      _StatusViewerScreenState();
}

class _StatusViewerScreenState extends ConsumerState<StatusViewerScreen> {
  List<StatusData>? _statuses;
  int _index = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(communityServiceProvider);
    try {
      final statuses = await svc.listStatuses();
      if (!mounted) return;
      setState(() {
        _statuses = statuses;
        _error = null;
      });
      for (final s in statuses.take(1)) {
        try {
          await svc.viewStatus(s.id);
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  void _next() {
    final list = _statuses;
    if (list == null || _index >= list.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _index++);
    try {
      ref.read(communityServiceProvider).viewStatus(list[_index].id);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final statuses = _statuses;
    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null && statuses == null
          ? Center(child: ErrorBox(_error!, onRetry: _load))
          : statuses == null
              ? const Center(child: CircularProgressIndicator())
              : statuses.isEmpty
                  ? const Center(
                      child: Text('No status updates',
                          style: TextStyle(color: Colors.white)))
                  : _viewer(statuses[_index]),
    );
  }

  Widget _viewer(StatusData s) {
    return GestureDetector(
      onTap: _next,
      onDoubleTap: () {
        if (_index > 0) setState(() => _index--);
      },
      child: Stack(children: [
        // Progress bars
        Positioned(
          top: 30,
          left: 12,
          right: 12,
          child: Row(children: [
            for (var i = 0; i < _statuses!.length; i++)
              Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i < _index
                        ? Colors.white
                        : i == _index
                            ? Colors.white
                            : Colors.white30,
                  ),
                ),
              ),
          ]),
        ),
        // Header
        Positioned(
          top: 44,
          left: 16,
          right: 16,
          child: Row(children: [
            IjwiAvatar(s.author.displayName, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.author.displayName,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                Text('Today',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7), fontSize: 12)),
              ]),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ]),
        ),
        // Body
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (s.quantityLabel != null &&
                  s.quantityLabel!.isNotEmpty)
                Text(s.quantityLabel!,
                    style: const TextStyle(
                        color: IjwiColors.amber,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (s.bodyText != null)
                Text(s.bodyText ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 20, height: 1.4)),
            ]),
          ),
        ),
        // Bottom action
        if (s.listingId != null)
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(maximumSize: const Size(220, 46)),
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/listing/${s.listingId}');
                },
                icon: const Icon(Icons.storefront, size: 18),
                label: const Text('View product'),
              ),
            ),
          ),
      ]),
    );
  }
}
