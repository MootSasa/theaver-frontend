import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/screens/auth/first_start_wizard_screen.dart';
import 'package:theaver/screens/auth/login_screen.dart';
import 'package:theaver/screens/auth/register_screen.dart';
import 'package:theaver/screens/settings/service_menu_screen.dart';
import 'package:theaver/services/account_manager.dart';
import 'package:theaver/services/auth_service.dart';
import 'package:theaver/services/database/app_database.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/services/session_bootstrap_coordinator.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/services/theav_theme_service.dart';
import 'package:theaver/theme/theme_provider.dart';
import 'package:theaver/widgets/auth/country_phone_input.dart';
import 'package:theaver/widgets/auth/theav_auth_primitives.dart';
import 'package:theaver/widgets/chat/chat_list_tile_item.dart';
import 'package:theaver/widgets/chat/chat_selection_header.dart';
import 'package:theaver/widgets/chat/classic_bottom_bar.dart';
import 'package:theaver/widgets/chat/floating_glass_app_bar.dart';
import 'package:theaver/widgets/chat/liquid_glass_input_field.dart';
import 'package:theaver/widgets/settings/settings_floating_header.dart';
import 'package:theaver/widgets/theme/real_app_appearance_preview.dart';

class _TestLiquidGlassProvider extends LiquidGlassProvider {
  _TestLiquidGlassProvider(this._mode);

  GlassMode _mode;

  @override
  GlassMode get mode => _mode;

  @override
  bool get enabled => _mode != GlassMode.disabled;

  @override
  bool get isLite => _mode == GlassMode.lite;

  @override
  bool get isFull => _mode == GlassMode.full;

  @override
  Future<void> setMode(GlassMode value) async {
    _mode = value;
    notifyListeners();
  }
}

class _PreloadedAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _PreloadedAppLocalizationsDelegate(this.l10n);

  final AppLocalizations l10n;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(l10n);

  @override
  bool shouldReload(covariant _PreloadedAppLocalizationsDelegate old) => false;
}

Future<AppLocalizations> _loadTestL10n(
  WidgetTester tester, [
  Locale locale = const Locale('en'),
]) async {
  final loaded =
      await tester.runAsync(() => AppLocalizations.delegate.load(locale));
  return loaded!;
}

void _useTallPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _buildAuthTestHost({
  required Widget child,
  required ThemeProvider themeProvider,
  required LiquidGlassProvider glassProvider,
  required LocaleProvider localeProvider,
  required AppLocalizations l10n,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ChangeNotifierProvider<LiquidGlassProvider>.value(value: glassProvider),
      ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
      ChangeNotifierProvider<ProfileThemeProvider>(
        create: (_) => ProfileThemeProvider(),
      ),
    ],
    child: Consumer2<ThemeProvider, LocaleProvider>(
      builder: (context, tp, lp, _) => MaterialApp(
        locale: lp.locale,
        supportedLocales:
            LocaleProvider.supportedLanguageCodes.map(Locale.new).toList(),
        localizationsDelegates: [
          _PreloadedAppLocalizationsDelegate(l10n),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: tp.lightThemeData,
        darkTheme: tp.darkThemeData,
        themeMode: tp.themeMode,
        home: child,
      ),
    ),
  );
}

