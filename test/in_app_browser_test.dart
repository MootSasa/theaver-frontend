import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:theaver/services/bot_service.dart';
import 'package:theaver/services/browser_data_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/mini_app_js_bridge.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/utils/link_opener.dart';
import 'package:theaver/utils/safari_url_safety.dart';
import 'package:theaver/widgets/bot/mini_app_webview_sheet.dart';
import 'package:theaver/widgets/bot/thv_invoice_sheet.dart';
import 'package:theaver/widgets/browser/in_app_browser_sheet.dart';
import 'package:theaver/widgets/browser/safari_browser_dialogs.dart';
import 'package:theaver/widgets/browser/safari_library_sheet.dart';
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
      expect(js, contains('theaverAppliedTopMargin'));
      expect(js, contains('hasTrackedTopAncestor'));
      expect(js, contains('usesEnvBottomVar'));
      expect(js, contains('applyTopSheetInset'));
      expect(js, contains('collectSheetPanels'));
      expect(js, contains("'top-pinned'"));
      expect(js, contains("'top-sheet'"));
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
      'InAppBrowserSheet keeps body edge-to-edge with soft LiquidGlassScrollEdge scroll pockets and dynamically updates browserTopClearance',
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
        expect(find.byKey(const ValueKey('in_app_browser_web_viewport')), findsNothing);
        expect(find.byKey(const ValueKey('in_app_browser_top_scroll_pocket')), findsOneWidget);
        expect(find.byKey(const ValueKey('in_app_browser_bottom_scroll_pocket')), findsOneWidget);

        // Edge-to-edge full-screen web layer with soft gradient LiquidGlassScrollEdge pocket (no opaque stripe).
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

        final topPocketFinder = find.byKey(
          const ValueKey('in_app_browser_top_scroll_pocket'),
        );
        final LiquidGlassScrollEdge topEdge =
            tester.widget<LiquidGlassScrollEdge>(
          find.descendant(
            of: topPocketFinder,
            matching: find.byType(LiquidGlassScrollEdge),
          ),
        );
        expect(topEdge.style, LiquidGlassScrollEdgeStyle.soft);
        final topPocketBoxes = tester.widgetList<DecoratedBox>(
          find.descendant(
            of: topPocketFinder,
            matching: find.byType(DecoratedBox),
          ),
        );
        expect(topPocketBoxes, isNotEmpty);
        for (final box in topPocketBoxes) {
          final dec = box.decoration as BoxDecoration;
          expect(dec.border, isNull);
          expect(dec.gradient, isNotNull);
        }

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

  group('Safari iOS 26 Browser Alerts, Security Analysis & Site Info Popover', () {
    test('SafariUrlSafetyAnalyzer decodes Punycode, flags homographs, upgrades HTTP, and classifies schemes', () {
      final dzen = SafariUrlSafetyAnalyzer.analyzeUrl('https://dzen.ru/news');
      expect(dzen.securityLevel, SafariConnectionSecurityLevel.secureHttps);
      expect(dzen.isSuspiciousHomograph, isFalse);
      expect(dzen.displayHost, 'dzen.ru');

      final sslWarn = SafariUrlSafetyAnalyzer.analyzeUrl(
        'https://expired.badssl.com/',
        hasSslWarning: true,
      );
      expect(sslWarn.securityLevel, SafariConnectionSecurityLevel.sslCertificateWarning);

      final httpInfo = SafariUrlSafetyAnalyzer.analyzeUrl('http://neverssl.com/');
      expect(httpInfo.securityLevel, SafariConnectionSecurityLevel.insecureHttp);
      expect(
        SafariUrlSafetyAnalyzer.tryBuildHttpsUpgrade('http://neverssl.com:80/test?a=1#b'),
        'https://neverssl.com/test?a=1#b',
      );
      expect(
        SafariUrlSafetyAnalyzer.tryBuildHttpsUpgrade('https://dzen.ru/'),
        isNull,
      );

      final localInfo = SafariUrlSafetyAnalyzer.analyzeUrl('http://localhost:8080/app');
      expect(localInfo.securityLevel, SafariConnectionSecurityLevel.secureHttps);

      final yandexRu = SafariUrlSafetyAnalyzer.analyzeUrl('https://xn--d1acpjx3f.xn--p1ai/');
      expect(yandexRu.isInternationalized, isTrue);
      expect(yandexRu.unicodeHost, 'яндекс.рф');
      expect(yandexRu.isSuspiciousHomograph, isFalse);

      final mixedHomograph = SafariUrlSafetyAnalyzer.analyzeUrl('https://xn--pple-43d.com/');
      expect(mixedHomograph.unicodeHost, 'аpple.com');
      expect(mixedHomograph.isSuspiciousHomograph, isTrue);

      final lookalikeAllCyrillic = SafariUrlSafetyAnalyzer.analyzeUrl('https://xn--80ak6aa92e.com/');
      expect(lookalikeAllCyrillic.unicodeHost, 'аррӏе.com');
      expect(lookalikeAllCyrillic.isSuspiciousHomograph, isTrue);

      expect(
        SafariUrlSafetyAnalyzer.classifyExternalUri(Uri.parse('tel:+79991112233')).kind,
        ExternalSchemeKind.tel,
      );
      expect(
        SafariUrlSafetyAnalyzer.classifyExternalUri(Uri.parse('mailto:a@b.ru')).kind,
        ExternalSchemeKind.mailto,
      );
      expect(
        SafariUrlSafetyAnalyzer.classifyExternalUri(Uri.parse('tg://resolve?domain=theaver')).kind,
        ExternalSchemeKind.telegram,
      );
      expect(
        SafariUrlSafetyAnalyzer.classifyExternalUri(Uri.parse('intent://scan/#Intent')).kind,
        ExternalSchemeKind.appIntent,
      );
      expect(
        SafariUrlSafetyAnalyzer.classifyExternalUri(Uri.parse('javascript:alert(1)')).kind,
        ExternalSchemeKind.blocked,
      );
    });

    testWidgets(
      'showSafariWebAlert uses LiquidGlassLens without Fade/Opacity in GlassMode.full and handles JS, SSL, Auth, Permission, External prompts',
      (tester) async {
        late BuildContext hostCtx;
        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: _TestLiquidGlassProvider(GlassMode.full),
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  hostCtx = context;
                  return const Scaffold(body: SizedBox.shrink());
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. SSL Warning -> LiquidGlassLens with 0 BackdropFilter and 0 Opacity/FadeTransition ancestors.
        final Future<bool> sslFuture1 = showSafariSslWarningDialog(
          hostCtx,
          host: 'expired.badssl.com',
        );
        await tester.pumpAndSettle();

        final sslDialogFinder = find.byKey(const ValueKey('safari_ssl_warning_dialog'));
        expect(sslDialogFinder, findsOneWidget);
        final lensFinder = find.descendant(
          of: sslDialogFinder,
          matching: find.byType(LiquidGlassLens),
        );
        expect(lensFinder, findsOneWidget);
        expect(
          find.descendant(
            of: sslDialogFinder,
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
        );
        expect(
          find.ancestor(
            of: lensFinder,
            matching: find.byType(FadeTransition),
          ),
          findsNothing,
        );
        expect(
          find.ancestor(
            of: lensFinder,
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );

        await tester.tap(find.byKey(const ValueKey('safari_ssl_go_back_btn')));
        await tester.pumpAndSettle();
        expect(await sslFuture1, isFalse);

        final Future<bool> sslFuture2 = showSafariSslWarningDialog(
          hostCtx,
          host: 'expired.badssl.com',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('safari_ssl_proceed_btn')));
        await tester.pumpAndSettle();
        expect(await sslFuture2, isTrue);

        // 2. JS Prompt + Mute checkbox
        final promptFuture = showSafariJsPromptDialog(
          hostCtx,
          originHost: 'dzen.ru',
          isSecure: true,
          message: 'Введите код:',
          defaultText: '123',
          offerMuteOption: true,
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('safari_js_prompt_input')),
          '4242',
        );
        await tester.tap(find.byKey(const ValueKey('safari_js_mute_checkbox')));
        await tester.tap(find.byKey(const ValueKey('safari_js_prompt_ok_btn')));
        await tester.pumpAndSettle();
        final promptRes = await promptFuture;
        expect(promptRes.value, '4242');
        expect(promptRes.muteHost, isTrue);

        // 3. JS Confirm + Alert
        final confirmFuture = showSafariJsConfirmDialog(
          hostCtx,
          originHost: 'dzen.ru',
          isSecure: true,
          message: 'Удалить черновик?',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('safari_js_confirm_cancel_btn')));
        await tester.pumpAndSettle();
        expect((await confirmFuture).confirmed, isFalse);

        // 4. HTTP Auth
        final authFuture = showSafariHttpAuthDialog(
          hostCtx,
          host: 'intranet.example.com',
          realm: 'Staff Area',
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('safari_http_auth_user')),
          'admin',
        );
        await tester.enterText(
          find.byKey(const ValueKey('safari_http_auth_password')),
          'secret',
        );
        await tester.tap(find.byKey(const ValueKey('safari_http_auth_submit_btn')));
        await tester.pumpAndSettle();
        final authRes = await authFuture;
        expect(authRes, isNotNull);
        expect(authRes!.user, 'admin');
        expect(authRes.password, 'secret');

        // 5. Permission & External App prompts
        final permFuture = showSafariPermissionDialog(
          hostCtx,
          host: 'meet.example.com',
          types: const {
            WebViewPermissionResourceType.camera,
            WebViewPermissionResourceType.microphone,
          },
        );
        await tester.pumpAndSettle();
        expect(find.text('Доступ к камере и микрофону'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('safari_permission_allow_btn')));
        await tester.pumpAndSettle();
        expect(await permFuture, isTrue);

        final extFuture = showSafariExternalAppDialog(
          hostCtx,
          uri: Uri.parse('tel:+79990001122'),
          sourceHost: 'dzen.ru',
        );
        await tester.pumpAndSettle();
        expect(find.text('Позвонить по номеру?'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('safari_external_confirm_btn')));
        await tester.pumpAndSettle();
        expect(await extFuture, isTrue);
      },
    );

    testWidgets(
      'InAppBrowserSheet opens SafariSiteInfoPopover from security icon and menu, upgrades HTTP, and closes on Back without exiting browser',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final session = MiniAppSession(
          launchData: const MiniAppLaunchData(
            url: 'http://neverssl.com/login',
            initData: '',
          ),
          isBrowser: true,
        )..pageTitle = 'NeverSSL';

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

        // Tap warning badge in center pill -> opens Site Info Popover with HTTP warning & HTTPS upgrade.
        await tester.tap(
          find.byKey(const ValueKey('in_app_browser_security_badge_button')),
        );
        await tester.pumpAndSettle();

        final popoverFinder = find.byKey(const ValueKey('in_app_browser_site_info_popover'));
        expect(popoverFinder, findsOneWidget);
        expect(find.text('Соединение не защищено'), findsOneWidget);
        expect(find.byKey(const ValueKey('safari_site_info_upgrade_https')), findsOneWidget);

        // System Back dismisses only the popover and leaves browser open.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(popoverFinder, findsNothing);
        expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsOneWidget);

        // Re-open via overflow menu "Сведения о сайте" and tap HTTPS upgrade pill.
        await tester.tap(find.byKey(const ValueKey('in_app_browser_menu_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Сведения о сайте'));
        await tester.pumpAndSettle();
        expect(popoverFinder, findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('safari_site_info_upgrade_https')));
        await tester.pumpAndSettle();
        expect(popoverFinder, findsNothing);
        expect(session.currentUrl, 'https://neverssl.com/login');

        // Re-open on upgraded HTTPS page -> shows "Соединение защищено".
        await tester.tap(
          find.byKey(const ValueKey('in_app_browser_security_badge_button')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Соединение защищено'), findsOneWidget);
        expect(find.byKey(const ValueKey('safari_site_info_upgrade_https')), findsNothing);

        // When SSL warning is active on current page, popover displays SSL warning + reset button.
        session.currentPageHasSslWarning = true;
        session.acceptedSslWarningHosts.add('neverssl.com');
        session.onSheetStateChanged?.call();
        await tester.pumpAndSettle();
        expect(find.text('Сертификат не проверен'), findsOneWidget);
        expect(find.byKey(const ValueKey('safari_site_info_reset_permissions')), findsOneWidget);
      },
    );

    testWidgets(
      'LinkOpener warns on suspicious homograph domains and minimized MiniAppSession fails closed on JS/SSL requests',
      (tester) async {
        LinkOpener.debugForceInAppSupportedForTest = true;

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
        await tester.pumpAndSettle();

        // Suspicious homograph shows warning dialog; cancelling keeps InAppBrowserSheet closed.
        final openFuture = LinkOpener.openUrl(homeCtx, 'https://xn--pple-43d.com/');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('safari_suspicious_link_dialog')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('safari_suspicious_cancel_btn')));
        await tester.pumpAndSettle();
        await openFuture;
        expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsNothing);

        // Minimized MiniAppSession without active dialog delegate fails closed immediately.
        final minimized = MiniAppSession(
          launchData: const MiniAppLaunchData(
            url: 'https://example.org/',
            initData: '',
          ),
          isBrowser: true,
        )..isMinimized = true;

        expect(
          await minimized.handleJavaScriptConfirm(
            const JavaScriptConfirmDialogRequest(
              message: 'Confirm?',
              url: 'https://example.org/',
            ),
          ),
          isFalse,
        );
        expect(
          await minimized.handleJavaScriptPrompt(
            const JavaScriptTextInputDialogRequest(
              message: 'Prompt?',
              url: 'https://example.org/',
              defaultText: 'def',
            ),
          ),
          '',
        );

        final t0 = DateTime(2026, 11, 21, 12, 0, 0);
        expect(minimized.recordJsDialogAndShouldOfferMute(t0), isFalse);
        expect(
          minimized.recordJsDialogAndShouldOfferMute(
            t0.add(const Duration(milliseconds: 400)),
          ),
          isFalse,
        );
        expect(
          minimized.recordJsDialogAndShouldOfferMute(
            t0.add(const Duration(milliseconds: 900)),
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'InAppBrowserSheet downward header swipe hands off offset & velocity seamlessly without frame-0 jump',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        LinkOpener.debugForceInAppSupportedForTest = true;

        final navKey = GlobalKey<NavigatorState>();
        late BuildContext homeCtx;

        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: _TestLiquidGlassProvider(GlassMode.full),
            child: MaterialApp(
              navigatorKey: navKey,
              builder: (context, child) => MinimizedMiniAppHost(
                navigatorKey: navKey,
                child: child ?? const SizedBox.shrink(),
              ),
              home: Builder(
                builder: (context) {
                  homeCtx = context;
                  return const Scaffold(
                    body: Center(child: Text('HomeForSwipe')),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        unawaited(LinkOpener.openUrl(homeCtx, 'https://dzen.ru/'));
        await tester.pumpAndSettle();

        final sheetFinder = find.byKey(const ValueKey('in_app_browser_sheet'));
        final pillFinder = find.byKey(const ValueKey('webview_header_center_pill'));
        expect(sheetFinder, findsOneWidget);
        expect(pillFinder, findsOneWidget);
        expect(tester.getTopLeft(sheetFinder).dy, closeTo(0.0, 0.5));

        final Offset pillCenter = tester.getCenter(pillFinder);
        final TestGesture drag = await tester.startGesture(pillCenter);
        await drag.moveBy(
          const Offset(0.0, 20.0),
          timeStamp: const Duration(milliseconds: 16),
        );
        await drag.moveBy(
          const Offset(0.0, 55.0),
          timeStamp: const Duration(milliseconds: 32),
        );
        await drag.moveBy(
          const Offset(0.0, 55.0),
          timeStamp: const Duration(milliseconds: 48),
        );
        await tester.pump();

        final double draggedDy = tester.getTopLeft(sheetFinder).dy;
        expect(draggedDy, closeTo(110.0, 2.0));

        await drag.up();
        await tester.pump();

        // Route dismissal must continue directly from >= ~108px without snapping back to y=0.
        final double releaseFrameDy = tester.getTopLeft(sheetFinder).dy;
        expect(releaseFrameDy, greaterThanOrEqualTo(108.0));

        // Minimize dock bar starts appearing immediately without waiting on snapshot timeout.
        expect(
          find.byKey(const ValueKey('minimized_mini_app_bar')),
          findsOneWidget,
        );

        await tester.pumpAndSettle();
        expect(sheetFinder, findsNothing);
        expect(
          find.byKey(const ValueKey('minimized_mini_app_dock_region')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Popup overlays (SiteInfo popover, Safari alert, 3-dots menu, modal sheets) freeze webpage scrolling and interaction until dismissed',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        LinkOpener.debugForceInAppSupportedForTest = true;

        Uri? launchedExternal;
        const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(urlLauncherChannel, (call) async {
          if (call.method == 'launch' || call.method == 'launchUrl') {
            final args = call.arguments as Map?;
            final rawUrl = args?['url']?.toString();
            if (rawUrl != null) {
              launchedExternal = Uri.tryParse(rawUrl);
            }
            return true;
          }
          if (call.method == 'canLaunch') {
            return true;
          }
          return null;
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(urlLauncherChannel, null);
        });
        LinkOpener.debugExternalLauncherForTest = (uri) async {
          launchedExternal = uri;
        };

        final browserSession = MiniAppSession(
          launchData: const MiniAppLaunchData(
            url: 'https://dzen.ru/',
            initData: '',
          ),
          isBrowser: true,
        )..pageTitle = 'Дзен';

        late BuildContext hostCtx;
        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: _TestLiquidGlassProvider(GlassMode.full),
            child: MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(400, 800),
                  padding: EdgeInsets.only(top: 24, bottom: 16),
                ),
                child: Builder(
                  builder: (context) {
                    hostCtx = context;
                    return InAppBrowserSheet(session: browserSession);
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final guardFinder = find.byKey(
          const ValueKey('in_app_browser_web_interaction_guard'),
        );
        final pageActionBtnFinder = find.descendant(
          of: guardFinder,
          matching: find.text('Открыть во внешнем браузере'),
        );
        expect(guardFinder, findsOneWidget);
        expect(pageActionBtnFinder, findsOneWidget);
        expect(
          tester.widget<IgnorePointer>(guardFinder).ignoring,
          isFalse,
        );
        expect(browserSession.isWebPageInteractionLocked, isFalse);

        // 1. SiteInfo Popover locks page interaction, swallows drags, and blocks taps to page buttons.
        await tester.tap(
          find.byKey(const ValueKey('in_app_browser_security_badge_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('in_app_browser_site_info_popover')),
          findsOneWidget,
        );
        expect(
          tester.widget<IgnorePointer>(guardFinder).ignoring,
          isTrue,
        );
        expect(browserSession.isWebPageInteractionLocked, isTrue);

        // Dragging over the page area beneath the popover is absorbed and does NOT close popover.
        await tester.dragFrom(
          const Offset(24, 520),
          const Offset(0, -140),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('in_app_browser_site_info_popover')),
          findsOneWidget,
        );

        // Tapping outside (below the popover) hits the opaque backdrop and closes only the popover.
        await tester.tapAt(const Offset(200, 680));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('in_app_browser_site_info_popover')),
          findsNothing,
        );
        expect(launchedExternal, isNull);
        expect(
          tester.widget<IgnorePointer>(guardFinder).ignoring,
          isFalse,
        );
        expect(browserSession.isWebPageInteractionLocked, isFalse);

        // 2. Overflow menu locks page interaction until dismissed.
        await tester.tap(
          find.byKey(const ValueKey('in_app_browser_menu_button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('in_app_browser_overflow_menu')),
          findsOneWidget,
        );
        expect(
          tester.widget<IgnorePointer>(guardFinder).ignoring,
          isTrue,
        );
        expect(browserSession.isWebPageInteractionLocked, isTrue);

        await tester.tapAt(const Offset(24, 560));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('in_app_browser_overflow_menu')),
          findsNothing,
        );
        expect(launchedExternal, isNull);
        expect(
          tester.widget<IgnorePointer>(guardFinder).ignoring,
          isFalse,
        );
        expect(browserSession.isWebPageInteractionLocked, isFalse);

        // 3. Safari warning alert dialog locks page & increments activeSafariWebAlertCount.
        final alertFuture = showSafariSslWarningDialog(
          hostCtx,
          host: 'expired.badssl.com',
        );
        await tester.pumpAndSettle();

        expect(activeSafariWebAlertCount.value, 1);
        expect(
          tester.widget<IgnorePointer>(guardFinder).ignoring,
          isTrue,
        );
        expect(browserSession.isWebPageInteractionLocked, isTrue);

        await tester.tap(find.byKey(const ValueKey('safari_ssl_go_back_btn')));
        await tester.pumpAndSettle();
        expect(await alertFuture, isFalse);
        expect(activeSafariWebAlertCount.value, 0);
        expect(
          tester.widget<IgnorePointer>(guardFinder).ignoring,
          isFalse,
        );
        expect(browserSession.isWebPageInteractionLocked, isFalse);

        // 4. Pushing a secondary modal sheet (Bookmarks & History) locks via ModalRoute.isCurrentOf.
        await tester.tap(
          find.byKey(const ValueKey('in_app_browser_menu_button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Закладки и история'));
        await tester.pumpAndSettle();

        expect(
          tester.widget<IgnorePointer>(guardFinder).ignoring,
          isTrue,
        );
        expect(browserSession.isWebPageInteractionLocked, isTrue);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          tester.widget<IgnorePointer>(guardFinder).ignoring,
          isFalse,
        );
        expect(browserSession.isWebPageInteractionLocked, isFalse);

        // Once all overlays are dismissed, page interaction works normally again.
        await tester.tap(pageActionBtnFinder);
        await tester.pumpAndSettle();
        expect(launchedExternal?.toString(), 'https://dzen.ru/');

        // 5. Scrollable content test: verify actual Scrollable pixels stay 0 while alert/popover open,
        // then scroll freely once dismissed.
        tester.view.physicalSize = const Size(400, 340);
        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: _TestLiquidGlassProvider(GlassMode.full),
            child: MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(400, 340),
                  padding: EdgeInsets.only(top: 24, bottom: 16),
                ),
                child: Builder(
                  builder: (context) {
                    hostCtx = context;
                    return InAppBrowserSheet(session: browserSession);
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final compactGuardFinder = find.byKey(
          const ValueKey('in_app_browser_web_interaction_guard'),
        );
        final scrollableFinder = find.descendant(
          of: compactGuardFinder,
          matching: find.byType(Scrollable),
        );
        double pageScrollOffset() =>
            tester.state<ScrollableState>(scrollableFinder.first).position.pixels;
        expect(
          tester
              .state<ScrollableState>(scrollableFinder.first)
              .position
              .maxScrollExtent,
          greaterThan(10.0),
        );

        final compactAlertFuture = showSafariSslWarningDialog(
          hostCtx,
          host: 'expired.badssl.com',
        );
        await tester.pumpAndSettle();
        expect(tester.widget<IgnorePointer>(compactGuardFinder).ignoring, isTrue);

        await tester.dragFrom(const Offset(24, 170), const Offset(0, -100));
        await tester.pumpAndSettle();
        expect(pageScrollOffset(), closeTo(0.0, 0.1));

        final compactGoBackBtn = find.byKey(const ValueKey('safari_ssl_go_back_btn'));
        await tester.ensureVisible(compactGoBackBtn);
        await tester.pumpAndSettle();
        await tester.tap(compactGoBackBtn);
        await tester.pumpAndSettle();
        expect(await compactAlertFuture, isFalse);
        expect(tester.widget<IgnorePointer>(compactGuardFinder).ignoring, isFalse);

        await tester.dragFrom(const Offset(200, 170), const Offset(0, -100));
        await tester.pumpAndSettle();
        expect(pageScrollOffset(), greaterThan(0.0));

        // 6. MiniAppWebViewSheet also guards its page on overflow menu & Safari alerts.
        tester.view.physicalSize = const Size(400, 800);
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
        late BuildContext miniCtx;
        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: _TestLiquidGlassProvider(GlassMode.full),
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  miniCtx = context;
                  return MiniAppWebViewSheet(
                    launchData: miniSession.launchData,
                    botName: 'Walt',
                    botUsername: 'walt',
                    session: miniSession,
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final miniGuardFinder = find.byKey(
          const ValueKey('mini_app_web_interaction_guard'),
        );
        expect(
          tester.widget<IgnorePointer>(miniGuardFinder).ignoring,
          isFalse,
        );
        expect(miniSession.isWebPageInteractionLocked, isFalse);

        await tester.tap(
          find.byKey(const ValueKey('mini_app_more_menu_button')),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<IgnorePointer>(miniGuardFinder).ignoring,
          isTrue,
        );
        expect(miniSession.isWebPageInteractionLocked, isTrue);

        await tester.tapAt(const Offset(24, 560));
        await tester.pumpAndSettle();
        expect(
          tester.widget<IgnorePointer>(miniGuardFinder).ignoring,
          isFalse,
        );
        expect(miniSession.isWebPageInteractionLocked, isFalse);

        final miniAlertFuture = showSafariWebAlert<bool>(
          context: miniCtx,
          title: 'Popup',
          message: 'Locked?',
          actions: const [
            SafariAlertAction<bool>(
              label: 'OK',
              result: true,
              isPrimary: true,
              buttonKey: ValueKey('mini_lock_ok_btn'),
            ),
          ],
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<IgnorePointer>(miniGuardFinder).ignoring,
          isTrue,
        );
        expect(miniSession.isWebPageInteractionLocked, isTrue);

        await tester.tap(find.byKey(const ValueKey('mini_lock_ok_btn')));
        await tester.pumpAndSettle();
        expect(await miniAlertFuture, isTrue);
        expect(
          tester.widget<IgnorePointer>(miniGuardFinder).ignoring,
          isFalse,
        );
        expect(miniSession.isWebPageInteractionLocked, isFalse);
      },
    );

    testWidgets(
      'Popups, SiteInfo popover, 3-dots menu, and modal sheets dismiss on outside tap, Escape key, and System Back without closing browser',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        LinkOpener.debugForceInAppSupportedForTest = true;

        final browserSession = MiniAppSession(
          launchData: const MiniAppLaunchData(
            url: 'https://dzen.ru/',
            initData: '',
          ),
          isBrowser: true,
        )..pageTitle = 'Дзен';

        late BuildContext homeCtx;
        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: _TestLiquidGlassProvider(GlassMode.full),
            child: MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(400, 800),
                  padding: EdgeInsets.only(top: 24, bottom: 16),
                ),
                child: Builder(
                  builder: (context) {
                    homeCtx = context;
                    return const Scaffold(body: SizedBox.shrink());
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        unawaited(
          showTheavModalSheet<void>(
            context: homeCtx,
            enableDrag: false,
            barrierDismissible: true,
            useRootNavigator: true,
            customSheetBuilder: (_) => InAppBrowserSheet(session: browserSession),
            builder: (_) => const SizedBox.shrink(),
          ),
        );
        await tester.pumpAndSettle();

        final browserSheetFinder = find.byKey(
          const ValueKey('in_app_browser_sheet'),
        );
        final BuildContext browserCtx = tester.element(browserSheetFinder);
        final Offset browserCloseCenter = tester.getCenter(
          find.byKey(const ValueKey('in_app_browser_close_button')),
        );
        expect(browserSheetFinder, findsOneWidget);

        // 1. SSL warning alert: outside tap, Escape, and System Back.
        final sslOutside = showSafariSslWarningDialog(
          browserCtx,
          host: 'expired.badssl.com',
        );
        await tester.pumpAndSettle();
        expect(activeSafariWebAlertCount.value, 1);
        expect(browserSession.isWebPageInteractionLocked, isTrue);

        await tester.tapAt(const Offset(16, 80));
        await tester.pumpAndSettle();
        expect(await sslOutside, isFalse);
        expect(activeSafariWebAlertCount.value, 0);
        expect(browserSession.isWebPageInteractionLocked, isFalse);
        expect(browserSheetFinder, findsOneWidget);

        final sslEsc = showSafariSslWarningDialog(
          browserCtx,
          host: 'expired.badssl.com',
        );
        await tester.pumpAndSettle();
        expect(activeSafariWebAlertCount.value, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(await sslEsc, isFalse);
        expect(activeSafariWebAlertCount.value, 0);
        expect(browserSession.isWebPageInteractionLocked, isFalse);
        expect(browserSheetFinder, findsOneWidget);

        final sslBack = showSafariSslWarningDialog(
          browserCtx,
          host: 'expired.badssl.com',
        );
        await tester.pumpAndSettle();
        expect(activeSafariWebAlertCount.value, 1);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(await sslBack, isFalse);
        expect(activeSafariWebAlertCount.value, 0);
        expect(browserSession.isWebPageInteractionLocked, isFalse);
        expect(browserSheetFinder, findsOneWidget);

        // 2. JS Prompt (with autofocused TextField): Escape and outside tap.
        final promptEsc = showSafariJsPromptDialog(
          browserCtx,
          originHost: 'dzen.ru',
          isSecure: true,
          message: 'Введите значение:',
          defaultText: 'abc',
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect((await promptEsc).value, isNull);
        expect(activeSafariWebAlertCount.value, 0);
        expect(browserSheetFinder, findsOneWidget);

        final promptOutside = showSafariJsPromptDialog(
          browserCtx,
          originHost: 'dzen.ru',
          isSecure: true,
          message: 'Введите значение:',
          defaultText: 'abc',
        );
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(16, 80));
        await tester.pumpAndSettle();
        expect((await promptOutside).value, isNull);
        expect(activeSafariWebAlertCount.value, 0);
        expect(browserSheetFinder, findsOneWidget);

        // 3. SafariSiteInfoPopover: outside tap over [×], Escape, System Back.
        final siteInfoBtn = find.byKey(
          const ValueKey('in_app_browser_security_badge_button'),
        );
        final siteInfoPopover = find.byKey(
          const ValueKey('in_app_browser_site_info_popover'),
        );

        await tester.tap(siteInfoBtn);
        await tester.pumpAndSettle();
        expect(siteInfoPopover, findsOneWidget);
        await tester.tapAt(browserCloseCenter);
        await tester.pumpAndSettle();
        expect(siteInfoPopover, findsNothing);
        expect(browserSheetFinder, findsOneWidget);
        expect(browserSession.isWebPageInteractionLocked, isFalse);

        await tester.tap(siteInfoBtn);
        await tester.pumpAndSettle();
        expect(siteInfoPopover, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(siteInfoPopover, findsNothing);
        expect(browserSheetFinder, findsOneWidget);

        await tester.tap(siteInfoBtn);
        await tester.pumpAndSettle();
        expect(siteInfoPopover, findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(siteInfoPopover, findsNothing);
        expect(browserSheetFinder, findsOneWidget);

        // 4. Browser 3-dots menu: outside tap over [×], Escape, System Back.
        final browserMenuBtn = find.byKey(
          const ValueKey('in_app_browser_menu_button'),
        );
        final browserMenuFinder = find.byKey(
          const ValueKey('in_app_browser_overflow_menu'),
        );

        await tester.tap(browserMenuBtn);
        await tester.pumpAndSettle();
        expect(browserMenuFinder, findsOneWidget);
        await tester.tapAt(browserCloseCenter);
        await tester.pumpAndSettle();
        expect(browserMenuFinder, findsNothing);
        expect(browserSheetFinder, findsOneWidget);
        expect(browserSession.isWebPageInteractionLocked, isFalse);

        await tester.tap(browserMenuBtn);
        await tester.pumpAndSettle();
        expect(browserMenuFinder, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(browserMenuFinder, findsNothing);
        expect(browserSheetFinder, findsOneWidget);

        await tester.tap(browserMenuBtn);
        await tester.pumpAndSettle();
        expect(browserMenuFinder, findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(browserMenuFinder, findsNothing);
        expect(browserSheetFinder, findsOneWidget);

        // 5. Secondary TheavModalSheet (Bookmarks & History): outside tap, Escape, Back.
        for (final dismissAction in [
          () => tester.tapAt(const Offset(200, 40)),
          () => tester.sendKeyEvent(LogicalKeyboardKey.escape),
          () => tester.binding.handlePopRoute(),
        ]) {
          await tester.tap(browserMenuBtn);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Закладки и история'));
          await tester.pumpAndSettle();
          expect(browserSession.isWebPageInteractionLocked, isTrue);

          await dismissAction();
          await tester.pumpAndSettle();
          expect(find.text('Закладки'), findsNothing);
          expect(browserSheetFinder, findsOneWidget);
          expect(browserSession.isWebPageInteractionLocked, isFalse);
        }

        // Close browser sheet before Mini App checks.
        await tester.tap(
          find.byKey(const ValueKey('in_app_browser_close_button')),
        );
        await tester.pumpAndSettle();
        expect(browserSheetFinder, findsNothing);

        // 6. MiniAppWebViewSheet 3-dots menu & popup dismissal over it.
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
        unawaited(
          showTheavModalSheet<void>(
            context: homeCtx,
            enableDrag: false,
            barrierDismissible: true,
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

        final miniSheetFinder = find.byType(MiniAppWebViewSheet);
        final Offset miniCloseCenter = tester.getCenter(
          find.byKey(const ValueKey('mini_app_close_or_back_button')),
        );
        final miniMoreBtn = find.byKey(
          const ValueKey('mini_app_more_menu_button'),
        );
        final miniMenuFinder = find.byKey(
          const ValueKey('webview_right_pill_expanded'),
        );

        await tester.tap(miniMoreBtn);
        await tester.pumpAndSettle();
        expect(miniMenuFinder, findsOneWidget);
        await tester.tapAt(miniCloseCenter);
        await tester.pumpAndSettle();
        expect(miniMenuFinder, findsNothing);
        expect(miniSheetFinder, findsOneWidget);
        expect(miniSession.isWebPageInteractionLocked, isFalse);

        await tester.tap(miniMoreBtn);
        await tester.pumpAndSettle();
        expect(miniMenuFinder, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(miniMenuFinder, findsNothing);
        expect(miniSheetFinder, findsOneWidget);

        await tester.tap(miniMoreBtn);
        await tester.pumpAndSettle();
        expect(miniMenuFinder, findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(miniMenuFinder, findsNothing);
        expect(miniSheetFinder, findsOneWidget);
      },
    );

    testWidgets(
      'SafariLibrarySheet renders segmented control, current-page quick bookmark card, date-grouped history, search, and Safari clear confirmation',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        LinkOpener.debugForceInAppSupportedForTest = true;

        final now = DateTime.now();
        final todayNoon = DateTime(now.year, now.month, now.day, 12, 0);
        final earlierToday = todayNoon.subtract(const Duration(minutes: 15));
        final yesterdayNoon = todayNoon.subtract(const Duration(days: 1));

        SharedPreferences.setMockInitialValues({
          'in_app_browser_bookmarks': jsonEncode([
            {
              'url': 'https://dart.dev/guides',
              'title': 'Dart Guides',
              'createdAt': earlierToday.toIso8601String(),
            },
            for (int i = 1; i <= 8; i++)
              {
                'url': 'https://example.org/bookmark-$i',
                'title': 'Bookmark $i',
                'createdAt': earlierToday
                    .subtract(Duration(minutes: i))
                    .toIso8601String(),
              },
          ]),
          'in_app_browser_history': jsonEncode([
            {
              'url': 'https://dart.dev/guides',
              'title': 'Dart Guides',
              'visitedAt': todayNoon.toIso8601String(),
            },
            {
              'url': 'https://flutter.dev/docs',
              'title': 'Flutter Docs',
              'visitedAt': earlierToday.toIso8601String(),
            },
            {
              'url': 'https://pub.dev/packages',
              'title': 'Pub Packages',
              'visitedAt': yesterdayNoon.toIso8601String(),
            },
          ]),
        });
        await BrowserDataService.instance.ensureLoaded(forceReload: true);

        final browserSession = MiniAppSession(
          launchData: const MiniAppLaunchData(
            url: 'https://dzen.ru/',
            initData: '',
          ),
          isBrowser: true,
        )..pageTitle = 'Дзен';

        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: _TestLiquidGlassProvider(GlassMode.full),
            child: MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                inputDecorationTheme: const InputDecorationTheme(
                  filled: true,
                  fillColor: Color(0xFF1C1C1E),
                ),
              ),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(400, 800),
                  padding: EdgeInsets.only(top: 24, bottom: 16),
                ),
                child: InAppBrowserSheet(session: browserSession),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open library from bottom Safari toolbar button.
        await tester.tap(find.byTooltip('Закладки и история'));
        await tester.pumpAndSettle();

        final libraryFinder = find.byType(SafariLibrarySheet);
        expect(libraryFinder, findsOneWidget);
        expect(
          find.byType(TheavSegmentedControl<SafariLibraryTab>),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('safari_library_page_view')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('safari_library_search_input')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('safari_library_current_page_card')),
          findsOneWidget,
        );
        expect(find.text('Сохранённые сайты'), findsOneWidget);
        expect(find.text('Dart Guides'), findsOneWidget);

        // Plain close icon without button wrapper & borderless card groups.
        expect(
          find.byKey(const ValueKey('safari_library_close_btn')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: libraryFinder,
            matching: find.byType(TheavHeaderIconButton),
          ),
          findsNothing,
        );
        final groupWidget = tester.widget<TheavInsetGroup>(
          find.byType(TheavInsetGroup).first,
        );
        expect(groupWidget.showBorder, isFalse);

        // Transparent search field even when InputDecorationTheme(filled: true) is set.
        final searchTf = tester.widget<TextField>(
          find.byKey(const ValueKey('safari_library_search_input')),
        );
        expect(searchTf.decoration?.filled, isFalse);
        expect(searchTf.decoration?.fillColor, Colors.transparent);
        expect(searchTf.decoration?.border, InputBorder.none);

        // LiquidGlassTabBar dual-pipeline switcher with zero ClipRRect or Opacity ancestors.
        final segmentedFinder = find.byKey(
          const ValueKey('safari_library_segmented_control'),
        );
        expect(
          find.descendant(
            of: segmentedFinder,
            matching: find.byType(LiquidGlassView),
          ),
          findsNWidgets(2),
        );
        expect(
          find.descendant(
            of: segmentedFinder,
            matching: find.byKey(const ValueKey('lg-animated-nav-gesture-overlay')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: segmentedFinder,
            matching: find.byType(ClipRRect),
          ),
          findsNothing,
        );
        final segmentedLens = find.descendant(
          of: segmentedFinder,
          matching: find.byType(LiquidGlassLens),
        );
        expect(segmentedLens, findsOneWidget);
        expect(
          find.ancestor(of: segmentedLens, matching: find.byType(Opacity)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.descendant(
              of: libraryFinder,
              matching: find.byType(ListView),
            ),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
        );

        // Bottom feathered scroll edge is active on overflowed list; scrolling activates top edge too.
        expect(
          find.byKey(const ValueKey('safari_bookmarks_bottom_scroll_edge')),
          findsOneWidget,
        );
        await tester.drag(
          find.descendant(of: libraryFinder, matching: find.byType(ListView)).first,
          const Offset(0, -140),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('safari_bookmarks_top_scroll_edge')),
          findsOneWidget,
        );
        await tester.drag(
          find.descendant(of: libraryFinder, matching: find.byType(ListView)).first,
          const Offset(0, 180),
        );
        await tester.pumpAndSettle();

        // Quick-bookmark current page via Safari capsule pill button.
        final toggleCurrentBtn = find.byKey(
          const ValueKey('safari_library_toggle_current_bookmark_btn'),
        );
        expect(find.text('Сохранить'), findsOneWidget);
        await tester.tap(toggleCurrentBtn);
        await tester.pumpAndSettle();
        expect(find.text('Сохранено'), findsOneWidget);
        expect(BrowserDataService.instance.isBookmarked('https://dzen.ru/'), isTrue);

        // Press-and-hold horizontal drag across LiquidGlassTabBar slides glass pill & PageView to History.
        final Offset bookmarksCenter = tester.getCenter(find.text('Закладки'));
        final TestGesture grabHistory =
            await tester.startGesture(bookmarksCenter);
        await tester.pump(const Duration(milliseconds: 120));
        for (int step = 0; step < 6; step++) {
          await grabHistory.moveBy(const Offset(24, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 60));
        await grabHistory.up();
        await tester.pumpAndSettle();
        expect(find.text('Сегодня'), findsOneWidget);
        expect(find.text('Вчера'), findsOneWidget);

        // Press-and-drag back to Bookmarks, then switch via tap to History.
        final Offset historyCenter = tester.getCenter(find.text('История'));
        final TestGesture grabBookmarks =
            await tester.startGesture(historyCenter);
        await tester.pump(const Duration(milliseconds: 120));
        for (int step = 0; step < 6; step++) {
          await grabBookmarks.moveBy(const Offset(-24, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 60));
        await grabBookmarks.up();
        await tester.pumpAndSettle();
        expect(find.text('Сохранённые сайты'), findsOneWidget);

        await tester.tap(find.text('История'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text('Сегодня'), findsOneWidget);
        expect(find.text('Вчера'), findsOneWidget);
        expect(find.text('Flutter Docs'), findsOneWidget);
        expect(find.text('Pub Packages'), findsOneWidget);

        // Search filter + exact single entry deletion by entry rather than index 0.
        await tester.enterText(
          find.byKey(const ValueKey('safari_library_search_input')),
          'flutter',
        );
        await tester.pumpAndSettle();
        expect(find.text('Flutter Docs'), findsOneWidget);
        expect(find.text('Pub Packages'), findsNothing);

        final flutterEntry = BrowserDataService.instance.history.firstWhere(
          (e) => e.url == 'https://flutter.dev/docs',
        );
        await tester.tap(
          find.byKey(
            ValueKey(
              'safari_history_remove_${flutterEntry.url}_${flutterEntry.visitedAt.microsecondsSinceEpoch}',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Ничего не найдено'), findsOneWidget);
        expect(
          BrowserDataService.instance.history
              .any((e) => e.url == 'https://dart.dev/guides'),
          isTrue,
        );
        expect(
          BrowserDataService.instance.history
              .any((e) => e.url == 'https://pub.dev/packages'),
          isTrue,
        );

        // Clear search restores remaining Today & Yesterday sections.
        await tester.tap(
          find.byKey(const ValueKey('safari_library_search_clear_btn')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Dart Guides'), findsOneWidget);
        expect(find.text('Pub Packages'), findsOneWidget);

        // Safari confirmation dialog clears history while preserving bookmarks.
        await tester.tap(
          find.byKey(const ValueKey('safari_library_clear_history_btn')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('safari_clear_history_confirm_dialog')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('safari_clear_history_confirm_btn')),
        );
        await tester.pumpAndSettle();
        expect(BrowserDataService.instance.history, isEmpty);
        expect(find.text('История браузера пуста'), findsOneWidget);

        // Switch back to Bookmarks and tap saved Dart Guides bookmark -> navigates & closes sheet.
        await tester.tap(find.text('Закладки'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text('Dart Guides'), findsOneWidget);
        await tester.tap(find.text('Dart Guides'));
        await tester.pumpAndSettle();
        expect(libraryFinder, findsNothing);
        expect(browserSession.currentUrl, 'https://dart.dev/guides');
      },
    );

    for (final mode in const <GlassMode>[GlassMode.full, GlassMode.disabled]) {
      testWidgets(
        'SafariSiteInfoPopover morphs directly from address capsule and back without second oval or Opacity around glass in $mode',
        (tester) async {
          tester.view.physicalSize = const Size(400, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          LinkOpener.debugForceInAppSupportedForTest = true;

          final browserSession = MiniAppSession(
            launchData: const MiniAppLaunchData(
              url: 'https://dzen.ru/',
              initData: '',
            ),
            isBrowser: true,
          )..pageTitle = 'Дзен';

          await tester.pumpWidget(
            ChangeNotifierProvider<LiquidGlassProvider>.value(
              value: _TestLiquidGlassProvider(mode),
              child: MaterialApp(
                home: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(400, 800),
                    padding: EdgeInsets.only(top: 24, bottom: 16),
                  ),
                  child: InAppBrowserSheet(session: browserSession),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final headerFinder = find.byType(WebViewFloatingHeader);
          final securityBtn = find.byKey(
            const ValueKey('in_app_browser_security_badge_button'),
          );
          final popoverFinder = find.byKey(
            const ValueKey('in_app_browser_site_info_popover'),
          );
          final guardFinder = find.byKey(
            const ValueKey('in_app_browser_web_interaction_guard'),
          );

          expect(popoverFinder, findsNothing);

          Finder? centerMorphFinder;
          Finder? centerLensFinder;
          State? centerMorphState;

          if (mode == GlassMode.full) {
            expect(find.byType(LiquidGlassMorph), findsNWidgets(2));
            centerMorphFinder =
                find.byKey(const ValueKey('webview_center_morph'));
            centerLensFinder = find.descendant(
              of: centerMorphFinder,
              matching: find.byType(LiquidGlassLens),
            );
            expect(centerLensFinder, findsOneWidget);
            centerMorphState = tester.state(centerMorphFinder);
            expect(tester.getRect(centerLensFinder).height, closeTo(44.0, 0.5));
          }

          // Open Site Info popover by morphing the center address pill itself.
          await tester.tap(securityBtn);
          await tester.pump();
          for (int i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }

          if (mode == GlassMode.full) {
            expect(find.byType(LiquidGlassMorph), findsNWidgets(2));
            expect(
              identical(tester.state(centerMorphFinder!), centerMorphState),
              isTrue,
            );
            expect(
              tester.getRect(centerLensFinder!).height,
              greaterThan(44.5),
            );
          }

          await tester.pumpAndSettle();
          expect(popoverFinder, findsOneWidget);
          expect(browserSession.isWebPageInteractionLocked, isTrue);

          double openHeight = 0.0;
          if (mode == GlassMode.full) {
            final Rect openRect = tester.getRect(centerLensFinder!);
            openHeight = openRect.height;
            expect(openRect.width, closeTo(328.0, 1.0));
            expect(openHeight, greaterThan(200.0));
            expect(find.byType(LiquidGlassMorph), findsNWidgets(2));
            expect(
              find.ancestor(
                of: centerMorphFinder!,
                matching: find.descendant(
                  of: headerFinder,
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is FadeTransition ||
                        (w is Opacity && w.opacity > 0.0 && w.opacity < 1.0),
                  ),
                ),
              ),
              findsNothing,
            );
          }

          // Tap outside below the card to collapse back into the address pill.
          await tester.tapAt(const Offset(200, 480));
          await tester.pump();

          expect(
            tester.widget<IgnorePointer>(guardFinder).ignoring,
            isFalse,
          );
          expect(browserSession.isWebPageInteractionLocked, isFalse);

          for (int i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          if (mode == GlassMode.full) {
            expect(find.byType(LiquidGlassMorph), findsNWidgets(2));
            expect(
              identical(tester.state(centerMorphFinder!), centerMorphState),
              isTrue,
            );
            final double midCloseHeight =
                tester.getRect(centerLensFinder!).height;
            expect(midCloseHeight, greaterThan(44.5));
            expect(midCloseHeight, lessThan(openHeight - 10.0));
          }

          await tester.pumpAndSettle();
          expect(popoverFinder, findsNothing);
          expect(securityBtn, findsOneWidget);
          if (mode == GlassMode.full) {
            expect(find.byType(LiquidGlassMorph), findsNWidgets(2));
            expect(
              tester.getRect(centerLensFinder!).height,
              closeTo(44.0, 0.5),
            );
          }
        },
      );
    }

    testWidgets(
      'InAppBrowserSheet right ⋮ capsule uses single-lens morph, unmounts cleanly off-screen on collapse, and renders spacious 44dp menu items',
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
        )..pageTitle = 'Дзен';

        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: _TestLiquidGlassProvider(GlassMode.full),
            child: MaterialApp(
              home: BackdropGroup(
                child: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(400, 800),
                    padding: EdgeInsets.only(top: 24, bottom: 16),
                  ),
                  child: InAppBrowserSheet(session: session),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final headerFinder = find.byType(WebViewFloatingHeader);
        final rightMorphFinder = find.byKey(const ValueKey('webview_right_morph'));
        expect(rightMorphFinder, findsOneWidget);
        final rightMorphWidget = tester.widget<LiquidGlassMorph>(rightMorphFinder);
        expect(rightMorphWidget.motion.blended, isFalse);
        expect(rightMorphWidget.smoothness, 0);
        expect(
          find.descendant(
            of: headerFinder,
            matching: find.byType(LiquidGlassBlender),
          ),
          findsNothing,
        );

        // Opening overflow menu renders spacious 44dp rows without LiquidGlassBlender.
        await tester.tap(find.byKey(const ValueKey('in_app_browser_menu_button')));
        await tester.pumpAndSettle();
        final overflowMenu = find.byKey(const ValueKey('in_app_browser_overflow_menu'));
        expect(overflowMenu, findsOneWidget);
        final menuItemInk = find
            .ancestor(
              of: find.text('Найти на странице'),
              matching: find.byType(InkWell),
            )
            .first;
        expect(tester.getSize(menuItemInk).height, closeTo(44.0, 0.5));
        expect(
          find.descendant(
            of: headerFinder,
            matching: find.byType(LiquidGlassBlender),
          ),
          findsNothing,
        );

        // Close menu before testing collapse.
        await tester.tapAt(const Offset(24, 560));
        await tester.pumpAndSettle();
        expect(overflowMenu, findsNothing);

        // Collapse chrome: right capsule unmounts before/at screen edge exit.
        session.applyBrowserPageMetaPayload('{"collapsed":true}');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(
          find.descendant(
            of: headerFinder,
            matching: find.byType(LiquidGlassBlender),
          ),
          findsNothing,
        );
        await tester.pump(const Duration(milliseconds: 90));
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.byKey(const ValueKey('in_app_browser_menu_button')), findsNothing);
        expect(find.byKey(const ValueKey('in_app_browser_close_button')), findsNothing);

        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('in_app_browser_compact_domain')), findsOneWidget);

        // Expand back and verify right ⋮ capsule returns cleanly.
        await tester.tap(find.byKey(const ValueKey('webview_header_center_pill')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('in_app_browser_menu_button')), findsOneWidget);
      },
    );
  });
}
