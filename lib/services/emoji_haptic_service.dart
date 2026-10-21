import 'dart:async';
import 'package:flutter/animation.dart';
import '../utils/haptic_utils.dart';

/// Represents a frame-synchronized binding between an AnimationController and
/// a sequence of haptic feedback triggers.
class HapticBinding {
  final Animation<double> animation;
  final int totalFrames;
  final Map<int, VoidCallback> frameActions;
  final Set<int> _triggered = {};
  late final VoidCallback _listener;
  bool _isDisposed = false;

  HapticBinding({
    required this.animation,
    required this.totalFrames,
    required this.frameActions,
  }) {
    _listener = _onTick;
    animation.addListener(_listener);
  }

  void _onTick() {
    if (_isDisposed) return;
    final val = animation.value;
    if (val <= 0.0) {
      _triggered.clear();
      return;
    }
    final currentFrame = (val * totalFrames).floor();
    for (final entry in frameActions.entries) {
      if (currentFrame >= entry.key && !_triggered.contains(entry.key)) {
        _triggered.add(entry.key);
        entry.value();
      }
    }
  }

  /// Resets triggered flags to allow replay from frame 0.
  void reset() {
    _triggered.clear();
  }

  /// Detaches the listener from the animation controller and cancels pending timers.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    animation.removeListener(_listener);
    _triggered.clear();
  }
}

/// Service responsible for authentic Telegram-like haptic feedback
/// for interactive emojis, animated stickers, and dice games.
/// Supports both frame-accurate AnimationController bindings and standalone playback.
class EmojiHapticService {
  EmojiHapticService._();
  static final EmojiHapticService instance = EmojiHapticService._();

  final List<Timer> _activeTimers = [];

  void _schedule(int milliseconds, VoidCallback action) {
    if (milliseconds <= 0) {
      action();
      return;
    }
    final timer = Timer(Duration(milliseconds: milliseconds), () {
      action();
    });
    _activeTimers.add(timer);
  }

  /// Cancels all scheduled haptic feedback pulses (e.g. on navigate away or unmount).
  void cancelAll() {
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    _activeTimers.clear();
  }

  // ---------------------------------------------------------------------------
  // Frame-Accurate Controller Bindings
  // ---------------------------------------------------------------------------

