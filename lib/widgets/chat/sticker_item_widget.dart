import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:lottie/lottie.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../services/sticker_service.dart';
import '../../theme/theav_theme.dart';
import '../../utils/emoji_utils.dart';

/// Network/disk image widget that supports pausing multi-frame animations (`animated_webp`, `.gif`),
/// disk caching via [StickerService], concurrent animation capping, and frame-rate throttling.
///
/// Key performance guarantees:
/// 1. NEVER wraps `animated_webp` or `.gif` in [ResizeImage], avoiding Flutter's C++ `SkWebpCodec`
///    `O(N²)` software frame re-decoding bug when `targetWidth != nativeWidth`.
/// 2. Resolves from local disk (`FileImage`) via [StickerService] so scrolling never re-downloads over HTTP.
/// 3. Caps simultaneous active multi-frame raster animations at `_kMaxConcurrentRasterAnimators` (4)
///    and throttles UI `setState` frame rebuilds to `_kMinFrameIntervalMs` (55ms ≈ 18 FPS),
///    skipping frame rebuilds while the user is fast-flinging a scrollable list.
class ControlledAnimatedNetworkImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final bool animate;
  final bool isAnimatedWebpOrGif;
  final WidgetBuilder? errorBuilder;

  const ControlledAnimatedNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.cacheWidth,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.low,
    this.animate = true,
    this.isAnimatedWebpOrGif = false,
    this.errorBuilder,
  });

  @override
  State<ControlledAnimatedNetworkImage> createState() =>
      _ControlledAnimatedNetworkImageState();
}

