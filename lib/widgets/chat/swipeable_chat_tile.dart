import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../services/chat_service.dart';
import '../../services/chat_swipe_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';

/// A swipeable chat item wrapper that tracks the user's finger in real time,
/// limits movement to a bounded distance (never sliding across the entire screen),
/// requires a minimum drag threshold to trigger the configured swipe action,
/// and springs back smoothly on finger release.
/// Also supports dragging a chat into the right tiling workspace on wide screens.
class SwipeableChatTile extends StatefulWidget {
  final Widget child;
  final Chat chat;
  final Future<void> Function(ChatSwipeAction action) onAction;
  final Future<void> Function(ChatSwipeAction action)? onRightSwipe;
  final ChatSwipeAction? rightSwipeAction;
  final DraggingChatPayload Function(Rect initialRect, Offset globalPosition)?
      onCreateDragPayload;
  final GestureTapUpCallback? onSecondaryTapUp;
  final bool enabled;
  final ChatSwipeAction? overrideAction;

  const SwipeableChatTile({
    super.key,
    required this.child,
    required this.chat,
    required this.onAction,
    this.onRightSwipe,
    this.rightSwipeAction,
    this.onCreateDragPayload,
    this.onSecondaryTapUp,
    this.enabled = true,
    this.overrideAction,
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

  bool _hasAncestorRouteSwipeBack() {
    if (!mounted) return false;
    return hasActiveSwipeBackAncestor(context);
  }

  bool _canSwipeRight() =>
      widget.onRightSwipe != null || !_hasAncestorRouteSwipeBack();

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
    final canWorkspaceDrag = _canDragToWorkspace();
    if (canWorkspaceDrag && _rawDragOffset > 0) {
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

    if (!_canSwipeRight() &&
        (!canWorkspaceDrag || _hasAncestorRouteSwipeBack()) &&
        _rawDragOffset > 0.0) {
      _rawDragOffset = 0.0;
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
      final defaultAction = widget.overrideAction ?? ChatSwipeService().action;
      if (fromOffset > 0) {
        final handler = widget.onRightSwipe ?? widget.onAction;
        HapticUtils.impact();
        handler(widget.rightSwipeAction ?? defaultAction);
      } else {
        HapticUtils.impact();
        widget.onAction(defaultAction);
      }
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
        return widget.chat.isArchived
            ? Icon(Icons.unarchive_outlined, color: color, size: size)
            : iconoir.Archive(color: color, width: size, height: size);
      case ChatSwipeAction.mute:
        return iconoir.BellOff(color: color, width: size, height: size);
      case ChatSwipeAction.delete:
        return iconoir.Trash(color: color, width: size, height: size);
    }
  }

  String _resolveActionLabel(ChatSwipeAction action) {
    if (action == ChatSwipeAction.read) {
      return widget.chat.hasUnread ? 'Прочитать' : 'Не прочитано';
    }
    if (action == ChatSwipeAction.pin) {
      return widget.chat.isPinned ? 'Открепить' : 'Закрепить';
    }
    if (action == ChatSwipeAction.archive) {
      return widget.chat.isArchived ? 'Разархивировать' : action.label;
    }
    return action.label;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    final leftAction = widget.overrideAction ?? ChatSwipeService().action;
    final isDragging = _dragOffset != 0.0;
    final isRight = _dragOffset > 0;
    final activeAction =
        isRight ? (widget.rightSwipeAction ?? leftAction) : leftAction;
    final progress = (_dragOffset.abs() / _threshold).clamp(0.0, 1.0);
    final isCrossed = _dragOffset.abs() >= _threshold;
    final String actionLabel = _resolveActionLabel(activeAction);

    Widget content = Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Background action badge
        if (isDragging)
          Positioned.fill(
            child: Container(
              color: activeAction.color,
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
                            _buildActionIcon(activeAction, Colors.white, 24),
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
                            _buildActionIcon(activeAction, Colors.white, 24),
                          ],
                  ),
                ),
              ),
            ),
          ),

        // Foreground tile moving with finger
        RawGestureDetector(
          gestures: <Type, GestureRecognizerFactory>{
            _ChatTileHorizontalDragRecognizer:
                GestureRecognizerFactoryWithHandlers<
                    _ChatTileHorizontalDragRecognizer>(
              () => _ChatTileHorizontalDragRecognizer(
                canSwipeRightGetter: _canSwipeRight,
                canWorkspaceDragGetter: _canDragToWorkspace,
                hasAncestorRouteSwipeBackGetter: _hasAncestorRouteSwipeBack,
              ),
              (_ChatTileHorizontalDragRecognizer instance) {
                instance.canSwipeRightGetter = _canSwipeRight;
                instance.canWorkspaceDragGetter = _canDragToWorkspace;
                instance.hasAncestorRouteSwipeBackGetter =
                    _hasAncestorRouteSwipeBack;
                instance.onStart = _onHorizontalDragStart;
                instance.onUpdate = _onHorizontalDragUpdate;
                instance.onEnd = _onHorizontalDragEnd;
                instance.onCancel = _onHorizontalDragCancel;
              },
            ),
          },
          behavior: HitTestBehavior.opaque,
          child: GestureDetector(
            onSecondaryTapUp: widget.onSecondaryTapUp,
            behavior: HitTestBehavior.translucent,
            child: Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: widget.child,
              ),
            ),
          ),
        ),
      ],
    );

    if (widget.onRightSwipe != null) {
      content = SwipeBackBlocker(child: content);
    }

    return content;
  }
}

