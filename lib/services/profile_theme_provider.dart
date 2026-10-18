import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/name_color_preset.dart';
import 'account_manager.dart';
import 'auth_service.dart';
import 'profile_instant_cache.dart';

/// Модель палитры фона профиля
class ProfileColorPreset {
  final String id;
  final String nameKey;
  final Color backgroundColor;
  final List<Color>? gradientColors;
  final Color ringColor;
  final Color statusColor;
  final bool isCustom;

  bool get isGradient => gradientColors != null && gradientColors!.length > 1;

  const ProfileColorPreset({
    required this.id,
    required this.nameKey,
    required this.backgroundColor,
    this.gradientColors,
    required this.ringColor,
    required this.statusColor,
    this.isCustom = false,
  });

  /// Создание пользовательского пресета из выбранного цвета
  factory ProfileColorPreset.fromCustomColor(Color color) {
    final opaque = color.withValues(alpha: 1.0);
    final status = Color.alphaBlend(Colors.white.withValues(alpha: 0.7), opaque);
    final ring = Color.alphaBlend(Colors.white.withValues(alpha: 0.85), opaque);
    return ProfileColorPreset(
      id: 'custom_${opaque.toARGB32()}',
      nameKey: 'profile_color_custom',
      backgroundColor: opaque,
      ringColor: ring,
      statusColor: status,
      isCustom: true,
    );
  }

  /// Создание пользовательского градиентного пресета из двух выбранных цветов
  factory ProfileColorPreset.fromCustomGradient(Color color1, Color color2) {
    final c1 = color1.withValues(alpha: 1.0);
    final c2 = color2.withValues(alpha: 1.0);
    final status = Color.alphaBlend(Colors.white.withValues(alpha: 0.7), c1);
    final ring = Color.alphaBlend(Colors.white.withValues(alpha: 0.85), c1);
    return ProfileColorPreset(
      id: 'custom_grad_${c1.toARGB32()}_${c2.toARGB32()}',
      nameKey: 'profile_color_custom',
      backgroundColor: c1,
      gradientColors: [c1, c2],
      ringColor: ring,
      statusColor: status,
      isCustom: true,
    );
  }
}

/// 16 дизайнерских цветовых палитр профиля (сплошные и диагональные двухцветные полукруги)
class ProfileColorPresets {
  // Ряд 1: Сплошные цвета
  static const blue = ProfileColorPreset(
    id: 'blue',
    nameKey: 'profile_color_blue',
    backgroundColor: Color(0xFF2B82C9),
    ringColor: Color(0xFF5AB6F0),
    statusColor: Color(0xFF9FD6FF),
  );

  static const green = ProfileColorPreset(
    id: 'green',
    nameKey: 'profile_color_green',
    backgroundColor: Color(0xFF3CAD3A),
    ringColor: Color(0xFF75DB73),
    statusColor: Color(0xFFB5F5B3),
  );

  static const orange = ProfileColorPreset(
    id: 'orange',
    nameKey: 'profile_color_orange',
    backgroundColor: Color(0xFFE58822),
    ringColor: Color(0xFFF7B152),
    statusColor: Color(0xFFFFD9A3),
  );

  static const red = ProfileColorPreset(
    id: 'red',
    nameKey: 'profile_color_red',
    backgroundColor: Color(0xFFD64D53),
    ringColor: Color(0xFFF57D82),
    statusColor: Color(0xFFFFBCC0),
  );

  static const purple = ProfileColorPreset(
    id: 'purple',
    nameKey: 'profile_color_purple',
    backgroundColor: Color(0xFF8B5CD6),
    ringColor: Color(0xFFB98DFB),
    statusColor: Color(0xFFDFCAFF),
  );

  static const cyan = ProfileColorPreset(
    id: 'cyan',
    nameKey: 'profile_color_cyan',
    backgroundColor: Color(0xFF26B2BA),
    ringColor: Color(0xFF5BE0E8),
    statusColor: Color(0xFFA6FAFF),
  );

