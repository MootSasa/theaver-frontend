import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

/// Wraps a multi-window tile in a repaint boundary that automatically freezes
/// the tile's layer subtree into a single GPU texture ([ui.Image]) when the
/// tile is stationary (no descendant layer updates and no pointer contact).
///
/// Why this matters on Impeller:
/// `RepaintBoundary` (`OffsetLayer`) retains its display list across frames via
/// `SceneBuilder.addRetained`, but Impeller does not raster-cache an
/// `OffsetLayer` that contains `BackdropFilterLayer`s. Consequently, every
/// `BackdropFilter` inside stationary tiles (`MainScreen`, inactive chat tile)
/// would otherwise re-execute its blur + shader pass on the GPU on every single
/// frame while the user scrolls another tile.
///
/// When frozen:
/// - All `BackdropFilter`s inside the stationary tile are pre-composited into
///   one tile-local [ui.Image].
/// - `_TileCacheOffsetLayer`'s retained `ui.OffsetEngineLayer` contains only a
///   single `ui.Picture` drawing that [ui.Image] (`0` `BackdropFilter` passes).
/// - In `updateSubtreeNeedsAddToScene()`, a `< 2µs` layer-subtree signature
///   check runs before scene building:
///   - If nothing inside the tile changed, `_needsAddToScene` stays `false` and
///     Flutter calls `builder.addRetained(engineLayer!)` in `O(1)`.
///   - The instant any descendant `RenderObject` inside the tile paints (at any
///     depth, even inside nested `RepaintBoundary`s) or a pointer touches the
///     tile, the signature changes (or pointer listener fires), waking
///     `_TileCacheOffsetLayer` on that exact frame with zero frame latency.
class StaticTileCacheBoundary extends StatefulWidget {
  const StaticTileCacheBoundary({
    super.key,
    required this.enabled,
    required this.child,
    this.idleThreshold = const Duration(milliseconds: 750),
  });

  final bool enabled;
  final Widget child;
  final Duration idleThreshold;

  /// Isolates the enclosing tile's live compositing layer into a tile-bounded
  /// backdrop subpass while a full-tile [BackdropFilter] overlay (such as
  /// `MessageContextMenu` or `RoundVideoRecordingOverlay`) is mounted.
  ///
  /// Without this, when the tile is in live mode (`_renderLive`), its
  /// [OffsetLayer] composites directly into the root window scene at
  /// `(offset.dx, offset.dy)`, so a full-tile [BackdropFilter] samples across
  /// the 8px transparent `TileResizeDivider` and adjacent tiles within
  /// `3 * sigma` of the left and right tile borders.
  static VoidCallback acquireLiveBackdropIsolation(BuildContext context) {
    final renderBoundary = context
        .findAncestorRenderObjectOfType<_RenderStaticTileCacheBoundary>();
    if (renderBoundary == null) {
      return () {};
    }
    renderBoundary.acquireLiveBackdropIsolation();
    bool released = false;
    return () {
      if (released) return;
      released = true;
      renderBoundary.releaseLiveBackdropIsolation();
    };
  }

  @override
  State<StaticTileCacheBoundary> createState() =>
      _StaticTileCacheBoundaryState();
}

class _StaticTileCacheBoundaryState extends State<StaticTileCacheBoundary> {
  int _activePointers = 0;

  void _onPointerDown(PointerDownEvent _) {
    _activePointers++;
    if (_activePointers == 1) {
      setState(() {});
    }
  }

  void _onPointerUpOrCancel(PointerEvent _) {
    if (_activePointers > 0) {
      _activePointers--;
      if (_activePointers == 0 && mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double dpr = View.maybeOf(context)?.devicePixelRatio ??
        MediaQuery.maybeDevicePixelRatioOf(context) ??
        1.0;
    final bool canCache = widget.enabled && _activePointers == 0;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUpOrCancel,
      onPointerCancel: _onPointerUpOrCancel,
      child: _StaticTileCacheRenderObjectWidget(
        cacheEnabled: canCache,
        devicePixelRatio: dpr,
        idleThreshold: widget.idleThreshold,
        child: widget.child,
      ),
    );
  }
}

class _StaticTileCacheRenderObjectWidget extends SingleChildRenderObjectWidget {
  const _StaticTileCacheRenderObjectWidget({
    required this.cacheEnabled,
    required this.devicePixelRatio,
    required this.idleThreshold,
    super.child,
  });

