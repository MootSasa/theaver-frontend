import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../l10n/app_localizations.dart';
import '../../services/chat_service.dart';
import '../../services/voice_note_recorder_service.dart';

/// Full-featured Telegram-style overlay for recording voice messages.
/// Supports:
/// - Pulsing recording dot & live timer.
/// - Real-time animated amplitude waveform bars.
/// - Slide to cancel (swipe left) with trash animation.
/// - Swipe up to lock (hands-free mode) with trash, pause/resume, preview, and send actions.
/// - Reply & quote preview chip.
class VoiceRecordingOverlay extends StatefulWidget {
  final VoiceNoteRecorderService recorderService;
  final VoidCallback onCancel;
  final Function(VoiceRecordResult result) onSend;
  final VoidCallback onTooShort;
  final Offset? buttonPosition;
  final Message? replyToMessage;
  final bool isQuote;
  final String? quoteText;
  final VoidCallback? onCancelReply;

  const VoiceRecordingOverlay({
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
  State<VoiceRecordingOverlay> createState() => VoiceRecordingOverlayState();
}

class VoiceRecordingOverlayState extends State<VoiceRecordingOverlay>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late AnimationController _lockSlideController;

  bool _isLocked = false;
  bool _isSending = false;
  bool _isCancelling = false;
  double _dragOffsetX = 0.0;
  double _dragOffsetY = 0.0;

  static const double _kCancelThreshold = -85.0;
  static const double _kLockThreshold = -70.0;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _lockSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    widget.recorderService.addListener(_onRecorderUpdate);
  }

