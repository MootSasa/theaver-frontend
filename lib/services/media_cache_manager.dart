import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../config/app_config.dart';
import 'auth_service.dart';
import 'settings_service.dart';
import 'cache_service.dart';

/// Progress model containing received bytes, total expected bytes, and fraction (0.0 - 1.0).
class DownloadByteProgress {
  final int receivedBytes;
  final int totalBytes;
  final double fraction;

  const DownloadByteProgress({
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.fraction = 0.0,
  });

  /// Human-readable progress string, e.g. "4.2 MB / 400 MB" or "4.2 MB"
  String formatProgress() {
    if (totalBytes > 0) {
      final rec = MediaCacheManager.formatBytes(receivedBytes);
      final tot = MediaCacheManager.formatBytes(totalBytes);
      return '$rec / $tot';
    }
    if (receivedBytes > 0) {
      return MediaCacheManager.formatBytes(receivedBytes);
    }
    return '';
  }
}

/// Manager for downloading and caching media files with resumable range downloads,
/// byte progress tracking, cancel/pause capability, and auto-download policy checks.
class MediaCacheManager {
  static final MediaCacheManager instance = MediaCacheManager._internal();
  MediaCacheManager._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 10),
  ));

  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, ValueNotifier<double>> _progressNotifiers = {};
  final Map<String, ValueNotifier<DownloadByteProgress>> _byteProgressNotifiers = {};
  final Map<String, String> _localPathCache = {};

  /// Formats byte count into human-readable string (e.g. 14.2 MB)
  static String formatBytes(int bytes, [int decimals = 1]) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  /// Get or create a ValueNotifier for tracking download fraction of a URL (0.0 - 1.0)
  ValueNotifier<double> getProgressNotifier(String url) {
    return _progressNotifiers.putIfAbsent(url, () => ValueNotifier<double>(0.0));
  }

  /// Get or create a ValueNotifier for tracking byte download progress of a URL
  ValueNotifier<DownloadByteProgress> getByteProgressNotifier(String url) {
    return _byteProgressNotifiers.putIfAbsent(
      url,
      () => ValueNotifier<DownloadByteProgress>(const DownloadByteProgress()),
    );
  }

  bool isDownloading(String url) {
    return _cancelTokens.containsKey(url);
  }

  /// Cancel or pause an ongoing download without deleting the partial file or resetting progress
  void cancelDownload(String url) {
    final token = _cancelTokens.remove(url);
    if (token != null && !token.isCancelled) {
      token.cancel('User cancelled');
    }
    // Note: Do NOT reset notifiers to 0 so the paused progress state remains displayed
  }

  /// Returns the primary cache directory for media (`getApplicationCacheDirectory() / miptgram_media`)
  Future<Directory> getMediaCacheDirectory() async {
    final cacheDir = await getApplicationCacheDirectory();
    final dir = Directory(path.join(cacheDir.path, 'miptgram_media'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Generates a sanitized cache filename while preserving media file extension
  String getCacheFilename(String url) {
    final uri = Uri.tryParse(url);
    final ext = uri != null ? path.extension(uri.path) : '';
    final sanitized = url.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (ext.isNotEmpty && !sanitized.endsWith(ext)) {
      return '$sanitized$ext';
    }
    return sanitized;
  }

  /// Checks if the file is cached locally on disk and exists
  Future<File?> getCachedFile(String url) async {
    if (url.isEmpty) return null;
    final cachedPath = _localPathCache[url];
    if (cachedPath != null) {
      final f = File(cachedPath);
      if (await f.exists()) {
        try {
          if (await f.length() > 0) {
            return f;
          } else {
            await f.delete();
            _localPathCache.remove(url);
          }
        } catch (_) {}
      } else {
        _localPathCache.remove(url);
      }
    }

    final filename = getCacheFilename(url);
    final legacySanitized = url.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final filenamesToCheck = {filename, legacySanitized};

    for (final fname in filenamesToCheck) {
      // 1. Check primary application cache directory
      try {
        final cacheDir = await getApplicationCacheDirectory();
        final targetPath = path.join(cacheDir.path, 'miptgram_media', fname);
        final f = File(targetPath);
        if (await f.exists()) {
          if (await f.length() > 0) {
            _localPathCache[url] = targetPath;
            return f;
          } else {
            await f.delete();
          }
        }
      } catch (_) {}

      // 2. Check legacy documents directory
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final targetPath = path.join(docDir.path, 'miptgram_media', fname);
        final f = File(targetPath);
        if (await f.exists()) {
          if (await f.length() > 0) {
            _localPathCache[url] = targetPath;
            return f;
          } else {
            await f.delete();
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Checks if a partial download file (.tmp) exists and returns its current progress
  Future<DownloadByteProgress?> getPartialProgress(String url, {int? totalSize}) async {
    if (url.isEmpty) return null;
    final filename = getCacheFilename(url);
    final legacySanitized = url.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final filenamesToCheck = {filename, legacySanitized};

    // Check primary cache directory first, then legacy documents directory
    for (final dirGetter in [getApplicationCacheDirectory, getApplicationDocumentsDirectory]) {
      for (final fname in filenamesToCheck) {
        try {
          final dir = await dirGetter();
          final tempPath = path.join(dir.path, 'miptgram_media', '$fname.tmp');
          final tempFile = File(tempPath);
          if (await tempFile.exists()) {
            final len = await tempFile.length();
            if (len > 0) {
              final tot = totalSize ?? len;
              final fraction = tot > 0 ? (len / tot).clamp(0.0, 1.0) : 0.0;
              final prog = DownloadByteProgress(
                receivedBytes: len,
                totalBytes: tot,
                fraction: fraction,
              );
              _byteProgressNotifiers[url]?.value = prog;
              _progressNotifiers[url]?.value = fraction;
              return prog;
            }
          }
        } catch (_) {}
      }
    }
    return null;
  }

  /// Clears in-memory cache, cancel tokens and progress notifiers
  void clearMemoryCache() {
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) {
        token.cancel('Cache cleared');
      }
    }
    _cancelTokens.clear();
    _localPathCache.clear();
    _progressNotifiers.clear();
    _byteProgressNotifiers.clear();
  }

  /// Clears all downloaded media files from disk (both cache and legacy directories)
  Future<void> clearDiskCache() async {
    clearMemoryCache();
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final mediaCacheDir = Directory(path.join(cacheDir.path, 'miptgram_media'));
      if (await mediaCacheDir.exists()) {
        await mediaCacheDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing media cache dir: $e');
    }

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final legacyMediaDir = Directory(path.join(docDir.path, 'miptgram_media'));
      if (await legacyMediaDir.exists()) {
        await legacyMediaDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing legacy media dir: $e');
    }
  }

  /// Deletes a specific media file from disk cache and memory
  Future<void> deleteMedia(String url) async {
    cancelDownload(url);
    _localPathCache.remove(url);
    _progressNotifiers.remove(url);
    _byteProgressNotifiers.remove(url);

    final filename = getCacheFilename(url);
    final legacySanitized = url.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final filenamesToCheck = {filename, legacySanitized};

    for (final name in filenamesToCheck) {
      try {
        final cacheDir = await getApplicationCacheDirectory();
        final f1 = File(path.join(cacheDir.path, 'miptgram_media', name));
        if (await f1.exists()) await f1.delete();
        final tmp1 = File(path.join(cacheDir.path, 'miptgram_media', '$name.tmp'));
        if (await tmp1.exists()) await tmp1.delete();
      } catch (_) {}

      try {
        final docDir = await getApplicationDocumentsDirectory();
        final f2 = File(path.join(docDir.path, 'miptgram_media', name));
        if (await f2.exists()) await f2.delete();
        final tmp2 = File(path.join(docDir.path, 'miptgram_media', '$name.tmp'));
        if (await tmp2.exists()) await tmp2.delete();
      } catch (_) {}
    }
  }

  /// Evicts a specific media file from disk cache and memory (alias for deleteMedia)
  Future<void> evict(String url) => deleteMedia(url);

  /// Computes the total size in bytes of downloaded media files in cache
  Future<int> getCacheSizeBytes() async {
    int total = 0;
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final mediaCacheDir = Directory(path.join(cacheDir.path, 'miptgram_media'));
      if (await mediaCacheDir.exists()) {
        await for (final entity in mediaCacheDir.list(recursive: true)) {
          if (entity is File) {
            total += await entity.length();
          }
        }
      }
    } catch (_) {}

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final legacyMediaDir = Directory(path.join(docDir.path, 'miptgram_media'));
      if (await legacyMediaDir.exists()) {
        await for (final entity in legacyMediaDir.list(recursive: true)) {
          if (entity is File) {
            total += await entity.length();
          }
        }
      }
    } catch (_) {}
    return total;
  }

  void _emitProgress(
    String url,
    int received,
    int total,
    void Function(double fraction)? onProgress,
    void Function(DownloadByteProgress progress)? onByteProgress,
  ) {
    final fraction = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
    final prog = DownloadByteProgress(
      receivedBytes: received,
      totalBytes: total,
      fraction: fraction,
    );

    final pNotifier = _progressNotifiers[url];
    if (pNotifier != null) pNotifier.value = fraction;

    final bNotifier = _byteProgressNotifiers[url];
    if (bNotifier != null) bNotifier.value = prog;

    onProgress?.call(fraction);
    onByteProgress?.call(prog);
  }

  /// Alias for downloadMedia
  Future<File?> downloadFile(
    String url, {
    void Function(double progress)? onProgress,
    void Function(DownloadByteProgress progress)? onByteProgress,
    int? expectedTotalSize,
  }) => downloadMedia(
    url,
    onProgress: onProgress,
    onByteProgress: onByteProgress,
    expectedTotalSize: expectedTotalSize,
  );

  /// Download a media file to local cache with HTTP Range resume and byte progress tracking
  Future<File?> downloadMedia(
    String url, {
    void Function(double progress)? onProgress,
    void Function(DownloadByteProgress progress)? onByteProgress,
    int? expectedTotalSize,
  }) async {
    if (url.isEmpty) return null;

    final existing = await getCachedFile(url);
    if (existing != null) {
      _emitProgress(url, await existing.length(), await existing.length(), onProgress, onByteProgress);
      return existing;
    }

    if (_cancelTokens.containsKey(url)) {
      // Already downloading
      return null;
    }

    final cancelToken = CancelToken();
    _cancelTokens[url] = cancelToken;

    try {
      final mediaDir = await getMediaCacheDirectory();

      final filename = getCacheFilename(url);
      final targetPath = path.join(mediaDir.path, filename);
      final tempPath = '$targetPath.tmp';
      final tempFile = File(tempPath);

      int existingBytes = 0;
      if (await tempFile.exists()) {
        existingBytes = await tempFile.length();
      }

      final resolvedUrl = AppConfig.resolveMediaUrl(url) ?? url;
      final parsedUri = Uri.tryParse(resolvedUrl);

      // S3/MinIO storage buckets and direct file downloads reject Bearer tokens with HTTP 400 Bad Request.
      // We only attach Authorization if the URL is an /api/ endpoint and NOT a MinIO/S3 storage endpoint.
      bool shouldAttachAuth = false;
      if (parsedUri != null) {
        final pathLower = parsedUri.path.toLowerCase();
        final isMinIOStorage = parsedUri.port == 9000 ||
            parsedUri.host.contains('minio') ||
            parsedUri.host.startsWith('storage.') ||
            (AppConfig.storageUrl.isNotEmpty &&
                parsedUri.host == (Uri.tryParse(AppConfig.storageUrl)?.host ?? ''));
        if (!isMinIOStorage && pathLower.contains('/api/')) {
          shouldAttachAuth = true;
        }
      }

      final headers = <String, dynamic>{};
      if (shouldAttachAuth) {
        final token = await AuthService.getToken();
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }
      }
      if (existingBytes > 0) {
        headers['Range'] = 'bytes=$existingBytes-';
      }

      Response<ResponseBody> response;
      try {
        response = await _dio.get<ResponseBody>(
          resolvedUrl,
          cancelToken: cancelToken,
          options: Options(
            headers: headers,
            responseType: ResponseType.stream,
          ),
        );
      } on DioException catch (dioErr) {
        // If server returns 416 (Range Not Satisfiable), delete corrupted .tmp file and retry from offset 0
        if (dioErr.response?.statusCode == 416 && headers.containsKey('Range')) {
          debugPrint('Media download 416 Range Not Satisfiable for $url, resetting .tmp file and retrying from 0');
          try {
            if (await tempFile.exists()) await tempFile.delete();
          } catch (_) {}
          headers.remove('Range');
          existingBytes = 0;
          response = await _dio.get<ResponseBody>(
            resolvedUrl,
            cancelToken: cancelToken,
            options: Options(
              headers: headers,
              responseType: ResponseType.stream,
            ),
          );
        } else {
          rethrow;
        }
      }

      final statusCode = response.statusCode ?? 200;
      final isPartial = statusCode == 206;

      int totalBytes = expectedTotalSize ?? -1;
      if (isPartial) {
        final contentRange = response.headers.value('content-range');
        if (contentRange != null && contentRange.contains('/')) {
          final totalStr = contentRange.split('/').last.trim();
          totalBytes = int.tryParse(totalStr) ?? totalBytes;
        }
        if (totalBytes <= 0) {
          final cl = int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
          if (cl > 0) {
            totalBytes = existingBytes + cl;
          }
        }
      } else {
        existingBytes = 0;
        final cl = int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
        if (cl > 0) {
          totalBytes = cl;
        }
      }

      int currentBytes = existingBytes;
      _emitProgress(url, currentBytes, totalBytes, onProgress, onByteProgress);

      final raf = await tempFile.open(
        mode: isPartial ? FileMode.append : FileMode.write,
      );

      try {
        await for (final chunk in response.data!.stream) {
          if (cancelToken.isCancelled) break;
          await raf.writeFrom(chunk);
          currentBytes += chunk.length;
          _emitProgress(url, currentBytes, totalBytes, onProgress, onByteProgress);
        }
      } finally {
        await raf.close();
      }

      if (cancelToken.isCancelled) {
        debugPrint('Media download paused/cancelled at $currentBytes bytes: $url');
        return null;
      }

      if (await tempFile.exists()) {
        final actualLength = await tempFile.length();
        if (actualLength > 0 && (totalBytes <= 0 || actualLength >= totalBytes)) {
          final targetFile = File(targetPath);
          if (await targetFile.exists()) {
            try {
              await targetFile.delete();
            } catch (_) {}
          }
          final finalFile = await tempFile.rename(targetPath);
          _localPathCache[url] = targetPath;
          _emitProgress(url, actualLength, actualLength, onProgress, onByteProgress);
          _triggerDebouncedCacheCleanup();
          return finalFile;
        } else if (actualLength == 0) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      if (cancelToken.isCancelled) {
        debugPrint('Media download cancelled for: $url');
      } else {
        debugPrint('Media download error for $url: $e');
        if (e is DioException && (e.response?.statusCode != null && e.response!.statusCode! >= 400 && e.response!.statusCode! < 500)) {
          // Fatal client error (e.g. 404, 400, 403), remove any incomplete .tmp file
          try {
            final mediaDir = await getMediaCacheDirectory();
            final filename = getCacheFilename(url);
            final tempPath = path.join(mediaDir.path, '$filename.tmp');
            final tempFile = File(tempPath);
            if (await tempFile.exists()) await tempFile.delete();
          } catch (_) {}
        }
      }
    } finally {
      _cancelTokens.remove(url);
    }
    return null;
  }

  DateTime? _lastCleanupTime;
  void _triggerDebouncedCacheCleanup() {
    final now = DateTime.now();
    if (_lastCleanupTime == null || now.difference(_lastCleanupTime!).inMinutes >= 5) {
      _lastCleanupTime = now;
      Future.microtask(() async {
        try {
          await CacheService().init();
        } catch (_) {}
      });
    }
  }

  /// Evaluates whether media should auto-download based on user Settings and size limits
  bool shouldAutoDownload({
    required String messageType,
    int? fileSize,
    bool? isWifi,
  }) {
    final settings = SettingsService().storageSettings;
    final wifi = isWifi ?? true;
    final size = fileSize ?? 0;

    if (messageType == 'photo' || messageType == 'image') {
      final allowed = wifi
          ? settings.autoDownloadPhotosOnWifi
          : settings.autoDownloadPhotosOnCellular;
      if (!allowed) return false;
      return size <= 10 * 1024 * 1024;
    }

    if (messageType == 'video') {
      final allowed = wifi
          ? settings.autoDownloadVideosOnWifi
          : settings.autoDownloadVideosOnCellular;
      if (!allowed) return false;
      return wifi ? size <= 15 * 1024 * 1024 : size <= 5 * 1024 * 1024;
    }

    if (messageType == 'file' || messageType == 'document') {
      final allowed = wifi
          ? settings.autoDownloadFilesOnWifi
          : settings.autoDownloadFilesOnCellular;
      if (!allowed) return false;
      return size <= 3 * 1024 * 1024;
    }

    if (messageType == 'audio' || messageType == 'voice') {
      final allowed = wifi
          ? settings.autoDownloadAudioOnWifi
          : settings.autoDownloadAudioOnCellular;
      if (!allowed) return false;
      return size <= 10 * 1024 * 1024;
    }

    return false;
  }
}
