import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../widgets/tiling/tile_viewport_scope.dart';

/// Physical shape category of the top display cutout used as a metaball anchor.
enum CutoutAnchorKind {
  /// No physical cutout in the active viewport (or landscape / split-screen lower tile).
  /// Avatar collapses upward into the top edge (`BLACK_KING_BAR`).
  none,

  /// Circular or unified dual-sensor stadium punch-hole (centered, left, or right).
  punchHole,

  /// iOS Dynamic Island floating stadium pill (`top >= 11pt`).
  dynamicIsland,

  /// Edge-attached top notch (classic iPhone notch, wide Android notch, or waterdrop).
  topNotch,
}

/// Horizontal placement of the top cutout across the screen width.
enum CutoutHorizontalGravity {
  left,
  center,
  right,
}

/// Normalized logical-`dp` geometry of the top display cutout.
@immutable
class DisplayCutoutSpec {
  final CutoutAnchorKind kind;
  final CutoutHorizontalGravity gravity;
  final Rect bounds;
  final double cornerRadius;
  final bool isOval;
  final List<Offset>? polygonDp;

  const DisplayCutoutSpec({
    required this.kind,
    required this.gravity,
    required this.bounds,
    required this.cornerRadius,
    this.isOval = false,
    this.polygonDp,
  });

  static const DisplayCutoutSpec none = DisplayCutoutSpec(
    kind: CutoutAnchorKind.none,
    gravity: CutoutHorizontalGravity.center,
    bounds: Rect.zero,
    cornerRadius: 0.0,
    isOval: false,
  );

  bool get hasCutout =>
      kind != CutoutAnchorKind.none && bounds.width > 0.0 && bounds.height > 0.0;

  bool get isCorner =>
      hasCutout && gravity != CutoutHorizontalGravity.center;

  DisplayCutoutSpec shiftX(double dx) {
    if (dx == 0.0 || !hasCutout) return this;
    final delta = Offset(dx, 0.0);
    return DisplayCutoutSpec(
      kind: kind,
      gravity: gravity,
      bounds: bounds.shift(delta),
      cornerRadius: cornerRadius,
      isOval: isOval,
      polygonDp: polygonDp?.map((pt) => pt + delta).toList(growable: false),
    );
  }

  DisplayCutoutSpec reclassifyGravityForWidth(double viewportWidth) {
    if (!hasCutout || viewportWidth <= 0.0) return this;
    final cx = bounds.center.dx;
    final halfW = viewportWidth * 0.5;
    final nextGravity = (cx - halfW).abs() <= 12.0
        ? CutoutHorizontalGravity.center
        : (cx < halfW
            ? CutoutHorizontalGravity.left
            : CutoutHorizontalGravity.right);
    if (nextGravity == gravity) return this;
    return DisplayCutoutSpec(
      kind: kind,
      gravity: nextGravity,
      bounds: bounds,
      cornerRadius: cornerRadius,
      isOval: isOval,
      polygonDp: polygonDp,
    );
  }

