import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/design_system.dart';
import '../../shared/widgets/ui.dart';
import 'community_models.dart';
import 'community_service.dart';
import 'post_card.dart';

/// Debounced community search across posts, people, groups and channels.
class CommunitySearchScreen extends ConsumerStatefulWidget {
  const CommunitySearchScreen({super.key});

  @override
  ConsumerState<CommunitySearchScreen> createState() =>
      _CommunitySearchScreenState();
}

class _CommunitySearchScreenState
    extends ConsumerState<CommunitySearchScreen> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  List<Post> _posts = const [];
  List<FarmerIdentity> _people = const [];
  List<CommunityGroupProfile> _groups = const [];
  List<ChannelProfile> _channels = const [];

  static const recent = ['Coffee', 'Potatoes', 'Organic', 'Livestock'];

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (value.trim().length >= 2) {
        _search(value.trim());
      } else {
        setState(() {
          _posts = const [];
          _people = const [];
          _groups = const [];
          _channels = const [];
        });
      }
    });
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    final svc = ref.read(communityServiceProvider);
    try {
      final res = await svc.search(q);
      final postsRaw = res['posts'] as List? ?? const [];
      final peopleRaw = res['users'] as List? ?? res['farmers'] as List? ?? const [];
      final groupsRaw = res['groups'] as List? ?? const [];
      final channelsRaw = res['channels'] as List? ?? const [];
      if (!mounted) return;
      setState(() {
        _posts = postsRaw
            .map((j) => Post.fromJson(j as Map<String, dynamic>))
            .toList();
        _people = peopleRaw
            .map((j) => FarmerIdentity.fromJson(j as Map<String, dynamic>))
            .toList();
        _groups = groupsRaw
            .map((j) => CommunityGroupProfile.fromJson(j as Map<String, dynamic>))
            .toList();
        _channels = channelsRaw
            .map((j) => ChannelProfile.fromJson(j as Map<String, dynamic>))
            .toList();
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _ctl.text.trim();
    final hasResults = _posts.isNotEmpty ||
        _people.isNotEmpty ||
        _groups.isNotEmpty ||
        _channels.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _ctl,
            autofocus: true,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'Search agriculture, farmers, topics…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
          ),
        ),
        if (query.isEmpty) _recentSearches() else _results(hasResults),
      ]),
    );
  }

  Widget _recentSearches() {
    return Expanded(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Recent searches',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          for (final r in recent)
            ListTile(
              leading: const Icon(Icons.history, color: IjwiColors.muted),
              title: Text(r),
              onTap: () {
                _ctl.text = r;
                _search(r);
              },
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Try',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          for (final t in ['Coffee', 'Potatoes', 'Maize', 'Avocado'])
            ActionChip(
              label: Text('#$t'),
              onPressed: () {
                _ctl.text = t;
                _search(t);
              },
            ),
        ],
      ),
    );
  }

  Widget _results(bool hasResults) {
    return Expanded(
      child: !hasResults
          ? const Center(
              child: Text('No results found',
                  style: TextStyle(color: IjwiColors.muted)))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (_people.isNotEmpty) ...[
                  _sectionHeader('People'),
                  for (final p in _people.take(5))
                    ListTile(
                      leading: IjwiAvatar(p.displayName),
                      title: Text(p.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          [p.region ?? '', p.mainCrops.join(', ')]
                              .where((e) => e.isNotEmpty)
                              .join(' · ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/community/farmer/${p.id}'),
                    ),
                ],
                if (_groups.isNotEmpty) ...[
                  _sectionHeader('Groups'),
                  for (final g in _groups.take(5))
                    ListTile(
                      leading: IjwiAvatar(g.name, isGroup: true),
                      title: Text(g.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${g.memberCount} members'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/community/group/${g.id}'),
                    ),
                ],
                if (_channels.isNotEmpty) ...[
                  _sectionHeader('Channels'),
                  for (final ch in _channels.take(5))
                    ListTile(
                      leading: const Icon(Icons.campaign_outlined,
                          color: IjwiColors.blue),
                      title: Text(ch.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${ch.subscriberCount} followers'),
                      onTap: () => context.push('/community/channel/${ch.id}'),
                    ),
                ],
                if (_posts.isNotEmpty) ...[
                  _sectionHeader('Posts'),
                  for (final p in _posts)
                    PostCard(post: p, onChanged: (_) {}),
                ],
              ],
            ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
    );
  }
}
