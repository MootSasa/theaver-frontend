import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'account_manager.dart';
import 'auth_service.dart';
import 'update_platform_stub.dart'
    if (dart.library.io) 'update_platform_io.dart'
    if (dart.library.js_interop) 'update_platform_web.dart';
import 'update_platform_types.dart';

export 'update_platform_types.dart' show UpdateInstallResult, UpdateInstallStatus;

/// Модель данных о доступном обновлении
class AppUpdateInfo {
  final bool hasUpdate;
  final String latestVersion;
  final int latestBuild;
  final int minSupportedBuild;
  final bool forceUpdate;
  final String downloadUrl;
  final int apkSizeBytes;
  final String sha256;
  final String releaseNotes;
  final String architecture;
  final String channel;

  const AppUpdateInfo({
    required this.hasUpdate,
    required this.latestVersion,
    required this.latestBuild,
    required this.minSupportedBuild,
    required this.forceUpdate,
    required this.downloadUrl,
    required this.apkSizeBytes,
    required this.sha256,
    required this.releaseNotes,
    this.architecture = 'universal',
    this.channel = 'stable',
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final hasUpdateRaw = json['has_update'] as bool? ?? false;
    final forceUpdateRaw = json['force_update'] as bool? ?? false;
    final rawDownloadUrl = json['download_url'] as String? ?? '';
    final resolvedDownloadUrl = AppConfig.resolveMediaUrl(rawDownloadUrl) ?? rawDownloadUrl;
    return AppUpdateInfo(
      hasUpdate: hasUpdateRaw || forceUpdateRaw,
      latestVersion: json['latest_version'] as String? ?? '',
      latestBuild: (json['latest_build'] as num?)?.toInt() ?? 0,
      minSupportedBuild: (json['min_supported_build'] as num?)?.toInt() ?? 1,
      forceUpdate: forceUpdateRaw,
      downloadUrl: resolvedDownloadUrl,
      apkSizeBytes: (json['apk_size_bytes'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String? ?? '',
      releaseNotes: json['release_notes'] as String? ?? '',
      architecture: json['architecture'] as String? ?? 'universal',
      channel: json['channel'] as String? ?? 'stable',
    );
  }

  factory AppUpdateInfo.noUpdate() {
    return const AppUpdateInfo(
      hasUpdate: false,
      latestVersion: '',
      latestBuild: 0,
      minSupportedBuild: 1,
      forceUpdate: false,
      downloadUrl: '',
      apkSizeBytes: 0,
      sha256: '',
      releaseNotes: '',
      architecture: 'universal',
      channel: 'stable',
    );
  }

  String get formattedSize {
    if (apkSizeBytes <= 0) return '';
    final mb = apkSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => {
        'has_update': hasUpdate,
        'latest_version': latestVersion,
        'latest_build': latestBuild,
        'min_supported_build': minSupportedBuild,
        'force_update': forceUpdate,
        'download_url': downloadUrl,
        'apk_size_bytes': apkSizeBytes,
        'sha256': sha256,
        'release_notes': releaseNotes,
        'architecture': architecture,
        'channel': channel,
      };
}

enum AppUpdateStatus {
  idle,
  checking,
  available,
  downloading,
  readyToInstall,
  installing,
  upToDate,
  error,
}

class AppUpdateDownloadState {
  final AppUpdateStatus status;
  final AppUpdateInfo? availableUpdate;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final double speedBytesPerSec;
  final String? downloadedFilePath;
  final String? errorMessage;
  final DateTime? lastCheckedAt;

  const AppUpdateDownloadState({
    this.status = AppUpdateStatus.idle,
    this.availableUpdate,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0.0,
    this.downloadedFilePath,
    this.errorMessage,
    this.lastCheckedAt,
  });

  bool get hasAvailableUpdate =>
      availableUpdate != null && availableUpdate!.hasUpdate;

  AppUpdateDownloadState copyWith({
    AppUpdateStatus? status,
    AppUpdateInfo? availableUpdate,
    bool clearUpdate = false,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    double? speedBytesPerSec,
    String? downloadedFilePath,
    bool clearFile = false,
    String? errorMessage,
    bool clearError = false,
    DateTime? lastCheckedAt,
  }) {
    return AppUpdateDownloadState(
      status: status ?? this.status,
      availableUpdate: clearUpdate ? null : (availableUpdate ?? this.availableUpdate),
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      downloadedFilePath:
          clearFile ? null : (downloadedFilePath ?? this.downloadedFilePath),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}

/// Сервис проверки, фоновой загрузки и установки обновлений Theaver.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const String prefAutoCheckKey = 'auto_check_updates';
  static const String prefIgnoredBuildKey = 'ignored_update_build';
  static const String prefNotifiedBuildKey = 'notified_update_build';
  static const String prefNotifiedTimestampKey = 'notified_update_timestamp_ms';
  static const String prefChannelKey = 'update_channel';
  static const String prefLastCheckedMsKey = 'update_last_checked_ms';
  static const String prefCachedUpdateJsonKey = 'update_cached_info_json';
  static const String prefSnoozedUntilMsKey = 'update_snoozed_until_ms';
  static const String prefSnoozedBuildKey = 'update_snoozed_build';

  final ValueNotifier<AppUpdateDownloadState> stateNotifier =
      ValueNotifier<AppUpdateDownloadState>(const AppUpdateDownloadState());

  final UpdatePlatformAdapter _platform = createUpdatePlatformAdapter();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 10),
    ),
  );

  CancelToken? _activeCancelToken;
  bool _initialized = false;

  @visibleForTesting
  void resetForTesting() {
    _activeCancelToken?.cancel();
    _activeCancelToken = null;
    _initialized = false;
    stateNotifier.value = const AppUpdateDownloadState();
  }

  /// Инициализация состояния обновлений из SharedPreferences + синк настроек с сервером.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(prefLastCheckedMsKey);
      final lastChecked = lastMs != null && lastMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastMs)
          : null;

      AppUpdateInfo? cachedUpdate;
      String? readyPath;
      final cachedRaw = prefs.getString(prefCachedUpdateJsonKey);
      if (cachedRaw != null && cachedRaw.isNotEmpty) {
        try {
          final map = jsonDecode(cachedRaw) as Map<String, dynamic>;
          final parsed = AppUpdateInfo.fromJson(map);
          final currentBuild = await getCurrentBuildNumber();
          if (parsed.hasUpdate && parsed.latestBuild > currentBuild) {
            cachedUpdate = parsed;
            if (!kIsWeb && parsed.downloadUrl.isNotEmpty) {
              final candidatePath = await _platform.resolveUpdateSavePath(
                parsed.downloadUrl,
                parsed.latestBuild,
              );
              if (candidatePath != null &&
                  await _platform.fileExistsAndMatchesSha256(
                    candidatePath,
                    parsed.sha256,
                  )) {
                readyPath = candidatePath;
              }
            }
          }
        } catch (_) {}
      }

      stateNotifier.value = stateNotifier.value.copyWith(
        status: readyPath != null
            ? AppUpdateStatus.readyToInstall
            : (cachedUpdate != null ? AppUpdateStatus.available : AppUpdateStatus.idle),
        availableUpdate: cachedUpdate,
        downloadedFilePath: readyPath,
        progress: readyPath != null ? 1.0 : 0.0,
        lastCheckedAt: lastChecked,
      );
    } catch (e) {
      debugPrint('[AppUpdateService] init error: $e');
    }

