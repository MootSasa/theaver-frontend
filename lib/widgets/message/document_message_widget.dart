import 'dart:io' show File, Directory;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../l10n/app_localizations.dart';
import '../../services/file_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/media_cache_manager.dart';
import '../../services/media_send_coordinator.dart';
import '../design_system/theav_design_system.dart';
import 'telegram_upload_progress.dart';

enum DownloadStatus { idle, downloading, downloaded, failed }

class DocumentMessageWidget extends StatefulWidget {
  final String fileUrl;
  final String fileName;
  final double fileSize; // in bytes
  final String? localId;
  final int sendStatus;
  final VoidCallback? onCancelUpload;
  final VoidCallback? onRetry;

  const DocumentMessageWidget({
    Key? key,
    required this.fileUrl,
    required this.fileName,
    required this.fileSize,
    this.localId,
    this.sendStatus = 1,
    this.onCancelUpload,
    this.onRetry,
  }) : super(key: key);

  @override
  State<DocumentMessageWidget> createState() => _DocumentMessageWidgetState();
}

class _DocumentMessageWidgetState extends State<DocumentMessageWidget> {
  DownloadStatus _status = DownloadStatus.idle;
  double _progress = 0.0;
  String? _downloadedFilePath;
  double _resolvedFileSize = 0.0;

  bool get _isUploadingOrFailed => widget.sendStatus != 1;

  @override
  void initState() {
    super.initState();
    _resolvedFileSize = widget.fileSize;
    if (!_isUploadingOrFailed) {
      _checkFileExists();
    }
  }

