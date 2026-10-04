import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/theav_theme.dart';
import 'auth_service.dart';

/// Service managing built-in presets, cloud-synced account themes,
/// local device active themes, and .theavtheme package import/export.
class TheavThemeService extends ChangeNotifier {
  static final TheavThemeService _instance = TheavThemeService._internal();
  factory TheavThemeService() => _instance;
  TheavThemeService._internal();

  static const String _keyActiveLightId = 'device_active_light_theme_id';
  static const String _keyActiveDarkId = 'device_active_dark_theme_id';
  static const String _keyActiveLightThemeJson = 'device_active_light_theme_json';
  static const String _keyActiveDarkThemeJson = 'device_active_dark_theme_json';
  static const String _keyCachedCustomThemes = 'device_cached_custom_themes';
  static const String _keyThemeOverrides = 'device_theme_overrides_json';

  String _activeLightThemeId = 'theaver_classic';
  String _activeDarkThemeId = 'dark_slate';
  TheavTheme? _activeLightTheme;
  TheavTheme? _activeDarkTheme;
  Map<String, TheavTheme> _themeOverrides = {};
  List<TheavTheme> _customThemes = [];
  bool _isSyncing = false;

  String get activeLightThemeId => _activeLightThemeId;
  String get activeDarkThemeId => _activeDarkThemeId;
  List<TheavTheme> get customThemes => List.unmodifiable(_customThemes);
  bool get isSyncing => _isSyncing;

