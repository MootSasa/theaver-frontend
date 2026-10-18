import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../widgets/profile/profile_content_tabs.dart';
import 'account_manager.dart';
import 'auth_service.dart';
import 'avatar_sync_service.dart';
import 'database/app_database.dart';
import 'profile_theme_provider.dart';

/// Синхронный снимок данных профиля пользователя (своего или собеседника) для мгновенного открытия без lazy-загрузки.
class CachedUserProfileSnapshot {
  final String userId;
  final String name;
  final String surname;
  final String username;
  final String email;
  final String phone;
  final String? bio;
  final DateTime? birthday;
  final String? avatarUrl;
  final List<String> avatarUrls;
  final List<int> avatarIds;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? musicTitle;
  final String? musicAuthor;
  final bool isMuted;
  final bool isBlocked;
  final String? resolvedChatId;
  final String? colorPresetId;

  const CachedUserProfileSnapshot({
    required this.userId,
    this.name = '',
    this.surname = '',
    this.username = '',
    this.email = '',
    this.phone = '',
    this.bio,
    this.birthday,
    this.avatarUrl,
    this.avatarUrls = const [],
    this.avatarIds = const [],
    this.isOnline = false,
    this.lastSeen,
    this.musicTitle,
    this.musicAuthor,
    this.isMuted = false,
    this.isBlocked = false,
    this.resolvedChatId,
    this.colorPresetId,
  });

