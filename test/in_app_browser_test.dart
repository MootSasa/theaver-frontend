import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:theaver/services/bot_service.dart';
import 'package:theaver/services/browser_data_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/mini_app_js_bridge.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/utils/link_opener.dart';
import 'package:theaver/widgets/bot/mini_app_webview_sheet.dart';
import 'package:theaver/widgets/bot/thv_invoice_sheet.dart';
import 'package:theaver/widgets/browser/in_app_browser_sheet.dart';
import 'package:theaver/widgets/design_system/theav_design_system.dart';

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

    test('MiniAppSession.buildBrowserSafeInsetsScript & applyBrowserPageMetaPayload support Safari iOS 26 scroll pocket and collapse', () {
      final js = MiniAppSession.buildBrowserSafeInsetsScript(
        topPx: 82,
        compactTopPx: 56,
        bottomPx: 80,
        compactBottomPx: 16,
        flutterViewportHeight: 800,
      );
      expect(js, contains('window.__theaverTopClear = 82;'));
      expect(js, contains('window.__theaverCompactTopClear = 56;'));
      expect(js, contains('window.__theaverBottomClear = 80;'));
      expect(js, contains('window.__theaverCompactBottomClear = 16;'));
      expect(js, contains('window.__theaverFlutterVh = 800;'));
      expect(js, contains('window.__theaverSyncSafeZones('));
      expect(js, contains('--theaver-top-obscured'));
      expect(js, contains('--theaver-safe-bottom'));
      expect(js, contains('--theaver-header-clearance'));
      expect(js, contains('--theaver-bottom-clearance'));
      expect(js, contains('--tg-safe-area-inset-top'));
      expect(js, contains('--tg-safe-area-inset-bottom'));
      expect(js, contains('safe-area-inset-bottom'));
      expect(js, contains('__theaverSetCollapsedFromHost'));
      expect(js, contains('elementsFromPoint'));
      expect(js, contains('scroll-padding-top:'));
      expect(js, contains('scroll-padding-bottom:'));
      expect(js, contains('getEffectiveSize'));
      expect(js, contains('offsetHeight'));
      expect(js, contains('parseTransformTy'));
      expect(js, contains('getTargetTranslateY'));
      expect(js, contains('getAnimations'));
      expect(js, contains('isPinnedElementHiding'));
      expect(js, contains('applyPinnedOffset'));
      expect(js, contains('transitionrun'));
      expect(js, contains('__theaverRefreshTrackedPinned'));
      expect(js, contains('theaverScrollContainerPt'));
      expect(js, contains("'top-pinned'"));
      expect(js, contains('takeRecords'));
      expect(js, contains('TheaverBrowserTheme'));
      expect(js, isNot(contains("visibility === 'hidden'")));
      expect(js, isNot(contains('__theaver_top_cap')));
      expect(js, isNot(contains('__theaver_bottom_cap')));
      expect(js, isNot(contains("'bottom-pinned'")));
      expect(js, isNot(contains("'top-abs'")));
      expect(js, isNot(contains("'bottom-abs'")));
      expect(js, isNot(contains("'full-drawer'")));
      expect(js, isNot(contains('deferredBottomBars')));

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
        r'"{\"collapsed\":true,\"topIsDark\":true,\"topColor\":\"rgb(32, 32, 34)\",\"bottomColor\":\"rgb(24, 24, 26)\",\"canvasColor\":\"rgb(24, 24, 26)\"}"',
      );
      expect(session.browserChromeCollapsed, isTrue);
      expect(session.browserTopIsDark, isTrue);
      expect(session.browserTopPocketColor, const Color(0xFF202022));
      expect(session.browserBottomPocketColor, const Color(0xFF18181A));
      expect(session.browserCanvasColor, const Color(0xFF18181A));
      expect(sheetChanges, 1);

      // Identical payload must be deduplicated without triggering extra rebuilds.
      session.applyBrowserPageMetaPayload(
        '{"collapsed":true,"topIsDark":true,"topColor":"rgb(32, 32, 34)","bottomColor":"rgb(24, 24, 26)","canvasColor":"rgb(24, 24, 26)"}',
      );
      expect(sheetChanges, 1);

      // Collapse + luminance/color transition notifies once.
      session.applyBrowserPageMetaPayload(
        '{"collapsed":false,"topIsDark":false,"topColor":"rgb(255, 255, 255)","bottomColor":"rgb(239, 240, 242)","canvasColor":"rgb(239, 240, 242)"}',
      );
      expect(session.browserChromeCollapsed, isFalse);
      expect(session.browserTopIsDark, isFalse);
      expect(session.browserTopPocketColor, const Color(0xFFFFFFFF));
      expect(session.browserBottomPocketColor, const Color(0xFFEFF0F2));
      expect(session.browserCanvasColor, const Color(0xFFEFF0F2));
      expect(sheetChanges, 2);
    });

    testWidgets(
      'InAppBrowserSheet keeps body edge-to-edge with scroll pockets and dynamically updates browserTopClearance',
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
        expect(find.byKey(const ValueKey('in_app_browser_top_scroll_pocket')), findsOneWidget);
        expect(find.byKey(const ValueKey('in_app_browser_bottom_scroll_pocket')), findsOneWidget);

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
        expect(session.browserCompactTopClearance, closeTo(62.0, 0.01));
        expect(session.browserBottomClearance, closeTo(80.0, 0.01));
        expect(session.browserCompactBottomClearance, closeTo(16.0, 0.01));
        expect(session.browserViewportHeight, closeTo(800.0, 0.01));
        expect(session.browserForceExpanded, isFalse);

        // Opening Find-in-Page lowers top clearance below the find capsule and forces expanded chrome.
        await tester.tap(find.byKey(const ValueKey('in_app_browser_menu_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Найти на странице'));
        await tester.pumpAndSettle();

        expect(session.browserTopClearance, closeTo(134.0, 0.01));
        expect(session.browserForceExpanded, isTrue);

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
        expect(session.browserForceExpanded, isFalse);
      },
    );

    testWidgets(
      'InAppBrowserSheet morphs 3 top capsules into compact domain pill and hides bottom bar on downward scroll, expanding on domain tap',
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
        )..pageTitle = 'Дзен — главная новость дня и очень длинный заголовок статьи';
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

        // Expanded initial state: 3 top capsules + bottom navigation capsule.
        expect(find.byKey(const ValueKey('in_app_browser_close_button')), findsOneWidget);
        expect(find.byKey(const ValueKey('in_app_browser_minimize_button')), findsOneWidget);
        expect(find.byKey(const ValueKey('in_app_browser_menu_button')), findsOneWidget);
        final Size expandedSize = tester.getSize(
          find.byKey(const ValueKey('webview_header_center_pill')),
        );
        expect(expandedSize.height, closeTo(44.0, 0.5));
        expect(expandedSize.width, greaterThan(180.0));
        final State centerMatteState = tester.state(
          find.byKey(const ValueKey('webview_center_matte_morph')),
        );
        expect(
          tester
              .widget<IgnorePointer>(
                find.byKey(const ValueKey('in_app_browser_bottom_bar_ignore')),
              )
              .ignoring,
          isFalse,
        );
        expect(find.byKey(const ValueKey('in_app_browser_bottom_bar')), findsOneWidget);

        // Downward scroll continuously morphs both width & height toward compact domain pill.
        session.applyBrowserPageMetaPayload(
          '{"collapsed":true,"topIsDark":false,"topColor":"rgb(239, 240, 242)","bottomColor":"rgb(239, 240, 242)","canvasColor":"rgb(239, 240, 242)"}',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));

        expect(
          identical(
            tester.state(find.byKey(const ValueKey('webview_center_matte_morph'))),
            centerMatteState,
          ),
          isTrue,
        );
        final Size midSize = tester.getSize(
          find.byKey(const ValueKey('webview_header_center_pill')),
        );
        expect(midSize.height, greaterThan(26.5));
        expect(midSize.height, lessThan(43.5));
        expect(midSize.width, lessThan(expandedSize.width - 10.0));
        expect(midSize.width, greaterThan(110.0));

        await tester.pumpAndSettle();

        expect(session.browserChromeCollapsed, isTrue);
        expect(session.browserTopPocketColor, const Color(0xFFEFF0F2));
        expect(
          tester
              .widget<IgnorePointer>(
                find.byKey(const ValueKey('in_app_browser_bottom_bar_ignore')),
              )
              .ignoring,
          isTrue,
        );
        expect(
          tester
              .widget<IgnorePointer>(
                find.byKey(const ValueKey('webview_header_left_ignore')),
              )
              .ignoring,
          isTrue,
        );
        expect(
          tester
              .widget<IgnorePointer>(
                find.byKey(const ValueKey('webview_header_right_ignore')),
              )
              .ignoring,
          isTrue,
        );
        expect(find.byKey(const ValueKey('in_app_browser_minimize_button')), findsNothing);
        expect(find.byKey(const ValueKey('in_app_browser_menu_button')), findsNothing);
        expect(find.byKey(const ValueKey('in_app_browser_close_button')), findsNothing);
        expect(find.byKey(const ValueKey('in_app_browser_compact_domain')), findsOneWidget);
        final Size compactSize = tester.getSize(
          find.byKey(const ValueKey('webview_header_center_pill')),
        );
        expect(compactSize.height, closeTo(26.0, 0.5));
        expect(compactSize.width, lessThan(midSize.width));
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('webview_header_center_pill')))
              .dy,
          closeTo(32.0, 0.5),
        );

        // Tapping compact center domain pill morphs back to all 3 top capsules & bottom bar.
        await tester.tap(find.byKey(const ValueKey('webview_header_center_pill')));
        await tester.pumpAndSettle();

        expect(
          identical(
            tester.state(find.byKey(const ValueKey('webview_center_matte_morph'))),
            centerMatteState,
          ),
          isTrue,
        );
        expect(session.browserChromeCollapsed, isFalse);
        expect(find.byKey(const ValueKey('in_app_browser_close_button')), findsOneWidget);
        expect(find.byKey(const ValueKey('in_app_browser_minimize_button')), findsOneWidget);
        expect(find.byKey(const ValueKey('in_app_browser_menu_button')), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('webview_header_center_pill'))).height,
          closeTo(44.0, 0.5),
        );
        expect(
          tester
              .widget<IgnorePointer>(
                find.byKey(const ValueKey('in_app_browser_bottom_bar_ignore')),
              )
              .ignoring,
          isFalse,
        );

        // Overflow menu morph still opens smoothly after expanding back.
        await tester.tap(find.byKey(const ValueKey('in_app_browser_menu_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('in_app_browser_overflow_menu')), findsOneWidget);
      },
    );

    testWidgets(
      'InAppBrowserSheet uses continuous LiquidGlassMorph center pill in Glass mode',
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
        )..pageTitle = 'Дзен — главная лента новостей и статей';

        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: _TestLiquidGlassProvider(GlassMode.full),
            child: MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(400, 800),
                  padding: EdgeInsets.only(top: 24, bottom: 16),
                ),
                child: InAppBrowserSheet(session: session),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final centerMorphFinder = find.byKey(const ValueKey('webview_center_morph'));
        expect(centerMorphFinder, findsOneWidget);
        expect(find.byType(LiquidGlassMorph), findsNWidgets(2));
        final centerMorphWidget = tester.widget<LiquidGlassMorph>(centerMorphFinder);
        expect(centerMorphWidget.motion.blended, isFalse);
        expect(centerMorphWidget.smoothness, 0);
        final centerLensFinder = find.descendant(
          of: centerMorphFinder,
          matching: find.byType(LiquidGlassLens),
        );
        expect(centerLensFinder, findsOneWidget);
        expect(tester.getRect(centerLensFinder).top, closeTo(32.0, 0.5));
        expect(tester.getRect(centerLensFinder).height, closeTo(44.0, 0.5));
        final State glassMorphState = tester.state(centerMorphFinder);

        session.applyBrowserPageMetaPayload(
          '{"collapsed":true,"topIsDark":false,"topColor":"rgb(255, 255, 255)","bottomColor":"rgb(255, 255, 255)","canvasColor":"rgb(255, 255, 255)"}',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(identical(tester.state(centerMorphFinder), glassMorphState), isTrue);
        expect(centerLensFinder, findsOneWidget);
        final Rect collapseFrame60 = tester.getRect(centerLensFinder);
        expect(collapseFrame60.top, closeTo(32.0, 0.5));
        expect(collapseFrame60.height, inInclusiveRange(25.9, 44.1));

        await tester.pump(const Duration(milliseconds: 90));
        expect(centerLensFinder, findsOneWidget);
        final Rect collapseFrame150 = tester.getRect(centerLensFinder);
        expect(collapseFrame150.top, closeTo(32.0, 0.5));
        expect(collapseFrame150.height, inInclusiveRange(25.9, 44.1));

        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('in_app_browser_compact_domain')), findsOneWidget);
        expect(centerLensFinder, findsOneWidget);
        final Rect compactLensRect = tester.getRect(centerLensFinder);
        expect(compactLensRect.top, closeTo(32.0, 0.5));
        expect(compactLensRect.height, closeTo(26.0, 0.5));
        expect(
          tester.getSize(find.byKey(const ValueKey('webview_header_center_pill'))).height,
          closeTo(26.0, 0.5),
        );

        await tester.tap(find.byKey(const ValueKey('webview_header_center_pill')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(identical(tester.state(centerMorphFinder), glassMorphState), isTrue);
        expect(centerLensFinder, findsOneWidget);
        final Rect expandFrame60 = tester.getRect(centerLensFinder);
        expect(expandFrame60.top, closeTo(32.0, 0.5));
        expect(expandFrame60.height, inInclusiveRange(25.9, 44.1));

        await tester.pump(const Duration(milliseconds: 90));
        expect(centerLensFinder, findsOneWidget);
        final Rect expandFrame150 = tester.getRect(centerLensFinder);
        expect(expandFrame150.top, closeTo(32.0, 0.5));
        expect(expandFrame150.height, inInclusiveRange(25.9, 44.1));

        await tester.pumpAndSettle();
        expect(identical(tester.state(centerMorphFinder), glassMorphState), isTrue);
        expect(session.browserChromeCollapsed, isFalse);
        expect(centerLensFinder, findsOneWidget);
        final Rect expandedLensRect = tester.getRect(centerLensFinder);
        expect(expandedLensRect.top, closeTo(32.0, 0.5));
        expect(expandedLensRect.height, closeTo(44.0, 0.5));
        expect(
          tester.getSize(find.byKey(const ValueKey('webview_header_center_pill'))).height,
          closeTo(44.0, 0.5),
        );
      },
    );

    testWidgets(
      'InAppBrowserSheet center LiquidGlassMorph never freezes under rapid up-down scroll reversals',
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
        )..pageTitle = 'Дзен — длинный заголовок новости для морфинга капсулы';

        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: _TestLiquidGlassProvider(GlassMode.full),
            child: MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(400, 800),
                  padding: EdgeInsets.only(top: 24, bottom: 16),
                ),
                child: InAppBrowserSheet(session: session),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final centerMorphFinder = find.byKey(const ValueKey('webview_center_morph'));
        final centerLensFinder = find.descendant(
          of: centerMorphFinder,
          matching: find.byType(LiquidGlassLens),
        );
        final State glassMorphState = tester.state(centerMorphFinder);

        void pushCollapsed(bool collapsed) {
          session.applyBrowserPageMetaPayload(
            '{"collapsed":$collapsed,"topIsDark":false,"topColor":"rgb(255, 255, 255)","bottomColor":"rgb(255, 255, 255)","canvasColor":"rgb(255, 255, 255)"}',
          );
        }

        // 1. Mid-flight reversal while outgoing expanded child is still alive (~50ms):
        // collapse -> reverse back up before contentOutEnd -> settle -> collapse again.
        pushCollapsed(true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        pushCollapsed(false);
        await tester.pumpAndSettle();
        expect(identical(tester.state(centerMorphFinder), glassMorphState), isTrue);
        expect(tester.getRect(centerLensFinder).height, closeTo(44.0, 0.5));

        pushCollapsed(true);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('in_app_browser_compact_domain')), findsOneWidget);
        expect(tester.getRect(centerLensFinder).height, closeTo(26.0, 0.5));
        expect(tester.getRect(centerLensFinder).top, closeTo(32.0, 0.5));

        // Tap compact capsule to expand back cleanly.
        await tester.tap(find.byKey(const ValueKey('webview_header_center_pill')));
        await tester.pumpAndSettle();
        expect(tester.getRect(centerLensFinder).height, closeTo(44.0, 0.5));

        // 2. Single-frame / pre-measurement bounce (collapse -> 1 frame -> expand -> collapse).
        pushCollapsed(true);
        await tester.pump();
        pushCollapsed(false);
        await tester.pumpAndSettle();
        expect(tester.getRect(centerLensFinder).height, closeTo(44.0, 0.5));

        pushCollapsed(true);
        await tester.pumpAndSettle();
        expect(tester.getRect(centerLensFinder).height, closeTo(26.0, 0.5));

        // 3. Rapid 8-step up-down scroll oscillation burst ending collapsed, then expanded.
        const delaysMs = <int>[25, 45, 30, 55, 20, 40, 35, 30];
        for (int i = 0; i < delaysMs.length; i++) {
          pushCollapsed(i.isEven ? false : true);
          await tester.pump();
          await tester.pump(Duration(milliseconds: delaysMs[i]));
        }
        pushCollapsed(true);
        await tester.pumpAndSettle();
        expect(identical(tester.state(centerMorphFinder), glassMorphState), isTrue);
        expect(find.byKey(const ValueKey('in_app_browser_compact_domain')), findsOneWidget);
        expect(tester.getRect(centerLensFinder).height, closeTo(26.0, 0.5));
        expect(tester.getRect(centerLensFinder).top, closeTo(32.0, 0.5));

        pushCollapsed(false);
        await tester.pumpAndSettle();
        expect(tester.getRect(centerLensFinder).height, closeTo(44.0, 0.5));
        expect(tester.getRect(centerLensFinder).top, closeTo(32.0, 0.5));
      },
    );

    testWidgets(
      'System Back performs web back without closing InAppBrowserSheet or MiniAppWebViewSheet; close button pops cleanly',
      (tester) async {
        LinkOpener.debugForceInAppSupportedForTest = true;

        late BuildContext homeCtx;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                homeCtx = context;
                return const Scaffold(body: Center(child: Text('HomeHost')));
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. InAppBrowserSheet: system Back navigates back/closes overlays and never closes browser.
        unawaited(LinkOpener.openUrl(homeCtx, 'https://dzen.ru/news'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsOneWidget);

        // Open menu -> Back closes menu only.
        await tester.tap(find.byKey(const ValueKey('in_app_browser_menu_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('in_app_browser_overflow_menu')), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('in_app_browser_overflow_menu')), findsNothing);
        expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsOneWidget);

        // Open Find-in-Page -> Back closes find bar only.
        await tester.tap(find.byKey(const ValueKey('in_app_browser_menu_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Найти на странице'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsOneWidget);

        // Simulate web history stack (`canGoBack = true`) -> Back goes back without closing.
        final browserWidget = tester.widget<InAppBrowserSheet>(
          find.byType(InAppBrowserSheet),
        );
        browserWidget.session.canGoBack = true;
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(browserWidget.session.canGoBack, isFalse);
        expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsOneWidget);

        // Even at root (`canGoBack == false`), system Back does NOT close the browser.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsOneWidget);

        // Tapping [x] closes the browser cleanly even if canGoBack == true.
        browserWidget.session.canGoBack = true;
        await tester.tap(find.byKey(const ValueKey('in_app_browser_close_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsNothing);
        expect(find.text('HomeHost'), findsOneWidget);

        // 2. MiniAppWebViewSheet: system Back triggers web back / back_button_pressed without closing Mini App.
        final miniSession = MiniAppSession(
          launchData: const MiniAppLaunchData(
            url: 'https://api.theaver.app/api/miniapps/wallet',
            initData: 'hash=walt',
            botId: '2',
            botUsername: 'walt',
            botDisplayName: 'Walt',
          ),
          botName: 'Walt',
          botUsername: 'walt',
        );
        miniSession.backButtonVisible = true;

        unawaited(
          showTheavModalSheet<void>(
            context: homeCtx,
            enableDrag: false,
            useRootNavigator: true,
            customSheetBuilder: (_) => MiniAppWebViewSheet(
              launchData: miniSession.launchData,
              botName: 'Walt',
              botUsername: 'walt',
              session: miniSession,
            ),
            builder: (_) => const SizedBox.shrink(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MiniAppWebViewSheet), findsOneWidget);

        // With Telegram BackButton visible -> system Back stays open.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MiniAppWebViewSheet), findsOneWidget);

        // With history canGoBack == true and backButtonVisible == false -> Back navigates back cleanly.
        miniSession.backButtonVisible = false;
        miniSession.canGoBack = true;
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(miniSession.canGoBack, isFalse);
        expect(find.byType(MiniAppWebViewSheet), findsOneWidget);

        // At root (backButtonVisible == false, canGoBack == false) -> system Back still keeps Mini App open.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MiniAppWebViewSheet), findsOneWidget);

        // Explicit close button [x] closes MiniAppWebViewSheet cleanly.
        await tester.tap(find.byKey(const ValueKey('mini_app_close_or_back_button')));
        await tester.pumpAndSettle();
        expect(find.byType(MiniAppWebViewSheet), findsNothing);
      },
    );
  });
}
