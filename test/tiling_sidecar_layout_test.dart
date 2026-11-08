import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/services/sticker_service.dart';
import 'package:theaver/services/tiling_layout_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TilingLayoutController Emoji/Sticker Sidecar', () {
    test('canDockEmojiSidecar respects 960px single/vertical and 1280px horizontal thresholds', () {
      final ctrl = TilingLayoutController.instance;
      ctrl.closeAllChats();
      ctrl.closeEmojiSidecar();
      ctrl.updateWindowMetrics(const Size(1360, 800));

      // Open 1 chat tile
      ctrl.openChatInActiveTile(
        chatId: 'chat_1',
        chatType: 'private',
        title: 'Alice',
      );
      expect(ctrl.chatTiles.length, 1);
      expect(ctrl.canDockEmojiSidecar(960), isTrue);
      expect(ctrl.canDockEmojiSidecar(900), isFalse);

      // Open 2nd chat tile in horizontal split (side-by-side)
      ctrl.openChatInAdjacentTile(
        chatId: 'chat_2',
        chatType: 'private',
        title: 'Bob',
        splitAxis: Axis.horizontal,
      );
      expect(ctrl.chatTiles.length, 2);
      expect(ctrl.effectiveSplitAxis, Axis.horizontal);
      // In horizontal split of 2 chats, docking requires >= 1280px; < 1280px uses Flyout over inactive tile
      expect(ctrl.canDockEmojiSidecar(1280), isTrue);
      expect(ctrl.canDockEmojiSidecar(1100), isFalse);

      // Switch to vertical split (top/bottom)
      ctrl.openChatInAdjacentTile(
        chatId: 'chat_2',
        chatType: 'private',
        title: 'Bob',
        splitAxis: Axis.vertical,
      );
      expect(ctrl.effectiveSplitAxis, Axis.vertical);
      expect(ctrl.canDockEmojiSidecar(960), isTrue);
      expect(ctrl.canDockEmojiSidecar(850), isFalse);
    });

    test('openEmojiSidecar, toggleEmojiSidecar, and handleBackAction priority', () async {
      final ctrl = TilingLayoutController.instance;
      ctrl.closeAllChats();
      ctrl.closeEmojiSidecar();

      ctrl.openChatInActiveTile(
        chatId: 'chat_1',
        chatType: 'private',
        title: 'Alice',
      );
      expect(ctrl.isEmojiSidecarOpen, isFalse);

      ctrl.toggleEmojiSidecar();
      expect(ctrl.isEmojiSidecarOpen, isTrue);

      ctrl.updateSidecarWidth(-40);
      expect(ctrl.sidecarWidth, 380);

      // handleBackAction must close the Emoji/Sticker sidecar first without closing the chat tile
      final handled = await ctrl.handleBackAction();
      expect(handled, isTrue);
      expect(ctrl.isEmojiSidecarOpen, isFalse);
      expect(ctrl.chatTiles.length, 1);
    });
  });

  group('StickerItem & StickerPack Semantic Search and Premium Effects', () {
    test('StickerItem.matchesLocalQuery matches RU/EN visual descriptions, OCR, tags, and emojis', () {
      final item = StickerItem.fromJson({
        'id': 42,
        'pack_id': 7,
        'pack_short_name': 'cyber_cats',
        'pack_title': 'Кибер Котики',
        'file_url': '/api/stickers/media/7/42.tgs',
        'emoji_list': ['🐱', '🔥'],
        'effect_animation_url': '/api/stickers/media/7/42_effect.tgs',
        'format': 'tgs',
        'ocr_text': 'ПОГНАЛИ GO',
        'visual_description_ru': 'рыжий кот в очках смеется огонь',
        'visual_description_en': 'orange cat with glasses laughing fire',
        'tags': ['кот', 'cat', 'огонь', 'смех'],
      });

      expect(item.hasPremiumEffect, isTrue);
      expect(item.hasFullscreenEffect, isTrue);
      expect(item.isVector, isTrue);

      // Matches Russian visual description (even when user doesn't know the underlying emoji)
      expect(item.matchesLocalQuery('рыжий кот'), isTrue);
      expect(item.matchesLocalQuery('очках'), isTrue);
      // Matches English visual description
      expect(item.matchesLocalQuery('laughing'), isTrue);
      // Matches OCR text on sticker
      expect(item.matchesLocalQuery('погнали'), isTrue);
      // Matches emoji
      expect(item.matchesLocalQuery('🔥'), isTrue);
      // Non-matching query
      expect(item.matchesLocalQuery('динозавр'), isFalse);
    });
  });
}