  CachedUserProfileSnapshot copyWith({
    String? name,
    String? surname,
    String? username,
    String? email,
    String? phone,
    String? bio,
    DateTime? birthday,
    String? avatarUrl,
    List<String>? avatarUrls,
    List<int>? avatarIds,
    bool? isOnline,
    DateTime? lastSeen,
    String? musicTitle,
    String? musicAuthor,
    bool? isMuted,
    bool? isBlocked,
    String? resolvedChatId,
    String? colorPresetId,
  }) {
    return CachedUserProfileSnapshot(
      userId: userId,
      name: name ?? this.name,
      surname: surname ?? this.surname,
      username: username ?? this.username,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      bio: bio ?? this.bio,
      birthday: birthday ?? this.birthday,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarUrls: avatarUrls ?? this.avatarUrls,
      avatarIds: avatarIds ?? this.avatarIds,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      musicTitle: musicTitle ?? this.musicTitle,
      musicAuthor: musicAuthor ?? this.musicAuthor,
      isMuted: isMuted ?? this.isMuted,
      isBlocked: isBlocked ?? this.isBlocked,
      resolvedChatId: resolvedChatId ?? this.resolvedChatId,
      colorPresetId: colorPresetId ?? this.colorPresetId,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'surname': surname,
        'username': username,
        'email': email,
        'phone': phone,
        'bio': bio,
        'birthday': birthday?.toIso8601String(),
        'avatarUrl': avatarUrl,
        'avatarUrls': avatarUrls,
        'avatarIds': avatarIds,
        'isOnline': isOnline,
        'lastSeen': lastSeen?.toIso8601String(),
        'musicTitle': musicTitle,
        'musicAuthor': musicAuthor,
        'isMuted': isMuted,
        'isBlocked': isBlocked,
        'resolvedChatId': resolvedChatId,
        'colorPresetId': colorPresetId,
      };

  factory CachedUserProfileSnapshot.fromJson(Map<String, dynamic> json) {
    return CachedUserProfileSnapshot(
      userId: (json['userId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      surname: (json['surname'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      bio: json['bio']?.toString(),
      birthday: json['birthday'] != null
          ? DateTime.tryParse(json['birthday'].toString())
          : null,
      avatarUrl: json['avatarUrl']?.toString(),
      avatarUrls: (json['avatarUrls'] as List?)
              ?.map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
      avatarIds: (json['avatarIds'] as List?)
              ?.map((e) => e is int ? e : (e as num).toInt())
              .toList() ??
          const [],
      isOnline: json['isOnline'] == true,
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'].toString())
          : null,
      musicTitle: json['musicTitle']?.toString(),
      musicAuthor: json['musicAuthor']?.toString(),
      isMuted: json['isMuted'] == true,
      isBlocked: json['isBlocked'] == true,
      resolvedChatId: json['resolvedChatId']?.toString(),
      colorPresetId: json['colorPresetId']?.toString(),
    );
  }
}

/// Синхронный снимок данных профиля группы или канала.
class CachedGroupProfileSnapshot {
  final String chatId;
  final String name;
  final String description;
  final String inviteLink;
  final bool isPublic;
  final bool historyForNew;
  final int slowModeInterval;
  final int memberCount;
  final String myRole;
  final String? avatarUrl;
  final List<ProfileMemberItem> members;
  final bool isMuted;

  const CachedGroupProfileSnapshot({
    required this.chatId,
    this.name = '',
    this.description = '',
    this.inviteLink = '',
    this.isPublic = false,
    this.historyForNew = true,
    this.slowModeInterval = 0,
    this.memberCount = 0,
    this.myRole = 'member',
    this.avatarUrl,
    this.members = const [],
    this.isMuted = false,
  });

  Map<String, dynamic> toJson() => {
        'chatId': chatId,
        'name': name,
        'description': description,
        'inviteLink': inviteLink,
        'isPublic': isPublic,
        'historyForNew': historyForNew,
        'slowModeInterval': slowModeInterval,
        'memberCount': memberCount,
        'myRole': myRole,
        'avatarUrl': avatarUrl,
        'isMuted': isMuted,
        'members': members
            .map((m) => {
                  'user_id': m.userId,
                  'name': m.name,
                  'surname': m.surname,
                  'username': m.username,
                  'avatar_url': m.avatarUrl,
                  'role': m.role,
                  'is_online': m.isOnline,
                  'last_seen': m.lastSeen,
                })
            .toList(),
      };

  factory CachedGroupProfileSnapshot.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'] as List?;
    return CachedGroupProfileSnapshot(
      chatId: (json['chatId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      inviteLink: (json['inviteLink'] ?? '').toString(),
      isPublic: json['isPublic'] == true,
      historyForNew: json['historyForNew'] ?? true,
      slowModeInterval: (json['slowModeInterval'] as num?)?.toInt() ?? 0,
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      myRole: (json['myRole'] ?? 'member').toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      isMuted: json['isMuted'] == true,
      members: rawMembers
              ?.whereType<Map>()
              .map((m) =>
                  ProfileMemberItem.fromJson(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
    );
  }
}

/// Синхронный снимок вкладок общих материалов чата (Медиа, Файлы, Ссылки, Голосовые).
class CachedSharedContentSnapshot {
  final List<DbMessage> mediaMessages;
  final List<DbMessage> fileMessages;
  final List<DbMessage> linkMessages;
  final List<DbMessage> voiceMessages;

  const CachedSharedContentSnapshot({
    this.mediaMessages = const [],
    this.fileMessages = const [],
    this.linkMessages = const [],
    this.voiceMessages = const [],
  });
}

/// Глобальный in-memory + disk кэш профилей для мгновенного (0 мс, Frame 0) открытия `ProfileScreen`.
class ProfileInstantCache {
  static final ProfileInstantCache instance = ProfileInstantCache._internal();
  factory ProfileInstantCache() => instance;
  ProfileInstantCache._internal();

  static const String _kUserCachePrefix = 'instant_profile_user_v1_';
  static const String _kGroupCachePrefix = 'instant_profile_group_v1_';

  final Map<String, CachedUserProfileSnapshot> _userSnapshots = {};
  final Map<String, CachedGroupProfileSnapshot> _groupSnapshots = {};
  final Map<String, CachedSharedContentSnapshot> _sharedContentSnapshots = {};
  final Map<String, ProfileColorPreset> _colorPresets = {};
  final Map<String, double> _avatarLuminanceCache = {};
  final Set<String> _blockedUserIds = {};

  SharedPreferences? _prefs;
  bool _initialized = false;

  /// Инициализация при старте приложения: синхронно поднимает в RAM все сохранённые снимки профилей и цветов.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;

      for (final key in prefs.getKeys()) {
        if (key.startsWith(_kUserCachePrefix)) {
          final raw = prefs.getString(key);
          if (raw != null && raw.isNotEmpty) {
            try {
              final map = jsonDecode(raw) as Map<String, dynamic>;
              final snap = CachedUserProfileSnapshot.fromJson(map);
              if (snap.userId.isNotEmpty) {
                _userSnapshots[snap.userId] = snap;
                if (snap.colorPresetId != null &&
                    snap.colorPresetId!.isNotEmpty) {
                  _colorPresets[snap.userId] =
                      ProfileColorPresets.getById(snap.colorPresetId!);
                }
              }
            } catch (_) {}
          }
        } else if (key.startsWith(_kGroupCachePrefix)) {
          final raw = prefs.getString(key);
          if (raw != null && raw.isNotEmpty) {
            try {
              final map = jsonDecode(raw) as Map<String, dynamic>;
              final snap = CachedGroupProfileSnapshot.fromJson(map);
              if (snap.chatId.isNotEmpty) {
                _groupSnapshots[snap.chatId] = snap;
              }
            } catch (_) {}
          }
        } else if (key.endsWith('_profile_color_preset_id') &&
            key != 'profile_color_preset_id') {
          final uid =
              key.substring(0, key.length - '_profile_color_preset_id'.length);
          final presetId = prefs.getString(key);
          if (uid.isNotEmpty && presetId != null && presetId.isNotEmpty) {
            _colorPresets[uid] = ProfileColorPresets.getById(presetId);
          }
        }
      }

      // Сразу формируем начальный снимок текущего аккаунта
      _syncCurrentAccountToMemory(prefs);
    } catch (e) {
      debugPrint('[ProfileInstantCache] init error: $e');
    }
  }

  void _syncCurrentAccountToMemory([SharedPreferences? prefs]) {
    final acc = AccountManager().currentAccount;
    if (acc == null) return;
    final p = prefs ?? _prefs;
    final uid = acc.userId;
    final musicTitle = p?.getString('${uid}_profile_music_title');
    final musicAuthor = p?.getString('${uid}_profile_music_author');
    final presetId = p?.getString('${uid}_profile_color_preset_id');
    final localHistory =
        p?.getStringList('local_avatar_history_$uid') ?? const <String>[];

    final existing = _userSnapshots[uid];
    final combinedAvatars = <String>[
      ...localHistory.where((s) => s.isNotEmpty),
      if (existing != null) ...existing.avatarUrls,
      if (acc.avatarUrl != null && acc.avatarUrl!.isNotEmpty) acc.avatarUrl!,
    ];
    final dedupedAvatars = <String>[];
    for (final u in combinedAvatars) {
      if (u.isNotEmpty && !dedupedAvatars.contains(u)) {
        dedupedAvatars.add(u);
      }
    }

    _userSnapshots[uid] = CachedUserProfileSnapshot(
      userId: uid,
      name: acc.name ?? existing?.name ?? '',
      surname: acc.surname ?? existing?.surname ?? '',
      username: acc.username ?? existing?.username ?? '',
      email: acc.email ?? existing?.email ?? '',
      phone: acc.phone ?? existing?.phone ?? '',
      bio: acc.bio ?? existing?.bio,
      birthday: acc.birthday ?? existing?.birthday,
      avatarUrl: dedupedAvatars.isNotEmpty
          ? dedupedAvatars.first
          : (acc.avatarUrl ?? existing?.avatarUrl),
      avatarUrls: dedupedAvatars,
      avatarIds: existing?.avatarIds ?? const [],
      isOnline: true,
      musicTitle: musicTitle ?? existing?.musicTitle,
      musicAuthor: musicAuthor ?? existing?.musicAuthor,
      resolvedChatId: existing?.resolvedChatId,
      colorPresetId: presetId ?? existing?.colorPresetId,
    );
    if (presetId != null && presetId.isNotEmpty) {
      _colorPresets[uid] = ProfileColorPresets.getById(presetId);
    }
  }

  // ============================================================
  // Синхронные геттеры для Frame 0 в ProfileScreen.initState()
  // ============================================================

  CachedUserProfileSnapshot? getSelfSnapshotSync() {
    _syncCurrentAccountToMemory();
    final uid = AccountManager().currentAccount?.userId;
    if (uid == null || uid.isEmpty) return null;
    return _userSnapshots[uid];
  }

  CachedUserProfileSnapshot? getUserSnapshotSync(String userId) {
    if (userId.isEmpty) return null;
    return _userSnapshots[userId];
  }

  CachedGroupProfileSnapshot? getGroupSnapshotSync(String chatId) {
    if (chatId.isEmpty) return null;
    return _groupSnapshots[chatId];
  }

  CachedSharedContentSnapshot? getSharedContentSync(String? chatId) {
    if (chatId == null || chatId.isEmpty) return null;
    return _sharedContentSnapshots[chatId];
  }

  ProfileColorPreset? getUserColorPresetSync(String userId) {
    if (userId.isEmpty) return null;
    final fromMap = _colorPresets[userId];
    if (fromMap != null) return fromMap;
    final snap = _userSnapshots[userId];
    if (snap?.colorPresetId != null && snap!.colorPresetId!.isNotEmpty) {
      final preset = ProfileColorPresets.getById(snap.colorPresetId!);
      _colorPresets[userId] = preset;
      return preset;
    }
    final presetId = _prefs?.getString('${userId}_profile_color_preset_id');
    if (presetId != null && presetId.isNotEmpty) {
      final preset = ProfileColorPresets.getById(presetId);
      _colorPresets[userId] = preset;
      return preset;
    }
    return null;
  }

  bool isChatMutedSync(String? chatId) {
    if (chatId == null || chatId.isEmpty) return false;
    return _prefs?.getBool('muted_chat_$chatId') ??
        _groupSnapshots[chatId]?.isMuted ??
        false;
  }

  bool isUserBlockedSync(String? userId) {
    if (userId == null || userId.isEmpty) return false;
    if (_blockedUserIds.contains(userId)) return true;
    return _userSnapshots[userId]?.isBlocked ?? false;
  }

  double? getAvatarLuminanceSync(String? urlOrPath) {
    if (urlOrPath == null || urlOrPath.isEmpty) return null;
    return _avatarLuminanceCache[urlOrPath];
  }

  void setAvatarLuminance(String urlOrPath, double luminance) {
    if (urlOrPath.isEmpty) return;
    _avatarLuminanceCache[urlOrPath] = luminance;
  }

  // ============================================================
  // Обновление снимков из UI / фоновых запросов
  // ============================================================

  void putUserSnapshot(CachedUserProfileSnapshot snapshot) {
    if (snapshot.userId.isEmpty) return;
    _userSnapshots[snapshot.userId] = snapshot;
    if (snapshot.colorPresetId != null && snapshot.colorPresetId!.isNotEmpty) {
      _colorPresets[snapshot.userId] =
          ProfileColorPresets.getById(snapshot.colorPresetId!);
    }
    _persistUserSnapshot(snapshot);
  }

  void putUserColorPreset(String userId, ProfileColorPreset preset) {
    if (userId.isEmpty) return;
    _colorPresets[userId] = preset;
    final existing = _userSnapshots[userId];
    if (existing != null) {
      final updated = existing.copyWith(colorPresetId: preset.id);
      _userSnapshots[userId] = updated;
      _persistUserSnapshot(updated);
    }
  }

  void putGroupSnapshot(CachedGroupProfileSnapshot snapshot) {
    if (snapshot.chatId.isEmpty) return;
    _groupSnapshots[snapshot.chatId] = snapshot;
    _persistGroupSnapshot(snapshot);
  }

  void putSharedContent(String chatId, CachedSharedContentSnapshot content) {
    if (chatId.isEmpty) return;
    _sharedContentSnapshots[chatId] = content;
  }

  Future<void> _persistUserSnapshot(CachedUserProfileSnapshot snapshot) async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.setString(
        '$_kUserCachePrefix${snapshot.userId}',
        jsonEncode(snapshot.toJson()),
      );
    } catch (_) {}
  }

  Future<void> _persistGroupSnapshot(
      CachedGroupProfileSnapshot snapshot) async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.setString(
        '$_kGroupCachePrefix${snapshot.chatId}',
        jsonEncode(snapshot.toJson()),
      );
    } catch (_) {}
  }