    unawaited(syncUpdatePreferencesWithServer());
  }

  Future<bool> isAutoCheckEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(prefAutoCheckKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setAutoCheckEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefAutoCheckKey, enabled);
    } catch (e) {
      debugPrint('[AppUpdateService] Error saving auto check: $e');
    }
    unawaited(syncUpdatePreferencesWithServer());
  }

  /// Получить выбранный канал обновлений ('stable', 'beta', 'alpha')
  Future<String> getChannel() async {
    final domainChannel = AppConfig.webDomainChannel;
    if (domainChannel != null && domainChannel.isNotEmpty) {
      return domainChannel;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(prefChannelKey);
      if (saved != null && saved.isNotEmpty) {
        return saved;
      }
      final currentVer = AppConfig.currentVersion.toLowerCase();
      if (currentVer.contains('alpha') || currentVer.contains('dev')) {
        return 'alpha';
      }
      if (currentVer.contains('beta') || currentVer.contains('rc')) {
        return 'beta';
      }
      return 'stable';
    } catch (_) {
      return 'stable';
    }
  }

  Future<void> setChannel(String channel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefChannelKey, channel);
    } catch (e) {
      debugPrint('[AppUpdateService] Error saving update channel: $e');
    }
    unawaited(syncUpdatePreferencesWithServer());
  }

  /// Текущий номер сборки приложения (с нормализацией ABI-префиксов на Android)
  Future<int> getCurrentBuildNumber() async {
    if (AppConfig.hasEnvBuildNumber && AppConfig.appBuildNumber > 0) {
      return AppConfig.appBuildNumber;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final rawBuild = int.tryParse(info.buildNumber);
      if (rawBuild != null && rawBuild > 0) {
        return getPlatform() == 'android'
            ? AppConfig.normalizeAndroidBuildNumber(rawBuild, version: info.version)
            : rawBuild;
      }
    } catch (_) {}
    return AppConfig.currentBuildNumber;
  }

  /// Текущая версия приложения (например, 1.19.0-beta.401)
  Future<String> getCurrentVersion() async {
    if (AppConfig.hasEnvAppVersion && AppConfig.appVersion.isNotEmpty) {
      return AppConfig.appVersion;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        return info.version;
      }
    } catch (_) {}
    return AppConfig.currentVersion;
  }

  String getPlatform() => kIsWeb ? 'web' : _platform.platformName;

  Future<String> getArchitecture() =>
      kIsWeb ? Future.value('universal') : _platform.detectArchitecture();

  Future<String> getDeviceArchitecture() => getArchitecture();

  /// Синхронизирует текущую версию, архитектуру, канал и флаг автопроверки с сервером
  /// (работает и на Desktop/Web без push-токена).
  Future<void> syncUpdatePreferencesWithServer() async {
    try {
      final authToken = await AuthService.getToken();
      if (authToken == null || authToken.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final deviceId = AccountManager().currentDeviceId ??
          prefs.getString('current_device_id') ??
          prefs.getString('device_id') ??
          '';
      if (deviceId.isEmpty) return;

      final platform = getPlatform();
      final arch = await getArchitecture();
      final appVersion = await getCurrentVersion();
      final appBuild = await getCurrentBuildNumber();
      final channel = await getChannel();
      final autoCheck = await isAutoCheckEnabled();

      await _dio.put(
        '${AppConfig.baseUrl}/api/notifications/update-settings',
        data: <String, dynamic>{
          'device_id': deviceId,
          'platform': platform,
          'app_version': appVersion,
          'app_build': appBuild,
          'architecture': arch,
          'update_channel': channel,
          'auto_check_updates': autoCheck,
        },
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $authToken',
            'Content-Type': 'application/json',
          },
        ),
      );
    } catch (_) {
      // Best effort: server might be unreachable or an older version without this route
    }
  }

  /// Запросить информацию о наличии обновления на сервере
  Future<AppUpdateInfo> checkForUpdate({bool silent = false, String? channel}) async {
    final wasDownloading =
        stateNotifier.value.status == AppUpdateStatus.downloading;
    if (!silent && !wasDownloading) {
      stateNotifier.value = stateNotifier.value.copyWith(
        status: AppUpdateStatus.checking,
        clearError: true,
      );
    }

    try {
      final platform = getPlatform();
      final arch = await getArchitecture();
      final currentBuild = await getCurrentBuildNumber();
      final currentVer = await getCurrentVersion();
      final ch = channel ?? await getChannel();

      if (kIsWeb) {
        final beforeBuild = AppConfig.currentBuildNumber;
        await AppConfig.syncWebVersionFromServer(channel: ch);
        final now = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(prefLastCheckedMsKey, now.millisecondsSinceEpoch);

        final baseUrl = AppConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
        final response = await _dio.get(
          '$baseUrl/api/app/check-update',
          queryParameters: {
            'platform': 'web',
            'arch': 'universal',
            'channel': ch,
            'build_number': beforeBuild,
            'version': currentVer,
          },
        );
        if (response.statusCode == 200 && response.data != null) {
          final map = response.data is Map<String, dynamic>
              ? response.data as Map<String, dynamic>
              : Map<String, dynamic>.from(response.data as Map);
          final info = AppUpdateInfo.fromJson(map);
          if (info.hasUpdate) {
            await prefs.setString(prefCachedUpdateJsonKey, jsonEncode(info.toJson()));
            stateNotifier.value = stateNotifier.value.copyWith(
              status: AppUpdateStatus.available,
              availableUpdate: info,
              lastCheckedAt: now,
              clearError: true,
            );
            return info;
          }
        }
        stateNotifier.value = stateNotifier.value.copyWith(
          status: AppUpdateStatus.upToDate,
          clearUpdate: true,
          lastCheckedAt: now,
          clearError: true,
        );
        return AppUpdateInfo.noUpdate();
      }

      final baseUrl = AppConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
      final response = await _dio.get(
        '$baseUrl/api/app/check-update',
        queryParameters: {
          'platform': platform,
          'arch': arch,
          'channel': ch,
          'build_number': currentBuild,
          'version': currentVer,
        },
      );

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefLastCheckedMsKey, now.millisecondsSinceEpoch);

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : Map<String, dynamic>.from(response.data as Map);

        final updateInfo = AppUpdateInfo.fromJson(data);

        if (updateInfo.hasUpdate) {
          await prefs.setString(prefCachedUpdateJsonKey, jsonEncode(updateInfo.toJson()));

          String? readyPath;
          if (updateInfo.downloadUrl.isNotEmpty) {
            final candidate = await _platform.resolveUpdateSavePath(
              updateInfo.downloadUrl,
              updateInfo.latestBuild,
            );
            if (candidate != null &&
                await _platform.fileExistsAndMatchesSha256(
                  candidate,
                  updateInfo.sha256,
                )) {
              readyPath = candidate;
            }
          }

          if (!wasDownloading) {
            stateNotifier.value = stateNotifier.value.copyWith(
              status: readyPath != null
                  ? AppUpdateStatus.readyToInstall
                  : AppUpdateStatus.available,
              availableUpdate: updateInfo,
              downloadedFilePath: readyPath,
              clearFile: readyPath == null,
              progress: readyPath != null ? 1.0 : 0.0,
              lastCheckedAt: now,
              clearError: true,
            );
          }

          if (silent && !await shouldPromptInApp(updateInfo)) {
            return updateInfo;
          }
          return updateInfo;
        }

        await prefs.remove(prefCachedUpdateJsonKey);
        if (!wasDownloading) {
          stateNotifier.value = stateNotifier.value.copyWith(
            status: AppUpdateStatus.upToDate,
            clearUpdate: true,
            clearFile: true,
            progress: 0.0,
            lastCheckedAt: now,
            clearError: true,
          );
        }
        return AppUpdateInfo.noUpdate();
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Check for update failed: $e');
      if (!wasDownloading) {
        stateNotifier.value = stateNotifier.value.copyWith(
          status: AppUpdateStatus.error,
          errorMessage: e.toString(),
        );
      }
    }

    return AppUpdateInfo.noUpdate();
  }

  /// Отложить напоминание об обновлении (кнопка «Напомнить позже», 24 часа).
  Future<void> snoozeUpdate(
    int buildNumber, {
    Duration duration = const Duration(hours: 24),
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final untilMs = DateTime.now().add(duration).millisecondsSinceEpoch;
      await prefs.setInt(prefSnoozedBuildKey, buildNumber);
      await prefs.setInt(prefSnoozedUntilMsKey, untilMs);
    } catch (_) {}
  }

  /// Навсегда пропустить конкретную сборку (кнопка «Пропустить сборку»).
  Future<void> ignoreBuild(int buildNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefIgnoredBuildKey, buildNumber);
    } catch (_) {}
  }

  /// Нужно ли автоматически показывать диалог обновления в приложении.
  Future<bool> shouldPromptInApp(AppUpdateInfo update) async {
    if (!update.hasUpdate) return false;
    if (update.forceUpdate) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ignoredBuild = prefs.getInt(prefIgnoredBuildKey) ?? 0;
      if (ignoredBuild >= update.latestBuild) return false;

      final snoozedBuild = prefs.getInt(prefSnoozedBuildKey) ?? 0;
      final snoozedUntilMs = prefs.getInt(prefSnoozedUntilMsKey) ?? 0;
      if (snoozedBuild == update.latestBuild &&
          DateTime.now().millisecondsSinceEpoch < snoozedUntilMs) {
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Нужно ли отправлять системное уведомление на устройство об этой сборке.
  Future<bool> shouldNotifyDevice(AppUpdateInfo update) async {
    if (!update.hasUpdate || update.latestBuild <= 0) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final notifiedBuild = prefs.getInt(prefNotifiedBuildKey) ?? 0;
      if (update.latestBuild > notifiedBuild) {
        return true;
      }
      if (update.forceUpdate) {
        final notifiedAtMs = prefs.getInt(prefNotifiedTimestampKey) ?? 0;
        final elapsedMs = DateTime.now().millisecondsSinceEpoch - notifiedAtMs;
        if (elapsedMs >= const Duration(hours: 12).inMilliseconds) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  Future<void> markDeviceNotified(int buildNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefNotifiedBuildKey, buildNumber);
      await prefs.setInt(
        prefNotifiedTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  /// Фоновая загрузка обновления в кэш с вычислением скорости и проверкой SHA-256.
  /// Продолжается даже после закрытия модального окна.
  Future<String?> downloadUpdate(AppUpdateInfo update) async {
    if (kIsWeb) {
      applyWebUpdate();
      return null;
    }
    if (update.downloadUrl.isEmpty) {
      stateNotifier.value = stateNotifier.value.copyWith(
        status: AppUpdateStatus.error,
        availableUpdate: update,
        errorMessage: 'Ссылка для скачивания отсутствует',
      );
      return null;
    }
    if (stateNotifier.value.status == AppUpdateStatus.downloading) {
      return null;
    }

    try {
      final savePath = await _platform.resolveUpdateSavePath(
        update.downloadUrl,
        update.latestBuild,
      );
      if (savePath == null) {
        throw Exception('Не удалось определить путь для сохранения файла');
      }

      if (await _platform.fileExistsAndMatchesSha256(savePath, update.sha256)) {
        stateNotifier.value = stateNotifier.value.copyWith(
          status: AppUpdateStatus.readyToInstall,
          availableUpdate: update,
          downloadedFilePath: savePath,
          progress: 1.0,
          downloadedBytes: update.apkSizeBytes,
          totalBytes: update.apkSizeBytes,
          speedBytesPerSec: 0.0,
          clearError: true,
        );
        return savePath;
      }

      await _platform.deleteFileIfExists(savePath);

      _activeCancelToken = CancelToken();
      final resolvedUrl =
          AppConfig.resolveMediaUrl(update.downloadUrl) ?? update.downloadUrl;

      stateNotifier.value = stateNotifier.value.copyWith(
        status: AppUpdateStatus.downloading,
        availableUpdate: update,
        progress: 0.0,
        downloadedBytes: 0,
        totalBytes: update.apkSizeBytes,
        speedBytesPerSec: 0.0,
        clearFile: true,
        clearError: true,
      );

      int lastSampleBytes = 0;
      DateTime lastSampleAt = DateTime.now();
      double currentSpeed = 0.0;

      await _dio.download(
        resolvedUrl,
        savePath,
        cancelToken: _activeCancelToken,
        deleteOnError: true,
        options: Options(followRedirects: true),
        onReceiveProgress: (received, total) {
          final now = DateTime.now();
          final elapsedMs = now.difference(lastSampleAt).inMilliseconds;
          if (elapsedMs >= 300) {
            final deltaBytes = received - lastSampleBytes;
            if (deltaBytes >= 0) {
              currentSpeed = (deltaBytes * 1000.0) / elapsedMs;
            }
            lastSampleAt = now;
            lastSampleBytes = received;
          } else if (received < total) {
            // Throttle UI rebuilds during rapid socket reads unless nearing end
            return;
          }
          final effectiveTotal = total > 0 ? total : update.apkSizeBytes;
          final pct = effectiveTotal > 0
              ? (received / effectiveTotal).clamp(0.0, 1.0)
              : 0.0;
          stateNotifier.value = stateNotifier.value.copyWith(
            status: AppUpdateStatus.downloading,
            availableUpdate: update,
            progress: pct,
            downloadedBytes: received,
            totalBytes: effectiveTotal,
            speedBytesPerSec: currentSpeed,
          );
        },
      );

      await _platform.verifyDownloadedFile(savePath, update.sha256);

      stateNotifier.value = stateNotifier.value.copyWith(
        status: AppUpdateStatus.readyToInstall,
        availableUpdate: update,
        downloadedFilePath: savePath,
        progress: 1.0,
        speedBytesPerSec: 0.0,
        clearError: true,
      );
      return savePath;
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        stateNotifier.value = stateNotifier.value.copyWith(
          status: AppUpdateStatus.available,
          availableUpdate: update,
          progress: 0.0,
          downloadedBytes: 0,
          speedBytesPerSec: 0.0,
          clearError: true,
        );
        return null;
      }
      debugPrint('[AppUpdateService] Update download failed: $e');
      stateNotifier.value = stateNotifier.value.copyWith(
        status: AppUpdateStatus.error,
        availableUpdate: update,
        speedBytesPerSec: 0.0,
        errorMessage: 'Ошибка загрузки: $e',
      );
      return null;
    } finally {
      _activeCancelToken = null;
    }
  }

  void cancelDownload() {
    _activeCancelToken?.cancel('Cancelled by user');
  }

  Future<UpdateInstallResult> downloadAndInstall(AppUpdateInfo update) async {
    final path = await downloadUpdate(update);
    if (path == null) {
      return UpdateInstallResult(
        UpdateInstallStatus.failed,
        stateNotifier.value.errorMessage ?? 'Загрузка отменена',
      );
    }
    return installApk(path);
  }

  Future<UpdateInstallResult> installApk(String filePath) async {
    if (kIsWeb) {
      applyWebUpdate();
      return const UpdateInstallResult(UpdateInstallStatus.reloadedWeb, 'Web reload');
    }
    stateNotifier.value = stateNotifier.value.copyWith(
      status: AppUpdateStatus.installing,
      clearError: true,
    );
    final res = await _platform.installDownloadedPackage(filePath);
    if (!res.isSuccess) {
      stateNotifier.value = stateNotifier.value.copyWith(
        status: AppUpdateStatus.readyToInstall,
        errorMessage: 'Не удалось запустить установщик: ${res.message}',
      );
    } else {
      stateNotifier.value = stateNotifier.value.copyWith(
        status: AppUpdateStatus.readyToInstall,
        clearError: true,
      );
    }
    return res;
  }

  void applyWebUpdate() {
    _platform.reloadWebPage();
  }
}
