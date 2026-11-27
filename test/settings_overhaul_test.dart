import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/chat_folder.dart';
import 'package:theaver/screens/settings/about_theaver_screen.dart';
import 'package:theaver/screens/settings/settings_screen.dart';
import 'package:theaver/screens/settings/settings_search_index.dart';
import 'package:theaver/services/app_lock_service.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/chat_swipe_service.dart';
import 'package:theaver/services/deep_link_service.dart';
import 'package:theaver/services/notification_settings_provider.dart';
import 'package:theaver/services/power_saving_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/services/unread_count_provider.dart';
import 'package:theaver/theme/app_theme.dart';
import 'package:theaver/theme/theme_provider.dart';
import 'package:theaver/widgets/settings/settings_group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('User-scoped SettingsService isolation', () {
    test(
        'isolates powerSavingSettings, notificationSettings, and per-chat rules across users',
        () async {
      final service = SettingsService();
      await service.init();

      await service.reloadForUser('alice');
      await service.updatePowerSavingSettings(
        powerSavingEnabled: true,
        limitFrameRate: true,
      );
      await service.saveNotificationSettings(
        GlobalNotificationSettings(
          privateChatNotifications: false,
          badgeMode: BadgeMode.chats,
        ),
      );
      await service.saveChatNotificationSettings(
        'chat-1',
        const ChatNotificationSettings(
          chatId: 'chat-1',
          muteState: MuteState.muted,
        ),
      );

      // Switch to Bob and verify defaults are intact and independent
      await service.reloadForUser('bob');
      expect(service.powerSavingSettings.powerSavingEnabled, isFalse);
      expect(service.notificationSettings.privateChatNotifications, isTrue);
      expect(service.notificationSettings.badgeMode, BadgeMode.messages);
      expect(service.getChatNotificationSettings('chat-1'), isNull);

      await service.updatePowerSavingSettings(powerSavingEnabled: false);
      await service.saveNotificationSettings(
        GlobalNotificationSettings(privateChatNotifications: true),
      );

      // Switch back to Alice and verify her persisted scoped values remain
      await service.reloadForUser('alice');
      expect(service.powerSavingSettings.powerSavingEnabled, isTrue);
      expect(service.powerSavingSettings.limitFrameRate, isTrue);
      expect(service.notificationSettings.privateChatNotifications, isFalse);
      expect(service.notificationSettings.badgeMode, BadgeMode.chats);
      expect(
        service.getChatNotificationSettings('chat-1')?.muteState,
        MuteState.muted,
      );
    });
  });

  group('AppLockService PBKDF2 & lockout', () {
    test('hashes PIN with PBKDF2-SHA256, locks out on 5th failure, and disables cleanly',
        () async {
      final salt = List<int>.generate(16, (i) => i + 1);
      final d1 = AppLockService.derivePbkdf2Sha256('2580', salt);
      final d2 = AppLockService.derivePbkdf2Sha256('2580', salt);
      final dWrong = AppLockService.derivePbkdf2Sha256('1234', salt);
      expect(d1.length, 32);
      expect(d1, equals(d2));
      expect(d1, isNot(equals(dWrong)));

      final lock = AppLockService.forTesting();
      await lock.init();
      expect(lock.hasPin, isFalse);

      expect(await lock.setPin('2580'), isTrue);
      expect(lock.hasPin, isTrue);
      expect(await lock.verifyPin('2580'), isTrue);
      expect(lock.failedAttempts, 0);

      for (var i = 1; i <= 4; i++) {
        expect(await lock.verifyPin('0000'), isFalse);
        expect(lock.failedAttempts, i);
        expect(lock.isLockedOut, isFalse);
      }

      // 5th consecutive failed attempt triggers lockout
      expect(await lock.verifyPin('0000'), isFalse);
      expect(lock.failedAttempts, 5);
      expect(lock.isLockedOut, isTrue);
      expect(lock.lockoutRemaining, greaterThan(Duration.zero));

      // Even the correct PIN is rejected while locked out
      expect(await lock.verifyPin('2580'), isFalse);

      // Fresh unlocked instance with clean mock prefs can set & disable PIN
      SharedPreferences.setMockInitialValues({});
      final unlocked = AppLockService.forTesting();
      await unlocked.init();
      expect(await unlocked.setPin('2580'), isTrue);
      expect(await unlocked.disablePin('9999'), isFalse);
      expect(unlocked.hasPin, isTrue);
      expect(await unlocked.disablePin('2580'), isTrue);
      expect(unlocked.hasPin, isFalse);
    });
  });

  group('EffectiveChatSettings & UnreadCountProvider badges', () {
    test('inherits category defaults and honors expired vs active muteUntil',
        () async {
      final service = SettingsService();
      await service.init();
      await service.reloadForUser('notif_user');

      await service.saveNotificationSettings(
        GlobalNotificationSettings(
          privateChatNotifications: false,
          groupChatNotifications: true,
        ),
      );

      final effPrivate =
          service.getEffectiveChatSettings('p1', chatType: 'private');
      final effGroup =
          service.getEffectiveChatSettings('g1', chatType: 'group');
      expect(effPrivate.muteState, MuteState.muted);
      expect(effGroup.muteState, MuteState.notMuted);

      await service.saveChatNotificationSettings(
        'expired-chat',
        ChatNotificationSettings(
          chatId: 'expired-chat',
          muteState: MuteState.mutedUntil,
          muteUntil: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      );
      await service.saveChatNotificationSettings(
        'future-chat',
        ChatNotificationSettings(
          chatId: 'future-chat',
          muteState: MuteState.mutedUntil,
          muteUntil: DateTime.now().add(const Duration(hours: 2)),
        ),
      );

      expect(
        service.getEffectiveChatSettings('expired-chat').muteState,
        MuteState.notMuted,
      );
      expect(
        service.getEffectiveChatSettings('future-chat').muteState,
        MuteState.mutedUntil,
      );
    });

    test('computes badge counts for messages, chats, disabled, and muted filter',
        () {
      final provider = UnreadCountProvider();
      provider.loadFromChats([
        Chat(
          id: 'c1',
          chatType: 'private',
          name: 'Alice',
          updatedAt: '2026-01-01T00:00:00Z',
          unreadCount: 5,
        ),
        Chat(
          id: 'c2',
          chatType: 'group',
          name: 'Team',
          updatedAt: '2026-01-01T00:00:00Z',
          unreadCount: 3,
        ),
        Chat(
          id: 'c3',
          chatType: 'channel',
          name: 'Marked',
          updatedAt: '2026-01-01T00:00:00Z',
          unreadCount: -1,
        ),
      ]);

      expect(
        provider.getBadgeCount(
          badgeEnabled: false,
          badgeMode: BadgeMode.messages,
          includeMutedChats: true,
        ),
        0,
      );

      expect(
        provider.getBadgeCount(
          badgeEnabled: true,
          badgeMode: BadgeMode.messages,
          includeMutedChats: true,
        ),
        9,
      );

      expect(
        provider.getBadgeCount(
          badgeEnabled: true,
          badgeMode: BadgeMode.chats,
          includeMutedChats: true,
        ),
        3,
      );

      bool isMuted(String chatId, String? chatType) => chatId == 'c2';

      expect(
        provider.getBadgeCount(
          badgeEnabled: true,
          badgeMode: BadgeMode.messages,
          includeMutedChats: false,
          isMutedResolver: isMuted,
        ),
        6,
      );

      expect(
        provider.getBadgeCount(
          badgeEnabled: true,
          badgeMode: BadgeMode.chats,
          includeMutedChats: false,
          isMutedResolver: isMuted,
        ),
        2,
      );
    });
  });

  group('PowerSavingProvider gating', () {
    test('controls blur, animations, autoplay, and haptics flags', () {
      addTearDown(
        () => PowerSavingProvider.instance
            .setSettingsForTest(PowerSavingSettings.defaults()),
      );

      PowerSavingProvider.instance
          .setSettingsForTest(PowerSavingSettings.defaults());
      expect(PowerSavingProvider.instance.isActive, isFalse);
      expect(PowerSavingProvider.instance.allowBlur, isTrue);
      expect(PowerSavingProvider.instance.allowAnimations, isTrue);
      expect(PowerSavingProvider.instance.allowAutoplayGif, isTrue);
      expect(PowerSavingProvider.instance.allowAutoplayVideo, isTrue);
      expect(PowerSavingProvider.instance.allowHaptics, isTrue);

      PowerSavingProvider.instance.setSettingsForTest(
        PowerSavingSettings(
          powerSavingEnabled: true,
          batteryThreshold: 30,
          reduceBackgroundActivity: true,
          lowerScreenBrightness: false,
          limitFrameRate: true,
          disableVibrations: true,
          disableLocationServices: true,
        ),
      );
      expect(PowerSavingProvider.instance.isActive, isTrue);
      expect(PowerSavingProvider.instance.allowBlur, isFalse);
      expect(PowerSavingProvider.instance.allowAnimations, isFalse);
      expect(PowerSavingProvider.instance.allowAutoplayGif, isFalse);
      expect(PowerSavingProvider.instance.allowAutoplayVideo, isFalse);
      expect(PowerSavingProvider.instance.allowHaptics, isFalse);

      // Even if sub-flags are set, inactive master switch keeps media/animations enabled
      PowerSavingProvider.instance.setSettingsForTest(
        PowerSavingSettings(
          powerSavingEnabled: false,
          batteryThreshold: 20,
          reduceBackgroundActivity: true,
          lowerScreenBrightness: true,
          limitFrameRate: true,
          disableVibrations: true,
          disableLocationServices: false,
        ),
      );
      expect(PowerSavingProvider.instance.allowBlur, isTrue);
      expect(PowerSavingProvider.instance.allowAutoplayVideo, isTrue);
      expect(PowerSavingProvider.instance.allowHaptics, isTrue);
    });
  });

  group('ChatSwipeAction & ChatFolder matching', () {
    test('all swipe actions are implemented and folder filtering rules apply',
        () {
      for (final action in ChatSwipeAction.values) {
        expect(action.isImplemented, isTrue);
      }

      const folder = ChatFolder(
        id: 'work',
        name: 'Work',
        includedTypes: ['group'],
        includedChatIds: ['vip-private'],
        excludedChatIds: ['noisy-group'],
      );

      final vipPrivate = Chat(
        id: 'vip-private',
        chatType: 'private',
        name: 'VIP',
        updatedAt: '2026-01-01T00:00:00Z',
      );
      final regularPrivate = Chat(
        id: 'reg-private',
        chatType: 'private',
        name: 'Friend',
        updatedAt: '2026-01-01T00:00:00Z',
      );
      final normalGroup = Chat(
        id: 'team-group',
        chatType: 'group',
        name: 'Engineering',
        updatedAt: '2026-01-01T00:00:00Z',
      );
      final noisyGroup = Chat(
        id: 'noisy-group',
        chatType: 'group',
        name: 'Spam',
        updatedAt: '2026-01-01T00:00:00Z',
      );

      expect(folder.matchesChat(vipPrivate), isTrue);
      expect(folder.matchesChat(regularPrivate), isFalse);
      expect(folder.matchesChat(normalGroup), isTrue);
      expect(folder.matchesChat(noisyGroup), isFalse);
    });
  });

  group('ThemeProvider.isTimeInDarkSchedule', () {
    test('evaluates same-day and overnight windows accurately', () {
      const sameDayStart = TimeOfDay(hour: 9, minute: 0);
      const sameDayEnd = TimeOfDay(hour: 18, minute: 0);
      expect(
        ThemeProvider.isTimeInDarkSchedule(
          DateTime(2026, 1, 1, 8, 59),
          sameDayStart,
          sameDayEnd,
        ),
        isFalse,
      );
      expect(
        ThemeProvider.isTimeInDarkSchedule(
          DateTime(2026, 1, 1, 9, 0),
          sameDayStart,
          sameDayEnd,
        ),
        isTrue,
      );
      expect(
        ThemeProvider.isTimeInDarkSchedule(
          DateTime(2026, 1, 1, 18, 0),
          sameDayStart,
          sameDayEnd,
        ),
        isFalse,
      );

      const overnightStart = TimeOfDay(hour: 22, minute: 0);
      const overnightEnd = TimeOfDay(hour: 7, minute: 0);
      expect(
        ThemeProvider.isTimeInDarkSchedule(
          DateTime(2026, 1, 1, 21, 59),
          overnightStart,
          overnightEnd,
        ),
        isFalse,
      );
      expect(
        ThemeProvider.isTimeInDarkSchedule(
          DateTime(2026, 1, 1, 22, 0),
          overnightStart,
          overnightEnd,
        ),
        isTrue,
      );
      expect(
        ThemeProvider.isTimeInDarkSchedule(
          DateTime(2026, 1, 1, 2, 30),
          overnightStart,
          overnightEnd,
        ),
        isTrue,
      );
      expect(
        ThemeProvider.isTimeInDarkSchedule(
          DateTime(2026, 1, 1, 7, 0),
          overnightStart,
          overnightEnd,
        ),
        isFalse,
      );
    });
  });

  group('SettingsSearchIndex filtering & exclusions', () {
    test('hides app_updates on Web, matches keywords, and excludes Wallets', () {
      final entries = SettingsSearchIndex.defaultEntries();

      // Wallet/Cards must remain excluded
      for (final e in entries) {
        final combined =
            '${e.id} ${e.titleKey} ${e.fallbackTitle}'.toLowerCase();
        expect(combined.contains('wallet'), isFalse);
        expect(combined.contains('кошел'), isFalse);
        expect(combined.contains('banking'), isFalse);
      }

      final nonWebAll =
          SettingsSearchIndex.filter(entries, '', isWeb: false);
      final webAll = SettingsSearchIndex.filter(entries, '', isWeb: true);
      expect(nonWebAll.any((e) => e.id == 'app_updates'), isTrue);
      expect(webAll.any((e) => e.id == 'app_updates'), isFalse);

      expect(
        SettingsSearchIndex.filter(entries, 'update', isWeb: true)
            .any((e) => e.id == 'app_updates'),
        isFalse,
      );
      expect(
        SettingsSearchIndex.filter(entries, 'update', isWeb: false)
            .any((e) => e.id == 'app_updates'),
        isTrue,
      );

      expect(
        SettingsSearchIndex.filter(entries, '2fa', isWeb: false)
            .any((e) => e.id == 'security_2fa'),
        isTrue,
      );
      expect(
        SettingsSearchIndex.filter(entries, 'почта', isWeb: false)
            .any((e) => e.id == 'recovery_email'),
        isTrue,
      );
      expect(
        SettingsSearchIndex.filter(entries, 'шрифт', isWeb: false)
            .any((e) => e.id == 'chat_settings'),
        isTrue,
      );
    });

    testWidgets(
      'SettingsScreen search input displays localized settings_search_hint instead of global search_hint',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final l10n = AppLocalizations(const Locale('ru'));
        await tester.runAsync(() => l10n.load());

        final themeProvider = ThemeProvider();
        final notifProvider = NotificationSettingsProvider();
        final powerSaving = PowerSavingProvider();
        final localeProvider = LocaleProvider();
        addTearDown(themeProvider.dispose);
        addTearDown(notifProvider.dispose);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
              ChangeNotifierProvider<NotificationSettingsProvider>.value(
                value: notifProvider,
              ),
              ChangeNotifierProvider<PowerSavingProvider>.value(
                value: powerSaving,
              ),
              ChangeNotifierProvider<LocaleProvider>.value(
                value: localeProvider,
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              locale: const Locale('ru'),
              localizationsDelegates: [
                _PreloadedLocalizationsDelegate(l10n),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ru'), Locale('en')],
              home: const SettingsScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final searchField = tester.widget<TextField>(
          find.byKey(const ValueKey<String>('settings_search_input')),
        );
        expect(searchField.decoration?.hintText, 'Поиск в настройках...');
        expect(
          searchField.decoration?.hintText,
          isNot(equals(l10n.translate('search_hint'))),
        );

        for (final code in LocaleProvider.supportedLanguageCodes) {
          final loc = AppLocalizations(Locale(code));
          await tester.runAsync(() => loc.load());
          final hint = loc.translate('settings_search_hint');
          expect(hint, isNotEmpty, reason: 'Empty settings_search_hint in $code');
          expect(
            hint,
            isNot(equals('settings_search_hint')),
            reason: 'Missing key settings_search_hint in $code',
          );
          expect(
            hint,
            isNot(equals(loc.translate('search_hint'))),
            reason: 'Settings hint collided with global search_hint in $code',
          );
        }
      },
    );
  });

  group('DeepLinkService.parseUri QR links', () {
    test('parses qrLogin and qrGrant across custom scheme, https, and hash', () {
      final p1 = DeepLinkService.parseUri(
        Uri.parse('theaver://qr-login?token=abc_123'),
      );
      expect(p1?.type, DeepLinkType.qrLogin);
      expect(p1?.identifier, 'abc_123');

      final p2 = DeepLinkService.parseUri(
        Uri.parse('theaver://qr-login?mode=grant&token=grant_456'),
      );
      expect(p2?.type, DeepLinkType.qrGrant);
      expect(p2?.identifier, 'grant_456');

      final p3 = DeepLinkService.parseUri(
        Uri.parse('https://theaver.app/qr-login?token=web_789'),
      );
      expect(p3?.type, DeepLinkType.qrLogin);
      expect(p3?.identifier, 'web_789');

      final p4 = DeepLinkService.parseUri(
        Uri.parse('https://theaver.app/qr-login?mode=grant&token=web_grant_0'),
      );
      expect(p4?.type, DeepLinkType.qrGrant);
      expect(p4?.identifier, 'web_grant_0');

      final p5 = DeepLinkService.parseUri(
        Uri.parse('https://theaver.app/#/qr-login?mode=grant&token=hash_tok'),
      );
      expect(p5?.type, DeepLinkType.qrGrant);
      expect(p5?.identifier, 'hash_tok');
    });
  });

  group('AboutTheaverScreen borderless SettingsGroup UI', () {
    testWidgets(
      'renders 4 borderless SettingsGroup sections and 5-tap unlocks Debug // W.I.P',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final l10n = AppLocalizations(const Locale('ru'));
        await tester.runAsync(() => l10n.load());

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: [
              _PreloadedLocalizationsDelegate(l10n),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ru'), Locale('en')],
            home: const AboutTheaverScreen(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final groupFinder = find.byType(SettingsGroup);
        expect(groupFinder, findsNWidgets(4));

        for (final groupElem in groupFinder.evaluate()) {
          final containerFinder = find.descendant(
            of: find.byWidget(groupElem.widget),
            matching: find.byType(Container),
          );
          final outerCard = tester.widget<Container>(containerFinder.first);
          final deco = outerCard.decoration as BoxDecoration?;
          expect(deco?.border, isNull);
          expect(deco?.borderRadius, BorderRadius.circular(16));
        }

        expect(find.text('Debug // W.I.P'), findsNothing);

        final versionFinder = find.textContaining('Theaver ');
        expect(versionFinder, findsWidgets);
        for (int i = 0; i < 5; i++) {
          await tester.tap(versionFinder.first);
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pump(const Duration(seconds: 4));

        expect(find.text('Debug // W.I.P'), findsOneWidget);
      },
    );
  });
}

class _PreloadedLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  final AppLocalizations localizations;
  const _PreloadedLocalizationsDelegate(this.localizations);

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(localizations);

  @override
  bool shouldReload(_PreloadedLocalizationsDelegate old) => false;
}
