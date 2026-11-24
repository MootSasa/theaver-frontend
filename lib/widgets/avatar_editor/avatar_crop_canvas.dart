import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../l10n/app_localizations.dart';
import '../../models/avatar_editor_models.dart';
import '../../utils/avatar_studio_renderer.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../chat/sticker_item_widget.dart';

enum _CropCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Interactive photo crop, filter preview, sticker/text, and markup canvas.
///
/// Wrapped in [SwipeBackBlocker] so drag/zoom/draw gestures inside the editor
/// never trigger [SwipeBackPageRoute] navigation pops.
class AvatarCropCanvas extends StatefulWidget {
  final ui.Image? image;
  final AvatarStudioState state;
  final AvatarShapeMask maskShape;
  final AvatarEditorTab activeTab;
  final AvatarBrushStyle activeBrushStyle;
  final Color activeBrushColor;
  final double activeBrushWidthFraction;
  final String? selectedLayerId;
  final EdgeInsets viewportPadding;
  final bool forceShowThirdsGrid;
  final ValueChanged<AvatarStudioState> onStateChanged;
  final ValueChanged<AvatarStudioState> onCommitHistory;
  final ValueChanged<String?>? onSelectLayer;
  final ValueChanged<AvatarTextLayer>? onEditTextLayer;

  const AvatarCropCanvas({
    super.key,
    required this.image,
    required this.state,
    required this.maskShape,
    required this.activeTab,
    required this.activeBrushStyle,
    required this.activeBrushColor,
    required this.activeBrushWidthFraction,
    this.selectedLayerId,
    this.viewportPadding = const EdgeInsets.fromLTRB(20, 92, 20, 220),
    this.forceShowThirdsGrid = false,
    required this.onStateChanged,
    required this.onCommitHistory,
    this.onSelectLayer,
    this.onEditTextLayer,
  });

  @override
  State<AvatarCropCanvas> createState() => _AvatarCropCanvasState();
}

class _AvatarCropCanvasState extends State<AvatarCropCanvas> {
  bool _isInteracting = false;
  double _startScale = 1.0;
  Offset _startPan = Offset.zero;
  Offset _startFocal = Offset.zero;

  AvatarBrushStroke? _inProgressStroke;
  int _strokeSeq = 0;

  // Layer drag/pinch state
  String? _draggingLayerId;
  bool _hoveringTrash = false;
  double _layerStartNormX = 0.5;
  double _layerStartNormY = 0.5;
  double _layerStartScale = 1.0;
  double _layerStartRotation = 0.0;
  Offset _layerStartFocal = Offset.zero;

  // Corner handle resize state
  Rect _cornerStartNormRect = AvatarStudioState.fullRect;

  // Independent miniature circle drag state
  bool _isDraggingMiniCircle = false;
  Offset _startMiniCenter = AvatarStudioState.defaultMiniCenter;

  void _setInteracting(bool value) {
    if (_isInteracting != value) {
      setState(() => _isInteracting = value);
    }
  }

  Rect _computeStageSquare(Size viewportSize) {
    final double left = widget.viewportPadding.left;
    final double top = widget.viewportPadding.top;
    final double right = math.max(left + 80.0, viewportSize.width - widget.viewportPadding.right);
    final double bottom = math.max(top + 80.0, viewportSize.height - widget.viewportPadding.bottom);
    final Rect area = Rect.fromLTRB(left, top, right, bottom);
    final double side = math.max(120.0, math.min(area.width, area.height));
    return Rect.fromCenter(center: area.center, width: side, height: side);
  }

  Rect _computeCropRect(Rect stageSquare) {
    final ui.Image? img = widget.image;
    if (img == null) return stageSquare;
    final Size rawSize = Size(img.width.toDouble(), img.height.toDouble());
    final Rect norm = AvatarStudioGeometry.effectiveCropNormRect(
      widget.state,
      rawSize,
    );
    return Rect.fromLTWH(
      stageSquare.left + norm.left * stageSquare.width,
      stageSquare.top + norm.top * stageSquare.height,
      norm.width * stageSquare.width,
      norm.height * stageSquare.height,
    );
  }

  void _handlePointerSignal(
    PointerSignalEvent event,
    double stageSide,
    Rect cropRect,
  ) {
    final ui.Image? img = widget.image;
    if (img == null || event is! PointerScrollEvent) return;
    final Size rawSize = Size(img.width.toDouble(), img.height.toDouble());
    final double factor = event.scrollDelta.dy > 0 ? 0.92 : 1.08;
    final double nextScale = (widget.state.scale * factor).clamp(1.0, 5.0);
    final AvatarStudioState next = widget.state.copyWith(scale: nextScale);
    final Offset clampedPan = AvatarStudioGeometry.clampPanOffset(
      panOffset: next.panOffset,
      stageSide: stageSide,
      cropSize: cropRect.size,
      rawImageSize: rawSize,
      state: next,
    );
    final AvatarStudioState committed = next.copyWith(panOffset: clampedPan);
    widget.onStateChanged(committed);
    widget.onCommitHistory(committed);
  }

