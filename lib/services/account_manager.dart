import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'auth_service.dart';

/// Manages multiple user accounts and device sessions.
/// Provides functionality for:
/// - Storing and switching between multiple accounts
/// - Remembering the last active account
/// - Tracking device sessions
class AccountManager extends ChangeNotifier {
  AccountManager._internal();
  static final AccountManager _instance = AccountManager._internal();
  factory AccountManager() => _instance;

  late SharedPreferences _prefs;
  
  // Storage keys
  static const String _accountsKey = 'accounts';
  static const String _currentAccountIdKey = 'current_account_id';
  static const String _deviceSessionsKey = 'device_sessions';
  static const String _currentDeviceIdKey = 'current_device_id';
  static const String _pendingProfileSyncKey = 'pending_profile_sync';

  List<Account> _accounts = [];
  Account? _currentAccount;
  List<DeviceSession> _deviceSessions = [];
  String? _currentDeviceId;

  /// Initialize the account manager. Must be called before using.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadAccounts();
    await _loadDeviceSessions();
    await _initCurrentDevice();
    unawaited(trySyncPendingProfile());
  }

  // ==================== Account Management ====================

  Future<void> _loadAccounts() async {
    final accountsJson = _prefs.getStringList(_accountsKey) ?? [];
    _accounts = accountsJson.map((json) => Account.fromJson(jsonDecode(json))).toList();

    final currentAccountId = _prefs.getString(_currentAccountIdKey);
    if (currentAccountId != null) {
      try {
        _currentAccount = _accounts.firstWhere((acc) => acc.userId == currentAccountId);
      } catch (_) {
        _currentAccount = null;
      }
    }
  }

  Future<void> _saveAccounts() async {
    final accountsJson = _accounts.map((acc) => jsonEncode(acc.toJson())).toList();
    await _prefs.setStringList(_accountsKey, accountsJson);
    if (_currentAccount != null) {
      await _prefs.setString(_currentAccountIdKey, _currentAccount!.userId);
    } else {
      await _prefs.remove(_currentAccountIdKey);
    }
    notifyListeners();
  }

  /// Add a new account. Throws if account with same userId already exists.
  Future<void> addAccount(Account account) async {
    if (_accounts.any((acc) => acc.userId == account.userId)) {
      throw Exception('Account with userId ${account.userId} already exists.');
    }
    _accounts.add(account);
    _currentAccount = account;
    await _saveAccounts();
  }

  /// Remove an account and optionally logout from its sessions.
  Future<void> removeAccount(String userId) async {
    _accounts.removeWhere((acc) => acc.userId == userId);
    if (_currentAccount?.userId == userId) {
      _currentAccount = null;
    }
    await _saveAccounts();
  }

  /// Clears the currently active account pointer without removing accounts from the list
  Future<void> clearCurrentAccount() async {
    _currentAccount = null;
    await _saveAccounts();
  }

  /// Get the currently active account.
  Account? get currentAccount => _currentAccount;

  /// Set the current active account by userId.
  Future<void> setCurrentAccount(String userId) async {
    final account = _accounts.firstWhere(
      (acc) => acc.userId == userId,
      orElse: () => throw Exception('Account not found'),
    );
    _currentAccount = account;
    await _saveAccounts();
  }

  /// Get all stored accounts.
  List<Account> get accounts => List.unmodifiable(_accounts);

  /// Check if an account exists.
  bool hasAccount(String userId) => _accounts.any((acc) => acc.userId == userId);

  /// Update account token.
  Future<void> updateAccountToken(String userId, String token) async {
    final index = _accounts.indexWhere((acc) => acc.userId == userId);
    if (index != -1) {
      final oldAccount = _accounts[index];
      _accounts[index] = oldAccount.copyWith(
        token: token,
        lastLogin: DateTime.now(),
      );
      if (_currentAccount?.userId == userId) {
        _currentAccount = _accounts[index];
      }
      await _saveAccounts();
    }
  }

  /// Update account profile information.
  Future<void> updateAccountProfile(String userId, {
    String? username,
    String? displayName,
    String? avatarUrl,
    String? name,
    String? surname,
    String? email,
    String? phone,
    String? localAvatarPath,
  }) async {
    final index = _accounts.indexWhere((acc) => acc.userId == userId);
    if (index != -1) {
      final oldAccount = _accounts[index];
      _accounts[index] = Account(
        userId: oldAccount.userId,
        token: oldAccount.token,
        username: username ?? oldAccount.username,
        displayName: displayName ?? oldAccount.displayName,
        avatarUrl: avatarUrl ?? oldAccount.avatarUrl,
        lastLogin: oldAccount.lastLogin,
        name: name ?? oldAccount.name,
        surname: surname ?? oldAccount.surname,
        email: email ?? oldAccount.email,
        phone: phone ?? oldAccount.phone,
        localAvatarPath: localAvatarPath ?? oldAccount.localAvatarPath,
      );
      if (_currentAccount?.userId == userId) {
        _currentAccount = _accounts[index];
      }
      await _saveAccounts();
    }
  }

  /// Сохраняет локально несохраненные параметры профиля для последующей синхронизации
  Future<void> savePendingProfileSync(Map<String, dynamic> data) async {
    await _prefs.setString(_pendingProfileSyncKey, jsonEncode(data));
  }

  /// Получает несохраненные локальные параметры профиля
  Map<String, dynamic>? getPendingProfileSync() {
    final raw = _prefs.getString(_pendingProfileSyncKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Очищает несохраненные параметры после успешной синхронизации
  Future<void> clearPendingProfileSync() async {
    await _prefs.remove(_pendingProfileSyncKey);
  }

  /// Попытка синхронизации несохраненного профиля с сервером при запуске приложения
  Future<void> trySyncPendingProfile() async {
    final pendingData = getPendingProfileSync();
    if (pendingData == null) return;

    try {
      final name = pendingData['name'] as String? ?? '';
      final surname = pendingData['surname'] as String? ?? '';
      final username = pendingData['username'] as String? ?? '';
      final email = pendingData['email'] as String? ?? '';
      final phone = pendingData['phone'] as String? ?? '';

      final result = await AuthService.updateProfile(
        name: name,
        surname: surname,
        username: username,
        email: email,
        phone: phone,
      );

      if (result['synced'] == true) {
        await clearPendingProfileSync();
      }
    } catch (_) {}
  }

  /// Check if there's a saved account to auto-login.
  bool get hasSavedAccount => _currentAccount != null;

  /// Get the last active account ID.
  String? get lastActiveAccountId => _prefs.getString(_currentAccountIdKey);

  // ==================== Device Session Management ====================

  Future<void> _initCurrentDevice() async {
    _currentDeviceId = _prefs.getString(_currentDeviceIdKey);
    if (_currentDeviceId == null) {
      // Generate a unique device ID
      _currentDeviceId = '${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(8)}';
      await _prefs.setString(_currentDeviceIdKey, _currentDeviceId!);
    }
  }

  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    return List.generate(length, (i) => chars[(random + i) % chars.length]).join();
  }

  Future<void> _loadDeviceSessions() async {
    final sessionsJson = _prefs.getStringList(_deviceSessionsKey) ?? [];
    _deviceSessions = sessionsJson.map((json) => DeviceSession.fromJson(jsonDecode(json))).toList();
  }

  Future<void> _saveDeviceSessions() async {
    final sessionsJson = _deviceSessions.map((s) => jsonEncode(s.toJson())).toList();
    await _prefs.setStringList(_deviceSessionsKey, sessionsJson);
  }

  /// Get device information for current device.
  Future<DeviceInfo> getCurrentDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    
    if (kIsWeb) {
      final webInfo = await deviceInfo.webBrowserInfo;
      return DeviceInfo(
        deviceName: '${webInfo.browserName.name} on ${webInfo.platform ?? 'Web'}',
        deviceType: DeviceType.web,
        os: webInfo.platform ?? 'Web',
        osVersion: webInfo.appVersion ?? 'Unknown',
      );
    }
    
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return DeviceInfo(
        deviceName: '${androidInfo.manufacturer} ${androidInfo.model}',
        deviceType: DeviceType.android,
        os: 'Android',
        osVersion: androidInfo.version.release,
      );
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return DeviceInfo(
        deviceName: iosInfo.name,
        deviceType: DeviceType.ios,
        os: 'iOS',
        osVersion: iosInfo.systemVersion,
      );
    } else if (Platform.isLinux) {
      final linuxInfo = await deviceInfo.linuxInfo;
      return DeviceInfo(
        deviceName: linuxInfo.name,
        deviceType: DeviceType.linux,
        os: 'Linux',
        osVersion: linuxInfo.version ?? 'Unknown',
      );
    } else if (Platform.isWindows) {
      final windowsInfo = await deviceInfo.windowsInfo;
      return DeviceInfo(
        deviceName: 'Windows PC',
        deviceType: DeviceType.windows,
        os: 'Windows',
        osVersion: windowsInfo.displayVersion,
      );
    } else if (Platform.isMacOS) {
      final macInfo = await deviceInfo.macOsInfo;
      return DeviceInfo(
        deviceName: macInfo.computerName,
        deviceType: DeviceType.macos,
        os: 'macOS',
        osVersion: macInfo.osRelease,
      );
    }
    
    return DeviceInfo(
      deviceName: 'Unknown Device',
      deviceType: DeviceType.unknown,
      os: 'Unknown',
      osVersion: 'Unknown',
    );
  }

  /// Register current device session for an account.
  Future<void> registerDeviceSession(String userId) async {
    final deviceInfo = await getCurrentDeviceInfo();
    final now = DateTime.now();
    
    // Check if device already registered for this account
    final existingIndex = _deviceSessions.indexWhere(
      (s) => s.deviceId == _currentDeviceId && s.userId == userId,
    );
    
    if (existingIndex != -1) {
      // Update existing session
      _deviceSessions[existingIndex] = DeviceSession(
        id: _deviceSessions[existingIndex].id,
        deviceId: _currentDeviceId!,
        userId: userId,
        deviceName: deviceInfo.deviceName,
        deviceType: deviceInfo.deviceType,
        os: deviceInfo.os,
        osVersion: deviceInfo.osVersion,
        lastActive: now,
        isCurrent: true,
        location: _deviceSessions[existingIndex].location,
      );
    } else {
      // Create new session
      final session = DeviceSession(
        id: 'session_${now.millisecondsSinceEpoch}',
        deviceId: _currentDeviceId!,
        userId: userId,
        deviceName: deviceInfo.deviceName,
        deviceType: deviceInfo.deviceType,
        os: deviceInfo.os,
        osVersion: deviceInfo.osVersion,
        lastActive: now,
        isCurrent: true,
      );
      _deviceSessions.add(session);
    }
    
    // Mark other sessions as not current
    for (int i = 0; i < _deviceSessions.length; i++) {
      if (_deviceSessions[i].deviceId != _currentDeviceId) {
        _deviceSessions[i] = DeviceSession(
          id: _deviceSessions[i].id,
          deviceId: _deviceSessions[i].deviceId,
          userId: _deviceSessions[i].userId,
          deviceName: _deviceSessions[i].deviceName,
          deviceType: _deviceSessions[i].deviceType,
          os: _deviceSessions[i].os,
          osVersion: _deviceSessions[i].osVersion,
          lastActive: _deviceSessions[i].lastActive,
          isCurrent: false,
          location: _deviceSessions[i].location,
        );
      }
    }
    
    await _saveDeviceSessions();
  }

  /// Get all device sessions for current account.
  List<DeviceSession> getDeviceSessionsForAccount(String userId) {
    return _deviceSessions.where((s) => s.userId == userId).toList();
  }

  /// Get all device sessions (for all accounts).
  List<DeviceSession> get allDeviceSessions => List.unmodifiable(_deviceSessions);

  /// Remove a device session.
  Future<void> removeDeviceSession(String sessionId) async {
    _deviceSessions.removeWhere((s) => s.id == sessionId);
    await _saveDeviceSessions();
  }

  /// Remove all device sessions for an account (except current).
  Future<void> removeAllDeviceSessionsForAccount(String userId) async {
    _deviceSessions.removeWhere(
      (s) => s.userId == userId && s.deviceId != _currentDeviceId,
    );
    await _saveDeviceSessions();
  }

  /// Update last active time for current device.
  Future<void> updateCurrentDeviceActivity() async {
    if (_currentAccount == null || _currentDeviceId == null) return;
    
    final index = _deviceSessions.indexWhere(
      (s) => s.deviceId == _currentDeviceId && s.userId == _currentAccount!.userId,
    );
    
    if (index != -1) {
      _deviceSessions[index] = DeviceSession(
        id: _deviceSessions[index].id,
        deviceId: _deviceSessions[index].deviceId,
        userId: _deviceSessions[index].userId,
        deviceName: _deviceSessions[index].deviceName,
        deviceType: _deviceSessions[index].deviceType,
        os: _deviceSessions[index].os,
        osVersion: _deviceSessions[index].osVersion,
        lastActive: DateTime.now(),
        isCurrent: true,
        location: _deviceSessions[index].location,
      );
      await _saveDeviceSessions();
    }
  }

  /// Get current device ID.
  String? get currentDeviceId => _currentDeviceId;

  /// Clear all data (for logout).
  Future<void> clearAll() async {
    _accounts.clear();
    _currentAccount = null;
    _deviceSessions.clear();
    await _prefs.remove(_accountsKey);
    await _prefs.remove(_currentAccountIdKey);
    await _prefs.remove(_deviceSessionsKey);
    // Keep device ID for future logins
  }
}

