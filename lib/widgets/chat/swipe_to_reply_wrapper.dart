import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../utils/haptic_utils.dart';
import '../tiling/tile_viewport_scope.dart';

/// Controller interface used by [TrackpadBackGestureWrapper] to drive a
/// [SwipeToReplyWrapper] during a leftward two-finger trackpad gesture.
abstract class TrackpadReplyTarget {
  bool startTrackpadDrag();
  void updateTrackpadDrag(double dx);
  void endTrackpadDrag();
  void cancelTrackpadDrag();
}

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

  static _SwipeToReplyWrapperState? _hoveredState;
  static _SwipeToReplyWrapperState? _activeState;
  static DateTime? _lastReplyGestureEndTime;

  /// True while any message row is actively being dragged for reply.
  static bool get isAnyReplyGestureActive => _activeState != null;

  /// Short cooldown after a reply drag finishes/cancels so a rightward
  /// cancel motion cannot immediately trigger a trackpad Back gesture.
  static bool get isInReplyCooldown {
    final last = _lastReplyGestureEndTime;
    if (last == null) return false;
    return DateTime.now().difference(last) < const Duration(milliseconds: 220);
  }

  /// Resolves the currently hovered [TrackpadReplyTarget] for the given [tileId].
  static TrackpadReplyTarget? resolveHoveredForTile(String? tileId) {
    final hovered = _hoveredState;
    if (hovered == null || !hovered.mounted) return null;
    if (!hovered.widget.enabled || hovered.widget.onReply == null) return null;
    if (tileId != null && hovered._tileId != null && hovered._tileId != tileId) {
      return null;
    }
    return hovered;
  }

  static void _markHovered(_SwipeToReplyWrapperState state) {
    if (state.mounted && state.widget.enabled && state.widget.onReply != null) {
      _hoveredState = state;
    }
  }

  static void _unmarkHovered(_SwipeToReplyWrapperState state) {
    if (_hoveredState == state) {
      _hoveredState = null;
    }
  }

  static void _markActive(_SwipeToReplyWrapperState state) {
    _activeState = state;
  }

  static void _unmarkActive(_SwipeToReplyWrapperState state) {
    if (_activeState == state) {
      _activeState = null;
      _lastReplyGestureEndTime = DateTime.now();
    }
  }

  @override
  State<SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<SwipeToReplyWrapper>
    with SingleTickerProviderStateMixin
    implements TrackpadReplyTarget {
  double _dragOffset = 0.0; // Negative = leftward
  double _bounceStartOffset = 0.0;
  bool _thresholdHapticFired = false;
  String? _tileId;

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
          _dragOffset = _bounceAnimation.value * _bounceStartOffset;
        });
      }
    });
    _bounceController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _dragOffset = 0.0;
        _bounceStartOffset = 0.0;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tileId = TileViewportScope.maybeTileIdOf(context);
  }

  @override
  void dispose() {
    SwipeToReplyWrapper._unmarkHovered(this);
    SwipeToReplyWrapper._unmarkActive(this);
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

  void _applyDeltaDx(double dx) {
    setState(() {
      if (dx < 0) {
        _dragOffset += dx * 0.8; // damping factor when pulling left
      } else {
        // Allow rightward movement to return bubble to 0 and cancel reply
        _dragOffset += dx;
      }
      _dragOffset = _dragOffset.clamp(-widget.maxDragDistance, 0.0);
    });

    final activatedNow = _isActivated;
    if (activatedNow && !_thresholdHapticFired) {
      _thresholdHapticFired = true;
      HapticUtils.selection();
    } else if (!activatedNow && _thresholdHapticFired) {
      _thresholdHapticFired = false;
      HapticUtils.selection();
    }
  }

  void _finishDrag({required bool canceled}) {
    SwipeToReplyWrapper._unmarkActive(this);
    _thresholdHapticFired = false;
    if (!canceled && _isActivated) {
      HapticUtils.impact();
      widget.onReply?.call();
    }
    _bounceStartOffset = _dragOffset;
    _bounceController.forward(from: 0.0);
  }

  @override
  bool startTrackpadDrag() {
    if (!mounted || !widget.enabled || widget.onReply == null) return false;
    _bounceController.stop();
    _thresholdHapticFired = false;
    SwipeToReplyWrapper._markActive(this);
    return true;
  }

  @override
  void updateTrackpadDrag(double dx) {
    if (!mounted || !widget.enabled || widget.onReply == null) return;
    _applyDeltaDx(dx);
  }

  @override
  void endTrackpadDrag() {
    if (!mounted) {
      SwipeToReplyWrapper._unmarkActive(this);
      return;
    }
    _finishDrag(canceled: false);
  }

  @override
  void cancelTrackpadDrag() {
    if (!mounted) {
      SwipeToReplyWrapper._unmarkActive(this);
      return;
    }
    _finishDrag(canceled: true);
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _bounceController.stop();
    _thresholdHapticFired = false;
    SwipeToReplyWrapper._markActive(this);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _applyDeltaDx(details.delta.dx);
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _finishDrag(canceled: false);
  }

  void _onHorizontalDragCancel() {
    _finishDrag(canceled: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.onReply == null) {
      return widget.child;
    }

    final theme = Theme.of(context);

    return MouseRegion(
      opaque: false,
      onEnter: (_) => SwipeToReplyWrapper._markHovered(this),
      onHover: (_) => SwipeToReplyWrapper._markHovered(this),
      onExit: (_) => SwipeToReplyWrapper._unmarkHovered(this),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: (_) => SwipeToReplyWrapper._markHovered(this),
        onPointerMove: (_) => SwipeToReplyWrapper._markHovered(this),
        onPointerDown: (_) => SwipeToReplyWrapper._markHovered(this),
        onPointerSignal: (_) => SwipeToReplyWrapper._markHovered(this),
        onPointerPanZoomStart: (_) => SwipeToReplyWrapper._markHovered(this),
        child: RawGestureDetector(
          gestures: <Type, GestureRecognizerFactory>{
            _ReplyGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<_ReplyGestureRecognizer>(
              () => _ReplyGestureRecognizer(),
              (_ReplyGestureRecognizer instance) {
                instance.onStart = _onHorizontalDragStart;
                instance.onUpdate = _onHorizontalDragUpdate;
                instance.onEnd = _onHorizontalDragEnd;
                instance.onCancel = _onHorizontalDragCancel;
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
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.15),
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
        ),
      ),
    );
  }
}

/// Custom recognizer that ONLY accepts leftward swipes on touch/stylus
/// so mouse LMB dragging on PC/Web can select message text cleanly,
/// while two-finger trackpad gestures are arbitrated by [TrackpadBackGestureWrapper].
class _ReplyGestureRecognizer extends HorizontalDragGestureRecognizer {
  bool _gestureAccepted = false;
  double _cumDx = 0.0;
  double _cumDy = 0.0;

  _ReplyGestureRecognizer()
      : super(
          supportedDevices: const <PointerDeviceKind>{
            PointerDeviceKind.touch,
            PointerDeviceKind.stylus,
            PointerDeviceKind.invertedStylus,
          },
        );

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _gestureAccepted = false;
    _cumDx = 0.0;
    _cumDy = 0.0;
    super.addAllowedPointer(event);
  }

  @override
  void acceptGesture(int pointer) {
    _gestureAccepted = true;
    super.acceptGesture(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    _gestureAccepted = false;
    super.rejectGesture(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    // Only filter direction BEFORE the gesture has been accepted.
    // Once accepted, allow the user to drag back rightward (dx > 0) to cancel the reply.
    if (!_gestureAccepted && event is PointerMoveEvent) {
      _cumDx += event.delta.dx;
      _cumDy += event.delta.dy;

      // Reject immediately if moving right (Back gesture) or predominantly vertical (scroll)
      if (_cumDx > 2.0 || (_cumDy.abs() > 6.0 && _cumDy.abs() > _cumDx.abs())) {
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }

      // Accept only when clearly moving left and horizontal movement dominates vertical
      if (_cumDx < -6.0 && _cumDx.abs() > _cumDy.abs() * 1.8) {
        resolve(GestureDisposition.accepted);
      }
    }
    super.handleEvent(event);
  }
}



