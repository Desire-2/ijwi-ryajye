import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import '../../features/auth/auth_controller.dart';
import '../../shared/widgets/ui.dart';

class _HomeData {
  int listings = 0;
  int orders = 0;
  int availableMinor = 0;
  List<Map<String, dynamic>> prices = [];
  bool loaded = false;
}

/// Personalized dashboard: role-aware greeting, live stats, quick actions,
/// market pulse strip and next-step guidance.
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  _HomeData _data = _HomeData();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    final d = _HomeData();
    await Future.wait([
      api
          .getJson('/listings/mine', query: {'page': '1', 'per_page': '1'})
          .then((r) => d.listings =
              ((r['pagination'] as Map<String, dynamic>?)?['total'] as num?)
                      ?.toInt() ??
                  (r['items'] as List?)?.length ??
                  0)
          .catchError((_) => 0),
      api
          .getJson('/orders', query: {'page': '1', 'per_page': '1'})
          .then((r) => d.orders =
              ((r['pagination'] as Map<String, dynamic>?)?['total'] as num?)
                      ?.toInt() ??
                  (r['items'] as List?)?.length ??
                  0)
          .catchError((_) => 0),
      api.getJson('/wallet').then((r) {
        d.availableMinor = (r['available_minor'] as num?)?.toInt() ?? 0;
      }).catchError((_) {}),
      api
          .getJson('/market-prices')
          .then((r) =>
              d.prices = ((r['prices'] as List?) ?? const [])
                  .take(3)
                  .toList()
                  .cast<Map<String, dynamic>>())
          .catchError((_) => <Map<String, dynamic>>[]),
    ]);
    if (!mounted) return;
    setState(() => _data = d..loaded = true);
  }

  String _greeting(String hourPart) {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    final user = ref.watch(authProvider).valueOrNull;
    final role = user?.primaryRole ?? '';
    final isBuyerOnly = user?.primaryRole == 'BUYER';

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('${_greeting('')}, ${user?.fullName.split(' ').first ?? ''}!',
              overflow: TextOverflow.ellipsis),
          Text(role.isEmpty ? 'Welcome to Ijwi Ryajye' : role,
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        actions: [
          Stack(children: [
            IconButton(
                tooltip: 'Notifications',
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => context.push('/notifications')),
            Positioned(
                right: 9, top: 9,
                child: Container(width: 8, height: 8,
                    decoration: const BoxDecoration(
                        color: IjwiColors.amber, shape: BoxShape.circle))),
          ]),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          // ---- Live stats ----
          Row(children: [
            Expanded(child: StatChip(icon: Icons.storefront_outlined,
                label: 'Listings', value: '${_data.listings}',
                onTap: () => context.go('/sell'))),
            const SizedBox(width: 8),
            Expanded(child: StatChip(icon: Icons.receipt_long_outlined,
                label: 'Orders', value: '${_data.orders}',
                onTap: () => context.go('/orders'))),
            const SizedBox(width: 8),
            Expanded(child: StatChip(icon: Icons.account_balance_wallet_outlined,
                label: tr('wallet'),
                value: formatRwf(_data.availableMinor, withSymbol: false),
                onTap: () => context.go('/wallet'))),
          ]),
          const SizedBox(height: 18),

          // ---- Quick actions ----
          Text('What do you want to do?',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _ActionTile(
                icon: Icons.agriculture,
                label: isBuyerOnly ? 'Browse market' : 'Sell harvest',
                color: IjwiColors.green,
                onTap: () =>
                    context.push(isBuyerOnly ? '/market' : '/sell/new'))),
            const SizedBox(width: 10),
            Expanded(child: _ActionTile(
                icon: Icons.auto_awesome,
                label: 'Ask Ijwi',
                color: IjwiColors.blue,
                onTap: () => context.push('/intelligence'))),
            const SizedBox(width: 10),
            Expanded(child: _ActionTile(
                icon: Icons.local_offer_outlined,
                label: 'My offers',
                color: IjwiColors.amber,
                onTap: () => context.push('/offers'))),
          ]),
          const SizedBox(height: 6),

          // ---- Market pulse strip ----
          SectionHeader(
              'Today\'s market',
              actionLabel: tr('tab_market'),
              onAction: () => context.go('/market')),
          if (!_data.loaded)
            const Skeleton(height: 64)
          else if (_data.prices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Market prices will appear here.',
                  style: TextStyle(color: IjwiColors.muted)),
            )
          else
            ..._data.prices.map((p) {
              final name = p['product_name'] as String? ??
                  p['name'] as String? ??
                  'Product';
              final emoji =
                  (p['emoji'] as String?) ?? (p['product_emoji'] as String?) ?? '🌱';
              final mid = (p['avg_minor'] as num? ??
                      p['mid_minor'] as num? ??
                      0)
                  .toInt();
              final change = (p['change_pct'] as num?)?.toDouble();
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Text(emoji,
                      style: const TextStyle(fontSize: 24)),
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: change == null
                      ? null
                      : Text(
                          '${change >= 0 ? "▲" : "▼"} ${change.abs().toStringAsFixed(1)}% this week',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: change >= 0
                                  ? IjwiColors.green
                                  : IjwiColors.red)),
                  trailing: Text(formatRwf(mid),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: IjwiColors.greenDark)),
                ),
              );
            }),

          const SizedBox(height: 8),
          // ---- Guidance ----
          if (_data.loaded && !isBuyerOnly && _data.listings == 0)
            Card(
              color: IjwiColors.greenLight,
              child: ListTile(
                leading: const Icon(Icons.tips_and_updates_outlined,
                    color: IjwiColors.greenDark),
                title: const Text('Post your first harvest',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text(
                    'Add what you have to sell and buyers across Rwanda can find you today.',
                    style: TextStyle(fontSize: 12.5)),
                trailing: const Icon(Icons.arrow_forward,
                    color: IjwiColors.greenDark),
                onTap: () => context.push('/sell/new'),
              ),
            ),
          if (_data.loaded && isBuyerOnly)
            Card(
              color: IjwiColors.blue.withOpacity(0.08),
              child: ListTile(
                leading: const Icon(Icons.groups_2, color: IjwiColors.blue),
                title: const Text('Join farmer communities',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text(
                    'Talk directly to growers in groups and get the best farm-gate prices.',
                    style: TextStyle(fontSize: 12.5)),
                trailing:
                    const Icon(Icons.arrow_forward, color: IjwiColors.blue),
                onTap: () => context.go('/community'),
              ),
            ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(
      {required this.icon, required this.label, required this.color,
      required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(IjwiRadius.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(IjwiRadius.md),
          border: Border.all(color: const Color(0xFFD7E2DA)),
        ),
        child: Column(children: [
          CircleAvatar(
              radius: 21,
              backgroundColor: color.withOpacity(0.13),
              child: Icon(icon, color: color, size: 22)),
          const SizedBox(height: 7),
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
