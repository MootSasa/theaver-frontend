import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:theaver/services/bot_service.dart';
import 'package:theaver/services/browser_data_service.dart';
import 'package:theaver/services/mini_app_js_bridge.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/utils/link_opener.dart';
import 'package:theaver/widgets/bot/mini_app_webview_sheet.dart';
import 'package:theaver/widgets/bot/thv_invoice_sheet.dart';
import 'package:theaver/widgets/browser/in_app_browser_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BrowserDataService.instance.resetForTesting();
    MiniAppSessionController.instance.closeAllMinimized();
    LinkOpener.debugForceInAppSupportedForTest = false;
    LinkOpener.debugExternalLauncherForTest = null;
    await SettingsService().init();
  });

  tearDown(() {
    MiniAppSessionController.instance.closeAllMinimized();
    BrowserDataService.instance.resetForTesting();
    LinkOpener.debugForceInAppSupportedForTest = false;
    LinkOpener.debugExternalLauncherForTest = null;
  });

  group('In-App Browser Settings & Local Data', () {
    test('SettingsService inAppBrowser defaults to true, updates notifier, and persists', () async {
      final settings = SettingsService();
      expect(settings.inAppBrowser, isTrue);
      expect(settings.inAppBrowserNotifier.value, isTrue);

      await settings.setInAppBrowser(false);
      expect(settings.inAppBrowser, isFalse);
      expect(settings.inAppBrowserNotifier.value, isFalse);

      await settings.init();
      expect(settings.inAppBrowser, isFalse);

      await settings.setInAppBrowser(true);
      expect(settings.inAppBrowser, isTrue);
    });

    test('BrowserDataService bookmarks, history, and clearHistoryAndCookies preserve bookmarks', () async {
      final svc = BrowserDataService.instance;
      await svc.ensureLoaded(forceReload: true);

      final added = await svc.toggleBookmark(
        'https://docs.theaver.app/api',
        'Theaver API Docs',
      );
      expect(added, isTrue);
      expect(svc.isBookmarked('https://docs.theaver.app/api'), isTrue);
      expect(svc.bookmarks.length, 1);

      await svc.recordVisit('https://example.com/news', 'Example News');
      await svc.recordVisit('https://docs.theaver.app/api', 'Theaver API Docs');
      expect(svc.history.length, 2);
      expect(svc.history.first.url, 'https://docs.theaver.app/api');

      await svc.clearHistoryAndCookies();
      expect(svc.history, isEmpty);
      expect(svc.bookmarks.length, 1);
      expect(svc.isBookmarked('https://docs.theaver.app/api'), isTrue);

      final removed = await svc.toggleBookmark(
        'https://docs.theaver.app/api',
        'Theaver API Docs',
      );
      expect(removed, isFalse);
      expect(svc.bookmarks, isEmpty);
    });
  });

  group('LinkOpener & InAppBrowserSheet Integration', () {
    testWidgets('LinkOpener opens InAppBrowserSheet when enabled, minimizes to dock, coexists in 3D tabs, and restores', (tester) async {
      LinkOpener.debugForceInAppSupportedForTest = true;
      Uri? launchedExternal;
      LinkOpener.debugExternalLauncherForTest = (uri) async {
        launchedExternal = uri;
      };

      final navKey = GlobalKey<NavigatorState>();
      late BuildContext homeCtx;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          builder: (context, child) => MinimizedMiniAppHost(
            navigatorKey: navKey,
            child: child ?? const SizedBox.shrink(),
          ),
          home: Builder(
            builder: (context) {
              homeCtx = context;
              return const Scaffold(
                body: Center(child: Text('Home Screen')),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Non-HTTP scheme bypasses InAppBrowserSheet even when inAppBrowser == true
      await LinkOpener.openUrl(homeCtx, 'mailto:support@theaver.app');
      expect(launchedExternal?.scheme, 'mailto');
      expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsNothing);
      launchedExternal = null;

      // 2. HTTP(S) link opens InAppBrowserSheet
      unawaited(LinkOpener.openUrl(homeCtx, 'https://example.org/docs'));
      await tester.pumpAndSettle();

      expect(find.byType(InAppBrowserSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsOneWidget);
      expect(find.byType(WebViewFloatingHeader), findsOneWidget);
      expect(find.byKey(const ValueKey('in_app_browser_bottom_bar')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('in_app_browser_bottom_bar')).evaluate().single.widget,
        isA<WebViewFloatingCapsule>(),
      );
      expect(find.text('example.org'), findsWidgets);
      expect(launchedExternal, isNull);

      // 2b. Tapping 3-dots morphs the browser menu inside WebViewFloatingHeader, tapping outside closes it
      await tester.tap(find.byKey(const ValueKey('in_app_browser_menu_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final morphMidSize = tester.getSize(
        find.byKey(const ValueKey('webview_right_matte_morph')),
      );
      expect(morphMidSize.width, greaterThan(88.0));
      expect(morphMidSize.width, lessThan(252.0));
      expect(morphMidSize.height, greaterThan(44.0));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(WebViewFloatingHeader),
          matching: find.byKey(const ValueKey('in_app_browser_overflow_menu')),
        ),
        findsOneWidget,
      );
      await tester.tapAt(tester.getCenter(find.byType(InAppBrowserSheet)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('in_app_browser_overflow_menu')),
        findsNothing,
      );

      // 2c. Tapping center title pill opens MiniAppTabsSwitcher with preview content for the browser tab
      await tester.tap(find.byKey(const ValueKey('webview_header_center_pill')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mini_app_tabs_switcher')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>)
                  .value
                  .startsWith('mini_app_tab_preview_'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('example.org').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('mini_app_tabs_switcher')), findsNothing);

      // 3. Minimize browser tab into bottom dock
      await tester.tap(find.byKey(const ValueKey('in_app_browser_minimize_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsNothing);
      expect(find.byKey(const ValueKey('minimized_mini_app_dock_region')), findsOneWidget);
      expect(find.text('example.org'), findsOneWidget);

      // 4. Coexist with a minimized @walt Mini App in the same dock & open 3D switcher
      final waltSession = MiniAppSession(
        launchData: const MiniAppLaunchData(
          url: 'https://api.theaver.app/api/miniapps/wallet',
          initData: 'hash=walt',
          botId: '2',
          botUsername: 'walt',
          botDisplayName: 'Walt',
          botIsVerified: true,
        ),
        botName: 'Walt',
        botUsername: 'walt',
        isVerified: true,
      );
      MiniAppSessionController.instance.minimize(
        waltSession,
        navigator: navKey.currentState,
      );
      await tester.pumpAndSettle();

      expect(find.text('Walt'), findsOneWidget);
      expect(find.byKey(const ValueKey('minimized_mini_app_extra_count')), findsOneWidget);
      expect(find.text(' и ещё 1'), findsOneWidget);

      // Tap minimized bar -> opens 3D MiniAppTabsSwitcher showing both browser tab and @walt
      await tester.tap(find.byKey(const ValueKey('minimized_mini_app_bar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mini_app_tabs_switcher')), findsOneWidget);
      expect(find.text('Закрыть все вкладки'), findsOneWidget);
      expect(find.text('example.org'), findsWidgets);
      expect(find.text('Walt'), findsWidgets);

      // Tap browser card to restore InAppBrowserSheet directly
      await tester.tap(find.text('example.org').first);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('mini_app_tabs_switcher')), findsNothing);

      // Close restored browser sheet
      await tester.tap(find.byKey(const ValueKey('in_app_browser_close_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsNothing);
    });

    testWidgets('LinkOpener uses external launcher when inAppBrowser setting is false', (tester) async {
      LinkOpener.debugForceInAppSupportedForTest = true;
      await SettingsService().setInAppBrowser(false);

      Uri? launchedExternal;
      LinkOpener.debugExternalLauncherForTest = (uri) async {
        launchedExternal = uri;
      };

      late BuildContext homeCtx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              homeCtx = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      await LinkOpener.openUrl(homeCtx, 'https://example.com/path');
      await tester.pumpAndSettle();

      expect(launchedExternal.toString(), 'https://example.com/path');
      expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsNothing);
    });
  });

  group('THV Invoices & @walt Mini App Bridge', () {
    test('extractThvInvoiceSlug parses slug, API URL, and theaver:// deeplink', () {
      expect(extractThvInvoiceSlug('inv_abc123_XYZ'), 'inv_abc123_XYZ');
      expect(
        extractThvInvoiceSlug('https://api.theaver.app/api/invoices/inv_pay_42'),
        'inv_pay_42',
      );
      expect(
        extractThvInvoiceSlug('/api/invoices/inv_rel_777'),
        'inv_rel_777',
      );
      expect(
        extractThvInvoiceSlug('theaver://invoice/inv_deep_999'),
        'inv_deep_999',
      );
      expect(extractThvInvoiceSlug('https://example.com/normal'), isNull);
    });

    test('MiniAppJsBridge injects Telegram.WebApp.openInvoice and web_app_open_invoice', () {
      const launch = MiniAppLaunchData(
        url: 'https://api.theaver.app/api/miniapps/wallet',
        initData: 'auth_date=1&hash=h',
        botId: '2',
        botUsername: 'walt',
        botDisplayName: 'Walt',
      );
      final js = MiniAppJsBridge.buildInjectionScript(
        launch,
        MiniAppJsBridge.buildThemeParams(ThemeData.dark()),
        colorScheme: 'dark',
        viewportHeight: 720,
        topClearance: 88,
        bottomClearance: 64,
      );
      expect(js, contains('openInvoice'));
      expect(js, contains('web_app_open_invoice'));
      expect(js, contains('invoiceClosed'));
      expect(js, contains('--theaver-header-clearance'));
      expect(js, contains('--theaver-bottom-clearance'));
      expect(js, contains('theaver_webapp_ready'));
    });

    test('MiniAppSession.updateLoadProgress throttles sub-2% updates and preserves bounds', () {
      final session = MiniAppSession(
        launchData: const MiniAppLaunchData(
          url: 'https://example.com',
          initData: '',
        ),
        isBrowser: true,
      );
      var notifications = 0;
      session.loadProgressNotifier.addListener(() => notifications++);

      session.updateLoadProgress(10);
      expect(session.loadProgress, closeTo(0.10, 0.001));
      expect(notifications, 1);

      // Sub-2% step is suppressed to prevent unnecessary rebuild ticks.
      session.updateLoadProgress(11);
      expect(session.loadProgress, closeTo(0.10, 0.001));
      expect(notifications, 1);

      // >= 2% delta or 100% boundary propagates immediately.
      session.updateLoadProgress(12);
      expect(session.loadProgress, closeTo(0.12, 0.001));
      expect(notifications, 2);

      session.updateLoadProgress(100);
      expect(session.loadProgress, 1.0);
      expect(notifications, 3);
    });

    testWidgets('MiniAppWebViewSheet renders verified seal for @walt', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MiniAppWebViewSheet(
              launchData: MiniAppLaunchData(
                url: 'https://api.theaver.app/api/miniapps/wallet',
                initData: 'hash=walt',
                botId: '2',
                botUsername: 'walt',
                botDisplayName: 'Walt',
              ),
              botName: 'Walt',
              botUsername: 'walt',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MiniAppVerifiedSeal), findsOneWidget);
      expect(find.text('@walt • mini app'), findsOneWidget);
    });

    test('MiniAppSession.buildBrowserSafeInsetsScript & applyBrowserPageMetaPayload offset pinned controls without caps', () {
      final js = MiniAppSession.buildBrowserSafeInsetsScript(
        topPx: 82,
        bottomPx: 80,
        flutterViewportHeight: 800,
      );
      expect(js, contains('window.__theaverTopClear = 82;'));
      expect(js, contains('window.__theaverBottomClear = 80;'));
      expect(js, contains('window.__theaverFlutterVh = 800;'));
      expect(js, contains('window.__theaverSyncSafeZones(82, 80, 800)'));
      expect(js, contains('--theaver-header-clearance'));
      expect(js, contains('--theaver-bottom-clearance'));
      expect(js, contains('--tg-safe-area-inset-top'));
      expect(js, contains('--tg-safe-area-inset-bottom'));
      expect(js, contains('scroll-padding-top:'));
      expect(js, contains('scroll-padding-bottom:'));
      expect(js, contains('getEffectiveSize'));
      expect(js, contains('offsetHeight'));
      expect(js, contains('theaverScrollContainerPt'));
      expect(js, contains('deferredTopBars'));
      expect(js, contains('deferredBottomBars'));
      expect(js, contains("'top-pinned'"));
      expect(js, contains("'bottom-pinned'"));
      expect(js, contains("'top-abs'"));
      expect(js, contains("'bottom-abs'"));
      expect(js, contains("'full-drawer'"));
      expect(js, contains('takeRecords'));
      expect(js, contains('TheaverBrowserTheme'));
      expect(js, isNot(contains("visibility === 'hidden'")));
      expect(js, isNot(contains('__theaver_top_cap')));
      expect(js, isNot(contains('__theaver_bottom_cap')));

      final session = MiniAppSession(
        launchData: const MiniAppLaunchData(
          url: 'https://dzen.ru/',
          initData: '',
        ),
        isBrowser: true,
      );
      int sheetChanges = 0;
      session.onSheetStateChanged = () => sheetChanges++;

      // Double-encoded string mirrors Android WebView runJavaScriptReturningResult output.
      session.applyBrowserPageMetaPayload(
        r'"{\"topIsDark\":true,\"canvasColor\":\"rgb(239, 240, 242)\"}"',
      );
      expect(session.browserTopIsDark, isTrue);
      expect(session.browserCanvasColor, const Color(0xFFEFF0F2));
      expect(sheetChanges, 1);

      // Identical payload must be deduplicated without triggering extra rebuilds.
      session.applyBrowserPageMetaPayload(
        '{"topIsDark":true,"canvasColor":"rgb(239, 240, 242)"}',
      );
      expect(sheetChanges, 1);

      // Luminance transition notifies once.
      session.applyBrowserPageMetaPayload(
        '{"topIsDark":false,"canvasColor":"rgb(255, 255, 255)"}',
      );
      expect(session.browserTopIsDark, isFalse);
      expect(session.browserCanvasColor, const Color(0xFFFFFFFF));
      expect(sheetChanges, 2);
    });

    testWidgets(
      'InAppBrowserSheet keeps body edge-to-edge without bars and dynamically updates browserTopClearance',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final session = MiniAppSession(
          launchData: const MiniAppLaunchData(
            url: 'https://dzen.ru/',
            initData: '',
          ),
          isBrowser: true,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(400, 800),
                padding: EdgeInsets.only(top: 24, bottom: 16),
              ),
              child: InAppBrowserSheet(session: session),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('in_app_browser_top_cap')), findsNothing);
        expect(find.byKey(const ValueKey('in_app_browser_bottom_cap')), findsNothing);
        expect(find.byKey(const ValueKey('in_app_browser_safe_viewport')), findsNothing);

        final sheetFinder = find.byKey(const ValueKey('in_app_browser_sheet'));
        expect(tester.getRect(sheetFinder), const Rect.fromLTWH(0, 0, 400, 800));
        final sheetStack = tester.widget<Stack>(
          find.descendant(of: sheetFinder, matching: find.byType(Stack)).first,
        );
        final firstLayer = sheetStack.children.first as Positioned;
        expect(firstLayer.left, 0.0);
        expect(firstLayer.right, 0.0);
        expect(firstLayer.top, 0.0);
        expect(firstLayer.bottom, 0.0);
        expect(
          tester.getRect(find.byWidget(firstLayer)),
          const Rect.fromLTWH(0, 0, 400, 800),
        );

        expect(session.browserTopClearance, closeTo(82.0, 0.01));
        expect(session.browserBottomClearance, closeTo(80.0, 0.01));
        expect(session.browserViewportHeight, closeTo(800.0, 0.01));

        // Opening Find-in-Page lowers top clearance below the find capsule.
        await tester.tap(find.byKey(const ValueKey('in_app_browser_menu_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Найти на странице'));
        await tester.pumpAndSettle();

        expect(session.browserTopClearance, closeTo(134.0, 0.01));

        // Closing Find-in-Page restores normal top clearance.
        final findCapsuleFinder = find.ancestor(
          of: find.byType(TextField),
          matching: find.byType(WebViewFloatingCapsule),
        );
        final findBarCloseFinder = find.descendant(
          of: findCapsuleFinder,
          matching: find.byIcon(Icons.close_rounded),
        );
        await tester.tap(findBarCloseFinder);
        await tester.pumpAndSettle();
        expect(session.browserTopClearance, closeTo(82.0, 0.01));
      },
    );
  });
}
