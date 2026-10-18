import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'media_cache_manager.dart';

/// Representation of a single media category in cache
class CacheCategoryInfo {
  final String key;
  final int sizeBytes;
  final int fileCount;

  const CacheCategoryInfo({
    required this.key,
    required this.sizeBytes,
    required this.fileCount,
  });

  String get sizeHuman => CacheService.formatBytes(sizeBytes);
}

/// Comprehensive cache breakdown across all media categories
class CacheBreakdown {
  final int totalBytes;
  final CacheCategoryInfo photos;
  final CacheCategoryInfo videos;
  final CacheCategoryInfo audio;
  final CacheCategoryInfo files;
  final CacheCategoryInfo other;

  const CacheBreakdown({
    required this.totalBytes,
    required this.photos,
    required this.videos,
    required this.audio,
    required this.files,
    required this.other,
  });

  String get totalHuman => CacheService.formatBytes(totalBytes);

  factory CacheBreakdown.empty() {
    return const CacheBreakdown(
      totalBytes: 0,
      photos: CacheCategoryInfo(key: 'photos', sizeBytes: 0, fileCount: 0),
      videos: CacheCategoryInfo(key: 'videos', sizeBytes: 0, fileCount: 0),
      audio: CacheCategoryInfo(key: 'audio', sizeBytes: 0, fileCount: 0),
      files: CacheCategoryInfo(key: 'files', sizeBytes: 0, fileCount: 0),
      other: CacheCategoryInfo(key: 'other', sizeBytes: 0, fileCount: 0),
    );
  }

  List<CacheCategoryInfo> get categories => [photos, videos, audio, files, other];
}

