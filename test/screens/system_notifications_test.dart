// ignore_for_file: depend_on_referenced_packages
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/screens/chat/private_chat_screen.dart';
import 'package:theaver/screens/chat/system_notifications_screen.dart';
import 'package:theaver/services/account_manager.dart';
import 'package:theaver/services/chat_instant_cache.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/chat_swipe_service.dart';
import 'package:theaver/services/database/app_database.dart';
import 'package:theaver/services/emoji_haptic_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/notification_settings_provider.dart';
import 'package:theaver/services/peer_customization_cache.dart';
import 'package:theaver/services/power_saving_provider.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/services/unread_count_provider.dart';
import 'package:theaver/services/wallpaper_provider.dart';
import 'package:theaver/theme/app_theme.dart';
import 'package:theaver/theme/theme_provider.dart';
import 'package:theaver/widgets/chat/chat_list_tile_item.dart';
import 'package:theaver/widgets/chat/floating_glass_app_bar.dart';
import 'package:theaver/widgets/chat/liquid_glass_input_field.dart';
import 'package:theaver/widgets/design_system/theav_design_system.dart';
import 'package:theaver/widgets/message/message_bubble.dart';
import 'package:theaver/widgets/message/message_status_widget.dart';

class _TestLiquidGlassProvider extends LiquidGlassProvider {
  _TestLiquidGlassProvider(this._mode);

  final GlassMode _mode;

  @override
  GlassMode get mode => _mode;

  @override
  bool get enabled => _mode != GlassMode.disabled;

  @override
  bool get isLite => _mode == GlassMode.lite;

  @override
  bool get isFull => _mode == GlassMode.full;
}

class _TestPowerSavingProvider extends ChangeNotifier
    implements PowerSavingProvider {
  _TestPowerSavingProvider(this._allowBlur);

  final bool _allowBlur;

  @override
  bool get allowBlur => _allowBlur;

  @override
  bool get allowAnimations => _allowBlur;

  @override
  bool get isActive => !_allowBlur;

  @override
  bool get allowAutoplayGif => true;

  @override
  bool get allowAutoplayVideo => true;

  @override
  bool get allowHaptics => true;

  @override
  PowerSavingSettings get settings => PowerSavingSettings.defaults();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreloadedAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  final AppLocalizations instance;
  const _PreloadedAppLocalizationsDelegate(this.instance);

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(instance);

  @override
  bool shouldReload(covariant _PreloadedAppLocalizationsDelegate old) => false;
}

Future<AppLocalizations> _loadRuTestL10n(WidgetTester tester) async {
  return (await tester.runAsync(
    () => AppLocalizations.delegate.load(const Locale('ru')),
  ))!;
}

Widget _buildSystemTestHost({
  required Widget child,
  required AppLocalizations l10n,
  GlassMode glassMode = GlassMode.disabled,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider<LiquidGlassProvider>.value(
        value: _TestLiquidGlassProvider(glassMode),
      ),
      ChangeNotifierProvider<PowerSavingProvider>.value(
        value: _TestPowerSavingProvider(true),
      ),
      ChangeNotifierProvider(create: (_) => UnreadCountProvider()),
      ChangeNotifierProvider(create: (_) => NotificationSettingsProvider()),
      ChangeNotifierProvider(create: (_) => WallpaperProvider()),
      ChangeNotifierProvider.value(value: PeerCustomizationCache.instance),
      ChangeNotifierProvider(create: (_) => ProfileThemeProvider()),
      ChangeNotifierProvider.value(value: EmojiHapticService.instance),
    ],
    child: MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: const [Locale('en'), Locale('ru')],
      localizationsDelegates: [
        _PreloadedAppLocalizationsDelegate(l10n),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.dark(),
      home: child,
    ),
  );
}

