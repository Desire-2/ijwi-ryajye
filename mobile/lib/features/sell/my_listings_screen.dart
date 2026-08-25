import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import '../../shared/widgets/ui.dart';

class MyListingRow {
  MyListingRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String? ?? '',
        state = j['state'] as String? ?? 'ACTIVE',
        priceMinor = (j['price_minor'] as num?)?.toInt() ?? 0,
        available = (j['available_quantity'] as num?)?.toDouble() ?? 0,
        unit = j['unit_code'] as String? ?? 'kg',
        listingType = j['listing_type'] as String? ?? 'FIXED_PRICE',
        emoji =
            (j['product'] as Map<String, dynamic>?)?['emoji'] as String? ?? '🌱';

  final String id;
  final String title;
  final String state;
  final int priceMinor;
  final double available;
  final String unit;
  final String listingType;
  final String emoji;
}

/// "Sell Your Harvest" hub: the farmer's own listings + entry point to publish.
class MyListingsScreen extends ConsumerStatefulWidget {
  const MyListingsScreen({super.key});

  @override
  ConsumerState<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends ConsumerState<MyListingsScreen> {
  List<MyListingRow>? _items;
  String? _error;

  Future<void> _load() async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .getJson('/listings/mine', query: {'per_page': '50'});
      setState(() {
        _items = (res['items'] as List? ?? const [])
            .map((j) => MyListingRow.fromJson(j as Map<String, dynamic>))
            .toList();
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

  Future<void> _closeListing(MyListingRow l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close listing?'),
        content: Text('"${l.title}" will no longer appear in the market.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Close')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(apiClientProvider)
          .postJson('/listings/${l.id}/close', {});
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
    final tr = ref.watch(trProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('my_listings'))),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: IjwiColors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(tr('make_offer') == 'Make offer'
            ? 'Sell Harvest'
            : tr('btn_register')),
        onPressed: () async {
          await context.push('/sell/new');
          await _load();
        },
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _items == null
            ? (_error != null
                ? ListView(children: [ErrorBox(_error!, onRetry: _load)])
                : ListView(children: const [
                    Skeleton(height: 84),
                    SizedBox(height: 8),
                    Skeleton(height: 84),
                  ]))
            : _items!.isEmpty
                ? ListView(children: [
                    EmptyState(
                      icon: Icons.storefront_outlined,
                      title: 'No listings yet',
                      message:
                          'Your harvest can reach buyers around you. Publish your first listing now.',
                      actionLabel: tr('my_listings') == 'My listings'
                          ? 'Sell Your Harvest'
                          : tr('btn_register'),
                      onAction: () async {
                        await context.push('/sell/new');
                        await _load();
                      },
                    ),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: _items!.length,
                    itemBuilder: (context, i) {
                      final l = _items![i];
                      return Card(
                        child: ListTile(
                          leading: Text(l.emoji,
                              style: const TextStyle(fontSize: 28)),
                          title: Text(l.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              '${formatRwf(l.priceMinor)}/${l.unit} · '
                              '${l.available.toStringAsFixed(0)} ${l.unit} left'
                              ' · ${l.listingType == "AUCTION" ? "Auction" : "Fixed"}'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'close') _closeListing(l);
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                  value: 'close', child: Text('Close listing')),
                            ],
                            child: Chip(
                              visualDensity: VisualDensity.compact,
                              backgroundColor:
                                  l.state == 'ACTIVE'
                                      ? IjwiColors.greenLight
                                      : const Color(0xFFEEE7DA),
                              label: Text(l.state,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: l.state == 'ACTIVE'
                                          ? IjwiColors.greenDark
                                          : IjwiColors.muted)),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
