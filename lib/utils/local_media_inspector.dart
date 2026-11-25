import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/media_cache_manager.dart';

/// Metadata and permanent local outbox copy for an outgoing media/document item.
class OutboxStagedFile {
  final File file;
  final String fileName;
  final int fileSize;
  final String messageType; // 'image' | 'video' | 'gif' | 'file'
  final String mimeType;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final Uint8List? thumbnailBytes;

  const OutboxStagedFile({
    required this.file,
    required this.fileName,
    required this.fileSize,
    required this.messageType,
    required this.mimeType,
    this.width,
    this.height,
    this.durationSeconds,
    this.thumbnailBytes,
  });
}

/// Copies outgoing media/files to a dedicated outbox directory and extracts
/// dimensions, duration, and first-frame video thumbnails before upload begins.
class LocalMediaInspector {
  LocalMediaInspector._();

  static const Duration _probeTimeout = Duration(seconds: 2);
  static const int _maxInMemoryCodecBytes = 20 * 1024 * 1024;
  static const MethodChannel _muxerChannel = MethodChannel(
    'com.example.app/media_muxer',
  );

  static const Set<String> _videoExtensions = {
    '.mp4',
    '.mov',
    '.mkv',
    '.webm',
    '.avi',
    '.3gp',
    '.m4v',
  };

  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
    '.heif',
    '.bmp',
  };

  /// Returns `true` when [path] lives inside the app-owned outbox staging area.
  static bool isOutboxFilePath(String? path) {
    if (path == null || path.isEmpty) return false;
    final normalized = path.replaceAll('\\', '/');
    return normalized.contains('/outbox_files/') ||
        normalized.contains('/theaver_outbox/');
  }

  /// Removes a previously staged temporary outbox copy without touching user files.
  static Future<void> cleanupStagedFile(String? path) async {
    if (!isOutboxFilePath(path)) return;
    try {
      final f = File(path!);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }

  /// Stages [source] under an outbox directory keyed by [localId] and inspects
  /// basic media properties so the optimistic bubble renders accurate geometry
  /// on frame 0 without waiting for network upload.
  static Future<OutboxStagedFile> stageAndInspect(
    File source, {
    required String localId,
    required bool asDocument,
    bool preferVideo = false,
  }) async {
    final rawName = p.basename(source.path);
    final fileName = rawName.isNotEmpty ? rawName : 'file_$localId';
    final ext = p.extension(fileName).toLowerCase();

    final String messageType;
    if (asDocument) {
      messageType = 'file';
    } else if (preferVideo || _videoExtensions.contains(ext)) {
      messageType = 'video';
    } else if (ext == '.gif') {
      messageType = 'gif';
    } else if (_imageExtensions.contains(ext)) {
      messageType = 'image';
    } else {
      messageType = 'file';
    }

    final String mimeType = _inferMimeType(ext, messageType);
    final File stagedFile = await _stageCopy(source, localId, fileName);

    int fileSize = 0;
    try {
      if (await stagedFile.exists()) {
        fileSize = await stagedFile.length();
      } else if (await source.exists()) {
        fileSize = await source.length();
      }
    } catch (_) {}

    int? width;
    int? height;
    int? durationSeconds;
    Uint8List? thumbnailBytes;

    if (!kIsWeb && (messageType == 'image' || messageType == 'gif')) {
      final dims = await _probeImageDimensions(
        stagedFile,
        fileSize: fileSize,
      );
      width = dims?.$1;
      height = dims?.$2;
    } else if (!kIsWeb && messageType == 'video') {
      final videoMeta = await _probeVideo(stagedFile);
      width = videoMeta.$1;
      height = videoMeta.$2;
      durationSeconds = videoMeta.$3;
      thumbnailBytes = videoMeta.$4;
      if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
        MediaCacheManager.instance.cacheVideoThumbnail(
          stagedFile.path,
          thumbnailBytes,
        );
      }
    }

    return OutboxStagedFile(
      file: stagedFile,
      fileName: fileName,
      fileSize: fileSize,
      messageType: messageType,
      mimeType: mimeType,
      width: width,
      height: height,
      durationSeconds: durationSeconds,
      thumbnailBytes: thumbnailBytes,
    );
  }

  static Future<File> _stageCopy(
    File source,
    String localId,
    String fileName,
  ) async {
    if (isOutboxFilePath(source.path)) {
      try {
        if (await source.exists()) {
          return source;
        }
      } catch (_) {}
    }
    try {
      final outboxDir = await _resolveOutboxDirectory();
      if (!await outboxDir.exists()) {
        await outboxDir.create(recursive: true);
      }
      final safeBase = fileName.replaceAll(
        RegExp(r'[^a-zA-Z0-9._\-\u0400-\u04FF]'),
        '_',
      );
      final targetPath = p.join(outboxDir.path, '${localId}_$safeBase');
      if (await source.exists()) {
        return await source.copy(targetPath);
      }
    } catch (_) {}
    return source;
  }

  static Future<Directory> _resolveOutboxDirectory() async {
    try {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'outbox_files'));
    } catch (_) {
      return Directory(p.join(Directory.systemTemp.path, 'theaver_outbox'));
    }
  }

  static String _inferMimeType(String ext, String messageType) {
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.mp4':
      case '.m4v':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.webm':
        return 'video/webm';
      case '.mkv':
        return 'video/x-matroska';
      case '.pdf':
        return 'application/pdf';
      default:
        if (messageType == 'image') return 'image/jpeg';
        if (messageType == 'video') return 'video/mp4';
        if (messageType == 'gif') return 'image/gif';
        return 'application/octet-stream';
    }
  }

  static Future<(int, int)?> _probeImageDimensions(
    File file, {
    required int fileSize,
  }) async {
    try {
      if (!await file.exists()) return null;
      // Fast zero-codec header sniff for PNG/GIF/JPEG so arbitrary sizes &
      // headless unit tests succeed immediately.
      final headerBytes = await _readHeaderSlice(file, 64 * 1024);
      final parsed = parseImageDimensionsFromBytes(headerBytes);
      if (parsed != null) return parsed;

      if (fileSize > _maxInMemoryCodecBytes) return null;
      final bytes = await file.readAsBytes();
      final codec = await ui
          .instantiateImageCodec(bytes)
          .timeout(const Duration(milliseconds: 1500));
      try {
        final frame = await codec.getNextFrame().timeout(
              const Duration(milliseconds: 1500),
            );
        final w = frame.image.width;
        final h = frame.image.height;
        frame.image.dispose();
        if (w > 0 && h > 0) return (w, h);
      } finally {
        codec.dispose();
      }
    } catch (_) {}
    return null;
  }

  static Future<Uint8List> _readHeaderSlice(File file, int maxBytes) async {
    final raf = await file.open();
    try {
      final len = await raf.length();
      final toRead = len < maxBytes ? len : maxBytes;
      if (toRead <= 0) return Uint8List(0);
      return await raf.read(toRead);
    } finally {
      await raf.close();
    }
  }

  /// Parses width/height headers for PNG, GIF, and JPEG without spawning an engine codec.
  @visibleForTesting
  static (int, int)? parseImageDimensionsFromBytes(Uint8List bytes) {
    if (bytes.length < 10) return null;

    // PNG: 8-byte signature + IHDR length/type + uint32 width + uint32 height
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      final bd = ByteData.sublistView(bytes);
      final w = bd.getUint32(16, Endian.big);
      final h = bd.getUint32(20, Endian.big);
      if (w > 0 && h > 0) return (w, h);
    }

    // GIF: 'GIF87a' or 'GIF89a' followed by uint16 LE width & height
    if (bytes.length >= 10 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      final bd = ByteData.sublistView(bytes);
      final w = bd.getUint16(6, Endian.little);
      final h = bd.getUint16(8, Endian.little);
      if (w > 0 && h > 0) return (w, h);
    }

    // JPEG: SOI (FF D8) followed by SOF0..SOF3/SOF9..SOF11 markers
    if (bytes.length >= 12 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      int offset = 2;
      while (offset + 8 < bytes.length) {
        if (bytes[offset] != 0xFF) {
          offset++;
          continue;
        }
        while (offset < bytes.length && bytes[offset] == 0xFF) {
          offset++;
        }
        if (offset >= bytes.length) break;
        final marker = bytes[offset++];
        if (marker == 0xD8 || marker == 0xD9 || marker == 0x00 || marker == 0x01) {
          continue;
        }
        if (offset + 2 > bytes.length) break;
        final segLen = (bytes[offset] << 8) | bytes[offset + 1];
        if (segLen < 2 || offset + segLen > bytes.length) break;
        final isSof = (marker >= 0xC0 && marker <= 0xC3) ||
            (marker >= 0xC5 && marker <= 0xC7) ||
            (marker >= 0xC9 && marker <= 0xCB) ||
            (marker >= 0xCD && marker <= 0xCF);
        if (isSof && offset + 7 < bytes.length) {
          final h = (bytes[offset + 3] << 8) | bytes[offset + 4];
          final w = (bytes[offset + 5] << 8) | bytes[offset + 6];
          if (w > 0 && h > 0) return (w, h);
        }
        offset += segLen;
      }
    }

    return null;
  }

  static Future<(int?, int?, int?, Uint8List?)> _probeVideo(File file) async {
    int? width;
    int? height;
    int? durationSeconds;
    Uint8List? thumb;

    try {
      final res = await _muxerChannel
          .invokeMethod<Map<dynamic, dynamic>>(
            'getVideoThumbnail',
            {'videoPath': file.path},
          )
          .timeout(_probeTimeout);
      if (res != null) {
        final rawThumb = res['thumbnail'];
        if (rawThumb is Uint8List && rawThumb.isNotEmpty) {
          thumb = rawThumb;
        }
        final rawW = res['width'];
        if (rawW is num && rawW > 0) width = rawW.toInt();
        final rawH = res['height'];
        if (rawH is num && rawH > 0) height = rawH.toInt();
        final rawDur = res['duration'] ?? res['duration_seconds'];
        if (rawDur is num && rawDur > 0) {
          // If platform returns milliseconds > 36000, normalise cautiously?
          // Assume seconds unless `duration_ms` is present.
          durationSeconds = rawDur.toInt();
        }
        final rawDurMs = res['duration_ms'] ?? res['durationMs'];
        if (rawDurMs is num && rawDurMs > 0) {
          durationSeconds = (rawDurMs.toDouble() / 1000.0).round().clamp(1, 86400);
        }
      }
    } catch (_) {}

    return (width, height, durationSeconds, thumb);
  }
}
