import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../utils/date_time_utils.dart';
import 'account_manager.dart';
import 'auth_service.dart';
import 'database/app_database.dart';
import 'websocket_service.dart';

String? _optNonEmptyString(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isNotEmpty ? s : null;
}

bool _parseContactBool(dynamic value, {bool defaultValue = false}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final s = value.toString().trim().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return defaultValue;
}

/// Represents a contact or per-user override entry synced with `/api/contacts`.
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
  final bool isContact;
  final String note;
  final String? customAvatarUrl;
  final String? originalAvatarUrl;
  final String? originalDisplayName;
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
    this.isContact = true,
    this.note = '',
    this.customAvatarUrl,
    this.originalAvatarUrl,
    this.originalDisplayName,
    this.addedAt,
    this.updatedAt,
  });

  /// Returns true when the user has set a local custom photo for this contact.
  bool get hasCustomAvatar =>
      customAvatarUrl != null && customAvatarUrl!.trim().isNotEmpty;

  /// Resolves the effective avatar URL: custom contact photo -> avatarUrl -> originalAvatarUrl.
  String? get effectiveAvatarUrl {
    if (hasCustomAvatar) return customAvatarUrl!.trim();
    if (avatarUrl.trim().isNotEmpty) return avatarUrl.trim();
    if (originalAvatarUrl != null && originalAvatarUrl!.trim().isNotEmpty) {
      return originalAvatarUrl!.trim();
    }
    return null;
  }

  /// Custom name defined locally by the user (first+last or nickname), or empty.
  String get customName {
    final fullCustom = '$customFirstName $customLastName'.trim();
    if (fullCustom.isNotEmpty) return fullCustom;
    if (nickname.trim().isNotEmpty) return nickname.trim();
    return '';
  }

  /// Returns true when the contact has a non-empty local custom name or nickname.
  bool get hasCustomName => customName.isNotEmpty;

  /// Display name resolved in Telegram contact priority:
  /// custom first+last name -> nickname -> originalDisplayName ?? displayName -> @username -> fallback ID.
  String get effectiveName {
    final custom = customName;
    if (custom.isNotEmpty) return custom;
    if (originalDisplayName != null &&
        originalDisplayName!.trim().isNotEmpty) {
      return originalDisplayName!.trim();
    }
    if (displayName.trim().isNotEmpty) return displayName.trim();
    if (username.trim().isNotEmpty) return '@${username.trim()}';
    return 'Пользователь #$contactUserId';
  }

  ContactItem copyWith({
    String? id,
    String? userId,
    String? contactUserId,
    String? username,
    String? displayName,
    String? customFirstName,
    String? customLastName,
    String? nickname,
    String? avatarUrl,
    bool? isOnline,
    DateTime? lastSeen,
    bool clearLastSeen = false,
    String? lastSeenStatus,
    bool? isVerified,
    bool? isBot,
    bool? isFavorite,
    bool? isMutual,
    bool? isContact,
    String? note,
    String? customAvatarUrl,
    bool clearCustomAvatarUrl = false,
    String? originalAvatarUrl,
    bool clearOriginalAvatarUrl = false,
    String? originalDisplayName,
    bool clearOriginalDisplayName = false,
    DateTime? addedAt,
    DateTime? updatedAt,
  }) {
    return ContactItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      contactUserId: contactUserId ?? this.contactUserId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      customFirstName: customFirstName ?? this.customFirstName,
      customLastName: customLastName ?? this.customLastName,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: clearLastSeen ? null : (lastSeen ?? this.lastSeen),
      lastSeenStatus: lastSeenStatus ?? this.lastSeenStatus,
      isVerified: isVerified ?? this.isVerified,
      isBot: isBot ?? this.isBot,
      isFavorite: isFavorite ?? this.isFavorite,
      isMutual: isMutual ?? this.isMutual,
      isContact: isContact ?? this.isContact,
      note: note ?? this.note,
      customAvatarUrl: clearCustomAvatarUrl
          ? null
          : (customAvatarUrl ?? this.customAvatarUrl),
      originalAvatarUrl: clearOriginalAvatarUrl
          ? null
          : (originalAvatarUrl ?? this.originalAvatarUrl),
      originalDisplayName: clearOriginalDisplayName
          ? null
          : (originalDisplayName ?? this.originalDisplayName),
      addedAt: addedAt ?? this.addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'contact_user_id': contactUserId,
        'username': username,
        'display_name': displayName,
        'custom_first_name': customFirstName,
        'custom_last_name': customLastName,
        'nickname': nickname,
        'avatar_url': avatarUrl,
        'is_online': isOnline,
        if (lastSeen != null) 'last_seen': lastSeen!.toUtc().toIso8601String(),
        'last_seen_status': lastSeenStatus,
        'is_verified': isVerified,
        'is_bot': isBot,
        'is_favorite': isFavorite,
        'is_mutual': isMutual,
        'is_contact': isContact,
        'note': note,
        if (customAvatarUrl != null) 'custom_avatar_url': customAvatarUrl,
        if (originalAvatarUrl != null)
          'original_avatar_url': originalAvatarUrl,
        if (originalDisplayName != null)
          'original_display_name': originalDisplayName,
        if (addedAt != null) 'added_at': addedAt!.toUtc().toIso8601String(),
        if (updatedAt != null)
          'updated_at': updatedAt!.toUtc().toIso8601String(),
      };

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
      isOnline: _parseContactBool(json['is_online']),
      lastSeen: DateTimeUtils.parseUtcDateTime(json['last_seen']),
      lastSeenStatus: (json['last_seen_status'] ?? '').toString(),
      isVerified: _parseContactBool(json['is_verified']),
      isBot: _parseContactBool(json['is_bot']),
      isFavorite: _parseContactBool(json['is_favorite']),
      isMutual: _parseContactBool(json['is_mutual']),
      isContact: json.containsKey('is_contact')
          ? _parseContactBool(json['is_contact'], defaultValue: true)
          : true,
      note: (json['note'] ?? '').toString(),
      customAvatarUrl: _optNonEmptyString(json['custom_avatar_url']),
      originalAvatarUrl: _optNonEmptyString(json['original_avatar_url']),
      originalDisplayName: _optNonEmptyString(json['original_display_name']),
      addedAt: DateTimeUtils.parseUtcDateTime(json['added_at']),
      updatedAt: DateTimeUtils.parseUtcDateTime(json['updated_at']),
    );
  }
}

