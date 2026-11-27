import 'dart:async';
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
  ValueNotifier<DownloadByteProgress>? _byteNotifier;

  bool get _isUploadingOrFailed => widget.sendStatus != 1;

  @override
  void initState() {
    super.initState();
    _resolvedFileSize = widget.fileSize;
    if (!_isUploadingOrFailed) {
      _syncCacheImmediate();
      _checkFileExists();
    }
  }

  @override
  void didUpdateWidget(DocumentMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fileSize > 0 && widget.fileSize != _resolvedFileSize) {
      _resolvedFileSize = widget.fileSize;
    }
    if (oldWidget.fileUrl != widget.fileUrl) {
      _detachByteNotifier();
      _downloadedFilePath = null;
      _status = DownloadStatus.idle;
      _progress = 0.0;
    }
    if (!_isUploadingOrFailed &&
        (oldWidget.sendStatus != widget.sendStatus ||
            oldWidget.fileName != widget.fileName ||
            oldWidget.fileUrl != widget.fileUrl)) {
      _syncCacheImmediate();
      _checkFileExists();
    }
  }

  @override
  void dispose() {
    _detachByteNotifier();
    super.dispose();
  }

  void _attachByteNotifier() {
    if (kIsWeb || widget.fileUrl.isEmpty) return;
    _detachByteNotifier();
    _byteNotifier =
        MediaCacheManager.instance.getByteProgressNotifier(widget.fileUrl);
    _byteNotifier?.addListener(_onByteProgress);
  }

  void _detachByteNotifier() {
    _byteNotifier?.removeListener(_onByteProgress);
    _byteNotifier = null;
  }

  void _onByteProgress() {
    if (!mounted || _byteNotifier == null) return;
    final bp = _byteNotifier!.value;
    final downloading = MediaCacheManager.instance.isDownloading(widget.fileUrl);
    if (bp.fraction >= 1.0 && !downloading) {
      _checkFileExists();
      return;
    }
    setState(() {
      if (downloading) {
        _status = DownloadStatus.downloading;
      }
      _progress = bp.fraction;
      if (bp.totalBytes > 0 && _resolvedFileSize <= 0) {
        _resolvedFileSize = bp.totalBytes.toDouble();
      }
    });
  }

  void _syncCacheImmediate() {
    if (kIsWeb || _isUploadingOrFailed || widget.fileUrl.isEmpty) return;
    final syncFile = MediaCacheManager.instance.getCachedFileSync(
      widget.fileUrl,
    );
    if (syncFile != null) {
      _status = DownloadStatus.downloaded;
      _downloadedFilePath = syncFile.path;
      _progress = 1.0;
      if (_resolvedFileSize <= 0) {
        try {
          final len = syncFile.lengthSync();
          if (len > 0) {
            _resolvedFileSize = len.toDouble();
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _checkFileExists() async {
    if (kIsWeb || _isUploadingOrFailed || widget.fileUrl.isEmpty) return;
    final String checkedUrl = widget.fileUrl;
    try {
      final cached = await MediaCacheManager.instance.getCachedFile(checkedUrl);
      if (!mounted || widget.fileUrl != checkedUrl || _isUploadingOrFailed) {
        return;
      }
      if (cached != null && await cached.exists()) {
        final len = await cached.length();
        if (len > 0) {
          _detachByteNotifier();
          if (!mounted || widget.fileUrl != checkedUrl) return;
          if (_status != DownloadStatus.downloaded ||
              _downloadedFilePath != cached.path ||
              (_resolvedFileSize <= 0 && len > 0)) {
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

      if (MediaCacheManager.instance.isDownloading(checkedUrl)) {
        _attachByteNotifier();
        setState(() {
          _status = DownloadStatus.downloading;
          _progress = _byteNotifier?.value.fraction ?? _progress;
        });
        return;
      }

      final effectiveSize =
          widget.fileSize > 0 ? widget.fileSize : _resolvedFileSize;
      final int? sizeInt = effectiveSize > 0 ? effectiveSize.round() : null;
      final bool autoDownload =
          !MediaCacheManager.instance.wasCancelledByUser(checkedUrl) &&
              MediaCacheManager.instance.shouldAutoDownload(
                messageType: 'file',
                fileSize: sizeInt,
              );
      if (autoDownload) {
        unawaited(_startDownload(autoTriggered: true));
      } else if (_status == DownloadStatus.downloaded) {
        setState(() {
          _status = DownloadStatus.idle;
          _downloadedFilePath = null;
          _progress = 0.0;
        });
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
      onTap: () {
        if (_status == DownloadStatus.downloaded) {
          _openDownloadedFile();
        } else if (_status == DownloadStatus.downloading) {
          _cancelDownload();
        } else {
          _startDownload();
        }
      },
      onLongPress: _status == DownloadStatus.downloaded ? _showFileOptions : null,
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
      return GestureDetector(
        onTap: _cancelDownload,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: _progress > 0 ? _progress : null,
                strokeWidth: 2.0,
              ),
              const Icon(
                Icons.close_rounded,
                size: 15,
                color: Color(0xFF0088CC),
              ),
            ],
          ),
        ),
      );
    } else if (_status == DownloadStatus.failed) {
      return IconButton(
        onPressed: () => _startDownload(),
        icon: const iconoir.Refresh(width: 20, height: 20),
        tooltip: context.l10n.translate('chat_file_not_found'),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      );
    } else if (_status == DownloadStatus.downloaded) {
      return IconButton(
        onPressed: _showFileOptions,
        icon: Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        ),
        tooltip: widget.fileName,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      );
    } else {
      return IconButton(
        onPressed: () => _startDownload(),
        icon: const iconoir.Download(width: 20, height: 20, color: Color(0xFF0088CC)),
        tooltip: context.l10n.translate('chat_download'),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      );
    }
  }

  Future<void> _startDownload({bool autoTriggered = false}) async {
    if (_status == DownloadStatus.downloading) return;
    if (!kIsWeb) {
      _attachByteNotifier();
    }
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
      _detachByteNotifier();
      if (mounted) {
        if (MediaCacheManager.instance.wasCancelledByUser(widget.fileUrl)) {
          setState(() {
            _status = DownloadStatus.idle;
            _progress = 0.0;
          });
          return;
        }
        setState(() {
          _status = DownloadStatus.failed;
          _progress = 0.0;
        });
        if (!autoTriggered) {
          GlassToastService().showError(
            context,
            'Download failed: ${e.toString()}',
          );
        }
      }
    }
  }

  void _cancelDownload() {
    MediaCacheManager.instance.cancelDownload(widget.fileUrl, byUser: true);
    _detachByteNotifier();
    if (mounted) {
      setState(() {
        _status = DownloadStatus.idle;
        _progress = 0.0;
      });
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
    final effectiveSize =
        widget.fileSize > 0 ? widget.fileSize : _resolvedFileSize;
    final int? sizeInt = effectiveSize > 0 ? effectiveSize.round() : null;
    final String requestedUrl = widget.fileUrl;

    // Single download into MediaCacheManager only (matches Telegram internal cache UX).
    final cachedFile = await MediaCacheManager.instance.downloadMedia(
      requestedUrl,
      expectedTotalSize: sizeInt,
      onProgress: (p) {
        if (mounted && _status == DownloadStatus.downloading) {
          setState(() {
            _progress = p;
          });
        }
      },
    );

    _detachByteNotifier();
    if (MediaCacheManager.instance.wasCancelledByUser(requestedUrl)) {
      if (mounted) {
        setState(() {
          _status = DownloadStatus.idle;
          _progress = 0.0;
        });
      }
      return;
    }

    if (cachedFile == null || !await cachedFile.exists()) {
      throw Exception('Failed to download file');
    }

    final fileLen = await cachedFile.length();
    if (mounted) {
      setState(() {
        _status = DownloadStatus.downloaded;
        _progress = 1.0;
        _downloadedFilePath = cachedFile.path;
        if (_resolvedFileSize <= 0 && fileLen > 0) {
          _resolvedFileSize = fileLen.toDouble();
        }
      });
    }
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

  Future<void> _saveToDownloads() async {
    try {
      await FileService().downloadToDownloads(widget.fileUrl, widget.fileName);
      if (mounted) {
        GlassToastService().show(
          context,
          AppLocalizations.trStatic(
            'saved_to_downloads',
            'Сохранено в Загрузки',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        GlassToastService().showError(context, 'Ошибка сохранения: $e');
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
              leading: const iconoir.Download(width: 20, height: 20),
              title: AppLocalizations.trStatic(
                'save_to_downloads',
                'Сохранить в Загрузки',
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _saveToDownloads();
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
}