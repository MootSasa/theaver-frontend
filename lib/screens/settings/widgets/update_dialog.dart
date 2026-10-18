import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart' show ResultType;
import '../../../services/update_service.dart';
import '../../../utils/haptic_utils.dart';

class UpdateDialog extends StatefulWidget {
  final AppUpdateInfo update;
  final bool isManual;

  const UpdateDialog({
    Key? key,
    required this.update,
    this.isManual = false,
  }) : super(key: key);

  static Future<void> show(
    BuildContext context,
    AppUpdateInfo update, {
    bool isManual = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !update.forceUpdate,
      builder: (context) => UpdateDialog(
        update: update,
        isManual: isManual,
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _downloadedText = '';
  String? _errorMessage;
  File? _downloadedFile;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    if (widget.update.downloadUrl.isEmpty) {
      setState(() {
        _errorMessage = 'Ссылка для скачивания отсутствует';
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _downloadedText = '0.0 MB';
    });
    HapticUtils.tap();

    _cancelToken = CancelToken();

    try {
      final file = await AppUpdateService.instance.downloadApk(
        downloadUrl: widget.update.downloadUrl,
        expectedSha256: widget.update.sha256,
        cancelToken: _cancelToken,
        onProgress: (received, total) {
          if (!mounted) return;
          final effectiveTotal = total > 0 ? total : widget.update.apkSizeBytes;
          if (effectiveTotal > 0) {
            final percent = (received / effectiveTotal).clamp(0.0, 1.0);
            final recMB = (received / (1024 * 1024)).toStringAsFixed(1);
            final totMB = (effectiveTotal / (1024 * 1024)).toStringAsFixed(1);
            setState(() {
              _progress = percent;
              _downloadedText = '$recMB MB / $totMB MB';
            });
          } else {
            final recMB = (received / (1024 * 1024)).toStringAsFixed(1);
            setState(() {
              _downloadedText = '$recMB MB';
            });
          }
        },
      );

      if (!mounted) return;

      if (file != null) {
        setState(() {
          _isDownloading = false;
          _downloadedFile = file;
          _progress = 1.0;
        });

        // Запуск установки
        await _installApk(file.path);
      } else {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Не удалось сохранить файл обновления';
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (CancelToken.isCancel(e as dynamic)) {
        setState(() {
          _isDownloading = false;
          _progress = 0.0;
          _downloadedText = '';
        });
      } else {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Ошибка загрузки: $e';
        });
      }
    }
  }

  Future<void> _installApk(String path) async {
    HapticUtils.tap();
    try {
      final res = await AppUpdateService.instance.installApk(path);
      debugPrint('[UpdateDialog] Install result: ${res.type} - ${res.message}');
      if (res.type != ResultType.done && mounted) {
        setState(() {
          _errorMessage = 'Не удалось запустить установщик: ${res.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка запуска установщика: $e';
        });
      }
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel();
    HapticUtils.tap();
  }

  void _dismissDialog() {
    HapticUtils.tap();
    if (!widget.update.forceUpdate) {
      AppUpdateService.instance.ignoreBuild(widget.update.latestBuild);
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isForce = widget.update.forceUpdate;

    return PopScope(
      canPop: !isForce && !_isDownloading,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: theme.dialogBackgroundColor,
        elevation: 8,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Icon
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: isForce
                          ? colorScheme.error.withValues(alpha: 0.12)
                          : colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isForce ? Icons.warning_amber_rounded : Icons.system_update_alt_rounded,
                      size: 28,
                      color: isForce ? colorScheme.error : colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isForce ? 'Требуется обновление' : 'Доступно обновление',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Theaver v${widget.update.latestVersion} (билд ${widget.update.latestBuild})',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (widget.update.formattedSize.isNotEmpty) ...[
                          Text(
                            'Размер: ${widget.update.formattedSize}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Changelog Box
              if (widget.update.releaseNotes.trim().isNotEmpty) ...[
                Text(
                  'Что нового:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      widget.update.releaseNotes.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Error Message
              if (_errorMessage != null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              // Downloading Progress
              if (_isDownloading) ...[
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      borderRadius: BorderRadius.circular(8),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _progress > 0
                              ? '${(_progress * 100).toInt()}%'
                              : 'Загрузка...',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _downloadedText,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _cancelDownload,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Отмена'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (_downloadedFile != null) ...[
                // Downloaded & Ready to install
                FilledButton.icon(
                  onPressed: () => _installApk(_downloadedFile!.path),
                  icon: const Icon(Icons.install_mobile_rounded, size: 20),
                  label: const Text('Установить обновление'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ] else ...[
                // Action Buttons
                Row(
                  children: [
                    if (!isForce) ...[
                      Expanded(
                        child: TextButton(
                          onPressed: _dismissDialog,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Позже'),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      flex: isForce ? 1 : 2,
                      child: FilledButton.icon(
                        onPressed: _startDownload,
                        icon: const Icon(Icons.download_rounded, size: 20),
                        label: const Text('Обновить'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
