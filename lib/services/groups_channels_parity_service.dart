import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../utils/date_time_utils.dart';
import 'auth_service.dart';
import 'chat_service.dart';

String? _parityNonEmpty(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  return s.isNotEmpty ? s : null;
}

int _parityInt(dynamic raw, {int defaultValue = 0}) {
  if (raw == null) return defaultValue;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString()) ?? defaultValue;
}

double _parityDouble(dynamic raw, {double defaultValue = 0.0}) {
  if (raw == null) return defaultValue;
  if (raw is double) return raw;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString()) ?? defaultValue;
}

bool _parityBool(dynamic raw, {bool defaultValue = false}) {
  if (raw == null) return defaultValue;
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  final s = raw.toString().trim().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return defaultValue;
}

/// A Telegram-style topic inside a Forum Supergroup.
class ForumTopic {
  final int id;
  final String chatId;
  final String title;
  final int iconColor;
  final String? iconEmoji;
  final bool isGeneral;
  final bool isClosed;
  final bool isPinned;
  final bool isHidden;
  final String? createdBy;
  final int unreadCount;
  final String? lastMessageId;
  final String? lastMessage;
  final String? lastMessageType;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderId;
  final String? lastMessageSenderName;

  const ForumTopic({
    required this.id,
    required this.chatId,
    required this.title,
    this.iconColor = 0xFF6FB9F0,
    this.iconEmoji,
    this.isGeneral = false,
    this.isClosed = false,
    this.isPinned = false,
    this.isHidden = false,
    this.createdBy,
    this.unreadCount = 0,
    this.lastMessageId,
    this.lastMessage,
    this.lastMessageType,
    this.lastMessageAt,
    this.lastMessageSenderId,
    this.lastMessageSenderName,
  });

