import 'package:flutter/foundation.dart';

/// Community feed entity models mapped 1:1 to the backend API contracts.
/// These models are the single source of truth for community data in Flutter.

class CommunityProfile {
  const CommunityProfile({
    required this.id,
    required this.name,
    this.slug = '',
    this.description = '',
    this.iconEmoji = '🌍',
    this.communityType = 'crop',
    this.creatorId,
    this.memberCount = 0,
    this.verifiedExpertsCount = 0,
    this.joined = false,
    this.isPrivate = false,
  });

  factory CommunityProfile.fromJson(Map<String, dynamic> j) {
    return CommunityProfile(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      slug: j['slug'] as String? ?? '',
      description: j['description'] as String? ?? '',
      iconEmoji: j['icon_emoji'] as String? ?? '🌍',
      communityType: j['community_type'] as String? ?? 'crop',
      creatorId: j['creator_id'] as String?,
      memberCount: (j['member_count'] as num?)?.toInt() ?? 0,
      verifiedExpertsCount: (j['verified_experts_count'] as num?)?.toInt() ?? 0,
      joined: j['joined'] == true || j['is_member'] == true,
      isPrivate: j['is_private'] == true,
    );
  }

  final String id;
  final String name;
  final String slug;
  final String description;
  final String iconEmoji;
  final String communityType;
  final String? creatorId;
  final int memberCount;
  final int verifiedExpertsCount;
  final bool joined;
  final bool isPrivate;
}

class CommunityGroupProfile {
  const CommunityGroupProfile({
    required this.id,
    required this.name,
    this.description = '',
    this.groupType = 'interest',
    this.memberCount = 0,
    this.myRole,
    this.isPrivate = false,
    this.requireApproval = true,
    this.photoKey,
  });

  factory CommunityGroupProfile.fromJson(Map<String, dynamic> j) {
    return CommunityGroupProfile(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      description: j['description'] as String? ?? '',
      groupType: j['group_type'] as String? ?? 'interest',
      memberCount: (j['member_count'] as num?)?.toInt() ?? 0,
      myRole: j['my_role'] as String?,
      isPrivate: j['is_private'] == true,
      requireApproval: j['require_approval'] == true,
      photoKey: j['photo_key'] as String?,
    );
  }

  final String id;
  final String name;
  final String description;
  final String groupType;
  final int memberCount;
  final String? myRole;
  final bool isPrivate;
  final bool requireApproval;
  final String? photoKey;

  bool get isMember => myRole != null;
}

class ChannelProfile {
  const ChannelProfile({
    required this.id,
    required this.name,
    this.slug = '',
    this.description = '',
    this.channelType = 'broadcast',
    this.subscriberCount = 0,
    this.followed = false,
  });

  factory ChannelProfile.fromJson(Map<String, dynamic> j) {
    return ChannelProfile(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? j['title'] as String? ?? '',
      slug: j['slug'] as String? ?? '',
      description: j['description'] as String? ?? '',
      channelType: j['channel_type'] as String? ?? 'broadcast',
      subscriberCount: ((j['subscriber_count'] as num?) ??
              (j['follower_count'] as num?) ??
              0)
          .toInt(),
      followed: j['followed'] == true || j['is_following'] == true,
    );
  }

  final String id;
  final String name;
  final String slug;
  final String description;
  final String channelType;
  final int subscriberCount;
  final bool followed;
}

class FarmerIdentity {
  const FarmerIdentity({
    required this.id,
    this.username = '',
    this.fullName = '',
    this.region,
    this.district,
    this.mainCrops = const [],
    this.yearsExperience,
    this.ratingAvg,
    this.completedTransactions,
    this.reputationTier,
    this.verified = false,
    this.specialization,
  });

