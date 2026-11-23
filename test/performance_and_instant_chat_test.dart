import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/profile_customization.dart';
import 'package:theaver/screens/chat/channel_screen.dart';
import 'package:theaver/screens/chat/private_chat_screen.dart';
import 'package:theaver/screens/settings/profile_screen.dart';
import 'package:theaver/services/bot_service.dart';
import 'package:theaver/services/chat_instant_cache.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/emoji_haptic_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/notification_settings_provider.dart';
import 'package:theaver/services/peer_customization_cache.dart';
import 'package:theaver/services/power_saving_provider.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/services/unread_count_provider.dart';
import 'package:theaver/services/wallpaper_provider.dart';
import 'package:theaver/theme/theme_provider.dart';
import 'package:theaver/utils/image_utils.dart';
import 'package:theaver/widgets/chat/channel_bottom_capsule_bar.dart';
import 'package:theaver/widgets/chat/chat_input_bar.dart';
import 'package:theaver/widgets/chat/chat_messages_shimmer.dart';
import 'package:theaver/widgets/chat/chat_scaffold.dart';
import 'package:theaver/widgets/chat/floating_glass_app_bar.dart';
import 'package:theaver/widgets/design_system/theav_design_system.dart';
import 'package:theaver/widgets/user/avatar_with_status.dart';

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

Future<AppLocalizations> _loadTestL10n(WidgetTester tester) async {
  return (await tester.runAsync(
    () => AppLocalizations.delegate.load(const Locale('en')),
  ))!;
}

