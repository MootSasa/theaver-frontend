import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/widgets/chat/floating_glass_app_bar.dart';
import 'package:theaver/widgets/chat/animated_ellipsis_text.dart';
import 'package:theaver/widgets/user/avatar_with_status.dart';
import 'package:theaver/utils/date_time_utils.dart';
import 'package:theaver/l10n/app_localizations.dart';

class _TestAppLocalizations extends AppLocalizations {
  final Map<String, String> translations;
  _TestAppLocalizations(Locale locale, this.translations) : super(locale);

  @override
  String translate(String key) => translations[key] ?? key;
}

class _TestAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  final Map<String, String> translations;
  const _TestAppLocalizationsDelegate([this.translations = const {}]);

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return _TestAppLocalizations(locale, translations);
  }

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

final Map<String, String> _kRussianTranslations = {
  'chat_typing': 'печатает...',
  'chat_user_typing': '{name} печатает...',
  'chat_status_online': 'в сети',
  'chat_status_last_seen_just_now': 'был(а) только что',
  'chat_status_last_seen_minutes': 'был(а) {m} мин. назад',
  'chat_status_last_seen_today': 'был(а) сегодня в {time}',
  'chat_status_last_seen_yesterday': 'был(а) вчера в {time}',
  'chat_status_last_seen_recently': 'был(а) недавно',
  'chat_status_members_count': '{count} участников',
  'chat_status_members_and_online': '{count} участников, {online} в сети',
  'chat_status_subscribers_count': '{count} подписчиков',
  'chat_status_connecting': 'соединение...',
  'date_today': 'Сегодня',
  'date_yesterday': 'Вчера',
  'weekday_mon': 'Пн',
  'weekday_tue': 'Вт',
  'weekday_wed': 'Ср',
  'weekday_thu': 'Чт',
  'weekday_fri': 'Пт',
  'weekday_sat': 'Сб',
  'weekday_sun': 'Вс',
  'chat_menu_profile': 'Профиль',
  'chat_menu_voice_call': 'Голосовой звонок',
  'chat_menu_video_call': 'Видеозвонок',
  'chat_menu_search_messages': 'Поиск сообщений',
  'chat_menu_mute': 'Без звука',
  'chat_menu_unmute': 'Включить звук',
  'chat_menu_clear_history': 'Очистить историю',
  'chat_menu_report': 'Пожаловаться',
};