  /// Attaches frame-accurate haptic feedback to an AnimationController for interactive emojis.
  HapticBinding attachInteractiveEmoji(
    Animation<double> animation,
    String emoji, {
    int totalFrames = 180,
  }) {
    final trimmed = emoji.trim();
    final Map<int, VoidCallback> actions = {};

    // 1. ❤️ Hearts: canonical Telegram HeartbeatHaptic (3 heartbeat cycles: 6 pulses)
    if (_isHeart(trimmed)) {
      actions[0] = () => HapticUtils.impact();
      actions[12] = () => HapticUtils.tap();
      actions[60] = () => HapticUtils.impact();
      actions[72] = () => HapticUtils.tap();
      actions[120] = () => HapticUtils.impact();
      actions[132] = () => HapticUtils.tap();
      return HapticBinding(
        animation: animation,
        totalFrames: totalFrames,
        frameActions: actions,
      );
    }

    // 2. 🍑 Peach: canonical Telegram PeachHaptic (slap impact + jiggle ripples)
    if (trimmed == '🍑' || trimmed == '1f351') {
      const frames = 120;
      actions[30] = () => HapticUtils.tap();
      actions[35] = () => HapticUtils.heavy(); // Slap impact
      actions[45] = () => HapticUtils.impact(); // Ripple 1
      actions[54] = () => HapticUtils.selection(); // Jiggle settling
      return HapticBinding(
        animation: animation,
        totalFrames: frames,
        frameActions: actions,
      );
    }

    // 3. ⚰️ Coffin: canonical Telegram CoffinHaptic (creak, swing open, lid slam shut)
    if (trimmed == '⚰️' || trimmed == '⚰' || trimmed == '26b0' || trimmed == '26b0-fe0f') {
      actions[24] = () => HapticUtils.impact();
      actions[36] = () => HapticUtils.heavy();
      actions[162] = () => HapticUtils.heavy(); // Slam shut
      return HapticBinding(
        animation: animation,
        totalFrames: totalFrames,
        frameActions: actions,
      );
    }

    // 4. Other interactive emojis with calibrated keyframes
    switch (trimmed) {
      case '👏':
      case '1f44f':
        // 6 distinct claps separated by 19 frames
        const frames = 130;
        actions[14] = () => HapticUtils.impact();
        actions[33] = () => HapticUtils.impact();
        actions[52] = () => HapticUtils.impact();
        actions[71] = () => HapticUtils.tap();
        actions[90] = () => HapticUtils.tap();
        actions[109] = () => HapticUtils.tap();
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '💣':
      case '1f4a3':
        actions[0] = () => HapticUtils.selection();
        actions[50] = () => HapticUtils.tap();
        actions[75] = () => HapticUtils.impact();
        actions[98] = () {
          HapticUtils.heavy();
          _schedule(60, () => HapticUtils.impact());
          _schedule(140, () => HapticUtils.impact());
        };
        break;

      case '🍾':
      case '1f37e':
        actions[0] = () => HapticUtils.selection();
        actions[33] = () => HapticUtils.heavy(); // Cork pop
        actions[46] = () => HapticUtils.impact(); // Foam erupts
        actions[68] = () => HapticUtils.tap(); // Fizz
        break;

      case '🍆':
      case '1f346':
        actions[0] = () => HapticUtils.selection();
        actions[38] = () => HapticUtils.tap();
        actions[62] = () => HapticUtils.heavy(); // Whip snap up
        actions[79] = () => HapticUtils.impact();
        break;

      case '💩':
      case '1f4a9':
        actions[0] = () => HapticUtils.selection();
        actions[31] = () => HapticUtils.impact(); // Plop compression
        actions[49] = () => HapticUtils.tap(); // Rebound
        break;

      case '🤮':
      case '1f92e':
        actions[26] = () => HapticUtils.selection();
        actions[52] = () => HapticUtils.selection();
        actions[89] = () => HapticUtils.heavy(); // Puke eruption
        actions[105] = () => HapticUtils.impact();
        break;

      case '👍':
      case '1f44d':
        const frames = 116;
        actions[0] = () => HapticUtils.selection();
        actions[21] = () => HapticUtils.tap();
        actions[45] = () => HapticUtils.heavy(); // Pop up
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '👎':
      case '1f44e':
        actions[0] = () => HapticUtils.selection();
        actions[22] = () => HapticUtils.tap();
        actions[48] = () => HapticUtils.heavy();
        break;

      case '🎉':
      case '🎊':
      case '1f389':
      case '1f38a':
        actions[0] = () => HapticUtils.selection();
        actions[74] = () => HapticUtils.heavy(); // Popper shot
        actions[99] = () => HapticUtils.tap(); // Confetti
        break;

      case '🎈':
      case '1f388':
        actions[0] = () => HapticUtils.selection();
        actions[45] = () => HapticUtils.impact();
        actions[83] = () => HapticUtils.tap();
        break;

      case '🔥':
      case '1f525':
        actions[0] = () => HapticUtils.impact();
        actions[19] = () => HapticUtils.tap();
        actions[49] = () => HapticUtils.tap();
        actions[79] = () => HapticUtils.tap();
        break;

      case '⚡':
      case '26a1':
        actions[0] = () => HapticUtils.heavy();
        actions[7] = () => HapticUtils.impact();
        actions[15] = () => HapticUtils.tap();
        break;

      case '💋':
      case '👄':
      case '1f48b':
      case '1f444':
        actions[0] = () => HapticUtils.selection();
        actions[30] = () => HapticUtils.impact(); // Kiss smack
        actions[45] = () => HapticUtils.tap(); // Heart flies
        break;

      case '🎆':
      case '🎇':
      case '1f386':
      case '1f387':
        actions[0] = () => HapticUtils.selection();
        actions[36] = () => HapticUtils.heavy();
        actions[51] = () => HapticUtils.tap();
        actions[63] = () => HapticUtils.tap();
        break;

      default:
        break;
    }

    return HapticBinding(
      animation: animation,
      totalFrames: totalFrames,
      frameActions: actions,
    );
  }

