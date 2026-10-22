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

    // 2. 🍑 Peach: 5 distinct slaps (1 on main emoji + 4 flying peach slaps in effect)
    if (trimmed == '🍑' || trimmed == '1f351') {
      const frames = 120;
      actions[31] = () => _pulse(HapticType.heavy); // 1st slap (main peach)
      actions[50] = () => _pulse(HapticType.impact); // 2nd slap (effect hand 1)
      actions[57] = () => _pulse(HapticType.heavy); // 3rd slap (effect hand 2)
      actions[102] = () => _pulse(HapticType.impact); // 4th slap (effect hand 4)
      actions[111] = () => _pulse(HapticType.heavy); // 5th slap (effect hand 3)
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
        actions[3] = () => _pulseClimax(); // Cork blast & smoke eruption
        actions[18] = () => _pulse(HapticType.impact); // Foam geyser shoots
        actions[71] = () => _pulse(HapticType.heavy); // First glass pair clinks
        actions[91] = () => _pulse(HapticType.impact); // Second glass pair clinks
        actions[123] = () => _pulse(HapticType.tap); // Third glass pair clinks
        break;

      case '🥂':
      case '1f942':
        // Glasses pull apart in anticipation during f0-f60 (no strike at f8).
        // Middle cheer clink: glasses collide firmly at frame 68
        actions[68] = () => _pulse(HapticType.heavy);
        actions[74] = () => _pulse(HapticType.tap);
        // Final cheer clink: glasses collide for the toast at frame 158
        actions[158] = () => _pulse(HapticType.heavy);
        actions[164] = () => _pulse(HapticType.tap);
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
        // Exact balloon pops and confetti bursts in 1f388
        actions[0] = () => _pulse(HapticType.selection);
        actions[57] = () => _pulse(HapticType.impact); // Balloon pop 1
        actions[65] = () => _pulse(HapticType.heavy); // Balloon pop 2
        actions[74] = () => _pulse(HapticType.impact); // Balloon pop 3
        actions[82] = () => _pulse(HapticType.heavy); // Balloon pop 4
        actions[91] = () => _pulse(HapticType.impact); // Balloon pop 5
        actions[97] = () => _pulse(HapticType.heavy); // Balloon pop 6
        actions[107] = () => _pulse(HapticType.impact); // Balloon pop 7
        actions[116] = () => _pulse(HapticType.heavy); // Balloon pop 8
        actions[127] = () => _pulse(HapticType.impact); // Balloon pop 9
        actions[144] = () => _pulseClimax(); // Final balloon pop
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
        // Synchronized with all rocket burst layers in 1f386
        actions[0] = () => _pulse(HapticType.selection);
        actions[31] = () => _pulse(HapticType.impact); // Rocket 1 burst
        actions[36] = () => _pulse(HapticType.heavy); // Flash expansion
        actions[49] = () => _pulse(HapticType.impact); // Rocket 2 burst
        actions[54] = () => _pulse(HapticType.heavy); // Rocket 3 burst
        actions[65] = () => _pulse(HapticType.heavy); // Rocket 4 burst
        actions[76] = () => _pulse(HapticType.impact); // Rocket 5 burst
        actions[87] = () => _pulse(HapticType.heavy); // Rocket 6 burst
        actions[125] = () => _pulse(HapticType.impact); // Rocket 7 burst
        actions[134] = () => _pulseClimax(); // Rocket 8 climax explosion
        break;

      case '🧨':
      case '1f9e8':
        actions[0] = () => _pulse(HapticType.selection);
        actions[73] = () => _pulse(HapticType.selection);
        actions[80] = () => _pulse(HapticType.tap);
        actions[85] = () => _pulse(HapticType.impact);
        actions[90] = () => _pulseClimax(withSecondaryEcho: true); // Massive detonation
        actions[96] = () => _pulse(HapticType.impact); // Blast shockwave
        actions[107] = () => _pulse(HapticType.tap); // Smoke settle
        break;

      case '🤯':
      case '1f92f':
        actions[71] = () => _pulse(HapticType.selection);
        actions[84] = () => _pulse(HapticType.tap);
        actions[98] = () => _pulse(HapticType.impact);
        actions[113] = () => _pulseClimax(); // Brain eruption mushroom cloud
        actions[122] = () => _pulse(HapticType.impact); // Flying pieces
        actions[137] = () => _pulse(HapticType.tap); // Smoke dissipate
        break;

      case '💥':
      case '1f4a5':
        actions[0] = () => _pulseClimax(); // Flash explosion blast
        actions[10] = () => _pulse(HapticType.impact); // Circular shockwave expansion
        actions[34] = () => _pulse(HapticType.tap); // Dissipation
        actions[104] = () => _pulse(HapticType.tap); // Residual tremor
        break;

      case '👊':
      case '1f44a':
        // Fist pulls back slowly in anticipation (f0-f91).
        // Strike onto screen glass occurs precisely at frame 97 (peak scale 120.5% + impact burst)
        actions[97] = () => _pulseClimax(withSecondaryEcho: true); // Powerful punch smash into screen glass
        actions[108] = () => _pulse(HapticType.impact); // Screen recoil shockwave
        break;

      case '🚀':
      case '1f680':
        actions[0] = () => _pulse(HapticType.selection);
        actions[50] = () => _pulse(HapticType.tap);
        actions[65] = () => _pulse(HapticType.tap);
        actions[80] = () => _pulse(HapticType.impact); // Engine rev up
        actions[86] = () => _pulseClimax(); // Rocket liftoff thrust
        actions[118] = () => _pulse(HapticType.impact); // Trail flame
        break;

      case '💔':
      case '1f494':
        actions[0] = () => _pulse(HapticType.tap); // Heart beat
        actions[26] = () => _pulse(HapticType.heavy); // Crack splits in two
        actions[36] = () => _pulse(HapticType.impact); // Halves separation shudder
        actions[98] = () => _pulse(HapticType.impact); // Halves slam and re-seal
        actions[108] = () => _pulse(HapticType.tap); // Beat of healed heart
        break;

      case '💯':
      case '1f4af':
        actions[0] = () => _pulse(HapticType.selection);
        actions[50] = () => _pulse(HapticType.impact); // Underline 1
        actions[63] = () => _pulse(HapticType.heavy); // Stamp underline 2
        actions[80] = () => _pulse(HapticType.tap); // Ink splatter
        break;

      case '🥳':
      case '1f973':
        actions[0] = () => _pulse(HapticType.selection);
        actions[34] = () => _pulse(HapticType.impact); // Horn blower extends
        actions[100] = () => _pulseClimax(); // Confetti explosion blast
        break;

      case '🪙':
      case '1fa99':
        actions[0] = () => _pulse(HapticType.selection);
        actions[26] = () => _pulse(HapticType.tap); // Coin toss flick
        actions[112] = () => _pulse(HapticType.heavy); // Metallic coin slap catch
        actions[124] = () => _pulse(HapticType.tap); // Palm settle
        break;

      case '👻':
      case '1f47b':
        actions[0] = () => _pulse(HapticType.selection);
        actions[71] = () => _pulse(HapticType.heavy); // Sudden "BOO!" scare jump
        actions[91] = () => _pulse(HapticType.tap); // Wobble float
        break;

      case '😱':
      case '1f631':
        actions[0] = () => _pulse(HapticType.selection);
        actions[32] = () => _pulse(HapticType.heavy); // Slap hands on cheeks
        actions[42] = () => _pulse(HapticType.tap); // Tremble
        actions[53] = () => _pulse(HapticType.tap); // Tremble
        actions[82] = () => _pulse(HapticType.impact); // Gasp of horror
        break;

      case '🎩':
      case '1f3a9':
        actions[0] = () => _pulse(HapticType.selection);
        actions[12] = () => _pulse(HapticType.tap); // Wand flourish
        actions[86] = () => _pulse(HapticType.heavy); // Wand taps top hat brim
        actions[98] = () => _pulse(HapticType.impact); // Rabbit pops out
        break;

      case '🗿':
      case '1f5ff':
        actions[0] = () => _pulse(HapticType.selection);
        actions[24] = () => _pulse(HapticType.impact); // Stone monolith shifts
        actions[78] = () => _pulse(HapticType.heavy); // Solid stone turn lock
        break;

      case '🆒':
      case '1f192':
        actions[0] = () => _pulse(HapticType.selection);
        actions[84] = () => _pulse(HapticType.impact);
        actions[102] = () => _pulse(HapticType.heavy);
        actions[110] = () => _pulse(HapticType.tap);
        break;

      case '🆓':
      case '1f193':
        actions[0] = () => _pulse(HapticType.selection);
        actions[29] = () => _pulse(HapticType.impact);
        actions[60] = () => _pulse(HapticType.heavy);
        actions[71] = () => _pulse(HapticType.tap);
        break;

      case '🆕':
      case '1f195':
        actions[5] = () => _pulse(HapticType.selection);
        actions[30] = () => _pulse(HapticType.heavy);
        actions[46] = () => _pulse(HapticType.tap);
        break;

      case '🆗':
      case '1f197':
        actions[8] = () => _pulse(HapticType.selection);
        actions[22] = () => _pulse(HapticType.impact);
        actions[35] = () => _pulse(HapticType.heavy);
        break;

      case '🆙':
      case '1f199':
        actions[22] = () => _pulse(HapticType.selection);
        actions[40] = () => _pulse(HapticType.heavy);
        actions[46] = () => _pulse(HapticType.tap);
        break;

      case '🌈':
      case '1f308':
        actions[12] = () => _pulse(HapticType.selection);
        actions[23] = () => _pulse(HapticType.impact);
        actions[49] = () => _pulse(HapticType.tap);
        break;

      case '🌑':
      case '1f311':
        actions[0] = () => _pulse(HapticType.selection);
        actions[30] = () => _pulse(HapticType.tap);
        actions[60] = () => _pulse(HapticType.impact);
        break;

      case '🌒':
      case '1f312':
        actions[30] = () => _pulse(HapticType.tap);
        actions[60] = () => _pulse(HapticType.impact);
        actions[84] = () => _pulse(HapticType.tap);
        break;

      case '🌓':
      case '1f313':
        actions[30] = () => _pulse(HapticType.tap);
        actions[60] = () => _pulse(HapticType.impact);
        break;

      case '🌔':
      case '1f314':
        actions[30] = () => _pulse(HapticType.tap);
        actions[60] = () => _pulse(HapticType.impact);
        actions[79] = () => _pulse(HapticType.tap);
        break;

      case '🌕':
      case '1f315':
        actions[15] = () => _pulse(HapticType.selection);
        actions[60] = () => _pulse(HapticType.heavy);
        actions[90] = () => _pulse(HapticType.tap);
        break;

      case '🌖':
      case '1f316':
        actions[30] = () => _pulse(HapticType.tap);
        actions[60] = () => _pulse(HapticType.impact);
        break;

      case '🌗':
      case '1f317':
        actions[30] = () => _pulse(HapticType.tap);
        actions[60] = () => _pulse(HapticType.impact);
        break;

      case '🌘':
      case '1f318':
        actions[30] = () => _pulse(HapticType.tap);
        actions[60] = () => _pulse(HapticType.impact);
        break;

      case '🌚':
      case '1f31a':
        actions[20] = () => _pulse(HapticType.selection);
        actions[42] = () => _pulse(HapticType.tap);
        actions[53] = () => _pulse(HapticType.tap);
        break;

      case '🌛':
      case '1f31b':
        actions[26] = () => _pulse(HapticType.tap);
        actions[41] = () => _pulse(HapticType.tap);
        actions[77] = () => _pulse(HapticType.impact);
        break;

      case '🌜':
      case '1f31c':
        actions[23] = () => _pulse(HapticType.tap);
        actions[36] = () => _pulse(HapticType.tap);
        actions[44] = () => _pulse(HapticType.impact);
        break;

      case '🌝':
      case '1f31d':
        actions[22] = () => _pulse(HapticType.tap);
        actions[38] = () => _pulse(HapticType.impact);
        actions[58] = () => _pulse(HapticType.tap);
        break;

      case '🌞':
      case '1f31e':
        actions[11] = () => _pulse(HapticType.selection);
        actions[31] = () => _pulse(HapticType.impact);
        actions[58] = () => _pulse(HapticType.tap);
        break;

      case '🌟':
      case '1f31f':
        actions[10] = () => _pulse(HapticType.selection);
        actions[40] = () => _pulse(HapticType.impact);
        actions[80] = () => _pulse(HapticType.heavy);
        actions[110] = () => _pulse(HapticType.tap);
        break;

      case '🌡':
      case '🌡️':
      case '1f321':
      case '1f321-fe0f':
        actions[18] = () => _pulse(HapticType.selection);
        actions[51] = () => _pulse(HapticType.impact);
        actions[60] = () => _pulse(HapticType.heavy);
        break;

      case '🌤':
      case '🌤️':
      case '1f324':
      case '1f324-fe0f':
        actions[35] = () => _pulse(HapticType.selection);
        actions[46] = () => _pulse(HapticType.tap);
        actions[70] = () => _pulse(HapticType.tap);
        break;

      case '🌥':
      case '🌥️':
      case '1f325':
      case '1f325-fe0f':
        actions[35] = () => _pulse(HapticType.selection);
        actions[55] = () => _pulse(HapticType.tap);
        actions[82] = () => _pulse(HapticType.tap);
        break;

      case '🌦':
      case '🌦️':
      case '1f326':
      case '1f326-fe0f':
        actions[13] = () => _pulse(HapticType.selection);
        actions[22] = () => _pulse(HapticType.tap);
        actions[48] = () => _pulse(HapticType.tap);
        break;

      case '🌧':
      case '🌧️':
      case '1f327':
      case '1f327-fe0f':
        actions[13] = () => _pulse(HapticType.selection);
        actions[22] = () => _pulse(HapticType.impact);
        actions[48] = () => _pulse(HapticType.tap);
        actions[75] = () => _pulse(HapticType.tap);
        break;

      case '🌨':
      case '🌨️':
      case '1f328':
      case '1f328-fe0f':
        actions[24] = () => _pulse(HapticType.selection);
        actions[33] = () => _pulse(HapticType.tap);
        actions[60] = () => _pulse(HapticType.tap);
        break;

      case '🌩':
      case '🌩️':
      case '1f329':
      case '1f329-fe0f':
        actions[24] = () => _pulse(HapticType.selection);
        actions[45] = () => _pulse(HapticType.heavy);
        actions[52] = () => _pulse(HapticType.impact);
        actions[70] = () => _pulse(HapticType.tap);
        break;

      case '🌭':
      case '1f32d':
        actions[23] = () => _pulse(HapticType.tap);
        actions[37] = () => _pulse(HapticType.impact);
        actions[65] = () => _pulse(HapticType.heavy);
        break;

      case '🌮':
      case '1f32e':
        actions[33] = () => _pulse(HapticType.impact);
        actions[40] = () => _pulse(HapticType.heavy);
        actions[68] = () => _pulse(HapticType.tap);
        break;

      case '🌱':
      case '1f331':
        actions[10] = () => _pulse(HapticType.selection);
        actions[22] = () => _pulse(HapticType.impact);
        actions[34] = () => _pulse(HapticType.tap);
        break;

      case '🌲':
      case '1f332':
        actions[26] = () => _pulse(HapticType.selection);
        actions[44] = () => _pulse(HapticType.impact);
        actions[68] = () => _pulse(HapticType.tap);
        break;

      case '🌳':
      case '1f333':
        actions[30] = () => _pulse(HapticType.selection);
        actions[40] = () => _pulse(HapticType.impact);
        actions[75] = () => _pulse(HapticType.tap);
        break;

      case '🌴':
      case '1f334':
        actions[22] = () => _pulse(HapticType.selection);
        actions[35] = () => _pulse(HapticType.impact);
        actions[60] = () => _pulse(HapticType.tap);
        break;

      case '🌵':
      case '1f335':
        actions[18] = () => _pulse(HapticType.tap);
        actions[30] = () => _pulse(HapticType.tap);
        actions[55] = () => _pulse(HapticType.impact);
        break;

      case '🌷':
      case '1f337':
        actions[17] = () => _pulse(HapticType.selection);
        actions[51] = () => _pulse(HapticType.impact);
        actions[69] = () => _pulse(HapticType.tap);
        break;

      case '🌸':
      case '1f338':
        actions[25] = () => _pulse(HapticType.selection);
        actions[41] = () => _pulse(HapticType.impact);
        actions[72] = () => _pulse(HapticType.tap);
        break;

      case '🌹':
      case '1f339':
        actions[20] = () => _pulse(HapticType.selection);
        actions[42] = () => _pulse(HapticType.heavy);
        actions[75] = () => _pulse(HapticType.tap);
        break;

      case '🌺':
      case '1f33a':
        actions[16] = () => _pulse(HapticType.selection);
        actions[59] = () => _pulse(HapticType.impact);
        actions[89] = () => _pulse(HapticType.tap);
        break;

      case '🌼':
      case '1f33c':
        actions[18] = () => _pulse(HapticType.selection);
        actions[48] = () => _pulse(HapticType.impact);
        actions[100] = () => _pulse(HapticType.tap);
        break;

      case '🌿':
      case '1f33f':
        actions[21] = () => _pulse(HapticType.selection);
        actions[35] = () => _pulse(HapticType.tap);
        actions[47] = () => _pulse(HapticType.impact);
        break;

      case '🍀':
      case '1f340':
        actions[19] = () => _pulse(HapticType.selection);
        actions[55] = () => _pulse(HapticType.impact);
        actions[112] = () => _pulse(HapticType.heavy);
        actions[125] = () => _pulse(HapticType.tap);
        break;

      // --- 1f34c .. 1f37d-fe0f (Food & Drink) ---
      case '🍌':
      case '1f34c':
        actions[16] = () => _pulse(HapticType.selection);
        actions[50] = () => _pulse(HapticType.tap);
        actions[71] = () => _pulse(HapticType.heavy);
        actions[100] = () => _pulse(HapticType.impact);
        break;

      case '🍓':
      case '1f353':
        actions[38] = () => _pulse(HapticType.selection);
        actions[54] = () => _pulse(HapticType.heavy);
        actions[90] = () => _pulse(HapticType.impact);
        actions[121] = () => _pulse(HapticType.tap);
        break;

      case '🍔':
      case '1f354':
        actions[23] = () => _pulse(HapticType.selection);
        actions[60] = () => _pulse(HapticType.tap);
        actions[74] = () => _pulse(HapticType.impact);
        actions[95] = () => _pulse(HapticType.tap);
        actions[132] = () => _pulse(HapticType.heavy);
        break;

      case '🍕':
      case '1f355':
        const frames = 101;
        actions[27] = () => _pulse(HapticType.impact);
        actions[55] = () => _pulse(HapticType.heavy);
        actions[80] = () => _pulse(HapticType.tap);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🍖':
      case '1f356':
        const frames = 149;
        actions[25] = () => _pulse(HapticType.selection);
        actions[36] = () => _pulse(HapticType.heavy);
        actions[103] = () => _pulse(HapticType.impact);
        actions[120] = () => _pulse(HapticType.tap);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🍗':
      case '1f357':
        const frames = 170;
        actions[20] = () => _pulse(HapticType.selection);
        actions[40] = () => _pulse(HapticType.impact);
        actions[113] = () => _pulse(HapticType.heavy);
        actions[129] = () => _pulse(HapticType.tap);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🍘':
      case '1f358':
        const frames = 179;
        actions[34] = () => _pulse(HapticType.impact);
        actions[84] = () => _pulse(HapticType.heavy);
        actions[135] = () => _pulse(HapticType.tap);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🍙':
      case '1f359':
        const frames = 179;
        actions[17] = () => _pulse(HapticType.selection);
        actions[37] = () => _pulse(HapticType.heavy);
        actions[82] = () => _pulse(HapticType.impact);
        actions[133] = () => _pulse(HapticType.tap);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🍟':
      case '1f35f':
        actions[29] = () => _pulse(HapticType.selection);
        actions[50] = () => _pulse(HapticType.impact);
        actions[65] = () => _pulse(HapticType.tap);
        actions[104] = () => _pulse(HapticType.heavy);
        actions[120] = () => _pulse(HapticType.tap);
        break;

      case '🍡':
      case '1f361':
        actions[30] = () => _pulse(HapticType.heavy);
        actions[98] = () => _pulse(HapticType.impact);
        actions[126] = () => _pulse(HapticType.impact);
        actions[156] = () => _pulse(HapticType.heavy);
        break;

      case '🍢':
      case '1f362':
        const frames = 179;
        actions[19] = () => _pulse(HapticType.heavy);
        actions[81] = () => _pulse(HapticType.impact);
        actions[108] = () => _pulse(HapticType.impact);
        actions[126] = () => _pulse(HapticType.heavy);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🍣':
      case '1f363':
        const frames = 179;
        actions[25] = () => _pulse(HapticType.selection);
        actions[42] = () => _pulse(HapticType.impact);
        actions[74] = () => _pulse(HapticType.heavy);
        actions[128] = () => _pulse(HapticType.impact);
        actions[152] = () => _pulse(HapticType.tap);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🍥':
      case '1f365':
        const frames = 179;
        actions[47] = () => _pulse(HapticType.tap);
        actions[98] = () => _pulse(HapticType.tap);
        actions[148] = () => _pulse(HapticType.heavy);
        actions[169] = () => _pulse(HapticType.impact);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🍦':
      case '1f366':
        actions[18] = () => _pulse(HapticType.selection);
        actions[33] = () => _pulse(HapticType.heavy);
        actions[77] = () => _pulse(HapticType.impact);
        actions[127] = () => _pulse(HapticType.tap);
        break;

      case '🍩':
      case '1f369':
        actions[14] = () => _pulse(HapticType.selection);
        actions[27] = () => _pulse(HapticType.impact);
        actions[47] = () => _pulse(HapticType.heavy);
        actions[83] = () => _pulse(HapticType.impact);
        actions[135] = () => _pulse(HapticType.tap);
        break;

      case '🍪':
      case '1f36a':
        const frames = 179;
        actions[12] = () => _pulse(HapticType.selection);
        actions[38] = () => _pulse(HapticType.impact);
        actions[69] = () => _pulse(HapticType.heavy);
        actions[90] = () => _pulse(HapticType.tap);
        actions[118] = () => _pulse(HapticType.tap);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🍫':
      case '1f36b':
        actions[11] = () => _pulse(HapticType.impact);
        actions[25] = () => _pulse(HapticType.impact);
        actions[40] = () => _pulse(HapticType.heavy);
        actions[111] = () => _pulse(HapticType.tap);
        break;

      case '🍭':
      case '1f36d':
        actions[20] = () => _pulse(HapticType.selection);
        actions[48] = () => _pulse(HapticType.tap);
        actions[95] = () => _pulse(HapticType.impact);
        actions[119] = () => _pulse(HapticType.heavy);
        break;

      case '🍮':
      case '1f36e':
        actions[25] = () => _pulse(HapticType.selection);
        actions[48] = () => _pulse(HapticType.impact);
        actions[71] = () => _pulse(HapticType.heavy);
        actions[88] = () => _pulse(HapticType.tap);
        break;

      case '🍰':
      case '1f370':
        const frames = 179;
        actions[15] = () => _pulse(HapticType.selection);
        actions[45] = () => _pulse(HapticType.impact);
        actions[76] = () => _pulse(HapticType.heavy);
        actions[148] = () => _pulse(HapticType.tap);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🍱':
      case '1f371':
        const frames = 179;
        actions[13] = () => _pulse(HapticType.selection);
        actions[42] = () => _pulse(HapticType.heavy);
        actions[66] = () => _pulse(HapticType.impact);
        actions[100] = () => _pulse(HapticType.tap);
        actions[148] = () => _pulse(HapticType.tap);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🍳':
      case '1f373':
        actions[9] = () => _pulse(HapticType.selection);
        actions[64] = () => _pulse(HapticType.tap);
        actions[87] = () => _pulse(HapticType.heavy);
        actions[104] = () => _pulse(HapticType.impact);
        actions[146] = () => _pulse(HapticType.tap);
        break;

      case '🍷':
      case '1f377':
        const frames = 133;
        actions[14] = () => _pulse(HapticType.selection);
        actions[45] = () => _pulse(HapticType.tap);
        actions[74] = () => _pulse(HapticType.impact);
        actions[88] = () => _pulse(HapticType.heavy);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🍸':
      case '1f378':
        const frames = 149;
        actions[22] = () => _pulse(HapticType.selection);
        actions[37] = () => _pulse(HapticType.impact);
        actions[92] = () => _pulse(HapticType.tap);
        actions[120] = () => _pulse(HapticType.heavy);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🍹':
      case '1f379':
        actions[19] = () => _pulse(HapticType.tap);
        actions[44] = () => _pulse(HapticType.impact);
        actions[76] = () => _pulse(HapticType.heavy);
        actions[132] = () => _pulse(HapticType.tap);
        actions[164] = () => _pulse(HapticType.tap);
        break;

      case '🍼':
      case '1f37c':
        const frames = 144;
        actions[25] = () => _pulse(HapticType.tap);
        actions[49] = () => _pulse(HapticType.impact);
        actions[93] = () => _pulse(HapticType.heavy);
        actions[132] = () => _pulse(HapticType.tap);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🍽️':
      case '🍽':
      case '1f37d':
      case '1f37d-fe0f':
        actions[20] = () => _pulse(HapticType.selection);
        actions[46] = () => _pulse(HapticType.heavy);
        actions[71] = () => _pulse(HapticType.tap);
        actions[98] = () => _pulse(HapticType.heavy);
        actions[161] = () => _pulse(HapticType.tap);
        break;

      // --- 1f37f .. 1f385 & 1f393 .. 1f3a8 (Celebration & Arts) ---
      case '🍿':
      case '1f37f':
        const frames = 161;
        actions[26] = () => _pulse(HapticType.selection);
        actions[52] = () => _pulse(HapticType.tap);
        actions[71] = () => _pulse(HapticType.impact);
        actions[91] = () => _pulse(HapticType.heavy);
        actions[113] = () => _pulse(HapticType.impact);
        actions[146] = () => _pulse(HapticType.tap);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🎂':
      case '1f382':
        actions[30] = () => _pulse(HapticType.selection);
        actions[45] = () => _pulse(HapticType.tap);
        actions[101] = () => _pulse(HapticType.heavy);
        actions[126] = () => _pulse(HapticType.impact);
        actions[153] = () => _pulse(HapticType.tap);
        break;

      case '🎃':
      case '1f383':
        actions[8] = () => _pulse(HapticType.tap);
        actions[38] = () => _pulse(HapticType.heavy);
        actions[69] = () => _pulse(HapticType.selection);
        actions[101] = () => _pulse(HapticType.selection);
        actions[127] = () => _pulse(HapticType.impact);
        actions[155] = () => _pulse(HapticType.tap);
        break;

      case '🎄':
      case '1f384':
        actions[20] = () => _pulse(HapticType.selection);
        actions[46] = () => _pulse(HapticType.tap);
        actions[78] = () => _pulse(HapticType.tap);
        actions[93] = () => _pulse(HapticType.tap);
        actions[108] = () => _pulse(HapticType.impact);
        break;

      case '🎅':
      case '1f385':
        actions[8] = () => _pulse(HapticType.tap);
        actions[41] = () => _pulse(HapticType.impact);
        actions[65] = () => _pulse(HapticType.impact);
        actions[96] = () => _pulse(HapticType.heavy);
        actions[129] = () => _pulse(HapticType.tap);
        break;

      case '🎓':
      case '1f393':
        actions[28] = () => _pulse(HapticType.selection);
        actions[41] = () => _pulse(HapticType.impact);
        actions[106] = () => _pulse(HapticType.heavy);
        actions[119] = () => _pulse(HapticType.tap);
        break;

      case '🎖️':
      case '🎖':
      case '1f396':
      case '1f396-fe0f':
        actions[34] = () => _pulse(HapticType.selection);
        actions[53] = () => _pulse(HapticType.impact);
        actions[87] = () => _pulse(HapticType.tap);
        actions[123] = () => _pulse(HapticType.tap);
        actions[152] = () => _pulse(HapticType.heavy);
        break;

      case '🎗️':
      case '🎗':
      case '1f397':
      case '1f397-fe0f':
        actions[17] = () => _pulse(HapticType.selection);
        actions[55] = () => _pulse(HapticType.tap);
        actions[74] = () => _pulse(HapticType.impact);
        actions[101] = () => _pulse(HapticType.tap);
        break;

      case '🎙️':
      case '🎙':
      case '1f399':
      case '1f399-fe0f':
        const frames = 151;
        actions[10] = () => _pulse(HapticType.selection);
        actions[45] = () => _pulse(HapticType.impact);
        actions[68] = () => _pulse(HapticType.tap);
        actions[95] = () => _pulse(HapticType.heavy);
        return HapticBinding(
          animation: animation,
          totalFrames: frames,
          frameActions: actions,
        );

      case '🎟️':
      case '🎟':
      case '1f39f':
      case '1f39f-fe0f':
        actions[10] = () => _pulse(HapticType.selection);
        actions[44] = () => _pulse(HapticType.tap);
        actions[51] = () => _pulse(HapticType.heavy);
        actions[65] = () => _pulse(HapticType.impact);
        actions[117] = () => _pulse(HapticType.tap);
        break;

      case '🎢':
      case '1f3a2':
        actions[28] = () => _pulse(HapticType.selection);
        actions[45] = () => _pulse(HapticType.impact);
        actions[71] = () => _pulse(HapticType.tap);
        actions[98] = () => _pulse(HapticType.impact);
        actions[132] = () => _pulse(HapticType.tap);
        break;

      case '🎤':
      case '1f3a4':
        actions[20] = () => _pulse(HapticType.selection);
        actions[40] = () => _pulse(HapticType.heavy);
        actions[66] = () => _pulse(HapticType.tap);
        actions[86] = () => _pulse(HapticType.tap);
        actions[106] = () => _pulse(HapticType.tap);
        actions[126] = () => _pulse(HapticType.impact);
        break;

      case '🎨':
      case '1f3a8':
        actions[9] = () => _pulse(HapticType.selection);
        actions[35] = () => _pulse(HapticType.impact);
        actions[51] = () => _pulse(HapticType.tap);
        actions[63] = () => _pulse(HapticType.impact);
        actions[76] = () => _pulse(HapticType.tap);
        actions[97] = () => _pulse(HapticType.heavy);
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

  /// Attaches frame-accurate haptic feedback to the roll / idle phase AnimationController of a dice or ball.
  HapticBinding attachDiceRoll(
    Animation<double> animation,
    String emoji, {
    int totalFrames = 100,
  }) {
    final trimmed = emoji.trim();
    final Map<int, VoidCallback> actions = {};

    if (trimmed == '🏀' || trimmed == '1f3c0') {
      // 1f3c0_1: basketball bouncing on floor: f0 (slam), f50 (floor bounce), f100 (floor bounce)
      actions[0] = () => _pulse(HapticType.impact);
      actions[50] = () => _pulse(HapticType.heavy);
      actions[100] = () => _pulse(HapticType.impact);
    } else if (trimmed == '⚽' || trimmed == '26bd') {
      // 26bd_1: football bouncing on floor: f0 (slam), f60 (floor bounce), f120 (floor bounce)
      actions[0] = () => _pulse(HapticType.impact);
      actions[60] = () => _pulse(HapticType.heavy);
      actions[120] = () => _pulse(HapticType.impact);
    } else if (trimmed == '🎲' || trimmed == '1f3b2') {
      // 1f3b2_1: rolling dice: f0 (throw), f60 (floor landing)
      actions[0] = () => _pulse(HapticType.selection);
      actions[60] = () => _pulse(HapticType.heavy);
    } else if (trimmed == '🎳' || trimmed == '1f3b3') {
      // 1f3b3_1: bowling ball on lane: f0 (throw), f26 (lane impact)
      actions[0] = () => _pulse(HapticType.selection);
      actions[26] = () => _pulse(HapticType.impact);
    } else if (trimmed == '🎯' || trimmed == '1f3af') {
      actions[0] = () => _pulse(HapticType.selection);
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
      // In all basketball outcomes (1f3c0_2..6), the ball starts on the floor (f0),
      // rises up, drops back to the floor for the 2nd bounce (f40), and is launched into the shot!
      actions[0] = () => _pulse(HapticType.impact); // 1st ground bounce
      actions[40] = () => _pulse(HapticType.heavy); // 2nd ground bounce & shot launch

      if (value == 1) {
        // 1f3c0_2: Rim graze / airball miss
        actions[115] = () => _pulse(HapticType.heavy); // Rim graze strike
        actions[121] = () => _pulse(HapticType.impact); // Rebound off rim
      } else if (value == 2) {
        // 1f3c0_3: Rim rattle and bounce out
        actions[100] = () => _pulse(HapticType.heavy); // Rim strike
        actions[104] = () => _pulse(HapticType.impact); // Rim bounce
        actions[111] = () => _pulse(HapticType.tap); // Opposite rim rattle
        actions[125] = () => _pulse(HapticType.selection); // Rim roll out
      } else if (value == 3) {
        // 1f3c0_4: Backboard bank and rim roll out
        actions[114] = () => _pulse(HapticType.heavy); // Backboard strike
        actions[119] = () => _pulse(HapticType.impact); // Rim bounce
        actions[129] = () => _pulse(HapticType.tap); // Rim roll out
      } else if (value == 4) {
        // 1f3c0_5: Rim rattle, bank, and IN (Score!)
        actions[100] = () => _pulse(HapticType.heavy); // Rim strike
        actions[104] = () => _pulse(HapticType.impact); // Rim bounce
        actions[111] = () => _pulse(HapticType.tap); // Rim rattle
        actions[125] = () => _pulse(HapticType.tap); // Rim settle
        actions[133] = () => _pulse(HapticType.heavy); // Swish into net!
        actions[167] = () => _pulse(HapticType.impact); // Net exit drop
      } else {
        // 1f3c0_6 (value 5): Nothing but net! Clean SWISH (Score!)
        actions[104] = () => _pulse(HapticType.heavy); // Clean swish into net
        actions[117] = () => _pulse(HapticType.impact); // Net stretch climax
        actions[128] = () => _pulse(HapticType.tap); // Net recoil
      }
    }
    // 2. ⚽ Football (1..5)
    else if (trimmed == '⚽' || trimmed == '26bd') {
      // In all football outcomes (26bd_2..6), the foot strikes the ball at the turf at frame 2
      actions[2] = () => _pulse(HapticType.heavy);

      if (value == 1) {
        // 26bd_2: Wide left miss (flies past goal into background)
        actions[120] = () => _pulse(HapticType.impact); // 1st ground bounce far wide
        actions[142] = () => _pulse(HapticType.tap); // 2nd ground bounce
      } else if (value == 2) {
        // 26bd_3: Upper-right post/crossbar hit and rebound out! (hit 3 spark at f90)
        actions[90] = () => _pulse(HapticType.heavy); // Post strike & ricochet
        actions[112] = () => _pulse(HapticType.impact); // Rebound turf landing
        actions[144] = () => _pulse(HapticType.tap); // 2nd turf bounce
      } else if (value == 3) {
        // 26bd_4: Clean goal into center/left net (net bulges at f96-f105)
        actions[96] = () => _pulse(HapticType.heavy); // Ball hits back of the net
        actions[105] = () => _pulse(HapticType.impact); // Net maximum stretch
        actions[112] = () => _pulse(HapticType.impact); // Ball drops from net onto turf
        actions[130] = () => _pulse(HapticType.tap); // Turf settle
      } else if (value == 4) {
        // 26bd_5: Post-and-IN goal! (hit 3 post strike at f90, ricochets into net at f98)
        actions[90] = () => _pulse(HapticType.heavy); // Post strike
        actions[98] = () => _pulse(HapticType.heavy); // Ricochet into net
        actions[112] = () => _pulse(HapticType.impact); // Net ripple / bounce
        actions[126] = () => _pulse(HapticType.tap); // Turf settle inside goal
      } else {
        // 26bd_6 (value 5): Upper-corner rocket goal!
        actions[92] = () => _pulse(HapticType.heavy); // Blasts into top-corner net
        actions[105] = () => _pulse(HapticType.impact); // Net stretch recoil
        actions[120] = () => _pulse(HapticType.impact); // Ball drops from high net
        actions[140] = () => _pulse(HapticType.tap); // Turf settle inside goal
      }
    }
    // 3. 🎲 Dice (1..6)
    else if (trimmed == '🎲' || trimmed == '1f3b2') {
      // Floor contact keyframes from shadow and spinmaster layers in 1f3b2_2..7:
      // f0: initial throw
      // f60: 1st hard slam on floor (shadow 93%, Y=74)
      // f100: 2nd bounce on floor (shadow 93%, Y=59)
      // f130: 3rd settle bounce on floor (shadow 93%)
      // f150: resting on floor
      actions[0] = () => _pulse(HapticType.selection);
      actions[60] = () => _pulse(HapticType.heavy); // 1st floor slam
      actions[100] = () => _pulse(HapticType.impact); // 2nd floor bounce
      actions[130] = () => _pulse(HapticType.tap); // 3rd floor settle
      actions[150] = () => _pulse(HapticType.selection); // Rest
      if (value == 6) {
        actions[155] = () => _pulse(HapticType.tap); // Lucky 6 celebration
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
    // Exact reel stop frames from 1f3b0_4..20 keyframes:
    // Left reel: f32 (was 65 - arrived too late)
    // Center reel: f58 (was 83)
    // Right reel: f84 (was 101)
    // Jackpot celebration: f98 (was 111)
    final Map<int, VoidCallback> actions = {
      0: () => _pulse(HapticType.impact), // Lever pull
      32: () => _pulse(HapticType.selection), // Left reel stop
      58: () => _pulse(HapticType.selection), // Center reel stop
      84: () => _pulse(HapticType.selection), // Right reel stop
    };

    final isJackpot = (value == 1 || value == 22 || value == 43 || value == 64);
    if (isJackpot) {
      actions[98] = () {
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
      _schedule(517, () => _pulse(HapticType.heavy));
      _schedule(833, () => _pulse(HapticType.impact));
      _schedule(950, () => _pulse(HapticType.heavy));
      _schedule(1700, () => _pulse(HapticType.impact));
      _schedule(1850, () => _pulse(HapticType.heavy));
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
        _schedule(950, () => _pulse(HapticType.impact));
        _schedule(1083, () => _pulse(HapticType.heavy));
        _schedule(1233, () => _pulse(HapticType.impact));
        _schedule(1367, () => _pulse(HapticType.heavy));
        _schedule(1517, () => _pulse(HapticType.impact));
        _schedule(1617, () => _pulse(HapticType.heavy));
        _schedule(1783, () => _pulse(HapticType.impact));
        _schedule(1933, () => _pulse(HapticType.heavy));
        _schedule(2117, () => _pulse(HapticType.impact));
        _schedule(2400, () => _pulseClimax());
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
        _pulseClimax(); // Cork pop
        _schedule(300, () => _pulse(HapticType.impact)); // Foam eruption
        _schedule(1183, () => _pulse(HapticType.heavy)); // First glass clink
        _schedule(1517, () => _pulse(HapticType.impact)); // Second glass clink
        _schedule(2050, () => _pulse(HapticType.tap)); // Third glass clink
        break;

      case '🥂':
      case '1f942':
        // Middle cheer clink: glasses collide firmly at frame 68 (1133ms)
        _schedule(1133, () => _pulse(HapticType.heavy));
        _schedule(1233, () => _pulse(HapticType.tap));
        // Final cheer clink: glasses collide for the toast at frame 158 (2633ms)
        _schedule(2633, () => _pulse(HapticType.heavy));
        _schedule(2733, () => _pulse(HapticType.tap));
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
        _schedule(517, () => _pulse(HapticType.impact));
        _schedule(600, () => _pulse(HapticType.heavy));
        _schedule(817, () => _pulse(HapticType.impact));
        _schedule(900, () => _pulse(HapticType.heavy));
        _schedule(1083, () => _pulse(HapticType.heavy));
        _schedule(1267, () => _pulse(HapticType.impact));
        _schedule(1450, () => _pulse(HapticType.heavy));
        _schedule(2083, () => _pulse(HapticType.impact));
        _schedule(2233, () => _pulseClimax());
        break;

      case '💋':
      case '👄':
      case '1f48b':
      case '1f444':
        _pulse(HapticType.selection);
        _schedule(500, () => _pulse(HapticType.impact));
        _schedule(750, () => _pulse(HapticType.tap));
        break;

      case '🧨':
      case '1f9e8':
        _pulse(HapticType.selection);
        _schedule(1217, () => _pulse(HapticType.selection));
        _schedule(1333, () => _pulse(HapticType.tap));
        _schedule(1417, () => _pulse(HapticType.impact));
        _schedule(1500, () => _pulseClimax(withSecondaryEcho: true)); // Massive detonation
        _schedule(1600, () => _pulse(HapticType.impact)); // Blast shockwave
        _schedule(1783, () => _pulse(HapticType.tap)); // Smoke settle
        break;

      case '🤯':
      case '1f92f':
        _schedule(1183, () => _pulse(HapticType.selection));
        _schedule(1400, () => _pulse(HapticType.tap));
        _schedule(1633, () => _pulse(HapticType.impact));
        _schedule(1883, () => _pulseClimax()); // Brain eruption mushroom cloud
        _schedule(2033, () => _pulse(HapticType.impact)); // Flying pieces
        _schedule(2283, () => _pulse(HapticType.tap)); // Smoke dissipate
        break;

      case '💥':
      case '1f4a5':
        _pulseClimax(); // Flash explosion blast
        _schedule(167, () => _pulse(HapticType.impact)); // Circular shockwave expansion
        _schedule(567, () => _pulse(HapticType.tap)); // Dissipation
        _schedule(1733, () => _pulse(HapticType.tap)); // Residual tremor
        break;

      case '👊':
      case '1f44a':
        // Strike onto screen glass occurs precisely at frame 97 (1617 ms)
        _schedule(1617, () => _pulseClimax(withSecondaryEcho: true)); // Powerful punch smash into screen glass
        _schedule(1800, () => _pulse(HapticType.impact)); // Screen recoil shockwave
        break;

      case '🚀':
      case '1f680':
        _pulse(HapticType.selection);
        _schedule(833, () => _pulse(HapticType.tap));
        _schedule(1083, () => _pulse(HapticType.tap));
        _schedule(1333, () => _pulse(HapticType.impact)); // Engine rev up
        _schedule(1433, () => _pulseClimax()); // Rocket liftoff thrust
        _schedule(1967, () => _pulse(HapticType.impact)); // Trail flame
        break;

      case '💔':
      case '1f494':
        _pulse(HapticType.tap); // Heart beat
        _schedule(433, () => _pulse(HapticType.heavy)); // Crack splits in two
        _schedule(600, () => _pulse(HapticType.impact)); // Halves separation shudder
        _schedule(1633, () => _pulse(HapticType.impact)); // Halves slam and re-seal
        _schedule(1800, () => _pulse(HapticType.tap)); // Beat of healed heart
        break;

      case '💯':
      case '1f4af':
        _pulse(HapticType.selection);
        _schedule(833, () => _pulse(HapticType.impact)); // Underline 1
        _schedule(1050, () => _pulse(HapticType.heavy)); // Stamp underline 2
        _schedule(1333, () => _pulse(HapticType.tap)); // Ink splatter
        break;

      case '🥳':
      case '1f973':
        _pulse(HapticType.selection);
        _schedule(567, () => _pulse(HapticType.impact)); // Horn blower extends
        _schedule(1667, () => _pulseClimax()); // Confetti explosion blast
        break;

      case '🪙':
      case '1fa99':
        _pulse(HapticType.selection);
        _schedule(433, () => _pulse(HapticType.tap)); // Coin toss flick
        _schedule(1867, () => _pulse(HapticType.heavy)); // Metallic coin slap catch
        _schedule(2067, () => _pulse(HapticType.tap)); // Palm settle
        break;

      case '👻':
      case '1f47b':
        _pulse(HapticType.selection);
        _schedule(1183, () => _pulse(HapticType.heavy)); // Sudden "BOO!" scare jump
        _schedule(1517, () => _pulse(HapticType.tap)); // Wobble float
        break;

      case '😱':
      case '1f631':
        _pulse(HapticType.selection);
        _schedule(533, () => _pulse(HapticType.heavy)); // Slap hands on cheeks
        _schedule(700, () => _pulse(HapticType.tap)); // Tremble
        _schedule(883, () => _pulse(HapticType.tap)); // Tremble
        _schedule(1367, () => _pulse(HapticType.impact)); // Gasp of horror
        break;

      case '🎩':
      case '1f3a9':
        _pulse(HapticType.selection);
        _schedule(200, () => _pulse(HapticType.tap)); // Wand flourish
        _schedule(1433, () => _pulse(HapticType.heavy)); // Wand taps top hat brim
        _schedule(1633, () => _pulse(HapticType.impact)); // Rabbit pops out
        break;

      case '🗿':
      case '1f5ff':
        _pulse(HapticType.selection);
        _schedule(400, () => _pulse(HapticType.impact)); // Stone monolith shifts
        _schedule(1300, () => _pulse(HapticType.heavy)); // Solid stone turn lock
        break;

      case '🆒':
      case '1f192':
        _pulse(HapticType.selection);
        _schedule(1400, () => _pulse(HapticType.impact));
        _schedule(1700, () => _pulse(HapticType.heavy));
        _schedule(1833, () => _pulse(HapticType.tap));
        break;

      case '🆓':
      case '1f193':
        _pulse(HapticType.selection);
        _schedule(483, () => _pulse(HapticType.impact));
        _schedule(1000, () => _pulse(HapticType.heavy));
        _schedule(1183, () => _pulse(HapticType.tap));
        break;

      case '🆕':
      case '1f195':
        _schedule(83, () => _pulse(HapticType.selection));
        _schedule(500, () => _pulse(HapticType.heavy));
        _schedule(767, () => _pulse(HapticType.tap));
        break;

      case '🆗':
      case '1f197':
        _schedule(133, () => _pulse(HapticType.selection));
        _schedule(367, () => _pulse(HapticType.impact));
        _schedule(583, () => _pulse(HapticType.heavy));
        break;

      case '🆙':
      case '1f199':
        _schedule(367, () => _pulse(HapticType.selection));
        _schedule(667, () => _pulse(HapticType.heavy));
        _schedule(767, () => _pulse(HapticType.tap));
        break;

      case '🌈':
      case '1f308':
        _schedule(200, () => _pulse(HapticType.selection));
        _schedule(383, () => _pulse(HapticType.impact));
        _schedule(817, () => _pulse(HapticType.tap));
        break;

      case '🌑':
      case '1f311':
        _pulse(HapticType.selection);
        _schedule(500, () => _pulse(HapticType.tap));
        _schedule(1000, () => _pulse(HapticType.impact));
        break;

      case '🌒':
      case '1f312':
        _schedule(500, () => _pulse(HapticType.tap));
        _schedule(1000, () => _pulse(HapticType.impact));
        _schedule(1400, () => _pulse(HapticType.tap));
        break;

      case '🌓':
      case '1f313':
        _schedule(500, () => _pulse(HapticType.tap));
        _schedule(1000, () => _pulse(HapticType.impact));
        break;

      case '🌔':
      case '1f314':
        _schedule(500, () => _pulse(HapticType.tap));
        _schedule(1000, () => _pulse(HapticType.impact));
        _schedule(1317, () => _pulse(HapticType.tap));
        break;

      case '🌕':
      case '1f315':
        _schedule(250, () => _pulse(HapticType.selection));
        _schedule(1000, () => _pulse(HapticType.heavy));
        _schedule(1500, () => _pulse(HapticType.tap));
        break;

      case '🌖':
      case '1f316':
        _schedule(500, () => _pulse(HapticType.tap));
        _schedule(1000, () => _pulse(HapticType.impact));
        break;

      case '🌗':
      case '1f317':
        _schedule(500, () => _pulse(HapticType.tap));
        _schedule(1000, () => _pulse(HapticType.impact));
        break;

      case '🌘':
      case '1f318':
        _schedule(500, () => _pulse(HapticType.tap));
        _schedule(1000, () => _pulse(HapticType.impact));
        break;

      case '🌚':
      case '1f31a':
        _schedule(333, () => _pulse(HapticType.selection));
        _schedule(700, () => _pulse(HapticType.tap));
        _schedule(883, () => _pulse(HapticType.tap));
        break;

      case '🌛':
      case '1f31b':
        _schedule(433, () => _pulse(HapticType.tap));
        _schedule(683, () => _pulse(HapticType.tap));
        _schedule(1283, () => _pulse(HapticType.impact));
        break;

      case '🌜':
      case '1f31c':
        _schedule(383, () => _pulse(HapticType.tap));
        _schedule(600, () => _pulse(HapticType.tap));
        _schedule(733, () => _pulse(HapticType.impact));
        break;

      case '🌝':
      case '1f31d':
        _schedule(367, () => _pulse(HapticType.tap));
        _schedule(633, () => _pulse(HapticType.impact));
        _schedule(967, () => _pulse(HapticType.tap));
        break;

      case '🌞':
      case '1f31e':
        _schedule(183, () => _pulse(HapticType.selection));
        _schedule(517, () => _pulse(HapticType.impact));
        _schedule(967, () => _pulse(HapticType.tap));
        break;

      case '🌟':
      case '1f31f':
        _schedule(167, () => _pulse(HapticType.selection));
        _schedule(667, () => _pulse(HapticType.impact));
        _schedule(1333, () => _pulse(HapticType.heavy));
        _schedule(1833, () => _pulse(HapticType.tap));
        break;

      case '🌡':
      case '🌡️':
      case '1f321':
      case '1f321-fe0f':
        _schedule(300, () => _pulse(HapticType.selection));
        _schedule(850, () => _pulse(HapticType.impact));
        _schedule(1000, () => _pulse(HapticType.heavy));
        break;

      case '🌤':
      case '🌤️':
      case '1f324':
      case '1f324-fe0f':
        _schedule(583, () => _pulse(HapticType.selection));
        _schedule(767, () => _pulse(HapticType.tap));
        _schedule(1167, () => _pulse(HapticType.tap));
        break;

      case '🌥':
      case '🌥️':
      case '1f325':
      case '1f325-fe0f':
        _schedule(583, () => _pulse(HapticType.selection));
        _schedule(917, () => _pulse(HapticType.tap));
        _schedule(1367, () => _pulse(HapticType.tap));
        break;

      case '🌦':
      case '🌦️':
      case '1f326':
      case '1f326-fe0f':
        _schedule(217, () => _pulse(HapticType.selection));
        _schedule(367, () => _pulse(HapticType.tap));
        _schedule(800, () => _pulse(HapticType.tap));
        break;

      case '🌧':
      case '🌧️':
      case '1f327':
      case '1f327-fe0f':
        _schedule(217, () => _pulse(HapticType.selection));
        _schedule(367, () => _pulse(HapticType.impact));
        _schedule(800, () => _pulse(HapticType.tap));
        _schedule(1250, () => _pulse(HapticType.tap));
        break;

      case '🌨':
      case '🌨️':
      case '1f328':
      case '1f328-fe0f':
        _schedule(400, () => _pulse(HapticType.selection));
        _schedule(550, () => _pulse(HapticType.tap));
        _schedule(1000, () => _pulse(HapticType.tap));
        break;

      case '🌩':
      case '🌩️':
      case '1f329':
      case '1f329-fe0f':
        _schedule(400, () => _pulse(HapticType.selection));
        _schedule(750, () => _pulse(HapticType.heavy));
        _schedule(867, () => _pulse(HapticType.impact));
        _schedule(1167, () => _pulse(HapticType.tap));
        break;

      case '🌭':
      case '1f32d':
        _schedule(383, () => _pulse(HapticType.tap));
        _schedule(617, () => _pulse(HapticType.impact));
        _schedule(1083, () => _pulse(HapticType.heavy));
        break;

      case '🌮':
      case '1f32e':
        _schedule(550, () => _pulse(HapticType.impact));
        _schedule(667, () => _pulse(HapticType.heavy));
        _schedule(1133, () => _pulse(HapticType.tap));
        break;

      case '🌱':
      case '1f331':
        _schedule(167, () => _pulse(HapticType.selection));
        _schedule(367, () => _pulse(HapticType.impact));
        _schedule(567, () => _pulse(HapticType.tap));
        break;

      case '🌲':
      case '1f332':
        _schedule(433, () => _pulse(HapticType.selection));
        _schedule(733, () => _pulse(HapticType.impact));
        _schedule(1133, () => _pulse(HapticType.tap));
        break;

      case '🌳':
      case '1f333':
        _schedule(500, () => _pulse(HapticType.selection));
        _schedule(667, () => _pulse(HapticType.impact));
        _schedule(1250, () => _pulse(HapticType.tap));
        break;

      case '🌴':
      case '1f334':
        _schedule(367, () => _pulse(HapticType.selection));
        _schedule(583, () => _pulse(HapticType.impact));
        _schedule(1000, () => _pulse(HapticType.tap));
        break;

      case '🌵':
      case '1f335':
        _schedule(300, () => _pulse(HapticType.tap));
        _schedule(500, () => _pulse(HapticType.tap));
        _schedule(917, () => _pulse(HapticType.impact));
        break;

      case '🌷':
      case '1f337':
        _schedule(283, () => _pulse(HapticType.selection));
        _schedule(850, () => _pulse(HapticType.impact));
        _schedule(1150, () => _pulse(HapticType.tap));
        break;

      case '🌸':
      case '1f338':
        _schedule(417, () => _pulse(HapticType.selection));
        _schedule(683, () => _pulse(HapticType.impact));
        _schedule(1200, () => _pulse(HapticType.tap));
        break;

      case '🌹':
      case '1f339':
        _schedule(333, () => _pulse(HapticType.selection));
        _schedule(700, () => _pulse(HapticType.heavy));
        _schedule(1250, () => _pulse(HapticType.tap));
        break;

      case '🌺':
      case '1f33a':
        _schedule(267, () => _pulse(HapticType.selection));
        _schedule(983, () => _pulse(HapticType.impact));
        _schedule(1483, () => _pulse(HapticType.tap));
        break;

      case '🌼':
      case '1f33c':
        _schedule(300, () => _pulse(HapticType.selection));
        _schedule(800, () => _pulse(HapticType.impact));
        _schedule(1667, () => _pulse(HapticType.tap));
        break;

      case '🌿':
      case '1f33f':
        _schedule(350, () => _pulse(HapticType.selection));
        _schedule(583, () => _pulse(HapticType.tap));
        _schedule(783, () => _pulse(HapticType.impact));
        break;

      case '🍀':
      case '1f340':
        _schedule(317, () => _pulse(HapticType.selection));
        _schedule(917, () => _pulse(HapticType.impact));
        _schedule(1867, () => _pulse(HapticType.heavy));
        _schedule(2083, () => _pulse(HapticType.tap));
        break;

      // --- 1f34c .. 1f37d-fe0f (Food & Drink) ---
      case '🍌':
      case '1f34c':
        _schedule(267, () => _pulse(HapticType.selection));
        _schedule(833, () => _pulse(HapticType.tap));
        _schedule(1183, () => _pulse(HapticType.heavy));
        _schedule(1667, () => _pulse(HapticType.impact));
        break;

      case '🍓':
      case '1f353':
        _schedule(633, () => _pulse(HapticType.selection));
        _schedule(900, () => _pulse(HapticType.heavy));
        _schedule(1500, () => _pulse(HapticType.impact));
        _schedule(2017, () => _pulse(HapticType.tap));
        break;

      case '🍔':
      case '1f354':
        _schedule(383, () => _pulse(HapticType.selection));
        _schedule(1000, () => _pulse(HapticType.tap));
        _schedule(1233, () => _pulse(HapticType.impact));
        _schedule(1583, () => _pulse(HapticType.tap));
        _schedule(2200, () => _pulse(HapticType.heavy));
        break;

      case '🍕':
      case '1f355':
        _schedule(450, () => _pulse(HapticType.impact));
        _schedule(917, () => _pulse(HapticType.heavy));
        _schedule(1333, () => _pulse(HapticType.tap));
        break;

      case '🍖':
      case '1f356':
        _schedule(417, () => _pulse(HapticType.selection));
        _schedule(600, () => _pulse(HapticType.heavy));
        _schedule(1717, () => _pulse(HapticType.impact));
        _schedule(2000, () => _pulse(HapticType.tap));
        break;

      case '🍗':
      case '1f357':
        _schedule(333, () => _pulse(HapticType.selection));
        _schedule(667, () => _pulse(HapticType.impact));
        _schedule(1883, () => _pulse(HapticType.heavy));
        _schedule(2150, () => _pulse(HapticType.tap));
        break;

      case '🍘':
      case '1f358':
        _schedule(567, () => _pulse(HapticType.impact));
        _schedule(1400, () => _pulse(HapticType.heavy));
        _schedule(2250, () => _pulse(HapticType.tap));
        break;

      case '🍙':
      case '1f359':
        _schedule(283, () => _pulse(HapticType.selection));
        _schedule(617, () => _pulse(HapticType.heavy));
        _schedule(1367, () => _pulse(HapticType.impact));
        _schedule(2217, () => _pulse(HapticType.tap));
        break;

      case '🍟':
      case '1f35f':
        _schedule(483, () => _pulse(HapticType.selection));
        _schedule(833, () => _pulse(HapticType.impact));
        _schedule(1083, () => _pulse(HapticType.tap));
        _schedule(1733, () => _pulse(HapticType.heavy));
        _schedule(2000, () => _pulse(HapticType.tap));
        break;

      case '🍡':
      case '1f361':
        _schedule(500, () => _pulse(HapticType.heavy));
        _schedule(1633, () => _pulse(HapticType.impact));
        _schedule(2100, () => _pulse(HapticType.impact));
        _schedule(2600, () => _pulse(HapticType.heavy));
        break;

      case '🍢':
      case '1f362':
        _schedule(317, () => _pulse(HapticType.heavy));
        _schedule(1350, () => _pulse(HapticType.impact));
        _schedule(1800, () => _pulse(HapticType.impact));
        _schedule(2100, () => _pulse(HapticType.heavy));
        break;

      case '🍣':
      case '1f363':
        _schedule(417, () => _pulse(HapticType.selection));
        _schedule(700, () => _pulse(HapticType.impact));
        _schedule(1233, () => _pulse(HapticType.heavy));
        _schedule(2133, () => _pulse(HapticType.impact));
        _schedule(2533, () => _pulse(HapticType.tap));
        break;

      case '🍥':
      case '1f365':
        _schedule(783, () => _pulse(HapticType.tap));
        _schedule(1633, () => _pulse(HapticType.tap));
        _schedule(2467, () => _pulse(HapticType.heavy));
        _schedule(2817, () => _pulse(HapticType.impact));
        break;

      case '🍦':
      case '1f366':
        _schedule(300, () => _pulse(HapticType.selection));
        _schedule(550, () => _pulse(HapticType.heavy));
        _schedule(1283, () => _pulse(HapticType.impact));
        _schedule(2117, () => _pulse(HapticType.tap));
        break;

      case '🍩':
      case '1f369':
        _schedule(233, () => _pulse(HapticType.selection));
        _schedule(450, () => _pulse(HapticType.impact));
        _schedule(783, () => _pulse(HapticType.heavy));
        _schedule(1383, () => _pulse(HapticType.impact));
        _schedule(2250, () => _pulse(HapticType.tap));
        break;

      case '🍪':
      case '1f36a':
        _schedule(200, () => _pulse(HapticType.selection));
        _schedule(633, () => _pulse(HapticType.impact));
        _schedule(1150, () => _pulse(HapticType.heavy));
        _schedule(1500, () => _pulse(HapticType.tap));
        _schedule(1967, () => _pulse(HapticType.tap));
        break;

      case '🍫':
      case '1f36b':
        _schedule(183, () => _pulse(HapticType.impact));
        _schedule(417, () => _pulse(HapticType.impact));
        _schedule(667, () => _pulse(HapticType.heavy));
        _schedule(1850, () => _pulse(HapticType.tap));
        break;

      case '🍭':
      case '1f36d':
        _schedule(333, () => _pulse(HapticType.selection));
        _schedule(800, () => _pulse(HapticType.tap));
        _schedule(1583, () => _pulse(HapticType.impact));
        _schedule(1983, () => _pulse(HapticType.heavy));
        break;

      case '🍮':
      case '1f36e':
        _schedule(417, () => _pulse(HapticType.selection));
        _schedule(800, () => _pulse(HapticType.impact));
        _schedule(1183, () => _pulse(HapticType.heavy));
        _schedule(1467, () => _pulse(HapticType.tap));
        break;

      case '🍰':
      case '1f370':
        _schedule(250, () => _pulse(HapticType.selection));
        _schedule(750, () => _pulse(HapticType.impact));
        _schedule(1267, () => _pulse(HapticType.heavy));
        _schedule(2467, () => _pulse(HapticType.tap));
        break;

      case '🍱':
      case '1f371':
        _schedule(217, () => _pulse(HapticType.selection));
        _schedule(700, () => _pulse(HapticType.heavy));
        _schedule(1100, () => _pulse(HapticType.impact));
        _schedule(1667, () => _pulse(HapticType.tap));
        _schedule(2467, () => _pulse(HapticType.tap));
        break;

      case '🍳':
      case '1f373':
        _schedule(150, () => _pulse(HapticType.selection));
        _schedule(1067, () => _pulse(HapticType.tap));
        _schedule(1450, () => _pulse(HapticType.heavy));
        _schedule(1733, () => _pulse(HapticType.impact));
        _schedule(2433, () => _pulse(HapticType.tap));
        break;

      case '🍷':
      case '1f377':
        _schedule(233, () => _pulse(HapticType.selection));
        _schedule(750, () => _pulse(HapticType.tap));
        _schedule(1233, () => _pulse(HapticType.impact));
        _schedule(1467, () => _pulse(HapticType.heavy));
        break;

      case '🍸':
      case '1f378':
        _schedule(367, () => _pulse(HapticType.selection));
        _schedule(617, () => _pulse(HapticType.impact));
        _schedule(1533, () => _pulse(HapticType.tap));
        _schedule(2000, () => _pulse(HapticType.heavy));
        break;

      case '🍹':
      case '1f379':
        _schedule(317, () => _pulse(HapticType.tap));
        _schedule(733, () => _pulse(HapticType.impact));
        _schedule(1267, () => _pulse(HapticType.heavy));
        _schedule(2200, () => _pulse(HapticType.tap));
        _schedule(2733, () => _pulse(HapticType.tap));
        break;

      case '🍼':
      case '1f37c':
        _schedule(417, () => _pulse(HapticType.tap));
        _schedule(817, () => _pulse(HapticType.impact));
        _schedule(1550, () => _pulse(HapticType.heavy));
        _schedule(2200, () => _pulse(HapticType.tap));
        break;

      case '🍽️':
      case '🍽':
      case '1f37d':
      case '1f37d-fe0f':
        _schedule(333, () => _pulse(HapticType.selection));
        _schedule(767, () => _pulse(HapticType.heavy));
        _schedule(1183, () => _pulse(HapticType.tap));
        _schedule(1633, () => _pulse(HapticType.heavy));
        _schedule(2683, () => _pulse(HapticType.tap));
        break;

      // --- 1f37f .. 1f385 & 1f393 .. 1f3a8 (Celebration & Arts) ---
      case '🍿':
      case '1f37f':
        _schedule(433, () => _pulse(HapticType.selection));
        _schedule(867, () => _pulse(HapticType.tap));
        _schedule(1183, () => _pulse(HapticType.impact));
        _schedule(1517, () => _pulse(HapticType.heavy));
        _schedule(1883, () => _pulse(HapticType.impact));
        _schedule(2433, () => _pulse(HapticType.tap));
        break;

      case '🎂':
      case '1f382':
        _schedule(500, () => _pulse(HapticType.selection));
        _schedule(750, () => _pulse(HapticType.tap));
        _schedule(1683, () => _pulse(HapticType.heavy));
        _schedule(2100, () => _pulse(HapticType.impact));
        _schedule(2550, () => _pulse(HapticType.tap));
        break;

      case '🎃':
      case '1f383':
        _schedule(133, () => _pulse(HapticType.tap));
        _schedule(633, () => _pulse(HapticType.heavy));
        _schedule(1150, () => _pulse(HapticType.selection));
        _schedule(1683, () => _pulse(HapticType.selection));
        _schedule(2117, () => _pulse(HapticType.impact));
        _schedule(2583, () => _pulse(HapticType.tap));
        break;

      case '🎄':
      case '1f384':
        _schedule(333, () => _pulse(HapticType.selection));
        _schedule(767, () => _pulse(HapticType.tap));
        _schedule(1300, () => _pulse(HapticType.tap));
        _schedule(1550, () => _pulse(HapticType.tap));
        _schedule(1800, () => _pulse(HapticType.impact));
        break;

      case '🎅':
      case '1f385':
        _schedule(133, () => _pulse(HapticType.tap));
        _schedule(683, () => _pulse(HapticType.impact));
        _schedule(1083, () => _pulse(HapticType.impact));
        _schedule(1600, () => _pulse(HapticType.heavy));
        _schedule(2150, () => _pulse(HapticType.tap));
        break;

      case '🎓':
      case '1f393':
        _schedule(467, () => _pulse(HapticType.selection));
        _schedule(683, () => _pulse(HapticType.impact));
        _schedule(1767, () => _pulse(HapticType.heavy));
        _schedule(1983, () => _pulse(HapticType.tap));
        break;

      case '🎖️':
      case '🎖':
      case '1f396':
      case '1f396-fe0f':
        _schedule(567, () => _pulse(HapticType.selection));
        _schedule(883, () => _pulse(HapticType.impact));
        _schedule(1450, () => _pulse(HapticType.tap));
        _schedule(2050, () => _pulse(HapticType.tap));
        _schedule(2533, () => _pulse(HapticType.heavy));
        break;

      case '🎗️':
      case '🎗':
      case '1f397':
      case '1f397-fe0f':
        _schedule(283, () => _pulse(HapticType.selection));
        _schedule(917, () => _pulse(HapticType.tap));
        _schedule(1233, () => _pulse(HapticType.impact));
        _schedule(1683, () => _pulse(HapticType.tap));
        break;

      case '🎙️':
      case '🎙':
      case '1f399':
      case '1f399-fe0f':
        _schedule(167, () => _pulse(HapticType.selection));
        _schedule(750, () => _pulse(HapticType.impact));
        _schedule(1133, () => _pulse(HapticType.tap));
        _schedule(1583, () => _pulse(HapticType.heavy));
        break;

      case '🎟️':
      case '🎟':
      case '1f39f':
      case '1f39f-fe0f':
        _schedule(167, () => _pulse(HapticType.selection));
        _schedule(733, () => _pulse(HapticType.tap));
        _schedule(850, () => _pulse(HapticType.heavy));
        _schedule(1083, () => _pulse(HapticType.impact));
        _schedule(1950, () => _pulse(HapticType.tap));
        break;

      case '🎢':
      case '1f3a2':
        _schedule(467, () => _pulse(HapticType.selection));
        _schedule(750, () => _pulse(HapticType.impact));
        _schedule(1183, () => _pulse(HapticType.tap));
        _schedule(1633, () => _pulse(HapticType.impact));
        _schedule(2200, () => _pulse(HapticType.tap));
        break;

      case '🎤':
      case '1f3a4':
        _schedule(333, () => _pulse(HapticType.selection));
        _schedule(667, () => _pulse(HapticType.heavy));
        _schedule(1100, () => _pulse(HapticType.tap));
        _schedule(1433, () => _pulse(HapticType.tap));
        _schedule(1767, () => _pulse(HapticType.tap));
        _schedule(2100, () => _pulse(HapticType.impact));
        break;

      case '🎨':
      case '1f3a8':
        _schedule(150, () => _pulse(HapticType.selection));
        _schedule(583, () => _pulse(HapticType.impact));
        _schedule(850, () => _pulse(HapticType.tap));
        _schedule(1050, () => _pulse(HapticType.impact));
        _schedule(1267, () => _pulse(HapticType.tap));
        _schedule(1617, () => _pulse(HapticType.heavy));
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
      _schedule(1000, () => _pulse(HapticType.heavy)); // 1st floor slam
      _schedule(1667, () => _pulse(HapticType.impact)); // 2nd floor bounce
      _schedule(2167, () => _pulse(HapticType.tap)); // 3rd settle
      _schedule(2500, () => _pulse(HapticType.selection)); // Rest
      if (value == 6) {
        _schedule(2580, () => _pulse(HapticType.tap));
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
      _pulse(HapticType.impact); // Frame 0: 1st ground bounce
      _schedule(667, () => _pulse(HapticType.heavy)); // Frame 40: 2nd ground bounce & shot launch

      if (value == 1) {
        _schedule(1917, () => _pulse(HapticType.heavy)); // f115: rim graze
        _schedule(2017, () => _pulse(HapticType.impact)); // f121: rebound
      } else if (value == 2) {
        _schedule(1667, () => _pulse(HapticType.heavy)); // f100: rim hit
        _schedule(1733, () => _pulse(HapticType.impact)); // f104: bounce
        _schedule(1850, () => _pulse(HapticType.tap)); // f111: rattle
        _schedule(2083, () => _pulse(HapticType.selection)); // f125: roll out
      } else if (value == 3) {
        _schedule(1900, () => _pulse(HapticType.heavy)); // f114: backboard strike
        _schedule(1983, () => _pulse(HapticType.impact)); // f119: rim bounce
        _schedule(2150, () => _pulse(HapticType.tap)); // f129: roll out
      } else if (value == 4) {
        _schedule(1667, () => _pulse(HapticType.heavy)); // f100: rim hit
        _schedule(1733, () => _pulse(HapticType.impact)); // f104: bounce
        _schedule(1850, () => _pulse(HapticType.tap)); // f111: rattle
        _schedule(2083, () => _pulse(HapticType.tap)); // f125: settle
        _schedule(2217, () => _pulse(HapticType.heavy)); // f133: swish!
        _schedule(2783, () => _pulse(HapticType.impact)); // f167: net exit
      } else {
        _schedule(1733, () => _pulse(HapticType.heavy)); // f104: clean swish
        _schedule(1950, () => _pulse(HapticType.impact)); // f117: stretch climax
        _schedule(2133, () => _pulse(HapticType.tap)); // f128: recoil
      }
      return;
    }

    // ⚽ Football / Soccer (1..5)
    if (trimmed == '⚽' || trimmed == '26bd') {
      // Frame 2 turf kick off
      _pulse(HapticType.heavy);

      if (value == 1) {
        // 26bd_2: Wide left miss
        _schedule(2000, () => _pulse(HapticType.impact)); // f120: ground bounce
        _schedule(2367, () => _pulse(HapticType.tap)); // f142: 2nd bounce
      } else if (value == 2) {
        // 26bd_3: Post strike & rebound out
        _schedule(1500, () => _pulse(HapticType.heavy)); // f90: post strike
        _schedule(1867, () => _pulse(HapticType.impact)); // f112: turf landing
        _schedule(2400, () => _pulse(HapticType.tap)); // f144: 2nd turf bounce
      } else if (value == 3) {
        // 26bd_4: Clean goal into center/left net
        _schedule(1600, () => _pulse(HapticType.heavy)); // f96: net hit
        _schedule(1750, () => _pulse(HapticType.impact)); // f105: net stretch
        _schedule(1867, () => _pulse(HapticType.impact)); // f112: drop to turf
        _schedule(2167, () => _pulse(HapticType.tap)); // f130: turf settle
      } else if (value == 4) {
        // 26bd_5: Post-and-IN goal
        _schedule(1500, () => _pulse(HapticType.heavy)); // f90: post strike
        _schedule(1633, () => _pulse(HapticType.heavy)); // f98: ricochet into net
        _schedule(1867, () => _pulse(HapticType.impact)); // f112: net ripple
        _schedule(2100, () => _pulse(HapticType.tap)); // f126: turf settle
      } else {
        // 26bd_6 (value 5): Upper-corner rocket goal
        _schedule(1533, () => _pulse(HapticType.heavy)); // f92: top net blast
        _schedule(1750, () => _pulse(HapticType.impact)); // f105: net recoil
        _schedule(2000, () => _pulse(HapticType.impact)); // f120: drop to turf
        _schedule(2333, () => _pulse(HapticType.tap)); // f140: turf settle
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
      _pulse(HapticType.impact); // Lever pull
      _schedule(533, () => _pulse(HapticType.selection)); // Left reel stop (f32)
      _schedule(967, () => _pulse(HapticType.selection)); // Center reel stop (f58)
      _schedule(1400, () => _pulse(HapticType.selection)); // Right reel stop (f84)
      if (value == 1 || value == 22 || value == 43 || value == 64) {
        _schedule(1633, () { // Jackpot celebration (f98)
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
        s == '🤎';
  }
}
