import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/models/community_models.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/database/app_database.dart';
import 'package:theaver/services/dm_parity_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/services/sticker_service.dart';
import 'package:theaver/services/tiling_layout_controller.dart';
import 'package:theaver/theme/app_theme.dart';
import 'package:theaver/widgets/chat/chat_list_tile_item.dart';
import 'package:theaver/widgets/chat/liquid_glass_input_field.dart';

class _DisabledGlassProvider extends LiquidGlassProvider {
  @override
  GlassMode get mode => GlassMode.disabled;

  @override
  bool get enabled => false;

  @override
  bool get isLite => false;

  @override
  bool get isFull => false;
}

class _EmojiToggleComposerHarness extends StatefulWidget {
  const _EmojiToggleComposerHarness({required this.controller});

  final RichTextEditingController controller;

  @override
  State<_EmojiToggleComposerHarness> createState() =>
      _EmojiToggleComposerHarnessState();
}

class _EmojiToggleComposerHarnessState
    extends State<_EmojiToggleComposerHarness> {
  final FocusNode _inputFocusNode = FocusNode();
  bool _showEmojiPanel = false;
  bool _isKeyboardRising = false;

  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void dispose() {
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _onEmojiToggle() {
    if (_showEmojiPanel || _isKeyboardRising) {
      setState(() {
        _isKeyboardRising = true;
        _showEmojiPanel = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_inputFocusNode.hasFocus) {
          _inputFocusNode.requestFocus();
        }
        if (_isMobilePlatform) {
          SystemChannels.textInput.invokeMethod('TextInput.show');
        }
      });
    } else {
      if (!widget.controller.selection.isValid) {
        widget.controller.selection = TextSelection.collapsed(
          offset: widget.controller.text.length,
        );
      }
      setState(() {
        _showEmojiPanel = true;
        _isKeyboardRising = false;
      });
      if (_isMobilePlatform) {
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showEmojiPanel || _isKeyboardRising) return;
        if (!_inputFocusNode.hasFocus) {
          _inputFocusNode.requestFocus();
        }
        if (_isMobilePlatform) {
          SystemChannels.textInput.invokeMethod('TextInput.hide');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Spacer(),
          LiquidGlassInputField(
            enabled: true,
            controller: widget.controller,
            focusNode: _inputFocusNode,
            hintText: 'Message',
            isEmojiPanelOpen: _showEmojiPanel && !_isKeyboardRising,
            onEmoji: _onEmojiToggle,
            onTapInputWhenEmojiOpen: _onEmojiToggle,
          ),
          if (_showEmojiPanel)
            const SizedBox(
              key: ValueKey<String>('mock_emoji_panel'),
              height: 240,
            ),
        ],
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
    TilingLayoutController.instance.closeAllChats();
  });

  group('Composer, Chat Swipe, Badge & ChatList Regressions', () {
    testWidgets(
      'Issue 2: Opening emoji panel on Android keeps TextField readOnly with blinking cursor and zero TextInput.show/setClient calls, while switching back shows keyboard',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final List<String> textInputCalls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
          textInputCalls.add(call.method);
          return null;
        });

        try {
          final controller = RichTextEditingController();
          addTearDown(controller.dispose);

          await tester.pumpWidget(
            ChangeNotifierProvider<LiquidGlassProvider>.value(
              value: _DisabledGlassProvider(),
              child: MaterialApp(
                locale: const Locale('ru'),
                supportedLocales: const <Locale>[Locale('ru'), Locale('en')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                theme: AppTheme.dark(),
                home: _EmojiToggleComposerHarness(controller: controller),
              ),
            ),
          );
          await tester.pumpAndSettle();

          textInputCalls.clear();

          // Tap emoji button while keyboard is closed and input is unfocused.
          final emojiBtn = find.descendant(
            of: find.byType(LiquidGlassInputField),
            matching: find.byType(GestureDetector).first,
          );
          expect(emojiBtn, findsOneWidget);
          await tester.tap(emojiBtn);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(
            find.byKey(const ValueKey<String>('mock_emoji_panel')),
            findsOneWidget,
          );

          final TextField tfOpen = tester.widget<TextField>(
            find.byType(TextField),
          );
          expect(tfOpen.readOnly, isTrue);
          expect(tfOpen.showCursor, isTrue);
          expect(tfOpen.keyboardType, TextInputType.none);
          expect(textInputCalls.contains('TextInput.show'), isFalse);
          expect(textInputCalls.contains('TextInput.setClient'), isFalse);

          // Programmatic emoji insertion continues working while readOnly == true.
          controller.text = '🔥';
          await tester.pump();
          expect(controller.text, '🔥');

          // Switch back from emoji panel to keyboard.
          textInputCalls.clear();
          await tester.tap(emojiBtn);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          final TextField tfClosed = tester.widget<TextField>(
            find.byType(TextField),
          );
          expect(tfClosed.readOnly, isFalse);
          expect(tfClosed.keyboardType, TextInputType.multiline);
          expect(textInputCalls.contains('TextInput.show'), isTrue);
        } finally {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.textInput, null);
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Issue 3B/3C: ChatListTileItem renders unread dot when unreadCount == -1 and updateChatLastMessage converts -1 -> 1 on new incoming message',
      (tester) async {
        final chatMarkedUnread = Chat(
          id: '42',
          chatType: 'private',
          name: 'Marked Unread Peer',
          lastMessage: 'Hello',
          lastMessageTime: '2026-11-24T12:00:00Z',
          updatedAt: '2026-11-24T12:00:00Z',
          unreadCount: -1,
        );

        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: _DisabledGlassProvider(),
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: Scaffold(
                body: ChatListTileItem(
                  chat: chatMarkedUnread,
                  isSelectMode: false,
                  isSelected: false,
                  isMuted: false,
                  onTap: () {},
                  onLongPress: () {},
                  onSwipeAction: (_) async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Marked Unread Peer'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is SizedBox &&
                w.width == 18 &&
                w.height == 18 &&
                w.child == null,
          ),
          findsWidgets,
        );

        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.initialize();
        await db.saveChat(
          chatMarkedUnread.toCompanion(),
        );
        await db.updateChatLastMessage(
          chatId: '42',
          content: 'New msg',
          createdAt: '2026-11-24T12:01:00Z',
          incrementUnread: true,
        );
        final updated = await db.getChat('42');
        expect(updated, isNotNull);
        expect(updated!.unreadCount, 1);
      },
    );

    test(
      'Issue 4: Stringified int JSON fields parse safely across Chat, ChatDetails, Message, Sticker, DM & Community models and AppDatabase preserves media-only private chats',
      () async {
        final chat = Chat.fromJson(<String, dynamic>{
          'id': '397710081',
          'chat_type': 'private',
          'name': 'Alice',
          'pinned_message_id': '1009',
          'community_id': '4',
          'unread_count': '3',
          'last_message': '',
          'last_message_type': 'image',
          'last_message_time': '2026-11-24T12:00:00Z',
          'updated_at': '2026-11-24T12:00:00Z',
        });
        expect(chat.pinnedMessageId, 1009);
        expect(chat.pinnedMessageIds, equals(<int>[1009]));
        expect(chat.communityId, 4);
        expect(chat.unreadCount, 3);

        final details = ChatDetails.fromJson(<String, dynamic>{
          'id': '397710081',
          'chat_type': 'group',
          'name': 'Group',
          'pinned_message_id': '1009',
          'created_by': '1',
          'created_at': '2026-11-24T12:00:00Z',
          'updated_at': '2026-11-24T12:00:00Z',
        });
        expect(details.pinnedMessageId, 1009);

        final msg = Message.fromJson(<String, dynamic>{
          'id': '55',
          'chat_id': '397710081',
          'sender_id': '1',
          'content': '<b>hi</b>',
          'message_type': 'text',
          'created_at': '2026-11-24T12:00:00Z',
          'quote_offset': '2',
          'quote_length': '4',
          'send_status': '1',
          'topic_id': '12',
          'entities': [
            {'type': 'bold', 'offset': '0', 'length': '2'},
          ],
          'reactions': {'🔥': '7'},
        });
        expect(msg.quoteOffset, 2);
        expect(msg.quoteLength, 4);
        expect(msg.sendStatus, 1);
        expect(msg.topicId, 12);
        expect(msg.entities.single.offset, 0);
        expect(msg.entities.single.length, 2);
        expect(msg.reactions['🔥'], 7);

        final sticker = StickerItem.fromJson(<String, dynamic>{
          'id': '7',
          'pack_id': '2',
          'width': '512',
          'height': '512',
          'file_size': '2048',
          'order_index': '1',
        });
        expect(sticker.id, 7);
        expect(sticker.packId, 2);

        final pack = StickerPack.fromJson(<String, dynamic>{
          'id': '2',
          'owner_id': '99',
          'stickers_count': '10',
          'installed_count': '3',
        });
        expect(pack.id, 2);
        expect(pack.ownerId, 99);

        final gif = GifItemModel.fromJson(<String, dynamic>{
          'id': 'g1',
          'url': 'https://example.com/a.gif',
          'width': '320',
          'height': '240',
          'duration': '4',
          'use_count': '2',
        });
        expect(gif.width, 320);

        final tag = SavedTagItem.fromJson(<String, dynamic>{
          'tag': '❤️',
          'count': '5',
        });
        expect(tag.count, 5);

        final comm = Community.fromJson(<String, dynamic>{
          'id': '6',
          'name': 'Comm',
          'member_count': '12',
          'online_count': '3',
          'my_permissions': '8',
          'channels': [
            {'id': '10', 'community_id': '6', 'unread_count': '4'},
          ],
        });
        expect(comm.memberCount, 12);
        expect(comm.channels.single.unreadCount, 4);

        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);

        // Save both a media-only private chat (lastMessage == '', no communityId)
        // and an empty ghost private chat.
        await db.saveChat(
          Chat(
            id: '397710081',
            chatType: 'private',
            name: 'Alice',
            pinnedMessageId: chat.pinnedMessageId,
            unreadCount: 0,
            lastMessage: '',
            lastMessageType: 'image',
            lastMessageTime: '2026-11-24T12:00:00Z',
            updatedAt: '2026-11-24T12:00:00Z',
          ).toCompanion(),
        );
        await db.saveChat(
          Chat(
            id: 'ghost_private',
            chatType: 'private',
            name: '',
            lastMessage: '',
            updatedAt: '2026-11-24T11:00:00Z',
          ).toCompanion(),
        );

        await db.initialize();
        final visibleChats = await db.watchChats().first;
        expect(visibleChats.any((c) => c.chatId == '397710081'), isTrue);
        expect(visibleChats.any((c) => c.chatId == 'ghost_private'), isFalse);
      },
    );
  });
}
