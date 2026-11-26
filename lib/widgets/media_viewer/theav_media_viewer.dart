import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    hide FileService;
import 'package:http/http.dart' as http;
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/theav_media_item.dart';
import '../../services/auth_service.dart';
import '../../services/file_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/media_cache_manager.dart';
import '../../services/sticker_service.dart';
import '../../services/video_pip_service.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../design_system/theav_design_system.dart';
import '../message/blurred_media_placeholder.dart';
import 'theav_media_hud.dart';
import 'theav_media_video_surface.dart';
import 'theav_media_viewer_route.dart';
import 'theav_zoomable_media_stage.dart';

/// Unified 120 FPS Telegram-style fullscreen media viewer for photos, videos,
/// GIFs, and profile/suggested avatars across the entire application.
///
/// Architectural guarantees:
/// - Pushes via [TheavMediaViewerRoute] which dynamically sets `opaque = true`
///   at rest so Flutter skips painting heavy underlying `ProfileScreen` /
///   `ChatScreen` subtrees (`0.0 ms/frame`), and restores `opaque = false`
///   immediately when 2D drag-to-dismiss starts.
/// - Zero shaders (`LiquidGlassLens`), zero [BackdropFilter], and zero [Opacity]
///   `saveLayer`s on stage or HUD.
/// - Drives 2D drag-to-dismiss backdrop fade purely via [ValueNotifier] without
///   rebuilding [PageView] items.
/// - Defers host index sync (`onBeforeCloseSyncIndex`) until close so swiping
///   never triggers `ProfileScreen.setState`.
class TheavMediaViewer extends StatefulWidget {
  final List<TheavMediaItem> items;
  final int initialIndex;
  final TheavMediaViewerConfig config;

  const TheavMediaViewer({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.config = const TheavMediaViewerConfig(),
  });

  static Future<T?> open<T>(
    BuildContext context, {
    required List<TheavMediaItem> items,
    int initialIndex = 0,
    TheavMediaViewerConfig config = const TheavMediaViewerConfig(),
  }) {
    if (items.isEmpty) return Future<T?>.value(null);
    return Navigator.of(context, rootNavigator: true).push<T>(
      TheavMediaViewerRoute<T>(
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: Navigator.of(context, rootNavigator: true).context,
        ),
        builder: (_) => TheavMediaViewer(
          items: items,
          initialIndex: initialIndex,
          config: config,
        ),
      ),
    );
  }

  @override
  State<TheavMediaViewer> createState() => _TheavMediaViewerState();
}

class _TheavMediaViewerState extends State<TheavMediaViewer> {
  late List<TheavMediaItem> _items;
  late int _currentIndex;
  late final PageController _pageController;
  final FocusNode _focusNode = FocusNode();

  final ValueNotifier<double> _dragBackdropOpacityNotifier =
      ValueNotifier<double>(1.0);
  final Map<int, TheavVideoPlaybackBridge> _videoBridges =
      <int, TheavVideoPlaybackBridge>{};

  bool _hudVisible = true;
  bool _isZoomed = false;
  bool _isSaving = false;
  bool _isClosing = false;

  TheavMediaViewerRouteScope? _routeScope;

  @override
  void initState() {
    super.initState();
    _items = List<TheavMediaItem>.of(widget.items);
    _currentIndex = _items.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, _items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeScope = TheavMediaViewerRouteScope.maybeOf(context);
  }

