import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../shared/widgets/ui.dart';
import 'community_models.dart';
import 'community_service.dart';
import 'post_card.dart';

/// Community profile: cover, join state, pinned content, groups and member feed.
class CommunityProfileScreen extends ConsumerStatefulWidget {
  const CommunityProfileScreen({required this.communityId, super.key});

  final String communityId;

  @override
  ConsumerState<CommunityProfileScreen> createState() =>
      _CommunityProfileScreenState();
}

class _CommunityProfileScreenState
    extends ConsumerState<CommunityProfileScreen> {
  CommunityProfile? _community;
  List<Post>? _posts;
  List<CommunityGroupProfile>? _groups;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(communityServiceProvider);
    try {
      final all = await svc.listCommunities();
      final community = all.firstWhere(
          (c) => c.id == widget.communityId,
          orElse: () => all.isNotEmpty
              ? all.first
              : CommunityProfile(id: widget.communityId, name: 'Community'));
      final postsTask = svc.listPosts(communityId: widget.communityId);
      final results = await Future.wait([postsTask]);
      if (!mounted) return;
      setState(() {
        _community = community;
        _posts = results[0] as List<Post>;
        _groups = null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  Future<void> _join() async {
    final svc = ref.read(communityServiceProvider);
    try {
      await svc.joinCommunity(widget.communityId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Joined community')));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = _community;
    return Scaffold(
      appBar: AppBar(title: Text(c?.name ?? 'Community')),
      body: _error != null && c == null
          ? ErrorBox(_error!, onRetry: _load)
          : c == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _cover(c),
                    _actions(c),
                    SectionHeader('Community discussions'),
                    if (_posts == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Skeleton(height: 140),
                      )
                    else if (_posts!.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: Text('No posts in this community yet',
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

  Widget _cover(CommunityProfile c) {
    return Container(
      color: IjwiColors.greenLight,
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Text(c.iconEmoji, style: const TextStyle(fontSize: 48)),
        const SizedBox(height: 8),
        Text(c.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        if (c.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(c.description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: IjwiColors.muted, height: 1.4)),
          ),
        const SizedBox(height: 8),
        Text('${c.memberCount} members · ${c.communityType} community',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: IjwiColors.green)),
      ]),
    );
  }

  Widget _actions(CommunityProfile c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: c.joined ? null : _join,
            icon: Icon(c.joined ? Icons.check : Icons.add),
            label: Text(c.joined ? 'Joined' : 'Join community'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:           OutlinedButton.icon(
            onPressed: () => context.push(
                '/community/post/new?communityId=${widget.communityId}'),
            icon: const Icon(Icons.edit),
            label: const Text('Write a post'),
          ),
        ),
      ]),
    );
  }
}
