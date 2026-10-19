import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

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
    return AppUpdateInfo(
      hasUpdate: hasUpdateRaw || forceUpdateRaw,
      latestVersion: json['latest_version'] as String? ?? '',
      latestBuild: (json['latest_build'] as num?)?.toInt() ?? 0,
      minSupportedBuild: (json['min_supported_build'] as num?)?.toInt() ?? 1,
      forceUpdate: forceUpdateRaw,
      downloadUrl: json['download_url'] as String? ?? '',
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
}

/// Сервис проверки, загрузки и запуска установки обновлений
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const String prefAutoCheckKey = 'auto_check_updates';
  static const String prefIgnoredBuildKey = 'ignored_update_build';
  static const String prefChannelKey = 'update_channel';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 10),
    ),
  );

  /// Включена ли авто-проверка обновлений
  Future<bool> isAutoCheckEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(prefAutoCheckKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Сохранить настройку авто-проверки
  Future<void> setAutoCheckEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefAutoCheckKey, enabled);
    } catch (e) {
      debugPrint('[AppUpdateService] Error saving auto check: $e');
    }
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
      // Default to 'beta' so users receive both beta and stable updates
      return 'beta';
    } catch (_) {
      return 'beta';
    }
  }

  /// Установить выбранный канал обновлений
  Future<void> setChannel(String channel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefChannelKey, channel);
    } catch (e) {
      debugPrint('[AppUpdateService] Error saving update channel: $e');
    }
  }

  /// Текущий номер сборки приложения
  Future<int> getCurrentBuildNumber() async {
    if (AppConfig.appBuildNumber > 1) {
      return AppConfig.appBuildNumber;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final rawBuild = int.tryParse(info.buildNumber) ?? AppConfig.currentBuildNumber;
      // Flutter --split-per-abi prefixes versionCode with 1000 / 2000 / 4000
      if (!kIsWeb && Platform.isAndroid && rawBuild >= 1000 && rawBuild < 10000) {
        return rawBuild % 1000;
      }
      return rawBuild;
    } catch (_) {
      return AppConfig.currentBuildNumber;
    }
  }

  /// Текущая версия приложения (например, 1.4.0-beta.270)
  Future<String> getCurrentVersion() async {
    if (AppConfig.appVersion != '1.0.0' && AppConfig.appVersion.isNotEmpty) {
      return AppConfig.appVersion;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version.isNotEmpty ? info.version : AppConfig.currentVersion;
    } catch (_) {
      return AppConfig.currentVersion;
    }
  }

  /// Текущая платформа для запроса обновлений
  String getPlatform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      if (Platform.isWindows) return 'windows';
      if (Platform.isMacOS) return 'macos';
      if (Platform.isLinux) return 'linux';
    } catch (_) {}
    return defaultTargetPlatform.name.toLowerCase();
  }

  /// Определение аппаратной архитектуры процессора устройства
  Future<String> getArchitecture() async {
    if (kIsWeb) return 'universal';

    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final abis = androidInfo.supportedAbis;
        if (abis.isNotEmpty) {
          final primary = abis.first.toLowerCase();
          if (primary.contains('arm64') || primary.contains('aarch64') || primary.contains('v8a')) {
            return 'arm64-v8a';
          } else if (primary.contains('armeabi-v7a') || primary.contains('armv7')) {
            return 'armeabi-v7a';
          } else if (primary.contains('x86_64') || primary.contains('amd64')) {
            return 'x86_64';
          } else if (primary.contains('x86')) {
            return 'x86';
          }
          return primary;
        }
      } else if (Platform.isWindows) {
        final archEnv = Platform.environment['PROCESSOR_ARCHITECTURE']?.toLowerCase() ?? '';
        final archW6432 = Platform.environment['PROCESSOR_ARCHITEW6432']?.toLowerCase() ?? '';
        String winArch = 'x64';
        if (archEnv.contains('arm64') || archW6432.contains('arm64')) {
          winArch = 'arm64';
        } else if (archEnv.contains('amd64') || archEnv.contains('x64') || archW6432.contains('amd64')) {
          winArch = 'x64';
        } else if (archEnv.contains('x86')) {
          winArch = 'x86';
        }
        try {
          final appDir = File(Platform.resolvedExecutable).parent.path;
          final hasUninstaller = File('$appDir\\unins000.exe').existsSync() ||
              File('$appDir\\unins001.exe').existsSync();
          if (hasUninstaller) {
            return '$winArch-installer';
          }
        } catch (_) {}
        return winArch;
      } else if (Platform.isMacOS) {
        final v = Platform.version.toLowerCase();
        if (v.contains('arm64') || v.contains('aarch64')) return 'arm64';
        if (v.contains('x64') || v.contains('x86_64')) return 'x86_64';
      } else if (Platform.isLinux) {
        final v = Platform.version.toLowerCase();
        if (v.contains('arm64') || v.contains('aarch64')) return 'arm64';
        if (v.contains('x64') || v.contains('x86_64') || v.contains('amd64')) return 'x86_64';
        if (v.contains('arm')) return 'armv7l';
      } else if (Platform.isIOS) {
        return 'arm64';
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Failed to detect architecture: $e');
    }

    // Fallback based on Platform.version
    try {
      final v = Platform.version.toLowerCase();
      if (v.contains('arm64') || v.contains('aarch64')) return 'arm64';
      if (v.contains('x64') || v.contains('x86_64') || v.contains('amd64')) return 'x86_64';
    } catch (_) {}

    return 'universal';
  }

  /// Запросить информацию о наличии обновления на сервере
  Future<AppUpdateInfo> checkForUpdate({bool silent = false, String? channel}) async {
    if (kIsWeb) return AppUpdateInfo.noUpdate();

    try {
      final platform = getPlatform();
      final arch = await getArchitecture();
      final currentBuild = await getCurrentBuildNumber();
      final currentVer = await getCurrentVersion();
      final ch = channel ?? await getChannel();

      final baseUrl = AppConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
      final url = '$baseUrl/api/app/check-update';

      final response = await _dio.get(
        url,
        queryParameters: {
          'platform': platform,
          'arch': arch,
          'channel': ch,
          'build_number': currentBuild,
          'version': currentVer,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : Map<String, dynamic>.from(response.data as Map);

        final updateInfo = AppUpdateInfo.fromJson(data);

        // Если это тихая проверка при запуске, проверяем не скрыл ли пользователь этот билд
        if (silent && !updateInfo.forceUpdate) {
          final prefs = await SharedPreferences.getInstance();
          final ignoredBuild = prefs.getInt(prefIgnoredBuildKey) ?? 0;
          if (ignoredBuild >= updateInfo.latestBuild) {
            return AppUpdateInfo.noUpdate();
          }
        }

        return updateInfo;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Check for update failed: $e');
    }

    return AppUpdateInfo.noUpdate();
  }

  /// Пропустить / игнорировать этот номер сборки при авто-проверках
  Future<void> ignoreBuild(int buildNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefIgnoredBuildKey, buildNumber);
    } catch (_) {}
  }

  /// Скачать файл обновления во временную директорию с проверкой SHA-256
  Future<File?> downloadApk({
    required String downloadUrl,
    required void Function(int received, int total) onProgress,
    String? expectedSha256,
    CancelToken? cancelToken,
  }) async {
    if (kIsWeb) return null;

    try {
      Directory targetDir;
      try {
        targetDir = await getTemporaryDirectory();
      } catch (_) {
        if (Platform.isAndroid) {
          final extDirs = await getExternalCacheDirectories();
          if (extDirs != null && extDirs.isNotEmpty) {
            targetDir = extDirs.first;
          } else {
            rethrow;
          }
        } else {
          rethrow;
        }
      }

      String fileName = 'theaver_update.apk';
      try {
        final uri = Uri.parse(downloadUrl);
        if (uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty) {
          fileName = uri.pathSegments.last;
        }
      } catch (_) {}

      final savePath = '${targetDir.path}/$fileName';
      final file = File(savePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      await _dio.download(
        downloadUrl,
        savePath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        deleteOnError: true,
        options: Options(
          followRedirects: true,
        ),
      );

      if (await file.exists()) {
        final length = await file.length();
        if (length <= 0) {
          await file.delete();
          throw Exception('Скачанный файл пуст');
        }

        if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
          final digest = await sha256.bind(file.openRead()).first;
          final actualHex = digest.toString().toLowerCase();
          final expectedHex = expectedSha256.trim().toLowerCase();
          if (actualHex != expectedHex) {
            await file.delete();
            throw Exception('Контрольная сумма SHA-256 не совпала (файл повреждён при загрузке)');
          }
        }

        return file;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Update download failed: $e');
      rethrow;
    }
    return null;
  }

  /// Запустить установщик пакета (Android APK или автообновление на Windows/Desktop)
  Future<OpenResult> installApk(String filePath) async {
    if (kIsWeb) {
      return OpenResult(type: ResultType.error, message: 'Not supported on Web');
    }

    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('app.theaver.messenger/installer');
        final res = await channel.invokeMethod<String>('installApk', {
          'filePath': filePath,
        });
        if (res == 'done' || res == 'settings_opened') {
          return OpenResult(type: ResultType.done, message: res ?? 'done');
        }
      } catch (e) {
        debugPrint('[AppUpdateService] Native installApk channel failed, falling back to OpenFile: $e');
      }
      return await OpenFile.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
    }

    final lowerPath = filePath.toLowerCase();

    // Windows Installer (.exe)
    if (Platform.isWindows && lowerPath.endsWith('.exe')) {
      try {
        final currentPid = pid;
        final exeFile = File(Platform.resolvedExecutable);
        final appDir = exeFile.parent.path;
        final exeName = exeFile.uri.pathSegments.last;
        final tempDir = await getTemporaryDirectory();
        final scriptFile = File('${tempDir.path}\\theaver_apply_installer.bat');
        final scriptContent = '''@echo off
chcp 65001 >nul
ping 127.0.0.1 -n 2 >nul
taskkill /F /PID $currentPid >nul 2>&1
ping 127.0.0.1 -n 2 >nul
"$filePath" /SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /DIR="$appDir"
if exist "$appDir\\$exeName" (
  start "" /D "$appDir" "$appDir\\$exeName"
)
del /F /Q "$filePath" >nul 2>&1
del "%~f0"
''';
        await scriptFile.writeAsString(scriptContent);
        await Process.start(
          'cmd.exe',
          ['/c', scriptFile.path],
          mode: ProcessStartMode.detached,
        );
        exit(0);
      } catch (e) {
        debugPrint('[AppUpdateService] Windows installer auto-update fallback: $e');
        return await OpenFile.open(filePath);
      }
    }

    // Windows Portable (.zip)
    if (Platform.isWindows && lowerPath.endsWith('.zip')) {
      try {
        final currentPid = pid;
        final bytes = await File(filePath).readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        final tempDir = await getTemporaryDirectory();
        final stagingDir = Directory('${tempDir.path}\\theaver_update_staging');
        if (await stagingDir.exists()) {
          await stagingDir.delete(recursive: true);
        }
        await stagingDir.create(recursive: true);

        for (final file in archive) {
          final filename = file.name.replaceAll('/', '\\');
          if (filename.isEmpty) continue;
          if (file.isFile) {
            final data = file.content as List<int>;
            final outFile = File('${stagingDir.path}\\$filename');
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(data);
          } else {
            await Directory('${stagingDir.path}\\$filename').create(recursive: true);
          }
        }

        // If the ZIP had a single root folder, unwrap it so its contents copy directly into appDir
        String sourceDir = stagingDir.path;
        final entries = await stagingDir.list().toList();
        if (entries.length == 1 && entries.first is Directory) {
          sourceDir = entries.first.path;
        }

        final exeFile = File(Platform.resolvedExecutable);
        final appDir = exeFile.parent.path;
        final exeName = exeFile.uri.pathSegments.last;
        final scriptFile = File('${tempDir.path}\\theaver_apply_update.bat');
        final scriptContent = '''@echo off
chcp 65001 >nul
ping 127.0.0.1 -n 2 >nul
taskkill /F /PID $currentPid >nul 2>&1
ping 127.0.0.1 -n 2 >nul
robocopy "$sourceDir" "$appDir" /E /IS /IT /IM /R:15 /W:1 /NFL /NDL /NJH /NJS /nc /ns /np >nul
if %ERRORLEVEL% GEQ 8 (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c robocopy \\"$sourceDir\\" \\"$appDir\\" /E /IS /IT /IM /R:10 /W:1' -Verb RunAs -Wait"
)
rmdir /S /Q "${stagingDir.path}" >nul 2>&1
del /F /Q "$filePath" >nul 2>&1
start "" /D "$appDir" "$appDir\\$exeName"
del "%~f0"
''';
        await scriptFile.writeAsString(scriptContent);
        await Process.start(
          'cmd.exe',
          ['/c', scriptFile.path],
          mode: ProcessStartMode.detached,
        );
        exit(0);
      } catch (e) {
        debugPrint('[AppUpdateService] Windows auto-update fallback: $e');
        return await OpenFile.open(filePath);
      }
    }

    // Linux (.tar.gz / .tgz)
    if (Platform.isLinux && (lowerPath.endsWith('.tar.gz') || lowerPath.endsWith('.tgz'))) {
      try {
        final currentPid = pid;
        final tempDir = await getTemporaryDirectory();
        final stagingDir = Directory('${tempDir.path}/theaver_update_staging');
        if (await stagingDir.exists()) {
          await stagingDir.delete(recursive: true);
        }
        await stagingDir.create(recursive: true);

        final tarResult = await Process.run('tar', ['-xzf', filePath, '-C', stagingDir.path]);
        if (tarResult.exitCode == 0) {
          final exeFile = File(Platform.resolvedExecutable);
          final appDir = exeFile.parent.path;
          final exeName = exeFile.uri.pathSegments.last;
          final scriptFile = File('${tempDir.path}/theaver_apply_update.sh');
          final scriptContent = '''#!/bin/sh
sleep 1
kill -9 $currentPid 2>/dev/null || true
sleep 1
cp -rf "${stagingDir.path}/." "$appDir/"
chmod +x "$appDir/$exeName"
rm -rf "${stagingDir.path}" "$filePath"
cd "$appDir" && "./$exeName" >/dev/null 2>&1 &
rm -f "\$0"
''';
          await scriptFile.writeAsString(scriptContent);
          await Process.run('chmod', ['+x', scriptFile.path]);
          await Process.start(
            '/bin/sh',
            [scriptFile.path],
            mode: ProcessStartMode.detached,
          );
          exit(0);
        }
      } catch (e) {
        debugPrint('[AppUpdateService] Linux auto-update fallback: $e');
      }
    }

    // macOS (.zip)
    if (Platform.isMacOS && lowerPath.endsWith('.zip')) {
      try {
        final currentPid = pid;
        final tempDir = await getTemporaryDirectory();
        final stagingDir = Directory('${tempDir.path}/theaver_update_staging');
        if (await stagingDir.exists()) {
          await stagingDir.delete(recursive: true);
        }
        await stagingDir.create(recursive: true);

        final dittoRes = await Process.run('ditto', ['-x', '-k', filePath, stagingDir.path]);
        if (dittoRes.exitCode == 0) {
          final entries = await stagingDir.list().toList();
          Directory? newAppBundle;
          for (final entry in entries) {
            if (entry is Directory && entry.path.endsWith('.app')) {
              newAppBundle = entry;
              break;
            }
          }
          final exeFile = File(Platform.resolvedExecutable);
          // .../Theaver.app/Contents/MacOS/theaver -> .../Theaver.app
          final currentAppBundle = exeFile.parent.parent.parent;
          if (newAppBundle != null && currentAppBundle.path.endsWith('.app')) {
            final scriptFile = File('${tempDir.path}/theaver_apply_update.sh');
            final scriptContent = '''#!/bin/sh
sleep 1
kill -9 $currentPid 2>/dev/null || true
sleep 1
rm -rf "${currentAppBundle.path}"
mv "${newAppBundle.path}" "${currentAppBundle.path}"
xattr -cr "${currentAppBundle.path}" 2>/dev/null || true
rm -rf "${stagingDir.path}" "$filePath"
open "${currentAppBundle.path}"
rm -f "\$0"
''';
            await scriptFile.writeAsString(scriptContent);
            await Process.run('chmod', ['+x', scriptFile.path]);
            await Process.start(
              '/bin/sh',
              [scriptFile.path],
              mode: ProcessStartMode.detached,
            );
            exit(0);
          }
        }
      } catch (e) {
        debugPrint('[AppUpdateService] macOS auto-update fallback: $e');
      }
    }

    return await OpenFile.open(filePath);
  }
}
