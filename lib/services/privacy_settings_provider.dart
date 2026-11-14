import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'settings_service.dart';
import 'auth_service.dart';
import '../config/app_config.dart';

/// Provider для управления настройками приватности и безопасности.
/// Синхронизируется с сервером через REST API.
class PrivacySettingsProvider extends ChangeNotifier {
  PrivacySettings _privacy = const PrivacySettings();
  List<PrivacyException> _exceptions = [];
  TwoFactorAuthSettings _twoFactor = const TwoFactorAuthSettings();
  AppLockSettings _appLock = const AppLockSettings();
  List<BlockedUser> _blockedUsers = [];
  bool _isLoading = false;
  String? _error;

  PrivacySettings get privacy => _privacy;
  List<PrivacyException> get exceptions => _exceptions;
  TwoFactorAuthSettings get twoFactor => _twoFactor;
  AppLockSettings get appLock => _appLock;
  List<BlockedUser> get blockedUsers => _blockedUsers;
  bool get isLoading => _isLoading;
  String? get error => _error;

  final Dio _dio = Dio();

  Future<Map<String, String>> _h() async {
    final token = await AuthService.getToken();
    return {'Authorization': 'Bearer ${token ?? ""}'};
  }

  /// Загрузить все настройки приватности с сервера
  Future<void> loadPrivacySettings() async {
    _isLoading = true; _error = null; notifyListeners();
    try {
      final r = await _dio.get('${AppConfig.baseUrl}/api/settings/privacy',
          options: Options(headers: await _h()));
      _privacy = PrivacySettings.fromJson(r.data);
      _error = null;
    } catch (e) {
      _error = 'Failed to load privacy settings: $e';
      debugPrint('PrivacySettingsProvider: $_error');
    } finally { _isLoading = false; notifyListeners(); }
  }

  /// Сохранить настройки приватности на сервер
  Future<bool> savePrivacySettings(PrivacySettings settings) async {
    try {
      await _dio.put('${AppConfig.baseUrl}/api/settings/privacy',
          data: settings.toJson(), options: Options(headers: await _h()));
      _privacy = settings; notifyListeners(); return true;
    } catch (e) {
      _error = 'Failed to save privacy settings: $e'; return false;
    }
  }

  /// Обновить одно поле приватности
  Future<bool> updatePrivacyField(String field, dynamic value) async {
    final updated = _copyWithField(field, value);
    return savePrivacySettings(updated);
  }

  PrivacySettings _copyWithField(String field, dynamic value) {
    switch (field) {
      case 'last_seen_visibility': return _privacy.copyWith(lastSeenVisibility: value as PrivacyVisibility);
      case 'profile_photo_visibility': return _privacy.copyWith(profilePhotoVisibility: value as PrivacyVisibility);
      case 'phone_number_visibility': return _privacy.copyWith(phoneNumberVisibility: value as PrivacyVisibility);
      case 'phone_call_privacy': return _privacy.copyWith(phoneCallPrivacy: value as PrivacyVisibility);
      case 'call_privacy': return _privacy.copyWith(callPrivacy: value as PrivacyVisibility);
      case 'groups_channels_privacy': return _privacy.copyWith(groupsChannelsPrivacy: value as PrivacyVisibility);
      case 'bio_visibility': return _privacy.copyWith(bioVisibility: value as PrivacyVisibility);
      case 'birthday_visibility': return _privacy.copyWith(birthdayVisibility: value as PrivacyVisibility);
      case 'forwarded_messages': return _privacy.copyWith(forwardedMessages: value as PrivacyVisibility);
      case 'show_online_status': return _privacy.copyWith(showOnlineStatus: value as bool);
      case 'show_read_receipts': return _privacy.copyWith(showReadReceipts: value as bool);
      default: return _privacy;
    }
  }

  /// Загрузить исключения для конкретного правила
  Future<List<PrivacyException>> loadExceptions(String ruleType) async {
    try {
      final r = await _dio.get('${AppConfig.baseUrl}/api/settings/privacy/exceptions/$ruleType',
          options: Options(headers: await _h()));
      final list = (r.data as List).map((e) => PrivacyException.fromJson(e)).toList();
      _exceptions = list; notifyListeners(); return list;
    } catch (e) { debugPrint('PrivacySettingsProvider: loadExceptions: $e'); return []; }
  }

