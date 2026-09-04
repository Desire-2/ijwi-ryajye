import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../shared/widgets/ui.dart';
import 'market_realtime.dart';
import 'marketplace_models.dart';
import 'marketplace_repository.dart';
import 'marketplace_widgets.dart';

/// Marketplace home: search-first, category rail, market prices, for-you
/// listings, buyer opportunities and trending produce. All sections render
/// real backend data with skeleton loading and empty states.
class MarketScreen extends ConsumerStatefulWidget {
  const MarketScreen({super.key});

  @override
  ConsumerState<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends ConsumerState<MarketScreen> with MarketRealtime {
  List<Category>? _categories;
  List<Listing>? _listings;
  List<BuyerRequest>? _requests;
  List<MarketPriceRow>? _prices;
  bool _loading = true;
  String? _error;
  bool _offline = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      final categoriesFuture = repo.categories();
      final listingsFuture = repo.listings(perPage: 10);
      final requestsFuture = repo.buyerRequests(perPage: 6);
      final pricesFuture = repo.marketPrices(days: 7);
      final categories = await categoriesFuture;
      final listingPage = await listingsFuture;
      final requests = await requestsFuture;
      final prices = await pricesFuture;
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _listings = listingPage.items;
        _requests = requests.items;
        _prices = prices;
        _loading = false;
        _error = null;
        _offline = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (ApiClient.isOfflineError(e)) {
        // No connectivity: fall back to listings cached from earlier feeds.
        final cached = await repo.cachedListings();
        if (!mounted) return;
        setState(() {
          _loading = false;
          _offline = true;
          if (_listings == null) {
            _listings = cached.isEmpty ? null : cached;
            _error = cached.isEmpty ? ApiClient.errorMessage(e) : null;
          } else {
            _error = null; // keep what is already on screen
          }
        });
        return;
      }
      setState(() {
        _loading = false;
        _error = ApiClient.errorMessage(e);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    // New listings refresh the home without a manual pull (personal offer /
    // order events are handled by the offers/orders screens instead).
    attachMarketRealtime({
      'listing.created': (_) => _load(),
    });
  }

  @override
  void dispose() {
    detachMarketRealtime();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Favorites',
            icon: const Icon(Icons.favorite_outline),
            onPressed: () => context.push('/market/favorites'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _listings == null) {
      return ListView(
        padding: const EdgeInsets.all(14),
        children: const [
          Skeleton(height: 46),
          SizedBox(height: 18),
          Skeleton(height: 76),
          SizedBox(height: 12),
          Skeleton(height: 84),
          SizedBox(height: 8),
          Skeleton(height: 84),
          SizedBox(height: 8),
          Skeleton(height: 120),
        ],
      );
    }
    if (_error != null && _listings == null) {
      return ListView(children: [ErrorBox(_error!, onRetry: _load)]);
    }
    if (_offline) {
      return _buildOfflineBody();
    }
    final listings = _listings ?? const <Listing>[];
    final categories = _categories ?? const <Category>[];
    final requests = _requests ?? const <BuyerRequest>[];
    final prices = _prices ?? const <MarketPriceRow>[];

    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      // ---- Search-first ----
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: MarketplaceSearchBar(),
      ),

      // ---- Categories ----
      if (categories.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Row(children: [
            const Text('Categories',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const Spacer(),
            TextButton(
              onPressed: () => context.push('/market/search', extra: {'scope': 'categories'}),
              child: const Text('See all'),
            ),
          ]),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _CategoryPill(categories[i]),
          ),
        ),
      ],

      // ---- Market prices strip ----
      if (prices.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Text('Today’s market prices',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: prices.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _PriceTile(prices[i]),
          ),
        ),
      ],

      // ---- Buyer opportunities ----
      SectionHeader(
        '🔥 Buyer opportunities',
        actionLabel: requests.isNotEmpty ? 'See all' : null,
        onAction: requests.isNotEmpty ? () => context.push('/market/requests') : null,
      ),
      if (requests.isEmpty && !_loading)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('No open buyer requests right now.',
              style: TextStyle(color: IjwiColors.muted)),
        )
      else
        ...requests.map((r) => _OpportunityCard(request: r, repo: ref.read(marketplaceRepositoryProvider))),

      // ---- For you ----
      SectionHeader('For you',
          actionLabel: listings.isNotEmpty ? 'See all' : null,
          onAction: listings.isNotEmpty
              ? () => context.push('/market/search', extra: {'browse': true})
              : null),
      if (listings.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('New listings will appear here.',
              style: TextStyle(color: IjwiColors.muted)),
        )
      else
        ...listings.take(5).map((l) => ListingRow(listing: l)),

      // ---- Trending produce rail ----
      if (listings.length > 3) ...[
        SectionHeader('⚡ Latest harvests',
            actionLabel: 'See all',
            onAction: () => context.push('/market/search', extra: {'browse': true})),
        SizedBox(
          height: 232,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: listings.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => SizedBox(
              width: 168,
              child: ProductCard(listing: listings[i]),
            ),
          ),
        ),
      ],
    ]);
  }

  /// Offline fallback: banner + listings saved from earlier feeds. Tapping a
  /// listing still opens its cached detail load (which degrades gracefully).
  Widget _buildOfflineBody() {
    final listings = _listings ?? const <Listing>[];
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: MarketplaceSearchBar(),
      ),
      const SizedBox(height: 4),
      const _OfflineBanner(),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          const Text('Saved listings',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const Spacer(),
          if (listings.isNotEmpty)
            TextButton(onPressed: _load, child: const Text('Retry')),
        ]),
      ),
      if (listings.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'No saved listings yet — open the marketplace once online and\nproduce will be available here while you are offline.',
            style: TextStyle(color: IjwiColors.muted, height: 1.4),
          ),
        )
      else
        ...listings.take(12).map((l) => ListingRow(listing: l)),
    ]);
  }
}

