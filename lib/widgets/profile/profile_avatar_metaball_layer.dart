import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/profile_customization.dart';
import '../../services/display_cutout_service.dart';
import '../../services/power_saving_provider.dart';
import '../user/avatar_decoration_frame.dart';
import 'expandable_avatar.dart';

/// Pure kinematic & optical snapshot of the profile avatar metaball at a given
/// vertical [scrollOffset]. Separated for deterministic `O(1)` evaluation and unit testing.
@immutable
class ProfileAvatarMetaballGeometry {
  static const double defaultCollapseExtent = 155.0;
  static const double baseAvatarDiameter = 110.0;
  static const double decorationOuterMultiplier = 1.24;
  static const double decorationFullContractScale = 0.81;
  static const double decorationUnmountProgress = 0.36;
  static const double scalarFieldActivationGapDp = 24.0;
  static const double blackKingBarHeight = 32.0;

  final double progress;
  final Offset startCenter;
  final Offset controlPoint;
  final Offset targetCenter;
  final Offset avatarCenter;
  final double avatarDiameter;
  final double avatarScale;
  final double edgeGapDp;
  final Offset suctionDirection;
  final Offset anchorNeckOrigin;
  final double cutoutClipTopY;
  final bool isCornerTrajectory;
  final bool isScalarFieldActive;
  final double scalarBlurSigma;
  final double scalarFieldOpacity;
  final double avatarBlurSigma;
  final double avatarRgbScale;
  final double avatarAlpha;
  final double frameContractFactor;
  final double frameOpacity;
  final bool frameMounted;
  final bool frameShouldAnimate;

  const ProfileAvatarMetaballGeometry({
    required this.progress,
    required this.startCenter,
    required this.controlPoint,
    required this.targetCenter,
    required this.avatarCenter,
    required this.avatarDiameter,
    required this.avatarScale,
    required this.edgeGapDp,
    required this.suctionDirection,
    required this.anchorNeckOrigin,
    required this.cutoutClipTopY,
    required this.isCornerTrajectory,
    required this.isScalarFieldActive,
    required this.scalarBlurSigma,
    required this.scalarFieldOpacity,
    required this.avatarBlurSigma,
    required this.avatarRgbScale,
    required this.avatarAlpha,
    required this.frameContractFactor,
    required this.frameOpacity,
    required this.frameMounted,
    required this.frameShouldAnimate,
  });

