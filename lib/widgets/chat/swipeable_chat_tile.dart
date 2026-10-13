import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../services/chat_service.dart';
import '../../services/chat_swipe_service.dart';
import '../../utils/haptic_utils.dart';

/// A swipeable chat item wrapper that tracks the user's finger in real time,
/// limits movement to a bounded distance (never sliding across the entire screen),
/// requires a minimum drag threshold to trigger the configured swipe action,
/// and springs back smoothly on finger release.
class SwipeableChatTile extends StatefulWidget {
  final Widget child;
  final Chat chat;
  final Future<void> Function(ChatSwipeAction action) onAction;
  final bool enabled;

  const SwipeableChatTile({
    super.key,
    required this.child,
    required this.chat,
    required this.onAction,
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
  bool _thresholdCrossed = false;

  static const double _threshold = 64.0;
  static const double _maxDrag = 110.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (_animation != null) {
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
    _animation = Tween<double>(begin: from, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward(from: 0.0);
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _controller.stop();
    _thresholdCrossed = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    final delta = details.primaryDelta ?? 0.0;
    final current = _dragOffset + delta;
    final sign = current >= 0 ? 1.0 : -1.0;
    final abs = current.abs();

    // 1:1 displacement up to threshold, followed by soft rubber-band resistance
    final damped = abs <= 64.0 ? abs : (64.0 + (abs - 64.0) * 0.35);
    final clamped = damped > _maxDrag ? _maxDrag : damped;

    setState(() {
      _dragOffset = sign * clamped;
    });

    if (_dragOffset.abs() >= _threshold && !_thresholdCrossed) {
      _thresholdCrossed = true;
      HapticUtils.selection();
    } else if (_dragOffset.abs() < _threshold && _thresholdCrossed) {
      _thresholdCrossed = false;
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!widget.enabled) return;
    final bool shouldTrigger = _dragOffset.abs() >= _threshold;
    final fromOffset = _dragOffset;
    _animateBack(from: fromOffset);

    if (shouldTrigger) {
      HapticUtils.selection();
      final action = ChatSwipeService().action;
      widget.onAction(action);
    }
  }

  void _onHorizontalDragCancel() {
    if (!widget.enabled) return;
    _animateBack(from: _dragOffset);
  }

  Widget _buildActionIcon(ChatSwipeAction action, Color color, double size) {
    switch (action) {
      case ChatSwipeAction.pin:
        return iconoir.Pin(color: color, width: size, height: size);
      case ChatSwipeAction.read:
        return iconoir.ChatBubble(color: color, width: size, height: size);
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

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Background action badge
        if (isDragging)
          Positioned.fill(
            child: Container(
              color: action.color,
              alignment: isRight ? Alignment.centerLeft : Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AnimatedScale(
                scale: isCrossed ? 1.15 : (0.7 + 0.3 * progress),
                duration: const Duration(milliseconds: 100),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: isRight
                      ? [
                          _buildActionIcon(action, Colors.white, 22),
                          const SizedBox(width: 8),
                          Text(
                            action.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ]
                      : [
                          Text(
                            action.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildActionIcon(action, Colors.white, 22),
                        ],
                ),
              ),
            ),
          ),

        // Foreground tile moving with finger
        GestureDetector(
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          onHorizontalDragCancel: _onHorizontalDragCancel,
          behavior: HitTestBehavior.translucent,
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
