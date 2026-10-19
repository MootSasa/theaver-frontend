import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../config/app_config.dart';
import 'auth_service.dart';
import 'media_cache_manager.dart';
import 'settings_service.dart';

/// Service for handling file operations with MinIO backend
class FileService {
  final Dio _dio;
  final String baseUrl;

  FileService({
    String? baseUrl,
  })  : baseUrl = baseUrl ?? AppConfig.baseUrl,
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 5),
        ));

  /// Get authorization headers
  Future<Map<String, String>> _getHeaders() async {
    final token = await AuthService.getToken();
    return {
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Upload a file to the server
  ///
  /// [file] - The file to upload
  /// [onProgress] - Optional callback for upload progress (0.0 to 1.0)
  Future<UploadResult> uploadFile(
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    final fileName = path.basename(file.path);
    final fileLength = await file.length();
    
    // Determine mime type from file extension
    final mimeType = _getMimeType(fileName);
    
    final formData = FormData.fromMap({
      'file': MultipartFile.fromStream(
        () => file.openRead(),
        fileLength,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      ),
    });

    try {
      final headers = await _getHeaders();
      final response = await _dio.post(
        '$baseUrl/api/files/upload',
        data: formData,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
        onSendProgress: (sent, total) {
          if (onProgress != null && total > 0) {
            onProgress(sent / total);
          }
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final result = UploadResult.fromJson(response.data);
        if (result.url.isNotEmpty) {
          await MediaCacheManager.instance.seedCacheFromFile(result.url, file);
        }
        return result;
      } else {
        throw FileUploadException(
          response.data['message'] ?? 'Upload failed',
        );
      }
    } on DioException catch (e) {
      throw FileUploadException(
        e.response?.data?['message'] ?? 'Upload failed: ${e.message}',
      );
    }
  }

  /// Upload a file in chunks to allow progressive processing and streaming.
  /// Used for uploading files in chunks.
  Future<UploadResult> uploadFileChunked(
    File file, {
    void Function(double progress)? onProgress,
    int chunkSize = 256 * 1024, // 256 KB per chunk
  }) async {
    final fileName = path.basename(file.path);
    final rawSize = await file.length();
    final totalSize = math.max(rawSize, 1);
    final mimeType = _getMimeType(fileName);
    final partsCount = (totalSize / chunkSize).ceil().clamp(1, 10000);

    final headers = await _getHeaders();

    // 1. Initialize chunked upload
    final initResponse = await _dio.post(
      '$baseUrl/api/files/upload/chunked/init',
      data: {
        'file_name': fileName,
        'total_size': totalSize,
        'parts_count': partsCount,
        'mime_type': mimeType,
      },
      options: Options(headers: headers),
    );

    if (initResponse.statusCode != 200 || initResponse.data['success'] != true) {
      throw FileUploadException(
        initResponse.data['message'] ?? 'Failed to initialize chunked upload',
      );
    }

    final uploadId = initResponse.data['upload_id'] as String;

    // 2. Upload each chunk with retry
    final raf = await file.open(mode: FileMode.read);
    try {
      for (int i = 0; i < partsCount; i++) {
        final start = i * chunkSize;
        final currentChunkSize = (start + chunkSize > totalSize)
            ? (totalSize - start)
            : chunkSize;

        await raf.setPosition(start);
        final chunkBytes = await raf.read(currentChunkSize);
        final partNumber = i + 1;

        Response? partResponse;
        Object? lastError;

        for (int attempt = 0; attempt < 3; attempt++) {
          try {
            final formData = FormData.fromMap({
              'upload_id': uploadId,
              'part_number': partNumber.toString(),
              'chunk_index': i.toString(),
              'chunk': MultipartFile.fromBytes(
                chunkBytes,
                filename: 'part_$partNumber',
                contentType: MediaType.parse('application/octet-stream'),
              ),
            });

            partResponse = await _dio.put(
              '$baseUrl/api/files/upload/chunked/part?upload_id=$uploadId&part_number=$partNumber',
              data: formData,
              options: Options(headers: headers),
            );

            if (partResponse.statusCode == 200 && partResponse.data?['success'] == true) {
              lastError = null;
              break;
            } else {
              lastError = partResponse.data?['message'] ?? 'Failed to upload chunk $partNumber';
            }
          } catch (e) {
            lastError = e;
            if (attempt < 2) {
              await Future.delayed(Duration(milliseconds: 250 * (attempt + 1)));
            }
          }
        }

        if (partResponse == null || partResponse.statusCode != 200 || partResponse.data?['success'] != true) {
          throw FileUploadException(
            lastError != null ? lastError.toString() : 'Failed to upload chunk $partNumber',
          );
        }

        if (onProgress != null) {
          onProgress((i + 1) / partsCount);
        }
      }
    } finally {
      await raf.close();
    }

    // 3. Complete chunked upload
    final completeResponse = await _dio.post(
      '$baseUrl/api/files/upload/chunked/complete',
      data: {
        'upload_id': uploadId,
      },
      options: Options(headers: headers),
    );

    if (completeResponse.statusCode == 200 && completeResponse.data['success'] == true) {
      final result = UploadResult.fromJson(completeResponse.data);
      if (result.url.isNotEmpty) {
        await MediaCacheManager.instance.seedCacheFromFile(result.url, file);
      }
      return result;
    } else {
      throw FileUploadException(
        completeResponse.data['message'] ?? 'Failed to complete chunked upload',
      );
    }
  }

  /// Uploads a media file in chunks
  Future<UploadResult> uploadMediaFile(
    File file, {
    void Function(double progress)? onProgress,
  }) {
    return uploadFileChunked(file, onProgress: onProgress);
  }

  /// Extracts basic local file metadata (file size, is_video) before upload.
  /// The blurred thumbnail and media dimensions are created on the server.
  static Future<Map<String, dynamic>> extractMediaPayload(
    File file, {
    bool isVideo = false,
  }) async {
    try {
      final totalSize = await file.length();
      return {
        'file_size': totalSize,
        'is_video': isVideo,
      };
    } catch (_) {
      return {};
    }
  }

  /// Get a presigned URL for direct upload to MinIO
  Future<PresignedUrlResult> getPresignedUploadUrl(
    String fileName,
    String contentType,
  ) async {
    try {
      final headers = await _getHeaders();
      final response = await _dio.post(
        '$baseUrl/api/files/upload-presigned',
        data: {
          'file_name': fileName,
          'content_type': contentType,
        },
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return PresignedUrlResult.fromJson(response.data);
      } else {
        throw FileUploadException(
          response.data['message'] ?? 'Failed to get upload URL',
        );
      }
    } on DioException catch (e) {
      throw FileUploadException(
        e.response?.data?['message'] ?? 'Failed to get upload URL: ${e.message}',
      );
    }
  }

  /// Upload file directly to MinIO using presigned URL
  Future<void> uploadToPresignedUrl(
    String presignedUrl,
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    final fileStream = file.openRead();
    final fileLength = await file.length();
    final fileName = path.basename(file.path);
    final mimeType = _getMimeType(fileName);

    try {
      await _dio.put(
        presignedUrl,
        data: fileStream,
        options: Options(
          headers: {
            'Content-Type': mimeType,
            'Content-Length': fileLength.toString(),
          },
        ),
        onSendProgress: (sent, total) {
          if (onProgress != null && total > 0) {
            onProgress(sent / total);
          }
        },
      );
    } on DioException catch (e) {
      throw FileUploadException('Direct upload failed: ${e.message}');
    }
  }

  /// Get a presigned URL for downloading a file
  Future<String> getPresignedDownloadUrl(String objectName) async {
    try {
      final headers = await _getHeaders();
      final response = await _dio.get(
        '$baseUrl/api/files/download-presigned/$objectName',
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['download_url'];
      } else {
        throw FileDownloadException(
          response.data['message'] ?? 'Failed to get download URL',
        );
      }
    } on DioException catch (e) {
      throw FileDownloadException(
        e.response?.data?['message'] ?? 'Failed to get download URL: ${e.message}',
      );
    }
  }

  /// Download a file from the server
  Future<File> downloadFile(
    String objectName,
    String savePath, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final headers = await _getHeaders();
      await _dio.download(
        '$baseUrl/api/files/download/$objectName',
        savePath,
        options: Options(headers: headers),
        onReceiveProgress: (received, total) {
          if (onProgress != null && total > 0) {
            onProgress(received / total);
          }
        },
      );
      return File(savePath);
    } on DioException catch (e) {
      throw FileDownloadException('Download failed: ${e.message}');
      }
    }
  
    /// Download a file to the default downloads directory
    /// Returns the path where the file was saved
    Future<String> downloadToDownloads(
      String objectName,
      String fileName, {
      String? customDownloadPath,
      void Function(double progress)? onProgress,
    }) async {
      try {
        // Get download directory
        String downloadDir;
        if (customDownloadPath != null && customDownloadPath.isNotEmpty) {
          downloadDir = customDownloadPath;
        } else {
          // Use default downloads directory
          final defaultDir = await getDefaultDownloadDirectory();
          downloadDir = defaultDir;
        }
  
        // Ensure directory exists
        final dir = Directory(downloadDir);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
  
        // Generate unique filename if file already exists
        String finalPath = path.join(downloadDir, fileName);
        final file = File(finalPath);
        if (await file.exists()) {
          final ext = path.extension(fileName);
          final nameWithoutExt = path.basenameWithoutExtension(fileName);
          int counter = 1;
          while (await File(finalPath).exists()) {
            finalPath = path.join(downloadDir, '${nameWithoutExt}_$counter$ext');
            counter++;
          }
        }
  
        // Download file
        await downloadFile(objectName, finalPath, onProgress: onProgress);
        return finalPath;
      } catch (e) {
        throw FileDownloadException('Failed to download to downloads: $e');
      }
    }
  
    /// Get default download directory based on user settings and platform
    Future<String> getDefaultDownloadDirectory() async {
      // 0. Check user-configured custom download path from SettingsService
      try {
        final customPath = SettingsService().storageSettings.downloadPath;
        if (customPath != null && customPath.isNotEmpty) {
          final customDir = Directory(customPath);
          if (await customDir.exists()) {
            return customDir.path;
          }
        }
      } catch (_) {}

      // 1. Try platform-provided Downloads directory (desktop and supported mobile)
      try {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null && await downloadsDir.exists()) {
          return downloadsDir.path;
        }
      } catch (_) {}

      // 2. Android public Downloads directory if accessible
      if (Platform.isAndroid) {
        final directory = Directory('/storage/emulated/0/Download');
        if (await directory.exists()) {
          return directory.path;
        }
      }

      // 3. Desktop environment variables
      if (Platform.isLinux || Platform.isMacOS) {
        final home = Platform.environment['HOME'] ?? '';
        if (home.isNotEmpty) {
          final dirPath = path.join(home, 'Downloads');
          if (await Directory(dirPath).exists()) {
            return dirPath;
          }
        }
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'] ?? '';
        if (userProfile.isNotEmpty) {
          final dirPath = path.join(userProfile, 'Downloads');
          if (await Directory(dirPath).exists()) {
            return dirPath;
          }
        }
      }

      // 4. Fallback to app documents/Downloads
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final downloadsDir = Directory(path.join(docsDir.path, 'Downloads'));
        if (!await downloadsDir.exists()) {
          await downloadsDir.create(recursive: true);
        }
        return downloadsDir.path;
      } catch (_) {}

      // 5. Final fallback to system temp
      return Directory.systemTemp.path;
    }
  
    /// Open a file with the system's default application
    Future<void> openFile(String filePath) async {
      try {
        final file = File(filePath);
        if (!await file.exists()) {
          throw FileOpenException('File does not exist: $filePath');
        }
  
        final result = await OpenFile.open(filePath);
        if (result.type != ResultType.done) {
          throw FileOpenException('Failed to open file: ${result.message}');
        }
      } catch (e) {
        if (e is FileOpenException) rethrow;
        throw FileOpenException('Failed to open file: $e');
      }
    }
  
    /// Download and open a file
    /// Downloads the file to downloads directory and opens it
    Future<String> downloadAndOpen(
      String objectName,
      String fileName, {
      String? customDownloadPath,
      void Function(double progress)? onProgress,
    }) async {
      // Download file
      final filePath = await downloadToDownloads(
        objectName,
        fileName,
        customDownloadPath: customDownloadPath,
        onProgress: onProgress,
      );
  
      // Open file
      await openFile(filePath);
  
      return filePath;
    }

  /// Delete a file from the server
  Future<void> deleteFile(String objectName) async {
    try {
      final headers = await _getHeaders();
      final response = await _dio.delete(
        '$baseUrl/api/files/$objectName',
        options: Options(headers: headers),
      );

      if (response.statusCode != 200 || response.data['success'] != true) {
        throw FileDeleteException(
          response.data['message'] ?? 'Delete failed',
        );
      }
    } on DioException catch (e) {
      throw FileDeleteException(
        e.response?.data?['message'] ?? 'Delete failed: ${e.message}',
      );
    }
  }

  /// Upload an avatar image
  Future<String> uploadAvatar(File file) async {
    final fileName = path.basename(file.path);
    final fileLength = await file.length();
    final mimeType = _getMimeType(fileName);

    final formData = FormData.fromMap({
      'avatar': MultipartFile.fromStream(
        () => file.openRead(),
        fileLength,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      ),
    });

    try {
      final headers = await _getHeaders();
      final response = await _dio.post(
        '$baseUrl/api/files/upload-avatar',
        data: formData,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['avatar_url'];
      } else {
        throw FileUploadException(
          response.data['message'] ?? 'Avatar upload failed',
        );
      }
    } on DioException catch (e) {
      throw FileUploadException(
        e.response?.data?['message'] ?? 'Avatar upload failed: ${e.message}',
      );
    }
  }

  /// Get mime type from file extension
  String _getMimeType(String fileName) {
    final ext = path.extension(fileName).toLowerCase();
    final mimeTypes = {
      // Images
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.gif': 'image/gif',
      '.webp': 'image/webp',
      '.heic': 'image/heic',
      '.heif': 'image/heif',
      '.svg': 'image/svg+xml',
      '.bmp': 'image/bmp',
      '.tiff': 'image/tiff',
      '.tif': 'image/tiff',
      // Videos
      '.mp4': 'video/mp4',
      '.webm': 'video/webm',
      '.mov': 'video/quicktime',
      '.avi': 'video/x-msvideo',
      '.3gp': 'video/3gpp',
      '.mkv': 'video/x-matroska',
      // Audio
      '.mp3': 'audio/mpeg',
      '.ogg': 'audio/ogg',
      '.wav': 'audio/wav',
      '.m4a': 'audio/mp4',
      '.aac': 'audio/aac',
      '.opus': 'audio/opus',
      '.flac': 'audio/flac',
      '.amr': 'audio/amr',
      // Documents
      '.pdf': 'application/pdf',
      '.doc': 'application/msword',
      '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      '.xls': 'application/vnd.ms-excel',
      '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      '.ppt': 'application/vnd.ms-powerpoint',
      '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      '.txt': 'text/plain',
      // Archives
      '.zip': 'application/zip',
      '.rar': 'application/x-rar-compressed',
      '.7z': 'application/x-7z-compressed',
      '.gz': 'application/gzip',
      '.tar': 'application/gzip',
    };
    return mimeTypes[ext] ?? 'application/octet-stream';
  }
}

