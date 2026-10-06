import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../l10n/app_localizations.dart';
import '../../services/chat_service.dart';
import '../../services/video_note_recorder_service.dart';

/// Full-screen Telegram-style overlay for recording circular video notes («кружочки»).
/// Features:
/// - Cinematic backdrop blur (`BackdropFilter`) dimming the chat behind the circle.
/// - 1:1 circular live viewfinder (`ClipOval`) with breathing pulse aura and no time limit.
/// - Elapsed timer badge with pulsating red recording dot.
/// - Swipe up to lock (hands-free mode) with flip camera, pause, trash, and send actions.
/// - Slide to cancel with Telegram trash can animation (shrinking & flying into trash).
/// - Short-press (< 1s) discard with hint tooltip.
class RoundVideoRecordingOverlay extends StatefulWidget {
  final VideoNoteRecorderService recorderService;
  final VoidCallback onCancel;
  final Function(File file) onSend;
  final VoidCallback onTooShort;
  final Offset? buttonPosition;
  final Message? replyToMessage;
  final bool isQuote;
  final String? quoteText;
  final VoidCallback? onCancelReply;

  const RoundVideoRecordingOverlay({
    Key? key,
    required this.recorderService,
    required this.onCancel,
    required this.onSend,
    required this.onTooShort,
    this.buttonPosition,
    this.replyToMessage,
    this.isQuote = false,
    this.quoteText,
    this.onCancelReply,
  }) : super(key: key);

  @override
  State<RoundVideoRecordingOverlay> createState() =>
      _RoundVideoRecordingOverlayState();
}