  /// List of built-in preset themes
  static final List<TheavTheme> builtInThemes = [
    // 1. Theaver Classic (Light)
    const TheavTheme(
      id: 'theaver_classic',
      name: 'Theaver Classic',
      author: 'Theaver Team',
      isDark: false,
      isBuiltIn: true,
      bubbleRadius: 16.0,
      palette: TheavPalette(
        primary: Color(0xFF0088CC),
        onPrimary: Colors.white,
        background: Color(0xFFFFFFFF),
        surface: Color(0xFFF5F5F5),
        onSurface: Color(0xFF1C1C1E),
        appBarBackground: Color(0xFFFFFFFF),
        appBarForeground: Color(0xFF1C1C1E),
        chatBubbleOutgoing: Color(0xFF0088CC),
        chatBubbleOutgoingText: Colors.white,
        chatBubbleOutgoingSubtext: Color(0xB3FFFFFF),
        chatBubbleIncoming: Color(0xFFF2F2F7),
        chatBubbleIncomingText: Color(0xFF1C1C1E),
        chatBubbleIncomingSubtext: Color(0xFF8E8E93),
        chatDateBadge: Color(0x33000000),
        chatDateBadgeText: Colors.white,
      ),
      wallpaper: TheavWallpaper(
        type: 'pattern',
        patternName: 'science',
        backgroundColor: Color(0xFFEAF2F8),
        patternColor: Color(0xFF0088CC),
        patternOpacity: 0.14,
        fourCornerGradient: FourCornerGradient(
          topLeft: Color(0xFFD4EBF8),
          topRight: Color(0xFFE8EEF5),
          bottomLeft: Color(0xFFCCE4F6),
          bottomRight: Color(0xFFDCEAF5),
        ),
        motionEnabled: true,
      ),
    ),

    // 2. Dark Slate (Dark)
    const TheavTheme(
      id: 'dark_slate',
      name: 'Dark Slate',
      author: 'Theaver Team',
      isDark: true,
      isBuiltIn: true,
      bubbleRadius: 16.0,
      palette: TheavPalette(
        primary: Color(0xFF0088CC),
        onPrimary: Colors.white,
        background: Color(0xFF1C1C1E),
        surface: Color(0xFF2C2C2E),
        onSurface: Color(0xFFE5E5EA),
        appBarBackground: Color(0xFF1C1C1E),
        appBarForeground: Colors.white,
        chatBubbleOutgoing: Color(0xFF0088CC),
        chatBubbleOutgoingText: Colors.white,
        chatBubbleOutgoingSubtext: Color(0xB3FFFFFF),
        chatBubbleIncoming: Color(0xFF2C2C2E),
        chatBubbleIncomingText: Color(0xFFE5E5EA),
        chatBubbleIncomingSubtext: Color(0xFF8E8E93),
        chatDateBadge: Color(0x66000000),
        chatDateBadgeText: Colors.white,
      ),
      wallpaper: TheavWallpaper(
        type: 'pattern',
        patternName: 'space',
        backgroundColor: Color(0xFF14181E),
        patternColor: Color(0xFF5CB8E6),
        patternOpacity: 0.12,
        fourCornerGradient: FourCornerGradient(
          topLeft: Color(0xFF14181E),
          topRight: Color(0xFF1C222B),
          bottomLeft: Color(0xFF101318),
          bottomRight: Color(0xFF1A2433),
        ),
        motionEnabled: true,
      ),
    ),

    // 3. Arctic Frost (Light)
    const TheavTheme(
      id: 'arctic_frost',
      name: 'Arctic Frost',
      author: 'Theaver Team',
      isDark: false,
      isBuiltIn: true,
      bubbleRadius: 18.0,
      palette: TheavPalette(
        primary: Color(0xFF0288D1),
        onPrimary: Colors.white,
        background: Color(0xFFF1F8FB),
        surface: Color(0xFFE1F5FE),
        onSurface: Color(0xFF0D47A1),
        appBarBackground: Color(0xFFE1F5FE),
        appBarForeground: Color(0xFF0D47A1),
        chatBubbleOutgoing: Color(0xFF0288D1),
        chatBubbleOutgoingText: Colors.white,
        chatBubbleOutgoingSubtext: Color(0xB3FFFFFF),
        chatBubbleIncoming: Colors.white,
        chatBubbleIncomingText: Color(0xFF0D47A1),
        chatBubbleIncomingSubtext: Color(0xFF546E7A),
        chatDateBadge: Color(0x330288D1),
        chatDateBadgeText: Colors.white,
      ),
      wallpaper: TheavWallpaper(
        type: 'pattern',
        patternName: 'flowers',
        backgroundColor: Color(0xFFF1F8FB),
        patternColor: Color(0xFF0288D1),
        patternOpacity: 0.16,
        fourCornerGradient: FourCornerGradient(
          topLeft: Color(0xFFE1F5FE),
          topRight: Color(0xFFE0F2F1),
          bottomLeft: Color(0xFFB3E5FC),
          bottomRight: Color(0xFFE8EAF6),
        ),
        motionEnabled: true,
      ),
    ),

    // 4. Emerald Nature (Light)
    const TheavTheme(
      id: 'emerald_nature',
      name: 'Emerald Nature',
      author: 'Theaver Team',
      isDark: false,
      isBuiltIn: true,
      bubbleRadius: 16.0,
      palette: TheavPalette(
        primary: Color(0xFF2E7D32),
        onPrimary: Colors.white,
        background: Color(0xFFF4FBF4),
        surface: Color(0xFFE8F5E9),
        onSurface: Color(0xFF1B5E20),
        appBarBackground: Color(0xFFE8F5E9),
        appBarForeground: Color(0xFF1B5E20),
        chatBubbleOutgoing: Color(0xFF2E7D32),
        chatBubbleOutgoingText: Colors.white,
        chatBubbleOutgoingSubtext: Color(0xB3FFFFFF),
        chatBubbleIncoming: Colors.white,
        chatBubbleIncomingText: Color(0xFF1B5E20),
        chatBubbleIncomingSubtext: Color(0xFF689F38),
        chatDateBadge: Color(0x332E7D32),
        chatDateBadgeText: Colors.white,
      ),
      wallpaper: TheavWallpaper(
        type: 'pattern',
        patternName: 'flowers',
        backgroundColor: Color(0xFFE8F5E9),
        patternColor: Color(0xFF2E7D32),
        patternOpacity: 0.15,
        fourCornerGradient: FourCornerGradient(
          topLeft: Color(0xFFE8F5E9),
          topRight: Color(0xFFF1F8E9),
          bottomLeft: Color(0xFFC8E6C9),
          bottomRight: Color(0xFFDCEDC8),
        ),
        motionEnabled: true,
      ),
    ),

    // 5. Midnight Neon (Dark OLED)
    const TheavTheme(
      id: 'midnight_neon',
      name: 'Midnight Neon',
      author: 'Theaver Team',
      isDark: true,
      isBuiltIn: true,
      bubbleRadius: 20.0,
      palette: TheavPalette(
        primary: Color(0xFF7C4DFF),
        onPrimary: Colors.white,
        background: Color(0xFF000000),
        surface: Color(0xFF121212),
        onSurface: Color(0xFFE0E0E0),
        appBarBackground: Color(0xFF000000),
        appBarForeground: Colors.white,
        chatBubbleOutgoing: Color(0xFF651FFF),
        chatBubbleOutgoingText: Colors.white,
        chatBubbleOutgoingSubtext: Color(0xB3FFFFFF),
        chatBubbleIncoming: Color(0xFF1E1E24),
        chatBubbleIncomingText: Colors.white,
        chatBubbleIncomingSubtext: Color(0xFF9E9E9E),
        chatDateBadge: Color(0x667C4DFF),
        chatDateBadgeText: Colors.white,
      ),
      wallpaper: TheavWallpaper(
        type: 'pattern',
        patternName: 'science',
        backgroundColor: Color(0xFF000000),
        patternColor: Color(0xFF00E5FF),
        patternOpacity: 0.15,
        fourCornerGradient: FourCornerGradient(
          topLeft: Color(0xFF120024),
          topRight: Color(0xFF001224),
          bottomLeft: Color(0xFF24001A),
          bottomRight: Color(0xFF002422),
        ),
        motionEnabled: true,
      ),
    ),

    // 6. Warm Romance (Light)
    const TheavTheme(
      id: 'warm_romance',
      name: 'Warm Romance',
      author: 'Theaver Team',
      isDark: false,
      isBuiltIn: true,
      bubbleRadius: 16.0,
      palette: TheavPalette(
        primary: Color(0xFFE91E63),
        onPrimary: Colors.white,
        background: Color(0xFFFFF5F7),
        surface: Color(0xFFFCE4EC),
        onSurface: Color(0xFF880E4F),
        appBarBackground: Color(0xFFFCE4EC),
        appBarForeground: Color(0xFF880E4F),
        chatBubbleOutgoing: Color(0xFFE91E63),
        chatBubbleOutgoingText: Colors.white,
        chatBubbleOutgoingSubtext: Color(0xB3FFFFFF),
        chatBubbleIncoming: Colors.white,
        chatBubbleIncomingText: Color(0xFF880E4F),
        chatBubbleIncomingSubtext: Color(0xFFAD1457),
        chatDateBadge: Color(0x33E91E63),
        chatDateBadgeText: Colors.white,
      ),
      wallpaper: TheavWallpaper(
        type: 'pattern',
        patternName: 'love',
        backgroundColor: Color(0xFFFCE4EC),
        patternColor: Color(0xFFE91E63),
        patternOpacity: 0.15,
        fourCornerGradient: FourCornerGradient(
          topLeft: Color(0xFFFCE4EC),
          topRight: Color(0xFFFFF3E0),
          bottomLeft: Color(0xFFF8BBD0),
          bottomRight: Color(0xFFFFEBEE),
        ),
        motionEnabled: true,
      ),
    ),
  ];

