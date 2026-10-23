import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../services/dice_cache_service.dart';
import '../../services/emoji_haptic_service.dart';
import '../../utils/emoji_utils.dart';

/// Authentic Telegram 5-layer composite Slot Machine widget (🎰).
///
/// Composites 5 synchronized layers (512x512 canvas at 60 fps):
/// - Layer 0 (Background): casing and idle/win lights (`1f3b0_1` or `1f3b0_2`)
/// - Layer 1 (Left Reel): outcome animation (`1f3b0_4..8`)
/// - Layer 2 (Center Reel): outcome animation (`1f3b0_10..14`)
/// - Layer 3 (Right Reel): outcome animation (`1f3b0_16..20`)
/// - Layer 4 (Front / Lever): machine casing and lever pull (`1f3b0_3`)
///
/// For historical messages (autoPlay == false), immediately renders the
/// final settled state on frame 180 (value = 1.0) with all 3 stopped reels showing.
/// On tap, triggers authentic lever pull, reel spins, and Telegram haptic feedback.
class SlotMachineWidget extends StatefulWidget {
  final int value;
  final double size;
  final bool autoPlay;

  const SlotMachineWidget({
    super.key,
    required this.value,
    this.size = 130.0,
    this.autoPlay = false,
  });

  @override
  State<SlotMachineWidget> createState() => _SlotMachineWidgetState();
}

class _SlotMachineWidgetState extends State<SlotMachineWidget>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _leverController;
  late AnimationController _bgController;

  LottieComposition? _idleBgComp;
  LottieComposition? _winBgComp;
  LottieComposition? _leftComp;
  LottieComposition? _centerComp;
  LottieComposition? _rightComp;
  LottieComposition? _leverComp;

  bool _isRolling = false;
  bool _hasPlayedOnce = false;
  bool _showWinBackground = false;
  late SlotReelIndices _indices;

  @override
  void initState() {
    super.initState();
    _indices = DiceCacheService.getSlotIndices(widget.value);
    _showWinBackground = (!widget.autoPlay && _indices.isWin);

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _leverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 667),
    );
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1667),
    );

    _mainController.addListener(_onMainFrame);

    if (!widget.autoPlay) {
      _mainController.value = 1.0;
      _leverController.value = 1.0;
      if (_indices.isWin) {
        _bgController.repeat();
      } else {
        _bgController.value = 1.0;
      }
    }

    _loadCompositions();
  }

  void _onMainFrame() {
    // Total duration is 3000ms at 60fps = 180 frames.
    // Right reel lands at frame 84, meaning all 3 reels have fully stopped.
    final frame = (_mainController.value * 180).floor();
    if (_indices.isWin && frame >= 84 && !_showWinBackground) {
      if (mounted) {
        setState(() {
          _showWinBackground = true;
        });
        _bgController.repeat();
      }
    }
  }

  @override
  void didUpdateWidget(covariant SlotMachineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _indices = DiceCacheService.getSlotIndices(widget.value);
      _showWinBackground = (!widget.autoPlay && _indices.isWin);
      _loadCompositions();
    }
  }

  HapticBinding? _hapticBinding;

  @override
  void dispose() {
    _mainController.removeListener(_onMainFrame);
    _hapticBinding?.dispose();
    _mainController.dispose();
    _leverController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  Future<void> _loadCompositions() async {
    const cp = '1f3b0';
    _indices = DiceCacheService.getSlotIndices(widget.value);

    final idleBgFuture = DiceCacheService.instance.getDiceComposition(cp, 1);
    final winBgFuture = _indices.isWin
        ? DiceCacheService.instance.getDiceComposition(cp, 2)
        : Future.value(null);
    final leverFuture = DiceCacheService.instance.getDiceComposition(cp, _indices.leverIndex);
    final leftFuture = DiceCacheService.instance.getDiceComposition(cp, _indices.leftOutcomeIndex);
    final centerFuture = DiceCacheService.instance.getDiceComposition(cp, _indices.centerOutcomeIndex);
    final rightFuture = DiceCacheService.instance.getDiceComposition(cp, _indices.rightOutcomeIndex);

    final results = await Future.wait([
      idleBgFuture,
      winBgFuture,
      leverFuture,
      leftFuture,
      centerFuture,
      rightFuture,
    ]);

    if (!mounted) return;

    setState(() {
      _idleBgComp = results[0];
      _winBgComp = results[1];
      _leverComp = results[2];
      _leftComp = results[3];
      _centerComp = results[4];
      _rightComp = results[5];
    });

    if (widget.autoPlay && !_hasPlayedOnce) {
      _hasPlayedOnce = true;
      _playSequence();
    } else if (!_isRolling) {
      _mainController.value = 1.0;
      _leverController.value = 1.0;
      if (_indices.isWin) {
        _bgController.repeat();
      } else {
        _bgController.value = 1.0;
      }
    }
  }

  Future<void> _playSequence() async {
    if (_isRolling) return;
    setState(() {
      _isRolling = true;
      _showWinBackground = false;
    });
    _bgController.stop();
    _bgController.value = 0.0;

    // Frame-accurate synchronized Telegram haptics for slot roll, stops, and jackpot
    _hapticBinding?.dispose();
    _hapticBinding = EmojiHapticService.instance.attachSlotMachine(
      _mainController,
      widget.value,
      totalFrames: 180,
    );

    // 1. Pull lever
    _leverController.forward(from: 0.0);

    // 2. Spin reels
    final future = _mainController.forward(from: 0.0);

    try {
      await future.orCancel;
    } catch (_) {
      // Ignored if cancelled / disposed
    }

    if (!mounted) return;
    setState(() => _isRolling = false);
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_leftComp != null && _centerComp != null && _rightComp != null) {
      final bgComp = _showWinBackground ? _winBgComp : _idleBgComp;
      content = SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Layer 0: Background (static casing during roll; flashing siren only after all 3 reels stop on win)
            if (bgComp != null)
              Lottie(
                composition: bgComp,
                controller: _showWinBackground ? _bgController : null,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
              ),
            // Layer 1: Left Reel
            Lottie(
              composition: _leftComp!,
              controller: _mainController,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
            ),
            // Layer 2: Center Reel
            Lottie(
              composition: _centerComp!,
              controller: _mainController,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
            ),
            // Layer 3: Right Reel
            Lottie(
              composition: _rightComp!,
              controller: _mainController,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
            ),
            // Layer 4: Front Casing and Lever
            if (_leverComp != null)
              Lottie(
                composition: _leverComp!,
                controller: _leverController,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
              ),
          ],
        ),
      );
    } else {
      // Shimmer/fallback placeholder while compositions load
      content = SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: EmojiUtils.appleEmoji(
            '🎰',
            size: widget.size * 0.65,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _playSequence,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}
