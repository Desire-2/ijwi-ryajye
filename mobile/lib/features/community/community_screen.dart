import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../shared/widgets/ui.dart';

class _CommunityRow {
  _CommunityRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String? ?? '',
        description = j['description'] as String? ?? '',
        memberCount = (j['member_count'] as num?)?.toInt() ?? 0,
        joined = j['joined'] == true || j['is_member'] == true;

  final String id;
  final String name;
  final String description;
  final int memberCount;
  final bool joined;
}

class _GroupRow {
  _GroupRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String? ?? '',
        memberCount = (j['member_count'] as num?)?.toInt() ?? 0,
        myRole = j['my_role'] as String?,
        isPrivate = j['is_private'] == true;

  final String id;
  final String name;
  final int memberCount;
  final String? myRole;
  final bool isPrivate;
}

class _ChannelRow {
  _ChannelRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = (j['title'] as String?) ?? (j['name'] as String?) ?? 'Channel',
        followers = ((j['follower_count'] as num?) ??
                (j['subscriber_count'] as num?) ??
                (j['member_count'] as num?) ??
                0)
            .toInt();

  final String id;
  final String title;
  final int followers;
}

/// Community hub: Communities · Groups · Channels.
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  List<_CommunityRow>? _communities;
  List<_GroupRow>? _groups;
  List<_ChannelRow>? _channels;
  String? _errorGroups;

  @override
  void initState() {
    super.initState();
    _loadCommunities();
    _loadGroups();
    _loadChannels();
  }

  Future<void> _loadCommunities() async {
    try {
      final res =
          await ref.read(apiClientProvider).getJson('/communities');
      setState(() => _communities = (res['communities'] as List? ??
              res['items'] as List? ??
              const [])
          .map((j) => _CommunityRow.fromJson(j as Map<String, dynamic>))
          .toList());
    } catch (_) {}
  }

  Future<void> _loadGroups() async {
    try {
      final res = await ref.read(apiClientProvider).getJson('/groups');
      setState(() {
        _groups = (res['groups'] as List? ?? const [])
            .map((j) => _GroupRow.fromJson(j as Map<String, dynamic>))
            .toList();
        _errorGroups = null;
      });
    } catch (e) {
      setState(() => _errorGroups = ApiClient.errorMessage(e));
    }
  }

  Future<void> _loadChannels() async {
    try {
      final res = await ref.read(apiClientProvider).getJson('/channels');
      setState(() => _channels = (res['channels'] as List? ??
              res['items'] as List? ??
              const [])
          .map((j) => _ChannelRow.fromJson(j as Map<String, dynamic>))
          .toList());
    } catch (_) {}
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
            decoration:
                const InputDecoration(labelText: 'Group name'),
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
      await ref.read(apiClientProvider).postJson('/groups',
          {'name': nameCtl.text.trim(), 'require_approval': false});
      await _loadGroups();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  Future<void> _joinGroup(_GroupRow g) async {
    if (g.myRole != null) {
      // Already a member → open its chat room.
      context.go('/chat/${g.id}?group=1');
      return;
    }
    try {
      final res = await ref
          .read(apiClientProvider)
          .postJson('/groups/${g.id}/join', {});
      final state = res['state'];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(state == 'PENDING'
                ? 'Join request sent — waiting for approval.'
                : 'Welcome to ${g.name}!')));
      }
      await _loadGroups();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  /// Group chat rooms are conversations with group_id; resolve mine and open.
  Future<void> _openGroupChat(_GroupRow g) async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .getJson('/conversations', query: {'type': 'GROUP'});
      final convs = (res['conversations'] as List? ?? const [])
          .map((j) => j as Map<String, dynamic>)
          .toList();
      final match =
          convs.where((c) => c['group_id'] == g.id).toList();
      if (!mounted) return;
      if (match.isNotEmpty) {
        context.go('/chat/${match.first['id']}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Join the group first to open its chat.')));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('community')),
        actions: [
          IconButton(
              tooltip: 'Create group',
              onPressed: _createGroup,
              icon: const Icon(Icons.add_circle_outline)),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Communities'),
            Tab(text: 'Groups'),
            Tab(text: 'Channels'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _communitiesTab(),
        _groupsTab(),
        _channelsTab(),
      ]),
    );
  }

  Widget _communitiesTab() {
    final items = _communities;
    return RefreshIndicator(
      onRefresh: _loadCommunities,
      child: items == null
          ? ListView(children: const [Skeleton(height: 76), Skeleton(height: 76)])
          : items.isEmpty
              ? ListView(children: const [
                  EmptyState(
                      icon: Icons.public,
                      title: 'No communities yet',
                      message:
                          'Regional farmer communities appear here once created.'),
                ])
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final c = items[i];
                    return Card(
                      child: ListTile(
                        leading: const IjwiAvatar('', size: 44, isGroup: true),
                        title: Text(c.name,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(c.description.isEmpty
                            ? '${c.memberCount} members'
                            : c.description),
                        trailing: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(70, 34)),
                            onPressed: () async {
                              try {
                                await ref.read(apiClientProvider).postJson(
                                    '/communities/${c.id}/join', {});
                                await _loadCommunities();
                              } catch (_) {}
                            },
                            child: Text(c.joined ? 'Open' : 'Join')),
                      ),
                    );
                  }),
    );
  }

  Widget _groupsTab() {
    final tr = ref.watch(trProvider);
    return RefreshIndicator(
      onRefresh: _loadGroups,
      child: _groups == null
          ? (_errorGroups != null
              ? ListView(children: [ErrorBox(_errorGroups!, onRetry: _loadGroups)])
              : ListView(children: const [Skeleton(height: 76), Skeleton(height: 76)]))
          : _groups!.isEmpty
              ? ListView(children: [
                  EmptyState(
                      icon: Icons.groups_2,
                      title: tr('community'),
                      message:
                          'Create a group for your cooperative, village or crop — chat, share listings and organize together.',
                      actionLabel: 'Create group',
                      onAction: _createGroup),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: _groups!.length,
                  itemBuilder: (context, i) {
                    final g = _groups![i];
                    final member = g.myRole != null;
                    return Card(
                      child: ListTile(
                        leading: IjwiAvatar(g.name, isGroup: true),
                        title: Row(children: [
                          Expanded(
                              child: Text(g.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700))),
                          if (g.isPrivate)
                            Icon(Icons.lock_outline,
                                size: 15, color: Colors.grey.shade500),
                        ]),
                        subtitle: Text(
                            '${g.memberCount} members'
                            '${member && g.myRole != null ? " · you: ${g.myRole!.toLowerCase().replaceAll("_", " ")}" : ""}'),
                        trailing: member
                            ? IconButton(
                                tooltip: 'Open chat',
                                icon: const Icon(Icons.chat_bubble_outline,
                                    color: IjwiColors.green),
                                onPressed: () => _openGroupChat(g))
                            : null,
                        onTap: () => _joinGroup(g),
                      ),
                    );
                  }),
    );
  }

  Widget _channelsTab() {
    final items = _channels;
    return RefreshIndicator(
      onRefresh: _loadChannels,
      child: items == null
          ? ListView(children: const [Skeleton(height: 76)])
          : items.isEmpty
              ? ListView(children: const [
                  EmptyState(
                      icon: Icons.campaign_outlined,
                      title: 'No channels yet',
                      message:
                          'Broadcast channels for market intelligence and training will appear here.'),
                ])
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final ch = items[i];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                            backgroundColor: Color(0xFFEDE9FE),
                            child: Icon(Icons.campaign_outlined,
                                color: IjwiColors.blue)),
                        title: Text(ch.title,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${ch.followers} followers'),
                        trailing: IconButton(
                            icon: const Icon(Icons.add_alert_outlined),
                            tooltip: 'Follow',
                            onPressed: () async {
                              try {
                                await ref.read(apiClientProvider).postJson(
                                    '/channels/${ch.id}/follow', {});
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Following')));
                                }
                              } catch (_) {}
                            }),
                      ),
                    );
                  }),
    );
  }
}