// ==================== Data Models ====================

/// Represents a user account with full profile data.
class Account {
  final String userId;
  final String token;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final DateTime? lastLogin;
  // Full profile data
  final String? name;
  final String? surname;
  final String? email;
  final String? phone;
  final String? localAvatarPath;

  Account({
    required this.userId,
    required this.token,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.lastLogin,
    this.name,
    this.surname,
    this.email,
    this.phone,
    this.localAvatarPath,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'token': token,
      'username': username,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'lastLogin': lastLogin?.toIso8601String(),
      'name': name,
      'surname': surname,
      'email': email,
      'phone': phone,
      'localAvatarPath': localAvatarPath,
    };
  }

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      userId: json['userId'] as String,
      token: json['token'] as String,
      username: json['username'] as String?,
      displayName: json['displayName'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      lastLogin: json['lastLogin'] != null
          ? DateTime.parse(json['lastLogin'] as String)
          : null,
      name: json['name'] as String?,
      surname: json['surname'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      localAvatarPath: json['localAvatarPath'] as String?,
    );
  }

  Account copyWith({
    String? userId,
    String? token,
    String? username,
    String? displayName,
    String? avatarUrl,
    DateTime? lastLogin,
    String? name,
    String? surname,
    String? email,
    String? phone,
    String? localAvatarPath,
  }) {
    return Account(
      userId: userId ?? this.userId,
      token: token ?? this.token,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastLogin: lastLogin ?? this.lastLogin,
      name: name ?? this.name,
      surname: surname ?? this.surname,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      localAvatarPath: localAvatarPath ?? this.localAvatarPath,
    );
  }
}