class _RoundVideoRecordingOverlayState extends State<RoundVideoRecordingOverlay>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late AnimationController _trashController;
  late AnimationController _flipController;

  bool _isLocked = false;
  bool _isSending = false;
  bool _isCancelling = false;
  double _dragOffsetX = 0.0;
  double _dragOffsetY = 0.0;

  static const double _kCircleDiameter = 240.0;
  static const double _kCancelThreshold = -85.0;
  static const double _kLockThreshold = -70.0;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _trashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    widget.recorderService.addListener(_onRecorderUpdate);
  }

  void _onRecorderUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.recorderService.removeListener(_onRecorderUpdate);
    _fadeController.dispose();
    _pulseController.dispose();
    _trashController.dispose();
    _flipController.dispose();
    super.dispose();
  }

  /// Called by parent or gesture detector when finger moves
  void updatePointerOffset(double dx, double dy) {
    if (_isLocked || _isCancelling || _isSending) return;

    setState(() {
      _dragOffsetX = dx.clamp(-160.0, 0.0);
      _dragOffsetY = dy.clamp(-120.0, 0.0);
    });

    // Check lock threshold
    if (_dragOffsetY <= _kLockThreshold && !_isLocked) {
      HapticFeedback.mediumImpact();
      setState(() {
        _isLocked = true;
        _dragOffsetX = 0.0;
        _dragOffsetY = 0.0;
      });
      return;
    }

    // Check cancel threshold
    if (_dragOffsetX <= _kCancelThreshold && !_isCancelling) {
      _triggerTrashCancel();
    }
  }

  /// Called by parent when finger is released without locking
  void handlePointerUp() {
    if (_isLocked || _isCancelling || _isSending) return;

    if (widget.recorderService.elapsed.inMilliseconds < 1000) {
      // Too short (< 1s) -> discard
      _discardTooShort();
    } else {
      // Normal release -> send immediately
      _finishAndSend();
    }
  }

  Future<void> _triggerTrashCancel() async {
    _isCancelling = true;
    HapticFeedback.heavyImpact();
    setState(() {});

    await _trashController.forward();
    await widget.recorderService.cancelRecording();
    widget.onCancel();
  }

  Future<void> _discardTooShort() async {
    _isCancelling = true;
    await widget.recorderService.cancelRecording();
    widget.onTooShort();
  }

  Future<void> _finishAndSend() async {
    if (_isSending) return;
    setState(() => _isSending = true);

    final file = await widget.recorderService.stopRecording();
    if (file != null && mounted) {
      widget.onSend(file);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.translate('chat_upload_error') ??
                'Failed to record video note',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      widget.onCancel();
    }
  }

  Future<void> _flipCamera() async {
    _flipController.forward(from: 0.0);
    HapticFeedback.selectionClick();
    await widget.recorderService.flipCamera();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final diameter = math.min(size.width * 0.68, _kCircleDiameter);

    return FadeTransition(
      opacity: _fadeController,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Cinematic Telegram Backdrop Blur
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
              child: Container(
                color: Colors.black.withValues(alpha: 0.42),
              ),
            ),
          ),

          // 2. Circular Camera Viewfinder with Breathing Aura
          if (!_isCancelling)
            Positioned(
              bottom: size.height * 0.18 - (_dragOffsetY * 0.4),
              child: Transform.translate(
                offset: Offset(_dragOffsetX * 0.4, 0),
                child: _buildCameraViewfinder(diameter, theme),
              ),
            )
          else
            // Telegram Flying-to-Trash animation
            AnimatedBuilder(
              animation: _trashController,
              builder: (context, child) {
                final progress = _trashController.value;
                final scale = (1.0 - progress * 0.9).clamp(0.05, 1.0);
                final dx = -progress * (size.width * 0.35);
                final dy = progress * 60.0;

                return Positioned(
                  bottom: size.height * 0.18 + dy,
                  left: (size.width - diameter) / 2 + dx,
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: (1.0 - progress).clamp(0.0, 1.0),
                      child: _buildCameraCircle(diameter),
                    ),
                  ),
                );
              },
            ),

          // 3. Reply Preview Banner (when replying/quoting)
          if (!_isCancelling) _buildReplyBanner(theme),

          // 4. Slide-to-cancel & Lock gestures track (when NOT locked)
          if (!_isLocked && !_isCancelling) ...[
            _buildSlideToCancelTrack(l10n, size),
            _buildSwipeUpLockIndicator(l10n, size),
          ],

          // 5. Hands-free Controls Bar (when LOCKED)
          if (_isLocked && !_isCancelling)
            _buildHandsFreeControlBar(l10n, theme, size),
        ],
      ),
    );
  }

  Widget _buildReplyBanner(ThemeData theme) {
    if (widget.replyToMessage == null) return const SizedBox.shrink();
    final reply = widget.replyToMessage!;
    final replyText = widget.quoteText ?? reply.content;
    return Positioned(
      top: 48,
      left: 20,
      right: 20,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.reply_rounded, color: Colors.white70, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reply.senderName.isNotEmpty ? reply.senderName : 'Сообщение',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (replyText.isNotEmpty)
                      Text(
                        replyText.replaceAll('\n', ' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.onCancelReply != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onCancelReply,
                  child: const Icon(Icons.close, color: Colors.white70, size: 16),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Circular camera viewfinder with pulse aura and top timer badge
  Widget _buildCameraViewfinder(double diameter, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top elapsed timer badge
        _buildTimerBadge(),
        const SizedBox(height: 12),

        // Clean circular camera viewfinder without pulsating aura
        Stack(
          alignment: Alignment.center,
          children: [
            // Camera Circle Preview
            _buildCameraCircle(diameter),

            // Sending indicator overlay
            if (_isSending)
              Container(
                width: diameter,
                height: diameter,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black45,
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCameraCircle(double diameter) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
          width: 2.0,
        ),
      ),
      child: ClipOval(
        child: AnimatedBuilder(
          animation: _flipController,
          builder: (context, child) {
            final angle = _flipController.value * math.pi;
            final isBack = _flipController.value >= 0.5;

            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002)
                ..rotateY(angle + (isBack ? math.pi : 0)),
              child: widget.recorderService.cameraController != null &&
                      widget.recorderService.cameraController!.value.isInitialized
                  ? FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: diameter,
                        height: diameter,
                        child: CameraPreview(
                          widget.recorderService.cameraController!,
                        ),
                      ),
                    )
                  : (widget.recorderService.renderer != null &&
                          widget.recorderService.isInitialized
                      ? FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: diameter,
                            height: diameter,
                            child: RTCVideoView(
                              widget.recorderService.renderer!,
                              mirror: widget.recorderService.isFrontCamera,
                              objectFit:
                                  RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            ),
                          ),
                        )
                      : Container(
                          color: Colors.black87,
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white70,
                            ),
                          ),
                        )),
            );
          },
        ),
      ),
    );
  }

  /// Floating timer badge at top of circle with pulsing red dot
  Widget _buildTimerBadge() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing Red Recording Dot
              Opacity(
                opacity: 0.4 + (_pulseController.value * 0.6),
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                _formatDuration(widget.recorderService.elapsed),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Slide-to-cancel hint on the left of the button
  Widget _buildSlideToCancelTrack(AppLocalizations? l10n, Size size) {
    final cancelOpacity =
        (1.0 - (_dragOffsetX.abs() / 100.0)).clamp(0.0, 1.0);

    return Positioned(
      bottom: size.height * 0.05,
      left: size.width * 0.12,
      child: Opacity(
        opacity: cancelOpacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Shimmer / moving chevron
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(-_pulseController.value * 5.0, 0),
                  child: const iconoir.NavArrowLeft(
                    width: 20,
                    height: 20,
                    color: Colors.white70,
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
            Text(
              l10n?.translate('chat_video_note_swipe_cancel') ??
                  'Slide to cancel',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Swipe up to lock vertical capsule indicator
  Widget _buildSwipeUpLockIndicator(AppLocalizations? l10n, Size size) {
    return Positioned(
      bottom: size.height * 0.11 - (_dragOffsetY * 0.5),
      right: size.width * 0.06,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const iconoir.Lock(
              width: 20,
              height: 20,
              color: Colors.white,
            ),
            const SizedBox(height: 6),
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, -_pulseController.value * 4.0),
                  child: const iconoir.NavArrowUp(
                    width: 16,
                    height: 16,
                    color: Colors.white70,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Hands-Free Controls Bar when recording is locked
  Widget _buildHandsFreeControlBar(
    AppLocalizations? l10n,
    ThemeData theme,
    Size size,
  ) {
    return Positioned(
      bottom: size.height * 0.04,
      left: size.width * 0.08,
      right: size.width * 0.08,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Discard / Trash Button
            GestureDetector(
              onTap: () {
                HapticFeedback.heavyImpact();
                _triggerTrashCancel();
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.redAccent,
                ),
                child: const Center(
                  child: iconoir.Trash(
                    width: 22,
                    height: 22,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // Flip Camera Button
            GestureDetector(
              onTap: _flipCamera,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                child: const Center(
                  child: iconoir.Refresh(
                    width: 22,
                    height: 22,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // Send Video Note Button
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                _finishAndSend();
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                ),
                child: const Center(
                  child: iconoir.SendSolid(
                    width: 24,
                    height: 24,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