  factory DisplayCutoutSpec.fromChannelMap(
    Map<Object?, Object?>? raw, {
    required double windowWidth,
  }) {
    if (raw == null || raw['hasCutout'] != true) {
      return DisplayCutoutSpec.none;
    }

    final refWidth = (raw['referenceWidthDp'] as num?)?.toDouble();
    final coordScale = (refWidth != null &&
            refWidth > 0.0 &&
            windowWidth > 0.0 &&
            (refWidth - windowWidth).abs() > 0.25)
        ? (windowWidth / refWidth)
        : 1.0;

    final left = ((raw['left'] as num?)?.toDouble() ?? 0.0) * coordScale;
    var top = ((raw['top'] as num?)?.toDouble() ?? 0.0) * coordScale;
    final width = ((raw['width'] as num?)?.toDouble() ?? 0.0) * coordScale;
    var height = ((raw['height'] as num?)?.toDouble() ?? 0.0) * coordScale;
    if (width <= 0.0 || height <= 0.0) {
      return DisplayCutoutSpec.none;
    }

    final kindRaw = raw['kind'] as String? ?? '';
    final CutoutAnchorKind kind = switch (kindRaw) {
      'dynamicIsland' => CutoutAnchorKind.dynamicIsland,
      'topNotch' => CutoutAnchorKind.topNotch,
      'punchHole' => CutoutAnchorKind.punchHole,
      _ => CutoutAnchorKind.none,
    };
    if (kind == CutoutAnchorKind.none) {
      return DisplayCutoutSpec.none;
    }

    final rawIsOval = (raw['isOval'] as bool?) ?? (width > height * 1.15);
    if (kind == CutoutAnchorKind.punchHole &&
        !rawIsOval &&
        width <= 42.0 &&
        top <= 3.0 &&
        height > width * 1.04) {
      top = (top + height) - width;
      height = width;
    }

    final bounds = Rect.fromLTWH(left, top, width, height);
    final gravityRaw = raw['gravity'] as String?;
    final CutoutHorizontalGravity gravity = switch (gravityRaw) {
      'left' => CutoutHorizontalGravity.left,
      'right' => CutoutHorizontalGravity.right,
      'center' => CutoutHorizontalGravity.center,
      _ => _inferGravity(bounds.center.dx, windowWidth),
    };

    final isOval = rawIsOval;
    final defaultRadius = (kind == CutoutAnchorKind.punchHole ||
            kind == CutoutAnchorKind.dynamicIsland ||
            isOval)
        ? math.min(width, height) * 0.5
        : math.min(width * 0.25, height * 0.55);
    final rawCornerRadius = (raw['cornerRadius'] as num?)?.toDouble();
    final cornerRadius =
        (rawCornerRadius != null ? rawCornerRadius * coordScale : defaultRadius)
            .clamp(0.0, math.max(width, height) * 0.5);

    List<Offset>? polygon;
    final rawPoly = raw['polygonDp'];
    if (rawPoly is List && rawPoly.length >= 12 && rawPoly.length.isEven) {
      final pts = <Offset>[];
      for (int i = 0; i + 1 < rawPoly.length; i += 2) {
        final px = (rawPoly[i] as num?)?.toDouble();
        final py = (rawPoly[i + 1] as num?)?.toDouble();
        if (px != null && py != null) {
          pts.add(Offset(px * coordScale, py * coordScale));
        }
      }
      if (pts.length >= 6) {
        polygon = List<Offset>.unmodifiable(pts);
      }
    }

    return DisplayCutoutSpec(
      kind: kind,
      gravity: gravity,
      bounds: bounds,
      cornerRadius: cornerRadius,
      isOval: isOval,
      polygonDp: polygon,
    );
  }

  static CutoutHorizontalGravity _inferGravity(
    double centerX,
    double windowWidth,
  ) {
    if (windowWidth <= 0.0) return CutoutHorizontalGravity.center;
    final halfW = windowWidth * 0.5;
    if ((centerX - halfW).abs() <= 12.0) {
      return CutoutHorizontalGravity.center;
    }
    return centerX < halfW
        ? CutoutHorizontalGravity.left
        : CutoutHorizontalGravity.right;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DisplayCutoutSpec &&
        other.kind == kind &&
        other.gravity == gravity &&
        other.bounds == bounds &&
        other.cornerRadius == cornerRadius &&
        other.isOval == isOval &&
        listEquals(other.polygonDp, polygonDp);
  }

  @override
  int get hashCode => Object.hash(
        kind,
        gravity,
        bounds,
        cornerRadius,
        isOval,
        polygonDp == null ? null : Object.hashAll(polygonDp!),
      );
}

@immutable
class _CutoutCacheKey {
  final int widthTenths;
  final int heightTenths;
  final int topPaddingTenths;

  const _CutoutCacheKey({
    required this.widthTenths,
    required this.heightTenths,
    required this.topPaddingTenths,
  });

  factory _CutoutCacheKey.fromMetrics(Size windowSize, double topPadding) {
    return _CutoutCacheKey(
      widthTenths: (windowSize.width * 10.0).round(),
      heightTenths: (windowSize.height * 10.0).round(),
      topPaddingTenths: (topPadding * 10.0).round(),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _CutoutCacheKey &&
        other.widthTenths == widthTenths &&
        other.heightTenths == heightTenths &&
        other.topPaddingTenths == topPaddingTenths;
  }

  @override
  int get hashCode =>
      Object.hash(widthTenths, heightTenths, topPaddingTenths);
}

class _MutableRectCluster {
  Rect bounds;
  int count;

  _MutableRectCluster(this.bounds) : count = 1;
}

/// Resolves and caches physical camera cutout / Dynamic Island / notch metrics
/// in logical `dp`, unifying dual-camera sensors into a single stadium oval.
class DisplayCutoutService extends ChangeNotifier {
  DisplayCutoutService._();