/// Directional horizontal drag recognizer for chat list rows:
/// - Always accepts leftward swipes (`dx < 0`) for row actions (read, pin, archive, etc.).
/// - Only claims rightward touch swipes (`dx > 0`) when [canSwipeRightGetter] is `true`
///   (or when detaching a chat into a desktop multi-pane workspace with no poppable route),
///   yielding cleanly to route/tab rightward swipe-back everywhere else.
class _ChatTileHorizontalDragRecognizer
    extends HorizontalDragGestureRecognizer {
  bool Function() canSwipeRightGetter;
  bool Function() canWorkspaceDragGetter;
  bool Function() hasAncestorRouteSwipeBackGetter;

  int? _trackedPointer;
  Offset _downGlobalPos = Offset.zero;
  double _cumDx = 0.0;
  double _cumDy = 0.0;
  bool _gestureAccepted = false;

  _ChatTileHorizontalDragRecognizer({
    required this.canSwipeRightGetter,
    required this.canWorkspaceDragGetter,
    required this.hasAncestorRouteSwipeBackGetter,
  }) {
    onlyAcceptDragOnThreshold = true;
  }

  bool _allowRightwardForKind(PointerDeviceKind kind) {
    if (canSwipeRightGetter()) return true;
    if (canWorkspaceDragGetter()) {
      if (kind == PointerDeviceKind.mouse) return true;
      if (!hasAncestorRouteSwipeBackGetter()) return true;
    }
    return false;
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _trackedPointer = event.pointer;
    _downGlobalPos = event.position;
    _cumDx = 0.0;
    _cumDy = 0.0;
    _gestureAccepted = false;
    super.addAllowedPointer(event);
  }

  @override
  void acceptGesture(int pointer) {
    if (pointer == _trackedPointer) {
      _gestureAccepted = true;
    }
    super.acceptGesture(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer == _trackedPointer) {
      _gestureAccepted = false;
      _trackedPointer = null;
    }
    super.rejectGesture(pointer);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    if (_cumDx < 0) {
      return _cumDx <= -10.0 && _cumDx.abs() > _cumDy.abs() * 1.5;
    }
    if (!_allowRightwardForKind(pointerDeviceKind)) {
      return false;
    }
    return _cumDx >= 10.0 && _cumDx > _cumDy.abs() * 1.5;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer == _trackedPointer &&
        !_gestureAccepted &&
        event is PointerMoveEvent) {
      _cumDx = event.position.dx - _downGlobalPos.dx;
      _cumDy = event.position.dy - _downGlobalPos.dy;

      // Reject predominantly vertical scrolling
      if (_cumDy.abs() > 10.0 && _cumDy.abs() > _cumDx.abs()) {
        _trackedPointer = null;
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }

      // Reject rightward swipes when no right-swipe action is configured so
      // ancestor SwipeBackPageRoute / InteractiveSwipeBackGestureDetector wins.
      if (_cumDx > 3.0 && !_allowRightwardForKind(event.kind)) {
        _trackedPointer = null;
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }

      if (_cumDx <= -10.0 && _cumDx.abs() > _cumDy.abs() * 1.5) {
        _gestureAccepted = true;
        resolve(GestureDisposition.accepted);
      } else if (_cumDx >= 10.0 &&
          _cumDx > _cumDy.abs() * 1.5 &&
          _allowRightwardForKind(event.kind)) {
        _gestureAccepted = true;
        resolve(GestureDisposition.accepted);
      }
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (event.pointer == _trackedPointer) {
        _trackedPointer = null;
      }
    }
    super.handleEvent(event);
  }
}