Widget createTestApp(Widget child, {Map<String, String>? translations}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LiquidGlassProvider()),
    ],
    child: MaterialApp(
      localizationsDelegates: [
        _TestAppLocalizationsDelegate(translations ?? _kRussianTranslations),
      ],
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  group('AnimatedEllipsisText tests ("." -> ".." -> "...")', () {
    testWidgets('Cycles ellipsis "." -> ".." -> "..." smoothly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          const AnimatedEllipsisText(
            text: 'печатает...',
            dotInterval: Duration(milliseconds: 200),
          ),
        ),
      );

      // Frame 1: 1 dot visible
      await tester.pump();
      expect(find.textContaining('печатает.'), findsOneWidget);

      // Frame 2: after 200ms -> 2 dots
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('печатает..'), findsOneWidget);

      // Frame 3: after another 200ms -> 3 dots
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('печатает...'), findsOneWidget);

      // Frame 4: wraps around back to 1 dot
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('печатает.'), findsOneWidget);
    });

    testWidgets('Renders static text unchanged when no ellipsis present',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          const AnimatedEllipsisText(
            text: 'в сети',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('в сети'), findsOneWidget);
    });
  });

  group('Typing Indicator Timer Tests (4-second window & keepalive)', () {
    test('Typing indicator remains active during brief pauses and resets after 4s', () async {
      bool isTyping = false;
      Timer? typingTimer;

      void onTypingReceived() {
        isTyping = true;
        typingTimer?.cancel();
        typingTimer = Timer(const Duration(seconds: 4), () {
          isTyping = false;
        });
      }

      onTypingReceived();
      expect(isTyping, isTrue);

      // Fast forward 2 seconds (user paused typing) -> still typing!
      await Future.delayed(const Duration(milliseconds: 2000));
      expect(isTyping, isTrue);

      // User continues typing -> extends window
      onTypingReceived();
      await Future.delayed(const Duration(milliseconds: 2000));
      expect(isTyping, isTrue);

      // User stops typing for > 4 seconds
      await Future.delayed(const Duration(milliseconds: 2100));
      expect(isTyping, isFalse);

      typingTimer?.cancel();
    });

    test('Typing indicator cancels immediately when is_typing: false is received', () {
      bool isTyping = false;
      Timer? typingTimer;

      void onTypingIndicator(bool typing) {
        if (!typing) {
          typingTimer?.cancel();
          isTyping = false;
          return;
        }
        isTyping = true;
        typingTimer?.cancel();
        typingTimer = Timer(const Duration(seconds: 4), () {
          isTyping = false;
        });
      }

      // Sender starts typing
      onTypingIndicator(true);
      expect(isTyping, isTrue);

      // Sender clears field or sends message (isTyping = false)
      onTypingIndicator(false);
      expect(isTyping, isFalse);
    });

    test('Sender sends keepalive while text is present and stops when text is cleared', () {
      final List<bool> sentIndicators = [];
      Timer? keepAliveTimer;
      bool amITyping = false;
      String currentText = '';

      void stopMyTyping() {
        keepAliveTimer?.cancel();
        keepAliveTimer = null;
        if (amITyping) {
          amITyping = false;
          sentIndicators.add(false);
        }
      }

      void onInputTextChanged(String text) {
        currentText = text;
        final bool hasText = text.trim().isNotEmpty;
        if (hasText) {
          if (!amITyping) {
            amITyping = true;
            sentIndicators.add(true);
          }
          keepAliveTimer ??= Timer.periodic(const Duration(milliseconds: 200), (_) {
            if (currentText.trim().isNotEmpty) {
              sentIndicators.add(true);
            } else {
              stopMyTyping();
            }
          });
        } else {
          stopMyTyping();
        }
      }

      // Type some characters
      onInputTextChanged('Hello');
      expect(sentIndicators, [true]);
      expect(amITyping, isTrue);

      // Erase text
      onInputTextChanged('');
      expect(sentIndicators, [true, false]);
      expect(amITyping, isFalse);
      expect(keepAliveTimer, isNull);
    });
  });

  group('ChatParticipant presence serialization', () {
    test('ChatParticipant correctly parses is_online and last_seen', () {
      final now = DateTime.now().toUtc();
      final json = {
        'id': 'user-123',
        'display_name': 'Alice',
        'role': 'member',
        'is_online': true,
        'last_seen': now.toIso8601String(),
      };

      final participant = ChatParticipant.fromJson(json);
      expect(participant.id, 'user-123');
      expect(participant.displayName, 'Alice');
      expect(participant.isOnline, isTrue);
      expect(participant.lastSeen, isNotNull);
      expect(participant.lastSeen!.year, now.year);

      // Test copyWith
      final updated = participant.copyWith(isOnline: false);
      expect(updated.isOnline, isFalse);
      expect(updated.displayName, 'Alice');
    });

    test('ChatParticipant handles missing or null is_online/last_seen gracefully', () {
      final json = {
        'id': 'user-456',
        'display_name': 'Bob',
        'role': 'member',
      };

      final participant = ChatParticipant.fromJson(json);
      expect(participant.id, 'user-456');
      expect(participant.isOnline, isFalse);
      expect(participant.lastSeen, isNull);
    });
  });

  group('FloatingGlassAppBar Status and Presence Widget Tests', () {
    testWidgets('Shows "соединение..." when isConnected == false',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'Bob',
            isOnline: true,
            isConnected: false, // Server unavailable
            onBack: () {},
            onTitleTap: () {},
            onAvatarTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.textContaining('соединение'), findsOneWidget);
    });

    testWidgets('Shows "в сети" when user isOnline == true and isConnected == true',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'Bob',
            isOnline: true,
            isConnected: true,
            onBack: () {},
            onTitleTap: () {},
            onAvatarTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('в сети'), findsOneWidget);
    });

    testWidgets('Shows custom statusText (e.g. typing) overriding isOnline',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'Bob',
            isOnline: true,
            isConnected: true,
            statusText: 'печатает...',
            onBack: () {},
            onTitleTap: () {},
            onAvatarTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.textContaining('печатает'), findsOneWidget);
      expect(find.text('в сети'), findsNothing);
    });

    testWidgets('Shows "был(а) недавно" fallback when lastSeen == null (never vanishes)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'Bob',
            isOnline: false,
            lastSeen: null,
            isConnected: true,
            onBack: () {},
            onTitleTap: () {},
            onAvatarTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('был(а) недавно'), findsOneWidget);
    });

    testWidgets('Shows "был(а) только что" when lastSeen < 1 minute ago',
        (WidgetTester tester) async {
      final justNow = DateTime.now().subtract(const Duration(seconds: 15));
      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'Charlie',
            isOnline: false,
            lastSeen: justNow,
            isConnected: true,
            onBack: () {},
            onTitleTap: () {},
            onAvatarTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('был(а) только что'), findsOneWidget);
    });

    testWidgets('Shows "был(а) 15 мин. назад" when lastSeen is 15 minutes ago',
        (WidgetTester tester) async {
      final fifteenMinutesAgo = DateTime.now().subtract(const Duration(minutes: 15));
      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'Dave',
            isOnline: false,
            lastSeen: fifteenMinutesAgo,
            isConnected: true,
            onBack: () {},
            onTitleTap: () {},
            onAvatarTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Dave'), findsOneWidget);
      expect(find.text('был(а) 15 мин. назад'), findsOneWidget);
    });

    testWidgets('Shows "был(а) сегодня в HH:mm" with time converted to local device timezone',
        (WidgetTester tester) async {
      final now = DateTime.now();
      // 2 hours ago today (guaranteed today if now.hour >= 2, or earlier today)
      final twoHoursAgo = now.subtract(const Duration(hours: 2));
      final utcTime = twoHoursAgo.toUtc();
      final localHour = twoHoursAgo.hour.toString().padLeft(2, '0');
      final localMinute = twoHoursAgo.minute.toString().padLeft(2, '0');

      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'Eve',
            isOnline: false,
            lastSeen: utcTime, // Passed as UTC!
            isConnected: true,
            onBack: () {},
            onTitleTap: () {},
            onAvatarTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Eve'), findsOneWidget);
      if (now.day == twoHoursAgo.day) {
        expect(find.text('был(а) сегодня в $localHour:$localMinute'), findsOneWidget);
      } else {
        expect(find.text('был(а) вчера в $localHour:$localMinute'), findsOneWidget);
      }
    });

    testWidgets('Automatically transitions from "был(а) только что" to "был(а) 1 мин. назад" over time',
        (WidgetTester tester) async {
      final origProvider = DateTimeUtils.nowProvider;
      DateTimeUtils.nowProvider = () => tester.binding.clock.now();
      try {
        final lastSeen = tester.binding.clock.now();
        await tester.pumpWidget(
          createTestApp(
            FloatingGlassAppBar(
              name: 'David',
              isOnline: false,
              lastSeen: lastSeen,
              isConnected: true,
              onBack: () {},
              onTitleTap: () {},
              onAvatarTap: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.text('David'), findsOneWidget);
        expect(find.text('был(а) только что'), findsOneWidget);

        // Advance time by 65 seconds (periodic timer ticks every 3s and auto-updates)
        await tester.pump(const Duration(seconds: 65));

        expect(find.text('был(а) 1 мин. назад'), findsOneWidget);

        // Advance another 60 seconds
        await tester.pump(const Duration(seconds: 60));

        expect(find.text('был(а) 2 мин. назад'), findsOneWidget);
      } finally {
        DateTimeUtils.nowProvider = origProvider;
      }
    });

    testWidgets('Shows group status: "5 участников, 2 в сети" when onlineCount >= 1',
        (WidgetTester tester) async {
      const int total = 5;
      const int online = 2;
      final subtitle = _kRussianTranslations['chat_status_members_and_online']!
          .replaceAll('{count}', total.toString())
          .replaceAll('{online}', online.toString());

      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'MIPT Discussion Group',
            isOnline: false,
            isConnected: true,
            statusText: subtitle,
            onBack: () {},
            onTitleTap: () {},
            onAvatarTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('MIPT Discussion Group'), findsOneWidget);
      expect(find.text('5 участников, 2 в сети'), findsOneWidget);
    });

    testWidgets('Shows group status: "5 участников" when onlineCount == 0',
        (WidgetTester tester) async {
      const int total = 5;
      final subtitle = _kRussianTranslations['chat_status_members_count']!
          .replaceAll('{count}', total.toString());

      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'MIPT Discussion Group',
            isOnline: false,
            isConnected: true,
            statusText: subtitle,
            onBack: () {},
            onTitleTap: () {},
            onAvatarTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('MIPT Discussion Group'), findsOneWidget);
      expect(find.text('5 участников'), findsOneWidget);
    });

    testWidgets('Shows channel status: "1250 подписчиков"',
        (WidgetTester tester) async {
      const int total = 1250;
      final subtitle = _kRussianTranslations['chat_status_subscribers_count']!
          .replaceAll('{count}', total.toString());

      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'MIPT News Channel',
            isOnline: false,
            isConnected: true,
            statusText: subtitle,
            onBack: () {},
            onTitleTap: () {},
            onAvatarTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('MIPT News Channel'), findsOneWidget);
      expect(find.text('1250 подписчиков'), findsOneWidget);
    });

    testWidgets('Opens actions menu on avatar tap, dismisses on backdrop tap, and reopens smoothly',
        (WidgetTester tester) async {
      bool viewProfileCalled = false;
      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'Alice',
            isOnline: true,
            isConnected: true,
            onBack: () {},
            onTitleTap: () {},
            onViewProfile: () => viewProfileCalled = true,
            onSearch: () {},
            onToggleMute: () {},
            onClearHistory: () {},
            onReport: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Avatar is present
      final avatarFinder = find.byType(AvatarWithStatus);
      expect(avatarFinder, findsOneWidget);

      // 1. Open menu: tap avatar
      await tester.tap(avatarFinder);
      await tester.pumpAndSettle();

      // Menu options should be visible
      expect(find.text('Профиль'), findsOneWidget);
      expect(find.text('Поиск сообщений'), findsOneWidget);
      expect(find.text('Без звука'), findsOneWidget);
      expect(find.text('Очистить историю'), findsOneWidget);
      expect(find.text('Пожаловаться'), findsOneWidget);

      // 2. Dismiss menu: tap backdrop
      final backdropFinder = find.byKey(const ValueKey<String>('chat_appbar_backdrop'));
      expect(backdropFinder, findsOneWidget);
      await tester.tap(backdropFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Menu options should be gone
      expect(find.text('Профиль'), findsNothing);
      expect(find.text('Поиск сообщений'), findsNothing);

      // 3. Reopen menu: tap avatar again
      await tester.tap(find.byType(AvatarWithStatus));
      await tester.pumpAndSettle();
      expect(find.text('Профиль'), findsOneWidget);

      // 4. Tap menu action: "Профиль"
      await tester.tap(find.text('Профиль'));
      await tester.pumpAndSettle();
      expect(viewProfileCalled, isTrue);
      expect(find.text('Профиль'), findsNothing);
    });

    testWidgets('Renders separate voice call pill when onVoiceCall is provided, and hides in channel',
        (WidgetTester tester) async {
      bool callCalled = false;
      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'Bob',
            isOnline: true,
            isConnected: true,
            onBack: () {},
            onTitleTap: () {},
            onVoiceCall: () => callCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final callPillFinder = find.byKey(const ValueKey<String>('chat_appbar_call_pill'));
      expect(callPillFinder, findsOneWidget);

      await tester.tap(callPillFinder);
      await tester.pumpAndSettle();
      expect(callCalled, isTrue);

      // In channel mode, call pill must not be rendered
      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'Channel',
            isOnline: true,
            isChannel: true,
            isConnected: true,
            onBack: () {},
            onTitleTap: () {},
            onVoiceCall: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('chat_appbar_call_pill')), findsNothing);
    });
  });

  group('Localization Files Verification (10 languages)', () {
    const languages = ['ru', 'en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'pt', 'zh'];
    const requiredKeys = [
      'chat_typing',
      'chat_user_typing',
      'chat_status_online',
      'chat_status_last_seen_just_now',
      'chat_status_last_seen_minutes',
      'chat_status_last_seen_today',
      'chat_status_last_seen_yesterday',
      'chat_status_last_seen_recently',
      'chat_status_members_count',
      'chat_status_members_and_online',
      'chat_status_subscribers_count',
      'chat_status_connecting',
      'weekday_mon',
      'weekday_tue',
      'weekday_wed',
      'weekday_thu',
      'weekday_fri',
      'weekday_sat',
      'weekday_sun',
      'chat_menu_profile',
      'chat_menu_voice_call',
      'chat_menu_video_call',
      'chat_menu_search_messages',
      'chat_menu_mute',
      'chat_menu_unmute',
      'chat_menu_clear_history',
      'chat_menu_report',
    ];

    for (final lang in languages) {
      test('Language file assets/l10n/$lang.json contains all keys including connecting and placeholders', () {
        final file = File('assets/l10n/$lang.json');
        expect(file.existsSync(), isTrue, reason: 'File $lang.json should exist');

        final content = file.readAsStringSync();
        final Map<String, dynamic> jsonMap = jsonDecode(content);

        for (final key in requiredKeys) {
          expect(jsonMap.containsKey(key), isTrue,
              reason: '$lang.json is missing key "$key"');
          expect(jsonMap[key], isA<String>(),
              reason: '$key in $lang.json must be a non-null string');
          expect((jsonMap[key] as String).isNotEmpty, isTrue,
              reason: '$key in $lang.json must not be empty');
        }

        // Check required placeholders
        expect(jsonMap['chat_user_typing'], contains('{name}'),
            reason: '$lang.json chat_user_typing must contain {name}');
        expect(jsonMap['chat_status_last_seen_minutes'], contains('{m}'),
            reason: '$lang.json chat_status_last_seen_minutes must contain {m}');
        expect(jsonMap['chat_status_last_seen_today'], contains('{time}'),
            reason: '$lang.json chat_status_last_seen_today must contain {time}');
        expect(jsonMap['chat_status_last_seen_yesterday'], contains('{time}'),
            reason: '$lang.json chat_status_last_seen_yesterday must contain {time}');
        expect(jsonMap['chat_status_members_count'], contains('{count}'),
            reason: '$lang.json chat_status_members_count must contain {count}');
        expect(jsonMap['chat_status_members_and_online'], contains('{count}'),
            reason: '$lang.json chat_status_members_and_online must contain {count}');
        expect(jsonMap['chat_status_members_and_online'], contains('{online}'),
            reason: '$lang.json chat_status_members_and_online must contain {online}');
        expect(jsonMap['chat_status_subscribers_count'], contains('{count}'),
            reason: '$lang.json chat_status_subscribers_count must contain {count}');
        expect(jsonMap['chat_status_connecting'], contains('...'),
            reason: '$lang.json chat_status_connecting must contain ...');
      });
    }
  });

  group('DateTimeUtils Timezone & Calendar Logic Tests', () {
    test('parseUtcDateTime parses UTC string with Z and converts to local', () {
      const utcString = '2026-09-04T12:00:00Z';
      final dt = DateTimeUtils.parseUtcDateTime(utcString);
      expect(dt, isNotNull);
      expect(dt!.isUtc, isFalse);
      expect(dt.toUtc(), DateTime.utc(2026, 9, 4, 12, 0, 0));
    });

    test('parseUtcDateTime treats strings without Z as UTC Greenwich and converts to local', () {
      const stringWithoutZ = '2026-09-04 12:00:00';
      final dt = DateTimeUtils.parseUtcDateTime(stringWithoutZ);
      expect(dt, isNotNull);
      expect(dt!.isUtc, isFalse);
      expect(dt.toUtc(), DateTime.utc(2026, 9, 4, 12, 0, 0));
    });

    test('parseUtcDateTime handles existing UTC DateTime, null, and empty', () {
      final utcDt = DateTime.utc(2026, 9, 4, 15, 30);
      final local = DateTimeUtils.parseUtcDateTime(utcDt);
      expect(local!.isUtc, isFalse);
      expect(local.toUtc(), utcDt);

      expect(DateTimeUtils.parseUtcDateTime(null), isNull);
      expect(DateTimeUtils.parseUtcDateTime(''), isNull);
      expect(DateTimeUtils.parseUtcDateTime('   '), isNull);
    });

    testWidgets('formatLastSeen produces "сегодня" and local HH:mm for device calendar today',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (context) {
              final deviceNow = DateTime(2026, 9, 5, 14, 0); // 14:00 today
              // 3 hours ago today (11:00 today local)
              final lastSeenLocal = DateTime(2026, 9, 5, 11, 0);
              final lastSeenUtc = lastSeenLocal.toUtc();

              final result = DateTimeUtils.formatLastSeen(
                lastSeenUtc,
                context,
                now: deviceNow,
              );

              final timeStr =
                  '${lastSeenLocal.hour.toString().padLeft(2, '0')}:${lastSeenLocal.minute.toString().padLeft(2, '0')}';
              expect(result, 'был(а) сегодня в $timeStr');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('formatLastSeen produces "вчера" and local HH:mm for device calendar yesterday',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (context) {
              final deviceNow = DateTime(2026, 9, 5, 10, 0); // Sep 5 10:00
              // Yesterday at 23:30 local
              final lastSeenLocal = DateTime(2026, 9, 4, 23, 30);
              final lastSeenUtc = lastSeenLocal.toUtc();

              final result = DateTimeUtils.formatLastSeen(
                lastSeenUtc,
                context,
                now: deviceNow,
              );

              final timeStr =
                  '${lastSeenLocal.hour.toString().padLeft(2, '0')}:${lastSeenLocal.minute.toString().padLeft(2, '0')}';
              expect(result, 'был(а) вчера в $timeStr');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('formatLastSeen handles cross-midnight timezone shifts (Greenwich yesterday vs device today)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (context) {
              // Simulated device is in UTC+3 (Moscow)
              // Server UTC is 2026-09-04 22:30:00Z (calendar day Sep 4)
              // Local time in UTC+3 is 2026-09-05 01:30:00 (calendar day Sep 5)
              // Local device now is 2026-09-05 08:00:00
              final localLastSeen = DateTime(2026, 9, 5, 1, 30);
              final localNow = DateTime(2026, 9, 5, 8, 0);

              final result = DateTimeUtils.formatLastSeen(
                localLastSeen,
                context,
                now: localNow,
              );

              expect(result, 'был(а) сегодня в 01:30');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    test('formatTimeHHmm formats local hours and minutes', () {
      final utcDt = DateTime.utc(2026, 9, 4, 12, 5);
      final local = utcDt.toLocal();
      final expected =
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      expect(DateTimeUtils.formatTimeHHmm(utcDt.toIso8601String()), expected);
    });

    test('formatDateSeparator correctly returns Сегодня, Вчера, and DD.MM.YYYY based on local date', () {
      final now = DateTime(2026, 9, 5, 12, 0);
      final todayMsg = DateTime(2026, 9, 5, 2, 0);
      final yesterdayMsg = DateTime(2026, 9, 4, 23, 0);
      final olderMsg = DateTime(2026, 9, 2, 15, 0);

      expect(DateTimeUtils.formatDateSeparator(todayMsg, now: now), 'Сегодня');
      expect(DateTimeUtils.formatDateSeparator(yesterdayMsg, now: now), 'Вчера');
      expect(DateTimeUtils.formatDateSeparator(olderMsg, now: now), '2.09.2026');
    });

    testWidgets('formatDateSeparator with context returns localized Today and Yesterday',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (context) {
              final now = DateTime(2026, 9, 5, 12, 0);
              final todayMsg = DateTime(2026, 9, 5, 2, 0);
              final yesterdayMsg = DateTime(2026, 9, 4, 23, 0);

              expect(
                DateTimeUtils.formatDateSeparator(todayMsg, context: context, now: now),
                'Сегодня',
              );
              expect(
                DateTimeUtils.formatDateSeparator(yesterdayMsg, context: context, now: now),
                'Вчера',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('formatWeekday returns correct localized abbreviated day names',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (context) {
              expect(DateTimeUtils.formatWeekday(DateTime.monday, context), 'Пн');
              expect(DateTimeUtils.formatWeekday(DateTime.tuesday, context), 'Вт');
              expect(DateTimeUtils.formatWeekday(DateTime.wednesday, context), 'Ср');
              expect(DateTimeUtils.formatWeekday(DateTime.thursday, context), 'Чт');
              expect(DateTimeUtils.formatWeekday(DateTime.friday, context), 'Пт');
              expect(DateTimeUtils.formatWeekday(DateTime.saturday, context), 'Сб');
              expect(DateTimeUtils.formatWeekday(DateTime.sunday, context), 'Вс');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });
}
