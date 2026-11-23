import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/screens/settings/browser_vault_and_data_screen.dart';
import 'package:theaver/services/bot_service.dart';
import 'package:theaver/services/browser_data_service.dart';
import 'package:theaver/services/browser_otp_autofill_service.dart';
import 'package:theaver/services/browser_site_settings_service.dart';
import 'package:theaver/services/browser_vault_auth_gate.dart';
import 'package:theaver/services/browser_vault_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/utils/browser_autofill_script.dart';
import 'package:theaver/utils/browser_context_menu_script.dart';
import 'package:theaver/utils/browser_reader_mode_script.dart';
import 'package:theaver/widgets/bot/mini_app_webview_sheet.dart';
import 'package:theaver/widgets/browser/in_app_browser_sheet.dart';
import 'package:theaver/widgets/browser/safari_autofill_overlays.dart';
import 'package:theaver/widgets/browser/safari_element_context_sheet.dart';
import 'package:theaver/widgets/browser/safari_reader_mode_view.dart';
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

class _PreloadedAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _PreloadedAppLocalizationsDelegate(this.preloaded);

  final AppLocalizations preloaded;

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == preloaded.locale.languageCode;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(preloaded);

  @override
  bool shouldReload(covariant _PreloadedAppLocalizationsDelegate old) =>
      old.preloaded.locale != preloaded.locale;
}