/// Device type enumeration.
enum DeviceType {
  android,
  ios,
  web,
  windows,
  macos,
  linux,
  unknown,
}

/// Device information.
class DeviceInfo {
  final String deviceName;
  final DeviceType deviceType;
  final String os;
  final String osVersion;

  DeviceInfo({
    required this.deviceName,
    required this.deviceType,
    required this.os,
    required this.osVersion,
  });
}

/// Represents a device session.
class DeviceSession {
  final String id;
  final String deviceId;
  final String userId;
  final String deviceName;
  final DeviceType deviceType;
  final String os;
  final String osVersion;
  final DateTime lastActive;
  final bool isCurrent;
  final String? location;
  final String? ipAddress;
  final String? city;
  final String? country;
  final String? countryCode;
  final String? appVersion;

  DeviceSession({
    required this.id,
    required this.deviceId,
    required this.userId,
    required this.deviceName,
    required this.deviceType,
    required this.os,
    required this.osVersion,
    required this.lastActive,
    required this.isCurrent,
    this.location,
    this.ipAddress,
    this.city,
    this.country,
    this.countryCode,
    this.appVersion,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceId': deviceId,
      'userId': userId,
      'deviceName': deviceName,
      'deviceType': deviceType.index,
      'os': os,
      'osVersion': osVersion,
      'lastActive': lastActive.toIso8601String(),
      'isCurrent': isCurrent,
      'location': location,
      'ipAddress': ipAddress,
      'city': city,
      'country': country,
      'countryCode': countryCode,
      'appVersion': appVersion,
    };
  }