class _ControlledAnimatedNetworkImageState
    extends State<ControlledAnimatedNetworkImage> {
  static const int _kMaxConcurrentRasterAnimators = 4;
  static const int _kMinFrameIntervalMs = 55;
  static final List<_ControlledAnimatedNetworkImageState> _activeAnimators =
      <_ControlledAnimatedNetworkImageState>[];

  ImageStream? _imageStream;
  ImageStreamListener? _listener;
  ImageInfo? _imageInfo;
  bool _isListening = false;
  bool _hasError = false;
  int _lastFramePaintMs = 0;
  int _resolveToken = 0;

  bool get _wantsAnimation => widget.animate && widget.isAnimatedWebpOrGif;

  bool get _isAllowedToAnimate {
    if (!_wantsAnimation) return false;
    final idx = _activeAnimators.indexOf(this);
    if (idx == -1) return false;
    return idx >= _activeAnimators.length - _kMaxConcurrentRasterAnimators;
  }

  void _syncAnimatorSlot() {
    if (_wantsAnimation) {
      if (!_activeAnimators.contains(this)) {
        _activeAnimators.add(this);
        // If adding this pushed an older animator out of the top N, pause that older one
        if (_activeAnimators.length > _kMaxConcurrentRasterAnimators) {
          final evictedIdx =
              _activeAnimators.length - _kMaxConcurrentRasterAnimators - 1;
          if (evictedIdx >= 0 && evictedIdx < _activeAnimators.length) {
            _activeAnimators[evictedIdx]._onAnimatorSlotChanged();
          }
        }
      }
    } else {
      _releaseAnimatorSlot();
    }
  }

  void _releaseAnimatorSlot() {
    final wasPresent = _activeAnimators.remove(this);
    if (wasPresent && _activeAnimators.isNotEmpty) {
      for (final st in _activeAnimators.reversed
          .take(_kMaxConcurrentRasterAnimators)) {
        st._onAnimatorSlotChanged();
      }
    }
  }

  void _onAnimatorSlotChanged() {
    if (!mounted) return;
    _updateSubscription();
  }

  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener(
      _handleFrame,
      onError: _handleError,
    );
    _syncAnimatorSlot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prepareAndResolve();
  }

  @override
  void didUpdateWidget(covariant ControlledAnimatedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimatorSlot();
    if (oldWidget.url != widget.url ||
        oldWidget.isAnimatedWebpOrGif != widget.isAnimatedWebpOrGif ||
        (!widget.isAnimatedWebpOrGif &&
            oldWidget.cacheWidth != widget.cacheWidth)) {
      _prepareAndResolve();
    } else if (oldWidget.animate != widget.animate) {
      _updateSubscription();
    }
  }

  void _prepareAndResolve() {
    if (widget.url.isEmpty) {
      _stopListening();
      _disposeImageInfo();
      return;
    }
    _hasError = false;
    final token = ++_resolveToken;

    if (!kIsWeb) {
      final syncFile =
          StickerService.instance.getCachedRasterFileSync(widget.url);
      if (syncFile != null) {
        _resolveProvider(FileImage(syncFile));
        return;
      }
      StickerService.instance.getOrDownloadRasterFile(widget.url).then((file) {
        if (!mounted || token != _resolveToken) return;
        if (file != null) {
          _resolveProvider(FileImage(file));
        } else {
          _resolveProvider(NetworkImage(widget.url));
        }
      });
      return;
    }

    _resolveProvider(NetworkImage(widget.url));
  }

  void _resolveProvider(ImageProvider baseProvider) {
    if (!mounted) return;
    // CRITICAL: Never wrap multi-frame animated WebP or GIF in ResizeImage!
    // ResizeImage forces SkWebpCodec to re-decode all prior frames 0..N on every tick (O(N²)).
    final ImageProvider provider = widget.isAnimatedWebpOrGif
        ? baseProvider
        : ResizeImage.resizeIfNeeded(
            widget.cacheWidth,
            null,
            baseProvider,
          );
    final ImageStream newStream =
        provider.resolve(createLocalImageConfiguration(context));
    if (newStream.key != _imageStream?.key) {
      _stopListening();
      _imageStream = newStream;
      _startListening();
    } else {
      _updateSubscription();
    }
  }

  void _startListening() {
    if (_imageStream == null || _listener == null || _isListening) return;
    _isListening = true;
    _imageStream!.addListener(_listener!);
  }

  void _stopListening() {
    if (_imageStream == null || _listener == null || !_isListening) return;
    _isListening = false;
    _imageStream!.removeListener(_listener!);
  }

  void _updateSubscription() {
    if (_isAllowedToAnimate) {
      _startListening();
    } else if (_imageInfo != null) {
      // We already have a frame to display statically; detach listener so
      // MultiFrameImageStreamCompleter stops decoding frames immediately.
      _stopListening();
    } else {
      // Need at least the first frame before we can detach.
      _startListening();
    }
  }

  void _handleFrame(ImageInfo info, bool synchronousCall) {
    if (!mounted) {
      return;
    }
    final bool isFirstFrame = _imageInfo == null;
    if (!isFirstFrame) {
      if (!_isAllowedToAnimate) {
        _stopListening();
        return;
      }
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastFramePaintMs < _kMinFrameIntervalMs) {
        return;
      }
      if (Scrollable.recommendDeferredLoadingForContext(context)) {
        return;
      }
      _lastFramePaintMs = nowMs;
    } else {
      _lastFramePaintMs = DateTime.now().millisecondsSinceEpoch;
    }

    final ImageInfo? oldInfo = _imageInfo;
    _imageInfo = info.clone();
    if (oldInfo != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        oldInfo.dispose();
      });
    }
    if (!_isAllowedToAnimate) {
      // Detach immediately after capturing the first frame so animation timer stops.
      _stopListening();
    }
    if (mounted) {
      setState(() {
        _hasError = false;
      });
    }
  }

  void _handleError(Object exception, StackTrace? stackTrace) {
    if (!mounted) return;
    setState(() {
      _hasError = true;
    });
  }

  void _disposeImageInfo() {
    final ImageInfo? old = _imageInfo;
    _imageInfo = null;
    if (old != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        old.dispose();
      });
    }
  }

  @override
  void dispose() {
    _resolveToken++;
    _releaseAnimatorSlot();
    _stopListening();
    _disposeImageInfo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError && widget.errorBuilder != null) {
      return widget.errorBuilder!(context);
    }
    final ui.Image? raw = _imageInfo?.image;
    if (raw == null) {
      return SizedBox(width: widget.width, height: widget.height);
    }
    return RawImage(
      image: raw,
      scale: _imageInfo?.scale ?? 1.0,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
    );
  }
}

