import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../config/app_config.dart';

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
    final file = File(Uri.parse(url).toFilePath());
    if (file.existsSync()) return url;
  } else if (!kIsWeb && (url.contains(':\\') || url.contains(':/'))) {
    final file = File(url);
    if (file.existsSync()) return url;
  } else if (url.startsWith('/')) {
    if (!kIsWeb) {
      final file = File(url);
      if (file.existsSync()) return url;
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
    if (!kIsWeb) {
      // Fallback: check if local file path without scheme
      final file = File(url);
      if (file.existsSync()) return url;
    }
    return null;
  } catch (e) {
    if (!kIsWeb) {
      // Check if it's a valid local file path even if URI parsing failed
      try {
        final file = File(url);
        if (file.existsSync()) return url;
      } catch (_) {}
    }
    return null;
  }
}

final Map<String, MemoryImage> _dataUrlMemoryImageCache = {};

/// Creates an ImageProvider from an avatar URL or local file path.
/// Supports network URLs (http/https via CachedNetworkImageProvider with offline disk cache),
/// local file paths, and data: URLs (base64).
/// If the URL is invalid or empty, falls back to [localFallbackPath] if provided.
ImageProvider? avatarImageProvider(String? url, {String? localFallbackPath}) {
  if ((url == null || url.isEmpty) && (localFallbackPath == null || localFallbackPath.isEmpty)) {
    return null;
  }

  // If URL is missing, try fallback local path
  if (url == null || url.isEmpty) {
    if (!kIsWeb && localFallbackPath != null) {
      final f = File(localFallbackPath);
      if (f.existsSync()) return FileImage(f);
    }
    return null;
  }

  // Handle data: URLs (base64 encoded avatars stored in DB)
  if (url.startsWith('data:')) {
    final cached = _dataUrlMemoryImageCache[url];
    if (cached != null) return cached;
    try {
      final commaIndex = url.indexOf(',');
      if (commaIndex == -1) return null;
      final base64Str = url.substring(commaIndex + 1);
      final bytes = base64Decode(base64Str);
      final provider = MemoryImage(bytes);
      if (_dataUrlMemoryImageCache.length > 64) {
        _dataUrlMemoryImageCache.remove(_dataUrlMemoryImageCache.keys.first);
      }
      _dataUrlMemoryImageCache[url] = provider;
      return provider;
    } catch (_) {
      return null;
    }
  }

  // Handle local file paths or file:// URIs on non-Web platforms
  if (!kIsWeb) {
    if (url.startsWith('file://')) {
      try {
        final file = File(Uri.parse(url).toFilePath());
        if (file.existsSync()) return FileImage(file);
      } catch (_) {}
    }

    final localFile = File(url);
    if (localFile.existsSync()) {
      return FileImage(localFile);
    }
  }

  // Network URL or relative backend path
  final validUrl = getValidAvatarUrl(url);
  if (validUrl == null || (!validUrl.startsWith('http://') && !validUrl.startsWith('https://'))) {
    if (!kIsWeb && localFallbackPath != null) {
      final f = File(localFallbackPath);
      if (f.existsSync()) return FileImage(f);
    }
    return null;
  }

  return CachedNetworkImageProvider(
    validUrl,
    errorListener: (e) {
      debugPrint('[avatarImageProvider] Failed to load avatar ($validUrl): $e');
    },
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
  final provider = avatarImageProvider(avatarUrl, localFallbackPath: localFallbackPath);
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
