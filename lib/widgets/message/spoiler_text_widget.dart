import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../utils/haptic_utils.dart';
import 'message_interactive_state.dart';

/// Lightweight particle for Telegram-style spoiler dust.
///
/// Uses normalized coordinates [nx], [ny] in `[0.0, 1.0]` within a specific line box
/// when idle, and transitions to physical pixel offsets during radial tap dispersion.
class SpoilerParticle {
  /// Normalized position within its assigned rect (`0.0 .. 1.0`).
  double nx;
  double ny;

  /// Velocity in pixels per frame at 60fps.
  double vx;
  double vy;

  /// Current opacity (`0.0 .. 1.0`) and phase for smooth sinusoidal twinkle.
  double alpha;
  double phase;
  double phaseSpeed;

  /// Size tier (`0`: fine 1.15dp, `1`: medium 1.45dp, `2`: bright 1.75dp).
  final int sizeTier;

  /// Displacement accumulated during radial explosion.
  double explodeDx = 0.0;
  double explodeDy = 0.0;

  SpoilerParticle({
    required this.nx,
    required this.ny,
    required this.vx,
    required this.vy,
    required this.alpha,
    required this.phase,
    required this.phaseSpeed,
    required this.sizeTier,
  });

  static final math.Random _random = math.Random();

  static SpoilerParticle create([
    double width = 100.0,
    double height = 24.0,
    bool isMedia = false,
  ]) {
    final angle = _random.nextDouble() * 2 * math.pi;
    final speed = (isMedia ? 0.45 : 0.32) * (0.45 + _random.nextDouble() * 0.75);
    final phase = _random.nextDouble() * 2 * math.pi;
    final phaseSpeed = 0.06 + _random.nextDouble() * 0.09;
    final r = _random.nextDouble();
    final int tier = r < 0.48
        ? 0
        : (r < 0.84 ? 1 : 2);

    return SpoilerParticle(
      nx: _random.nextDouble(),
      ny: _random.nextDouble(),
      vx: math.cos(angle) * speed,
      vy: math.sin(angle) * speed,
      alpha: 0.25 + 0.70 * (0.5 + 0.5 * math.sin(phase)),
      phase: phase,
      phaseSpeed: phaseSpeed,
      sizeTier: tier,
    );
  }

  double get x => nx * 300.0;
  double get y => ny * 40.0;

  void update(double width, double height) => updateIdle(width, height);

  void updateIdle(double rectWidth, double rectHeight) {
    if (rectWidth <= 0 || rectHeight <= 0) return;

    nx += vx / math.max(rectWidth, 8.0);
    ny += vy / math.max(rectHeight, 8.0);

    // Toroidal wrap preserves strictly uniform spatial distribution even in tiny rects
    if (nx < 0.0) {
      nx += 1.0;
    } else if (nx > 1.0) {
      nx -= 1.0;
    }
    if (ny < 0.0) {
      ny += 1.0;
    } else if (ny > 1.0) {
      ny -= 1.0;
    }

    phase += phaseSpeed;
    if (phase > math.pi * 200) {
      phase -= math.pi * 200;
    }
    alpha = (0.22 + 0.76 * (0.5 + 0.5 * math.sin(phase))).clamp(0.15, 0.98);
  }

  void resetExplosion() {
    explodeDx = 0.0;
    explodeDy = 0.0;
  }
}

/// Shared batch renderer that draws Telegram-style multi-layered shimmering dust
/// inside a list of [rects] without any solid background box for text spoilers.
class TelegramSpoilerPainterUtils {
  static const List<double> _alphaBuckets = [0.28, 0.52, 0.76, 0.96];

