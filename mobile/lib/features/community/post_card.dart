import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/design_system.dart';
import '../../shared/widgets/ui.dart';
import 'community_models.dart';
import 'community_service.dart';
import 'community_widgets.dart';

/// Reusable post card. Renders a distinct visual treatment per post type,
/// with reactions, comments, share and save actions wired to the community
/// service.
class PostCard extends ConsumerWidget {
  const PostCard({
    required this.post,
    required this.onChanged,
    this.onTap,
    super.key,
  });

  final Post post;
  final ValueChanged<Post> onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeColor = PostTypeStyle.color(post.postType);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(IjwiRadius.md),
        onTap: onTap ?? () => context.push('/community/post/${post.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context),
              const SizedBox(height: 8),
              _typeTag(context),
              if (post.title.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(post.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ],
              if (post.bodyText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(post.bodyText,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(height: 1.4, fontSize: 14)),
              ],
              if (post.locationLabel != null &&
                  post.locationLabel!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.place_outlined,
                      size: 13, color: IjwiColors.muted),
                  const SizedBox(width: 2),
                  Text(post.locationLabel!,
                      style: const TextStyle(
                          fontSize: 12, color: IjwiColors.muted)),
                ]),
              ],
              if (post.topicTags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in post.topicTags)
                    Chip(
                      label: Text('#$t'),
                      visualDensity: VisualDensity.compact,
                      labelStyle: const TextStyle(
                          fontSize: 12, color: IjwiColors.green),
                      backgroundColor: IjwiColors.greenLight,
                      side: BorderSide.none,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ]),
              ],
              const SizedBox(height: 10),
              _actionBar(context, ref, typeColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(children: [
      IjwiAvatar(post.author.displayName),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Flexible(
                child: Text(
                  post.author.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (post.author.verified)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.verified,
                      size: 15, color: IjwiColors.blue),
                ),
            ]),
            if (post.createdAt != null)
              Text(_timeAgo(post.createdAt!),
                  style: const TextStyle(fontSize: 12, color: IjwiColors.muted)),
          ],
        ),
      ),
      if (post.isPinned)
        const Icon(Icons.push_pin, size: 16, color: IjwiColors.amber),
    ]);
  }

  Widget _typeTag(BuildContext context) {
    final c = PostTypeStyle.color(post.postType);
    final icon = PostTypeStyle.icon(post.postType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 3),
        Text(PostTypeStyle.label(post.postType),
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }

  Widget _actionBar(BuildContext context, WidgetRef ref, Color color) {
    final svc = ref.read(communityServiceProvider);
    return Row(
      children: [
        _reactionButton(context, svc),
        const SizedBox(width: 14),
        _countIcon(Icons.chat_bubble_outline, post.replyCount, 'Comment'),
        const SizedBox(width: 14),
        _shareButton(context, svc),
        const Spacer(),
        _saveButton(context, svc),
      ],
    );
  }

  Widget _reactionButton(BuildContext context, CommunityService svc) {
    final hasReaction = post.myReaction != null;
    return GestureDetector(
      onTap: () => _showReactionPicker(context, svc),
      child: Row(children: [
        Icon(
          hasReaction ? Icons.favorite : Icons.favorite_border,
          size: 20,
          color: hasReaction ? IjwiColors.red : IjwiColors.green,
        ),
        const SizedBox(width: 4),
        Text('${post.reactionCount}',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: hasReaction ? IjwiColors.red : IjwiColors.muted)),
      ]),
    );
  }

  Widget _shareButton(BuildContext context, CommunityService svc) {
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copied — share it with your group'))),
      child: Row(children: [
        const Icon(Icons.share_outlined, size: 19, color: IjwiColors.muted),
        const SizedBox(width: 4),
        Text('${post.shareCount}',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: IjwiColors.muted)),
      ]),
    );
  }

  Widget _countIcon(IconData icon, int count, String semantic) {
    return Semantics(
      label: '$semantic $count',
      child: Row(children: [
        Icon(icon, size: 19, color: IjwiColors.muted),
        const SizedBox(width: 4),
        Text('$count',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: IjwiColors.muted)),
      ]),
    );
  }

  Widget _saveButton(BuildContext context, CommunityService svc) {
    return IconButton(
      onPressed: () => _toggleSave(context, svc),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      icon: Icon(
        post.saved ? Icons.bookmark : Icons.bookmark_border,
        size: 20,
        color: post.saved ? IjwiColors.amber : IjwiColors.muted,
      ),
    );
  }

  Future<void> _toggleSave(BuildContext context, CommunityService svc) async {
    try {
      final res = await svc.savePost(post.id);
      onChanged(_copyWith(saved: res['saved'] == true));
    } catch (_) {}
  }

  void _showReactionPicker(BuildContext context, CommunityService svc) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            for (final e in PostTypeStyle.reactionEmojis)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final res = await svc.reactToPost(post.id, e);
                    onChanged(_copyWith(
                      myReaction: res['removed'] == true ? null : e,
                      reactionCount: res['removed'] == true
                          ? (post.reactionCount - 1).clamp(0, 999999)
                          : post.reactionCount + 1,
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(res['removed'] == true ? 'Removed' : e),
                        duration: const Duration(milliseconds: 600)));
                  } catch (_) {}
                },
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: IjwiColors.greenLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 26)),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Post _copyWith({
    int? reactionCount,
    String? myReaction,
    bool? saved,
  }) {
    return Post(
      id: post.id,
      author: post.author,
      postType: post.postType,
      title: post.title,
      bodyText: post.bodyText,
      mediaKeys: post.mediaKeys,
      communityId: post.communityId,
      groupId: post.groupId,
      channelId: post.channelId,
      entityRefType: post.entityRefType,
      entityRefId: post.entityRefId,
      listingId: post.listingId,
      topicTags: post.topicTags,
      locationLabel: post.locationLabel,
      isPinned: post.isPinned,
      isFeatured: post.isFeatured,
      isBestAnswer: post.isBestAnswer,
      bestAnswerCommentId: post.bestAnswerCommentId,
      replyCount: post.replyCount,
      reactionCount: reactionCount ?? post.reactionCount,
      shareCount: post.shareCount,
      viewCount: post.viewCount,
      myReaction: myReaction ?? post.myReaction,
      saved: saved ?? post.saved,
      authorFollowed: post.authorFollowed,
      createdAt: post.createdAt,
    );
  }

  String _timeAgo(String iso) {
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final diff = DateTime.now().difference(t.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${t.day}/${t.month}';
  }
}