  factory FarmerIdentity.fromJson(Map<String, dynamic> j) {
    return FarmerIdentity(
      id: j['id'] as String? ?? '',
      username: j['username'] as String? ?? '',
      fullName: j['full_name'] as String? ?? '',
      region: j['region'] as String?,
      district: j['district'] as String?,
      mainCrops: (j['main_crops'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      yearsExperience: (j['years_experience'] as num?)?.toInt(),
      ratingAvg: (j['rating_avg'] as num?)?.toDouble(),
      completedTransactions: (j['completed_transactions'] as num?)?.toInt(),
      reputationTier: j['reputation_tier'] as String?,
      verified: j['verified'] == true,
      specialization: j['specialization'] as String?,
    );
  }

  final String id;
  final String username;
  final String fullName;
  final String? region;
  final String? district;
  final List<String> mainCrops;
  final int? yearsExperience;
  final double? ratingAvg;
  final int? completedTransactions;
  final String? reputationTier;
  final bool verified;
  final String? specialization;

  String get displayName =>
      fullName.isNotEmpty ? fullName : (username.isNotEmpty ? username : 'Farmer');
}

class Post {
  const Post({
    required this.id,
    required this.author,
    required this.postType,
    this.title = '',
    this.bodyText = '',
    this.mediaKeys = const [],
    this.communityId,
    this.groupId,
    this.channelId,
    this.entityRefType,
    this.entityRefId,
    this.listingId,
    this.topicTags = const [],
    this.locationLabel,
    this.isPinned = false,
    this.isFeatured = false,
    this.isBestAnswer = false,
    this.bestAnswerCommentId,
    this.replyCount = 0,
    this.reactionCount = 0,
    this.shareCount = 0,
    this.viewCount = 0,
    this.myReaction,
    this.saved = false,
    this.authorFollowed = false,
    this.createdAt,
  });

  factory Post.fromJson(Map<String, dynamic> j) {
    return Post(
      id: j['id'] as String? ?? '',
      author: FarmerIdentity.fromJson(
          (j['author'] as Map<String, dynamic>?) ?? const {}),
      postType: j['post_type'] as String? ?? 'text',
      title: j['title'] as String? ?? '',
      bodyText: j['body_text'] as String? ?? '',
      mediaKeys: (j['media_keys'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      communityId: j['community_id'] as String?,
      groupId: j['group_id'] as String?,
      channelId: j['channel_id'] as String?,
      entityRefType: j['entity_ref_type'] as String?,
      entityRefId: j['entity_ref_id'] as String?,
      listingId: j['listing_id'] as String?,
      topicTags: (j['topic_tags'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      locationLabel: j['location_label'] as String?,
      isPinned: j['is_pinned'] == true,
      isFeatured: j['is_featured'] == true,
      isBestAnswer: j['is_best_answer'] == true,
      bestAnswerCommentId: j['best_answer_comment_id'] as String?,
      replyCount: (j['reply_count'] as num?)?.toInt() ?? 0,
      reactionCount: (j['reaction_count'] as num?)?.toInt() ?? 0,
      shareCount: (j['share_count'] as num?)?.toInt() ?? 0,
      viewCount: (j['view_count'] as num?)?.toInt() ?? 0,
      myReaction: j['my_reaction'] as String?,
      saved: j['saved'] == true,
      authorFollowed: j['author_followed'] == true,
      createdAt: j['created_at'] as String?,
    );
  }

  final String id;
  final FarmerIdentity author;
  final String postType;
  final String title;
  final String bodyText;
  final List<String> mediaKeys;
  final String? communityId;
  final String? groupId;
  final String? channelId;
  final String? entityRefType;
  final String? entityRefId;
  final String? listingId;
  final List<String> topicTags;
  final String? locationLabel;
  final bool isPinned;
  final bool isFeatured;
  final bool isBestAnswer;
  final String? bestAnswerCommentId;
  final int replyCount;
  final int reactionCount;
  final int shareCount;
  final int viewCount;
  final String? myReaction;
  final bool saved;
  final bool authorFollowed;
  final String? createdAt;

  Post copyWithReplyCount(int replyCount) {
    return Post(
      id: id,
      author: author,
      postType: postType,
      title: title,
      bodyText: bodyText,
      mediaKeys: mediaKeys,
      communityId: communityId,
      groupId: groupId,
      channelId: channelId,
      entityRefType: entityRefType,
      entityRefId: entityRefId,
      listingId: listingId,
      topicTags: topicTags,
      locationLabel: locationLabel,
      isPinned: isPinned,
      isFeatured: isFeatured,
      isBestAnswer: isBestAnswer,
      bestAnswerCommentId: bestAnswerCommentId,
      replyCount: replyCount,
      reactionCount: reactionCount,
      shareCount: shareCount,
      viewCount: viewCount,
      myReaction: myReaction,
      saved: saved,
      authorFollowed: authorFollowed,
      createdAt: createdAt,
    );
  }
}

class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.author,
    this.parentCommentId,
    required this.bodyText,
    this.mediaKey,
    this.isBestAnswer = false,
    this.reactionCount = 0,
    this.replyCount = 0,
    this.myReaction,
    this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> j) {
    return Comment(
      id: j['id'] as String? ?? '',
      postId: j['post_id'] as String? ?? '',
      author: FarmerIdentity.fromJson(
          (j['author'] as Map<String, dynamic>?) ?? const {}),
      parentCommentId: j['parent_comment_id'] as String?,
      bodyText: j['body_text'] as String? ?? '',
      mediaKey: j['media_key'] as String?,
      isBestAnswer: j['is_best_answer'] == true,
      reactionCount: (j['reaction_count'] as num?)?.toInt() ?? 0,
      replyCount: (j['reply_count'] as num?)?.toInt() ?? 0,
      myReaction: j['my_reaction'] as String?,
      createdAt: j['created_at'] as String?,
    );
  }

  final String id;
  final String postId;
  final FarmerIdentity author;
  final String? parentCommentId;
  final String bodyText;
  final String? mediaKey;
  final bool isBestAnswer;
  final int reactionCount;
  final int replyCount;
  final String? myReaction;
  final String? createdAt;
}

class PollData {
  const PollData({
    required this.id,
    required this.question,
    this.options = const [],
    this.multipleChoice = false,
    this.anonymous = false,
    this.closed = false,
    this.totalVotes = 0,
    this.closesAt,
  });

  factory PollData.fromJson(Map<String, dynamic> j) {
    return PollData(
      id: j['poll_id'] as String? ?? j['id'] as String? ?? '',
      question: j['question'] as String? ?? '',
      options: (j['options'] as List? ?? const [])
          .map((o) => PollOptionData.fromJson(o as Map<String, dynamic>))
          .toList(),
      multipleChoice: j['multiple_choice'] == true,
      anonymous: j['anonymous'] == true,
      closed: j['closed'] == true,
      totalVotes: (j['total_votes'] as num?)?.toInt() ?? 0,
      closesAt: j['closes_at'] as String?,
    );
  }

  final String id;
  final String question;
  final List<PollOptionData> options;
  final bool multipleChoice;
  final bool anonymous;
  final bool closed;
  final int totalVotes;
  final String? closesAt;
}

class PollOptionData {
  const PollOptionData({
    required this.id,
    required this.label,
    this.votes = 0,
    this.percent = 0,
  });

  factory PollOptionData.fromJson(Map<String, dynamic> j) {
    return PollOptionData(
      id: j['id'] as String? ?? '',
      label: j['label'] as String? ?? '',
      votes: (j['votes'] as num?)?.toInt() ?? 0,
      percent: (j['percent'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String label;
  final int votes;
  final int percent;
}

class EventData {
  const EventData({
    required this.id,
    required this.title,
    this.groupId,
    this.communityId,
    this.description = '',
    required this.startsAt,
    this.endsAt,
    this.locationLabel,
    this.onlineLink,
    this.organizerId,
    this.cancelled = false,
  });

  factory EventData.fromJson(Map<String, dynamic> j) {
    return EventData(
      id: j['id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      groupId: j['group_id'] as String?,
      communityId: j['community_id'] as String?,
      description: j['description'] as String? ?? '',
      startsAt: j['starts_at'] as String? ?? '',
      endsAt: j['ends_at'] as String?,
      locationLabel: j['location_label'] as String?,
      onlineLink: j['online_link'] as String?,
      organizerId: j['organizer_id'] as String?,
      cancelled: j['cancelled'] == true,
    );
  }

  final String id;
  final String title;
  final String? groupId;
  final String? communityId;
  final String description;
  final String startsAt;
  final String? endsAt;
  final String? locationLabel;
  final String? onlineLink;
  final String? organizerId;
  final bool cancelled;
}

class StatusData {
  const StatusData({
    required this.id,
    required this.author,
    required this.statusType,
    this.bodyText,
    this.mediaKey,
    this.templateKind,
    this.listingId,
    this.productId,
    this.quantityLabel,
    required this.expiresAt,
    this.viewed = false,
    this.reaction,
    this.createdAt,
  });

  factory StatusData.fromJson(Map<String, dynamic> j) {
    return StatusData(
      id: j['id'] as String? ?? '',
      author: FarmerIdentity.fromJson(
          (j['author'] as Map<String, dynamic>?) ?? const {}),
      statusType: j['status_type'] as String? ?? 'text',
      bodyText: j['body_text'] as String?,
      mediaKey: j['media_key'] as String?,
      templateKind: j['template_kind'] as String?,
      listingId: j['listing_id'] as String?,
      productId: j['product_id'] as String?,
      quantityLabel: j['quantity_label'] as String?,
      expiresAt: j['expires_at'] as String? ?? '',
      viewed: j['viewed'] == true,
      reaction: j['reaction'] as String?,
      createdAt: j['created_at'] as String?,
    );
  }

  final String id;
  final FarmerIdentity author;
  final String statusType;
  final String? bodyText;
  final String? mediaKey;
  final String? templateKind;
  final String? listingId;
  final String? productId;
  final String? quantityLabel;
  final String expiresAt;
  final bool viewed;
  final String? reaction;
  final String? createdAt;
}

class Opportunity {
  const Opportunity({
    required this.id,
    required this.title,
    this.description,
    this.product,
    this.quantityValue,
    this.unitCode,
    this.destinationRegion,
    this.requiredByDate,
    this.budgetMaxMinor,
    this.destinationDistrict,
    this.expiresAt,
    this.createdAt,
  });

  factory Opportunity.fromJson(Map<String, dynamic> j) {
    return Opportunity(
      id: j['id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      description: j['description'] as String?,
      product: j['product'] != null
          ? (j['product'] as Map<String, dynamic>)['name'] as String?
          : null,
      quantityValue: (j['quantity_value'] as num?)?.toDouble(),
      unitCode: j['unit_code'] as String?,
      destinationRegion: j['destination_region'] as String?,
      requiredByDate: j['required_by_date'] as String?,
      budgetMaxMinor: (j['budget_max_minor'] as num?)?.toInt(),
      destinationDistrict: j['destination_district'] as String?,
      expiresAt: j['expires_at'] as String?,
      createdAt: j['created_at'] as String?,
    );
  }

  final String id;
  final String title;
  final String? description;
  final String? product;
  final double? quantityValue;
  final String? unitCode;
  final String? destinationRegion;
  final String? destinationDistrict;
  final String? requiredByDate;
  final int? budgetMaxMinor;
  final String? expiresAt;
  final String? createdAt;
}
