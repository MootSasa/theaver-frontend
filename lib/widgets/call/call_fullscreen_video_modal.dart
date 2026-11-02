import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../../services/call_state_provider.dart';
import 'stream_quality_sheet.dart';

/// Fullscreen interactive viewer for any video tile or screen-share stream
/// inside a 1-on-1 or group call.
///
/// Features:
/// - Pinch-to-zoom and pan via [InteractiveViewer] (1x–4x)
/// - Tap anywhere to toggle top/bottom overlay controls
/// - Fit mode toggle ([RTCVideoViewObjectFitContain] vs [RTCVideoViewObjectFitCover])
/// - Quick orientation toggle (Landscape / Portrait)
/// - Quick call controls (Mute, Camera, Quality selector for streams, Close fullscreen)
class CallFullscreenVideoModal extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? participantUserId;
  final bool isScreenShare;
  final bool mirror;
  final RTCVideoRenderer? fallbackRenderer;

  const CallFullscreenVideoModal({
    super.key,
    required this.title,
    this.subtitle,
    this.participantUserId,
    this.isScreenShare = false,
    this.mirror = false,
    this.fallbackRenderer,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    String? subtitle,
    String? participantUserId,
    bool isScreenShare = false,
    bool mirror = false,
    RTCVideoRenderer? fallbackRenderer,
  }) {
    HapticFeedback.lightImpact();
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (ctx, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: CallFullscreenVideoModal(
              title: title,
              subtitle: subtitle,
              participantUserId: participantUserId,
              isScreenShare: isScreenShare,
              mirror: mirror,
              fallbackRenderer: fallbackRenderer,
            ),
          );
        },
      ),
    );
  }

  @override
  State<CallFullscreenVideoModal> createState() =>
      _CallFullscreenVideoModalState();
}

class _CallFullscreenVideoModalState extends State<CallFullscreenVideoModal> {
  final TransformationController _transformCtrl = TransformationController();
  bool _showControls = true;
  bool _coverFit = false;
  bool _forceLandscape = false;
  bool _hadActiveCall = false;

  @override
  void dispose() {
    _transformCtrl.dispose();
    if (_forceLandscape) {
      SystemChrome.setPreferredOrientations(const []);
    }
    super.dispose();
  }

  void _toggleOrientation() {
    HapticFeedback.selectionClick();
    setState(() {
      _forceLandscape = !_forceLandscape;
    });
    if (_forceLandscape) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(const []);
    }
  }

  void _resetZoom() {
    _transformCtrl.value = Matrix4.identity();
  }

  RTCVideoRenderer? _resolveRenderer(CallStateProvider provider) {
    if (widget.isScreenShare) {
      return provider.hasScreenShareStream
          ? provider.screenShareRenderer
          : widget.fallbackRenderer;
    }
    if (widget.participantUserId != null) {
      final r = provider.rendererForParticipant(widget.participantUserId!);
      if (r != null) return r;
    }
    return widget.fallbackRenderer ??
        (provider.hasRemoteVideoStream
            ? provider.remoteRenderer
            : (provider.hasLocalVideoStream ? provider.localRenderer : null));
  }

  @override
  Widget build(BuildContext context) {
    final callProvider = context.watch<CallStateProvider>();
    if (callProvider.hasActiveCall) {
      _hadActiveCall = true;
    } else if (_hadActiveCall) {
      _hadActiveCall = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }

    final renderer = _resolveRenderer(callProvider);
    final stream = widget.isScreenShare ? callProvider.focusedStream : null;
    final objectFit = _coverFit
        ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
        : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Interactive Zoomable Video Stage
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _showControls = !_showControls);
            },
            onDoubleTap: () {
              HapticFeedback.selectionClick();
              if (_transformCtrl.value != Matrix4.identity()) {
                _resetZoom();
              } else {
                setState(() => _coverFit = !_coverFit);
              }
            },
            child: InteractiveViewer(
              transformationController: _transformCtrl,
              minScale: 1.0,
              maxScale: 4.5,
              panEnabled: true,
              scaleEnabled: true,
              child: Center(
                child: renderer != null
                    ? RTCVideoView(
                        renderer,
                        mirror: widget.mirror && !widget.isScreenShare,
                        objectFit: objectFit,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isScreenShare
                                ? Icons.screen_share_rounded
                                : Icons.videocam_off_rounded,
                            size: 48,
                            color: Colors.white54,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),

          // Top Overlay Bar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            top: _showControls ? 0 : -110,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                14,
                MediaQuery.of(context).padding.top + 8,
                14,
                16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.78),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  _buildCircleButton(
                    icon: Icons.fullscreen_exit_rounded,
                    tooltip: 'Свернуть из полного экрана',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  if (widget.isScreenShare) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          stream != null
                              ? '${stream.qualityBadge} • ${stream.codec}'
                              : (widget.subtitle ??
                                  callProvider.formattedDuration),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (stream != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final q = await ViewerQualitySelectorSheet.show(
                          context,
                          currentQuality: callProvider.viewerQuality,
                          stream: stream,
                        );
                        if (q != null) {
                          callProvider.setViewerQuality(q);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white24,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.hd_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              callProvider.viewerQuality.label,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  _buildCircleButton(
                    icon: _coverFit
                        ? Icons.fit_screen_rounded
                        : Icons.aspect_ratio_rounded,
                    tooltip: _coverFit ? 'Вписать целиком' : 'Заполнить экран',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _coverFit = !_coverFit);
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildCircleButton(
                    icon: Icons.screen_rotation_rounded,
                    tooltip: 'Повернуть экран',
                    onTap: _toggleOrientation,
                  ),
                ],
              ),
            ),
          ),

          // Bottom Quick Controls
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            bottom: _showControls ? 0 : -110,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                MediaQuery.of(context).padding.bottom + 20,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.82),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildBottomAction(
                    icon: callProvider.isMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    label: callProvider.isMuted ? 'Вкл. микр.' : 'Микрофон',
                    danger: callProvider.isMuted,
                    onTap: () => callProvider.toggleMute(),
                  ),
                  const SizedBox(width: 24),
                  _buildBottomAction(
                    icon: callProvider.isVideoOn
                        ? Icons.videocam_rounded
                        : Icons.videocam_off_rounded,
                    label: 'Камера',
                    active: callProvider.isVideoOn,
                    onTap: () => callProvider.toggleVideo(),
                  ),
                  const SizedBox(width: 24),
                  _buildBottomAction(
                    icon: Icons.fullscreen_exit_rounded,
                    label: 'Свернуть',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.8,
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildBottomAction({
    required IconData icon,
    required String label,
    bool active = false,
    bool danger = false,
    required VoidCallback onTap,
  }) {
    final bg = danger
        ? Colors.redAccent.withValues(alpha: 0.28)
        : (active
            ? Colors.white.withValues(alpha: 0.24)
            : Colors.white.withValues(alpha: 0.12));
    final fg = danger ? Colors.redAccent : Colors.white;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 0.8,
              ),
            ),
            child: Icon(icon, color: fg, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
