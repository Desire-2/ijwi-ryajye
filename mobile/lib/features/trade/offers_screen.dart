import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import '../../features/market/market_realtime.dart';
import '../../features/market/marketplace_models.dart';
import '../../features/market/marketplace_repository.dart';
import '../../features/market/marketplace_widgets.dart';
import '../../shared/widgets/ui.dart';

/// Offers hub: the user's sent offers (as buyer) and received offers (as
/// seller). Pending offers can be accepted, countered, rejected or withdrawn
/// — all actions go through the backend negotiation state machine.
class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key});

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen>
    with MarketRealtime {
  List<Offer>? _items;
  String? _error;
  String _role = 'seller'; // "seller" = offers I received, "buyer" = offers I sent
  String? _actingOfferId;

  @override
  void initState() {
    super.initState();
    _load();
    // New offers, counters, acceptances and rejections refresh the active
    // list automatically; bursts are coalesced before reloading.
    attachMarketRealtime({
      'offer.created': (_) => _load(),
      'offer.updated': (_) => _load(),
      'offer.accepted': (_) => _load(),
    });
  }

  @override
  void dispose() {
    detachMarketRealtime();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final page =
          await ref.read(marketplaceRepositoryProvider).offers(role: _role);
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

  Future<void> _act(Offer o, String action, {int? price, double? qty}) async {
    setState(() => _actingOfferId = o.id);
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      switch (action) {
        case 'accept':
          final order = await repo.acceptOffer(o.id);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Offer accepted — order created'),
              backgroundColor: IjwiColors.green));
          context.push('/orders/${order.id}');
        case 'reject':
          await repo.rejectOffer(o.id);
        case 'withdraw':
          await repo.withdrawOffer(o.id);
        case 'counter':
          await repo.counterOffer(o.id,
              priceMinor: price ?? 0, quantity: qty,
              message: 'Counteroffer');
      }
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _actingOfferId = null);
    }
  }

  Future<void> _counter(Offer o) async {
    final priceCtl = TextEditingController(text: '${o.priceMinor}');
    final qtyCtl =
        TextEditingController(text: o.quantityValue.toStringAsFixed(0));
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Counteroffer',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
            controller: qtyCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Quantity (${o.unitCode})'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: priceCtl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: 'New price (${o.currencyCode} minor)'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send counteroffer'),
          ),
        ]),
      ),
    );
    if (confirmed != true) return;
    await _act(o, 'counter',
        price: int.tryParse(priceCtl.text.trim()) ?? 0,
        qty: double.tryParse(qtyCtl.text.trim()));
  }

  Color _stateColor(String s) {
    switch (s) {
      case 'ACCEPTED':
        return IjwiColors.green;
      case 'REJECTED':
      case 'EXPIRED':
      case 'WITHDRAWN':
      case 'CANCELLED':
        return IjwiColors.red;
      case 'COUNTERED':
        return IjwiColors.amber;
      default:
        return IjwiColors.blue;
    }
  }

  String _stateLabel(String s) => switch (s) {
        'PENDING' => 'Pending',
        'COUNTERED' => 'Countered',
        'ACCEPTED' => 'Accepted',
        'REJECTED' => 'Rejected',
        'WITHDRAWN' => 'Withdrawn',
        'EXPIRED' => 'Expired',
        'CANCELLED' => 'Cancelled',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offers', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 'seller', label: Text('Received')),
                ButtonSegment(value: 'buyer', label: Text('Sent')),
              ],
              selected: {_role},
              onSelectionChanged: (s) {
                setState(() {
                  _role = s.first;
                  _items = null;
                });
                _load();
              },
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
                    Skeleton(height: 110), SizedBox(height: 8),
                    Skeleton(height: 110),
                  ]))
            : _items!.isEmpty
                ? const MarketplaceEmpty(
                    icon: Icons.local_offer_outlined,
                    title: 'No offers yet',
                    message:
                        'When buyers make offers on your harvest, they appear here.')
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: _items!.length,
                    itemBuilder: (context, i) =>
                        _OfferCard(o: _items![i],
                            acting: _actingOfferId == _items![i].id,
                            onAccept: () => _act(_items![i], 'accept'),
                            onReject: () => _act(_items![i], 'reject'),
                            onWithdraw: () => _act(_items![i], 'withdraw'),
                            onCounter: () => _counter(_items![i]),
                            role: _role,
                            stateColor: _stateColor(_items![i].state),
                            stateLabel: _stateLabel(_items![i].state), tr: tr),
                  ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.o,
    required this.acting,
    required this.onAccept,
    required this.onReject,
    required this.onWithdraw,
    required this.onCounter,
    required this.role,
    required this.stateColor,
    required this.stateLabel,
    required this.tr,
  });

  final Offer o;
  final bool acting;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onWithdraw;
  final VoidCallback onCounter;
  final String role;
  final Color stateColor;
  final String stateLabel;
  final dynamic tr;

  @override
  Widget build(BuildContext context) {
    final canAct = o.isPending && !acting;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                '${o.quantityValue.toStringAsFixed(o.quantityValue == o.quantityValue.roundToDouble() ? 0 : 2)} ${o.unitCode} · '
                '${formatMoney(o.priceMinor, o.currencyCode)}/${o.unitCode}',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: stateColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(stateLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: stateColor)),
            ),
          ]),
          Text(
            'Total ${formatMoney(o.totalMinor, o.currencyCode)}',
            style: const TextStyle(
                fontSize: 13, color: IjwiColors.muted, fontWeight: FontWeight.w700),
          ),
          if (o.message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(o.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5)),
          ],
          if (o.expiresAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text('Expires ${timeAgoIso(o.expiresAt) == '' ? o.expiresAt : timeAgoIso(o.expiresAt)}',
                  style:
                      const TextStyle(fontSize: 11, color: IjwiColors.muted)),
            ),
          if (canAct) ...[
            const SizedBox(height: 10),
            Row(children: [
              if (role == 'seller') ...[
                FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(104, 40)),
                  onPressed: onAccept,
                  child: Text(tr('accept_offer'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(104, 40)),
                  onPressed: onCounter,
                  child: const Text('Counter'),
                ),
                const SizedBox(width: 8),
                IconButton(
                    tooltip: tr('reject'),
                    onPressed: onReject,
                    icon: const Icon(Icons.close, color: IjwiColors.red)),
              ] else ...[
                IconButton(
                    tooltip: 'Withdraw',
                    onPressed: onWithdraw,
                    icon: const Icon(Icons.undo, color: IjwiColors.muted)),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}