void main() {
  group('System Notifications Message Parsing Tests', () {
    test('Correctly extracts alert lines from security alert payload', () {
      const content = '🔔 Новый вход в аккаунт\n'
          '📱 Устройство: Chrome on Windows\n'
          '💻 ОС: Windows 11\n'
          '🌐 Местоположение: Москва, Россия (127.0.0.1)\n'
          '⏰ Время: 2026-09-03 21:00:00';

      final lines = content.split('\n');
      String device = '';
      String os = '';
      String location = '';
      String timeStr = '';

      for (final line in lines) {
        if (line.contains('📱')) {
          device = line.replaceAll('📱', '').replaceAll('Устройство:', '').replaceAll('Device:', '').trim();
        } else if (line.contains('💻')) {
          os = line.replaceAll('💻', '').replaceAll('ОС:', '').replaceAll('OS:', '').trim();
        } else if (line.contains('🌐')) {
          location = line.replaceAll('🌐', '').replaceAll('Местоположение:', '').replaceAll('Location:', '').replaceAll('Локация:', '').trim();
        } else if (line.contains('⏰')) {
          timeStr = line.replaceAll('⏰', '').replaceAll('Время:', '').replaceAll('Time:', '').trim();
        }
      }

      expect(device, equals('Chrome on Windows'));
      expect(os, equals('Windows 11'));
      expect(location, equals('Москва, Россия (127.0.0.1)'));
      expect(timeStr, equals('2026-09-03 21:00:00'));
    });

    test('Chat with chatType system is recognized correctly', () {
      final chat = Chat(
        id: 'system-chat-1',
        chatType: 'system',
        name: 'Системные уведомления',
        updatedAt: DateTime.now().toIso8601String(),
        isPinned: true,
      );

      expect(chat.chatType, equals('system'));
      expect(chat.isPinned, isTrue);
      expect(chat.name, equals('Системные уведомления'));
    });
  });

  group('Unified System Chat Widget Tests', () {
    const testUserId = 'user_sys_test_1';

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      ChatInstantCache.instance.clearForTesting();

      await AccountManager().init();
      if (AccountManager().hasAccount(testUserId)) {
        await AccountManager().removeAccount(testUserId);
      }
      await AccountManager().addAccount(
        Account(
          userId: testUserId,
          token: 'jwt_sys_test_token',
          username: 'sys_tester',
          displayName: 'System Tester',
          lastLogin: DateTime.now(),
        ),
      );

      await AppDatabase.closeAll();
      AppDatabase.setActiveUser(testUserId);
      AppDatabase.setTestingInstance(
        testUserId,
        AppDatabase.forTesting(
          NativeDatabase.memory(),
          userId: testUserId,
        ),
      );
    });

    tearDown(() async {
      ChatInstantCache.instance.clearForTesting();
      if (AccountManager().hasAccount(testUserId)) {
        await AccountManager().removeAccount(testUserId);
      }
      await AppDatabase.closeAll();
    });

    testWidgets(
      'Read-only SystemNotificationsScreen uses PrivateChatScreen chrome, forces incoming bubble alignment, shows Devices button and read-only banner',
      (tester) async {
        final l10n = await _loadRuTestL10n(tester);
        const sysChatId = 'sys_ro_1';
        const iso = '2026-11-27T12:00:00.000Z';

        ChatInstantCache.instance.seedSnapshotForTesting(
          ChatInstantSnapshot(
            chatId: sysChatId,
            isVerified: true,
            messages: [
              Message(
                id: '901',
                chatId: sysChatId,
                senderId: testUserId,
                senderName: 'Системные уведомления',
                content: 'Новый вход в аккаунт с устройства Chrome',
                messageType: 'text',
                isEdited: false,
                createdAt: iso,
                mediaPayload: const {'device_id': 'dev_1'},
              ),
            ],
          ),
        );

        await tester.pumpWidget(
          _buildSystemTestHost(
            l10n: l10n,
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SystemNotificationsScreen(
                            chatId: sysChatId,
                            chatName: 'System Notifications',
                          ),
                        ),
                      );
                    },
                    child: const Text('OpenSystemChat'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('OpenSystemChat'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(find.byType(PrivateChatScreen), findsOneWidget);

        final appBar = tester.widget<FloatingGlassAppBar>(
          find.byType(FloatingGlassAppBar),
        );
        expect(appBar.isVerified, isTrue);
        expect(appBar.isSavedChat, isFalse);
        expect(appBar.onReport, isNull);
        expect(appBar.onVoiceCall, isNull);

        expect(find.text('Системные уведомления'), findsOneWidget);
        expect(find.text('Служебный чат'), findsOneWidget);

        final bubble = tester.widget<MessageBubble>(
          find.byType(MessageBubble),
        );
        expect(bubble.isMe, isFalse);

        expect(find.text(l10n.translate('devices_title')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(TheavFloatingSurface),
            matching: find.text('Это системный чат только для чтения'),
          ),
          findsOneWidget,
        );
        expect(find.byType(LiquidGlassInputField), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'Interactive 2-party system chat keeps custom title, verified badge, and composer input',
      (tester) async {
        final l10n = await _loadRuTestL10n(tester);
        const sysChatId = 'sys_2p_1';
        const botPeerId = 'sys_bot_1';
        const iso = '2026-11-27T12:05:00.000Z';

        ChatInstantCache.instance.seedSnapshotForTesting(
          ChatInstantSnapshot(
            chatId: sysChatId,
            isVerified: true,
            messages: [
              Message(
                id: '902',
                chatId: sysChatId,
                senderId: botPeerId,
                senderName: 'Theaver Support',
                content: 'Здравствуйте, чем помочь?',
                messageType: 'text',
                isEdited: false,
                createdAt: iso,
              ),
            ],
          ),
        );

        await tester.pumpWidget(
          _buildSystemTestHost(
            l10n: l10n,
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PrivateChatScreen(
                            chatId: sysChatId,
                            initialChatType: 'system',
                            otherUserId: botPeerId,
                            otherUserName: 'Theaver Support',
                          ),
                        ),
                      );
                    },
                    child: const Text('OpenInteractiveSystemChat'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('OpenInteractiveSystemChat'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(find.byType(PrivateChatScreen), findsOneWidget);

        final appBar = tester.widget<FloatingGlassAppBar>(
          find.byType(FloatingGlassAppBar),
        );
        expect(appBar.isVerified, isTrue);
        expect(appBar.onReport, isNull);

        expect(find.text('Theaver Support'), findsOneWidget);
        expect(find.byType(LiquidGlassInputField), findsOneWidget);
        expect(
          find.text('Это системный чат только для чтения'),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'ChatListTileItem localizes default system chat name and suppresses outgoing checkmarks only for read-only system chats',
      (tester) async {
        final l10n = await _loadRuTestL10n(tester);
        Future<void> noopSwipe(ChatSwipeAction _) async {}

        final readOnlySystemChat = Chat(
          id: 'sys_ro_1',
          chatType: 'system',
          name: 'System Notifications',
          lastMessage: 'New login',
          lastMessageSenderId: testUserId,
          lastMessageTime: '2026-11-27T12:00:00Z',
          updatedAt: '2026-11-27T12:00:00Z',
        );

        await tester.pumpWidget(
          _buildSystemTestHost(
            l10n: l10n,
            child: Scaffold(
              body: ChatListTileItem(
                chat: readOnlySystemChat,
                isSelectMode: false,
                isSelected: false,
                isMuted: false,
                currentUserId: testUserId,
                onTap: () {},
                onLongPress: () {},
                onSwipeAction: noopSwipe,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Системные уведомления'), findsOneWidget);
        expect(find.byType(iconoir.ShieldCheck), findsAtLeastNWidgets(1));
        expect(find.byType(MessageStatusWidget), findsNothing);

        final interactiveSystemChat = Chat(
          id: 'sys_2p_1',
          chatType: 'system',
          name: 'Theaver Support',
          otherUserId: 'sys_bot_1',
          lastMessage: 'Принято',
          lastMessageSenderId: testUserId,
          lastMessageTime: '2026-11-27T12:05:00Z',
          updatedAt: '2026-11-27T12:05:00Z',
        );

        await tester.pumpWidget(
          _buildSystemTestHost(
            l10n: l10n,
            child: Scaffold(
              body: ChatListTileItem(
                chat: interactiveSystemChat,
                isSelectMode: false,
                isSelected: false,
                isMuted: false,
                currentUserId: testUserId,
                onTap: () {},
                onLongPress: () {},
                onSwipeAction: noopSwipe,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Theaver Support'), findsOneWidget);
        expect(find.byType(MessageStatusWidget), findsOneWidget);
      },
    );
  });
}