  static const pink = ProfileColorPreset(
    id: 'pink',
    nameKey: 'profile_color_pink',
    backgroundColor: Color(0xFFCF5088),
    ringColor: Color(0xFFF584B5),
    statusColor: Color(0xFFFFC0DC),
  );

  static const slate = ProfileColorPreset(
    id: 'slate',
    nameKey: 'profile_color_slate',
    backgroundColor: Color(0xFF708799),
    ringColor: Color(0xFF9AAEC0),
    statusColor: Color(0xFFCCD9E5),
  );

  // Ряд 2: Диагональные двухцветные полукруги
  static const skyBlueGrad = ProfileColorPreset(
    id: 'sky_blue_grad',
    nameKey: 'profile_color_sky_blue_grad',
    backgroundColor: Color(0xFF3C95DC),
    gradientColors: [Color(0xFF5AB6F0), Color(0xFF2575C0)],
    ringColor: Color(0xFF7ECBFB),
    statusColor: Color(0xFFBFE5FF),
  );

  static const limeGrad = ProfileColorPreset(
    id: 'lime_grad',
    nameKey: 'profile_color_lime_grad',
    backgroundColor: Color(0xFF5FB63C),
    gradientColors: [Color(0xFF8CD848), Color(0xFF389230)],
    ringColor: Color(0xFFA8EE6E),
    statusColor: Color(0xFFD4FFB0),
  );

  static const goldGrad = ProfileColorPreset(
    id: 'gold_grad',
    nameKey: 'profile_color_gold_grad',
    backgroundColor: Color(0xFFE8A02F),
    gradientColors: [Color(0xFFF6C844), Color(0xFFD9771A)],
    ringColor: Color(0xFFFAD76F),
    statusColor: Color(0xFFFFE8A3),
  );

  static const peachGrad = ProfileColorPreset(
    id: 'peach_grad',
    nameKey: 'profile_color_peach_grad',
    backgroundColor: Color(0xFFDF6055),
    gradientColors: [Color(0xFFF78A69), Color(0xFFC73641)],
    ringColor: Color(0xFFFFB099),
    statusColor: Color(0xFFFFD4C7),
  );

  static const violetGrad = ProfileColorPreset(
    id: 'violet_grad',
    nameKey: 'profile_color_violet_grad',
    backgroundColor: Color(0xFF9C4FD6),
    gradientColors: [Color(0xFFC76EF4), Color(0xFF702FB8)],
    ringColor: Color(0xFFDB95FF),
    statusColor: Color(0xFFF1C8FF),
  );

  static const aquaGrad = ProfileColorPreset(
    id: 'aqua_grad',
    nameKey: 'profile_color_aqua_grad',
    backgroundColor: Color(0xFF3CAFBB),
    gradientColors: [Color(0xFF5BD5CF), Color(0xFF1E8A99)],
    ringColor: Color(0xFF86F3ED),
    statusColor: Color(0xFFC7FFF9),
  );

  static const roseGrad = ProfileColorPreset(
    id: 'rose_grad',
    nameKey: 'profile_color_rose_grad',
    backgroundColor: Color(0xFFC5446F),
    gradientColors: [Color(0xFFE9658E), Color(0xFFA12450)],
    ringColor: Color(0xFFFF95B7),
    statusColor: Color(0xFFFFCBE0),
  );

  static const slateGrad = ProfileColorPreset(
    id: 'slate_grad',
    nameKey: 'profile_color_slate_grad',
    backgroundColor: Color(0xFF738799),
    gradientColors: [Color(0xFF9AAEC0), Color(0xFF4C5F70)],
    ringColor: Color(0xFFBCCCDA),
    statusColor: Color(0xFFE2EDF7),
  );

  static const List<ProfileColorPreset> row1Solids = [
    blue,
    green,
    orange,
    red,
    purple,
    cyan,
    pink,
    slate,
  ];