  static final DisplayCutoutService instance = DisplayCutoutService._();

  static const MethodChannel _channel =
      MethodChannel('app.theaver.messenger/display_cutout');

  /// Maximum horizontal gap (`dp`) between adjacent top camera cutouts
  /// to unify them into a single stadium oval.
  static const double kDualSensorMergeGapDp = 28.0;

  /// Maximum `top` coordinate (`dp`) considered part of the top bezel/status-bar zone.
  static const double kMaxTopZoneDp = 56.0;

  @visibleForTesting
  DisplayCutoutSpec? debugOverrideSpec;

  _CutoutCacheKey? _cachedKey;
  DisplayCutoutSpec? _cachedNativeSpec;
  _CutoutCacheKey? _inFlightKey;

  @visibleForTesting
  void resetForTesting() {
    debugOverrideSpec = null;
    _cachedKey = null;
    _cachedNativeSpec = null;
    _inFlightKey = null;
  }

  /// Synchronous Frame-0 fallback built from Flutter's [ui.DisplayFeature] list.
  /// Clusters dual front cameras (`gap <= 28dp`) into a single stadium oval.
  static DisplayCutoutSpec fromDisplayFeatures(
    List<ui.DisplayFeature> features,
    Size windowSize, {
    bool isIOSPlatform = false,
  }) {
    if (windowSize.width <= 0.0 ||
        windowSize.height <= 0.0 ||
        windowSize.width > windowSize.height ||
        features.isEmpty) {
      return DisplayCutoutSpec.none;
    }

    final topRects = <Rect>[];
    for (final f in features) {
      if (f.type == ui.DisplayFeatureType.cutout &&
          f.bounds.width > 0.0 &&
          f.bounds.height > 0.0 &&
          f.bounds.top < kMaxTopZoneDp) {
        var r = f.bounds;
        if (!isIOSPlatform &&
            r.width <= 42.0 &&
            r.top <= 3.0 &&
            r.height > r.width * 1.04) {
          r = Rect.fromLTWH(r.left, r.bottom - r.width, r.width, r.width);
        }
        topRects.add(r);
      }
    }
    if (topRects.isEmpty) {
      return DisplayCutoutSpec.none;
    }

    topRects.sort((a, b) => a.left.compareTo(b.left));
    final clusters = <_MutableRectCluster>[];
    for (final r in topRects) {
      final last = clusters.isNotEmpty ? clusters.last : null;
      if (last != null && r.left - last.bounds.right <= kDualSensorMergeGapDp) {
        last.bounds = last.bounds.expandToInclude(r);
        last.count += 1;
      } else {
        clusters.add(_MutableRectCluster(r));
      }
    }

    final halfW = windowSize.width * 0.5;
    _MutableRectCluster chosen = clusters.first;
    double bestDist = (chosen.bounds.center.dx - halfW).abs();
    for (int i = 1; i < clusters.length; i++) {
      final d = (clusters[i].bounds.center.dx - halfW).abs();
      if (d < bestDist) {
        bestDist = d;
        chosen = clusters[i];
      }
    }

    final bounds = chosen.bounds;
    final gravity =
        DisplayCutoutSpec._inferGravity(bounds.center.dx, windowSize.width);
    final isOval = chosen.count > 1 || bounds.width > bounds.height * 1.15;

    final CutoutAnchorKind kind;
    if (gravity != CutoutHorizontalGravity.center) {
      kind = CutoutAnchorKind.punchHole;
    } else if (isIOSPlatform && bounds.top >= 8.0) {
      kind = CutoutAnchorKind.dynamicIsland;
    } else if (bounds.top >= 2.5 || bounds.width <= 72.0) {
      kind = CutoutAnchorKind.punchHole;
    } else {
      kind = CutoutAnchorKind.topNotch;
    }

    final cornerRadius = (kind == CutoutAnchorKind.punchHole ||
            kind == CutoutAnchorKind.dynamicIsland ||
            isOval)
        ? math.min(bounds.width, bounds.height) * 0.5
        : math.min(bounds.width * 0.25, bounds.height * 0.55);

    return DisplayCutoutSpec(
      kind: kind,
      gravity: gravity,
      bounds: bounds,
      cornerRadius: cornerRadius,
      isOval: isOval,
    );
  }

