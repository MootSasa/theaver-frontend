import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/config/app_config.dart';
import 'package:theaver/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('AppUpdateInfo Model Tests', () {
    test('parses complete JSON correctly', () {
      final json = {
        'has_update': true,
        'latest_version': '1.2.0',
        'latest_build': 42,
        'min_supported_build': 10,
        'force_update': false,
        'download_url': 'https://storage.theaver.app/releases/theaver-v1.2.0.apk',
        'apk_size_bytes': 47185920, // ~45.0 MB
        'sha256': 'abc123def456',
        'release_notes': '• Voice calls improvements\n• Bug fixes',
      };

      final info = AppUpdateInfo.fromJson(json);

      expect(info.hasUpdate, isTrue);
      expect(info.latestVersion, equals('1.2.0'));
      expect(info.latestBuild, equals(42));
      expect(info.minSupportedBuild, equals(10));
      expect(info.forceUpdate, isFalse);
      expect(info.downloadUrl, equals('https://storage.theaver.app/releases/theaver-v1.2.0.apk'));
      expect(info.apkSizeBytes, equals(47185920));
      expect(info.sha256, equals('abc123def456'));
      expect(info.releaseNotes, contains('Voice calls'));
      expect(info.formattedSize, equals('45.0 MB'));
    });

    test('parses empty / partial JSON with safe defaults', () {
      final info = AppUpdateInfo.fromJson({});

      expect(info.hasUpdate, isFalse);
      expect(info.latestVersion, isEmpty);
      expect(info.latestBuild, equals(0));
      expect(info.minSupportedBuild, equals(1));
      expect(info.forceUpdate, isFalse);
      expect(info.downloadUrl, isEmpty);
      expect(info.apkSizeBytes, equals(0));
      expect(info.sha256, isEmpty);
      expect(info.releaseNotes, isEmpty);
      expect(info.formattedSize, isEmpty);
    });

    test('noUpdate factory returns consistent blank model', () {
      final info = AppUpdateInfo.noUpdate();

      expect(info.hasUpdate, isFalse);
      expect(info.latestVersion, isEmpty);
      expect(info.latestBuild, equals(0));
      expect(info.formattedSize, isEmpty);
    });
  });

  group('AppConfig.normalizeAndroidBuildNumber Tests', () {
    test('strips split-per-abi prefixes accurately', () {
      expect(AppConfig.normalizeAndroidBuildNumber(2401), equals(401));
      expect(AppConfig.normalizeAndroidBuildNumber(4401), equals(401));
      expect(AppConfig.normalizeAndroidBuildNumber(1401), equals(401));
      expect(AppConfig.normalizeAndroidBuildNumber(401), equals(401));
      expect(
        AppConfig.normalizeAndroidBuildNumber(
          3205,
          version: '1.20.0-beta.1205',
        ),
        equals(1205),
      );
      expect(
        AppConfig.normalizeAndroidBuildNumber(
          5205,
          version: '1.20.0-beta.1205',
        ),
        equals(1205),
      );
    });
  });

  group('AppUpdateService Policy & Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AppUpdateService.instance.resetForTesting();
    });

    AppUpdateInfo buildSampleUpdate({
      int latestBuild = 500,
      bool forceUpdate = false,
    }) {
      return AppUpdateInfo(
        hasUpdate: true,
        latestVersion: '1.20.0',
        latestBuild: latestBuild,
        minSupportedBuild: 100,
        forceUpdate: forceUpdate,
        downloadUrl: 'https://storage.theaver.app/releases/theaver.apk',
        apkSizeBytes: 10485760,
        sha256: 'deadbeefdeadbeef',
        releaseNotes: '- Bug fixes',
      );
    }

    test('snoozeUpdate suppresses prompt temporarily without ignoring permanently', () async {
      final update500 = buildSampleUpdate(latestBuild: 500);

      expect(await AppUpdateService.instance.shouldPromptInApp(update500), isTrue);

      await AppUpdateService.instance.snoozeUpdate(500);
      expect(await AppUpdateService.instance.shouldPromptInApp(update500), isFalse);

      // Expired snooze allows prompting again
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        AppUpdateService.prefSnoozedUntilMsKey,
        DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
      );
      expect(await AppUpdateService.instance.shouldPromptInApp(update500), isTrue);

      // ignoreBuild suppresses only up to ignored build, not newer builds
      await AppUpdateService.instance.ignoreBuild(500);
      expect(await AppUpdateService.instance.shouldPromptInApp(update500), isFalse);

      final update501 = buildSampleUpdate(latestBuild: 501);
      expect(await AppUpdateService.instance.shouldPromptInApp(update501), isTrue);

      // forceUpdate overrides both snooze and ignoreBuild
      await AppUpdateService.instance.snoozeUpdate(500);
      final forced500 = buildSampleUpdate(latestBuild: 500, forceUpdate: true);
      expect(await AppUpdateService.instance.shouldPromptInApp(forced500), isTrue);
    });

    test('shouldNotifyDevice deduplicates notified builds', () async {
      final update500 = buildSampleUpdate(latestBuild: 500);
      expect(await AppUpdateService.instance.shouldNotifyDevice(update500), isTrue);

      await AppUpdateService.instance.markDeviceNotified(500);
      expect(await AppUpdateService.instance.shouldNotifyDevice(update500), isFalse);

      final update501 = buildSampleUpdate(latestBuild: 501);
      expect(await AppUpdateService.instance.shouldNotifyDevice(update501), isTrue);
    });

    test('init restores lastCheckedAt and cached AppUpdateInfo', () async {
      final expectedMs = DateTime(2026, 11, 14, 9, 30).millisecondsSinceEpoch;
      final cachedUpdate = buildSampleUpdate(latestBuild: 9999);
      SharedPreferences.setMockInitialValues({
        AppUpdateService.prefLastCheckedMsKey: expectedMs,
        AppUpdateService.prefCachedUpdateJsonKey: jsonEncode(cachedUpdate.toJson()),
      });

      await AppUpdateService.instance.init();

      final state = AppUpdateService.instance.stateNotifier.value;
      expect(state.lastCheckedAt?.millisecondsSinceEpoch, equals(expectedMs));
      expect(state.availableUpdate?.latestBuild, equals(9999));
      expect(state.status, equals(AppUpdateStatus.available));
    });
  });
}
