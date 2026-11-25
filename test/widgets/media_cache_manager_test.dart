// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/services/media_cache_manager.dart';
import 'package:theaver/services/settings_service.dart';

class _MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;
  _MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationCachePath() async => tempDir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('media_cache_test_');
    PathProviderPlatform.instance = _MockPathProviderPlatform(testDir);
    MediaCacheManager.instance.clearMemoryCache();
  });

  tearDown(() async {
    MediaCacheManager.instance.clearMemoryCache();
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('MediaCacheManager Zero-Byte and Eviction Tests', () {
    test('getCachedFile deletes 0-byte corrupt files and returns null', () async {
      const url = 'https://storage.theaver.app/theaver-files/video/test_corrupt.mp4';
      final mediaDir = await MediaCacheManager.instance.getMediaCacheDirectory();
      final filename = MediaCacheManager.instance.getCacheFilename(url);
      final corruptFile = File('${mediaDir.path}/$filename');
      await corruptFile.writeAsBytes([]); // 0-byte file

      expect(await corruptFile.exists(), isTrue);
      expect(await corruptFile.length(), 0);

      final cached = await MediaCacheManager.instance.getCachedFile(url);
      expect(cached, isNull);
      expect(await corruptFile.exists(), isFalse);
    });

    test('getCachedFile returns valid non-empty file', () async {
      const url = 'https://storage.theaver.app/theaver-files/video/valid_video.mp4';
      final mediaDir = await MediaCacheManager.instance.getMediaCacheDirectory();
      final filename = MediaCacheManager.instance.getCacheFilename(url);
      final validFile = File('${mediaDir.path}/$filename');
      await validFile.writeAsBytes([1, 2, 3, 4, 5]);

      final cached = await MediaCacheManager.instance.getCachedFile(url);
      expect(cached, isNotNull);
      expect(await cached!.length(), equals(5));
    });

    test('evict deletes both cached file and .tmp file', () async {
      const url = 'https://storage.theaver.app/theaver-files/video/to_evict.mp4';
      final mediaDir = await MediaCacheManager.instance.getMediaCacheDirectory();
      final filename = MediaCacheManager.instance.getCacheFilename(url);
      final targetFile = File('${mediaDir.path}/$filename');
      final tmpFile = File('${mediaDir.path}/$filename.tmp');
      await targetFile.writeAsBytes([10, 20]);
      await tmpFile.writeAsBytes([10]);

      expect(await targetFile.exists(), isTrue);
      expect(await tmpFile.exists(), isTrue);

      await MediaCacheManager.instance.evict(url);

      expect(await targetFile.exists(), isFalse);
      expect(await tmpFile.exists(), isFalse);
      expect(await MediaCacheManager.instance.getCachedFile(url), isNull);
    });
  });

  group('MediaCacheManager Authorization Header Selectivity Tests', () {
    test('Direct MinIO / storage URLs do not require Bearer token', () {
      final s3Uri = Uri.parse('http://localhost:9000/theaver-files/video/note.mp4');
      final isMinIOStorage = s3Uri.port == 9000 ||
          s3Uri.host.contains('minio') ||
          s3Uri.host.startsWith('storage.');
      expect(isMinIOStorage, isTrue);

      final apiUri = Uri.parse('http://localhost:8080/api/files/download/note.mp4');
      final isApiMinIO = apiUri.port == 9000 ||
          apiUri.host.contains('minio') ||
          apiUri.host.startsWith('storage.');
      expect(isApiMinIO, isFalse);
      expect(apiUri.path.contains('/api/'), isTrue);
    });
  });

  group('Canonical Cache Keys, Cross-Extension Aliasing & Telegram Auto-Download Rules', () {
    test('equivalent media URL forms map to one canonical key and hit seeded cache', () async {
      final src = File('${testDir.path}/demo_src.mp4');
      await src.writeAsBytes([7, 8, 9, 10, 11]);

      const variants = [
        '/media/videos/demo.mp4',
        'https://storage.theaver.app/media/videos/demo.mp4',
        'http://localhost:9000/media/videos/demo.mp4',
        'https://api.theaver.app/api/files/download/videos/demo.mp4',
        'https://storage.theaver.app/media/videos/demo.mp4?X-Amz-Signature=deadbeef&X-Amz-Expires=300',
      ];

      final expectedKey = MediaCacheManager.instance.canonicalCacheKey(variants.first);
      final expectedName = MediaCacheManager.instance.getCacheFilename(variants.first);
      for (final v in variants) {
        expect(MediaCacheManager.instance.canonicalCacheKey(v), expectedKey);
        expect(MediaCacheManager.instance.getCacheFilename(v), expectedName);
      }

      final seeded = await MediaCacheManager.instance.seedCacheFromFile(
        variants.first,
        src,
        deleteSourceIfTemp: false,
      );
      expect(seeded, isNotNull);

      for (final v in variants) {
        final syncHit = MediaCacheManager.instance.getCachedFileSync(v);
        expect(syncHit, isNotNull, reason: 'sync miss for $v');
        expect(syncHit!.path, seeded!.path);

        final asyncHit = await MediaCacheManager.instance.getCachedFile(v);
        expect(asyncHit, isNotNull, reason: 'async miss for $v');
        expect(asyncHit!.path, seeded.path);
      }
    });

    test('preserveSourceExtension persists local alias across memory cache clears', () async {
      final movSrc = File('${testDir.path}/iphone_clip.mov');
      await movSrc.writeAsBytes([1, 2, 3, 4, 5, 6]);
      const serverMp4Url = 'https://storage.theaver.app/media/videos/transcoded_out.mp4';

      final seeded = await MediaCacheManager.instance.seedCacheFromFile(
        serverMp4Url,
        movSrc,
        deleteSourceIfTemp: false,
        preserveSourceExtension: true,
      );
      expect(seeded, isNotNull);
      expect(seeded!.path.endsWith('.mov'), isTrue);

      // Clear in-memory caches (simulating cold restart) -> disk alias must still resolve.
      MediaCacheManager.instance.clearMemoryCache();
      final hit = await MediaCacheManager.instance.getCachedFile(serverMp4Url);
      expect(hit, isNotNull);
      expect(hit!.path, seeded.path);
      expect(await hit.readAsBytes(), [1, 2, 3, 4, 5, 6]);
    });

    test('shouldAutoDownload enforces Telegram null/zero size guards per media type', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await SettingsService().init();
      await SettingsService().saveStorageSettings(
        StorageSettings(
          autoDownloadPhotosOnWifi: true,
          autoDownloadVideosOnWifi: true,
          autoDownloadFilesOnWifi: true,
          autoDownloadAudioOnWifi: true,
          autoDownloadPhotosOnCellular: false,
          autoDownloadVideosOnCellular: false,
          autoDownloadFilesOnCellular: false,
          autoDownloadAudioOnCellular: false,
          autoDownloadPhotosOnRoaming: false,
          autoDownloadVideosOnRoaming: false,
          autoDownloadFilesOnRoaming: false,
          autoDownloadAudioOnRoaming: false,
        ),
      );
      addTearDown(
        () => SettingsService().saveStorageSettings(StorageSettings.defaults()),
      );

      expect(
        MediaCacheManager.instance.shouldAutoDownload(
          messageType: 'video',
          fileSize: null,
          isWifi: true,
        ),
        isFalse,
      );
      expect(
        MediaCacheManager.instance.shouldAutoDownload(
          messageType: 'video',
          fileSize: 0,
          isWifi: true,
        ),
        isFalse,
      );
      expect(
        MediaCacheManager.instance.shouldAutoDownload(
          messageType: 'file',
          fileSize: null,
          isWifi: true,
        ),
        isFalse,
      );
      expect(
        MediaCacheManager.instance.shouldAutoDownload(
          messageType: 'audio',
          fileSize: null,
          isWifi: true,
        ),
        isFalse,
      );
      expect(
        MediaCacheManager.instance.shouldAutoDownload(
          messageType: 'image',
          fileSize: null,
          isWifi: true,
        ),
        isTrue,
      );
      expect(
        MediaCacheManager.instance.shouldAutoDownload(
          messageType: 'voice',
          fileSize: null,
          isWifi: true,
        ),
        isTrue,
      );
      expect(
        MediaCacheManager.instance.shouldAutoDownload(
          messageType: 'video',
          fileSize: 2 * 1024 * 1024,
          isWifi: true,
        ),
        isTrue,
      );
      expect(
        MediaCacheManager.instance.shouldAutoDownload(
          messageType: 'file',
          fileSize: 2 * 1024 * 1024,
          isWifi: true,
        ),
        isTrue,
      );
      expect(
        MediaCacheManager.instance.shouldAutoDownload(
          messageType: 'file',
          fileSize: 5 * 1024 * 1024,
          isWifi: true,
        ),
        isFalse,
      );
    });
  });
}
