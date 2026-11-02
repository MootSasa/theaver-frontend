import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/community_models.dart';
import 'auth_service.dart';
import 'database/app_database.dart';

/// REST client for Theaver Communities (`/api/communities/*`).
class CommunityService {
  static const String _prefsKeyPrefix = 'cached_communities_v2_';
  static final Map<String, Community> _cache = {};
  static bool _loadedFromDisk = false;
  static String? _loadedUserId;

  static Future<String> _currentPrefsKey() async {
    final userId = await AuthService.getUserId() ?? 'anon';
    if (_loadedUserId != null && _loadedUserId != userId) {
      _cache.clear();
      _loadedFromDisk = false;
    }
    _loadedUserId = userId;
    return '$_prefsKeyPrefix$userId';
  }

  /// Clears in-memory cache when switching accounts so communities from another
  /// account never leak into the active account.
  static void clearMemoryCache() {
    _cache.clear();
    _loadedFromDisk = false;
    _loadedUserId = null;
  }

  static Community _stripFakeLocalChannels(Community community) {
    final cleanCategories = community.categories
        .where((c) => !c.id.startsWith('cat_') && !c.id.startsWith('local_'))
        .toList();
    final cleanChannels = community.channels
        .where((ch) => !ch.id.startsWith('ch_') && !ch.id.startsWith('local_'))
        .toList();
    if (cleanCategories.length == community.categories.length &&
        cleanChannels.length == community.channels.length) {
      return community;
    }
    return community.copyWith(
      categories: cleanCategories,
      channels: cleanChannels,
    );
  }

  /// Stores a [Community] in the in-memory lookup cache, persists to SharedPreferences,
  /// and syncs it to the local Drift [AppDatabase] `chats` table (`chatType: 'community'`)
  /// ONLY if the current user is actually a member (`community.isMember == true`).
  static void cacheCommunity(Community community) {
    if (community.id.isEmpty) return;
    final sanitized = _stripFakeLocalChannels(community);
    if (!sanitized.isMember) {
      _cache.remove(sanitized.id);
      unawaited(_persistCacheToDisk());
      unawaited(AppDatabase().deleteChat('community_${sanitized.id}'));
      return;
    }
    final prev = _cache[sanitized.id];
    final merged = (prev != null &&
            sanitized.channels.isEmpty &&
            prev.channels.isNotEmpty)
        ? sanitized.copyWith(
            categories: sanitized.categories.isNotEmpty
                ? sanitized.categories
                : prev.categories,
            channels: prev.channels,
            roles: sanitized.roles.isNotEmpty ? sanitized.roles : prev.roles,
          )
        : sanitized;
    _cache[sanitized.id] = merged;
    unawaited(_persistCacheToDisk());
    unawaited(_syncCommunityToDb(merged));
  }

  /// Retrieves a cached [Community] by ID, if available.
  static Community? getCachedCommunity(String communityId) {
    final cleanId = communityId.startsWith('community_')
        ? communityId.substring('community_'.length)
        : communityId;
    return _cache[cleanId];
  }

  /// Returns all currently cached communities the user is a member of.
  static List<Community> getCachedCommunitiesList() {
    return _cache.values.where((c) => c.isMember).toList();
  }

  /// Returns true if [chatId] belongs to a channel inside any known community.
  static bool isCommunityChannelId(String chatId) {
    if (chatId.isEmpty || chatId.startsWith('community_')) return false;
    for (final c in _cache.values) {
      for (final ch in c.channels) {
        if (ch.id == chatId) return true;
      }
    }
    return false;
  }

  /// Searches cached & persisted communities locally by name or description.
  static Future<List<Community>> searchCommunitiesLocal(
    String query, {
    int limit = 20,
  }) async {
    await _ensureDiskCacheLoaded();
    final qLower = query.trim().toLowerCase();
    if (qLower.isEmpty) return _cache.values.take(limit).toList();
    final matched = <Community>[];
    for (final c in _cache.values) {
      if (c.name.toLowerCase().contains(qLower) ||
          c.description.toLowerCase().contains(qLower)) {
        matched.add(c);
        if (matched.length >= limit) break;
      }
    }
    return matched;
  }

  static Future<void> _ensureDiskCacheLoaded() async {
    final key = await _currentPrefsKey();
    if (_loadedFromDisk) return;
    _loadedFromDisk = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final comm = _stripFakeLocalChannels(
                Community.fromJson(Map<String, dynamic>.from(item)),
              );
              if (comm.id.isNotEmpty &&
                  comm.isMember &&
                  !_cache.containsKey(comm.id)) {
                _cache[comm.id] = comm;
                unawaited(_syncCommunityToDb(comm));
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[CommunityService] _ensureDiskCacheLoaded error: $e');
    }
  }

