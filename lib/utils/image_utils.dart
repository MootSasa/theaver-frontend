import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../config/app_config.dart';

final Map<String, ({bool exists, int checkedAtMs})> _localFileExistsCache = {};
const int _kLocalFileExistsTtlMs = 5000;

/// Invalidates cached `File.existsSync()` lookups for local avatar paths.
void invalidateLocalAvatarCache([String? path]) {
  if (path != null && path.isNotEmpty) {
    _localFileExistsCache.remove(path);
  } else {
    _localFileExistsCache.clear();
  }
}

bool _localFileExistsCached(String filePath) {
  if (kIsWeb || filePath.isEmpty) return false;
  final now = DateTime.now().millisecondsSinceEpoch;
  final cached = _localFileExistsCache[filePath];
  if (cached != null && (now - cached.checkedAtMs) < _kLocalFileExistsTtlMs) {
    return cached.exists;
  }
  bool exists = false;
  try {
    exists = File(filePath).existsSync();
  } catch (_) {}
  if (_localFileExistsCache.length > 512) {
    _localFileExistsCache.clear();
  }
  _localFileExistsCache[filePath] = (exists: exists, checkedAtMs: now);
  return exists;
}

/// Validates and returns a valid avatar URL or local file path, or null if invalid
///
/// This function checks if the URL is a valid HTTP/HTTPS URL, data: URL, relative URL,
/// or local file path to prevent errors when loading images.
String? getValidAvatarUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  // data: URLs are valid (base64 encoded avatars)
  if (url.startsWith('data:')) return url;

  // Rewrite internal/local MinIO URLs (localhost:9000 / 127.0.0.1:9000 / minio:9000) to public storageUrl
  if (url.startsWith('http://localhost:9000') ||
      url.startsWith('http://127.0.0.1:9000') ||
      url.startsWith('http://minio:9000') ||
      url.startsWith('https://localhost:9000') ||
      url.startsWith('https://127.0.0.1:9000') ||
      url.startsWith('https://minio:9000')) {
    final base = AppConfig.storageUrl.replaceAll(RegExp(r'/+$'), '');
    final parsed = Uri.tryParse(url);
    if (parsed != null) {
      url = '$base${parsed.path}${parsed.hasQuery ? '?${parsed.query}' : ''}';
    }
  }
  
  // Local file path or file:// URI
  if (!kIsWeb && url.startsWith('file://')) {
    try {
      if (_localFileExistsCached(Uri.parse(url).toFilePath())) return url;
    } catch (_) {}
  } else if (!kIsWeb && (url.contains(':\\') || url.contains(':/'))) {
    if (_localFileExistsCached(url)) return url;
  } else if (url.startsWith('/')) {
    if (!kIsWeb && _localFileExistsCached(url)) {
      return url;
    }
    // Relative URL on storage or backend (e.g. /avatars/xyz.jpg or /api/...)
    final base = url.startsWith('/avatars/')
        ? AppConfig.storageUrl
        : AppConfig.baseUrl;
    final cleanBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$cleanBase$url';
  }
  
  try {
    final uri = Uri.parse(url);
    if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return url;
    }
    if (!kIsWeb && _localFileExistsCached(url)) {
      return url;
    }
    return null;
  } catch (e) {
    if (!kIsWeb && _localFileExistsCached(url)) {
      return url;
    }
    return null;
  }
}

final Map<String, MemoryImage> _dataUrlMemoryImageCache = {};

ImageProvider _maybeResizeAvatar(
  ImageProvider provider, {
  required int? maxDecodeDimension,
  required bool fullResolution,
}) {
  if (fullResolution || maxDecodeDimension == null || maxDecodeDimension <= 0) {
    return provider;
  }
  return ResizeImage(
    provider,
    width: maxDecodeDimension,
    height: maxDecodeDimension,
    policy: ResizeImagePolicy.fit,
  );
}