  static const List<ProfileColorPreset> row2Gradients = [
    skyBlueGrad,
    limeGrad,
    goldGrad,
    peachGrad,
    violetGrad,
    aquaGrad,
    roseGrad,
    slateGrad,
  ];

  static const List<ProfileColorPreset> allPresets = [
    ...row1Solids,
    ...row2Gradients,
  ];

  static ProfileColorPreset getById(String id) {
    if (id.startsWith('custom_grad_')) {
      final parts = id.replaceFirst('custom_grad_', '').split('_');
      if (parts.length == 2) {
        final val1 = int.tryParse(parts[0]);
        final val2 = int.tryParse(parts[1]);
        if (val1 != null && val2 != null) {
          return ProfileColorPreset.fromCustomGradient(Color(val1), Color(val2));
        }
      }
    } else if (id.startsWith('custom_')) {
      final valueStr = id.replaceFirst('custom_', '');
      final val = int.tryParse(valueStr);
      if (val != null) {
        return ProfileColorPreset.fromCustomColor(Color(val));
      }
    }
    return allPresets.firstWhere(
      (preset) => preset.id == id,
      orElse: () => blue,
    );
  }
}

/// Провайдер состояния фона профиля пользователя, цвета имени и стиля полоски цитирования.
class ProfileThemeProvider extends ChangeNotifier {
  static const String _legacyPrefPresetKey = 'profile_color_preset_id';
  static const String _legacyPrefNameColorKey = 'user_name_color_preset_id';
  static const String _legacyPrefStripStyleKey = 'user_reply_strip_style';

  static String _prefPresetKey(String uid) => '${uid}_profile_color_preset_id';
  static String _prefNameColorKey(String uid) => '${uid}_user_name_color_preset_id';
  static String _prefStripStyleKey(String uid) => '${uid}_user_reply_strip_style';

  String? _currentUserId;
  ProfileColorPreset? _currentPreset = ProfileColorPresets.blue;
  NameColorPreset _currentNameColorPreset = NameColorPresets.red;
  ReplyStripStyle _currentStripStyle = ReplyStripStyle.solid;

  String? get currentUserId => _currentUserId;
  ProfileColorPreset? get currentPreset => _currentPreset;
  bool get hasCustomColor => _currentPreset != null;
  String? get selectedPresetId => _currentPreset?.id;
  Color get primaryColor => _currentPreset?.backgroundColor ?? const Color(0xFF2B82C9);
  Color get statusColor => _currentPreset?.statusColor ?? const Color(0xFF9FD6FF);

  NameColorPreset get currentNameColorPreset => _currentNameColorPreset;
  ReplyStripStyle get currentStripStyle => _currentStripStyle;
  Color get activeNameColor => _currentNameColorPreset.primaryColor;

  Future<void> init() async {
    final accountManager = AccountManager();
    accountManager.removeListener(_onAccountManagerChanged);
    accountManager.addListener(_onAccountManagerChanged);

    final currentUid = accountManager.currentAccount?.userId;
    await switchUser(currentUid, force: true);
  }

  void _onAccountManagerChanged() {
    final newUid = AccountManager().currentAccount?.userId;
    if (newUid != _currentUserId) {
      switchUser(newUid);
    }
  }

