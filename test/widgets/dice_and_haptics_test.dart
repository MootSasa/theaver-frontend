import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });
}
