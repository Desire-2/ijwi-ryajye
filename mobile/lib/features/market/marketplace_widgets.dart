import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import 'marketplace_models.dart';

/// Tappable search entry that opens the dedicated search screen.
class MarketplaceSearchBar extends StatelessWidget {
  const MarketplaceSearchBar({this.hint, super.key});

  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(IjwiRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(IjwiRadius.lg),
        onTap: () => context.push('/market/search'),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(IjwiRadius.lg),
            border: Border.all(color: const Color(0xFFD7E2DA)),
          ),
          child: Row(children: [
            const Icon(Icons.search, color: IjwiColors.green),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hint ?? 'Search products, farmers, buyers…',
                style: const TextStyle(
                    color: IjwiColors.muted, fontSize: 14.5),
              ),
            ),
            const Icon(Icons.tune, size: 20, color: IjwiColors.muted),
          ]),
        ),
      ),
    );
  }
}

/// Availability state chip.
class AvailabilityBadge extends StatelessWidget {
  const AvailabilityBadge(this.listing, {super.key});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = listing.state == 'ACTIVE'
        ? listing.isSoldOut
            ? ('Sold out', IjwiColors.red, IjwiColors.red.withOpacity(0.1))
            : (listing.availableQuantity < listing.quantityValue * 0.25
                ? 'Limited'
                : 'Available',
                IjwiColors.green, IjwiColors.greenLight)
        : (listing.availabilityLabel, IjwiColors.muted,
            const Color(0xFFEEE7DA));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

/// ✓ Verified … badge.
class VerificationBadge extends StatelessWidget {
  const VerificationBadge({this.label = 'Verified', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.verified, size: 14, color: IjwiColors.blue),
      const SizedBox(width: 3),
      Text(label,
          style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: IjwiColors.blue)),
    ]);
  }
}

/// Quality grade chip (only when the grade is meaningful).
class QualityBadge extends StatelessWidget {
  const QualityBadge(this.grade, {super.key});

  final String grade;

  @override
  Widget build(BuildContext context) {
    if (grade.isEmpty || grade == 'UNGRADED') return const SizedBox.shrink();
    final color = switch (grade) {
      'PREMIUM' || 'GRADE_A' => IjwiColors.green,
      'GRADE_B' => IjwiColors.amber,
      _ => IjwiColors.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(grade.replaceAll('_', ' '),
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

/// Listing type badge: Auction / Bulk / Negotiable / Contract.
class ListingTypeBadge extends StatelessWidget {
  const ListingTypeBadge(this.listing, {super.key});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (listing.listingType) {
      'AUCTION' => ('Auction', IjwiColors.amber),
      'FORWARD_CONTRACT' => ('Forward harvest', IjwiColors.blue),
      'GROUP_SALE' => ('Group sale', IjwiColors.green),
      'NEGOTIABLE' || 'FIXED_PRICE' when listing.isNegotiable =>
        ('Negotiable', IjwiColors.green),
      _ => ('Fixed price', IjwiColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

/// Premium agricultural product card for grids and horizontal rails.
class ProductCard extends StatelessWidget {
  const ProductCard({required this.listing, this.onTap, super.key});

  final Listing listing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final price = listing.priceMinor;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(IjwiRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(IjwiRadius.md),
        onTap: () => context.push('/listing/${listing.id}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(IjwiRadius.md),
            border: Border.all(color: const Color(0xFFD7E2DA)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // visual header — emoji tile, never a broken network image
            Stack(children: [
              Container(
                height: 96,
                width: double.infinity,
                color: IjwiColors.greenLight.withOpacity(0.55),
                child: Center(
                  child: Text(listing.productEmoji,
                      style: const TextStyle(fontSize: 44)),
                ),
              ),
              Positioned(top: 6, left: 6, child: AvailabilityBadge(listing)),
              if (listing.isAuction) ...[
                Positioned(
                    top: 6, right: 6, child: ListingTypeBadge(listing)),
              ],
            ]),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(listing.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    price == null
                        ? 'Price negotiable'
                        : '${formatMoney(price, listing.currencyCode)} / ${listing.unitCode}',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: price == null ? IjwiColors.muted : IjwiColors.greenDark),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatQuantity(listing.availableQuantity, listing.unitCode),
                    style: const TextStyle(
                        fontSize: 11.5, color: IjwiColors.muted),
                  ),
                  if (listing.locationLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.location_on_outlined,
                          size: 13, color: IjwiColors.muted),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(listing.locationLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: IjwiColors.muted)),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: Text(
                        listing.seller?.fullName.isNotEmpty == true
                            ? listing.seller!.fullName
                            : listing.seller != null
                                ? 'Seller'
                                : '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (listing.seller?.ratingAvg != null &&
                        (listing.seller?.ratingAvg ?? 0) > 0) ...[
                      const Icon(Icons.star, size: 13, color: IjwiColors.amber),
                      const SizedBox(width: 2),
                      Text(listing.seller!.ratingAvg.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w800)),
                    ],
                  ]),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Compact horizontal listing row for list sections.
class ListingRow extends StatelessWidget {
  const ListingRow({required this.listing, super.key});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final price = listing.priceMinor;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
              color: IjwiColors.greenLight.withOpacity(0.6),
              borderRadius: BorderRadius.circular(IjwiRadius.sm)),
          child: Center(
              child: Text(listing.productEmoji,
                  style: const TextStyle(fontSize: 26))),
        ),
        title: Text(listing.productName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
        subtitle: Text(
          [
            price == null
                ? 'Negotiable'
                : '${formatMoney(price, listing.currencyCode)}/${listing.unitCode}',
            formatQuantity(listing.availableQuantity, listing.unitCode),
            listing.locationLabel,
          ].where((s) => s.isNotEmpty).join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (listing.seller?.ratingAvg != null &&
              (listing.seller?.ratingAvg ?? 0) > 0)
            Text(listing.seller!.ratingAvg.toStringAsFixed(1),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: IjwiColors.muted),
        ]),
        onTap: () => context.push('/listing/${listing.id}'),
      ),
    );
  }
}

/// Seller identity row with verification + rating.
class SellerRow extends StatelessWidget {
  const SellerRow({this.seller, this.onTap, super.key});

