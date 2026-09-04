import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import '../../features/market/market_realtime.dart';
import '../../features/market/marketplace_models.dart';
import '../../features/market/marketplace_repository.dart';
import '../../features/market/marketplace_widgets.dart';
import '../../shared/widgets/ui.dart';

/// Orders hub: buyer/seller tabs with state, filtered by backend `state`
/// param, tapping opens the full order detail (timeline, transitions, pay).
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen>
    with MarketRealtime {
  List<OrderJson>? _items;
  String? _error;
  String _state = '';

  @override
  void initState() {
    super.initState();
    _load();
    // Order transitions (including payment confirmation and delivery
    // advances) refresh the list automatically.
    attachMarketRealtime({
      'order.updated': (_) => _load(),
      'order.created': (_) => _load(),
    });
  }

  @override
  void dispose() {
    detachMarketRealtime();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(marketplaceRepositoryProvider);
      final page = await repo.orders(state: _state.isEmpty ? null : _state);
      if (mounted) {
        setState(() {
          _items = page.items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  Color _stateColor(String s) => switch (s) {
        'COMPLETED' || 'DELIVERED' || 'PAID' => IjwiColors.green,
        'CANCELLED' || 'DISPUTED' || 'REFUNDED' => IjwiColors.red,
        'IN_TRANSIT' || 'READY_FOR_PICKUP' || 'PROCESSING' => IjwiColors.blue,
        'PAYMENT_PENDING' => IjwiColors.amber,
        _ => IjwiColors.muted,
      };

  String _stateLabel(String s) => switch (s) {
        'PAYMENT_PENDING' => 'Payment pending',
        'PROCESSING' => 'Processing',
        'READY_FOR_PICKUP' => 'Ready',
        'IN_TRANSIT' => 'In transit',
        'DELIVERED' => 'Delivered',
        'COMPLETED' => 'Completed',
        'CANCELLED' => 'Cancelled',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (label, value) in [
                    ('All', ''),
                    ('Active', 'PROCESSING'),
                    ('Paid', 'PAID'),
                    ('Done', 'COMPLETED'),
                    ('Cancelled', 'CANCELLED'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(label,
                            style: const TextStyle(fontSize: 12.5)),
                        selected: _state == value,
                        onSelected: (_) {
                          setState(() {
                            _state = value;
                            _items = null;
                          });
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _items == null
            ? (_error != null
                ? ListView(children: [ErrorBox(_error!, onRetry: _load)])
                : ListView(padding: const EdgeInsets.all(14), children: const [
                    Skeleton(height: 96), SizedBox(height: 8),
                    Skeleton(height: 96),
                  ]))
            : _items!.isEmpty
                ? const MarketplaceEmpty(
                    icon: Icons.receipt_long_outlined,
                    title: 'No orders here',
                    message:
                        'Orders from accepted offers and direct purchases will appear here.')
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: _items!.length,
                    itemBuilder: (context, i) {
                      final o = _items![i];
                      final color = _stateColor(o.state);
                      return Card(
                        margin:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        child: ListTile(
                          title: Row(children: [
                            Expanded(
                              child: Text(
                                o.orderNumber,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14.5),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: color.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                  _stateLabel(o.state).toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: color)),
                            ),
                          ]),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              '${o.quantityValue.toStringAsFixed(o.quantityValue == o.quantityValue.roundToDouble() ? 0 : 2)} ${o.unitCode}'
                              '${o.items.isNotEmpty && o.items.first.description.isNotEmpty ? ' · ${o.items.first.description}' : ''}'
                              ' · ${timeAgoIso(o.createdAt) == '' ? 'recent' : timeAgoIso(o.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(formatMoney(o.totalAmountMinor, o.currencyCode),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 14.5)),
                            const SizedBox(width: 6),
                            const Icon(Icons.chevron_right,
                                color: IjwiColors.muted),
                          ]),
                          onTap: () async {
                            await context.push('/orders/${o.id}');
                            await _load();
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}