  static ProfileAvatarMetaballGeometry compute({
    required double scrollOffset,
    required double screenWidth,
    required double statusBarHeight,
    required double topOffset,
    required DisplayCutoutSpec cutout,
    double collapseScrollExtent = defaultCollapseExtent,
  }) {
    final safeExtent = collapseScrollExtent > 1.0
        ? collapseScrollExtent
        : defaultCollapseExtent;
    final p = (scrollOffset / safeExtent).clamp(0.0, 1.0);

    final halfW = screenWidth * 0.5;
    final p0 = Offset(halfW, topOffset + baseAvatarDiameter * 0.5);

    final Offset p2;
    final double d2;
    switch (cutout.kind) {
      case CutoutAnchorKind.punchHole:
        p2 = cutout.bounds.center;
        final minDim = math.min(cutout.bounds.width, cutout.bounds.height);
        d2 = (0.55 * minDim).clamp(10.0, 18.0);
      case CutoutAnchorKind.dynamicIsland:
        p2 = Offset(halfW, cutout.bounds.center.dy);
        d2 = 18.0;
      case CutoutAnchorKind.topNotch:
        p2 = Offset(halfW, math.max(6.0, cutout.bounds.bottom - 10.0));
        d2 = 18.0;
      case CutoutAnchorKind.none:
        p2 = Offset(halfW, -18.0);
        d2 = 22.0;
    }

    final bool isCorner = cutout.isCorner;
    final Offset p1;
    if (isCorner) {
      final rawControlY = math.max(p2.dy + 42.0, statusBarHeight + 30.0);
      final clampedControlY = p0.dy > p2.dy + 16.0
          ? math.min(p0.dy - 8.0, rawControlY)
          : (p0.dy + p2.dy) * 0.5;
      p1 = Offset(
        p2.dx + 0.18 * (p0.dx - p2.dx),
        clampedControlY,
      );
    } else {
      p1 = Offset((p0.dx + p2.dx) * 0.5, (p0.dy + p2.dy) * 0.5);
    }

    // Follow scroll 1:1 on vertical trajectory (matching Telegram's SettingsActivity/ProfileActivity)
    // and gentle sine easing on corner Bezier arcs, with linear diameter scaling.
    final tPos = isCorner ? Curves.easeInOutSine.transform(p) : p;
    final tSize = p;

    final Offset currentCenter;
    if (isCorner) {
      final u = 1.0 - tPos;
      currentCenter = Offset(
        u * u * p0.dx + 2.0 * u * tPos * p1.dx + tPos * tPos * p2.dx,
        u * u * p0.dy + 2.0 * u * tPos * p1.dy + tPos * tPos * p2.dy,
      );
    } else {
      currentCenter = Offset(
        ui.lerpDouble(p0.dx, p2.dx, tPos)!,
        ui.lerpDouble(p0.dy, p2.dy, tPos)!,
      );
    }

    final currentDiameter = ui.lerpDouble(baseAvatarDiameter, d2, tSize)!;
    final currentRadius = currentDiameter * 0.5;
    final currentScale = currentDiameter / baseAvatarDiameter;

    // Signed distance & neck orientation toward the cutout or top edge.
    final double dGap;
    final Offset neckTarget;
    if (cutout.hasCutout) {
      final ca = cutout.bounds.center;
      final a = cutout.bounds.width * 0.5;
      final b = cutout.bounds.height * 0.5;
      final r = math.min(cutout.cornerRadius, math.min(a, b));
      final qx = (currentCenter.dx - ca.dx).abs() - (a - r);
      final qy = (currentCenter.dy - ca.dy).abs() - (b - r);
      final outsideDist = Offset(math.max(qx, 0.0), math.max(qy, 0.0)).distance;
      final insideDist = math.min(math.max(qx, qy), 0.0);
      dGap = (outsideDist + insideDist - r) - currentRadius;

      if (cutout.kind == CutoutAnchorKind.topNotch) {
        neckTarget = Offset(
          currentCenter.dx.clamp(
            cutout.bounds.left + 12.0,
            cutout.bounds.right - 12.0,
          ),
          math.max(0.0, cutout.bounds.bottom - 6.0),
        );
      } else {
        neckTarget = ca;
      }
    } else {
      dGap = currentCenter.dy - currentRadius;
      neckTarget = Offset(currentCenter.dx, -6.0);
    }

    final deltaToNeck = neckTarget - currentCenter;
    final distToNeck = deltaToNeck.distance;
    final uDir = distToNeck > 0.001
        ? (deltaToNeck / distToNeck)
        : const Offset(0.0, -1.0);

    final cutoutClipTopY =
        (cutout.hasCutout && cutout.bounds.top > 1.0) ? cutout.bounds.top : 0.0;

    // Compact logical-dp Gaussian sigma (matching Telegram's ~15px = ~5dp radius)
    // so the cutout anchor stays strictly inside the physical camera hole without
    // shifting its center or edges when the neck forms.
    final scalarBlurSigma = switch (cutout.kind) {
      CutoutAnchorKind.punchHole => 5.0,
      _ => 6.0,
    };

    final scalarFieldOpacity = p <= 0.93
        ? 1.0
        : (1.0 -
            Curves.easeInCubic.transform(((p - 0.93) / 0.066).clamp(0.0, 1.0)));

    final isScalarFieldActive = p > 0.002 &&
        p < 0.998 &&
        dGap <= scalarFieldActivationGapDp &&
        scalarFieldOpacity > 0.002;

    // Keep photo 100% sharp through the first 45% of scroll, then apply subtle
    // optical softness (up to 4.5dp) as it nears the camera cutout.
    final avatarBlurProgress = ((p - 0.45) / 0.45).clamp(0.0, 1.0);
    final avatarBlurSigma =
        4.5 * Curves.easeInQuad.transform(avatarBlurProgress);

    // Keep full natural photo colors all the way to cutout contact (p <= 0.72),
    // darkening into #000000 only during final absorption inside the cutout (0.72..0.95).
    final darkenProgress = ((p - 0.72) / 0.23).clamp(0.0, 1.0);
    final avatarRgbScale = 1.0 - Curves.easeInCubic.transform(darkenProgress);

    final fadeProgress = ((p - 0.88) / 0.105).clamp(0.0, 1.0);
    final avatarAlpha = 1.0 - Curves.easeInOutCubic.transform(fadeProgress);

    // Custom avatar decoration frame ("absorb into droplet" on scroll up, "bloom" on scroll down).
    final frameMounted = p < decorationUnmountProgress;
    final frameContractT = Curves.easeInCubic
        .transform(((p - 0.02) / 0.34).clamp(0.0, 1.0));
    final frameContractFactor = ui.lerpDouble(
      1.0,
      decorationFullContractScale,
      frameContractT,
    )!;
    final frameFadeT = Curves.easeOutCubic
        .transform(((p - 0.04) / 0.32).clamp(0.0, 1.0));
    final frameOpacity = (1.0 - frameFadeT).clamp(0.0, 1.0);
    final frameShouldAnimate = p < 0.08;

    return ProfileAvatarMetaballGeometry(
      progress: p,
      startCenter: p0,
      controlPoint: p1,
      targetCenter: p2,
      avatarCenter: currentCenter,
      avatarDiameter: currentDiameter,
      avatarScale: currentScale,
      edgeGapDp: dGap,
      suctionDirection: uDir,
      anchorNeckOrigin: neckTarget,
      cutoutClipTopY: cutoutClipTopY,
      isCornerTrajectory: isCorner,
      isScalarFieldActive: isScalarFieldActive,
      scalarBlurSigma: scalarBlurSigma,
      scalarFieldOpacity: scalarFieldOpacity,
      avatarBlurSigma: avatarBlurSigma,
      avatarRgbScale: avatarRgbScale,
      avatarAlpha: avatarAlpha,
      frameContractFactor: frameContractFactor,
      frameOpacity: frameOpacity,
      frameMounted: frameMounted,
      frameShouldAnimate: frameShouldAnimate,
    );
  }
}