  static Future<void> _persistCacheToDisk() async {
    try {
      final key = await _currentPrefsKey();
      final prefs = await SharedPreferences.getInstance();
      final list =
          _cache.values.where((c) => c.isMember).map((c) => c.toJson()).toList();
      await prefs.setString(key, jsonEncode(list));
    } catch (e) {
      debugPrint('[CommunityService] _persistCacheToDisk error: $e');
    }
  }

  static Future<void> _syncCommunityToDb(Community c) async {
    if (!c.isMember) return;
    try {
      final db = AppDatabase();
      // Ensure individual community channels are never stored as standalone chats on the main screen
      for (final ch in c.channels) {
        if (ch.id.isNotEmpty) {
          unawaited(db.deleteChat(ch.id));
        }
      }
      final activeVoice = c.activeVoiceCount;
      final subtitle = activeVoice > 0
          ? '🔊 $activeVoice в голосовом • ${c.memberCount} участн.'
          : (c.description.isNotEmpty
              ? c.description
              : '${c.memberCount} участн. • Сообщество');
      await db.saveChats([
        ChatsCompanion(
          chatId: Value('community_${c.id}'),
          chatType: const Value('community'),
          name: Value(c.name),
          avatarUrl: Value(c.avatarUrl),
          lastMessage: Value(subtitle),
          lastMessageTime: Value(c.createdAt.toIso8601String()),
          lastMessageType: const Value('text'),
          updatedAt: Value(c.createdAt.toIso8601String()),
          unreadCount: Value(c.totalUnreadCount),
          otherUserId: Value(c.id),
        ),
      ]);
    } catch (_) {}
  }

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Lists all communities the current user belongs to (`GET /api/communities`).
  static Future<List<Community>> getCommunities() async {
    await _ensureDiskCacheLoaded();
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/communities'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Community> serverList = const [];
        if (data is Map<String, dynamic> && data['communities'] is List) {
          serverList = (data['communities'] as List)
              .whereType<Map>()
              .map((m) => _stripFakeLocalChannels(
                    Community.fromJson(Map<String, dynamic>.from(m))
                        .copyWith(isMember: true),
                  ))
              .toList();
        } else if (data is List) {
          serverList = data
              .whereType<Map>()
              .map((m) => _stripFakeLocalChannels(
                    Community.fromJson(Map<String, dynamic>.from(m))
                        .copyWith(isMember: true),
                  ))
              .toList();
        }
        final serverIds = serverList.map((c) => c.id).toSet();
        // Remove any stale cached communities that the user is no longer a member of
        final staleIds =
            _cache.keys.where((id) => !serverIds.contains(id)).toList();
        for (final staleId in staleIds) {
          _cache.remove(staleId);
          unawaited(AppDatabase().deleteChat('community_$staleId'));
        }
        for (final c in serverList) {
          _cache[c.id] = c;
          unawaited(_syncCommunityToDb(c));
        }
        unawaited(_persistCacheToDisk());
        return serverList;
      }
    } catch (e) {
      debugPrint('[CommunityService] getCommunities error: $e');
    }
    return _cache.values.where((c) => c.isMember).toList();
  }

  /// Creates a new community (`POST /api/communities`).
  static Future<Community?> createCommunity({
    required String name,
    String description = '',
    String? avatarUrl,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/communities'),
        headers: await _headers(),
        body: jsonEncode({
          'name': name,
          'description': description,
          'is_public': true,
          if (avatarUrl != null && avatarUrl.isNotEmpty) ...{
            'avatar_url': avatarUrl,
            'icon_url': avatarUrl,
          },
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final map = data['community'] is Map<String, dynamic>
              ? data['community'] as Map<String, dynamic>
              : data;
          final comm = Community.fromJson(map).copyWith(isMember: true);
          cacheCommunity(comm);
          return comm;
        }
      }
    } catch (e) {
      debugPrint('[CommunityService] createCommunity error: $e');
    }
    return null;
  }

  /// Fetches full community details (`GET /api/communities/:communityId`).
  /// For non-members viewing a public community, returns the preview payload
  /// (`isMember == false`) WITHOUT adding it to the joined communities cache.
  static Future<Community?> getCommunity(String communityId) async {
    await _ensureDiskCacheLoaded();
    final cleanId = communityId.startsWith('community_')
        ? communityId.substring('community_'.length)
        : communityId;
    if (cleanId.startsWith('local_')) {
      return _cache[cleanId];
    }
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/communities/$cleanId'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final map = data['community'] is Map<String, dynamic>
              ? data['community'] as Map<String, dynamic>
              : data;
          final comm = _stripFakeLocalChannels(Community.fromJson(map));
          if (comm.isMember) {
            cacheCommunity(comm);
          } else {
            _cache.remove(cleanId);
            unawaited(AppDatabase().deleteChat('community_$cleanId'));
          }
          return comm;
        }
      }
    } catch (e) {
      debugPrint('[CommunityService] getCommunity error: $e');
    }
    return _cache[cleanId];
  }

  /// Updates community metadata (`PATCH /api/communities/:communityId`).
  static Future<Community?> updateCommunity(
    String communityId, {
    String? name,
    String? description,
    String? avatarUrl,
  }) async {
    final cleanId = communityId.startsWith('community_')
        ? communityId.substring('community_'.length)
        : communityId;
    if (cleanId.startsWith('local_') && _cache.containsKey(cleanId)) {
      final updated = _cache[cleanId]!.copyWith(
        name: name,
        description: description,
        avatarUrl: avatarUrl,
      );
      cacheCommunity(updated);
      return updated;
    }
    try {
      final response = await http.patch(
        Uri.parse('${AppConfig.baseUrl}/api/communities/$cleanId'),
        headers: await _headers(),
        body: jsonEncode({
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (avatarUrl != null) ...{
            'avatar_url': avatarUrl,
            'icon_url': avatarUrl,
          },
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final map = data['community'] is Map<String, dynamic>
              ? data['community'] as Map<String, dynamic>
              : data;
          final comm = Community.fromJson(map);
          cacheCommunity(comm);
          return comm;
        }
      }
    } catch (e) {
      debugPrint('[CommunityService] updateCommunity error: $e');
    }
    if (_cache.containsKey(cleanId)) {
      final updated = _cache[cleanId]!.copyWith(
        name: name,
        description: description,
        avatarUrl: avatarUrl,
      );
      cacheCommunity(updated);
      return updated;
    }
    return null;
  }

  /// Deletes a community (`DELETE /api/communities/:communityId`).
  static Future<bool> deleteCommunity(String communityId) async {
    final cleanId = communityId.startsWith('community_')
        ? communityId.substring('community_'.length)
        : communityId;
    _cache.remove(cleanId);
    unawaited(_persistCacheToDisk());
    try {
      await AppDatabase().deleteChat('community_$cleanId');
    } catch (_) {}
    if (cleanId.startsWith('local_')) {
      return true;
    }
    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/communities/$cleanId'),
        headers: await _headers(),
      );
      return response.statusCode == 200 || response.statusCode == 404;
    } catch (e) {
      debugPrint('[CommunityService] deleteCommunity error: $e');
      return true;
    }
  }

  /// Joins a public community by ID (`POST /api/communities/:communityId/join`).
  static Future<Community?> joinCommunity(String communityId) async {
    final cleanId = communityId.startsWith('community_')
        ? communityId.substring('community_'.length)
        : communityId;
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/communities/$cleanId/join'),
        headers: await _headers(),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final map = data['community'] is Map<String, dynamic>
              ? data['community'] as Map<String, dynamic>
              : data;
          final comm =
              _stripFakeLocalChannels(Community.fromJson(map)).copyWith(
            isMember: true,
          );
          cacheCommunity(comm);
          return comm;
        }
      }
    } catch (e) {
      debugPrint('[CommunityService] joinCommunity error: $e');
    }
    return null;
  }

  /// Leaves a community (`POST /api/communities/:communityId/leave`).
  static Future<bool> leaveCommunity(String communityId) async {
    final cleanId = communityId.startsWith('community_')
        ? communityId.substring('community_'.length)
        : communityId;
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/communities/$cleanId/leave'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        _cache.remove(cleanId);
        unawaited(_persistCacheToDisk());
        try {
          await AppDatabase().deleteChat('community_$cleanId');
        } catch (_) {}
        return true;
      }
    } catch (e) {
      debugPrint('[CommunityService] leaveCommunity error: $e');
    }
    return false;
  }

  /// Joins a community via invite code (`POST /api/communities/join/:code`).
  static Future<Community?> joinByCode(String code) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/communities/join/$code'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final map = data['community'] is Map<String, dynamic>
              ? data['community'] as Map<String, dynamic>
              : data;
          final comm =
              _stripFakeLocalChannels(Community.fromJson(map)).copyWith(
            isMember: true,
          );
          cacheCommunity(comm);
          return comm;
        }
      }
    } catch (e) {
      debugPrint('[CommunityService] joinByCode error: $e');
    }
    return null;
  }

  /// Creates a category (`POST /api/communities/:communityId/categories`).
  static Future<CommunityCategory?> createCategory(
    String communityId, {
    required String name,
    int position = 0,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/api/communities/$communityId/categories',
        ),
        headers: await _headers(),
        body: jsonEncode({'name': name, 'position': position}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final map = data['category'] is Map<String, dynamic>
              ? data['category'] as Map<String, dynamic>
              : data;
          return CommunityCategory.fromJson(map);
        }
      }
    } catch (e) {
      debugPrint('[CommunityService] createCategory error: $e');
    }
    return null;
  }

  /// Deletes a category (`DELETE /api/communities/:communityId/categories/:categoryId`).
  static Future<bool> deleteCategory(
    String communityId,
    String categoryId,
  ) async {
    try {
      final response = await http.delete(
        Uri.parse(
          '${AppConfig.baseUrl}/api/communities/$communityId/categories/$categoryId',
        ),
        headers: await _headers(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CommunityService] deleteCategory error: $e');
      return false;
    }
  }

  /// Creates a channel inside a community (`POST /api/communities/:communityId/channels`).
  static Future<CommunityChannel?> createChannel(
    String communityId, {
    required String name,
    String channelType = 'text', // 'text' | 'voice' | 'stage' | 'announcement'
    String? categoryId,
    String topic = '',
  }) async {
    try {
      final parsedCatId =
          categoryId != null ? int.tryParse(categoryId.trim()) : null;
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/communities/$communityId/channels'),
        headers: await _headers(),
        body: jsonEncode({
          'name': name,
          'channel_kind': channelType,
          'channel_type': channelType,
          'type': channelType,
          if (parsedCatId != null)
            'category_id': parsedCatId
          else if (categoryId != null && categoryId.isNotEmpty)
            'category_id': categoryId,
          if (topic.isNotEmpty) ...{
            'topic': topic,
            'description': topic,
          },
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final map = data['channel'] is Map<String, dynamic>
              ? data['channel'] as Map<String, dynamic>
              : data;
          return CommunityChannel.fromJson(map);
        }
      }
    } catch (e) {
      debugPrint('[CommunityService] createChannel error: $e');
    }
    return null;
  }

  /// Lists roles (`GET /api/communities/:communityId/roles`).
  static Future<List<CommunityRole>> getRoles(String communityId) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/communities/$communityId/roles'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['roles'] is List) {
          return (data['roles'] as List)
              .whereType<Map<String, dynamic>>()
              .map(CommunityRole.fromJson)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[CommunityService] getRoles error: $e');
    }
    return const [];
  }

  /// Creates a role (`POST /api/communities/:communityId/roles`).
  static Future<CommunityRole?> createRole(
    String communityId, {
    required String name,
    String colorHex = '#5C6BC0',
    int permissions = 0,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/communities/$communityId/roles'),
        headers: await _headers(),
        body: jsonEncode({
          'name': name,
          'color': colorHex,
          'permissions': permissions,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final map = data['role'] is Map<String, dynamic>
              ? data['role'] as Map<String, dynamic>
              : data;
          return CommunityRole.fromJson(map);
        }
      }
    } catch (e) {
      debugPrint('[CommunityService] createRole error: $e');
    }
    return null;
  }

  /// Updates a role (`PATCH /api/communities/:communityId/roles/:roleId`).
  static Future<CommunityRole?> updateRole(
    String communityId,
    String roleId, {
    String? name,
    String? colorHex,
    int? permissions,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse(
          '${AppConfig.baseUrl}/api/communities/$communityId/roles/$roleId',
        ),
        headers: await _headers(),
        body: jsonEncode({
          if (name != null) 'name': name,
          if (colorHex != null) 'color': colorHex,
          if (permissions != null) 'permissions': permissions,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final map = data['role'] is Map<String, dynamic>
              ? data['role'] as Map<String, dynamic>
              : data;
          return CommunityRole.fromJson(map);
        }
      }
    } catch (e) {
      debugPrint('[CommunityService] updateRole error: $e');
    }
    return null;
  }

  /// Generates an invite code (`POST /api/communities/:communityId/invites`).
  static Future<String?> createInviteCode(String communityId) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/communities/$communityId/invites'),
        headers: await _headers(),
        body: jsonEncode({'max_uses': 0, 'expires_in_hours': 168}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return (data['code'] ?? data['invite_code'])?.toString();
        }
      }
    } catch (e) {
      debugPrint('[CommunityService] createInviteCode error: $e');
    }
    return null;
  }
}
