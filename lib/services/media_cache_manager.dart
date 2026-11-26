import 'dart:async';
import 'dart:convert';
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
  final Set<String> _pausedUrls = {};
  final Map<String, String> _aliasFilenames = {};
  String? _cachedMediaDirPath;
  String? _aliasesLoadedForDir;

  static const Set<String> _publicBuckets = {'releases', 'stickers'};
  static const Set<String> _volatilePresignQueryParams = {
    'mt',
    'x-amz-algorithm',
    'x-amz-credential',
    'x-amz-date',
    'x-amz-expires',
    'x-amz-signedheaders',
    'x-amz-signature',
    'x-amz-security-token',
    'awsaccesskeyid',
    'signature',
    'expires',
  };

  static bool _isStorageUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final storageHost = Uri.tryParse(AppConfig.storageUrl)?.host.toLowerCase() ?? '';
    return uri.port == 8333 ||
        uri.port == 9000 ||
        host.contains('seaweedfs') ||
        host.contains('minio') ||
        host.startsWith('storage.') ||
        (storageHost.isNotEmpty && host == storageHost);
  }

  /// Extracts a storage object key when [rawOrResolvedUrl] points to the private
  /// `media` bucket (or `/api/files/download/<objectName>`). Returns `null` for
  /// public buckets (`releases`, `stickers`), `avatars` (served via
  /// `/api/files/avatar/`), already-presigned URLs, and external hosts.
  String? extractProtectedObjectName(
    String rawOrResolvedUrl, {
    bool ignorePresignQuery = false,
  }) {
    final trimmed = rawOrResolvedUrl.trim();
    if (trimmed.isEmpty || AppConfig.isLocalFilePath(trimmed)) return null;
    final resolved = AppConfig.resolveMediaUrl(trimmed) ?? trimmed;
    final uri = Uri.tryParse(resolved);
    if (uri == null) return null;

    // Already a presigned S3 URL — must not strip query signature unless
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

    if (!_isStorageUri(uri)) return null;

    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length < 2) return null;
    final bucket = segs.first.toLowerCase();
    if (_publicBuckets.contains(bucket) || bucket == 'avatars') return null;
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

  /// Canonicalizes storage/API/presigned/relative URLs and local file paths
  /// into a single deterministic cache key so identical objects share one entry.
  String canonicalCacheKey(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    final hashIdx = trimmed.indexOf('#');
    final noFrag = hashIdx != -1 ? trimmed.substring(0, hashIdx) : trimmed;
    if (AppConfig.isLocalFilePath(noFrag)) {
      String filePath = noFrag;
      if (noFrag.startsWith('file://')) {
        try {
          filePath = Uri.parse(noFrag).toFilePath();
        } catch (_) {}
      }
      return 'local:${path.normalize(filePath)}';
    }
    final protectedObj = extractProtectedObjectName(
      noFrag,
      ignorePresignQuery: true,
    );
    if (protectedObj != null && protectedObj.isNotEmpty) {
      return 'obj:$protectedObj';
    }
    final resolved = AppConfig.resolveMediaUrl(noFrag) ?? noFrag;
    final uri = Uri.tryParse(resolved);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final Map<String, List<String>> filtered = <String, List<String>>{};
      uri.queryParametersAll.forEach((k, values) {
        if (!_volatilePresignQueryParams.contains(k.toLowerCase())) {
          filtered[k] = values;
        }
      });
      final cleanUri = Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
        queryParameters: filtered.isEmpty ? null : filtered,
      );
      return 'url:${cleanUri.toString()}';
    }
    return 'raw:$resolved';
  }

  String _fnv1aHex(String input) {
    int hash = 0x811c9dc5;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  void _loadAliasesSyncIfNeeded(String dirPath) {
    if (_aliasesLoadedForDir == dirPath) return;
    _aliasesLoadedForDir = dirPath;
    try {
      final aliasFile = File(path.join(dirPath, 'local_aliases.json'));
      if (!aliasFile.existsSync()) return;
      final decoded = jsonDecode(aliasFile.readAsStringSync());
      if (decoded is Map) {
        decoded.forEach((k, v) {
          final keyStr = k.toString();
          final valStr = v?.toString() ?? '';
          if (keyStr.isNotEmpty && valStr.isNotEmpty) {
            _aliasFilenames.putIfAbsent(keyStr, () => valStr);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveAliases(String dirPath) async {
    try {
      final aliasFile = File(path.join(dirPath, 'local_aliases.json'));
      if (_aliasFilenames.isEmpty) {
        if (await aliasFile.exists()) {
          await aliasFile.delete();
        }
        return;
      }
      await aliasFile.writeAsString(jsonEncode(_aliasFilenames), flush: false);
    } catch (_) {}
  }

  /// Fetches and disk-caches remote thumbnail bytes (with automatic private-bucket
  /// `/api/files/download/...` fallback on 401/403).
  Future<Uint8List?> fetchThumbnailBytes(String rawOrResolvedUrl) async {
    if (kIsWeb || rawOrResolvedUrl.isEmpty) return null;
    final resolved = AppConfig.resolveMediaUrl(rawOrResolvedUrl) ?? rawOrResolvedUrl;
    final mem = getCachedVideoThumbnailSync(resolved);
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

  /// Synchronously returns a cached [File] if its local path is known in memory
  /// or present inside the already-discovered media cache directory.
  /// Prevents a 1-frame placeholder flash when cloning media bubbles or replacing
  /// optimistic outgoing messages with server messages.
  File? getCachedFileSync(String url) {
    if (kIsWeb || url.isEmpty) return null;
    final resolvedUrl = AppConfig.resolveMediaUrl(url) ?? url;
    final key = canonicalCacheKey(url);
    final cachedPath = _localPathCache[key] ??
        _localPathCache[url] ??
        _localPathCache[resolvedUrl];
    if (cachedPath != null) {
      final f = File(cachedPath);
      if (f.existsSync() && f.lengthSync() > 0) {
        if (key.isNotEmpty) _localPathCache[key] = f.path;
        return f;
      }
      if (key.isNotEmpty) _localPathCache.remove(key);
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
          if (key.isNotEmpty) _localPathCache[key] = filePath;
          _localPathCache[url] = filePath;
          return directFile;
        }
      } catch (_) {}
    }

    final mediaDirPath = _cachedMediaDirPath;
    if (mediaDirPath != null) {
      _loadAliasesSyncIfNeeded(mediaDirPath);
      for (final fname in _candidateCacheFilenames(url)) {
        try {
          final targetPath = path.join(mediaDirPath, fname);
          final f = File(targetPath);
          if (f.existsSync() && f.lengthSync() > 0) {
            if (key.isNotEmpty) _localPathCache[key] = targetPath;
            _localPathCache[url] = targetPath;
            _localPathCache[resolvedUrl] = targetPath;
            return f;
          }
        } catch (_) {}
      }
    }
    return null;
  }

  /// Synchronously returns a cached video first-frame thumbnail if already extracted.
  Uint8List? getCachedVideoThumbnailSync(String filePath) {
    if (filePath.isEmpty) return null;
    final exact = _videoThumbnailCache[filePath];
    if (exact != null) return exact;
    final key = canonicalCacheKey(filePath);
    return key.isNotEmpty ? _videoThumbnailCache[key] : null;
  }

  /// Caches an extracted video first-frame thumbnail in memory.
  void cacheVideoThumbnail(String filePath, Uint8List bytes) {
    if (filePath.isEmpty || bytes.isEmpty) return;
    if (_videoThumbnailCache.length >= 240) {
      _videoThumbnailCache.remove(_videoThumbnailCache.keys.first);
    }
    _videoThumbnailCache[filePath] = bytes;
    final key = canonicalCacheKey(filePath);
    if (key.isNotEmpty) {
      _videoThumbnailCache[key] = bytes;
    }
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
    final key = canonicalCacheKey(url);
    return _progressNotifiers.putIfAbsent(
      key,
      () => ValueNotifier<double>(0.0),
    );
  }

  /// Get or create a ValueNotifier for tracking byte download progress of a URL
  ValueNotifier<DownloadByteProgress> getByteProgressNotifier(String url) {
    final key = canonicalCacheKey(url);
    return _byteProgressNotifiers.putIfAbsent(
      key,
      () => ValueNotifier<DownloadByteProgress>(const DownloadByteProgress()),
    );
  }

  bool isDownloading(String url) {
    final key = canonicalCacheKey(url);
    if (key.isEmpty) return false;
    return _cancelTokens.containsKey(key) ||
        _inFlightDownloads.containsKey(key);
  }

  bool wasCancelledByUser(String url) {
    final key = canonicalCacheKey(url);
    return key.isNotEmpty && _userCancelledUrls.contains(key);
  }

  bool wasDownloadPaused(String url) {
    final key = canonicalCacheKey(url);
    return key.isNotEmpty && _pausedUrls.contains(key);
  }

  /// Cancel or pause an ongoing download without deleting the partial file or resetting progress
  void cancelDownload(String url, {bool byUser = true}) {
    final key = canonicalCacheKey(url);
    if (key.isEmpty) return;
    if (byUser) {
      _userCancelledUrls.add(key);
      _pausedUrls.remove(key);
    } else {
      _pausedUrls.add(key);
    }
    final token = _cancelTokens.remove(key);
    if (token != null && !token.isCancelled) {
      token.cancel(byUser ? 'User cancelled' : 'Download paused');
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
    _cachedMediaDirPath = dir.path;
    _loadAliasesSyncIfNeeded(dir.path);
    return dir;
  }

  String _legacyCacheFilename(String url) {
    final uri = Uri.tryParse(url);
    final ext = uri != null ? path.extension(uri.path) : '';
    final sanitized = url.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (ext.isNotEmpty && !sanitized.endsWith(ext)) {
      return '$sanitized$ext';
    }
    return sanitized;
  }

  /// Generates a sanitized canonical cache filename while preserving media file extension
  String getCacheFilename(String url) {
    final key = canonicalCacheKey(url);
    if (key.isEmpty) return '';
    final resolved = AppConfig.resolveMediaUrl(url) ?? url;
    final uri = Uri.tryParse(resolved);
    final String extPath = key.startsWith('obj:')
        ? key.substring(4)
        : (uri != null ? uri.path : resolved);
    final ext = path.extension(extPath);
    String sanitized = key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (sanitized.length > 180) {
      sanitized =
          '${sanitized.substring(0, 90)}_${_fnv1aHex(key)}_${sanitized.substring(sanitized.length - 60)}';
    }
    if (ext.isNotEmpty && !sanitized.endsWith(ext)) {
      return '$sanitized$ext';
    }
    return sanitized;
  }

  List<String> _candidateCacheFilenames(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return const <String>[];
    final key = canonicalCacheKey(trimmed);
    final resolved = AppConfig.resolveMediaUrl(trimmed) ?? trimmed;
    final candidates = <String>{};
    final alias = _aliasFilenames[key];
    if (alias != null && alias.isNotEmpty) {
      candidates.add(alias);
    }
    final canonical = getCacheFilename(trimmed);
    if (canonical.isNotEmpty) {
      candidates.add(canonical);
    }
    final legacyResolved = _legacyCacheFilename(resolved);
    if (legacyResolved.isNotEmpty) {
      candidates.add(legacyResolved);
    }
    final legacyRaw = _legacyCacheFilename(trimmed);
    if (legacyRaw.isNotEmpty) {
      candidates.add(legacyRaw);
    }
    final bareSanitized = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (bareSanitized.isNotEmpty) {
      candidates.add(bareSanitized);
    }
    return candidates.toList(growable: false);
  }

  /// Checks if the file is cached locally on disk and exists
  Future<File?> getCachedFile(String url) async {
    if (kIsWeb || url.isEmpty) return null;

    // Support direct local file paths (e.g., pending outgoing media before upload completes)
    final key = canonicalCacheKey(url);
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
          if (key.isNotEmpty) _localPathCache[key] = filePath;
          _localPathCache[url] = filePath;
          return directFile;
        }
      } catch (_) {}
    }

    final resolvedUrl = AppConfig.resolveMediaUrl(url) ?? url;
    final cachedPath = _localPathCache[key] ??
        _localPathCache[url] ??
        _localPathCache[resolvedUrl];
    if (cachedPath != null) {
      final f = File(cachedPath);
      if (await f.exists()) {
        try {
          if (await f.length() > 0) {
            if (key.isNotEmpty) _localPathCache[key] = f.path;
            return f;
          } else {
            await f.delete();
            if (key.isNotEmpty) _localPathCache.remove(key);
            _localPathCache.remove(url);
            _localPathCache.remove(resolvedUrl);
          }
        } catch (_) {}
      } else {
        if (key.isNotEmpty) _localPathCache.remove(key);
        _localPathCache.remove(url);
        _localPathCache.remove(resolvedUrl);
      }
    }

    final mediaDir = await getMediaCacheDirectory();
    final filenamesToCheck = _candidateCacheFilenames(url);

    for (final fname in filenamesToCheck) {
      // Check primary app-private cache directory
      try {
        final targetPath = path.join(mediaDir.path, fname);
        final f = File(targetPath);
        if (await f.exists()) {
          if (await f.length() > 0) {
            if (key.isNotEmpty) _localPathCache[key] = targetPath;
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
    final key = canonicalCacheKey(url);
    final mediaDir = await getMediaCacheDirectory();
    final filenamesToCheck = _candidateCacheFilenames(url);

    for (final fname in filenamesToCheck) {
      try {
        final tempPath = path.join(mediaDir.path, '$fname.tmp');
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
            _byteProgressNotifiers[key]?.value = prog;
            _progressNotifiers[key]?.value = fraction;
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
    _videoThumbnailCache.clear();
    _progressNotifiers.clear();
    _byteProgressNotifiers.clear();
    _userCancelledUrls.clear();
    _pausedUrls.clear();
    _aliasFilenames.clear();
    _cachedMediaDirPath = null;
    _aliasesLoadedForDir = null;
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
  /// or compressed/uploaded media), avoiding re-downloading our own sent media and cleaning up temp files.
  Future<File?> seedCacheFromFile(
    String remoteUrl,
    File sourceFile, {
    bool deleteSourceIfTemp = true,
    bool preserveSourceExtension = false,
  }) async {
    if (kIsWeb || remoteUrl.isEmpty) return null;
    try {
      if (!await sourceFile.exists()) return null;
      final len = await sourceFile.length();
      if (len <= 0) return null;

      final mediaDir = await getMediaCacheDirectory();
      final key = canonicalCacheKey(remoteUrl);
      final resolvedUrl = AppConfig.resolveMediaUrl(remoteUrl) ?? remoteUrl;
      final baseFilename = getCacheFilename(remoteUrl);
      String targetFilename = baseFilename;
      bool usedAlias = false;
      if (preserveSourceExtension) {
        final srcExt = path.extension(sourceFile.path).toLowerCase();
        final dstExt = path.extension(baseFilename).toLowerCase();
        if (srcExt.isNotEmpty && srcExt != dstExt) {
          targetFilename = '${path.basenameWithoutExtension(baseFilename)}$srcExt';
          usedAlias = true;
        }
      }
      final targetPath = path.join(mediaDir.path, targetFilename);
      final targetFile = File(targetPath);

      if (path.canonicalize(sourceFile.path) != path.canonicalize(targetPath)) {
        final seedTempPath = '$targetPath.seed_tmp';
        final seedTempFile = File(seedTempPath);
        if (await seedTempFile.exists()) {
          await seedTempFile.delete();
        }
        await sourceFile.copy(seedTempPath);
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await seedTempFile.rename(targetPath);

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

      if (usedAlias) {
        _aliasFilenames[key] = targetFilename;
        await _saveAliases(mediaDir.path);
      } else if (_aliasFilenames.remove(key) != null) {
        await _saveAliases(mediaDir.path);
      }

      if (key.isNotEmpty) _localPathCache[key] = targetPath;
      _localPathCache[remoteUrl] = targetPath;
      _localPathCache[resolvedUrl] = targetPath;

      final existingThumb = getCachedVideoThumbnailSync(sourceFile.path);
      if (existingThumb != null && existingThumb.isNotEmpty) {
        _videoThumbnailCache[targetPath] = existingThumb;
        if (key.isNotEmpty) {
          _videoThumbnailCache[key] = existingThumb;
        }
      }
      return targetFile;
    } catch (e) {
      debugPrint('MediaCacheManager.seedCacheFromFile error: $e');
      return null;
    }
  }

  /// Deletes a specific media file from disk cache and memory, returning freed bytes
  Future<int> deleteMedia(String url) async {
    final key = canonicalCacheKey(url);
    final resolvedUrl = AppConfig.resolveMediaUrl(url) ?? url;
    cancelDownload(url, byUser: false);
    if (key.isNotEmpty) {
      _localPathCache.remove(key);
      _progressNotifiers.remove(key);
      _byteProgressNotifiers.remove(key);
    }
    _localPathCache.remove(url);
    _localPathCache.remove(resolvedUrl);
    _progressNotifiers.remove(url);
    _progressNotifiers.remove(resolvedUrl);
    _byteProgressNotifiers.remove(url);
    _byteProgressNotifiers.remove(resolvedUrl);
    if (kIsWeb) return 0;

    int freedBytes = 0;
    final mediaDir = await getMediaCacheDirectory();
    final filenamesToCheck = _candidateCacheFilenames(url);
    if (_aliasFilenames.remove(key) != null) {
      await _saveAliases(mediaDir.path);
    }

    for (final name in filenamesToCheck) {
      try {
        final f1 = File(path.join(mediaDir.path, name));
        if (await f1.exists()) {
          freedBytes += await f1.length();
          await f1.delete();
        }
        final tmp1 = File(path.join(mediaDir.path, '$name.tmp'));
        if (await tmp1.exists()) {
          freedBytes += await tmp1.length();
          await tmp1.delete();
        }
        final seedTmp = File(path.join(mediaDir.path, '$name.seed_tmp'));
        if (await seedTmp.exists()) {
          freedBytes += await seedTmp.length();
          await seedTmp.delete();
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

    final key = canonicalCacheKey(url);
    _progressNotifiers[key]?.value = fraction;
    _byteProgressNotifiers[key]?.value = prog;

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
    final key = canonicalCacheKey(url);
    _userCancelledUrls.remove(key);
    _pausedUrls.remove(key);

    final existing = await getCachedFile(url);
    if (existing != null) {
      final len = await existing.length();
      _emitProgress(url, len, len, onProgress, onByteProgress, isFinalized: true);
      return existing;
    }

    final existingFuture = _inFlightDownloads[key];
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
      key: key,
      url: url,
      resolvedUrl: resolvedUrl,
      onProgress: onProgress,
      onByteProgress: onByteProgress,
      expectedTotalSize: expectedTotalSize,
    );
    _inFlightDownloads[key] = downloadFuture;
    try {
      return await downloadFuture;
    } finally {
      if (identical(_inFlightDownloads[key], downloadFuture)) {
        _inFlightDownloads.remove(key);
      }
    }
  }

  Future<File?> _downloadMediaInternal({
    required String key,
    required String url,
    required String resolvedUrl,
    void Function(double progress)? onProgress,
    void Function(DownloadByteProgress progress)? onByteProgress,
    int? expectedTotalSize,
  }) async {
    final cancelToken = CancelToken();
    _cancelTokens[key] = cancelToken;

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

      // Prefer authenticated `/api/files/download/<objectName>` (or `/api/files/avatar/<objectName>`)
      // when the target is inside a protected S3 bucket so we don't waste a guaranteed 403 round-trip.
      String requestUrl = resolvedUrl;
      bool shouldAttachAuth = false;
      if (parsedUri != null) {
        final pathLower = parsedUri.path.toLowerCase();
        final isPresigned = parsedUri.queryParameters.containsKey('X-Amz-Signature') ||
            parsedUri.queryParameters.containsKey('x-amz-signature');
        if (protectedObj != null && !pathLower.contains('/api/files/download/')) {
          final token = await AuthService.getToken();
          if (token != null && token.isNotEmpty) {
            requestUrl = '${AppConfig.baseUrl}/api/files/download/$protectedObj';
            shouldAttachAuth = true;
          }
        } else if (!isPresigned &&
            _isStorageUri(parsedUri) &&
            parsedUri.path.startsWith('/avatars/') &&
            parsedUri.path.length > '/avatars/'.length) {
          final avatarObj = parsedUri.path.substring('/avatars/'.length);
          final apiBase = AppConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
          requestUrl = '$apiBase/api/files/avatar/$avatarObj';
          shouldAttachAuth = true;
        } else {
          final isStorage = _isStorageUri(parsedUri);
          if (!isStorage && !isPresigned && pathLower.contains('/api/')) {
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
          final oldAlias = _aliasFilenames.remove(key);
          if (oldAlias != null && oldAlias != filename) {
            try {
              final oldAliasFile = File(path.join(mediaDir.path, oldAlias));
              if (await oldAliasFile.exists()) {
                await oldAliasFile.delete();
              }
            } catch (_) {}
            await _saveAliases(mediaDir.path);
          } else if (oldAlias != null) {
            await _saveAliases(mediaDir.path);
          }
          if (key.isNotEmpty) _localPathCache[key] = targetPath;
          _localPathCache[url] = targetPath;
          _localPathCache[resolvedUrl] = targetPath;
          if (identical(_cancelTokens[key], cancelToken)) {
            _cancelTokens.remove(key);
          }
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
      if (identical(_cancelTokens[key], cancelToken)) {
        _cancelTokens.remove(key);
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
    final int size = fileSize ?? 0;

    if (messageType == 'photo' || messageType == 'image') {
      final allowed = wifi
          ? settings.autoDownloadPhotosOnWifi
          : (roaming
              ? settings.autoDownloadPhotosOnRoaming
              : settings.autoDownloadPhotosOnCellular);
      if (!allowed) return false;
      return fileSize == null || size <= 0 || size <= 10 * 1024 * 1024;
    }

    if (messageType == 'video') {
      final allowed = wifi
          ? settings.autoDownloadVideosOnWifi
          : (roaming
              ? settings.autoDownloadVideosOnRoaming
              : settings.autoDownloadVideosOnCellular);
      if (!allowed) return false;
      if (fileSize == null || size <= 0) return false;
      return wifi ? size <= 15 * 1024 * 1024 : size <= 5 * 1024 * 1024;
    }

    if (messageType == 'file' || messageType == 'document') {
      final allowed = wifi
          ? settings.autoDownloadFilesOnWifi
          : (roaming
              ? settings.autoDownloadFilesOnRoaming
              : settings.autoDownloadFilesOnCellular);
      if (!allowed) return false;
      if (fileSize == null || size <= 0) return false;
      return size <= 3 * 1024 * 1024;
    }

    if (messageType == 'voice') {
      final allowed = wifi
          ? settings.autoDownloadAudioOnWifi
          : (roaming
              ? settings.autoDownloadAudioOnRoaming
              : settings.autoDownloadAudioOnCellular);
      if (!allowed) return false;
      return fileSize == null || size <= 0 || size <= 10 * 1024 * 1024;
    }

    if (messageType == 'audio') {
      final allowed = wifi
          ? settings.autoDownloadAudioOnWifi
          : (roaming
              ? settings.autoDownloadAudioOnRoaming
              : settings.autoDownloadAudioOnCellular);
      if (!allowed) return false;
      if (fileSize == null || size <= 0) return false;
      return size <= 10 * 1024 * 1024;
    }

    return false;
  }
}