/// Renders a sticker or custom emoji media asset (`.webp`, `animated_webp`, `.tgs`, `.json`, `.gif`)
/// on a strictly transparent background (`Colors.transparent`).
class StickerMediaView extends StatefulWidget {
  final String fileUrl;
  final String? thumbnailUrl;
  final Object? stickerId;
  final String format;
  final double width;
  final double height;
  final bool animate;
  final bool repeat;
  final BoxFit fit;
  final Color? adaptiveTintColor;

  const StickerMediaView({
    super.key,
    required this.fileUrl,
    this.thumbnailUrl,
    this.stickerId,
    this.format = 'webp',
    required this.width,
    required this.height,
    this.animate = true,
    this.repeat = true,
    this.fit = BoxFit.contain,
    this.adaptiveTintColor,
  });

  bool get isLottie {
    final fmt = format.toLowerCase();
    final lowerUrl = fileUrl.toLowerCase();
    return fmt == 'tgs' ||
        fmt == 'lottie' ||
        fmt == 'json' ||
        lowerUrl.endsWith('.tgs') ||
        lowerUrl.endsWith('.json');
  }

  bool get isAnimatedRaster {
    final fmt = format.toLowerCase();
    final lowerUrl = fileUrl.toLowerCase();
    if (fmt == 'animated_webp' || fmt == 'gif' || lowerUrl.endsWith('.gif')) {
      return true;
    }
    final item = StickerService.instance.getStickerByIdSync(stickerId) ??
        StickerService.instance.getStickerByUrlSync(fileUrl);
    return item != null && item.format.toLowerCase() == 'animated_webp';
  }

  @override
  State<StickerMediaView> createState() => _StickerMediaViewState();
}

class _StickerMediaViewState extends State<StickerMediaView> {
  LottieComposition? _composition;
  ui.Image? _bakedFirstFrame;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant StickerMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileUrl != widget.fileUrl ||
        oldWidget.format != widget.format ||
        oldWidget.animate != widget.animate) {
      _loadIfNeeded();
    }
  }

  Future<void> _loadIfNeeded() async {
    if (!widget.isLottie || widget.fileUrl.isEmpty) return;
    final cached = StickerService.instance.getCachedComposition(widget.fileUrl);
    if (cached != null) {
      if (mounted && _composition != cached) {
        setState(() => _composition = cached);
      }
      if (!widget.animate && _bakedFirstFrame == null) {
        final frame = await StickerService.instance.getBakedFirstFrame(
          widget.fileUrl,
          size: (widget.width * 2).round().clamp(64, 256),
        );
        if (mounted && frame != null) {
          setState(() => _bakedFirstFrame = frame);
        }
      }
      return;
    }

    if (_loading) return;
    _loading = true;
    try {
      if (!widget.animate) {
        final frame = await StickerService.instance.getBakedFirstFrame(
          widget.fileUrl,
          size: (widget.width * 2).round().clamp(64, 256),
        );
        if (mounted && frame != null) {
          setState(() => _bakedFirstFrame = frame);
        }
      }
      final comp = await StickerService.instance.getLottieComposition(widget.fileUrl);
      if (mounted && comp != null) {
        setState(() => _composition = comp);
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fileUrl.isEmpty) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    Widget content;
    if (widget.isLottie) {
      if (!widget.animate && _bakedFirstFrame != null) {
        content = RawImage(
          image: _bakedFirstFrame,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
        );
      } else if (_composition != null) {
        content = Lottie(
          composition: _composition,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          animate: widget.animate,
          repeat: widget.repeat,
          frameRate: const FrameRate(30),
          renderCache: RenderCache.drawingCommands,
        );
      } else if (_bakedFirstFrame != null) {
        content = RawImage(
          image: _bakedFirstFrame,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
        );
      } else {
        content = SizedBox(width: widget.width, height: widget.height);
      }
    } else {
      final bool isAnimRaster = widget.isAnimatedRaster;
      final String? staticThumbUrl = !widget.animate
          ? StickerService.instance.resolveStaticThumbnailUrl(
              widget.fileUrl,
              explicitThumbnailUrl: widget.thumbnailUrl,
              stickerId: widget.stickerId,
            )
          : null;

      final bool useStaticThumb = !widget.animate && staticThumbUrl != null;
      final String effectiveUrl = useStaticThumb
          ? staticThumbUrl
          : StickerService.resolveUrl(widget.fileUrl);
      final bool effectiveIsAnimated = isAnimRaster && !useStaticThumb;

      final int? targetCacheWidth = (!effectiveIsAnimated && widget.width.isFinite)
          ? (widget.width * 1.8).round().clamp(48, 320)
          : null;

      content = ControlledAnimatedNetworkImage(
        url: effectiveUrl,
        width: widget.width,
        height: widget.height,
        cacheWidth: targetCacheWidth,
        fit: widget.fit,
        animate: widget.animate && effectiveIsAnimated,
        isAnimatedWebpOrGif: effectiveIsAnimated,
        filterQuality: FilterQuality.low,
        errorBuilder: (_) => SizedBox(
          width: widget.width,
          height: widget.height,
        ),
      );
    }

    if (widget.adaptiveTintColor != null) {
      content = ColorFiltered(
        colorFilter: ColorFilter.mode(
          widget.adaptiveTintColor!,
          BlendMode.srcIn,
        ),
        child: content,
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: content,
      ),
    );
  }
}

