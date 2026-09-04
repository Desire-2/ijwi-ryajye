import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import 'marketplace_models.dart';
import 'marketplace_repository.dart';

/// Five-star row (filled/half/empty based on [rating]).
class StarRow extends StatelessWidget {
  const StarRow(this.rating, {super.key, this.size = 14});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final icon = rating >= i + 0.75
            ? Icons.star_rounded
            : rating >= i + 0.25
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded;
        return Icon(icon, size: size, color: IjwiColors.amber);
      }),
    );
  }
}

/// One review received by a user (profile / listing detail).
class ReviewCard extends StatelessWidget {
  const ReviewCard(this.review, {super.key});

  final UserReview review;

  @override
  Widget build(BuildContext context) {
    final what =
        review.productName ?? review.listingTitle ?? 'purchase';
    final qty = review.orderQuantity != null
        ? '${formatQuantity(review.orderQuantity!, review.orderUnit)} of '
        : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            StarRow(review.overallRating.toDouble()),
            const Spacer(),
            if (review.verifiedTransaction)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: IjwiColors.greenLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.verified, size: 11, color: IjwiColors.greenDark),
                  SizedBox(width: 2),
                  Text('Verified purchase',
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: IjwiColors.greenDark)),
                ]),
              ),
          ]),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(review.comment, style: const TextStyle(height: 1.35)),
          ],
          const SizedBox(height: 6),
          Text(
            '$qty$what · ${review.reviewerName}'
            '${_ago()}',
            style: const TextStyle(
                fontSize: 11.5, color: IjwiColors.muted),
          ),
        ]),
      ),
    );
  }

  String _ago() {
    final ago = timeAgoIso(review.createdAt);
    return ago.isEmpty ? '' : ' · $ago';
  }
}

/// Compact aggregate row: big average, star row, review count.
class ReputationHeader extends StatelessWidget {
  const ReputationHeader(this.summary, {super.key, this.onViewAll});

  final ReputationSummary summary;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final hasReviews = summary.ratingCount > 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Text(
            hasReviews ? summary.ratingAvg.toStringAsFixed(1) : '—',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            StarRow(hasReviews ? summary.ratingAvg : 0),
            const SizedBox(height: 2),
            Text(hasReviews
                ? '${summary.ratingCount} '
                    '${summary.ratingCount == 1 ? 'review' : 'reviews'}'
                : 'No reviews yet',
                style: const TextStyle(
                    fontSize: 11.5, color: IjwiColors.muted)),
          ]),
          const Spacer(),
          if (summary.completedActivity > 0)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${summary.completedActivity}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900)),
              const Text('completed',
                  style: TextStyle(fontSize: 10.5, color: IjwiColors.muted)),
            ]),
          if (onViewAll != null && hasReviews)
            TextButton(onPressed: onViewAll, child: const Text('See all')),
        ]),
      ),
    );
  }
}

/// Self-loading block that shows a seller's reviews on a listing detail page.
/// Hidden entirely when the seller has no reviews yet.
class SellerReviewsPreview extends ConsumerStatefulWidget {
  const SellerReviewsPreview({required this.sellerId, super.key});

  final String sellerId;

  @override
  ConsumerState<SellerReviewsPreview> createState() =>
      _SellerReviewsPreviewState();
}

class _SellerReviewsPreviewState extends ConsumerState<SellerReviewsPreview> {
  ReputationSummary? _summary;
  List<UserReview> _reviews = const [];
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      final summary = await repo.reputationSummary(widget.sellerId);
      final reviews = await repo.userReviews(widget.sellerId);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _reviews = reviews.take(2).toList();
        _done = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _done = true); // hide quietly on failure
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (!_done || summary == null || summary.ratingCount == 0) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16, top: 6, bottom: 2),
          child: Text('Reviews',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ReputationHeader(summary,
              onViewAll: () =>
                  context.push('/community/farmer/${widget.sellerId}')),
        ),
        const SizedBox(height: 8),
        for (final r in _reviews)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ReviewCard(r),
          ),
      ],
    );
  }

}