  /// Переключение на настройки конкретного пользователя
  Future<void> switchUser(String? userId, {bool force = false}) async {
    if (!force && _currentUserId == userId) return;
    _currentUserId = userId;

    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId.isNotEmpty) {
      final presetKey = _prefPresetKey(userId);
      final nameColorKey = _prefNameColorKey(userId);
      final stripStyleKey = _prefStripStyleKey(userId);

      // Проверяем скоупированный ключ, либо мигрируем со старого общего ключа
      String? savedId = prefs.getString(presetKey);
      if (savedId == null && prefs.containsKey(_legacyPrefPresetKey)) {
        savedId = prefs.getString(_legacyPrefPresetKey);
        if (savedId != null) await prefs.setString(presetKey, savedId);
      }
      _currentPreset = (savedId != null && savedId.isNotEmpty)
          ? ProfileColorPresets.getById(savedId)
          : ProfileColorPresets.blue;

      String? savedNameColorId = prefs.getString(nameColorKey);
      if (savedNameColorId == null && prefs.containsKey(_legacyPrefNameColorKey)) {
        savedNameColorId = prefs.getString(_legacyPrefNameColorKey);
        if (savedNameColorId != null) await prefs.setString(nameColorKey, savedNameColorId);
      }
      _currentNameColorPreset = (savedNameColorId != null && savedNameColorId.isNotEmpty)
          ? NameColorPresets.getById(savedNameColorId)
          : NameColorPresets.red;

      String? savedStyleName = prefs.getString(stripStyleKey);
      if (savedStyleName == null && prefs.containsKey(_legacyPrefStripStyleKey)) {
        savedStyleName = prefs.getString(_legacyPrefStripStyleKey);
        if (savedStyleName != null) await prefs.setString(stripStyleKey, savedStyleName);
      }
      _currentStripStyle = (savedStyleName != null && savedStyleName.isNotEmpty)
          ? ReplyStripStyle.values.firstWhere(
              (s) => s.name == savedStyleName,
              orElse: () => ReplyStripStyle.solid,
            )
          : ReplyStripStyle.solid;
    } else {
      _currentPreset = ProfileColorPresets.blue;
      _currentNameColorPreset = NameColorPresets.red;
      _currentStripStyle = ReplyStripStyle.solid;
    }

    notifyListeners();