/// Inline or standalone Custom Emoji widget (`20x20` inside text, `22x22` in reaction pill,
/// or `115.2x115.2` standalone in message bubble).
class InlineCustomEmojiWidget extends StatefulWidget {
  final String customEmojiId;
  final String? fallbackEmoji;
  final String? directUrl;
  final String? directFormat;
  final double size;
  final bool isMe;
  final bool enableTapEffect;
  final Color? adaptiveTextColor;

  const InlineCustomEmojiWidget({
    super.key,
    required this.customEmojiId,
    this.fallbackEmoji,
    this.directUrl,
    this.directFormat,
    this.size = 20.0,
    this.isMe = true,
    this.enableTapEffect = false,
    this.adaptiveTextColor,
  });

  @override
  State<InlineCustomEmojiWidget> createState() => _InlineCustomEmojiWidgetState();
}

class _InlineCustomEmojiWidgetState extends State<InlineCustomEmojiWidget> {
  final LayerLink _layerLink = LayerLink();
  final Key _visibilityKey = UniqueKey();
  StickerItem? _sticker;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _sticker = StickerService.instance.getStickerByIdSync(widget.customEmojiId);
    if (_sticker == null) {
      _resolveSticker();
    }
  }

  @override
  void didUpdateWidget(covariant InlineCustomEmojiWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customEmojiId != widget.customEmojiId ||
        oldWidget.directUrl != widget.directUrl) {
      final cached =
          StickerService.instance.getStickerByIdSync(widget.customEmojiId);
      if (cached != null) {
        _sticker = cached;
      } else {
        _resolveSticker();
      }
    }
  }

  Future<void> _resolveSticker() async {
    if (widget.customEmojiId.isEmpty) return;
    final cached = StickerService.instance.getStickerByIdSync(widget.customEmojiId);
    if (cached != null) {
      if (mounted && _sticker != cached) setState(() => _sticker = cached);
      return;
    }
    final fetched = await StickerService.instance.getStickerById(widget.customEmojiId);
    if (mounted && fetched != null && _sticker != fetched) {
      setState(() => _sticker = fetched);
    }
  }

  void _handleTap() {
    if (!widget.enableTapEffect) return;
    HapticFeedback.lightImpact();
    final effectUrl = _sticker?.effectAnimationUrl;
    final emoji = (_sticker?.emojis.isNotEmpty ?? false)
        ? _sticker!.emojis.first
        : widget.fallbackEmoji;
    EmojiEffectOverlay.showStickerEffect(
      context: context,
      effectUrl: effectUrl,
      fallbackEmoji: emoji,
      layerLink: _layerLink,
      stickerSize: widget.size,
      isMe: widget.isMe,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileUrl = _sticker?.fileUrl.isNotEmpty == true
        ? _sticker!.fileUrl
        : (widget.directUrl ?? '');
    final format = _sticker?.format.isNotEmpty == true
        ? _sticker!.format
        : (widget.directFormat ?? 'webp');

    if (fileUrl.isEmpty) {
      if (widget.fallbackEmoji != null && widget.fallbackEmoji!.isNotEmpty) {
        return Text(
          widget.fallbackEmoji!,
          style: EmojiUtils.emojiTextStyle(fontSize: widget.size * 0.85),
        );
      }
      return SizedBox(width: widget.size, height: widget.size);
    }

    final tint = (_sticker?.isAdaptiveTextColor == true)
        ? widget.adaptiveTextColor
        : null;

    Widget media = StickerMediaView(
      fileUrl: fileUrl,
      thumbnailUrl: _sticker?.thumbnailUrl,
      stickerId: _sticker?.id ?? widget.customEmojiId,
      format: format,
      width: widget.size,
      height: widget.size,
      animate: _isVisible,
      adaptiveTintColor: tint,
    );

    if (widget.enableTapEffect) {
      media = GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: CompositedTransformTarget(
          link: _layerLink,
          child: media,
        ),
      );
    }

    if (widget.size >= 40.0) {
      return VisibilityDetector(
        key: _visibilityKey,
        onVisibilityChanged: (info) {
          final visible = info.visibleFraction > 0.01;
          if (mounted && _isVisible != visible) {
            setState(() => _isVisible = visible);
          }
        },
        child: media,
      );
    }

    return media;
  }
}

