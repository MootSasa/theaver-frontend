import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'database/app_database.dart';
import '../config/app_config.dart';

/// Unified peer item returned by `GET /api/search` in `my_peers` and `global_peers`.
class SearchPeer {
  final String peerType; // 'user' | 'group' | 'channel'
  final String id;
  final String? chatId;
  final String name;
  final String username;
  final String description;
  final String? avatarUrl;
  final bool isBot;
  final bool isVerified;
  final bool isPublic;
  final int memberCount;
  final bool isMember;

  const SearchPeer({
    required this.peerType,
    required this.id,
    this.chatId,
    required this.name,
    this.username = '',
    this.description = '',
    this.avatarUrl,
    this.isBot = false,
    this.isVerified = false,
    this.isPublic = false,
    this.memberCount = 0,
    this.isMember = false,
  });

  bool get isUser => peerType == 'user';
  bool get isGroup => peerType == 'group';
  bool get isChannel => peerType == 'channel';

  /// Alias for [peerType] (`'user'`, `'group'`, `'channel'`).
  String get type => peerType;

  /// Alias for [name].
  String get title => name;

  SearchPeer copyWith({
    String? peerType,
    String? id,
    String? chatId,
    String? name,
    String? username,
    String? description,
    String? avatarUrl,
    bool? isBot,
    bool? isVerified,
    bool? isPublic,
    int? memberCount,
    bool? isMember,
  }) {
    return SearchPeer(
      peerType: peerType ?? this.peerType,
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      name: name ?? this.name,
      username: username ?? this.username,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isBot: isBot ?? this.isBot,
      isVerified: isVerified ?? this.isVerified,
      isPublic: isPublic ?? this.isPublic,
      memberCount: memberCount ?? this.memberCount,
      isMember: isMember ?? this.isMember,
    );
  }

  SearchResultUser toUser({bool isMyPeer = false}) =>
      SearchResultUser.fromPeer(this, isMyPeer: isMyPeer);

  SearchResultGroup toGroup() => SearchResultGroup.fromPeer(this);

  SearchResultChannel toChannel() => SearchResultChannel.fromPeer(this);