  void _onRecorderUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.recorderService.removeListener(_onRecorderUpdate);
    if (!_isSending && widget.recorderService.isRecording) {
      widget.recorderService.cancelRecording();
    }
    _fadeController.dispose();
    _pulseController.dispose();
    _lockSlideController.dispose();
    super.dispose();
  }

  /// Updates pointer drag offset from parent gesture detector.
  void updatePointerOffset(double dx, double dy) {
    if (_isLocked || _isSending || _isCancelling) return;

    setState(() {
      _dragOffsetX = dx;
      _dragOffsetY = dy;
    });

    // Check lock threshold (swipe up)
    if (_dragOffsetY <= _kLockThreshold && !_isLocked) {
      _lockRecording();
    }

    // Check cancel threshold (swipe left)
    if (_dragOffsetX <= _kCancelThreshold && !_isCancelling) {
      _cancelRecording();
    }
  }

  /// Handles touch release when not locked.
  void handlePointerUp() {
    if (_isLocked || _isSending || _isCancelling) return;

    if (_dragOffsetX <= _kCancelThreshold) {
      _cancelRecording();
      return;
    }

    // Minimum recording duration: 1 second
    if (widget.recorderService.elapsed.inMilliseconds < 1000) {
      _discardTooShort();
      return;
    }

    _sendRecording();
  }

  void _lockRecording() {
    if (_isLocked) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isLocked = true;
      _dragOffsetX = 0.0;
      _dragOffsetY = 0.0;
    });
    widget.recorderService.setLocked(true);
    _lockSlideController.forward();
  }

  Future<void> _sendRecording() async {
    if (_isSending || _isCancelling) return;
    _isSending = true;
    HapticFeedback.lightImpact();

    try {
      final result = await widget.recorderService.stopRecording();
      if (result != null && result.file.existsSync() && await result.file.length() > 0) {
        widget.onSend(result);
      } else {
        widget.onCancel();
      }
    } catch (e) {
      debugPrint('[VoiceRecordingOverlay] _sendRecording error: $e');
      widget.onCancel();
    }
  }

  Future<void> _cancelRecording() async {
    if (_isCancelling || _isSending) return;
    _isCancelling = true;
    HapticFeedback.heavyImpact();

    await widget.recorderService.cancelRecording();
    if (mounted) {
      widget.onCancel();
    }
  }

  Future<void> _discardTooShort() async {
    if (_isCancelling || _isSending) return;
    _isCancelling = true;

    await widget.recorderService.cancelRecording();
    if (mounted) {
      widget.onTooShort();
      widget.onCancel();
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final elapsedText = _formatDuration(widget.recorderService.elapsed);

    return FadeTransition(
      opacity: _fadeController,
      child: Stack(
        children: [
          // 1. Transparent touch blocker behind overlay when locked
          if (_isLocked)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {},
              ),
            ),

          // 2. Lock pill (when holding and sliding up)
          if (!_isLocked)
            Positioned(
              right: 16,
              bottom: 74 + bottomPadding + (_dragOffsetY.clamp(-90.0, 0.0) * -0.5),
              child: Opacity(
                opacity: (1.0 - (_dragOffsetX.abs() / 60.0)).clamp(0.0, 1.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xE01C1C1E) : const Color(0xF0FFFFFF),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      iconoir.Lock(width: 18, height: 18, color: Colors.grey),
                      SizedBox(height: 4),
                      iconoir.NavArrowUp(width: 16, height: 16, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),

          // 3. Bottom Recording Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reply/Quote banner if attached
                if (widget.replyToMessage != null)
                  _buildReplyBanner(context, isDark, primaryColor),

                // Main Bar Container
                Container(
                  padding: EdgeInsets.fromLTRB(14, 8, 14, 8 + bottomPadding),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xF51E1E20) : const Color(0xF8F7F7F8),
                    border: Border(
                      top: BorderSide(
                        color: isDark ? Colors.white12 : Colors.black12,
                        width: 0.5,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    height: 48,
                    child: _isLocked
                        ? _buildLockedControls(context, primaryColor, elapsedText)
                        : _buildHoldControls(context, primaryColor, elapsedText),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBanner(BuildContext context, bool isDark, Color primaryColor) {
    final senderName = widget.replyToMessage?.senderName ?? 'User';
    final preview = widget.isQuote && widget.quoteText != null
        ? widget.quoteText!
        : (widget.replyToMessage?.content ?? '');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xCC2C2C2E) : const Color(0xEEFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: primaryColor, width: 3.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  preview,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (widget.onCancelReply != null)
            GestureDetector(
              onTap: widget.onCancelReply,
              child: const Icon(Icons.close, size: 16, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildHoldControls(BuildContext context, Color primaryColor, String elapsedText) {
    final slideOffset = _dragOffsetX.clamp(-120.0, 0.0);
    final l10n = AppLocalizations.of(context);
    final cancelHint = l10n?.translate('chat_voice_swipe_cancel') ?? 'Slide to cancel';

    return Row(
      children: [
        // 1. Red flashing recording dot
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.4 + 0.6 * _pulseController.value),
                shape: BoxShape.circle,
              ),
            );
          },
        ),
        const SizedBox(width: 8),

        // 2. Timer
        Text(
          elapsedText,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),

        // 3. Live animated waveform bars
        Expanded(
          child: Transform.translate(
            offset: Offset(slideOffset * 0.4, 0),
            child: _buildLiveWaveform(primaryColor),
          ),
        ),

        // 4. Slide to cancel hint
        Transform.translate(
          offset: Offset(slideOffset, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const iconoir.NavArrowLeft(width: 18, height: 18, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                cancelHint,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),

        // 5. Pulsing microphone icon under finger
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.85 + 0.15 * _pulseController.value),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: iconoir.MicrophoneSolid(width: 22, height: 22, color: Colors.white),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLockedControls(BuildContext context, Color primaryColor, String elapsedText) {
    final isPaused = widget.recorderService.isPaused;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 1. Trash / Discard Button
        IconButton(
          icon: const iconoir.Trash(width: 24, height: 24, color: Colors.redAccent),
          onPressed: _cancelRecording,
          tooltip: 'Discard',
        ),

        // 2. Timer & Live/Static Waveform
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isPaused ? Colors.grey : Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              elapsedText,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),

        // 3. Pause / Resume Button
        IconButton(
          icon: Icon(
            isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            size: 28,
            color: primaryColor,
          ),
          onPressed: () {
            if (isPaused) {
              widget.recorderService.resumeRecording();
            } else {
              widget.recorderService.pauseRecording();
            }
          },
        ),

        // 4. Send Button
        GestureDetector(
          onTap: _sendRecording,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: primaryColor,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: iconoir.SendSolid(width: 20, height: 20, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveWaveform(Color color) {
    final amplitudes = widget.recorderService.liveAmplitudes;
    return SizedBox(
      height: 24,
      child: CustomPaint(
        painter: _LiveWaveformPainter(
          amplitudes: amplitudes,
          color: color.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _LiveWaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final Color color;

  _LiveWaveformPainter({
    required this.amplitudes,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4;

    const double gap = 3.2;
    final int maxBars = (size.width / gap).floor();
    final visibleAmps = amplitudes.length > maxBars
        ? amplitudes.sublist(amplitudes.length - maxBars)
        : amplitudes;

    double x = size.width - (visibleAmps.length * gap);
    final centerY = size.height / 2;

    for (final amp in visibleAmps) {
      final barHeight = math.max(3.0, amp * size.height * 0.9);
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
      x += gap;
    }
  }

  @override
  bool shouldRepaint(_LiveWaveformPainter oldDelegate) => true;
}
