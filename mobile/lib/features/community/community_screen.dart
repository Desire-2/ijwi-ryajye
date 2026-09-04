import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../shared/widgets/ui.dart';
import 'community_models.dart';
import 'community_service.dart';
import 'post_card.dart';

/// The social heart of Ijwi Ryajye.
///
/// Provides the entry points to the whole communication ecosystem:
/// statuses, feed, discover, groups, channels, opportunities.
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  List<Post>? _feed;
  List<StatusData>? _statuses;
  List<CommunityProfile>? _recommended;
  List<CommunityGroupProfile>? _groups;
  List<ChannelProfile>? _channels;
  List<Opportunity>? _opportunities;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(showRefresh: false);
  }

  Future<void> _load({bool showRefresh = true}) async {
    final svc = ref.read(communityServiceProvider);
    try {
      final results = await Future.wait([
        svc.listPosts(forYou: true, perPage: 20),
        svc.listStatuses(),
        svc.recommendedCommunities(),
        svc.listGroups(),
        svc.listChannels(),
      ]);
      if (!mounted) return;
      setState(() {
        _feed = results[0] as List<Post>;
        _statuses = results[1] as List<StatusData>;
        _recommended = results[2] as List<CommunityProfile>;
        _groups = results[3] as List<CommunityGroupProfile>;
        _channels = results[4] as List<ChannelProfile>;
        _error = null;
      });
      _loadOpportunities();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  Future<void> _loadOpportunities() async {
    try {
      final opps = await ref
          .read(communityServiceProvider)
          .listBuyerRequests();
      if (!mounted) return;
      setState(() => _opportunities = opps);
    } catch (_) {}
  }

  void _updatePost(Post updated) {
    setState(() {
      _feed = _feed?.map((p) => p.id == updated.id ? updated : p).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('community')),
        actions: [
          IconButton(
              tooltip: 'Search',
              onPressed: () => context.push('/community/search'),
              icon: const Icon(Icons.search)),
          IconButton(
              tooltip: 'Create post',
              onPressed: () => context.push('/community/post/new'),
              icon: const Icon(Icons.add_circle_outline)),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [Tab(text: 'Feed'), Tab(text: 'Discover')],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _feedTab(),
        _discoverTab(),
      ]),
    );
  }

  Widget _feedTab() {
    final statuses = _statuses;
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: _feed == null && _error == null
          ? ListView(
              padding: const EdgeInsets.all(12),
              children: const [
                Skeleton(height: 90),
                Skeleton(height: 140),
                Skeleton(height: 90),
                Skeleton(height: 140),
                Skeleton(height: 90),
              ],
            )
          : _error != null && _feed == null
              ? ListView(children: [
                  ErrorBox(_error!, onRetry: _load),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount:
                      (_feed?.length ?? 0) + (statuses != null ? 2 : 0) + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return _composerBar(context);
                    }
                    if (statuses != null && i == 1) {
                      return _statusRow(context, statuses);
                    }
                    final idx = i - (statuses != null ? 2 : 1);
                    final posts = _feed!;
                    if (idx >= posts.length) {
                      return const SizedBox.shrink();
                    }
                    final p = posts[idx];
                    return PostCard(
                        post: p, onChanged: _updatePost);
                  },
                ),
    );
  }

  Widget _composerBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(IjwiRadius.md),
          onTap: () => context.push('/community/post/new'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Icon(Icons.edit_outlined, color: IjwiColors.green),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "What's happening on your farm?",
                  style: TextStyle(color: IjwiColors.muted),
                ),
              ),
              const Icon(Icons.photo_outlined, color: IjwiColors.muted),
              const SizedBox(width: 12),
              const Icon(Icons.mic_none_outlined, color: IjwiColors.muted),
              const SizedBox(width: 12),
              const Icon(Icons.help_outline, color: IjwiColors.blue),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _statusRow(BuildContext context, List<StatusData> statuses) {
    final visible =
        statuses.where((s) => !s.viewed).take(12).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final s = visible[i];
          return GestureDetector(
            onTap: () => context.push('/community/statuses'),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: IjwiColors.green, width: 2.5),
                ),
                child: IjwiAvatar(s.author.displayName, size: 48),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 60,
                child: Text(
                  s.author.displayName.split(' ').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _discoverTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _heroCard(context),
          if (_opportunities != null && _opportunities!.isNotEmpty) ...[
            SectionHeader('Opportunities',
                actionLabel: 'See all',
                onAction: () => context.push('/community/opportunities')),
            _opportunityStrip(context, _opportunities!),
          ],
          SectionHeader('Recommended communities',
              actionLabel: 'Discover',
              onAction: () => context.push('/community/discover')),
          _recommendedRow(context),
          SectionHeader('Your groups',
              actionLabel: 'Create',
              onAction: _createGroup),
          if (_groups == null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Skeleton(height: 72),
            )
          else if (_groups!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: EmptyState(
                icon: Icons.groups_2,
                title: 'Join a group',
                message:
                    'Groups connect farmers by crop, location and purpose.',
                actionLabel: 'Create group',
                onAction: _createGroup,
              ),
            )
          else
            for (final g in _groups!.take(6)) _groupTile(context, g),
          SectionHeader('Channels',
              actionLabel: 'Explore',
              onAction: () => context.push('/community/discover')),
          if (_channels == null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Skeleton(height: 72),
            )
          else
            for (final c in _channels!.take(4)) _channelTile(context, c),
        ],
      ),
    );
  }

  Widget _heroCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B7A43), Color(0xFF0F5A2F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(IjwiRadius.lg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Your Agriculture Network',
          style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Learn. Connect. Trade. Grow.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: IjwiColors.green,
            minimumSize: const Size(0, 40),
          ),
          onPressed: () => context.push('/community/discover'),
          child: const Text('Discover communities'),
        ),
      ]),
    );
  }

  Widget _opportunityStrip(BuildContext context, List<Opportunity> opps) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: opps.take(6).length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final o = opps[i];
          return Container(
            width: 220,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: IjwiColors.red.withOpacity(0.08),
              border: Border.all(color: IjwiColors.red.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(IjwiRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.local_fire_department,
                      size: 14, color: IjwiColors.red),
                  SizedBox(width: 4),
                  Text('BUYER REQUEST',
                      style: TextStyle(
                          color: IjwiColors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 4),
                Text(o.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                    '${o.product ?? ''}${o.quantityValue != null ? ' · ${_num(o.quantityValue!)} ${o.unitCode}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: IjwiColors.muted)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _recommendedRow(BuildContext context) {
    final recs = _recommended;
    if (recs == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Skeleton(height: 90),
      );
    }
    if (recs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('No community suggestions yet',
            style: TextStyle(color: IjwiColors.muted)),
      );
    }
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: recs.take(8).length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final c = recs[i];
          return GestureDetector(
            onTap: () => context.push('/community/${c.id}'),
            child: Container(
              width: 140,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: IjwiColors.greenLight,
                borderRadius: BorderRadius.circular(IjwiRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(c.iconEmoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 4),
                  Text(c.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  Text('${c.memberCount} members',
                      style: const TextStyle(
                          fontSize: 11, color: IjwiColors.muted)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _groupTile(BuildContext context, CommunityGroupProfile g) {
    return Card(
      child: ListTile(
        leading: IjwiAvatar(g.name, isGroup: true),
        title: Row(children: [
          Expanded(
              child: Text(g.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          if (g.isPrivate)
            Icon(Icons.lock_outline, size: 15, color: Colors.grey.shade500),
        ]),
        subtitle: Text('${g.memberCount} members'
            '${g.isMember ? " · you: ${g.myRole!.toLowerCase().replaceAll("_", " ")}" : ""}'),
        trailing: g.isMember
            ? IconButton(
                tooltip: 'Open group',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => context.push('/community/group/${g.id}'))
            : OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(70, 34)),
                onPressed: () async {
                  try {
                    await ref
                        .read(communityServiceProvider)
                        .joinGroup(g.id);
                    await _load();
                  } catch (_) {}
                },
                child: const Text('Join')),
        onTap: () => context.push('/community/group/${g.id}'),
      ),
    );
  }

  Widget _channelTile(BuildContext context, ChannelProfile ch) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
            backgroundColor: Color(0xFFEDE9FE),
            child: Icon(Icons.campaign_outlined, color: IjwiColors.blue)),
        title: Text(ch.name,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${ch.subscriberCount} followers'),
        trailing: ch.followed
            ? const Icon(Icons.check, color: IjwiColors.green)
            : IconButton(
                icon: const Icon(Icons.add_alert_outlined),
                tooltip: 'Follow',
                onPressed: () async {
                  try {
                    await ref
                        .read(communityServiceProvider)
                        .followChannel(ch.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Following')));
                  } catch (_) {}
                }),
        onTap: () => context.push('/community/channel/${ch.id}'),
      ),
    );
  }

  Future<void> _createGroup() async {
    final nameCtl = TextEditingController();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Create a group',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
            controller: nameCtl,
            textCapitalization: TextCapitalization.words,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Group name'),
          ),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create')),
        ]),
      ),
    );
    if (created != true || nameCtl.text.trim().length < 2) return;
    try {
      await ref.read(communityServiceProvider).createGroup(
          {'name': nameCtl.text.trim(), 'require_approval': false});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