/// Amber banner shown at the top of the marketplace when we fell back to the
/// local cache because the network is unreachable.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(IjwiRadius.md),
        border: Border.all(color: IjwiColors.amber, width: 1.1),
      ),
      child: Row(children: [
        const Icon(Icons.wifi_off_rounded, color: IjwiColors.amber, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('You’re offline',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: IjwiColors.ink)),
              SizedBox(height: 2),
              Text('Showing saved listings. Pull to refresh to retry.',
                  style:
                      TextStyle(fontSize: 12, color: IjwiColors.muted)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill(this.category);

  final Category category;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(IjwiRadius.md),
      onTap: () => context.push('/market/search', extra: {'category': category}),
      child: Container(
        width: 104,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(IjwiRadius.md),
          border: Border.all(color: const Color(0xFFD7E2DA)),
        ),
        child: Column(children: [
          Text(category.icon.isNotEmpty ? category.icon : '🌾',
              style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 6),
          Text(category.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _PriceTile extends StatelessWidget {
  const _PriceTile(this.price);

  final MarketPriceRow price;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(IjwiRadius.md),
        border: Border.all(color: const Color(0xFFD7E2DA)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(price.productName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
        const Spacer(),
        Text(
          price.midMinor != null
              ? '${(price.midMinor! / 100).toStringAsFixed(0)} ${price.currencyCode}'
              : '—',
          style: const TextStyle(
              color: IjwiColors.greenDark,
              fontWeight: FontWeight.w900,
              fontSize: 14),
        ),
        Text('per ${price.unitCode}${price.region != null ? ' · ${price.region}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: IjwiColors.muted)),
      ]),
    );
  }
}

/// Buyer opportunity card → Respond opens a structured offer against the
/// buyer request (seller → buyer), exactly as the backend expects.
class _OpportunityCard extends ConsumerWidget {
  const _OpportunityCard({required this.request, required this.repo});

  final BuyerRequest request;
  final MarketplaceRepository repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(IjwiRadius.sm)),
            child: const Center(
                child: Icon(Icons.local_fire_department,
                    color: IjwiColors.amber, size: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(request.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                '${request.quantityValue.toStringAsFixed(0)} ${request.unitCode} needed'
                '${request.destinationLabel.isNotEmpty ? ' · ${request.destinationLabel}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: IjwiColors.muted),
              ),
              if (request.requiredByDate != null)
                Text('Required by ${request.requiredByDate}',
                    style: const TextStyle(fontSize: 11, color: IjwiColors.amber)),
            ]),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
                minimumSize: const Size(88, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
            onPressed: () => _respond(context, ref),
            child: const Text('Respond', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  Future<void> _respond(BuildContext context, WidgetRef ref) async {
    final qtyCtl = TextEditingController(
        text: request.quantityValue.toStringAsFixed(0));
    final priceCtl = TextEditingController();
    final budget = request.budgetMaxMinor ?? request.budgetMinMinor;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Respond to buyer request',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(request.title,
              style: const TextStyle(color: IjwiColors.muted, fontSize: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: qtyCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Quantity (${request.unitCode})'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: priceCtl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Your price / ${request.unitCode} (${request.currencyCode} minor)',
              helperText: budget != null
                  ? 'Buyer budget up to ${(budget / 100).toStringAsFixed(0)} ${request.currencyCode}'
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send offer'),
          ),
        ]),
      ),
    );
    if (sent != true) return;
    try {
      await repo.createOffer({
        'buyer_request_id': request.id,
        'quantity_value': double.tryParse(qtyCtl.text.trim()) ?? 0,
        'price_minor': int.tryParse(priceCtl.text.trim()) ?? 0,
        'unit_code': request.unitCode,
        'currency_code': request.currencyCode,
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Offer sent to the buyer'),
          backgroundColor: IjwiColors.green));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }
}