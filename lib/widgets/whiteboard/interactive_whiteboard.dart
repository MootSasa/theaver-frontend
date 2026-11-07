import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../models/theav_theme.dart';
import '../../models/whiteboard_models.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/whiteboard_service.dart';

/// Miro-style Collaborative Interactive Whiteboard widget.
///
/// Works both inside live Voice/Video/Stage calls and as a standalone
/// Community Whiteboard channel (`channel_type == 'whiteboard'`).
class InteractiveWhiteboard extends StatefulWidget {
  final String roomId;
  final String? chatId;
  final String title;
  final VoidCallback? onClose;
  final bool embeddedInCall;

  const InteractiveWhiteboard({
    super.key,
    required this.roomId,
    this.chatId,
    this.title = 'Интерактивная доска',
    this.onClose,
    this.embeddedInCall = false,
  });

  @override
  State<InteractiveWhiteboard> createState() => _InteractiveWhiteboardState();
}

class _InteractiveWhiteboardState extends State<InteractiveWhiteboard> {
  static const double _canvasWidth = 3600.0;
  static const double _canvasHeight = 2400.0;

  late final WhiteboardController _controller;
  late final TransformationController _transformCtrl;
  int _activePointers = 0;
  Offset? _lastScenePoint;
  double _currentZoom = 1.0;
  bool _centeredInitially = false;

  @override
  void initState() {
    super.initState();
    _controller = WhiteboardController(
      roomId: widget.roomId,
      chatId: widget.chatId,
    );
    _transformCtrl = TransformationController();
    _transformCtrl.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final scale = _transformCtrl.value.getMaxScaleOnAxis();
    if ((scale - _currentZoom).abs() > 0.02 && mounted) {
      setState(() => _currentZoom = scale);
    }
  }