  static void paintSpoilerRects({
    required Canvas canvas,
    required List<Rect> rects,
    required List<List<SpoilerParticle>> rectParticles,
    required Color color,
    required bool isMedia,
    required double revealProgress,
    Offset? revealOrigin,
  }) {
    if (rects.isEmpty) return;

    // Compute maximum distance from revealOrigin to any corner of the spoiler rects
    double maxDist = 1.0;
    if (revealProgress > 0.0 && revealOrigin != null) {
      for (final r in rects) {
        final d1 = (r.topLeft - revealOrigin).distance;
        final d2 = (r.topRight - revealOrigin).distance;
        final d3 = (r.bottomLeft - revealOrigin).distance;
        final d4 = (r.bottomRight - revealOrigin).distance;
        maxDist = math.max(maxDist, math.max(math.max(d1, d2), math.max(d3, d4)));
      }
    }

    final double waveRadius = revealProgress * (maxDist * 1.25 + 16.0);
    final double waveBand = math.max(maxDist * 0.38, 24.0);

    // For media only, draw a subtle tinted veil; for text, NEVER draw a background box
    if (isMedia) {
      final remaining = (1.0 - revealProgress).clamp(0.0, 1.0);
      if (remaining > 0.01) {
        for (final rect in rects) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(4)),
            Paint()
              ..color = color.withValues(alpha: 0.22 * remaining)
              ..style = PaintingStyle.fill,
          );
        }
      }
    }

    // 4 alpha buckets x 2 stroke sizes for rich organic depth with minimal draw calls
    final bucketsFine = List<List<double>>.generate(4, (_) => <double>[]);
    final bucketsBold = List<List<double>>.generate(4, (_) => <double>[]);

    for (int rIdx = 0; rIdx < rects.length; rIdx++) {
      final rect = rects[rIdx];
      if (rect.width <= 0 || rect.height <= 0) continue;

      final particles = rectParticles[rIdx];
      for (int i = 0; i < particles.length; i++) {
        final p = particles[i];
        if (revealProgress <= 0.0) {
          p.updateIdle(rect.width, rect.height);
        }

        double px = rect.left + p.nx * rect.width;
        double py = rect.top + p.ny * rect.height;
        double effectiveAlpha = p.alpha;

        if (revealProgress > 0.0) {
          final origin = revealOrigin ?? rect.center;
          final dx = px - origin.dx;
          final dy = py - origin.dy;
          final dist = math.sqrt(dx * dx + dy * dy);

          // Radial wave front pushes particles outward from tap origin and dissolves them
          final waveDelta = waveRadius - dist;
          if (waveDelta > 0.0) {
            final localT = (waveDelta / waveBand).clamp(0.0, 1.0);
            final invDist = dist > 0.5 ? (1.0 / dist) : 0.0;
            final dirX = dist > 0.5 ? dx * invDist : math.cos(p.phase);
            final dirY = dist > 0.5 ? dy * invDist : math.sin(p.phase);

            final pushDistance = localT * localT * 14.0 + localT * 4.0;
            px += dirX * pushDistance + p.vx * localT * 6.0;
            py += dirY * pushDistance + p.vy * localT * 6.0;
            effectiveAlpha *= (1.0 - localT);
          } else {
            p.updateIdle(rect.width, rect.height);
            px = rect.left + p.nx * rect.width;
            py = rect.top + p.ny * rect.height;
          }
        }

        if (effectiveAlpha <= 0.04) continue;

        final int bucketIdx = effectiveAlpha < 0.38
            ? 0
            : (effectiveAlpha < 0.62
                ? 1
                : (effectiveAlpha < 0.84 ? 2 : 3));

        if (p.sizeTier == 0) {
          bucketsFine[bucketIdx]
            ..add(px)
            ..add(py);
        } else {
          bucketsBold[bucketIdx]
            ..add(px)
            ..add(py);
        }
      }
    }

    final double fineStroke = isMedia ? 1.7 : 1.25;
    final double boldStroke = isMedia ? 2.3 : 1.65;

    final paint = Paint()..strokeCap = StrokeCap.round;

    for (int b = 0; b < 4; b++) {
      final fineCoords = bucketsFine[b];
      if (fineCoords.isNotEmpty) {
        paint
            ..color = color.withValues(alpha: _alphaBuckets[b])
            ..strokeWidth = fineStroke;
        canvas.drawRawPoints(
          ui.PointMode.points,
          Float32List.fromList(fineCoords),
          paint,
        );
      }

      final boldCoords = bucketsBold[b];
      if (boldCoords.isNotEmpty) {
        paint
            ..color = color.withValues(alpha: _alphaBuckets[b])
            ..strokeWidth = boldStroke;
        canvas.drawRawPoints(
          ui.PointMode.points,
          Float32List.fromList(boldCoords),
          paint,
        );
      }
    }
  }

  /// Coalesces horizontally adjacent [TextBox] rects on the same visual line
  /// and snaps consecutive line rects vertically (`bottom == next.top`) so
  /// multi-line spoilers form a single continuous, gap-free particle cloud.
  static List<Rect> normalizeAndMergeLineRects(List<Rect> rawRects) {
    final valid = <Rect>[];
    for (final r in rawRects) {
      if (r.width > 0 && r.height > 0) {
        valid.add(r);
      }
    }
    if (valid.length <= 1) return valid;

    // 1. Merge rects on the same visual line that touch or nearly touch horizontally
    final mergedLines = <Rect>[valid.first];
    for (int i = 1; i < valid.length; i++) {
      final prev = mergedLines.last;
      final curr = valid[i];
      final bool sameLine = (curr.center.dy - prev.center.dy).abs() <=
          math.min(prev.height, curr.height) * 0.45;
      final bool horizontallyAdjacent =
          curr.left <= prev.right + 6.0 && curr.right >= prev.left - 6.0;

      if (sameLine && horizontallyAdjacent) {
        mergedLines[mergedLines.length - 1] = Rect.fromLTRB(
          math.min(prev.left, curr.left),
          math.min(prev.top, curr.top),
          math.max(prev.right, curr.right),
          math.max(prev.bottom, curr.bottom),
        );
      } else {
        mergedLines.add(curr);
      }
    }

    // 2. Snap vertical seams between consecutive lines so line[i].bottom == line[i+1].top
    for (int i = 0; i < mergedLines.length - 1; i++) {
      final upper = mergedLines[i];
      final lower = mergedLines[i + 1];
      final verticalGap = lower.top - upper.bottom;
      if (lower.top >= upper.top && verticalGap.abs() <= 10.0) {
        final seamY = (upper.bottom + lower.top) * 0.5;
        mergedLines[i] = Rect.fromLTRB(
          upper.left,
          upper.top,
          upper.right,
          seamY,
        );
        mergedLines[i + 1] = Rect.fromLTRB(
          lower.left,
          seamY,
          lower.right,
          lower.bottom,
        );
      }
    }

    return mergedLines;
  }

  static void syncParticlesForRects(
    List<Rect> rects,
    List<List<SpoilerParticle>> rectParticles, {
    required bool isMedia,
  }) {
    while (rectParticles.length < rects.length) {
      rectParticles.add(<SpoilerParticle>[]);
    }
    if (rectParticles.length > rects.length) {
      rectParticles.removeRange(rects.length, rectParticles.length);
    }

    // Strict constant spatial density (particles per square logical pixel)
    // with no high minPerRect floor or low maxPerRect ceiling that would skew density.
    final double areaDivisor = isMedia ? 24.0 : 14.5;
    final int minPerRect = isMedia ? 16 : 2;
    const int maxPerRect = 3000;

    for (int i = 0; i < rects.length; i++) {
      final r = rects[i];
      final area = math.max(0.0, r.width * r.height);
      final target = (area / areaDivisor).round().clamp(minPerRect, maxPerRect);
      final list = rectParticles[i];
      while (list.length < target) {
        list.add(SpoilerParticle.create(r.width, r.height, isMedia));
      }
      if (list.length > target) {
        list.removeRange(target, list.length);
      }
    }
  }
}

