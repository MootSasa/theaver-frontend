import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:lottie/lottie.dart';
import '../../services/sticker_service.dart';
import '../../theme/theav_theme.dart';
import '../../utils/emoji_utils.dart';

/// Renders a sticker or custom emoji media asset (`.webp`, `animated_webp`, `.tgs`, `.json`, `.gif`)
/// on a strictly transparent background (`Colors.transparent`).
class StickerMediaView extends StatefulWidget {
  final String fileUrl;
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
      if (mounted) {
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
      final resolvedUrl = StickerService.resolveUrl(widget.fileUrl);
      content = Image.network(
        resolvedUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => SizedBox(
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

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: content,
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
  StickerItem? _sticker;

  @override
  void initState() {
    super.initState();
    _resolveSticker();
  }

  @override
  void didUpdateWidget(covariant InlineCustomEmojiWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customEmojiId != widget.customEmojiId ||
        oldWidget.directUrl != widget.directUrl) {
      _resolveSticker();
    }
  }

  Future<void> _resolveSticker() async {
    if (widget.customEmojiId.isEmpty) return;
    final cached = StickerService.instance.getStickerByIdSync(widget.customEmojiId);
    if (cached != null) {
      if (mounted) setState(() => _sticker = cached);
      return;
    }
    final fetched = await StickerService.instance.getStickerById(widget.customEmojiId);
    if (mounted && fetched != null) {
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
      format: format,
      width: widget.size,
      height: widget.size,
      animate: true,
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
