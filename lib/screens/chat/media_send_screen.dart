import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:image_cropper/image_cropper.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../../services/settings_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/chat/send_options_popup.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/message/media_spoiler_overlay.dart';

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
        return 0;
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
  final bool hasMediaSpoiler;
  final bool isSilent;
  final DateTime? scheduleAt;
  final bool sendWhenOnline;
  final Map<String, String> captionsByPath;

  const MediaSendResult({
    required this.files,
    this.caption,
    this.asDocument = false,
    this.quality = MediaQuality.hd,
    this.hasMediaSpoiler = false,
    this.isSilent = false,
    this.scheduleAt,
    this.sendWhenOnline = false,
    this.captionsByPath = const {},
  });
}

class MediaSendScreen extends StatefulWidget {
  final List<File> initialFiles;
  final String? initialCaption;
  final bool isPrivateChat;
  final bool isPeerOnline;
  final bool showSilentOption;

  const MediaSendScreen({
    super.key,
    required this.initialFiles,
    this.initialCaption,
    this.isPrivateChat = false,
    this.isPeerOnline = true,
    this.showSilentOption = true,
  });

  @override
  State<MediaSendScreen> createState() => _MediaSendScreenState();
}

class _MediaSendScreenState extends State<MediaSendScreen> {
  late List<File> _files;
  late PageController _pageController;
  final FocusNode _captionFocusNode = FocusNode();
  int _currentIndex = 0;
  MediaQuality _selectedQuality = MediaQuality.hd;
  bool _asDocument = false;
  bool _hasMediaSpoiler = false;
  bool _isCompressing = false;

  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, TextEditingController> _captionControllers = {};

  bool get _isDesktop {
    if (kIsWeb) return true;
    return !Platform.isAndroid && !Platform.isIOS;
  }

  TextEditingController _captionControllerFor(File file) {
    return _captionControllers.putIfAbsent(
      file.path,
      () => TextEditingController(),
    );
  }

  TextEditingController? get _activeCaptionController {
    if (_files.isEmpty || _currentIndex < 0 || _currentIndex >= _files.length) {
      return null;
    }
    return _captionControllerFor(_files[_currentIndex]);
  }