  // ============================================================
  // Фоновый прогрев (Prefetch) до нажатия на профиль
  // ============================================================

  /// Прогревает профиль текущего пользователя (вызывается при старте / входе в приложение).
  Future<void> warmupSelf({BuildContext? context}) async {
    await init();
    final acc = AccountManager().currentAccount;
    if (acc == null) return;
    final uid = acc.userId;

    // 1. Загружаем общие материалы «Избранного» из локальной БД
    String? savedChatId = _userSnapshots[uid]?.resolvedChatId;
    try {
      final savedChat = await AppDatabase().getSavedChat();
      if (savedChat != null) {
        savedChatId = savedChat.chatId;
        await prefetchSharedContent(savedChat.chatId);
      }
    } catch (_) {}

    // 2. Загружаем профиль с сервера
    try {
      final localHistory = await AvatarSyncService().getLocalAvatarUrls(uid);
      final result = await AuthService.getCurrentUser();
      if (result['success'] == true && result['user'] is Map) {
        final user = Map<String, dynamic>.from(result['user'] as Map);
        final serverUrls = <String>[];
        final serverIds = <int>[];
        if (user['avatars'] is List) {
          for (final a in (user['avatars'] as List)) {
            if (a is Map) {
              final u = a['avatar_url']?.toString() ?? '';
              if (u.isNotEmpty) serverUrls.add(u);
              final idVal = a['id'];
              if (idVal is num) serverIds.add(idVal.toInt());
            }
          }
        }
        final combined = <String>[];
        for (final l in localHistory) {
          if (l.isNotEmpty && !combined.contains(l)) combined.add(l);
        }
        for (final s in serverUrls) {
          if (s.isNotEmpty && !combined.contains(s)) combined.add(s);
        }
        final primaryAvatar = localHistory.isNotEmpty
            ? localHistory.first
            : (user['avatar_url']?.toString() ?? acc.avatarUrl);
        if (primaryAvatar != null &&
            primaryAvatar.isNotEmpty &&
            !combined.contains(primaryAvatar)) {
          combined.insert(0, primaryAvatar);
        }

        final prefs = _prefs ?? await SharedPreferences.getInstance();
        final musicTitle = prefs.getString('${uid}_profile_music_title');
        final musicAuthor = prefs.getString('${uid}_profile_music_author');
        final presetId = prefs.getString('${uid}_profile_color_preset_id');

        final snap = CachedUserProfileSnapshot(
          userId: uid,
          name: (user['name'] ?? acc.name ?? '').toString(),
          surname: (user['surname'] ?? acc.surname ?? '').toString(),
          username: (user['username'] ?? acc.username ?? '').toString(),
          email: (user['email'] ?? acc.email ?? '').toString(),
          phone: (user['phone'] ?? acc.phone ?? '').toString(),
          bio: user['bio']?.toString() ?? acc.bio,
          birthday: user['birthday'] != null
              ? DateTime.tryParse(user['birthday'].toString())
              : acc.birthday,
          avatarUrl: primaryAvatar,
          avatarUrls: combined,
          avatarIds: serverIds,
          isOnline: true,
          musicTitle: musicTitle,
          musicAuthor: musicAuthor,
          resolvedChatId: savedChatId,
          colorPresetId: presetId,
        );
        putUserSnapshot(snap);
        if (context != null && context.mounted) {
          _precacheAvatarImages(context, combined);
        }
      }
    } catch (_) {}
  }

