import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/market/market_realtime.dart';
import '../../features/market/marketplace_models.dart';
import '../../features/market/marketplace_repository.dart';
import '../../features/market/marketplace_widgets.dart';
import '../../features/market/review_widgets.dart';
import '../../features/sell/listing_wizard_engine.dart';

import '../../shared/widgets/ui.dart';

/// Full listing detail: media, price/availability, trust, quality, delivery
/// options, auction live state, seller bridge and a sticky action bar.
/// Only actions supported by the listing type / backend state are shown.
class ListingDetailScreen extends ConsumerStatefulWidget {
  const ListingDetailScreen({required this.listingId, super.key});

  final String listingId;

  @override
  ConsumerState<ListingDetailScreen> createState() =>
      _ListingDetailScreenState();
}

class _ListingDetailScreenState extends ConsumerState<ListingDetailScreen>
    with MarketRealtime {
  Listing? _listing;
  List<Bid> _bids = const [];
  String? _error;
  bool _busy = false;
  bool? _favorited;

  Future<void> _load() async {
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      final (l, _) = await repo.listing(widget.listingId);
      if (mounted) {
        setState(() {
          _listing = l;
          _error = null;
        });
      }
      if (l.isAuction) {
        final bids = await repo.bids(widget.listingId);
        if (mounted) setState(() => _bids = bids);
      }
      _loadFavorite();
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  Future<void> _loadFavorite() async {
    try {
      final favs = await ref.read(marketplaceRepositoryProvider).favorites();
      if (mounted) {
        setState(
            () => _favorited = favs.any((f) => f.id == widget.listingId));
      }
    } catch (_) {
      if (mounted) setState(() => _favorited = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    // Auction listings update live when anyone bids; a full reload only runs
    // when this auction's winning bid is accepted (state change).
    attachMarketRealtime({
      'bid.placed': (data) => _onBidPlaced(data),
      'bid.accepted': (data) {
        if (data['listing_id'] == widget.listingId) _load();
      },
    }, debounceMs: 250);
  }

  @override
  void dispose() {
    detachMarketRealtime();
    super.dispose();
  }

  /// Live bid update: refresh the bid list and the auction end time without
  /// re-fetching the listing (which would inflate the view counter).
  Future<void> _onBidPlaced(Map<String, dynamic> data) async {
    if (data['listing_id'] != widget.listingId) return;
    final l = _listing;
    if (l == null || !l.isAuction) return;
    final endAt = data['auction_end_at'] as String?;
    if (endAt != null) {
      setState(() => l.auctionEndAt = endAt);
    }
    try {
      final bids = await ref.read(marketplaceRepositoryProvider).bids(widget.listingId);
      if (mounted && _listing?.id == widget.listingId) {
        setState(() => _bids = bids);
      }
    } catch (_) {
      // best effort: pull-to-refresh still available
    }
  }

  Future<void> _toggleFavorite() async {
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      if (_favorited == true) {
        await repo.removeFavorite(widget.listingId);
        setState(() => _favorited = false);
      } else {
        await repo.addFavorite(widget.listingId);
        setState(() => _favorited = true);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_favorited == true
              ? 'Saved to favorites'
              : 'Removed from favorites')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  Future<void> _share() async {
    final l = _listing!;
    final price = l.priceMinor == null
        ? 'Price negotiable'
        : '${formatMoney(l.priceMinor!, l.currencyCode)} / ${l.unitCode}';
    await Share.share(
      '${l.productEmoji} ${l.productName} — $price — '
      '${formatQuantity(l.availableQuantity, l.unitCode)} available'
      '${l.locationLabel.isNotEmpty ? ' in ${l.locationLabel}' : ''}\n'
      'Find it on Ijwi Ryajye.',
      subject: l.productName,
    );
  }

  Future<void> _messageSeller() async {
    final l = _listing!;
    final sellerId = l.seller?.id;
    if (sellerId == null) return;
    try {
      setState(() => _busy = true);
      final convId = await ref
          .read(marketplaceRepositoryProvider)
          .startConversation(
              withUserId: sellerId, context: 'listing', listingId: l.id);
      if (!mounted) return;
      context.push('/chat/$convId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- trade actions ----

  Future<void> _buyNow({required double quantity}) async {
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      setState(() => _busy = true);
      final order = await repo.createOrderDraft(
          listingId: widget.listingId, quantity: quantity);
      if (!mounted) return;
      context.push('/orders/${order.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _askQuantityAndPrice({required bool auction}) async {
    final l = _listing!;
    final qtyCtl = TextEditingController(text: '10');
    final priceCtl = TextEditingController(
        text: l.priceMinor == null ? '' : '${l.priceMinor}');
    final sent = await showModalBottomSheet<bool>(
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
            Text(auction ? 'Place your bid' : 'Make an offer',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(l.productName,
                style: const TextStyle(color: IjwiColors.muted, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: qtyCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Quantity (${l.unitCode})'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: auction
                    ? 'Your bid (${l.currencyCode} minor)'
                    : 'Your price / ${l.unitCode} (${l.currencyCode} minor)',
                helperText: l.negotiable
                    ? 'Price is negotiable — offer what works for you'
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(auction ? 'Place bid' : 'Send offer'),
            ),
          ],
        ),
      ),
    );
    if (sent != true) return;
    final qty = double.tryParse(qtyCtl.text.trim()) ?? 0;
    final price = int.tryParse(priceCtl.text.trim()) ?? 0;
    if (qty <= 0 || price <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a valid quantity and price')));
      }
      return;
    }
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      setState(() => _busy = true);
      if (auction) {
        await repo.placeBid(
            listingId: widget.listingId,
            amountMinor: price,
            quantityValue: qty);
      } else {
        await repo.createOffer({
          'listing_id': widget.listingId,
          'quantity_value': qty,
          'price_minor': price,
          'unit_code': l.unitCode,
          'currency_code': l.currencyCode,
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(auction ? 'Bid placed' : 'Offer sent'),
          backgroundColor: IjwiColors.green));
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

  Future<void> _acceptWinningBid() async {
    try {
      setState(() => _busy = true);
      final order = await ref
          .read(marketplaceRepositoryProvider)
          .acceptWinningBid(widget.listingId);
      if (!mounted) return;
      context.push('/orders/${order.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    final l = _listing;
    final me = ref.watch(authProvider).valueOrNull;
    final isMyListing = l != null && me != null && me.id == l.seller?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(l?.productName ?? tr('tab_market')),
        actions: [
          IconButton(
            tooltip: _favorited == true ? 'Saved' : 'Save',
            icon: Icon(
                _favorited == true ? Icons.favorite : Icons.favorite_border,
                color: _favorited == true ? IjwiColors.red : Colors.white),
            onPressed: l == null ? null : _toggleFavorite,
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: l == null ? null : _share,
          ),
        ],
      ),
      body: _error != null && l == null
          ? ListView(children: [ErrorBox(_error!, onRetry: _load)])
          : l == null
              ? ListView(padding: const EdgeInsets.all(14), children: const [
                  Skeleton(height: 200), SizedBox(height: 10),
                  Skeleton(height: 90), SizedBox(height: 10),
                  Skeleton(height: 120),
                ])
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 20),
                    children: [
                      _hero(l),
                      _mainInfo(l),
                      if (l.isAuction) _auctionPanel(l, isMyListing),
                      _detailRows(l),
                      _aboutSection(l),
                      _sellerCard(l),
                      if (l.seller != null)
                        SellerReviewsPreview(sellerId: l.seller!.id),
                      if (l.isAuction && _bids.isNotEmpty) _bidsSection(l),
                      if (l.state != 'ACTIVE')
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'This listing is ${l.availabilityLabel.toLowerCase()}.',
                            style: const TextStyle(
                                color: IjwiColors.muted,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
      bottomNavigationBar: l == null ? null : _stickyBar(l, isMyListing),
    );
  }

  Widget _hero(Listing l) {
    return Container(
      height: 190,
      width: double.infinity,
      color: IjwiColors.greenLight.withOpacity(0.55),
      child: Stack(children: [
        Center(
            child: Text(l.productEmoji, style: const TextStyle(fontSize: 84))),
        Positioned(top: 12, left: 12, child: AvailabilityBadge(l)),
        Positioned(top: 12, right: 12, child: ListingTypeBadge(l)),
        if (l.promotedUntil != null)
          Positioned(
              bottom: 12,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: IjwiColors.amber.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('Sponsored',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              )),
      ]),
    );
  }

  Widget _mainInfo(Listing l) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (l.priceMinor != null)
              Text(
                '${formatMoney(l.priceMinor!, l.currencyCode)} / ${l.unitCode}',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: l.isAuction ? IjwiColors.amber : IjwiColors.greenDark),
              )
            else
              const Text('Price negotiable',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: IjwiColors.muted)),
            const Spacer(),
            QualityBadge(l.qualityGrade),
          ]),
          const SizedBox(height: 8),
          Text(
            '${formatQuantity(l.quantityValue, l.unitCode)} total · '
            '${formatQuantity(l.availableQuantity, l.unitCode)} available'
            '${l.soldQuantity > 0 ? ' · ${formatQuantity(l.soldQuantity, l.unitCode)} sold' : ''}',
            style: const TextStyle(
                fontSize: 13, color: IjwiColors.muted, fontWeight: FontWeight.w600),
          ),
          if (l.variety.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Variety: ${l.variety}',
                style:
                    const TextStyle(fontSize: 13, color: IjwiColors.muted)),
          ],
        ]),
      ),
    );
  }

  Widget _auctionPanel(Listing l, bool isMyListing) {
    final winning = _bids.where((b) => b.isWinning).firstOrNull;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: IjwiColors.amber.withOpacity(0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.gavel, color: IjwiColors.amber, size: 20),
            const SizedBox(width: 8),
            const Text('Auction',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const Spacer(),
            AuctionCountdown(endAt: l.auctionEndAt),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Current highest bid',
                    style: TextStyle(fontSize: 12, color: IjwiColors.muted)),
                Text(
                  winning != null
                      ? formatMoney(winning.amountMinor, winning.currencyCode)
                      : l.priceMinor != null
                          ? '${formatMoney(l.priceMinor!, l.currencyCode)} (start)'
                          : 'No bids yet',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: IjwiColors.amber),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${_bids.length} bids',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
              if (l.reservePriceMinor != null)
                Text(
                  'Reserve ${(l.reservePriceMinor! / 100).toStringAsFixed(0)} ${l.currencyCode}',
                  style: const TextStyle(
                      fontSize: 11.5, color: IjwiColors.muted),
                ),
            ]),
          ]),
          if (isMyListing && winning != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _acceptWinningBid,
              icon: const Icon(Icons.check),
              label: const Text('Accept winning bid'),
            ),
          ],
        ]),
      ),
    );
  }

  /// Description + the listing's flexible per-kind attributes (breed, weight,
  /// condition, route...), labelled from the same engine the wizard uses.
  Widget _aboutSection(Listing l) {
    final attrs = l.attributes.entries
        .where((e) => e.value != null && e.value.toString().trim().isNotEmpty)
        .toList();
    final hasDescription = l.description.trim().isNotEmpty;
    final hasVariety = l.variety.trim().isNotEmpty && !attrs.any((e) => e.key == 'variety');
    if (!hasDescription && !hasVariety && attrs.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('About this offer',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          if (hasDescription) ...[
            const SizedBox(height: 8),
            Text(l.description,
                style: const TextStyle(fontSize: 13.5, height: 1.45)),
          ],
          if (hasVariety || attrs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (hasVariety)
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: IjwiColors.greenLight,
                  label: Text('Variety: ${l.variety}',
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
              for (final e in attrs)
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: IjwiColors.greenLight,
                  label: Text(
                      '${attributeLabel(e.key)}: '
                      '${formatAttributeValue(e.key, e.value)}',
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _detailRows(Listing l) {
    final rows = <String, String?>{
      if (l.locationLabel.isNotEmpty) 'Location': '📍 ${l.locationLabel}',
      if (l.expectedHarvestDate != null)
        'Expected harvest': l.expectedHarvestDate,
      if (l.productionMethod != null && l.productionMethod!.isNotEmpty)
        'Production': l.productionMethod!.replaceAll('_', ' '),
      if (l.certification.isNotEmpty) 'Certification': l.certification,
      if (l.minimumOrderValue > 0)
        'Minimum order':
            '${l.minimumOrderValue.toStringAsFixed(l.minimumOrderValue == l.minimumOrderValue.roundToDouble() ? 0 : 2)} ${l.unitCode}',
      if (l.maximumOrderValue != null)
        'Maximum order':
            '${l.maximumOrderValue!.toStringAsFixed(l.maximumOrderValue == l.maximumOrderValue!.roundToDouble() ? 0 : 2)} ${l.unitCode}',
      if (l.deliveryOptions.isNotEmpty)
        'Delivery': l.deliveryOptions.map((d) => d.replaceAll('_', ' ')).join(', '),
      if (l.negotiable) 'Negotiable': 'Yes',
    };
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Details',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 8),
          for (final e in rows.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 118,
                  child: Text(e.key,
                      style: const TextStyle(
                          color: IjwiColors.muted, fontSize: 13)),
                ),
                Expanded(
                  child: Text(e.value ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _sellerCard(Listing l) {
    final s = l.seller;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(s?.fullName ?? 'Seller',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            if (s?.isVerified == true) ...[
              const SizedBox(width: 6),
              const VerificationBadge(),
            ],
          ]),
          const SizedBox(height: 6),
          SellerRow(seller: s,
              onTap: s != null
                  ? () => context.push('/community/farmer/${s.id}')
                  : null),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: _busy ? null : _messageSeller,
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Message'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: s != null
                    ? () => context.push('/community/farmer/${s.id}')
                    : null,
                child: const Text('View profile'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _bidsSection(Listing l) {
    final me = ref.watch(authProvider).valueOrNull;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Bids',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 6),
          for (final b in _bids.take(8))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                  b.isWinning ? Icons.emoji_events : Icons.circle_outlined,
                  size: 18,
                  color: b.isWinning ? IjwiColors.amber : IjwiColors.muted),
              title: Text(formatMoney(b.amountMinor, b.currencyCode),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14)),
              subtitle: Text(
                  '${formatQuantity(b.quantityValue, b.unitCode)}'
                  '${b.isWinning ? ' · leading' : ''}'
                  '${b.bidderId == me?.id ? ' · you' : ''}'),
              trailing: timeAgoIso(b.placedAt).isEmpty
                  ? null
                  : Text(timeAgoIso(b.placedAt),
                      style:
                          const TextStyle(fontSize: 11, color: IjwiColors.muted)),
            ),
        ]),
      ),
    );
  }

  Widget _stickyBar(Listing l, bool isMyListing) {
    final lActive = l.state == 'ACTIVE' && !l.isSoldOut;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
              top: BorderSide(color: const Color(0xFFD7E2DA).withOpacity(0.6))),
        ),
        child: Row(children: [
          IconButton(
            tooltip: _favorited == true ? 'Saved' : 'Save',
            icon: Icon(
                _favorited == true ? Icons.favorite : Icons.favorite_border,
                color: _favorited == true ? IjwiColors.red : IjwiColors.green),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            tooltip: 'Message',
            icon: Icon(isMyListing ? Icons.visibility_outlined : Icons.chat_bubble_outline,
                color: IjwiColors.green),
            onPressed: isMyListing ? null : _messageSeller,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: l.isAuction
                ? FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: IjwiColors.amber,
                        foregroundColor: Colors.white),
                    onPressed: !lActive || _busy
                        ? null
                        : () => _askQuantityAndPrice(auction: true),
                    child: Text(_bids.isEmpty ? 'Place bid' : 'Bid higher'),
                  )
                : Row(children: [
                    if (l.isNegotiable) ...[
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: !lActive || _busy
                              ? null
                              : () => _askQuantityAndPrice(auction: false),
                          child: const Text('Make offer'),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      flex: l.isNegotiable ? 1 : 2,
                      child: FilledButton(
                        onPressed: !lActive || _busy
                            ? null
                            : () => _buyNow(quantity: l.minimumOrderValue > 0
                                ? l.minimumOrderValue
                                : 10),
                        child: Text(l.listingType == 'FORWARD_CONTRACT'
                            ? 'Reserve harvest'
                            : 'Buy now'),
                      ),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}