  final bool cacheEnabled;
  final double devicePixelRatio;
  final Duration idleThreshold;

  @override
  _RenderStaticTileCacheBoundary createRenderObject(BuildContext context) {
    return _RenderStaticTileCacheBoundary(
      cacheEnabled: cacheEnabled,
      devicePixelRatio: devicePixelRatio,
      idleThreshold: idleThreshold,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStaticTileCacheBoundary renderObject,
  ) {
    renderObject
      ..cacheEnabled = cacheEnabled
      ..devicePixelRatio = devicePixelRatio
      ..idleThreshold = idleThreshold;
  }
}

class _RenderStaticTileCacheBoundary extends RenderProxyBox
    implements LiquidGlassSubpassBoundary {
  _RenderStaticTileCacheBoundary({
    required bool cacheEnabled,
    required double devicePixelRatio,
    required this.idleThreshold,
  })  : _cacheEnabled = cacheEnabled,
        _devicePixelRatio = devicePixelRatio;

  bool _cacheEnabled;
  bool get cacheEnabled => _cacheEnabled;
  set cacheEnabled(bool value) {
    if (_cacheEnabled == value) return;
    _cacheEnabled = value;
    final tileLayer = layer as _TileCacheOffsetLayer?;
    if (!value) {
      tileLayer?.unfreezeImmediately();
      markNeedsPaint();
    } else {
      tileLayer?.scheduleIdleFreeze();
    }
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if ((_devicePixelRatio - value).abs() < 1e-4) return;
    _devicePixelRatio = value;
    (layer as _TileCacheOffsetLayer?)?.unfreezeImmediately();
    markNeedsPaint();
  }

  Duration idleThreshold;

  bool _isSubpassActive = false;
  int _liveBackdropIsolationCount = 0;

  bool get isLiveBackdropIsolated => _liveBackdropIsolationCount > 0;

  void acquireLiveBackdropIsolation() {
    _liveBackdropIsolationCount++;
    if (_liveBackdropIsolationCount == 1) {
      (layer as _TileCacheOffsetLayer?)?.onLiveBackdropIsolationChanged();
      requestVisualSceneUpdate();
    }
  }

  void releaseLiveBackdropIsolation() {
    if (_liveBackdropIsolationCount <= 0) return;
    _liveBackdropIsolationCount--;
    if (_liveBackdropIsolationCount == 0) {
      (layer as _TileCacheOffsetLayer?)?.onLiveBackdropIsolationChanged();
      requestVisualSceneUpdate();
    }
  }

  @override
  bool get isSubpassActive => _isSubpassActive;

  @override
  bool get isRepaintBoundary => true;

  @override
  OffsetLayer updateCompositedLayer({
    required covariant _TileCacheOffsetLayer? oldLayer,
  }) {
    final _TileCacheOffsetLayer result = oldLayer ?? _TileCacheOffsetLayer();
    result.boundary = this;
    return result;
  }

  /// Switches all descendant [LiquidGlassSubpassRepackable] render objects
  /// between tile-local coordinates (`active == true`) and window-global
  /// coordinates (`active == false`).
  void repackSubpassDependents(bool active) {
    if (_isSubpassActive == active) return;
    _isSubpassActive = active;
    void visit(RenderObject node) {
      if (node is LiquidGlassSubpassRepackable) {
        node.onSubpassChanged();
      }
      node.visitChildren(visit);
    }

    visitChildren(visit);
  }

  void requestVisualSceneUpdate() {
    if (!attached) return;
    owner?.requestVisualUpdate();
    SchedulerBinding.instance.scheduleFrame();
  }

  @override
  void performLayout() {
    final Size oldSize = hasSize ? size : Size.zero;
    super.performLayout();
    if (oldSize != size) {
      (layer as _TileCacheOffsetLayer?)?.unfreezeImmediately();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    (layer as _TileCacheOffsetLayer?)?.onBoundaryPainted();
    super.paint(context, offset);
  }

  @override
  void detach() {
    (layer as _TileCacheOffsetLayer?)?.disposeCache();
    super.detach();
  }
}

class _TileCacheOffsetLayer extends OffsetLayer {
  _RenderStaticTileCacheBoundary? boundary;

  ui.Image? _cachedImage;
  ui.Picture? _cachedPicture;
  int _lastSignature = 0;
  int _stableFrames = 0;
  bool _isFrozen = false;
  bool _freezeRequested = false;
  Timer? _idleTimer;

  /// Number of consecutive frames with an identical layer-subtree signature
  /// before an inactive tile automatically freezes while another tile is
  /// animating (must exceed the 500ms cursor blink plateau).
  static const int _kAutoFreezeStableFrames = 45;

  /// Ensures at most one tile captures its snapshot on any single frame so
  /// freezing multiple tiles never causes a combined frame spike.
  static Duration _lastCaptureFrameTimestamp = Duration.zero;

  static const ui.ColorFilter _kIdentityIsolationColorFilter =
      ui.ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  bool _wasLiveBackdropIsolated = false;
  ui.ClipRectEngineLayer? _isolationClipLayer;
  ui.ColorFilterEngineLayer? _isolationColorFilterLayer;

  void onLiveBackdropIsolationChanged() {
    if (_isFrozen || _cachedImage != null || _cachedPicture != null) {
      unfreezeImmediately();
    } else {
      _isolationClipLayer = null;
      _isolationColorFilterLayer = null;
      _clearSubtreeEngineLayers(this);
      markNeedsAddToScene();
      final b = boundary;
      if (b != null && b.attached && b.cacheEnabled && !b.isLiveBackdropIsolated) {
        scheduleIdleFreeze();
      }
    }
  }

  void onBoundaryPainted() {
    _stableFrames = 0;
    if (_isFrozen || _cachedImage != null || _cachedPicture != null) {
      unfreezeImmediately();
    } else {
      scheduleIdleFreeze();
    }
  }

  void unfreezeImmediately() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _freezeRequested = false;
    _stableFrames = 0;
    if (_isFrozen || _cachedImage != null || _cachedPicture != null) {
      _disposeCachedResources();
      _isolationClipLayer = null;
      _isolationColorFilterLayer = null;
      final b = boundary;
      final bool isolateBackdrop =
          b != null && b.attached && b.hasSize && b.isLiveBackdropIsolated;
      if (b != null && b.isSubpassActive != isolateBackdrop) {
        b.repackSubpassDependents(isolateBackdrop);
      }
      _clearSubtreeEngineLayers(this);
      markNeedsAddToScene();
    }
  }

  void scheduleIdleFreeze() {
    _idleTimer?.cancel();
    _idleTimer = null;
    final b = boundary;
    if (b == null || !b.attached || !b.cacheEnabled || b.isLiveBackdropIsolated) {
      return;
    }
    _idleTimer = Timer(b.idleThreshold, _onIdleTimerFired);
  }

  void _onIdleTimerFired() {
    _idleTimer = null;
    final b = boundary;
    if (b == null ||
        !b.attached ||
        !b.cacheEnabled ||
        b.isLiveBackdropIsolated ||
        !b.hasSize) {
      return;
    }
    if (_isFrozen) return;
    if (b.size.width < 1.0 || b.size.height < 1.0) return;
    if (_hasUncacheableLayer(this)) return;

    _freezeRequested = true;
    markNeedsAddToScene();
    b.requestVisualSceneUpdate();
  }

  @override
  void updateSubtreeNeedsAddToScene() {
    final b = boundary;
    if (b == null ||
        !b.attached ||
        !b.hasSize ||
        !b.cacheEnabled ||
        b.isLiveBackdropIsolated) {
      if (_isFrozen) {
        unfreezeImmediately();
      }
      super.updateSubtreeNeedsAddToScene();
      return;
    }

    final int sig = _computeSubtreeSignature(this);
    if (_isFrozen) {
      if (sig != _lastSignature || _hasUncacheableLayer(this)) {
        // A descendant layer inside this tile changed on this exact frame!
        // Unfreeze immediately so addToScene renders live layers.
        unfreezeImmediately();
        _lastSignature = sig;
        super.updateSubtreeNeedsAddToScene();
      }
      // Otherwise do NOT call super.updateSubtreeNeedsAddToScene():
      // child layers with alwaysNeedsAddToScene (like LensTransformTrackingLayer)
      // must not wake this frozen OffsetLayer while its subtree is unchanged.
      return;
    }

    if (sig != _lastSignature) {
      _lastSignature = sig;
      _stableFrames = 0;
      _freezeRequested = false;
      scheduleIdleFreeze();
    } else {
      _stableFrames++;
      if (_stableFrames >= _kAutoFreezeStableFrames &&
          !_hasUncacheableLayer(this)) {
        _freezeRequested = true;
      }
    }

    super.updateSubtreeNeedsAddToScene();
    if (_freezeRequested) {
      markNeedsAddToScene();
    }
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    final b = boundary;
    if (b == null ||
        !b.attached ||
        !b.hasSize ||
        !b.cacheEnabled ||
        b.isLiveBackdropIsolated) {
      _renderLive(builder, b);
      return;
    }

    if (_isFrozen && _cachedPicture != null && !_freezeRequested) {
      engineLayer = builder.pushOffset(
        offset.dx,
        offset.dy,
        oldLayer: engineLayer as ui.OffsetEngineLayer?,
      );
      builder.addPicture(Offset.zero, _cachedPicture!);
      builder.pop();
      return;
    }

    if (_freezeRequested && !_hasUncacheableLayer(this)) {
      final Duration frameTs =
          SchedulerBinding.instance.currentSystemFrameTimeStamp;
      if (frameTs != Duration.zero && frameTs == _lastCaptureFrameTimestamp) {
        // Another tile already captured on this frame; defer to next frame.
        _freezeRequested = false;
        _idleTimer?.cancel();
        _idleTimer = Timer(const Duration(milliseconds: 20), _onIdleTimerFired);
        _renderLive(builder, b);
        return;
      }

      _freezeRequested = false;
      final Size size = b.size;
      final double dpr = b.devicePixelRatio;
      if (_captureToCache(b, size, dpr)) {
        _lastCaptureFrameTimestamp = frameTs;
        _isFrozen = true;
        _idleTimer?.cancel();
        _idleTimer = null;
        _lastSignature = _computeSubtreeSignature(this);
        engineLayer = builder.pushOffset(
          offset.dx,
          offset.dy,
          oldLayer: engineLayer as ui.OffsetEngineLayer?,
        );
        builder.addPicture(Offset.zero, _cachedPicture!);
        builder.pop();
        return;
      }
    }

    _renderLive(builder, b);
  }

  void _renderLive(
    ui.SceneBuilder builder,
    _RenderStaticTileCacheBoundary? b,
  ) {
    final bool wasFrozen =
        _isFrozen || _cachedImage != null || _cachedPicture != null;
    _disposeCachedResources();
    final bool isolateBackdrop =
        b != null && b.attached && b.hasSize && b.isLiveBackdropIsolated;
    if (b != null && b.isSubpassActive != isolateBackdrop) {
      b.repackSubpassDependents(isolateBackdrop);
    }
    if (wasFrozen || _wasLiveBackdropIsolated != isolateBackdrop) {
      _wasLiveBackdropIsolated = isolateBackdrop;
      _isolationClipLayer = null;
      _isolationColorFilterLayer = null;
      _clearSubtreeEngineLayers(this);
    }
    if (isolateBackdrop) {
      engineLayer = builder.pushOffset(
        offset.dx,
        offset.dy,
        oldLayer: engineLayer as ui.OffsetEngineLayer?,
      );
      _isolationClipLayer = builder.pushClipRect(
        Offset.zero & b.size,
        oldLayer: _isolationClipLayer,
      );
      _isolationColorFilterLayer = builder.pushColorFilter(
        _kIdentityIsolationColorFilter,
        oldLayer: _isolationColorFilterLayer,
      );
      addChildrenToScene(builder);
      builder.pop();
      builder.pop();
      builder.pop();
      return;
    }
    super.addToScene(builder);
  }

  bool _captureToCache(
    _RenderStaticTileCacheBoundary b,
    Size size,
    double dpr,
  ) {
    final int pixelWidth = (size.width * dpr).round();
    final int pixelHeight = (size.height * dpr).round();
    if (pixelWidth <= 0 || pixelHeight <= 0) return false;

    ui.Scene? scene;
    try {
      // 1. Repack all descendant LiquidGlassLens & LiquidGlassBlender uniforms
      //    into tile-local space (0..size.width, 0..size.height).
      b.repackSubpassDependents(true);

      // 2. Ensure child layers do not try to addRetained from the main window's
      //    SceneBuilder into our offscreen capture SceneBuilder.
      _clearSubtreeEngineLayers(this);

      // 3. Build an offscreen scene of the tile's child layers at full DPR.
      final ui.SceneBuilder captureBuilder = ui.SceneBuilder();
      final Matrix4 scaleMatrix = Matrix4.diagonal3Values(dpr, dpr, 1.0);
      captureBuilder.pushTransform(scaleMatrix.storage);
      addChildrenToScene(captureBuilder);
      captureBuilder.pop();

      scene = captureBuilder.build();
      final ui.Image image = scene.toImageSync(pixelWidth, pixelHeight);

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      final Rect src = Rect.fromLTWH(
        0,
        0,
        pixelWidth.toDouble(),
        pixelHeight.toDouble(),
      );
      final Rect dst = Rect.fromLTWH(
        0,
        0,
        pixelWidth / dpr,
        pixelHeight / dpr,
      );
      canvas.drawImageRect(
        image,
        src,
        dst,
        ui.Paint()..filterQuality = ui.FilterQuality.low,
      );
      final ui.Picture picture = recorder.endRecording();

      _disposeCachedResources();
      _isolationClipLayer = null;
      _isolationColorFilterLayer = null;
      _cachedImage = image;
      _cachedPicture = picture;
      return true;
    } catch (_) {
      _isolationClipLayer = null;
      _isolationColorFilterLayer = null;
      b.repackSubpassDependents(false);
      _clearSubtreeEngineLayers(this);
      return false;
    } finally {
      scene?.dispose();
    }
  }

  static int _computeSubtreeSignature(ContainerLayer root) {
    int hash = 17;
    void visit(Layer layer) {
      hash = 0x1fffffff & (hash * 31 + identityHashCode(layer));
      if (layer is OffsetLayer) {
        final Offset o = layer.offset;
        hash = 0x1fffffff & (hash * 31 + (o.dx.hashCode ^ (o.dy.hashCode << 1)));
      }
      if (layer is PictureLayer) {
        hash = 0x1fffffff & (hash * 31 + identityHashCode(layer.picture));
      } else if (layer is LiquidGlassTrackedLayer) {
        hash = 0x1fffffff & (hash * 31 + layer.paintRevision);
      } else if (layer is BackdropFilterLayer) {
        hash = 0x1fffffff & (hash * 31 + layer.filter.hashCode);
      } else if (layer is TransformLayer) {
        final Matrix4? m = layer.transform;
        if (m != null) {
          final s = m.storage;
          hash = 0x1fffffff &
              (hash * 31 +
                  (s[0].hashCode ^
                      (s[5].hashCode << 1) ^
                      (s[12].hashCode << 2) ^
                      (s[13].hashCode << 3)));
        }
      } else if (layer is ClipRectLayer) {
        hash = 0x1fffffff & (hash * 31 + layer.clipRect.hashCode);
      } else if (layer is ClipRRectLayer) {
        hash = 0x1fffffff & (hash * 31 + layer.clipRRect.hashCode);
      } else if (layer is ClipPathLayer) {
        hash = 0x1fffffff & (hash * 31 + identityHashCode(layer.clipPath));
      } else if (layer is OpacityLayer) {
        hash = 0x1fffffff & (hash * 31 + (layer.alpha ?? 255));
      } else if (layer is ImageFilterLayer) {
        hash = 0x1fffffff & (hash * 31 + layer.imageFilter.hashCode);
      } else if (layer is ColorFilterLayer) {
        hash = 0x1fffffff & (hash * 31 + layer.colorFilter.hashCode);
      }
      if (layer is ContainerLayer) {
        Layer? child = layer.firstChild;
        while (child != null) {
          visit(child);
          child = child.nextSibling;
        }
      }
    }

    Layer? child = root.firstChild;
    while (child != null) {
      visit(child);
      child = child.nextSibling;
    }
    return hash;
  }

  static bool _hasUncacheableLayer(Layer root) {
    if (root is TextureLayer ||
        root is PlatformViewLayer ||
        root is FollowerLayer) {
      return true;
    }
    if (root is ContainerLayer) {
      Layer? child = root.firstChild;
      while (child != null) {
        if (_hasUncacheableLayer(child)) return true;
        child = child.nextSibling;
      }
    }
    return false;
  }

  static void _clearSubtreeEngineLayers(ContainerLayer root) {
    Layer? child = root.firstChild;
    while (child != null) {
      child.engineLayer = null;
      if (child is ContainerLayer) {
        _clearSubtreeEngineLayers(child);
      }
      child = child.nextSibling;
    }
  }

  void _disposeCachedResources() {
    _isFrozen = false;
    _cachedPicture?.dispose();
    _cachedPicture = null;
    _cachedImage?.dispose();
    _cachedImage = null;
  }

  void disposeCache() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _freezeRequested = false;
    _stableFrames = 0;
    _disposeCachedResources();
  }

  @override
  void dispose() {
    disposeCache();
    boundary = null;
    super.dispose();
  }
}