  /// Triggers an asynchronous native cutout query on Android / iOS if the
  /// window metrics changed since the last cached lookup.
  void ensureQueried({
    required Size windowSize,
    required double topViewPadding,
  }) {
    if (debugOverrideSpec != null) return;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    if (windowSize.width <= 0.0 || windowSize.height <= 0.0) return;

    final key = _CutoutCacheKey.fromMetrics(windowSize, topViewPadding);
    if (_cachedKey == key || _inFlightKey == key) return;

    _inFlightKey = key;
    final widthSnapshot = windowSize.width;
    unawaited(_queryNative(key, widthSnapshot));
  }

  Future<void> _queryNative(_CutoutCacheKey key, double windowWidth) async {
    try {
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('getDisplayCutout');
      final parsed = DisplayCutoutSpec.fromChannelMap(
        raw,
        windowWidth: windowWidth,
      );
      final changed = _cachedKey != key || _cachedNativeSpec != parsed;
      _cachedKey = key;
      _cachedNativeSpec = parsed;
      if (_inFlightKey == key) {
        _inFlightKey = null;
      }
      if (changed) {
        notifyListeners();
      }
    } on MissingPluginException {
      _cachedKey = key;
      _cachedNativeSpec = null;
      if (_inFlightKey == key) {
        _inFlightKey = null;
      }
    } catch (_) {
      if (_inFlightKey == key) {
        _inFlightKey = null;
      }
    }
  }

  /// Resolves the effective [DisplayCutoutSpec] in the local coordinate space
  /// of the profile viewport (`0 .. viewportWidth`), accounting for portrait vs
  /// landscape orientation and split-screen / tiling viewports.
  DisplayCutoutSpec resolveForContext(
    BuildContext context, {
    GlobalKey? viewportKey,
  }) {
    if (TileViewportScope.hasTopNeighborOf(context)) {
      return DisplayCutoutSpec.none;
    }

    final windowSize = MediaQuery.sizeOf(context);
    final viewportSize = TileViewportScope.sizeOf(context);
    if (viewportSize.width <= 0.0 ||
        viewportSize.height <= 0.0 ||
        viewportSize.width > viewportSize.height ||
        windowSize.width > windowSize.height) {
      return DisplayCutoutSpec.none;
    }

    DisplayCutoutSpec baseSpec;
    final override = debugOverrideSpec;
    if (override != null) {
      baseSpec = override;
    } else {
      final viewPaddingTop = MediaQuery.viewPaddingOf(context).top;
      final key = _CutoutCacheKey.fromMetrics(windowSize, viewPaddingTop);
      ensureQueried(windowSize: windowSize, topViewPadding: viewPaddingTop);

      final nativeSpec = (_cachedKey == key) ? _cachedNativeSpec : null;
      if (nativeSpec != null) {
        baseSpec = nativeSpec;
      } else {
        final isIOS = !kIsWeb && Platform.isIOS;
        baseSpec = fromDisplayFeatures(
          MediaQuery.displayFeaturesOf(context),
          windowSize,
          isIOSPlatform: isIOS,
        );
      }
    }

    if (!baseSpec.hasCutout) {
      return DisplayCutoutSpec.none;
    }

    // Account for multi-window / tiling offset if the profile stack is narrower
    // than the full window or shifted below the physical top bezel.
    final renderObj = viewportKey?.currentContext?.findRenderObject();
    if (renderObj is RenderBox && renderObj.attached && renderObj.hasSize) {
      final globalTopLeft = renderObj.localToGlobal(Offset.zero);
      if (globalTopLeft.dy > 2.0) {
        return DisplayCutoutSpec.none;
      }
      if ((viewportSize.width - windowSize.width).abs() > 2.0 ||
          globalTopLeft.dx.abs() > 1.0) {
        final shifted = baseSpec
            .shiftX(-globalTopLeft.dx)
            .reclassifyGravityForWidth(viewportSize.width);
        if (shifted.bounds.left < 2.0 ||
            shifted.bounds.right > viewportSize.width - 2.0) {
          return DisplayCutoutSpec.none;
        }
        return shifted;
      }
    } else if ((viewportSize.width - windowSize.width).abs() > 2.0) {
      // Before first layout of a split tile, avoid guessing horizontal offset.
      return DisplayCutoutSpec.none;
    }

    return baseSpec;
  }
}
