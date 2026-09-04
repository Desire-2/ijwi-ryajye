import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import '../../shared/widgets/ui.dart';
import '../market/market_realtime.dart';
import '../market/marketplace_models.dart';
import '../market/marketplace_repository.dart';

/// Seller dashboard: every number comes from `/seller/dashboard`, computed
/// server-side from the seller's own listings / offers / orders / wallet.
class SellerDashboardScreen extends ConsumerStatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  ConsumerState<SellerDashboardScreen> createState() =>
      _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends ConsumerState<SellerDashboardScreen>
    with MarketRealtime {
  SellerDashboard? _dash;
  String? _error;

  Future<void> _load() async {
    try {
      final dash =
          await ref.read(marketplaceRepositoryProvider).sellerDashboard();
      if (!mounted) return;
      setState(() {
        _dash = dash;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    attachMarketRealtime({
      // New/updated offers and order or wallet changes refresh the KPIs live.
      'offer.created': (_) => _load(),
      'offer.updated': (_) => _load(),
      'order.updated': (_) => _load(),
      'wallet.updated': (_) => _load(),
    });
  }

  @override
  void dispose() {
    detachMarketRealtime();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dash = _dash;
    return Scaffold(
      appBar: AppBar(title: const Text('Seller dashboard')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: dash == null
            ? (_error != null
                ? ListView(children: [ErrorBox(_error!, onRetry: _load)])
                : ListView(children: const [
                    Skeleton(height: 140),
                    SizedBox(height: 10),
                    Skeleton(height: 84),
                    SizedBox(height: 10),
                    Skeleton(height: 84),
                  ]))
            : _buildBody(dash),
      ),
    );
  }

  Widget _buildBody(SellerDashboard dash) {
    final s = dash.summary;
    if (s.listingsTotal == 0 && s.ordersTotal == 0) {
      // Fresh seller: guide them to publish (spec §92 no-dead-end).
      return ListView(children: [
        EmptyState(
          icon: Icons.storefront_outlined,
          title: 'No sales activity yet',
          message:
              'Publish your harvest and buyer offers, orders and revenue will appear here.',
          actionLabel: 'Sell Your Harvest',
          onAction: () => context.push('/sell/new'),
        ),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _revenueCard(dash),
        const SizedBox(height: 12),
        _trustRow(dash),
        const SizedBox(height: 12),
        _kpiGrid(dash),
        const SizedBox(height: 18),
        _sectionTitle('Listing performance',
            count: s.listingsTotal, onSeeAll: s.listingsTotal > 3
                ? () => context.push('/sell')
                : null),
        ...dash.listings.take(3).map(_listingRow),
        if (dash.listings.isEmpty)
          _emptyHint('No listings yet — publish one to start tracking views.'),
        const SizedBox(height: 18),
        _sectionTitle('Recent orders',
            count: dash.recentOrders.length,
            onSeeAll: dash.recentOrders.isNotEmpty
                ? () => context.push('/orders')
                : null),
        ...dash.recentOrders.map(_orderRow),
        if (dash.recentOrders.isEmpty)
          _emptyHint('Orders you receive will show up here in real time.'),
        const SizedBox(height: 18),
        _sectionTitle('Incoming offers',
            count: s.offersTotal,
            onSeeAll: dash.recentOffers.isNotEmpty
                ? () => context.push('/offers')
                : null),
        ...dash.recentOffers.map(_offerRow),
        if (dash.recentOffers.isEmpty)
          _emptyHint('Offers from buyers appear here as soon as they arrive.'),
        const SizedBox(height: 24),
      ],
    );
  }

  // ---------- Revenue + wallet ----------

  Widget _revenueCard(SellerDashboard dash) {
    final s = dash.summary;
    final cur = dash.wallet.currencyCode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: IjwiColors.green,
        borderRadius: BorderRadius.circular(IjwiRadius.lg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Net revenue',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
        const SizedBox(height: 4),
        Text(formatMoney(s.netRevenueMinor, cur),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Row(children: [
          _revChip('Gross', formatMoney(s.grossSalesMinor, cur)),
          const SizedBox(width: 8),
          _revChip('Fees', '− ${formatMoney(s.feesMinor, cur)}'),
        ]),
        const Divider(color: Colors.white24, height: 22),
        Row(children: [
          Expanded(
            child: _walletLine('Available to withdraw',
                formatMoney(dash.wallet.availableMinor, cur)),
          ),
          Expanded(
            child: _walletLine('Pending release',
                formatMoney(dash.wallet.pendingMinor, cur)),
          ),
        ]),
      ]),
    );
  }

  Widget _revChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label  $value',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700)),
    );
  }

  Widget _walletLine(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
      const SizedBox(height: 2),
      Text(value,
          style: const TextStyle(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
    ]);
  }

  Widget _trustRow(SellerDashboard dash) {
    final s = dash.summary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          const Icon(Icons.star_rounded, color: IjwiColors.amber, size: 30),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              s.ratingCount > 0 ? s.ratingAvg.toStringAsFixed(1) : '—',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            Text('${s.ratingCount} review(s)',
                style: const TextStyle(fontSize: 11, color: IjwiColors.muted)),
          ]),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: IjwiColors.greenLight,
                borderRadius: BorderRadius.circular(999)),
            child: Text(_titleCase(s.reputationTier),
                style: const TextStyle(
                    color: IjwiColors.greenDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${s.completedTransactions}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900)),
            const Text('completed',
                style: TextStyle(fontSize: 11, color: IjwiColors.muted)),
          ]),
        ]),
      ),
    );
  }

  // ---------- KPI tiles ----------

  Widget _kpiGrid(SellerDashboard dash) {
    final s = dash.summary;
    return LayoutBuilder(builder: (context, box) {
      final tile = (box.maxWidth - 10) / 2;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        _kpi(tile, Icons.visibility_outlined, 'Views',
            '${s.totalViews}'),
        _kpi(tile, Icons.storefront_outlined, 'Active listings',
            '${s.listingsActive}'),
        _kpi(tile, Icons.mail_outline, 'Pending offers',
            '${s.offersPending}',
            highlight: s.offersPending > 0),
        _kpi(tile, Icons.receipt_long_outlined, 'Open orders',
            '${s.ordersOpen}'),
        _kpi(tile, Icons.task_alt, 'Completed', '${s.ordersCompleted}'),
        _kpi(tile, Icons.verified_outlined, 'Transactions',
            '${s.completedTransactions}'),
      ]);
    });
  }

  Widget _kpi(double width, IconData icon, String label, String value,
      {bool highlight = false}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight ? IjwiColors.amber.withValues(alpha: 0.14) : IjwiColors.card,
        borderRadius: BorderRadius.circular(IjwiRadius.md),
        border: highlight ? Border.all(color: IjwiColors.amber, width: 1.2) : null,
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: IjwiColors.green),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w900)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: IjwiColors.muted)),
          ]),
        ),
      ]),
    );
  }

  // ---------- Sections ----------

  Widget _sectionTitle(String title, {int? count, VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        if (onSeeAll != null)
          TextButton(onPressed: onSeeAll, child: const Text('See all')),
      ]),
    );
  }

  Widget _emptyHint(String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(message,
          style: const TextStyle(color: IjwiColors.muted, fontSize: 13)),
    );
  }

  Widget _listingRow(DashboardListingRow l) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => context.push('/listing/${l.id}'),
        leading: Text(l.emoji, style: const TextStyle(fontSize: 26)),
        title: Text(l.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Wrap(spacing: 10, children: [
            _miniStat(Icons.visibility_outlined, '${l.viewCount}'),
            _miniStat(Icons.mail_outline, '${l.offersPending}'),
            _miniStat(Icons.receipt_long_outlined, '${l.ordersTotal}'),
          ]),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(l.soldValueMinor > 0
                ? formatMoney(l.soldValueMinor, l.currencyCode)
                : '—',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13)),
            Text(
                '${formatQuantity(l.availableQuantity, l.unitCode)} left',
                style: const TextStyle(
                    fontSize: 11, color: IjwiColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String value) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: IjwiColors.muted),
      const SizedBox(width: 2),
      Text(value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _orderRow(DashboardOrderRow o) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => context.push('/orders/${o.id}'),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: _stateColor(o.state).withValues(alpha: 0.14),
          child: Icon(Icons.receipt_long_outlined,
              size: 18, color: _stateColor(o.state)),
        ),
        title: Row(children: [
          Flexible(
            child: Text(o.orderNumber,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 6),
          _stateChip(o.state),
        ]),
        subtitle: Text(
            '${o.buyerName} · ${o.listingTitle ?? ''} · ${formatQuantity(o.quantityValue, o.unitCode)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatMoney(o.totalAmountMinor, o.currencyCode),
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13)),
            if (timeAgoIso(o.createdAt).isNotEmpty)
              Text(timeAgoIso(o.createdAt),
                  style: const TextStyle(
                      fontSize: 11, color: IjwiColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _offerRow(DashboardOfferRow o) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => context.push('/offers'),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: o.state == 'PENDING'
              ? IjwiColors.greenLight
              : const Color(0xFFEEE7DA),
          child: Icon(Icons.mail_outline,
              size: 18,
              color:
                  o.state == 'PENDING' ? IjwiColors.greenDark : IjwiColors.muted),
        ),
        title: Text('${o.buyerName} · ${o.listingTitle ?? 'Listing'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(
            '${formatQuantity(o.quantityValue, o.unitCode)} @ '
            '${formatMoney(o.priceMinor, o.currencyCode)}/${o.unitCode}'
            '${timeAgoIso(o.createdAt).isEmpty ? '' : ' · ${timeAgoIso(o.createdAt)}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12)),
        trailing: _stateChip(o.state),
      ),
    );
  }

  Widget _stateChip(String state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _stateColor(state).withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(_titleCase(state),
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: _stateColor(state))),
    );
  }

  Color _stateColor(String state) {
    const open = {
      'PENDING', 'PAID', 'PROCESSING', 'READY_FOR_PICKUP', 'IN_TRANSIT',
      'DELIVERED', 'ACTIVE',
    };
    const bad = {
      'CANCELLED', 'REFUNDED', 'DISPUTED', 'REJECTED', 'EXPIRED', 'WITHDRAWN',
    };
    if (bad.contains(state)) return IjwiColors.red;
    if (state == 'COMPLETED') return IjwiColors.greenDark;
    if (state == 'PAUSED' || state == 'CLOSED') return IjwiColors.muted;
    if (open.contains(state)) return IjwiColors.blue;
    return IjwiColors.muted;
  }

  String _titleCase(String raw) {
    if (raw.isEmpty) return raw;
    return raw
        .toLowerCase()
        .split('_')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