  /// Attaches frame-accurate haptic feedback to the outcome phase AnimationController of a dice roll.
  HapticBinding attachDiceOutcome(
    Animation<double> animation,
    String emoji,
    int value, {
    int totalFrames = 180,
  }) {
    final trimmed = emoji.trim();
    final Map<int, VoidCallback> actions = {};

    // 1. 🏀 Basketball
    if (trimmed == '🏀' || trimmed == '1f3c0') {
      if (value == 1) {
        // Miss / airball
        actions[50] = () => HapticUtils.impact();
        actions[100] = () => HapticUtils.tap();
      } else if (value >= 2 && value <= 3) {
        // Rim hit and bounce out + 3 floor bounces
        actions[75] = () => HapticUtils.impact();
        actions[102] = () => HapticUtils.selection();
        actions[120] = () => HapticUtils.heavy();
        actions[132] = () => HapticUtils.impact();
        actions[156] = () => HapticUtils.tap();
      } else {
        // Scored basket (4..5): net swish + 3 floor bounces
        actions[75] = () => HapticUtils.impact();
        actions[119] = () => HapticUtils.heavy();
        actions[131] = () => HapticUtils.impact();
        actions[156] = () => HapticUtils.tap();
      }
    }
    // 2. ⚽ Football
    else if (trimmed == '⚽' || trimmed == '26bd') {
      if (value == 1) {
        actions[2] = () => HapticUtils.tap();
        actions[45] = () => HapticUtils.selection();
      } else if (value == 2) {
        actions[2] = () => HapticUtils.impact();
        actions[44] = () => HapticUtils.heavy(); // Crossbar clang
        actions[120] = () => HapticUtils.impact();
        actions[141] = () => HapticUtils.tap();
      } else {
        actions[2] = () => HapticUtils.impact();
        actions[44] = () => HapticUtils.heavy(); // Net strike
        actions[53] = () => HapticUtils.impact();
        actions[112] = () => HapticUtils.impact();
        actions[138] = () => HapticUtils.tap();
      }
    }
    // 3. 🎲 Dice (1..6)
    else if (trimmed == '🎲' || trimmed == '1f3b2') {
      actions[0] = () => HapticUtils.selection();
      actions[30] = () => HapticUtils.tap(); // 1st table bounce
      actions[60] = () => HapticUtils.impact(); // 2nd table bounce
      actions[80] = () => HapticUtils.heavy(); // Settle on face
      if (value == 6) {
        actions[89] = () => HapticUtils.tap(); // Lucky 6
      }
    }
    // 4. 🎳 Bowling (1..6)
    else if (trimmed == '🎳' || trimmed == '1f3b3') {
      if (value == 1) {
        actions[60] = () => HapticUtils.selection(); // Gutter
      } else if (value >= 2 && value <= 5) {
        actions[90] = () => HapticUtils.heavy(); // Pins hit
        actions[99] = () => HapticUtils.impact();
        actions[108] = () => HapticUtils.tap();
      } else {
        actions[90] = () => HapticUtils.heavy(); // Strike hit
        actions[94] = () {
          HapticUtils.heavy();
          _schedule(70, () => HapticUtils.impact());
        };
        actions[107] = () => HapticUtils.impact();
      }
    }
    // 5. 🎯 Darts (1..6)
    else if (trimmed == '🎯' || trimmed == '1f3af') {
      const frames = 100;
      if (value == 1) {
        actions[0] = () => HapticUtils.selection();
      } else if (value >= 2 && value <= 5) {
        actions[59] = () => HapticUtils.impact();
      } else {
        actions[59] = () => HapticUtils.heavy(); // Bullseye!
        actions[67] = () => HapticUtils.impact(); // Target resonance
      }
      return HapticBinding(
        animation: animation,
        totalFrames: frames,
        frameActions: actions,
      );
    }

    return HapticBinding(
      animation: animation,
      totalFrames: totalFrames,
      frameActions: actions,
    );
  }

  /// Attaches frame-accurate haptic feedback to the main AnimationController of the slot machine.
  HapticBinding attachSlotMachine(
    Animation<double> animation,
    int value, {
    int totalFrames = 180,
  }) {
    final Map<int, VoidCallback> actions = {
      0: () => HapticUtils.impact(), // Lever pull
      65: () => HapticUtils.selection(), // Left reel stop
      83: () => HapticUtils.selection(), // Center reel stop
      101: () => HapticUtils.selection(), // Right reel stop
    };

    final isJackpot = (value == 1 || value == 22 || value == 43 || value == 64);
    if (isJackpot) {
      actions[111] = () {
        HapticUtils.heavy();
        _schedule(70, () => HapticUtils.impact());
        _schedule(150, () => HapticUtils.heavy());
        _schedule(230, () => HapticUtils.tap());
      };
    }

    return HapticBinding(
      animation: animation,
      totalFrames: totalFrames,
      frameActions: actions,
    );
  }

  // ---------------------------------------------------------------------------
  // Standalone playback (fallback for non-controller callers)
  // ---------------------------------------------------------------------------

