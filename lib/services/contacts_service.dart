import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../utils/date_time_utils.dart';
import 'auth_service.dart';

/// Represents a contact entry synced with `/api/contacts`.
class ContactItem {
  final String id;
  final String userId;
  final String contactUserId;
  final String username;
  final String displayName;
  final String customFirstName;
  final String customLastName;
  final String nickname;
  final String avatarUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final String lastSeenStatus;
  final bool isVerified;
  final bool isBot;
  final bool isFavorite;
  final bool isMutual;
  final DateTime? addedAt;
  final DateTime? updatedAt;

  const ContactItem({
    required this.id,
    required this.userId,
    required this.contactUserId,
    this.username = '',
    this.displayName = '',
    this.customFirstName = '',
    this.customLastName = '',
    this.nickname = '',
    this.avatarUrl = '',
    this.isOnline = false,
    this.lastSeen,
    this.lastSeenStatus = '',
    this.isVerified = false,
    this.isBot = false,
    this.isFavorite = false,
    this.isMutual = false,
    this.addedAt,
    this.updatedAt,
  });

  /// Display name resolved in Telegram contact priority:
  /// custom first+last name -> nickname -> user's displayName -> username.
  String get effectiveName {
    final fullCustom = '$customFirstName $customLastName'.trim();
    if (fullCustom.isNotEmpty) return fullCustom;
    if (nickname.trim().isNotEmpty) return nickname.trim();
    if (displayName.trim().isNotEmpty) return displayName.trim();
    if (username.trim().isNotEmpty) return '@${username.trim()}';
    return 'Пользователь #$contactUserId';
  }

  factory ContactItem.fromJson(Map<String, dynamic> json) {
    final cid = (json['contact_user_id'] ?? json['user_id'] ?? json['id'] ?? '')
        .toString();
    return ContactItem(
      id: (json['id'] ?? cid).toString(),
      userId: (json['user_id'] ?? cid).toString(),
      contactUserId: cid,
      username: (json['username'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      customFirstName: (json['custom_first_name'] ?? '').toString(),
      customLastName: (json['custom_last_name'] ?? '').toString(),
      nickname: (json['nickname'] ?? '').toString(),
      avatarUrl: (json['avatar_url'] ?? '').toString(),
      isOnline: json['is_online'] == true || json['is_online'] == 1,
      lastSeen: DateTimeUtils.parseUtcDateTime(json['last_seen']),
      lastSeenStatus: (json['last_seen_status'] ?? '').toString(),
      isVerified: json['is_verified'] == true || json['is_verified'] == 1,
      isBot: json['is_bot'] == true || json['is_bot'] == 1,
      isFavorite: json['is_favorite'] == true || json['is_favorite'] == 1,
      isMutual: json['is_mutual'] == true || json['is_mutual'] == 1,
      addedAt: DateTimeUtils.parseUtcDateTime(json['added_at']),
      updatedAt: DateTimeUtils.parseUtcDateTime(json['updated_at']),
    );
  }
}

/// Manages Telegram-style server-backed Contacts CRUD (`/api/contacts`).
class ContactsService {
  ContactsService._();

  static final ValueNotifier<List<ContactItem>> contactsNotifier =
      ValueNotifier<List<ContactItem>>(<ContactItem>[]);
  static final Map<String, ContactItem> _cache = <String, ContactItem>{};
  static bool _loadedOnce = false;

  static bool isContactSync(String userId) => _cache.containsKey(userId);
  static ContactItem? getCached(String userId) => _cache[userId];

  static void _replaceCache(List<ContactItem> items) {
    _cache
      ..clear()
      ..addEntries(items.map((e) => MapEntry(e.contactUserId, e)));
    _loadedOnce = true;
    contactsNotifier.value = List<ContactItem>.unmodifiable(items);
  }

  static void clearCache() {
    _cache.clear();
    _loadedOnce = false;
    contactsNotifier.value = <ContactItem>[];
  }

  static Future<List<ContactItem>> getContacts({
    bool forceRefresh = false,
  }) async {
    if (_loadedOnce && !forceRefresh) {
      return contactsNotifier.value;
    }
    try {
      final token = await AuthService.getToken();
      if (token == null) return contactsNotifier.value;
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/contacts'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['contacts'] is List) {
          final items = (data['contacts'] as List)
              .whereType<Map>()
              .map((m) => ContactItem.fromJson(Map<String, dynamic>.from(m)))
              .toList();
          _replaceCache(items);
          return items;
        }
      }
    } catch (e) {
      debugPrint('ContactsService.getContacts error: $e');
    }
    return contactsNotifier.value;
  }

  static Future<Map<String, dynamic>> addContact({
    String? userId,
    String? username,
    String? firstName,
    String? lastName,
    String? nickname,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final body = <String, dynamic>{
        if (userId != null && userId.isNotEmpty)
          'user_id': int.tryParse(userId) ?? userId,
        if (username != null && username.isNotEmpty) 'username': username,
        if (firstName != null) 'custom_first_name': firstName,
        if (lastName != null) 'custom_last_name': lastName,
        if (nickname != null) 'nickname': nickname,
      };
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/contacts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true &&
          data['contact'] is Map) {
        final item = ContactItem.fromJson(
          Map<String, dynamic>.from(data['contact'] as Map),
        );
        _cache[item.contactUserId] = item;
        contactsNotifier.value =
            List<ContactItem>.unmodifiable(_cache.values.toList());
        return {'success': true, 'contact': item};
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? data['description'] ?? 'Не удалось добавить контакт')
                .toString()
            : 'Не удалось добавить контакт',
      };
    } catch (e) {
      debugPrint('ContactsService.addContact error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> updateContact(
    String userId, {
    String? firstName,
    String? lastName,
    String? nickname,
    bool? isFavorite,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final body = <String, dynamic>{
        if (firstName != null) 'custom_first_name': firstName,
        if (lastName != null) 'custom_last_name': lastName,
        if (nickname != null) 'nickname': nickname,
        if (isFavorite != null) 'is_favorite': isFavorite,
      };
      final response = await http.patch(
        Uri.parse('${AppConfig.baseUrl}/api/contacts/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        await getContacts(forceRefresh: true);
        return {'success': true, 'contact': _cache[userId]};
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? 'Не удалось обновить контакт').toString()
            : 'Не удалось обновить контакт',
      };
    } catch (e) {
      debugPrint('ContactsService.updateContact error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> deleteContact(String userId) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/contacts/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        _cache.remove(userId);
        contactsNotifier.value =
            List<ContactItem>.unmodifiable(_cache.values.toList());
        return {'success': true};
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? 'Не удалось удалить контакт').toString()
            : 'Не удалось удалить контакт',
      };
    } catch (e) {
      debugPrint('ContactsService.deleteContact error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}
