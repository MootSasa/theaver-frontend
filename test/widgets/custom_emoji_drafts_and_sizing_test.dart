import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/models/chat_draft.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/sticker_service.dart';
import 'package:theaver/utils/emoji_utils.dart';
import 'package:theaver/utils/entity_parser.dart';
import 'package:theaver/widgets/chat/rich_text_editing_controller.dart';

void main() {
  group('RichTextEditingController custom emoji parser & cursor alignment', () {
    test('insertCustomEmoji uses 1-code-unit placeholder and expands in cleanText & entities', () {
      final controller = RichTextEditingController();
      const item1 = StickerItem(
        id: 101,
        packId: 1,
        fileUrl: '/uploads/stickers/101.tgs',
        format: 'tgs',
        emojiList: ['🔥'],
      );
      const item2 = StickerItem(
        id: 102,
        packId: 1,
        fileUrl: '/uploads/stickers/102.webp',
        format: 'webp',
        emojiList: ['😂'],
      );

      controller.insertCustomEmoji(item1);
      // Internal text has 1 UTF-16 code unit matching 1 WidgetSpan
      expect(controller.text.length, 1);
      expect(controller.selection.baseOffset, 1);
      // Expanded payload has 2-code-unit surrogate pair for '🔥'
      expect(controller.cleanText, '🔥');
      expect(controller.entities.length, 1);
      expect(controller.entities.first.type, 'custom_emoji');
      expect(controller.entities.first.customEmojiId, '101');
      expect(controller.entities.first.offset, 0);
      expect(controller.entities.first.length, 2);

      // Insert second custom emoji right after first
      controller.insertCustomEmoji(item2);
      expect(controller.text.length, 2);
      expect(controller.selection.baseOffset, 2);
      expect(controller.cleanText, '🔥😂');
      expect(controller.entities.length, 2);
      expect(controller.entities[0].offset, 0);
      expect(controller.entities[0].length, 2);
      expect(controller.entities[1].offset, 2);
      expect(controller.entities[1].length, 2);
      expect(controller.entities[1].customEmojiId, '102');

      // Type text between the two custom emojis (at internal index 1)
      final current = controller.text;
      final updated = '${current.substring(0, 1)} hi ${current.substring(1)}';
      controller.value = TextEditingValue(
        text: updated,
        selection: const TextSelection.collapsed(offset: 5),
      );

      expect(controller.cleanText, '🔥 hi 😂');
      expect(controller.entities.length, 2);
      expect(controller.entities[0].offset, 0);
      expect(controller.entities[0].length, 2);
      expect(controller.entities[1].offset, 6); // '🔥' (2) + ' hi ' (4) = 6
      expect(controller.entities[1].length, 2);
    });

    test('loadMessage round-trips custom emojis and formatting spans accurately', () {
      final controller = RichTextEditingController();
      const rawText = 'Hello 🔥 world 😂!';
      final entities = <MessageEntity>[
        const MessageEntity(type: 'bold', offset: 0, length: 5),
        const MessageEntity(
          type: 'custom_emoji',
          offset: 6,
          length: 2,
          customEmojiId: '501',
          documentUrl: '/uploads/stickers/501.tgs',
          format: 'tgs',
        ),
        const MessageEntity(
          type: 'custom_emoji',
          offset: 15,
          length: 2,
          customEmojiId: '502',
          documentUrl: '/uploads/stickers/502.webp',
          format: 'webp',
        ),
      ];

      controller.loadMessage(rawText, entities);
      // Internal text has 1-unit placeholders instead of 2-unit surrogate pairs
      expect(controller.text.length, rawText.length - 2);
      expect(controller.cleanText, rawText);

      final roundTrip = controller.entities;
      expect(roundTrip.length, 3);
      final boldEnt = roundTrip.firstWhere((e) => e.type == 'bold');
      expect(boldEnt.offset, 0);
      expect(boldEnt.length, 5);

      final ceEntities = roundTrip.where((e) => e.type == 'custom_emoji').toList();
      expect(ceEntities.length, 2);
      expect(ceEntities[0].customEmojiId, '501');
      expect(ceEntities[0].offset, 6);
      expect(ceEntities[0].length, 2);
      expect(ceEntities[1].customEmojiId, '502');
      expect(ceEntities[1].offset, 15);
      expect(ceEntities[1].length, 2);
    });
  });

  group('ChatDraft custom emoji entities persistence', () {
    test('serializes and deserializes entities in ChatDraft', () {
      final draft = ChatDraft(
        text: '👍 test',
        entities: const [
          MessageEntity(
            type: 'custom_emoji',
            offset: 0,
            length: 2,
            customEmojiId: '777',
            documentUrl: '/uploads/stickers/777.tgs',
            format: 'tgs',
          ),
        ],
        updatedAt: DateTime.utc(2026, 11, 9),
      );

      final json = draft.toJson();
      final restored = ChatDraft.fromJson(json);
      expect(restored.text, '👍 test');
      expect(restored.entities.length, 1);
      expect(restored.entities.first.customEmojiId, '777');
      expect(restored.entities.first.documentUrl, '/uploads/stickers/777.tgs');
      expect(restored.entities.first.format, 'tgs');
    });
  });

  group('EmojiUtils 7-tier sizing and frameless emoji-only detection', () {
    test('emojiTierSize returns 7 distinct size tiers for counts 1 to 7+', () {
      final sizes = [
        EmojiUtils.emojiTierSize(1),
        EmojiUtils.emojiTierSize(2),
        EmojiUtils.emojiTierSize(3),
        EmojiUtils.emojiTierSize(4),
        EmojiUtils.emojiTierSize(5),
        EmojiUtils.emojiTierSize(6),
        EmojiUtils.emojiTierSize(7),
      ];
      expect(sizes.toSet().length, 7);
      for (int i = 0; i < sizes.length - 1; i++) {
        expect(sizes[i], greaterThan(sizes[i + 1]));
      }
      expect(EmojiUtils.emojiTierSize(8), EmojiUtils.emojiTierSize(7));
      expect(EmojiUtils.emojiTierSize(25), EmojiUtils.emojiTierSize(7));
    });

    test('countTotalEmojiOnly counts Unicode, custom, and mixed emoji-only messages of any length', () {
      expect(EmojiUtils.countTotalEmojiOnly('😀', const []), 1);
      expect(EmojiUtils.countTotalEmojiOnly('😀😂🔥👍🎉❤️✨🚀', const []), 8);

      const customOnly = [
        MessageEntity(type: 'custom_emoji', offset: 0, length: 2, customEmojiId: '1'),
        MessageEntity(type: 'custom_emoji', offset: 2, length: 2, customEmojiId: '2'),
        MessageEntity(type: 'custom_emoji', offset: 4, length: 2, customEmojiId: '3'),
        MessageEntity(type: 'custom_emoji', offset: 6, length: 2, customEmojiId: '4'),
      ];
      expect(EmojiUtils.countTotalEmojiOnly('😀😂🔥👍', customOnly), 4);

      const mixed = [
        MessageEntity(type: 'custom_emoji', offset: 0, length: 2, customEmojiId: '1'),
      ];
      expect(EmojiUtils.countTotalEmojiOnly('😀 😂 🔥', mixed), 3);
      expect(EmojiUtils.countTotalEmojiOnly('😀 hello', mixed), 0);
    });
  });

  group('Custom emoji URL suppression & link preview isolation', () {
    test('EntityParser.isInternalStorageUrl recognizes internal storage and rejects it for previews', () {
      expect(EntityParser.isInternalStorageUrl('https://storage.theaver.app/stickers/101.webp'), isTrue);
      expect(EntityParser.isInternalStorageUrl('https://storage.theaver.app/avatars/avatar_12.jpg'), isTrue);
      expect(EntityParser.isInternalStorageUrl('http://storage.theaver.app/test'), isTrue);
      expect(EntityParser.isInternalStorageUrl('http://127.0.0.1:9000/bucket/item'), isTrue);
      expect(EntityParser.isInternalStorageUrl('http://localhost:9000/media'), isTrue);

      // External web links should NOT be internal storage URLs
      expect(EntityParser.isInternalStorageUrl('https://github.com/flutter/flutter'), isFalse);
      expect(EntityParser.isInternalStorageUrl('https://google.com'), isFalse);
      expect(EntityParser.isInternalStorageUrl('https://example.com/image.png'), isFalse);
    });

    test('insertCustomEmoji sets documentUrl and keeps url null so link preview is not triggered', () {
      final controller = RichTextEditingController();
      const item = StickerItem(
        id: 777,
        packId: 10,
        fileUrl: 'https://storage.theaver.app/stickers/777.webp',
        format: 'webp',
        emojiList: ['🚀'],
      );

      controller.insertCustomEmoji(item);

      // RichSpan for custom emoji must have null url
      expect(controller.spans.length, 1);
      final span = controller.spans.first;
      expect(span.type, 'custom_emoji');
      expect(span.url, isNull);
      expect(span.documentUrl, 'https://storage.theaver.app/stickers/777.webp');

      // Generated MessageEntity must also have null url
      final entities = controller.entities;
      expect(entities.length, 1);
      final entity = entities.first;
      expect(entity.type, 'custom_emoji');
      expect(entity.url, isNull);
      expect(entity.documentUrl, 'https://storage.theaver.app/stickers/777.webp');
    });

    test('loadMessage with custom emoji entity ensures span.url remains null', () {
      final controller = RichTextEditingController();
      const rawText = 'Check this 🚀 out!';
      final entities = <MessageEntity>[
        const MessageEntity(
          type: 'custom_emoji',
          offset: 11,
          length: 2,
          customEmojiId: '888',
          documentUrl: 'https://storage.theaver.app/stickers/888.webp',
          format: 'webp',
        ),
      ];

      controller.loadMessage(rawText, entities);

      final customSpans = controller.spans.where((s) => s.type == 'custom_emoji').toList();
      expect(customSpans.length, 1);
      expect(customSpans.first.url, isNull);
      expect(customSpans.first.documentUrl, 'https://storage.theaver.app/stickers/888.webp');
    });
  });
}
