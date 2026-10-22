import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/services/dice_cache_service.dart';
import 'package:theaver/services/emoji_effect_cache_service.dart';
import 'package:theaver/services/emoji_haptic_service.dart';
import 'package:theaver/utils/emoji_utils.dart';
import 'package:theaver/widgets/message/dice_message_widget.dart';
import 'package:theaver/widgets/message/slot_machine_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dice Emojis & Haptics Tests', () {
    test('EmojiUtils recognizes all 6 Telegram dice emojis and codepoints', () {
      const dice = ['🎲', '🎯', '🏀', '⚽', '🎳', '🎰'];
      const codepoints = ['1f3b2', '1f3af', '1f3c0', '26bd', '1f3b3', '1f3b0'];

      for (int i = 0; i < dice.length; i++) {
        expect(EmojiUtils.isDiceEmoji(dice[i]), isTrue);
        expect(EmojiUtils.isDiceEmoji(codepoints[i]), isTrue);
        expect(EmojiUtils.diceCodepoint(dice[i]), equals(codepoints[i]));
        expect(EmojiUtils.diceCodepoint(codepoints[i]), equals(codepoints[i]));
      }

      expect(EmojiUtils.isDiceEmoji('hello'), isFalse);
      expect(EmojiUtils.isDiceEmoji('❤️'), isFalse);
      expect(EmojiUtils.isDiceEmoji('🍑'), isFalse);
    });

    test('DiceCacheService.getOutcomeIndex calculates correct animation index', () {
      // 🎲 Dice: value 1..6 -> index 2..7
      expect(DiceCacheService.getOutcomeIndex('🎲', 1), equals(2));
      expect(DiceCacheService.getOutcomeIndex('🎲', 6), equals(7));

      // 🎯 Darts: value 1..6 -> index 2..7
      expect(DiceCacheService.getOutcomeIndex('🎯', 1), equals(2));
      expect(DiceCacheService.getOutcomeIndex('🎯', 6), equals(7));

      // 🏀 Basketball: value 1..5 -> index 2..6
      expect(DiceCacheService.getOutcomeIndex('🏀', 1), equals(2));
      expect(DiceCacheService.getOutcomeIndex('🏀', 5), equals(6));

      // ⚽ Football: value 1..5 -> index 2..6
      expect(DiceCacheService.getOutcomeIndex('⚽', 1), equals(2));
      expect(DiceCacheService.getOutcomeIndex('⚽', 5), equals(6));

      // 🎳 Bowling: value 1..6 -> index 2..7
      expect(DiceCacheService.getOutcomeIndex('🎳', 1), equals(2));
      expect(DiceCacheService.getOutcomeIndex('🎳', 6), equals(7));

      // 🎰 Slot Machine 5-layer composite mapping
      // Value 1: BAR BAR BAR (Jackpot)
      final slot1 = DiceCacheService.getSlotIndices(1);
      expect(slot1.isWin, isTrue);
      expect(slot1.is777, isFalse);
      expect(slot1.backgroundIndex, equals(2)); // drumsBG+light_win
      expect(slot1.leverIndex, equals(3));
      expect(slot1.leftOutcomeIndex, equals(6));   // left_bar
      expect(slot1.centerOutcomeIndex, equals(12)); // middle_bar
      expect(slot1.rightOutcomeIndex, equals(18));  // right_bar

      // Value 22: BERRIES BERRIES BERRIES (Jackpot)
      final slot22 = DiceCacheService.getSlotIndices(22);
      expect(slot22.isWin, isTrue);
      expect(slot22.is777, isFalse);
      expect(slot22.backgroundIndex, equals(2));
      expect(slot22.leftOutcomeIndex, equals(7));   // left_berries
      expect(slot22.centerOutcomeIndex, equals(13)); // middle_berries
      expect(slot22.rightOutcomeIndex, equals(19));  // right_berries

      // Value 43: LEMON LEMON LEMON (Jackpot)
      final slot43 = DiceCacheService.getSlotIndices(43);
      expect(slot43.isWin, isTrue);
      expect(slot43.is777, isFalse);
      expect(slot43.backgroundIndex, equals(2));
      expect(slot43.leftOutcomeIndex, equals(8));   // left_lemon
      expect(slot43.centerOutcomeIndex, equals(14)); // middle_lemon
      expect(slot43.rightOutcomeIndex, equals(20));  // right_lemon

      // Value 64: 777 Jackpot
      final slot64 = DiceCacheService.getSlotIndices(64);
      expect(slot64.isWin, isTrue);
      expect(slot64.is777, isTrue);
      expect(slot64.backgroundIndex, equals(2));
      expect(slot64.leftOutcomeIndex, equals(4));   // left_7_win
      expect(slot64.centerOutcomeIndex, equals(10)); // middle_7_win
      expect(slot64.rightOutcomeIndex, equals(16));  // right_7_win

      // Non-win (Value 2: left Berries, mid BAR, right BAR)
      final slot2 = DiceCacheService.getSlotIndices(2);
      expect(slot2.isWin, isFalse);
      expect(slot2.is777, isFalse);
      expect(slot2.backgroundIndex, equals(1)); // drumsBG+light_idle
      expect(slot2.leftOutcomeIndex, equals(7));   // left_berries
      expect(slot2.centerOutcomeIndex, equals(12)); // middle_bar
      expect(slot2.rightOutcomeIndex, equals(18));  // right_bar
    });

    test('EmojiHapticService handles all interactive emojis and cancels safely', () {
      final haptic = EmojiHapticService.instance;

      // Heartbeat 6-pulse pattern
      expect(() => haptic.playInteractiveEmojiHaptic('❤️'), returnsNormally);
      haptic.cancelAll();

      // Peach slap
      expect(() => haptic.playInteractiveEmojiHaptic('🍑'), returnsNormally);
      haptic.cancelAll();

      // Coffin double thud
      expect(() => haptic.playInteractiveEmojiHaptic('⚰️'), returnsNormally);
      haptic.cancelAll();

      // Variant B: party popper, balloon, bomb, champagne
      expect(() => haptic.playInteractiveEmojiHaptic('🎉'), returnsNormally);
      expect(() => haptic.playInteractiveEmojiHaptic('🎈'), returnsNormally);
      expect(() => haptic.playInteractiveEmojiHaptic('💣'), returnsNormally);
      expect(() => haptic.playInteractiveEmojiHaptic('🍾'), returnsNormally);
      expect(() => haptic.playInteractiveEmojiHaptic('🔥'), returnsNormally);
      haptic.cancelAll();

      // Dice roll haptics
      expect(() => haptic.playDiceHaptic('🎲', 6), returnsNormally);
      expect(() => haptic.playDiceHaptic('🎯', 6), returnsNormally);
      expect(() => haptic.playDiceHaptic('🏀', 4), returnsNormally);
      expect(() => haptic.playDiceHaptic('⚽', 5), returnsNormally);
      expect(() => haptic.playDiceHaptic('🎳', 6), returnsNormally);
      expect(() => haptic.playDiceHaptic('🎰', 64), returnsNormally);
      // Non-interactive / static emojis handle safely without error
      expect(() => haptic.playInteractiveEmojiHaptic('🪑'), returnsNormally);
      expect(() => haptic.playInteractiveEmojiHaptic('random_text'), returnsNormally);
      haptic.cancelAll();
    });

    test('Peach 🍑 is recognized as both animated emoji and effect', () {
      expect(EmojiEffectCacheService.instance.hasAnimatedEmoji('🍑'), isTrue);
      expect(EmojiEffectCacheService.instance.hasAnimatedEmoji('1f351'), isTrue);
      expect(EmojiEffectCacheService.instance.hasEffect('🍑'), isTrue);
      expect(EmojiEffectCacheService.instance.hasEffect('1f351'), isTrue);
    });

    testWidgets('DiceMessageWidget renders with autoPlay=false without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DiceMessageWidget(
              emoji: '🎲',
              value: 6,
              autoPlay: false,
            ),
          ),
        ),
      );

      expect(find.byType(DiceMessageWidget), findsOneWidget);
    });

    testWidgets('SlotMachineWidget renders composite layers without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DiceMessageWidget(
              emoji: '🎰',
              value: 64, // 777 Jackpot
              autoPlay: false,
            ),
          ),
        ),
      );

      expect(find.byType(DiceMessageWidget), findsOneWidget);
      expect(find.byType(SlotMachineWidget), findsOneWidget);
    });

    testWidgets('HapticBinding triggers actions on exact keyframes and resets on 0', (tester) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(seconds: 3),
      );

      final triggeredFrames = <int>[];
      final binding = HapticBinding(
        animation: controller,
        totalFrames: 180,
        frameActions: {
          24: () => triggeredFrames.add(24),
          36: () => triggeredFrames.add(36),
          162: () => triggeredFrames.add(162),
        },
      );

      // Advance to frame 20 (no triggers)
      controller.value = 20 / 180;
      expect(triggeredFrames, isEmpty);

      // Advance to frame 30 (frame 24 triggers)
      controller.value = 30 / 180;
      expect(triggeredFrames, equals([24]));

      // Advance to frame 170 (frames 36 and 162 trigger)
      controller.value = 170 / 180;
      expect(triggeredFrames, equals([24, 36, 162]));

      // Advance again to 180 (no duplicate triggers)
      controller.value = 1.0;
      expect(triggeredFrames, equals([24, 36, 162]));

      // Reset to 0 (clears triggers)
      controller.value = 0.0;
      triggeredFrames.clear();

      // Advance back to frame 30 (frame 24 triggers again on replay)
      controller.value = 30 / 180;
      expect(triggeredFrames, equals([24]));

      binding.dispose();
      controller.value = 1.0;
      // Disposed: no further triggers
      expect(triggeredFrames, equals([24]));

      controller.dispose();
    });

    test('attachInteractiveEmoji registers keyframes correctly', () {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(seconds: 3),
      );

      final coffinBinding = EmojiHapticService.instance.attachInteractiveEmoji(controller, '⚰️');
      expect(coffinBinding.frameActions.containsKey(24), isTrue);
      expect(coffinBinding.frameActions.containsKey(36), isTrue);
      expect(coffinBinding.frameActions.containsKey(162), isTrue);
      coffinBinding.dispose();

      // ❤️ 3 double heartbeats (impact + tap) on the Lottie beat peaks.
      for (final heart in ['❤️', '2764', '🧡', '🤍', '🤎']) {
        final heartBinding = EmojiHapticService.instance.attachInteractiveEmoji(controller, heart);
        expect(heartBinding.frameActions.keys, equals([5, 20, 64, 79, 129, 144]), reason: heart);
        heartBinding.dispose();
      }

      final clapBinding = EmojiHapticService.instance.attachInteractiveEmoji(controller, '👏');
      expect(clapBinding.totalFrames, equals(130));
      expect(clapBinding.frameActions.keys, containsAll([14, 33, 52, 71, 90, 109]));
      clapBinding.dispose();

      final peachBinding = EmojiHapticService.instance.attachInteractiveEmoji(controller, '🍑');
      expect(peachBinding.totalFrames, equals(120));
      expect(peachBinding.frameActions.keys, equals([31]));
      peachBinding.dispose();

      // The 4 remaining peach slaps live in the fullscreen effect binding.
      final peachEffect = EmojiHapticService.instance.attachEmojiEffect(controller, '1f351');
      expect(peachEffect.frameActions.keys, equals([50, 57, 102, 111]));
      peachEffect.dispose();

      final bombBinding = EmojiHapticService.instance.attachInteractiveEmoji(controller, '💣');
      expect(bombBinding.frameActions.keys, containsAll([0, 50, 75, 98]));
      bombBinding.dispose();

      final champagneBinding = EmojiHapticService.instance.attachInteractiveEmoji(controller, '🍾');
      expect(champagneBinding.frameActions.keys, containsAll([3, 18, 71, 91, 123]));
      champagneBinding.dispose();

      final cheersBinding = EmojiHapticService.instance.attachInteractiveEmoji(controller, '🥂');
      expect(cheersBinding.frameActions.keys, containsAll([68, 74, 158, 164]));
      expect(cheersBinding.frameActions.containsKey(8), isFalse);
      cheersBinding.dispose();

      final balloonBinding = EmojiHapticService.instance.attachInteractiveEmoji(controller, '🎈');
      expect(balloonBinding.frameActions.keys, containsAll([57, 65, 74, 82, 91, 97, 107, 116, 127, 144]));
      balloonBinding.dispose();

      final fireworkBinding = EmojiHapticService.instance.attachInteractiveEmoji(controller, '🎆');
      expect(fireworkBinding.frameActions.keys, containsAll([31, 36, 49, 54, 65, 76, 87, 125, 134]));
      fireworkBinding.dispose();

      controller.dispose();
    });

    test('attachDiceRoll and attachDiceOutcome register calibrated keyframes for sports, dice and slots', () {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(seconds: 3),
      );

      // Roll phase ground bounces
      final bballRoll = EmojiHapticService.instance.attachDiceRoll(controller, '🏀');
      expect(bballRoll.frameActions.keys, containsAll([0, 50, 100]));
      bballRoll.dispose();

      final soccerRoll = EmojiHapticService.instance.attachDiceRoll(controller, '⚽');
      expect(soccerRoll.frameActions.keys, containsAll([0, 60, 120]));
      soccerRoll.dispose();

      final diceRoll = EmojiHapticService.instance.attachDiceRoll(controller, '🎲');
      expect(diceRoll.frameActions.keys, containsAll([0, 60]));
      diceRoll.dispose();

      // Outcome phase
      final bballScore = EmojiHapticService.instance.attachDiceOutcome(controller, '🏀', 4);
      expect(bballScore.frameActions.keys, containsAll([0, 40, 100, 104, 111, 125, 133, 167]));
      bballScore.dispose();

      final bballClean = EmojiHapticService.instance.attachDiceOutcome(controller, '🏀', 5);
      expect(bballClean.frameActions.keys, containsAll([0, 40, 104, 117, 128]));
      bballClean.dispose();

      final bballRim = EmojiHapticService.instance.attachDiceOutcome(controller, '🏀', 2);
      expect(bballRim.frameActions.keys, containsAll([0, 40, 100, 104, 111, 125]));
      bballRim.dispose();

      // Football all 5 outcomes tested individually
      final soccerVal1 = EmojiHapticService.instance.attachDiceOutcome(controller, '⚽', 1);
      expect(soccerVal1.frameActions.keys, containsAll([2, 120, 142]));
      soccerVal1.dispose();

      final soccerVal2 = EmojiHapticService.instance.attachDiceOutcome(controller, '⚽', 2);
      expect(soccerVal2.frameActions.keys, containsAll([2, 90, 112, 144]));
      soccerVal2.dispose();

      final soccerVal3 = EmojiHapticService.instance.attachDiceOutcome(controller, '⚽', 3);
      expect(soccerVal3.frameActions.keys, containsAll([2, 96, 105, 112, 130]));
      soccerVal3.dispose();

      final soccerVal4 = EmojiHapticService.instance.attachDiceOutcome(controller, '⚽', 4);
      expect(soccerVal4.frameActions.keys, containsAll([2, 90, 98, 112, 126]));
      soccerVal4.dispose();

      final soccerVal5 = EmojiHapticService.instance.attachDiceOutcome(controller, '⚽', 5);
      expect(soccerVal5.frameActions.keys, containsAll([2, 92, 105, 120, 140]));
      soccerVal5.dispose();

      final bowlingStrike = EmojiHapticService.instance.attachDiceOutcome(controller, '🎳', 6);
      expect(bowlingStrike.frameActions.keys, containsAll([90, 94, 107]));
      bowlingStrike.dispose();

      final diceSix = EmojiHapticService.instance.attachDiceOutcome(controller, '🎲', 6);
      expect(diceSix.frameActions.keys, containsAll([0, 60, 100, 130, 150, 155]));
      diceSix.dispose();

      final slotMachine = EmojiHapticService.instance.attachSlotMachine(controller, 64);
      expect(slotMachine.frameActions.keys, containsAll([0, 32, 58, 84, 98]));
      slotMachine.dispose();

      controller.dispose();
    });

    test('EmojiHapticService uniform haptics mode toggles and notifies listeners', () async {
      SharedPreferences.setMockInitialValues({'emoji_haptic_uniform_tap': false});
      final haptic = EmojiHapticService.instance;
      await haptic.init();
      expect(haptic.isUniformHaptics, isFalse);

      bool notified = false;
      void listener() {
        notified = true;
      }

      haptic.addListener(listener);

      await haptic.setUniformHaptics(true);
      expect(haptic.isUniformHaptics, isTrue);
      expect(notified, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('emoji_haptic_uniform_tap'), isTrue);

      // Reset
      notified = false;
      await haptic.setUniformHaptics(false);
      expect(haptic.isUniformHaptics, isFalse);
      expect(notified, isTrue);
      expect(prefs.getBool('emoji_haptic_uniform_tap'), isFalse);

      haptic.removeListener(listener);
    });

    testWidgets('EmojiHapticService attaches and plays all 13 newly added expressive emojis', (tester) async {
      final controller = AnimationController(vsync: const TestVSync(), duration: const Duration(seconds: 3));
      final haptic = EmojiHapticService.instance;

      final testCases = <String, List<int>>{
        '🧨': [0, 73, 80, 85, 90, 96, 107],
        '1f9e8': [0, 73, 80, 85, 90, 96, 107],
        '🤯': [71, 84, 98, 113, 122, 137],
        '1f92f': [71, 84, 98, 113, 122, 137],
        '💥': [0, 10, 34, 104],
        '1f4a5': [0, 10, 34, 104],
        '👊': [97, 108],
        '1f44a': [97, 108],
        '🚀': [0, 50, 65, 80, 86, 118],
        '1f680': [0, 50, 65, 80, 86, 118],
        '💔': [0, 26, 36, 98, 108],
        '1f494': [0, 26, 36, 98, 108],
        '💯': [0, 50, 63, 80],
        '1f4af': [0, 50, 63, 80],
        '🥳': [0, 34, 100],
        '1f973': [0, 34, 100],
        '🪙': [0, 26, 112, 124],
        '1fa99': [0, 26, 112, 124],
        '👻': [0, 71, 91],
        '1f47b': [0, 71, 91],
        '😱': [0, 32, 42, 53, 82],
        '1f631': [0, 32, 42, 53, 82],
        '🎩': [0, 12, 86, 98],
        '1f3a9': [0, 12, 86, 98],
        '🗿': [0, 24, 78],
        '1f5ff': [0, 24, 78],
        '🆒': [0, 84, 102, 110],
        '1f192': [0, 84, 102, 110],
        '🆓': [0, 29, 60, 71],
        '1f193': [0, 29, 60, 71],
        '🆕': [5, 30, 46],
        '1f195': [5, 30, 46],
        '🆗': [8, 22, 35],
        '1f197': [8, 22, 35],
        '🆙': [22, 40, 46],
        '1f199': [22, 40, 46],
        '🌈': [12, 23, 49],
        '1f308': [12, 23, 49],
        '🌑': [0, 30, 60],
        '1f311': [0, 30, 60],
        '🌒': [30, 60, 84],
        '1f312': [30, 60, 84],
        '🌓': [30, 60],
        '1f313': [30, 60],
        '🌔': [30, 60, 79],
        '1f314': [30, 60, 79],
        '🌕': [15, 60, 90],
        '1f315': [15, 60, 90],
        '🌖': [30, 60],
        '1f316': [30, 60],
        '🌗': [30, 60],
        '1f317': [30, 60],
        '🌘': [30, 60],
        '1f318': [30, 60],
        '🌚': [20, 42, 53],
        '1f31a': [20, 42, 53],
        '🌛': [26, 41, 77],
        '1f31b': [26, 41, 77],
        '🌜': [23, 36, 44],
        '1f31c': [23, 36, 44],
        '🌝': [22, 38, 58],
        '1f31d': [22, 38, 58],
        '🌞': [11, 31, 58],
        '1f31e': [11, 31, 58],
        '🌟': [10, 40, 80, 110],
        '1f31f': [10, 40, 80, 110],
        '🌡': [18, 51, 60],
        '1f321': [18, 51, 60],
        '🌤': [35, 46, 70],
        '1f324': [35, 46, 70],
        '🌥': [35, 55, 82],
        '1f325': [35, 55, 82],
        '🌦': [13, 22, 48],
        '1f326': [13, 22, 48],
        '🌧': [13, 22, 48, 75],
        '1f327': [13, 22, 48, 75],
        '🌨': [24, 33, 60],
        '1f328': [24, 33, 60],
        '🌩': [24, 45, 52, 70],
        '1f329': [24, 45, 52, 70],
        '🌭': [23, 37, 65],
        '1f32d': [23, 37, 65],
        '🌮': [33, 40, 68],
        '1f32e': [33, 40, 68],
        '🌱': [10, 22, 34],
        '1f331': [10, 22, 34],
        '🌲': [26, 44, 68],
        '1f332': [26, 44, 68],
        '🌳': [30, 40, 75],
        '1f333': [30, 40, 75],
        '🌴': [22, 35, 60],
        '1f334': [22, 35, 60],
        '🌵': [18, 30, 55],
        '1f335': [18, 30, 55],
        '🌷': [17, 51, 69],
        '1f337': [17, 51, 69],
        '🌸': [25, 41, 72],
        '1f338': [25, 41, 72],
        '🌹': [20, 42, 75],
        '1f339': [20, 42, 75],
        '🌺': [16, 59, 89],
        '1f33a': [16, 59, 89],
        '🌼': [18, 48, 100],
        '1f33c': [18, 48, 100],
        '🌿': [21, 35, 47],
        '1f33f': [21, 35, 47],
        '🍀': [19, 55, 112, 125],
        '1f340': [19, 55, 112, 125],
        '🍌': [16, 50, 71, 100],
        '1f34c': [16, 50, 71, 100],
        '🍓': [38, 54, 90, 121],
        '1f353': [38, 54, 90, 121],
        '🍔': [23, 60, 74, 95, 132],
        '1f354': [23, 60, 74, 95, 132],
        '🍕': [27, 55, 80],
        '1f355': [27, 55, 80],
        '🍖': [25, 36, 103, 120],
        '1f356': [25, 36, 103, 120],
        '🍗': [20, 40, 113, 129],
        '1f357': [20, 40, 113, 129],
        '🍘': [34, 84, 135],
        '1f358': [34, 84, 135],
        '🍙': [17, 37, 82, 133],
        '1f359': [17, 37, 82, 133],
        '🍟': [29, 50, 65, 104, 120],
        '1f35f': [29, 50, 65, 104, 120],
        '🍡': [30, 98, 126, 156],
        '1f361': [30, 98, 126, 156],
        '🍢': [19, 81, 108, 126],
        '1f362': [19, 81, 108, 126],
        '🍣': [25, 42, 74, 128, 152],
        '1f363': [25, 42, 74, 128, 152],
        '🍥': [47, 98, 148, 169],
        '1f365': [47, 98, 148, 169],
        '🍦': [18, 33, 77, 127],
        '1f366': [18, 33, 77, 127],
        '🍩': [14, 27, 47, 83, 135],
        '1f369': [14, 27, 47, 83, 135],
        '🍪': [12, 38, 69, 90, 118],
        '1f36a': [12, 38, 69, 90, 118],
        '🍫': [11, 25, 40, 111],
        '1f36b': [11, 25, 40, 111],
        '🍭': [20, 48, 95, 119],
        '1f36d': [20, 48, 95, 119],
        '🍮': [25, 48, 71, 88],
        '1f36e': [25, 48, 71, 88],
        '🍰': [15, 45, 76, 148],
        '1f370': [15, 45, 76, 148],
        '🍱': [13, 42, 66, 100, 148],
        '1f371': [13, 42, 66, 100, 148],
        '🍳': [9, 64, 87, 104, 146],
        '1f373': [9, 64, 87, 104, 146],
        '🍷': [14, 45, 74, 88],
        '1f377': [14, 45, 74, 88],
        '🍸': [22, 37, 92, 120],
        '1f378': [22, 37, 92, 120],
        '🍹': [19, 44, 76, 132, 164],
        '1f379': [19, 44, 76, 132, 164],
        '🍼': [25, 49, 93, 132],
        '1f37c': [25, 49, 93, 132],
        '🍽️': [20, 46, 71, 98, 161],
        '1f37d': [20, 46, 71, 98, 161],
        '1f37d-fe0f': [20, 46, 71, 98, 161],
        '🍿': [26, 52, 71, 91, 113, 146],
        '1f37f': [26, 52, 71, 91, 113, 146],
        '🎂': [30, 45, 101, 126, 153],
        '1f382': [30, 45, 101, 126, 153],
        '🎃': [8, 38, 69, 101, 127, 155],
        '1f383': [8, 38, 69, 101, 127, 155],
        '🎄': [20, 46, 78, 93, 108],
        '1f384': [20, 46, 78, 93, 108],
        '🎅': [8, 41, 65, 96, 129],
        '1f385': [8, 41, 65, 96, 129],
        '🎓': [28, 41, 106, 119],
        '1f393': [28, 41, 106, 119],
        '🎖️': [34, 53, 87, 123, 152],
        '1f396': [34, 53, 87, 123, 152],
        '1f396-fe0f': [34, 53, 87, 123, 152],
        '🎗️': [17, 55, 74, 101],
        '1f397': [17, 55, 74, 101],
        '🎙️': [10, 45, 68, 95],
        '1f399': [10, 45, 68, 95],
        '1f399-fe0f': [10, 45, 68, 95],
        '🎟️': [10, 44, 51, 65, 117],
        '1f39f': [10, 44, 51, 65, 117],
        '1f39f-fe0f': [10, 44, 51, 65, 117],
        '🎢': [28, 45, 71, 98, 132],
        '1f3a2': [28, 45, 71, 98, 132],
        '🎤': [20, 40, 66, 86, 106, 126],
        '1f3a4': [20, 40, 66, 86, 106, 126],
        '🎨': [9, 35, 51, 63, 76, 97],
        '1f3a8': [9, 35, 51, 63, 76, 97],
        '🎫': [15, 55, 70, 85, 100, 125],
        '1f3ab': [15, 55, 70, 85, 100, 125],
        '🎬': [0, 21, 34, 83, 106],
        '1f3ac': [0, 21, 34, 83, 106],
        '🎭': [18, 42, 83, 114, 136, 158],
        '1f3ad': [18, 42, 83, 114, 136, 158],
        '🎮': [34, 62, 110, 131, 160],
        '1f3ae': [34, 62, 110, 131, 160],
        '🎵': [10, 36, 71, 114, 150],
        '1f3b5': [10, 36, 71, 114, 150],
        '🎶': [22, 44, 72, 99, 128, 160],
        '1f3b6': [22, 44, 72, 99, 128, 160],
        '🏀': [34, 64, 90, 109, 138, 154],
        '1f3c0': [34, 64, 90, 109, 138, 154],
        '🏁': [22, 45, 68, 98, 129, 157],
        '1f3c1': [22, 45, 68, 98, 129, 157],
        '🏅': [26, 39, 66, 95, 117, 150],
        '1f3c5': [26, 39, 66, 95, 117, 150],
        '🏆': [7, 22, 48, 78, 105, 142],
        '1f3c6': [7, 22, 48, 78, 105, 142],
        '🏕️': [23, 41, 62, 78, 100, 127],
        '🏕': [23, 41, 62, 78, 100, 127],
        '1f3d5': [23, 41, 62, 78, 100, 127],
        '1f3d5-fe0f': [23, 41, 62, 78, 100, 127],
        '🏖️': [20, 40, 57, 74, 95],
        '🏖': [20, 40, 57, 74, 95],
        '1f3d6': [20, 40, 57, 74, 95],
        '🏛️': [0, 35, 130, 144, 160, 172],
        '🏛': [0, 35, 130, 144, 160, 172],
        '1f3db': [0, 35, 130, 144, 160, 172],
        '1f3db-fe0f': [0, 35, 130, 144, 160, 172],
        '🏝️': [19, 40, 75, 89, 124, 150],
        '🏝': [19, 40, 75, 89, 124, 150],
        '1f3dd': [19, 40, 75, 89, 124, 150],
        '🏠': [30, 46, 60, 74, 99, 125],
        '1f3e0': [30, 46, 60, 74, 99, 125],
        '🏳️': [22, 45, 68, 98, 129, 157],
        '🏳': [22, 45, 68, 98, 129, 157],
        '1f3f3': [22, 45, 68, 98, 129, 157],
        '1f3f3-fe0f': [22, 45, 68, 98, 129, 157],
        '🏴‍☠️': [22, 45, 68, 98, 129, 157],
        '🏴‍☠': [22, 45, 68, 98, 129, 157],
        '1f3f4-200d-2620': [22, 45, 68, 98, 129, 157],
        '1f3f4-200d-2620-fe0f': [22, 45, 68, 98, 129, 157],
        '🏴': [22, 45, 68, 98, 129, 157],
        '1f3f4': [22, 45, 68, 98, 129, 157],
        '🏵️': [20, 37, 61, 76, 96, 137],
        '🏵': [20, 37, 61, 76, 96, 137],
        '1f3f5': [20, 37, 61, 76, 96, 137],
        '🐂': [30, 62, 78, 100, 136, 156],
        '1f402': [30, 62, 78, 100, 136, 156],
        '🐄': [22, 54, 74, 114, 146],
        '1f404': [22, 54, 74, 114, 146],
        '🐅': [37, 57, 97, 125, 141],
        '1f405': [37, 57, 97, 125, 141],
        '🐆': [27, 56, 93, 122, 145],
        '1f406': [27, 56, 93, 122, 145],
        '🐇': [23, 58, 94, 104, 127, 162],
        '1f407': [23, 58, 94, 104, 127, 162],
        '🐈‍⬛': [40, 51, 65, 96, 115],
        '1f408-200d-2b1b': [40, 51, 65, 96, 115],
        '🐈': [8, 29, 77, 103, 176],
        '1f408': [8, 29, 77, 103, 176],
        '🐌': [37, 48, 71, 90, 144],
        '1f40c': [37, 48, 71, 90, 144],
        '🐍': [21, 58, 87, 121, 161],
        '1f40d': [21, 58, 87, 121, 161],
        '🐎': [13, 25, 76, 98, 110, 155],
        '1f40e': [13, 25, 76, 98, 110, 155],
        '🐔': [3, 34, 89, 99, 119, 148],
        '1f414': [3, 34, 89, 99, 119, 148],
        '🐙': [10, 55, 88, 103, 142],
        '1f419': [10, 55, 88, 103, 142],
        '🐛': [5, 35, 65, 95, 125, 155],
        '1f41b': [5, 35, 65, 95, 125, 155],
        '🐜': [10, 34, 58, 82, 106, 130],
        '1f41c': [10, 34, 58, 82, 106, 130],
        '🐝': [22, 76, 90, 105, 120, 153],
        '1f41d': [22, 76, 90, 105, 120, 153],
        '🐞': [25, 52, 69, 136, 146],
        '1f41e': [25, 52, 69, 136, 146],
        '🐟': [17, 24, 46, 88, 97, 111],
        '1f41f': [17, 24, 46, 88, 97, 111],
        '🐠': [12, 52, 104, 118, 135],
        '1f420': [12, 52, 104, 118, 135],
        '🐢': [40, 53, 63, 78, 155],
        '1f422': [40, 53, 63, 78, 155],
        '🐣': [20, 43, 51, 84, 107, 117],
        '1f423': [20, 43, 51, 84, 107, 117],
        '🐤': [15, 53, 75, 88, 109, 134],
        '1f424': [15, 53, 75, 88, 109, 134],
        '🐥': [28, 61, 78, 110, 140, 171],
        '1f425': [28, 61, 78, 110, 140, 171],
        '🐦': [21, 45, 63, 77, 98, 117],
        '1f426': [21, 45, 63, 77, 98, 117],
        '🐧': [18, 34, 45, 69, 127, 150],
        '1f427': [18, 34, 45, 69, 127, 150],
        '🐨': [7, 36, 51, 76, 95, 120],
        '1f428': [7, 36, 51, 76, 95, 120],
        '🐭': [16, 36, 57, 82, 103, 135],
        '1f42d': [16, 36, 57, 82, 103, 135],
        '🐯': [23, 51, 85, 114, 130, 155],
        '1f42f': [23, 51, 85, 114, 130, 155],
        '🐰': [16, 39, 60, 83, 105, 135],
        '1f430': [16, 39, 60, 83, 105, 135],
        '🐱': [21, 55, 77, 101, 119, 149],
        '1f431': [21, 55, 77, 101, 119, 149],
        '🐳': [12, 28, 54, 83, 118, 145],
        '1f433': [12, 28, 54, 83, 118, 145],
        '🐴': [18, 36, 77, 96, 122, 153],
        '1f434': [18, 36, 77, 96, 122, 153],
        '🐵': [16, 29, 55, 81, 107],
        '1f435': [16, 29, 55, 81, 107],
        '🐶': [19, 42, 56, 78, 102, 133],
        '1f436': [19, 42, 56, 78, 102, 133],
        '🐷': [11, 26, 35, 67, 87, 116],
        '1f437': [11, 26, 35, 67, 87, 116],
        '🐸': [25, 69, 87, 106, 120, 156],
        '1f438': [25, 69, 87, 106, 120, 156],
        '🐹': [15, 29, 49, 70, 96, 120],
        '1f439': [15, 29, 49, 70, 96, 120],
        '🐻‍❄️': [20, 55, 95, 110, 126, 155],
        '🐻‍❄': [20, 55, 95, 110, 126, 155],
        '1f43b-200d-2744': [20, 55, 95, 110, 126, 155],
        '1f43b-200d-2744-fe0f': [20, 55, 95, 110, 126, 155],
        '🐻': [28, 55, 75, 114, 141, 165],
        '1f43b': [28, 55, 75, 114, 141, 165],
        '🐼': [19, 38, 65, 88, 117, 145],
        '1f43c': [19, 38, 65, 88, 117, 145],
        '🐽': [10, 20, 40, 60, 95, 126],
        '1f43d': [10, 20, 40, 60, 95, 126],
        '🐾': [41, 68, 85, 107, 125, 160],
        '1f43e': [41, 68, 85, 107, 125, 160],
        '👀': [19, 32, 51, 79, 106, 129],
        '1f440': [19, 32, 51, 79, 106, 129],
        '👁️': [11, 18, 67, 81, 129, 155],
        '👁': [11, 18, 67, 81, 129, 155],
        '1f441': [11, 18, 67, 81, 129, 155],
        '1f441-fe0f': [11, 18, 67, 81, 129, 155],
        '👂': [11, 25, 69, 81, 99, 150],
        '1f442': [11, 25, 69, 81, 99, 150],
        '👃': [13, 40, 56, 112, 126, 143],
        '1f443': [13, 40, 56, 112, 126, 143],
        '👅': [22, 42, 64, 92, 124],
        '1f445': [22, 42, 64, 92, 124],
        '👆': [16, 42, 70, 95],
        '1f446': [16, 42, 70, 95],
        '👇': [18, 32, 49, 80],
        '1f447': [18, 32, 49, 80],
        '👈': [38, 72, 95, 113, 131],
        '1f448': [38, 72, 95, 113, 131],
        '👉': [19, 41, 59, 77, 111],
        '1f449': [19, 41, 59, 77, 111],
        '👋': [15, 26, 37, 48, 59, 70, 81, 92],
        '1f44b': [15, 26, 37, 48, 59, 70, 81, 92],
        '👌': [11, 19, 28, 42],
        '1f44c': [11, 19, 28, 42],
        '👐': [29, 36, 54, 79, 103],
        '1f450': [29, 36, 54, 79, 103],
        '👑': [10, 27, 55, 62, 88, 112],
        '1f451': [10, 27, 55, 62, 88, 112],
        '👛': [7, 20, 57, 73, 89, 128],
        '1f45b': [7, 20, 57, 73, 89, 128],
        '👜': [16, 55, 81, 104, 135, 155],
        '1f45c': [16, 55, 81, 104, 135, 155],
        '👠': [10, 36, 84, 113, 134, 157],
        '1f460': [10, 36, 84, 113, 134, 157],
        '👣': [30, 58, 86, 114, 143],
        '1f463': [30, 58, 86, 114, 143],
        '👤': [37, 52, 66, 84, 126],
        '1f464': [37, 52, 66, 84, 126],
        '👥': [34, 60, 77, 102, 146],
        '1f465': [34, 60, 77, 102, 146],
        '👨‍🏫': [10, 70, 90, 105, 140],
        '1f468-200d-1f3eb': [10, 70, 90, 105, 140],
        '👨‍👩‍👧‍👦': [19, 39, 60, 95, 131],
        '1f468-200d-1f469-200d-1f467-200d-1f466': [19, 39, 60, 95, 131],
        '👨‍💻': [12, 26, 39, 60, 107, 135],
        '1f468-200d-1f4bb': [12, 26, 39, 60, 107, 135],
        '👨‍⚕️': [12, 31, 53, 94, 134],
        '👨‍⚕': [12, 31, 53, 94, 134],
        '1f468-200d-2695-fe0f': [12, 31, 53, 94, 134],
        '1f468-200d-2695': [12, 31, 53, 94, 134],
        '👩‍💻': [12, 26, 39, 60, 107, 135],
        '1f469-200d-1f4bb': [12, 26, 39, 60, 107, 135],
        '👩‍⚕️': [12, 31, 53, 94, 134],
        '👩‍⚕': [12, 31, 53, 94, 134],
        '1f469-200d-2695-fe0f': [12, 31, 53, 94, 134],
        '1f469-200d-2695': [12, 31, 53, 94, 134],
        '👮‍♀️': [14, 38, 52, 67, 83, 105],
        '👮‍♀': [14, 38, 52, 67, 83, 105],
        '1f46e-200d-2640-fe0f': [14, 38, 52, 67, 83, 105],
        '1f46e-200d-2640': [14, 38, 52, 67, 83, 105],
        '👮‍♂️': [14, 38, 52, 67, 83, 105],
        '👮‍♂': [14, 38, 52, 67, 83, 105],
        '1f46e-200d-2642-fe0f': [14, 38, 52, 67, 83, 105],
        '1f46e-200d-2642': [14, 38, 52, 67, 83, 105],
        '👵': [12, 30, 56, 82, 109, 130],
        '1f475': [12, 30, 56, 82, 109, 130],
        '👶': [12, 53, 74, 88, 102, 123],
        '1f476': [12, 53, 74, 88, 102, 123],
        '👹': [10, 35, 49, 65, 82, 110],
        '1f479': [10, 35, 49, 65, 82, 110],
        '👺': [14, 36, 55, 97, 122],
        '1f47a': [14, 36, 55, 97, 122],
        '👽': [17, 32, 49, 76, 101, 136],
        '1f47d': [17, 32, 49, 76, 101, 136],
        '👾': [12, 28, 60, 92, 147],
        '1f47e': [12, 28, 60, 92, 147],
        '👿': [7, 20, 42, 71, 94, 141],
        '1f47f': [7, 20, 42, 71, 94, 141],
        '💀': [20, 55, 69, 83, 97, 111],
        '1f480': [20, 55, 69, 83, 97, 111],
        '💃': [12, 27, 46, 63, 96, 114, 141],
        '1f483': [12, 27, 46, 63, 96, 114, 141],
        '💄': [28, 36, 55, 72, 87, 113, 135],
        '1f484': [28, 36, 55, 72, 87, 113, 135],
        '💅': [14, 26, 51, 75, 99, 121, 146],
        '1f485': [14, 26, 51, 75, 99, 121, 146],
        '💉': [16, 40, 65, 85, 105, 139],
        '1f489': [16, 40, 65, 85, 105, 139],
        '💊': [20, 29, 48, 72, 115, 142],
        '1f48a': [20, 29, 48, 72, 115, 142],
        '💌': [60, 76, 94, 109, 127, 137, 163, 173],
        '1f48c': [60, 76, 94, 109, 127, 137, 163, 173],
        '💎': [12, 35, 60, 90, 120, 150],
        '1f48e': [12, 35, 60, 90, 120, 150],
        '💐': [14, 38, 57, 93, 128, 156],
        '1f490': [14, 38, 57, 93, 128, 156],
        '💓': [5, 21, 56, 72, 89, 102],
        '1f493': [5, 21, 56, 72, 89, 102],
        '💕': [15, 25, 58, 70, 96, 110],
        '1f495': [15, 25, 58, 70, 96, 110],
        '💖': [20, 35, 75, 88, 120, 135],
        '1f496': [20, 35, 75, 88, 120, 135],
        '💗': [28, 43, 74, 92, 120, 137],
        '1f497': [28, 43, 74, 92, 120, 137],
        '💘': [5, 15, 42, 54, 78, 95],
        '1f498': [5, 15, 42, 54, 78, 95],
        '💝': [30, 45, 60, 75, 134, 151],
        '1f49d': [30, 45, 60, 75, 134, 151],
        '💞': [14, 34, 69, 84, 122, 139],
        '1f49e': [14, 34, 69, 84, 122, 139],
        '💟': [18, 30, 45, 55, 80, 95],
        '1f49f': [18, 30, 45, 55, 80, 95],
        '💡': [22, 50, 60, 83, 115, 150],
        '1f4a1': [22, 50, 60, 83, 115, 150],
        '💢': [19, 30, 44, 73, 109, 120, 134, 163],
        '1f4a2': [19, 30, 44, 73, 109, 120, 134, 163],
        '💤': [15, 25, 42, 62, 100, 118, 135],
        '1f4a4': [15, 25, 42, 62, 100, 118, 135],
        '💪': [20, 45, 62, 93, 111, 128, 150],
        '1f4aa': [20, 45, 62, 93, 111, 128, 150],
        '💫': [22, 36, 57, 70, 90, 117, 157],
        '1f4ab': [22, 36, 57, 70, 90, 117, 157],
        '💬': [10, 27, 36, 47, 81, 114, 150],
        '1f4ac': [10, 27, 36, 47, 81, 114, 150],
        '💭': [9, 24, 39, 60, 84, 113, 138],
        '1f4ad': [9, 24, 39, 60, 84, 113, 138],
        '💰': [22, 41, 71, 119, 124, 142],
        '1f4b0': [22, 41, 71, 119, 124, 142],
        '💱': [0, 35, 70, 90, 125, 160],
        '1f4b1': [0, 35, 70, 90, 125, 160],
        '💸': [5, 45, 81, 107, 145, 175],
        '1f4b8': [5, 45, 81, 107, 145, 175],
        '💻': [0, 42, 59, 76, 99, 138, 167],
        '1f4bb': [0, 42, 59, 76, 99, 138, 167],
        '💼': [19, 64, 89, 116, 135, 144],
        '1f4bc': [19, 64, 89, 116, 135, 144],
        '📁': [20, 26, 54, 68, 80, 119],
        '1f4c1': [20, 26, 54, 68, 80, 119],
        '📂': [0, 30, 60, 76, 120, 179],
        '1f4c2': [0, 30, 60, 76, 120, 179],
        '📅': [16, 41, 66, 108, 136, 155, 170],
        '1f4c6': [16, 41, 66, 108, 136, 155, 170],
        '📈': [10, 50, 90, 145, 180],
        '1f4c8': [10, 50, 90, 145, 180],
        '📉': [10, 50, 90, 145, 180],
        '1f4c9': [10, 50, 90, 145, 180],
        '📊': [6, 30, 66, 90, 126, 150],
        '1f4ca': [6, 30, 66, 90, 126, 150],
        '📖': [25, 48, 62, 71, 80, 104, 127],
        '1f4d6': [25, 48, 62, 71, 80, 104, 127],
        '📚': [45, 55, 104, 144, 175],
        '1f4da': [45, 55, 104, 144, 175],
        '📝': [15, 30, 49, 64, 84, 104, 128],
        '1f4dd': [15, 30, 49, 64, 84, 104, 128],
        '📞': [8, 24, 43, 75, 87, 122],
        '1f4de': [8, 24, 43, 75, 87, 122],
        '📣': [18, 26, 46, 58, 86, 106, 141],
        '1f4e3': [18, 26, 46, 58, 86, 106, 141],
        '📤': [16, 38, 60, 73, 124],
        '1f4e4': [16, 38, 60, 73, 124],
        '📥': [10, 27, 38, 77, 102, 133],
        '1f4e5': [10, 27, 38, 77, 102, 133],
        '📨': [9, 17, 47, 65, 80, 126],
        '1f4e8': [9, 17, 47, 65, 80, 126],
        '📫': [20, 23, 30, 39, 130, 150],
        '1f4ec': [20, 23, 30, 39, 130, 150],
        '📪': [13, 29, 35, 116, 140],
        '1f4ed': [13, 29, 35, 116, 140],
        '📰': [22, 39, 59, 83, 126, 148],
        '1f4f0': [22, 39, 59, 83, 126, 148],
        '📱': [15, 30, 48, 71, 78, 98],
        '1f4f1': [15, 30, 48, 71, 78, 98],
        '📲': [21, 38, 52, 90, 115, 142, 158],
        '1f4f2': [21, 38, 52, 90, 115, 142, 158],
        '📺': [13, 32, 88, 113, 148, 155],
        '1f4fa': [13, 32, 88, 113, 148, 155],
        '🔍': [20, 42, 69, 102, 124, 152],
        '1f50d': [20, 42, 69, 102, 124, 152],
        '🔎': [20, 48, 92, 131, 150, 179],
        '1f50e': [20, 48, 92, 131, 150, 179],
        '🔐': [40, 60, 66, 78, 114, 130, 167],
        '1f510': [40, 60, 66, 78, 114, 130, 167],
        '🔑': [12, 37, 56, 73, 104, 123, 156],
        '1f511': [12, 37, 56, 73, 104, 123, 156],
        '🔝': [22, 32, 61, 76, 99],
        '1f51d': [22, 32, 61, 76, 99],
        '🔞': [40, 61, 91, 124, 144],
        '1f51e': [40, 61, 91, 124, 144],
      };

      for (final entry in testCases.entries) {
        final binding = haptic.attachInteractiveEmoji(controller, entry.key, totalFrames: 180);
        expect(binding.frameActions.keys, containsAll(entry.value), reason: 'Failed for ${entry.key}');
        binding.dispose();

        expect(() => haptic.playInteractiveEmojiHaptic(entry.key), returnsNormally);
        haptic.cancelAll();
      }

      controller.dispose();
    });

    test('attachEmojiEffect keyframes match existing effect files and stay within their duration', () {
      final controller = AnimationController(vsync: const TestVSync(), duration: const Duration(seconds: 3));
      final haptic = EmojiHapticService.instance;
      const effectCodepoints = [
        '1f192', '1f31a', '1f32d', '1f346', '1f34c', '1f351', '1f353', '1f37e',
        '1f382', '1f383', '1f384', '1f385', '1f389', '1f38a', '1f44d', '1f44e',
        '1f47b', '1f48b', '1f494', '1f4a5', '1f4a9', '1f4af', '1f525',
        '1f5ff', '1f631', '1f92e', '1f92f', '1f973', '26a1',
        '1f3c6', '1f3f4-200d-2620', '1f433', '1f43e', '1f440',
        '1f445', '1f44b', '1f44c', '1f451', '1f468-200d-1f4bb', '1f46e-200d-2642',
        '1f47e', '1f483', '1f485', '1f48a', '1f48e', '1f490', '1f498', '1f4b8', '1f51d', '1f51e',
      ];

      for (final cp in effectCodepoints) {
        final keyframes = EmojiHapticService.effectKeyframesFor(cp);
        expect(keyframes, isNotNull, reason: 'No effect haptics for $cp');

        final file = File('../backend/assets/emoji_effects/$cp.json');
        if (file.existsSync()) {
          final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          final total = ((json['op'] as num) - (json['ip'] as num)).round();
          for (final (frame, _) in keyframes!) {
            expect(frame, inInclusiveRange(0, total), reason: 'Frame $frame out of range for $cp');
          }
        }

        final binding = haptic.attachEmojiEffect(controller, cp);
        expect(binding.frameActions.keys, equals(keyframes!.map((k) => k.$1)));
        binding.dispose();
      }

      // 👏 and hearts keep only the emoji's own haptics (no effect pulses).
      for (final cp in ['1f44f', '2764', '2764-fe0f', '1f90d', '1f90e']) {
        expect(EmojiHapticService.effectKeyframesFor(cp), isNull, reason: '$cp must not vibrate on effect');
        final b = haptic.attachEmojiEffect(controller, cp);
        expect(b.frameActions, isEmpty);
        b.dispose();
      }
      expect(EmojiHapticService.effectKeyframesFor('26a1-fe0f'), isNotNull);
      final empty = haptic.attachEmojiEffect(controller, '1f600');
      expect(empty.frameActions, isEmpty);
      empty.dispose();

      controller.dispose();
    });
  });
}
