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
  static const String _keyCachedCustomThemes = 'device_cached_custom_themes';

  String _activeLightThemeId = 'theaver_classic';
  String _activeDarkThemeId = 'dark_slate';
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
        patternName: 'christmas',
        backgroundColor: Color(0xFFE1F5FE),
        patternColor: Color(0xFF0288D1),
        patternOpacity: 0.16,
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
        type: 'gradient4',
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
        motionEnabled: true,
      ),
    ),
  ];

  /// Initialize service, load local preferences, and sync with cloud
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _activeLightThemeId = prefs.getString(_keyActiveLightId) ?? 'theaver_classic';
    _activeDarkThemeId = prefs.getString(_keyActiveDarkId) ?? 'dark_slate';

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
    notifyListeners();

    // Background sync from server
    syncCloudThemes();
  }

  /// Get all available themes (built-ins + custom/cloud)
  List<TheavTheme> getAllThemes() {
    return [...builtInThemes, ..._customThemes];
  }

  /// Get active theme for light mode
  TheavTheme get activeLightTheme {
    return getAllThemes().firstWhere(
      (t) => t.id == _activeLightThemeId,
      orElse: () => builtInThemes[0],
    );
  }

  /// Get active theme for dark mode
  TheavTheme get activeDarkTheme {
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
      await prefs.setString(_keyActiveDarkId, theme.id);
    } else {
      _activeLightThemeId = theme.id;
      await prefs.setString(_keyActiveLightId, theme.id);
    }
    notifyListeners();
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
            map[c.id] = c;
          }

          _customThemes = map.values.toList();
          await _persistCustomThemes();
        }
      }
    } catch (e) {
      debugPrint('TheavThemeService: syncCloudThemes error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Save or update a theme in account cloud and local list
  Future<bool> saveTheme(TheavTheme theme, {bool saveToCloud = true}) async {
    // 1. Update local custom themes list
    final idx = _customThemes.indexWhere((t) => t.id == theme.id);
    if (idx != -1) {
      _customThemes[idx] = theme.copyWith(isCloudSaved: saveToCloud || theme.isCloudSaved);
    } else {
      _customThemes.add(theme.copyWith(isCloudSaved: saveToCloud));
    }
    await _persistCustomThemes();
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
              'theme_id': theme.id,
              'name': theme.name,
              'is_dark': theme.isDark,
              'theme_data': theme.toJson(),
            }),
          );
          if (res.statusCode == 200) {
            debugPrint('TheavThemeService: Successfully saved theme ${theme.id} to cloud');
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
    await _persistCustomThemes();

    // If active theme was deleted, reset to default
    if (_activeLightThemeId == themeId) {
      _activeLightThemeId = builtInThemes[0].id;
    }
    if (_activeDarkThemeId == themeId) {
      _activeDarkThemeId = builtInThemes[1].id;
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
    if (theme.wallpaper.imagePath != null) {
      final file = File(theme.wallpaper.imagePath!);
      if (await file.exists()) {
        final imgBytes = await file.readAsBytes();
        archive.addFile(ArchiveFile('wallpaper.png', imgBytes.length, imgBytes));
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
