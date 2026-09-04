import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../features/market/marketplace_models.dart';
import '../../features/market/marketplace_repository.dart';
import '../../features/market/review_widgets.dart';
import '../../shared/widgets/ui.dart';
import 'community_models.dart';
import 'community_service.dart';
import 'post_card.dart';

/// Public farmer profile opened from community. Shows identity, verification,
/// crops, marketplace presence and their posts. Follow / message wired.
class FarmerProfileScreen extends ConsumerStatefulWidget {
  const FarmerProfileScreen({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<FarmerProfileScreen> createState() =>
      _FarmerProfileScreenState();
}

class _FarmerProfileScreenState extends ConsumerState<FarmerProfileScreen> {
  FarmerIdentity? _identity;
  List<Post>? _posts;
  ReputationSummary? _reputation;
  List<UserReview> _reviews = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    final svc = ref.read(communityServiceProvider);
    try {
      final res = await api.getJson('/users/${widget.userId}');
      final identity = FarmerIdentity.fromJson(
          (res['user'] as Map<String, dynamic>?) ??
              (res['farmer'] as Map<String, dynamic>?) ??
              res);
      final posts = await svc.listPosts(authorId: widget.userId);
      if (!mounted) return;
      setState(() {
        _identity = identity;
        _posts = posts;
        _error = null;
      });
      unawaited(_loadReviews());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  /// Best-effort: reviews/reputation never block the profile itself.
  Future<void> _loadReviews() async {
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      final rep = await repo.reputationSummary(widget.userId);
      final reviews = await repo.userReviews(widget.userId);
      if (!mounted) return;
      setState(() {
        _reputation = rep;
        _reviews = reviews.take(10).toList();
      });
    } catch (_) {
      // profile still renders without the reviews block
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _identity;
    return Scaffold(
      appBar: AppBar(title: const Text('Farmer')),
      body: _error != null && u == null
          ? ErrorBox(_error!, onRetry: _load)
          : u == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _profileCard(context, u),
                    _actions(context, u),
                    _reviewsSection(),
                    const SectionHeader('Posts'),
                    if (_posts == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Skeleton(height: 120),
                      )
                    else if (_posts!.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: Text('No posts yet',
                                style:
                                    TextStyle(color: IjwiColors.muted))),
                      )
                    else
                      for (final p in _posts!)
                        PostCard(post: p, onChanged: (_) {}),
                  ],
                ),
    );
  }

  /// Reviews received from completed transactions (real reputation data).
  Widget _reviewsSection() {
    final rep = _reputation;
    if (rep == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Reviews'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ReputationHeader(rep),
        ),
        const SizedBox(height: 10),
        for (final r in _reviews)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ReviewCard(r),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _profileCard(BuildContext context, FarmerIdentity u) {
    return Container(
      color: IjwiColors.greenLight,
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        IjwiAvatar(u.displayName, size: 72),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(u.displayName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          if (u.verified)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child:
                  Icon(Icons.verified, size: 20, color: IjwiColors.blue),
            ),
        ]),
        if (u.region != null)
          Text(u.region!,
              style: const TextStyle(color: IjwiColors.muted)),
        if (u.mainCrops.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 6, children: [
              for (final c in u.mainCrops)
                Chip(
                  label: Text(c),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.white,
                  side: BorderSide.none,
                ),
            ]),
          ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (u.yearsExperience != null)
            _stat('${u.yearsExperience}y', 'experience'),
          if (u.ratingAvg != null) ...[
            const SizedBox(width: 16),
            _stat('${u.ratingAvg}', '★ rating'),
          ],
          if (u.completedTransactions != null) ...[
            const SizedBox(width: 16),
            _stat('${u.completedTransactions}', 'transactions'),
          ],
        ]),
      ]),
    );
  }

  Widget _stat(String value, String label) {
    return Column(children: [
      Text(value,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      Text(label,
          style: const TextStyle(color: IjwiColors.muted, fontSize: 11)),
    ]);
  }

  Widget _actions(BuildContext context, FarmerIdentity u) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              try {
                await ref
                    .read(communityServiceProvider)
                    .followUser(u.id);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Following farmer')));
              } catch (_) {}
            },
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Follow'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: () async {
              final api = ref.read(apiClientProvider);
              try {
                final res = await api.postJson('/conversations',
                    {'with_user_id': u.id, 'context': 'DIRECT'});
                final convId = (res['conversation'] as Map<String, dynamic>?)?['id'] ??
                    res['id'];
                if (convId != null && mounted) {
                  Navigator.of(context).pop();
                  context.push('/chat/$convId');
                }
              } catch (_) {}
            },
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Message'),
          ),
        ),
      ]),
    );
  }
}
