import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../utils/haptic_utils.dart';

/// A wrapper widget that enables swipe-to-reply gesture on a message row.
/// Swipe LEFT (drag from right to left) to reply, similar to some messaging apps.
/// The wrapper takes the full width of the screen so the swipe works
/// across the entire row, not just on the message bubble.
///
/// Uses RawGestureDetector with a custom recognizer to ensure it ONLY
/// captures leftward swipes, allowing the global rightward swipe-back gesture to work.
class SwipeToReplyWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onReply;
  final bool enabled;

  /// Minimum horizontal drag distance to activate reply (in logical pixels)
  final double activationThreshold;

  /// Maximum drag distance (the message won't move further)
  final double maxDragDistance;

  const SwipeToReplyWrapper({
    Key? key,
    required this.child,
    this.onReply,
    this.enabled = true,
    this.activationThreshold = 60.0,
    this.maxDragDistance = 80.0,
  }) : super(key: key);

  @override
  State<SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<SwipeToReplyWrapper>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0.0; // Negative = leftward
  bool _hasActivated = false;

  late final AnimationController _bounceController;
  late final Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bounceAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _bounceController,
        curve: Curves.easeOutBack,
      ),
    );
    _bounceController.addListener(() {
      if (mounted) {
        setState(() {
          final startOffset = _hasActivated ? -widget.maxDragDistance : _dragOffset;
          _dragOffset = _bounceAnimation.value * startOffset;
        });
      }
    });
    _bounceController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _hasActivated = false;
        _dragOffset = 0.0;
      }
    });
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  // Clamp offset to leftward range [−maxDrag, 0]
  double get _clampedOffset =>
      _dragOffset.clamp(-widget.maxDragDistance, 0.0);

  // Progress: 0 at rest, 1 at activation threshold
  double get _progress =>
      (-_clampedOffset / widget.activationThreshold).clamp(0.0, 1.0);

  bool get _isActivated => -_clampedOffset >= widget.activationThreshold;

  void _onHorizontalDragStart(DragStartDetails details) {
    _bounceController.stop();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      // Only allow leftward drag (negative delta)
      if (details.delta.dx < 0) {
        _dragOffset += details.delta.dx * 0.8; // damping factor
      } else {
        // Allow small rightward movement to return
        _dragOffset += details.delta.dx;
      }
      _dragOffset = _dragOffset.clamp(-widget.maxDragDistance, 0.0);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_isActivated) {
      HapticUtils.impact();
      _hasActivated = true;
      widget.onReply!();
    }
    // Bounce back with spring animation
    _bounceController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.onReply == null) {
      return widget.child;
    }

    final theme = Theme.of(context);

    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _ReplyGestureRecognizer: GestureRecognizerFactoryWithHandlers<_ReplyGestureRecognizer>(
          () => _ReplyGestureRecognizer(),
          (_ReplyGestureRecognizer instance) {
            instance.onStart = _onHorizontalDragStart;
            instance.onUpdate = _onHorizontalDragUpdate;
            instance.onEnd = _onHorizontalDragEnd;
          },
        ),
      },
      behavior: HitTestBehavior.translucent,
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Reply icon on the right side (appears when swiping left)
            if (-_clampedOffset > 5)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Opacity(
                      opacity: _progress,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: iconoir.Reply(
                          width: 20,
                          height: 20,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // The message itself, shifted left
            Transform.translate(
              offset: Offset(_clampedOffset, 0),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom recognizer that ONLY accepts leftward swipes.
class _ReplyGestureRecognizer extends HorizontalDragGestureRecognizer {
  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      final double dx = event.delta.dx;
      final double dy = event.delta.dy;
      
      // Only activate if moving LEFT (dx < 0) AND horizontal movement dominates vertical (dx < -abs(dy)*2)
      // This prevents accidental reply activation during vertical scrolling.
      if (dx < -0.1 && dx.abs() > dy.abs() * 2) {
        resolve(GestureDisposition.accepted);
      } else if (dx > 0.1 || dy.abs() > dx.abs() * 0.5) {
        // If moving right, or vertical movement is significant, reject
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }
    }
    super.handleEvent(event);
  }
}