/// Peek & Pop overlay shown when long-pressing a sticker or custom emoji in `EmojiStickerPanel`.
class StickerPeekPopOverlay extends StatefulWidget {
  final StickerItem sticker;
  final VoidCallback onSend;
  final VoidCallback? onOpenPack;
  final VoidCallback onClose;

  const StickerPeekPopOverlay({
    super.key,
    required this.sticker,
    required this.onSend,
    this.onOpenPack,
    required this.onClose,
  });

  static void show({
    required BuildContext context,
    required StickerItem sticker,
    required VoidCallback onSend,
    VoidCallback? onOpenPack,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    HapticFeedback.mediumImpact();

    late OverlayEntry entry;
    bool removed = false;
    void close() {
      if (!removed) {
        removed = true;
        try {
          entry.remove();
        } catch (_) {}
      }
    }

    entry = OverlayEntry(
      builder: (ctx) => StickerPeekPopOverlay(
        sticker: sticker,
        onSend: () {
          close();
          onSend();
        },
        onOpenPack: onOpenPack != null
            ? () {
                close();
                onOpenPack();
              }
            : null,
        onClose: close,
      ),
    );
    overlay.insert(entry);
  }

  @override
  State<StickerPeekPopOverlay> createState() => _StickerPeekPopOverlayState();
}

class _StickerPeekPopOverlayState extends State<StickerPeekPopOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  final LayerLink _stickerLayerLink = LayerLink();
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = StickerService.instance.isFavorite(widget.sticker.id);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();

