import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'community_models.dart';

/// Single data-access layer for the Community module.
/// Every community screen calls these methods instead of touching the
/// API client directly. This keeps the Community experience consistent and
/// testable in one place.
class CommunityService {
  CommunityService(this._api);

  final ApiClient _api;

  // ---- Communities ----
  Future<List<CommunityProfile>> listCommunities({String? type}) async {
    final res = await _api.getJson('/communities',
        query: type != null ? {'type': type} : null);
    final items = (res['communities'] as List? ??
            res['items'] as List? ??
            const [])
        .map((j) => CommunityProfile.fromJson(j as Map<String, dynamic>))
        .toList();
    return items;
  }

  Future<List<CommunityProfile>> recommendedCommunities() async {
    final res = await _api.getJson('/communities/recommended');
    final raw = res['recommendations'] as List? ?? res['communities'] as List? ?? const [];
    return raw
        .map((j) => CommunityProfile.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> joinCommunity(String id) async {
    await _api.postJson('/communities/$id/join', {});
  }

  // ---- Groups ----
  Future<List<CommunityGroupProfile>> listGroups({String? q}) async {
    final res = await _api.getJson('/groups', query: q != null ? {'q': q} : null);
    final items = (res['groups'] as List? ??
            res['items'] as List? ??
            const [])
        .map((j) => CommunityGroupProfile.fromJson(j as Map<String, dynamic>))
        .toList();
    return items;
  }

  Future<CommunityGroupProfile> getGroup(String id) async {
    final res = await _api.getJson('/groups/$id');
    return CommunityGroupProfile.fromJson(
        (res['group'] as Map<String, dynamic>?) ?? res);
  }

  Future<Map<String, dynamic>> createGroup(Map<String, dynamic> payload) async {
    return _api.postJson('/groups', payload);
  }

  Future<Map<String, dynamic>> joinGroup(String id) async {
    return _api.postJson('/groups/$id/join', {});
  }

  // ---- Channels ----
  Future<List<ChannelProfile>> listChannels() async {
    final res = await _api.getJson('/channels');
    final items = (res['channels'] as List? ??
            res['items'] as List? ??
            const [])
        .map((j) => ChannelProfile.fromJson(j as Map<String, dynamic>))
        .toList();
    return items;
  }

  Future<void> followChannel(String id) async {
    await _api.postJson('/channels/$id/follow', {});
  }

  Future<void> unfollowChannel(String id) async {
    await _api.postJson('/channels/$id/unfollow', {});
  }

  Future<List<Post>> channelPosts(String channelId) async {
    final res = await _api.getJson('/channels/$channelId/posts');
    final items = res['posts'] as List? ?? res['items'] as List? ?? const [];
    return items
        .map((j) => Post.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  // ---- Posts / feed ----
  Future<List<Post>> listPosts({
    String? communityId,
    String? groupId,
    String? channelId,
    String? postType,
    String? authorId,
    String? topic,
    bool? forYou,
    int page = 1,
    int perPage = 20,
  }) async {
    final query = <String, dynamic>{'page': page, 'per_page': perPage};
    if (communityId != null) query['community_id'] = communityId;
    if (groupId != null) query['group_id'] = groupId;
    if (channelId != null) query['channel_id'] = channelId;
    if (postType != null) query['post_type'] = postType;
    if (authorId != null) query['author_id'] = authorId;
    if (topic != null) query['topic'] = topic;
    if (forYou == true) query['feed'] = 'for_you';

    final res = await _api.getJson('/posts', query: query);
    final items = res['items'] as List? ?? res['posts'] as List? ?? const [];
    return items
        .map((j) => Post.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<Post> getPost(String id) async {
    final res = await _api.getJson('/posts/$id');
    return Post.fromJson((res['post'] as Map<String, dynamic>?) ?? res);
  }

  Future<Post> createPost({
    required String postType,
    String title = '',
    String bodyText = '',
    List<String> mediaKeys = const [],
    String? communityId,
    String? groupId,
    String? channelId,
    String? listingId,
    List<String>? topicTags,
    String? location,
  }) async {
    final payload = <String, dynamic>{
      'post_type': postType,
      'title': title,
      'body_text': bodyText,
      'media_keys': mediaKeys,
      if (communityId != null) 'community_id': communityId,
      if (groupId != null) 'group_id': groupId,
      if (channelId != null) 'channel_id': channelId,
      if (listingId != null) 'listing_id': listingId,
      if (topicTags != null) 'topic_tags': topicTags.join(','),
      if (location != null) 'location_label': location,
    };
    final res = await _api.postJson('/posts', payload);
    return Post.fromJson((res['post'] as Map<String, dynamic>?) ?? res);
  }

  Future<List<Post>> savedPosts() async {
    final res = await _api.getJson('/posts/saved');
    final items = res['items'] as List? ?? const [];
    return items
        .map((j) => Post.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> reactToPost(String id, String emoji) async {
    return _api.postJson('/posts/$id/react', {'emoji': emoji});
  }

  Future<Map<String, dynamic>> savePost(String id) async {
    return _api.postJson('/posts/$id/save', {});
  }

  Future<void> deletePost(String id) async {
    await _api.delete('/posts/$id');
  }

  // ---- Comments ----
  Future<List<Comment>> listComments(String postId,
      {int page = 1, String sort = 'newest'}) async {
    final res = await _api.getJson('/posts/$postId/comments',
        query: {'page': page, 'sort': sort});
    final items = res['items'] as List? ?? const [];
    return items
        .map((j) => Comment.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<Comment> addComment(String postId, String body,
      {String? parentCommentId}) async {
    final res = await _api.postJson('/posts/$postId/comments',
        {'body_text': body, if (parentCommentId != null) 'parent_comment_id': parentCommentId});
    return Comment.fromJson((res['comment'] as Map<String, dynamic>?) ?? res);
  }

  Future<List<Comment>> listReplies(String commentId) async {
    final res = await _api.getJson('/comments/$commentId/replies');
    final items = res['items'] as List? ?? const [];
    return items
        .map((j) => Comment.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> reactToComment(String id, String emoji) async {
    return _api.postJson('/comments/$id/react', {'emoji': emoji});
  }

  Future<void> markBestAnswer(String postId, String commentId) async {
    await _api.postJson('/posts/$postId/best-answer', {'comment_id': commentId});
  }

  // ---- Follow ----
  Future<Map<String, dynamic>> followUser(String id) async {
    return _api.postJson('/users/$id/follow', {});
  }

  Future<Map<String, dynamic>> unfollowUser(String id) async {
    return _api.postJson('/users/$id/unfollow', {});
  }

  // ---- Status ----
  Future<List<StatusData>> listStatuses() async {
    final res = await _api.getJson('/statuses');
    final items = res['statuses'] as List? ?? res['items'] as List? ?? const [];
    return items.map((j) => StatusData.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> createStatus({
    required String statusType,
    String? bodyText,
    String? mediaKey,
    String? listingId,
  }) async {
    return _api.postJson('/statuses', {
      'status_type': statusType,
      if (bodyText != null) 'body_text': bodyText,
      if (mediaKey != null) 'media_key': mediaKey,
      if (listingId != null) 'listing_id': listingId,
    });
  }

  Future<void> viewStatus(String id) async {
    await _api.postJson('/statuses/$id/view', {});
  }

  // ---- Polls ----
  Future<List<PollData>> createPoll({
    required String question,
    required List<String> options,
    bool multipleChoice = false,
    bool anonymous = false,
    int ttlHours = 48,
    String? groupId,
    String? conversationId,
  }) async {
    final res = await _api.postJson('/polls', {
      'question': question,
      'options': options,
      'multiple_choice': multipleChoice,
      'anonymous': anonymous,
      'ttl_hours': ttlHours,
      if (groupId != null) 'group_id': groupId,
      if (conversationId != null) 'conversation_id': conversationId,
    });
    return [];
  }

  Future<Map<String, dynamic>> votePoll(String pollId, List<String> optionIds) async {
    return _api.postJson('/polls/$pollId/vote', {'option_ids': optionIds});
  }

  Future<PollData> pollResults(String pollId) async {
    final res = await _api.getJson('/polls/$pollId/results');
    return PollData.fromJson(res);
  }

  // ---- Events ----
  Future<List<EventData>> listEvents() async {
    final res = await _api.getJson('/events');
    final items = res['events'] as List? ?? res['items'] as List? ?? const [];
    return items.map((j) => EventData.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<EventData> createEvent({
    required String title,
    required String startsAt,
    String description = '',
    String? endsAt,
    String? locationLabel,
    String? groupId,
    String? communityId,
  }) async {
    final res = await _api.postJson('/events', {
      'title': title,
      'starts_at': startsAt,
      'description': description,
      if (endsAt != null) 'ends_at': endsAt,
      if (locationLabel != null) 'location_label': locationLabel,
      if (groupId != null) 'group_id': groupId,
      if (communityId != null) 'community_id': communityId,
    });
    return EventData.fromJson(res);
  }

  Future<void> rsvpEvent(String id, String response) async {
    await _api.postJson('/events/$id/rsvp', {'response': response});
  }

  // ---- Opportunities ----
  Future<List<Opportunity>> listOpportunities() async {
    final res = await _api.getJson('/opportunities');
    final items = res['opportunities'] as List? ?? res['items'] as List? ?? const [];
    return items
        .map((j) => Opportunity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<Opportunity>> listBuyerRequests() async {
    final res = await _api.getJson('/buyer-requests');
    final items = res['buyer_requests'] as List? ?? res['items'] as List? ?? const [];
    return items
        .map((j) => Opportunity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  // ---- Search ----
  Future<Map<String, dynamic>> search(String query) async {
    return _api.getJson('/search', query: {'q': query});
  }

  // ---- Report ----
  Future<void> report({
    required String subjectType,
    required String subjectId,
    required String reason,
    String details = '',
  }) async {
    await _api.postJson('/reports', {
      'subject_type': subjectType,
      'subject_id': subjectId,
      'reason': reason,
      'details': details,
    });
  }

  // ---- Group chat link ----
  Future<Map<String, dynamic>> groupConversation(String groupId) async {
    final res = await _api.getJson('/conversations', query: {'type': 'GROUP'});
    final convs = res['conversations'] as List? ?? const [];
    for (final c in convs) {
      if ((c as Map<String, dynamic>)['group_id'] == groupId) {
        return c as Map<String, dynamic>;
      }
    }
    throw Exception('No conversation for this group');
  }
}

class CommunityServiceProvider {
  static String? pendingDraft;
  static bool draftSaved = false;
}

final communityServiceProvider = Provider<CommunityService>((ref) {
  return CommunityService(ref.watch(apiClientProvider));
});