/// Manages Telegram-style server-backed Contacts CRUD & per-user overrides (`/api/contacts`).
class ContactsService {
  ContactsService._();

  static const String _cacheKeyPrefix = 'contacts_cache_v2_';

  /// Emits only saved contacts (`isContact == true`) for contact lists & pickers.
  static final ValueNotifier<List<ContactItem>> contactsNotifier =
      ValueNotifier<List<ContactItem>>(<ContactItem>[]);

  /// Monotonically incremented whenever any contact or non-contact override changes.
  static final ValueNotifier<int> revisionNotifier = ValueNotifier<int>(0);

  /// Holds all cached contact and non-contact override rows for O(1) synchronous lookup.
  static final Map<String, ContactItem> _cache = <String, ContactItem>{};
  static bool _loadedOnce = false;
  static bool _diskLoaded = false;
  static String? _activeUserId;
  static Future<void> _pendingPersist = Future<void>.value();

  static String? _resolveUserId([String? explicitUserId]) {
    if (explicitUserId != null) {
      final t = explicitUserId.trim();
      return t.isNotEmpty ? t : null;
    }
    try {
      final uid = AccountManager().currentAccount?.userId.trim();
      if (uid != null && uid.isNotEmpty) return uid;
    } catch (_) {}
    return _activeUserId;
  }

  static String? _storageKeyForUser(String? userId) {
    final clean = userId?.trim();
    if (clean == null || clean.isEmpty) return null;
    return '$_cacheKeyPrefix$clean';
  }

  /// Returns true only when [userId] is saved as an explicit contact (`isContact == true`).
  static bool isContactSync(String? userId) {
    final uid = userId?.trim();
    if (uid == null || uid.isEmpty) return false;
    return _cache[uid]?.isContact == true;
  }

  /// Returns the cached contact or override entry for [userId], if any.
  static ContactItem? getCached(String? userId) {
    final uid = userId?.trim();
    if (uid == null || uid.isEmpty) return null;
    return _cache[uid];
  }

  /// Alias for [getCached] returning any cached contact or non-contact override.
  static ContactItem? getOverride(String? userId) => getCached(userId);

  /// Returns all saved contacts (`isContact == true`), excluding override-only entries.
  static List<ContactItem> getSavedContacts() => contactsNotifier.value;

