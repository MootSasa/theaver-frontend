import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/theav_theme.dart';
import 'package:theaver/screens/settings/profile_screen.dart';
import 'package:theaver/services/account_manager.dart';
import 'package:theaver/services/display_cutout_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/peer_customization_cache.dart';
import 'package:theaver/services/power_saving_provider.dart';
import 'package:theaver/services/profile_instant_cache.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/services/theav_theme_service.dart';
import 'package:theaver/theme/app_theme.dart';
import 'package:theaver/theme/theme_provider.dart';
import 'package:theaver/widgets/profile/liquid_glass_info_panel.dart';
import 'package:theaver/widgets/profile/liquid_glass_music_status.dart';
import 'package:theaver/widgets/profile/liquid_glass_profile_buttons.dart';
import 'package:theaver/widgets/profile/profile_section_pill.dart';

class _TestAppLocalizations extends AppLocalizations {
  _TestAppLocalizations(super.locale);

  static const Map<String, String> _translations = {
    'profile_online': 'в сети',
    'chat_online': 'в сети',
    'chat_offline': 'не в сети',
    'profile_choose_photo': 'Фото',
    'profile_edit_btn': 'Изменить',
    'profile_menu_change_color': 'Цвет',
    'profile_phone': 'телефон',
    'profile_bio': 'о себе',
    'profile_username': 'имя пользователя',
    'profile_tab_wall': 'Стена',
    'profile_tab_gifts': 'Подарки',
    'profile_tab_media': 'Медиа',
  };

  @override
  String translate(String key, [Map<String, String>? params]) =>
      _translations[key] ?? key;
}

class _TestAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _TestAppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(_TestAppLocalizations(locale));

  @override
  bool shouldReload(covariant _TestAppLocalizationsDelegate old) => false;
}

TheavTheme _builtInById(String id) {
  return TheavThemeService.builtInThemes.firstWhere((t) => t.id == id);
}

Color _findFirstFilledContainerColor(WidgetTester tester, Finder root) {
  final descendants = find.descendant(
    of: root,
    matching: find.byType(Container),
  );
  for (final element in descendants.evaluate()) {
    final w = element.widget as Container;
    final dec = w.decoration;
    if (dec is BoxDecoration && dec.color != null) {
      return dec.color!;
    }
  }
  fail('Expected a Container with BoxDecoration.color inside $root');
}

