import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// Exposes the internal [Dio] client for attaching hermetic [HttpClientAdapter] mocks in tests.
  @visibleForTesting
  Dio get dioForTesting => _dio;

  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, Future<File?>> _inFlightDownloads = {};
  final Map<String, ({String url, DateTime expiresAt})> _presignedUrlCache = {};
  final Map<String, ValueNotifier<double>> _progressNotifiers = {};
  final Map<String, ValueNotifier<DownloadByteProgress>> _byteProgressNotifiers = {};
  final Map<String, String> _localPathCache = {};
  final Map<String, Uint8List> _videoThumbnailCache = {};
  final Set<String> _userCancelledUrls = {};

  static const Set<String> _publicBuckets = {'avatars', 'releases'};

  /// Extracts a MinIO object key when [rawOrResolvedUrl] points to the private
  /// media bucket (or `/api/files/download/<objectName>`). Returns `null` for
  /// public buckets (`avatars`, `releases`), already-presigned URLs, and
  /// external hosts.
  String? extractProtectedObjectName(
    String rawOrResolvedUrl, {
    bool ignorePresignQuery = false,
  }) {
    final trimmed = rawOrResolvedUrl.trim();
    if (trimmed.isEmpty || AppConfig.isLocalFilePath(trimmed)) return null;
    final resolved = AppConfig.resolveMediaUrl(trimmed) ?? trimmed;
    final uri = Uri.tryParse(resolved);
    if (uri == null) return null;

    // Already a presigned S3/MinIO URL — must not strip query signature unless
    // explicitly falling back after an expired-signature 401/403 failure.
    if (!ignorePresignQuery &&
        (uri.queryParameters.containsKey('X-Amz-Signature') ||
            uri.queryParameters.containsKey('x-amz-signature'))) {
      return null;
    }

    final rawPath = uri.path;
    final dlIdx = rawPath.indexOf('/api/files/download/');
    if (dlIdx != -1) {
      final obj = rawPath.substring(dlIdx + '/api/files/download/'.length);
      return obj.isNotEmpty ? Uri.decodeFull(obj) : null;
    }

    final storageUri = Uri.tryParse(AppConfig.storageUrl);
    final bool isStorageHost = uri.port == 9000 ||
        uri.host.contains('minio') ||
        uri.host.startsWith('storage.') ||
        (storageUri != null &&
            storageUri.host.isNotEmpty &&
            uri.host == storageUri.host);
    if (!isStorageHost) return null;

    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length < 2) return null;
    final bucket = segs.first.toLowerCase();
    if (_publicBuckets.contains(bucket)) return null;
    return segs.sublist(1).map(Uri.decodeComponent).join('/');
  }

  /// Resolves the best streaming target `(uri, httpHeaders)` for network video
  /// playback, obtaining a short-lived presigned MinIO URL (or authenticated
  /// `/api/files/download/...` fallback) when pointing at the private media bucket.
  Future<({Uri uri, Map<String, String> headers})?> resolveStreamableVideoTarget(
    String rawOrResolvedUrl,
  ) async {
    final resolved = AppConfig.resolveMediaUrl(rawOrResolvedUrl) ?? rawOrResolvedUrl;
    if (resolved.isEmpty) return null;

    final objectName = extractProtectedObjectName(resolved);
    if (objectName != null) {
      final cached = _presignedUrlCache[objectName];
      if (cached != null &&
          DateTime.now().isBefore(
            cached.expiresAt.subtract(const Duration(minutes: 5)),
          )) {
        final uri = Uri.tryParse(cached.url);
        if (uri != null) {
          return (uri: uri, headers: const <String, String>{});
        }
      }

      final token = await AuthService.getToken();
      if (token != null && token.isNotEmpty) {
        try {
          final resp = await _dio.get<dynamic>(
            '${AppConfig.baseUrl}/api/files/download-presigned/$objectName',
            options: Options(
              headers: {'Authorization': 'Bearer $token'},
              receiveTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 5),
            ),
          );
          if (resp.statusCode == 200 &&
              resp.data is Map &&
              resp.data['success'] == true) {
            final dlUrl = resp.data['download_url']?.toString() ?? '';
            final expiresSec =
                (resp.data['expires_in'] as num?)?.toInt() ?? 3600;
            final dlUri = Uri.tryParse(dlUrl);
            if (dlUri != null) {
              _presignedUrlCache[objectName] = (
                url: dlUrl,
                expiresAt: DateTime.now().add(Duration(seconds: expiresSec)),
              );
              return (uri: dlUri, headers: const <String, String>{});
            }
          }
        } catch (_) {}

        final fallbackUri =
            Uri.tryParse('${AppConfig.baseUrl}/api/files/download/$objectName');
        if (fallbackUri != null) {
          return (
            uri: fallbackUri,
            headers: <String, String>{'Authorization': 'Bearer $token'},
          );
        }
      }
    }

    final uri = Uri.tryParse(resolved);
    if (uri == null) return null;
    final bool needsAuth =
        uri.path.toLowerCase().contains('/api/') && objectName == null;
    if (needsAuth) {
      final token = await AuthService.getToken();
      if (token != null && token.isNotEmpty) {
        return (
          uri: uri,
          headers: <String, String>{'Authorization': 'Bearer $token'},
        );
      }
    }
    return (uri: uri, headers: const <String, String>{});
  }

  /// Fetches and disk-caches remote thumbnail bytes (with automatic private-bucket
  /// `/api/files/download/...` fallback on 401/403).
  Future<Uint8List?> fetchThumbnailBytes(String rawOrResolvedUrl) async {
    if (kIsWeb || rawOrResolvedUrl.isEmpty) return null;
    final resolved = AppConfig.resolveMediaUrl(rawOrResolvedUrl) ?? rawOrResolvedUrl;
    final mem = _videoThumbnailCache[resolved];
    if (mem != null && mem.isNotEmpty) return mem;

    final file = await downloadMedia(resolved);
    if (file == null || !await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        cacheVideoThumbnail(resolved, bytes);
        return bytes;
      }
    } catch (_) {}
    return null;
  }

  /// Synchronously returns a cached [File] if its local path is already known in memory.
  /// Prevents a 1-frame placeholder flash when cloning media bubbles for the blur context menu.
  File? getCachedFileSync(String url) {
    if (kIsWeb || url.isEmpty) return null;
    final resolvedUrl = AppConfig.resolveMediaUrl(url) ?? url;
    final cachedPath = _localPathCache[url] ?? _localPathCache[resolvedUrl];
    if (cachedPath != null) {
      final f = File(cachedPath);
      if (f.existsSync() && f.lengthSync() > 0) {
        return f;
      }
      _localPathCache.remove(url);
      _localPathCache.remove(resolvedUrl);
    }

    final uri = Uri.tryParse(url);
    final isNetwork =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (AppConfig.isLocalFilePath(url) ||
        (!isNetwork &&
            !url.startsWith('/api/') &&
            !url.startsWith('/uploads/') &&
            !url.startsWith('/media/'))) {
      try {
        final filePath =
            url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
        final directFile = File(filePath);
        if (directFile.existsSync() && directFile.lengthSync() > 0) {
          _localPathCache[url] = filePath;
          return directFile;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Synchronously returns a cached video first-frame thumbnail if already extracted.
  Uint8List? getCachedVideoThumbnailSync(String filePath) {
    if (filePath.isEmpty) return null;
    return _videoThumbnailCache[filePath];
  }

  /// Caches an extracted video first-frame thumbnail in memory.
  void cacheVideoThumbnail(String filePath, Uint8List bytes) {
    if (filePath.isEmpty || bytes.isEmpty) return;
    if (_videoThumbnailCache.length >= 120) {
      _videoThumbnailCache.remove(_videoThumbnailCache.keys.first);
    }
    _videoThumbnailCache[filePath] = bytes;
  }

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
    final resolvedUrl = AppConfig.resolveMediaUrl(url) ?? url;
    return _cancelTokens.containsKey(url) || _cancelTokens.containsKey(resolvedUrl);
  }

  bool wasCancelledByUser(String url) {
    final resolvedUrl = AppConfig.resolveMediaUrl(url) ?? url;
    return _userCancelledUrls.contains(url) || _userCancelledUrls.contains(resolvedUrl);
  }

  /// Cancel or pause an ongoing download without deleting the partial file or resetting progress
  void cancelDownload(String url, {bool byUser = true}) {
    final resolvedUrl = AppConfig.resolveMediaUrl(url) ?? url;
    if (byUser) {
      _userCancelledUrls.add(url);
      _userCancelledUrls.add(resolvedUrl);
    }
    final token = _cancelTokens.remove(url);
    if (token != null && !token.isCancelled) {
      token.cancel('User cancelled');
    }
    final resolvedToken = _cancelTokens.remove(resolvedUrl);
    if (resolvedToken != null && !resolvedToken.isCancelled) {
      resolvedToken.cancel('User cancelled');
    }
    // Note: Do NOT reset notifiers to 0 so the paused progress state remains displayed
  }

  /// Returns the primary cache directory for media (`getApplicationCacheDirectory() / theaver_media`)
  Future<Directory> getMediaCacheDirectory() async {
    final cacheDir = await getApplicationCacheDirectory();
    final dir = Directory(path.join(cacheDir.path, 'theaver_media'));
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
    if (kIsWeb || url.isEmpty) return null;

    // Support direct local file paths (e.g., pending outgoing media before upload completes)
    final uri = Uri.tryParse(url);
    final isNetwork = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (AppConfig.isLocalFilePath(url) ||
        (!isNetwork &&
            !url.startsWith('/api/') &&
            !url.startsWith('/uploads/') &&
            !url.startsWith('/media/'))) {
      try {
        final filePath = url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
        final directFile = File(filePath);
        if (await directFile.exists() && await directFile.length() > 0) {
          _localPathCache[url] = filePath;
          return directFile;
        }
      } catch (_) {}
    }

    final resolvedUrl = AppConfig.resolveMediaUrl(url) ?? url;
    final cachedPath = _localPathCache[url] ?? _localPathCache[resolvedUrl];
    if (cachedPath != null) {
      final f = File(cachedPath);
      if (await f.exists()) {
        try {
          if (await f.length() > 0) {
            return f;
          } else {
            await f.delete();
            _localPathCache.remove(url);
            _localPathCache.remove(resolvedUrl);
          }
        } catch (_) {}
      } else {
        _localPathCache.remove(url);
        _localPathCache.remove(resolvedUrl);
      }
    }

    final filename = getCacheFilename(url);
    final resolvedFilename = getCacheFilename(resolvedUrl);
    final legacySanitized = url.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final filenamesToCheck = {filename, resolvedFilename, legacySanitized};

    for (final fname in filenamesToCheck) {
      // Check primary app-private cache directory
      try {
        final cacheDir = await getApplicationCacheDirectory();
        final targetPath = path.join(cacheDir.path, 'theaver_media', fname);
        final f = File(targetPath);
        if (await f.exists()) {
          if (await f.length() > 0) {
            _localPathCache[url] = targetPath;
            _localPathCache[resolvedUrl] = targetPath;
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
    if (kIsWeb || url.isEmpty) return null;
    final filename = getCacheFilename(url);
    final legacySanitized = url.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final filenamesToCheck = {filename, legacySanitized};

    for (final fname in filenamesToCheck) {
      try {
        final dir = await getApplicationCacheDirectory();
        final tempPath = path.join(dir.path, 'theaver_media', '$fname.tmp');
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
    _inFlightDownloads.clear();
    _presignedUrlCache.clear();
    _localPathCache.clear();
    _progressNotifiers.clear();
    _byteProgressNotifiers.clear();
    _userCancelledUrls.clear();
  }

  /// Clears all downloaded media files from the app-private cache directory
  Future<void> clearDiskCache() async {
    clearMemoryCache();
    if (kIsWeb) return;
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final mediaCacheDir = Directory(path.join(cacheDir.path, 'theaver_media'));
      if (await mediaCacheDir.exists()) {
        await mediaCacheDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing media cache dir: $e');
    }
  }

  /// Seeds the local media cache directly from a local file (e.g. just-recorded voice/video note
  /// or compressed image after upload), avoiding re-downloading our own sent media and cleaning up temp files.
  Future<File?> seedCacheFromFile(
    String remoteUrl,
    File sourceFile, {
    bool deleteSourceIfTemp = true,
  }) async {
    if (kIsWeb || remoteUrl.isEmpty) return null;
    try {
      if (!await sourceFile.exists()) return null;
      final len = await sourceFile.length();
      if (len <= 0) return null;

      final mediaDir = await getMediaCacheDirectory();
      final resolvedUrl = AppConfig.resolveMediaUrl(remoteUrl) ?? remoteUrl;
      final targetFilename = getCacheFilename(resolvedUrl);
      final targetPath = path.join(mediaDir.path, targetFilename);
      final targetFile = File(targetPath);

      if (path.canonicalize(sourceFile.path) != path.canonicalize(targetPath)) {
        await sourceFile.copy(targetPath);

        if (deleteSourceIfTemp) {
          try {
            final tempDir = await getTemporaryDirectory();
            final normSource = path.normalize(sourceFile.path);
            final normTemp = path.normalize(tempDir.path);
            final base = path.basename(normSource);
            final isTempUpload = normSource.startsWith(normTemp) &&
                (base.startsWith('voice_note_') ||
                    base.startsWith('video_note_') ||
                    base.startsWith('REC') ||
                    base.startsWith('send_') ||
                    base.startsWith('image_picker') ||
                    base.startsWith('scaled_'));
            if (isTempUpload) {
              await sourceFile.delete();
            }
          } catch (_) {}
        }
      }

      _localPathCache[remoteUrl] = targetPath;
      _localPathCache[resolvedUrl] = targetPath;
      return targetFile;
    } catch (e) {
      debugPrint('MediaCacheManager.seedCacheFromFile error: $e');
      return null;
    }
  }

  /// Deletes a specific media file from disk cache and memory, returning freed bytes
  Future<int> deleteMedia(String url) async {
    final resolvedUrl = AppConfig.resolveMediaUrl(url) ?? url;
    cancelDownload(url);
    if (resolvedUrl != url) cancelDownload(resolvedUrl);
    _localPathCache.remove(url);
    _localPathCache.remove(resolvedUrl);
    _progressNotifiers.remove(url);
    _progressNotifiers.remove(resolvedUrl);
    _byteProgressNotifiers.remove(url);
    _byteProgressNotifiers.remove(resolvedUrl);
    if (kIsWeb) return 0;

    int freedBytes = 0;
    final filename = getCacheFilename(url);
    final resolvedFilename = getCacheFilename(resolvedUrl);
    final legacySanitized = url.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final filenamesToCheck = {filename, resolvedFilename, legacySanitized};

    for (final name in filenamesToCheck) {
      try {
        final cacheDir = await getApplicationCacheDirectory();
        final f1 = File(path.join(cacheDir.path, 'theaver_media', name));
        if (await f1.exists()) {
          freedBytes += await f1.length();
          await f1.delete();
        }
        final tmp1 = File(path.join(cacheDir.path, 'theaver_media', '$name.tmp'));
        if (await tmp1.exists()) {
          freedBytes += await tmp1.length();
          await tmp1.delete();
        }
      } catch (_) {}
    }
    return freedBytes;
  }

  /// Evicts a specific media file from disk cache and memory (alias for deleteMedia)
  Future<void> evict(String url) => deleteMedia(url);

  /// Computes the total size in bytes of downloaded media files in cache
  Future<int> getCacheSizeBytes() async {
    if (kIsWeb) return 0;
    int total = 0;
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final mediaCacheDir = Directory(path.join(cacheDir.path, 'theaver_media'));
      if (await mediaCacheDir.exists()) {
        await for (final entity in mediaCacheDir.list(recursive: true)) {
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
    void Function(DownloadByteProgress progress)? onByteProgress, {
    bool isFinalized = false,
  }) {
    final double fraction = isFinalized
        ? 1.0
        : (total > 0 ? (received / total).clamp(0.0, 0.99) : 0.0);
    final prog = DownloadByteProgress(
      receivedBytes: received,
      totalBytes: total,
      fraction: fraction,
    );

    final resolvedUrl = AppConfig.resolveMediaUrl(url) ?? url;

    final pNotifier = _progressNotifiers[url];
    if (pNotifier != null) pNotifier.value = fraction;
    if (resolvedUrl != url) {
      _progressNotifiers[resolvedUrl]?.value = fraction;
    }

    final bNotifier = _byteProgressNotifiers[url];
    if (bNotifier != null) bNotifier.value = prog;
    if (resolvedUrl != url) {
      _byteProgressNotifiers[resolvedUrl]?.value = prog;
    }

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

  /// Download a media file to local cache with HTTP Range resume, deduplicated
  /// in-flight futures, automatic private-bucket fallback, and byte progress.
  Future<File?> downloadMedia(
    String url, {
    void Function(double progress)? onProgress,
    void Function(DownloadByteProgress progress)? onByteProgress,
    int? expectedTotalSize,
  }) async {
    if (kIsWeb || url.isEmpty) return null;

    final resolvedUrl = AppConfig.resolveMediaUrl(url) ?? url;
    _userCancelledUrls.remove(url);
    _userCancelledUrls.remove(resolvedUrl);

    final existing = await getCachedFile(url);
    if (existing != null) {
      final len = await existing.length();
      _emitProgress(url, len, len, onProgress, onByteProgress, isFinalized: true);
      return existing;
    }

    final existingFuture = _inFlightDownloads[resolvedUrl];
    if (existingFuture != null) {
      if (onProgress == null && onByteProgress == null) {
        return existingFuture;
      }
      final notifier = getByteProgressNotifier(url);
      void forwardProgress() {
        onProgress?.call(notifier.value.fraction);
        onByteProgress?.call(notifier.value);
      }

      notifier.addListener(forwardProgress);
      try {
        return await existingFuture;
      } finally {
        notifier.removeListener(forwardProgress);
      }
    }

    final Future<File?> downloadFuture = _downloadMediaInternal(
      url: url,
      resolvedUrl: resolvedUrl,
      onProgress: onProgress,
      onByteProgress: onByteProgress,
      expectedTotalSize: expectedTotalSize,
    );
    _inFlightDownloads[resolvedUrl] = downloadFuture;
    try {
      return await downloadFuture;
    } finally {
      if (identical(_inFlightDownloads[resolvedUrl], downloadFuture)) {
        _inFlightDownloads.remove(resolvedUrl);
      }
    }
  }

  Future<File?> _downloadMediaInternal({
    required String url,
    required String resolvedUrl,
    void Function(double progress)? onProgress,
    void Function(DownloadByteProgress progress)? onByteProgress,
    int? expectedTotalSize,
  }) async {
    final cancelToken = CancelToken();
    _cancelTokens[url] = cancelToken;
    if (resolvedUrl != url) {
      _cancelTokens[resolvedUrl] = cancelToken;
    }

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

      final parsedUri = Uri.tryParse(resolvedUrl);
      final protectedObj = extractProtectedObjectName(resolvedUrl);

      // Prefer authenticated `/api/files/download/<objectName>` when the target is
      // inside a protected MinIO bucket so we don't waste a guaranteed 403 round-trip.
      String requestUrl = resolvedUrl;
      bool shouldAttachAuth = false;
      if (parsedUri != null) {
        final pathLower = parsedUri.path.toLowerCase();
        if (protectedObj != null && !pathLower.contains('/api/files/download/')) {
          final token = await AuthService.getToken();
          if (token != null && token.isNotEmpty) {
            requestUrl = '${AppConfig.baseUrl}/api/files/download/$protectedObj';
            shouldAttachAuth = true;
          }
        } else {
          final isMinIOStorage = parsedUri.port == 9000 ||
              parsedUri.host.contains('minio') ||
              parsedUri.host.startsWith('storage.') ||
              (AppConfig.storageUrl.isNotEmpty &&
                  parsedUri.host ==
                      (Uri.tryParse(AppConfig.storageUrl)?.host ?? ''));
          if (!isMinIOStorage && pathLower.contains('/api/')) {
            shouldAttachAuth = true;
          }
        }
      }

      final headers = <String, dynamic>{};
      if (shouldAttachAuth) {
        final token = await AuthService.getToken();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      }
      if (existingBytes > 0) {
        headers['Range'] = 'bytes=$existingBytes-';
      }

      Response<ResponseBody> response;
      try {
        response = await _dio.get<ResponseBody>(
          requestUrl,
          cancelToken: cancelToken,
          options: Options(
            headers: headers,
            responseType: ResponseType.stream,
          ),
        );
      } on DioException catch (dioErr) {
        final status = dioErr.response?.statusCode;
        // Private MinIO bucket returns 401/403 (or expired presign returns 403):
        // fallback to authenticated backend proxy.
        final fallbackObj = protectedObj ??
            extractProtectedObjectName(resolvedUrl, ignorePresignQuery: true);
        if ((status == 401 || status == 403) &&
            fallbackObj != null &&
            !requestUrl.contains('/api/files/download/')) {
          final token = await AuthService.getToken();
          if (token != null && token.isNotEmpty) {
            headers['Authorization'] = 'Bearer $token';
            requestUrl = '${AppConfig.baseUrl}/api/files/download/$fallbackObj';
            response = await _dio.get<ResponseBody>(
              requestUrl,
              cancelToken: cancelToken,
              options: Options(
                headers: headers,
                responseType: ResponseType.stream,
              ),
            );
          } else {
            rethrow;
          }
        } else if (status == 416 && headers.containsKey('Range')) {
          debugPrint('Media download 416 Range Not Satisfiable for $url, resetting .tmp file and retrying from 0');
          try {
            if (await tempFile.exists()) await tempFile.delete();
          } catch (_) {}
          headers.remove('Range');
          existingBytes = 0;
          response = await _dio.get<ResponseBody>(
            requestUrl,
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
          _localPathCache[resolvedUrl] = targetPath;
          _cancelTokens.remove(url);
          _cancelTokens.remove(resolvedUrl);
          _emitProgress(url, actualLength, actualLength, onProgress, onByteProgress, isFinalized: true);
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
      if (identical(_cancelTokens[url], cancelToken)) {
        _cancelTokens.remove(url);
      }
      if (resolvedUrl != url &&
          identical(_cancelTokens[resolvedUrl], cancelToken)) {
        _cancelTokens.remove(resolvedUrl);
      }
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

  static const MethodChannel _networkChannel =
      MethodChannel('app.theaver.messenger/network');
  String _cachedNetworkType = 'wifi';
  DateTime? _lastNetworkCheckTime;
  bool _isCheckingNetwork = false;

  void _refreshNetworkTypeIfNeeded() {
    if (kIsWeb) return;
    final now = DateTime.now();
    if (_isCheckingNetwork) return;
    if (_lastNetworkCheckTime != null &&
        now.difference(_lastNetworkCheckTime!).inSeconds < 10) {
      return;
    }
    _isCheckingNetwork = true;
    _lastNetworkCheckTime = now;
    Future.microtask(() async {
      try {
        if (Platform.isAndroid) {
          final result = await _networkChannel.invokeMethod<String>('getNetworkType');
          if (result != null && result.isNotEmpty) {
            _cachedNetworkType = result;
            return;
          }
        }
        // Fallback via NetworkInterface names (wlan/eth/en -> wifi, rmnet/ccmni/pdp -> cellular)
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.any,
        );
        bool hasWifi = false;
        bool hasCellular = false;
        for (final iface in interfaces) {
          final name = iface.name.toLowerCase();
          if (name.startsWith('wlan') ||
              name.startsWith('eth') ||
              name.startsWith('en') ||
              name.startsWith('wi-fi')) {
            hasWifi = true;
          } else if (name.startsWith('rmnet') ||
              name.startsWith('ccmni') ||
              name.startsWith('pdp') ||
              name.startsWith('wwan') ||
              name.startsWith('cell')) {
            hasCellular = true;
          }
        }
        if (hasWifi) {
          _cachedNetworkType = 'wifi';
        } else if (hasCellular) {
          _cachedNetworkType = 'cellular';
        }
      } catch (_) {
        // Keep previous cached network type
      } finally {
        _isCheckingNetwork = false;
      }
    });
  }

  /// Evaluates whether media should auto-download based on user Settings, real connectivity, and size limits
  bool shouldAutoDownload({
    required String messageType,
    int? fileSize,
    bool? isWifi,
  }) {
    _refreshNetworkTypeIfNeeded();
    final settings = SettingsService().storageSettings;
    final String netType = isWifi != null
        ? (isWifi ? 'wifi' : 'cellular')
        : _cachedNetworkType;
    if (netType == 'none') return false;

    final bool wifi = netType == 'wifi';
    final bool roaming = netType == 'roaming';
    final size = fileSize ?? 0;

    if (messageType == 'photo' || messageType == 'image') {
      final allowed = wifi
          ? settings.autoDownloadPhotosOnWifi
          : (roaming
              ? settings.autoDownloadPhotosOnRoaming
              : settings.autoDownloadPhotosOnCellular);
      if (!allowed) return false;
      return size <= 10 * 1024 * 1024;
    }

    if (messageType == 'video') {
      final allowed = wifi
          ? settings.autoDownloadVideosOnWifi
          : (roaming
              ? settings.autoDownloadVideosOnRoaming
              : settings.autoDownloadVideosOnCellular);
      if (!allowed) return false;
      return wifi ? size <= 15 * 1024 * 1024 : size <= 5 * 1024 * 1024;
    }

    if (messageType == 'file' || messageType == 'document') {
      final allowed = wifi
          ? settings.autoDownloadFilesOnWifi
          : (roaming
              ? settings.autoDownloadFilesOnRoaming
              : settings.autoDownloadFilesOnCellular);
      if (!allowed) return false;
      return size <= 3 * 1024 * 1024;
    }

    if (messageType == 'audio' || messageType == 'voice') {
      final allowed = wifi
          ? settings.autoDownloadAudioOnWifi
          : (roaming
              ? settings.autoDownloadAudioOnRoaming
              : settings.autoDownloadAudioOnCellular);
      if (!allowed) return false;
      return size <= 10 * 1024 * 1024;
    }

    return false;
  }
}
