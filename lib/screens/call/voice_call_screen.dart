import 'dart:io' show Platform;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../models/call_models.dart';
import '../../models/theav_theme.dart';
import '../../services/call_state_provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../widgets/call/call_fullscreen_video_modal.dart';
import '../../widgets/call/desktop_source_picker_modal.dart';
import '../../widgets/call/soundboard_sheet.dart';
import '../../widgets/call/stream_quality_sheet.dart';
import '../../widgets/whiteboard/interactive_whiteboard.dart';
import 'video_call_screen.dart';

/// 1-on-1 Voice Call Screen with Material Matte & Liquid Glass control dock,
/// High-FPS Screen Share support, and Minimize to Top Banner / PiP.
class VoiceCallScreen extends StatefulWidget {
  final String callId;
  final bool isCaller;
  final String? chatId;
  final String? peerName;
  final String? peerAvatarUrl;

  const VoiceCallScreen({
    super.key,
    required this.callId,
    required this.isCaller,
    this.chatId,
    this.peerName,
    this.peerAvatarUrl,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  bool _hadActiveCall = false;
  bool _isLeavingCall = false;
  bool _showingTransferDialog = false;

  void _showDeviceTransferDialog(
    BuildContext context,
    CallStateProvider callProvider,
  ) {
    if (_showingTransferDialog) return;
    final conflictId = callProvider.conflictCallId;
    if (conflictId == null) return;
    _showingTransferDialog = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181D2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.devices_rounded, color: Color(0xFF00E676), size: 24),
            SizedBox(width: 10),
            Text('Активный звонок', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Вы уже находитесь в этом звонке с другого устройства.\n\nПеревести звонок на это устройство?',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showingTransferDialog = false;
              callProvider.clearConflictCall();
              if (mounted) Navigator.of(context).maybePop();
            },
            child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              _showingTransferDialog = false;
              await callProvider.transferCallToThisDevice(
                conflictId,
                chatTitle: widget.peerName ?? 'Голосовой звонок',
                isVideo: false,
              );
            },
            child: const Text('Перевести', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).then((_) => _showingTransferDialog = false);
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<CallStateProvider>();
      provider.setMinimized(false);
      if (!provider.hasActiveCall) {
        provider.startOrJoinCall(
          chatId: widget.chatId ?? widget.callId,
          chatTitle: widget.peerName ?? 'Голосовой звонок',
          callType: 'voice',
          isVideo: false,
        );
      }
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _minimizeCall(CallStateProvider provider) {
    HapticFeedback.lightImpact();
    provider.setMinimized(true);
    Navigator.of(context).maybePop();
  }

  Future<void> _endCall(CallStateProvider provider) async {
    if (_isLeavingCall) return;
    _isLeavingCall = true;
    _hadActiveCall = false;
    HapticFeedback.mediumImpact();
    FocusManager.instance.primaryFocus?.unfocus();
    provider.leaveCall();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _onTapScreenShare(CallStateProvider provider) async {
    if (provider.isScreenSharing) {
      final updated = await StreamQualitySheet.show(
        context,
        initialConfig: provider.streamConfig,
        isUpdatingActiveStream: true,
        onStopStream: () => provider.stopScreenShare(),
      );
      if (updated != null) {
        await provider.updateScreenShareQuality(updated);
      }
      return;
    }

    StreamConfig? config;
    if (kIsWeb || (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux)) {
      config = await StreamQualitySheet.show(
        context,
        initialConfig: provider.streamConfig,
      );
    } else {
      config = await DesktopSourcePickerModal.show(
        context,
        initialConfig: provider.streamConfig,
      );
    }
    if (config != null) {
      await provider.startScreenShare(config);
    }
  }

  @override
  Widget build(BuildContext context) {
    final callProvider = context.watch<CallStateProvider>();
    if (callProvider.conflictCallId != null && !_showingTransferDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showDeviceTransferDialog(context, callProvider);
      });
    }
    if (callProvider.hasActiveCall) {
      _hadActiveCall = true;
    } else if (_hadActiveCall && !_isLeavingCall) {
      _hadActiveCall = false;
      _isLeavingCall = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
    final glassProvider = context.watch<LiquidGlassProvider>();
    final useGlass = glassProvider.enabled;
    final isFullGlass = glassProvider.isFull;
    final p = context.theav;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final peerTitle =
        widget.peerName ?? callProvider.activeCall?.title ?? 'Собеседник';
    final stream = callProvider.focusedStream;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_isLeavingCall && callProvider.hasActiveCall) {
          callProvider.setMinimized(true);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D111A),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Ambient background gradient
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.25),
                  radius: 1.1,
                  colors: [
                    primaryColor.withValues(alpha: 0.28),
                    const Color(0xFF0D111A),
                  ],
                ),
              ),
            ),

            // If local or remote screen share is active, show live stage preview
            if (callProvider.hasScreenShareStream)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    CallFullscreenVideoModal.show(
                      context,
                      title: 'Трансляция ${stream?.streamerName ?? peerTitle}',
                      subtitle: callProvider.formattedDuration,
                      isScreenShare: true,
                      fallbackRenderer: callProvider.screenShareRenderer,
                    );
                  },
                  child: RTCVideoView(
                    callProvider.screenShareRenderer,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  ),
                ),
              ),

            SafeArea(
              child: Column(
                children: [
                  // Top Bar (Minimize + E2E / Stream Quality badge)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        _buildTopIconButton(
                          icon: Icons.keyboard_arrow_down_rounded,
                          tooltip: 'Свернуть звонок',
                          onTap: () => _minimizeCall(callProvider),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.14),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.lock_outline_rounded,
                                size: 14,
                                color: Color(0xFF69F0AE),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                stream != null
                                    ? 'LIVE • ${stream.qualityBadge} (${stream.codec})'
                                    : 'Защищённый звонок',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (stream != null ||
                            callProvider.hasScreenShareStream ||
                            callProvider.isScreenSharing)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (stream != null ||
                                  callProvider.isSelfScreenShare) ...[
                                _buildTopIconButton(
                                  icon: callProvider.isSelfScreenShare
                                      ? Icons.tune_rounded
                                      : Icons.hd_rounded,
                                  tooltip: callProvider.isSelfScreenShare
                                      ? 'Настройки трансляции'
                                      : 'Качество просмотра',
                                  onTap: () async {
                                    if (callProvider.isSelfScreenShare) {
                                      await _onTapScreenShare(callProvider);
                                      return;
                                    }
                                    if (stream == null) return;
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
                                ),
                                const SizedBox(width: 8),
                              ],
                              _buildTopIconButton(
                                icon: Icons.open_in_full_rounded,
                                tooltip: 'На весь экран',
                                onTap: () {
                                  CallFullscreenVideoModal.show(
                                    context,
                                    title: callProvider.isSelfScreenShare
                                        ? 'Ваша трансляция экрана'
                                        : 'Трансляция ${stream?.streamerName ?? peerTitle}',
                                    subtitle: callProvider.formattedDuration,
                                    isScreenShare: true,
                                    fallbackRenderer:
                                        callProvider.screenShareRenderer,
                                  );
                                },
                              ),
                            ],
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildTopIconButton(
                                icon: callProvider.highFidelityAudio
                                    ? Icons.graphic_eq_rounded
                                    : Icons.music_note_outlined,
                                tooltip: callProvider.highFidelityAudio
                                    ? 'Hi-Fi Аудио (48 кГц Opus)'
                                    : 'Стандартный звук',
                                onTap: () {
                                  callProvider.toggleHighFidelityAudio();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(callProvider.highFidelityAudio
                                          ? 'Hi-Fi звук включён (48 кГц Opus)'
                                          : 'Стандартный звук'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  if (callProvider.isWhiteboardOpen)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: InteractiveWhiteboard(
                            roomId: callProvider.activeCall?.id ?? widget.callId,
                            chatId: callProvider.activeCall?.chatId ?? widget.chatId,
                            title: 'Доска • $peerTitle',
                            embeddedInCall: true,
                            onClose: () => callProvider.setWhiteboardOpen(false),
                          ),
                        ),
                      ),
                    )
                  else ...[
                    const Spacer(),

                    // Center Avatar with Speaking Pulse Rings
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (context, child) {
                      final isRinging =
                          callProvider.activeCall?.status == 'ringing';
                      final isAnyoneSpeaking = callProvider
                              .activeCall?.participants
                              .any((p) => p.isSpeaking && !p.isMuted) ??
                          false;
                      final showPulse = isRinging || isAnyoneSpeaking;
                      final pulse = showPulse ? _pulseCtrl.value : 0.0;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          if (showPulse) ...[
                            Container(
                              width: 156 + 24 * pulse,
                              height: 156 + 24 * pulse,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: primaryColor.withValues(
                                  alpha: 0.08 * (1 - pulse * 0.5),
                                ),
                              ),
                            ),
                            Container(
                              width: 136 + 12 * pulse,
                              height: 136 + 12 * pulse,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: primaryColor.withValues(alpha: 0.35),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ],
                          child!,
                        ],
                      );
                    },
                    child: CircleAvatar(
                      radius: 58,
                      backgroundColor: primaryColor.withValues(alpha: 0.25),
                      backgroundImage: widget.peerAvatarUrl != null &&
                              widget.peerAvatarUrl!.isNotEmpty
                          ? NetworkImage(widget.peerAvatarUrl!)
                          : null,
                      child: (widget.peerAvatarUrl == null ||
                              widget.peerAvatarUrl!.isEmpty)
                          ? Text(
                              peerTitle.isNotEmpty
                                  ? peerTitle[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    peerTitle,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    callProvider.formattedDuration,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),

                  if (callProvider.isScreenSharing) ...[
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.1),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            CallFullscreenVideoModal.show(
                              context,
                              title: 'Ваша трансляция экрана',
                              subtitle: callProvider.formattedDuration,
                              isScreenShare: true,
                              fallbackRenderer:
                                  callProvider.screenShareRenderer,
                            );
                          },
                          icon: const Icon(
                            Icons.screen_share_rounded,
                            size: 18,
                          ),
                          label: Text(
                            'Экран (${callProvider.streamConfig.badgeLabel})',
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Colors.redAccent.withValues(alpha: 0.22),
                            foregroundColor: Colors.redAccent,
                          ),
                          onPressed: () => callProvider.stopScreenShare(),
                          icon: const Icon(
                            Icons.stop_screen_share_rounded,
                            size: 18,
                          ),
                          label: const Text('Стоп'),
                        ),
                      ],
                    ),
                  ],

                    const Spacer(),
                  ],

                  // Bottom Floating Control Dock (LiquidGlassLens or Material Matte)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: SizedBox(
                      height: 76,
                      width: double.infinity,
                      child: useGlass
                          ? LiquidGlassLens(
                              style: glassProvider.createStyle(
                                context: context,
                                cornerRadius: 38,
                                color: Colors.white.withValues(alpha: 0.08),
                                refractionIndex: isFullGlass ? 1.12 : 1.05,
                                refractionWidth: 24.0,
                              ),
                              child: _buildControlsRow(
                                context,
                                callProvider,
                                primaryColor,
                                p,
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(38),
                              child: BackdropFilter.grouped(
                                filter:
                                    ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                                child: Container(
                                  height: 76,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1F2C)
                                        .withValues(alpha: 0.88),
                                    borderRadius: BorderRadius.circular(38),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.12),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: _buildControlsRow(
                                    context,
                                    callProvider,
                                    primaryColor,
                                    p,
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

  Widget _buildTopIconButton({
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
            color: Colors.white.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 0.8,
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildControlsRow(
    BuildContext context,
    CallStateProvider callProvider,
    Color primaryColor,
    TheavPalette p,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildControlButton(
          icon: callProvider.isMuted
              ? Icons.mic_off_rounded
              : Icons.mic_rounded,
          label: callProvider.isMuted ? 'Вкл. микр.' : 'Микрофон',
          active: !callProvider.isMuted,
          danger: callProvider.isMuted,
          onTap: () {
            HapticFeedback.selectionClick();
            callProvider.toggleMute();
          },
        ),
        _buildControlButton(
          icon: callProvider.isSpeakerOn
              ? Icons.volume_up_rounded
              : Icons.hearing_rounded,
          label: 'Динамик',
          active: callProvider.isSpeakerOn,
          onTap: () {
            HapticFeedback.selectionClick();
            callProvider.toggleSpeaker();
          },
        ),
        _buildControlButton(
          icon: Icons.videocam_rounded,
          label: 'Видео',
          active: callProvider.isVideoOn,
          onTap: () async {
            HapticFeedback.selectionClick();
            await callProvider.toggleVideo();
            if (!context.mounted || !callProvider.isVideoOn) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => VideoCallScreen(
                  callId: widget.callId,
                  isCaller: widget.isCaller,
                  chatId: widget.chatId,
                  peerName: widget.peerName,
                ),
              ),
            );
          },
        ),
        if (callProvider.isScreenSharing) ...[
          _buildControlButton(
            icon: Icons.stop_screen_share_rounded,
            label: 'Стоп экран',
            active: true,
            danger: true,
            onTap: () {
              HapticFeedback.mediumImpact();
              callProvider.stopScreenShare();
            },
          ),
          _buildControlButton(
            icon: Icons.tune_rounded,
            label: callProvider.streamConfig.badgeLabel,
            active: true,
            accentColor: primaryColor,
            onTap: () => _onTapScreenShare(callProvider),
          ),
        ] else
          _buildControlButton(
            icon: Icons.screen_share_rounded,
            label: 'Экран',
            active: false,
            accentColor: primaryColor,
            onTap: () => _onTapScreenShare(callProvider),
          ),
        _buildControlButton(
          icon: Icons.draw_rounded,
          label: 'Доска',
          active: callProvider.isWhiteboardOpen,
          accentColor: const Color(0xFFAA00FF),
          onTap: () {
            HapticFeedback.selectionClick();
            callProvider.toggleWhiteboard();
          },
        ),
        _buildControlButton(
          icon: Icons.music_note_rounded,
          label: 'Звуки',
          active: false,
          onTap: () {
            HapticFeedback.selectionClick();
            SoundboardSheet.show(
              context,
              callId: widget.callId,
            );
          },
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _endCall(callProvider),
          child: Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x66FF5252),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    bool active = false,
    bool danger = false,
    Color? accentColor,
    required VoidCallback onTap,
  }) {
    final bgColor = danger
        ? Colors.redAccent.withValues(alpha: 0.22)
        : (active
            ? (accentColor ?? Colors.white).withValues(alpha: 0.20)
            : Colors.white.withValues(alpha: 0.08));
    final fgColor = danger ? Colors.redAccent : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: fgColor, size: 22),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}