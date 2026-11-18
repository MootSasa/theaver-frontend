import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/profile_customization.dart';
import '../../services/sticker_service.dart';
import '../chat/sticker_item_widget.dart';

/// Renders a single monotone (adaptive) custom emoji glyph tinted with [color].
class ReplyEmojiGlyph extends StatefulWidget {
  final ReplyEmojiData? emoji;
  final StickerItem? stickerOverride;
  final Color color;
  final double size;
  final bool animate;
  final bool repeat;

  const ReplyEmojiGlyph({
    super.key,
    this.emoji,
    this.stickerOverride,
    required this.color,
    this.size = 24,
    this.animate = false,
    this.repeat = false,
  });

  @override
  State<ReplyEmojiGlyph> createState() => _ReplyEmojiGlyphState();
}

class _ReplyEmojiGlyphState extends State<ReplyEmojiGlyph> {
  StickerItem? _resolvedSticker;
  int? _fetchingStickerId;

  @override
  void initState() {
    super.initState();
    _resolveStickerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant ReplyEmojiGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emoji?.stickerId != widget.emoji?.stickerId ||
        oldWidget.stickerOverride?.id != widget.stickerOverride?.id ||
        oldWidget.emoji?.stickerUrl != widget.emoji?.stickerUrl) {
      if (oldWidget.emoji?.stickerId != widget.emoji?.stickerId) {
        _resolvedSticker = null;
        _fetchingStickerId = null;
      }
      _resolveStickerIfNeeded();
    }
  }

  void _resolveStickerIfNeeded() {
    if (widget.stickerOverride != null) return;
    final emoji = widget.emoji;
    if (emoji == null || emoji.stickerId <= 0) return;

    final syncMatch = StickerService.instance.getStickerByIdSync(emoji.stickerId);
    if (syncMatch != null && syncMatch.fileUrl.isNotEmpty) {
      _resolvedSticker = syncMatch;
      return;
    }

    if (emoji.stickerUrl != null && emoji.stickerUrl!.isNotEmpty) return;
    if (_fetchingStickerId == emoji.stickerId) return;

    final targetId = emoji.stickerId;
    _fetchingStickerId = targetId;
    unawaited(
      StickerService.instance.getStickerById(targetId).then((fetched) {
        if (!mounted || widget.emoji?.stickerId != targetId) return;
        if (fetched != null && fetched.fileUrl.isNotEmpty) {
          setState(() => _resolvedSticker = fetched);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final override = widget.stickerOverride;
    final synced = override ??
        _resolvedSticker ??
        (widget.emoji != null
            ? StickerService.instance.getStickerByIdSync(widget.emoji!.stickerId)
            : null);

    final String fileUrl = (synced != null && synced.fileUrl.isNotEmpty)
        ? synced.fileUrl
        : (widget.emoji?.stickerUrl ?? '');
    if (fileUrl.isEmpty) {
      return SizedBox(width: widget.size, height: widget.size);
    }

    final String thumbUrl =
        (synced != null && synced.thumbnailUrl.isNotEmpty)
            ? synced.thumbnailUrl
            : (widget.emoji?.thumbnailUrl ?? '');
    final String format = (synced != null && synced.format.isNotEmpty)
        ? synced.format
        : (widget.emoji?.stickerFormat ?? 'webp');
    final int? stickerId = synced?.id ?? widget.emoji?.stickerId;

    return StickerMediaView(
      fileUrl: fileUrl,
      thumbnailUrl: thumbUrl.isNotEmpty ? thumbUrl : null,
      stickerId: stickerId,
      format: format,
      width: widget.size,
      height: widget.size,
      animate: widget.animate,
      repeat: widget.repeat,
      adaptiveTintColor: widget.color,
    );
  }
}

class _ReplyWatermarkSlot {
  final double right;
  final double top;
  final double size;
  final double angle;
  final double alpha;
  final double minWidth;
  final bool isTopRightCorner;

  const _ReplyWatermarkSlot({
    required this.right,
    required this.top,
    required this.size,
    required this.angle,
    required this.alpha,
    required this.minWidth,
    this.isTopRightCorner = false,
  });
}

/// Renders Telegram Premium-style fixed-spacing monotone background emojis in
/// the upper right area of a reply/quote block, fading inward and clipping
/// excess lower rows cleanly when the container is short.
class ReplyBackgroundEmojiLayer extends StatelessWidget {
  static const double _kBottomClipAllowance = 2.0;

  final ReplyEmojiData? emoji;
  final Color color;
  final int maxSlots;
  final double opacityScale;
  final bool avoidTopRightCorner;

  const ReplyBackgroundEmojiLayer({
    super.key,
    required this.emoji,
    required this.color,
    this.maxSlots = 10,
    this.opacityScale = 1.0,
    this.avoidTopRightCorner = false,
  });

  static const List<_ReplyWatermarkSlot> _slots = <_ReplyWatermarkSlot>[
    _ReplyWatermarkSlot(
      right: 9,
      top: 4.0,
      size: 16.0,
      angle: 0.0,
      alpha: 0.55,
      minWidth: 96,
      isTopRightCorner: true,
    ),
    _ReplyWatermarkSlot(
      right: 5,
      top: 26.0,
      size: 14.0,
      angle: 0.0,
      alpha: 0.44,
      minWidth: 96,
    ),
    _ReplyWatermarkSlot(
      right: 35,
      top: 13.5,
      size: 14.5,
      angle: 0.0,
      alpha: 0.46,
      minWidth: 96,
    ),
    _ReplyWatermarkSlot(
      right: 28,
      top: 38.5,
      size: 13.5,
      angle: 0.0,
      alpha: 0.30,
      minWidth: 104,
    ),
    _ReplyWatermarkSlot(
      right: 61,
      top: 3.0,
      size: 13.5,
      angle: 0.0,
      alpha: 0.38,
      minWidth: 115,
    ),
    _ReplyWatermarkSlot(
      right: 56,
      top: 25.0,
      size: 14.0,
      angle: 0.0,
      alpha: 0.32,
      minWidth: 120,
    ),
    _ReplyWatermarkSlot(
      right: 88,
      top: 12.0,
      size: 13.0,
      angle: 0.0,
      alpha: 0.25,
      minWidth: 150,
    ),
    _ReplyWatermarkSlot(
      right: 80,
      top: 39.5,
      size: 12.5,
      angle: 0.0,
      alpha: 0.19,
      minWidth: 150,
    ),
    _ReplyWatermarkSlot(
      right: 109,
      top: 27.0,
      size: 12.0,
      angle: 0.0,
      alpha: 0.18,
      minWidth: 180,
    ),
    _ReplyWatermarkSlot(
      right: 118,
      top: 4.5,
      size: 12.0,
      angle: 0.0,
      alpha: 0.15,
      minWidth: 190,
    ),
  ];

  /// Exposed for testing: tilt angles of all watermark slots (all 0.0 per Telegram design).
  static List<double> get slotAngles => _slots.map((s) => s.angle).toList();

  @override
  Widget build(BuildContext context) {
    final data = emoji;
    if (data == null || data.stickerId <= 0) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: RepaintBoundary(
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              if (!w.isFinite || !h.isFinite || w < 96 || h < 18.5) {
                return const SizedBox.shrink();
              }

              final children = <Widget>[];
              final limit = maxSlots.clamp(0, _slots.length);
              for (int i = 0; i < _slots.length && children.length < limit; i++) {
                final slot = _slots[i];
                if (avoidTopRightCorner && slot.isTopRightCorner) continue;
                if (w < slot.minWidth) continue;
                if (slot.top + slot.size > h + _kBottomClipAllowance) continue;
                final slotColor = color.withValues(
                  alpha: (color.a * slot.alpha * opacityScale).clamp(0.0, 1.0),
                );
                final Widget glyph = ReplyEmojiGlyph(
                  emoji: data,
                  color: slotColor,
                  size: slot.size,
                );
                children.add(
                  Positioned(
                    right: slot.right,
                    top: slot.top,
                    child: slot.angle == 0.0
                        ? glyph
                        : Transform.rotate(
                            angle: slot.angle,
                            child: glyph,
                          ),
                  ),
                );
              }

              if (children.isEmpty) {
                return const SizedBox.shrink();
              }
              return Stack(
                fit: StackFit.expand,
                children: children,
              );
            },
          ),
        ),
      ),
    );
  }
}