  /// Plays authentic Telegram haptic feedback for interactive emojis based on millisecond timers.
  void playInteractiveEmojiHaptic(String emoji) {
    cancelAll();
    final trimmed = emoji.trim();

    if (_isHeart(trimmed)) {
      _schedule(0, () => HapticUtils.impact());
      _schedule(200, () => HapticUtils.tap());
      _schedule(1000, () => HapticUtils.impact());
      _schedule(1200, () => HapticUtils.tap());
      _schedule(2000, () => HapticUtils.impact());
      _schedule(2200, () => HapticUtils.tap());
      return;
    }

    if (trimmed == '🍑' || trimmed == '1f351') {
      _schedule(500, () => HapticUtils.tap());
      _schedule(580, () => HapticUtils.heavy());
      _schedule(750, () => HapticUtils.impact());
      _schedule(900, () => HapticUtils.selection());
      return;
    }

    if (trimmed == '⚰️' || trimmed == '⚰' || trimmed == '26b0' || trimmed == '26b0-fe0f') {
      _schedule(400, () => HapticUtils.impact());
      _schedule(600, () => HapticUtils.heavy());
      _schedule(2700, () => HapticUtils.heavy());
      return;
    }

    switch (trimmed) {
      case '👏':
      case '1f44f':
        _schedule(233, () => HapticUtils.impact());
        _schedule(550, () => HapticUtils.impact());
        _schedule(867, () => HapticUtils.impact());
        _schedule(1183, () => HapticUtils.tap());
        _schedule(1500, () => HapticUtils.tap());
        _schedule(1817, () => HapticUtils.tap());
        break;

      case '🎉':
      case '🎊':
      case '1f389':
      case '1f38a':
        HapticUtils.selection();
        _schedule(1233, () => HapticUtils.heavy());
        _schedule(1650, () => HapticUtils.tap());
        break;

      case '🎈':
      case '1f388':
        HapticUtils.selection();
        _schedule(750, () => HapticUtils.impact());
        _schedule(1383, () => HapticUtils.tap());
        break;

      case '💣':
      case '1f4a3':
        HapticUtils.selection();
        _schedule(833, () => HapticUtils.tap());
        _schedule(1250, () => HapticUtils.impact());
        _schedule(1633, () {
          HapticUtils.heavy();
          _schedule(60, () => HapticUtils.impact());
          _schedule(140, () => HapticUtils.impact());
        });
        break;

      case '🍾':
      case '1f37e':
        HapticUtils.selection();
        _schedule(550, () => HapticUtils.heavy());
        _schedule(767, () => HapticUtils.impact());
        _schedule(1133, () => HapticUtils.tap());
        break;

      case '🍆':
      case '1f346':
        HapticUtils.selection();
        _schedule(633, () => HapticUtils.tap());
        _schedule(1033, () => HapticUtils.heavy());
        _schedule(1317, () => HapticUtils.impact());
        break;

      case '💩':
      case '1f4a9':
        HapticUtils.selection();
        _schedule(517, () => HapticUtils.impact());
        _schedule(817, () => HapticUtils.tap());
        break;

      case '🤮':
      case '1f92e':
        _schedule(433, () => HapticUtils.selection());
        _schedule(867, () => HapticUtils.selection());
        _schedule(1483, () => HapticUtils.heavy());
        _schedule(1750, () => HapticUtils.impact());
        break;

      case '🔥':
      case '1f525':
        HapticUtils.impact();
        _schedule(317, () => HapticUtils.tap());
        _schedule(817, () => HapticUtils.tap());
        _schedule(1317, () => HapticUtils.tap());
        break;

      case '👍':
      case '1f44d':
        HapticUtils.selection();
        _schedule(350, () => HapticUtils.tap());
        _schedule(750, () => HapticUtils.heavy());
        break;

      case '👎':
      case '1f44e':
        HapticUtils.selection();
        _schedule(367, () => HapticUtils.tap());
        _schedule(800, () => HapticUtils.heavy());
        break;

      case '⚡':
      case '26a1':
        HapticUtils.heavy();
        _schedule(117, () => HapticUtils.impact());
        _schedule(250, () => HapticUtils.tap());
        break;

      case '🎆':
      case '🎇':
      case '1f386':
      case '1f387':
        HapticUtils.selection();
        _schedule(600, () => HapticUtils.heavy());
        _schedule(850, () => HapticUtils.tap());
        _schedule(1050, () => HapticUtils.tap());
        break;

      case '💋':
      case '👄':
      case '1f48b':
      case '1f444':
        HapticUtils.selection();
        _schedule(500, () => HapticUtils.impact());
        _schedule(750, () => HapticUtils.tap());
        break;

      default:
        break;
    }
  }

