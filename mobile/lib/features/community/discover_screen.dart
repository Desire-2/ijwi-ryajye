import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../shared/widgets/ui.dart';
import 'community_models.dart';
import 'community_service.dart';

/// Community discovery: communities, groups and channels broken out by
/// category so the feed is not one endless scroll.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  List<CommunityProfile>? _communities;
  List<CommunityGroupProfile>? _groups;
  List<ChannelProfile>? _channels;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(communityServiceProvider);
    try {
      final results = await Future.wait([
        svc.listCommunities(),
        svc.listGroups(),
        svc.listChannels(),
      ]);
      if (!mounted) return;
      setState(() {
        _communities = results[0] as List<CommunityProfile>;
        _groups = results[1] as List<CommunityGroupProfile>;
        _channels = results[2] as List<ChannelProfile>;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: _error != null && _communities == null
          ? ErrorBox(_error!, onRetry: _load)
          : Column(children: [
              TabBar(
                controller: _tabs,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                indicatorColor: Colors.white,
                tabs: const [
                  Tab(text: 'Communities'),
                  Tab(text: 'Groups'),
                  Tab(text: 'Channels'),
                ],
              ),
              Expanded(
                child: TabBarView(controller: _tabs, children: [
                  _communityGrid(),
                  _groupList(),
                  _channelList(),
                ]),
              ),
            ]),
    );
  }

  Widget _communityGrid() {
    final communities = _communities;
    if (communities == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.95,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: communities.length,
        itemBuilder: (context, i) {
          final c = communities[i];
          return GestureDetector(
            onTap: () => context.push('/community/${c.id}'),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: IjwiColors.greenLight,
                borderRadius: BorderRadius.circular(IjwiRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.iconEmoji, style: const TextStyle(fontSize: 28)),
                  const Spacer(),
                  Text(c.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('${c.memberCount} members',
                      style: const TextStyle(
                          fontSize: 12, color: IjwiColors.muted)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _groupList() {
    final groups = _groups;
    return RefreshIndicator(
      onRefresh: _load,
      child: groups == null
          ? const Center(child: CircularProgressIndicator())
          : groups.isEmpty
              ? ListView(children: const [
                  EmptyState(
                      icon: Icons.groups_2,
                      title: 'No groups to discover',
                      message: 'Create or join a group by crop, location or purpose.'),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: groups.length,
                  itemBuilder: (context, i) {
                    final g = groups[i];
                    return Card(
                      child: ListTile(
                        leading: IjwiAvatar(g.name, isGroup: true),
                        title: Row(children: [
                          Expanded(
                            child: Text(g.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                          if (g.isPrivate)
                            Icon(Icons.lock_outline,
                                size: 15, color: Colors.grey.shade500),
                        ]),
                        subtitle: Text(
                            '${g.memberCount} members'
                            '${g.isMember ? " · member" : ""}'),
                        trailing: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(70, 34)),
                            onPressed: () async {
                              if (!g.isMember) {
                                try {
                                  await ref
                                      .read(communityServiceProvider)
                                      .joinGroup(g.id);
                                  await _load();
                                } catch (_) {}
                              }
                            },
                            child: Text(g.isMember ? 'Open' : 'Join')),
                        onTap: () => context.push('/community/group/${g.id}'),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _channelList() {
    final channels = _channels;
    return RefreshIndicator(
      onRefresh: _load,
      child: channels == null
          ? const Center(child: CircularProgressIndicator())
          : channels.isEmpty
              ? ListView(children: const [
                  EmptyState(
                      icon: Icons.campaign_outlined,
                      title: 'No channels yet',
                      message: 'Broadcast channels for market intel and training.'),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: channels.length,
                  itemBuilder: (context, i) {
                    final ch = channels[i];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                            backgroundColor: Color(0xFFEDE9FE),
                            child: Icon(Icons.campaign_outlined,
                                color: IjwiColors.blue)),
                        title: Text(ch.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${ch.subscriberCount} followers'),
                        trailing: IconButton(
                            icon: const Icon(Icons.add_alert_outlined),
                            tooltip: 'Follow',
                            onPressed: () async {
                              try {
                                await ref
                                    .read(communityServiceProvider)
                                    .followChannel(ch.id);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Following')));
                                }
                              } catch (_) {}
                            }),
                        onTap: () =>
                            context.push('/community/channel/${ch.id}'),
                      ),
                    );
                  },
                ),
    );
  }
}