Widget _wrapTestApp({
  required Widget child,
  GlassMode mode = GlassMode.full,
  AppLocalizations? preloadedL10n,
}) {
  return ChangeNotifierProvider<LiquidGlassProvider>.value(
    value: _TestLiquidGlassProvider(mode),
    child: MaterialApp(
      locale: preloadedL10n?.locale,
      supportedLocales: const <Locale>[
        Locale('en'),
        Locale('ru'),
      ],
      localizationsDelegates: preloadedL10n != null
          ? <LocalizationsDelegate<dynamic>>[
              _PreloadedAppLocalizationsDelegate(preloadedL10n),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ]
          : null,
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 800),
          padding: EdgeInsets.only(top: 24, bottom: 16),
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void _expectNoTranslucentOpacityAboveGlass(WidgetTester tester) {
  final glassFinders = <Finder>[
    find.byType(LiquidGlassLens),
    find.byType(LiquidGlassMorph),
    find.byType(LiquidGlassSwitch),
    find.byType(TheavFloatingSurface),
  ];

  for (final finder in glassFinders) {
    for (final element in finder.evaluate()) {
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is InAppBrowserSheet ||
            widget is Scaffold ||
            widget is MaterialApp) {
          return false;
        }
        if (widget is Opacity && widget.opacity < 1.0) {
          fail('Forbidden translucent Opacity(${widget.opacity}) above glass $element');
        }
        if (widget is FadeTransition) {
          fail('Forbidden FadeTransition above glass $element');
        }
        if (widget is ClipRRect) {
          fail('Forbidden ClipRRect above glass $element');
        }
        return true;
      });
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    BrowserDataService.instance.resetForTesting();
    BrowserSiteSettingsService.instance.resetForTesting();
    BrowserVaultService.instance.resetForTesting();
    BrowserVaultAuthGate.instance.resetForTesting();
    BrowserOtpAutofillService.instance.resetForTesting();
    MiniAppSessionController.instance.closeAllMinimized();
    AppLocalizations.debugCurrent = null;
  });

  tearDown(() {
    MiniAppSessionController.instance.closeAllMinimized();
    BrowserDataService.instance.resetForTesting();
    BrowserSiteSettingsService.instance.resetForTesting();
    BrowserVaultService.instance.resetForTesting();
    BrowserVaultAuthGate.instance.resetForTesting();
    BrowserOtpAutofillService.instance.resetForTesting();
    AppLocalizations.debugCurrent = null;
  });

  group('Reader Mode & Typography (Aa)', () {
    test('BrowserReaderArticle parses structured article blocks and clamps values', () {
      final article = BrowserReaderArticle.fromJson(<String, dynamic>{
        'url': 'https://news.example.org/story-1',
        'title': 'Glass Architecture in Flutter',
        'byline': 'Elena Sokolova',
        'siteName': 'Theaver Engineering',
        'publishedTime': '2026-11-23',
        'estimatedReadMinutes': 4,
        'blocks': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'heading',
            'headingLevel': 2,
            'text': 'Overview',
          },
          <String, dynamic>{
            'type': 'paragraph',
            'text': 'Reader mode extracts clean typography and strips clutter.',
          },
          <String, dynamic>{
            'type': 'quote',
            'text': 'Solid glass refraction never wraps in translucent opacity.',
          },
          <String, dynamic>{
            'type': 'code',
            'text': 'setTextZoom(120);',
          },
          <String, dynamic>{
            'type': 'list',
            'items': <String>['Light', 'Sepia', 'Dark', 'OLED'],
          },
        ],
      });

      expect(article.title, 'Glass Architecture in Flutter');
      expect(article.estimatedReadMinutes, 4);
      expect(article.blocks, hasLength(5));
      expect(article.blocks[0].type, BrowserReaderBlockType.heading);
      expect(article.blocks[2].type, BrowserReaderBlockType.quote);
      expect(article.blocks[3].type, BrowserReaderBlockType.code);
      expect(article.blocks[4].items, hasLength(4));
    });

    test('BrowserSiteSettingsService persists reader appearance and per-site textZoom', () async {
      final settings = BrowserSiteSettingsService.instance
        ..debugUserIdOverride = 'alice';
      await settings.ensureLoaded(forceReload: true);

      await settings.setReaderTheme('oled');
      await settings.setReaderFontFamily('serif');
      await settings.setReaderFontScale(1.85); // Clamps to 1.50
      await settings.setTextZoomForUrl('https://docs.example.org/guide', 1.25);

      await settings.ensureLoaded(forceReload: true);
      expect(settings.readerTheme, 'oled');
      expect(settings.readerFontFamily, 'serif');
      expect(settings.readerFontScale, 1.50);
      expect(
        settings.sitePreferences['docs.example.org']?.textZoom,
        closeTo(1.25, 0.001),
      );

      // Resetting zoom to 1.0 prunes default site preference
      await settings.setTextZoomForUrl('https://docs.example.org/guide', 1.0);
      expect(settings.sitePreferences['docs.example.org'], isNull);
    });

    testWidgets('SafariReaderModeView renders all 4 themes and fires onExitReader', (tester) async {
      bool exited = false;
      const article = BrowserReaderArticle(
        url: 'https://news.example.org/story-1',
        title: 'Safari Reader Mode Test',
        byline: 'Test Author',
        siteName: 'News',
        estimatedReadMinutes: 3,
        blocks: <BrowserReaderBlock>[
          BrowserReaderBlock(
            type: BrowserReaderBlockType.paragraph,
            text: 'Clean distraction-free article body paragraph.',
          ),
          BrowserReaderBlock(
            type: BrowserReaderBlockType.quote,
            text: 'Pull quotes adapt to theme palette cleanly.',
          ),
        ],
      );

      final expectedBg = <String, Color>{
        'light': const Color(0xFFFAF9F6),
        'sepia': const Color(0xFFF4ECD8),
        'dark': const Color(0xFF1C1C1E),
        'oled': const Color(0xFF000000),
      };

      for (final entry in expectedBg.entries) {
        await tester.pumpWidget(
          _wrapTestApp(
            child: SafariReaderModeView(
              article: article,
              themeId: entry.key,
              fontFamilyId: entry.key == 'sepia' ? 'serif' : 'sans',
              fontScale: 1.15,
              onExitReader: () => exited = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final box = tester.widget<ColoredBox>(
          find.byKey(const ValueKey('safari_reader_mode_view')),
        );
        expect(box.color, entry.value);
        expect(find.text('Safari Reader Mode Test'), findsOneWidget);
        expect(find.text('~3 мин'), findsOneWidget);
      }

      await tester.tap(find.byKey(const ValueKey('safari_reader_exit_btn')));
      await tester.pumpAndSettle();
      expect(exited, isTrue);
    });

    testWidgets('SafariTypographySheetBody updates scale, theme, font, and reader toggle', (tester) async {
      double currentScale = 1.0;
      String currentTheme = 'light';
      String currentFont = 'sans';
      int toggleCount = 0;

      await tester.pumpWidget(
        _wrapTestApp(
          child: SafariTypographySheetBody(
            fontScale: currentScale,
            themeId: currentTheme,
            fontFamilyId: currentFont,
            readerAvailable: true,
            onFontScaleChanged: (v) => currentScale = v,
            onThemeChanged: (v) => currentTheme = v,
            onFontFamilyChanged: (v) => currentFont = v,
            onToggleReaderMode: () => toggleCount++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('safari_typography_sheet')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('safari_typography_increase_btn')));
      await tester.tap(find.byKey(const ValueKey('safari_typography_theme_sepia')));
      await tester.tap(find.byKey(const ValueKey('safari_typography_font_mono')));
      await tester.tap(find.byKey(const ValueKey('safari_typography_reader_toggle_btn')));
      await tester.pumpAndSettle();

      expect(currentScale, closeTo(1.05, 0.001));
      expect(currentTheme, 'sepia');
      expect(currentFont, 'mono');
      expect(toggleCount, 1);
    });

    testWidgets('InAppBrowserSheet toggles Reader Mode, keeps 2 LiquidGlassMorphs, handles Escape, and renders Pull-to-Refresh capsule', (tester) async {
      final session = MiniAppSession(
        launchData: const MiniAppLaunchData(
          url: 'https://news.example.org/article',
          initData: '',
        ),
        isBrowser: true,
      )
        ..pageTitle = 'Article'
        ..isReaderAvailable = true
        ..activeReaderArticle = const BrowserReaderArticle(
          url: 'https://news.example.org/article',
          title: 'Readable Article Title',
          blocks: <BrowserReaderBlock>[
            BrowserReaderBlock(
              type: BrowserReaderBlockType.paragraph,
              text: 'Article paragraph inside InAppBrowserSheet.',
            ),
          ],
        );

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

      expect(find.byType(LiquidGlassMorph), findsNWidgets(2));
      expect(find.byKey(const ValueKey('in_app_browser_reader_button')), findsOneWidget);
      _expectNoTranslucentOpacityAboveGlass(tester);

      // Pull-to-refresh overscroll telemetry shows capsule & stays glass-safe
      session.onBrowserPullToRefreshEvent?.call(0.75, false);
      await tester.pump();
      expect(find.byKey(const ValueKey('in_app_browser_ptr_capsule')), findsOneWidget);
      _expectNoTranslucentOpacityAboveGlass(tester);

      session.onBrowserPullToRefreshEvent?.call(0.40, true);
      await tester.pump();
      expect(find.byKey(const ValueKey('in_app_browser_ptr_capsule')), findsNothing);

      // Activate Reader Mode overlay on session
      session.isReaderModeActive = true;
      session.onSheetStateChanged?.call();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('safari_reader_mode_view')), findsOneWidget);
      expect(find.text('Readable Article Title'), findsOneWidget);
      expect(find.byType(LiquidGlassMorph), findsNWidgets(2));

      // Pressing Escape exits Reader Mode without closing InAppBrowserSheet
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(session.isReaderModeActive, isFalse);
      expect(find.byKey(const ValueKey('safari_reader_mode_view')), findsNothing);
      expect(find.byKey(const ValueKey('in_app_browser_sheet')), findsOneWidget);
    });
  });

  group('Long-Press Context Menu Script & Sheet', () {
    test('BrowserContextMenuTarget validates safe links/images and rejects dangerous schemes', () {
      final safe = BrowserContextMenuTarget.tryParseJson(
        '{"linkUrl":"https://theaver.app/docs","linkText":"Theaver Docs","imageUrl":"data:image/png;base64,AAAA","imageAlt":"Logo"}',
      );
      expect(safe, isNotNull);
      expect(safe!.hasLink, isTrue);
      expect(safe.hasImage, isTrue);
      expect(safe.linkText, 'Theaver Docs');

      final blockedJs = BrowserContextMenuTarget.tryParseJson(
        '{"linkUrl":"javascript:alert(1)","imageUrl":"data:text/html,<script>1</script>"}',
      );
      expect(blockedJs, isNull);

      final blockedVbs = BrowserContextMenuTarget.tryParseJson(
        '{"linkUrl":"vbscript:msgbox(1)","imageUrl":"vbscript:bad"}',
      );
      expect(blockedVbs, isNull);

      final blockedSvg = BrowserContextMenuTarget.tryParseJson(
        '{"imageUrl":"data:image/svg+xml,<svg onload=alert(1)/>"}',
      );
      expect(blockedSvg, isNull);

      final script = BrowserContextMenuScript.buildObserverScript();
      expect(script, contains('TheaverBrowserContextMenu'));
      expect(script, contains('window !== window.top'));
    });

    testWidgets('showSafariElementContextSheet renders actions and returns chosen SafariElementContextAction', (tester) async {
      late BuildContext hostCtx;
      await tester.pumpWidget(
        _wrapTestApp(
          child: Builder(
            builder: (ctx) {
              hostCtx = ctx;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Future<SafariElementContextAction?> resFuture =
          showSafariElementContextSheet(
        hostCtx,
        target: const BrowserContextMenuTarget(
          linkUrl: 'https://example.org/photo',
          linkText: 'Example Photo',
          imageUrl: 'https://cdn.example.org/pic.jpg',
          imageAlt: 'Hero',
        ),
        alreadyBookmarked: false,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('safari_element_context_sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('safari_context_open_in_new_tab')), findsOneWidget);
      expect(find.byKey(const ValueKey('safari_context_add_bookmark')), findsOneWidget);
      expect(find.byKey(const ValueKey('safari_context_copy_link')), findsOneWidget);
      expect(find.byKey(const ValueKey('safari_context_save_image')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('safari_context_save_image')));
      await tester.pumpAndSettle();
      expect(await resFuture, SafariElementContextAction.saveImage);
    });
  });

  group('Real AppLocalizations.delegate (en vs ru)', () {
    testWidgets('renders English translations under Locale(en) and Russian under Locale(ru)', (tester) async {
      const cardCandidate = BrowserPendingCardSubmission(
        url: 'https://checkout.example.org',
        origin: 'https://checkout.example.org',
        displayHost: 'checkout.example.org',
        cardNumber: '4111111111111111',
        holderName: 'ALICE',
        expMonth: 12,
        expYear: 2029,
        isUpdate: false,
      );

      final enL10n = (await tester.runAsync(
        () => AppLocalizations.delegate.load(const Locale('en')),
      ))!;
      final ruL10n = (await tester.runAsync(
        () => AppLocalizations.delegate.load(const Locale('ru')),
      ))!;

      // 1. English locale from real assets/l10n/en.json
      await tester.pumpWidget(
        _wrapTestApp(
          preloadedL10n: enL10n,
          child: Column(
            children: [
              SafariSaveCardSheet(
                candidate: cardCandidate,
                onSave: () {},
                onDismiss: () {},
              ),
              const Expanded(
                child: BrowserVaultAndDataScreen(
                  initialSection: 1,
                  autoUnlockPasswords: false,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Save card?'), findsOneWidget);
      expect(find.text('CVV is not saved'), findsOneWidget);
      expect(find.text('Payment Card Autofill'), findsOneWidget);
      expect(find.text('Browser Vault PIN'), findsOneWidget);

      // 2. Russian locale from real assets/l10n/ru.json
      await tester.pumpWidget(
        _wrapTestApp(
          preloadedL10n: ruL10n,
          child: Column(
            children: [
              SafariSaveCardSheet(
                candidate: cardCandidate,
                onSave: () {},
                onDismiss: () {},
              ),
              const Expanded(
                child: BrowserVaultAndDataScreen(
                  initialSection: 1,
                  autoUnlockPasswords: false,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Сохранить карту?'), findsOneWidget);
      expect(find.text('CVV не сохраняется'), findsOneWidget);
      expect(find.text('Автозаполнение банковских карт'), findsOneWidget);
      expect(find.text('PIN-код сейфа браузера'), findsOneWidget);
    });
  });
}