  void _handleDoubleTap(double stageSide, Rect cropRect) {
    final ui.Image? img = widget.image;
    if (img == null || widget.activeTab == AvatarEditorTab.markup) return;
    HapticUtils.selection();
    final Size rawSize = Size(img.width.toDouble(), img.height.toDouble());
    final bool currentlyBase = (widget.state.scale - 1.0).abs() < 0.15;
    final double nextScale = currentlyBase ? 2.0 : 1.0;
    final Offset nextPan = currentlyBase ? widget.state.panOffset : Offset.zero;
    final AvatarStudioState next = widget.state.copyWith(
      scale: nextScale,
      panOffset: nextPan,
    );
    final Offset clampedPan = AvatarStudioGeometry.clampPanOffset(
      panOffset: next.panOffset,
      stageSide: stageSide,
      cropSize: cropRect.size,
      rawImageSize: rawSize,
      state: next,
    );
    final AvatarStudioState committed = next.copyWith(panOffset: clampedPan);
    widget.onStateChanged(committed);
    widget.onCommitHistory(committed);
  }

  void _handleBgScaleStart(
    ScaleStartDetails details,
    Rect cropRect,
    Rect miniRect,
  ) {
    if (widget.selectedLayerId != null) {
      widget.onSelectLayer?.call(null);
    }
    _startScale = widget.state.scale;
    _startPan = widget.state.panOffset;
    _startFocal = details.focalPoint;
    final bool canMoveMini = miniRect.width < cropRect.width - 1.5 ||
        miniRect.height < cropRect.height - 1.5;
    _isDraggingMiniCircle = widget.activeTab == AvatarEditorTab.crop &&
        canMoveMini &&
        details.pointerCount <= 1 &&
        miniRect.inflate(8.0).contains(details.localFocalPoint);
    _startMiniCenter = widget.state.miniCenterNorm;
    _setInteracting(true);
  }

  void _handleBgScaleUpdate(
    ScaleUpdateDetails details,
    double stageSide,
    Rect cropRect,
  ) {
    final ui.Image? img = widget.image;
    if (img == null) return;
    if (_isDraggingMiniCircle) {
      if (details.pointerCount >= 2 || (details.scale - 1.0).abs() > 0.02) {
        _isDraggingMiniCircle = false;
        _startScale = widget.state.scale;
        _startPan = widget.state.panOffset;
        _startFocal = details.focalPoint;
      } else {
        final Offset delta = details.focalPoint - _startFocal;
        final Offset rawCenter = Offset(
          _startMiniCenter.dx + delta.dx / math.max(1.0, cropRect.width),
          _startMiniCenter.dy + delta.dy / math.max(1.0, cropRect.height),
        );
        final AvatarStudioState candidate =
            widget.state.copyWith(miniCenterNorm: rawCenter);
        final Offset clampedCenter = AvatarStudioGeometry.clampMiniCenterNorm(
          candidate,
          cropRect.size,
        );
        widget.onStateChanged(candidate.copyWith(miniCenterNorm: clampedCenter));
        return;
      }
    }

    final Size rawSize = Size(img.width.toDouble(), img.height.toDouble());
    final double nextScale = (_startScale * details.scale).clamp(1.0, 5.0);
    final Offset delta = details.focalPoint - _startFocal;
    final Offset candidatePan = _startPan +
        Offset(delta.dx / stageSide, delta.dy / stageSide);
    final AvatarStudioState candidate = widget.state.copyWith(
      scale: nextScale,
      panOffset: candidatePan,
    );
    final Offset clamped = AvatarStudioGeometry.clampPanOffset(
      panOffset: candidatePan,
      stageSide: stageSide,
      cropSize: cropRect.size,
      rawImageSize: rawSize,
      state: candidate,
    );
    widget.onStateChanged(candidate.copyWith(panOffset: clamped));
  }

  void _handleBgScaleEnd(ScaleEndDetails details) {
    _isDraggingMiniCircle = false;
    _setInteracting(false);
    widget.onCommitHistory(widget.state);
  }

  Offset _toCropNorm(Offset localPos, Rect cropRect) {
    final double nx =
        ((localPos.dx - cropRect.left) / math.max(1.0, cropRect.width))
            .clamp(0.0, 1.0);
    final double ny =
        ((localPos.dy - cropRect.top) / math.max(1.0, cropRect.height))
            .clamp(0.0, 1.0);
    return Offset(nx, ny);
  }

  void _handleDrawStart(DragStartDetails details, Rect cropRect) {
    final Offset normPt = _toCropNorm(details.localPosition, cropRect);
    setState(() {
      _inProgressStroke = AvatarBrushStroke(
        id: 'stroke_${++_strokeSeq}_${DateTime.now().microsecondsSinceEpoch}',
        points: <Offset>[normPt],
        color: widget.activeBrushColor,
        strokeWidthFraction: widget.activeBrushWidthFraction,
        style: widget.activeBrushStyle,
      );
    });
  }

