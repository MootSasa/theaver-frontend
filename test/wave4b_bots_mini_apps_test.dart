import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:theaver/services/bot_service.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/mini_app_js_bridge.dart';
import 'package:theaver/widgets/bot/inline_results_popup.dart';
import 'package:theaver/widgets/bot/mini_app_webview_sheet.dart';
import 'package:theaver/widgets/chat/bot_welcome_card.dart';
import 'package:theaver/widgets/chat/reply_keyboard_panel.dart';
import 'package:theaver/widgets/message/inline_keyboard_widget.dart';

void main() {
  group('Wave 4B Models & Parsers', () {
    test('BotInfo.fromJson parses Wave 4A mini app and metadata fields', () {
      final info = BotInfo.fromJson({
        'bot_info': {
          'id': '42',
          'username': 'shop_bot',
          'display_name': 'Shop Assistant',
          'about_text': 'Fast mini shop',
          'description': 'Detailed desc',
          'can_join_groups': true,
          'can_read_all_group_messages': false,
          'supports_inline_queries': true,
          'inline_placeholder': 'Search catalog...',
          'menu_button': {
            'type': 'web_app',
            'text': 'Магазин',
            'web_app': {'url': 'https://shop.theaver.app/mini'},
          },
          'main_app_url': 'https://shop.theaver.app/main',
          'has_main_web_app': true,
          'supports_inline_feedback': true,
          'short_name': 'shop',
          'web_apps': [
            {
              'short_name': 'orders',
              'title': 'Мои заказы',
              'description': 'История заказов',
              'url': 'https://shop.theaver.app/orders',
            },
          ],
          'commands': [
            {'command': '/start', 'description': 'Start bot'},
          ],
        },
      });

      expect(info.userId, '42');
      expect(info.username, 'shop_bot');
      expect(info.about, 'Fast mini shop');
      expect(info.menuButton.isWebApp, isTrue);
      expect(info.menuButton.text, 'Магазин');
      expect(info.effectiveWebAppUrl, 'https://shop.theaver.app/mini');
      expect(info.hasMainWebApp, isTrue);
      expect(info.supportsInlineFeedback, isTrue);
      expect(info.shortName, 'shop');
      expect(info.webApps.length, 1);
      expect(info.webApps.first.shortName, 'orders');
      expect(info.commands.length, 1);
      expect(info.commands.first.slashCommand, '/start');
    });

    test('BotInlineQueryResponse & parseInlineBotInput parse @bot queries', () {
      final parsed1 = BotService.parseInlineBotInput('@gif_bot funny cats');
      expect(parsed1, isNotNull);
      expect(parsed1!.botUsername, 'gif_bot');
      expect(parsed1.query, 'funny cats');

      final parsed2 = BotService.parseInlineBotInput('@wiki_bot ');
      expect(parsed2, isNotNull);
      expect(parsed2!.botUsername, 'wiki_bot');
      expect(parsed2.query, '');

      expect(BotService.parseInlineBotInput('@ab short'), isNull);
      expect(BotService.parseInlineBotInput('hello world'), isNull);

      final res = BotInlineQueryResponse.fromJson({
        'inline_query_id': 'iq_123',
        'next_offset': '20',
        'button': {
          'text': 'Open Mini App',
          'web_app': {'url': 'https://mini.theaver.app'},
        },
        'results': [
          {
            'id': 'r1',
            'type': 'article',
            'title': 'Article Title',
            'description': 'Desc',
            'input_message_content': {
              'message_text': '<b>Formatted</b>',
              'parse_mode': 'HTML',
            },
          },
          {
            'id': 'r2',
            'type': 'photo',
            'photo_url': 'https://cdn.example.com/p.jpg',
            'caption': 'Sunset',
          },
        ],
      }, botId: '88');

      expect(res.inlineQueryId, 'iq_123');
      expect(res.nextOffset, '20');
      expect(res.button?.text, 'Open Mini App');
      expect(res.button?.webAppUrl, 'https://mini.theaver.app');
      expect(res.results.length, 2);
      expect(res.results[0].resolvedMessageType, 'text');
      expect(res.results[0].resolvedContent, '<b>Formatted</b>');
      expect(res.results[1].resolvedMessageType, 'image');
      expect(res.results[1].resolvedFileUrl, 'https://cdn.example.com/p.jpg');
      expect(res.results[1].isVisualTile, isTrue);
    });

    test('Message getters expose viaBot and webAppData fields', () {
      final msg = Message.fromJson({
        'id': '100',
        'chat_id': '5',
        'sender_id': '7',
        'content': 'Via bot result',
        'message_type': 'text',
        'created_at': '2026-11-19T12:00:00Z',
        'via_bot_id': '42',
        'via_bot_username': 'gif_bot',
        'media_payload': {
          'web_app_data': {'data': '{"item":1}', 'button_text': 'Buy'},
        },
      });

      expect(msg.isViaBot, isTrue);
      expect(msg.viaBotId, '42');
      expect(msg.viaBotUsername, 'gif_bot');
      expect(msg.hasWebAppData, isTrue);
      expect(msg.webAppData?['data'], '{"item":1}');
    });

    test('MiniAppJsBridge builds theme params, injection script, and parses messages', () {
      final theme = ThemeData.dark();
      final tp = MiniAppJsBridge.buildThemeParams(theme);
      expect(tp['bg_color'], startsWith('#'));
      expect(tp['button_color']?.length, 7);

      const launch = MiniAppLaunchData(
        url: 'https://mini.theaver.app',
        initData: 'auth_date=12345&hash=abcdef',
        initDataUnsafe: {'auth_date': 12345},
        queryId: 'q_1',
        version: '7.10',
        botId: '42',
        botUsername: 'shop_bot',
      );
      final js = MiniAppJsBridge.buildInjectionScript(
        launch,
        tp,
        colorScheme: 'dark',
        viewportHeight: 640,
      );
      expect(js, contains('window.Telegram.WebApp'));
      expect(js, contains('MainButton'));
      expect(js, contains('SecondaryButton'));
      expect(js, contains('BackButton'));
      expect(js, contains('CloudStorage'));
      expect(js, contains('HapticFeedback'));
      expect(js, contains('requestWriteAccess'));
      expect(js, contains('sendData'));
      expect(js, contains('auth_date=12345&hash=abcdef'));

      final evt = MiniAppJsBridge.parseBridgeMessage(
        '{"eventType":"web_app_setup_main_button","eventData":{"is_visible":true,"text":"Pay"},"reqId":"r1"}',
      );
      expect(evt, isNotNull);
      expect(evt!.eventType, 'web_app_setup_main_button');
      expect(evt.eventData['is_visible'], isTrue);
      expect(evt.eventData['text'], 'Pay');
      expect(evt.reqId, 'r1');
    });
  });

  group('Wave 4B Widgets', () {
    testWidgets('MiniAppWebViewSheet renders safely without native WebViewPlatform', (tester) async {
      expect(WebViewPlatform.instance, isNull);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MiniAppWebViewSheet(
              launchData: MiniAppLaunchData(
                url: 'https://mini.theaver.app/shop',
                initData: 'hash=test',
                botId: '42',
                botUsername: 'shop_bot',
                botDisplayName: 'Shop Bot',
              ),
              botName: 'Shop Bot',
              botUsername: 'shop_bot',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shop Bot'), findsWidgets);
      expect(find.text('@shop_bot • mini app'), findsOneWidget);
      expect(find.text('Открыть в браузере'), findsOneWidget);
    });

    testWidgets('InlineKeyboardWidget handles web_app and switch_inline_query', (tester) async {
      String? openedUrl;
      String? openedBtn;
      String? insertedQuery;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineKeyboardWidget(
              chatId: '5',
              messageId: '10',
              botId: '42',
              botUsername: 'shop_bot',
              rows: const [
                [
                  {
                    'text': 'Open App',
                    'web_app': {'url': 'https://shop.theaver.app'},
                  },
                  {
                    'text': 'Search Inline',
                    'switch_inline_query_current_chat': 'shoes',
                  },
                ],
              ],
              onOpenWebApp: (u, btnText) {
                openedUrl = u;
                openedBtn = btnText;
              },
              onInsertText: (q) => insertedQuery = q,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open App'));
      expect(openedUrl, 'https://shop.theaver.app');
      expect(openedBtn, 'Open App');

      await tester.tap(find.text('Search Inline'));
      expect(insertedQuery, '@shop_bot shoes');
    });

    testWidgets('ReplyKeyboardPanel dispatches onButtonAction for special buttons', (tester) async {
      Map<String, dynamic>? specialAction;
      String? plainText;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReplyKeyboardPanel(
              isOpen: true,
              rows: const [
                [
                  {'text': 'Geo', 'request_location': true},
                  {'text': 'Plain'},
                ],
              ],
              onButtonPressed: (t) => plainText = t,
              onButtonAction: (btn) => specialAction = btn,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Geo'));
      expect(specialAction?['request_location'], isTrue);
      expect(plainText, isNull);

      await tester.tap(find.text('Plain'));
      expect(plainText, 'Plain');
    });

    testWidgets('InlineResultsPopup displays header button, articles, and invokes selection', (tester) async {
      BotInlineResult? selected;
      BotInlineResultsButton? tappedHeader;

      const resp = BotInlineQueryResponse(
        inlineQueryId: 'q1',
        botId: '42',
        button: BotInlineResultsButton(
          text: 'Open Dashboard',
          webAppUrl: 'https://dash.theaver.app',
        ),
        results: [
          BotInlineResult(
            id: 'a1',
            type: 'article',
            title: 'Weather Today',
            description: '+22°C Sunny',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineResultsPopup(
              botUsername: 'weather_bot',
              query: 'moscow',
              response: resp,
              onSelectResult: (r) => selected = r,
              onTapHeaderButton: (b) => tappedHeader = b,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dashboard'));
      expect(tappedHeader?.webAppUrl, 'https://dash.theaver.app');

      await tester.tap(find.text('Weather Today'));
      expect(selected?.id, 'a1');
    });

    testWidgets('BotWelcomeCard and BotStartBar render onOpenMainApp actions', (tester) async {
      var welcomeOpened = false;
      var barOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: BotWelcomeCard(
                    botName: 'Shop Bot',
                    onCommandTap: (_) {},
                    onOpenMainApp: () => welcomeOpened = true,
                    openAppLabel: 'Магазин',
                  ),
                ),
                BotStartBar(
                  onStartPressed: () {},
                  onOpenMainApp: () => barOpened = true,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Магазин'));
      expect(welcomeOpened, isTrue);

      await tester.tap(find.text('Приложение'));
      expect(barOpened, isTrue);
    });
  });
}
