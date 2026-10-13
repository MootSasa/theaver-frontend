import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/chat_folder.dart';
import 'account_manager.dart';
import 'auth_service.dart';

/// Service managing user-configurable chat folders with per-account local persistence
/// and backend cloud synchronization.
class ChatFolderService extends ChangeNotifier {
  ChatFolderService._internal();
  static final ChatFolderService _instance = ChatFolderService._internal();
  factory ChatFolderService() => _instance;

  late SharedPreferences _prefs;
  String? _currentUserId;
  List<ChatFolder> _folders = [];

  List<ChatFolder> get folders => List.unmodifiable(_folders);

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Initialize the folder service and hook into AccountManager
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final accountManager = AccountManager();
    accountManager.removeListener(_onAccountChanged);
    accountManager.addListener(_onAccountChanged);

    final currentUid = accountManager.currentAccount?.userId;
    await _switchUser(currentUid);
    _initialized = true;
  }

  void _onAccountChanged() {
    final newUid = AccountManager().currentAccount?.userId;
    if (newUid != _currentUserId) {
      _switchUser(newUid);
    }
  }

  String _storageKey(String? userId) =>
      userId != null && userId.isNotEmpty
          ? 'user_${userId}_chat_folders'
          : 'chat_folders_default';

  Future<void> _switchUser(String? userId) async {
    _currentUserId = userId;
    await _loadFromLocal();
    notifyListeners();
    // Background cloud sync
    syncFromCloud();
  }

  Future<void> _loadFromLocal() async {
    final key = _storageKey(_currentUserId);
    final jsonStr = _prefs.getString(key);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        _folders = decoded
            .map((item) => ChatFolder.fromJson(item as Map<String, dynamic>))
            .toList();
        _folders.sort((a, b) => a.order.compareTo(b.order));
        if (_folders.isNotEmpty) return;
      } catch (e) {
        debugPrint('[ChatFolderService] Error parsing local folders: $e');
      }
    }

    // Default baseline if no folders stored
    _folders = List.from(ChatFolder.defaults);
    await _saveToLocal();
  }

  Future<void> _saveToLocal() async {
    final key = _storageKey(_currentUserId);
    final jsonStr = jsonEncode(_folders.map((f) => f.toJson()).toList());
    await _prefs.setString(key, jsonStr);
  }

  /// Sync folders from cloud API
  Future<void> syncFromCloud() async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) return;

      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/user/folders'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['success'] == true && data['folders'] is List) {
          final List<dynamic> cloudList = data['folders'];
          if (cloudList.isNotEmpty) {
            _folders = cloudList
                .map((item) => ChatFolder.fromJson(item as Map<String, dynamic>))
                .toList();
            _folders.sort((a, b) => a.order.compareTo(b.order));
            await _saveToLocal();
            notifyListeners();
          } else if (_folders.isNotEmpty) {
            // First time cloud sync: push current default/local folders to cloud
            _pushToCloud();
          }
        }
      }
    } catch (e) {
      debugPrint('[ChatFolderService] Cloud sync skipped/failed: $e');
    }
  }

  /// Push current folder configuration to cloud
  Future<void> _pushToCloud() async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) return;

      await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/user/folders'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'folders': _folders.map((f) => f.toJson()).toList(),
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[ChatFolderService] Cloud push skipped/failed: $e');
    }
  }

  /// Save full list of folders and propagate locally and to cloud
  Future<void> saveFolders(List<ChatFolder> newFolders) async {
    _folders = List.from(newFolders);
    // Ensure order is normalized
    for (int i = 0; i < _folders.length; i++) {
      _folders[i] = _folders[i].copyWith(order: i);
    }
    await _saveToLocal();
    notifyListeners();
    _pushToCloud();
  }

  /// Reorder folders via drag-and-drop
  Future<void> reorderFolders(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _folders.length) return;
    if (newIndex < 0 || newIndex > _folders.length) return;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _folders.removeAt(oldIndex);
    _folders.insert(newIndex, item);

    await saveFolders(_folders);
  }

  /// Add a new folder
  Future<void> addFolder(ChatFolder folder) async {
    final updated = List<ChatFolder>.from(_folders);
    updated.add(folder.copyWith(order: updated.length));
    await saveFolders(updated);
  }

  /// Update an existing folder
  Future<void> updateFolder(ChatFolder folder) async {
    final idx = _folders.indexWhere((f) => f.id == folder.id);
    if (idx != -1) {
      final updated = List<ChatFolder>.from(_folders);
      updated[idx] = folder;
      await saveFolders(updated);
    }
  }

  /// Remove a folder (cannot remove 'all')
  Future<void> removeFolder(String folderId) async {
    if (folderId == 'all') return;
    final updated = _folders.where((f) => f.id != folderId).toList();
    await saveFolders(updated);
  }
}