Color _findNearestAncestorFilledColor(WidgetTester tester, Finder descendant) {
  final ancestors = find.ancestor(
    of: descendant,
    matching: find.byType(Container),
  );
  for (final element in ancestors.evaluate()) {
    final w = element.widget as Container;
    final dec = w.decoration;
    if (dec is BoxDecoration && dec.color != null) {
      return dec.color!;
    }
  }
  fail('Expected an ancestor Container with BoxDecoration.color for $descendant');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUserId = 'profile_mat_test_1';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      '${testUserId}_profile_music_title': 'Midnight City',
      '${testUserId}_profile_music_author': 'M83',
    });
    await SettingsService().init();
    DisplayCutoutService.instance.resetForTesting();
    PeerCustomizationCache.instance.clearForTesting();
    PowerSavingProvider.instance.setSettingsForTest(
      PowerSavingSettings.defaults(),
    );

    await AccountManager().init();
    if (AccountManager().hasAccount(testUserId)) {
      await AccountManager().removeAccount(testUserId);
    }
    await AccountManager().addAccount(
      Account(
        userId: testUserId,
        token: '',
        username: 'theme_tester',
        name: 'Theme',
        surname: 'Tester',
        phone: '+7 999 123 45 67',
        bio: 'Adaptive Material UI',
        lastLogin: DateTime.now(),
      ),
    );

    ProfileInstantCache.instance.putUserSnapshot(
      const CachedUserProfileSnapshot(
        userId: testUserId,
        name: 'Theme',
        surname: 'Tester',
        username: 'theme_tester',
        phone: '+7 999 123 45 67',
        bio: 'Adaptive Material UI',
        musicTitle: 'Midnight City',
        musicAuthor: 'M83',
        colorPresetId: 'blue',
      ),
    );
  });

  tearDown(() async {
    DisplayCutoutService.instance.resetForTesting();
    PeerCustomizationCache.instance.clearForTesting();
    PowerSavingProvider.instance.setSettingsForTest(
      PowerSavingSettings.defaults(),
    );
    if (AccountManager().hasAccount(testUserId)) {
      await AccountManager().removeAccount(testUserId);
    }
  });

  void configurePhoneViewport(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(393.0, 852.0);
    tester.view.padding = const FakeViewPadding(top: 54.0, bottom: 34.0);
    tester.view.viewPadding = const FakeViewPadding(top: 54.0, bottom: 34.0);
    addTearDown(tester.view.reset);
  }

  group('ProfileScreen Material theme & system brightness adaptation', () {
    testWidgets(
      'Follows system ThemeMode (Light <-> Dark) even when ProfileColorPresets.blue cover is active',
      (tester) async {
        configurePhoneViewport(tester);
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        final glassProvider = LiquidGlassProvider();
        await glassProvider.setMode(GlassMode.disabled);

        final profileThemeProvider = ProfileThemeProvider();
        await profileThemeProvider.init();
        await profileThemeProvider.setPreset(ProfileColorPresets.blue);

        final emeraldLight = _builtInById('emerald_nature');
        final emeraldDark = _builtInById('emerald_nature_dark');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<LiquidGlassProvider>.value(
                value: glassProvider,
              ),
              ChangeNotifierProvider<ProfileThemeProvider>.value(
                value: profileThemeProvider,
              ),
              ChangeNotifierProvider<PeerCustomizationCache>.value(
                value: PeerCustomizationCache.instance,
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.fromTheavTheme(emeraldLight),
              darkTheme: AppTheme.fromTheavTheme(emeraldDark),
              themeMode: ThemeMode.system,
              localizationsDelegates: const [
                _TestAppLocalizationsDelegate(),
              ],
              home: const ProfileScreen(
                entityType: ProfileEntityType.self,
                initialName: 'Theme Tester',
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // 1. System Light mode: Material buttons and panels use Light Emerald palette.
        final lightBackIcon = tester.widget<iconoir.NavArrowLeft>(
          find.byType(iconoir.NavArrowLeft),
        );
        final lightMoreIcon = tester.widget<iconoir.MoreVert>(
          find.byType(iconoir.MoreVert),
        );
        expect(lightBackIcon.color, equals(emeraldLight.palette.onSurface));
        expect(lightMoreIcon.color, equals(emeraldLight.palette.onSurface));

        expect(
          _findNearestAncestorFilledColor(
            tester,
            find.byType(iconoir.NavArrowLeft),
          ).computeLuminance(),
          greaterThan(0.75),
        );
        expect(
          _findNearestAncestorFilledColor(
            tester,
            find.byType(iconoir.MoreVert),
          ).computeLuminance(),
          greaterThan(0.75),
        );

        final lightCamIcon = tester.widget<iconoir.Camera>(
          find.byType(iconoir.Camera),
        );
        expect(lightCamIcon.color, equals(emeraldLight.palette.onSurface));
        expect(
          _findFirstFilledContainerColor(
            tester,
            find.byType(LiquidGlassProfileButtons),
          ).computeLuminance(),
          greaterThan(0.75),
        );

        final lightMusicIcon = tester.widget<iconoir.MusicDoubleNote>(
          find.byType(iconoir.MusicDoubleNote),
        );
        final lightMusicText = tester.widget<Text>(
          find.text('Midnight City - M83'),
        );
        expect(lightMusicIcon.color, equals(emeraldLight.palette.primary));
        expect(lightMusicText.style?.color, equals(emeraldLight.palette.onSurface));
        expect(
          _findFirstFilledContainerColor(
            tester,
            find.byType(LiquidGlassMusicStatus),
          ).computeLuminance(),
          greaterThan(0.75),
        );

        final lightQrIcon = tester.widget<iconoir.QrCode>(
          find.byType(iconoir.QrCode),
        );
        final lightInfoValue = tester.widget<Text>(find.text('@theme_tester'));
        expect(lightQrIcon.color, equals(emeraldLight.palette.primary));
        expect(lightInfoValue.style?.color, equals(emeraldLight.palette.onSurface));
        expect(
          _findFirstFilledContainerColor(
            tester,
            find.byType(LiquidGlassInfoPanel),
          ).computeLuminance(),
          greaterThan(0.75),
        );

        final lightSectionLabel = tester.widget<Text>(find.text('Стена'));
        expect(
          lightSectionLabel.style?.color,
          equals(emeraldLight.palette.onSurface),
        );
        expect(
          _findFirstFilledContainerColor(
            tester,
            find.byType(ProfileSectionPill),
          ).computeLuminance(),
          greaterThan(0.75),
        );

        // 2. Switch system brightness to Dark: all Material controls flip immediately.
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        final darkBackIcon = tester.widget<iconoir.NavArrowLeft>(
          find.byType(iconoir.NavArrowLeft),
        );
        final darkMoreIcon = tester.widget<iconoir.MoreVert>(
          find.byType(iconoir.MoreVert),
        );
        expect(darkBackIcon.color, equals(emeraldDark.palette.onSurface));
        expect(darkMoreIcon.color, equals(emeraldDark.palette.onSurface));

        expect(
          _findNearestAncestorFilledColor(
            tester,
            find.byType(iconoir.NavArrowLeft),
          ).computeLuminance(),
          lessThan(0.15),
        );
        expect(
          _findNearestAncestorFilledColor(
            tester,
            find.byType(iconoir.MoreVert),
          ).computeLuminance(),
          lessThan(0.15),
        );

        final darkCamIcon = tester.widget<iconoir.Camera>(
          find.byType(iconoir.Camera),
        );
        expect(darkCamIcon.color, equals(emeraldDark.palette.onSurface));
        expect(
          _findFirstFilledContainerColor(
            tester,
            find.byType(LiquidGlassProfileButtons),
          ).computeLuminance(),
          lessThan(0.15),
        );

        final darkMusicIcon = tester.widget<iconoir.MusicDoubleNote>(
          find.byType(iconoir.MusicDoubleNote),
        );
        final darkMusicText = tester.widget<Text>(
          find.text('Midnight City - M83'),
        );
        expect(darkMusicIcon.color, equals(emeraldDark.palette.primary));
        expect(darkMusicText.style?.color, equals(emeraldDark.palette.onSurface));
        expect(
          _findFirstFilledContainerColor(
            tester,
            find.byType(LiquidGlassMusicStatus),
          ).computeLuminance(),
          lessThan(0.15),
        );

        final darkQrIcon = tester.widget<iconoir.QrCode>(
          find.byType(iconoir.QrCode),
        );
        final darkInfoValue = tester.widget<Text>(find.text('@theme_tester'));
        expect(darkQrIcon.color, equals(emeraldDark.palette.primary));
        expect(darkInfoValue.style?.color, equals(emeraldDark.palette.onSurface));
        expect(
          _findFirstFilledContainerColor(
            tester,
            find.byType(LiquidGlassInfoPanel),
          ).computeLuminance(),
          lessThan(0.15),
        );

        final darkSectionLabel = tester.widget<Text>(find.text('Стена'));
        expect(
          darkSectionLabel.style?.color,
          equals(emeraldDark.palette.onSurface),
        );
        expect(
          _findFirstFilledContainerColor(
            tester,
            find.byType(ProfileSectionPill),
          ).computeLuminance(),
          lessThan(0.15),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'Dynamically updates all buttons, panels, and section pill dropdown across active app themes',
      (tester) async {
        configurePhoneViewport(tester);

        final glassProvider = LiquidGlassProvider();
        await glassProvider.setMode(GlassMode.disabled);

        final profileThemeProvider = ProfileThemeProvider();
        await profileThemeProvider.init();
        await profileThemeProvider.setPreset(ProfileColorPresets.blue);

        final themeProvider = ThemeProvider();
        final warmRomance = _builtInById('warm_romance');
        final daylightNeon = _builtInById('daylight_neon');
        final midnightNeon = _builtInById('midnight_neon');

        await themeProvider.setActiveTheme(warmRomance);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
              ChangeNotifierProvider<LiquidGlassProvider>.value(
                value: glassProvider,
              ),
              ChangeNotifierProvider<ProfileThemeProvider>.value(
                value: profileThemeProvider,
              ),
              ChangeNotifierProvider<PeerCustomizationCache>.value(
                value: PeerCustomizationCache.instance,
              ),
            ],
            child: Consumer<ThemeProvider>(
              builder: (context, tp, _) {
                return MaterialApp(
                  theme: tp.lightThemeData,
                  darkTheme: tp.darkThemeData,
                  themeMode: tp.themeMode,
                  localizationsDelegates: const [
                    _TestAppLocalizationsDelegate(),
                  ],
                  home: const ProfileScreen(
                    entityType: ProfileEntityType.self,
                    initialName: 'Theme Tester',
                  ),
                );
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // 1. Warm Romance (Light, Pink/Rose).
        expect(
          tester.widget<iconoir.NavArrowLeft>(find.byType(iconoir.NavArrowLeft)).color,
          equals(warmRomance.palette.onSurface),
        );
        expect(
          tester.widget<iconoir.Camera>(find.byType(iconoir.Camera)).color,
          equals(warmRomance.palette.onSurface),
        );
        expect(
          tester.widget<iconoir.QrCode>(find.byType(iconoir.QrCode)).color,
          equals(warmRomance.palette.primary),
        );
        expect(
          tester.widget<Text>(find.text('@theme_tester')).style?.color,
          equals(warmRomance.palette.onSurface),
        );
        final warmInfoFill = _findFirstFilledContainerColor(
          tester,
          find.byType(LiquidGlassInfoPanel),
        );
        expect(warmInfoFill.r, greaterThan(warmInfoFill.g));

        // Open ProfileSectionPill menu and inspect active & inactive row theme colors.
        await tester.tap(find.text('Стена'));
        await tester.pumpAndSettle();

        final selectedMenuRowText = tester.widget<Text>(find.text('Стена'));
        final unselectedMenuRowText = tester.widget<Text>(find.text('Подарки'));
        expect(
          selectedMenuRowText.style?.color,
          equals(warmRomance.palette.primary),
        );
        expect(
          unselectedMenuRowText.style?.color,
          equals(warmRomance.palette.onSurface),
        );

        // Close section menu before switching theme.
        await tester.tap(find.text('Стена'));
        await tester.pumpAndSettle();

        // 2. Switch app theme to Daylight Neon (Light, Violet).
        await themeProvider.setActiveTheme(daylightNeon);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          tester.widget<iconoir.NavArrowLeft>(find.byType(iconoir.NavArrowLeft)).color,
          equals(daylightNeon.palette.onSurface),
        );
        expect(
          tester.widget<iconoir.Camera>(find.byType(iconoir.Camera)).color,
          equals(daylightNeon.palette.onSurface),
        );
        expect(
          tester.widget<iconoir.QrCode>(find.byType(iconoir.QrCode)).color,
          equals(daylightNeon.palette.primary),
        );
        expect(
          tester.widget<Text>(find.text('@theme_tester')).style?.color,
          equals(daylightNeon.palette.onSurface),
        );
        expect(
          tester.widget<Text>(find.text('Стена')).style?.color,
          equals(daylightNeon.palette.onSurface),
        );
        final daylightInfoFill = _findFirstFilledContainerColor(
          tester,
          find.byType(LiquidGlassInfoPanel),
        );
        expect(daylightInfoFill.b, greaterThan(daylightInfoFill.g));

        // 3. Switch app theme to Midnight Neon (Dark OLED, Neon Violet).
        await themeProvider.setActiveTheme(midnightNeon);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          tester.widget<iconoir.NavArrowLeft>(find.byType(iconoir.NavArrowLeft)).color,
          equals(midnightNeon.palette.onSurface),
        );
        expect(
          tester.widget<iconoir.Camera>(find.byType(iconoir.Camera)).color,
          equals(midnightNeon.palette.onSurface),
        );
        expect(
          tester.widget<iconoir.QrCode>(find.byType(iconoir.QrCode)).color,
          equals(midnightNeon.palette.primary),
        );
        expect(
          tester.widget<Text>(find.text('@theme_tester')).style?.color,
          equals(midnightNeon.palette.onSurface),
        );
        expect(
          _findFirstFilledContainerColor(
            tester,
            find.byType(LiquidGlassInfoPanel),
          ).computeLuminance(),
          lessThan(0.08),
        );
        expect(
          _findFirstFilledContainerColor(
            tester,
            find.byType(LiquidGlassProfileButtons),
          ).computeLuminance(),
          lessThan(0.08),
        );
        expect(
          _findFirstFilledContainerColor(
            tester,
            find.byType(ProfileSectionPill),
          ).computeLuminance(),
          lessThan(0.08),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      },
    );
  });
}