  final SellerCard? seller;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = seller;
    return InkWell(
      borderRadius: BorderRadius.circular(IjwiRadius.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: IjwiColors.greenLight,
            child: Text(
                s != null && s.fullName.isNotEmpty
                    ? s.fullName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: IjwiColors.greenDark)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(
                    s?.fullName ?? 'Seller',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14.5),
                  ),
                ),
                if (s?.isVerified == true) ...[
                  const SizedBox(width: 5),
                  const VerificationBadge(),
                ],
              ]),
              Text(
                [
                  s?.reputationTier.replaceAll('_', ' ') ?? '',
                  s?.region ?? '',
                ].where((t) => t.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: IjwiColors.muted),
              ),
            ]),
          ),
          if ((s?.ratingAvg ?? 0) > 0) ...[
            const Icon(Icons.star, size: 16, color: IjwiColors.amber),
            const SizedBox(width: 3),
            Text(s!.ratingAvg.toStringAsFixed(1),
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          ],
          const Icon(Icons.chevron_right, color: IjwiColors.muted),
        ]),
      ),
    );
  }
}

/// Countdown to an auction close. The backend remains authoritative — this is
/// display only; bids are validated server-side.
class AuctionCountdown extends StatefulWidget {
  const AuctionCountdown({required this.endAt, super.key});

  final String? endAt;

  @override
  State<AuctionCountdown> createState() => _AuctionCountdownState();
}

class _AuctionCountdownState extends State<AuctionCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final end = DateTime.tryParse(widget.endAt ?? '');
    if (end == null) return const SizedBox.shrink();
    final remaining = end.difference(DateTime.now());
    if (remaining.isNegative) {
      return _pill('Auction closed', IjwiColors.muted);
    }
    String label;
    if (remaining.inDays > 0) {
      label = 'Ends in ${remaining.inDays}d ${remaining.inHours % 24}h';
    } else if (remaining.inHours > 0) {
      label = 'Ends in ${remaining.inHours}h ${remaining.inMinutes % 60}m';
    } else {
      label =
          'Ends in ${remaining.inMinutes}m ${remaining.inSeconds % 60}s';
    }
    return _pill(label, IjwiColors.amber);
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.schedule, size: 14, color: color),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: color)),
        ]),
      );
}

/// Empty state with a labelled action (used across marketplace screens).
class MarketplaceEmpty extends StatelessWidget {
  const MarketplaceEmpty({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
                color: IjwiColors.greenLight, shape: BoxShape.circle),
            child: Icon(icon, size: 38, color: IjwiColors.green),
          ),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: IjwiColors.muted, height: 1.4)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      ),
    );
  }
}