  /// Initialize service, load local preferences, and sync with cloud
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _activeLightThemeId = prefs.getString(_keyActiveLightId) ?? 'theaver_classic';
    _activeDarkThemeId = prefs.getString(_keyActiveDarkId) ?? 'dark_slate';

    // Load theme overrides (customized wallpapers, bubble radiuses, etc.)
    final overridesJson = prefs.getString(_keyThemeOverrides);
    if (overridesJson != null && overridesJson.isNotEmpty) {
      try {
        final Map<String, dynamic> map = jsonDecode(overridesJson);
        _themeOverrides = map.map((k, v) => MapEntry(k, TheavTheme.fromJson(v as Map<String, dynamic>)));
      } catch (e) {
        debugPrint('TheavThemeService: Error loading theme overrides: $e');
      }
    }

    // Load cached custom themes
    final cachedJson = prefs.getString(_keyCachedCustomThemes);
    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(cachedJson);
        _customThemes = list.map((item) => TheavTheme.fromJson(item as Map<String, dynamic>)).toList();
      } catch (e) {
        debugPrint('TheavThemeService: Error loading cached custom themes: $e');
      }
    }

    // Load active light theme
    final activeLightJson = prefs.getString(_keyActiveLightThemeJson);
    if (activeLightJson != null && activeLightJson.isNotEmpty) {
      try {
        _activeLightTheme = TheavTheme.fromJson(jsonDecode(activeLightJson));
      } catch (e) {
        debugPrint('TheavThemeService: Error loading active light theme: $e');
      }
    }

    // Load active dark theme
    final activeDarkJson = prefs.getString(_keyActiveDarkThemeJson);
    if (activeDarkJson != null && activeDarkJson.isNotEmpty) {
      try {
        _activeDarkTheme = TheavTheme.fromJson(jsonDecode(activeDarkJson));
      } catch (e) {
        debugPrint('TheavThemeService: Error loading active dark theme: $e');
      }
    }

    notifyListeners();

    // Background sync from server
    syncCloudThemes();
  }

  /// Get all available themes (built-ins with overrides + custom/cloud)
  List<TheavTheme> getAllThemes() {
    final builtInsWithOverrides = builtInThemes.map((b) => _themeOverrides[b.id] ?? b).toList();
    final customList = _customThemes.where((c) => !builtInThemes.any((b) => b.id == c.id)).toList();
    return [...builtInsWithOverrides, ...customList];
  }

  /// Get active theme for light mode
  TheavTheme get activeLightTheme {
    if (_activeLightTheme != null) return _activeLightTheme!;
    return getAllThemes().firstWhere(
      (t) => t.id == _activeLightThemeId,
      orElse: () => builtInThemes[0],
    );
  }

  /// Get active theme for dark mode
  TheavTheme get activeDarkTheme {
    if (_activeDarkTheme != null) return _activeDarkTheme!;
    return getAllThemes().firstWhere(
      (t) => t.id == _activeDarkThemeId,
      orElse: () => builtInThemes[1],
    );
  }

  /// Set active theme for this specific device
  Future<void> setActiveTheme(TheavTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    if (theme.isDark) {
      _activeDarkThemeId = theme.id;
      _activeDarkTheme = theme;
      await prefs.setString(_keyActiveDarkId, theme.id);
      await prefs.setString(_keyActiveDarkThemeJson, jsonEncode(theme.toJson()));
    } else {
      _activeLightThemeId = theme.id;
      _activeLightTheme = theme;
      await prefs.setString(_keyActiveLightId, theme.id);
      await prefs.setString(_keyActiveLightThemeJson, jsonEncode(theme.toJson()));
    }

    _themeOverrides[theme.id] = theme;
    await _persistThemeOverrides();

    if (!theme.isBuiltIn) {
      final idx = _customThemes.indexWhere((t) => t.id == theme.id);
      if (idx != -1) {
        _customThemes[idx] = theme;
      } else {
        _customThemes.add(theme);
      }
      await _persistCustomThemes();
    }

    notifyListeners();
  }

  Future<void> _persistThemeOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final map = _themeOverrides.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_keyThemeOverrides, jsonEncode(map));
  }

  /// Sync custom themes from server account
  Future<void> syncCloudThemes() async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) return;

    _isSyncing = true;
    notifyListeners();

    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/user/themes'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        if (body['success'] == true && body['themes'] is List) {
          final List<dynamic> cloudList = body['themes'];
          final List<TheavTheme> fetched = [];

          for (final item in cloudList) {
            final themeId = item['theme_id'] as String;
            final themeData = item['theme_data'] as Map<String, dynamic>? ?? {};
            themeData['id'] = themeId;
            themeData['name'] = item['name'] ?? themeData['name'];
            themeData['isDark'] = item['is_dark'] ?? themeData['isDark'];

            fetched.add(TheavTheme.fromJson(themeData, isCloudSaved: true));
          }

          // Merge fetched cloud themes with local themes
          final Map<String, TheavTheme> map = {};
          for (final t in _customThemes) {
            map[t.id] = t;
          }
          for (final c in fetched) {
            final existing = map[c.id];
            TheavTheme toStore = c;
            if (existing != null) {
              // If local existing theme has an image file that exists on disk, keep imagePath
              if (c.wallpaper.type == 'image' &&
                  (c.wallpaper.imagePath == null || !File(c.wallpaper.imagePath!).existsSync()) &&
                  existing.wallpaper.imagePath != null &&
                  File(existing.wallpaper.imagePath!).existsSync()) {
                toStore = c.copyWith(
                  wallpaper: c.wallpaper.copyWith(imagePath: existing.wallpaper.imagePath),
                );
              }
            }
            map[c.id] = toStore;

            // Trigger background download of cloud wallpaper image if needed
            if (toStore.wallpaper.type == 'image' &&
                (toStore.wallpaper.imageUrl != null && toStore.wallpaper.imageUrl!.isNotEmpty) &&
                (toStore.wallpaper.imagePath == null || !File(toStore.wallpaper.imagePath!).existsSync())) {
              _downloadCloudWallpaperIfNeeded(toStore);
            }
          }

          _customThemes = map.values.toList();
          await _persistCustomThemes();

          // Update active themes if they match synced cloud custom themes
          final prefs = await SharedPreferences.getInstance();
          if (_activeLightTheme != null && map.containsKey(_activeLightTheme!.id)) {
            _activeLightTheme = map[_activeLightTheme!.id]!;
            await prefs.setString(_keyActiveLightThemeJson, jsonEncode(_activeLightTheme!.toJson()));
          }
          if (_activeDarkTheme != null && map.containsKey(_activeDarkTheme!.id)) {
            _activeDarkTheme = map[_activeDarkTheme!.id]!;
            await prefs.setString(_keyActiveDarkThemeJson, jsonEncode(_activeDarkTheme!.toJson()));
          }
        }
      }
    } catch (e) {
      debugPrint('TheavThemeService: syncCloudThemes error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Download cloud wallpaper image to local storage for offline use
  Future<void> _downloadCloudWallpaperIfNeeded(TheavTheme theme) async {
    if (theme.wallpaper.type != 'image' || theme.wallpaper.imageUrl == null) return;
    final url = theme.wallpaper.imageUrl!;
    if (url.isEmpty) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final wallpaperDir = Directory('${appDir.path}/wallpapers');
      if (!await wallpaperDir.exists()) {
        await wallpaperDir.create(recursive: true);
      }
      final sanitizedId = theme.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final targetFile = File('${wallpaperDir.path}/theme_wp_$sanitizedId.png');
      if (await targetFile.exists() && await targetFile.length() > 0) {
        _updateThemeWallpaperPath(theme.id, targetFile.path);
        return;
      }

      Uint8List? bytes;
      if (url.startsWith('data:')) {
        final commaIdx = url.indexOf(',');
        if (commaIdx != -1) {
          bytes = base64Decode(url.substring(commaIdx + 1));
        }
      } else {
        var fullUrl = url;
        if (fullUrl.contains('storage.miptgram.ru')) {
          fullUrl = fullUrl.replaceAll('storage.miptgram.ru', 'storage.theaver.app');
        } else if (fullUrl.contains('miptgram.ru')) {
          fullUrl = fullUrl.replaceAll('miptgram.ru', 'theaver.app');
        }
        if (fullUrl.startsWith('/')) {
          fullUrl = '${AppConfig.baseUrl}$fullUrl';
        }
        final token = await AuthService.getToken();
        final res = await http.get(
          Uri.parse(fullUrl),
          headers: token != null ? {'Authorization': 'Bearer $token'} : null,
        );
        if (res.statusCode == 200) {
          bytes = res.bodyBytes;
        }
      }

      if (bytes != null && bytes.isNotEmpty) {
        await targetFile.writeAsBytes(bytes);
        _updateThemeWallpaperPath(theme.id, targetFile.path);
      }
    } catch (e) {
      debugPrint('TheavThemeService: Error downloading cloud wallpaper for theme ${theme.id}: $e');
    }
  }

  void _updateThemeWallpaperPath(String themeId, String path) {
    final idx = _customThemes.indexWhere((t) => t.id == themeId);
    if (idx != -1) {
      _customThemes[idx] = _customThemes[idx].copyWith(
        wallpaper: _customThemes[idx].wallpaper.copyWith(imagePath: path),
      );
      _persistCustomThemes();
    }
    if (_activeLightTheme?.id == themeId) {
      _activeLightTheme = _activeLightTheme!.copyWith(
        wallpaper: _activeLightTheme!.wallpaper.copyWith(imagePath: path),
      );
    }
    if (_activeDarkTheme?.id == themeId) {
      _activeDarkTheme = _activeDarkTheme!.copyWith(
        wallpaper: _activeDarkTheme!.wallpaper.copyWith(imagePath: path),
      );
    }
    notifyListeners();
  }

  /// Save or update a theme in account cloud and local list
  Future<bool> saveTheme(TheavTheme theme, {bool saveToCloud = true}) async {
    var themeToSave = theme;

    // If saving to cloud and wallpaper is a local image without a remote imageUrl, upload it
    if (saveToCloud && themeToSave.wallpaper.type == 'image') {
      final imgPath = themeToSave.wallpaper.imagePath;
      if (imgPath != null &&
          (themeToSave.wallpaper.imageUrl == null || themeToSave.wallpaper.imageUrl!.isEmpty)) {
        final file = File(imgPath);
        if (await file.exists()) {
          try {
            final uploadRes = await AuthService.uploadWallpaper(imgPath);
            if (uploadRes['success'] == true && uploadRes['wallpaper_url'] != null) {
              final serverUrl = uploadRes['wallpaper_url'] as String;
              themeToSave = themeToSave.copyWith(
                wallpaper: themeToSave.wallpaper.copyWith(imageUrl: serverUrl),
              );
              debugPrint('TheavThemeService: Uploaded theme wallpaper image to $serverUrl');
            }
          } catch (e) {
            debugPrint('TheavThemeService: Error uploading theme wallpaper: $e');
          }
        }
      }
    }

    _themeOverrides[themeToSave.id] = themeToSave;
    await _persistThemeOverrides();

    final prefs = await SharedPreferences.getInstance();
    if (themeToSave.id == _activeLightThemeId || (!themeToSave.isDark && _activeLightTheme?.id == themeToSave.id)) {
      _activeLightTheme = themeToSave;
      await prefs.setString(_keyActiveLightThemeJson, jsonEncode(themeToSave.toJson()));
    }
    if (themeToSave.id == _activeDarkThemeId || (themeToSave.isDark && _activeDarkTheme?.id == themeToSave.id)) {
      _activeDarkTheme = themeToSave;
      await prefs.setString(_keyActiveDarkThemeJson, jsonEncode(themeToSave.toJson()));
    }

    // 1. Update local custom themes list if custom theme
    if (!themeToSave.isBuiltIn) {
      final idx = _customThemes.indexWhere((t) => t.id == themeToSave.id);
      if (idx != -1) {
        _customThemes[idx] = themeToSave.copyWith(isCloudSaved: saveToCloud || themeToSave.isCloudSaved);
      } else {
        _customThemes.add(themeToSave.copyWith(isCloudSaved: saveToCloud));
      }
      await _persistCustomThemes();
    }
    notifyListeners();

    // 2. Upload to server if requested
    if (saveToCloud) {
      try {
        final token = await AuthService.getToken();
        if (token != null && token.isNotEmpty) {
          final res = await http.post(
            Uri.parse('${AppConfig.baseUrl}/api/user/themes'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'theme_id': themeToSave.id,
              'name': themeToSave.name,
              'is_dark': themeToSave.isDark,
              'theme_data': themeToSave.toJson(),
            }),
          );
          if (res.statusCode == 200) {
            debugPrint('TheavThemeService: Successfully saved theme ${themeToSave.id} to cloud');
            return true;
          }
        }
      } catch (e) {
        debugPrint('TheavThemeService: Error saving theme to cloud: $e');
      }
    }
    return true;
  }

  /// Delete a theme locally and from server
  Future<void> deleteTheme(String themeId) async {
    _customThemes.removeWhere((t) => t.id == themeId);
    _themeOverrides.remove(themeId);
    await _persistCustomThemes();
    await _persistThemeOverrides();

    final prefs = await SharedPreferences.getInstance();
    // If active theme was deleted, reset to default
    if (_activeLightThemeId == themeId) {
      _activeLightThemeId = builtInThemes[0].id;
      _activeLightTheme = builtInThemes[0];
      await prefs.setString(_keyActiveLightId, _activeLightThemeId);
      await prefs.setString(_keyActiveLightThemeJson, jsonEncode(_activeLightTheme!.toJson()));
    }
    if (_activeDarkThemeId == themeId) {
      _activeDarkThemeId = builtInThemes[1].id;
      _activeDarkTheme = builtInThemes[1];
      await prefs.setString(_keyActiveDarkId, _activeDarkThemeId);
      await prefs.setString(_keyActiveDarkThemeJson, jsonEncode(_activeDarkTheme!.toJson()));
    }
    notifyListeners();

    // Delete from cloud
    try {
      final token = await AuthService.getToken();
      if (token != null && token.isNotEmpty) {
        await http.delete(
          Uri.parse('${AppConfig.baseUrl}/api/user/themes/$themeId'),
          headers: {'Authorization': 'Bearer $token'},
        );
      }
    } catch (e) {
      debugPrint('TheavThemeService: Error deleting theme from cloud: $e');
    }
  }

  Future<void> _persistCustomThemes() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _customThemes.map((t) => t.toJson()).toList();
    await prefs.setString(_keyCachedCustomThemes, jsonEncode(jsonList));
  }

  /// Package a TheavTheme into a .theavtheme ZIP archive
  Future<Uint8List> exportThemePackage(TheavTheme theme) async {
    final archive = Archive();

    // 1. theme.json
    final manifestBytes = utf8.encode(jsonEncode(theme.toJson()));
    archive.addFile(ArchiveFile('theme.json', manifestBytes.length, manifestBytes));

    // 2. Custom wallpaper asset if present
    if (theme.wallpaper.imagePath != null && await File(theme.wallpaper.imagePath!).exists()) {
      final file = File(theme.wallpaper.imagePath!);
      final imgBytes = await file.readAsBytes();
      archive.addFile(ArchiveFile('wallpaper.png', imgBytes.length, imgBytes));
    } else if (theme.wallpaper.imageUrl != null && theme.wallpaper.imageUrl!.isNotEmpty) {
      try {
        final url = theme.wallpaper.imageUrl!;
        Uint8List? imgBytes;
        if (url.startsWith('data:')) {
          final commaIdx = url.indexOf(',');
          if (commaIdx != -1) {
            imgBytes = base64Decode(url.substring(commaIdx + 1));
          }
        } else {
          var fullUrl = url;
          if (fullUrl.contains('storage.miptgram.ru')) {
            fullUrl = fullUrl.replaceAll('storage.miptgram.ru', 'storage.theaver.app');
          } else if (fullUrl.contains('miptgram.ru')) {
            fullUrl = fullUrl.replaceAll('miptgram.ru', 'theaver.app');
          }
          if (fullUrl.startsWith('/')) {
            fullUrl = '${AppConfig.baseUrl}$fullUrl';
          }
          final token = await AuthService.getToken();
          final res = await http.get(
            Uri.parse(fullUrl),
            headers: token != null ? {'Authorization': 'Bearer $token'} : null,
          );
          if (res.statusCode == 200) {
            imgBytes = res.bodyBytes;
          }
        }
        if (imgBytes != null && imgBytes.isNotEmpty) {
          archive.addFile(ArchiveFile('wallpaper.png', imgBytes.length, imgBytes));
        }
      } catch (e) {
        debugPrint('TheavThemeService: Error bundling remote wallpaper: $e');
      }
    } else if (theme.wallpaper.customSvgPath != null) {
      final file = File(theme.wallpaper.customSvgPath!);
      if (await file.exists()) {
        final svgBytes = await file.readAsBytes();
        archive.addFile(ArchiveFile('wallpaper.svg', svgBytes.length, svgBytes));
      }
    }

    final encoder = ZipEncoder();
    final zipData = encoder.encode(archive);
    return Uint8List.fromList(zipData ?? []);
  }

  /// Import a TheavTheme from a .theavtheme ZIP archive
  Future<TheavTheme> importThemePackage(Uint8List zipBytes) async {
    final decoder = ZipDecoder();
    final archive = decoder.decodeBytes(zipBytes);

    ArchiveFile? manifestFile;
    ArchiveFile? wallpaperFile;

    for (final file in archive) {
      if (file.name == 'theme.json') {
        manifestFile = file;
      } else if (file.name == 'wallpaper.png' || file.name == 'wallpaper.svg') {
        wallpaperFile = file;
      }
    }

    if (manifestFile == null) {
      throw Exception('Invalid .theavtheme: theme.json manifest missing');
    }

    final jsonStr = utf8.decode(manifestFile.content as List<int>);
    final Map<String, dynamic> data = jsonDecode(jsonStr);

    String? localWallpaperPath;
    if (wallpaperFile != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory('${appDir.path}/imported_wallpapers');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      final savedFile = File('${targetDir.path}/${DateTime.now().millisecondsSinceEpoch}_${wallpaperFile.name}');
      await savedFile.writeAsBytes(wallpaperFile.content as List<int>);
      localWallpaperPath = savedFile.path;
    }

    var importedTheme = TheavTheme.fromJson(data);
    if (localWallpaperPath != null) {
      if (wallpaperFile!.name.endsWith('.svg')) {
        importedTheme = importedTheme.copyWith(
          wallpaper: importedTheme.wallpaper.copyWith(customSvgPath: localWallpaperPath),
        );
      } else {
        importedTheme = importedTheme.copyWith(
          wallpaper: importedTheme.wallpaper.copyWith(imagePath: localWallpaperPath),
        );
      }
    }

    return importedTheme;
  }
}