/// Result of a file upload operation
class UploadResult {
  final int fileId;
  final String objectName;
  final String url;
  final String fileName;
  final String mimeType;
  final int size;
  final String? thumbBase64;
  final String? thumbUrl;
  final int width;
  final int height;
  final int duration;

  UploadResult({
    required this.fileId,
    required this.objectName,
    required this.url,
    required this.fileName,
    required this.mimeType,
    required this.size,
    this.thumbBase64,
    this.thumbUrl,
    this.width = 0,
    this.height = 0,
    this.duration = 0,
  });

  int get fileSize => size;

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    return UploadResult(
      fileId: json['file_id'] ?? 0,
      objectName: json['object_name'] ?? '',
      url: json['url'] ?? '',
      fileName: json['file_name'] ?? '',
      mimeType: json['mime_type'] ?? '',
      size: json['size'] ?? 0,
      thumbBase64: json['thumb_base64'] as String?,
      thumbUrl: json['thumb_url'] as String? ?? json['thumbnail_url'] as String?,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Result of getting a presigned URL
class PresignedUrlResult {
  final String uploadUrl;
  final String objectName;
  final int expiresIn;

  PresignedUrlResult({
    required this.uploadUrl,
    required this.objectName,
    required this.expiresIn,
  });

  factory PresignedUrlResult.fromJson(Map<String, dynamic> json) {
    return PresignedUrlResult(
      uploadUrl: json['upload_url'] ?? '',
      objectName: json['object_name'] ?? '',
      expiresIn: json['expires_in'] ?? 0,
    );
  }
}

/// Exception thrown during file upload
class FileUploadException implements Exception {
  final String message;
  FileUploadException(this.message);
  
  @override
  String toString() => 'FileUploadException: $message';
}

/// Exception thrown during file download
class FileDownloadException implements Exception {
  final String message;
  FileDownloadException(this.message);
  
  @override
  String toString() => 'FileDownloadException: $message';
}

/// Exception thrown during file deletion
class FileDeleteException implements Exception {
  final String message;
  FileDeleteException(this.message);

  @override
  String toString() => 'FileDeleteException: $message';
}

/// Exception thrown during file open
class FileOpenException implements Exception {
  final String message;
  FileOpenException(this.message);

  @override
  String toString() => 'FileOpenException: $message';
}