  @override
  void dispose() {
    _transformCtrl.removeListener(_onTransformChanged);
    _transformCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _centerCanvasInViewport(Size viewportSize) {
    if (_centeredInitially || viewportSize.isEmpty) return;
    _centeredInitially = true;
    final dx = (viewportSize.width - _canvasWidth) / 2.0;
    final dy = (viewportSize.height - _canvasHeight) / 2.0;
    _transformCtrl.value = Matrix4.identity()..translateByDouble(dx, dy, 0.0, 1.0);
  }

  void _zoomBy(double factor, Size viewportSize) {
    final currentScale = _transformCtrl.value.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(0.25, 3.5);
    final actualFactor = targetScale / currentScale;
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final sceneCenter = _transformCtrl.toScene(center);

    final m = _transformCtrl.value.clone();
    m.translateByDouble(sceneCenter.dx, sceneCenter.dy, 0.0, 1.0);
    m.scaleByDouble(actualFactor, actualFactor, 1.0, 1.0);
    m.translateByDouble(-sceneCenter.dx, -sceneCenter.dy, 0.0, 1.0);
    _transformCtrl.value = m;
  }

  void _resetViewport(Size viewportSize) {
    final dx = (viewportSize.width - _canvasWidth) / 2.0;
    final dy = (viewportSize.height - _canvasHeight) / 2.0;
    _transformCtrl.value = Matrix4.identity()..translateByDouble(dx, dy, 0.0, 1.0);
  }

  Future<void> _promptEditElementText(WhiteboardElement element) async {
    final textCtrl = TextEditingController(text: element.text);
    final updatedText = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final p = ctx.theav;
        return AlertDialog(
          backgroundColor: p.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            element.isSticky ? 'Текст стикера' : 'Текст элемента',
            style: TextStyle(
              color: p.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          content: TextField(
            controller: textCtrl,
            autofocus: true,
            maxLines: 5,
            minLines: 2,
            style: TextStyle(color: p.textPrimary, fontSize: 14.5),
            decoration: InputDecoration(
              hintText: 'Введите текст...',
              hintStyle: TextStyle(color: p.textTertiary),
              filled: true,
              fillColor: p.surfaceSecondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Отмена', style: TextStyle(color: p.textSecondary)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(textCtrl.text.trim()),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    if (updatedText != null && mounted) {
      _controller.updateElement(element.copyWith(text: updatedText));
    }
  }

  Future<void> _confirmClearBoard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final p = ctx.theav;
        return AlertDialog(
          backgroundColor: p.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Очистить доску?',
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Все элементы на совместной доске будут удалены для всех участников (вы сможете отменить это действие кнопкой Undo).',
            style: TextStyle(color: p.textSecondary, fontSize: 13.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Отмена', style: TextStyle(color: p.textSecondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Очистить'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _controller.clearAll();
    }
  }

  void _handleCanvasTapUp(Offset localPosition) {
    final scenePoint = _transformCtrl.toScene(localPosition);
    final tool = _controller.activeTool;

    if (tool == WhiteboardTool.sticky || tool == WhiteboardTool.text) {
      HapticFeedback.lightImpact();
      final created = _controller.addStickyOrText(
        scenePoint: scenePoint,
        isSticky: tool == WhiteboardTool.sticky,
      );
      _promptEditElementText(created);
      return;
    }

    if (tool == WhiteboardTool.select) {
      // Hit test
      final hit = _controller.elements.reversed
          .where((e) => e.containsPoint(scenePoint))
          .firstOrNull;
      _controller.selectElement(hit?.id);
    }
  }

  void _handleCanvasDoubleTapDown(Offset localPosition) {
    final scenePoint = _transformCtrl.toScene(localPosition);
    final hit = _controller.elements.reversed
        .where((e) => e.containsPoint(scenePoint))
        .firstOrNull;
    if (hit != null && (hit.isSticky || hit.isText || hit.isShape)) {
      HapticFeedback.selectionClick();
      _controller.selectElement(hit.id);
      _promptEditElementText(hit);
    } else {
      HapticFeedback.lightImpact();
      final created = _controller.addStickyOrText(
        scenePoint: scenePoint,
        isSticky: true,
      );
      _promptEditElementText(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.theav;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final glassProvider = context.watch<LiquidGlassProvider>();
    final useGlass = glassProvider.enabled;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final isPanMode = _controller.activeTool == WhiteboardTool.pan ||
            _activePointers >= 2;

        return LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize =
                Size(constraints.maxWidth, constraints.maxHeight);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _centerCanvasInViewport(viewportSize);
            });

            return Container(
              color: isDark ? const Color(0xFF11151E) : const Color(0xFFF4F6FA),
              child: Stack(
                children: [
                  // 1. Infinite Pan & Zoom Miro Canvas
                  Positioned.fill(
                    child: Listener(
                      onPointerDown: (event) {
                        _activePointers++;
                        final scenePt =
                            _transformCtrl.toScene(event.localPosition);
                        if (_activePointers == 1 &&
                            event.buttons != kMiddleMouseButton &&
                            event.buttons != kSecondaryMouseButton &&
                            _controller.activeTool != WhiteboardTool.pan &&
                            _controller.activeTool != WhiteboardTool.sticky &&
                            _controller.activeTool != WhiteboardTool.text) {
                          _lastScenePoint = scenePt;
                          _controller.startInteraction(scenePt);
                        }
                      },
                      onPointerMove: (event) {
                        final scenePt =
                            _transformCtrl.toScene(event.localPosition);
                        if (_activePointers == 1 &&
                            event.buttons != kMiddleMouseButton &&
                            event.buttons != kSecondaryMouseButton &&
                            _controller.activeTool != WhiteboardTool.pan &&
                            _controller.activeTool != WhiteboardTool.sticky &&
                            _controller.activeTool != WhiteboardTool.text) {
                          final prev = _lastScenePoint ?? scenePt;
                          final delta = scenePt - prev;
                          _lastScenePoint = scenePt;
                          _controller.updateInteraction(scenePt, delta);
                        }
                      },
                      onPointerUp: (event) {
                        _activePointers = math.max(0, _activePointers - 1);
                        _lastScenePoint = null;
                        _controller.endInteraction();
                      },
                      onPointerCancel: (event) {
                        _activePointers = math.max(0, _activePointers - 1);
                        _lastScenePoint = null;
                        _controller.endInteraction();
                      },
                      onPointerHover: (event) {
                        final scenePt =
                            _transformCtrl.toScene(event.localPosition);
                        _controller.onHover(scenePt);
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) =>
                            _handleCanvasTapUp(details.localPosition),
                        onDoubleTapDown: (details) =>
                            _handleCanvasDoubleTapDown(details.localPosition),
                        child: InteractiveViewer(
                          transformationController: _transformCtrl,
                          constrained: false,
                          panEnabled: isPanMode,
                          scaleEnabled: true,
                          minScale: 0.25,
                          maxScale: 3.5,
                          boundaryMargin: const EdgeInsets.all(1200),
                          child: SizedBox(
                            width: _canvasWidth,
                            height: _canvasHeight,
                            child: RepaintBoundary(
                              child: CustomPaint(
                                size: const Size(_canvasWidth, _canvasHeight),
                                painter: _WhiteboardScenePainter(
                                  elements: _controller.elements,
                                  draftElement: _controller.activeDraftElement,
                                  selectedElementId:
                                      _controller.selectedElementId,
                                  remoteCursors: _controller.remoteCursors,
                                  localLaserTrail: _controller.localLaserTrail,
                                  gridStyle: _controller.gridStyle,
                                  isDark: isDark,
                                  primaryColor: primaryColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 2. Top Floating Header & Controls Bar
                  Positioned(
                    top: 10,
                    left: 12,
                    right: 12,
                    child: _buildTopHeaderBar(
                      context,
                      p: p,
                      primaryColor: primaryColor,
                      useGlass: useGlass,
                      viewportSize: viewportSize,
                    ),
                  ),

                  // 3. Contextual Style / Selection Bar (above Bottom Dock)
                  if (_shouldShowStyleBar())
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 76,
                      child: Center(
                        child: _buildContextualStyleBar(
                          context,
                          p: p,
                          primaryColor: primaryColor,
                          useGlass: useGlass,
                        ),
                      ),
                    ),

                  // 4. Bottom Floating Miro Tool Dock
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Center(
                      child: _buildBottomToolDock(
                        context,
                        p: p,
                        primaryColor: primaryColor,
                        useGlass: useGlass,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _shouldShowStyleBar() {
    if (_controller.selectedElement != null) return true;
    final t = _controller.activeTool;
    return t == WhiteboardTool.pen ||
        t == WhiteboardTool.highlighter ||
        t == WhiteboardTool.sticky ||
        t == WhiteboardTool.rectangle ||
        t == WhiteboardTool.ellipse ||
        t == WhiteboardTool.diamond ||
        t == WhiteboardTool.arrow ||
        t == WhiteboardTool.text;
  }

  Widget _wrapGlassPill({
    required BuildContext context,
    required TheavPalette p,
    required bool useGlass,
    required double radius,
    required Widget child,
  }) {
    if (useGlass) {
      return LiquidGlassLens(
        style: context.read<LiquidGlassProvider>().createStyle(
              context: context,
              cornerRadius: radius,
              color: p.surfaceElevated.withValues(alpha: 0.72),
              refractionIndex: 1.05,
              refractionWidth: 18.0,
            ),
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: p.surfaceElevated.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: p.borderSubtle, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildTopHeaderBar(
    BuildContext context, {
    required TheavPalette p,
    required Color primaryColor,
    required bool useGlass,
    required Size viewportSize,
  }) {
    final remoteCount = _controller.remoteCursors.length;
    final zoomPct = (_currentZoom * 100).round();

    return Row(
      children: [
        // Left: Board Title & Collaborators
        Flexible(
          child: _wrapGlassPill(
            context: context,
            p: p,
            useGlass: useGlass,
            radius: 16,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.draw_rounded,
                      size: 16,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                  if (remoteCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00E676),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '+$remoteCount онлайн',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF00E676),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const Spacer(),

        // Right: Undo/Redo, Grid, Zoom & Close
        _wrapGlassPill(
          context: context,
          p: p,
          useGlass: useGlass,
          radius: 16,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Отменить (Undo)',
                  icon: Icon(
                    Icons.undo_rounded,
                    size: 18,
                    color: _controller.canUndo
                        ? p.textPrimary
                        : p.textTertiary.withValues(alpha: 0.4),
                  ),
                  onPressed: _controller.canUndo ? _controller.undo : null,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Повторить (Redo)',
                  icon: Icon(
                    Icons.redo_rounded,
                    size: 18,
                    color: _controller.canRedo
                        ? p.textPrimary
                        : p.textTertiary.withValues(alpha: 0.4),
                  ),
                  onPressed: _controller.canRedo ? _controller.redo : null,
                ),
                Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: p.borderSubtle,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Стиль сетки холста',
                  icon: Icon(
                    _controller.gridStyle == WhiteboardGridStyle.dots
                        ? Icons.blur_on_rounded
                        : _controller.gridStyle == WhiteboardGridStyle.lines
                            ? Icons.grid_4x4_rounded
                            : Icons.crop_din_rounded,
                    size: 18,
                    color: p.textSecondary,
                  ),
                  onPressed: _controller.cycleGridStyle,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Отдалить',
                  icon: Icon(
                    Icons.remove_rounded,
                    size: 17,
                    color: p.textSecondary,
                  ),
                  onPressed: () => _zoomBy(0.8, viewportSize),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _resetViewport(viewportSize),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      '$zoomPct%',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: p.textSecondary,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Приблизить',
                  icon: Icon(
                    Icons.add_rounded,
                    size: 17,
                    color: p.textSecondary,
                  ),
                  onPressed: () => _zoomBy(1.25, viewportSize),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Очистить доску',
                  icon: Icon(
                    Icons.delete_sweep_rounded,
                    size: 18,
                    color: _controller.elements.isNotEmpty
                        ? Colors.redAccent
                        : p.textTertiary.withValues(alpha: 0.4),
                  ),
                  onPressed:
                      _controller.elements.isNotEmpty ? _confirmClearBoard : null,
                ),
                if (widget.onClose != null) ...[
                  Container(
                    width: 1,
                    height: 18,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    color: p.borderSubtle,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Свернуть доску',
                    icon: Icon(
                      Icons.close_rounded,
                      size: 19,
                      color: p.textPrimary,
                    ),
                    onPressed: widget.onClose,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContextualStyleBar(
    BuildContext context, {
    required TheavPalette p,
    required Color primaryColor,
    required bool useGlass,
  }) {
    final selected = _controller.selectedElement;
    final isStickyContext =
        _controller.activeTool == WhiteboardTool.sticky ||
            (selected != null && selected.isSticky);
    final palette = isStickyContext
        ? WhiteboardController.stickyPalette
        : WhiteboardController.defaultPalette;
    final currentColor = selected?.colorValue ?? _controller.activeColor;

    return _wrapGlassPill(
      context: context,
      p: p,
      useGlass: useGlass,
      radius: 18,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Color Swatches
            for (final cVal in palette)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _controller.setColor(cVal);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: currentColor == cVal ? 26 : 22,
                  height: currentColor == cVal ? 26 : 22,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: Color(cVal),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: currentColor == cVal
                          ? primaryColor
                          : Colors.black.withValues(alpha: 0.25),
                      width: currentColor == cVal ? 2.5 : 1.0,
                    ),
                    boxShadow: currentColor == cVal
                        ? [
                            BoxShadow(
                              color: Color(cVal).withValues(alpha: 0.45),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),

            // Stroke thickness selector (when not sticky)
            if (!isStickyContext) ...[
              Container(
                width: 1,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: p.borderSubtle,
              ),
              for (final w in const [2.5, 4.5, 8.0, 14.0])
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _controller.setStrokeWidth(w);
                  },
                  child: Container(
                    width: 28,
                    height: 26,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: ((selected?.strokeWidth ??
                                          _controller.activeStrokeWidth) -
                                      w)
                                  .abs() <
                              1.2
                          ? primaryColor.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: (w * 1.1).clamp(4.0, 16.0),
                      height: (w * 1.1).clamp(4.0, 16.0),
                      decoration: BoxDecoration(
                        color: p.textPrimary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],

            // Selected Element Actions (Edit Text / Delete)
            if (selected != null) ...[
              Container(
                width: 1,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: p.borderSubtle,
              ),
              if (selected.isSticky || selected.isText || selected.isShape)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _promptEditElementText(selected),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_note_rounded,
                          size: 17,
                          color: primaryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Текст',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _controller.deleteElement(selected.id);
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        size: 17,
                        color: Colors.redAccent,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Удалить',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomToolDock(
    BuildContext context, {
    required TheavPalette p,
    required Color primaryColor,
    required bool useGlass,
  }) {
    final tools = <({
      WhiteboardTool tool,
      IconData icon,
      String label,
    })>[
      (
        tool: WhiteboardTool.pan,
        icon: Icons.pan_tool_alt_rounded,
        label: 'Рука',
      ),
      (
        tool: WhiteboardTool.select,
        icon: Icons.near_me_rounded,
        label: 'Выбор',
      ),
      (
        tool: WhiteboardTool.pen,
        icon: Icons.edit_rounded,
        label: 'Перо',
      ),
      (
        tool: WhiteboardTool.highlighter,
        icon: Icons.brush_rounded,
        label: 'Маркер',
      ),
      (
        tool: WhiteboardTool.laser,
        icon: Icons.flare_rounded,
        label: 'Лазер',
      ),
      (
        tool: WhiteboardTool.sticky,
        icon: Icons.sticky_note_2_rounded,
        label: 'Стикер',
      ),
      (
        tool: WhiteboardTool.rectangle,
        icon: Icons.crop_square_rounded,
        label: 'Блок',
      ),
      (
        tool: WhiteboardTool.ellipse,
        icon: Icons.circle_outlined,
        label: 'Круг',
      ),
      (
        tool: WhiteboardTool.diamond,
        icon: Icons.diamond_outlined,
        label: 'Ромб',
      ),
      (
        tool: WhiteboardTool.arrow,
        icon: Icons.trending_flat_rounded,
        label: 'Стрелка',
      ),
      (
        tool: WhiteboardTool.text,
        icon: Icons.title_rounded,
        label: 'Текст',
      ),
      (
        tool: WhiteboardTool.eraser,
        icon: Icons.auto_fix_normal_rounded,
        label: 'Ластик',
      ),
    ];

    return _wrapGlassPill(
      context: context,
      p: p,
      useGlass: useGlass,
      radius: 20,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: tools.map((item) {
            final isSelected = _controller.activeTool == item.tool;
            final isLaser = item.tool == WhiteboardTool.laser;
            final activeColor =
                isLaser ? Colors.redAccent : primaryColor;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tooltip(
                message: item.label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _controller.setTool(item.tool);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? activeColor.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: isSelected
                            ? activeColor.withValues(alpha: 0.7)
                            : Colors.transparent,
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          size: 19,
                          color: isSelected ? activeColor : p.textSecondary,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? activeColor : p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// High-performance CustomPainter for the Miro-style infinite whiteboard canvas.
class _WhiteboardScenePainter extends CustomPainter {
  final List<WhiteboardElement> elements;
  final WhiteboardElement? draftElement;
  final String? selectedElementId;
  final Map<String, WhiteboardRemoteCursor> remoteCursors;
  final List<LaserTrailPoint> localLaserTrail;
  final WhiteboardGridStyle gridStyle;
  final bool isDark;
  final Color primaryColor;

  _WhiteboardScenePainter({
    required this.elements,
    required this.draftElement,
    required this.selectedElementId,
    required this.remoteCursors,
    required this.localLaserTrail,
    required this.gridStyle,
    required this.isDark,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);

    for (final elem in elements) {
      _paintElement(canvas, elem, isSelected: elem.id == selectedElementId);
    }

    if (draftElement != null) {
      _paintElement(canvas, draftElement!, isSelected: false);
    }

    // Paint Local & Remote Laser Trails
    _paintLaserTrail(canvas, localLaserTrail, const Color(0xFFFF1744));
    for (final cursor in remoteCursors.values) {
      if (cursor.laserTrail.isNotEmpty) {
        _paintLaserTrail(canvas, cursor.laserTrail, cursor.color);
      }
      _paintRemoteCursor(canvas, cursor);
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    if (gridStyle == WhiteboardGridStyle.none) return;

    const double step = 40.0;
    final gridColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    if (gridStyle == WhiteboardGridStyle.lines) {
      final paint = Paint()
        ..color = gridColor
        ..strokeWidth = 1.0;
      for (double x = 0; x <= size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (double y = 0; y <= size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    } else {
      // Miro Dot Matrix
      final paint = Paint()
        ..color = isDark
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.black.withValues(alpha: 0.14)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      final points = <Offset>[];
      for (double x = step; x < size.width; x += step) {
        for (double y = step; y < size.height; y += step) {
          points.add(Offset(x, y));
        }
      }
      canvas.drawPoints(ui.PointMode.points, points, paint);
    }
  }

  void _paintElement(
    Canvas canvas,
    WhiteboardElement elem, {
    required bool isSelected,
  }) {
    switch (elem.type) {
      case 'stroke':
      case 'highlighter':
        _paintStroke(canvas, elem);
        break;
      case 'sticky':
        _paintStickyNote(canvas, elem);
        break;
      case 'rectangle':
      case 'ellipse':
      case 'diamond':
        _paintShape(canvas, elem);
        break;
      case 'arrow':
        _paintArrow(canvas, elem);
        break;
      case 'text':
        _paintTextBox(canvas, elem);
        break;
    }

    if (isSelected) {
      _paintSelectionBox(canvas, elem.bounds);
    }
  }

  void _paintStroke(Canvas canvas, WhiteboardElement elem) {
    final pts = elem.points;
    if (pts.isEmpty) return;

    final isHighlighter = elem.type == 'highlighter';
    final paint = Paint()
      ..color = isHighlighter
          ? elem.color.withValues(alpha: 0.36)
          : elem.color
      ..strokeWidth = elem.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (pts.length == 1) {
      canvas.drawCircle(
        pts.first,
        elem.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length - 1; i++) {
      final mid = Offset(
        (pts[i].dx + pts[i + 1].dx) / 2,
        (pts[i].dy + pts[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(path, paint);
  }

  void _paintStickyNote(Canvas canvas, WhiteboardElement elem) {
    final rect = elem.bounds;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));

    // Soft Miro card shadow
    canvas.drawShadow(
      Path()..addRRect(rrect),
      Colors.black.withValues(alpha: 0.35),
      10.0,
      true,
    );

    final fillPaint = Paint()
      ..color = elem.color
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, fillPaint);

    // Subtle top accent band
    final topBandRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(rect.left, rect.top, rect.width, 26),
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
    );
    canvas.drawRRect(
      topBandRect,
      Paint()..color = Colors.black.withValues(alpha: 0.06),
    );

    // Author label in top band
    final authorTp = TextPainter(
      text: TextSpan(
        text: elem.authorName,
        style: TextStyle(
          color: Colors.black.withValues(alpha: 0.55),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width - 20);
    authorTp.paint(canvas, Offset(rect.left + 10, rect.top + 6));

    // Main note text
    if (elem.text.isNotEmpty) {
      final bodyTp = TextPainter(
        text: TextSpan(
          text: elem.text,
          style: const TextStyle(
            color: Color(0xFF1A1E29),
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 7,
        ellipsis: '…',
      )..layout(maxWidth: rect.width - 24);
      bodyTp.paint(canvas, Offset(rect.left + 12, rect.top + 34));
    }
  }

  void _paintShape(Canvas canvas, WhiteboardElement elem) {
    final rect = elem.bounds;
    final fillPaint = Paint()
      ..color = elem.color.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = elem.color
      ..strokeWidth = elem.strokeWidth
      ..style = PaintingStyle.stroke;

    if (elem.type == 'rectangle') {
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect, borderPaint);
    } else if (elem.type == 'ellipse') {
      canvas.drawOval(rect, fillPaint);
      canvas.drawOval(rect, borderPaint);
    } else if (elem.type == 'diamond') {
      final path = Path()
        ..moveTo(rect.center.dx, rect.top)
        ..lineTo(rect.right, rect.center.dy)
        ..lineTo(rect.center.dx, rect.bottom)
        ..lineTo(rect.left, rect.center.dy)
        ..close();
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, borderPaint);
    }

    if (elem.text.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: elem.text,
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1A1E29),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 4,
      )..layout(maxWidth: math.max(40, rect.width - 16));
      tp.paint(
        canvas,
        Offset(
          rect.center.dx - tp.width / 2,
          rect.center.dy - tp.height / 2,
        ),
      );
    }
  }

  void _paintArrow(Canvas canvas, WhiteboardElement elem) {
    final start = Offset(elem.x, elem.y);
    final end = Offset(elem.x + elem.width, elem.y + elem.height);
    final paint = Paint()
      ..color = elem.color
      ..strokeWidth = elem.strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(start, end, paint);

    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final headLength = (elem.strokeWidth * 3.2).clamp(12.0, 26.0);
    const headAngle = 0.48;

    final p1 = Offset(
      end.dx - headLength * math.cos(angle - headAngle),
      end.dy - headLength * math.sin(angle - headAngle),
    );
    final p2 = Offset(
      end.dx - headLength * math.cos(angle + headAngle),
      end.dy - headLength * math.sin(angle + headAngle),
    );

    final headPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(
      headPath,
      Paint()
        ..color = elem.color
        ..style = PaintingStyle.fill,
    );
  }

  void _paintTextBox(Canvas canvas, WhiteboardElement elem) {
    final tp = TextPainter(
      text: TextSpan(
        text: elem.text.isEmpty ? 'Текст' : elem.text,
        style: TextStyle(
          color: elem.color,
          fontSize: (14.0 + elem.strokeWidth * 1.5).clamp(16.0, 42.0),
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 420);
    tp.paint(canvas, Offset(elem.x, elem.y));
  }

  void _paintSelectionBox(Canvas canvas, Rect bounds) {
    final inflated = bounds.inflate(6);
    final borderPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(inflated, const Radius.circular(8)),
      borderPaint,
    );

    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final handleStroke = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (final corner in [
      inflated.topLeft,
      inflated.topRight,
      inflated.bottomLeft,
      inflated.bottomRight,
    ]) {
      canvas.drawCircle(corner, 5.0, handlePaint);
      canvas.drawCircle(corner, 5.0, handleStroke);
    }
  }

  void _paintLaserTrail(
    Canvas canvas,
    List<LaserTrailPoint> trail,
    Color laserColor,
  ) {
    if (trail.length < 2) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < trail.length - 1; i++) {
      final age = (now - trail[i + 1].timestampMs).clamp(0, 850);
      final alpha = (1.0 - age / 850.0).clamp(0.0, 1.0);
      if (alpha <= 0.02) continue;

      final glowPaint = Paint()
        ..color = laserColor.withValues(alpha: alpha * 0.55)
        ..strokeWidth = 10.0 * alpha
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawLine(trail[i].point, trail[i + 1].point, glowPaint);

      final corePaint = Paint()
        ..color = Colors.white.withValues(alpha: alpha * 0.95)
        ..strokeWidth = 3.2 * alpha
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(trail[i].point, trail[i + 1].point, corePaint);
    }
  }

  void _paintRemoteCursor(Canvas canvas, WhiteboardRemoteCursor cursor) {
    final pos = cursor.position;
    final c = cursor.color;

    if (cursor.isLaser) {
      // Glowing laser dot
      canvas.drawCircle(
        pos,
        9,
        Paint()
          ..color = c.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(pos, 4.5, Paint()..color = Colors.white);
    } else {
      // Vector Miro Cursor Arrow
      final cursorPath = Path()
        ..moveTo(pos.dx, pos.dy)
        ..lineTo(pos.dx + 5, pos.dy + 16)
        ..lineTo(pos.dx + 9, pos.dy + 11)
        ..lineTo(pos.dx + 16, pos.dy + 9)
        ..close();
      canvas.drawPath(cursorPath, Paint()..color = c);
      canvas.drawPath(
        cursorPath,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
    }

    // Participant Name Pill
    final tp = TextPainter(
      text: TextSpan(
        text: cursor.userName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 140);

    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        pos.dx + 12,
        pos.dy + 14,
        tp.width + 12,
        tp.height + 6,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(pillRect, Paint()..color = c);
    tp.paint(canvas, Offset(pos.dx + 18, pos.dy + 17));
  }

  @override
  bool shouldRepaint(covariant _WhiteboardScenePainter oldDelegate) => true;
}
