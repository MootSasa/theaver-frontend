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

      final clapBinding = EmojiHapticService.instance.attachInteractiveEmoji(controller, '👏');
      expect(clapBinding.totalFrames, equals(130));
      expect(clapBinding.frameActions.keys, containsAll([14, 33, 52, 71, 90, 109]));
      clapBinding.dispose();

      final peachBinding = EmojiHapticService.instance.attachInteractiveEmoji(controller, '🍑');
      expect(peachBinding.totalFrames, equals(120));
      expect(peachBinding.frameActions.keys, containsAll([30, 35, 45, 54]));
      peachBinding.dispose();

      final bombBinding = EmojiHapticService.instance.attachInteractiveEmoji(controller, '💣');
      expect(bombBinding.frameActions.keys, containsAll([0, 50, 75, 98]));
      bombBinding.dispose();

      final champagneBinding = EmojiHapticService.instance.attachInteractiveEmoji(controller, '🍾');
      expect(champagneBinding.frameActions.keys, containsAll([3, 18, 71, 91, 123]));
      champagneBinding.dispose();

      final cheersBinding = EmojiHapticService.instance.attachInteractiveEmoji(controller, '🥂');
      expect(cheersBinding.frameActions.keys, containsAll([8, 20, 68, 82]));
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
      expect(bballRoll.frameActions.keys, containsAll([0, 50]));
      bballRoll.dispose();

      final soccerRoll = EmojiHapticService.instance.attachDiceRoll(controller, '⚽');
      expect(soccerRoll.frameActions.keys, containsAll([0, 60]));
      soccerRoll.dispose();

      final diceRoll = EmojiHapticService.instance.attachDiceRoll(controller, '🎲');
      expect(diceRoll.frameActions.keys, containsAll([0, 60]));
      diceRoll.dispose();

      // Outcome phase
      final bballScore = EmojiHapticService.instance.attachDiceOutcome(controller, '🏀', 4);
      expect(bballScore.frameActions.keys, containsAll([40, 75, 119, 131, 156]));
      bballScore.dispose();

      final bballRim = EmojiHapticService.instance.attachDiceOutcome(controller, '🏀', 2);
      expect(bballRim.frameActions.keys, containsAll([40, 75, 102, 120, 132, 156]));
      bballRim.dispose();

      final soccerGoal = EmojiHapticService.instance.attachDiceOutcome(controller, '⚽', 4);
      expect(soccerGoal.frameActions.keys, containsAll([2, 44, 53, 112, 138]));
      soccerGoal.dispose();

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
  });
}
