import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide FileService;
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '../../l10n/app_localizations.dart';
import '../../services/file_service.dart';
import '../../utils/image_utils.dart';
import '../../utils/haptic_utils.dart';

/// Полноэкранный просмотрщик аватарок в стиле Telegram.
///
/// Поддерживает:
/// - Листание аватарок (PageView, боковые стрелки < / >, клавиши ← / →)
/// - Масштабирование и приближение (pinch-to-zoom и колёсико мыши)
/// - Сохранение фото в галерею/загрузки
/// - Поделиться фото
/// - Свайп вверх/вниз или клавиша Esc для закрытия
/// - Индикатор страниц и действия (Удалить / Выбрать новое фото)
class AvatarGalleryViewer extends StatefulWidget {
  final List<String> avatarUrls;
  final int initialIndex;
  final String? displayName;
  final VoidCallback? onChoosePhoto;
  final Function(int index)? onDelete;
  final Function(int index)? onPageChanged;

  final String? heroTagPrefix;

  const AvatarGalleryViewer({
    Key? key,
    required this.avatarUrls,
    this.initialIndex = 0,
    this.displayName,
    this.heroTagPrefix = 'avatar_hero',
    this.onChoosePhoto,
    this.onDelete,
    this.onPageChanged,
  }) : super(key: key);

  /// Открывает просмотрщик аватарок как полноэкранный диалог
  static Future<void> open(
    BuildContext context, {
    required List<String> avatarUrls,
    int initialIndex = 0,
    String? displayName,
    String? heroTagPrefix = 'avatar_hero',
    VoidCallback? onChoosePhoto,
    Function(int index)? onDelete,
    Function(int index)? onPageChanged,
  }) {
    if (avatarUrls.isEmpty) return Future.value();

    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (context, animation, secondaryAnimation) => AvatarGalleryViewer(
          avatarUrls: avatarUrls,
          initialIndex: initialIndex,
          displayName: displayName,
          heroTagPrefix: heroTagPrefix,
          onChoosePhoto: onChoosePhoto,
          onDelete: onDelete,
          onPageChanged: onPageChanged,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<AvatarGalleryViewer> createState() => _AvatarGalleryViewerState();
}

class _AvatarGalleryViewerState extends State<AvatarGalleryViewer> {
  late int _currentIndex;
  late PageController _pageController;
  final FocusNode _focusNode = FocusNode();
  final Map<int, PhotoViewController> _photoControllers = {};
  final Map<int, double> _baseScales = {};
  bool _isSaving = false;
  double _verticalDragOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, mathMax(0, widget.avatarUrls.length - 1));
    _pageController = PageController(initialPage: _currentIndex);
  }

  int mathMax(int a, int b) => a > b ? a : b;

  PhotoViewController _controllerForIndex(int index) {
    return _photoControllers.putIfAbsent(index, () => PhotoViewController());
  }

