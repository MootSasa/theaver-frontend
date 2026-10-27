import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../services/chat_service.dart';
import '../../services/chat_swipe_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/haptic_utils.dart';

/// A swipeable chat item wrapper that tracks the user's finger in real time,
/// limits movement to a bounded distance (never sliding across the entire screen),
/// requires a minimum drag threshold to trigger the configured swipe action,
/// and springs back smoothly on finger release.
/// Also supports dragging a chat into the right tiling workspace on wide screens.
class SwipeableChatTile extends StatefulWidget {
  final Widget child;
  final Chat chat;
  final Future<void> Function(ChatSwipeAction action) onAction;
  final DraggingChatPayload Function(Rect initialRect, Offset globalPosition)?
      onCreateDragPayload;
  final GestureTapUpCallback? onSecondaryTapUp;
  final bool enabled;

  const SwipeableChatTile({
    super.key,
    required this.child,
    required this.chat,
    required this.onAction,
    this.onCreateDragPayload,
    this.onSecondaryTapUp,
    this.enabled = true,
  });

  @override
  State<SwipeableChatTile> createState() => _SwipeableChatTileState();
}

class _SwipeableChatTileState extends State<SwipeableChatTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Animation<double>? _animation;
  double _dragOffset = 0.0;
  double _rawDragOffset = 0.0;
  bool _thresholdCrossed = false;
  bool _isWorkspaceDrag = false;
  PointerDeviceKind? _lastPointerKind;

  /// Minimum threshold in logical pixels required to trigger the swipe action.
  /// If released below this threshold, the tile simply snaps back without executing the action.
  static const double _threshold = 84.0;

  /// Free 1:1 finger tracking distance before soft rubber-band resistance starts.
  static const double _freeDragDistance = 180.0;

  /// Maximum allowed displacement of the tile so it does not slide offscreen.
  static const double _maxDrag = 240.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        if (mounted && _animation != null) {
          setState(() {
            _dragOffset = _animation!.value;
          });
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateBack({double from = 0.0}) {
    _rawDragOffset = 0.0;
    _thresholdCrossed = false;
    if (from == 0.0) {
      if (_dragOffset != 0.0 && mounted) {
        setState(() {
          _dragOffset = 0.0;
        });
      }
      return;
    }
    _animation = Tween<double>(begin: from, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward(from: 0.0);
  }

  bool _canDragToWorkspace() {
    if (widget.onCreateDragPayload == null) return false;
    final tiling = TilingLayoutController.instance;
    return tiling.isWorkspaceMounted &&
        tiling.windowSize.width >= TilingLayoutController.kTwoColumnBreakpoint;
  }

  void _promoteToWorkspaceDrag(Offset globalPosition, Offset delta) {
    final createPayload = widget.onCreateDragPayload;
    if (createPayload == null) return;

    Rect initialRect = Rect.fromCenter(
      center: globalPosition,
      width: 320,
      height: 72,
    );
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final topLeft = renderBox.localToGlobal(Offset.zero);
      initialRect = topLeft & renderBox.size;
    }

    _isWorkspaceDrag = true;
    _animateBack(from: _dragOffset);
    HapticUtils.selection();

    final payload = createPayload(initialRect, globalPosition);
    TilingLayoutController.instance.startDraggingChat(payload);
    TilingLayoutController.instance.updateDraggingChat(
      globalPosition,
      velocity: delta,
    );
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _controller.stop();
    _rawDragOffset = _dragOffset;
    _thresholdCrossed = _dragOffset.abs() >= _threshold;
    _isWorkspaceDrag = false;
    _lastPointerKind = details.kind;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;

    if (_isWorkspaceDrag) {
      TilingLayoutController.instance.updateDraggingChat(
        details.globalPosition,
        velocity: details.delta,
      );
      return;
    }

    final delta = details.primaryDelta ?? 0.0;
    _rawDragOffset += delta;

    // On wide desktop screens, dragging a chat item rightward with a mouse or
    // dragging it across the right boundary of the left tile detaches it into a workspace tile drag.
    if (_canDragToWorkspace() && _rawDragOffset > 0) {
      final tiling = TilingLayoutController.instance;
      final isMouseDragRight =
          _lastPointerKind == PointerDeviceKind.mouse && _rawDragOffset > 20.0;
      final crossedTileBoundary =
          details.globalPosition.dx >= tiling.leftTileWidth - 28.0 &&
              _rawDragOffset > 16.0;
      if (isMouseDragRight || crossedTileBoundary) {
        _promoteToWorkspaceDrag(details.globalPosition, details.delta);
        return;
      }
    }

    final sign = _rawDragOffset >= 0 ? 1.0 : -1.0;
    final abs = _rawDragOffset.abs();

    // 1:1 displacement with finger up to _freeDragDistance,
    // followed by soft rubber-band resistance up to _maxDrag
    final double effectiveOffset;
    if (abs <= _freeDragDistance) {
      effectiveOffset = abs;
    } else {
      effectiveOffset = _freeDragDistance + (abs - _freeDragDistance) * 0.35;
    }
    final clamped = effectiveOffset.clamp(0.0, _maxDrag);

    setState(() {
      _dragOffset = sign * clamped;
    });

    final isCrossed = _dragOffset.abs() >= _threshold;
    if (isCrossed && !_thresholdCrossed) {
      _thresholdCrossed = true;
      HapticUtils.selection();
    } else if (!isCrossed && _thresholdCrossed) {
      _thresholdCrossed = false;
      HapticUtils.selection();
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!widget.enabled) return;
    if (_isWorkspaceDrag) {
      _isWorkspaceDrag = false;
      TilingLayoutController.instance.endDraggingChat();
      return;
    }
    final bool shouldTrigger = _dragOffset.abs() >= _threshold;
    final fromOffset = _dragOffset;
    _animateBack(from: fromOffset);

    if (shouldTrigger) {
      HapticUtils.impact();
      final action = ChatSwipeService().action;
      widget.onAction(action);
    }
  }

  void _onHorizontalDragCancel() {
    if (!widget.enabled) return;
    if (_isWorkspaceDrag) {
      _isWorkspaceDrag = false;
      TilingLayoutController.instance.cancelDraggingChat();
      return;
    }
    _animateBack(from: _dragOffset);
  }

  Widget _buildActionIcon(ChatSwipeAction action, Color color, double size) {
    switch (action) {
      case ChatSwipeAction.pin:
        return widget.chat.isPinned
            ? iconoir.PinSlash(color: color, width: size, height: size)
            : iconoir.Pin(color: color, width: size, height: size);
      case ChatSwipeAction.read:
        return widget.chat.hasUnread
            ? iconoir.Check(color: color, width: size, height: size)
            : iconoir.ChatBubble(color: color, width: size, height: size);
      case ChatSwipeAction.archive:
        return iconoir.Archive(color: color, width: size, height: size);
      case ChatSwipeAction.mute:
        return iconoir.BellOff(color: color, width: size, height: size);
      case ChatSwipeAction.delete:
        return iconoir.Trash(color: color, width: size, height: size);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    final action = ChatSwipeService().action;
    final isDragging = _dragOffset != 0.0;
    final isRight = _dragOffset > 0;
    final progress = (_dragOffset.abs() / _threshold).clamp(0.0, 1.0);
    final isCrossed = _dragOffset.abs() >= _threshold;

    final String actionLabel = action == ChatSwipeAction.read
        ? (widget.chat.hasUnread ? 'Прочитать' : 'Не прочитано')
        : (action == ChatSwipeAction.pin
            ? (widget.chat.isPinned ? 'Открепить' : 'Закрепить')
            : action.label);

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Background action badge
        if (isDragging)
          Positioned.fill(
            child: Container(
              color: action.color,
              alignment: isRight ? Alignment.centerLeft : Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: AnimatedScale(
                scale: isCrossed ? 1.12 : (0.75 + 0.25 * progress),
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutBack,
                child: Opacity(
                  opacity: (0.35 + 0.65 * progress).clamp(0.0, 1.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: isRight
                        ? [
                            _buildActionIcon(action, Colors.white, 24),
                            const SizedBox(width: 10),
                            Text(
                              actionLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ]
                        : [
                            Text(
                              actionLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _buildActionIcon(action, Colors.white, 24),
                          ],
                  ),
                ),
              ),
            ),
          ),

        // Foreground tile moving with finger
        GestureDetector(
          onSecondaryTapUp: widget.onSecondaryTapUp,
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          onHorizontalDragCancel: _onHorizontalDragCancel,
          behavior: HitTestBehavior.opaque,
          child: Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}
