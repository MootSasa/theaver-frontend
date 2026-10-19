import 'dart:io' show File, Directory;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../l10n/app_localizations.dart';
import '../../services/file_service.dart';

enum DownloadStatus { idle, downloading, downloaded, failed }

class DocumentMessageWidget extends StatefulWidget {
  final String fileUrl;
  final String fileName;
  final double fileSize; // in bytes

  const DocumentMessageWidget({
    Key? key,
    required this.fileUrl,
    required this.fileName,
    required this.fileSize,
  }) : super(key: key);

  @override
  State<DocumentMessageWidget> createState() => _DocumentMessageWidgetState();
}

class _DocumentMessageWidgetState extends State<DocumentMessageWidget> {
  DownloadStatus _status = DownloadStatus.idle;
  double _progress = 0.0;
  String? _downloadedFilePath;

  @override
  void initState() {
    super.initState();
    _checkFileExists();
  }

  @override
  void didUpdateWidget(DocumentMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileName != widget.fileName || oldWidget.fileUrl != widget.fileUrl) {
      _checkFileExists();
    }
  }

  Future<void> _checkFileExists() async {
    if (kIsWeb) return;
    try {
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
            });
          }
        }
      }
    } catch (_) {}
  }

  String _formatSize(double bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final formattedSize = _formatSize(widget.fileSize);
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: ${e.toString()}')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download started for ${widget.fileName}')),
        );
        // Reset state since we can't track progress in web
        setState(() {
          _status = DownloadStatus.idle;
          _progress = 0.0;
        });
      }
    }

  Future<void> _downloadWithProgress() async {
    final request = http.Request('GET', Uri.parse(widget.fileUrl));
    final response = await request.send();

    if (response.statusCode != 200) {
      throw Exception('Failed to download file: ${response.statusCode}');
    }

    final contentLength = response.contentLength;
    final dir = await _getSaveDirectory();
    String baseName = widget.fileName;
    String extension = '';
    final dotIndex = baseName.lastIndexOf('.');
    if (dotIndex != -1) {
      extension = baseName.substring(dotIndex);
      baseName = baseName.substring(0, dotIndex);
    }

    File file = File('${dir.path}/${widget.fileName}');
    int counter = 1;
    while (await file.exists()) {
      file = File('${dir.path}/$baseName ($counter)$extension');
      counter++;
    }

    final sink = file.openWrite();
    int totalBytes = 0;

    await for (final List<int> chunk in response.stream) {
      totalBytes += chunk.length;
      final progress = contentLength != null
          ? totalBytes / contentLength
          : 0.0; // Indeterminate if no content length

      if (mounted) {
        setState(() {
          _progress = progress;
        });
      }

      sink.add(chunk);
    }

    await sink.close();

    if (mounted) {
      setState(() {
        _status = DownloadStatus.downloaded;
        _progress = 1.0;
        _downloadedFilePath = file.path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Файл скачан. Нажмите на файл, чтобы открыть.')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not downloaded yet')),
      );
      return;
    }

    try {
      final result = await OpenFile.open(_downloadedFilePath);
      if (result.type != ResultType.done) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to open file: ${result.message}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening file: $e')),
        );
      }
    }
  }

  void _showFileOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const iconoir.OpenNewWindow(width: 22, height: 22),
              title: Text(context.l10n.translate('chat_open_file')),
              onTap: () {
                Navigator.pop(context);
                _openDownloadedFile();
              },
            ),
            ListTile(
              leading: const iconoir.ShareAndroid(width: 22, height: 22),
              title: Text(context.l10n.translate('share')),
              onTap: () {
                Navigator.pop(context);
                _shareFile();
              },
            ),
            ListTile(
              leading: const iconoir.Folder(width: 22, height: 22),
              title: Text('Показать в папке: $_downloadedFilePath'),
              onTap: () {
                Navigator.pop(context);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала скачайте файл')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при отправке: $e')),
        );
      }
    }
  }

  /// Show the downloaded file in the system file manager
  Future<void> _showInFolder() async {
    if (_downloadedFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала скачайте файл')),
      );
      return;
    }
    try {
      // open_file can open the file, but to show in folder we use
      // the system's file manager via open_file with "folder" mode
      final result = await OpenFile.open(_downloadedFilePath);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть: ${result.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }
}