import 'dart:async';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// A widget that detects when a message becomes visible on screen
/// and triggers a callback. Used for marking messages as read
/// when the user actually sees them.
///
/// The message is considered "seen" when it's at least [visibilityThreshold]
/// visible for [visibleDuration] continuous milliseconds.
class VisibleMessageDetector extends StatefulWidget {
  final String messageId;
  final Widget child;
  final VoidCallback onMessageSeen;
  final double visibilityThreshold;
  final Duration visibleDuration;

  const VisibleMessageDetector({
    Key? key,
    required this.messageId,
    required this.child,
    required this.onMessageSeen,
    this.visibilityThreshold = 0.5,
    this.visibleDuration = const Duration(milliseconds: 500),
  }) : super(key: key);

  @override
  State<VisibleMessageDetector> createState() => _VisibleMessageDetectorState();
}

class _VisibleMessageDetectorState extends State<VisibleMessageDetector> {
  bool _hasBeenSeen = false;
  Timer? _visibleTimer;

  @override
  void didUpdateWidget(covariant VisibleMessageDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId != widget.messageId) {
      _visibleTimer?.cancel();
      _visibleTimer = null;
      _hasBeenSeen = false;
    }
  }

  @override
  void dispose() {
    _visibleTimer?.cancel();
    _visibleTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasBeenSeen) {
      // Already seen, no need to track anymore
      return widget.child;
    }

    return VisibilityDetector(
      key: Key('msg_visibility_${widget.messageId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: widget.child,
    );
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (_hasBeenSeen || !mounted) return;

    final visibleFraction = info.visibleFraction;

    if (visibleFraction >= widget.visibilityThreshold) {
      if (widget.visibleDuration == Duration.zero) {
        _hasBeenSeen = true;
        _visibleTimer?.cancel();
        _visibleTimer = null;
        widget.onMessageSeen();
        return;
      }

      // Start timer if not already active
      _visibleTimer ??= Timer(widget.visibleDuration, () {
        if (!mounted || _hasBeenSeen) return;
        setState(() {
          _hasBeenSeen = true;
        });
        _visibleTimer = null;
        widget.onMessageSeen();
      });
    } else {
      // Message is no longer sufficiently visible — cancel timer
      _visibleTimer?.cancel();
      _visibleTimer = null;
    }
  }
}
