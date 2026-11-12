import 'dart:convert';
import 'dart:io' show File;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../../utils/image_utils.dart';

/// Downloads (or returns a cached copy of) an image for use in notifications.
/// Returns a local file path or null. Never throws.
Future<String?> downloadOrGetCachedImage(String? url, {String prefix = 'notif_img'}) async {
  if (kIsWeb || url == null || url.isEmpty) return null;
  try {
    // 1. Data URLs (Base64 avatar string from backend/database)
    if (url.startsWith('data:')) {
      final commaIndex = url.indexOf(',');
      if (commaIndex == -1) return null;
      final bytes = base64Decode(url.substring(commaIndex + 1));
      final tempDir = await getTemporaryDirectory();
      final cachedFile = File('${tempDir.path}/${prefix}_${url.hashCode.abs()}.png');
      await cachedFile.writeAsBytes(bytes, flush: true);
      return cachedFile.path;
    }

    // 2. Local file paths or file:// URIs
    if (url.startsWith('file://')) {
      final f = File(Uri.parse(url).toFilePath());
      if (await f.exists()) return f.path;
    }
    if (!url.startsWith('http')) {
      final directFile = File(url);
      if (await directFile.exists()) return directFile.path;
    }

    // 3. Resolve relative paths / domain fixes
    final validUrl = getValidAvatarUrl(url);
    if (validUrl == null) return null;
    if (!validUrl.startsWith('http://') && !validUrl.startsWith('https://')) {
      final f = File(validUrl);
      return await f.exists() ? f.path : null;
    }

    // 4. Image cache populated by CachedNetworkImage
    try {
      final fileInfo = await DefaultCacheManager().getFileFromCache(validUrl);
      if (fileInfo != null && await fileInfo.file.exists() && (await fileInfo.file.length()) > 0) {
        return fileInfo.file.path;
      }
    } catch (_) {}

    // 5. Our own temp cache
    final tempDir = await getTemporaryDirectory();
    final cachedFile = File('${tempDir.path}/${prefix}_${validUrl.hashCode.abs()}.png');
    if (await cachedFile.exists() && (await cachedFile.length()) > 0) {
      return cachedFile.path;
    }

    // 6. Download
    final response = await Dio().get<List<int>>(
      validUrl,
      options: Options(
        responseType: ResponseType.bytes,
        sendTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
      ),
    );
    if (response.statusCode == 200 && response.data != null && response.data!.isNotEmpty) {
      await cachedFile.writeAsBytes(response.data!, flush: true);
      return cachedFile.path;
    }
  } catch (e) {
    debugPrint('Notifications: image download warning: $e');
  }
  return null;
}

/// Avatar variant of [downloadOrGetCachedImage].
Future<String?> downloadOrGetCachedAvatar(String? url) =>
    downloadOrGetCachedImage(url, prefix: 'notif_avatar');
