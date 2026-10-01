import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/common/adaptive_switch.dart';

enum MediaQuality {
  sd,
  hd,
  fhd,
  original;

  String get label {
    switch (this) {
      case MediaQuality.sd:
        return 'SD';
      case MediaQuality.hd:
        return 'HD';
      case MediaQuality.fhd:
        return 'FHD';
      case MediaQuality.original:
        return 'Hi-Res';
    }
  }

  String get resolutionText {
    switch (this) {
      case MediaQuality.sd:
        return '480p';
      case MediaQuality.hd:
        return '720p';
      case MediaQuality.fhd:
        return '1080p';
      case MediaQuality.original:
        return 'Original';
    }
  }

  IconData get badgeIcon {
    switch (this) {
      case MediaQuality.sd:
        return Icons.sd_rounded;
      case MediaQuality.hd:
        return Icons.hd_rounded;
      case MediaQuality.fhd:
        return Icons.high_quality_rounded;
      case MediaQuality.original:
        return Icons.auto_awesome_rounded;
    }
  }

  int get maxEdge {
    switch (this) {
      case MediaQuality.sd:
        return 854;
      case MediaQuality.hd:
        return 1280;
      case MediaQuality.fhd:
        return 1920;
      case MediaQuality.original:
        return 0; // No resize
    }
  }

  int get compressionQuality {
    switch (this) {
      case MediaQuality.sd:
        return 65;
      case MediaQuality.hd:
        return 80;
      case MediaQuality.fhd:
        return 90;
      case MediaQuality.original:
        return 100;
    }
  }
}

class MediaSendResult {
  final List<File> files;
  final String? caption;
  final bool asDocument;
  final MediaQuality quality;

  const MediaSendResult({
    required this.files,
    this.caption,
    this.asDocument = false,
    this.quality = MediaQuality.hd,
  });
}

class MediaSendScreen extends StatefulWidget {
  final List<File> initialFiles;
  final String? initialCaption;

  const MediaSendScreen({
    Key? key,
    required this.initialFiles,
    this.initialCaption,
  }) : super(key: key);

  @override
  State<MediaSendScreen> createState() => _MediaSendScreenState();
}

class _MediaSendScreenState extends State<MediaSendScreen> {
  late List<File> _files;
  late PageController _pageController;
  late TextEditingController _captionController;
  int _currentIndex = 0;
  MediaQuality _selectedQuality = MediaQuality.hd;
  bool _asDocument = false;
  bool _isCompressing = false;

  final Map<int, VideoPlayerController> _videoControllers = {};

  @override
  void initState() {
    super.initState();
    _files = List<File>.from(widget.initialFiles);
    _pageController = PageController(initialPage: 0);
    _captionController = TextEditingController(text: widget.initialCaption);
    _initVideoForIndex(0);
  }

  @override
  void dispose() {
    for (final controller in _videoControllers.values) {
      controller.dispose();
    }
    _pageController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  bool _isVideo(File file) {
    final ext = p.extension(file.path).toLowerCase();
    return ext == '.mp4' || ext == '.mov' || ext == '.avi' || ext == '.mkv' || ext == '.webm';
  }

  Future<void> _initVideoForIndex(int index) async {
    if (index < 0 || index >= _files.length) return;
    final file = _files[index];
    if (!_isVideo(file)) return;
    if (_videoControllers.containsKey(index)) return;

    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (mounted) {
        setState(() {
          _videoControllers[index] = controller;
        });
      }
    } catch (e) {
      debugPrint('[MediaSendScreen] Error initializing video: $e');
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    // Pause inactive video controllers
    _videoControllers.forEach((idx, ctrl) {
      if (idx != index && ctrl.value.isPlaying) {
        ctrl.pause();
      }
    });
    _initVideoForIndex(index);
  }

  Future<void> _cropCurrentImage() async {
    if (_files.isEmpty || _currentIndex >= _files.length) return;
    final file = _files[_currentIndex];
    if (_isVideo(file)) return;

    final l10n = AppLocalizations.of(context);
    final cropped = await ImageCropper().cropImage(
      sourcePath: file.path,
      compressQuality: 95,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: l10n?.translate('crop_image') ?? 'Crop & Rotate',
          toolbarColor: const Color(0xFF1E1E24),
          statusBarLight: false,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFF33A9FF),
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(
          title: l10n?.translate('crop_image') ?? 'Crop & Rotate',
          aspectRatioLockEnabled: false,
          resetAspectRatioEnabled: true,
        ),
      ],
    );