Widget _buildHost({
  required Widget child,
  required AppLocalizations l10n,
  bool allowBlur = true,
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
        value: _TestPowerSavingProvider(allowBlur),
      ),
      ChangeNotifierProvider(create: (_) => UnreadCountProvider()),
      ChangeNotifierProvider(create: (_) => NotificationSettingsProvider()),
      ChangeNotifierProvider(create: (_) => WallpaperProvider()),
      ChangeNotifierProvider.value(value: PeerCustomizationCache.instance),
      ChangeNotifierProvider(create: (_) => ProfileThemeProvider()),
      ChangeNotifierProvider.value(value: EmojiHapticService.instance),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('ru')],
      localizationsDelegates: [
        _PreloadedAppLocalizationsDelegate(l10n),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark(useMaterial3: true),
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ChatInstantCache.instance.clearForTesting();
  });

  tearDown(() {
    ChatInstantCache.instance.clearForTesting();
  });

  group('Wave 1: Material Frosted HUD Blur & Fallbacks', () {
    testWidgets(
      'GlassMode.disabled uses single-pass BackdropFilter on HUD when allowBlur=true and 0 BackdropFilter when allowBlur=false',
      (tester) async {
        final l10n = await _loadTestL10n(tester);
        Widget buildHud({required bool allowBlur}) {
          return _buildHost(
            l10n: l10n,
            allowBlur: allowBlur,
            child: ChatScaffold(
              appBar: FloatingGlassAppBar(
                name: 'Design QA',
                isOnline: true,
                onBack: () {},
                onTitleTap: () {},
              ),
              body: const Center(
                child: TheavFloatingSurface(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Floating Pill'),
                  ),
                ),
              ),
            ),
          );
        }

        await tester.pumpWidget(buildHud(allowBlur: true));
        await tester.pump();
        expect(find.byType(BackdropFilter), findsWidgets);

        await tester.pumpWidget(buildHud(allowBlur: false));
        await tester.pump();
        expect(find.byType(BackdropFilter), findsNothing);
      },
    );

    testWidgets(
      'TheavModalSheet suppresses BackdropFilter inside nested TheavFloatingSurface',
      (tester) async {
        final l10n = await _loadTestL10n(tester);
        await tester.pumpWidget(
          _buildHost(
            l10n: l10n,
            allowBlur: true,
            child: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showTheavModalSheet<void>(
                        context: context,
                        title: 'Sheet',
                        builder: (_) => const SizedBox(
                          height: 120,
                          child: Center(
                            child: TheavFloatingSurface(
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('Inside Sheet'),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('OpenSheet'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        await tester.tap(find.text('OpenSheet'));
        await tester.pumpAndSettle();

        expect(find.byType(TheavModalSheet), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(TheavModalSheet),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
        );
      },
    );
  });

  group('Wave 2: Uncropped Avatars & Zero-ClipPath Default Status Dot', () {
    test('avatarImageProvider preserves aspect ratio with ResizeImagePolicy.fit while avatarFullImageProvider stays full resolution', () {
      const url = 'https://example.com/wide_portrait.jpg';
      final thumbProvider = avatarImageProvider(url);
      final fullProvider = avatarFullImageProvider(url);

      expect(thumbProvider, isA<ResizeImage>());
      final resized = thumbProvider as ResizeImage;
      expect(resized.policy, ResizeImagePolicy.fit);
      expect(resized.width, 200);
      expect(resized.height, 200);

      expect(fullProvider, isNotNull);
      expect(fullProvider, isNot(isA<ResizeImage>()));
    });

    testWidgets(
      'AvatarWithStatus avoids ClipPath by default and keeps ClipPath only with AvatarDecorationPreset',
      (tester) async {
        final l10n = await _loadTestL10n(tester);
        await tester.pumpWidget(
          _buildHost(
            l10n: l10n,
            child: const Scaffold(
              body: Center(
                child: AvatarWithStatus(
                  avatarUrl: null,
                  name: 'Alice',
                  radius: 24,
                  isOnline: true,
                ),
              ),
            ),
          ),
        );
        expect(find.byType(ClipPath), findsNothing);

        await tester.pumpWidget(
          _buildHost(
            l10n: l10n,
            child: Scaffold(
              body: Center(
                child: AvatarWithStatus(
                  avatarUrl: null,
                  name: 'Alice',
                  radius: 24,
                  isOnline: true,
                  decorationOverride: AvatarDecorationPreset.builtInDefaults.first,
                ),
              ),
            ),
          ),
        );
        expect(find.byType(ClipPath), findsOneWidget);
      },
    );
  });

  group('Wave 3 & 4: Frame-0 Instant Chat Open & Epoch Parsing', () {
    test('Chat.updatedAtEpochMs, Message.createdAtEpochMs, and messagesEqual work deterministically', () {
      const iso = '2026-11-20T12:00:00.000Z';
      final expectedMs = DateTime.parse(iso).millisecondsSinceEpoch;
      final chat = Chat(
        id: 'c1',
        chatType: 'private',
        name: 'Alice',
        updatedAt: iso,
      );
      final m1 = Message(
        id: '100',
        chatId: 'c1',
        senderId: 'u2',
        content: 'Hello Frame 0',
        messageType: 'text',
        isEdited: false,
        createdAt: iso,
        senderName: 'Alice',
      );
      final m1Copy = m1.copyWith();
      final m2 = m1.copyWith(content: 'Edited');

      expect(chat.updatedAtEpochMs, expectedMs);
      expect(m1.createdAtEpochMs, expectedMs);
      expect(ChatInstantCache.messagesEqual([m1], [m1Copy]), isTrue);
      expect(ChatInstantCache.messagesEqual([m1], [m2]), isFalse);
    });

    testWidgets(
      'PrivateChatScreen renders cached bot messages and Menu WebApp chrome on Frame 0 without shimmer or Saved flash',
      (tester) async {
        final l10n = await _loadTestL10n(tester);
        const botChatId = 'chat_bot_1';
        const botUserId = 'bot_77';
        const iso = '2026-11-20T12:05:00.000Z';

        BotService.seedBotInfoCache(
          const BotInfo(
            userId: botUserId,
            username: 'helperbot',
            displayName: 'Helper Bot',
            isVerified: true,
            menuButton: BotMenuButton(
              type: 'web_app',
              text: 'Open Studio',
              webAppUrl: 'https://example.com/studio',
            ),
          ),
          chatId: botChatId,
        );

        ChatInstantCache.instance.seedSnapshotForTesting(
          ChatInstantSnapshot(
            chatId: botChatId,
            isBot: true,
            isVerified: true,
            username: 'helperbot',
            messages: [
              Message(
                id: '501',
                chatId: botChatId,
                senderId: botUserId,
                content: 'Instant bot welcome message',
                messageType: 'text',
                isEdited: false,
                createdAt: iso,
                senderName: 'Helper Bot',
              ),
            ],
          ),
        );

        await tester.pumpWidget(
          _buildHost(
            l10n: l10n,
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PrivateChatScreen(
                            chatId: botChatId,
                            otherUserName: 'Helper Bot',
                            otherUserId: botUserId,
                          ),
                        ),
                      );
                    },
                    child: const Text('OpenBot'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('OpenBot'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(find.byType(PrivateChatScreen), findsOneWidget);
        expect(find.byType(ChatMessagesShimmerSkeleton), findsNothing);
        expect(find.text('Instant bot welcome message'), findsOneWidget);
        expect(find.text('Open Studio'), findsOneWidget);

        final appBar = tester.widget<FloatingGlassAppBar>(
          find.byType(FloatingGlassAppBar),
        );
        expect(appBar.isBot, isTrue);
        expect(appBar.isVerified, isTrue);
        expect(appBar.isSavedChat, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'PrivateChatScreen with otherUserId=null does not flash Saved Messages chrome',
      (tester) async {
        final l10n = await _loadTestL10n(tester);
        await tester.pumpWidget(
          _buildHost(
            l10n: l10n,
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PrivateChatScreen(
                            chatId: 'dm_regular_99',
                            otherUserName: 'Bob',
                          ),
                        ),
                      );
                    },
                    child: const Text('OpenDM'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('OpenDM'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        final appBar = tester.widget<FloatingGlassAppBar>(
          find.byType(FloatingGlassAppBar),
        );
        expect(appBar.isSavedChat, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'ChannelScreen renders final subscriber vs owner bottom chrome and cached post on Frame 0',
      (tester) async {
        final l10n = await _loadTestL10n(tester);
        const subChannelId = 'channel_sub_1';
        const ownerChannelId = 'channel_owner_2';
        const iso = '2026-11-20T12:10:00.000Z';

        ChatInstantCache.instance.seedSnapshotForTesting(
          ChatInstantSnapshot(
            chatId: subChannelId,
            chatDetails: ChatDetails(
              id: subChannelId,
              chatType: 'channel',
              name: 'News Feed',
              createdBy: 'admin_1',
              createdAt: iso,
              updatedAt: iso,
              participants: const [],
              myRole: 'subscriber',
              isMember: true,
              subscriberCount: 420,
            ),
            messages: [
              Message(
                id: '901',
                chatId: subChannelId,
                senderId: 'admin_1',
                content: 'Instant channel announcement',
                messageType: 'text',
                isEdited: false,
                createdAt: iso,
                senderName: 'News Feed',
              ),
            ],
          ),
        );

        await tester.pumpWidget(
          _buildHost(
            l10n: l10n,
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ChannelScreen(
                            channelId: subChannelId,
                            channelName: 'News Feed',
                          ),
                        ),
                      );
                    },
                    child: const Text('OpenSubChannel'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('OpenSubChannel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(find.byType(ChatMessagesShimmerSkeleton), findsNothing);
        expect(find.text('Instant channel announcement'), findsOneWidget);
        final subBar = tester.widget<ChannelBottomCapsuleBar>(
          find.byType(ChannelBottomCapsuleBar),
        );
        expect(subBar.canPostInChannel, isFalse);
        expect(find.byType(ChatInputBar), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));

        // Now verify owner channel opens with ChatInputBar on Frame 0
        ChatInstantCache.instance.seedSnapshotForTesting(
          ChatInstantSnapshot(
            chatId: ownerChannelId,
            chatDetails: ChatDetails(
              id: ownerChannelId,
              chatType: 'channel',
              name: 'My Blog',
              createdBy: 'me_1',
              createdAt: iso,
              updatedAt: iso,
              participants: const [],
              myRole: 'owner',
              isMember: true,
              subscriberCount: 12,
            ),
            messages: [
              Message(
                id: '902',
                chatId: ownerChannelId,
                senderId: 'me_1',
                content: 'Owner post on Frame 0',
                messageType: 'text',
                isEdited: false,
                createdAt: iso,
                senderName: 'My Blog',
              ),
            ],
          ),
        );

        await tester.pumpWidget(
          _buildHost(
            l10n: l10n,
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ChannelScreen(
                            channelId: ownerChannelId,
                            channelName: 'My Blog',
                          ),
                        ),
                      );
                    },
                    child: const Text('OpenOwnerChannel'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('OpenOwnerChannel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(find.byType(ChatMessagesShimmerSkeleton), findsNothing);
        expect(find.text('Owner post on Frame 0'), findsOneWidget);
        final ownerBar = tester.widget<ChannelBottomCapsuleBar>(
          find.byType(ChannelBottomCapsuleBar),
        );
        expect(ownerBar.canPostInChannel, isTrue);
        expect(find.byType(ChatInputBar), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'PrivateChatScreen -> ProfileScreen transition keeps immutable Hero tag when otherUserId is initially null',
      (tester) async {
        final l10n = await _loadTestL10n(tester);
        await tester.pumpWidget(
          _buildHost(
            l10n: l10n,
            child: const PrivateChatScreen(
              chatId: 'dm_hero_stable_42',
              otherUserName: 'Alice Wonder',
            ),
          ),
        );
        await tester.pump();

        final appBar = tester.widget<FloatingGlassAppBar>(
          find.byType(FloatingGlassAppBar),
        );
        expect(appBar.heroTag, equals('chat_dm_hero_stable_42'));

        // Tap center pill in FloatingGlassAppBar to push ProfileScreen via SwipeBackPageRoute.
        await tester.tap(find.text('Alice Wonder'));
        await tester.pump();
        // Step through transition frames smoothly without exceptions or Hero tag mismatch.
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();

        final profileScreen = tester.widget<ProfileScreen>(
          find.byType(ProfileScreen),
        );
        expect(profileScreen.heroTag, equals('chat_dm_hero_stable_42'));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      },
    );
  });
}