  /// Plays synchronized haptic feedback for a dice roll and outcome collision.
  void playDiceHaptic(String emoji, int value) {
    cancelAll();
    final trimmed = emoji.trim();

    // 🎲 Dice (1..6)
    if (trimmed == '🎲' || trimmed == '1f3b2') {
      HapticUtils.selection();
      _schedule(500, () => HapticUtils.tap());
      _schedule(1000, () => HapticUtils.impact());
      _schedule(1330, () => HapticUtils.heavy());
      if (value == 6) {
        _schedule(1480, () => HapticUtils.tap());
      }
      return;
    }

    // 🎯 Darts (1..6)
    if (trimmed == '🎯' || trimmed == '1f3af') {
      HapticUtils.selection();
      if (value >= 2 && value <= 5) {
        _schedule(980, () => HapticUtils.impact());
      } else if (value == 6) {
        _schedule(980, () => HapticUtils.heavy());
        _schedule(1120, () => HapticUtils.impact());
      }
      return;
    }

    // 🏀 Basketball (1..5)
    if (trimmed == '🏀' || trimmed == '1f3c0') {
      HapticUtils.tap();
      if (value == 1) {
        _schedule(830, () => HapticUtils.impact());
        _schedule(1660, () => HapticUtils.tap());
      } else if (value >= 2 && value <= 3) {
        _schedule(1250, () => HapticUtils.impact());
        _schedule(1700, () => HapticUtils.selection());
        _schedule(2000, () => HapticUtils.heavy());
        _schedule(2200, () => HapticUtils.impact());
        _schedule(2650, () => HapticUtils.tap());
      } else {
        _schedule(1250, () => HapticUtils.impact());
        _schedule(1980, () => HapticUtils.heavy());
        _schedule(2180, () => HapticUtils.impact());
        _schedule(2600, () => HapticUtils.tap());
      }
      return;
    }

    // ⚽ Football / Soccer (1..5)
    if (trimmed == '⚽' || trimmed == '26bd') {
      if (value == 1) {
        HapticUtils.tap();
        _schedule(750, () => HapticUtils.selection());
      } else if (value == 2) {
        HapticUtils.impact();
        _schedule(730, () => HapticUtils.heavy());
        _schedule(2000, () => HapticUtils.impact());
        _schedule(2350, () => HapticUtils.tap());
      } else {
        HapticUtils.impact();
        _schedule(730, () => HapticUtils.heavy());
        _schedule(880, () => HapticUtils.impact());
        _schedule(1870, () => HapticUtils.impact());
        _schedule(2300, () => HapticUtils.tap());
      }
      return;
    }

    // 🎳 Bowling (1..6)
    if (trimmed == '🎳' || trimmed == '1f3b3') {
      HapticUtils.tap();
      if (value == 1) {
        _schedule(1000, () => HapticUtils.selection());
      } else if (value >= 2 && value <= 5) {
        _schedule(1500, () => HapticUtils.heavy());
        _schedule(1650, () => HapticUtils.impact());
        _schedule(1800, () => HapticUtils.tap());
      } else {
        _schedule(1500, () => HapticUtils.heavy());
        _schedule(1570, () {
          HapticUtils.heavy();
          _schedule(70, () => HapticUtils.impact());
        });
        _schedule(1780, () => HapticUtils.impact());
      }
      return;
    }

    // 🎰 Slot machine (1..64)
    if (trimmed == '🎰' || trimmed == '1f3b0') {
      HapticUtils.impact();
      _schedule(1080, () => HapticUtils.selection());
      _schedule(1380, () => HapticUtils.selection());
      _schedule(1680, () => HapticUtils.selection());
      if (value == 1 || value == 22 || value == 43 || value == 64) {
        _schedule(1850, () {
          HapticUtils.heavy();
          _schedule(70, () => HapticUtils.impact());
          _schedule(150, () => HapticUtils.heavy());
          _schedule(230, () => HapticUtils.tap());
        });
      }
    }
  }

  bool _isHeart(String s) {
    return s == '❤️' ||
        s == '❤' ||
        s == '2764' ||
        s == '2764-fe0f' ||
        s == '🧡' ||
        s == '💛' ||
        s == '💚' ||
        s == '💙' ||
        s == '💜' ||
        s == '🖤' ||
        s == '🤍' ||
        s == '🤎' ||
        s == '💔';
  }
}