  /// Resolves a user's display name synchronously with local contact overrides.
  static String resolveName(
    String? userId,
    String fallback, {
    bool allowAtFallback = false,
  }) {
    final c = getCached(userId);
    if (c != null) {
      final custom = c.customName;
      if (custom.isNotEmpty) return custom;
      if (fallback.trim().isEmpty) {
        if (c.originalDisplayName != null &&
            c.originalDisplayName!.trim().isNotEmpty) {
          return c.originalDisplayName!.trim();
        }
        if (c.displayName.trim().isNotEmpty) {
          return c.displayName.trim();
        }
        if (allowAtFallback && c.username.trim().isNotEmpty) {
          return '@${c.username.trim()}';
        }
        return c.effectiveName;
      }
      if (!allowAtFallback && fallback.trim().startsWith('@')) {
        if (c.originalDisplayName != null &&
            c.originalDisplayName!.trim().isNotEmpty) {
          return c.originalDisplayName!.trim();
        }
        if (c.displayName.trim().isNotEmpty) {
          return c.displayName.trim();
        }
      }
    }
    return fallback;
  }

  /// Resolves a user's avatar URL synchronously, preferring any local custom contact photo.
  static String? resolveAvatarUrl(String? userId, String? fallback) {
    final c = getCached(userId);
    if (c != null && c.hasCustomAvatar) {
      return c.customAvatarUrl;
    }
    return fallback;
  }

  /// Returns true if a local custom avatar override exists for [userId].
  static bool hasCustomAvatarFor(String? userId) {
    final c = getCached(userId);
    return c?.hasCustomAvatar ?? false;
  }

  static void _publishCacheUpdate() {
    contactsNotifier.value = List<ContactItem>.unmodifiable(
      _cache.values.where((c) => c.isContact),
    );
    revisionNotifier.value++;
  }