/// Creates a thumbnail [ImageProvider] from an avatar URL or local file path.
/// Uses [ResizeImagePolicy.fit] when [fullResolution] is false to cut VRAM usage
/// while preserving non-square photo aspect ratios without stretching.
ImageProvider? avatarImageProvider(
  String? url, {
  String? localFallbackPath,
  int? maxDecodeDimension = 200,
  bool fullResolution = false,
}) {
  if ((url == null || url.isEmpty) && (localFallbackPath == null || localFallbackPath.isEmpty)) {
    return null;
  }

  // If URL is missing, try fallback local path
  if (url == null || url.isEmpty) {
    if (!kIsWeb && localFallbackPath != null && _localFileExistsCached(localFallbackPath)) {
      return _maybeResizeAvatar(
        FileImage(File(localFallbackPath)),
        maxDecodeDimension: maxDecodeDimension,
        fullResolution: fullResolution,
      );
    }
    return null;
  }

  // Handle data: URLs (base64 encoded avatars stored in DB)
  if (url.startsWith('data:')) {
    var cached = _dataUrlMemoryImageCache[url];
    if (cached == null) {
      try {
        final commaIndex = url.indexOf(',');
        if (commaIndex == -1) return null;
        final base64Str = url.substring(commaIndex + 1);
        final bytes = base64Decode(base64Str);
        cached = MemoryImage(bytes);
        if (_dataUrlMemoryImageCache.length > 64) {
          _dataUrlMemoryImageCache.remove(_dataUrlMemoryImageCache.keys.first);
        }
        _dataUrlMemoryImageCache[url] = cached;
      } catch (_) {
        return null;
      }
    }
    return _maybeResizeAvatar(
      cached,
      maxDecodeDimension: maxDecodeDimension,
      fullResolution: fullResolution,
    );
  }

  // Handle local file paths or file:// URIs on non-Web platforms
  if (!kIsWeb) {
    if (url.startsWith('file://')) {
      try {
        final filePath = Uri.parse(url).toFilePath();
        if (_localFileExistsCached(filePath)) {
          return _maybeResizeAvatar(
            FileImage(File(filePath)),
            maxDecodeDimension: maxDecodeDimension,
            fullResolution: fullResolution,
          );
        }
      } catch (_) {}
    }

    if (_localFileExistsCached(url)) {
      return _maybeResizeAvatar(
        FileImage(File(url)),
        maxDecodeDimension: maxDecodeDimension,
        fullResolution: fullResolution,
      );
    }
  }

  // Network URL or relative backend path
  final validUrl = getValidAvatarUrl(url);
  if (validUrl == null || (!validUrl.startsWith('http://') && !validUrl.startsWith('https://'))) {
    if (!kIsWeb && localFallbackPath != null && _localFileExistsCached(localFallbackPath)) {
      return _maybeResizeAvatar(
        FileImage(File(localFallbackPath)),
        maxDecodeDimension: maxDecodeDimension,
        fullResolution: fullResolution,
      );
    }
    return null;
  }

  return _maybeResizeAvatar(
    CachedNetworkImageProvider(
      validUrl,
      errorListener: (e) {
        debugPrint('[avatarImageProvider] Failed to load avatar ($validUrl): $e');
      },
    ),
    maxDecodeDimension: maxDecodeDimension,
    fullResolution: fullResolution,
  );
}

/// Creates a full-resolution [ImageProvider] without thumbnail downscaling,
/// used for fullscreen photo inspection and expanded profile headers.
ImageProvider? avatarFullImageProvider(
  String? url, {
  String? localFallbackPath,
}) {
  return avatarImageProvider(
    url,
    localFallbackPath: localFallbackPath,
    fullResolution: true,
  );
}

/// Creates a CircleAvatar with proper error handling for avatar URLs and local file paths
/// 
/// If the URL is invalid or empty, displays initials instead
Widget buildAvatar({
  required String? avatarUrl,
  required String name,
  double radius = 20,
  Color backgroundColor = const Color(0xFF0088CC),
  String? localFallbackPath,
  Key? key,
}) {
  final provider = avatarImageProvider(
    avatarUrl,
    localFallbackPath: localFallbackPath,
    maxDecodeDimension: (radius * 6).round().clamp(120, 480),
  );
  return CircleAvatar(
    key: key,
    radius: radius,
    backgroundColor: backgroundColor,
    backgroundImage: provider,
    onBackgroundImageError: provider != null
        ? (exception, stackTrace) {
            debugPrint('[buildAvatar] Failed to render avatar ($avatarUrl): $exception');
          }
        : null,
    child: provider == null
        ? Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              color: Colors.white,
              fontSize: radius * 0.9,
              fontWeight: FontWeight.bold,
            ),
          )
        : null,
  );
}