/// Service for calculating, categorizing, clearing, and auto-purging local cache.
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  static const _photoExtensions = {
    '.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic', '.heif', '.bmp', '.svg'
  };
  static const _videoExtensions = {
    '.mp4', '.mov', '.webm', '.avi', '.mkv', '.3gp', '.m4v'
  };
  static const _audioExtensions = {
    '.m4a', '.mp3', '.ogg', '.wav', '.aac', '.opus', '.flac', '.amr', '.wma'
  };
  static const _fileExtensions = {
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    '.zip', '.rar', '.7z', '.tar', '.gz', '.txt', '.json', '.csv'
  };

  /// Categorize file by its extension or path
  static String categorizeFile(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    if (_photoExtensions.contains(ext)) return 'photos';
    if (_videoExtensions.contains(ext)) return 'videos';
    if (_audioExtensions.contains(ext)) return 'audio';
    if (_fileExtensions.contains(ext)) return 'files';
    return 'other';
  }

  /// Format bytes into human-readable representation
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(d < 10 && i > 0 ? 1 : 0)} ${suffixes[i]}';
  }

  /// Get directories that contain temporary / cache data
  Future<List<Directory>> _getCacheDirectories() async {
    if (kIsWeb) return <Directory>[];
    final dirs = <Directory>[];
    try {
      final tempDir = await getTemporaryDirectory();
      dirs.add(tempDir);
    } catch (e) {
      debugPrint('CacheService: getTemporaryDirectory error: $e');
    }

    try {
      final appCacheDir = await getApplicationCacheDirectory();
      if (!dirs.any((d) => d.path == appCacheDir.path)) {
        dirs.add(appCacheDir);
      }
    } catch (e) {
      debugPrint('CacheService: getApplicationCacheDirectory error: $e');
    }

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final legacyMediaDir = Directory(p.join(docDir.path, 'miptgram_media'));
      if (await legacyMediaDir.exists() && !dirs.any((d) => d.path == legacyMediaDir.path)) {
        dirs.add(legacyMediaDir);
      }
    } catch (e) {
      debugPrint('CacheService: legacy documents media dir error: $e');
    }

    return dirs;
  }

  /// Recursively collect all regular files from given directories
  Future<List<File>> _collectCacheFiles() async {
    final dirs = await _getCacheDirectories();
    final files = <File>[];

    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      try {
        final entities = dir.listSync(recursive: true, followLinks: false);
        for (final entity in entities) {
          if (entity is File) {
            final fileName = p.basename(entity.path);
            // Protect critical app databases, WAL, and preferences
            if (fileName.endsWith('.db') ||
                fileName.endsWith('.sqlite') ||
                fileName.endsWith('.db-wal') ||
                fileName.endsWith('.db-shm')) {
              continue;
            }
            files.add(entity);
          }
        }
      } catch (e) {
        debugPrint('CacheService: listSync error in ${dir.path}: $e');
      }
    }

    return files;
  }

  /// Calculate live device cache breakdown
  Future<CacheBreakdown> getCacheStats() async {
    var photosBytes = 0;
    var photosCount = 0;
    var videosBytes = 0;
    var videosCount = 0;
    var audioBytes = 0;
    var audioCount = 0;
    var filesBytes = 0;
    var filesCount = 0;
    var otherBytes = 0;
    var otherCount = 0;

    final files = await _collectCacheFiles();

    for (final file in files) {
      try {
        final len = file.lengthSync();
        final category = categorizeFile(file.path);
        switch (category) {
          case 'photos':
            photosBytes += len;
            photosCount++;
            break;
          case 'videos':
            videosBytes += len;
            videosCount++;
            break;
          case 'audio':
            audioBytes += len;
            audioCount++;
            break;
          case 'files':
            filesBytes += len;
            filesCount++;
            break;
          default:
            otherBytes += len;
            otherCount++;
            break;
        }
      } catch (_) {
        // Skip inaccessible files
      }
    }

    final total = photosBytes + videosBytes + audioBytes + filesBytes + otherBytes;

    return CacheBreakdown(
      totalBytes: total,
      photos: CacheCategoryInfo(key: 'photos', sizeBytes: photosBytes, fileCount: photosCount),
      videos: CacheCategoryInfo(key: 'videos', sizeBytes: videosBytes, fileCount: videosCount),
      audio: CacheCategoryInfo(key: 'audio', sizeBytes: audioBytes, fileCount: audioCount),
      files: CacheCategoryInfo(key: 'files', sizeBytes: filesBytes, fileCount: filesCount),
      other: CacheCategoryInfo(key: 'other', sizeBytes: otherBytes, fileCount: otherCount),
    );
  }

  /// Clear local device cache by selective categories.
  /// Does NOT touch server cloud storage or chat messages.
  Future<int> clearCache({
    bool photos = true,
    bool videos = true,
    bool audio = true,
    bool files = true,
    bool other = true,
  }) async {
    var freedBytes = 0;

    // Clear memory caches (Flutter ImageCache and MediaCacheManager memory state)
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
    MediaCacheManager.instance.clearMemoryCache();

    // 1. Clear DefaultCacheManager if photos are selected
    if (photos) {
      try {
        await DefaultCacheManager().emptyCache();
      } catch (e) {
        debugPrint('CacheService: DefaultCacheManager.emptyCache error: $e');
      }
    }

    // 2. Clear individual files from temp/cache directories
    final diskFiles = await _collectCacheFiles();

    for (final file in diskFiles) {
      final category = categorizeFile(file.path);
      final shouldDelete = (category == 'photos' && photos) ||
          (category == 'videos' && videos) ||
          (category == 'audio' && audio) ||
          (category == 'files' && files) ||
          (category == 'other' && other);

      if (shouldDelete) {
        try {
          final size = file.lengthSync();
          file.deleteSync();
          freedBytes += size;
        } catch (_) {
          // File may be locked or already deleted
        }
      }
    }

    if (photos && videos && audio && files && other) {
      await MediaCacheManager.instance.clearDiskCache();
    }

    return freedBytes;
  }

  /// Execute automatic cache cleanup based on Keep Media period and Max Cache Size limit.
  /// Safe to invoke on app start and in background.
  Future<int> runAutoCleanup({
    String keepMediaPeriod = 'forever',
    int maxCacheSizeBytes = 0,
  }) async {
    var freedBytes = 0;

    final Duration? maxAge = switch (keepMediaPeriod) {
      '3days' => const Duration(days: 3),
      '1week' => const Duration(days: 7),
      '1month' => const Duration(days: 30),
      _ => null, // 'forever' or unsupported
    };

    final files = await _collectCacheFiles();

    // 1. Age-based eviction if period != forever
    if (maxAge != null) {
      final cutoff = DateTime.now().subtract(maxAge);
      for (final file in List<File>.from(files)) {
        try {
          final stat = file.statSync();
          if (stat.modified.isBefore(cutoff)) {
            final size = stat.size;
            file.deleteSync();
            files.remove(file);
            freedBytes += size;
          }
        } catch (_) {}
      }
    }

    // 2. Size-based eviction if maxCacheSizeBytes > 0
    if (maxCacheSizeBytes > 0) {
      var currentTotal = 0;
      final fileEntries = <({File file, DateTime modified, int size})>[];

      for (final file in files) {
        try {
          final stat = file.statSync();
          currentTotal += stat.size;
          fileEntries.add((file: file, modified: stat.modified, size: stat.size));
        } catch (_) {}
      }

      if (currentTotal > maxCacheSizeBytes) {
        // Sort oldest first (LRU)
        fileEntries.sort((a, b) => a.modified.compareTo(b.modified));

        for (final entry in fileEntries) {
          if (currentTotal <= maxCacheSizeBytes) break;
          try {
            entry.file.deleteSync();
            currentTotal -= entry.size;
            freedBytes += entry.size;
          } catch (_) {}
        }
      }
    }

    return freedBytes;
  }

  static const String keyKeepMedia = 'storage_keep_media';
  static const String keyMaxCacheSize = 'storage_max_cache_size';

  /// Get configured keep media period ('3days', '1week', '1month', 'forever')
  Future<String> getKeepMediaPeriod() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(keyKeepMedia) ?? 'forever';
    } catch (_) {
      return 'forever';
    }
  }

  /// Set keep media period and run auto-cleanup
  Future<void> setKeepMediaPeriod(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyKeepMedia, value);
      final maxSizeBytes = await getMaxCacheSize();
      await runAutoCleanup(keepMediaPeriod: value, maxCacheSizeBytes: maxSizeBytes);
    } catch (e) {
      debugPrint('CacheService: setKeepMediaPeriod error: $e');
    }
  }

  /// Get configured max cache size in bytes (0 = no limit)
  Future<int> getMaxCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(keyMaxCacheSize) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Set max cache size in bytes and run auto-cleanup
  Future<void> setMaxCacheSize(int bytes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(keyMaxCacheSize, bytes);
      final period = await getKeepMediaPeriod();
      await runAutoCleanup(keepMediaPeriod: period, maxCacheSizeBytes: bytes);
    } catch (e) {
      debugPrint('CacheService: setMaxCacheSize error: $e');
    }
  }

  /// Initialize cache service and run background auto-cleanup
  Future<void> init() async {
    try {
      final period = await getKeepMediaPeriod();
      final maxSize = await getMaxCacheSize();
      await runAutoCleanup(keepMediaPeriod: period, maxCacheSizeBytes: maxSize);
    } catch (e) {
      debugPrint('CacheService: init error: $e');
    }
  }
}