  factory SearchPeer.fromJson(Map<String, dynamic> json) {
    final rawAvatar = json['avatar_url']?.toString().trim();
    final rawChatId = json['chat_id']?.toString().trim();
    return SearchPeer(
      peerType: (json['peer_type'] ?? json['chat_type'] ?? 'user').toString(),
      id: (json['id'] ?? '').toString(),
      chatId: (rawChatId != null && rawChatId.isNotEmpty) ? rawChatId : null,
      name: (json['name'] ?? json['display_name'] ?? json['username'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      avatarUrl: (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
      isBot: json['is_bot'] == true,
      isVerified: json['is_verified'] == true,
      isPublic: json['is_public'] == true,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      isMember: json['is_member'] == true,
    );
  }
}

/// Unified response from `GET /api/search`.
class UnifiedSearchResult {
  static const UnifiedSearchResult empty = UnifiedSearchResult();

  final String query;
  final String type;
  final List<SearchPeer> myPeers;
  final List<SearchPeer> globalPeers;
  final List<SearchResultMessage> messages;

  const UnifiedSearchResult({
    this.query = '',
    this.type = 'all',
    this.myPeers = const [],
    this.globalPeers = const [],
    this.messages = const [],
  });

  bool get isEmpty =>
      myPeers.isEmpty && globalPeers.isEmpty && messages.isEmpty;

  factory UnifiedSearchResult.fromJson(Map<String, dynamic> json) {
    final myRaw = json['my_peers'] as List<dynamic>? ?? const [];
    final globalRaw = json['global_peers'] as List<dynamic>? ?? const [];
    final msgRaw = json['messages'] as List<dynamic>? ?? const [];

    return UnifiedSearchResult(
      query: (json['query'] ?? '').toString(),
      type: (json['type'] ?? 'all').toString(),
      myPeers: myRaw
          .whereType<Map>()
          .map((e) => SearchPeer.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      globalPeers: globalRaw
          .whereType<Map>()
          .map((e) => SearchPeer.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      messages: msgRaw
          .whereType<Map>()
          .map((e) => SearchResultMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// SearchResultUser represents a user or bot in search results.
class SearchResultUser {
  final String id;
  final String name;
  final String email;
  final String username;
  final String? avatarUrl;
  final String? chatId;
  final bool isBot;
  final bool isVerified;
  final bool isMyPeer;

  SearchResultUser({
    required this.id,
    required this.name,
    required this.email,
    required this.username,
    this.avatarUrl,
    this.chatId,
    this.isBot = false,
    this.isVerified = false,
    this.isMyPeer = false,
  });

  factory SearchResultUser.fromJson(Map<String, dynamic> json) {
    final rawAvatar = json['avatar_url']?.toString().trim();
    final rawChatId = json['chat_id']?.toString().trim();
    return SearchResultUser(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? json['display_name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      avatarUrl: (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
      chatId: (rawChatId != null && rawChatId.isNotEmpty) ? rawChatId : null,
      isBot: json['is_bot'] == true,
      isVerified: json['is_verified'] == true,
      isMyPeer: json['is_member'] == true,
    );
  }

  factory SearchResultUser.fromPeer(SearchPeer peer, {bool isMyPeer = false}) {
    return SearchResultUser(
      id: peer.id,
      name: peer.name,
      email: '',
      username: peer.username,
      avatarUrl: peer.avatarUrl,
      chatId: peer.chatId,
      isBot: peer.isBot,
      isVerified: peer.isVerified,
      isMyPeer: isMyPeer || peer.isMember,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResultUser &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// SearchResultGroup represents a group in search results.
class SearchResultGroup {
  final String id;
  final String name;
  final String description;
  final String username;
  final String? avatarUrl;
  final bool isPublic;
  final int memberCount;
  final bool isMember;

  SearchResultGroup({
    required this.id,
    required this.name,
    required this.description,
    this.username = '',
    this.avatarUrl,
    this.isPublic = false,
    this.memberCount = 0,
    this.isMember = false,
  });

  factory SearchResultGroup.fromJson(Map<String, dynamic> json) {
    final rawAvatar = json['avatar_url']?.toString().trim();
    return SearchResultGroup(
      id: (json['id'] ?? json['chat_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      avatarUrl: (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
      isPublic: json['is_public'] == true,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      isMember: json['is_member'] == true,
    );
  }

  factory SearchResultGroup.fromPeer(SearchPeer peer) {
    return SearchResultGroup(
      id: peer.chatId ?? peer.id,
      name: peer.name,
      description: peer.description,
      username: peer.username,
      avatarUrl: peer.avatarUrl,
      isPublic: peer.isPublic,
      memberCount: peer.memberCount,
      isMember: peer.isMember,
    );
  }
}

/// SearchResultChannel represents a channel in search results.
class SearchResultChannel {
  final String id;
  final String name;
  final String description;
  final String groupId;
  final String username;
  final String? avatarUrl;
  final bool isPublic;
  final int memberCount;
  final bool isMember;
  final String chatType;

  SearchResultChannel({
    required this.id,
    required this.name,
    required this.description,
    required this.groupId,
    this.username = '',
    this.avatarUrl,
    this.isPublic = false,
    this.memberCount = 0,
    this.isMember = false,
    this.chatType = 'channel',
  });

  factory SearchResultChannel.fromJson(Map<String, dynamic> json) {
    final rawAvatar = json['avatar_url']?.toString().trim();
    final resolvedId = (json['id'] ?? json['chat_id'] ?? '').toString();
    return SearchResultChannel(
      id: resolvedId,
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      groupId: (json['group_id'] ?? resolvedId).toString(),
      username: (json['username'] ?? '').toString(),
      avatarUrl: (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
      isPublic: json['is_public'] == true,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      isMember: json['is_member'] == true,
      chatType: (json['chat_type'] ?? 'channel').toString(),
    );
  }

  factory SearchResultChannel.fromPeer(SearchPeer peer) {
    final resolvedId = peer.chatId ?? peer.id;
    return SearchResultChannel(
      id: resolvedId,
      name: peer.name,
      description: peer.description,
      groupId: resolvedId,
      username: peer.username,
      avatarUrl: peer.avatarUrl,
      isPublic: peer.isPublic,
      memberCount: peer.memberCount,
      isMember: peer.isMember,
      chatType: peer.peerType == 'group' ? 'group' : 'channel',
    );
  }
}

/// SearchResultMessage represents a message in search results.
class SearchResultMessage {
  final String id;
  final String content;
  final String chatId;
  final String chatType;
  final String chatName;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String messageType;
  final String userId;
  final String channelId;
  final String groupId;
  final DateTime createdAt;

  SearchResultMessage({
    required this.id,
    required this.content,
    required this.chatId,
    this.chatType = 'private',
    this.chatName = '',
    this.senderId = '',
    this.senderName = '',
    this.senderAvatar,
    this.messageType = 'text',
    required this.userId,
    required this.channelId,
    required this.groupId,
    required this.createdAt,
  });

  factory SearchResultMessage.fromJson(Map<String, dynamic> json) {
    final cId = (json['chat_id'] ?? json['channel_id'] ?? json['group_id'] ?? '').toString();
    final cType = (json['chat_type'] ??
            (json['channel_id'] != null && json['channel_id'].toString().isNotEmpty
                ? 'channel'
                : 'group'))
        .toString();
    final sId = (json['sender_id'] ?? json['user_id'] ?? '').toString();
    final rawAvatar = json['sender_avatar']?.toString().trim();

    return SearchResultMessage(
      id: (json['id'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      chatId: cId,
      chatType: cType,
      chatName: (json['chat_name'] ?? '').toString(),
      senderId: sId,
      senderName: (json['sender_name'] ?? '').toString(),
      senderAvatar: (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
      messageType: (json['message_type'] ?? 'text').toString(),
      userId: sId,
      channelId: cType == 'channel' ? cId : (json['channel_id'] ?? '').toString(),
      groupId: cType != 'channel' ? cId : (json['group_id'] ?? '').toString(),
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}

/// SearchService provides unified search functionality via `GET /api/search`.
class SearchService {
  /// Executes a unified search across the user's peers, global directory (users/bots/public chats),
  /// and messages (`GET /api/search`).
  static Future<UnifiedSearchResult> search({
    required String query,
    String type = 'all',
    String? chatId,
    int limit = 20,
    int offset = 0,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const UnifiedSearchResult();
    }

    try {
      final token = await AuthService.getToken();
      final queryParams = <String, String>{
        'query': trimmed,
        'type': type,
        'limit': limit.toString(),
        if (offset > 0) 'offset': offset.toString(),
        if (chatId != null && chatId.trim().isNotEmpty) 'chat_id': chatId.trim(),
      };

      final uri = Uri.parse('${AppConfig.baseUrl}/api/search')
          .replace(queryParameters: queryParams);

      if (AppConfig.enableDebugLogging) {
        debugPrint('SearchService: GET $uri');
      }

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> &&
            (data['success'] == true || data['ok'] == true)) {
          return UnifiedSearchResult.fromJson(data);
        }
      }
      return const UnifiedSearchResult();
    } catch (e) {
      debugPrint('Error in unified search: $e');
      return const UnifiedSearchResult();
    }
  }

  /// Searches for users and bots matching the query using `GET /api/search?type=users`.
  /// When [query] is empty, returns users from existing local private chats as initial suggestions.
  static Future<List<SearchResultUser>> searchUsers({
    required String query,
    int limit = 20,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      try {
        final localChats = await AppDatabase().getChats();
        final seen = <String>{};
        final contacts = <SearchResultUser>[];
        for (final c in localChats) {
          if (c.chatType == 'private' &&
              c.otherUserId != null &&
              c.otherUserId!.isNotEmpty &&
              !seen.contains(c.otherUserId)) {
            seen.add(c.otherUserId!);
            contacts.add(
              SearchResultUser(
                id: c.otherUserId!,
                name: c.name,
                email: '',
                username: '',
                avatarUrl: c.avatarUrl,
                chatId: c.chatId,
                isMyPeer: true,
              ),
            );
          }
        }
        return contacts;
      } catch (_) {
        return [];
      }
    }

    final result = await search(query: trimmed, type: 'users', limit: limit);
    final users = <SearchResultUser>[];
    final seenIds = <String>{};

    for (final p in result.myPeers) {
      if (p.isUser && seenIds.add(p.id)) {
        users.add(SearchResultUser.fromPeer(p, isMyPeer: true));
      }
    }
    for (final p in result.globalPeers) {
      if (p.isUser && seenIds.add(p.id)) {
        users.add(SearchResultUser.fromPeer(p, isMyPeer: false));
      }
    }
    return users;
  }

  /// Searches for groups matching the query using `GET /api/search?type=groups`.
  static Future<List<SearchResultGroup>> searchGroups({
    required String query,
    int limit = 20,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final result = await search(query: trimmed, type: 'groups', limit: limit);
    final groups = <SearchResultGroup>[];
    final seenIds = <String>{};

    for (final p in result.myPeers) {
      if (p.isGroup && seenIds.add(p.chatId ?? p.id)) {
        groups.add(SearchResultGroup.fromPeer(p));
      }
    }
    for (final p in result.globalPeers) {
      if (p.isGroup && seenIds.add(p.chatId ?? p.id)) {
        groups.add(SearchResultGroup.fromPeer(p));
      }
    }
    return groups;
  }

  /// Searches for channels matching the query using `GET /api/search?type=channels`.
  static Future<List<SearchResultChannel>> searchChannels({
    required String query,
    int limit = 20,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final result = await search(query: trimmed, type: 'channels', limit: limit);
    final channels = <SearchResultChannel>[];
    final seenIds = <String>{};

    for (final p in result.myPeers) {
      if (p.isChannel && seenIds.add(p.chatId ?? p.id)) {
        channels.add(SearchResultChannel.fromPeer(p));
      }
    }
    for (final p in result.globalPeers) {
      if (p.isChannel && seenIds.add(p.chatId ?? p.id)) {
        channels.add(SearchResultChannel.fromPeer(p));
      }
    }
    return channels;
  }

  /// Searches for messages matching the query using `GET /api/search?type=messages`.
  static Future<List<SearchResultMessage>> searchMessages({
    required String query,
    String? chatId,
    int limit = 20,
    int offset = 0,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final result = await search(
      query: trimmed,
      type: 'messages',
      chatId: chatId,
      limit: limit,
      offset: offset,
    );
    return result.messages;
  }
}
