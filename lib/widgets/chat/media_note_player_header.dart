import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../l10n/app_localizations.dart';
import '../../services/media_playback_coordinator.dart';
import '../../services/video_note_playback_service.dart';
import '../../services/voice_playback_service.dart';

/// Unified top mini-player header bar for Voice Messages and Video Notes («кружочки»).
/// Displayed at the top of the chat whenever audio/video note is playing.
class MediaNotePlayerHeader extends StatefulWidget {
  final VoidCallback? onScrollToActive;

  const MediaNotePlayerHeader({
    Key? key,
    this.onScrollToActive,
  }) : super(key: key);

  @override
  State<MediaNotePlayerHeader> createState() => _MediaNotePlayerHeaderState();
}

class _MediaNotePlayerHeaderState extends State<MediaNotePlayerHeader>
    with SingleTickerProviderStateMixin {
  final VoicePlaybackService _voiceService = VoicePlaybackService();
  final VideoNotePlaybackService _videoService = VideoNotePlaybackService();

  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  VideoPlayerController? _observedVideoController;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    );

    _voiceService.addListener(_onServiceChange);
    _videoService.addListener(_onServiceChange);
    _attachVideoController();
  }

  @override
  void dispose() {
    _observedVideoController?.removeListener(_onVideoTick);
    _voiceService.removeListener(_onServiceChange);
    _videoService.removeListener(_onServiceChange);
    _slideController.dispose();
    super.dispose();
  }

  void _attachVideoController() {
    final ctrl = _videoService.activeController;
    if (_observedVideoController != ctrl) {
      _observedVideoController?.removeListener(_onVideoTick);
      _observedVideoController = ctrl;
      _observedVideoController?.addListener(_onVideoTick);
    }
  }

  void _onVideoTick() {
    if (!mounted) return;
    setState(() {});
  }

  void _onServiceChange() {
    if (!mounted) return;
    _attachVideoController();
    final hasActive = _voiceService.hasActiveAudio || (_videoService.hasActiveVideo && !_videoService.isFloating);
    if (hasActive) {
      if (_slideController.status != AnimationStatus.forward &&
          _slideController.status != AnimationStatus.completed) {
        _slideController.forward();
      }
    } else {
      if (_slideController.status != AnimationStatus.reverse &&
          _slideController.status != AnimationStatus.dismissed) {
        _slideController.reverse();
      }
    }
    setState(() {});
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final hasVoice = _voiceService.hasActiveAudio;
    final hasVideo = _videoService.hasActiveVideo && !_videoService.isFloating;

    if (!hasVoice && !hasVideo && _slideController.value == 0.0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final l10n = AppLocalizations.of(context);

    final bool isVideo = hasVideo && _videoService.activeController != null;
    final String title;
    final String subtitle;
    final bool isPlaying;
    final double progress;
    final double speed;
    final VoidCallback onPlayPause;
    final VoidCallback onSpeed;
    final VoidCallback onClose;
    final VoidCallback onTap;

    if (isVideo) {
      final ctrl = _videoService.activeController!;
      title = _videoService.activeSenderName ?? l10n?.translate('chat_video_note') ?? 'Video message';
      final pos = ctrl.value.position;
      final dur = ctrl.value.duration;
      subtitle = '${l10n?.translate('chat_video_note') ?? 'Video message'} • ${_formatDuration(dur - pos)}';
      isPlaying = ctrl.value.isPlaying;
      progress = (dur.inMilliseconds > 0)
          ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;
      speed = MediaPlaybackCoordinator.instance.playbackSpeed;
      onPlayPause = _videoService.togglePlayPause;
      onSpeed = MediaPlaybackCoordinator.instance.cyclePlaybackSpeed;
      onClose = MediaPlaybackCoordinator.instance.stopAll;
      onTap = () {
        widget.onScrollToActive?.call();
        MediaPlaybackCoordinator.instance.navigateToActiveChat();
      };
    } else {
      title = _voiceService.activeSenderName ?? l10n?.translate('chat_voice_message') ?? 'Voice message';
      final pos = _voiceService.position;
      final dur = _voiceService.duration;
      final durText = dur > Duration.zero
          ? '${_formatDuration(pos)} / ${_formatDuration(dur)}'
          : _formatDuration(pos);
      subtitle = '${l10n?.translate('chat_voice_message') ?? 'Voice message'} • $durText';
      isPlaying = _voiceService.isPlaying;
      progress = (dur.inMilliseconds > 0)
          ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;
      speed = MediaPlaybackCoordinator.instance.playbackSpeed;
      onPlayPause = _voiceService.togglePlayPause;
      onSpeed = MediaPlaybackCoordinator.instance.cyclePlaybackSpeed;
      onClose = MediaPlaybackCoordinator.instance.stopAll;
      onTap = () {
        widget.onScrollToActive?.call();
        MediaPlaybackCoordinator.instance.navigateToActiveChat();
      };
    }

    final speedText = '${speed.toString().replaceAll('.0', '')}X';

    return SizeTransition(
      sizeFactor: _slideAnimation,
      axisAlignment: -1.0,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          height: 44,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xF2202022) : const Color(0xF7FFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black12,
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Main content row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // 1. Media Icon / Thumbnail
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          isVideo ? Icons.videocam_rounded : Icons.graphic_eq_rounded,
                          size: 17,
                          color: primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // 2. Title & Subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // 3. Playback Speed Selector (1X / 1.5X / 2X)
                    GestureDetector(
                      onTap: onSpeed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          speedText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ),
                    ),

                    // 4. Play / Pause Button
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 24,
                        color: primaryColor,
                      ),
                      onPressed: onPlayPause,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),

                    // 5. Close Button
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: Colors.grey),
                      onPressed: onClose,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),

              // Bottom Progress Line
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 2.0,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                    minHeight: 2.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