  /// Добавить исключение
  Future<bool> addException(String ruleType, String targetUserId, String exceptionType) async {
    try {
      await _dio.post('${AppConfig.baseUrl}/api/settings/privacy/exceptions',
          data: {'rule_type': ruleType, 'target_user_id': targetUserId, 'exception_type': exceptionType},
          options: Options(headers: await _h()));
      await loadExceptions(ruleType); return true;
    } catch (e) { debugPrint('PrivacySettingsProvider: addException: $e'); return false; }
  }

  /// Удалить исключение
  Future<bool> removeException(String exceptionId, String ruleType) async {
    try {
      await _dio.delete('${AppConfig.baseUrl}/api/settings/privacy/exceptions/$exceptionId',
          options: Options(headers: await _h()));
      await loadExceptions(ruleType); return true;
    } catch (e) { debugPrint('PrivacySettingsProvider: removeException: $e'); return false; }
  }

  /// Загрузить настройки 2FA
  Future<void> load2FA() async {
    try {
      final r = await _dio.get('${AppConfig.baseUrl}/api/security/2fa',
          options: Options(headers: await _h()));
      _twoFactor = TwoFactorAuthSettings.fromJson(r.data); notifyListeners();
    } catch (e) { debugPrint('PrivacySettingsProvider: load2FA: $e'); }
  }

