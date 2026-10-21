import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/haptic_utils.dart';

/// Service responsible for authentic Telegram-like haptic feedback
/// for interactive emojis, animated stickers, and dice games.
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

  /// Plays authentic Telegram haptic feedback for interactive emojis.
  void playInteractiveEmojiHaptic(String emoji) {
    cancelAll();
    final trimmed = emoji.trim();

    // 1. ❤️ Hearts: canonical Telegram HeartbeatHaptic (6-pulse rhythm: 3 heartbeat cycles)
    if (_isHeart(trimmed)) {
      _schedule(0, () => HapticUtils.impact());
      _schedule(200, () => HapticUtils.tap());
      _schedule(1000, () => HapticUtils.impact());
      _schedule(1200, () => HapticUtils.tap());
      _schedule(2000, () => HapticUtils.impact());
      _schedule(2200, () => HapticUtils.tap());
      return;
    }

    // 2. 🍑 Peach: canonical Telegram PeachHaptic (slap impact + jiggle waves)
    if (trimmed == '🍑' || trimmed == '1f351') {
      _schedule(580, () => HapticUtils.heavy());
      _schedule(750, () => HapticUtils.tap());
      _schedule(900, () => HapticUtils.selection());
      return;
    }

    // 3. ⚰️ Coffin: canonical Telegram CoffinHaptic (creak, swing open, and lid slam shut at 2620ms)
    if (trimmed == '⚰️' || trimmed == '⚰' || trimmed == '26b0' || trimmed == '26b0-fe0f') {
      _schedule(400, () => HapticUtils.impact());
      _schedule(600, () => HapticUtils.heavy());
      _schedule(2620, () => HapticUtils.heavy());
      return;
    }

    // 4. Synchronized effect culminations based on Telegram Lottie keyframes
    switch (trimmed) {
      case '🎉':
      case '🎊':
      case '1f389':
      case '1f38a':
        HapticUtils.selection();
        _schedule(460, () => HapticUtils.heavy());
        _schedule(700, () => HapticUtils.tap());
        break;

      case '🎈':
      case '1f388':
        HapticUtils.selection();
        _schedule(350, () => HapticUtils.tap());
        _schedule(750, () => HapticUtils.impact());
        _schedule(1380, () => HapticUtils.tap());
        break;

      case '💣':
      case '1f4a3':
        HapticUtils.selection();
        _schedule(850, () => HapticUtils.tap());
        _schedule(1250, () => HapticUtils.impact());
        _schedule(1640, () => HapticUtils.heavy());
        _schedule(1800, () => HapticUtils.impact());
        break;

      case '🍾':
      case '1f37e':
        HapticUtils.selection();
        _schedule(550, () => HapticUtils.heavy());
        _schedule(770, () => HapticUtils.impact());
        _schedule(1100, () => HapticUtils.tap());
        break;

      case '🍆':
      case '1f346':
        HapticUtils.selection();
        _schedule(630, () => HapticUtils.tap());
        _schedule(1030, () => HapticUtils.heavy());
        _schedule(1320, () => HapticUtils.impact());
        _schedule(1600, () => HapticUtils.tap());
        break;

      case '💩':
      case '1f4a9':
        HapticUtils.selection();
        _schedule(510, () => HapticUtils.impact());
        _schedule(810, () => HapticUtils.tap());
        break;

      case '🔥':
      case '1f525':
        HapticUtils.impact();
        _schedule(320, () => HapticUtils.tap());
        _schedule(820, () => HapticUtils.tap());
        _schedule(1320, () => HapticUtils.tap());
        break;

      case '👍':
      case '1f44d':
      case '👎':
      case '1f44e':
        HapticUtils.selection();
        _schedule(350, () => HapticUtils.tap());
        _schedule(750, () => HapticUtils.impact());
        break;

      case '👏':
      case '1f44f':
        // Exactly 6 authentic claps matching Null 85 keyframes: 233, 550, 867, 1183, 1500, 1817ms
        _schedule(233, () => HapticUtils.impact());
        _schedule(550, () => HapticUtils.impact());
        _schedule(867, () => HapticUtils.impact());
        _schedule(1183, () => HapticUtils.tap());
        _schedule(1500, () => HapticUtils.tap());
        _schedule(1817, () => HapticUtils.tap());
        break;

      case '⚡':
      case '26a1':
      case '26a1-fe0f':
        HapticUtils.impact();
        _schedule(120, () => HapticUtils.heavy());
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

      case '🤮':
      case '1f92e':
        HapticUtils.selection();
        _schedule(430, () => HapticUtils.selection());
        _schedule(860, () => HapticUtils.selection());
        _schedule(1480, () => HapticUtils.heavy());
        _schedule(1750, () => HapticUtils.impact());
        break;

      default:
        // Emojis without dedicated authentic haptic patterns do not trigger touch vibration
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
      _schedule(500, () => HapticUtils.tap());      // 1st table bounce
      _schedule(1000, () => HapticUtils.impact());  // 2nd table bounce
      _schedule(1330, () => HapticUtils.heavy());   // settle on face
      if (value == 6) {
        _schedule(1480, () => HapticUtils.tap());   // lucky 6 celebration
      }
      return;
    }

    // 🎯 Darts (1..6)
    if (trimmed == '🎯' || trimmed == '1f3af') {
      HapticUtils.selection(); // throw release
      if (value >= 2 && value <= 5) {
        _schedule(980, () => HapticUtils.impact()); // dart hits board
      } else if (value == 6) {
        _schedule(980, () => HapticUtils.heavy());  // Bullseye!
        _schedule(1120, () => HapticUtils.impact()); // target shudder
      }
      return;
    }

    // 🏀 Basketball (1..5)
    if (trimmed == '🏀' || trimmed == '1f3c0') {
      HapticUtils.tap(); // throw
      if (value == 1) {
        // Miss / airball: 2 floor bounces
        _schedule(830, () => HapticUtils.impact());
        _schedule(1660, () => HapticUtils.tap());
      } else if (value >= 2 && value <= 3) {
        // Rim hit and bounce out + 3 floor bounces
        _schedule(1250, () => HapticUtils.impact());
        _schedule(1700, () => HapticUtils.selection());
        _schedule(2000, () => HapticUtils.heavy());  // 1st floor bounce
        _schedule(2200, () => HapticUtils.impact()); // 2nd floor bounce
        _schedule(2650, () => HapticUtils.tap());    // 3rd floor bounce
      } else {
        // Scored basket (4..5): net swish + 3 floor bounces
        _schedule(1250, () => HapticUtils.impact());
        _schedule(1980, () => HapticUtils.heavy());  // 1st floor bounce
        _schedule(2180, () => HapticUtils.impact()); // 2nd floor bounce
        _schedule(2600, () => HapticUtils.tap());    // 3rd floor bounce
      }
      return;
    }

    // ⚽ Football / Soccer (1..5)
    if (trimmed == '⚽' || trimmed == '26bd') {
      if (value == 1) {
        // Miss / over bar
        HapticUtils.tap(); // kick
        _schedule(750, () => HapticUtils.selection());
      } else if (value == 2) {
        // Crossbar hit & rebound onto pitch
        HapticUtils.impact(); // kick
        _schedule(730, () => HapticUtils.heavy());  // crossbar clang
        _schedule(2000, () => HapticUtils.impact()); // 1st floor bounce
        _schedule(2350, () => HapticUtils.tap());    // 2nd floor bounce
      } else {
        // Goal (3..5)
        HapticUtils.impact(); // kick
        _schedule(730, () => HapticUtils.heavy());   // net strike
        _schedule(880, () => HapticUtils.impact());  // net tremor
        _schedule(1870, () => HapticUtils.impact()); // 1st floor bounce in goal
        _schedule(2300, () => HapticUtils.tap());    // 2nd floor bounce
      }
      return;
    }

    // 🎳 Bowling (1..6)
    if (trimmed == '🎳' || trimmed == '1f3b3') {
      HapticUtils.tap(); // roll start
      if (value == 1) {
        // Gutter ball
        _schedule(1000, () => HapticUtils.selection());
      } else if (value >= 2 && value <= 5) {
        // Pins hit
        _schedule(1500, () => HapticUtils.heavy());
        _schedule(1650, () => HapticUtils.impact());
      } else {
        // Strike!
        _schedule(1500, () => HapticUtils.heavy());
        _schedule(1600, () => HapticUtils.heavy());
        _schedule(1780, () => HapticUtils.impact());
      }
      return;
    }

    // 🎰 Slot Machine (1..64)
    if (trimmed == '🎰' || trimmed == '1f3b0') {
      HapticUtils.impact(); // lever pull
      _schedule(1080, () => HapticUtils.selection()); // Reel 1 stops
      _schedule(1380, () => HapticUtils.selection()); // Reel 2 stops
      _schedule(1680, () => HapticUtils.selection()); // Reel 3 stops

      // Winning 3-of-a-kind jackpot outcomes in Telegram: 1 (BAR), 22 (Berries), 43 (Lemons), 64 (777)
      if (value == 1 || value == 22 || value == 43 || value == 64) {
        _schedule(1850, () => HapticUtils.heavy());
        _schedule(2050, () => HapticUtils.heavy());
      }
      return;
    }

    // Fallback
    HapticUtils.impact();
  }

  bool _isHeart(String emoji) {
    const heartEmojis = {
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
      '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '❤️‍🔥', '❤️‍🩹'
    };
    if (heartEmojis.contains(emoji)) return true;
    const heartCodepoints = {
      '2764', '2764-fe0f', '1f9e1', '1f49b', '1f49a', '1f499', '1f49c',
      '1f5a4', '1f90d', '1f90e', '1f494', '2763', '1f495', '1f49e',
      '1f493', '1f497', '1f496', '1f498', '1f49d', '2764-fe0f-200d-1f525',
      '2764-fe0f-200d-1fa79'
    };
    return heartCodepoints.contains(emoji.toLowerCase());
  }
}
