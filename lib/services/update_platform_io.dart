import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import 'update_platform_types.dart';

UpdatePlatformAdapter createUpdatePlatformAdapter() => _IoUpdatePlatformAdapter();

class _IoUpdatePlatformAdapter implements UpdatePlatformAdapter {
  static const MethodChannel _installerChannel =
      MethodChannel('app.theaver.messenger/installer');

  @override
  String get platformName {
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      if (Platform.isWindows) return 'windows';
      if (Platform.isMacOS) return 'macos';
      if (Platform.isLinux) return 'linux';
    } catch (_) {}
    return defaultTargetPlatform.name.toLowerCase();
  }

  @override
  Future<String> detectArchitecture() async {
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final abis = androidInfo.supportedAbis;
        if (abis.isNotEmpty) {
          final primary = abis.first.toLowerCase();
          if (primary.contains('arm64') ||
              primary.contains('aarch64') ||
              primary.contains('v8a')) {
            return 'arm64-v8a';
          } else if (primary.contains('armeabi-v7a') ||
              primary.contains('armv7')) {
            return 'armeabi-v7a';
          } else if (primary.contains('x86_64') || primary.contains('amd64')) {
            return 'x86_64';
          } else if (primary.contains('x86')) {
            return 'x86';
          }
          return primary;
        }
      } else if (Platform.isWindows) {
        final archEnv =
            Platform.environment['PROCESSOR_ARCHITECTURE']?.toLowerCase() ?? '';
        final archW6432 =
            Platform.environment['PROCESSOR_ARCHITEW6432']?.toLowerCase() ?? '';
        String winArch = 'x64';
        if (archEnv.contains('arm64') || archW6432.contains('arm64')) {
          winArch = 'arm64';
        } else if (archEnv.contains('amd64') ||
            archEnv.contains('x64') ||
            archW6432.contains('amd64')) {
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
        if (v.contains('x64') || v.contains('x86_64') || v.contains('amd64')) {
          return 'x86_64';
        }
        if (v.contains('arm')) return 'armv7l';
      } else if (Platform.isIOS) {
        return 'arm64';
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Failed to detect architecture: $e');
    }

    try {
      final v = Platform.version.toLowerCase();
      if (v.contains('arm64') || v.contains('aarch64')) return 'arm64';
      if (v.contains('x64') || v.contains('x86_64') || v.contains('amd64')) {
        return 'x86_64';
      }
    } catch (_) {}

    return 'universal';
  }

  Future<Directory> _resolveCacheDir() async {
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      if (Platform.isAndroid) {
        final extDirs = await getExternalCacheDirectories();
        if (extDirs != null && extDirs.isNotEmpty) {
          return extDirs.first;
        }
      }
      rethrow;
    }
  }

  @override
  Future<String?> resolveUpdateSavePath(String downloadUrl, int latestBuild) async {
    final dir = await _resolveCacheDir();
    String fileName = 'theaver_update_$latestBuild.apk';
    try {
      final uri = Uri.parse(downloadUrl);
      if (uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty) {
        fileName = uri.pathSegments.last;
      }
    } catch (_) {}
    return '${dir.path}${Platform.pathSeparator}$fileName';
  }

  @override
  Future<bool> fileExistsAndMatchesSha256(String path, String? expectedSha256) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final len = await file.length();
      if (len <= 0) return false;
      if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
        final digest = await sha256.bind(file.openRead()).first;
        final actualHex = digest.toString().toLowerCase();
        if (actualHex != expectedSha256.trim().toLowerCase()) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> verifyDownloadedFile(String path, String? expectedSha256) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Файл обновления не найден на диске');
    }
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
  }

  @override
  Future<void> deleteFileIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  @override
  Future<UpdateInstallResult> installDownloadedPackage(String filePath) async {
    if (Platform.isAndroid) {
      try {
        final res = await _installerChannel.invokeMethod<String>('installApk', {
          'filePath': filePath,
        });
        if (res == 'LAUNCHED' || res == 'done') {
          return UpdateInstallResult(UpdateInstallStatus.launched, res ?? 'LAUNCHED');
        }
        if (res == 'PERMISSION_REQUESTED' || res == 'settings_opened') {
          return UpdateInstallResult(
            UpdateInstallStatus.permissionRequested,
            res ?? 'PERMISSION_REQUESTED',
          );
        }
      } on MissingPluginException catch (e) {
        debugPrint('[AppUpdateService] Native installApk missing, falling back to OpenFile: $e');
      } catch (e) {
        debugPrint('[AppUpdateService] Native installApk failed: $e');
        return UpdateInstallResult(UpdateInstallStatus.failed, e.toString());
      }
      final fallback = await OpenFile.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
      return fallback.type == ResultType.done
          ? UpdateInstallResult(UpdateInstallStatus.openedExternally, fallback.message)
          : UpdateInstallResult(UpdateInstallStatus.failed, fallback.message);
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

    final fallback = await OpenFile.open(filePath);
    return fallback.type == ResultType.done
        ? UpdateInstallResult(UpdateInstallStatus.openedExternally, fallback.message)
        : UpdateInstallResult(UpdateInstallStatus.failed, fallback.message);
  }

  @override
  void reloadWebPage() {}
}
