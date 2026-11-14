import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/profile_customization.dart';
import 'auth_service.dart';

/// Singleton synchronous cache + SharedPreferences LRU store (max 500 peers)
/// for peer avatar decorations, emoji statuses, badges, and customization catalogs.
class PeerCustomizationCache extends ChangeNotifier {
  static final PeerCustomizationCache instance = PeerCustomizationCache._internal();
  factory PeerCustomizationCache() => instance;
  PeerCustomizationCache._internal();

  static const int maxEntries = 500;
  static const String _prefsKey = 'peer_customizations_lru_v1';

  final Map<String, PeerCustomization> _peers = <String, PeerCustomization>{};
  List<AvatarDecorationPreset> _decorations = AvatarDecorationPreset.builtInDefaults;
  List<UserBadge> _badgesCatalog = UserBadge.builtInDefaults;

  bool _initialized = false;
  bool _catalogsFetched = false;
  Timer? _persistDebounce;

  List<AvatarDecorationPreset> get decorationsCatalog => List.unmodifiable(_decorations);
  List<UserBadge> get badgesCatalog => List.unmodifiable(_badgesCatalog);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key != null && value is Map) {
              _putInternal(
                key.toString(),
                PeerCustomization.fromJson(Map<String, dynamic>.from(value)),
              );
            }
          });
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[PeerCustomizationCache] Failed to load cache: $e');
    }
  }

  void _putInternal(String userId, PeerCustomization value) {
    if (userId.isEmpty) return;
    _peers.remove(userId);
    _peers[userId] = value;
    while (_peers.length > maxEntries) {
      _peers.remove(_peers.keys.first);
    }
  }

  /// Synchronously retrieves cached peer customization (or `null`), filtering expired emoji status.
  PeerCustomization? getSync(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    final entry = _peers[userId];
    if (entry == null) return null;
    // Touch LRU entry cleanly
    _peers.remove(userId);
    _peers[userId] = entry;
    if (entry.emojiStatus != null && entry.emojiStatus!.isExpired) {
      final cleaned = PeerCustomization(
        nameColorPresetId: entry.nameColorPresetId,
        replyStripStyle: entry.replyStripStyle,
        profileColorPresetId: entry.profileColorPresetId,
        avatarDecoration: entry.avatarDecoration,
        emojiStatus: null,
        badge: entry.badge,
        badgeIsDisplayed: entry.badgeIsDisplayed,
        profileBannerUrl: entry.profileBannerUrl,
      );
      _peers[userId] = cleaned;
      return cleaned;
    }
    return entry;
  }

  void put(String userId, PeerCustomization value, {bool notify = true}) {
    if (userId.isEmpty) return;
    _putInternal(userId, value);
    _schedulePersist();
    if (notify) {
      notifyListeners();
    }
  }

  void mergeFromJson(String userId, Map<String, dynamic> map, {bool notify = true}) {
    if (userId.isEmpty) return;
    final existing = _peers[userId];
    final next = existing != null
        ? existing.mergeAppearanceMap(map)
        : PeerCustomization.fromJson(map);
    put(userId, next, notify: notify);
  }

  void putFromJsonString(String? userId, String? rawJson, {bool notify = false}) {
    if (userId == null || userId.isEmpty || rawJson == null || rawJson.isEmpty) return;
    final parsed = PeerCustomization.tryParseJsonString(rawJson);
    if (parsed != null) {
      put(userId, parsed, notify: notify);
    }
  }

  AvatarDecorationPreset? findDecorationById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final d in _decorations) {
      if (d.id == id) return d;
    }
    return null;
  }

  UserBadge? findBadgeById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final b in _badgesCatalog) {
      if (b.id == id) return b;
    }
    return null;
  }

  void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 500), () {
      _persistNow();
    });
  }

  Future<void> _persistNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serialized = <String, dynamic>{};
      _peers.forEach((uid, cust) {
        serialized[uid] = cust.toJson();
      });
      await prefs.setString(_prefsKey, jsonEncode(serialized));
    } catch (e) {
      debugPrint('[PeerCustomizationCache] Failed to persist LRU: $e');
    }
  }

  /// Refreshes `/api/decorations` and `/api/badges/catalog` from the server.
  Future<void> refreshCatalogs({String? token, bool force = false}) async {
    if (_catalogsFetched && !force) return;
    try {
      final authToken = token ?? await AuthService.getToken();
      if (authToken == null || authToken.isEmpty) return;
      final headers = {
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      };

      final responses = await Future.wait([
        http.get(Uri.parse('${AppConfig.baseUrl}/api/decorations'), headers: headers),
        http.get(Uri.parse('${AppConfig.baseUrl}/api/badges/catalog'), headers: headers),
      ]);

      bool updated = false;
      if (responses[0].statusCode == 200) {
        final decBody = jsonDecode(responses[0].body);
        if (decBody is Map && decBody['decorations'] is List) {
          final loaded = (decBody['decorations'] as List)
              .whereType<Map>()
              .map((m) => AvatarDecorationPreset.fromJson(Map<String, dynamic>.from(m)))
              .where((d) => d.id.isNotEmpty)
              .toList();
          if (loaded.isNotEmpty) {
            _decorations = loaded;
            updated = true;
          }
        }
      }
      if (responses[1].statusCode == 200) {
        final badgeBody = jsonDecode(responses[1].body);
        if (badgeBody is Map && badgeBody['badges'] is List) {
          final loaded = (badgeBody['badges'] as List)
              .whereType<Map>()
              .map((m) => UserBadge.fromJson(Map<String, dynamic>.from(m)))
              .where((b) => b.id.isNotEmpty)
              .toList();
          if (loaded.isNotEmpty) {
            _badgesCatalog = loaded;
            updated = true;
          }
        }
      }
      _catalogsFetched = true;
      if (updated) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[PeerCustomizationCache] refreshCatalogs error: $e');
    }
  }

  @visibleForTesting
  void clearForTesting() {
    _persistDebounce?.cancel();
    _peers.clear();
    _decorations = AvatarDecorationPreset.builtInDefaults;
    _badgesCatalog = UserBadge.builtInDefaults;
    _catalogsFetched = false;
  }
}
