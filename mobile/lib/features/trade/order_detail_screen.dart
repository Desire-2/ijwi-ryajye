import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/market/market_realtime.dart';
import '../../features/market/marketplace_models.dart';
import '../../features/market/marketplace_repository.dart';
import '../../shared/widgets/ui.dart';

/// Order detail: products, fees, payment state, timeline from real backend
/// events, and role-aware actions (pay, transition, cancel, review).
class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen>
    with MarketRealtime {
  OrderJson? _order;
  String? _error;
  bool _busy = false;

  Future<void> _load() async {
    try {
      final o = await ref.read(marketplaceRepositoryProvider).order(widget.orderId);
      if (mounted) {
        setState(() {
          _order = o;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    attachMarketRealtime({
      // Only refresh when this order (or its delivery) actually changed.
      'order.updated': (data) {
        if (data['order_id'] == widget.orderId) _load();
      },
      'delivery.updated': (data) {
        final deliveryId = data['delivery_id'];
        if (deliveryId != null && deliveryId == _order?.deliveryId) _load();
      },
    }, debounceMs: 0);
  }

  @override
  void dispose() {
    detachMarketRealtime();
    super.dispose();
  }

  Future<void> _act(String action) async {
    final o = _order!;
    setState(() => _busy = true);
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      switch (action) {
        case 'pay':
          await repo.initiatePayment(o.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Payment initiated — awaiting confirmation'),
                backgroundColor: IjwiColors.green));
          }
        case 'cancel':
          await repo.cancelOrder(o.id);
        default:
          await repo.transitionOrder(o.id, action);
      }
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    final o = _order!;
    final me = ref.watch(authProvider).valueOrNull;
    final subjectRole = me?.id == o.sellerId ? 'buyer' : 'farmer';
    double rating = 5;
    final commentCtl = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Leave a review',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          StatefulBuilder(
            builder: (context, setLocal) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    iconSize: 34,
                    color: i <= rating ? IjwiColors.amber : IjwiColors.muted,
                    icon: Icon(
                        i <= rating ? Icons.star : Icons.star_border),
                    onPressed: () => setLocal(() => rating = i.toDouble()),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: commentCtl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Comment (optional)',
                hintText: 'Quality, communication, reliability…'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit review'),
          ),
        ]),
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(marketplaceRepositoryProvider)
          .reviewOrder(o.id,
              subjectRole: subjectRole,
              overall: rating.round(),
              comment: commentCtl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Review submitted'), backgroundColor: IjwiColors.green));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_order?.orderNumber ?? 'Order',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: _order == null
          ? (_error != null
              ? ListView(children: [ErrorBox(_error!, onRetry: _load)])
              : ListView(padding: const EdgeInsets.all(14), children: const [
                  Skeleton(height: 120), SizedBox(height: 8),
                  Skeleton(height: 160),
                ]))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                _statusHeader(_order!),
                const SizedBox(height: 4),
                _productCard(_order!),
                _moneyCard(_order!),
                if (_order!.events.isNotEmpty) _timeline(_order!),
                _actions(_order!),
              ]),
            ),
    );
  }

  Widget _statusHeader(OrderJson o) {
    final color = _stateColor(o.state);
    return Card(
      margin: const EdgeInsets.all(12),
      color: color.withOpacity(0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: color.withOpacity(0.14), shape: BoxShape.circle),
            child: Icon(_stateIcon(o.state), color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_stateLabel(o.state),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 17)),
              Text(
                  'Created ${timeAgoIso(o.createdAt) == '' ? o.createdAt ?? '' : timeAgoIso(o.createdAt)}'
                  '${o.cancelledReason != null ? ' · ${o.cancelledReason}' : ''}',
                  style: const TextStyle(fontSize: 12, color: IjwiColors.muted)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _productCard(OrderJson o) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final item in o.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                  child: Text(
                      '${item.description.isNotEmpty ? item.description : 'Product'}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                Text(
                    '${item.quantityValue.toStringAsFixed(item.quantityValue == item.quantityValue.roundToDouble() ? 0 : 2)} ${item.unitCode}',
                    style: const TextStyle(fontSize: 13)),
              ]),
            ),
          const Divider(height: 18),
          _row('Delivery', o.deliveryOption.replaceAll('_', ' ')),
          if (o.paymentTerms.isNotEmpty) _row('Payment terms', o.paymentTerms),
          if (o.hasContract) _row('Contract', 'Active'),
          if (o.deliveryId != null)
            _row('Delivery ID', o.deliveryId!),
        ]),
      ),
    );
  }

  Widget _moneyCard(OrderJson o) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row('Subtotal (${o.quantityValue.toStringAsFixed(o.quantityValue == o.quantityValue.roundToDouble() ? 0 : 2)} ${o.unitCode})',
              formatMoney(o.totalAmountMinor - o.platformFeeMinor, o.currencyCode)),
          _row('Platform fee', formatMoney(o.platformFeeMinor, o.currencyCode)),
          const Divider(height: 18),
          Row(children: [
            const Text('Total',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const Spacer(),
            Text(formatMoney(o.totalAmountMinor, o.currencyCode),
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    color: o.needsPayment ? IjwiColors.amber : IjwiColors.greenDark)),
          ]),
          Text('Unit price ${formatMoney(o.unitPriceMinor, o.currencyCode)} / ${o.unitCode}',
              style: const TextStyle(fontSize: 11.5, color: IjwiColors.muted)),
        ]),
      ),
    );
  }

  Widget _timeline(OrderJson o) {
    final steps = o.events.where((e) => e.toState != null).toList();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Timeline',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 10),
          for (final e in steps)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.check_circle,
                    size: 17, color: IjwiColors.green),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_stateLabel(e.toState!),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13.5)),
                    if (e.at != null)
                      Text(timeAgoIso(e.at) == '' ? e.at! : timeAgoIso(e.at!),
                          style: const TextStyle(
                              fontSize: 11.5, color: IjwiColors.muted)),
                  ]),
                ),
              ),
            ]),
        ]),
      ),
    );
  }

  Widget _actions(OrderJson o) {
    final me = ref.watch(authProvider).valueOrNull;
    final isSeller = me?.id == o.sellerId;
    final actions = <Widget>[];
    void add(Widget w) => actions.add(w);

    if (o.needsPayment && !isSeller) {
      add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: FilledButton.icon(
          onPressed: _busy ? null : () => _act('pay'),
          icon: const Icon(Icons.payment),
          label: Text(_busy ? 'Processing…' : 'Pay now — ${formatMoney(o.totalAmountMinor, o.currencyCode)}'),
        ),
      ));
    }

    final transitions = <String>[];
    if (isSeller) {
      if (o.state == 'PAID') transitions.add('PROCESSING');
      if (o.state == 'PROCESSING') transitions.add('READY_FOR_PICKUP');
      if (o.state == 'READY_FOR_PICKUP') transitions.add('IN_TRANSIT');
    } else {
      if (o.state == 'IN_TRANSIT') transitions.add('DELIVERED');
      if (o.state == 'DELIVERED') transitions.add('COMPLETED');
      if (o.state == 'COMPLETED') transitions.add('REVIEW');
    }
    // Any party can mark a delivered order completed (backend allows it).
    if (o.state == 'DELIVERED') transitions.add('COMPLETED');

    for (final t in transitions) {
      if (t == 'REVIEW') {
        add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: FilledButton.tonal(
            onPressed: _busy ? null : _review,
            child: const Text('Leave a review'),
          ),
        ));
        continue;
      }
      add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: FilledButton(
          onPressed: _busy ? null : () => _act(t),
          child: Text(t.replaceAll('_', ' ')),
        ),
      ));
    }

    if (o.state == 'ACCEPTED' || o.state == 'PROCESSING' || o.state == 'READY_FOR_PICKUP') {
      add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: IjwiColors.red),
          onPressed: _busy ? null : () => _act('cancel'),
          child: const Text('Cancel order'),
        ),
      ));
    }

    if (actions.isEmpty) return const SizedBox.shrink();
    return Column(children: actions);
  }

  static Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 120,
            child: Text(k,
                style: const TextStyle(color: IjwiColors.muted, fontSize: 13)),
          ),
          Expanded(
            child: Text(v,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ]),
      );

  Color _stateColor(String s) => switch (s) {
        'COMPLETED' || 'DELIVERED' || 'PAID' => IjwiColors.green,
        'CANCELLED' || 'DISPUTED' || 'REFUNDED' => IjwiColors.red,
        'IN_TRANSIT' || 'READY_FOR_PICKUP' || 'PROCESSING' => IjwiColors.blue,
        'PAYMENT_PENDING' => IjwiColors.amber,
        _ => IjwiColors.muted,
      };

  IconData _stateIcon(String s) => switch (s) {
        'COMPLETED' || 'DELIVERED' => Icons.check_circle,
        'CANCELLED' || 'REFUNDED' => Icons.cancel_outlined,
        'DISPUTED' => Icons.report_problem_outlined,
        'IN_TRANSIT' => Icons.local_shipping_outlined,
        'READY_FOR_PICKUP' => Icons.inventory_2_outlined,
        'PROCESSING' => Icons.precision_manufacturing_outlined,
        'PAYMENT_PENDING' => Icons.payment,
        'PAID' => Icons.verified_outlined,
        _ => Icons.receipt_long_outlined,
      };

  String _stateLabel(String s) => switch (s) {
        'DRAFT' => 'Draft',
        'OFFERED' => 'Offer received',
        'NEGOTIATING' => 'Negotiating',
        'ACCEPTED' => 'Order accepted',
        'PAYMENT_PENDING' => 'Payment pending',
        'PAID' => 'Paid',
        'PROCESSING' => 'Processing',
        'READY_FOR_PICKUP' => 'Ready for pickup',
        'IN_TRANSIT' => 'In transit',
        'DELIVERED' => 'Delivered',
        'COMPLETED' => 'Completed',
        'CANCELLED' => 'Cancelled',
        'DISPUTED' => 'Disputed',
        'REFUNDED' => 'Refunded',
        _ => s,
      };
}