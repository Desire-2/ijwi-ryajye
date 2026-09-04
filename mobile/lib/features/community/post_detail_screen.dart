import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../features/auth/auth_controller.dart';
import '../../shared/widgets/ui.dart';
import 'community_models.dart';
import 'community_service.dart';
import 'community_widgets.dart';
import 'post_card.dart';

/// Post detail with threaded comments, reactions, best answer and reply.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({required this.postId, super.key});

  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  Post? _post;
  List<Comment>? _comments;
  String? _error;
  String _sort = 'newest';
  final _replyCtl = TextEditingController();
  Comment? _replyingTo;
  String _selectedReaction = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(communityServiceProvider);
    try {
      final results = await Future.wait([
        svc.getPost(widget.postId),
        svc.listComments(widget.postId, sort: _sort),
      ]);
      if (!mounted) return;
      setState(() {
        _post = results[0] as Post;
        _comments = results[1] as List<Comment>;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  Future<void> _changeSort(String sort) async {
    setState(() => _sort = sort);
    final svc = ref.read(communityServiceProvider);
    try {
      final comments = await svc.listComments(widget.postId, sort: sort);
      if (mounted) setState(() => _comments = comments);
    } catch (_) {}
  }

  Future<void> _sendComment() async {
    final text = _replyCtl.text.trim();
    if (text.isEmpty) return;
    final svc = ref.read(communityServiceProvider);
    try {
      final comment = await svc.addComment(
        widget.postId,
        text,
        parentCommentId: _replyingTo?.id,
      );
      _replyCtl.clear();
      setState(() {
        _replyingTo = null;
        _comments = [
          ...?_comments,
          comment,
        ];
        if (_post != null) {
          _post = _post!.copyWithReplyCount(_post!.replyCount + 1);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  void _onCommentReaction(int index, String emoji) {
    final svc = ref.read(communityServiceProvider);
    final old = _comments![index];
    final newReaction = emoji;
    setState(() {
      _comments![index] = _copyCommentComment(old,
          myReaction: newReaction,
          reactionCount: old.reactionCount + 1);
    });
    svc.reactToComment(old.id, emoji);
  }

  Future<void> _markBestAnswer(Comment c) async {
    final svc = ref.read(communityServiceProvider);
    try {
      await svc.markBestAnswer(widget.postId, c.id);
      setState(() {
        _comments = _comments!.map((x) {
          if (x.id == c.id) {
            return _copyCommentComment(x, isBestAnswer: true);
          }
          return _copyCommentComment(x, isBestAnswer: false);
        }).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked as best answer')));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: _error != null && post == null
          ? ErrorBox(_error!, onRetry: _load)
          : post == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        PostCard(
                          post: post,
                          onChanged: (p) => setState(() => _post = p),
                          onTap: () {},
                        ),
                        _sortBar(context),
                        _bestAnswerSection(),
                        _commentsList(),
                      ],
                    ),
                  ),
                  _replyComposer(),
                ]),
    );
  }

  Widget _sortBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DropdownButton<String>(
          value: _sort,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: 'newest', child: Text('Newest')),
            DropdownMenuItem(value: 'top', child: Text('Top')),
            DropdownMenuItem(value: 'oldest', child: Text('Oldest')),
          ],
          onChanged: (v) {
            if (v != null) _changeSort(v);
          },
        ),
      ),
    );
  }

  Widget _bestAnswerSection() {
    final comments = _comments ?? [];
    final best =
        comments.where((c) => c.isBestAnswer).toList();
    if (best.isEmpty) return const SizedBox.shrink();
    final b = best.first;
    return Card(
      color: const Color(0xFFF1F8FF),
      child: ListTile(
        leading: const Icon(Icons.check_circle, color: IjwiColors.green),
        title: Text(b.author.displayName,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(b.bodyText),
        trailing: IconButton(
          onPressed: () {
            final me = ref.read(authProvider).valueOrNull;
            if (_post?.author.id == me?.id) _markBestAnswer(b);
          },
          icon: const Icon(Icons.check_circle_outline,
              color: IjwiColors.green),
          tooltip: 'Best answer',
        ),
      ),
    );
  }

  Widget _commentsList() {
    final comments = _comments ?? [];
    if (comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text('No comments yet. Start the discussion.',
              style: TextStyle(color: IjwiColors.muted)),
        ),
      );
    }
    return Column(children: [
      for (var i = 0; i < comments.length; i++) _commentTile(context, i),
    ]);
  }

  Widget _commentTile(BuildContext context, int index) {
    final c = _comments![index];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IjwiAvatar(c.author.displayName, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(c.author.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800)),
                    ),
                    if (c.isBestAnswer)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text('✓ Best Answer',
                            style: TextStyle(
                                color: IjwiColors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text(c.bodyText,
                      style: const TextStyle(height: 1.4, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(children: [
                    InkWell(
                      onTap: () => _showReactionSheet(context, index),
                      child: Text(c.myReaction ?? '❤',
                          style: const TextStyle(
                              color: IjwiColors.red, fontSize: 13)),
                    ),
                    const SizedBox(width: 6),
                    Text('${c.reactionCount}',
                        style: const TextStyle(
                            color: IjwiColors.muted, fontSize: 12)),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () => setState(() => _replyingTo = c),
                      child: const Text('Reply',
                          style: TextStyle(
                              color: IjwiColors.green, fontSize: 13)),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReactionSheet(BuildContext context, int index) {
    final svc = ref.read(communityServiceProvider);
    final c = _comments![index];
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            for (final e in PostTypeStyle.reactionEmojis)
              InkWell(
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _onCommentReaction(index, e);
                },
                child: Text(e, style: const TextStyle(fontSize: 30)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _replyComposer() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(children: [
          if (_replyingTo != null)
            Expanded(child: _replyingChip()),
          if (_replyingTo != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _replyingTo = null),
            ),
          Expanded(
            child: TextField(
              controller: _replyCtl,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Write a comment…',
                filled: true,
                fillColor: IjwiColors.surface,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
          IconButton(
            onPressed: _sendComment,
            icon: const Icon(Icons.send, color: IjwiColors.green),
          ),
        ]),
      ),
    );
  }

  Widget _replyingChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: IjwiColors.greenLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Replying to ${_replyingTo!.author.displayName}',
              style: const TextStyle(
                  fontSize: 11, color: IjwiColors.green,
                  fontWeight: FontWeight.w700)),
          Text(_replyingTo!.bodyText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: IjwiColors.muted)),
        ],
      ),
    );
  }

  Comment _copyCommentComment(Comment c,
      {String? myReaction, int? reactionCount, bool? isBestAnswer}) {
    return Comment(
      id: c.id,
      postId: c.postId,
      author: c.author,
      parentCommentId: c.parentCommentId,
      bodyText: c.bodyText,
      mediaKey: c.mediaKey,
      isBestAnswer: isBestAnswer ?? c.isBestAnswer,
      reactionCount: reactionCount ?? c.reactionCount,
      replyCount: c.replyCount,
      myReaction: myReaction ?? c.myReaction,
      createdAt: c.createdAt,
    );
  }
}