/// Renders the collapsed circular profile avatar with Telegram-style liquid
/// metaball suction into Dynamic Island, top notches, centered/corner punch-holes
/// (including unified dual-camera ovals), or the top edge, while smoothly
/// contracting custom [AvatarDecorationFrame] rings into the droplet core.
class ProfileAvatarMetaballLayer extends StatefulWidget {
  final GlobalKey? avatarKey;
  final GlobalKey? viewportKey;
  final double scrollOffset;
  final double screenWidth;
  final double statusBarHeight;
  final double topOffset;
  final PageController? pageController;
  final int? initialPage;
  final List<String> avatarUrls;
  final File? avatarFile;
  final Color? tintColor;
  final Color? backgroundColor;
  final String displayName;
  final AvatarDecorationPreset? decoration;
  final String? chatAvatarHeroTag;
  final VoidCallback? onTap;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final ValueChanged<int>? onPageChanged;

  const ProfileAvatarMetaballLayer({
    super.key,
    this.avatarKey,
    this.viewportKey,
    required this.scrollOffset,
    required this.screenWidth,
    required this.statusBarHeight,
    required this.topOffset,
    this.pageController,
    this.initialPage,
    this.avatarUrls = const [],
    this.avatarFile,
    this.tintColor,
    this.backgroundColor,
    this.displayName = '',
    this.decoration,
    this.chatAvatarHeroTag,
    this.onTap,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onPageChanged,
  });

  @override
  State<ProfileAvatarMetaballLayer> createState() =>
      _ProfileAvatarMetaballLayerState();
}