  @override
  void initState() {
    super.initState();
    _files = List<File>.from(widget.initialFiles);
    _pageController = PageController(initialPage: 0);
    if (_files.isNotEmpty) {
      final firstCtrl = TextEditingController(text: widget.initialCaption);
      _captionControllers[_files.first.path] = firstCtrl;
      _initVideoForFile(_files.first);
    }
    if (_isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctrl = _activeCaptionController;
        if (mounted && ctrl != null) {
          _captionFocusNode.requestFocus();
          ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _videoControllers.values) {
      controller.dispose();
    }
    _videoControllers.clear();
    for (final controller in _captionControllers.values) {
      controller.dispose();
    }
    _captionControllers.clear();
    _pageController.dispose();
    _captionFocusNode.dispose();
    super.dispose();
  }

  void _insertCaptionNewline() {
    final ctrl = _activeCaptionController;
    if (ctrl == null) return;
    final value = ctrl.value;
    final sel = value.selection;
    final int start = sel.isValid ? sel.start : value.text.length;
    final int end = sel.isValid ? sel.end : value.text.length;
    final newText = value.text.replaceRange(start, end, '\n');
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  KeyEventResult _handleCaptionKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final hw = HardwareKeyboard.instance;
      final isCtrlOrMeta = hw.isControlPressed || hw.isMetaPressed;
      final isShift = hw.isShiftPressed;
      final sendByEnter = SettingsService().sendByEnter;

      if (sendByEnter) {
        if (isShift || isCtrlOrMeta) {
          _insertCaptionNewline();
          return KeyEventResult.handled;
        }
        if (!_isCompressing) {
          _handleSend();
        }
        return KeyEventResult.handled;
      } else {
        if (isCtrlOrMeta) {
          if (!_isCompressing) {
            _handleSend();
          }
          return KeyEventResult.handled;
        }
        _insertCaptionNewline();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  bool _isVideo(File file) {
    final ext = p.extension(file.path).toLowerCase();
    return ext == '.mp4' ||
        ext == '.mov' ||
        ext == '.avi' ||
        ext == '.mkv' ||
        ext == '.webm';
  }

  Future<void> _initVideoForFile(File file) async {
    if (!_isVideo(file)) return;
    if (_videoControllers.containsKey(file.path)) return;

    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (mounted && _files.any((f) => f.path == file.path)) {
        setState(() {
          _videoControllers[file.path] = controller;
        });
      } else {
        await controller.dispose();
      }
    } catch (e) {
      debugPrint('[MediaSendScreen] Error initializing video: $e');
      await controller.dispose();
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    final activePath = (index >= 0 && index < _files.length)
        ? _files[index].path
        : null;
    _videoControllers.forEach((path, ctrl) {
      if (path != activePath && ctrl.value.isPlaying) {
        ctrl.pause();
      }
    });
    if (index >= 0 && index < _files.length) {
      _initVideoForFile(_files[index]);
    }
  }

  Future<void> _cropCurrentImage() async {
    if (kIsWeb || _files.isEmpty || _currentIndex >= _files.length) return;
    final file = _files[_currentIndex];
    if (_isVideo(file)) return;

    final l10n = AppLocalizations.of(context);
    final palette = context.theav;
    final cropped = await ImageCropper().cropImage(
      sourcePath: file.path,
      compressQuality: 95,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: l10n?.translate('crop_image') ?? 'Обрезка',
          toolbarColor: Colors.black,
          statusBarLight: false,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: palette.primary,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(
          title: l10n?.translate('crop_image') ?? 'Обрезка',
          aspectRatioLockEnabled: false,
          resetAspectRatioEnabled: true,
        ),
      ],
    );

    if (cropped != null && mounted) {
      final oldPath = file.path;
      final newPath = cropped.path;
      setState(() {
        if (oldPath != newPath) {
          final prevCaption = _captionControllers.remove(oldPath);
          final prevText = prevCaption?.text ?? '';
          if (prevCaption != null) {
            Future.delayed(
              const Duration(milliseconds: 200),
              prevCaption.dispose,
            );
          }
          _captionControllers[newPath] = TextEditingController(text: prevText);
          _videoControllers.remove(oldPath)?.dispose();
        }
        _files[_currentIndex] = File(newPath);
      });
    }
  }

  void _removeCurrentFile() {
    if (_files.length <= 1) {
      Navigator.pop(context);
      return;
    }

    final removedIndex = _currentIndex;
    final removedFile = _files[removedIndex];
    _videoControllers.remove(removedFile.path)?.dispose();
    _captionControllers.remove(removedFile.path)?.dispose();

    setState(() {
      _files.removeAt(removedIndex);
      if (_currentIndex >= _files.length) {
        _currentIndex = _files.length - 1;
      }
    });

    _pageController.jumpToPage(_currentIndex);
    if (_files.isNotEmpty) {
      _initVideoForFile(_files[_currentIndex]);
    }
  }

  void _showQualityPicker() {
    showTheavModalSheet<void>(
      context: context,
      title: 'Качество отправки',
      builder: (ctx) {
        final palette = ctx.theav;
        return StatefulBuilder(
          builder: (ctx, setSheetState) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TheavInsetGroup(
                  dividerIndent: 64,
                  children: [
                    for (final q in MediaQuality.values)
                      TheavListRow(
                        leading: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: q == _selectedQuality
                                ? palette.primary.withValues(alpha: 0.14)
                                : palette.onSurface.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                q.badgeIcon,
                                size: 15,
                                color: q == _selectedQuality
                                    ? palette.primary
                                    : palette.subtext,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                q.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: q == _selectedQuality
                                      ? palette.primary
                                      : palette.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        title: q.resolutionText,
                        subtitle: q == MediaQuality.original
                            ? 'Без сжатия'
                            : 'Оптимизация до ${q.resolutionText}',
                        trailing: TheavCheckCircle(
                          selected: q == _selectedQuality,
                        ),
                        onTap: () {
                          setState(() => _selectedQuality = q);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TheavInsetGroup(
                  children: [
                    TheavListRow(
                      leading: iconoir.Page(
                        width: 20,
                        height: 20,
                        color: palette.primary,
                      ),
                      title: 'Отправить как файл',
                      subtitle: 'Без сжатия в виде документа',
                      trailing: TheavSwitch(
                        value: _asDocument,
                        onChanged: (val) {
                          setState(() {
                            _asDocument = val;
                            if (val) _hasMediaSpoiler = false;
                          });
                          setSheetState(() {});
                          Navigator.pop(ctx);
                        },
                      ),
                      onTap: () {
                        setState(() {
                          _asDocument = !_asDocument;
                          if (_asDocument) _hasMediaSpoiler = false;
                        });
                        setSheetState(() {});
                        Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleSendLongPress() async {
    if (_files.isEmpty || _isCompressing) return;
    HapticUtils.selection();
    final choice = await showSendOptionsPopup(
      context: context,
      isPrivateChat: widget.isPrivateChat,
      isPeerOnline: widget.isPeerOnline,
      showSilentOption: widget.showSilentOption,
    );
    if (!mounted || choice == null) return;

    if (choice == SendOptionChoice.sendSilent) {
      await _handleSend(isSilent: true);
    } else if (choice == SendOptionChoice.schedule) {
      final scheduleAt = await showTheavScheduleSheet(context: context);
      if (mounted && scheduleAt != null) {
        await _handleSend(scheduleAt: scheduleAt);
      }
    } else if (choice == SendOptionChoice.sendWhenOnline) {
      await _handleSend(sendWhenOnline: true);
    }
  }

  Future<void> _handleSend({
    bool isSilent = false,
    DateTime? scheduleAt,
    bool sendWhenOnline = false,
  }) async {
    if (_files.isEmpty || _isCompressing) return;

    setState(() => _isCompressing = true);

    final Map<String, String> captionsByPath = {};
    final String activeCaption =
        _activeCaptionController?.text.trim() ?? '';
    String? resolvedCaption = activeCaption.isNotEmpty ? activeCaption : null;

    try {
      final List<File> readyFiles = [];

      if (_asDocument || _selectedQuality == MediaQuality.original) {
        for (final file in _files) {
          readyFiles.add(file);
          final cap = _captionControllers[file.path]?.text.trim() ?? '';
          if (cap.isNotEmpty) {
            captionsByPath[file.path] = cap;
            resolvedCaption ??= cap;
          }
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        for (int i = 0; i < _files.length; i++) {
          final file = _files[i];
          final cap = _captionControllers[file.path]?.text.trim() ?? '';
          File outFile = file;
          if (!_isVideo(file)) {
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
              outFile = File(compressed.path);
            }
          }
          readyFiles.add(outFile);
          if (cap.isNotEmpty) {
            captionsByPath[file.path] = cap;
            captionsByPath[outFile.path] = cap;
            resolvedCaption ??= cap;
          }
        }
      }

      if (mounted) {
        Navigator.pop(
          context,
          MediaSendResult(
            files: readyFiles,
            caption: resolvedCaption,
            asDocument: _asDocument,
            quality: _selectedQuality,
            hasMediaSpoiler: _hasMediaSpoiler && !_asDocument,
            isSilent: isSilent,
            scheduleAt: scheduleAt,
            sendWhenOnline: sendWhenOnline,
            captionsByPath: captionsByPath,
          ),
        );
      }
    } catch (e) {
      debugPrint('[MediaSendScreen] Error processing media: $e');
      for (final file in _files) {
        final cap = _captionControllers[file.path]?.text.trim() ?? '';
        if (cap.isNotEmpty) {
          captionsByPath[file.path] = cap;
          resolvedCaption ??= cap;
        }
      }
      if (mounted) {
        Navigator.pop(
          context,
          MediaSendResult(
            files: _files,
            caption: resolvedCaption,
            asDocument: _asDocument,
            quality: _selectedQuality,
            hasMediaSpoiler: _hasMediaSpoiler && !_asDocument,
            isSilent: isSilent,
            scheduleAt: scheduleAt,
            sendWhenOnline: sendWhenOnline,
            captionsByPath: captionsByPath,
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
    final palette = context.theav;
    final currentFile = _files.isNotEmpty && _currentIndex < _files.length
        ? _files[_currentIndex]
        : null;
    final isVideo = currentFile != null && _isVideo(currentFile);
    final activeController = currentFile != null
        ? _captionControllerFor(currentFile)
        : null;
    final Color hudDarkFill = Colors.black.withValues(alpha: 0.48);

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

                  Widget preview;
                  if (isVid) {
                    final ctrl = _videoControllers[file.path];
                    if (ctrl != null && ctrl.value.isInitialized) {
                      preview = Center(
                        child: AspectRatio(
                          aspectRatio: ctrl.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(ctrl),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    ctrl.value.isPlaying
                                        ? ctrl.pause()
                                        : ctrl.play();
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
                    } else {
                      preview = const Center(
                        child: CircularProgressIndicator(color: Colors.white70),
                      );
                    }
                  } else {
                    preview = GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        if (!_isDesktop) {
                          _captionFocusNode.unfocus();
                        }
                      },
                      child: InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 3.5,
                        child: Center(
                          child: Image.file(
                            file,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    );
                  }

                  return MediaSpoilerOverlay(
                    messageId: 'preview_${file.path}',
                    hasSpoiler: _hasMediaSpoiler && !_asDocument,
                    borderRadius: 0,
                    label: 'Скрыто спойлером',
                    child: preview,
                  );
                },
              ),
            ),

            // 2. 3-Part Floating Top HUD ([X] | [1 из N] | [Spoiler | File | Quality | Crop | Delete])
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    TheavHeaderIconButton(
                      icon: const iconoir.Xmark(
                        width: 20,
                        height: 20,
                        color: Colors.white,
                      ),
                      foregroundColor: Colors.white,
                      backgroundColor: hudDarkFill,
                      tooltip: 'Закрыть',
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Center(
                        child: TheavFloatingSurface(
                          borderRadius: 22,
                          colorOverride: hudDarkFill,
                          child: SizedBox(
                            height: 44,
                            child: Center(
                              widthFactor: 1,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                child: Text(
                                  '${_files.isEmpty ? 0 : _currentIndex + 1} из ${_files.length}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 0,
                      child: TheavFloatingSurface(
                        borderRadius: 22,
                        colorOverride: hudDarkFill,
                        child: SizedBox(
                          height: 44,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _HudActionButton(
                                    tooltip: _asDocument
                                        ? 'Спойлер недоступен для файлов'
                                        : (_hasMediaSpoiler
                                            ? 'Убрать спойлер'
                                            : 'Скрыть под спойлер'),
                                    active: _hasMediaSpoiler && !_asDocument,
                                    enabled: !_asDocument,
                                    activeColor: palette.primary,
                                    onTap: () {
                                      HapticUtils.selection();
                                      setState(() {
                                        _hasMediaSpoiler = !_hasMediaSpoiler;
                                      });
                                    },
                                    child: (_hasMediaSpoiler && !_asDocument)
                                        ? iconoir.EyeClosed(
                                            width: 19,
                                            height: 19,
                                            color: palette.primary,
                                          )
                                        : const iconoir.Eye(
                                            width: 19,
                                            height: 19,
                                            color: Colors.white,
                                          ),
                                  ),
                                  _HudActionButton(
                                    tooltip: _asDocument
                                        ? 'Отправлять как медиа'
                                        : 'Отправить как файл',
                                    active: _asDocument,
                                    activeColor: palette.primary,
                                    onTap: () {
                                      HapticUtils.selection();
                                      setState(() {
                                        _asDocument = !_asDocument;
                                        if (_asDocument) {
                                          _hasMediaSpoiler = false;
                                        }
                                      });
                                    },
                                    child: iconoir.Page(
                                      width: 19,
                                      height: 19,
                                      color: _asDocument
                                          ? palette.primary
                                          : Colors.white,
                                    ),
                                  ),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _showQualityPicker,
                                    child: Container(
                                      height: 32,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: palette.primary
                                            .withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        _selectedQuality.label,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: palette.primary,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (!isVideo && !kIsWeb)
                                    _HudActionButton(
                                      tooltip: 'Обрезать',
                                      onTap: _cropCurrentImage,
                                      child: const iconoir.Crop(
                                        width: 19,
                                        height: 19,
                                        color: Colors.white,
                                      ),
                                    ),
                                  if (_files.length > 1)
                                    _HudActionButton(
                                      tooltip: 'Удалить',
                                      onTap: _removeCurrentFile,
                                      child: const iconoir.Trash(
                                        width: 19,
                                        height: 19,
                                        color: Colors.white,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Bottom Bar (Thumbnails strip, Per-File Caption Input, Send + Long-press)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 10,
                  bottom: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.86),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                              onTap: () => _pageController.jumpToPage(idx),
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSel
                                        ? palette.primary
                                        : Colors.white24,
                                    width: isSel ? 2.5 : 1.0,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: _isVideo(file)
                                      ? Container(
                                          color: Colors.black54,
                                          child: const Center(
                                            child: iconoir.VideoCamera(
                                              width: 22,
                                              height: 22,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        )
                                      : Image.file(file, fit: BoxFit.cover),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TheavFloatingSurface(
                            borderRadius: 22,
                            colorOverride: Colors.black.withValues(alpha: 0.56),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: Focus(
                                canRequestFocus: false,
                                skipTraversal: true,
                                onKeyEvent: _handleCaptionKeyEvent,
                                child: TextField(
                                  controller: activeController,
                                  focusNode: _captionFocusNode,
                                  maxLines: 4,
                                  minLines: 1,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                  ),
                                  cursorColor: palette.primary,
                                  decoration: InputDecoration(
                                    hintText: AppLocalizations.of(context)
                                            ?.translate('chat_add_caption') ??
                                        'Добавить подпись...',
                                    hintStyle: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 14,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(vertical: 11),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _isCompressing ? null : () => _handleSend(),
                          onLongPress:
                              _isCompressing ? null : _handleSendLongPress,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: palette.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      palette.primary.withValues(alpha: 0.42),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Center(
                              child: _isCompressing
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: palette.onPrimary,
                                        strokeWidth: 2.0,
                                      ),
                                    )
                                  : Icon(
                                      Icons.arrow_upward_rounded,
                                      color: palette.onPrimary,
                                      size: 24,
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

class _HudActionButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String tooltip;
  final bool active;
  final bool enabled;
  final Color? activeColor;

  const _HudActionButton({
    required this.child,
    required this.tooltip,
    this.onTap,
    this.active = false,
    this.enabled = true,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final btn = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.35,
        child: Container(
          width: 34,
          height: 36,
          decoration: active
              ? BoxDecoration(
                  color: (activeColor ?? Colors.white).withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                )
              : null,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
    return Tooltip(message: tooltip, child: btn);
  }
}