/// Interactive Spoiler Widget with Telegram-style dust cloud and radial tap reveal.
class SpoilerTextWidget extends StatefulWidget {
  final Widget child;
  final TextStyle? textStyle;
  final bool initialRevealed;
  final bool isMedia;
  final String? stateKey;
  final VoidCallback? onReveal;
  final List<InlineSpoilerRange>? inlineRanges;
  final Widget Function(
    BuildContext context,
    GlobalKey richTextKey,
    Set<int> hiddenSpoilerIds,
  )? inlineBuilder;

  const SpoilerTextWidget({
    Key? key,
    required this.child,
    this.textStyle,
    this.initialRevealed = false,
    this.isMedia = false,
    this.stateKey,
    this.onReveal,
  })  : inlineRanges = null,
        inlineBuilder = null,
        _inlineParticleColor = null,
        super(key: key);

  const SpoilerTextWidget.inlineHost({
    Key? key,
    required List<InlineSpoilerRange> this.inlineRanges,
    required Color particleColor,
    this.stateKey,
    required Widget Function(
      BuildContext context,
      GlobalKey richTextKey,
      Set<int> hiddenSpoilerIds,
    ) this.inlineBuilder,
  })  : child = const SizedBox.shrink(),
        textStyle = const TextStyle(),
        initialRevealed = false,
        isMedia = false,
        onReveal = null,
        _inlineParticleColor = particleColor,
        super(key: key);

  final Color? _inlineParticleColor;

  SpoilerTextWidget.text({
    Key? key,
    required String text,
    TextStyle? style,
    bool initialRevealed = false,
    String? stateKey,
    VoidCallback? onReveal,
  }) : this(
          key: key,
          child: Text(
            text,
            style: style,
          ),
          textStyle: style,
          initialRevealed: initialRevealed,
          isMedia: false,
          stateKey: stateKey ?? 'text_${text.hashCode}',
          onReveal: onReveal,
        );

  @override
  State<SpoilerTextWidget> createState() => _SpoilerTextWidgetState();
}

