import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/services/bot_service.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/deep_link_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/mini_app_js_bridge.dart';
import 'package:theaver/widgets/bot/inline_results_popup.dart';
import 'package:theaver/widgets/bot/mini_app_chat_picker_sheet.dart';
import 'package:theaver/widgets/bot/mini_app_webview_sheet.dart';
import 'package:theaver/widgets/chat/bot_welcome_card.dart';
import 'package:theaver/widgets/chat/reply_keyboard_panel.dart';
import 'package:theaver/widgets/message/inline_keyboard_widget.dart';
import 'package:theaver/widgets/message/message_bubble.dart';

class _TestAppLocalizations extends AppLocalizations {
  _TestAppLocalizations(super.locale);

  @override
  String translate(String key, [Map<String, String>? params]) => key;
}

class _TestAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _TestAppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      _TestAppLocalizations(locale);

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

class _TestGlassProvider extends LiquidGlassProvider {
  @override
  GlassMode get mode => GlassMode.disabled;

  @override
  bool get enabled => false;

  @override
  bool get isLite => false;

  @override
  bool get isFull => false;
}

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
        version: '8.0',
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
      expect(js, contains('BottomButton'));
      expect(js, contains('SecondaryButton'));
      expect(js, contains('BackButton'));
      expect(js, contains('CloudStorage'));
      expect(js, contains('HapticFeedback'));
      expect(js, contains('BiometricManager'));
      expect(js, contains('LocationManager'));
      expect(js, contains('showScanQrPopup'));
      expect(js, contains('Accelerometer'));
      expect(js, contains('Gyroscope'));
      expect(js, contains('DeviceOrientation'));
      expect(js, contains('requestFullscreen'));
      expect(js, contains('lockOrientation'));
      expect(js, contains('downloadFile'));
      expect(js, contains('shareMessage'));
      expect(js, contains('shareToStory'));
      expect(js, contains('addToHomeScreen'));
      expect(js, contains('setEmojiStatus'));
      expect(js, contains('TelegramWebviewProxy'));
      expect(js, contains('receiveEvent'));
      expect(js, contains('requestWriteAccess'));
      expect(js, contains('sendData'));
      expect(js, contains('auth_date=12345&hash=abcdef'));
      expect(MiniAppJsBridge.isVersionAtLeast('8.0', '7.10'), isTrue);
      expect(MiniAppJsBridge.isVersionAtLeast('8.0', '8.0'), isTrue);
      expect(MiniAppJsBridge.isVersionAtLeast('7.10', '8.0'), isFalse);

      final launchUri = MiniAppJsBridge.buildLaunchUriWithHashParams(
        'https://mini.theaver.app/shop#/cart',
        initData: 'auth_date=12345&hash=abcdef',
        themeParams: tp,
        platform: 'android',
      );
      expect(launchUri.fragment, startsWith('/cart?'));
      expect(launchUri.fragment, contains('tgWebAppData='));
      expect(launchUri.fragment, contains('tgWebAppVersion=8.0'));

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

  group('Mini Apps v8.0 Deep Links, Pickers, WebAppData & Closing Confirmation', () {
    test('DeepLinkService.parseUri resolves Mini App startapp and invoice deep links', () {
      final tgResolve = DeepLinkService.parseUri(
        Uri.parse('tg://resolve?domain=shop_bot&appname=shop&startapp=ref_42'),
      );
      expect(tgResolve?.type, DeepLinkType.miniApp);
      expect(tgResolve?.botUsername, 'shop_bot');
      expect(tgResolve?.appShortName, 'shop');
      expect(tgResolve?.startParam, 'ref_42');

      final shortPath = DeepLinkService.parseUri(
        Uri.parse('https://t.me/shop_bot/orders?startapp=ord_9'),
      );
      expect(shortPath?.type, DeepLinkType.miniApp);
      expect(shortPath?.botUsername, 'shop_bot');
      expect(shortPath?.appShortName, 'orders');
      expect(shortPath?.startParam, 'ord_9');

      final directApp = DeepLinkService.parseUri(
        Uri.parse('https://theaver.app/walt?startapp=pay_alice_TON_5'),
      );
      expect(directApp?.type, DeepLinkType.miniApp);
      expect(directApp?.botUsername, 'walt');
      expect(directApp?.startParam, 'pay_alice_TON_5');

      final webInvoice = DeepLinkService.parseUri(
        Uri.parse('https://theaver.app/invoice/inv_abc123'),
      );
      expect(webInvoice?.type, DeepLinkType.invoice);
      expect(webInvoice?.invoiceSlug, 'inv_abc123');

      final tgInvoice = DeepLinkService.parseUri(
        Uri.parse('tg://invoice?slug=inv_xyz999'),
      );
      expect(tgInvoice?.type, DeepLinkType.invoice);
      expect(tgInvoice?.invoiceSlug, 'inv_xyz999');
    });

    test('DeepLinkService.resolveAllowedChatTypes handles both top-level booleans and chat_types lists', () {
      final topLevel = DeepLinkService.resolveAllowedChatTypes({
        'allow_user_chats': true,
        'allow_bot_chats': false,
        'allow_group_chats': false,
        'allow_channel_chats': true,
      });
      expect(topLevel.allowUsers, isTrue);
      expect(topLevel.allowBots, isFalse);
      expect(topLevel.allowGroups, isFalse);
      expect(topLevel.allowChannels, isTrue);

      final listBased = DeepLinkService.resolveAllowedChatTypes(['groups', 'channels']);
      expect(listBased.allowUsers, isFalse);
      expect(listBased.allowBots, isFalse);
      expect(listBased.allowGroups, isTrue);
      expect(listBased.allowChannels, isTrue);
    });

    testWidgets('MessageBubble renders web_app_data badge instead of blank bubble', (tester) async {
      final msg = Message(
        id: 'm_wad_1',
        chatId: 'c_1',
        senderId: 'me',
        content: '',
        messageType: 'text',
        isEdited: false,
        createdAt: '2026-11-22T12:00:00Z',
        senderName: 'Me',
        mediaPayload: const {
          'web_app_data': {
            'button_text': 'Checkout',
            'data': '{"order_id":99}',
          },
        },
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<LiquidGlassProvider>.value(
          value: _TestGlassProvider(),
          child: MaterialApp(
            localizationsDelegates: const [
              _TestAppLocalizationsDelegate(),
              DefaultMaterialLocalizations.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            home: Scaffold(
              body: MessageBubble(
                message: msg,
                isMe: true,
                currentUserId: 'me',
                formatTime: (_) => '12:00',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Данные Mini App: Checkout'), findsOneWidget);
      expect(find.text('{"order_id":99}'), findsOneWidget);
    });

    testWidgets('showMiniAppChatPickerSheet filters peer types and returns chosen chatId', (tester) async {
      late BuildContext hostCtx;
      final chats = <Chat>[
        Chat(
          id: 'u1',
          chatType: 'private',
          name: 'Alice',
          updatedAt: '2026-11-22T12:00:00Z',
        ),
        Chat(
          id: 'g1',
          chatType: 'group',
          name: 'Devs Group',
          updatedAt: '2026-11-22T12:00:00Z',
        ),
        Chat(
          id: 'ch1',
          chatType: 'channel',
          name: 'Release Channel',
          updatedAt: '2026-11-22T12:00:00Z',
        ),
      ];

      await tester.pumpWidget(
        ChangeNotifierProvider<LiquidGlassProvider>.value(
          value: _TestGlassProvider(),
          child: MaterialApp(
            home: Builder(
              builder: (ctx) {
                hostCtx = ctx;
                return const Scaffold(body: SizedBox.expand());
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      String? picked;
      unawaited(
        showMiniAppChatPickerSheet(
          hostCtx,
          allowGroupChats: false,
          allowChannelChats: false,
          debugChatsOverride: chats,
        ).then((v) => picked = v),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Devs Group'), findsNothing);
      expect(find.text('Release Channel'), findsNothing);

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      expect(picked, 'u1');
    });

    testWidgets('MiniAppTabsSwitcher confirms closing when closingConfirmation is true', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = MiniAppSession(
        id: 'confirm_close_tab',
        launchData: const MiniAppLaunchData(
          url: 'https://mini.theaver.app/checkout',
          initData: 'hash=test',
          botId: '42',
          botUsername: 'shop_bot',
          botDisplayName: 'Shop Bot',
        ),
        botName: 'Shop Bot',
        botUsername: 'shop_bot',
      )..closingConfirmation = true;

      var closedCount = 0;
      await tester.pumpWidget(
        ChangeNotifierProvider<LiquidGlassProvider>.value(
          value: _TestGlassProvider(),
          child: MaterialApp(
            home: Scaffold(
              body: MiniAppTabsSwitcher(
                sessions: [session],
                onDismiss: () {},
                onSelectSession: (_) {},
                onCloseSession: (_) => closedCount++,
                onCloseAll: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const ValueKey('mini_app_tab_dismiss_confirm_close_tab')),
        const Offset(-350, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Закрыть Mini App?'), findsOneWidget);
      await tester.tap(find.text('Остаться'));
      await tester.pumpAndSettle();
      expect(closedCount, 0);
      expect(
        find.byKey(const ValueKey('mini_app_tab_card_confirm_close_tab')),
        findsOneWidget,
      );
    });
  });
}
