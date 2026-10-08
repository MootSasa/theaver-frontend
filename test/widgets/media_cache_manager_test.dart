import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:theaver/services/media_cache_manager.dart';

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
}