class _SpoilerTextWidgetState extends State<SpoilerTextWidget>
    with TickerProviderStateMixin {
  late bool _isFullyRevealed;
  bool _isRevealing = false;
  Offset? _tapOrigin;

  late AnimationController _loopController;
  late AnimationController _revealController;
  late Animation<double> _revealAnimation;

  final List<List<SpoilerParticle>> _localRectParticles = [];
  final GlobalKey _childKey = GlobalKey();
  MessageInteractiveEntry? _interactiveEntry;

  String get _effectiveStateKey =>
      widget.stateKey ??
      (widget.isMedia ? 'media_spoiler' : 'block_spoiler');

  List<List<SpoilerParticle>> get _activeRectParticles =>
      _interactiveEntry?.getBlockParticles(_effectiveStateKey) ??
      _localRectParticles;

  bool get _isInlineHost =>
      widget.inlineRanges != null && widget.inlineBuilder != null;

  @override
  void initState() {
    super.initState();
    _isFullyRevealed = widget.initialRevealed;

    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _revealAnimation = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (mounted) {
            setState(() {
              _isFullyRevealed = true;
              _isRevealing = false;
              _loopController.stop();
            });
          }
          _interactiveEntry?.setBlockSpoilerRevealed(
            _effectiveStateKey,
            true,
          );
        }
      });

    if (!_isFullyRevealed && !_isInlineHost) {
      _loopController.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInlineHost) return;
    final newEntry = MessageInteractiveScope.maybeOf(context);
    if (_interactiveEntry != newEntry) {
      _interactiveEntry?.removeListener(_onInteractiveEntryChanged);
      _interactiveEntry = newEntry;
      _interactiveEntry?.addListener(_onInteractiveEntryChanged);
    }
    _syncFromInteractiveEntry(initial: true);
  }

  void _onInteractiveEntryChanged() {
    if (!mounted) return;
    _syncFromInteractiveEntry(initial: false);
  }

  void _syncFromInteractiveEntry({required bool initial}) {
    final entry = _interactiveEntry;
    if (entry == null) return;
    final savedRevealed = entry.getBlockSpoilerRevealed(_effectiveStateKey);
    if (savedRevealed != null && savedRevealed != _isFullyRevealed && !_isRevealing) {
      if (initial) {
        _isFullyRevealed = savedRevealed;
        if (_isFullyRevealed) {
          _loopController.stop();
        } else if (!_loopController.isAnimating) {
          _loopController.repeat();
        }
      } else {
        setState(() {
          _isFullyRevealed = savedRevealed;
          if (_isFullyRevealed) {
            _loopController.stop();
          } else if (!_loopController.isAnimating) {
            _loopController.repeat();
          }
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant SpoilerTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isInlineHost) return;
    if (widget.initialRevealed != oldWidget.initialRevealed &&
        widget.initialRevealed != _isFullyRevealed) {
      setState(() {
        _isFullyRevealed = widget.initialRevealed;
        _isRevealing = false;
        if (_isFullyRevealed) {
          _loopController.stop();
        } else {
          _loopController.repeat();
        }
      });
    }
  }

  @override
  void dispose() {
    if (_isRevealing) {
      _interactiveEntry?.setBlockSpoilerRevealed(_effectiveStateKey, true);
    }
    _interactiveEntry?.removeListener(_onInteractiveEntryChanged);
    _loopController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _tapOrigin = details.localPosition;
  }

  void _reveal() {
    if (_isFullyRevealed || _isRevealing) return;
    HapticUtils.tap();
    setState(() {
      _isRevealing = true;
    });
    _revealController.forward(from: 0.0);
    widget.onReveal?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInlineHost) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return TelegramInlineSpoilerHost(
        spoilerRanges: widget.inlineRanges!,
        particleColor: widget._inlineParticleColor ??
            DefaultTextStyle.of(context).style.color ??
            (isDark ? Colors.white : Colors.black),
        stateKey: widget.stateKey ?? 'inline_spoiler',
        builder: widget.inlineBuilder!,
      );
    }

    if (_isFullyRevealed) {
      return widget.child;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final particleColor = widget.textStyle?.color ??
        DefaultTextStyle.of(context).style.color ??
        (isDark ? Colors.white : Colors.black);

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTap: _reveal,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: _isRevealing ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Stack(
          fit: StackFit.passthrough,
          alignment: Alignment.center,
          children: [
            // Hidden / radially revealing child
            AnimatedBuilder(
              animation: _revealAnimation,
              builder: (context, child) {
                if (!_isRevealing) {
                  return Opacity(
                    opacity: widget.isMedia ? 0.04 : 0.0,
                    child: child,
                  );
                }
                final t = _revealAnimation.value;
                if (t >= 0.99) return child!;
                return ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (Rect bounds) {
                    final origin = _tapOrigin ?? bounds.center;
                    final maxR = math.max(
                      math.max(
                        (bounds.topLeft - origin).distance,
                        (bounds.topRight - origin).distance,
                      ),
                      math.max(
                        (bounds.bottomLeft - origin).distance,
                        (bounds.bottomRight - origin).distance,
                      ),
                    );
                    final currentR = t * (maxR * 1.25 + 12.0);
                    final feather = math.max(maxR * 0.25, 16.0);
                    final stopInner = ((currentR - feather) / math.max(currentR, 1.0)).clamp(0.0, 0.95);
                    final alignX = bounds.width > 0
                        ? ((origin.dx / bounds.width) * 2.0 - 1.0)
                        : 0.0;
                    final alignY = bounds.height > 0
                        ? ((origin.dy / bounds.height) * 2.0 - 1.0)
                        : 0.0;
                    final radiusRatio = currentR / math.max( math.max(bounds.width, bounds.height), 1.0);
                    return RadialGradient(
                      center: Alignment(alignX, alignY),
                      radius: math.max(radiusRatio, 0.01),
                      colors: const [Colors.white, Colors.white, Colors.transparent],
                      stops: [0.0, stopInner, 1.0],
                    ).createShader(bounds);
                  },
                  child: child,
                );
              },
              child: KeyedSubtree(
                key: _childKey,
                child: widget.child,
              ),
            ),

            // Animated Telegram dust particle layer
            if (!_isFullyRevealed)
              Positioned.fill(
                child: CustomPaint(
                  painter: _TelegramSpoilerParticlePainter(
                    childKey: _childKey,
                    rectParticles: _activeRectParticles,
                    color: particleColor,
                    isMedia: widget.isMedia,
                    revealAnimation: _isRevealing ? _revealAnimation : null,
                    revealOrigin: _tapOrigin,
                    repaint: _isRevealing ? _revealAnimation : _loopController,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TelegramSpoilerParticlePainter extends CustomPainter {
  final GlobalKey? childKey;
  final List<List<SpoilerParticle>> rectParticles;
  final Color color;
  final bool isMedia;
  final Animation<double>? revealAnimation;
  final Offset? revealOrigin;

  _TelegramSpoilerParticlePainter({
    this.childKey,
    required this.rectParticles,
    required this.color,
    required this.isMedia,
    this.revealAnimation,
    this.revealOrigin,
    required Listenable repaint,
  }) : super(repaint: repaint);

  static List<RenderParagraph> _findRenderParagraphs(RenderObject? root) {
    final list = <RenderParagraph>[];
    if (root == null) return list;
    void visitor(RenderObject child) {
      if (child is RenderParagraph) {
        list.add(child);
      }
      child.visitChildren(visitor);
    }
    if (root is RenderParagraph) {
      list.add(root);
    } else {
      root.visitChildren(visitor);
    }
    return list;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final revealT = revealAnimation?.value ?? 0.0;
    if (revealT >= 1.0) return;

    var textRects = <Rect>[];
    final childBox = childKey?.currentContext?.findRenderObject() as RenderBox?;

    if (!isMedia && childBox != null && childBox.hasSize) {
      final paragraphs = _findRenderParagraphs(childBox);
      for (final p in paragraphs) {
        final plain = p.text.toPlainText();
        if (plain.isEmpty) continue;
        final boxes = p.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: plain.length),
          boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
        );
        final paraRects = <Rect>[];
        for (final box in boxes) {
          final rawRect = box.toRect();
          if (rawRect.width <= 0 || rawRect.height <= 0) continue;
          try {
            final pGlobal = p.localToGlobal(rawRect.topLeft);
            final localOrigin = childBox.globalToLocal(pGlobal);
            paraRects.add(Rect.fromLTWH(localOrigin.dx, localOrigin.dy, rawRect.width, rawRect.height));
          } catch (_) {
            paraRects.add(rawRect);
          }
        }
        textRects.addAll(
          TelegramSpoilerPainterUtils.normalizeAndMergeLineRects(paraRects),
        );
      }
    }

    if (textRects.isEmpty) {
      textRects = <Rect>[Offset.zero & size];
    }

    TelegramSpoilerPainterUtils.syncParticlesForRects(
      textRects,
      rectParticles,
      isMedia: isMedia,
    );

    TelegramSpoilerPainterUtils.paintSpoilerRects(
      canvas: canvas,
      rects: textRects,
      rectParticles: rectParticles,
      color: color,
      isMedia: isMedia,
      revealProgress: revealT,
      revealOrigin: revealOrigin,
    );
  }

  @override
  bool shouldRepaint(covariant _TelegramSpoilerParticlePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.revealAnimation != revealAnimation ||
        oldDelegate.revealOrigin != revealOrigin ||
        oldDelegate.childKey != childKey;
  }
}

/// Range descriptor for an inline spoiler inside a [RichText] paragraph.
class InlineSpoilerRange {
  final int id;
  final int start;
  final int end;

  const InlineSpoilerRange({
    required this.id,
    required this.start,
    required this.end,
  });
}

/// Wraps a [RichText] paragraph that contains one or more inline `spoiler` entities,
/// drawing Telegram's floating particle cloud directly over the exact line boxes
/// of each spoiler range while allowing natural multi-line word wrapping and inline
/// bubble timestamps.
class TelegramInlineSpoilerHost extends StatefulWidget {
  final List<InlineSpoilerRange> spoilerRanges;
  final Color particleColor;
  final String stateKey;
  final Widget Function(
    BuildContext context,
    GlobalKey richTextKey,
    Set<int> hiddenSpoilerIds,
  ) builder;

  const TelegramInlineSpoilerHost({
    Key? key,
    required this.spoilerRanges,
    required this.particleColor,
    this.stateKey = 'inline_spoiler',
    required this.builder,
  }) : super(key: key);

  @override
  State<TelegramInlineSpoilerHost> createState() => _TelegramInlineSpoilerHostState();
}

class _TelegramInlineSpoilerHostState extends State<TelegramInlineSpoilerHost>
    with TickerProviderStateMixin {
  final GlobalKey _richTextKey = GlobalKey();
  late Set<int> _hiddenIds;
  int? _revealingId;
  Offset? _revealOrigin;

  late AnimationController _loopController;
  late AnimationController _revealController;
  late Animation<double> _revealAnimation;

  final Map<int, List<List<SpoilerParticle>>> _localParticlesBySpoilerId = {};
  final Map<int, List<Rect>> _localCachedRectsBySpoilerId = {};
  MessageInteractiveEntry? _interactiveEntry;

  Map<int, List<List<SpoilerParticle>>> get _activeParticlesBySpoilerId =>
      _interactiveEntry?.getInlineParticles(widget.stateKey) ??
      _localParticlesBySpoilerId;

  Map<int, List<Rect>> get _cachedRectsBySpoilerId =>
      _interactiveEntry?.getInlineCachedRects(widget.stateKey) ??
      _localCachedRectsBySpoilerId;

  @override
  void initState() {
    super.initState();
    _hiddenIds = widget.spoilerRanges.map((r) => r.id).toSet();

    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _revealAnimation = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          final completedId = _revealingId;
          if (mounted) {
            setState(() {
              if (completedId != null) {
                _hiddenIds.remove(completedId);
                _activeParticlesBySpoilerId.remove(completedId);
                _cachedRectsBySpoilerId.remove(completedId);
                _revealingId = null;
              }
              if (_hiddenIds.isEmpty) {
                _loopController.stop();
              }
            });
          }
          if (completedId != null) {
            _interactiveEntry?.markInlineSpoilerRevealed(
              widget.stateKey,
              completedId,
            );
          }
        }
      });

    if (_hiddenIds.isNotEmpty) {
      _loopController.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newEntry = MessageInteractiveScope.maybeOf(context);
    if (_interactiveEntry != newEntry) {
      _interactiveEntry?.removeListener(_onInteractiveEntryChanged);
      _interactiveEntry = newEntry;
      _interactiveEntry?.addListener(_onInteractiveEntryChanged);
    }
    _syncFromInteractiveEntry(initial: true);
  }

  void _onInteractiveEntryChanged() {
    if (!mounted) return;
    _syncFromInteractiveEntry(initial: false);
  }

  void _syncFromInteractiveEntry({required bool initial}) {
    final entry = _interactiveEntry;
    if (entry == null) return;
    final revealedSet = entry.getRevealedInlineSpoilers(widget.stateKey);
    if (revealedSet.isEmpty) return;

    final nextHidden = <int>{
      for (final id in _hiddenIds)
        if (!revealedSet.contains(id)) id,
    };
    if (nextHidden.length != _hiddenIds.length) {
      if (initial) {
        _hiddenIds = nextHidden;
        if (_hiddenIds.isEmpty) {
          _loopController.stop();
        }
      } else {
        setState(() {
          _hiddenIds = nextHidden;
          if (_revealingId != null && revealedSet.contains(_revealingId)) {
            _revealingId = null;
          }
          if (_hiddenIds.isEmpty) {
            _loopController.stop();
          }
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant TelegramInlineSpoilerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newIds = widget.spoilerRanges.map((r) => r.id).toSet();
    final oldIds = oldWidget.spoilerRanges.map((r) => r.id).toSet();
    if (newIds.length != oldIds.length || !newIds.containsAll(oldIds)) {
      final revealedSet =
          _interactiveEntry?.getRevealedInlineSpoilers(widget.stateKey) ??
              const <int>{};
      _hiddenIds = <int>{
        for (final id in newIds)
          if (!revealedSet.contains(id)) id,
      };
      _revealingId = null;
      _activeParticlesBySpoilerId.clear();
      _cachedRectsBySpoilerId.clear();
      if (_hiddenIds.isNotEmpty && !_loopController.isAnimating) {
        _loopController.repeat();
      } else if (_hiddenIds.isEmpty) {
        _loopController.stop();
      }
    }
  }

  @override
  void dispose() {
    if (_revealingId != null) {
      _interactiveEntry?.markInlineSpoilerRevealed(
        widget.stateKey,
        _revealingId!,
      );
    }
    _interactiveEntry?.removeListener(_onInteractiveEntryChanged);
    _loopController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  RenderParagraph? _findParagraph() {
    final ro = _richTextKey.currentContext?.findRenderObject();
    if (ro is RenderParagraph) return ro;
    RenderParagraph? found;
    void visitor(RenderObject child) {
      if (found != null) return;
      if (child is RenderParagraph) {
        found = child;
        return;
      }
      child.visitChildren(visitor);
    }
    ro?.visitChildren(visitor);
    return found;
  }

  int? _hitTestSpoiler(Offset localPos) {
    if (_hiddenIds.isEmpty) return null;
    final paragraph = _findParagraph();
    if (paragraph != null && paragraph.hasSize) {
      for (final range in widget.spoilerRanges) {
        if (!_hiddenIds.contains(range.id)) continue;
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: range.start, extentOffset: range.end),
        );
        for (final box in boxes) {
          if (box.toRect().inflate(3.0).contains(localPos)) {
            return range.id;
          }
        }
      }
    }
    for (final entry in _cachedRectsBySpoilerId.entries) {
      if (!_hiddenIds.contains(entry.key)) continue;
      for (final rect in entry.value) {
        if (rect.inflate(3.0).contains(localPos)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  void _triggerReveal(int spoilerId, Offset tapPos) {
    if (_revealingId == spoilerId) return;
    HapticUtils.tap();
    final previousRevealingId = _revealingId;
    setState(() {
      // If another spoiler was mid-reveal, finish revealing it immediately
      if (previousRevealingId != null) {
        _hiddenIds.remove(previousRevealingId);
      }
      _revealingId = spoilerId;
      _revealOrigin = tapPos;
    });
    if (previousRevealingId != null) {
      _interactiveEntry?.markInlineSpoilerRevealed(
        widget.stateKey,
        previousRevealingId,
      );
    }
    _revealController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    // Text inside a spoiler becomes visible as soon as its radial reveal starts
    // (masked by the dispersing particle cloud) or once revealed.
    final effectivelyHiddenForText = <int>{
      for (final id in _hiddenIds)
        if (id != _revealingId) id,
    };

    final richTextChild = widget.builder(
      context,
      _richTextKey,
      effectivelyHiddenForText,
    );

    if (_hiddenIds.isEmpty) {
      return richTextChild;
    }

    return _SpoilerTapInterceptor(
      hitTestSpoiler: _hitTestSpoiler,
      onSpoilerTap: _triggerReveal,
      child: CustomPaint(
        foregroundPainter: _InlineSpoilersForegroundPainter(
          richTextKey: _richTextKey,
          spoilerRanges: widget.spoilerRanges,
          hiddenIds: _hiddenIds,
          revealingId: _revealingId,
          revealAnimation: _revealingId != null ? _revealAnimation : null,
          revealOrigin: _revealOrigin,
          particleColor: widget.particleColor,
          particlesBySpoilerId: _activeParticlesBySpoilerId,
          cachedRectsBySpoilerId: _cachedRectsBySpoilerId,
          repaint: Listenable.merge([_loopController, _revealAnimation]),
        ),
        child: richTextChild,
      ),
    );
  }
}

/// Custom gesture wrapper that intercepts pointer taps ONLY when the pointer
/// lands inside an unrevealed spoiler rect. Participates in [GestureArena] so
/// tapping a hidden spoiler does NOT trigger the ancestor message bubble's `onTap`
/// (context menu), while letting drags/scrolls, long-presses, and taps outside
/// hidden spoilers pass through normally.
class _SpoilerTapInterceptor extends StatelessWidget {
  final int? Function(Offset localPos) hitTestSpoiler;
  final void Function(int spoilerId, Offset localPos) onSpoilerTap;
  final Widget child;

  const _SpoilerTapInterceptor({
    required this.hitTestSpoiler,
    required this.onSpoilerTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        _SpoilerTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_SpoilerTapGestureRecognizer>(
          () => _SpoilerTapGestureRecognizer(),
          (_SpoilerTapGestureRecognizer instance) {
            instance
              ..hitTestSpoiler = hitTestSpoiler
              ..onSpoilerTap = onSpoilerTap;
          },
        ),
      },
      child: child,
    );
  }
}

class _SpoilerTapGestureRecognizer extends OneSequenceGestureRecognizer {
  int? Function(Offset localPos)? hitTestSpoiler;
  void Function(int spoilerId, Offset localPos)? onSpoilerTap;

  int? _activePointer;
  int? _pendingSpoilerId;
  Offset? _downPos;
  int? _downTimeMs;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return false;
    final hitId = hitTestSpoiler?.call(event.localPosition);
    if (hitId == null) return false;
    _pendingSpoilerId = hitId;
    _downPos = event.localPosition;
    _downTimeMs = DateTime.now().millisecondsSinceEpoch;
    return super.isPointerAllowed(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _activePointer = event.pointer;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _activePointer) return;

    if (event is PointerMoveEvent) {
      final startPos = _downPos;
      if (startPos != null &&
          (event.localPosition - startPos).distance > 12.0) {
        _reset();
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
      }
    } else if (event is PointerUpEvent) {
      final id = _pendingSpoilerId;
      final startPos = _downPos;
      final startMs = _downTimeMs;
      _reset();

      if (id != null && startPos != null && startMs != null) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
        final moved = (event.localPosition - startPos).distance;
        if (elapsed < 450 && moved <= 12.0) {
          resolve(GestureDisposition.accepted);
          onSpoilerTap?.call(id, event.localPosition);
          stopTrackingPointer(event.pointer);
          return;
        }
      }
      resolve(GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
    } else if (event is PointerCancelEvent) {
      _reset();
      resolve(GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _activePointer = null;
  }

  void _reset() {
    _pendingSpoilerId = null;
    _downPos = null;
    _downTimeMs = null;
  }

  @override
  String get debugDescription => 'spoiler_tap';
}

class _InlineSpoilersForegroundPainter extends CustomPainter {
  final GlobalKey richTextKey;
  final List<InlineSpoilerRange> spoilerRanges;
  final Set<int> hiddenIds;
  final int? revealingId;
  final Animation<double>? revealAnimation;
  final Offset? revealOrigin;
  final Color particleColor;
  final Map<int, List<List<SpoilerParticle>>> particlesBySpoilerId;
  final Map<int, List<Rect>> cachedRectsBySpoilerId;

  _InlineSpoilersForegroundPainter({
    required this.richTextKey,
    required this.spoilerRanges,
    required this.hiddenIds,
    required this.revealingId,
    required this.revealAnimation,
    required this.revealOrigin,
    required this.particleColor,
    required this.particlesBySpoilerId,
    required this.cachedRectsBySpoilerId,
    required Listenable repaint,
  }) : super(repaint: repaint);

  RenderParagraph? _findParagraph() {
    final ro = richTextKey.currentContext?.findRenderObject();
    if (ro is RenderParagraph) return ro;
    RenderParagraph? found;
    void visitor(RenderObject child) {
      if (found != null) return;
      if (child is RenderParagraph) {
        found = child;
        return;
      }
      child.visitChildren(visitor);
    }
    ro?.visitChildren(visitor);
    return found;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (hiddenIds.isEmpty || size.width <= 0 || size.height <= 0) return;

    final paragraph = _findParagraph();
    final bool hasParagraph = paragraph != null && paragraph.hasSize;
    final int plainLen = hasParagraph ? paragraph.text.toPlainText().length : 0;

    for (final range in spoilerRanges) {
      if (!hiddenIds.contains(range.id)) continue;

      List<Rect> rects = const <Rect>[];
      if (hasParagraph) {
        final start = range.start.clamp(0, plainLen);
        final end = range.end.clamp(start, plainLen);
        if (start < end) {
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: end),
            boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
          );
          final rawRects = <Rect>[];
          for (final box in boxes) {
            final r = box.toRect();
            if (r.width > 0 && r.height > 0) {
              rawRects.add(r);
            }
          }
          rects = TelegramSpoilerPainterUtils.normalizeAndMergeLineRects(
            rawRects,
          );
          if (rects.isNotEmpty) {
            cachedRectsBySpoilerId[range.id] = rects;
          }
        }
      }
      if (rects.isEmpty) {
        rects = cachedRectsBySpoilerId[range.id] ?? const <Rect>[];
      }
      if (rects.isEmpty) continue;

      final particleLists = particlesBySpoilerId.putIfAbsent(
        range.id,
        () => <List<SpoilerParticle>>[],
      );

      TelegramSpoilerPainterUtils.syncParticlesForRects(
        rects,
        particleLists,
        isMedia: false,
      );

      final bool isThisRevealing = revealingId == range.id;
      final double revealT = isThisRevealing
          ? (revealAnimation?.value ?? 0.0)
          : 0.0;

      TelegramSpoilerPainterUtils.paintSpoilerRects(
        canvas: canvas,
        rects: rects,
        rectParticles: particleLists,
        color: particleColor,
        isMedia: false,
        revealProgress: revealT,
        revealOrigin: isThisRevealing ? revealOrigin : null,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _InlineSpoilersForegroundPainter oldDelegate) {
    return oldDelegate.particleColor != particleColor ||
        oldDelegate.hiddenIds != hiddenIds ||
        oldDelegate.revealingId != revealingId ||
        oldDelegate.revealAnimation != revealAnimation ||
        oldDelegate.revealOrigin != revealOrigin;
  }
}
