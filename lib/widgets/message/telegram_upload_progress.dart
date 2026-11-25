import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/media_cache_manager.dart';
import '../../services/media_send_coordinator.dart';

/// Matte Telegram-style radial upload indicator rendered via [CustomPainter].
/// Displays a rotating arc with byte sweep progress while uploading (`✕` to
/// cancel), a checkmark while waiting for album siblings (`✓`), or a retry
/// glyph (`↻`) on failure. Uses zero blur shaders to sustain 120fps scrolling.
class TelegramRadialUploadIndicator extends StatefulWidget {
  final OutgoingUploadProgress progress;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final double size;
  final Color badgeColor;
  final Color strokeColor;

  const TelegramRadialUploadIndicator({
    super.key,
    required this.progress,
    this.onCancel,
    this.onRetry,
    this.size = 48.0,
    this.badgeColor = const Color(0xA6000000),
    this.strokeColor = Colors.white,
  });

  @override
  State<TelegramRadialUploadIndicator> createState() =>
      _TelegramRadialUploadIndicatorState();
}

class _TelegramRadialUploadIndicatorState
    extends State<TelegramRadialUploadIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(TelegramRadialUploadIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress.phase != widget.progress.phase) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    final phase = widget.progress.phase;
    final shouldSpin = phase == OutgoingUploadPhase.preparing ||
        phase == OutgoingUploadPhase.uploading ||
        phase == OutgoingUploadPhase.sendingRpc;
    if (shouldSpin) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else {
      if (_rotationController.isAnimating) {
        _rotationController.stop();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.progress.isFailed) {
      widget.onRetry?.call();
    } else if (widget.progress.isCancelable) {
      widget.onCancel?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final iconSize = (widget.size * 0.44).clamp(16.0, 26.0);
    final IconData iconData;
    final Color iconColor;
    final String tooltip;

    if (p.isFailed) {
      iconData = Icons.refresh_rounded;
      iconColor = const Color(0xFFFF6B6B);
      tooltip = AppLocalizations.trStatic('upload_retry', 'Повторить');
    } else if (p.isWaitingSiblings) {
      iconData = Icons.check_rounded;
      iconColor = Colors.white;
      tooltip = AppLocalizations.trStatic('upload_cancel', 'Отменить');
    } else {
      iconData = Icons.close_rounded;
      iconColor = Colors.white;
      tooltip = AppLocalizations.trStatic('upload_cancel', 'Отменить');
    }

    return Semantics(
      button: p.isFailed || p.isCancelable,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: (p.isFailed || p.isCancelable) ? _handleTap : null,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.badgeColor,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: widget.size, height: widget.size),
                ),
                if (!p.isFailed && p.phase != OutgoingUploadPhase.sent)
                  AnimatedBuilder(
                    animation: _rotationController,
                    builder: (context, _) {
                      return CustomPaint(
                        size: Size.square(widget.size),
                        painter: _RadialUploadArcPainter(
                          fraction: p.isWaitingSiblings ? 1.0 : p.fraction,
                          rotationTurns: _rotationController.value,
                          strokeColor: widget.strokeColor,
                          drawFullRing: p.isWaitingSiblings,
                        ),
                      );
                    },
                  ),
                Icon(
                  iconData,
                  size: iconSize,
                  color: iconColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadialUploadArcPainter extends CustomPainter {
  final double fraction;
  final double rotationTurns;
  final Color strokeColor;
  final bool drawFullRing;

  _RadialUploadArcPainter({
    required this.fraction,
    required this.rotationTurns,
    required this.strokeColor,
    required this.drawFullRing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 4.0;
    if (radius <= 0) return;

    final trackPaint = Paint()
      ..color = strokeColor.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;
    canvas.drawCircle(center, radius, trackPaint);

    final arcPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.8;

    if (drawFullRing) {
      canvas.drawCircle(center, radius, arcPaint);
      return;
    }

    final clamped = fraction.clamp(0.0, 1.0);
    final sweepAngle = ui.lerpDouble(
      0.08 * math.pi * 2,
      math.pi * 2,
      clamped,
    )!;
    final startAngle = (-math.pi / 2) + (rotationTurns * math.pi * 2);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RadialUploadArcPainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.rotationTurns != rotationTurns ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.drawFullRing != drawFullRing;
  }
}

/// Overlay rendered over outgoing photo/video/gif bubbles and album tiles
/// showing live uploaded-byte counter badge and centered [TelegramRadialUploadIndicator].
class TelegramMediaUploadOverlay extends StatelessWidget {
  final String localId;
  final String? chatId;
  final String? groupedId;
  final int? fileSize;
  final int sendStatus;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final double indicatorSize;
  final bool showSizeBadge;

  const TelegramMediaUploadOverlay({
    super.key,
    required this.localId,
    this.chatId,
    this.groupedId,
    this.fileSize,
    this.sendStatus = 0,
    this.onCancel,
    this.onRetry,
    this.indicatorSize = 48.0,
    this.showSizeBadge = true,
  });

  String _formatCounter(OutgoingUploadProgress progress) {
    if (progress.isFailed) {
      return AppLocalizations.trStatic('upload_retry', 'Повторить');
    }
    final total = progress.totalBytes > 0 ? progress.totalBytes : (fileSize ?? 0);
    if (total <= 0) {
      return '...';
    }
    final sent = progress.isWaitingSiblings
        ? total
        : progress.sentBytes.clamp(0, total);
    return '${MediaCacheManager.formatBytes(sent)} / ${MediaCacheManager.formatBytes(total)}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OutgoingUploadProgress>(
      valueListenable: MediaSendCoordinator.instance.progressFor(
        localId,
        chatId: chatId,
        groupedId: groupedId,
        totalBytes: fileSize,
        sendStatus: sendStatus,
      ),
      builder: (context, progress, _) {
        if (progress.phase == OutgoingUploadPhase.sent ||
            progress.phase == OutgoingUploadPhase.cancelled) {
          return const SizedBox.shrink();
        }
        final counterText = showSizeBadge ? _formatCounter(progress) : '';
        return Stack(
          fit: StackFit.expand,
          children: [
            if (counterText.isNotEmpty)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    counterText,
                    style: TextStyle(
                      color: progress.isFailed
                          ? const Color(0xFFFF8A8A)
                          : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            Center(
              child: TelegramRadialUploadIndicator(
                progress: progress,
                size: indicatorSize,
                onCancel: onCancel ??
                    () => MediaSendCoordinator.instance.cancelUpload(localId),
                onRetry: onRetry ??
                    () => MediaSendCoordinator.instance.retryMessage(localId),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Fetches a video thumbnail URL through [MediaCacheManager.fetchThumbnailBytes]
/// so private-bucket thumbnails render immediately with Bearer auth fallback.
class RemoteVideoThumbnailImage extends StatefulWidget {
  final String? thumbUrl;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final BoxFit fit;

  const RemoteVideoThumbnailImage({
    super.key,
    required this.thumbUrl,
    this.width,
    this.height,
    this.cacheWidth,
    this.fit = BoxFit.cover,
  });

  @override
  State<RemoteVideoThumbnailImage> createState() =>
      _RemoteVideoThumbnailImageState();
}

class _RemoteVideoThumbnailImageState extends State<RemoteVideoThumbnailImage> {
  Uint8List? _bytes;
  String? _loadedUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RemoteVideoThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbUrl != widget.thumbUrl) {
      _bytes = null;
      _loadedUrl = null;
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.thumbUrl?.trim() ?? '';
    if (url.isEmpty || _loadedUrl == url) return;
    _loadedUrl = url;
    final bytes = await MediaCacheManager.instance.fetchThumbnailBytes(url);
    if (!mounted || _loadedUrl != url || bytes == null || bytes.isEmpty) {
      return;
    }
    setState(() {
      _bytes = bytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null || b.isEmpty) {
      return const SizedBox.shrink();
    }
    return Image.memory(
      b,
      width: widget.width,
      height: widget.height,
      cacheWidth: widget.cacheWidth,
      fit: widget.fit,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
    );
  }
}
