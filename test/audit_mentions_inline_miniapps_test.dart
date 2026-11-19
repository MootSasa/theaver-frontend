import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/services/bot_service.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/utils/entity_parser.dart';
import 'package:theaver/widgets/bot/inline_results_popup.dart';
import 'package:theaver/widgets/chat/floating_glass_app_bar.dart';
import 'package:theaver/widgets/chat/mention_and_bot_popup.dart';
import 'package:theaver/widgets/message/text_message_widget.dart';

void main() {
  group('EntityParser Mentions, Commands & Hashtags', () {
    test('detects @mention, /command, /command@bot, and #hashtag while skipping emails/urls/code', () {
      const raw =
          'Привет @ivan_dev! Запусти /start или /help@BotMother #theaver '
          'email user@example.com https://example.com/path#frag `/ignored`';
      final parsed = EntityParser.resolveMessageEntities(raw, null);

      final mentions =
          parsed.entities.where((e) => e.type == 'mention').toList();
      final commands =
          parsed.entities.where((e) => e.type == 'bot_command').toList();
      final hashtags =
          parsed.entities.where((e) => e.type == 'hashtag').toList();

      expect(
        mentions
            .map((e) => parsed.cleanText.substring(e.offset, e.offset + e.length))
            .toList(),
        equals(['@ivan_dev']),
      );
      expect(
        commands
            .map((e) => parsed.cleanText.substring(e.offset, e.offset + e.length))
            .toList(),
        equals(['/start', '/help@BotMother']),
      );
      expect(
        hashtags
            .map((e) => parsed.cleanText.substring(e.offset, e.offset + e.length))
            .toList(),
        equals(['#theaver']),
      );

      // round-trip toMarkdown must not inject markdown syntax for mention/command/hashtag
      expect(
        EntityParser.toMarkdown('Hi @ivan_dev /start #news', const [
          MessageEntity(type: 'mention', offset: 3, length: 9),
          MessageEntity(type: 'bot_command', offset: 13, length: 6),
          MessageEntity(type: 'hashtag', offset: 20, length: 5),
        ]),
        equals('Hi @ivan_dev /start #news'),
      );
    });
  });

  group('BotService.parseActiveMentionToken', () {
    test('extracts @ tokens at start and mid-message, rejecting emails', () {
      final atRoot = BotService.parseActiveMentionToken('@bot', 4);
      expect(atRoot, isNotNull);
      expect(atRoot!.query, 'bot');
      expect(atRoot.isAtMessageStart, isTrue);
      expect(atRoot.start, 0);
      expect(atRoot.end, 4);

      final bareAt = BotService.parseActiveMentionToken('@', 1);
      expect(bareAt, isNotNull);
      expect(bareAt!.query, '');
      expect(bareAt.isAtMessageStart, isTrue);

      final mid = BotService.parseActiveMentionToken('Привет @al пока', 10);
      expect(mid, isNotNull);
      expect(mid!.query, 'al');
      expect(mid.isAtMessageStart, isFalse);
      expect(mid.start, 7);
      expect(mid.end, 10);

      expect(BotService.parseActiveMentionToken('foo@bar.com', 7), isNull);
      expect(BotService.parseActiveMentionToken('hello world', 11), isNull);
      expect(BotService.parseActiveMentionToken('@ivan ', 6), isNull);
    });
  });

  group('InlineQueryController state transitions', () {
    test('dismisses cleanly on NOT_FOUND without showing error popup', () async {
      var calls = 0;
      final ctrl = InlineQueryController(
        debounceDuration: const Duration(milliseconds: 10),
        queryFetcher: ({
          required String botId,
          required String query,
          String? chatId,
          String? chatType,
          String offset = '',
        }) async {
          calls++;
          return BotInlineQueryResponse(
            botId: botId,
            errorCode: 'NOT_FOUND',
            errorMessage: 'Bot not found',
          );
        },
      );

      ctrl.onTextChanged('@alex hello', chatId: '1');
      expect(ctrl.isActive, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(calls, 1);
      expect(ctrl.isActive, isFalse);

      // Typing more text for the same dismissed human @alex does not re-trigger
      ctrl.onTextChanged('@alex hello world', chatId: '1');
      expect(ctrl.isActive, isFalse);
      expect(calls, 1);

      ctrl.dispose();
    });

    test('retains response state for BOT_INLINE_DISABLED and valid results', () async {
      final ctrl = InlineQueryController(
        debounceDuration: const Duration(milliseconds: 10),
        queryFetcher: ({
          required String botId,
          required String query,
          String? chatId,
          String? chatType,
          String offset = '',
        }) async {
          if (botId == 'noinline_bot') {
            return BotInlineQueryResponse(
              botId: botId,
              errorCode: 'BOT_INLINE_DISABLED',
            );
          }
          return const BotInlineQueryResponse(
            botId: 'BotMother',
            inlineQueryId: 'iq_1',
            results: [
              BotInlineResult(
                id: 'r1',
                type: 'article',
                title: 'Bot Studio',
                messageText: 'Open Studio',
              ),
            ],
          );
        },
      );

      ctrl.onTextChanged('@noinline_bot test', chatId: '1');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(ctrl.isActive, isTrue);
      expect(ctrl.response?.errorCode, 'BOT_INLINE_DISABLED');

      ctrl.onTextChanged('@BotMother studio', chatId: '1');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(ctrl.isActive, isTrue);
      expect(ctrl.response?.results.length, 1);
      expect(ctrl.response?.results.first.title, 'Bot Studio');

      ctrl.dispose();
    });
  });

  group('MentionAndBotPopup Widget', () {
    testWidgets('filters participants and inline bots and invokes callbacks',
        (tester) async {
      MentionCandidate? pickedMention;
      BotInfo? pickedBot;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MentionAndBotPopup(
              query: 'bot',
              isAtMessageStart: true,
              participants: const [
                MentionCandidate(
                  id: '10',
                  username: 'alex_dev',
                  displayName: 'Alex Dev',
                ),
                MentionCandidate(
                  id: '11',
                  username: 'helper_bot',
                  displayName: 'Helper Bot',
                  isBot: true,
                ),
              ],
              inlineBots: const [
                BotInfo(
                  userId: '1',
                  username: 'BotMother',
                  displayName: 'BotMother',
                  supportsInlineQueries: true,
                  inlinePlaceholder: 'Поиск Mini Apps',
                ),
              ],
              onSelectMention: (c) => pickedMention = c,
              onSelectInlineBot: (b) => pickedBot = b,
            ),
          ),
        ),
      );

      expect(find.text('BotMother'), findsOneWidget);
      expect(find.text('INLINE'), findsOneWidget);
      expect(find.text('Helper Bot'), findsOneWidget);
      expect(find.text('BOT'), findsOneWidget);
      expect(find.text('Alex Dev'), findsNothing);

      await tester.tap(find.text('BotMother'));
      expect(pickedBot?.username, 'BotMother');

      await tester.tap(find.text('Helper Bot'));
      expect(pickedMention?.username, 'helper_bot');
    });
  });

  group('TextMessageWidget interactive tokens', () {
    testWidgets('invokes onMentionTap, onCommandTap, and onHashtagTap',
        (tester) async {
      String? tappedMention;
      String? tappedCommand;
      String? tappedHashtag;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextMessageWidget(
              text: 'Напиши @BotMother или /newbot #studio',
              onMentionTap: (m) => tappedMention = m,
              onCommandTap: (c) => tappedCommand = c,
              onHashtagTap: (h) => tappedHashtag = h,
            ),
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      final rootSpan = richText.text as TextSpan;

      void visitSpan(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text == '@BotMother' && span.recognizer is TapGestureRecognizer) {
            (span.recognizer as TapGestureRecognizer).onTap?.call();
          } else if (span.text == '/newbot' && span.recognizer is TapGestureRecognizer) {
            (span.recognizer as TapGestureRecognizer).onTap?.call();
          } else if (span.text == '#studio' && span.recognizer is TapGestureRecognizer) {
            (span.recognizer as TapGestureRecognizer).onTap?.call();
          }
          span.children?.forEach(visitSpan);
        }
      }

      visitSpan(rootSpan);
      expect(tappedMention, 'BotMother');
      expect(tappedCommand, '/newbot');
      expect(tappedHashtag, '#studio');
    });
  });

  group('GlassChatMenu extraMenuItems', () {
    testWidgets('renders extraMenuItems and triggers callbacks', (tester) async {
      var statsTapped = false;
      final preloadedL10n = (await tester.runAsync(
        () => AppLocalizations.delegate.load(const Locale('ru')),
      ))!;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: [
            _PreloadedAppLocalizationsDelegate(preloadedL10n),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ru'), Locale('en')],
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    GlassChatMenu.show(
                      ctx,
                      isMuted: false,
                      onVoiceCall: () {},
                      onVideoCall: () {},
                      onSearch: () {},
                      onToggleMute: () {},
                      onClearHistory: () {},
                      onReport: () {},
                      onViewProfile: () {},
                      extraMenuItems: [
                        FloatingChatMenuItem(
                          label: 'Статистика канала',
                          iconBuilder: (c) => iconoir.StatsUpSquare(
                            color: c,
                            width: 20,
                            height: 20,
                          ),
                          onTap: () => statsTapped = true,
                        ),
                      ],
                    );
                  },
                  child: const Text('Open Menu'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Статистика канала'), findsOneWidget);
      await tester.tap(find.text('Статистика канала'));
      await tester.pumpAndSettle();
      expect(statsTapped, isTrue);
    });
  });
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
