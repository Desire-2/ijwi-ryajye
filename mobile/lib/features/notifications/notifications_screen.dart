import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import '../../shared/widgets/ui.dart';

class NotificationRow {
  NotificationRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        type = j['notification_type'] as String? ?? '',
        title = j['title'] as String? ?? '',
        body = j['body'] as String? ?? '',
        subjectType = j['subject_type'] as String?,
        subjectId = j['subject_id'] as String?,
        readAt = DateTime.tryParse(j['read_at'] as String? ?? ''),
        createdAt =
            DateTime.tryParse(j['created_at'] as String? ?? '') ??
                DateTime.now();

  final String id;
  final String type;
  final String title;
  final String body;
  final String? subjectType;
  final String? subjectId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get unread => readAt == null;

  IconData get icon {
    switch (type) {
      case 'OFFER_ACTIVITY':
      case 'OFFER_RECEIVED':
        return Icons.local_offer_outlined;
      case 'ORDER_UPDATE':
      case 'ORDER_STATUS':
        return Icons.receipt_long_outlined;
      case 'PAYMENT':
      case 'WALLET_CREDIT':
        return Icons.account_balance_wallet_outlined;
      case 'MESSAGE':
        return Icons.chat_bubble_outline;
      case 'GROUP_ACTIVITY':
      case 'GROUP_ANNOUNCEMENT':
        return Icons.groups_2;
      case 'PRICE_ALERT':
        return Icons.query_stats;
      default:
        return Icons.notifications_outlined;
    }
  }
}

/// Notification center with deep links:
/// offer→/offers, order→/orders, conversation/message→/chat/{id},
/// listing→/listing/{id}, wallet→/wallet, group→Community tab.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<NotificationRow>? _items;
  int _page = 1;
  bool _loadingMore = false;

  Future<void> _load({bool reset = true}) async {
    if (reset) _page = 1;
    try {
      final res = await ref.read(apiClientProvider).getJson('/notifications',
          query: {'page': '$_page', 'per_page': '30'});
      final next = (res['items'] as List? ?? const [])
          .map((j) => NotificationRow.fromJson(j as Map<String, dynamic>))
          .toList();
      setState(() {
        _items = reset ? next : [...(_items ?? []), ...next];
      });
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await ref
          .read(apiClientProvider)
          .postJson('/notifications/read-all', {});
      await _load();
    } catch (_) {}
  }

  void _open(NotificationRow n) {
    // Best-effort deep link by subject.
    final t = n.subjectType;
    final id = n.subjectId;
    if (id == null) return;
    switch (t) {
      case 'conversation':
      case 'message':
        context.go('/chat/$id');
        break;
      case 'offer':
      case 'order':
        context.go('/orders');
        break;
      case 'listing':
        context.go('/listing/$id');
        break;
      case 'group':
        context.go('/community');
        break;
      default:
        break;
    }
    if (n.unread) {
      ref.read(apiClientProvider).postJson('/notifications/${n.id}/read', {});
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(),
        child: _items == null
            ? ListView(children: const [Skeleton(height: 70), Skeleton(height: 70)])
            : _items!.isEmpty
                ? ListView(children: [
                    EmptyState(
                        icon: Icons.notifications_none,
                        title: 'All caught up',
                        message:
                            'Offers, orders, payments and community news will appear here.')
                  ])
                : ListView.builder(
                    itemCount: _items!.length + 1,
                    itemBuilder: (context, i) {
                      if (i >= _items!.length) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: OutlinedButton(
                            onPressed: _loadingMore
                                ? null
                                : () async {
                                    setState(() => _loadingMore = true);
                                    _page++;
                                    await _load(reset: false);
                                    setState(() => _loadingMore = false);
                                  },
                            child: Text(_loadingMore
                                ? 'Loading…'
                                : 'Load older'),
                          ),
                        );
                      }
                      final n = _items![i];
                      return Card(
                        color: n.unread
                            ? IjwiColors.greenLight.withOpacity(0.55)
                            : Colors.white,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: n.unread
                                ? IjwiColors.green.withOpacity(0.15)
                                : const Color(0xFFEEF2EF),
                            child: Icon(n.icon,
                                size: 20,
                                color: n.unread
                                    ? IjwiColors.greenDark
                                    : IjwiColors.muted),
                          ),
                          title: Text(n.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: n.unread
                                      ? FontWeight.w800
                                      : FontWeight.w600)),
                          subtitle: Text(n.body,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Text(timeAgo(n.createdAt),
                              style: const TextStyle(
                                  fontSize: 11, color: IjwiColors.muted)),
                          onTap: () => _open(n),
                        ),
                      );
                    }),
      ),
    );
  }
}
