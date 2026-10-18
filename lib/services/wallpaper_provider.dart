import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'account_manager.dart';
import 'auth_service.dart';
import 'websocket_service.dart';

class WallpaperProvider extends ChangeNotifier {
  static const String _legacyWallpaperPathKey = 'chat_wallpaper_path';
  static String _wallpaperPathKey(String uid) => '${uid}_chat_wallpaper_path';
  static String _wallpaperUrlKey(String uid) => '${uid}_chat_wallpaper_url';

  String? _currentUserId;
  String? _wallpaperPath;
  String? _wallpaperUrl;
  bool _isInitialized = false;

  String? get currentUserId => _currentUserId;
  String? get wallpaperPath => _wallpaperPath;
  String? get wallpaperUrl => _wallpaperUrl;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    final accountManager = AccountManager();
    accountManager.removeListener(_onAccountManagerChanged);
    accountManager.addListener(_onAccountManagerChanged);

    // Listen to WebSocket appearance updates for wallpaper sync
    WebSocketService().eventStream.listen(_handleWebSocketEvent);

    final currentUid = accountManager.currentAccount?.userId ?? await AuthService.getUserId();
    await switchUser(currentUid, force: true);
  }

  void _onAccountManagerChanged() {
    final newUid = AccountManager().currentAccount?.userId;
    if (newUid != _currentUserId) {
      switchUser(newUid);
    }
  }

  void _handleWebSocketEvent(WebSocketEvent event) {
    if (event.type == WebSocketEventType.userAppearanceUpdated) {
      final data = event.data;
      final eventUserId = data['user_id']?.toString();
      if (eventUserId != null && eventUserId == _currentUserId) {
        if (data.containsKey('wallpaper_url')) {
          final newWpUrl = data['wallpaper_url'] as String?;
          if (newWpUrl == null || newWpUrl.isEmpty) {
            removeWallpaper(syncToServer: false);
          } else {
            onRemoteWallpaperUpdated(newWpUrl, targetUserId: eventUserId);
          }
        }
      }
    }
  }

  /// Switch active wallpaper to specific user
  Future<void> switchUser(String? userId, {bool force = false}) async {
    if (!force && _currentUserId == userId) return;
    _currentUserId = userId;

    if (userId == null || userId.isEmpty) {
      _wallpaperPath = null;
      _wallpaperUrl = null;
      notifyListeners();
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // Migrate legacy non-scoped key to current user if needed
    if (!kIsWeb && prefs.containsKey(_legacyWallpaperPathKey)) {
      final legacyPath = prefs.getString(_legacyWallpaperPathKey);
      await prefs.remove(_legacyWallpaperPathKey);
      if (legacyPath != null && await File(legacyPath).exists()) {
        await prefs.setString(_wallpaperPathKey(userId), legacyPath);
      }
    }

    _wallpaperPath = kIsWeb ? null : prefs.getString(_wallpaperPathKey(userId));
    _wallpaperUrl = prefs.getString(_wallpaperUrlKey(userId));

    if (!kIsWeb && _wallpaperPath != null) {
      if (!await File(_wallpaperPath!).exists()) {
        _wallpaperPath = null;
        await prefs.remove(_wallpaperPathKey(userId));
      }
    }

    notifyListeners();

    // Background sync from server
    _syncFromServer(userId);
  }

  Future<void> _syncFromServer(String userId) async {
    try {
      final res = await AuthService.getAppearance();
      if (res['success'] == true && res['appearance'] != null) {
        final serverWpUrl = res['appearance']['wallpaper_url'] as String?;
        if (serverWpUrl != null && serverWpUrl.isNotEmpty) {
          if (serverWpUrl != _wallpaperUrl || (!kIsWeb && _wallpaperPath == null)) {
            await onRemoteWallpaperUpdated(serverWpUrl, targetUserId: userId);
          }
        } else if (_wallpaperUrl != null && _wallpaperUrl!.isNotEmpty) {
          // Server has no wallpaper, remove local if it was synced
          await removeWallpaper(syncToServer: false);
        }
      }
    } catch (e) {
      debugPrint('WallpaperProvider: Sync from server error: $e');
    }
  }

  /// Set local wallpaper path and sync to server asynchronously
  Future<void> setWallpaper(String path, {bool syncToServer = true}) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      _wallpaperPath = path;
      notifyListeners();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wallpaperPathKey(uid), path);
    _wallpaperPath = path;
    notifyListeners();

    if (syncToServer && !kIsWeb) {
      _uploadToServer(uid, path);
    }
  }

  Future<void> _uploadToServer(String uid, String filePath) async {
    try {
      final res = await AuthService.uploadWallpaper(filePath);
      if (res['success'] == true && res['wallpaper_url'] != null) {
        final serverUrl = res['wallpaper_url'] as String;
        _wallpaperUrl = serverUrl;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_wallpaperUrlKey(uid), serverUrl);
        debugPrint('WallpaperProvider: Successfully synced wallpaper to server for $uid');
      } else {
        debugPrint('WallpaperProvider: Upload failed: ${res['message']}');
      }
    } catch (e) {
      debugPrint('WallpaperProvider: Upload to server error: $e');
    }
  }

  /// Remove wallpaper locally and from server
  Future<void> removeWallpaper({bool syncToServer = true}) async {
    final uid = _currentUserId;
    if (uid != null && uid.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_wallpaperPathKey(uid));
      await prefs.remove(_wallpaperUrlKey(uid));
    }

    if (!kIsWeb && _wallpaperPath != null) {
      try {
        final file = File(_wallpaperPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    _wallpaperPath = null;
    _wallpaperUrl = null;
    notifyListeners();

    if (syncToServer && uid != null && uid.isNotEmpty) {
      try {
        await AuthService.deleteWallpaper();
      } catch (e) {
        debugPrint('WallpaperProvider: Delete from server error: $e');
      }
    }
  }

  /// Handle remote wallpaper update (download and save locally)
  Future<void> onRemoteWallpaperUpdated(String remoteUrl, {String? targetUserId}) async {
    final uid = targetUserId ?? _currentUserId;
    if (uid == null || uid.isEmpty) return;

    if (remoteUrl.contains('storage.miptgram.ru')) {
      remoteUrl = remoteUrl.replaceAll('storage.miptgram.ru', 'storage.theaver.app');
    } else if (remoteUrl.contains('miptgram.ru')) {
      remoteUrl = remoteUrl.replaceAll('miptgram.ru', 'theaver.app');
    }

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_wallpaperUrlKey(uid), remoteUrl);
      if (uid == _currentUserId) {
        _wallpaperUrl = remoteUrl;
        notifyListeners();
      }
      return;
    }

    try {
      Uint8List? imageBytes;
      if (remoteUrl.startsWith('data:')) {
        final commaIdx = remoteUrl.indexOf(',');
        if (commaIdx != -1) {
          final base64Str = remoteUrl.substring(commaIdx + 1);
          imageBytes = base64Decode(base64Str);
        }
      } else {
        String fullUrl = remoteUrl;
        if (fullUrl.startsWith('/')) {
          fullUrl = '${AppConfig.baseUrl}$fullUrl';
        }
        final token = await AuthService.getToken();
        final res = await http.get(
          Uri.parse(fullUrl),
          headers: token != null ? {'Authorization': 'Bearer $token'} : null,
        );
        if (res.statusCode == 200) {
          imageBytes = res.bodyBytes;
        }
      }

      if (imageBytes != null && imageBytes.isNotEmpty) {
        final appDir = await getApplicationDocumentsDirectory();
        final wallpaperDir = Directory('${appDir.path}/wallpapers');
        if (!await wallpaperDir.exists()) {
          await wallpaperDir.create(recursive: true);
        }
        final localFile = File('${wallpaperDir.path}/chat_wallpaper_$uid.png');
        await localFile.writeAsBytes(imageBytes);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_wallpaperPathKey(uid), localFile.path);
        await prefs.setString(_wallpaperUrlKey(uid), remoteUrl);

        if (uid == _currentUserId) {
          _wallpaperPath = localFile.path;
          _wallpaperUrl = remoteUrl;
          notifyListeners();
        }
        debugPrint('WallpaperProvider: Downloaded and applied remote wallpaper for $uid');
      }
    } catch (e) {
      debugPrint('WallpaperProvider: Failed to download remote wallpaper: $e');
    }
  }

  @override
  void dispose() {
    AccountManager().removeListener(_onAccountManagerChanged);
    super.dispose();
  }
}

