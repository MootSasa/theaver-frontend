import 'dart:async';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/haptic_utils.dart';

/// Semantic haptic impact levels supported by the service.
enum HapticType {
  selection,
  tap,
  impact,
  heavy,
}

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
class EmojiHapticService extends ChangeNotifier {
  EmojiHapticService._();
  static final EmojiHapticService instance = EmojiHapticService._();

  static const String _prefKeyUniformHaptics = 'emoji_haptic_uniform_tap';

  bool _isUniformHaptics = false;
  bool _isInitialized = false;

  /// Whether all haptic feedback pulses are converted to a single-strength light tap.
  /// Useful on devices where varied haptic levels are weak or feel unnatural.
  bool get isUniformHaptics => _isUniformHaptics;

  final List<Timer> _activeTimers = [];

  /// Initializes the service and loads the uniform haptic preference from local storage.
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isUniformHaptics = prefs.getBool(_prefKeyUniformHaptics) ?? false;
      _isInitialized = true;
    } catch (e) {
      debugPrint('EmojiHapticService.init error: $e');
    }
  }

  /// Configures whether to use single-strength tap haptics across all emojis and dice.
  Future<void> setUniformHaptics(bool value) async {
    if (_isUniformHaptics == value) return;
    _isUniformHaptics = value;
    notifyListeners();

    // Trigger immediate sample feedback so the user feels the selection
    HapticUtils.tap();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyUniformHaptics, value);
    } catch (e) {
      debugPrint('EmojiHapticService.setUniformHaptics error: $e');
    }
  }

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

  /// Emits a haptic pulse according to the current [isUniformHaptics] setting.
  void _pulse(HapticType type) {
    if (_isUniformHaptics) {
      HapticUtils.tap();
      return;
    }
    switch (type) {
      case HapticType.selection:
        HapticUtils.selection();
        break;
      case HapticType.tap:
        HapticUtils.tap();
        break;
      case HapticType.impact:
        HapticUtils.impact();
        break;
      case HapticType.heavy:
        HapticUtils.heavy();
        break;
    }
  }

  /// Emits a celebratory or explosion climax.
  void _pulseClimax({bool withSecondaryEcho = false}) {
    if (_isUniformHaptics) {
      HapticUtils.tap();
      if (withSecondaryEcho) {
        _schedule(90, () => HapticUtils.tap());
      }
      return;
    }
    HapticUtils.heavy();
    _schedule(60, () => HapticUtils.impact());
    if (withSecondaryEcho) {
      _schedule(140, () => HapticUtils.impact());
    }
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
      actions[0] = () => _pulse(HapticType.impact);
      actions[12] = () => _pulse(HapticType.tap);
      actions[60] = () => _pulse(HapticType.impact);
      actions[72] = () => _pulse(HapticType.tap);
      actions[120] = () => _pulse(HapticType.impact);
      actions[132] = () => _pulse(HapticType.tap);
      return HapticBinding(
        animation: animation,
        totalFrames: totalFrames,
        frameActions: actions,
      );
    }

    // 2. 🍑 Peach: canonical Telegram PeachHaptic (slap impact + jiggle ripples)
    if (trimmed == '🍑' || trimmed == '1f351') {
      const frames = 120;
      actions[30] = () => _pulse(HapticType.tap);
      actions[35] = () => _pulse(HapticType.heavy); // Slap impact
      actions[45] = () => _pulse(HapticType.impact); // Ripple 1
      actions[54] = () => _pulse(HapticType.selection); // Jiggle settling
      return HapticBinding(
        animation: animation,
        totalFrames: frames,
        frameActions: actions,
      );
    }

    // 3. ⚰️ Coffin: canonical Telegram CoffinHaptic (creak, swing open, lid slam shut)
    if (trimmed == '⚰️' || trimmed == '⚰' || trimmed == '26b0' || trimmed == '26b0-fe0f') {
      actions[24] = () => _pulse(HapticType.impact);
      actions[36] = () => _pulse(HapticType.heavy);
      actions[162] = () => _pulse(HapticType.heavy); // Slam shut
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
        actions[14] = () => _pulse(HapticType.impact);
        actions[33] = () => _pulse(HapticType.impact);
        actions[52] = () => _pulse(HapticType.impact);
        actions[71] = () => _pulse(HapticType.tap);
        actions[90] = () => _pulse(HapticType.tap);
        actions[109] = () => _pulse(HapticType.tap);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '💣':
      case '1f4a3':
        actions[0] = () => _pulse(HapticType.selection);
        actions[50] = () => _pulse(HapticType.tap);
        actions[75] = () => _pulse(HapticType.impact);
        actions[98] = () => _pulseClimax(withSecondaryEcho: true);
        break;

      case '🍾':
      case '1f37e':
        actions[0] = () => _pulse(HapticType.selection);
        actions[33] = () => _pulse(HapticType.heavy); // Cork pop
        actions[46] = () => _pulse(HapticType.impact); // Foam erupts
        actions[68] = () => _pulse(HapticType.tap); // Fizz
        break;

      case '🍆':
      case '1f346':
        actions[0] = () => _pulse(HapticType.selection);
        actions[38] = () => _pulse(HapticType.tap);
        actions[62] = () => _pulse(HapticType.heavy); // Whip snap up
        actions[79] = () => _pulse(HapticType.impact);
        break;

      case '💩':
      case '1f4a9':
        actions[0] = () => _pulse(HapticType.selection);
        actions[31] = () => _pulse(HapticType.impact); // Plop compression
        actions[49] = () => _pulse(HapticType.tap); // Rebound
        break;

      case '🤮':
      case '1f92e':
        actions[26] = () => _pulse(HapticType.selection);
        actions[52] = () => _pulse(HapticType.selection);
        actions[89] = () => _pulse(HapticType.heavy); // Puke eruption
        actions[105] = () => _pulse(HapticType.impact);
        break;

      case '👍':
      case '1f44d':
        const frames = 116;
        actions[0] = () => _pulse(HapticType.selection);
        actions[21] = () => _pulse(HapticType.tap);
        actions[45] = () => _pulse(HapticType.heavy); // Pop up
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '👎':
      case '1f44e':
        actions[0] = () => _pulse(HapticType.selection);
        actions[22] = () => _pulse(HapticType.tap);
        actions[48] = () => _pulse(HapticType.heavy);
        break;

      case '🎉':
      case '🎊':
      case '1f389':
      case '1f38a':
        actions[0] = () => _pulse(HapticType.selection);
        actions[74] = () => _pulse(HapticType.heavy); // Popper shot
        actions[99] = () => _pulse(HapticType.tap); // Confetti
        break;

      case '🎈':
      case '1f388':
        actions[0] = () => _pulse(HapticType.selection);
        actions[45] = () => _pulse(HapticType.impact);
        actions[83] = () => _pulse(HapticType.tap);
        break;

      case '🔥':
      case '1f525':
        actions[0] = () => _pulse(HapticType.impact);
        actions[19] = () => _pulse(HapticType.tap);
        actions[49] = () => _pulse(HapticType.tap);
        actions[79] = () => _pulse(HapticType.tap);
        break;

      case '⚡':
      case '26a1':
        actions[0] = () => _pulse(HapticType.heavy);
        actions[7] = () => _pulse(HapticType.impact);
        actions[15] = () => _pulse(HapticType.tap);
        break;

      case '💋':
      case '👄':
      case '1f48b':
      case '1f444':
        actions[0] = () => _pulse(HapticType.selection);
        actions[30] = () => _pulse(HapticType.impact); // Kiss smack
        actions[45] = () => _pulse(HapticType.tap); // Heart flies
        break;

      case '🎆':
      case '🎇':
      case '1f386':
      case '1f387':
        actions[0] = () => _pulse(HapticType.selection);
        actions[36] = () => _pulse(HapticType.heavy);
        actions[51] = () => _pulse(HapticType.tap);
        actions[63] = () => _pulse(HapticType.tap);
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
        actions[50] = () => _pulse(HapticType.impact);
        actions[100] = () => _pulse(HapticType.tap);
      } else if (value >= 2 && value <= 3) {
        // Rim hit and bounce out + 3 floor bounces
        actions[75] = () => _pulse(HapticType.impact);
        actions[102] = () => _pulse(HapticType.selection);
        actions[120] = () => _pulse(HapticType.heavy);
        actions[132] = () => _pulse(HapticType.impact);
        actions[156] = () => _pulse(HapticType.tap);
      } else {
        // Scored basket (4..5): net swish + 3 floor bounces
        actions[75] = () => _pulse(HapticType.impact);
        actions[119] = () => _pulse(HapticType.heavy);
        actions[131] = () => _pulse(HapticType.impact);
        actions[156] = () => _pulse(HapticType.tap);
      }
    }
    // 2. ⚽ Football
    else if (trimmed == '⚽' || trimmed == '26bd') {
      if (value == 1) {
        actions[2] = () => _pulse(HapticType.tap);
        actions[45] = () => _pulse(HapticType.selection);
      } else if (value == 2) {
        actions[2] = () => _pulse(HapticType.impact);
        actions[44] = () => _pulse(HapticType.heavy); // Crossbar clang
        actions[120] = () => _pulse(HapticType.impact);
        actions[141] = () => _pulse(HapticType.tap);
      } else {
        actions[2] = () => _pulse(HapticType.impact);
        actions[44] = () => _pulse(HapticType.heavy); // Net strike
        actions[53] = () => _pulse(HapticType.impact);
        actions[112] = () => _pulse(HapticType.impact);
        actions[138] = () => _pulse(HapticType.tap);
      }
    }
    // 3. 🎲 Dice (1..6)
    else if (trimmed == '🎲' || trimmed == '1f3b2') {
      actions[0] = () => _pulse(HapticType.selection);
      actions[30] = () => _pulse(HapticType.tap); // 1st table bounce
      actions[60] = () => _pulse(HapticType.impact); // 2nd table bounce
      actions[80] = () => _pulse(HapticType.heavy); // Settle on face
      if (value == 6) {
        actions[89] = () => _pulse(HapticType.tap); // Lucky 6
      }
    }
    // 4. 🎳 Bowling (1..6)
    else if (trimmed == '🎳' || trimmed == '1f3b3') {
      if (value == 1) {
        actions[60] = () => _pulse(HapticType.selection); // Gutter
      } else if (value >= 2 && value <= 5) {
        actions[90] = () => _pulse(HapticType.heavy); // Pins hit
        actions[99] = () => _pulse(HapticType.impact);
        actions[108] = () => _pulse(HapticType.tap);
      } else {
        actions[90] = () => _pulse(HapticType.heavy); // Strike hit
        actions[94] = () => _pulseClimax();
        actions[107] = () => _pulse(HapticType.impact);
      }
    }
    // 5. 🎯 Darts (1..6)
    else if (trimmed == '🎯' || trimmed == '1f3af') {
      const frames = 100;
      if (value == 1) {
        actions[0] = () => _pulse(HapticType.selection);
      } else if (value >= 2 && value <= 5) {
        actions[59] = () => _pulse(HapticType.impact);
      } else {
        actions[59] = () => _pulse(HapticType.heavy); // Bullseye!
        actions[67] = () => _pulse(HapticType.impact); // Target resonance
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
      0: () => _pulse(HapticType.impact), // Lever pull
      65: () => _pulse(HapticType.selection), // Left reel stop
      83: () => _pulse(HapticType.selection), // Center reel stop
      101: () => _pulse(HapticType.selection), // Right reel stop
    };

    final isJackpot = (value == 1 || value == 22 || value == 43 || value == 64);
    if (isJackpot) {
      actions[111] = () {
        if (_isUniformHaptics) {
          HapticUtils.tap();
          _schedule(90, () => HapticUtils.tap());
          _schedule(180, () => HapticUtils.tap());
        } else {
          HapticUtils.heavy();
          _schedule(70, () => HapticUtils.impact());
          _schedule(150, () => HapticUtils.heavy());
          _schedule(230, () => HapticUtils.tap());
        }
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
      _schedule(0, () => _pulse(HapticType.impact));
      _schedule(200, () => _pulse(HapticType.tap));
      _schedule(1000, () => _pulse(HapticType.impact));
      _schedule(1200, () => _pulse(HapticType.tap));
      _schedule(2000, () => _pulse(HapticType.impact));
      _schedule(2200, () => _pulse(HapticType.tap));
      return;
    }

    if (trimmed == '🍑' || trimmed == '1f351') {
      _schedule(500, () => _pulse(HapticType.tap));
      _schedule(580, () => _pulse(HapticType.heavy));
      _schedule(750, () => _pulse(HapticType.impact));
      _schedule(900, () => _pulse(HapticType.selection));
      return;
    }

    if (trimmed == '⚰️' || trimmed == '⚰' || trimmed == '26b0' || trimmed == '26b0-fe0f') {
      _schedule(400, () => _pulse(HapticType.impact));
      _schedule(600, () => _pulse(HapticType.heavy));
      _schedule(2700, () => _pulse(HapticType.heavy));
      return;
    }

    switch (trimmed) {
      case '👏':
      case '1f44f':
        _schedule(233, () => _pulse(HapticType.impact));
        _schedule(550, () => _pulse(HapticType.impact));
        _schedule(867, () => _pulse(HapticType.impact));
        _schedule(1183, () => _pulse(HapticType.tap));
        _schedule(1500, () => _pulse(HapticType.tap));
        _schedule(1817, () => _pulse(HapticType.tap));
        break;

      case '🎉':
      case '🎊':
      case '1f389':
      case '1f38a':
        _pulse(HapticType.selection);
        _schedule(1233, () => _pulse(HapticType.heavy));
        _schedule(1650, () => _pulse(HapticType.tap));
        break;

      case '🎈':
      case '1f388':
        _pulse(HapticType.selection);
        _schedule(750, () => _pulse(HapticType.impact));
        _schedule(1383, () => _pulse(HapticType.tap));
        break;

      case '💣':
      case '1f4a3':
        _pulse(HapticType.selection);
        _schedule(833, () => _pulse(HapticType.tap));
        _schedule(1250, () => _pulse(HapticType.impact));
        _schedule(1633, () => _pulseClimax(withSecondaryEcho: true));
        break;

      case '🍾':
      case '1f37e':
        _pulse(HapticType.selection);
        _schedule(550, () => _pulse(HapticType.heavy));
        _schedule(767, () => _pulse(HapticType.impact));
        _schedule(1133, () => _pulse(HapticType.tap));
        break;

      case '🍆':
      case '1f346':
        _pulse(HapticType.selection);
        _schedule(633, () => _pulse(HapticType.tap));
        _schedule(1033, () => _pulse(HapticType.heavy));
        _schedule(1317, () => _pulse(HapticType.impact));
        break;

      case '💩':
      case '1f4a9':
        _pulse(HapticType.selection);
        _schedule(517, () => _pulse(HapticType.impact));
        _schedule(817, () => _pulse(HapticType.tap));
        break;

      case '🤮':
      case '1f92e':
        _schedule(433, () => _pulse(HapticType.selection));
        _schedule(867, () => _pulse(HapticType.selection));
        _schedule(1483, () => _pulse(HapticType.heavy));
        _schedule(1750, () => _pulse(HapticType.impact));
        break;

      case '🔥':
      case '1f525':
        _pulse(HapticType.impact);
        _schedule(317, () => _pulse(HapticType.tap));
        _schedule(817, () => _pulse(HapticType.tap));
        _schedule(1317, () => _pulse(HapticType.tap));
        break;

      case '👍':
      case '1f44d':
        _pulse(HapticType.selection);
        _schedule(350, () => _pulse(HapticType.tap));
        _schedule(750, () => _pulse(HapticType.heavy));
        break;

      case '👎':
      case '1f44e':
        _pulse(HapticType.selection);
        _schedule(367, () => _pulse(HapticType.tap));
        _schedule(800, () => _pulse(HapticType.heavy));
        break;

      case '⚡':
      case '26a1':
        _pulse(HapticType.heavy);
        _schedule(117, () => _pulse(HapticType.impact));
        _schedule(250, () => _pulse(HapticType.tap));
        break;

      case '🎆':
      case '🎇':
      case '1f386':
      case '1f387':
        _pulse(HapticType.selection);
        _schedule(600, () => _pulse(HapticType.heavy));
        _schedule(850, () => _pulse(HapticType.tap));
        _schedule(1050, () => _pulse(HapticType.tap));
        break;

      case '💋':
      case '👄':
      case '1f48b':
      case '1f444':
        _pulse(HapticType.selection);
        _schedule(500, () => _pulse(HapticType.impact));
        _schedule(750, () => _pulse(HapticType.tap));
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
      _pulse(HapticType.selection);
      _schedule(500, () => _pulse(HapticType.tap));
      _schedule(1000, () => _pulse(HapticType.impact));
      _schedule(1330, () => _pulse(HapticType.heavy));
      if (value == 6) {
        _schedule(1480, () => _pulse(HapticType.tap));
      }
      return;
    }

    // 🎯 Darts (1..6)
    if (trimmed == '🎯' || trimmed == '1f3af') {
      _pulse(HapticType.selection);
      if (value >= 2 && value <= 5) {
        _schedule(980, () => _pulse(HapticType.impact));
      } else if (value == 6) {
        _schedule(980, () => _pulse(HapticType.heavy));
        _schedule(1120, () => _pulse(HapticType.impact));
      }
      return;
    }

    // 🏀 Basketball (1..5)
    if (trimmed == '🏀' || trimmed == '1f3c0') {
      _pulse(HapticType.tap);
      if (value == 1) {
        _schedule(830, () => _pulse(HapticType.impact));
        _schedule(1660, () => _pulse(HapticType.tap));
      } else if (value >= 2 && value <= 3) {
        _schedule(1250, () => _pulse(HapticType.impact));
        _schedule(1700, () => _pulse(HapticType.selection));
        _schedule(2000, () => _pulse(HapticType.heavy));
        _schedule(2200, () => _pulse(HapticType.impact));
        _schedule(2650, () => _pulse(HapticType.tap));
      } else {
        _schedule(1250, () => _pulse(HapticType.impact));
        _schedule(1980, () => _pulse(HapticType.heavy));
        _schedule(2180, () => _pulse(HapticType.impact));
        _schedule(2600, () => _pulse(HapticType.tap));
      }
      return;
    }

    // ⚽ Football / Soccer (1..5)
    if (trimmed == '⚽' || trimmed == '26bd') {
      if (value == 1) {
        _pulse(HapticType.tap);
        _schedule(750, () => _pulse(HapticType.selection));
      } else if (value == 2) {
        _pulse(HapticType.impact);
        _schedule(730, () => _pulse(HapticType.heavy));
        _schedule(2000, () => _pulse(HapticType.impact));
        _schedule(2350, () => _pulse(HapticType.tap));
      } else {
        _pulse(HapticType.impact);
        _schedule(730, () => _pulse(HapticType.heavy));
        _schedule(880, () => _pulse(HapticType.impact));
        _schedule(1870, () => _pulse(HapticType.impact));
        _schedule(2300, () => _pulse(HapticType.tap));
      }
      return;
    }

    // 🎳 Bowling (1..6)
    if (trimmed == '🎳' || trimmed == '1f3b3') {
      _pulse(HapticType.tap);
      if (value == 1) {
        _schedule(1000, () => _pulse(HapticType.selection));
      } else if (value >= 2 && value <= 5) {
        _schedule(1500, () => _pulse(HapticType.heavy));
        _schedule(1650, () => _pulse(HapticType.impact));
        _schedule(1800, () => _pulse(HapticType.tap));
      } else {
        _schedule(1500, () => _pulse(HapticType.heavy));
        _schedule(1570, () => _pulseClimax());
        _schedule(1780, () => _pulse(HapticType.impact));
      }
      return;
    }

    // 🎰 Slot machine (1..64)
    if (trimmed == '🎰' || trimmed == '1f3b0') {
      _pulse(HapticType.impact);
      _schedule(1080, () => _pulse(HapticType.selection));
      _schedule(1380, () => _pulse(HapticType.selection));
      _schedule(1680, () => _pulse(HapticType.selection));
      if (value == 1 || value == 22 || value == 43 || value == 64) {
        _schedule(1850, () {
          if (_isUniformHaptics) {
            HapticUtils.tap();
            _schedule(90, () => HapticUtils.tap());
            _schedule(180, () => HapticUtils.tap());
          } else {
            HapticUtils.heavy();
            _schedule(70, () => HapticUtils.impact());
            _schedule(150, () => HapticUtils.heavy());
            _schedule(230, () => HapticUtils.tap());
          }
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