  /// Прогревает профиль собеседника (цвет, био, день рождения, аватарки, общие медиа) при входе в чат.
  Future<void> prefetchUser(
    String userId, {
    String? chatId,
    ProfileThemeProvider? themeProvider,
    BuildContext? context,
  }) async {
    if (userId.isEmpty) return;
    await init();

    String? resolvedCid = chatId ?? _userSnapshots[userId]?.resolvedChatId;
    if (resolvedCid == null || resolvedCid.isEmpty) {
      try {
        final dbChat = await AppDatabase().getPrivateChatWithUser(userId);
        if (dbChat != null) {
          resolvedCid = dbChat.chatId;
        }
      } catch (_) {}
    }

    if (resolvedCid != null && resolvedCid.isNotEmpty) {
      prefetchSharedContent(resolvedCid);
    }

    // Параллельно загружаем цветовой пресет и данные профиля пользователя
    final presetFuture = themeProvider != null
        ? themeProvider.fetchUserPreset(userId)
        : _fetchUserPresetDirect(userId);
    final profileFuture = AuthService.getUserProfile(userId);

    try {
      final results = await Future.wait([presetFuture, profileFuture]);
      final preset = results[0] as ProfileColorPreset?;
      final res = results[1] as Map<String, dynamic>;

      if (preset != null) {
        _colorPresets[userId] = preset;
      }

      if (res['success'] == true && res['user'] is Map) {
        final u = Map<String, dynamic>.from(res['user'] as Map);
        final existing = _userSnapshots[userId];

        String name = existing?.name ?? '';
        String surname = existing?.surname ?? '';
        final displayName =
            u['display_name']?.toString() ?? u['name']?.toString();
        if (displayName != null && displayName.isNotEmpty) {
          final parts = displayName.trim().split(' ');
          name = parts.first;
          surname = parts.length > 1
              ? parts.sublist(1).join(' ')
              : (u['surname']?.toString() ?? '');
        }

        final urls = <String>[];
        if (u['avatars'] is List) {
          for (final a in (u['avatars'] as List)) {
            if (a is Map) {
              final urlStr = a['avatar_url']?.toString() ?? '';
              if (urlStr.isNotEmpty && !urls.contains(urlStr)) {
                urls.add(urlStr);
              }
            }
          }
        }
        final srvAvatar = u['avatar_url']?.toString();
        if (srvAvatar != null &&
            srvAvatar.isNotEmpty &&
            !urls.contains(srvAvatar)) {
          urls.insert(0, srvAvatar);
        }

        final isMuted = resolvedCid != null && resolvedCid.isNotEmpty
            ? (_prefs?.getBool('muted_chat_$resolvedCid') ?? false)
            : (existing?.isMuted ?? false);

        final snap = CachedUserProfileSnapshot(
          userId: userId,
          name: name,
          surname: surname,
          username: (u['username'] ?? existing?.username ?? '').toString(),
          phone: (u['phone'] ?? existing?.phone ?? '').toString(),
          bio: u['bio']?.toString() ?? existing?.bio,
          birthday: u['birthday'] != null
              ? DateTime.tryParse(u['birthday'].toString())
              : existing?.birthday,
          avatarUrl: srvAvatar ??
              (urls.isNotEmpty ? urls.first : existing?.avatarUrl),
          avatarUrls: urls.isNotEmpty ? urls : (existing?.avatarUrls ?? []),
          isOnline: u['is_online'] is bool
              ? (u['is_online'] as bool)
              : (existing?.isOnline ?? false),
          lastSeen: u['last_seen'] != null
              ? DateTime.tryParse(u['last_seen'].toString())
              : existing?.lastSeen,
          isMuted: isMuted,
          isBlocked:
              _blockedUserIds.contains(userId) || (existing?.isBlocked ?? false),
          resolvedChatId: resolvedCid,
          colorPresetId: preset?.id ?? existing?.colorPresetId,
        );
        putUserSnapshot(snap);
        if (context != null && context.mounted) {
          _precacheAvatarImages(context, snap.avatarUrls);
        }
      }
    } catch (_) {}
  }