class _ProfileAvatarMetaballLayerState
    extends State<ProfileAvatarMetaballLayer> {
  static const double _kStaticTopBufferPad = 40.0;

  static const ColorFilter _kMetaballThresholdColorFilter =
      ColorFilter.matrix(<double>[
    0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 51.0, -6375.0,
  ]);

  final GlobalKey _internalAvatarKey =
      GlobalKey(debugLabel: 'metaball_expandable_avatar');
  final GlobalKey _decorationCompanionKey =
      GlobalKey(debugLabel: 'metaball_decoration_companion');

  late final Listenable _mergedListenables = Listenable.merge(<Listenable>[
    DisplayCutoutService.instance,
    PowerSavingProvider.instance,
  ]);

  static ColorFilter _buildDarkenAndFadeMatrix(double rgbScale, double alpha) {
    final c = rgbScale.clamp(0.0, 1.0);
    final a = alpha.clamp(0.0, 1.0);
    return ColorFilter.matrix(<double>[
      c, 0.0, 0.0, 0.0, 0.0,
      0.0, c, 0.0, 0.0, 0.0,
      0.0, 0.0, c, 0.0, 0.0,
      0.0, 0.0, 0.0, a, 0.0,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final quickProgress = (widget.scrollOffset /
            ProfileAvatarMetaballGeometry.defaultCollapseExtent)
        .clamp(0.0, 1.0);
    if (quickProgress >= 0.998) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: ListenableBuilder(
        listenable: _mergedListenables,
        builder: (context, _) {
          final cutout = DisplayCutoutService.instance.resolveForContext(
            context,
            viewportKey: widget.viewportKey,
          );
          final geom = ProfileAvatarMetaballGeometry.compute(
            scrollOffset: widget.scrollOffset,
            screenWidth: widget.screenWidth,
            statusBarHeight: widget.statusBarHeight,
            topOffset: widget.topOffset,
            cutout: cutout,
          );

          if (geom.progress >= 0.998) {
            return const SizedBox.shrink();
          }

          final disableAnimations =
              MediaQuery.maybeDisableAnimationsOf(context) ?? false;
          final allowGpuMetaball =
              PowerSavingProvider.instance.allowBlur && !disableAnimations;

          final effectiveAvatarKey = widget.avatarKey ?? _internalAvatarKey;
          final dec = widget.decoration;
          final hasActiveDecoration = dec != null && dec.id != 'none';

          final coreAvatar = ExpandableAvatar(
            key: effectiveAvatarKey,
            pageController: widget.pageController,
            initialPage: widget.initialPage,
            avatarUrls: widget.avatarUrls,
            avatarFile: widget.avatarFile,
            expandFactor: 0.0,
            overExpandProgress: 0.0,
            bottomCollapseOverlap: 0.0,
            tintColor: widget.tintColor,
            backgroundColor: widget.backgroundColor,
            displayName: widget.displayName,
            decoration: dec,
            showDecoration: false,
            chatAvatarHeroTag: widget.chatAvatarHeroTag,
            onTap: widget.onTap,
            onVerticalDragStart: widget.onVerticalDragStart,
            onVerticalDragUpdate: widget.onVerticalDragUpdate,
            onVerticalDragEnd: widget.onVerticalDragEnd,
            onPageChanged: widget.onPageChanged,
          );

          const double baseD = ProfileAvatarMetaballGeometry.baseAvatarDiameter;
          const double outerFrameD = baseD *
              ProfileAvatarMetaballGeometry.decorationOuterMultiplier;

          // Idle fast-path (p <= 0.002): zero ImageFiltered / ColorFiltered / Transform overhead.
          if (geom.progress <= 0.002) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: geom.startCenter.dx - baseD * 0.5,
                  top: geom.startCenter.dy - baseD * 0.5,
                  width: baseD,
                  height: baseD,
                  child: coreAvatar,
                ),
                if (hasActiveDecoration)
                  Positioned(
                    left: geom.startCenter.dx - outerFrameD * 0.5,
                    top: geom.startCenter.dy - outerFrameD * 0.5,
                    width: outerFrameD,
                    height: outerFrameD,
                    child: IgnorePointer(
                      child: AvatarDecorationFrame(
                        key: _decorationCompanionKey,
                        decoration: dec,
                        avatarDiameter: baseD,
                        opacity: 1.0,
                        animate: true,
                        child: const SizedBox(width: baseD, height: baseD),
                      ),
                    ),
                  ),
              ],
            );
          }

          // Low-power / reduced-motion path: smooth Bezier translation + scale + fade without GPU blur passes.
          if (!allowGpuMetaball) {
            final simpleFade =
                (1.0 - ((geom.progress - 0.15) / 0.80).clamp(0.0, 1.0))
                    .clamp(0.0, 1.0);
            final avatarBoxLeft = geom.avatarCenter.dx - baseD * 0.5;
            final avatarBoxTop = geom.avatarCenter.dy - baseD * 0.5;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                if (simpleFade > 0.002)
                  Positioned(
                    left: avatarBoxLeft,
                    top: avatarBoxTop,
                    width: baseD,
                    height: baseD,
                    child: IgnorePointer(
                      ignoring: widget.scrollOffset > 80.0,
                      child: Opacity(
                        opacity: simpleFade,
                        child: Transform.scale(
                          scale: geom.avatarScale,
                          alignment: Alignment.center,
                          child: coreAvatar,
                        ),
                      ),
                    ),
                  ),
                if (hasActiveDecoration &&
                    geom.frameMounted &&
                    geom.frameOpacity > 0.002)
                  Positioned(
                    left: geom.avatarCenter.dx - outerFrameD * 0.5,
                    top: geom.avatarCenter.dy - outerFrameD * 0.5,
                    width: outerFrameD,
                    height: outerFrameD,
                    child: IgnorePointer(
                      child: Transform.scale(
                        scale: geom.avatarScale * geom.frameContractFactor,
                        alignment: Alignment.center,
                        child: AvatarDecorationFrame(
                          key: _decorationCompanionKey,
                          decoration: dec,
                          avatarDiameter: baseD,
                          opacity: geom.frameOpacity,
                          animate: false,
                          child: const SizedBox(width: baseD, height: baseD),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }

          // Full GPU liquid metaball path (0.002 < p < 0.998).
          final children = <Widget>[];

          // Sublayer 1: Static-origin black scalar field (cutout + opposing beaks + droplet) -> Blur -> Alpha threshold.
          if (geom.isScalarFieldActive) {
            children.add(_buildScalarFieldSublayer(cutout, geom));
          }

          // Sublayer 2: Single ExpandableAvatar instance -> Scale -> Gentle blur -> Late cutout-absorption darken -> Top clip.
          if (geom.avatarAlpha > 0.002) {
            final avatarBoxLeft = geom.avatarCenter.dx - baseD * 0.5;
            final avatarBoxTop = geom.avatarCenter.dy - baseD * 0.5;

            Widget avatarNode = Transform.scale(
              scale: geom.avatarScale,
              alignment: Alignment.center,
              child: coreAvatar,
            );

            if (geom.avatarBlurSigma > 0.05) {
              avatarNode = ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: geom.avatarBlurSigma,
                  sigmaY: geom.avatarBlurSigma,
                  tileMode: TileMode.decal,
                ),
                child: avatarNode,
              );
            }

            if (geom.avatarRgbScale < 0.999 || geom.avatarAlpha < 0.999) {
              avatarNode = ColorFiltered(
                colorFilter: _buildDarkenAndFadeMatrix(
                  geom.avatarRgbScale,
                  geom.avatarAlpha,
                ),
                child: avatarNode,
              );
            }

            final scaledTopY =
                geom.avatarCenter.dy - (baseD * 0.5) * geom.avatarScale;
            if (scaledTopY - geom.avatarBlurSigma * 2.5 <
                geom.cutoutClipTopY) {
              avatarNode = ClipRect(
                clipper: _LocalTopEdgeClipper(
                  minLocalY: geom.cutoutClipTopY - avatarBoxTop,
                  overhang: 24.0,
                ),
                child: avatarNode,
              );
            }

            children.add(
              Positioned(
                left: avatarBoxLeft,
                top: avatarBoxTop,
                width: baseD,
                height: baseD,
                child: IgnorePointer(
                  ignoring: widget.scrollOffset > 80.0,
                  child: avatarNode,
                ),
              ),
            );
          }

          // Sublayer 3: Unclipped custom avatar decoration frame contracting 1.0 -> 0.81 into the droplet core.
          if (hasActiveDecoration &&
              geom.frameMounted &&
              geom.frameOpacity > 0.002) {
            children.add(
              Positioned(
                left: geom.avatarCenter.dx - outerFrameD * 0.5,
                top: geom.avatarCenter.dy - outerFrameD * 0.5,
                width: outerFrameD,
                height: outerFrameD,
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: geom.avatarScale * geom.frameContractFactor,
                    alignment: Alignment.center,
                    child: AvatarDecorationFrame(
                      key: _decorationCompanionKey,
                      decoration: dec,
                      avatarDiameter: baseD,
                      opacity: geom.frameOpacity,
                      animate: geom.frameShouldAnimate,
                      child: const SizedBox(width: baseD, height: baseD),
                    ),
                  ),
                ),
              ),
            );
          }

          return Stack(
            clipBehavior: Clip.none,
            children: children,
          );
        },
      ),
    );
  }

  Widget _buildScalarFieldSublayer(
    DisplayCutoutSpec cutout,
    ProfileAvatarMetaballGeometry geom,
  ) {
    // Use a constant-origin top viewport band so the offscreen blur/color-matrix
    // texture never changes its origin or subpixel alignment during scroll.
    final bandWidth = math.max(1.0, widget.screenWidth);
    final bandVisibleHeight = math.max(widget.topOffset + 135.0, 220.0);
    final totalHeight = bandVisibleHeight + _kStaticTopBufferPad;

    Widget fieldWidget = ColorFiltered(
      colorFilter: _kMetaballThresholdColorFilter,
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: geom.scalarBlurSigma,
          sigmaY: geom.scalarBlurSigma,
          tileMode: TileMode.decal,
        ),
        child: CustomPaint(
          size: Size(bandWidth, totalHeight),
          painter: _MetaballScalarFieldPainter(
            topBufferPad: _kStaticTopBufferPad,
            screenWidth: bandWidth,
            cutout: cutout,
            geometry: geom,
          ),
        ),
      ),
    );

    if (geom.scalarFieldOpacity < 0.999) {
      fieldWidget = Opacity(
        opacity: geom.scalarFieldOpacity.clamp(0.0, 1.0),
        child: fieldWidget,
      );
    }

    fieldWidget = ClipRect(
      clipper: _LocalTopEdgeClipper(
        minLocalY: _kStaticTopBufferPad + geom.cutoutClipTopY,
        overhang: 0.0,
      ),
      child: fieldWidget,
    );

    return Positioned(
      left: 0.0,
      top: -_kStaticTopBufferPad,
      width: bandWidth,
      height: totalHeight,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: fieldWidget,
        ),
      ),
    );
  }
}

