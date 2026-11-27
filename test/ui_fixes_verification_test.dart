import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/models/profile_customization.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/utils/emoji_utils.dart';
import 'package:theaver/widgets/chat/chat_selection_header.dart';
import 'package:theaver/widgets/chat/emoji_sticker_panel.dart';
import 'package:theaver/widgets/chat/sticker_item_widget.dart';
import 'package:theaver/widgets/user/emoji_status_badge.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Fix 1: EmojiStatusBadge color rendering & EmojiStickerPanel emojiOnly', () {
    testWidgets(
      'EmojiStatusBadge uses AppleEmoji color font for Unicode and does not white-tint custom sticker emojis',
      (tester) async {
        const unicodeStatus = EmojiStatusData(
          type: 'unicode',
          emoji: '🔥',
        );
        const stickerStatus = EmojiStatusData(
          type: 'sticker',
          stickerId: 777,
          stickerUrl: '/uploads/stickers/fire_color.webp',
          stickerFormat: 'webp',
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  EmojiStatusBadge(
                    status: unicodeStatus,
                    size: 20,
                    fallbackColor: Colors.white,
                  ),
                  EmojiStatusBadge(
                    status: stickerStatus,
                    size: 20,
                    animate: false,
                    fallbackColor: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        );

        final textWidget = tester.widget<Text>(find.text('🔥'));
        expect(textWidget.style?.fontFamily, EmojiUtils.effectiveFontFamily);
        expect(textWidget.style?.color, isNull);

        final mediaView =
            tester.widget<StickerMediaView>(find.byType(StickerMediaView));
        expect(
          mediaView.adaptiveTintColor,
          isNull,
          reason:
              'Full-color custom emoji statuses must not receive a forced white srcIn tint',
        );
        expect(find.byType(ColorFiltered), findsNothing);
      },
    );

    testWidgets(
      'EmojiStickerPanel in emojiOnly mode hides GIF/Sticker nav & backspace and emits selected emoji',
      (tester) async {
        String? pickedEmoji;

        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>(
            create: (_) => LiquidGlassProvider(),
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 390,
                  height: 360,
                  child: EmojiStickerPanel(
                    emojiOnly: true,
                    expandToAvailableHeight: true,
                    selectedEmoji: '😀',
                    onEmojiSelected: (emoji) => pickedEmoji = emoji,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Chat search bar is rendered, while GIF/Stickers tabs & Backspace are hidden
        expect(find.text('Поиск эмодзи'), findsOneWidget);
        expect(find.text('GIF'), findsNothing);
        expect(find.text('Стикеры'), findsNothing);
        expect(find.byIcon(Icons.backspace_outlined), findsNothing);

        // Tapping a standard emoji fires onEmojiSelected
        await tester.tap(find.text('😀').first);
        await tester.pump();
        expect(pickedEmoji, '😀');
      },
    );
  });

  group('Fix 2: Chat selection bar button spacing', () {
    testWidgets(
      'ChatListAdaptiveTopBar spaces quick action buttons and counter pill comfortably without overflow',
      (tester) async {
        for (final width in <double>[390.0, 360.0]) {
          await tester.pumpWidget(
            ChangeNotifierProvider<LiquidGlassProvider>(
              create: (_) => LiquidGlassProvider(),
              child: MaterialApp(
                home: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: width,
                      child: ChatListAdaptiveTopBar(
                        isSelectMode: true,
                        selectedCount: 1,
                        onCancelSelection: () {},
                        normalTitle: 'Theaver',
                        selectionConfig: SelectionQuickActionsConfig(
                          canPin: true,
                          onPin: () {},
                          canMute: true,
                          onMute: () {},
                          canArchive: true,
                          onArchive: () {},
                          canDelete: true,
                          onDelete: () {},
                          overflowItems: [
                            SelectionMorphMenuItem(
                              id: 'select_all',
                              label: 'Выбрать все',
                              iconBuilder: (color, size) => iconoir.ListSelect(
                                color: color,
                                width: size,
                                height: size,
                              ),
                            ),
                          ],
                          onOverflowAction: (_) {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final pinCenter = tester.getCenter(find.byType(iconoir.Pin));
          final muteCenter = tester.getCenter(find.byType(iconoir.BellOff));
          final archiveCenter = tester.getCenter(find.byType(iconoir.Archive));
          final deleteCenter = tester.getCenter(find.byType(iconoir.Trash));
          final moreCenter = tester.getCenter(find.byType(iconoir.MoreVert));

          final expectedMinSpacing = width >= 380.0 ? 43.0 : 40.0;
          expect(muteCenter.dx - pinCenter.dx, greaterThanOrEqualTo(expectedMinSpacing));
          expect(archiveCenter.dx - muteCenter.dx, greaterThanOrEqualTo(expectedMinSpacing));
          expect(deleteCenter.dx - archiveCenter.dx, greaterThanOrEqualTo(expectedMinSpacing));
          expect(moreCenter.dx - deleteCenter.dx, greaterThanOrEqualTo(expectedMinSpacing));

          // Counter pill and right capsule have comfortable separation (>= 14px)
          final leftCancelRect =
              tester.getRect(find.byKey(const ValueKey<String>('left_cancel_selection')));
          final counterRect = tester.getRect(
            find.byKey(const ValueKey<String>('center_select_counter_compact')),
          );
          final capsuleRect =
              tester.getRect(find.byKey(const ValueKey<String>('right_select_capsule')));

          final gapLeft = counterRect.left - leftCancelRect.right;
          final gapRight = capsuleRect.left - counterRect.right;
          expect(gapLeft, greaterThanOrEqualTo(13.5));
          expect(gapRight, greaterThanOrEqualTo(13.5));
          expect((gapLeft - gapRight).abs(), lessThanOrEqualTo(1.0));
        }
      },
    );
  });

  group('Fix 3: MainScreen header top-to-bottom title replacement', () {
    testWidgets(
      'Switching between Настройки / Theaver / Поиск animates incoming title from top and outgoing title downward',
      (tester) async {
        String currentTitle = 'Theaver';
        String currentKey = 'chats_filter_0';
        late StateSetter updateBar;

        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>(
            create: (_) => LiquidGlassProvider(),
            child: MaterialApp(
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    updateBar = setState;
                    return SizedBox(
                      width: 390,
                      child: ChatListAdaptiveTopBar(
                        isSelectMode: false,
                        selectedCount: 0,
                        onCancelSelection: () {},
                        normalTitle: currentTitle,
                        normalTitleKey: currentKey,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final initialCenterY = tester.getCenter(find.text('Theaver')).dy;

        // Switch from 'Theaver' -> 'Настройки'
        updateBar(() {
          currentTitle = 'Настройки';
          currentKey = 'settings';
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));

        // Mid-transition: both texts exist; incoming 'Настройки' is above center, outgoing 'Theaver' is below center!
        expect(find.text('Настройки'), findsOneWidget);
        expect(find.text('Theaver'), findsOneWidget);

        final incomingY = tester.getCenter(find.text('Настройки')).dy;
        final outgoingY = tester.getCenter(find.text('Theaver')).dy;

        expect(
          incomingY,
          lessThan(initialCenterY - 2.0),
          reason: 'Incoming title must slide down from above center',
        );
        expect(
          outgoingY,
          greaterThan(initialCenterY + 2.0),
          reason: 'Outgoing title must slide down below center',
        );

        await tester.pumpAndSettle();
        expect(find.text('Theaver'), findsNothing);
        expect(find.text('Настройки'), findsOneWidget);
        expect(
          (tester.getCenter(find.text('Настройки')).dy - initialCenterY).abs(),
          lessThan(0.5),
        );

        // Switch from 'Настройки' -> 'Поиск'
        updateBar(() {
          currentTitle = 'Поиск';
          currentKey = 'search';
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));

        expect(find.text('Поиск'), findsOneWidget);
        expect(find.text('Настройки'), findsOneWidget);
        expect(tester.getCenter(find.text('Поиск')).dy, lessThan(initialCenterY - 2.0));
        expect(
          tester.getCenter(find.text('Настройки')).dy,
          greaterThan(initialCenterY + 2.0),
        );

        await tester.pumpAndSettle();
        expect(find.text('Настройки'), findsNothing);
        expect(find.text('Поиск'), findsOneWidget);
      },
    );
  });
}
