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
  final double topFrac;
  final double size;
  final double angle;
  final double alpha;
  final double minWidth;

  const _ReplyWatermarkSlot({
    required this.right,
    required this.topFrac,
    required this.size,
    required this.angle,
    required this.alpha,
    required this.minWidth,
  });
}

/// Renders Telegram Premium-style scattered monotone background emojis on the
/// right side of a reply quote block, fading inward so text stays readable.
class ReplyBackgroundEmojiLayer extends StatelessWidget {
  final ReplyEmojiData? emoji;
  final Color color;
  final int maxSlots;
  final double opacityScale;

  const ReplyBackgroundEmojiLayer({
    super.key,
    required this.emoji,
    required this.color,
    this.maxSlots = 7,
    this.opacityScale = 1.0,
  });

  static const List<_ReplyWatermarkSlot> _slots = <_ReplyWatermarkSlot>[
    _ReplyWatermarkSlot(
      right: 10,
      topFrac: 0.08,
      size: 16.0,
      angle: -0.18,
      alpha: 0.22,
      minWidth: 96,
    ),
    _ReplyWatermarkSlot(
      right: 6,
      topFrac: 0.88,
      size: 14.5,
      angle: 0.20,
      alpha: 0.20,
      minWidth: 96,
    ),
    _ReplyWatermarkSlot(
      right: 34,
      topFrac: 0.42,
      size: 15.0,
      angle: 0.16,
      alpha: 0.18,
      minWidth: 120,
    ),
    _ReplyWatermarkSlot(
      right: 58,
      topFrac: 0.06,
      size: 13.5,
      angle: -0.15,
      alpha: 0.15,
      minWidth: 150,
    ),
    _ReplyWatermarkSlot(
      right: 62,
      topFrac: 0.90,
      size: 15.0,
      angle: 0.21,
      alpha: 0.14,
      minWidth: 160,
    ),
    _ReplyWatermarkSlot(
      right: 88,
      topFrac: 0.46,
      size: 14.0,
      angle: -0.20,
      alpha: 0.10,
      minWidth: 195,
    ),
    _ReplyWatermarkSlot(
      right: 114,
      topFrac: 0.22,
      size: 12.5,
      angle: 0.18,
      alpha: 0.07,
      minWidth: 235,
    ),
  ];

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
              if (!w.isFinite || !h.isFinite || w < 96 || h < 20) {
                return const SizedBox.shrink();
              }

              final children = <Widget>[];
              final limit = maxSlots.clamp(0, _slots.length);
              for (int i = 0; i < limit; i++) {
                final slot = _slots[i];
                if (w < slot.minWidth) continue;
                final verticalSlack = (h - slot.size - 4.0).clamp(0.0, 200.0);
                final top = 2.0 + slot.topFrac * verticalSlack;
                final slotColor = color.withValues(
                  alpha: (color.a * slot.alpha * opacityScale).clamp(0.0, 1.0),
                );
                children.add(
                  Positioned(
                    right: slot.right,
                    top: top,
                    child: Transform.rotate(
                      angle: slot.angle,
                      child: ReplyEmojiGlyph(
                        emoji: data,
                        color: slotColor,
                        size: slot.size,
                      ),
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
