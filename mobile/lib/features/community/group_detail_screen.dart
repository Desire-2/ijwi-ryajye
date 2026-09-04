import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../shared/widgets/ui.dart';
import 'community_models.dart';
import 'community_service.dart';
import 'post_card.dart';

/// Group detail with header, join state, and tabs for chat, members and
/// announcements. Uses the group's conversation for real-time chat.
class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  CommunityGroupProfile? _group;
  List<Post>? _posts;
  List<Comment>? _comments;
  String? _error;
  String? _conversationId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(communityServiceProvider);
    try {
      final group = await svc.getGroup(widget.groupId);
      final postTask = svc.listPosts(groupId: widget.groupId, perPage: 20);
      final convTask = _resolveConv(svc, group);
      final results = await Future.wait([postTask, convTask]);
      if (!mounted) return;
      setState(() {
        _group = group;
        _posts = results[0] as List<Post>;
        _conversationId = results[1] as String?;
        _error = null;
      });
      _loadComments();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  Future<String?> _resolveConv(CommunityService svc, CommunityGroupProfile g) async {
    try {
      final c = await svc.groupConversation(g.id);
      return c['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadComments() async {
    final svc = ref.read(communityServiceProvider);
    final posts = _posts ?? [];
    try {
      final comments = <String, List<Comment>>{};
      for (final p in posts.take(5)) {
        comments[p.id] = await svc.listComments(p.id);
      }
      if (mounted) setState(() => _comments = comments.values.expand((e) => e).toList());
    } catch (_) {}
  }

  Future<void> _join() async {
    try {
      await ref.read(communityServiceProvider).joinGroup(widget.groupId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;
    return Scaffold(
      appBar: AppBar(title: Text(group?.name ?? 'Group')),
      body: _error != null && group == null
          ? ErrorBox(_error!, onRetry: _load)
          : group == null
              ? const Center(child: CircularProgressIndicator())
              : _content(group),
    );
  }

  Widget _content(CommunityGroupProfile group) {
    final member = group.isMember;
    return Column(children: [
      _header(context, group),
      if (member)
        TabBar(
          controller: _tabs,
          labelColor: IjwiColors.green,
          unselectedLabelColor: IjwiColors.muted,
          indicatorColor: IjwiColors.green,
          tabs: const [
            Tab(text: 'Chat'),
            Tab(text: 'Posts'),
            Tab(text: 'Members'),
          ],
        ),
      Expanded(
        child: !member
            ? _joinPrompt(group)
            : TabBarView(controller: _tabs, children: [
                _chatTab(context, group),
                _postsTab(context),
                _membersTab(group),
              ]),
      ),
    ]);
  }

  Widget _header(BuildContext context, CommunityGroupProfile group) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: IjwiColors.greenLight,
      child: Row(children: [
        IjwiAvatar(group.name, size: 56, isGroup: true),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              if (group.isPrivate)
                Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade500),
            ]),
            if (group.description.isNotEmpty)
              Text(group.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: IjwiColors.muted)),
            const SizedBox(height: 4),
            Text('${group.memberCount} members',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: IjwiColors.green)),
          ]),
        ),
        if (!group.isMember)
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
              onPressed: _join,
              child: const Text('Join'))
        else
          FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 40)),
              onPressed: () {
                if (_conversationId != null) {
                  context.push('/chat/$_conversationId');
                }
              },
              icon: const Icon(Icons.chat_bubble, size: 18),
              label: const Text('Chat')),
      ]),
    );
  }

  Widget _joinPrompt(CommunityGroupProfile group) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.groups_2, size: 56, color: IjwiColors.green),
          const SizedBox(height: 12),
          Text('Join ${group.name}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            'Connect with farmers, share updates and trade together.',
            textAlign: TextAlign.center,
            style: TextStyle(color: IjwiColors.muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _join, child: const Text('Join group')),
        ]),
      ),
    );
  }

  Widget _chatTab(BuildContext context, CommunityGroupProfile group) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.forum_outlined, size: 48, color: IjwiColors.muted),
        const SizedBox(height: 10),
        const Text('Group chat is open',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Message, react and share with members in real time.',
            textAlign: TextAlign.center,
            style: TextStyle(color: IjwiColors.muted)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () {
            if (_conversationId != null) {
              context.push('/chat/$_conversationId');
            }
          },
          icon: const Icon(Icons.chat),
          label: const Text('Open chat'),
        ),
      ]),
    );
  }

  Widget _postsTab(BuildContext context) {
    final posts = _posts;
    return RefreshIndicator(
      onRefresh: _load,
      child: posts == null
          ? const Center(child: CircularProgressIndicator())
          : posts.isEmpty
              ? ListView(children: const [
                  EmptyState(
                      icon: Icons.notes,
                      title: 'No group posts yet',
                      message: 'Share updates and discussions with this group.',
                      actionLabel: 'Write a post',
                      ),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: posts.length,
                  itemBuilder: (context, i) => PostCard(
                    post: posts[i],
                    onChanged: (p) => setState(() => _posts![i] = p),
                  ),
                ),
    );
  }

  Widget _membersTab(CommunityGroupProfile group) {
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            const Text('Group members',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const Spacer(),
            Text('${group.memberCount} total',
                style: const TextStyle(color: IjwiColors.muted, fontSize: 13)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: const Text(
            'Member directory loads with group permissions. Ask an admin to invite members.',
            textAlign: TextAlign.center,
            style: TextStyle(color: IjwiColors.muted),
          ),
        ),
      ],
    );
  }
}