  void _handleDrawUpdate(DragUpdateDetails details, Rect cropRect) {
    final AvatarBrushStroke? current = _inProgressStroke;
    if (current == null) return;
    final Offset normPt = _toCropNorm(details.localPosition, cropRect);
    if (current.points.isNotEmpty &&
        (normPt - current.points.last).distance < 0.003) {
      return;
    }
    setState(() {
      _inProgressStroke = current.copyWith(
        points: <Offset>[...current.points, normPt],
      );
    });
  }

  void _handleDrawEnd([DragEndDetails? _]) {
    final AvatarBrushStroke? finished = _inProgressStroke;
    if (finished == null) return;
    setState(() => _inProgressStroke = null);
    if (finished.points.isEmpty) return;
    final AvatarStudioState next = widget.state.copyWith(
      strokes: <AvatarBrushStroke>[...widget.state.strokes, finished],
    );
    widget.onStateChanged(next);
    widget.onCommitHistory(next);
  }

  void _handleDrawTap(TapUpDetails details, Rect cropRect) {
    final Offset normPt = _toCropNorm(details.localPosition, cropRect);
    final AvatarBrushStroke dot = AvatarBrushStroke(
      id: 'stroke_${++_strokeSeq}_${DateTime.now().microsecondsSinceEpoch}',
      points: <Offset>[normPt],
      color: widget.activeBrushColor,
      strokeWidthFraction: widget.activeBrushWidthFraction,
      style: widget.activeBrushStyle,
    );
    final AvatarStudioState next = widget.state.copyWith(
      strokes: <AvatarBrushStroke>[...widget.state.strokes, dot],
    );
    widget.onStateChanged(next);
    widget.onCommitHistory(next);
  }

  void _handleCornerDragStart(_CropCorner corner, Rect stageSquare) {
    final ui.Image? img = widget.image;
    if (img == null) return;
    final Size rawSize = Size(img.width.toDouble(), img.height.toDouble());
    _cornerStartNormRect =
        AvatarStudioGeometry.effectiveCropNormRect(widget.state, rawSize);
    _setInteracting(true);
  }

  void _handleCornerDragUpdate(
    _CropCorner corner,
    DragUpdateDetails details,
    Rect stageSquare,
  ) {
    final ui.Image? img = widget.image;
    if (img == null) return;
    final Size rawSize = Size(img.width.toDouble(), img.height.toDouble());
    final Size rotSize = AvatarStudioGeometry.rotatedImageSize(
      rawSize,
      widget.state.quarterTurns,
    );
    final double stageSide = math.max(1.0, stageSquare.width);
    final double dx = details.delta.dx / stageSide;
    final double dy = details.delta.dy / stageSide;

    const double minSide = 0.22;
    double l = _cornerStartNormRect.left;
    double t = _cornerStartNormRect.top;
    double r = _cornerStartNormRect.right;
    double b = _cornerStartNormRect.bottom;

    switch (corner) {
      case _CropCorner.topLeft:
        l = (l + dx).clamp(0.0, r - minSide);
        t = (t + dy).clamp(0.0, b - minSide);
        break;
      case _CropCorner.topRight:
        r = (r + dx).clamp(l + minSide, 1.0);
        t = (t + dy).clamp(0.0, b - minSide);
        break;
      case _CropCorner.bottomLeft:
        l = (l + dx).clamp(0.0, r - minSide);
        b = (b + dy).clamp(t + minSide, 1.0);
        break;
      case _CropCorner.bottomRight:
        r = (r + dx).clamp(l + minSide, 1.0);
        b = (b + dy).clamp(t + minSide, 1.0);
        break;
    }

    if (widget.state.aspectMode == AvatarCropAspectMode.original) {
      final double targetAspect = rotSize.width / math.max(1.0, rotSize.height);
      final double w = r - l;
      final double h = b - t;
      double newW = w;
      double newH = w / targetAspect;
      if (newH > h) {
        newH = h;
        newW = h * targetAspect;
      }
      if (newW < minSide) {
        newW = minSide;
        newH = minSide / targetAspect;
      }
      if (newH < minSide) {
        newH = minSide;
        newW = minSide * targetAspect;
      }

      switch (corner) {
        case _CropCorner.topLeft:
          l = (r - newW).clamp(0.0, r - minSide);
          t = (b - newH).clamp(0.0, b - minSide);
          break;
        case _CropCorner.topRight:
          r = (l + newW).clamp(l + minSide, 1.0);
          t = (b - newH).clamp(0.0, b - minSide);
          break;
        case _CropCorner.bottomLeft:
          l = (r - newW).clamp(0.0, r - minSide);
          b = (t + newH).clamp(t + minSide, 1.0);
          break;
        case _CropCorner.bottomRight:
          r = (l + newW).clamp(l + minSide, 1.0);
          b = (t + newH).clamp(t + minSide, 1.0);
          break;
      }
    }

    _cornerStartNormRect = Rect.fromLTRB(l, t, r, b);
    final Size nextCropSize = Size(
      _cornerStartNormRect.width * stageSide,
      _cornerStartNormRect.height * stageSide,
    );
    final AvatarStudioState next = widget.state.copyWith(
      freeRectNormalized: _cornerStartNormRect,
    );
    final Offset clampedPan = AvatarStudioGeometry.clampPanOffset(
      panOffset: next.panOffset,
      stageSide: stageSide,
      cropSize: nextCropSize,
      rawImageSize: rawSize,
      state: next,
    );
    widget.onStateChanged(next.copyWith(panOffset: clampedPan));
  }