  Future<ProfileColorPreset?> _fetchUserPresetDirect(String userId) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return _colorPresets[userId];
      final dio = Dio();
      final resp = await dio.get(
        '${AppConfig.baseUrl}/api/user/appearance/$userId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (resp.statusCode == 200 && resp.data is Map) {
        final data = resp.data as Map;
        if (data['success'] == true && data['appearance'] is Map) {
          final app = data['appearance'] as Map;
          final pcId = app['profile_color_preset_id']?.toString();
          if (pcId != null && pcId.isNotEmpty) {
            final prefs = _prefs ?? await SharedPreferences.getInstance();
            await prefs.setString('${userId}_profile_color_preset_id', pcId);
            final preset = ProfileColorPresets.getById(pcId);
            _colorPresets[userId] = preset;
            return preset;
          }
        }
      }
    } catch (_) {}
    return _colorPresets[userId];
  }

  /// Прогревает профиль группы или канала и общие медиа при входе в чат.
  Future<void> prefetchGroupOrChannel(
    String chatId, {
    BuildContext? context,
  }) async {
    if (chatId.isEmpty) return;
    await init();
    prefetchSharedContent(chatId);

    try {
      final token = await AuthService.getToken();
      if (token == null) return;
      final dio = Dio();
      final results = await Future.wait([
        dio
            .get(
              '${AppConfig.baseUrl}/api/chats/$chatId/group-settings',
              options: Options(headers: {'Authorization': 'Bearer $token'}),
            )
            .catchError((_) => Response(
                  requestOptions: RequestOptions(path: ''),
                  statusCode: 400,
                )),
        dio
            .get(
              '${AppConfig.baseUrl}/api/chats/$chatId/members',
              options: Options(headers: {'Authorization': 'Bearer $token'}),
            )
            .catchError((_) => Response(
                  requestOptions: RequestOptions(path: ''),
                  statusCode: 400,
                )),
      ]);

      final settingsResp = results[0];
      final membersResp = results[1];
      final existing = _groupSnapshots[chatId];
      final currentUid = AccountManager().currentAccount?.userId;

      String name = existing?.name ?? '';
      String description = existing?.description ?? '';
      String inviteLink = existing?.inviteLink ?? '';
      bool isPublic = existing?.isPublic ?? false;
      bool historyForNew = existing?.historyForNew ?? true;
      int slowModeInterval = existing?.slowModeInterval ?? 0;
      int memberCount = existing?.memberCount ?? 0;
      String? avatarUrl = existing?.avatarUrl;
      List<ProfileMemberItem> members = existing?.members ?? const [];
      String myRole = existing?.myRole ?? 'member';

      if (settingsResp.statusCode == 200 && settingsResp.data is Map) {
        final data = settingsResp.data as Map;
        if (data['name'] != null && data['name'].toString().isNotEmpty) {
          name = data['name'].toString();
        }
        description = (data['description'] ?? '').toString();
        inviteLink = (data['invite_link'] ?? '').toString();
        isPublic = data['is_public'] == true;
        historyForNew = data['history_for_new'] ?? true;
        slowModeInterval = (data['slow_mode_interval'] as num?)?.toInt() ?? 0;
        memberCount = (data['member_count'] as num?)?.toInt() ?? 0;
        final srvAvatar = data['avatar_url']?.toString();
        if (srvAvatar != null && srvAvatar.isNotEmpty) {
          avatarUrl = srvAvatar;
        }
      }

      if (membersResp.statusCode == 200 && membersResp.data is Map) {
        final rawMembers = membersResp.data['members'] as List?;
        if (rawMembers != null) {
          members = rawMembers
              .whereType<Map>()
              .map((m) =>
                  ProfileMemberItem.fromJson(Map<String, dynamic>.from(m)))
              .toList();
          if (memberCount == 0) {
            memberCount = members.length;
          }
          if (currentUid != null) {
            final me =
                members.where((m) => m.userId == currentUid).firstOrNull;
            if (me != null) {
              myRole = me.role;
            }
          }
        }
      }

      final isMuted = _prefs?.getBool('muted_chat_$chatId') ?? false;
      final snap = CachedGroupProfileSnapshot(
        chatId: chatId,
        name: name,
        description: description,
        inviteLink: inviteLink,
        isPublic: isPublic,
        historyForNew: historyForNew,
        slowModeInterval: slowModeInterval,
        memberCount: memberCount,
        myRole: myRole,
        avatarUrl: avatarUrl,
        members: members,
        isMuted: isMuted,
      );
      putGroupSnapshot(snap);
      if (context != null &&
          context.mounted &&
          avatarUrl != null &&
          avatarUrl.isNotEmpty) {
        _precacheAvatarImages(context, [avatarUrl]);
      }
    } catch (_) {}
  }

  /// Прогревает вкладки «Медиа», «Файлы», «Ссылки», «Голосовые» из SQLite для чата.
  Future<void> prefetchSharedContent(String chatId) async {
    if (chatId.isEmpty) return;
    try {
      final db = AppDatabase();
      final results = await Future.wait([
        db.getSharedMediaForChat(chatId),
        db.getSharedFilesForChat(chatId),
        db.getSharedLinksForChat(chatId),
        db.getSharedVoiceForChat(chatId),
      ]);
      _sharedContentSnapshots[chatId] = CachedSharedContentSnapshot(
        mediaMessages: results[0],
        fileMessages: results[1],
        linkMessages: results[2],
        voiceMessages: results[3],
      );
    } catch (_) {}
  }

  void _precacheAvatarImages(BuildContext context, List<String> urls) {
    for (final raw in urls.take(3)) {
      final resolved = AppConfig.resolveMediaUrl(raw) ?? raw;
      if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
        try {
          precacheImage(CachedNetworkImageProvider(resolved), context);
        } catch (_) {}
      }
    }
  }
}
