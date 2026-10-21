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

    // 2. 🍑 Peach: canonical Telegram PeachHaptic (heavy slap impact at 600ms)
    if (trimmed == '🍑' || trimmed == '1f351') {
      _schedule(600, () => HapticUtils.heavy());
      return;
    }

    // 3. ⚰️ Coffin: canonical Telegram CoffinHaptic (double thud at 400ms and 600ms)
    if (trimmed == '⚰️' || trimmed == '⚰' || trimmed == '26b0') {
      _schedule(400, () => HapticUtils.heavy());
      _schedule(600, () => HapticUtils.heavy());
      return;
    }

    // 4. Variant B: Synchronized effect culminations based on Telegram Lottie keyframes
    switch (trimmed) {
      case '🎉':
      case '🎊':
      case '1f389':
      case '1f38a':
        HapticUtils.tap();
        _schedule(450, () => HapticUtils.heavy());
        break;

      case '🎈':
      case '1f388':
        HapticUtils.tap();
        _schedule(700, () => HapticUtils.heavy());
        break;

      case '💣':
      case '1f4a3':
        HapticUtils.selection();
        _schedule(800, () => HapticUtils.heavy());
        break;

      case '🍾':
      case '1f37e':
        HapticUtils.tap();
        _schedule(500, () => HapticUtils.heavy());
        break;

      case '🍆':
      case '1f346':
        HapticUtils.tap();
        _schedule(900, () => HapticUtils.impact());
        break;

      case '💩':
      case '1f4a9':
        HapticUtils.tap();
        _schedule(500, () => HapticUtils.impact());
        break;

      case '🔥':
      case '1f525':
        HapticUtils.impact();
        _schedule(300, () => HapticUtils.tap());
        _schedule(600, () => HapticUtils.tap());
        break;

      case '👍':
      case '1f44d':
      case '👎':
      case '1f44e':
        HapticUtils.selection();
        _schedule(350, () => HapticUtils.impact());
        break;

      case '👏':
      case '1f44f':
        HapticUtils.tap();
        _schedule(250, () => HapticUtils.tap());
        _schedule(500, () => HapticUtils.tap());
        _schedule(750, () => HapticUtils.tap());
        break;

      case '⚡':
      case '26a1':
        HapticUtils.impact();
        _schedule(100, () => HapticUtils.heavy());
        break;

      case '🎆':
      case '🎇':
      case '1f386':
      case '1f387':
        HapticUtils.tap();
        _schedule(600, () => HapticUtils.heavy());
        break;

      case '💋':
      case '👄':
      case '1f48b':
      case '1f444':
        HapticUtils.tap();
        _schedule(450, () => HapticUtils.impact());
        break;

      case '🤮':
      case '1f92e':
        HapticUtils.tap();
        _schedule(550, () => HapticUtils.impact());
        break;

      default:
        // Generic interactive emoji touch feedback
        HapticUtils.tap();
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
      _schedule(1200, () => HapticUtils.impact());
      if (value == 6) {
        _schedule(1350, () => HapticUtils.tap());
      }
      return;
    }

    // 🎯 Darts (1..6)
    if (trimmed == '🎯' || trimmed == '1f3af') {
      HapticUtils.tap();
      _schedule(1000, () {
        if (value == 6) {
          // Bullseye!
          HapticUtils.heavy();
          _schedule(150, () => HapticUtils.impact());
        } else {
          HapticUtils.impact();
        }
      });
      return;
    }

    // 🏀 Basketball (1..5)
    if (trimmed == '🏀' || trimmed == '1f3c0') {
      HapticUtils.tap();
      _schedule(900, () => HapticUtils.selection());
      if (value >= 4) {
        // Scored basket!
        _schedule(1100, () => HapticUtils.impact());
      }
      return;
    }

    // ⚽ Football / Soccer (1..5)
    if (trimmed == '⚽' || trimmed == '26bd') {
      HapticUtils.tap();
      if (value >= 3) {
        // Goal!
        _schedule(800, () {
          HapticUtils.heavy();
          _schedule(150, () => HapticUtils.impact());
        });
      } else {
        // Miss / post
        _schedule(800, () => HapticUtils.selection());
      }
      return;
    }

    // 🎳 Bowling (1..6)
    if (trimmed == '🎳' || trimmed == '1f3b3') {
      HapticUtils.tap();
      _schedule(1100, () {
        HapticUtils.impact();
        if (value == 6) {
          // Strike!
          _schedule(150, () => HapticUtils.heavy());
        }
      });
      return;
    }

    // 🎰 Slot Machine (1..64)
    if (trimmed == '🎰' || trimmed == '1f3b0') {
      HapticUtils.tap();
      _schedule(1100, () => HapticUtils.selection());
      _schedule(1400, () => HapticUtils.selection());
      _schedule(1700, () => HapticUtils.selection());

      // Winning 3-of-a-kind jackpot outcomes in Telegram: 1 (BAR), 22 (Berries), 43 (Lemons), 64 (777)
      if (value == 1 || value == 22 || value == 43 || value == 64) {
        _schedule(1850, () {
          HapticUtils.heavy();
          _schedule(150, () => HapticUtils.impact());
        });
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