    if (widget.sticker.hasFullscreenEffect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _playEffect();
        }
      });
    }
  }

  void _playEffect() {
    EmojiEffectOverlay.showStickerEffect(
      context: context,
      effectUrl: widget.sticker.effectAnimationUrl,
      fallbackEmoji: widget.sticker.emojis.isNotEmpty
          ? widget.sticker.emojis.first
          : null,
      layerLink: _stickerLayerLink,
      stickerSize: 220,
      isMe: true,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _toggleFavorite() async {
    final next = await StickerService.instance.toggleFavorite(widget.sticker);
    if (mounted) {
      setState(() => _isFavorite = next);
    }
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TheavTheme.of(context);
    final emojis = widget.sticker.emojis.take(5).toList();

    return Material(
      color: Colors.transparent,
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _animController,
          curve: Curves.easeOutCubic,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onClose,
                behavior: HitTestBehavior.opaque,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
            Center(
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.88, end: 1.0).animate(
                  CurvedAnimation(
                    parent: _animController,
                    curve: Curves.easeOutBack,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (emojis.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: emojis
                              .map(
                                (e) => Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    e,
                                    style: EmojiUtils.emojiTextStyle(fontSize: 28),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    GestureDetector(
                      onTap: widget.sticker.hasFullscreenEffect ? _playEffect : null,
                      child: CompositedTransformTarget(
                        link: _stickerLayerLink,
                        child: StickerMediaView(
                          fileUrl: widget.sticker.fileUrl,
                          thumbnailUrl: widget.sticker.thumbnailUrl,
                          stickerId: widget.sticker.id,
                          format: widget.sticker.format,
                          width: 220,
                          height: 220,
                          animate: true,
                        ),
                      ),
                    ),
                    if (widget.sticker.hasFullscreenEffect)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: GestureDetector(
                          onTap: _playEffect,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: theme.secondaryBg.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: theme.dividerColor,
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                iconoir.Sparks(
                                  width: 14,
                                  height: 14,
                                  color: theme.accent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'С полноэкранным эффектом — нажмите для повтора',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Container(
                      width: 225,
                      decoration: BoxDecoration(
                        color: theme.secondaryBg.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.dividerColor,
                          width: 0.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildActionRow(
                            theme: theme,
                            icon: iconoir.SendDiagonal(
                              width: 18,
                              height: 18,
                              color: theme.textPrimary,
                            ),
                            label: 'Отправить',
                            onTap: widget.onSend,
                          ),
                          Divider(
                            height: 0.5,
                            thickness: 0.5,
                            color: theme.dividerColor,
                          ),
                          _buildActionRow(
                            theme: theme,
                            icon: _isFavorite
                                ? iconoir.StarSolid(
                                    width: 18,
                                    height: 18,
                                    color: theme.accent,
                                  )
                                : iconoir.Star(
                                    width: 18,
                                    height: 18,
                                    color: theme.textPrimary,
                                  ),
                            label: _isFavorite
                                ? 'Убрать из избранного'
                                : 'В избранное',
                            onTap: _toggleFavorite,
                          ),
                          if (widget.onOpenPack != null &&
                              widget.sticker.packId > 0) ...[
                            Divider(
                              height: 0.5,
                              thickness: 0.5,
                              color: theme.dividerColor,
                            ),
                            _buildActionRow(
                              theme: theme,
                              icon: iconoir.Folder(
                                width: 18,
                                height: 18,
                                color: theme.textPrimary,
                              ),
                              label: 'Открыть набор',
                              onTap: widget.onOpenPack!,
                            ),
                          ],
                        ],
                      ),
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

  Widget _buildActionRow({
    required TheavThemeData theme,
    required Widget icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: theme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 8x8px transparency checkerboard painter used exclusively in the Sticker Upload Studio
/// to help creators verify alpha channel transparency.
class CheckerboardPainter extends CustomPainter {
  final bool isDark;
  final double cellSize;

  const CheckerboardPainter({
    required this.isDark,
    this.cellSize = 8.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintA = Paint()
      ..color = isDark ? const Color(0xFF2A2A2E) : const Color(0xFFE5E5EA);
    final paintB = Paint()
      ..color = isDark ? const Color(0xFF1E1E22) : const Color(0xFFF2F2F7);

    final cols = (size.width / cellSize).ceil();
    final rows = (size.height / cellSize).ceil();

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final paint = ((r + c) % 2 == 0) ? paintA : paintB;
        canvas.drawRect(
          Rect.fromLTWH(
            c * cellSize,
            r * cellSize,
            cellSize,
            cellSize,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CheckerboardPainter oldDelegate) {
    return oldDelegate.isDark != isDark || oldDelegate.cellSize != cellSize;
  }
}
