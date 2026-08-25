import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';

class ListingSummary {
  ListingSummary.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String? ?? '',
        priceMinor = (j['price_minor'] as num?)?.toInt() ?? 0,
        quantity = (j['quantity_value'] as num?)?.toDouble() ?? 0,
        unit = j['unit_code'] as String? ?? 'kg',
        auction = (j['listing_type'] as String?) == 'AUCTION',
        region = j['location_region'] as String?,
        product =
            (j['product'] as Map<String, dynamic>?)?['name'] as String?;

  final String id;
  final String title;
  final int priceMinor;
  final double quantity;
  final String unit;
  final bool auction;
  final String? region;
  final String? product;
}

class _MarketPrice {
  _MarketPrice.fromJson(Map<String, dynamic> j)
      : name = (j['product'] as Map<String, dynamic>?)?['name'] as String? ?? '—',
        midMinor = (j['price_mid_minor'] as num?)?.toInt() ?? 0;

  final String name;
  final int midMinor;
}

class MarketScreen extends ConsumerStatefulWidget {
  const MarketScreen({super.key});

  @override
  ConsumerState<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends ConsumerState<MarketScreen> {
  List<ListingSummary>? _items;
  List<_MarketPrice>? _prices;
  String? _error;
  String _search = '';
  int _page = 1;

  Future<void> _loadPrices() async {
    try {
      final res =
          await ref.read(apiClientProvider).getJson('/market-prices',
              query: {'days': '1', 'limit': '12'});
      final seen = <String>{};
      final prices = <_MarketPrice>[];
      for (final j in (res['prices'] as List? ?? const [])) {
        final p = _MarketPrice.fromJson(j as Map<String, dynamic>);
        if (seen.add(p.name)) prices.add(p);
      }
      setState(() => _prices = prices.take(8).toList());
    } catch (_) {
      // Prices are a bonus strip; never block the listings view.
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _page = 1;
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/listings', query: {
        'page': '$_page',
        'per_page': '20',
        if (_search.isNotEmpty) 'product': _search,
      });
      final next = (res['items'] as List? ?? const [])
          .map((j) => ListingSummary.fromJson(j as Map<String, dynamic>))
          .toList();
      setState(() {
        _items = reset ? next : [...(_items ?? []), ...next];
        _error = null;
      });
    } catch (e) {
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _loadPrices();
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('tab_market')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              onSubmitted: (v) {
                _search = v.trim();
                _load(reset: true);
              },
              decoration: InputDecoration(
                hintText: '${tr('tab_market')}…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: Builder(builder: (context) {
          if (_error != null && _items == null) {
            return ListView(children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ]);
          }
          if (_items == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.builder(
            itemCount: _items!.length + (_prices?.isEmpty == false ? 1 : 0) + 1,
            itemBuilder: (context, i) {
              if (i == 0 && _prices != null && _prices!.isNotEmpty) {
                return SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    itemCount: _prices!.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, pi) {
                      final p = _prices![pi];
                      return Container(
                        width: 128,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(IjwiRadius.md),
                          border: Border.all(color: const Color(0xFFD7E2DA)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13)),
                            const Spacer(),
                            Text(compactRwf(p.midMinor),
                                style: const TextStyle(
                                    color: IjwiColors.green,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14)),
                          ],
                        ),
                      );
                    },
                  ),
                );
              }
              final li = i - ((_prices?.isEmpty == false ? 1 : 0));
              if (li == _items!.length) {
                return TextButton(
                  onPressed: () {
                    _page++;
                    _load();
                  },
                  child: const Text('Load more'),
                );
              }
              final l = _items![li];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: IjwiColors.greenLight,
                    child: Text(l.product?.isNotEmpty == true
                        ? l.product![0].toUpperCase()
                        : '?'),
                  ),
                  title: Text(l.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${formatRwf(l.priceMinor)} / ${l.unit}'
                      ' · ${l.quantity.toStringAsFixed(0)} ${l.unit}'
                      '${l.region != null ? ' · ${l.region}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: l.auction
                      ? const Chip(
                          avatar: Icon(Icons.gavel, size: 14),
                          label: Text('BID'),
                          visualDensity: VisualDensity.compact)
                      : null,
                  onTap: () => context.go('/listing/${l.id}'),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