  factory DeviceSession.fromJson(Map<String, dynamic> json) {
    return DeviceSession(
      id: json['id'] as String,
      deviceId: json['deviceId'] as String,
      userId: json['userId'] as String,
      deviceName: json['deviceName'] as String,
      deviceType: DeviceType.values[json['deviceType'] as int],
      os: json['os'] as String,
      osVersion: json['osVersion'] as String,
      lastActive: DateTime.parse(json['lastActive'] as String),
      isCurrent: json['isCurrent'] as bool,
      location: json['location'] as String?,
      ipAddress: json['ipAddress'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String?,
      countryCode: json['countryCode'] as String?,
      appVersion: json['appVersion'] as String?,
    );
  }

  DeviceSession copyWith({
    String? id,
    String? deviceId,
    String? userId,
    String? deviceName,
    DeviceType? deviceType,
    String? os,
    String? osVersion,
    DateTime? lastActive,
    bool? isCurrent,
    String? location,
    String? ipAddress,
    String? city,
    String? country,
    String? countryCode,
    String? appVersion,
  }) {
    return DeviceSession(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
      deviceName: deviceName ?? this.deviceName,
      deviceType: deviceType ?? this.deviceType,
      os: os ?? this.os,
      osVersion: osVersion ?? this.osVersion,
      lastActive: lastActive ?? this.lastActive,
      isCurrent: isCurrent ?? this.isCurrent,
      location: location ?? this.location,
      ipAddress: ipAddress ?? this.ipAddress,
      city: city ?? this.city,
      country: country ?? this.country,
      countryCode: countryCode ?? this.countryCode,
      appVersion: appVersion ?? this.appVersion,
    );
  }

  /// Get icon for device type.
  String get deviceIcon {
    switch (deviceType) {
      case DeviceType.android:
        return '📱';
      case DeviceType.ios:
        return '📱';
      case DeviceType.web:
        return '🌐';
      case DeviceType.windows:
        return '💻';
      case DeviceType.macos:
        return '💻';
      case DeviceType.linux:
        return '💻';
      case DeviceType.unknown:
        return '❓';
    }
  }
}
