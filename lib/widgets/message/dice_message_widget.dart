import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../services/dice_cache_service.dart';
import '../../services/emoji_haptic_service.dart';
import '../../utils/emoji_utils.dart';

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
    _loadCompositions();
  }

  @override
  void didUpdateWidget(covariant DiceMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emoji != widget.emoji || oldWidget.value != widget.value) {
      _loadCompositions();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadCompositions() async {
    final emoji = widget.emoji;
    final val = widget.value;

    // Prefetch both roll and outcome
    if (val != null) {
      DiceCacheService.instance.prefetchDice(emoji, val);
    }

    final rollComp = await DiceCacheService.instance.getDiceComposition(emoji, 1);
    LottieComposition? outcomeComp;
    if (val != null) {
      final outcomeIdx = DiceCacheService.getOutcomeIndex(emoji, val);
      outcomeComp = await DiceCacheService.instance.getDiceComposition(emoji, outcomeIdx);
    }

    if (!mounted) return;

    setState(() {
      _rollComposition = rollComp;
      _outcomeComposition = outcomeComp;
    });

    if (widget.autoPlay && !_hasPlayedOnce && val != null) {
      _hasPlayedOnce = true;
      _playSequence();
    } else if (outcomeComp != null && !_isRolling) {
      // Show final frame of outcome
      _controller.duration = outcomeComp.duration;
      _controller.value = 1.0;
    }
  }

  Future<void> _playSequence() async {
    if (_isRolling) return;
    final val = widget.value ?? 1;

    // Trigger haptic for roll start & landing
    EmojiHapticService.instance.playDiceHaptic(widget.emoji, val);

    if (_rollComposition != null) {
      setState(() => _isRolling = true);
      _controller.duration = _rollComposition!.duration;
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
      _controller.duration = outcomeComp.duration;
      _controller.reset();
      await _controller.forward();
    } else {
      setState(() => _isRolling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentComp = _isRolling ? _rollComposition : (_outcomeComposition ?? _rollComposition);

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
