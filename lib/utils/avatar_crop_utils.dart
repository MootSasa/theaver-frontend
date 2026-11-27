import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart' show CroppedFile;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/avatar_editor_models.dart';
import '../utils/avatar_studio_renderer.dart';
import '../widgets/avatar_editor/theav_avatar_editor_screen.dart';

/// Утилита для редактирования, обрезки и сжатия аватаров через встроенную
/// студию [TheavAvatarEditorScreen] (кроссплатформенно: mobile, desktop, web).
class AvatarCropUtils {
  /// Максимальный размер стороны аватара в пикселях.
  static const int maxAvatarSize = 1600;

  /// Качество сжатия (0-100).
  static const int compressionQuality = 90;

  /// Максимальный размер файла в байтах (3 MB).
  static const int maxFileSizeBytes = 3 * 1024 * 1024;

  /// Открывает встроенный кроссплатформенный редактор аватара [TheavAvatarEditorScreen].
  static Future<CroppedFile?> cropAvatar({
    required String imagePath,
    required BuildContext context,
    AvatarShapeMask maskShape = AvatarShapeMask.circle,
    AvatarEditorCtaMode ctaMode = AvatarEditorCtaMode.done,
    String? subjectName,
    AvatarCropAspectMode? initialAspectMode,
  }) async {
    debugPrint('[cropAvatar] Step 1: Opening studio editor for $imagePath');

    Uint8List? webBytes;
    if (kIsWeb) {
      try {
        webBytes = await XFile(imagePath).readAsBytes();
      } catch (e) {
        debugPrint('[cropAvatar] Web readAsBytes failed: $e');
        return null;
      }
    }

    if (!context.mounted) return null;

    final String fileName = kIsWeb
        ? 'avatar.jpg'
        : (path.basename(imagePath).isNotEmpty
            ? path.basename(imagePath)
            : 'avatar.jpg');

    final AvatarPickResult? result = await TheavAvatarEditorScreen.open(
      context: context,
      initialBytes: webBytes,
      initialFilePath: kIsWeb ? null : imagePath,
      fileName: fileName,
      maskShape: maskShape,
      ctaMode: ctaMode,
      subjectName: subjectName,
      initialAspectMode: initialAspectMode,
    );

    if (result == null) {
      debugPrint('[cropAvatar] Step 2: Cancelled by user');
      return null;
    }

    if (result.file != null) {
      debugPrint('[cropAvatar] Step 2: Studio returned ${result.file!.path}');
      return CroppedFile(result.file!.path);
    }

    if (result.bytes != null && result.bytes!.isNotEmpty && !kIsWeb) {
      final dir = await getTemporaryDirectory();
      final outPath = path.join(dir.path, result.fileName);
      await File(outPath).writeAsBytes(result.bytes!, flush: true);
      return CroppedFile(outPath);
    }

    return null;
  }

  /// Сжимает изображение до оптимального размера с сохранением пропорций исходного кадра.
  static Future<String> compressAvatar(String imagePath) async {
    debugPrint('[compressAvatar] Step 1: Starting compression for $imagePath');
    final dir = await getTemporaryDirectory();
    final targetPath = path.join(
      dir.path,
      'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );

    debugPrint('[compressAvatar] Step 2: First compression pass...');
    XFile? firstCompressed;
    try {
      firstCompressed = await FlutterImageCompress.compressAndGetFile(
        imagePath,
        targetPath,
        quality: compressionQuality,
        minWidth: 1280,
        minHeight: 1280,
        keepExif: false,
        format: CompressFormat.jpeg,
      );
    } catch (e) {
      debugPrint(
        '[compressAvatar] Step 2-fallback (platform compress unavailable): $e',
      );
      return imagePath;
    }

    if (firstCompressed == null) {
      debugPrint(
        '[compressAvatar] Step 2-warn: First compression returned null, using original',
      );
      return imagePath;
    }

    String compressedPath = firstCompressed.path;
    File file = File(compressedPath);
    int fileSize = await file.length();
    debugPrint(
      '[compressAvatar] Step 2-ok: First compression done, size=$fileSize bytes',
    );

    int quality = compressionQuality;
    while (fileSize > maxFileSizeBytes && quality > 10) {
      quality -= 10;

      final newTargetPath = path.join(
        dir.path,
        'avatar_${DateTime.now().millisecondsSinceEpoch}_q$quality.jpg',
      );

      XFile? newCompressedFile;
      try {
        newCompressedFile = await FlutterImageCompress.compressAndGetFile(
          compressedPath,
          newTargetPath,
          quality: quality,
          minWidth: 1280,
          minHeight: 1280,
          keepExif: false,
          format: CompressFormat.jpeg,
        );
      } catch (_) {
        break;
      }

      if (newCompressedFile != null) {
        await file.delete();
        compressedPath = newCompressedFile.path;
        file = File(compressedPath);
        fileSize = await file.length();
      } else {
        break;
      }
    }

    return compressedPath;
  }

  /// Полный пайплайн обработки аватара: студийный редактор + (при необходимости) сжатие.
  static Future<String?> processAvatar({
    required String imagePath,
    required BuildContext context,
    AvatarShapeMask maskShape = AvatarShapeMask.circle,
    AvatarEditorCtaMode ctaMode = AvatarEditorCtaMode.done,
    String? subjectName,
    AvatarCropAspectMode? initialAspectMode,
  }) async {
    debugPrint('[processAvatar] Step 1: Starting studio pipeline for $imagePath');
    final croppedFile = await cropAvatar(
      imagePath: imagePath,
      context: context,
      maskShape: maskShape,
      ctaMode: ctaMode,
      subjectName: subjectName,
      initialAspectMode: initialAspectMode,
    );

    if (croppedFile == null) {
      debugPrint(
        '[processAvatar] Step 1-cancel: cropAvatar returned null (user cancelled)',
      );
      return null;
    }

    if (!kIsWeb) {
      final File outFile = File(croppedFile.path);
      if (await outFile.exists()) {
        final Uint8List bytes = await outFile.readAsBytes();
        if (AvatarStudioRenderer.isAnimatedMediaBytes(bytes, croppedFile.path)) {
          debugPrint('[processAvatar] Preserved animated avatar: ${croppedFile.path}');
          return croppedFile.path;
        }
        if (bytes.length <= maxFileSizeBytes) {
          debugPrint(
            '[processAvatar] Studio output already within limit (${bytes.length} bytes)',
          );
          return croppedFile.path;
        }
      }
    }

    debugPrint(
      '[processAvatar] Step 2: Running fallback compression for ${croppedFile.path}',
    );
    final compressedPath = await compressAvatar(croppedFile.path);
    debugPrint('[processAvatar] Step 3: Pipeline complete, result=$compressedPath');
    return compressedPath;
  }

  /// Получает размер файла в человекочитаемом формате.
  static String getFileSizeString(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