  @override
  void didUpdateWidget(DocumentMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fileSize > 0 && widget.fileSize != _resolvedFileSize) {
      _resolvedFileSize = widget.fileSize;
    }
    if (!_isUploadingOrFailed &&
        (oldWidget.sendStatus != widget.sendStatus ||
            oldWidget.fileName != widget.fileName ||
            oldWidget.fileUrl != widget.fileUrl)) {
      _checkFileExists();
    }
  }

  Future<void> _checkFileExists() async {
    if (kIsWeb || _isUploadingOrFailed) return;
    try {
      // 1. Check MediaCacheManager first
      final cached = await MediaCacheManager.instance.getCachedFile(
        widget.fileUrl,
      );
      if (cached != null && await cached.exists()) {
        final len = await cached.length();
        if (len > 0) {
          if (mounted) {
            setState(() {
              _status = DownloadStatus.downloaded;
              _downloadedFilePath = cached.path;
              _progress = 1.0;
              if (_resolvedFileSize <= 0) {
                _resolvedFileSize = len.toDouble();
              }
            });
          }
          return;
        }
      }

      // 2. Check default Downloads directory
      final dir = await _getSaveDirectory();
      final file = File('${dir.path}/${widget.fileName}');
      if (await file.exists()) {
        final len = await file.length();
        if (len > 0) {
          if (mounted) {
            setState(() {
              _status = DownloadStatus.downloaded;
              _downloadedFilePath = file.path;
              _progress = 1.0;
              if (_resolvedFileSize <= 0) {
                _resolvedFileSize = len.toDouble();
              }
            });
          }
        }
      }
    } catch (_) {}
  }

  String _formatSize(double bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) {
      return '${bytes.toInt()} B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    if (_isUploadingOrFailed) {
      final lid = widget.localId;
      if (lid != null && lid.isNotEmpty) {
        return ValueListenableBuilder<OutgoingUploadProgress>(
          valueListenable: MediaSendCoordinator.instance.progressFor(
            lid,
            totalBytes: (widget.fileSize > 0 ? widget.fileSize : _resolvedFileSize)
                .round(),
            sendStatus: widget.sendStatus,
          ),
          builder: (context, progress, _) => _buildUploadingCard(
            context,
            progress,
          ),
        );
      }
      return _buildUploadingCard(
        context,
        OutgoingUploadProgress(
          localId: '',
          chatId: '',
          sentBytes: 0,
          totalBytes: widget.fileSize.round(),
          fraction: 0.0,
          phase: widget.sendStatus == 2
              ? OutgoingUploadPhase.failed
              : OutgoingUploadPhase.uploading,
        ),
      );
    }

    final effectiveSize = widget.fileSize > 0 ? widget.fileSize : _resolvedFileSize;
    final formattedSize = _formatSize(effectiveSize);
    return GestureDetector(
      onTap: _status == DownloadStatus.downloaded ? _showFileOptions : null,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const iconoir.Page(width: 32, height: 32, color: Color(0xFF0088CC)),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (formattedSize.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      formattedSize,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            _buildActionButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadingCard(
    BuildContext context,
    OutgoingUploadProgress progress,
  ) {
    final totalBytes = progress.totalBytes > 0
        ? progress.totalBytes
        : (widget.fileSize > 0 ? widget.fileSize : _resolvedFileSize).round();
    final String subtitle;
    if (progress.isFailed) {
      subtitle = AppLocalizations.trStatic('upload_retry', 'Повторить');
    } else if (totalBytes > 0) {
      final sent = progress.sentBytes.clamp(0, totalBytes);
      subtitle = AppLocalizations.trStatic(
        'upload_progress_of',
        '{sent} из {total}',
        {
          'sent': MediaCacheManager.formatBytes(sent),
          'total': MediaCacheManager.formatBytes(totalBytes),
        },
      );
    } else {
      subtitle = _formatSize(widget.fileSize);
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TelegramRadialUploadIndicator(
            progress: progress,
            size: 38,
            onCancel: widget.onCancelUpload ??
                (widget.localId != null
                    ? () => MediaSendCoordinator.instance.cancelUpload(
                          widget.localId!,
                        )
                    : null),
            onRetry: widget.onRetry ??
                (widget.localId != null
                    ? () => MediaSendCoordinator.instance.retryMessage(
                          widget.localId!,
                        )
                    : null),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.fileName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: progress.isFailed
                          ? const Color(0xFFFF6B6B)
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    if (_status == DownloadStatus.downloading) {
      return SizedBox(
        width: 32,
        height: 32,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: _progress > 0 ? _progress : null,
              strokeWidth: 2.0,
            ),
            if (_progress > 0)
              Text(
                '${(_progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      );
    } else if (_status == DownloadStatus.failed) {
      return IconButton(
        onPressed: _startDownload,
        icon: const iconoir.Refresh(width: 20, height: 20),
        tooltip: context.l10n.translate('chat_file_not_found'),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      );
    } else if (_status == DownloadStatus.downloaded) {
      return const iconoir.CheckCircle(color: Colors.green, width: 22, height: 22);
    } else {
      return IconButton(
        onPressed: _startDownload,
        icon: const iconoir.Download(width: 20, height: 20, color: Color(0xFF0088CC)),
        tooltip: context.l10n.translate('chat_download'),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      );
    }
  }

  Future<void> _startDownload() async {
    setState(() {
      _status = DownloadStatus.downloading;
      _progress = 0.0;
    });

    try {
      if (kIsWeb) {
        await _downloadWeb();
      } else {
        await _downloadWithProgress();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = DownloadStatus.failed;
          _progress = 0.0;
        });
        GlassToastService().showError(
          context,
          'Download failed: ${e.toString()}',
        );
      }
    }
  }

  Future<void> _downloadWeb() async {
    final uri = Uri.tryParse(widget.fileUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    // Show notification that download started
    if (mounted) {
      GlassToastService().show(
        context,
        'Download started for ${widget.fileName}',
      );
      // Reset state since we can't track progress in web
      setState(() {
        _status = DownloadStatus.idle;
        _progress = 0.0;
      });
    }
  }

  Future<void> _downloadWithProgress() async {
    // 1. Download into MediaCacheManager so it is cached and tracked in storage statistics
    final cachedFile = await MediaCacheManager.instance.downloadMedia(
      widget.fileUrl,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _progress = p;
          });
        }
      },
    );

    if (cachedFile == null || !await cachedFile.exists()) {
      throw Exception('Failed to download file');
    }

    final fileLen = await cachedFile.length();
    String openablePath = cachedFile.path;

    // 2. Also save to user's Downloads folder (or MediaStore.Downloads on Android)
    try {
      final savedPath = await FileService().downloadToDownloads(
        widget.fileUrl,
        widget.fileName,
      );
      if (!savedPath.startsWith('content://')) {
        openablePath = savedPath;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _status = DownloadStatus.downloaded;
        _progress = 1.0;
        _downloadedFilePath = openablePath;
        if (_resolvedFileSize <= 0 && fileLen > 0) {
          _resolvedFileSize = fileLen.toDouble();
        }
      });
      GlassToastService().show(
        context,
        'Файл скачан. Нажмите на файл, чтобы открыть.',
      );
    }
  }

  Future<Directory> _getSaveDirectory() async {
    final pathStr = await FileService().getDefaultDownloadDirectory();
    final dir = Directory(pathStr);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _openDownloadedFile() async {
    if (_downloadedFilePath == null) {
      GlassToastService().show(context, 'File not downloaded yet');
      return;
    }

    try {
      final result = await OpenFile.open(_downloadedFilePath);
      if (result.type != ResultType.done) {
        if (mounted) {
          GlassToastService().showError(
            context,
            'Failed to open file: ${result.message}',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        GlassToastService().showError(context, 'Error opening file: $e');
      }
    }
  }

  void _showFileOptions() {
    final parentContext = context;
    showTheavModalSheet<void>(
      context: parentContext,
      title: widget.fileName,
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: TheavInsetGroup(
          children: [
            TheavListRow(
              leading: const iconoir.OpenNewWindow(width: 20, height: 20),
              title: parentContext.l10n.translate('chat_open_file'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _openDownloadedFile();
              },
            ),
            TheavListRow(
              leading: const iconoir.ShareAndroid(width: 20, height: 20),
              title: parentContext.l10n.translate('share'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _shareFile();
              },
            ),
            TheavListRow(
              leading: const iconoir.Folder(width: 20, height: 20),
              title: 'Показать в папке',
              subtitle: _downloadedFilePath,
              onTap: () {
                Navigator.pop(sheetCtx);
                _showInFolder();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Share the downloaded file using the system share sheet
  Future<void> _shareFile() async {
    if (_downloadedFilePath == null) {
      GlassToastService().show(context, 'Сначала скачайте файл');
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: widget.fileName,
          files: [XFile(_downloadedFilePath!)],
        ),
      );
    } catch (e) {
      if (mounted) {
        GlassToastService().showError(context, 'Ошибка при отправке: $e');
      }
    }
  }

  /// Show the downloaded file in the system file manager
  Future<void> _showInFolder() async {
    if (_downloadedFilePath == null) {
      GlassToastService().show(context, 'Сначала скачайте файл');
      return;
    }
    try {
      // open_file can open the file, but to show in folder we use
      // the system's file manager via open_file with "folder" mode
      final result = await OpenFile.open(_downloadedFilePath);
      if (result.type != ResultType.done && mounted) {
        GlassToastService().showError(
          context,
          'Не удалось открыть: ${result.message}',
        );
      }
    } catch (e) {
      if (mounted) {
        GlassToastService().showError(context, 'Ошибка: $e');
      }
    }
  }
}