import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/services/dice_cache_service.dart';
import 'package:theaver/services/emoji_haptic_service.dart';
import 'package:theaver/utils/emoji_utils.dart';

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

      // 🎰 Slot Machine special jackpots & outcomes
      expect(DiceCacheService.getOutcomeIndex('🎰', 64), equals(21)); // 777 Jackpot
      expect(DiceCacheService.getOutcomeIndex('🎰', 1), equals(2));   // BAR
      expect(DiceCacheService.getOutcomeIndex('🎰', 22), equals(7));  // Berries
      expect(DiceCacheService.getOutcomeIndex('🎰', 43), equals(13)); // Lemons
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
      haptic.cancelAll();
    });
  });
}
