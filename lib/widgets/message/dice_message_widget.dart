import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../services/dice_cache_service.dart';
import '../../services/emoji_haptic_service.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/haptic_utils.dart';
import 'slot_machine_widget.dart';

/// Interactive Telegram dice game widget (🎲, 🎯, 🏀, ⚽, 🎳, 🎰).
/// Plays rolling animation followed by outcome animation, with authentic
/// Telegram haptic feedback at the moment of landing / goal / bullseye / strike.
class DiceMessageWidget extends StatefulWidget {
  final String emoji;
  final int? value;
  final bool isMe;
  final double size;
  final bool autoPlay;

  const DiceMessageWidget({
    super.key,
    required this.emoji,
    this.value,
    this.isMe = false,
    this.size = 130.0,
    this.autoPlay = false,
  });

  @override
  State<DiceMessageWidget> createState() => _DiceMessageWidgetState();
}

class _DiceMessageWidgetState extends State<DiceMessageWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  LottieComposition? _rollComposition;
  LottieComposition? _outcomeComposition;
  bool _isRolling = false;
  bool _hasPlayedOnce = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    if (!widget.autoPlay) {
      _controller.value = 1.0;
    }
    _loadCompositions();
  }

  HapticBinding? _hapticBinding;

  @override
  void didUpdateWidget(covariant DiceMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emoji != widget.emoji || oldWidget.value != widget.value) {
      _loadCompositions();
    }
  }

  @override
  void dispose() {
    _hapticBinding?.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadCompositions() async {
    final emoji = widget.emoji;
    final val = widget.value ?? 1;

    // Slots (🎰) are handled by dedicated composite SlotMachineWidget
    if (EmojiUtils.diceCodepoint(emoji) == '1f3b0' || emoji == '🎰') {
      return;
    }

    final outcomeIdx = DiceCacheService.getOutcomeIndex(emoji, val);

    // If historical message (!autoPlay), immediately load and display the outcome at final frame
    if (!widget.autoPlay) {
      final outcomeComp = await DiceCacheService.instance.getDiceComposition(emoji, outcomeIdx);
      if (!mounted) return;
      setState(() {
        _outcomeComposition = outcomeComp;
        _isRolling = false;
      });
      if (outcomeComp != null) {
        _controller.duration = outcomeComp.duration;
        _controller.value = 1.0; // Frozen on final outcome frame!
      }
      // Prefetch roll composition in background for replay on tap
      DiceCacheService.instance.getDiceComposition(emoji, 1).then((comp) {
        if (mounted) _rollComposition = comp;
      });
      return;
    }

    // Newly sent message with autoPlay: load roll first, then play sequence
    final rollComp = await DiceCacheService.instance.getDiceComposition(emoji, 1);
    final outcomeComp = await DiceCacheService.instance.getDiceComposition(emoji, outcomeIdx);

    if (!mounted) return;

    setState(() {
      _rollComposition = rollComp;
      _outcomeComposition = outcomeComp;
    });

    if (!_hasPlayedOnce) {
      _hasPlayedOnce = true;
      _playSequence();
    }
  }

  Future<void> _playSequence() async {
    if (_isRolling) return;
    final val = widget.value ?? 1;

    final rollComp = _rollComposition ??
        await DiceCacheService.instance.getDiceComposition(widget.emoji, 1);

    if (!mounted) return;

    if (rollComp != null) {
      setState(() {
        _rollComposition = rollComp;
        _isRolling = true;
      });
      _hapticBinding?.dispose();
      _hapticBinding = null;
      HapticUtils.selection(); // Subtle initial throw / release tap
      _controller.duration = rollComp.duration;
      _controller.reset();
      await _controller.forward();
    }

    if (!mounted) return;

    // Transition to outcome animation
    final outcomeIdx = DiceCacheService.getOutcomeIndex(widget.emoji, val);
    final outcomeComp = _outcomeComposition ??
        await DiceCacheService.instance.getDiceComposition(widget.emoji, outcomeIdx);

    if (!mounted) return;

    if (outcomeComp != null) {
      setState(() {
        _outcomeComposition = outcomeComp;
        _isRolling = false;
      });
      _hapticBinding?.dispose();
      final totalFrames = (outcomeComp.endFrame - outcomeComp.startFrame).round();
      _hapticBinding = EmojiHapticService.instance.attachDiceOutcome(
        _controller,
        widget.emoji,
        val,
        totalFrames: totalFrames > 0 ? totalFrames : 180,
      );
      _controller.duration = outcomeComp.duration;
      _controller.reset();
      await _controller.forward();
    } else {
      setState(() => _isRolling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Delegate 🎰 to composite 5-layer SlotMachineWidget
    if (EmojiUtils.diceCodepoint(widget.emoji) == '1f3b0' || widget.emoji == '🎰') {
      return SlotMachineWidget(
        value: widget.value ?? 1,
        size: widget.size,
        autoPlay: widget.autoPlay,
      );
    }

    // 2. Standard dice (🎲, 🎯, 🏀, ⚽, 🎳)
    final currentComp = _isRolling
        ? _rollComposition
        : (_outcomeComposition ?? (widget.autoPlay ? _rollComposition : null));

    Widget content;
    if (currentComp != null) {
      content = Lottie(
        composition: currentComp,
        controller: _controller,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
      );
    } else {
      // Fallback while loading Lottie
      content = SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: EmojiUtils.appleEmoji(
            widget.emoji,
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

