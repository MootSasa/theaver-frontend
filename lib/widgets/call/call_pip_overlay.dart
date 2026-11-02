import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../../services/call_state_provider.dart';

/// Draggable Picture-in-Picture floating mini-window for active video calls
/// and High-FPS screen share streams when minimized.
///
/// Snaps to the nearest screen corner on release and uses geometric [ScaleTransition]
/// for appear/disappear.
class CallPipOverlay extends StatefulWidget {
  final VoidCallback onRestoreCall;

  const CallPipOverlay({
    super.key,
    required this.onRestoreCall,
  });

  @override
  State<CallPipOverlay> createState() => _CallPipOverlayState();
}

class _CallPipOverlayState extends State<CallPipOverlay>
    with SingleTickerProviderStateMixin {
  Offset? _position;
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _scaleAnim = CurvedAnimation(
      parent: _scaleCtrl,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  Size _computePipDimensions({
    required RTCVideoValue? videoValue,
    required bool hasDisplay,
    required bool hasVideo,
    int? streamWidth,
    int? streamHeight,
  }) {
    double aspect = hasDisplay ? (16.0 / 9.0) : (hasVideo ? 0.72 : 1.55);

    if (videoValue != null &&
        videoValue.width > 0 &&
        videoValue.height > 0) {
      final rotated =
          videoValue.rotation == 90 || videoValue.rotation == 270;
      final effW = rotated ? videoValue.height : videoValue.width;
      final effH = rotated ? videoValue.width : videoValue.height;
      if (effW > 0 && effH > 0) {
        aspect = (effW / effH).clamp(0.5, 2.35);
      }
    } else if (hasDisplay &&
        streamWidth != null &&
        streamHeight != null &&
        streamWidth > 0 &&
        streamHeight > 0) {
      aspect = (streamWidth / streamHeight).clamp(0.5, 2.35);
    }

    if (!hasDisplay && !hasVideo) {
      return const Size(172.0, 110.0);
    }

    if (aspect < 0.92) {
      // Portrait video (e.g. vertical smartphone camera 9:16 or 3:4)
      const double height = 172.0;
      final double width = (height * aspect).clamp(100.0, 148.0);
      return Size(width, height);
    } else if (aspect <= 1.15) {
      // Square-ish video
      return const Size(140.0, 140.0);
    } else {
      // Landscape video or screen share (e.g. 16:9 / 16:10 / 4:3)
      const double width = 188.0;
      final double height = (width / aspect).clamp(102.0, 148.0);
      return Size(width, height);
    }
  }

  void _snapToNearestCorner(
    Size screenSize,
    EdgeInsets padding,
    Size pipSize,
  ) {
    final pos = _position;
    if (pos == null) return;
    const minX = 12.0;
    final maxX = (screenSize.width - pipSize.width - 12.0).clamp(minX, 9999.0);
    final minY = padding.top + 64.0;
    final maxY = (screenSize.height - pipSize.height - padding.bottom - 88.0)
        .clamp(minY, 9999.0);

    final targetX =
        (pos.dx + pipSize.width / 2) < screenSize.width / 2 ? minX : maxX;
    final targetY =
        (pos.dy + pipSize.height / 2) < screenSize.height / 2 ? minY : maxY;

    setState(() {
      _position = Offset(targetX, targetY);
    });
  }

  @override
  Widget build(BuildContext context) {
    final callProvider = context.watch<CallStateProvider>();
    final show = callProvider.shouldShowPip;

    if (show &&
        _scaleCtrl.status != AnimationStatus.forward &&
        _scaleCtrl.status != AnimationStatus.completed) {
      _scaleCtrl.forward();
    } else if (!show &&
        _scaleCtrl.status != AnimationStatus.reverse &&
        _scaleCtrl.status != AnimationStatus.dismissed) {
      _scaleCtrl.reverse();
    }

    return AnimatedBuilder(
      animation: _scaleCtrl,
      builder: (context, _) {
        if (_scaleCtrl.isDismissed && !show) {
          return const SizedBox.shrink();
        }

        final mq = MediaQuery.of(context);
        final screenSize = mq.size;

        final stream = callProvider.focusedStream;
        final hasDisplay = callProvider.hasScreenShareStream;
        final hasRemote = callProvider.hasRemoteVideoStream;
        final hasLocal = callProvider.hasLocalVideoStream;

        final RTCVideoRenderer? activeRenderer = hasDisplay
            ? callProvider.screenShareRenderer
            : (hasRemote
                ? callProvider.remoteRenderer
                : (hasLocal ? callProvider.localRenderer : null));

        Widget buildPipForValue(RTCVideoValue? videoVal) {
          final pipSize = _computePipDimensions(
            videoValue: videoVal,
            hasDisplay: hasDisplay,
            hasVideo: hasRemote || hasLocal,
            streamWidth: stream?.resolutionWidth,
            streamHeight: stream?.resolutionHeight,
          );
          final pipWidth = pipSize.width;
          final pipHeight = pipSize.height;

          final pos = _position ??
              Offset(
                screenSize.width - pipWidth - 14,
                mq.padding.top + 68,
              );

          return Positioned(
            left: pos.dx.clamp(
              8.0,
              (screenSize.width - pipWidth - 8.0).clamp(8.0, 9999.0),
            ),
            top: pos.dy.clamp(
              8.0,
              (screenSize.height - pipHeight - 8.0).clamp(8.0, 9999.0),
            ),
            child: ScaleTransition(
              scale: _scaleAnim,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onRestoreCall();
                },
                onPanUpdate: (details) {
                  setState(() {
                    _position = pos + details.delta;
                  });
                },
                onPanEnd: (_) =>
                    _snapToNearestCorner(screenSize, mq.padding, pipSize),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: pipWidth,
                  height: pipHeight,
                  padding: const EdgeInsets.all(1.2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12141A),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.44),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.5),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasDisplay)
                          RTCVideoView(
                            callProvider.screenShareRenderer,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          )
                        else if (hasRemote)
                          RTCVideoView(
                            callProvider.remoteRenderer,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          )
                        else if (hasLocal)
                          RTCVideoView(
                            callProvider.localRenderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          )
                        else
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF1A2234), Color(0xFF0E131D)],
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                stream != null
                                    ? Icons.screen_share_rounded
                                    : Icons.videocam_rounded,
                                color: Colors.white54,
                                size: 32,
                              ),
                            ),
                          ),

                        // Top overlay badge
                        Positioned(
                          left: 8,
                          top: 8,
                          right: 8,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.62),
                                  borderRadius: BorderRadius.circular(6),
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
                                    const SizedBox(width: 4),
                                    Text(
                                      stream != null
                                          ? stream.qualityBadge
                                          : callProvider.formattedDuration,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: widget.onRestoreCall,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.open_in_full_rounded,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Bottom quick controls
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 6,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  callProvider.activeCall?.title ?? 'Звонок',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(blurRadius: 4, color: Colors.black),
                                    ],
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => callProvider.leaveCall(),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.call_end_rounded,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        if (activeRenderer != null) {
          return ValueListenableBuilder<RTCVideoValue>(
            valueListenable: activeRenderer,
            builder: (context, videoVal, _) => buildPipForValue(videoVal),
          );
        }
        return buildPipForValue(null);
      },
    );
  }
}