    // Фоновая синхронизация с сервера для активного пользователя
    _fetchFromServer(userId);
  }

  Future<void> _fetchFromServer([String? targetUserId]) async {
    final userId = targetUserId ?? _currentUserId;
    try {
      final accountManager = AccountManager();
      String? token;
      if (userId != null) {
        final matching = accountManager.accounts.where((a) => a.userId == userId);
        if (matching.isNotEmpty) {
          token = matching.first.token;
        }
      }
      token ??= await AuthService.getToken();
      if (token == null) return;

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/user/appearance'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['appearance'] is Map) {
          final app = data['appearance'] as Map<String, dynamic>;
          final pcId = app['profile_color_preset_id']?.toString();
          final ncId = app['name_color_preset_id']?.toString();
          final rs = app['reply_strip_style']?.toString();

          final prefs = await SharedPreferences.getInstance();
          final bool isStillActive = (_currentUserId == userId);

          if (userId != null && userId.isNotEmpty) {
            if (pcId != null && pcId.isNotEmpty) {
              await prefs.setString(_prefPresetKey(userId), pcId);
              if (isStillActive) _currentPreset = ProfileColorPresets.getById(pcId);
            }
            if (ncId != null && ncId.isNotEmpty) {
              await prefs.setString(_prefNameColorKey(userId), ncId);
              if (isStillActive) _currentNameColorPreset = NameColorPresets.getById(ncId);
            }
            if (rs != null && rs.isNotEmpty) {
              await prefs.setString(_prefStripStyleKey(userId), rs);
              if (isStillActive) {
                _currentStripStyle = ReplyStripStyle.values.firstWhere(
                  (s) => s.name == rs,
                  orElse: () => ReplyStripStyle.solid,
                );
              }
            }
          }
          if (isStillActive) {
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('[ProfileThemeProvider] Error fetching appearance: $e');
    }
  }

  Future<void> _syncWithBackend({
    String? profileColorPresetId,
    String? nameColorPresetId,
    String? replyStripStyle,
    String? bubbleStyle,
  }) async {
    try {
      final userId = _currentUserId;
      String? token;
      if (userId != null) {
        final matching = AccountManager().accounts.where((a) => a.userId == userId);
        if (matching.isNotEmpty) {
          token = matching.first.token;
        }
      }
      token ??= await AuthService.getToken();
      if (token == null) return;

      final body = <String, dynamic>{};
      if (profileColorPresetId != null) body['profile_color_preset_id'] = profileColorPresetId;
      if (nameColorPresetId != null) body['name_color_preset_id'] = nameColorPresetId;
      if (replyStripStyle != null) body['reply_strip_style'] = replyStripStyle;
      if (bubbleStyle != null) body['bubble_style'] = bubbleStyle;

      final response = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/user/appearance'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      debugPrint('[ProfileThemeProvider] Sync appearance status: ${response.statusCode}');
    } catch (e) {
      debugPrint('[ProfileThemeProvider] Failed to sync appearance: $e');
    }
  }

  Future<void> setPreset(ProfileColorPreset? preset) async {
    if (_currentPreset?.id == preset?.id) return;
    _currentPreset = preset;
    final prefs = await SharedPreferences.getInstance();
    final uid = _currentUserId;
    if (uid != null && uid.isNotEmpty) {
      if (preset != null) {
        await prefs.setString(_prefPresetKey(uid), preset.id);
        _syncWithBackend(profileColorPresetId: preset.id);
      } else {
        await prefs.remove(_prefPresetKey(uid));
        _syncWithBackend(profileColorPresetId: 'blue');
      }
    }
    notifyListeners();
  }

  Future<void> setNameColorAndStyle(NameColorPreset preset, ReplyStripStyle style) async {
    _currentNameColorPreset = preset;
    _currentStripStyle = style;
    final prefs = await SharedPreferences.getInstance();
    final uid = _currentUserId;
    if (uid != null && uid.isNotEmpty) {
      await prefs.setString(_prefNameColorKey(uid), preset.id);
      await prefs.setString(_prefStripStyleKey(uid), style.name);
      _syncWithBackend(nameColorPresetId: preset.id, replyStripStyle: style.name);
    }
    notifyListeners();
  }

  final Map<String, ProfileColorPreset> _peerPresetCache = {};

  /// Получить закэшированный пресет оформления чужого пользователя синхронно (Frame 0)
  ProfileColorPreset? getCachedUserPreset(String userId) {
    if (userId.isEmpty) return null;
    if (userId == _currentUserId) return _currentPreset;
    return _peerPresetCache[userId] ??
        ProfileInstantCache.instance.getUserColorPresetSync(userId);
  }

  /// Загрузить пресет оформления конкретного пользователя с кэшированием в SharedPreferences и памяти
  Future<ProfileColorPreset?> fetchUserPreset(String userId) async {
    if (userId.isEmpty) return null;
    if (userId == _currentUserId) return _currentPreset;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedId = prefs.getString(_prefPresetKey(userId));
      if (cachedId != null && cachedId.isNotEmpty) {
        final preset = ProfileColorPresets.getById(cachedId);
        _peerPresetCache[userId] = preset;
        ProfileInstantCache.instance.putUserColorPreset(userId, preset);
      }

      final token = await AuthService.getToken();
      if (token != null) {
        final response = await http.get(
          Uri.parse('${AppConfig.baseUrl}/api/user/appearance/$userId'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['appearance'] is Map) {
            final app = data['appearance'] as Map<String, dynamic>;
            final pcId = app['profile_color_preset_id']?.toString();
            if (pcId != null && pcId.isNotEmpty) {
              await prefs.setString(_prefPresetKey(userId), pcId);
              final preset = ProfileColorPresets.getById(pcId);
              _peerPresetCache[userId] = preset;
              ProfileInstantCache.instance.putUserColorPreset(userId, preset);
              return preset;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ProfileThemeProvider] Error fetching peer preset for $userId: $e');
    }
    return _peerPresetCache[userId] ??
        ProfileInstantCache.instance.getUserColorPresetSync(userId);
  }

  Future<void> resetToDefault() async {
    await setPreset(ProfileColorPresets.blue);
    await setNameColorAndStyle(NameColorPresets.red, ReplyStripStyle.solid);
  }

  @override
  void dispose() {
    AccountManager().removeListener(_onAccountManagerChanged);
    super.dispose();
  }
}