    if (cropped != null) {
      setState(() {
        _files[_currentIndex] = File(cropped.path);
      });
    }
  }

  void _removeCurrentFile() {
    if (_files.length <= 1) {
      Navigator.pop(context);
      return;
    }

    final removedIndex = _currentIndex;
    _videoControllers[removedIndex]?.dispose();
    _videoControllers.remove(removedIndex);

    setState(() {
      _files.removeAt(removedIndex);
      if (_currentIndex >= _files.length) {
        _currentIndex = _files.length - 1;
      }
    });

    _pageController.jumpToPage(_currentIndex);
    _initVideoForIndex(_currentIndex);
  }

  void _showQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E24) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black26,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Качество отправки / Quality',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.titleMedium?.color,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...MediaQuality.values.map((q) {
                  final isSelected = q == _selectedQuality;
                  return InkWell(
                    onTap: () {
                      setState(() => _selectedQuality = q);
                      Navigator.pop(ctx);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF33A9FF).withValues(alpha: 0.15)
                                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF33A9FF)
                                    : (isDark ? Colors.white24 : Colors.black12),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  q.badgeIcon,
                                  size: 16,
                                  color: isSelected ? const Color(0xFF33A9FF) : theme.iconTheme.color,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  q.label,
                                  style: GoogleFonts.rubik(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? const Color(0xFF33A9FF) : theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  q.resolutionText,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: theme.textTheme.bodyLarge?.color,
                                  ),
                                ),
                                Text(
                                  q == MediaQuality.original
                                      ? 'Без сжатия / Uncompressed file'
                                      : 'Сжатие до ${q.resolutionText} / Optimized',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF33A9FF),
                              size: 22,
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                const Divider(height: 24),
                // Send as document switch
                AdaptiveSwitchListTile.adaptive(
                  value: _asDocument,
                  onChanged: (val) {
                    setState(() => _asDocument = val);
                    Navigator.pop(ctx);
                  },
                  title: const Text(
                    'Отправить как файл / As File',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  subtitle: const Text(
                    'Без сжатия в виде документа',
                    style: TextStyle(fontSize: 12),
                  ),
                  activeTrackColor: const Color(0xFF33A9FF),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleSend() async {
    if (_files.isEmpty || _isCompressing) return;

    setState(() => _isCompressing = true);

    try {
      final List<File> readyFiles = [];

      if (_asDocument || _selectedQuality == MediaQuality.original) {
        // Send original files without alteration
        readyFiles.addAll(_files);
      } else {
        final tempDir = await getTemporaryDirectory();
        for (int i = 0; i < _files.length; i++) {
          final file = _files[i];
          if (_isVideo(file)) {
            readyFiles.add(file);
            continue;
          }

          final targetPath = p.join(
            tempDir.path,
            'send_${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
          );

          final compressed = await FlutterImageCompress.compressAndGetFile(
            file.path,
            targetPath,
            minWidth: _selectedQuality.maxEdge,
            minHeight: _selectedQuality.maxEdge,
            quality: _selectedQuality.compressionQuality,
            format: CompressFormat.jpeg,
          );

          if (compressed != null) {
            readyFiles.add(File(compressed.path));
          } else {
            readyFiles.add(file);
          }
        }
      }

      if (mounted) {
        Navigator.pop(
          context,
          MediaSendResult(
            files: readyFiles,
            caption: _captionController.text.trim().isNotEmpty
                ? _captionController.text.trim()
                : null,
            asDocument: _asDocument,
            quality: _selectedQuality,
          ),
        );
      }
    } catch (e) {
      debugPrint('[MediaSendScreen] Error processing media: $e');
      if (mounted) {
        Navigator.pop(
          context,
          MediaSendResult(
            files: _files,
            caption: _captionController.text.trim().isNotEmpty
                ? _captionController.text.trim()
                : null,
            asDocument: _asDocument,
            quality: _selectedQuality,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCompressing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentFile = _files.isNotEmpty && _currentIndex < _files.length
        ? _files[_currentIndex]
        : null;
    final isVideo = currentFile != null && _isVideo(currentFile);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 1. PageView for Fullscreen Media Preview
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _files.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final file = _files[index];
                  final isVid = _isVideo(file);

                  if (isVid) {
                    final ctrl = _videoControllers[index];
                    if (ctrl != null && ctrl.value.isInitialized) {
                      return Center(
                        child: AspectRatio(
                          aspectRatio: ctrl.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(ctrl),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
                                  });
                                },
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    ctrl.value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white70),
                    );
                  }

                  return InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 3.5,
                    child: Center(
                      child: Image.file(
                        file,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
            ),

            // 2. Top Bar (Close, Quality Badge, Crop/Edit, Delete)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),

                    // Resolution Quality Badge with GoogleFonts
                    GestureDetector(
                      onTap: _showQualityPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF33A9FF).withValues(alpha: 0.7),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _selectedQuality.badgeIcon,
                              size: 16,
                              color: const Color(0xFF33A9FF),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _selectedQuality.label,
                              style: GoogleFonts.rubik(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Crop/Edit Button (only for images)
                    if (!isVideo)
                      IconButton(
                        icon: const Icon(Icons.crop_rotate_rounded, color: Colors.white, size: 24),
                        onPressed: _cropCurrentImage,
                      ),

                    // Remove current item button (if multiple)
                    if (_files.length > 1)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
                        onPressed: _removeCurrentFile,
                      ),
                  ],
                ),
              ),
            ),

            // 3. Bottom Bar (Thumbnails strip, Caption Input, Send Button)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.only(left: 12, right: 12, top: 10, bottom: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Multi-item Thumbnail Strip
                    if (_files.length > 1) ...[
                      SizedBox(
                        height: 52,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _files.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, idx) {
                            final file = _files[idx];
                            final isSel = idx == _currentIndex;
                            return GestureDetector(
                              onTap: () {
                                _pageController.jumpToPage(idx);
                              },
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSel ? const Color(0xFF33A9FF) : Colors.white24,
                                    width: isSel ? 2.5 : 1.0,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: _isVideo(file)
                                      ? Container(
                                          color: const Color(0xFF222226),
                                          child: const Icon(
                                            Icons.videocam_rounded,
                                            color: Colors.white70,
                                            size: 24,
                                          ),
                                        )
                                      : Image.file(
                                          file,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Caption Input & Send Button Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E24).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                                width: 1.0,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: TextField(
                              controller: _captionController,
                              maxLines: 4,
                              minLines: 1,
                              style: const TextStyle(color: Colors.white, fontSize: 15),
                              cursorColor: const Color(0xFF33A9FF),
                              decoration: const InputDecoration(
                                hintText: 'Добавить подпись... / Add caption...',
                                hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Send Button
                        GestureDetector(
                          onTap: _isCompressing ? null : _handleSend,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF33A9FF), Color(0xFF0077E6)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0077E6).withValues(alpha: 0.45),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Center(
                              child: _isCompressing
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.0,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.arrow_upward_rounded,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