  static void _persistToDisk() {
    final uid = _resolveUserId();
    final key = _storageKeyForUser(uid);
    if (key == null) return;
    final payload = jsonEncode(_cache.values.map((c) => c.toJson()).toList());
    _pendingPersist = _pendingPersist.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, payload);
      } catch (e) {
        debugPrint('ContactsService._persistToDisk error: $e');
      }
    });
  }

  /// Loads cached contacts & overrides for [userId] from `SharedPreferences`.
  static Future<void> init({String? userId}) async {
    final resolved = _resolveUserId(userId);
    if (_diskLoaded && resolved == _activeUserId) return;
    _activeUserId = resolved;
    _cache.clear();
    _loadedOnce = false;

    final key = _storageKeyForUser(resolved);
    if (key != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(key);
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final entry in decoded) {
              if (entry is Map) {
                final item = ContactItem.fromJson(
                  Map<String, dynamic>.from(entry),
                );
                if (item.contactUserId.isNotEmpty) {
                  _cache[item.contactUserId] = item;
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('ContactsService.init error: $e');
      }
    }
    _diskLoaded = true;
    _publishCacheUpdate();
  }

  /// Switches the active account contact cache and reloads overrides for [userId].
  static Future<void> switchAccount(String? userId) async {
    await _pendingPersist;
    _cache.clear();
    _loadedOnce = false;
    _diskLoaded = false;
    _activeUserId = null;
    contactsNotifier.value = const <ContactItem>[];
    revisionNotifier.value++;
    await init(userId: userId);
  }

  static void _replaceCache(List<ContactItem> items) {
    _cache
      ..clear()
      ..addEntries(
        items
            .where((e) => e.contactUserId.isNotEmpty)
            .map((e) => MapEntry(e.contactUserId, e)),
      );
    _loadedOnce = true;
    _diskLoaded = true;
    _activeUserId ??= _resolveUserId();
    _publishCacheUpdate();
    _persistToDisk();
  }

  static void _upsertCacheItem(ContactItem item) {
    if (item.contactUserId.isEmpty) return;
    _activeUserId ??= _resolveUserId();
    _cache[item.contactUserId] = item;
    _publishCacheUpdate();
    _persistToDisk();
  }

  /// Clears in-memory contact cache and optionally wipes the persisted disk cache.
  static Future<void> clearCache({
    bool clearDisk = false,
    String? userId,
  }) async {
    final targetUser = _resolveUserId(userId);
    if (userId == null ||
        userId.trim().isEmpty ||
        targetUser == _activeUserId) {
      _cache.clear();
      _loadedOnce = false;
      _diskLoaded = false;
      contactsNotifier.value = const <ContactItem>[];
      revisionNotifier.value++;
    }
    if (clearDisk) {
      final key = _storageKeyForUser(targetUser);
      if (key != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(key);
        } catch (e) {
          debugPrint('ContactsService.clearCache disk error: $e');
        }
      }
    }
  }

  static String? _dbNameForItem(ContactItem item) {
    if (item.hasCustomName) return item.customName;
    if (item.originalDisplayName != null &&
        item.originalDisplayName!.trim().isNotEmpty) {
      return item.originalDisplayName!.trim();
    }
    if (item.displayName.trim().isNotEmpty) return item.displayName.trim();
    if (item.username.trim().isNotEmpty) return '@${item.username.trim()}';
    return null;
  }

  static String? _originalNameForDeleted(
    ContactItem? previous,
    Map<String, dynamic>? data,
  ) {
    final fromData = _optNonEmptyString(data?['original_display_name']) ??
        _optNonEmptyString(data?['display_name']);
    if (fromData != null) return fromData;
    final fromDataUsername = _optNonEmptyString(data?['username']);
    if (fromDataUsername != null) return '@$fromDataUsername';
    if (previous != null) {
      if (previous.originalDisplayName != null &&
          previous.originalDisplayName!.trim().isNotEmpty) {
        return previous.originalDisplayName!.trim();
      }
      if (previous.displayName.trim().isNotEmpty) {
        return previous.displayName.trim();
      }
      if (previous.username.trim().isNotEmpty) {
        return '@${previous.username.trim()}';
      }
    }
    return null;
  }

  static String? _originalAvatarForDeleted(
    ContactItem? previous,
    Map<String, dynamic>? data,
  ) {
    final fromData = _optNonEmptyString(data?['original_avatar_url']) ??
        _optNonEmptyString(data?['avatar_url']);
    if (fromData != null) return fromData;
    if (previous != null) {
      if (previous.originalAvatarUrl != null &&
          previous.originalAvatarUrl!.trim().isNotEmpty) {
        return previous.originalAvatarUrl!.trim();
      }
      if (!previous.hasCustomAvatar && previous.avatarUrl.trim().isNotEmpty) {
        return previous.avatarUrl.trim();
      }
    }
    return null;
  }

  static Future<void> _propagateOverride(ContactItem item) async {
    if (item.contactUserId.isEmpty) return;
    try {
      await AppDatabase().applyContactOverrideInDb(
        item.contactUserId,
        effectiveName: _dbNameForItem(item),
        effectiveAvatarUrl: item.effectiveAvatarUrl,
      );
    } catch (e) {
      debugPrint('ContactsService._propagateOverride error: $e');
    }
  }

  static Future<void> _propagateDeleted(
    String userId, {
    ContactItem? previous,
    Map<String, dynamic>? eventData,
  }) async {
    if (userId.isEmpty) return;
    try {
      await AppDatabase().applyContactOverrideInDb(
        userId,
        effectiveName: _originalNameForDeleted(previous, eventData),
        effectiveAvatarUrl: _originalAvatarForDeleted(previous, eventData),
      );
    } catch (e) {
      debugPrint('ContactsService._propagateDeleted error: $e');
    }
  }

  static ContactItem _mergeServerContact(
    ContactItem? existing,
    Map<String, dynamic> map, {
    String? fallbackUserId,
  }) {
    final hasProfileFields = map.containsKey('username') ||
        map.containsKey('display_name') ||
        map.containsKey('original_display_name');
    if (hasProfileFields || existing == null) {
      final parsed = ContactItem.fromJson({
        if (fallbackUserId != null &&
            !map.containsKey('contact_user_id') &&
            !map.containsKey('user_id'))
          'contact_user_id': fallbackUserId,
        ...map,
      });
      return parsed.copyWith(
        isContact: map.containsKey('is_contact')
            ? parsed.isContact
            : (existing?.isContact ?? parsed.isContact),
        originalAvatarUrl: parsed.originalAvatarUrl ??
            (existing?.originalAvatarUrl ??
                (existing != null &&
                        !existing.hasCustomAvatar &&
                        existing.avatarUrl.isNotEmpty
                    ? existing.avatarUrl
                    : null)),
        originalDisplayName:
            parsed.originalDisplayName ?? existing?.originalDisplayName,
      );
    }

    final hasCustomAvatarKey = map.containsKey('custom_avatar_url');
    final nextCustomAvatar = hasCustomAvatarKey
        ? _optNonEmptyString(map['custom_avatar_url'])
        : existing.customAvatarUrl;
    return existing.copyWith(
      customFirstName: map.containsKey('custom_first_name')
          ? (map['custom_first_name'] ?? '').toString()
          : existing.customFirstName,
      customLastName: map.containsKey('custom_last_name')
          ? (map['custom_last_name'] ?? '').toString()
          : existing.customLastName,
      nickname: map.containsKey('nickname')
          ? (map['nickname'] ?? '').toString()
          : existing.nickname,
      note: map.containsKey('note')
          ? (map['note'] ?? '').toString()
          : existing.note,
      isFavorite: map.containsKey('is_favorite')
          ? _parseContactBool(map['is_favorite'])
          : existing.isFavorite,
      isContact: map.containsKey('is_contact')
          ? _parseContactBool(map['is_contact'], defaultValue: true)
          : existing.isContact,
      customAvatarUrl: nextCustomAvatar,
      clearCustomAvatarUrl: hasCustomAvatarKey && nextCustomAvatar == null,
      updatedAt: map.containsKey('updated_at')
          ? DateTimeUtils.parseUtcDateTime(map['updated_at'])
          : existing.updatedAt,
    );
  }

  static dynamic _tryDecodeJson(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static MediaType _imageMediaType(String fileName) {
    final ext = path.extension(fileName).toLowerCase();
    switch (ext) {
      case '.png':
        return MediaType('image', 'png');
      case '.gif':
        return MediaType('image', 'gif');
      case '.webp':
        return MediaType('image', 'webp');
      default:
        return MediaType('image', 'jpeg');
    }
  }

  static Future<Map<String, dynamic>> _sendAvatarMultipart(
    String urlPath,
    File file, {
    Uint8List? bytes,
    String? fileName,
    String fallbackError = 'Failed to upload photo',
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}$urlPath'),
      );
      request.headers['Authorization'] = 'Bearer $token';

      if (bytes != null) {
        final resolvedName = (fileName != null && fileName.trim().isNotEmpty)
            ? path.basename(fileName.trim())
            : (file.path.isNotEmpty
                ? path.basename(file.path)
                : 'avatar.jpg');
        request.files.add(
          http.MultipartFile.fromBytes(
            'avatar',
            bytes,
            filename: resolvedName,
            contentType: _imageMediaType(resolvedName),
          ),
        );
      } else {
        if (!await file.exists()) {
          return {'success': false, 'message': 'File not found'};
        }
        final resolvedName = (fileName != null && fileName.trim().isNotEmpty)
            ? path.basename(fileName.trim())
            : path.basename(file.path);
        request.files.add(
          await http.MultipartFile.fromPath(
            'avatar',
            file.path,
            filename: resolvedName,
            contentType: _imageMediaType(resolvedName),
          ),
        );
      }

      final streamed = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('Upload timed out'),
      );
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 30));
      final data = _tryDecodeJson(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data is Map &&
          data['success'] == true) {
        return {
          'success': true,
          'status_code': response.statusCode,
          'data': Map<String, dynamic>.from(data),
        };
      }
      return {
        'success': false,
        'status_code': response.statusCode,
        'message': data is Map
            ? (data['message'] ?? data['description'] ?? fallbackError)
                .toString()
            : fallbackError,
      };
    } catch (e) {
      debugPrint('ContactsService._sendAvatarMultipart error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Fetches saved contacts and (when [includeOverrides] is true) non-contact overrides.
  static Future<List<ContactItem>> getContacts({
    bool forceRefresh = false,
    bool includeOverrides = true,
  }) async {
    final activeUid = _resolveUserId();
    if (activeUid != null && _activeUserId != null && activeUid != _activeUserId) {
      await switchAccount(activeUid);
    } else if (!_diskLoaded) {
      await init(userId: activeUid);
    }

    if (_loadedOnce && !forceRefresh) {
      return getSavedContacts();
    }

    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) return getSavedContacts();
      final query = includeOverrides ? '?include_overrides=true' : '';
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/contacts$query'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = _tryDecodeJson(response.body);
        if (data is Map && data['contacts'] is List) {
          final prevCache = Map<String, ContactItem>.from(_cache);
          final parsed = (data['contacts'] as List)
              .whereType<Map>()
              .map((m) => ContactItem.fromJson(Map<String, dynamic>.from(m)))
              .where((c) => c.contactUserId.isNotEmpty)
              .toList();

          final nextList = includeOverrides
              ? parsed
              : <ContactItem>[
                  ...parsed,
                  ...prevCache.values.where(
                    (c) =>
                        !c.isContact &&
                        !parsed.any((p) => p.contactUserId == c.contactUserId),
                  ),
                ];

          _replaceCache(nextList);

          // Sync changed or customized overrides into Drift without scanning unmodified rows.
          final nextIds = nextList.map((e) => e.contactUserId).toSet();
          for (final item in nextList) {
            final prev = prevCache[item.contactUserId];
            final changed = prev == null
                ? (item.hasCustomName || item.hasCustomAvatar)
                : (prev.effectiveName != item.effectiveName ||
                    prev.effectiveAvatarUrl != item.effectiveAvatarUrl);
            if (changed) {
              unawaited(_propagateOverride(item));
            }
          }
          for (final entry in prevCache.entries) {
            if (!nextIds.contains(entry.key) &&
                (entry.value.hasCustomName || entry.value.hasCustomAvatar)) {
              unawaited(_propagateDeleted(entry.key, previous: entry.value));
            }
          }

          return getSavedContacts();
        }
      }
    } catch (e) {
      debugPrint('ContactsService.getContacts error: $e');
    }
    return getSavedContacts();
  }

  /// Creates or updates a contact or non-contact override (`POST /api/contacts`).
  static Future<Map<String, dynamic>> addContact({
    String? userId,
    String? username,
    String? firstName,
    String? lastName,
    String? nickname,
    String? note,
    bool isContact = true,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final body = <String, dynamic>{
        if (userId != null && userId.isNotEmpty)
          'user_id': int.tryParse(userId) ?? userId,
        if (username != null && username.isNotEmpty) 'username': username,
        if (firstName != null) 'custom_first_name': firstName,
        if (lastName != null) 'custom_last_name': lastName,
        if (nickname != null) 'nickname': nickname,
        if (note != null) 'note': note,
        'is_contact': isContact,
      };
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/contacts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      final data = _tryDecodeJson(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data is Map &&
          data['success'] == true &&
          data['contact'] is Map) {
        final rawMap = Map<String, dynamic>.from(data['contact'] as Map);
        final cid =
            (rawMap['contact_user_id'] ?? rawMap['user_id'] ?? userId ?? '')
                .toString();
        final item = _mergeServerContact(
          _cache[cid],
          rawMap,
          fallbackUserId: cid,
        );
        _upsertCacheItem(item);
        unawaited(_propagateOverride(item));
        return {'success': true, 'contact': item};
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ??
                    data['description'] ??
                    'Не удалось добавить контакт')
                .toString()
            : 'Не удалось добавить контакт',
      };
    } catch (e) {
      debugPrint('ContactsService.addContact error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Updates an existing contact or per-user override (`PATCH /api/contacts/:userId`).
  static Future<Map<String, dynamic>> updateContact(
    String userId, {
    String? firstName,
    String? lastName,
    String? nickname,
    String? note,
    bool? isFavorite,
    bool? isContact,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final body = <String, dynamic>{
        if (firstName != null) 'custom_first_name': firstName,
        if (lastName != null) 'custom_last_name': lastName,
        if (nickname != null) 'nickname': nickname,
        if (note != null) 'note': note,
        if (isFavorite != null) 'is_favorite': isFavorite,
        if (isContact != null) 'is_contact': isContact,
      };
      final response = await http.patch(
        Uri.parse('${AppConfig.baseUrl}/api/contacts/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
        if (data['contact'] is Map) {
          final merged = _mergeServerContact(
            _cache[userId],
            Map<String, dynamic>.from(data['contact'] as Map),
            fallbackUserId: userId,
          );
          _upsertCacheItem(merged);
          unawaited(_propagateOverride(merged));
          if (merged.username.isEmpty && merged.displayName.isEmpty) {
            await getContacts(forceRefresh: true);
          }
        } else {
          await getContacts(forceRefresh: true);
          final refreshed = _cache[userId];
          if (refreshed != null) {
            unawaited(_propagateOverride(refreshed));
          }
        }
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

  /// Removes a user from contacts (`DELETE /api/contacts/:userId`).
  static Future<Map<String, dynamic>> deleteContact(String userId) async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final previous = _cache[userId];
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/contacts/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
        if (data['contact'] is Map) {
          final remaining = _mergeServerContact(
            previous,
            Map<String, dynamic>.from(data['contact'] as Map),
            fallbackUserId: userId,
          );
          _upsertCacheItem(remaining);
          unawaited(_propagateOverride(remaining));
          return {'success': true, 'contact': remaining};
        }
        _cache.remove(userId);
        _publishCacheUpdate();
        _persistToDisk();
        unawaited(
          _propagateDeleted(
            userId,
            previous: previous,
            eventData: Map<String, dynamic>.from(data),
          ),
        );
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

  /// Uploads and sets a custom local photo for [userId] (`POST /api/contacts/:userId/avatar`).
  static Future<Map<String, dynamic>> setCustomAvatar(
    String userId,
    File file, {
    Uint8List? bytes,
    String? fileName,
  }) async {
    final res = await _sendAvatarMultipart(
      '/api/contacts/$userId/avatar',
      file,
      bytes: bytes,
      fileName: fileName,
      fallbackError: 'Failed to set contact photo',
    );
    if (res['success'] != true) return res;

    final data = res['data'] as Map<String, dynamic>;
    final prev = _cache[userId];
    ContactItem? updated;
    if (data['contact'] is Map) {
      updated = _mergeServerContact(
        prev,
        Map<String, dynamic>.from(data['contact'] as Map),
        fallbackUserId: userId,
      );
    } else {
      final customUrl = _optNonEmptyString(
        data['custom_avatar_url'] ?? data['avatar_url'],
      );
      if (prev != null) {
        updated = prev.copyWith(
          customAvatarUrl: customUrl,
          originalAvatarUrl: prev.originalAvatarUrl ??
              (!prev.hasCustomAvatar && prev.avatarUrl.isNotEmpty
                  ? prev.avatarUrl
                  : null),
        );
      } else if (customUrl != null) {
        updated = ContactItem(
          id: userId,
          userId: userId,
          contactUserId: userId,
          isContact: false,
          customAvatarUrl: customUrl,
        );
      }
    }

    if (updated != null) {
      _upsertCacheItem(updated);
      unawaited(_propagateOverride(updated));
    }
    return {
      'success': true,
      if (updated != null) 'contact': updated,
      'custom_avatar_url':
          updated?.customAvatarUrl ?? _optNonEmptyString(data['custom_avatar_url'] ?? data['avatar_url']),
      'message': data['message'] ?? 'Custom photo updated',
    };
  }

  /// Removes a previously set custom photo for [userId] (`DELETE /api/contacts/:userId/avatar`).
  static Future<Map<String, dynamic>> resetCustomAvatar(String userId) async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final prev = _cache[userId];
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/contacts/$userId/avatar'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
        if (data['contact'] is Map) {
          final updated = _mergeServerContact(
            prev,
            Map<String, dynamic>.from(data['contact'] as Map),
            fallbackUserId: userId,
          );
          _upsertCacheItem(updated);
          unawaited(_propagateOverride(updated));
          return {
            'success': true,
            'contact': updated,
            'message': data['message'] ?? 'Custom photo removed',
          };
        }

        if (prev != null) {
          final hasRemainingData =
              prev.isContact || prev.hasCustomName || prev.note.trim().isNotEmpty;
          if (!hasRemainingData) {
            _cache.remove(userId);
            _publishCacheUpdate();
            _persistToDisk();
            unawaited(
              _propagateDeleted(
                userId,
                previous: prev,
                eventData: Map<String, dynamic>.from(data),
              ),
            );
            return {
              'success': true,
              'message': data['message'] ?? 'Custom photo removed',
            };
          }
          final restoredAvatar =
              _optNonEmptyString(data['original_avatar_url']) ??
                  _optNonEmptyString(data['avatar_url']) ??
                  prev.originalAvatarUrl ??
                  (prev.avatarUrl != prev.customAvatarUrl ? prev.avatarUrl : '');
          final updated = prev.copyWith(
            clearCustomAvatarUrl: true,
            avatarUrl: restoredAvatar,
          );
          _upsertCacheItem(updated);
          unawaited(_propagateOverride(updated));
          return {
            'success': true,
            'contact': updated,
            'message': data['message'] ?? 'Custom photo removed',
          };
        }

        unawaited(
          _propagateDeleted(
            userId,
            eventData: Map<String, dynamic>.from(data),
          ),
        );
        return {
          'success': true,
          'message': data['message'] ?? 'Custom photo removed',
        };
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? 'Failed to remove custom photo').toString()
            : 'Failed to remove custom photo',
      };
    } catch (e) {
      debugPrint('ContactsService.resetCustomAvatar error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Suggests a profile photo to [userId] via private chat (`POST /api/contacts/:userId/suggest-photo`).
  static Future<Map<String, dynamic>> suggestPhoto(
    String userId,
    File file, {
    Uint8List? bytes,
    String? fileName,
  }) async {
    final res = await _sendAvatarMultipart(
      '/api/contacts/$userId/suggest-photo',
      file,
      bytes: bytes,
      fileName: fileName,
      fallbackError: 'Failed to suggest photo',
    );
    if (res['success'] != true) return res;

    final data = res['data'] as Map<String, dynamic>;
    final chatId =
        _optNonEmptyString(data['chat_id'] ?? data['chatId']) ?? '';
    final photoUrl = _optNonEmptyString(
          data['photo_url'] ?? data['photoUrl'] ?? data['avatar_url'],
        ) ??
        '';
    return {
      'success': true,
      'chatId': chatId,
      'chat_id': chatId,
      'photoUrl': photoUrl,
      'photo_url': photoUrl,
      if (data['message_id'] != null) 'message_id': data['message_id'],
      'message': data['message'] ?? 'Photo suggested',
    };
  }

  /// Applies a suggested photo URL to the current user's profile (`POST /api/user/avatar/from-suggested`).
  static Future<Map<String, dynamic>> applySuggestedAvatar(
    String photoUrl,
  ) async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/user/avatar/from-suggested'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'photo_url': photoUrl}),
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
        final newAvatarUrl =
            _optNonEmptyString(data['avatar_url'] ?? data['photo_url']) ??
                photoUrl;
        final accountManager = AccountManager();
        if (accountManager.currentAccount != null) {
          await accountManager.updateAccountProfile(
            accountManager.currentAccount!.userId,
            avatarUrl: newAvatarUrl,
          );
        }
        return {
          'success': true,
          'avatar_url': newAvatarUrl,
          if (data['avatar_id'] != null) 'avatar_id': data['avatar_id'],
          'message': data['message'] ?? 'Avatar updated',
        };
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? 'Failed to apply suggested avatar')
                .toString()
            : 'Failed to apply suggested avatar',
      };
    } catch (e) {
      debugPrint('ContactsService.applySuggestedAvatar error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Applies a real-time or delta-sync contact event (`contact_updated` / `contact_deleted`).
  static Future<void> applyRemoteContactEvent(
    WebSocketEventType type,
    Map<String, dynamic> data,
  ) async {
    if (type == WebSocketEventType.contactUpdated) {
      final rawMap = data['contact'] is Map
          ? Map<String, dynamic>.from(data['contact'] as Map)
          : data;
      final cid = (rawMap['contact_user_id'] ??
              rawMap['user_id'] ??
              rawMap['id'] ??
              '')
          .toString()
          .trim();
      if (cid.isEmpty) return;
      final merged = _mergeServerContact(
        _cache[cid],
        rawMap,
        fallbackUserId: cid,
      );
      _upsertCacheItem(merged);
      await _propagateOverride(merged);
      return;
    }

    if (type == WebSocketEventType.contactDeleted) {
      final uid = (data['contact_user_id'] ??
              data['deleted_user_id'] ??
              data['user_id'] ??
              data['id'] ??
              '')
          .toString()
          .trim();
      if (uid.isEmpty) return;

      final previous = _cache[uid];
      if (data['contact'] is Map) {
        final remaining = _mergeServerContact(
          previous,
          Map<String, dynamic>.from(data['contact'] as Map),
          fallbackUserId: uid,
        );
        _upsertCacheItem(remaining);
        await _propagateOverride(remaining);
        return;
      }

      _cache.remove(uid);
      _publishCacheUpdate();
      _persistToDisk();
      await _propagateDeleted(uid, previous: previous, eventData: data);
    }
  }
}