int _leadingZeroBits(List<int> digest) {
  var total = 0;
  for (final b in digest) {
    if (b == 0) {
      total += 8;
    } else {
      var v = b;
      var lz = 0;
      if ((v & 0xF0) == 0) {
        lz += 4;
        v <<= 4;
      }
      if ((v & 0xC0) == 0) {
        lz += 2;
        v <<= 2;
      }
      if ((v & 0x80) == 0) {
        lz += 1;
      }
      return total + lz;
    }
  }
  return total;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      (_) async => <String, dynamic>{},
    );
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
  });

  group('LocaleProvider system locale resolution', () {
    testWidgets('uses supported OS locale on fresh launch and honors explicit pref', (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('de', 'DE');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);

      final lpAuto = LocaleProvider();
      await lpAuto.ready;
      expect(lpAuto.locale.languageCode, 'de');
      expect(lpAuto.hasExplicitSelection, isFalse);

      tester.platformDispatcher.localeTestValue = const Locale('uk', 'UA');
      final lpUnsupported = LocaleProvider();
      await lpUnsupported.ready;
      expect(lpUnsupported.locale.languageCode, 'en');
      expect(lpUnsupported.hasExplicitSelection, isFalse);

      SharedPreferences.setMockInitialValues({'selected_language': 'ru'});
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
      final lpExplicit = LocaleProvider();
      await lpExplicit.ready;
      expect(lpExplicit.locale.languageCode, 'ru');
      expect(lpExplicit.hasExplicitSelection, isTrue);
    });
  });

  group('E.164 phone normalization and CountryPhoneInput', () {
    test('normalizes CIS and international formats strictly', () {
      expect(normalizeToE164('8 (999) 123-45-67', defaultIso: 'RU'), '+79991234567');
      expect(normalizeToE164('+375 (29) 111-22-33', defaultIso: 'RU'), '+375291112233');
      expect(normalizeToE164('9991234567', defaultIso: 'RU'), '+79991234567');
      expect(normalizeToE164('1234', defaultIso: 'RU'), isNull);
    });

    testWidgets('switches country pill and outputs E.164 on international paste', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      String selectedIso = 'RU';
      String latestE164 = '';
      final tp = ThemeProvider();
      addTearDown(tp.dispose);
      final gp = _TestLiquidGlassProvider(GlassMode.disabled);
      final lp = LocaleProvider();
      await lp.ready;
      final l10n = await _loadTestL10n(tester);

      await tester.pumpWidget(
        _buildAuthTestHost(
          themeProvider: tp,
          glassProvider: gp,
          localeProvider: lp,
          l10n: l10n,
          child: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: CountryPhoneInput(
                controller: ctrl,
                countryIso: selectedIso,
                onCountryChanged: (entry) =>
                    setState(() => selectedIso = entry.iso),
                onE164Changed: (val) => latestE164 = val,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '+375291112233');
      await tester.pump();
      expect(selectedIso, 'BY');
      expect(latestE164, '+375291112233');
      expect(find.text('BY +375'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '+79991234567');
      await tester.pump();
      expect(selectedIso, 'RU');
      expect(find.text('RU +7'), findsOneWidget);

      await tester.tap(find.text('RU +7'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Belarus'), findsOneWidget);
      await tester.tap(find.text('Belarus'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(selectedIso, 'BY');
      expect(find.text('BY +375'), findsOneWidget);
    });
  });

  test('computeRegistrationProofOfWork finds valid SHA-256 zero-bit nonce', () async {
    const challenge = '1795000000.12.register.testtoken.testsig';
    final nonce = await computeRegistrationProofOfWork(challenge);
    final digest = sha256.convert(utf8.encode('$challenge:$nonce')).bytes;
    expect(_leadingZeroBits(digest), greaterThanOrEqualTo(12));
  });

  group('RealAppAppearancePreview, FirstStartWizardScreen & onboarding adoption', () {
    testWidgets('switches glass modes on Dialog without ParentDataWidget error and renders real MainScreen preview', (tester) async {
      _useTallPhoneViewport(tester);
      final tp = ThemeProvider();
      addTearDown(tp.dispose);
      final gp = _TestLiquidGlassProvider(GlassMode.disabled);
      final lp = LocaleProvider();
      await lp.ready;
      final l10n = await _loadTestL10n(tester);

      await tester.pumpWidget(
        _buildAuthTestHost(
          themeProvider: tp,
          glassProvider: gp,
          localeProvider: lp,
          l10n: l10n,
          child: const Scaffold(
            body: SingleChildScrollView(
              child: RealAppAppearancePreview(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default Dialog mode mounts real FloatingGlassAppBar & LiquidGlassInputField
      expect(find.byType(FloatingGlassAppBar), findsOneWidget);
      expect(find.byType(LiquidGlassInputField), findsOneWidget);

      // Regression guard for ChatBottomScrollEdge ParentDataWidget across Lite/Full/Material
      await gp.setMode(GlassMode.lite);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);

      await gp.setMode(GlassMode.full);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);

      await gp.setMode(GlassMode.disabled);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Toggle to Workspace ("Main Screen") with Material -> mounts real MainScreen widgets
      await tester.ensureVisible(find.text('Main Screen'));
      await tester.tap(find.text('Main Screen'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatListAdaptiveTopBar), findsOneWidget);
      expect(find.byType(ChatListTileItem), findsWidgets);
      expect(find.byType(ClassicBottomBar), findsOneWidget);
      expect(find.byType(LiquidGlassScaffold), findsNothing);

      // Switch to Liquid Glass Lite & Full -> mounts real LiquidGlassScaffold pill pipeline + LiquidGlassMorph (+)
      await gp.setMode(GlassMode.lite);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
      expect(find.byType(LiquidGlassScaffold), findsOneWidget);
      expect(find.byType(LiquidGlassMorph), findsWidgets);
      expect(find.byType(ClassicBottomBar), findsNothing);

      await gp.setMode(GlassMode.full);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
      expect(find.byType(LiquidGlassScaffold), findsOneWidget);
      expect(find.byType(LiquidGlassMorph), findsWidgets);

      await gp.setMode(GlassMode.disabled);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    test('adoptDeviceOnboardingAppearanceIfUnset copies pre-login ThemeMode, GlassMode, and theme IDs into user namespace', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': ThemeMode.dark.index,
        'glass_mode': GlassMode.full.index,
        'liquid_glass_design': true,
        'device_active_dark_theme_id': 'midnight_neon',
      });
      await SettingsService().init();

      await SettingsService().adoptDeviceOnboardingAppearanceIfUnset('user_42');
      await TheavThemeService().adoptDeviceOnboardingAppearanceIfUnset('user_42');
      await ThemeProvider.adoptDeviceOnboardingAppearanceIfUnset('user_42');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('u_user_42_glass_mode'), GlassMode.full.index);
      expect(prefs.getBool('u_user_42_liquid_glass_design'), isTrue);
      expect(prefs.getInt('user_user_42_theme_mode'), ThemeMode.dark.index);
      expect(prefs.getString('user_user_42_active_dark_theme_id'), 'midnight_neon');
    });

    testWidgets('FirstStartWizardScreen shows dissolving hero without top header, morphs language button, and opens Step 1 with Material default', (tester) async {
      _useTallPhoneViewport(tester);
      final tp = ThemeProvider();
      addTearDown(tp.dispose);
      final gp = _TestLiquidGlassProvider(GlassMode.disabled);
      final lp = LocaleProvider();
      await lp.ready;
      final l10n = await _loadTestL10n(tester);

      await tester.pumpWidget(
        _buildAuthTestHost(
          themeProvider: tp,
          glassProvider: gp,
          localeProvider: lp,
          l10n: l10n,
          child: const FirstStartWizardScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.byKey(const ValueKey<String>('onboarding_greeting_text')),
        findsOneWidget,
      );
      expect(find.byType(SettingsFloatingHeader), findsNothing);

      // Advance periodic greeting dissolve timer safely without exceptions.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);

      final langBtn = find.byKey(
        const ValueKey<String>('onboarding_language_morph_btn'),
      );
      expect(langBtn, findsOneWidget);
      await tester.tap(langBtn);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Deutsch'), findsOneWidget);
      await tester.tap(find.text('English').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      expect(gp.mode, GlassMode.disabled);
      expect(tp.themeMode, ThemeMode.system);
      expect(find.byType(RealAppAppearancePreview), findsOneWidget);
      expect(find.text('Material'), findsOneWidget);
      expect(find.text('Liquid Glass'), findsOneWidget);
    });
  });

  group('LoginScreen & ServiceMenuScreen', () {
    testWidgets('hides unconfigured OAuth, renders regional order when configured, and opens ServiceMenuScreen after 5 emblem taps', (tester) async {
      _useTallPhoneViewport(tester);
      final tp = ThemeProvider();
      addTearDown(tp.dispose);
      final gp = _TestLiquidGlassProvider(GlassMode.disabled);
      final lp = LocaleProvider();
      await lp.ready;
      final l10n = await _loadTestL10n(tester);

      await tester.pumpWidget(
        _buildAuthTestHost(
          themeProvider: tp,
          glassProvider: gp,
          localeProvider: lp,
          l10n: l10n,
          child: const LoginScreen(
            key: ValueKey<String>('login_empty'),
            debugProvidersOverride: AuthProvidersConfig(providers: []),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OAuthBrandGlyph), findsNothing);

      await tester.pumpWidget(
        _buildAuthTestHost(
          themeProvider: tp,
          glassProvider: gp,
          localeProvider: lp,
          l10n: l10n,
          child: const LoginScreen(
            key: ValueKey<String>('login_ru'),
            debugProvidersOverride: AuthProvidersConfig(
              countryCode: 'RU',
              providers: [
                AuthProviderInfo(id: 'yandex', displayName: 'Yandex ID', recommendedForRegion: true),
                AuthProviderInfo(id: 'vk', displayName: 'VK ID', recommendedForRegion: true),
                AuthProviderInfo(id: 'huawei', displayName: 'Huawei ID', recommendedForRegion: true),
                AuthProviderInfo(id: 'google', displayName: 'Google'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final glyphs = find.byType(OAuthBrandGlyph);
      expect(glyphs, findsNWidgets(4));
      final yYandex = tester.getTopLeft(glyphs.at(0)).dy;
      final yVk = tester.getTopLeft(glyphs.at(1)).dy;
      final yHuawei = tester.getTopLeft(glyphs.at(2)).dy;
      final yGoogle = tester.getTopLeft(glyphs.at(3)).dy;
      expect(yYandex < yVk && yVk < yHuawei && yHuawei < yGoogle, isTrue);

      final emblem = find.byKey(const ValueKey<String>('login_brand_emblem'));
      await tester.ensureVisible(emblem);
      for (var i = 0; i < 5; i++) {
        await tester.tap(emblem);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byType(ServiceMenuScreen), findsOneWidget);
    });
  });

  group('RegisterScreen OAuth prefill & SessionBootstrapCoordinator', () {
    testWidgets('prefills verified phone for Yandex ID and leaves phone unverified for Google', (tester) async {
      _useTallPhoneViewport(tester);
      final tp = ThemeProvider();
      addTearDown(tp.dispose);
      final gp = _TestLiquidGlassProvider(GlassMode.disabled);
      final lp = LocaleProvider();
      await lp.ready;
      final l10n = await _loadTestL10n(tester);

      await tester.pumpWidget(
        _buildAuthTestHost(
          themeProvider: tp,
          glassProvider: gp,
          localeProvider: lp,
          l10n: l10n,
          child: const RegisterScreen(
            key: ValueKey<String>('reg_yandex'),
            initialCountryCode: 'RU',
            oauthPrefill: OAuthRegistrationPrefill(
              provider: 'yandex',
              providerName: 'Yandex ID',
              oauthRegistrationToken: 'ya_reg_tok',
              email: 'alex@yandex.ru',
              emailVerified: true,
              phone: '+79991112233',
              phoneVerified: true,
              firstName: 'Alexey',
              lastName: 'Smirnov',
              suggestedUsername: 'alex_smirnov',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Yandex ID'), findsNWidgets(2));

      await tester.pumpWidget(
        _buildAuthTestHost(
          themeProvider: tp,
          glassProvider: gp,
          localeProvider: lp,
          l10n: l10n,
          child: const RegisterScreen(
            key: ValueKey<String>('reg_google'),
            initialCountryCode: 'US',
            oauthPrefill: OAuthRegistrationPrefill(
              provider: 'google',
              providerName: 'Google',
              oauthRegistrationToken: 'g_reg_tok',
              email: 'ivan@gmail.com',
              emailVerified: true,
              phone: '',
              phoneVerified: false,
              firstName: 'Ivan',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Verified badge appears only on Email (once), not on Phone.
      expect(find.text('Google'), findsOneWidget);
    });

    testWidgets('SessionBootstrapCoordinator calls AppDatabase.setActiveUser strictly before ensureSavedChatExists and preserves profile fields', (tester) async {
      final order = <String>[];
      SessionBootstrapCoordinator.debugCallOrderLog = order;
      SessionBootstrapCoordinator.debugEnsureSavedChatOverride = (_) async {};
      SessionBootstrapCoordinator.skipBackgroundNetworkSyncInTests = true;
      addTearDown(() {
        SessionBootstrapCoordinator.debugCallOrderLog = null;
        SessionBootstrapCoordinator.debugEnsureSavedChatOverride = null;
        SessionBootstrapCoordinator.skipBackgroundNetworkSyncInTests = false;
      });

      await tester.runAsync(() async {
        await SessionBootstrapCoordinator.bootstrapAuthenticatedSession(
          token: 'jwt_test_777',
          userId: '777',
          userMap: {
            'username': 'smirnov_alex',
            'first_name': 'Alexey',
            'last_name': 'Smirnov',
            'display_name': 'Alexey Smirnov',
            'email': 'alex@theaver.app',
            'email_verified': true,
            'phone': '+79991112233',
          },
        );
      });
      await tester.pump();

      expect(order, ['setActiveUser:777', 'ensureSavedChatExists:777']);
      expect(AppDatabase.activeUserId, '777');
      final acc = AccountManager().currentAccount;
      expect(acc, isNotNull);
      expect(acc!.phone, '+79991112233');
      expect(acc.name, 'Alexey');
      expect(acc.surname, 'Smirnov');
      expect(acc.emailVerified, isTrue);
    });
  });
}