  void _handleCornerDragEnd([DragEndDetails? _]) {
    _setInteracting(false);
    widget.onCommitHistory(widget.state);
  }

  bool _isTrashZone(double normY) => normY > 0.88;

  void _updateHoverTrash(double normY) {
    final bool inside = _isTrashZone(normY);
    if (inside != _hoveringTrash) {
      if (inside) HapticUtils.impact();
      setState(() => _hoveringTrash = inside);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwipeBackBlocker(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size viewportSize = constraints.biggest;
          if (viewportSize.isEmpty) return const SizedBox.shrink();

          final Rect stageSquare = _computeStageSquare(viewportSize);
          final Rect cropRect = _computeCropRect(stageSquare);
          final Rect miniRect = AvatarStudioGeometry.effectiveMiniRectInCrop(
            widget.state,
            cropRect.size,
          ).shift(cropRect.topLeft);
          final bool showHandles =
              widget.image != null &&
              widget.state.aspectMode != AvatarCropAspectMode.square1x1 &&
              widget.activeTab != AvatarEditorTab.markup;
          final bool showMiniControl =
              widget.image != null && widget.activeTab == AvatarEditorTab.crop;
          final bool showMiniBadge =
              widget.image != null &&
              (miniRect.width < cropRect.width - 2.0 ||
                  miniRect.height < cropRect.height - 2.0);
          final bool showGrid = _isInteracting || widget.forceShowThirdsGrid;

          final List<AvatarBrushStroke> renderStrokes = <AvatarBrushStroke>[
            ...widget.state.strokes,
            if (_inProgressStroke != null) _inProgressStroke!,
          ];

          return Listener(
            onPointerSignal: (event) =>
                _handlePointerSignal(event, stageSquare.width, cropRect),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background gesture surface for pan / pinch-zoom / double-tap / mini-circle drag
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () =>
                      _handleDoubleTap(stageSquare.width, cropRect),
                  onScaleStart: (d) =>
                      _handleBgScaleStart(d, cropRect, miniRect),
                  onScaleUpdate: (d) =>
                      _handleBgScaleUpdate(d, stageSquare.width, cropRect),
                  onScaleEnd: _handleBgScaleEnd,
                  child: CustomPaint(
                    painter: _AvatarStagePainter(
                      image: widget.image,
                      state: widget.state,
                      stageSide: stageSquare.width,
                      cropRect: cropRect,
                      strokes: renderStrokes,
                    ),
                  ),
                ),

                // Interactive Sticker & Text Overlays inside cropRect
                Positioned.fromRect(
                  rect: cropRect,
                  child: ClipRect(
                    clipBehavior: _draggingLayerId != null
                        ? Clip.none
                        : Clip.hardEdge,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final AvatarStickerLayer layer
                            in widget.state.stickers)
                          _buildStickerWidget(layer, cropRect),
                        for (final AvatarTextLayer layer
                            in widget.state.textLayers)
                          _buildTextWidget(layer, cropRect),
                      ],
                    ),
                  ),
                ),

                // Two-tier Scrim & Independent Miniature Cutout
                IgnorePointer(
                  child: CustomPaint(
                    painter: _AvatarMaskOverlayPainter(
                      cropRect: cropRect,
                      miniRect: miniRect,
                      maskShape: widget.maskShape,
                      aspectMode: widget.state.aspectMode,
                    ),
                  ),
                ),