  /// Включить или сменить пароль 2FA
  Future<Map<String, dynamic>> enable2FA(
    String password,
    String recoveryEmail, {
    String? currentPassword,
    String? current2faPassword,
  }) async {
    try {
      final body = <String, dynamic>{
        'password': password,
        'recovery_email': recoveryEmail,
        if (currentPassword != null && currentPassword.isNotEmpty)
          'current_password': currentPassword,
        if (current2faPassword != null && current2faPassword.isNotEmpty)
          'current_2fa_password': current2faPassword,
      };
      final r = await _dio.post(
        '${AppConfig.baseUrl}/api/security/2fa/enable',
        data: body,
        options: Options(headers: await _h()),
      );
      await load2FA();
      final data = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
      final codes = (data['recovery_codes'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          <String>[];
      return {
        'success': true,
        'recovery_codes': codes,
      };
    } on DioException catch (e) {
      final data = e.response?.data;
      final error = data is Map ? (data['error']?.toString() ?? 'unknown') : 'network_error';
      debugPrint('PrivacySettingsProvider: enable2FA: $error ($e)');
      return {'success': false, 'error': error, 'recovery_codes': <String>[]};
    } catch (e) {
      debugPrint('PrivacySettingsProvider: enable2FA: $e');
      return {'success': false, 'error': 'unknown', 'recovery_codes': <String>[]};
    }
  }

  /// Отключить 2FA
  Future<Map<String, dynamic>> disable2FA({String? password}) async {
    try {
      await _dio.post(
        '${AppConfig.baseUrl}/api/security/2fa/disable',
        data: {
          if (password != null && password.isNotEmpty) 'password': password,
        },
        options: Options(headers: await _h()),
      );
      await load2FA();
      return {'success': true};
    } on DioException catch (e) {
      final data = e.response?.data;
      final error = data is Map ? (data['error']?.toString() ?? 'unknown') : 'network_error';
      debugPrint('PrivacySettingsProvider: disable2FA: $error ($e)');
      return {'success': false, 'error': error};
    } catch (e) {
      debugPrint('PrivacySettingsProvider: disable2FA: $e');
      return {'success': false, 'error': 'unknown'};
    }
  }

  /// Перевыпустить резервные коды 2FA
  Future<Map<String, dynamic>> regenerateRecoveryCodes(String password) async {
    try {
      final r = await _dio.post(
        '${AppConfig.baseUrl}/api/security/2fa/recovery-codes/regenerate',
        data: {'password': password},
        options: Options(headers: await _h()),
      );
      await load2FA();
      final data = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
      final codes = (data['recovery_codes'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          <String>[];
      return {
        'success': true,
        'recovery_codes': codes,
      };
    } on DioException catch (e) {
      final data = e.response?.data;
      final error = data is Map ? (data['error']?.toString() ?? 'unknown') : 'network_error';
      debugPrint('PrivacySettingsProvider: regenerateRecoveryCodes: $error ($e)');
      return {'success': false, 'error': error, 'recovery_codes': <String>[]};
    } catch (e) {
      debugPrint('PrivacySettingsProvider: regenerateRecoveryCodes: $e');
      return {'success': false, 'error': 'unknown', 'recovery_codes': <String>[]};
    }
  }

  /// Загрузить настройки блокировки приложения
  Future<void> loadAppLock() async {
    try {
      final r = await _dio.get('${AppConfig.baseUrl}/api/security/app-lock',
          options: Options(headers: await _h()));
      _appLock = AppLockSettings.fromJson(r.data); notifyListeners();
    } catch (e) { debugPrint('PrivacySettingsProvider: loadAppLock: $e'); }
  }

  /// Сохранить настройки блокировки приложения
  Future<bool> saveAppLock(AppLockSettings settings) async {
    try {
      await _dio.put('${AppConfig.baseUrl}/api/security/app-lock',
          data: settings.toJson(), options: Options(headers: await _h()));
      _appLock = settings; notifyListeners(); return true;
    } catch (e) { debugPrint('PrivacySettingsProvider: saveAppLock: $e'); return false; }
  }

  /// Загрузить список заблокированных пользователей
  Future<void> loadBlockedUsers() async {
    try {
      final r = await _dio.get('${AppConfig.baseUrl}/api/security/blocked',
          options: Options(headers: await _h()));
      _blockedUsers = (r.data as List).map((e) => BlockedUser.fromJson(e)).toList();
      notifyListeners();
    } catch (e) { debugPrint('PrivacySettingsProvider: loadBlockedUsers: $e'); }
  }

  /// Заблокировать пользователя
  Future<bool> blockUser(String userId) async {
    try {
      await _dio.post('${AppConfig.baseUrl}/api/security/blocked',
          data: {'blocked_user_id': userId}, options: Options(headers: await _h()));
      await loadBlockedUsers(); return true;
    } catch (e) { debugPrint('PrivacySettingsProvider: blockUser: $e'); return false; }
  }

  /// Разблокировать пользователя
  Future<bool> unblockUser(String userId) async {
    try {
      await _dio.delete('${AppConfig.baseUrl}/api/security/blocked/$userId',
          options: Options(headers: await _h()));
      await loadBlockedUsers(); return true;
    } catch (e) { debugPrint('PrivacySettingsProvider: unblockUser: $e'); return false; }
  }

  int _accountTTLMonths = 6;
  int get accountTTLMonths => _accountTTLMonths;

  /// Загрузить настройку авто-удаления аккаунта
  Future<void> loadAccountTTL() async {
    try {
      final r = await _dio.get('${AppConfig.baseUrl}/api/security/account-ttl',
          options: Options(headers: await _h()));
      if (r.data != null && r.data['ttl_months'] != null) {
        _accountTTLMonths = r.data['ttl_months'] as int;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('PrivacySettingsProvider: loadAccountTTL: $e');
    }
  }

  /// Сохранить настройку авто-удаления аккаунта
  Future<bool> saveAccountTTL(int months) async {
    try {
      await _dio.put('${AppConfig.baseUrl}/api/security/account-ttl',
          data: {'ttl_months': months}, options: Options(headers: await _h()));
      _accountTTLMonths = months;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('PrivacySettingsProvider: saveAccountTTL: $e');
      return false;
    }
  }

  /// Загрузить все данные разом
  Future<void> loadAll() async {
    await Future.wait([loadPrivacySettings(), load2FA(), loadAppLock(), loadBlockedUsers(), loadAccountTTL()]);
  }

  /// Сбросить кэш в памяти и перезагрузить данные при смене аккаунта
  Future<void> reloadForUser() async {
    _privacy = const PrivacySettings();
    _exceptions = [];
    _twoFactor = const TwoFactorAuthSettings();
    _appLock = const AppLockSettings();
    _blockedUsers = [];
    _accountTTLMonths = 6;
    _error = null;
    notifyListeners();
    await loadAll();
  }
}
