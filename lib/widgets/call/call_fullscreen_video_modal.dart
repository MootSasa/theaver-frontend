import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../../models/call_models.dart';
import '../../services/call_state_provider.dart';
import 'stream_quality_sheet.dart';

/// Fullscreen interactive viewer for any video tile or screen-share stream
/// inside a 1-on-1 or group call.
///
/// Features:
/// - Pinch-to-zoom and pan via [InteractiveViewer] (1x–4.5x)
/// - Instant tap anywhere to toggle top/bottom overlay controls
/// - Self-screen-share mirror protection (prevents infinite recursive capture
///   feedback loops by offering a dedicated broadcast control card + optional preview)
/// - Fit mode toggle ([RTCVideoViewObjectFitContain] vs [RTCVideoViewObjectFitCover])
/// - Quick orientation toggle (Landscape / Portrait on mobile)
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
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 160),
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
  bool _hadScreenShare = false;
  bool _enabledSelfPreviewHere = false;
  bool _isClosing = false;
  CallStateProvider? _cachedProvider;

  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cachedProvider = context.read<CallStateProvider>();
  }

  @override
  void dispose() {
    if (_enabledSelfPreviewHere && _cachedProvider != null) {
      final prov = _cachedProvider!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        prov.setPreviewOwnScreenShare(false);
      });
    }
    _transformCtrl.dispose();
    if (_forceLandscape && _isMobilePlatform) {
      SystemChrome.setPreferredOrientations(const []);
    }
    super.dispose();
  }

  void _closeModal() {
    if (_isClosing || !mounted) return;
    _isClosing = true;
    if (_enabledSelfPreviewHere && _cachedProvider != null) {
      _cachedProvider!.setPreviewOwnScreenShare(false);
      _enabledSelfPreviewHere = false;
    }
    Navigator.of(context).pop();
  }

  void _toggleOrientation() {
    if (!_isMobilePlatform) return;
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
    setState(() {});
  }

  RTCVideoRenderer? _resolveRenderer(CallStateProvider provider) {
    if (widget.isScreenShare) {
      if (provider.isSelfScreenShare) {
        return provider.previewOwnScreenShare
            ? (provider.screenShareRenderer.srcObject != null
                ? provider.screenShareRenderer
                : widget.fallbackRenderer)
            : null;
      }
      final focused = provider.focusedStream;
      if (focused != null) {
        final r = provider.rendererForStream(focused.streamerId);
        if (r != null && r.srcObject != null) return r;
      }
      return provider.hasScreenShareStream
          ? provider.screenShareRenderer
          : (widget.fallbackRenderer ?? provider.screenShareRenderer);
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

  Future<void> _onTapQualitySelector(CallStateProvider callProvider) async {
    if (callProvider.isSelfScreenShare) {
      final updated = await StreamQualitySheet.show(
        context,
        initialConfig: callProvider.streamConfig,
        isUpdatingActiveStream: true,
      );
      if (updated != null) {
        await callProvider.updateScreenShareQuality(updated);
      }
      return;
    }
    final stream = callProvider.focusedStream;
    if (stream == null) return;
    final q = await ViewerQualitySelectorSheet.show(
      context,
      currentQuality: callProvider.viewerQuality,
      stream: stream,
    );
    if (q != null) {
      callProvider.setViewerQuality(q);
    }
  }

  Widget _buildSelfScreenShareControlStage(
    BuildContext context,
    CallStateProvider callProvider,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final stream = callProvider.focusedStream;
    final cfg = callProvider.streamConfig;
    final specsText = stream != null
        ? '${stream.resolutionWidth}×${stream.resolutionHeight} @ ${stream.fps} FPS • ${stream.codec} • ${(stream.bitrateKbps / 1000).toStringAsFixed(1)} Mbps'
        : '${cfg.width}×${cfg.height} @ ${cfg.fps} FPS • ${cfg.codec} • ${(cfg.bitrateKbps / 1000).toStringAsFixed(1)} Mbps';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 96),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF141822),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.screen_share_rounded,
                    size: 34,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
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
                    const Flexible(
                      child: Text(
                        'Вы делитесь экраном',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  specsText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFFAB40),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Живое превью собственного экрана скрыто по умолчанию, чтобы избежать эффекта бесконечного зеркала и лишней нагрузки на видеокодер.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _enabledSelfPreviewHere = true;
                      callProvider.setPreviewOwnScreenShare(true);
                    },
                    icon: const Icon(Icons.visibility_rounded, size: 19),
                    label: const Text(
                      'Показать превью экрана',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _onTapQualitySelector(callProvider),
                    icon: const Icon(Icons.tune_rounded, size: 19),
                    label: Text(
                      'Изменить качество (${cfg.badgeLabel})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.22),
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      await callProvider.stopScreenShare();
                      _closeModal();
                    },
                    icon: const Icon(
                      Icons.stop_screen_share_rounded,
                      size: 19,
                    ),
                    label: const Text(
                      'Остановить трансляцию',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
        _closeModal();
      });
    }

    final stream = widget.isScreenShare ? callProvider.focusedStream : null;
    final isSelfScreenShare =
        widget.isScreenShare && callProvider.isSelfScreenShare;
    final isScreenShareActive = widget.isScreenShare &&
        (callProvider.isScreenSharing ||
            stream != null ||
            callProvider.hasScreenShareStream);

    if (isScreenShareActive) {
      _hadScreenShare = true;
    } else if (widget.isScreenShare && _hadScreenShare) {
      _hadScreenShare = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _closeModal();
      });
    }

    final renderer = _resolveRenderer(callProvider);
    final objectFit = _coverFit
        ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
        : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain;

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Main Stage: either Self-Stream Control Card or Interactive Zoomable Video Stage
          if (isSelfScreenShare && !callProvider.previewOwnScreenShare)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _showControls = !_showControls);
              },
              child: _buildSelfScreenShareControlStage(context, callProvider),
            )
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _showControls = !_showControls);
              },
              child: InteractiveViewer(
                transformationController: _transformCtrl,
                minScale: 1.0,
                maxScale: 4.5,
                panEnabled: true,
                scaleEnabled: true,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.hasBoundedWidth &&
                            constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : MediaQuery.sizeOf(context).width;
                    final h = constraints.hasBoundedHeight &&
                            constraints.maxHeight.isFinite
                        ? constraints.maxHeight
                        : MediaQuery.sizeOf(context).height;
                    final rotKey = widget.isScreenShare
                        ? (stream?.streamerId ?? 'screen_share')
                        : (widget.participantUserId ??
                            (callProvider.hasRemoteVideoStream
                                ? 'remote'
                                : 'local'));
                    final rot = callProvider.getParticipantRotation(rotKey);

                    return SizedBox(
                      width: w,
                      height: h,
                      child: renderer != null
                          ? RotatedBox(
                              quarterTurns: rot ~/ 90,
                              child: RTCVideoView(
                                renderer,
                                mirror: widget.mirror &&
                                    !widget.isScreenShare &&
                                    ((widget.participantUserId == 'local' ||
                                            widget.participantUserId ==
                                                callProvider.currentUserId)
                                        ? callProvider.isFrontCamera
                                        : true),
                                objectFit: objectFit,
                              ),
                            )
                          : Center(
                              child: Column(
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
                    );
                  },
                ),
              ),
            ),

          // Floating "Hide self preview" pill when self-screen-share mirror preview is enabled
          if (isSelfScreenShare && callProvider.previewOwnScreenShare)
            Positioned(
              top: MediaQuery.of(context).padding.top + 68,
              left: 0,
              right: 0,
              child: Center(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.72),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: Colors.white24, width: 0.8),
                    ),
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    callProvider.setPreviewOwnScreenShare(false);
                  },
                  icon: const Icon(Icons.visibility_off_rounded, size: 16),
                  label: const Text(
                    'Скрыть превью (убрать зеркало)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                    onTap: _closeModal,
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
                          isSelfScreenShare
                              ? 'Ваша трансляция экрана'
                              : widget.title,
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
                  if (stream != null || isSelfScreenShare) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _onTapQualitySelector(callProvider),
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
                            Icon(
                              isSelfScreenShare
                                  ? Icons.tune_rounded
                                  : Icons.hd_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isSelfScreenShare
                                  ? callProvider.streamConfig.badgeLabel
                                  : callProvider.viewerQuality.label,
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
                  if (widget.isScreenShare &&
                      (callProvider.activeCall?.streams.length ?? 0) > 1) ...[
                    const SizedBox(width: 8),
                    PopupMenuButton<CallStreamInfo>(
                      tooltip: 'Сменить стрим',
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white24,
                            width: 0.8,
                          ),
                        ),
                        child: const Icon(
                          Icons.swap_calls_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                      onSelected: (selected) {
                        callProvider.setFocusedStream(selected);
                      },
                      itemBuilder: (context) {
                        return (callProvider.activeCall?.streams ?? [])
                            .map((s) => PopupMenuItem<CallStreamInfo>(
                                  value: s,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.screen_share_rounded,
                                        size: 16,
                                        color: s.streamerId == stream?.streamerId
                                            ? const Color(0xFF00E676)
                                            : Colors.white70,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          s.streamerName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList();
                      },
                    ),
                  ],
                  if (_transformCtrl.value != Matrix4.identity()) ...[
                    const SizedBox(width: 8),
                    _buildCircleButton(
                      icon: Icons.zoom_out_map_rounded,
                      tooltip: 'Сбросить масштаб',
                      onTap: _resetZoom,
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
                    icon: Icons.rotate_90_degrees_cw_rounded,
                    tooltip: 'Повернуть видео на 90°',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      final rotKey = widget.isScreenShare
                          ? (stream?.streamerId ?? 'screen_share')
                          : (widget.participantUserId ??
                              (callProvider.hasRemoteVideoStream
                                  ? 'remote'
                                  : 'local'));
                      callProvider.rotateParticipant(rotKey);
                    },
                  ),
                  if (_isMobilePlatform) ...[
                    const SizedBox(width: 8),
                    _buildCircleButton(
                      icon: Icons.screen_rotation_rounded,
                      tooltip: 'Повернуть экран',
                      onTap: _toggleOrientation,
                    ),
                  ],
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
                  if (callProvider.isVideoOn) ...[
                    const SizedBox(width: 24),
                    _buildBottomAction(
                      icon: Icons.flip_camera_ios_rounded,
                      label: 'Камера',
                      active: true,
                      onTap: () => callProvider.switchCamera(),
                    ),
                  ],
                  if (isSelfScreenShare) ...[
                    const SizedBox(width: 24),
                    _buildBottomAction(
                      icon: Icons.stop_screen_share_rounded,
                      label: 'Стоп экран',
                      danger: true,
                      onTap: () async {
                        await callProvider.stopScreenShare();
                        _closeModal();
                      },
                    ),
                  ],
                  const SizedBox(width: 24),
                  _buildBottomAction(
                    icon: Icons.fullscreen_exit_rounded,
                    label: 'Свернуть',
                    onTap: _closeModal,
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
