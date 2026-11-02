import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../services/call_state_provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../widgets/call/call_fullscreen_video_modal.dart';
import '../../widgets/call/stream_quality_sheet.dart';

/// 1-on-1 Video Call & High-FPS Screen Share Screen with Liquid Glass & Material Matte
/// controls, draggable local camera preview, and Minimize to Top Banner + PiP.
class VideoCallScreen extends StatefulWidget {
  final String callId;
  final bool isCaller;
  final String? chatId;
  final String? peerName;
  final String? peerAvatarUrl;

  const VideoCallScreen({
    super.key,
    required this.callId,
    required this.isCaller,
    this.chatId,
    this.peerName,
    this.peerAvatarUrl,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  Offset _localPreviewOffset = const Offset(16, 92);
  bool _hadActiveCall = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<CallStateProvider>();
      provider.setMinimized(false);
      if (!provider.hasActiveCall) {
        provider.startOrJoinCall(
          chatId: widget.chatId ?? widget.callId,
          chatTitle: widget.peerName ?? 'Видеозвонок',
          callType: 'video',
          isVideo: true,
        );
      } else if (!provider.isVideoOn && !provider.isTogglingVideo) {
        provider.toggleVideo();
      }
    });
  }

  void _minimizeCall(CallStateProvider provider) {
    HapticFeedback.lightImpact();
    provider.setMinimized(true);
    Navigator.of(context).maybePop();
  }

  Future<void> _endCall(CallStateProvider provider) async {
    HapticFeedback.mediumImpact();
    await provider.leaveCall();
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _onTapScreenShare(CallStateProvider provider) async {
    if (provider.isScreenSharing) {
      final updated = await StreamQualitySheet.show(
        context,
        initialConfig: provider.streamConfig,
        isUpdatingActiveStream: true,
      );
      if (updated != null) {
        await provider.updateScreenShareQuality(updated);
      }
      return;
    }
    final config = await StreamQualitySheet.show(
      context,
      initialConfig: provider.streamConfig,
    );
    if (config != null) {
      await provider.startScreenShare(config);
    }
  }

  void _openMainStageFullscreen(
    CallStateProvider callProvider,
    String peerTitle,
  ) {
    final hasScreenShare = callProvider.hasScreenShareStream;
    final hasRemoteVideo = callProvider.hasRemoteVideoStream;
    final hasLocalVideo =
        callProvider.hasLocalVideoStream && callProvider.isVideoOn;
    if (!hasScreenShare && !hasRemoteVideo && !hasLocalVideo) return;

    final stream = callProvider.focusedStream;
    CallFullscreenVideoModal.show(
      context,
      title: hasScreenShare
          ? 'Трансляция ${stream?.streamerName ?? peerTitle}'
          : (hasRemoteVideo ? peerTitle : 'Вы'),
      subtitle: callProvider.formattedDuration,
      isScreenShare: hasScreenShare,
      mirror: !hasScreenShare && !hasRemoteVideo && hasLocalVideo,
      fallbackRenderer: hasScreenShare
          ? callProvider.screenShareRenderer
          : (hasRemoteVideo
              ? callProvider.remoteRenderer
              : callProvider.localRenderer),
    );
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
    final glassProvider = context.watch<LiquidGlassProvider>();
    final useGlass = glassProvider.enabled;
    final isFullGlass = glassProvider.isFull;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final peerTitle =
        widget.peerName ?? callProvider.activeCall?.title ?? 'Видеозвонок';
    final stream = callProvider.focusedStream;

    final hasScreenShare = callProvider.hasScreenShareStream;
    final hasRemoteVideo = callProvider.hasRemoteVideoStream;
    final hasLocalVideo = callProvider.hasLocalVideoStream;
    final hasAnyStageVideo =
        hasScreenShare || hasRemoteVideo || (hasLocalVideo && callProvider.isVideoOn);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && callProvider.hasActiveCall) {
          callProvider.setMinimized(true);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0D14),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Main Stage: Screen Share > Remote Video > Local Video > Placeholder
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (hasAnyStageVideo) {
                    setState(() => _showControls = !_showControls);
                  }
                },
                onDoubleTap: () {
                  if (hasAnyStageVideo) {
                    _openMainStageFullscreen(callProvider, peerTitle);
                  }
                },
                child: hasScreenShare
                    ? InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 4.0,
                        child: RTCVideoView(
                          callProvider.screenShareRenderer,
                          objectFit: RTCVideoViewObjectFit
                              .RTCVideoViewObjectFitContain,
                        ),
                      )
                    : hasRemoteVideo
                        ? InteractiveViewer(
                            minScale: 1.0,
                            maxScale: 3.5,
                            child: RTCVideoView(
                              callProvider.remoteRenderer,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitCover,
                            ),
                          )
                        : hasLocalVideo && callProvider.isVideoOn
                            ? RTCVideoView(
                                callProvider.localRenderer,
                                mirror: true,
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: const Alignment(0, -0.2),
                                    radius: 1.0,
                                    colors: [
                                      primaryColor.withValues(alpha: 0.25),
                                      const Color(0xFF0A0D14),
                                    ],
                                  ),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircleAvatar(
                                        radius: 48,
                                        backgroundColor:
                                            primaryColor.withValues(alpha: 0.25),
                                        child: Text(
                                          peerTitle.isNotEmpty
                                              ? peerTitle[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            fontSize: 36,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        peerTitle,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        callProvider.formattedDuration,
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Colors.white
                                              .withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
              ),
            ),

            // Draggable Local Camera Self-View when remote video or screen share is on main stage
            if (hasLocalVideo &&
                callProvider.isVideoOn &&
                (hasRemoteVideo || hasScreenShare))
              Positioned(
                right: _localPreviewOffset.dx,
                top: _localPreviewOffset.dy,
                child: GestureDetector(
                  onPanUpdate: (d) {
                    setState(() {
                      _localPreviewOffset = Offset(
                        (_localPreviewOffset.dx - d.delta.dx).clamp(12.0, 260.0),
                        (_localPreviewOffset.dy + d.delta.dy).clamp(72.0, 520.0),
                      );
                    });
                  },
                  onTap: () {
                    CallFullscreenVideoModal.show(
                      context,
                      title: 'Ваша камера',
                      subtitle: callProvider.formattedDuration,
                      participantUserId: 'local',
                      mirror: true,
                      fallbackRenderer: callProvider.localRenderer,
                    );
                  },
                  child: Container(
                    width: 112,
                    height: 156,
                    padding: const EdgeInsets.all(1.2),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 14,
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
                          RTCVideoView(
                            callProvider.localRenderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          ),
                          Positioned(
                            right: 6,
                            top: 6,
                            child: GestureDetector(
                              onTap: () => callProvider.switchCamera(),
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.cameraswitch_rounded,
                                  size: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Top Header & Bottom Dock
            if (_showControls || !hasAnyStageVideo)
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          _buildTopCircleBtn(
                            icon: Icons.keyboard_arrow_down_rounded,
                            tooltip: 'Свернуть в окно (PiP)',
                            onTap: () => _minimizeCall(callProvider),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          peerTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          callProvider.formattedDuration,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: Colors.white
                                                .withValues(alpha: 0.72),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (stream != null)
                                    GestureDetector(
                                      onTap: () async {
                                        final q =
                                            await ViewerQualitySelectorSheet.show(
                                          context,
                                          currentQuality:
                                              callProvider.viewerQuality,
                                          stream: stream,
                                        );
                                        if (q != null) {
                                          callProvider.setViewerQuality(q);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFFFF8F00),
                                              Color(0xFFFF5722),
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          stream.qualityBadge,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (hasAnyStageVideo) ...[
                            const SizedBox(width: 8),
                            _buildTopCircleBtn(
                              icon: Icons.open_in_full_rounded,
                              tooltip: 'На весь экран',
                              onTap: () => _openMainStageFullscreen(
                                callProvider,
                                peerTitle,
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          _buildTopCircleBtn(
                            icon: Icons.cameraswitch_rounded,
                            tooltip: 'Сменить камеру',
                            onTap: () => callProvider.switchCamera(),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  if (callProvider.isScreenSharing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Colors.redAccent.withValues(alpha: 0.26),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => callProvider.stopScreenShare(),
                        icon: const Icon(
                          Icons.stop_screen_share_rounded,
                          size: 18,
                        ),
                        label: Text(
                          'Остановить трансляцию (${callProvider.streamConfig.badgeLabel})',
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: SizedBox(
                      height: 74,
                      width: double.infinity,
                      child: useGlass
                          ? LiquidGlassLens(
                              style: glassProvider.createStyle(
                                context: context,
                                cornerRadius: 37,
                                color: Colors.black.withValues(alpha: 0.35),
                                refractionIndex: isFullGlass ? 1.12 : 1.05,
                                refractionWidth: 24.0,
                              ),
                              child: _buildBottomControls(
                                callProvider,
                                primaryColor,
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(37),
                              child: BackdropFilter.grouped(
                                filter:
                                    ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                                child: Container(
                                  height: 74,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF141822)
                                        .withValues(alpha: 0.88),
                                    borderRadius: BorderRadius.circular(37),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.14),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: _buildBottomControls(
                                    callProvider,
                                    primaryColor,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopCircleBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
              width: 0.8,
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildBottomControls(
    CallStateProvider callProvider,
    Color primaryColor,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildDockIcon(
          icon: callProvider.isMuted
              ? Icons.mic_off_rounded
              : Icons.mic_rounded,
          label: callProvider.isMuted ? 'Вкл. микр.' : 'Микрофон',
          danger: callProvider.isMuted,
          active: !callProvider.isMuted,
          onTap: () => callProvider.toggleMute(),
        ),
        _buildDockIcon(
          icon: callProvider.isVideoOn
              ? Icons.videocam_rounded
              : Icons.videocam_off_rounded,
          label: 'Камера',
          active: callProvider.isVideoOn,
          onTap: () => callProvider.toggleVideo(),
        ),
        _buildDockIcon(
          icon: callProvider.isScreenSharing
              ? Icons.tune_rounded
              : Icons.screen_share_rounded,
          label: callProvider.isScreenSharing
              ? callProvider.streamConfig.badgeLabel
              : 'Go Live',
          active: callProvider.isScreenSharing,
          accentColor: primaryColor,
          onTap: () => _onTapScreenShare(callProvider),
        ),
        _buildDockIcon(
          icon: callProvider.isSpeakerOn
              ? Icons.volume_up_rounded
              : Icons.hearing_rounded,
          label: 'Динамик',
          active: callProvider.isSpeakerOn,
          onTap: () => callProvider.toggleSpeaker(),
        ),
        GestureDetector(
          onTap: () => _endCall(callProvider),
          child: Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDockIcon({
    required IconData icon,
    required String label,
    bool active = false,
    bool danger = false,
    Color? accentColor,
    required VoidCallback onTap,
  }) {
    final bg = danger
        ? Colors.redAccent.withValues(alpha: 0.24)
        : (active
            ? (accentColor ?? Colors.white).withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.08));
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: 21),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }
}