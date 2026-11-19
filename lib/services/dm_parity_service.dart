import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'auth_service.dart';
import 'chat_service.dart';

class SavedTagItem {
  final String tag;
  final String label;
  final int count;

  const SavedTagItem({
    required this.tag,
    this.label = '',
    this.count = 0,
  });

  factory SavedTagItem.fromJson(Map<String, dynamic> json) {
    return SavedTagItem(
      tag: (json['tag'] ?? json['emoji'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      count: (json['count'] as num?)?.toInt() ??
          int.tryParse(json['count']?.toString() ?? '') ??
          0,
    );
  }

  Map<String, dynamic> toJson() => {
        'tag': tag,
        'label': label,
        'count': count,
      };
}

class SavedPeerItem {
  final String savedPeerKey;
  final String peerType;
  final String peerId;
  final String title;
  final String avatarUrl;
  final int messageCount;
  final String lastMessageAt;
  final String lastMessagePreview;

  const SavedPeerItem({
    required this.savedPeerKey,
    required this.peerType,
    this.peerId = '',
    required this.title,
    this.avatarUrl = '',
    this.messageCount = 0,
    this.lastMessageAt = '',
    this.lastMessagePreview = '',
  });

  factory SavedPeerItem.fromJson(Map<String, dynamic> json) {
    return SavedPeerItem(
      savedPeerKey: (json['saved_peer_key'] ?? '').toString(),
      peerType: (json['peer_type'] ?? 'self').toString(),
      peerId: (json['peer_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      avatarUrl: (json['avatar_url'] ?? '').toString(),
      messageCount: (json['message_count'] as num?)?.toInt() ??
          int.tryParse(json['message_count']?.toString() ?? '') ??
          0,
      lastMessageAt: (json['last_message_at'] ?? '').toString(),
      lastMessagePreview: (json['last_message_preview'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'saved_peer_key': savedPeerKey,
        'peer_type': peerType,
        'peer_id': peerId,
        'title': title,
        'avatar_url': avatarUrl,
        'message_count': messageCount,
        'last_message_at': lastMessageAt,
        'last_message_preview': lastMessagePreview,
      };
}

class CommonGroupItem {
  final String id;
  final String name;
  final String username;
  final String chatType;
  final String avatarUrl;
  final int participantsCount;
  final String updatedAt;

  const CommonGroupItem({
    required this.id,
    required this.name,
    this.username = '',
    this.chatType = 'group',
    this.avatarUrl = '',
    this.participantsCount = 0,
    this.updatedAt = '',
  });

  factory CommonGroupItem.fromJson(Map<String, dynamic> json) {
    return CommonGroupItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      chatType: (json['chat_type'] ?? 'group').toString(),
      avatarUrl: (json['avatar_url'] ?? '').toString(),
      participantsCount: (json['participants_count'] as num?)?.toInt() ??
          int.tryParse(json['participants_count']?.toString() ?? '') ??
          0,
      updatedAt: (json['updated_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'chat_type': chatType,
        'avatar_url': avatarUrl,
        'participants_count': participantsCount,
        'updated_at': updatedAt,
      };
}

class ChatAppearanceConfig {
  final String themeId;
  final String wallpaperUrl;
  final Map<String, dynamic> wallpaperSettings;
  final String accentColorId;
  final bool isShared;

  const ChatAppearanceConfig({
    this.themeId = '',
    this.wallpaperUrl = '',
    this.wallpaperSettings = const {},
    this.accentColorId = '',
    this.isShared = false,
  });

  bool get isEmpty =>
      themeId.isEmpty &&
      wallpaperUrl.isEmpty &&
      accentColorId.isEmpty &&
      wallpaperSettings.isEmpty;

  factory ChatAppearanceConfig.fromJson(Map<String, dynamic> json) {
    final rawSettings = json['wallpaper_settings'];
    return ChatAppearanceConfig(
      themeId: (json['theme_id'] ?? '').toString(),
      wallpaperUrl: (json['wallpaper_url'] ?? '').toString(),
      wallpaperSettings: rawSettings is Map
          ? Map<String, dynamic>.from(rawSettings)
          : const {},
      accentColorId: (json['accent_color_id'] ?? '').toString(),
      isShared: json['is_shared'] == true || json['for_both'] == true,
    );
  }

  static ChatAppearanceConfig? tryParseJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty || raw == 'null') return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return ChatAppearanceConfig.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> toJson({bool includeForBoth = false}) => {
        'theme_id': themeId,
        'wallpaper_url': wallpaperUrl,
        'wallpaper_settings': wallpaperSettings,
        'accent_color_id': accentColorId,
        'is_shared': isShared,
        if (includeForBoth) 'for_both': isShared,
      };
}

class TranslationResult {
  final String messageId;
  final String chatId;
  final String targetLang;
  final String sourceLang;
  final String translatedText;
  final String provider;
  final bool cached;

  const TranslationResult({
    required this.messageId,
    this.chatId = '',
    required this.targetLang,
    this.sourceLang = '',
    required this.translatedText,
    this.provider = '',
    this.cached = false,
  });

  factory TranslationResult.fromJson(Map<String, dynamic> json) {
    return TranslationResult(
      messageId: (json['message_id'] ?? '').toString(),
      chatId: (json['chat_id'] ?? '').toString(),
      targetLang: (json['target_lang'] ?? '').toString(),
      sourceLang: (json['source_lang'] ?? '').toString(),
      translatedText: (json['translated_text'] ?? '').toString(),
      provider: (json['provider'] ?? '').toString(),
      cached: json['cached'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'message_id': messageId,
        'chat_id': chatId,
        'target_lang': targetLang,
        'source_lang': sourceLang,
        'translated_text': translatedText,
        'provider': provider,
        'cached': cached,
      };
}

class SharedMediaPage {
  final String type;
  final List<Message> messages;
  final bool hasMore;
  final String nextBeforeId;

  const SharedMediaPage({
    required this.type,
    required this.messages,
    this.hasMore = false,
    this.nextBeforeId = '',
  });
}

class DmParityService {
  DmParityService._();

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _decodeMap(http.Response resp) {
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> setChatAutoDelete(
    String chatId,
    int ttlSeconds,
  ) async {
    try {
      final resp = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/auto-delete'),
        headers: await _headers(),
        body: jsonEncode({
          'ttl_seconds': ttlSeconds,
          'message_auto_delete_time': ttlSeconds,
        }),
      );
      final body = _decodeMap(resp);
      return {
        'success': resp.statusCode == 200 && body['success'] == true,
        'message_auto_delete_time':
            (body['message_auto_delete_time'] as num?)?.toInt() ?? ttlSeconds,
        if (body['message'] != null) 'message': body['message'],
      };
    } catch (e) {
      debugPrint('DmParityService.setChatAutoDelete error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> consumeViewOnce(
    String chatId,
    String messageId,
  ) async {
    try {
      final resp = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/consume-view-once',
        ),
        headers: await _headers(),
      );
      final body = _decodeMap(resp);
      return {
        'success': resp.statusCode == 200 && body['success'] == true,
        'status_code': resp.statusCode,
        'is_burned': body['is_burned'] == true || resp.statusCode == 410,
        'viewed_at': body['viewed_at']?.toString(),
        'expires_at': body['expires_at']?.toString(),
        'ttl_seconds': (body['ttl_seconds'] as num?)?.toInt() ?? 0,
        if (body['message'] != null) 'message': body['message'],
      };
    } catch (e) {
      debugPrint('DmParityService.consumeViewOnce error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<bool> reportScreenshot(String chatId) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/screenshot'),
        headers: await _headers(),
      );
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('DmParityService.reportScreenshot error: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> updateLiveLocation(
    String chatId,
    String messageId, {
    double? latitude,
    double? longitude,
    int? heading,
    double? horizontalAccuracy,
    int? livePeriod,
    bool stop = false,
  }) async {
    try {
      final payload = <String, dynamic>{
        if (stop) 'stop': true,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (heading != null) 'heading': heading,
        if (horizontalAccuracy != null)
          'horizontal_accuracy': horizontalAccuracy,
        if (livePeriod != null) 'live_period': livePeriod,
      };
      final resp = await http.patch(
        Uri.parse(
          '${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/live-location',
        ),
        headers: await _headers(),
        body: jsonEncode(payload),
      );
      final body = _decodeMap(resp);
      return {
        'success': resp.statusCode == 200 && body['success'] == true,
        'media_payload': body['media_payload'],
        if (body['message'] != null) 'message': body['message'],
      };
    } catch (e) {
      debugPrint('DmParityService.updateLiveLocation error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<SharedMediaPage> getChatSharedMedia(
    String chatId, {
    String type = 'media',
    int limit = 50,
    String? beforeId,
    int offset = 0,
  }) async {
    try {
      final query = <String, String>{
        'type': type,
        'limit': limit.toString(),
        if (offset > 0) 'offset': offset.toString(),
        if (beforeId != null && beforeId.isNotEmpty) 'before_id': beforeId,
      };
      final uri = Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/shared-media')
          .replace(queryParameters: query);
      final resp = await http.get(uri, headers: await _headers());
      if (resp.statusCode != 200) {
        return SharedMediaPage(type: type, messages: const []);
      }
      final body = _decodeMap(resp);
      final rawList = body['messages'] as List<dynamic>? ?? const [];
      final parsed = rawList
          .whereType<Map>()
          .map((m) => Message.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      return SharedMediaPage(
        type: (body['type'] ?? type).toString(),
        messages: parsed,
        hasMore: body['has_more'] == true,
        nextBeforeId: (body['next_before_id'] ?? '').toString(),
      );
    } catch (e) {
      debugPrint('DmParityService.getChatSharedMedia error: $e');
      return SharedMediaPage(type: type, messages: const []);
    }
  }

  static Future<List<CommonGroupItem>> getCommonGroups(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (userId.isEmpty) return const [];
    try {
      final uri =
          Uri.parse('${AppConfig.baseUrl}/api/users/$userId/common-groups')
              .replace(queryParameters: {
        'limit': limit.toString(),
        if (offset > 0) 'offset': offset.toString(),
      });
      final resp = await http.get(uri, headers: await _headers());
      if (resp.statusCode != 200) return const [];
      final body = _decodeMap(resp);
      final list = body['groups'] as List<dynamic>? ?? const [];
      return list
          .whereType<Map>()
          .map((e) => CommonGroupItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('DmParityService.getCommonGroups error: $e');
      return const [];
    }
  }

  static Future<Map<String, dynamic>> submitReport({
    String? chatId,
    String? targetUserId,
    List<String> messageIds = const [],
    required String reason,
    String details = '',
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/reports'),
        headers: await _headers(),
        body: jsonEncode({
          if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId,
          if (targetUserId != null && targetUserId.isNotEmpty)
            'target_user_id': targetUserId,
          if (messageIds.isNotEmpty) 'message_ids': messageIds,
          'reason': reason,
          if (details.trim().isNotEmpty) 'details': details.trim(),
        }),
      );
      final body = _decodeMap(resp);
      return {
        'success': resp.statusCode == 200 && body['success'] == true,
        'report_id': body['report_id']?.toString(),
        if (body['message'] != null) 'message': body['message'],
      };
    } catch (e) {
      debugPrint('DmParityService.submitReport error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<List<SavedTagItem>> getSavedTags() async {
    try {
      final resp = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/saved/tags'),
        headers: await _headers(),
      );
      if (resp.statusCode != 200) return const [];
      final body = _decodeMap(resp);
      final list = body['tags'] as List<dynamic>? ?? const [];
      return list
          .whereType<Map>()
          .map((e) => SavedTagItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('DmParityService.getSavedTags error: $e');
      return const [];
    }
  }

  static Future<Map<String, dynamic>> toggleSavedMessageTag(
    String messageId,
    String tag,
  ) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/saved/messages/$messageId/tags'),
        headers: await _headers(),
        body: jsonEncode({'tag': tag, 'emoji': tag}),
      );
      final body = _decodeMap(resp);
      final savedTags = (body['saved_tags'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();
      return {
        'success': resp.statusCode == 200 && body['success'] == true,
        'active': body['active'] == true,
        'saved_tags': savedTags,
        'reactions': body['reactions'],
        if (body['message'] != null) 'message': body['message'],
      };
    } catch (e) {
      debugPrint('DmParityService.toggleSavedMessageTag error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> removeSavedMessageTag(
    String messageId,
    String tag,
  ) async {
    try {
      final encodedTag = Uri.encodeComponent(tag);
      final resp = await http.delete(
        Uri.parse(
          '${AppConfig.baseUrl}/api/chats/saved/messages/$messageId/tags/$encodedTag',
        ),
        headers: await _headers(),
      );
      final body = _decodeMap(resp);
      final savedTags = (body['saved_tags'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();
      return {
        'success': resp.statusCode == 200 && body['success'] == true,
        'saved_tags': savedTags,
        'reactions': body['reactions'],
      };
    } catch (e) {
      debugPrint('DmParityService.removeSavedMessageTag error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<bool> setSavedTagLabel(String tag, String label) async {
    try {
      final encodedTag = Uri.encodeComponent(tag);
      final resp = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/chats/saved/tags/$encodedTag/label'),
        headers: await _headers(),
        body: jsonEncode({'label': label}),
      );
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('DmParityService.setSavedTagLabel error: $e');
      return false;
    }
  }

  static Future<List<SavedPeerItem>> getSavedPeers() async {
    try {
      final resp = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/saved/peers'),
        headers: await _headers(),
      );
      if (resp.statusCode != 200) return const [];
      final body = _decodeMap(resp);
      final list = body['peers'] as List<dynamic>? ?? const [];
      return list
          .whereType<Map>()
          .map((e) => SavedPeerItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('DmParityService.getSavedPeers error: $e');
      return const [];
    }
  }

  static Future<ChatAppearanceConfig?> getChatAppearance(String chatId) async {
    try {
      final resp = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/appearance'),
        headers: await _headers(),
      );
      if (resp.statusCode != 200) return null;
      final body = _decodeMap(resp);
      final raw = body['appearance'];
      if (raw is Map) {
        return ChatAppearanceConfig.fromJson(Map<String, dynamic>.from(raw));
      }
      return null;
    } catch (e) {
      debugPrint('DmParityService.getChatAppearance error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> updateChatAppearance(
    String chatId,
    ChatAppearanceConfig config, {
    bool forBoth = false,
  }) async {
    try {
      final resp = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/appearance'),
        headers: await _headers(),
        body: jsonEncode({
          'theme_id': config.themeId,
          'wallpaper_url': config.wallpaperUrl,
          'wallpaper_settings': config.wallpaperSettings,
          'accent_color_id': config.accentColorId,
          'for_both': forBoth,
        }),
      );
      final body = _decodeMap(resp);
      final raw = body['appearance'];
      return {
        'success': resp.statusCode == 200 && body['success'] == true,
        'appearance': raw is Map
            ? ChatAppearanceConfig.fromJson(Map<String, dynamic>.from(raw))
            : null,
        if (body['message'] != null) 'message': body['message'],
      };
    } catch (e) {
      debugPrint('DmParityService.updateChatAppearance error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> deleteChatAppearance(
    String chatId, {
    bool forBoth = false,
  }) async {
    try {
      final uri =
          Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/appearance')
              .replace(queryParameters: {if (forBoth) 'for_both': 'true'});
      final resp = await http.delete(uri, headers: await _headers());
      final body = _decodeMap(resp);
      final raw = body['appearance'];
      return {
        'success': resp.statusCode == 200 && body['success'] == true,
        'appearance': raw is Map
            ? ChatAppearanceConfig.fromJson(Map<String, dynamic>.from(raw))
            : null,
      };
    } catch (e) {
      debugPrint('DmParityService.deleteChatAppearance error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> translateMessage({
    String? chatId,
    required String messageId,
    required String targetLang,
    String sourceLang = 'auto',
    bool force = false,
  }) async {
    try {
      final url = (chatId != null && chatId.isNotEmpty)
          ? '${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/translate'
          : '${AppConfig.baseUrl}/api/messages/$messageId/translate';
      final resp = await http.post(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode({
          'target_lang': targetLang,
          if (sourceLang.isNotEmpty) 'source_lang': sourceLang,
          if (force) 'force': true,
        }),
      );
      final body = _decodeMap(resp);
      if (resp.statusCode == 200 && body['success'] == true) {
        return {
          'success': true,
          'translation': TranslationResult.fromJson(body),
        };
      }
      return {
        'success': false,
        'status_code': resp.statusCode,
        'error': body['error']?.toString(),
        'message': body['message']?.toString() ?? 'Translation failed',
      };
    } catch (e) {
      debugPrint('DmParityService.translateMessage error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
}