  @override
  void dispose() {
    for (final b in _videoBridges.values) {
      b.dispose();
    }
    _videoBridges.clear();
    _dragBackdropOpacityNotifier.dispose();
    _focusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  TheavVideoPlaybackBridge _bridgeForIndex(int index) {
    return _videoBridges.putIfAbsent(
      index,
      () => TheavVideoPlaybackBridge(),
    );
  }

  String _tr(String key, String fallback) {
    try {
      final val = context.l10n.translate(key);
      if (val.isNotEmpty && val != key) return val;
    } catch (_) {}
    return fallback;
  }

  void _syncCloseIndexAndPop({bool fromDrag = false}) {
    if (_isClosing || !mounted) return;
    _isClosing = true;
    widget.config.onBeforeCloseSyncIndex?.call(_currentIndex);
    if (fromDrag) {
      _routeScope?.markDragDismissing();
    } else {
      _routeScope?.setRestingOpaque(false);
    }
    Navigator.of(context).pop();
  }

  void _onPageChanged(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
      _isZoomed = false;
    });
    widget.config.onPageChanged?.call(index);
  }

  void _goToPage(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= _items.length) return;
    if (targetIndex == _currentIndex) return;
    HapticUtils.selection();
    _pageController.animateToPage(
      targetIndex,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _syncCloseIndexAndPop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _goToPage(_currentIndex - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _goToPage(_currentIndex + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      final item = _items[_currentIndex];
      if (item.kind == TheavMediaKind.video) {
        unawaited(_bridgeForIndex(_currentIndex).togglePlayPause());
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.keyM) {
      final item = _items[_currentIndex];
      if (item.kind == TheavMediaKind.video) {
        unawaited(_bridgeForIndex(_currentIndex).toggleMute());
        return KeyEventResult.handled;
      }
    }
    final isCtrlOrMeta = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (isCtrlOrMeta && key == LogicalKeyboardKey.keyS) {
      if (!_items[_currentIndex].hasProtectedContent) {
        unawaited(_saveCurrentItem());
      } else {
        GlassToastService().show(
          context,
          _tr(
            'media_viewer_protected_content',
            'Копирование и сохранение запрещены',
          ),
          icon: Icons.lock_outline_rounded,
        );
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _enterPipForCurrentVideo() async {
    final item = _items[_currentIndex];
    if (item.kind != TheavMediaKind.video) return;
    final bridge = _bridgeForIndex(_currentIndex);
    final VideoPlayerController? liveCtrl = bridge.detachControllerForPip();
    if (liveCtrl == null) return;

    await VideoPipService.instance.enterPip(
      controller: liveCtrl,
      item: item,
      playlist: _items,
      itemIndex: _currentIndex,
      viewerConfig: widget.config,
    );

    if (mounted) {
      _syncCloseIndexAndPop();
    }
  }

  Future<File?> _materializeLocalFile(TheavMediaItem item) async {
    if (kIsWeb) return null;
    if (item.localFilePath != null && item.localFilePath!.isNotEmpty) {
      final f = File(item.localFilePath!);
      if (await f.exists() && await f.length() > 0) return f;
    }
    if (item.memoryBytes != null && item.memoryBytes!.isNotEmpty) {
      final tempDir = await getTemporaryDirectory();
      final f = File(
        p.join(
          tempDir.path,
          'theaver_media_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );
      await f.writeAsBytes(item.memoryBytes!, flush: true);
      return f;
    }

    final resolved = item.resolvedUrl;
    if (resolved.isEmpty) return null;

    if (resolved.startsWith('data:')) {
      final commaIdx = resolved.indexOf(',');
      if (commaIdx != -1) {
        final bytes = base64Decode(resolved.substring(commaIdx + 1));
        final tempDir = await getTemporaryDirectory();
        final f = File(
          p.join(
            tempDir.path,
            'theaver_media_${DateTime.now().millisecondsSinceEpoch}.jpg',
          ),
        );
        await f.writeAsBytes(bytes, flush: true);
        return f;
      }
    }

    if (resolved.startsWith('file://')) {
      final f = File(Uri.parse(resolved).toFilePath());
      if (await f.exists() && await f.length() > 0) return f;
    }

    if (resolved.startsWith('/') &&
        !resolved.startsWith('/api/') &&
        !resolved.startsWith('/uploads/') &&
        !resolved.startsWith('/media/')) {
      final f = File(resolved);
      if (await f.exists() && await f.length() > 0) return f;
    }

    final cached = await MediaCacheManager.instance.getCachedFile(resolved);
    if (cached != null && await cached.exists()) return cached;

    if (item.kind == TheavMediaKind.avatar ||
        item.kind == TheavMediaKind.photo) {
      try {
        final valid =
            stripAvatarCropFragment(getValidAvatarUrl(resolved)) ?? resolved;
        final cachedNet = await DefaultCacheManager().getFileFromCache(valid);
        if (cachedNet != null && await cachedNet.file.exists()) {
          return cachedNet.file;
        }
      } catch (_) {}
    }

    final downloaded = await MediaCacheManager.instance.downloadFile(
      resolved,
      expectedTotalSize: item.fileSize,
    );
    if (downloaded != null && await downloaded.exists()) return downloaded;

    // Authenticated direct HTTP fallback (e.g. for API-hosted avatar endpoints)
    final uri = Uri.tryParse(resolved);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final headers = <String, String>{};
      if (resolved.startsWith(AppConfig.baseUrl)) {
        final token = await AuthService.getToken();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      }
      final resp = await http
          .get(uri, headers: headers.isNotEmpty ? headers : null)
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        final ext = p.extension(uri.path).isNotEmpty
            ? p.extension(uri.path)
            : (item.kind == TheavMediaKind.video ? '.mp4' : '.jpg');
        final f = File(
          p.join(
            tempDir.path,
            'theaver_media_${DateTime.now().millisecondsSinceEpoch}$ext',
          ),
        );
        await f.writeAsBytes(resp.bodyBytes, flush: true);
        return f;
      }
    }
    return null;
  }

  String _resolveExportFileName(TheavMediaItem item, File sourceFile) {
    final candidate = item.fileName?.trim() ?? '';
    if (candidate.isNotEmpty) return candidate;
    final srcExt = p.extension(sourceFile.path);
    final defaultExt = item.kind == TheavMediaKind.video
        ? '.mp4'
        : (item.kind == TheavMediaKind.gif ? '.gif' : '.jpg');
    final ext = srcExt.isNotEmpty ? srcExt : defaultExt;
    return 'Theaver_${DateTime.now().millisecondsSinceEpoch}$ext';
  }

  Future<void> _saveCurrentItem() async {
    if (_isSaving || _items.isEmpty) return;
    final item = _items[_currentIndex];
    if (item.hasProtectedContent) {
      GlassToastService().show(
        context,
        _tr(
          'media_viewer_protected_content',
          'Копирование и сохранение запрещены',
        ),
        icon: Icons.lock_outline_rounded,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final file = await _materializeLocalFile(item);
      if (file == null || !await file.exists()) {
        throw Exception('File unavailable');
      }

      final fileName = _resolveExportFileName(item, file);
      bool savedToGallery = false;

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          final PermissionState perm =
              await PhotoManager.requestPermissionExtend();
          if (perm.hasAccess || perm.isAuth) {
            if (item.kind == TheavMediaKind.video ||
                item.isVideoBackedGif) {
              await PhotoManager.editor.saveVideo(file, title: fileName);
            } else {
              await PhotoManager.editor.saveImageWithPath(
                file.path,
                title: fileName,
              );
            }
            savedToGallery = true;
          }
        } catch (e) {
          debugPrint('[TheavMediaViewer] PhotoManager save fallback: $e');
        }
      }

      if (!savedToGallery) {
        final dirPath = await FileService().getDefaultDownloadDirectory();
        final dir = Directory(dirPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        String targetPath = p.join(dir.path, fileName);
        if (await File(targetPath).exists()) {
          final ext = p.extension(fileName);
          final stem = p.basenameWithoutExtension(fileName);
          targetPath = p.join(
            dir.path,
            '${stem}_${DateTime.now().millisecondsSinceEpoch}$ext',
          );
        }
        await file.copy(targetPath);
      }

      HapticUtils.impact();
      if (mounted) {
        GlassToastService().show(
          context,
          savedToGallery
              ? _tr(
                  'media_viewer_saved_to_gallery',
                  'Сохранено в галерею',
                )
              : _tr(
                  'media_viewer_saved_to_downloads',
                  'Сохранено в загрузки',
                ),
          icon: Icons.check_circle_outline_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        GlassToastService().showError(
          context,
          _tr('profile_save_error', 'Ошибка сохранения: {error}')
              .replaceAll('{error}', e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _shareCurrentItem() async {
    final item = _items[_currentIndex];
    if (item.hasProtectedContent) {
      GlassToastService().show(
        context,
        _tr(
          'media_viewer_protected_content',
          'Копирование и сохранение запрещены',
        ),
        icon: Icons.lock_outline_rounded,
      );
      return;
    }

    try {
      final file = await _materializeLocalFile(item);
      if (file == null || !await file.exists()) {
        if (mounted) {
          GlassToastService().showError(
            context,
            _tr('media_viewer_file_unavailable', 'Не удалось подготовить файл'),
          );
        }
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path)],
          text: item.caption?.trim().isNotEmpty == true
              ? item.caption!.trim()
              : (item.senderName ?? 'Theaver'),
        ),
      );
    } catch (e) {
      if (mounted) {
        GlassToastService().showError(context, e.toString());
      }
    }
  }

  Future<void> _saveCurrentGifToFavorites() async {
    final item = _items[_currentIndex];
    if (item.hasProtectedContent) return;
    HapticUtils.tap();
    await StickerService.instance.saveGif(
      item.id,
      item.resolvedUrl,
      item.resolvedThumbUrl,
      item.width,
      item.height,
    );
    if (mounted) {
      GlassToastService().show(
        context,
        _tr('media_viewer_gif_saved', 'GIF добавлена в избранные'),
        icon: Icons.check_circle_outline_rounded,
      );
    }
  }

  void _openMoreMenu() {
    if (_items.isEmpty) return;
    HapticUtils.selection();
    final int activeIndex = _currentIndex;
    final item = _items[activeIndex];
    final extraActions =
        widget.config.extraActionsBuilder?.call(item, activeIndex) ??
            const <TheavMediaAction>[];
    final palette = context.theav;

    showTheavModalSheet<void>(
      context: context,
      title: _resolveSheetTitle(item),
      showCloseButton: true,
      builder: (sheetCtx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!item.hasProtectedContent)
              TheavListRow(
                leading: iconoir.Download(
                  color: palette.primary,
                  width: 20,
                  height: 20,
                ),
                title: (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                    ? _tr(
                        'media_viewer_save_to_gallery',
                        'Сохранить в галерею',
                      )
                    : _tr(
                        'media_viewer_save_to_downloads',
                        'Сохранить в загрузки',
                      ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  unawaited(_saveCurrentItem());
                },
              ),
            if (item.kind == TheavMediaKind.gif && !item.hasProtectedContent)
              TheavListRow(
                leading: Icon(
                  Icons.gif_box_outlined,
                  color: palette.primary,
                  size: 21,
                ),
                title: _tr('media_viewer_save_gif', 'Сохранить в GIF'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  unawaited(_saveCurrentGifToFavorites());
                },
              ),
            if (!item.hasProtectedContent)
              TheavListRow(
                leading: iconoir.ShareIos(
                  color: palette.primary,
                  width: 20,
                  height: 20,
                ),
                title: _tr('share', 'Поделиться'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  unawaited(_shareCurrentItem());
                },
              ),
            if (!item.hasProtectedContent &&
                widget.config.onForwardItem != null &&
                !item.id.startsWith('local_') &&
                !AppConfig.isLocalFilePath(item.url))
              TheavListRow(
                leading: iconoir.ForwardMessage(
                  color: palette.primary,
                  width: 20,
                  height: 20,
                ),
                title: _tr('forward', 'Переслать'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await widget.config.onForwardItem!(context, item);
                },
              ),
            if (widget.config.onJumpToMessage != null &&
                item.messageId != null &&
                item.messageId!.isNotEmpty)
              TheavListRow(
                leading: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: palette.primary,
                  size: 20,
                ),
                title: _tr(
                  'media_viewer_jump_to_message',
                  'Перейти к сообщению',
                ),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await widget.config.onJumpToMessage!(context, item);
                },
              ),
            for (final action in extraActions)
              TheavListRow(
                leading: action.icon != null
                    ? Icon(
                        action.icon,
                        color: action.isDestructive
                            ? palette.error
                            : palette.primary,
                        size: 20,
                      )
                    : null,
                title: action.label,
                isDestructive: action.isDestructive,
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await action.onSelected(context, item, activeIndex);
                },
              ),
            if (widget.config.onDeleteItem != null)
              TheavListRow(
                leading: iconoir.Trash(
                  color: palette.error,
                  width: 20,
                  height: 20,
                ),
                title: _tr('delete', 'Удалить'),
                isDestructive: true,
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final bool deleted = await widget.config.onDeleteItem!(
                    context,
                    item,
                    activeIndex,
                  );
                  if (deleted && mounted) {
                    _handleItemDeleted(activeIndex);
                  }
                },
              ),
          ],
        );
      },
    );
  }

  String _resolveSheetTitle(TheavMediaItem item) {
    if (item.hasProtectedContent) {
      return _tr(
        'media_viewer_protected_content',
        'Защищённый контент',
      );
    }
    switch (item.kind) {
      case TheavMediaKind.avatar:
        return _tr('profile_avatar_title', 'Фото профиля');
      case TheavMediaKind.gif:
        return 'GIF';
      case TheavMediaKind.video:
        return _tr('chat_video', 'Видео');
      case TheavMediaKind.photo:
        return _tr('chat_photo', 'Фото');
    }
  }

  void _handleItemDeleted(int deletedIndex) {
    if (!mounted || deletedIndex < 0 || deletedIndex >= _items.length) return;
    if (_items.length == 1) {
      _syncCloseIndexAndPop();
      return;
    }
    setState(() {
      _videoBridges.remove(deletedIndex)?.dispose();
      _items.removeAt(deletedIndex);
      if (_currentIndex >= _items.length) {
        _currentIndex = _items.length - 1;
      }
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(_currentIndex);
    }
  }

  ImageProvider _resolveStaticImageProvider(TheavMediaItem item) {
    if (item.memoryBytes != null && item.memoryBytes!.isNotEmpty) {
      return MemoryImage(item.memoryBytes!);
    }
    if (!kIsWeb &&
        item.localFilePath != null &&
        item.localFilePath!.isNotEmpty) {
      final f = File(item.localFilePath!);
      if (f.existsSync()) return FileImage(f);
    }
    final resolved = item.resolvedUrl;
    final cachedFile = MediaCacheManager.instance.getCachedFileSync(resolved);
    if (cachedFile != null) {
      return FileImage(cachedFile);
    }
    if (resolved.startsWith('data:')) {
      try {
        final commaIdx = resolved.indexOf(',');
        if (commaIdx != -1) {
          return MemoryImage(base64Decode(resolved.substring(commaIdx + 1)));
        }
      } catch (_) {}
    }
    if (!kIsWeb && resolved.startsWith('file://')) {
      return FileImage(File(Uri.parse(resolved).toFilePath()));
    }
    if (!kIsWeb &&
        resolved.startsWith('/') &&
        !resolved.startsWith('/api/') &&
        !resolved.startsWith('/uploads/') &&
        !resolved.startsWith('/media/')) {
      final f = File(resolved);
      if (f.existsSync()) return FileImage(f);
    }
    if (item.kind == TheavMediaKind.avatar) {
      final avatarProv = avatarFullImageProvider(item.url);
      if (avatarProv != null) return avatarProv;
    }
    final cleanUrl = stripAvatarCropFragment(
          AppConfig.resolveMediaUrl(resolved) ?? resolved,
        ) ??
        resolved;
    return CachedNetworkImageProvider(
      cleanUrl,
      cacheKey: AppConfig.cacheKeyForUrl(cleanUrl),
      headers: AppConfig.authHeadersForUrl(cleanUrl),
    );
  }

  Widget _buildStaticMediaChild(
    BuildContext context,
    TheavMediaItem item,
    bool enableHero,
  ) {
    final resolved = item.resolvedUrl;
    final bool hasDirectLocal =
        (item.memoryBytes != null && item.memoryBytes!.isNotEmpty) ||
            (!kIsWeb &&
                item.localFilePath != null &&
                item.localFilePath!.isNotEmpty &&
                File(item.localFilePath!).existsSync()) ||
            MediaCacheManager.instance.getCachedFileSync(resolved) != null ||
            resolved.startsWith('data:') ||
            (!kIsWeb && resolved.startsWith('file://')) ||
            (!kIsWeb &&
                resolved.startsWith('/') &&
                !resolved.startsWith('/api/') &&
                !resolved.startsWith('/uploads/') &&
                !resolved.startsWith('/media/'));

    if (!kIsWeb &&
        item.kind == TheavMediaKind.photo &&
        !hasDirectLocal &&
        MediaCacheManager.instance.extractProtectedObjectName(
              resolved,
              ignorePresignQuery: true,
            ) !=
            null) {
      final Widget cachedViewerImage = Center(
        child: _MediaCacheViewerImage(
          item: item,
          resolvedUrl: resolved,
        ),
      );
      if (!enableHero || item.heroTag.isEmpty) return cachedViewerImage;
      return Hero(
        tag: item.heroTag,
        child: cachedViewerImage,
      );
    }

    final provider = _resolveStaticImageProvider(item);
    final Widget image = Image(
      image: provider,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        final double? fraction = progress.expectedTotalBytes != null &&
                progress.expectedTotalBytes! > 0
            ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
            : null;
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (item.thumbBase64 != null && item.thumbBase64!.isNotEmpty)
                BlurredMediaPlaceholder(
                  thumbBase64: item.thumbBase64,
                  aspectRatio: item.aspectRatio,
                  fit: BoxFit.contain,
                ),
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xB3101218),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    value: fraction,
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      errorBuilder: (context, _, __) => const Center(
        child: iconoir.MediaImage(
          color: Colors.white54,
          width: 60,
          height: 60,
        ),
      ),
    );

    final Widget centered = Center(child: image);
    if (!enableHero || item.heroTag.isEmpty) return centered;
    return Hero(
      tag: item.heroTag,
      child: centered,
    );
  }

  Widget _buildPage(BuildContext context, int index) {
    final item = _items[index];
    final bool isActive = index == _currentIndex;
    final bool isVideo = item.kind == TheavMediaKind.video;

    final Widget mediaContent = (isVideo || item.kind == TheavMediaKind.gif)
        ? TheavMediaVideoSurface(
            item: item,
            isActive: isActive,
            enableHero: isActive,
            bridge: isVideo ? _bridgeForIndex(index) : null,
          )
        : _buildStaticMediaChild(context, item, isActive);

    return TheavZoomableMediaStage(
      key: ValueKey<String>('stage_${item.id}'),
      enableZoom: true,
      enableDoubleTapSeek: isVideo,
      onDoubleTapSeek: isVideo
          ? (deltaSec) => _bridgeForIndex(index)
              .seekRelative(Duration(seconds: deltaSec))
          : null,
      onSingleTap: () {
        setState(() => _hudVisible = !_hudVisible);
      },
      onZoomStateChanged: (zoomed) {
        if (isActive && _isZoomed != zoomed && mounted) {
          setState(() => _isZoomed = zoomed);
        }
      },
      onDismissStart: () {
        _routeScope?.setRestingOpaque(false);
        if (_hudVisible && mounted) {
          setState(() => _hudVisible = false);
        }
      },
      onDismissUpdate: (offset, progress) {
        _dragBackdropOpacityNotifier.value =
            (1.0 - progress * 0.85).clamp(0.0, 1.0);
      },
      onDismissEnd: (confirmed) {
        if (confirmed) {
          _syncCloseIndexAndPop(fromDrag: true);
        } else {
          _dragBackdropOpacityNotifier.value = 1.0;
          _routeScope?.setRestingOpaque(true);
          if (!_hudVisible && mounted) {
            setState(() => _hudVisible = true);
          }
        }
      },
      child: mediaContent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TheavMediaItem currentItem = _items[_currentIndex];
    final Animation<double>? routeAnim = _routeScope?.transitionAnimation;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Dynamic pure-black backdrop fading linearly on push/pop AND 2D drag
            Positioned.fill(
              child: RepaintBoundary(
                child: ValueListenableBuilder<double>(
                  valueListenable: _dragBackdropOpacityNotifier,
                  builder: (context, dragAlpha, _) {
                    if (routeAnim == null) {
                      return ColoredBox(
                        color: Colors.black.withValues(alpha: dragAlpha),
                      );
                    }
                    return AnimatedBuilder(
                      animation: routeAnim,
                      builder: (context, _) {
                        final double combinedAlpha =
                            (routeAnim.value * dragAlpha).clamp(0.0, 1.0);
                        return ColoredBox(
                          color: Colors.black.withValues(alpha: combinedAlpha),
                        );
                      },
                    );
                  },
                ),
              ),
            ),

            // 120 FPS media PageView
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                physics: _isZoomed || _items.length <= 1
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                onPageChanged: _onPageChanged,
                itemCount: _items.length,
                itemBuilder: _buildPage,
              ),
            ),

            // Clean matte HUD (no blur, no glass shaders)
            Positioned.fill(
              child: TheavMediaHud(
                items: _items,
                currentIndex: _currentIndex,
                currentItem: currentItem,
                hudVisible: _hudVisible,
                isZoomed: _isZoomed,
                isSaving: _isSaving,
                titleOverride: widget.config.titleOverride,
                primaryTopAction: widget.config.primaryTopAction,
                videoBridge: currentItem.kind == TheavMediaKind.video
                    ? _bridgeForIndex(_currentIndex)
                    : null,
                bottomAccessory: widget.config.bottomAccessoryBuilder
                    ?.call(context, currentItem, _currentIndex),
                hasJumpToMessage: widget.config.onJumpToMessage != null &&
                    currentItem.messageId != null &&
                    currentItem.messageId!.isNotEmpty,
                onClose: () => _syncCloseIndexAndPop(),
                onSave: _saveCurrentItem,
                onEnterPip: currentItem.kind == TheavMediaKind.video
                    ? () => unawaited(_enterPipForCurrentVideo())
                    : null,
                onOpenMoreMenu: _openMoreMenu,
                onPrevPage: _currentIndex > 0
                    ? () => _goToPage(_currentIndex - 1)
                    : null,
                onNextPage: _currentIndex < _items.length - 1
                    ? () => _goToPage(_currentIndex + 1)
                    : null,
                onSelectFilmstripIndex: _goToPage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders protected `/media/` photos through [MediaCacheManager] so opening a
/// photo in the fullscreen viewer shares the exact same disk cache as chat bubbles
/// without triggering duplicate downloads into `DefaultCacheManager`.
class _MediaCacheViewerImage extends StatefulWidget {
  final TheavMediaItem item;
  final String resolvedUrl;

  const _MediaCacheViewerImage({
    required this.item,
    required this.resolvedUrl,
  });

  @override
  State<_MediaCacheViewerImage> createState() => _MediaCacheViewerImageState();
}

class _MediaCacheViewerImageState extends State<_MediaCacheViewerImage> {
  File? _cachedFile;
  ValueNotifier<DownloadByteProgress>? _byteNotifier;
  double _fraction = 0.0;
  bool _hasError = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _syncImmediate();
    if (_cachedFile == null) {
      _loadMedia();
    }
  }

  @override
  void didUpdateWidget(covariant _MediaCacheViewerImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resolvedUrl != widget.resolvedUrl) {
      _detachNotifier();
      _cachedFile = null;
      _fraction = 0.0;
      _hasError = false;
      _syncImmediate();
      if (_cachedFile == null) {
        _loadMedia();
      }
    }
  }

  @override
  void dispose() {
    _detachNotifier();
    super.dispose();
  }

  void _detachNotifier() {
    _byteNotifier?.removeListener(_onProgressTick);
    _byteNotifier = null;
  }

  void _onProgressTick() {
    if (!mounted || _byteNotifier == null) return;
    final val = _byteNotifier!.value.fraction;
    if ((val - _fraction).abs() >= 0.01) {
      setState(() => _fraction = val);
    }
  }

  void _syncImmediate() {
    final sync = MediaCacheManager.instance.getCachedFileSync(
      widget.resolvedUrl,
    );
    if (sync != null) {
      _cachedFile = sync;
      _hasError = false;
      _isLoading = false;
    }
  }

  Future<void> _loadMedia() async {
    final String targetUrl = widget.resolvedUrl;
    if (targetUrl.isEmpty || _isLoading) return;
    _isLoading = true;
    _hasError = false;

    final existing = await MediaCacheManager.instance.getCachedFile(targetUrl);
    if (!mounted || widget.resolvedUrl != targetUrl) return;
    if (existing != null && await existing.exists() && await existing.length() > 0) {
      _isLoading = false;
      setState(() {
        _cachedFile = existing;
        _hasError = false;
      });
      return;
    }

    _detachNotifier();
    _byteNotifier =
        MediaCacheManager.instance.getByteProgressNotifier(targetUrl);
    _byteNotifier?.addListener(_onProgressTick);
    if (mounted) {
      setState(() => _fraction = _byteNotifier?.value.fraction ?? 0.0);
    }

    final file = await MediaCacheManager.instance.downloadMedia(
      targetUrl,
      expectedTotalSize: widget.item.fileSize,
    );
    _detachNotifier();
    _isLoading = false;
    if (!mounted || widget.resolvedUrl != targetUrl) return;
    if (file != null && await file.exists() && await file.length() > 0) {
      setState(() {
        _cachedFile = file;
        _hasError = false;
      });
    } else {
      setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _cachedFile;
    if (file != null) {
      return Image.file(
        file,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const Center(
          child: iconoir.MediaImage(
            color: Colors.white54,
            width: 60,
            height: 60,
          ),
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: GestureDetector(
          onTap: _loadMedia,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xB3101218),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.refresh_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      );
    }

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.item.thumbBase64 != null &&
              widget.item.thumbBase64!.isNotEmpty)
            BlurredMediaPlaceholder(
              thumbBase64: widget.item.thumbBase64,
              aspectRatio: widget.item.aspectRatio,
              fit: BoxFit.contain,
            ),
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xB3101218),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                value: _fraction > 0 ? _fraction : null,
                strokeWidth: 2.4,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