  void _goToPrev() {
    if (_currentIndex <= 0) return;
    HapticUtils.selection();
    _pageController.animateToPage(
      _currentIndex - 1,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToNext() {
    if (_currentIndex >= widget.avatarUrls.length - 1) return;
    HapticUtils.selection();
    _pageController.animateToPage(
      _currentIndex + 1,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goToPrev();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goToNext();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0.0) return;

    final ctrl = _controllerForIndex(_currentIndex);
    final currentScale = ctrl.scale;
    if (currentScale == null || currentScale <= 0) return;

    final baseScale = _baseScales.putIfAbsent(_currentIndex, () => currentScale);
    final zoomFactor = dy < 0 ? 1.16 : (1.0 / 1.16);
    final nextScale = (currentScale * zoomFactor).clamp(baseScale, baseScale * 4.0);
    ctrl.scale = nextScale;
    if ((nextScale - baseScale).abs() < 0.01) {
      ctrl.position = Offset.zero;
    }
  }

  @override
  void dispose() {
    for (final ctrl in _photoControllers.values) {
      ctrl.dispose();
    }
    _focusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<File?> _getLocalImageFile(String url) async {
    try {
      if (url.startsWith('file://')) {
        final filePath = Uri.parse(url).toFilePath();
        final file = File(filePath);
        if (await file.exists()) return file;
      }
      final localFile = File(url);
      if (await localFile.exists()) {
        return localFile;
      }

      // Если это data: URL (base64)
      if (url.startsWith('data:')) {
        final commaIndex = url.indexOf(',');
        final base64Str = url.substring(commaIndex + 1);
        final bytes = Uri.parse('data:;base64,$base64Str').data!.contentAsBytes();
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/avatar_temp_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await file.writeAsBytes(bytes);
        return file;
      }

      // Проверка локального кэша CachedNetworkImage/DefaultCacheManager
      final validUrl = getValidAvatarUrl(url) ?? url;
      try {
        final cached = await DefaultCacheManager().getFileFromCache(validUrl);
        if (cached != null && await cached.file.exists()) {
          return cached.file;
        }
      } catch (_) {}

      // Скачивание сетевого файла
      final response = await http.get(Uri.parse(validUrl));
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/avatar_temp_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
    } catch (e) {
      debugPrint('[AvatarGalleryViewer] Error getting image file: $e');
    }
    return null;
  }

  String _tr(BuildContext context, String key, String fallback) {
    try {
      final val = context.l10n.translate(key);
      if (val.isNotEmpty && val != key) return val;
    } catch (_) {}
    return fallback;
  }

  Future<void> _saveToGallery() async {
    if (_currentIndex >= widget.avatarUrls.length) return;
    setState(() => _isSaving = true);

    final url = widget.avatarUrls[_currentIndex];
    try {
      final file = await _getLocalImageFile(url);
      if (file == null || !await file.exists()) {
        throw Exception('Unable to load image');
      }

      // Сохраняем в пользовательскую директорию Загрузок
      final downloadDirPath = await FileService().getDefaultDownloadDirectory();
      final downloadsDir = Directory(downloadDirPath);
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final targetFile = File('${downloadsDir.path}/theaver_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.copy(targetFile.path);

      HapticUtils.impact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr(
              context,
              'profile_avatar_saved',
              'Фото сохранено в память устройства',
            )),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[AvatarGalleryViewer] Error saving image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(context, 'profile_save_error', 'Ошибка сохранения: {error}')
                  .replaceAll('{error}', e.toString()),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _shareImage() async {
    if (_currentIndex >= widget.avatarUrls.length) return;
    final url = widget.avatarUrls[_currentIndex];
    final file = await _getLocalImageFile(url);
    if (file != null && await file.exists()) {
      final shareText = (widget.displayName != null && widget.displayName!.isNotEmpty)
          ? widget.displayName!
          : 'Theaver';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: shareText,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = widget.avatarUrls.length;
    final titleText = totalCount > 1
        ? _tr(context, 'profile_avatar_counter', '{current} из {total}')
            .replaceAll('{current}', '${_currentIndex + 1}')
            .replaceAll('{total}', '$totalCount')
        : (widget.displayName ?? _tr(context, 'profile_avatar_title', 'Аватар'));

    final dragProgress = (_verticalDragOffset.abs() / 260.0).clamp(0.0, 1.0);
    final bgOpacity = (1.0 - dragProgress * 0.72).clamp(0.0, 1.0);
    final uiOpacity = (1.0 - dragProgress * 1.4).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: bgOpacity),
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Opacity(
          opacity: uiOpacity,
          child: AppBar(
            backgroundColor: Colors.black.withValues(alpha: 0.4 * bgOpacity),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              titleText,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined, color: Colors.white),
                tooltip: _tr(context, 'share', 'Поделиться'),
                onPressed: _shareImage,
              ),
              IconButton(
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download_rounded, color: Colors.white),
                tooltip: _tr(context, 'profile_save', 'Сохранить'),
                onPressed: _saveToGallery,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) {
                  switch (value) {
                    case 'save':
                      _saveToGallery();
                      break;
                    case 'share':
                      _shareImage();
                      break;
                    case 'choose':
                      Navigator.pop(context);
                      widget.onChoosePhoto?.call();
                      break;
                    case 'delete':
                      HapticUtils.heavy();
                      widget.onDelete?.call(_currentIndex);
                      if (widget.avatarUrls.length <= 1) {
                        Navigator.pop(context);
                      }
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'save',
                    child: ListTile(
                      leading: const Icon(Icons.save_alt, color: Color(0xFF0088CC)),
                      title: Text(_tr(context, 'profile_save_to_gallery', 'Сохранить в галерею')),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: ListTile(
                      leading: const Icon(Icons.share, color: Color(0xFF0088CC)),
                      title: Text(_tr(context, 'share', 'Поделиться')),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (widget.onChoosePhoto != null)
                    PopupMenuItem(
                      value: 'choose',
                      child: ListTile(
                        leading: const Icon(Icons.add_a_photo, color: Color(0xFF0088CC)),
                        title: Text(_tr(context, 'profile_choose_new_photo', 'Выбрать новое фото')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (widget.onDelete != null)
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline, color: Colors.red),
                        title: Text(
                          _tr(context, 'profile_delete_photo', 'Удалить фото'),
                          style: const TextStyle(color: Colors.red),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: _handlePointerSignal,
          child: GestureDetector(
            onVerticalDragUpdate: (details) {
              setState(() {
                _verticalDragOffset += details.delta.dy;
              });
            },
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0.0;
              if (_verticalDragOffset.abs() > 85.0 || velocity.abs() > 400.0) {
                Navigator.pop(context);
              } else {
                setState(() {
                  _verticalDragOffset = 0.0;
                });
              }
            },
            child: Stack(
              children: [
                if (totalCount > 0)
                  Transform.translate(
                    offset: Offset(0, _verticalDragOffset),
                    child: PhotoViewGallery.builder(
                      scrollPhysics: const BouncingScrollPhysics(),
                      builder: (context, index) {
                        final url = widget.avatarUrls[index];
                        final provider = avatarImageProvider(url) ?? NetworkImage(url);
                        final tag = widget.heroTagPrefix != null ? '${widget.heroTagPrefix}_$url' : 'avatar_hero_$url';
                        return PhotoViewGalleryPageOptions(
                          imageProvider: provider,
                          controller: _controllerForIndex(index),
                          filterQuality: FilterQuality.medium,
                          initialScale: PhotoViewComputedScale.contained,
                          minScale: PhotoViewComputedScale.contained,
                          maxScale: PhotoViewComputedScale.covered * 4.0,
                          heroAttributes: PhotoViewHeroAttributes(tag: tag),
                        );
                      },
                      itemCount: totalCount,
                      loadingBuilder: (context, event) => const Center(
                        child: CircularProgressIndicator(color: Color(0xFF0088CC)),
                      ),
                      backgroundDecoration: const BoxDecoration(color: Colors.transparent),
                      pageController: _pageController,
                      onPageChanged: (index) {
                        setState(() {
                          _currentIndex = index;
                        });
                        widget.onPageChanged?.call(index);
                      },
                    ),
                  ),

                // Боковые кнопки-стрелки «<» и «>» для навигации мышью
                if (totalCount > 1 && _currentIndex > 0)
                  Positioned(
                    left: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Opacity(
                        opacity: uiOpacity,
                        child: _GalleryNavArrowButton(
                          isLeft: true,
                          onTap: _goToPrev,
                        ),
                      ),
                    ),
                  ),
                if (totalCount > 1 && _currentIndex < totalCount - 1)
                  Positioned(
                    right: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Opacity(
                        opacity: uiOpacity,
                        child: _GalleryNavArrowButton(
                          isLeft: false,
                          onTap: _goToNext,
                        ),
                      ),
                    ),
                  ),

                // Точки-индикаторы снизу (если аватарок больше 1)
                if (totalCount > 1)
                  Positioned(
                    bottom: 30,
                    left: 0,
                    right: 0,
                    child: Opacity(
                      opacity: uiOpacity,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(totalCount, (index) {
                          return GestureDetector(
                            onTap: () {
                              if (_currentIndex != index) {
                                HapticUtils.selection();
                                _pageController.animateToPage(
                                  index,
                                  duration: const Duration(milliseconds: 240),
                                  curve: Curves.easeOutCubic,
                                );
                              }
                            },
                            child: Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _currentIndex == index
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryNavArrowButton extends StatefulWidget {
  final bool isLeft;
  final VoidCallback onTap;

  const _GalleryNavArrowButton({
    required this.isLeft,
    required this.onTap,
  });

  @override
  State<_GalleryNavArrowButton> createState() => _GalleryNavArrowButtonState();
}

class _GalleryNavArrowButtonState extends State<_GalleryNavArrowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: _hovered ? 0.62 : 0.42),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: _hovered ? 0.28 : 0.14),
                  width: 0.5,
                ),
              ),
              child: widget.isLeft
                  ? const iconoir.NavArrowLeft(
                      width: 24,
                      height: 24,
                      color: Colors.white,
                    )
                  : const iconoir.NavArrowRight(
                      width: 24,
                      height: 24,
                      color: Colors.white,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
