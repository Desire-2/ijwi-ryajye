import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';

class ListingDetail {
  ListingDetail.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String? ?? '',
        priceMinor = (j['price_minor'] as num?)?.toInt() ?? 0,
        quantity = (j['quantity_value'] as num?)?.toDouble() ?? 0,
        unit = j['unit_code'] as String? ?? 'kg',
        listingType = j['listing_type'] as String? ?? 'FIXED_PRICE',
        region = j['location_region'] as String?,
        sellerId = (j['seller'] as Map<String, dynamic>?)?['id'] as String?;

  final String id;
  final String title;
  final int priceMinor;
  final double quantity;
  final String unit;
  final String listingType;
  final String? region;
  final String? sellerId;

  bool get isAuction => listingType == 'AUCTION';
}

class ListingDetailScreen extends ConsumerStatefulWidget {
  const ListingDetailScreen({required this.listingId, super.key});

  final String listingId;

  @override
  ConsumerState<ListingDetailScreen> createState() =>
      _ListingDetailScreenState();
}

class _ListingDetailScreenState extends ConsumerState<ListingDetailScreen> {
  ListingDetail? _listing;
  String? _error;
  bool _sending = false;

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/listings/${widget.listingId}');
      setState(() {
        _listing =
            ListingDetail.fromJson(res['listing'] as Map<String, dynamic>);
        _error = null;
      });
    } catch (e) {
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _makeOffer() async {
    final l = _listing!;
    final qtyCtl = TextEditingController(text: '10');
    final priceCtl =
        TextEditingController(text: (l.priceMinor).toStringAsFixed(0));
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.isAuction ? 'Place bid' : 'Make offer',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
              controller: qtyCtl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'Quantity (${l.unit})'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtl,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Price per unit (minor)'),
            ),
            const SizedBox(height: 8),
            Text('Total ≈ ${compactRwf(l.priceMinor * 10)}',
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.isAuction ? 'Place bid' : 'Send offer'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _sending = true);
    try {
      if (l.isAuction) {
        await ref.read(apiClientProvider).postJson('/bids', {
          'listing_id': l.id,
          'amount_minor': int.tryParse(priceCtl.text.trim()) ?? 0,
          'quantity_value':
              double.tryParse(qtyCtl.text.trim()) ?? 0,
        });
      } else {
        await ref.read(apiClientProvider).postJson('/offers', {
          'listing_id': l.id,
          'quantity_value': double.tryParse(qtyCtl.text.trim()) ?? 0,
          'price_minor': int.tryParse(priceCtl.text.trim()) ?? 0,
        });
      }
      // Offline-safe: also record in outbox for retry semantics.
      await ref.read(syncEngineProvider.future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l.isAuction ? 'Bid placed' : 'Offer sent')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    final l = _listing;
    return Scaffold(
      appBar: AppBar(title: Text(l?.title ?? tr('tab_market'))),
      body: _error != null
          ? ListView(children: [
              Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red)))
            ])
          : l == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.title,
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Text(
                                '${formatRwf(l.priceMinor)} / ${l.unit}',
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: IjwiColors.green)),
                            const SizedBox(height: 10),
                            Wrap(spacing: 8, children: [
                              Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(l.isAuction
                                      ? 'AUCTION'
                                      : l.listingType)),
                              if (l.region != null)
                                Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(l.region!)),
                            ]),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _sending ? null : _makeOffer,
                      icon: const Icon(Icons.local_offer_outlined),
                      label: Text(l.isAuction
                          ? tr('place_bid')
                          : tr('make_offer')),
                    ),
                  ],
                ),
    );
  }
}