  factory ForumTopic.fromJson(Map<String, dynamic> json) {
    return ForumTopic(
      id: _parityInt(json['id']),
      chatId: (json['chat_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      iconColor: _parityInt(json['icon_color'], defaultValue: 0xFF6FB9F0),
      iconEmoji: _parityNonEmpty(json['icon_emoji']),
      isGeneral: _parityBool(json['is_general']),
      isClosed: _parityBool(json['is_closed']),
      isPinned: _parityBool(json['is_pinned']),
      isHidden: _parityBool(json['is_hidden']),
      createdBy: _parityNonEmpty(json['created_by']),
      unreadCount: _parityInt(json['unread_count']),
      lastMessageId: _parityNonEmpty(json['last_message_id']),
      lastMessage: _parityNonEmpty(json['last_message']),
      lastMessageType: _parityNonEmpty(json['last_message_type']),
      lastMessageAt: DateTimeUtils.parseUtcDateTime(json['last_message_at']),
      lastMessageSenderId: _parityNonEmpty(json['last_message_sender_id']),
      lastMessageSenderName: _parityNonEmpty(json['last_message_sender_name']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id.toString(),
        'chat_id': chatId,
        'title': title,
        'icon_color': iconColor,
        if (iconEmoji != null) 'icon_emoji': iconEmoji,
        'is_general': isGeneral,
        'is_closed': isClosed,
        'is_pinned': isPinned,
        'is_hidden': isHidden,
        if (createdBy != null) 'created_by': createdBy,
        'unread_count': unreadCount,
        if (lastMessageId != null) 'last_message_id': lastMessageId,
        if (lastMessage != null) 'last_message': lastMessage,
        if (lastMessageType != null) 'last_message_type': lastMessageType,
        if (lastMessageAt != null)
          'last_message_at': lastMessageAt!.toUtc().toIso8601String(),
        if (lastMessageSenderId != null)
          'last_message_sender_id': lastMessageSenderId,
        if (lastMessageSenderName != null)
          'last_message_sender_name': lastMessageSenderName,
      };

  ForumTopic copyWith({
    int? id,
    String? chatId,
    String? title,
    int? iconColor,
    String? iconEmoji,
    bool clearIconEmoji = false,
    bool? isGeneral,
    bool? isClosed,
    bool? isPinned,
    bool? isHidden,
    String? createdBy,
    int? unreadCount,
    String? lastMessageId,
    String? lastMessage,
    String? lastMessageType,
    DateTime? lastMessageAt,
    String? lastMessageSenderId,
    String? lastMessageSenderName,
  }) {
    return ForumTopic(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      title: title ?? this.title,
      iconColor: iconColor ?? this.iconColor,
      iconEmoji: clearIconEmoji ? null : (iconEmoji ?? this.iconEmoji),
      isGeneral: isGeneral ?? this.isGeneral,
      isClosed: isClosed ?? this.isClosed,
      isPinned: isPinned ?? this.isPinned,
      isHidden: isHidden ?? this.isHidden,
      createdBy: createdBy ?? this.createdBy,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageSenderName:
          lastMessageSenderName ?? this.lastMessageSenderName,
    );
  }
}

/// Recent Actions (Admin Log) audit entry for a group or channel.
class AdminLogEvent {
  final int id;
  final String chatId;
  final String action;
  final String? actorId;
  final String actorName;
  final String actorUsername;
  final String? actorAvatar;
  final String? targetUserId;
  final String targetUserName;
  final String targetUserUsername;
  final String? targetUserAvatar;
  final String? targetMessageId;
  final Map<String, dynamic>? oldValue;
  final Map<String, dynamic>? newValue;
  final DateTime? createdAt;

  const AdminLogEvent({
    required this.id,
    required this.chatId,
    required this.action,
    this.actorId,
    this.actorName = '',
    this.actorUsername = '',
    this.actorAvatar,
    this.targetUserId,
    this.targetUserName = '',
    this.targetUserUsername = '',
    this.targetUserAvatar,
    this.targetMessageId,
    this.oldValue,
    this.newValue,
    this.createdAt,
  });

  factory AdminLogEvent.fromJson(Map<String, dynamic> json) {
    return AdminLogEvent(
      id: _parityInt(json['id']),
      chatId: (json['chat_id'] ?? '').toString(),
      action: (json['action'] ?? '').toString(),
      actorId: _parityNonEmpty(json['actor_id']),
      actorName: (json['actor_name'] ?? '').toString(),
      actorUsername: (json['actor_username'] ?? '').toString(),
      actorAvatar: _parityNonEmpty(json['actor_avatar']),
      targetUserId: _parityNonEmpty(json['target_user_id']),
      targetUserName: (json['target_user_name'] ?? '').toString(),
      targetUserUsername: (json['target_user_username'] ?? '').toString(),
      targetUserAvatar: _parityNonEmpty(json['target_user_avatar']),
      targetMessageId: _parityNonEmpty(json['target_message_id']),
      oldValue: json['old_value'] is Map
          ? Map<String, dynamic>.from(json['old_value'] as Map)
          : null,
      newValue: json['new_value'] is Map
          ? Map<String, dynamic>.from(json['new_value'] as Map)
          : null,
      createdAt: DateTimeUtils.parseUtcDateTime(json['created_at']),
    );
  }
}

/// Member who joined a chat via a specific invite link.
class InviteLinkImporter {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool viaJoinRequest;
  final DateTime? joinedAt;

  const InviteLinkImporter({
    required this.userId,
    this.username = '',
    this.displayName = '',
    this.avatarUrl,
    this.viaJoinRequest = false,
    this.joinedAt,
  });

  factory InviteLinkImporter.fromJson(Map<String, dynamic> json) {
    return InviteLinkImporter(
      userId: (json['user_id'] ?? json['id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      avatarUrl: _parityNonEmpty(json['avatar_url']),
      viaJoinRequest: _parityBool(json['via_join_request']),
      joinedAt: DateTimeUtils.parseUtcDateTime(json['joined_at']),
    );
  }
}

/// Identity peer available for "Send As" (personal account, anonymous group admin, or public/linked channel).
class SendAsPeer {
  final String peerType; // 'user' | 'group' | 'channel'
  final String id;
  final String? chatId;
  final String name;
  final String username;
  final String? avatarUrl;
  final bool isVerified;
  final bool isSelected;
  final int? subscriberCount;
  final int? memberCount;

  const SendAsPeer({
    required this.peerType,
    required this.id,
    this.chatId,
    required this.name,
    this.username = '',
    this.avatarUrl,
    this.isVerified = false,
    this.isSelected = false,
    this.subscriberCount,
    this.memberCount,
  });

  bool get isUser => peerType == 'user';
  bool get isGroupAnon => peerType == 'group';
  bool get isChannel => peerType == 'channel';

  bool matchesSelection({
    String? selectedSendAsMode,
    String? selectedSendAsChatId,
  }) {
    final mode = selectedSendAsMode?.trim() ?? '';
    final cid = selectedSendAsChatId?.trim() ?? '';
    if (mode == 'group') return isGroupAnon;
    if (mode == 'channel') {
      return isChannel && (cid.isEmpty || (chatId ?? id) == cid);
    }
    if (mode == 'user') return isUser;
    if (cid.isNotEmpty) {
      return isChannel && (chatId ?? id) == cid;
    }
    return isSelected;
  }

  SendAsPeer copyWith({
    String? peerType,
    String? id,
    String? chatId,
    String? name,
    String? username,
    String? avatarUrl,
    bool? isVerified,
    bool? isSelected,
    int? subscriberCount,
    int? memberCount,
  }) {
    return SendAsPeer(
      peerType: peerType ?? this.peerType,
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      name: name ?? this.name,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isVerified: isVerified ?? this.isVerified,
      isSelected: isSelected ?? this.isSelected,
      subscriberCount: subscriberCount ?? this.subscriberCount,
      memberCount: memberCount ?? this.memberCount,
    );
  }

  factory SendAsPeer.fromJson(Map<String, dynamic> json) {
    return SendAsPeer(
      peerType: (json['peer_type'] ?? 'user').toString(),
      id: (json['id'] ?? '').toString(),
      chatId: _parityNonEmpty(json['chat_id']),
      name: (json['name'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      avatarUrl: _parityNonEmpty(json['avatar_url']),
      isVerified: _parityBool(json['is_verified']),
      isSelected: _parityBool(json['is_selected']),
      subscriberCount: json['subscriber_count'] != null
          ? _parityInt(json['subscriber_count'])
          : null,
      memberCount: json['member_count'] != null
          ? _parityInt(json['member_count'])
          : null,
    );
  }
}

/// Result returned by `GET /api/chats/:id/send-as-peers`.
class SendAsPeersResult {
  final List<SendAsPeer> peers;
  final String? selectedSendAsChatId;
  final String selectedSendAsMode; // 'user' | 'group' | 'channel'

  const SendAsPeersResult({
    this.peers = const <SendAsPeer>[],
    this.selectedSendAsChatId,
    this.selectedSendAsMode = 'user',
  });

  SendAsPeer? get activePeer {
    if (peers.isEmpty) return null;
    if (selectedSendAsMode == 'group') {
      for (final p in peers) {
        if (p.isGroupAnon) return p;
      }
    }
    if (selectedSendAsMode == 'channel' ||
        (selectedSendAsChatId != null && selectedSendAsChatId!.isNotEmpty)) {
      for (final p in peers) {
        if (p.isChannel &&
            (p.chatId == selectedSendAsChatId || p.id == selectedSendAsChatId)) {
          return p;
        }
      }
    }
    if (selectedSendAsMode == 'user') {
      for (final p in peers) {
        if (p.isUser) return p;
      }
    }
    for (final p in peers) {
      if (p.isSelected) return p;
    }
    return peers.first;
  }
}

/// One day point in channel membership/post growth chart.
class ChannelDailyGrowthPoint {
  final String date;
  final int joined;
  final int left;
  final int net;
  final int posts;
  final int views;

  const ChannelDailyGrowthPoint({
    required this.date,
    this.joined = 0,
    this.left = 0,
    this.net = 0,
    this.posts = 0,
    this.views = 0,
  });

  factory ChannelDailyGrowthPoint.fromJson(Map<String, dynamic> json) {
    return ChannelDailyGrowthPoint(
      date: (json['date'] ?? '').toString(),
      joined: _parityInt(json['joined']),
      left: _parityInt(json['left']),
      net: _parityInt(json['net']),
      posts: _parityInt(json['posts']),
      views: _parityInt(json['views']),
    );
  }
}

/// Summary of a top performing channel post.
class ChannelTopPost {
  final String messageId;
  final String content;
  final String messageType;
  final int viewsCount;
  final int forwardsCount;
  final int commentsCount;
  final int reactionsCount;
  final DateTime? createdAt;

  const ChannelTopPost({
    required this.messageId,
    this.content = '',
    this.messageType = 'text',
    this.viewsCount = 0,
    this.forwardsCount = 0,
    this.commentsCount = 0,
    this.reactionsCount = 0,
    this.createdAt,
  });

  factory ChannelTopPost.fromJson(Map<String, dynamic> json) {
    return ChannelTopPost(
      messageId: (json['message_id'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      messageType: (json['message_type'] ?? 'text').toString(),
      viewsCount: _parityInt(json['views_count']),
      forwardsCount: _parityInt(json['forwards_count']),
      commentsCount: _parityInt(json['comments_count']),
      reactionsCount: _parityInt(json['reactions_count']),
      createdAt: DateTimeUtils.parseUtcDateTime(json['created_at']),
    );
  }
}

/// Channel-wide statistics from `GET /api/chats/:id/stats`.
class ChannelStats {
  final int subscribersCount;
  final double notificationsEnabledPercent;
  final int joined7d;
  final int left7d;
  final int joined30d;
  final int left30d;
  final int postsCount;
  final int totalViews;
  final double avgViewsPerPost;
  final int totalForwards;
  final int totalComments;
  final int totalReactions;
  final List<ChannelDailyGrowthPoint> dailyGrowth;
  final List<ChannelTopPost> topPosts;

  const ChannelStats({
    this.subscribersCount = 0,
    this.notificationsEnabledPercent = 0,
    this.joined7d = 0,
    this.left7d = 0,
    this.joined30d = 0,
    this.left30d = 0,
    this.postsCount = 0,
    this.totalViews = 0,
    this.avgViewsPerPost = 0,
    this.totalForwards = 0,
    this.totalComments = 0,
    this.totalReactions = 0,
    this.dailyGrowth = const [],
    this.topPosts = const [],
  });

  factory ChannelStats.fromJson(Map<String, dynamic> json) {
    final map = json['stats'] is Map
        ? Map<String, dynamic>.from(json['stats'] as Map)
        : json;
    final growth = <ChannelDailyGrowthPoint>[];
    if (map['daily_growth'] is List) {
      for (final item in map['daily_growth'] as List) {
        if (item is Map) {
          growth.add(
            ChannelDailyGrowthPoint.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final tops = <ChannelTopPost>[];
    if (map['top_posts'] is List) {
      for (final item in map['top_posts'] as List) {
        if (item is Map) {
          tops.add(ChannelTopPost.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return ChannelStats(
      subscribersCount: _parityInt(map['subscribers_count']),
      notificationsEnabledPercent:
          _parityDouble(map['notifications_enabled_percent']),
      joined7d: _parityInt(map['joined_7d']),
      left7d: _parityInt(map['left_7d']),
      joined30d: _parityInt(map['joined_30d']),
      left30d: _parityInt(map['left_30d']),
      postsCount: _parityInt(map['posts_count']),
      totalViews: _parityInt(map['total_views']),
      avgViewsPerPost: _parityDouble(map['avg_views_per_post']),
      totalForwards: _parityInt(map['total_forwards']),
      totalComments: _parityInt(map['total_comments']),
      totalReactions: _parityInt(map['total_reactions']),
      dailyGrowth: growth,
      topPosts: tops,
    );
  }
}

/// Emoji breakdown entry in [PostStats].
class PostReactionBreakdownItem {
  final String emoji;
  final int count;

  const PostReactionBreakdownItem({required this.emoji, required this.count});

  factory PostReactionBreakdownItem.fromJson(Map<String, dynamic> json) {
    return PostReactionBreakdownItem(
      emoji: (json['emoji'] ?? '').toString(),
      count: _parityInt(json['count']),
    );
  }
}

/// Single post reach & engagement stats from `GET /api/chats/:id/messages/:messageId/stats`.
class PostStats {
  final String chatId;
  final String messageId;
  final int viewsCount;
  final int uniqueViewers;
  final int forwardsCount;
  final int commentsCount;
  final int reactionsTotal;
  final List<PostReactionBreakdownItem> reactionsBreakdown;
  final int subscribersCount;
  final double engagementRate;
  final DateTime? createdAt;

  const PostStats({
    this.chatId = '',
    this.messageId = '',
    this.viewsCount = 0,
    this.uniqueViewers = 0,
    this.forwardsCount = 0,
    this.commentsCount = 0,
    this.reactionsTotal = 0,
    this.reactionsBreakdown = const [],
    this.subscribersCount = 0,
    this.engagementRate = 0,
    this.createdAt,
  });

  factory PostStats.fromJson(Map<String, dynamic> json) {
    final map = json['stats'] is Map
        ? Map<String, dynamic>.from(json['stats'] as Map)
        : json;
    final breakdown = <PostReactionBreakdownItem>[];
    if (map['reactions_breakdown'] is List) {
      for (final item in map['reactions_breakdown'] as List) {
        if (item is Map) {
          breakdown.add(
            PostReactionBreakdownItem.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return PostStats(
      chatId: (map['chat_id'] ?? '').toString(),
      messageId: (map['message_id'] ?? '').toString(),
      viewsCount: _parityInt(map['views_count']),
      uniqueViewers: _parityInt(map['unique_viewers']),
      forwardsCount: _parityInt(map['forwards_count']),
      commentsCount: _parityInt(map['comments_count']),
      reactionsTotal: _parityInt(map['reactions_total']),
      reactionsBreakdown: breakdown,
      subscribersCount: _parityInt(map['subscribers_count']),
      engagementRate: _parityDouble(map['engagement_rate']),
      createdAt: DateTimeUtils.parseUtcDateTime(map['created_at']),
    );
  }
}

/// Similar public channel suggestion from `GET /api/chats/:id/similar-channels`.
class SimilarChannelItem {
  final String id;
  final String name;
  final String username;
  final String description;
  final String? avatarUrl;
  final bool isVerified;
  final int subscriberCount;
  final int overlapCount;
  final bool isMember;

  const SimilarChannelItem({
    required this.id,
    required this.name,
    this.username = '',
    this.description = '',
    this.avatarUrl,
    this.isVerified = false,
    this.subscriberCount = 0,
    this.overlapCount = 0,
    this.isMember = false,
  });

  SimilarChannelItem copyWith({bool? isMember, int? subscriberCount}) {
    return SimilarChannelItem(
      id: id,
      name: name,
      username: username,
      description: description,
      avatarUrl: avatarUrl,
      isVerified: isVerified,
      subscriberCount: subscriberCount ?? this.subscriberCount,
      overlapCount: overlapCount,
      isMember: isMember ?? this.isMember,
    );
  }

  factory SimilarChannelItem.fromJson(Map<String, dynamic> json) {
    return SimilarChannelItem(
      id: (json['id'] ?? json['chat_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      avatarUrl: _parityNonEmpty(json['avatar_url']),
      isVerified: _parityBool(json['is_verified']),
      subscriberCount:
          _parityInt(json['subscriber_count'] ?? json['member_count']),
      overlapCount: _parityInt(json['overlap_count']),
      isMember: _parityBool(json['is_member']),
    );
  }
}

/// Paginated & privacy-aware member list result (`GET /api/chats/:id/members`).
class MembersPageResult {
  final List<ChatParticipant> members;
  final bool participantsHidden;
  final int total;
  final bool hasMore;

  const MembersPageResult({
    this.members = const [],
    this.participantsHidden = false,
    this.total = 0,
    this.hasMore = false,
  });

  factory MembersPageResult.fromJson(Map<String, dynamic> json) {
    final list = <ChatParticipant>[];
    if (json['members'] is List) {
      for (final item in json['members'] as List) {
        if (item is Map) {
          list.add(ChatParticipant.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return MembersPageResult(
      members: list,
      participantsHidden: _parityBool(json['participants_hidden']),
      total: _parityInt(json['total'], defaultValue: list.length),
      hasMore: _parityBool(json['has_more']),
    );
  }
}

/// Detailed result from `POST /api/chats/:id/members`.
class AddMembersResult {
  final bool success;
  final List<String> addedUserIds;
  final List<String> skippedUserIds;
  final List<String> skippedPrivacyUserIds;
  final String? message;

  const AddMembersResult({
    this.success = false,
    this.addedUserIds = const [],
    this.skippedUserIds = const [],
    this.skippedPrivacyUserIds = const [],
    this.message,
  });

  factory AddMembersResult.fromJson(
    Map<String, dynamic> json, {
    bool success = true,
  }) {
    List<String> parseIds(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    return AddMembersResult(
      success: success && json['success'] != false,
      addedUserIds: parseIds(json['added_user_ids']),
      skippedUserIds: parseIds(json['skipped_user_ids']),
      skippedPrivacyUserIds: parseIds(json['skipped_privacy_user_ids']),
      message: _parityNonEmpty(json['message']),
    );
  }
}

/// Paginated banned users result (`GET /api/chats/:id/banned`).
class BannedMembersPageResult {
  final List<ChatParticipant> bannedMembers;
  final bool hasMore;

  const BannedMembersPageResult({
    this.bannedMembers = const [],
    this.hasMore = false,
  });

  factory BannedMembersPageResult.fromJson(Map<String, dynamic> json) {
    final rawList = (json['banned_members'] ?? json['members']) as List?;
    final list = <ChatParticipant>[];
    if (rawList != null) {
      for (final item in rawList) {
        if (item is Map) {
          list.add(ChatParticipant.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return BannedMembersPageResult(
      bannedMembers: list,
      hasMore: _parityBool(json['has_more']),
    );
  }
}

/// Unread mentions or reactions jump-list result.
class UnreadBadgeItemsResult {
  final int count;
  final List<String> messageIds;
  final List<Map<String, dynamic>> items;

  const UnreadBadgeItemsResult({
    this.count = 0,
    this.messageIds = const [],
    this.items = const [],
  });

  factory UnreadBadgeItemsResult.fromJson(
    Map<String, dynamic> json, {
    required String itemsKey,
  }) {
    final ids = <String>[];
    if (json['message_ids'] is List) {
      for (final id in json['message_ids'] as List) {
        final s = id.toString().trim();
        if (s.isNotEmpty) ids.add(s);
      }
    }
    final parsedItems = <Map<String, dynamic>>[];
    if (json[itemsKey] is List) {
      for (final item in json[itemsKey] as List) {
        if (item is Map) {
          parsedItems.add(Map<String, dynamic>.from(item));
        }
      }
    }
    return UnreadBadgeItemsResult(
      count: _parityInt(json['count'], defaultValue: ids.length),
      messageIds: ids,
      items: parsedItems,
    );
  }
}

/// REST client for Wave 3B Telegram Groups, Forums, Channels & Stats endpoints.
class GroupsChannelsParityService {
  GroupsChannelsParityService._();

  static Future<Map<String, String>?> _headers() async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) return null;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static String _errMsg(dynamic data, String fallback) {
    if (data is Map) {
      final msg = data['message']?.toString() ?? data['description']?.toString();
      if (msg != null && msg.trim().isNotEmpty) return msg;
    }
    return fallback;
  }

  // ==================== FORUM TOPICS ====================

  static Future<({bool isForum, List<ForumTopic> topics})> getTopics(
    String chatId, {
    String? query,
  }) async {
    try {
      final headers = await _headers();
      if (headers == null) return (isForum: false, topics: <ForumTopic>[]);
      var url = '${AppConfig.baseUrl}/api/chats/$chatId/topics';
      if (query != null && query.trim().isNotEmpty) {
        url += '?q=${Uri.encodeQueryComponent(query.trim())}';
      }
      final resp = await http.get(Uri.parse(url), headers: headers);
      final data = _decode(resp.body);
      if (resp.statusCode == 200 && data is Map && data['success'] == true) {
        final topics = <ForumTopic>[];
        if (data['topics'] is List) {
          for (final item in data['topics'] as List) {
            if (item is Map) {
              topics.add(ForumTopic.fromJson(Map<String, dynamic>.from(item)));
            }
          }
        }
        return (isForum: _parityBool(data['is_forum']), topics: topics);
      }
    } catch (e) {
      debugPrint('getTopics error: $e');
    }
    return (isForum: false, topics: <ForumTopic>[]);
  }

  static Future<ForumTopic?> createTopic(
    String chatId, {
    required String title,
    int? iconColor,
    String? iconEmoji,
  }) async {
    try {
      final headers = await _headers();
      if (headers == null) return null;
      final resp = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/topics'),
        headers: headers,
        body: jsonEncode({
          'title': title.trim(),
          if (iconColor != null) 'icon_color': iconColor,
          if (iconEmoji != null && iconEmoji.isNotEmpty) 'icon_emoji': iconEmoji,
        }),
      );
      final data = _decode(resp.body);
      if ((resp.statusCode == 200 || resp.statusCode == 201) &&
          data is Map &&
          data['success'] == true &&
          data['topic'] is Map) {
        return ForumTopic.fromJson(
          Map<String, dynamic>.from(data['topic'] as Map),
        );
      }
    } catch (e) {
      debugPrint('createTopic error: $e');
    }
    return null;
  }

  static Future<ForumTopic?> updateTopic(
    String chatId,
    int topicId, {
    String? title,
    int? iconColor,
    String? iconEmoji,
    bool? isClosed,
    bool? isPinned,
    bool? isHidden,
  }) async {
    try {
      final headers = await _headers();
      if (headers == null) return null;
      final body = <String, dynamic>{
        if (title != null) 'title': title.trim(),
        if (iconColor != null) 'icon_color': iconColor,
        if (iconEmoji != null) 'icon_emoji': iconEmoji,
        if (isClosed != null) 'is_closed': isClosed,
        if (isPinned != null) 'is_pinned': isPinned,
        if (isHidden != null) 'is_hidden': isHidden,
      };
      final resp = await http.patch(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/topics/$topicId'),
        headers: headers,
        body: jsonEncode(body),
      );
      final data = _decode(resp.body);
      if (resp.statusCode == 200 &&
          data is Map &&
          data['success'] == true &&
          data['topic'] is Map) {
        return ForumTopic.fromJson(
          Map<String, dynamic>.from(data['topic'] as Map),
        );
      }
    } catch (e) {
      debugPrint('updateTopic error: $e');
    }
    return null;
  }

  static Future<bool> deleteTopic(String chatId, int topicId) async {
    try {
      final headers = await _headers();
      if (headers == null) return false;
      final resp = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/topics/$topicId'),
        headers: headers,
      );
      final data = _decode(resp.body);
      return resp.statusCode == 200 && data is Map && data['success'] == true;
    } catch (e) {
      debugPrint('deleteTopic error: $e');
      return false;
    }
  }

  // ==================== ADMIN LOG & INVITE IMPORTERS ====================

  static Future<({List<AdminLogEvent> events, int hours, bool hasMore})>
      getAdminLog(
    String chatId, {
    String? action,
    String? category,
    String? actorId,
    String? query,
    int hours = 48,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final headers = await _headers();
      if (headers == null) {
        return (events: <AdminLogEvent>[], hours: hours, hasMore: false);
      }
      final params = <String, String>{
        'hours': '$hours',
        'limit': '$limit',
        'offset': '$offset',
        if (action != null && action.isNotEmpty) 'action': action,
        if (category != null && category.trim().isNotEmpty)
          'category': category.trim(),
        if (actorId != null && actorId.isNotEmpty) 'actor_id': actorId,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      };
      final uri = Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/admin-log')
          .replace(queryParameters: params);
      final resp = await http.get(uri, headers: headers);
      final data = _decode(resp.body);
      if (resp.statusCode == 200 && data is Map && data['success'] == true) {
        final events = <AdminLogEvent>[];
        if (data['events'] is List) {
          for (final item in data['events'] as List) {
            if (item is Map) {
              events.add(
                AdminLogEvent.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
        return (
          events: events,
          hours: _parityInt(data['hours'], defaultValue: hours),
          hasMore: _parityBool(data['has_more']),
        );
      }
    } catch (e) {
      debugPrint('getAdminLog error: $e');
    }
    return (events: <AdminLogEvent>[], hours: hours, hasMore: false);
  }

  static Future<
      ({
        int total,
        List<InviteLinkImporter> importers,
        bool hasMore,
      })> getInviteLinkImporters(
    String chatId,
    int linkId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final headers = await _headers();
      if (headers == null) {
        return (total: 0, importers: <InviteLinkImporter>[], hasMore: false);
      }
      final uri = Uri.parse(
        '${AppConfig.baseUrl}/api/chats/$chatId/invite-links/$linkId/importers',
      ).replace(queryParameters: {
        'limit': '$limit',
        'offset': '$offset',
      });
      final resp = await http.get(uri, headers: headers);
      final data = _decode(resp.body);
      if (resp.statusCode == 200 && data is Map && data['success'] == true) {
        final list = <InviteLinkImporter>[];
        if (data['importers'] is List) {
          for (final item in data['importers'] as List) {
            if (item is Map) {
              list.add(
                InviteLinkImporter.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
        final total = _parityInt(data['total'], defaultValue: list.length);
        final hasMore = data.containsKey('has_more')
            ? _parityBool(data['has_more'])
            : (offset + list.length < total);
        return (total: total, importers: list, hasMore: hasMore);
      }
    } catch (e) {
      debugPrint('getInviteLinkImporters error: $e');
    }
    return (total: 0, importers: <InviteLinkImporter>[], hasMore: false);
  }

  // ==================== SEND AS CHANNEL ====================

  static Future<SendAsPeersResult> getSendAsPeers(String chatId) async {
    try {
      final headers = await _headers();
      if (headers == null) {
        return const SendAsPeersResult();
      }
      final resp = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/send-as-peers'),
        headers: headers,
      );
      final data = _decode(resp.body);
      if (resp.statusCode == 200 && data is Map && data['success'] == true) {
        final peers = <SendAsPeer>[];
        if (data['peers'] is List) {
          for (final item in data['peers'] as List) {
            if (item is Map) {
              peers.add(SendAsPeer.fromJson(Map<String, dynamic>.from(item)));
            }
          }
        }
        final selectedChatId = _parityNonEmpty(data['selected_send_as_chat_id']);
        final rawMode = _parityNonEmpty(data['selected_send_as_mode']);
        String resolvedMode;
        if (rawMode == 'user' || rawMode == 'group' || rawMode == 'channel') {
          resolvedMode = rawMode!;
        } else if (selectedChatId != null && selectedChatId.isNotEmpty) {
          resolvedMode = 'channel';
        } else if (peers.any((p) => p.isSelected && p.isGroupAnon)) {
          resolvedMode = 'group';
        } else if (peers.any((p) => p.isSelected && p.isChannel)) {
          resolvedMode = 'channel';
        } else {
          resolvedMode = 'user';
        }
        return SendAsPeersResult(
          peers: peers,
          selectedSendAsChatId: selectedChatId,
          selectedSendAsMode: resolvedMode,
        );
      }
    } catch (e) {
      debugPrint('getSendAsPeers error: $e');
    }
    return const SendAsPeersResult();
  }

  static Future<bool> setSendAsPeer(
    String chatId,
    String? sendAsChatId, {
    String? sendAsMode,
  }) async {
    try {
      final headers = await _headers();
      if (headers == null) return false;
      final trimmedChatId = sendAsChatId?.trim() ?? '';
      final hasChatId = trimmedChatId.isNotEmpty;
      final trimmedMode = sendAsMode?.trim() ?? '';
      final effectiveMode = (trimmedMode == 'user' ||
              trimmedMode == 'group' ||
              trimmedMode == 'channel')
          ? trimmedMode
          : (hasChatId ? 'channel' : 'user');
      final resp = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/send-as'),
        headers: headers,
        body: jsonEncode({
          'send_as_mode': effectiveMode,
          'send_as_chat_id': (effectiveMode == 'channel' && hasChatId)
              ? (int.tryParse(trimmedChatId) ?? trimmedChatId)
              : null,
        }),
      );
      final data = _decode(resp.body);
      return resp.statusCode == 200 && data is Map && data['success'] == true;
    } catch (e) {
      debugPrint('setSendAsPeer error: $e');
      return false;
    }
  }

  // ==================== UNREAD MENTIONS & REACTIONS ====================

  static Future<UnreadBadgeItemsResult> getUnreadMentions(
    String chatId,
  ) async {
    try {
      final headers = await _headers();
      if (headers == null) return const UnreadBadgeItemsResult();
      final resp = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/unread-mentions'),
        headers: headers,
      );
      final data = _decode(resp.body);
      if (resp.statusCode == 200 && data is Map && data['success'] == true) {
        return UnreadBadgeItemsResult.fromJson(
          Map<String, dynamic>.from(data),
          itemsKey: 'mentions',
        );
      }
    } catch (e) {
      debugPrint('getUnreadMentions error: $e');
    }
    return const UnreadBadgeItemsResult();
  }

  static Future<int?> markUnreadMentionsRead(
    String chatId, {
    List<String>? messageIds,
    String? upToMessageId,
  }) async {
    try {
      final headers = await _headers();
      if (headers == null) return null;
      final body = <String, dynamic>{
        if (messageIds != null && messageIds.isNotEmpty)
          'message_ids':
              messageIds.map((id) => int.tryParse(id) ?? id).toList(),
        if (upToMessageId != null && upToMessageId.isNotEmpty)
          'up_to_message_id': int.tryParse(upToMessageId) ?? upToMessageId,
      };
      final resp = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/api/chats/$chatId/unread-mentions/read',
        ),
        headers: headers,
        body: jsonEncode(body),
      );
      final data = _decode(resp.body);
      if (resp.statusCode == 200 && data is Map && data['success'] == true) {
        return _parityInt(data['unread_mentions_count']);
      }
    } catch (e) {
      debugPrint('markUnreadMentionsRead error: $e');
    }
    return null;
  }

  static Future<UnreadBadgeItemsResult> getUnreadReactions(
    String chatId,
  ) async {
    try {
      final headers = await _headers();
      if (headers == null) return const UnreadBadgeItemsResult();
      final resp = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/unread-reactions'),
        headers: headers,
      );
      final data = _decode(resp.body);
      if (resp.statusCode == 200 && data is Map && data['success'] == true) {
        return UnreadBadgeItemsResult.fromJson(
          Map<String, dynamic>.from(data),
          itemsKey: 'reactions',
        );
      }
    } catch (e) {
      debugPrint('getUnreadReactions error: $e');
    }
    return const UnreadBadgeItemsResult();
  }

  static Future<int?> markUnreadReactionsRead(
    String chatId, {
    List<String>? messageIds,
    String? upToMessageId,
  }) async {
    try {
      final headers = await _headers();
      if (headers == null) return null;
      final body = <String, dynamic>{
        if (messageIds != null && messageIds.isNotEmpty)
          'message_ids':
              messageIds.map((id) => int.tryParse(id) ?? id).toList(),
        if (upToMessageId != null && upToMessageId.isNotEmpty)
          'up_to_message_id': int.tryParse(upToMessageId) ?? upToMessageId,
      };
      final resp = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/api/chats/$chatId/unread-reactions/read',
        ),
        headers: headers,
        body: jsonEncode(body),
      );
      final data = _decode(resp.body);
      if (resp.statusCode == 200 && data is Map && data['success'] == true) {
        return _parityInt(data['unread_reactions_count']);
      }
    } catch (e) {
      debugPrint('markUnreadReactionsRead error: $e');
    }
    return null;
  }

  // ==================== STATS & SIMILAR CHANNELS ====================

  static Future<ChannelStats?> getChannelStats(String chatId) async {
    try {
      final headers = await _headers();
      if (headers == null) return null;
      final resp = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/stats'),
        headers: headers,
      );
      final data = _decode(resp.body);
      if (resp.statusCode == 200 && data is Map && data['success'] == true) {
        return ChannelStats.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      debugPrint('getChannelStats error: $e');
    }
    return null;
  }

  static Future<PostStats?> getPostStats(
    String chatId,
    String messageId,
  ) async {
    try {
      final headers = await _headers();
      if (headers == null) return null;
      final resp = await http.get(
        Uri.parse(
          '${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/stats',
        ),
        headers: headers,
      );
      final data = _decode(resp.body);
      if (resp.statusCode == 200 && data is Map && data['success'] == true) {
        return PostStats.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      debugPrint('getPostStats error: $e');
    }
    return null;
  }

  static Future<List<SimilarChannelItem>> getSimilarChannels(
    String chatId, {
    int limit = 20,
  }) async {
    try {
      final headers = await _headers();
      if (headers == null) return [];
      final resp = await http.get(
        Uri.parse(
          '${AppConfig.baseUrl}/api/chats/$chatId/similar-channels?limit=$limit',
        ),
        headers: headers,
      );
      final data = _decode(resp.body);
      if (resp.statusCode == 200 && data is Map && data['success'] == true) {
        final result = <SimilarChannelItem>[];
        if (data['channels'] is List) {
          for (final item in data['channels'] as List) {
            if (item is Map) {
              result.add(
                SimilarChannelItem.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
        return result;
      }
    } catch (e) {
      debugPrint('getSimilarChannels error: $e');
    }
    return [];
  }

  // ==================== MEMBERS & BANNED UPGRADES ====================

  static Future<MembersPageResult> getMembersFiltered(
    String chatId, {
    String? query,
    String filter = 'all',
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final headers = await _headers();
      if (headers == null) return const MembersPageResult();
      final params = <String, String>{
        'filter': filter,
        'limit': '$limit',
        'offset': '$offset',
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      };
      final uri = Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/members')
          .replace(queryParameters: params);
      final resp = await http.get(uri, headers: headers);
      final data = _decode(resp.body);
      if (resp.statusCode == 200 && data is Map && data['success'] != false) {
        return MembersPageResult.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      debugPrint('getMembersFiltered error: $e');
    }
    return const MembersPageResult();
  }

  static Future<AddMembersResult> addMembersDetailed(
    String chatId,
    List<String> userIds,
  ) async {
    try {
      final headers = await _headers();
      if (headers == null) {
        return const AddMembersResult(
          success: false,
          message: 'Not authenticated',
        );
      }
      final resp = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/members'),
        headers: headers,
        body: jsonEncode({
          'user_ids': userIds.map((id) => int.tryParse(id) ?? id).toList(),
        }),
      );
      final data = _decode(resp.body);
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final ok = resp.statusCode >= 200 &&
            resp.statusCode < 300 &&
            map['success'] != false;
        return AddMembersResult.fromJson(map, success: ok);
      }
      return AddMembersResult(
        success: false,
        message: _errMsg(data, 'Не удалось добавить участников'),
      );
    } catch (e) {
      debugPrint('addMembersDetailed error: $e');
      return AddMembersResult(success: false, message: 'Network error: $e');
    }
  }

  static Future<BannedMembersPageResult> getBannedMembersPaged(
    String chatId, {
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final headers = await _headers();
      if (headers == null) return const BannedMembersPageResult();
      final params = <String, String>{
        'limit': '$limit',
        'offset': '$offset',
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      };
      final uri = Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/banned')
          .replace(queryParameters: params);
      final resp = await http.get(uri, headers: headers);
      final data = _decode(resp.body);
      if (resp.statusCode == 200 && data is Map && data['success'] != false) {
        return BannedMembersPageResult.fromJson(
          Map<String, dynamic>.from(data),
        );
      }
    } catch (e) {
      debugPrint('getBannedMembersPaged error: $e');
    }
    return const BannedMembersPageResult();
  }
}