class _LocalTopEdgeClipper extends CustomClipper<Rect> {
  final double minLocalY;
  final double overhang;

  const _LocalTopEdgeClipper({
    required this.minLocalY,
    required this.overhang,
  });

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(
      -overhang,
      minLocalY,
      size.width + overhang,
      size.height + overhang,
    );
  }

  @override
  bool shouldReclip(covariant _LocalTopEdgeClipper oldClipper) {
    return (oldClipper.minLocalY - minLocalY).abs() > 0.05 ||
        oldClipper.overhang != overhang;
  }
}

class _MetaballScalarFieldPainter extends CustomPainter {
  final double topBufferPad;
  final double screenWidth;
  final DisplayCutoutSpec cutout;
  final ProfileAvatarMetaballGeometry geometry;

  const _MetaballScalarFieldPainter({
    required this.topBufferPad,
    required this.screenWidth,
    required this.cutout,
    required this.geometry,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final blackPaint = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.save();
    canvas.translate(0.0, topBufferPad);

    final avatarCenter = geometry.avatarCenter;
    final avatarR = geometry.avatarDiameter * 0.5;
    final u = geometry.suctionDirection;
    final n = Offset(-u.dy, u.dx);

    // Bell-shaped tension weight: ramps up only within 20dp of contact and
    // retracts smoothly back to 0 once the droplet passes inside the cutout.
    final approach = ((20.0 - geometry.edgeGapDp) / 18.0).clamp(0.0, 1.0);
    final retract = ((geometry.edgeGapDp + 16.0) / 15.0).clamp(0.0, 1.0);
    final bridgeWeight = Curves.easeOutQuad.transform(approach) *
        Curves.easeInOut.transform(retract);
    final cutoutBeakReach = 7.0 * bridgeWeight;
    final avatarBeakReach = 5.0 * bridgeWeight;

    // 1. Draw the physical cutout anchor strictly inside hardware bounds
    // (slightly deflated so zero black halo ever appears around the real camera,
    // and its top/side edges stay 100% stationary).
    Offset anchorSurfacePoint;
    double anchorBeakHalfWidth;

    if (cutout.hasCutout) {
      final bounds = cutout.bounds;
      final rMin = math.min(bounds.width, bounds.height) * 0.5;
      final deflate = rMin > 4.0 ? 0.6 : 0.0;

      final poly = cutout.polygonDp;
      if (poly != null && poly.length >= 6 && !cutout.isOval) {
        final path = Path()..moveTo(poly.first.dx, poly.first.dy);
        for (int i = 1; i < poly.length; i++) {
          path.lineTo(poly[i].dx, poly[i].dy);
        }
        path.close();
        canvas.drawPath(path, blackPaint);
      } else if (cutout.kind == CutoutAnchorKind.topNotch &&
          bounds.top <= 1.0) {
        final notchSeed = Rect.fromLTRB(
          bounds.left + deflate,
          -16.0,
          bounds.right - deflate,
          bounds.bottom - deflate,
        );
        final radius = math.max(0.0, cutout.cornerRadius - deflate);
        canvas.drawRRect(
          RRect.fromRectAndRadius(notchSeed, Radius.circular(radius)),
          blackPaint,
        );
      } else {
        final seedBounds = bounds.deflate(deflate);
        final radius = (cutout.cornerRadius - deflate).clamp(
          0.0,
          math.min(seedBounds.width, seedBounds.height) * 0.5,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(seedBounds, Radius.circular(radius)),
          blackPaint,
        );
      }

      if (cutout.kind == CutoutAnchorKind.topNotch) {
        anchorSurfacePoint = Offset(
          geometry.anchorNeckOrigin.dx,
          bounds.bottom - deflate,
        );
        anchorBeakHalfWidth = math.min(bounds.width * 0.22, 4.5);
      } else {
        final a = math.max(1.0, bounds.width * 0.5 - deflate);
        final b = math.max(1.0, bounds.height * 0.5 - deflate);
        final denom = math.sqrt(
          (b * u.dx) * (b * u.dx) + (a * u.dy) * (a * u.dy),
        );
        final supportR = denom > 0.001 ? (a * b / denom) : b;
        anchorSurfacePoint = bounds.center - u * supportR;
        anchorBeakHalfWidth = math.min(rMin * 0.42, 3.8);
      }
    } else {
      final barRect = Rect.fromLTWH(
        -36.0,
        -ProfileAvatarMetaballGeometry.blackKingBarHeight,
        screenWidth + 72.0,
        ProfileAvatarMetaballGeometry.blackKingBarHeight - 0.5,
      );
      canvas.drawRect(barRect, blackPaint);
      anchorSurfacePoint = Offset(avatarCenter.dx, -0.5);
      anchorBeakHalfWidth = 5.0;
    }

    // 2. Draw the avatar black droplet seed strictly inside the photo circle
    // (-1.2dp) so bright avatars never show a dark rim before absorption.
    final seedAvatarR = math.max(2.5, avatarR - 1.2);
    canvas.drawCircle(avatarCenter, seedAvatarR, blackPaint);

    // 3. Draw narrow opposing tension beaks strictly along unit vector u.
    if (bridgeWeight > 0.02) {
      final avatarChordCenter = avatarCenter + u * (seedAvatarR * 0.68);
      final avatarChordHalfW = seedAvatarR * 0.62;
      final avatarTip = avatarCenter + u * (seedAvatarR + avatarBeakReach);

      final avatarBeak = Path()
        ..moveTo(
          avatarChordCenter.dx - n.dx * avatarChordHalfW,
          avatarChordCenter.dy - n.dy * avatarChordHalfW,
        )
        ..lineTo(avatarTip.dx, avatarTip.dy)
        ..lineTo(
          avatarChordCenter.dx + n.dx * avatarChordHalfW,
          avatarChordCenter.dy + n.dy * avatarChordHalfW,
        )
        ..close();
      canvas.drawPath(avatarBeak, blackPaint);

      final anchorBaseCenter = anchorSurfacePoint + u * 3.0;
      final anchorTip = anchorSurfacePoint - u * cutoutBeakReach;
      final anchorBeak = Path()
        ..moveTo(
          anchorBaseCenter.dx - n.dx * anchorBeakHalfWidth,
          anchorBaseCenter.dy - n.dy * anchorBeakHalfWidth,
        )
        ..lineTo(anchorTip.dx, anchorTip.dy)
        ..lineTo(
          anchorBaseCenter.dx + n.dx * anchorBeakHalfWidth,
          anchorBaseCenter.dy + n.dy * anchorBeakHalfWidth,
        )
        ..close();
      canvas.drawPath(anchorBeak, blackPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MetaballScalarFieldPainter oldDelegate) {
    return oldDelegate.topBufferPad != topBufferPad ||
        oldDelegate.screenWidth != screenWidth ||
        oldDelegate.cutout != cutout ||
        (oldDelegate.geometry.progress - geometry.progress).abs() > 0.0005 ||
        oldDelegate.geometry.avatarCenter != geometry.avatarCenter ||
        (oldDelegate.geometry.avatarDiameter - geometry.avatarDiameter).abs() >
            0.05;
  }
}