                // Rule-of-Thirds Grid (AnimatedOpacity ONLY on CustomPaint)
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: showGrid ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 140),
                    child: CustomPaint(
                      painter: _AvatarThirdsGridPainter(cropRect: cropRect),
                    ),
                  ),
                ),

                // Finger drawing surface in Markup tab
                if (widget.activeTab == AvatarEditorTab.markup)
                  Positioned.fromRect(
                    rect: cropRect,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _handleDrawTap(d, Rect.fromLTWH(0, 0, cropRect.width, cropRect.height)),
                      onPanStart: (d) => _handleDrawStart(d, Rect.fromLTWH(0, 0, cropRect.width, cropRect.height)),
                      onPanUpdate: (d) => _handleDrawUpdate(d, Rect.fromLTWH(0, 0, cropRect.width, cropRect.height)),
                      onPanEnd: _handleDrawEnd,
                      onPanCancel: _handleDrawEnd,
                      child: const SizedBox.expand(),
                    ),
                  ),

                // Draggable 4-corner resize handles for Original / Free crop modes
                if (showHandles) ..._buildCornerHandles(cropRect, stageSquare),

                // Interactive miniature circle/squircle rim resize handle
                if (showMiniControl)
                  _buildMiniResizeHandle(cropRect, miniRect),

                // Live miniature preview badge when outer photo differs from miniature circle
                if (showMiniBadge)
                  Positioned(
                    top: widget.viewportPadding.top + 8.0,
                    left: 18.0,
                    child: IgnorePointer(
                      child: Container(
                        width: 48.0,
                        height: 48.0,
                        decoration: BoxDecoration(
                          borderRadius: widget.maskShape.borderRadiusForSize(48.0),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.88),
                            width: 1.5,
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 10.0,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius:
                              widget.maskShape.borderRadiusForSize(48.0),
                          child: CustomPaint(
                            size: const Size(48.0, 48.0),
                            painter: _MiniCirclePreviewPainter(
                              image: widget.image!,
                              state: widget.state,
                              stageSide: stageSquare.width,
                              cropRect: cropRect,
                              miniRect: miniRect,
                              strokes: renderStrokes,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Drag-to-delete trash pill at bottom of crop area
                if (_draggingLayerId != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: math.max(16.0, widget.viewportPadding.bottom + 8.0),
                    child: IgnorePointer(
                      child: Center(
                        child: AnimatedScale(
                          scale: _hoveringTrash ? 1.12 : 1.0,
                          duration: const Duration(milliseconds: 140),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _hoveringTrash
                                  ? const Color(0xFFFF3B30)
                                  : Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: Colors.white.withValues(
                                  alpha: _hoveringTrash ? 0.85 : 0.25,
                                ),
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const iconoir.Trash(
                                  width: 18,
                                  height: 18,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  context.trOr(
                                    'avatar_editor_drag_to_delete',
                                    'Отпустите, чтобы удалить',
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStickerWidget(AvatarStickerLayer layer, Rect cropRect) {
    final double minSide = math.min(cropRect.width, cropRect.height);
    final double side = (minSide * 0.24 * layer.scale).clamp(24.0, minSide * 1.4);
    final bool selected = widget.selectedLayerId == layer.id;
    final double cx = layer.normX * cropRect.width;
    final double cy = layer.normY * cropRect.height;

    return Positioned(
      left: cx - side * 0.5,
      top: cy - side * 0.5,
      width: side,
      height: side,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticUtils.selection();
          widget.onSelectLayer?.call(layer.id);
        },
        onScaleStart: (details) {
          widget.onSelectLayer?.call(layer.id);
          setState(() {
            _draggingLayerId = layer.id;
            _hoveringTrash = false;
          });
          _layerStartNormX = layer.normX;
          _layerStartNormY = layer.normY;
          _layerStartScale = layer.scale;
          _layerStartRotation = layer.rotation;
          _layerStartFocal = details.focalPoint;
        },
        onScaleUpdate: (details) {
          final Offset delta = details.focalPoint - _layerStartFocal;
          final double nextX =
              (_layerStartNormX + delta.dx / math.max(1.0, cropRect.width))
                  .clamp(-0.15, 1.15);
          final double nextY =
              (_layerStartNormY + delta.dy / math.max(1.0, cropRect.height))
                  .clamp(-0.15, 1.15);
          final double nextScale =
              (_layerStartScale * details.scale).clamp(0.35, 3.2);
          final double nextRot = _layerStartRotation + details.rotation;

          _updateHoverTrash(nextY);
          final List<AvatarStickerLayer> updated = [
            for (final s in widget.state.stickers)
              if (s.id == layer.id)
                s.copyWith(
                  normX: nextX,
                  normY: nextY,
                  scale: nextScale,
                  rotation: nextRot,
                )
              else
                s,
          ];
          widget.onStateChanged(widget.state.copyWith(stickers: updated));
        },
        onScaleEnd: (_) {
          final bool shouldDelete = _hoveringTrash;
          setState(() {
            _draggingLayerId = null;
            _hoveringTrash = false;
          });
          if (shouldDelete) {
            final List<AvatarStickerLayer> remaining = widget.state.stickers
                .where((s) => s.id != layer.id)
                .toList();
            final next = widget.state.copyWith(stickers: remaining);
            widget.onStateChanged(next);
            widget.onCommitHistory(next);
            widget.onSelectLayer?.call(null);
          } else {
            widget.onCommitHistory(widget.state);
          }
        },
        child: Transform.rotate(
          angle: layer.rotation,
          child: Container(
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF38BDF8),
                      width: 1.4,
                    ),
                  )
                : null,
            child: Center(
              child: layer.stickerUrl != null && layer.stickerUrl!.isNotEmpty
                  ? StickerMediaView(
                      fileUrl: layer.stickerUrl!,
                      format: layer.stickerFormat,
                      width: side,
                      height: side,
                      animate: true,
                    )
                  : Text(
                      layer.emoji ?? '😀',
                      style: EmojiUtils.emojiTextStyle(
                        fontSize: side * 0.84,
                        height: 1.0,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextWidget(AvatarTextLayer layer, Rect cropRect) {
    final measured = AvatarStudioPaint.layoutTextLayer(
      cropSize: cropRect.size,
      layer: layer,
      textDirection: Directionality.of(context),
    );
    final Size box = measured.boxSize;
    final bool selected = widget.selectedLayerId == layer.id;
    final double cx = layer.normX * cropRect.width;
    final double cy = layer.normY * cropRect.height;

    return Positioned(
      left: cx - box.width * 0.5,
      top: cy - box.height * 0.5,
      width: box.width,
      height: box.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticUtils.selection();
          if (selected) {
            widget.onEditTextLayer?.call(layer);
          } else {
            widget.onSelectLayer?.call(layer.id);
          }
        },
        onDoubleTap: () => widget.onEditTextLayer?.call(layer),
        onScaleStart: (details) {
          widget.onSelectLayer?.call(layer.id);
          setState(() {
            _draggingLayerId = layer.id;
            _hoveringTrash = false;
          });
          _layerStartNormX = layer.normX;
          _layerStartNormY = layer.normY;
          _layerStartScale = layer.scale;
          _layerStartRotation = layer.rotation;
          _layerStartFocal = details.focalPoint;
        },
        onScaleUpdate: (details) {
          final Offset delta = details.focalPoint - _layerStartFocal;
          final double nextX =
              (_layerStartNormX + delta.dx / math.max(1.0, cropRect.width))
                  .clamp(-0.15, 1.15);
          final double nextY =
              (_layerStartNormY + delta.dy / math.max(1.0, cropRect.height))
                  .clamp(-0.15, 1.15);
          final double nextScale =
              (_layerStartScale * details.scale).clamp(0.45, 3.0);
          final double nextRot = _layerStartRotation + details.rotation;

          _updateHoverTrash(nextY);
          final List<AvatarTextLayer> updated = [
            for (final t in widget.state.textLayers)
              if (t.id == layer.id)
                t.copyWith(
                  normX: nextX,
                  normY: nextY,
                  scale: nextScale,
                  rotation: nextRot,
                )
              else
                t,
          ];
          widget.onStateChanged(widget.state.copyWith(textLayers: updated));
        },
        onScaleEnd: (_) {
          final bool shouldDelete = _hoveringTrash;
          setState(() {
            _draggingLayerId = null;
            _hoveringTrash = false;
          });
          if (shouldDelete) {
            final List<AvatarTextLayer> remaining = widget.state.textLayers
                .where((t) => t.id != layer.id)
                .toList();
            final next = widget.state.copyWith(textLayers: remaining);
            widget.onStateChanged(next);
            widget.onCommitHistory(next);
            widget.onSelectLayer?.call(null);
          } else {
            widget.onCommitHistory(widget.state);
          }
        },
        child: Transform.rotate(
          angle: layer.rotation,
          child: Container(
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF38BDF8),
                      width: 1.4,
                    ),
                  )
                : null,
            child: CustomPaint(
              painter: _SingleTextLayerPainter(
                layer: layer,
                cropSize: cropRect.size,
                textDirection: Directionality.of(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset _miniResizeHandleCenter(Rect miniRect) {
    if (widget.maskShape == AvatarShapeMask.circle) {
      final double r = math.min(miniRect.width, miniRect.height) * 0.5;
      const double diag = 0.7071067811865475;
      return miniRect.center + Offset(r * diag, r * diag);
    }
    return miniRect.bottomRight -
        Offset(miniRect.width * 0.088, miniRect.height * 0.088);
  }

  void _handleMiniResizeUpdate(DragUpdateDetails details, Rect cropRect) {
    final RenderObject? ro = context.findRenderObject();
    if (ro is! RenderBox) return;
    final Offset localPos = ro.globalToLocal(details.globalPosition);
    final Rect curMini = AvatarStudioGeometry.effectiveMiniRectInCrop(
      widget.state,
      cropRect.size,
    ).shift(cropRect.topLeft);
    final double dist = (localPos - curMini.center).distance;
    final double newDiameter = widget.maskShape == AvatarShapeMask.circle
        ? dist * 2.0
        : dist / 0.5826;
    final double minCropSide =
        math.max(1.0, math.min(cropRect.width, cropRect.height));
    final double nextFrac = (newDiameter / minCropSide)
        .clamp(AvatarStudioState.minMiniSizeFraction, 1.0)
        .toDouble();
    final AvatarStudioState candidate =
        widget.state.copyWith(miniSizeFrac: nextFrac);
    final Offset clampedCenter = AvatarStudioGeometry.clampMiniCenterNorm(
      candidate,
      cropRect.size,
    );
    widget.onStateChanged(candidate.copyWith(miniCenterNorm: clampedCenter));
  }

  Widget _buildMiniResizeHandle(Rect cropRect, Rect miniRect) {
    const double hitSize = 40.0;
    final Offset handleCenter = _miniResizeHandleCenter(miniRect);
    return Positioned(
      left: handleCenter.dx - hitSize * 0.5,
      top: handleCenter.dy - hitSize * 0.5,
      width: hitSize,
      height: hitSize,
      child: GestureDetector(
        key: const ValueKey<String>('avatar_mini_circle_resize_handle'),
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _setInteracting(true),
        onPanUpdate: (DragUpdateDetails d) => _handleMiniResizeUpdate(d, cropRect),
        onPanEnd: (_) {
          _setInteracting(false);
          widget.onCommitHistory(widget.state);
        },
        onPanCancel: () {
          _setInteracting(false);
          widget.onCommitHistory(widget.state);
        },
        child: Center(
          child: Container(
            width: 22.0,
            height: 22.0,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.45),
                width: 1.5,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.40),
                  blurRadius: 6.0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.open_in_full_rounded,
              size: 12.0,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCornerHandles(Rect cropRect, Rect stageSquare) {
    const double hitSize = 36.0;
    final entries = <(_CropCorner, Offset)>[
      (_CropCorner.topLeft, cropRect.topLeft),
      (_CropCorner.topRight, cropRect.topRight),
      (_CropCorner.bottomLeft, cropRect.bottomLeft),
      (_CropCorner.bottomRight, cropRect.bottomRight),
    ];

    return [
      for (final entry in entries)
        Positioned(
          left: entry.$2.dx - hitSize * 0.5,
          top: entry.$2.dy - hitSize * 0.5,
          width: hitSize,
          height: hitSize,
          child: GestureDetector(
            key: ValueKey<String>('avatar_crop_handle_${entry.$1.name}'),
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _handleCornerDragStart(entry.$1, stageSquare),
            onPanUpdate: (d) =>
                _handleCornerDragUpdate(entry.$1, d, stageSquare),
            onPanEnd: _handleCornerDragEnd,
            onPanCancel: _handleCornerDragEnd,
            child: const SizedBox.expand(),
          ),
        ),
    ];
  }
}

class _AvatarStagePainter extends CustomPainter {
  final ui.Image? image;
  final AvatarStudioState state;
  final double stageSide;
  final Rect cropRect;
  final List<AvatarBrushStroke> strokes;

  _AvatarStagePainter({
    required this.image,
    required this.state,
    required this.stageSide,
    required this.cropRect,
    required this.strokes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Image? img = image;
    if (img == null) return;

    AvatarStudioPaint.paintPhotoLayer(
      canvas: canvas,
      image: img,
      cropRect: cropRect,
      stageSide: stageSide,
      state: state,
      filterQuality: FilterQuality.medium,
    );

    canvas.save();
    canvas.clipRect(cropRect);
    AvatarStudioPaint.paintVignette(
      canvas: canvas,
      cropRect: cropRect,
      vignette: state.adjustments.vignette,
    );
    AvatarStudioPaint.paintBrushStrokes(
      canvas: canvas,
      bounds: cropRect,
      strokes: strokes,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AvatarStagePainter oldDelegate) {
    return !identical(oldDelegate.image, image) ||
        oldDelegate.state != state ||
        oldDelegate.stageSide != stageSide ||
        oldDelegate.cropRect != cropRect ||
        !listEquals(oldDelegate.strokes, strokes);
  }
}

class _SingleTextLayerPainter extends CustomPainter {
  final AvatarTextLayer layer;
  final Size cropSize;
  final TextDirection textDirection;

  _SingleTextLayerPainter({
    required this.layer,
    required this.cropSize,
    required this.textDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final AvatarTextLayer centered = layer.copyWith(normX: 0.5, normY: 0.5);
    AvatarStudioPaint.paintTextLayer(
      canvas: canvas,
      bounds: Offset.zero & size,
      layer: centered,
      textDirection: textDirection,
    );
  }

  @override
  bool shouldRepaint(covariant _SingleTextLayerPainter oldDelegate) {
    return oldDelegate.layer != layer ||
        oldDelegate.cropSize != cropSize ||
        oldDelegate.textDirection != textDirection;
  }
}

class _MiniCirclePreviewPainter extends CustomPainter {
  final ui.Image image;
  final AvatarStudioState state;
  final double stageSide;
  final Rect cropRect;
  final Rect miniRect;
  final List<AvatarBrushStroke> strokes;

  _MiniCirclePreviewPainter({
    required this.image,
    required this.state,
    required this.stageSide,
    required this.cropRect,
    required this.miniRect,
    required this.strokes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final Rect localMini = miniRect.shift(-cropRect.topLeft);
    final double scale = size.width / math.max(1.0, localMini.width);
    final Rect scaledCrop =
        Rect.fromLTWH(0.0, 0.0, cropRect.width, cropRect.height);

    canvas.save();
    canvas.scale(scale, scale);
    canvas.translate(-localMini.left, -localMini.top);
    AvatarStudioPaint.paintPhotoLayer(
      canvas: canvas,
      image: image,
      cropRect: scaledCrop,
      stageSide: stageSide,
      state: state,
      filterQuality: FilterQuality.medium,
    );
    AvatarStudioPaint.paintVignette(
      canvas: canvas,
      cropRect: scaledCrop,
      vignette: state.adjustments.vignette,
    );
    AvatarStudioPaint.paintBrushStrokes(
      canvas: canvas,
      bounds: scaledCrop,
      strokes: strokes,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MiniCirclePreviewPainter oldDelegate) {
    return !identical(oldDelegate.image, image) ||
        oldDelegate.state != state ||
        oldDelegate.stageSide != stageSide ||
        oldDelegate.cropRect != cropRect ||
        oldDelegate.miniRect != miniRect ||
        !listEquals(oldDelegate.strokes, strokes);
  }
}

class _AvatarMaskOverlayPainter extends CustomPainter {
  final Rect cropRect;
  final Rect miniRect;
  final AvatarShapeMask maskShape;
  final AvatarCropAspectMode aspectMode;

  _AvatarMaskOverlayPainter({
    required this.cropRect,
    required this.miniRect,
    required this.maskShape,
    required this.aspectMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect full = Offset.zero & size;
    final RRect cropRRect =
        RRect.fromRectAndRadius(cropRect, const Radius.circular(2.0));
    final RRect miniCutout = maskShape.shapeRRect(miniRect);

    // Tier 1: Heavy dim outside outer cropRect
    final Path outerScrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(full)
      ..addRRect(cropRRect);
    canvas.drawPath(
      outerScrim,
      Paint()..color = Colors.black.withValues(alpha: 0.72),
    );

    // Tier 2: Softer dim inside cropRect around miniature circle/squircle cutout
    final Path innerScrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(cropRect)
      ..addRRect(miniCutout);
    canvas.drawPath(
      innerScrim,
      Paint()..color = Colors.black.withValues(alpha: 0.40),
    );

    // Outer photo frame outline
    if (aspectMode != AvatarCropAspectMode.square1x1) {
      canvas.drawRRect(
        cropRRect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..isAntiAlias = true,
      );

      // L-shaped corner brackets
      final Paint bracketPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.square;
      const double arm = 18.0;
      canvas.drawLine(cropRect.topLeft, cropRect.topLeft + const Offset(arm, 0), bracketPaint);
      canvas.drawLine(cropRect.topLeft, cropRect.topLeft + const Offset(0, arm), bracketPaint);
      canvas.drawLine(cropRect.topRight, cropRect.topRight + const Offset(-arm, 0), bracketPaint);
      canvas.drawLine(cropRect.topRight, cropRect.topRight + const Offset(0, arm), bracketPaint);
      canvas.drawLine(cropRect.bottomLeft, cropRect.bottomLeft + const Offset(arm, 0), bracketPaint);
      canvas.drawLine(cropRect.bottomLeft, cropRect.bottomLeft + const Offset(0, -arm), bracketPaint);
      canvas.drawLine(cropRect.bottomRight, cropRect.bottomRight + const Offset(-arm, 0), bracketPaint);
      canvas.drawLine(cropRect.bottomRight, cropRect.bottomRight + const Offset(0, -arm), bracketPaint);
    }

    // Crisp 1.6dp ring around the miniature avatar cutout
    canvas.drawRRect(
      miniCutout,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _AvatarMaskOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.miniRect != miniRect ||
        oldDelegate.maskShape != maskShape ||
        oldDelegate.aspectMode != aspectMode;
  }
}

class _AvatarThirdsGridPainter extends CustomPainter {
  final Rect cropRect;

  _AvatarThirdsGridPainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.36)
      ..strokeWidth = 0.75;

    final double thirdW = cropRect.width / 3.0;
    final double thirdH = cropRect.height / 3.0;

    for (int i = 1; i <= 2; i++) {
      final double x = cropRect.left + thirdW * i;
      canvas.drawLine(
        Offset(x, cropRect.top),
        Offset(x, cropRect.bottom),
        paint,
      );
      final double y = cropRect.top + thirdH * i;
      canvas.drawLine(
        Offset(cropRect.left, y),
        Offset(cropRect.right, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarThirdsGridPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
  }
}
