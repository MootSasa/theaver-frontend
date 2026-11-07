import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/services/update_service.dart';

void main() {
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
}
