import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/name_color_preset.dart';
import 'package:theaver/models/profile_customization.dart';
import 'package:theaver/screens/settings/profile_banner_editor_screen.dart';
import 'package:theaver/screens/settings/profile_customization_screen.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/peer_customization_cache.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/widgets/common/adaptive_switch.dart';
import 'package:theaver/widgets/common/glass_modal_sheet.dart';
import 'package:theaver/widgets/chat/message_reply_info.dart';
import 'package:theaver/widgets/profile/floating_emoji_status_menu.dart';
import 'package:theaver/widgets/profile/floating_reply_emoji_menu.dart';
import 'package:theaver/widgets/profile/name_color_picker.dart';
import 'package:theaver/widgets/profile/profile_banner_layer.dart';
import 'package:theaver/widgets/profile/profile_floating_top_switcher.dart';
import 'package:theaver/widgets/message/collapsible_blockquote_widget.dart';
import 'package:theaver/widgets/profile/reply_background_emoji_layer.dart';
import 'package:theaver/widgets/profile/reply_message_preview_card.dart';
import 'package:theaver/widgets/user/avatar_with_status.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:theaver/widgets/user/emoji_status_badge.dart';

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
  bool shouldReload(_PreloadedAppLocalizationsDelegate old) => false;
}

Widget _buildTestHarness({
  required ProfileThemeProvider themeProvider,
  required LiquidGlassProvider glassProvider,
  Brightness brightness = Brightness.dark,
  int initialTab = 0,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProfileThemeProvider>.value(value: themeProvider),
      ChangeNotifierProvider<LiquidGlassProvider>.value(value: glassProvider),
      ChangeNotifierProvider<PeerCustomizationCache>.value(
        value: PeerCustomizationCache.instance,
      ),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.dark
          ? ThemeData.dark(useMaterial3: true)
          : ThemeData.light(useMaterial3: true),
      home: ProfileCustomizationScreen(initialTab: initialTab),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
  });

  testWidgets(
    'Renders compact word-fitted Liquid Glass switcher with smooth animation, hides avatar online dot, and scrolls Profile tab freely top-to-bottom',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final themeProvider = ProfileThemeProvider();
      final glassProvider = LiquidGlassProvider();
      await glassProvider.setMode(GlassMode.full);

      await tester.pumpWidget(
        _buildTestHarness(
          themeProvider: themeProvider,
          glassProvider: glassProvider,
        ),
      );
      await tester.pump();

      // 1. Compact floating top switcher via LiquidGlassTabBar.buildGlassPillBar (same architecture as EmojiStickerPanel)
      expect(find.byType(ProfileFloatingBackButton), findsOneWidget);
      expect(find.byType(ProfileFloatingSwitcherScaffold), findsOneWidget);
      expect(find.text('Profile Customization'), findsNothing);
      expect(find.text('Profile'), findsWidgets);
      expect(find.text('Chat Name'), findsWidgets);
      expect(find.text('Status'), findsNothing);

      final gestureOverlayFinder = find.byKey(
        const ValueKey('lg-animated-nav-gesture-overlay'),
      );
      expect(gestureOverlayFinder, findsOneWidget);
      final overlayRect = tester.getRect(gestureOverlayFinder);
      final scaffoldCtx = tester.element(
        find.byType(ProfileFloatingSwitcherScaffold),
      );
      final shortMeasured = ProfileFloatingSwitcherScaffold.measureCompactWidth(
        scaffoldCtx,
        const <String>['Tab', 'Two'],
        maxWidth: 320.0,
      );
      final fullMeasured = ProfileFloatingSwitcherScaffold.measureCompactWidth(
        scaffoldCtx,
        const <String>['Profile', 'Chat Name'],
        maxWidth: 320.0,
      );
      // Width scales strictly with exact word sizes and matches compact 38px height
      expect(shortMeasured, lessThan(130.0));
      expect(shortMeasured, lessThan(fullMeasured));
      expect(overlayRect.width, closeTo(fullMeasured - 6.0, 0.5));
      expect(overlayRect.height, lessThanOrEqualTo(kProfileFloatingBarHeight));

      // Anti-AI-slop checks: no AppBar, no Live Preview label, no bottom Save/Reset buttons
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Live Preview'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);

      // 2. Every AvatarWithStatus on screen has isOnline == false
      final avatars = tester.widgetList<AvatarWithStatus>(
        find.byType(AvatarWithStatus),
      );
      expect(avatars, isNotEmpty);
      for (final avatar in avatars) {
        expect(avatar.isOnline, isFalse);
      }

      // 3. Full-screen gradient preset + smooth top-to-bottom Profile tab scrolling under the floating switcher
      await themeProvider.setPreset(ProfileColorPresets.skyBlueGrad);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      final profileListFinder = find.byKey(
        const PageStorageKey<String>('profile_customization_tab_profile'),
      );
      expect(profileListFinder, findsOneWidget);

      await tester.drag(profileListFinder, const Offset(0, -320));
      await tester.pump();
      final coverHeaderRect = tester.getRect(find.text('Cover & Banner'));
      expect(coverHeaderRect.top, lessThan(overlayRect.bottom));
      expect(tester.takeException(), isNull);

      // Scroll all the way down to bottom section and back up smoothly
      await tester.drag(profileListFinder, const Offset(0, -360));
      await tester.pump();
      expect(find.text('All Platform Badges'), findsOneWidget);

      await tester.drag(profileListFinder, const Offset(0, 680));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Animates switching smoothly across Classic, Lite, and Full modes via both tap and swipe, and eliminates double panels on Chat Name tab',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final themeProvider = ProfileThemeProvider();
      final glassProvider = LiquidGlassProvider();

      for (final mode in <GlassMode>[
        GlassMode.disabled,
        GlassMode.lite,
        GlassMode.full,
      ]) {
        await glassProvider.setMode(mode);
        for (final brightness in <Brightness>[
          Brightness.light,
          Brightness.dark,
        ]) {
          await tester.pumpWidget(
            _buildTestHarness(
              themeProvider: themeProvider,
              glassProvider: glassProvider,
              brightness: brightness,
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);

          if (mode == GlassMode.disabled) {
            final classicRect = tester.getRect(
              find.byKey(const ValueKey<String>('profile_classic_top_switcher')),
            );
            final expectedW =
                ProfileFloatingSwitcherScaffold.measureCompactWidth(
              tester.element(find.byType(ProfileFloatingSwitcherScaffold)),
              const <String>['Profile', 'Chat Name'],
              maxWidth: 320.0,
            );
            expect(classicRect.width, closeTo(expectedW, 0.5));
            expect(classicRect.height, equals(kProfileFloatingBarHeight));
            await tester.tap(find.text('Chat Name'));
          } else {
            final navOverlayRect = tester.getRect(
              find.byKey(const ValueKey('lg-animated-nav-gesture-overlay')),
            );
            await tester.tapAt(
              Offset(
                navOverlayRect.left + navOverlayRect.width * 0.75,
                navOverlayRect.center.dy,
              ),
            );
          }

          // Verify mid-flight PageView animation is actively interpolating (not snapping instantaneously)
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 120));
          final pageView = tester.widget<PageView>(
            find.byType(PageView).first,
          );
          final midPage = pageView.controller?.page ?? 0.0;
          expect(midPage, greaterThan(0.05));
          expect(midPage, lessThan(0.99));

          // Settle transition
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.byType(ReplyMessagePreviewCard), findsOneWidget);

          // Verify NO double panels on Chat Name tab:
          // 1) ReplyMessagePreviewCard is NOT wrapped inside ProfileGlassSection
          expect(
            find.ancestor(
              of: find.byType(ReplyMessagePreviewCard),
              matching: find.byType(ProfileGlassSection),
            ),
            findsNothing,
          );
          // 2) NameColorPaletteRow + ReplyStripStyleSelector share ONE single unified ProfileGlassSection
          final nameTabFinder = find.byKey(
            const PageStorageKey<String>('profile_customization_tab_name'),
          );
          expect(
            find.descendant(
              of: nameTabFinder,
              matching: find.byType(ProfileGlassSection),
            ),
            findsOneWidget,
          );
          final stripSelector = tester.widget<ReplyStripStyleSelector>(
            find.byType(ReplyStripStyleSelector),
          );
          expect(stripSelector.flatInCard, isTrue);

          // Verify horizontal swipe is disabled (NeverScrollableScrollPhysics)
          final pageViewAfter = tester.widget<PageView>(
            find.byType(PageView).first,
          );
          expect(pageViewAfter.physics, isA<NeverScrollableScrollPhysics>());
          await tester.drag(
            find.byType(PageView).first,
            const Offset(320, 0),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          // Still on Chat Name tab because swipe is disabled
          expect(
            find.byKey(const ValueKey<String>('profile_emoji_status_row')),
            findsNothing,
          );

          // Switch back to Profile exclusively via top bar pill tap
          if (mode == GlassMode.disabled) {
            await tester.tap(find.text('Profile'));
          } else {
            final navOverlayRect = tester.getRect(
              find.byKey(const ValueKey('lg-animated-nav-gesture-overlay')),
            );
            await tester.tapAt(
              Offset(
                navOverlayRect.left + navOverlayRect.width * 0.25,
                navOverlayRect.center.dy,
              ),
            );
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(
            find.byKey(const ValueKey<String>('profile_emoji_status_row')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'Emoji Status picker has no short-note input, selects and clears status at Frame 0, and updates frame/badge/name-color immediately',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final devBadge = UserBadge.builtInDefaults.firstWhere(
        (b) => b.id == 'developer',
      );
      final themeProvider = ProfileThemeProvider()
        ..seedOwnCustomizationForTest(
          PeerCustomization(
            badge: devBadge,
            badgeIsDisplayed: true,
          ),
          userId: 'u_test_1',
        );
      final glassProvider = LiquidGlassProvider();

      await tester.pumpWidget(
        _buildTestHarness(
          themeProvider: themeProvider,
          glassProvider: glassProvider,
        ),
      );
      await tester.pump();

      // 1. Emoji Status row on Profile tab opens Telegram-style floating menu WITHOUT short-note input
      final statusRow = find.byKey(
        const ValueKey<String>('profile_emoji_status_row'),
      );
      expect(statusRow, findsOneWidget);
      expect(themeProvider.currentEmojiStatus, isNull);
      expect(find.text('Choose emoji and note'), findsNothing);

      await tester.tap(statusRow);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(FloatingEmojiStatusMenu), findsOneWidget);
      expect(find.byType(TheavGlassModalSheet), findsNothing);
      final menuRect = tester.getRect(find.byType(FloatingEmojiStatusMenu));
      expect(menuRect.left, greaterThanOrEqualTo(8.0));
      expect(menuRect.right, lessThanOrEqualTo(382.0));
      expect(menuRect.top, greaterThanOrEqualTo(8.0));
      expect(menuRect.bottom, lessThanOrEqualTo(834.0));
      expect(menuRect.height, lessThanOrEqualTo(360.0));
      expect(find.text('Add a short note (up to 64 chars)'), findsNothing);

      // Tap emoji inside floating menu -> instant Frame-0 status update with empty note and auto-close
      await tester.tap(
        find.descendant(
          of: find.byType(FloatingEmojiStatusMenu),
          matching: find.text('😀'),
        ).first,
      );
      await tester.pump();
      expect(themeProvider.currentEmojiStatus?.emoji, '😀');
      expect(themeProvider.currentEmojiStatus?.note, isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FloatingEmojiStatusMenu), findsNothing);

      // Re-open floating menu -> tap clear icon cell (⊝) -> clears status at Frame 0 and auto-closes
      await tester.tap(statusRow);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(FloatingEmojiStatusMenu), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('floating_emoji_status_clear')),
      );
      await tester.pump();
      expect(themeProvider.currentEmojiStatus, isNull);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FloatingEmojiStatusMenu), findsNothing);

      // 2. Tap an avatar decoration frame in the horizontal carousel -> instant apply
      final profileScrollable = find.descendant(
        of: find.byKey(
          const PageStorageKey<String>('profile_customization_tab_profile'),
        ),
        matching: find.byType(Scrollable),
      ).first;
      final firstPreset =
          PeerCustomizationCache.instance.decorationsCatalog.first;
      await tester.scrollUntilVisible(
        find.text(firstPreset.id),
        160.0,
        scrollable: profileScrollable,
      );
      await tester.pump();
      await tester.tap(find.text(firstPreset.id).hitTestable().first);
      await tester.pump();
      expect(themeProvider.currentAvatarDecoration?.id, firstPreset.id);

      // 3. Scroll to Profile Badge section, toggle AdaptiveSwitch -> hides badge immediately
      await tester.scrollUntilVisible(
        find.text('All Platform Badges'),
        200.0,
        scrollable: profileScrollable,
      );
      await tester.pump();
      expect(themeProvider.isBadgeDisplayed, isTrue);
      expect(find.byType(AdaptiveSwitch), findsOneWidget);

      await tester.tap(find.byType(AdaptiveSwitch));
      await tester.pump();
      expect(themeProvider.isBadgeDisplayed, isFalse);
      expect(themeProvider.currentVisibleBadge, isNull);

      // 4. Open All Platform Badges modal sheet -> shows catalog cleanly
      await tester.tap(find.text('All Platform Badges'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(TheavGlassModalSheet), findsOneWidget);
      expect(find.text('CREATOR'), findsWidgets);
      Navigator.of(tester.element(find.byType(TheavGlassModalSheet))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // 5. Switch to 'Chat Name' tab -> ReplyMessagePreviewCard + instant flat strip style update
      await tester.tap(find.text('Chat Name'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ReplyMessagePreviewCard), findsOneWidget);

      final stripSelector = find.byType(ReplyStripStyleSelector);
      expect(stripSelector, findsOneWidget);
      final selectorRect = tester.getRect(stripSelector);
      await tester.tapAt(
        Offset(
          selectorRect.left + selectorRect.width * 0.38,
          selectorRect.center.dy,
        ),
      );
      await tester.pump();
      expect(themeProvider.currentStripStyle, ReplyStripStyle.dualColor);

      // Flush PeerCustomizationCache 500ms persist debounce timer
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'initialTab: 2 opens FloatingEmojiStatusMenu automatically on Profile tab',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final themeProvider = ProfileThemeProvider()
        ..seedOwnCustomizationForTest(
          const PeerCustomization(),
          userId: 'u_test_init2',
        );
      final glassProvider = LiquidGlassProvider();

      await tester.pumpWidget(
        _buildTestHarness(
          themeProvider: themeProvider,
          glassProvider: glassProvider,
          initialTab: 2,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(FloatingEmojiStatusMenu), findsOneWidget);
      expect(find.byType(TheavGlassModalSheet), findsNothing);

      Navigator.of(
        tester.element(find.byType(FloatingEmojiStatusMenu)),
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FloatingEmojiStatusMenu), findsNothing);

      // Flush PeerCustomizationCache 500ms persist debounce timer
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Shows Adjust Banner row when banner exists, edits position/height/zoom/dim/blur & reset, and saves to provider',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final themeProvider = ProfileThemeProvider()
        ..seedOwnCustomizationForTest(
          const PeerCustomization(
            profileBannerUrl: 'https://example.com/banner.webp',
          ),
          userId: 'u_banner_edit',
        );
      final glassProvider = LiquidGlassProvider();

      await tester.pumpWidget(
        _buildTestHarness(
          themeProvider: themeProvider,
          glassProvider: glassProvider,
        ),
      );
      await tester.pump();

      final bannerFinder = find.byKey(
        const ValueKey<String>('profile_customization_banner'),
      );
      expect(bannerFinder, findsOneWidget);
      final initialBannerHeight = tester.getSize(bannerFinder).height;
      expect(initialBannerHeight, closeTo(250.0, 1.0));

      final adjustRowFinder = find.byKey(
        const ValueKey<String>('profile_banner_adjust_row'),
      );
      await tester.ensureVisible(adjustRowFinder);
      await tester.pump();
      expect(adjustRowFinder, findsOneWidget);

      await tester.tap(adjustRowFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(ProfileBannerEditorScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ProfileGlassSection),
          matching: find.byType(ProfileGlassSection),
        ),
        findsNothing,
      );

      final heroAvatar = tester.widget<AvatarWithStatus>(
        find.descendant(
          of: find.byType(ProfileBannerEditorScreen),
          matching: find.byType(AvatarWithStatus),
        ),
      );
      expect(heroAvatar.isOnline, isFalse);

      // No ImageFiltered in ProfileBannerLayer while blur == 0.0
      final blurFilterFinder = find.descendant(
        of: find.descendant(
          of: find.byType(ProfileBannerEditorScreen),
          matching: find.byType(ProfileBannerLayer),
        ),
        matching: find.byType(ImageFiltered),
      );
      expect(blurFilterFinder, findsNothing);

      // Enable blur and verify ImageFiltered mounts
      final blurSliderFinder = find.byKey(
        const ValueKey<String>('banner_blur_slider'),
      );
      await tester.ensureVisible(blurSliderFinder);
      tester.widget<Slider>(blurSliderFinder).onChanged!(6.0);
      await tester.pump();
      expect(blurFilterFinder, findsOneWidget);

      // Tap Reset button and confirm blur resets cleanly
      await tester.tap(
        find.byKey(const ValueKey<String>('banner_editor_reset_btn')),
      );
      await tester.pump();
      expect(blurFilterFinder, findsNothing);

      // Drag preview stage to update focal posX/posY
      await tester.drag(
        find.byKey(const ValueKey<String>('banner_editor_gesture_stage')),
        const Offset(60, -40),
      );
      await tester.pump();

      // Switch height to tall and set zoom/dim/blur
      await tester.tap(
        find.byKey(const ValueKey<String>('banner_height_tall')),
      );
      await tester.pump(const Duration(milliseconds: 220));

      final scaleSliderFinder = find.byKey(
        const ValueKey<String>('banner_scale_slider'),
      );
      tester.widget<Slider>(scaleSliderFinder).onChanged!(1.8);
      final dimSliderFinder = find.byKey(
        const ValueKey<String>('banner_dim_slider'),
      );
      tester.widget<Slider>(dimSliderFinder).onChanged!(0.5);
      tester.widget<Slider>(blurSliderFinder).onChanged!(6.0);
      await tester.pump();

      // Save and verify pop + provider + rendered banner height update
      await tester.tap(
        find.byKey(const ValueKey<String>('banner_editor_save_btn')),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(ProfileBannerEditorScreen), findsNothing);
      final saved = themeProvider.currentBannerLayout;
      expect(saved.heightMode, ProfileBannerHeightMode.tall);
      expect(saved.scale, closeTo(1.8, 0.01));
      expect(saved.dim, closeTo(0.5, 0.01));
      expect(saved.blur, closeTo(6.0, 0.05));
      expect(saved.posX, isNot(0.0));
      expect(saved.posY, isNot(0.0));

      expect(
        tester.getSize(bannerFinder).height,
        greaterThan(initialBannerHeight),
      );

      // Flush PeerCustomizationCache 500ms persist debounce timer
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'ProfileBannerEditorScreen previews in-memory local bytes on 800x600 Liquid Glass surface and passes bytes/layout to onSaveOverride',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final themeProvider = ProfileThemeProvider()
        ..seedOwnCustomizationForTest(
          const PeerCustomization(),
          userId: 'u_banner_local',
        );
      final glassProvider = LiquidGlassProvider();
      await glassProvider.setMode(GlassMode.full);

      // Valid 1x1 transparent PNG
      final pngBytes = Uint8List.fromList(const <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]);

      ProfileBannerLayout? submittedLayout;
      Uint8List? submittedBytes;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProfileThemeProvider>.value(
              value: themeProvider,
            ),
            ChangeNotifierProvider<LiquidGlassProvider>.value(
              value: glassProvider,
            ),
            ChangeNotifierProvider<PeerCustomizationCache>.value(
              value: PeerCustomizationCache.instance,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light(useMaterial3: true),
            home: Builder(
              builder: (ctx) => Center(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => ProfileBannerEditorScreen(
                          initialBytes: pngBytes,
                          initialFileName: 'sample.png',
                          displayName: 'Test User',
                          onSaveOverride: (
                            layout, {
                            filePath,
                            bytes,
                            fileName,
                          }) async {
                            submittedLayout = layout;
                            submittedBytes = bytes;
                            return true;
                          },
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Editor'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Open Editor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(ProfileBannerEditorScreen), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('banner_height_compact')),
      );
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(
        find.byKey(const ValueKey<String>('banner_editor_save_btn')),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(submittedLayout?.heightMode, ProfileBannerHeightMode.compact);
      expect(submittedBytes, equals(pngBytes));
      expect(find.byType(ProfileBannerEditorScreen), findsNothing);

      // Flush PeerCustomizationCache 500ms persist debounce timer
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'ProfileBannerLayer leaves zero opaque pixels along bottom ShaderMask boundary under fractional height, dim, and blur',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(240, 280));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final Uint8List pngBytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 16, 16),
          Paint()..color = const Color(0xFF1890FF),
        );
        final picture = recorder.endRecording();
        final img = await picture.toImage(16, 16);
        final bd = await img.toByteData(format: ui.ImageByteFormat.png);
        img.dispose();
        picture.dispose();
        return bd!.buffer.asUint8List();
      }) as Uint8List;

      final boundaryKey = GlobalKey();
      const double fractionalHeight = 175.3;
      const double testDpr = 2.75;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 200,
                height: 240,
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: fractionalHeight,
                      child: ProfileBannerLayer(
                        localBytes: pngBytes,
                        layout: const ProfileBannerLayout(
                          heightMode: ProfileBannerHeightMode.compact,
                          dim: 0.45,
                          blur: 4.0,
                        ),
                        animate: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          MemoryImage(pngBytes),
          tester.element(find.byType(ProfileBannerLayer)),
        );
      });
      await tester.pump();

      final boundary =
          boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final raster = await tester.runAsync(() async {
        final ui.Image image = await boundary.toImage(pixelRatio: testDpr);
        final ByteData? rgba =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final int width = image.width;
        final int height = image.height;
        image.dispose();
        return (width: width, height: height, bytes: rgba!.buffer.asUint8List());
      }) as ({int width, int height, Uint8List bytes});

      int alphaAt(int x, int y) =>
          raster.bytes[(y * raster.width + x) * 4 + 3];

      final int centerX = raster.width ~/ 2;
      expect(alphaAt(centerX, 30), greaterThan(180));

      final int minRow = (fractionalHeight * testDpr).floor() - 2;
      final int maxRow = (fractionalHeight * testDpr).ceil() + 3;
      expect(maxRow, lessThan(raster.height));

      for (int y = minRow; y <= maxRow; y++) {
        for (final x in <int>[
          raster.width ~/ 4,
          centerX,
          (raster.width * 3) ~/ 4,
        ]) {
          expect(
            alphaAt(x, y),
            equals(0),
            reason: 'Expected zero alpha at boundary pixel ($x, $y)',
          );
        }
      }
    },
  );

  testWidgets(
    'Name tab renders Background Emoji row, previews ReplyBackgroundEmojiLayer watermark, and FloatingReplyEmojiMenu shows monotone-only clear/empty state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final themeProvider = ProfileThemeProvider();
      final glassProvider = LiquidGlassProvider();

      await tester.pumpWidget(
        _buildTestHarness(
          themeProvider: themeProvider,
          glassProvider: glassProvider,
          initialTab: 1,
        ),
      );
      await tester.pump();

      final rowFinder = find.byKey(
        const ValueKey<String>('customization_reply_emoji_row'),
      );
      expect(rowFinder, findsOneWidget);
      expect(find.text('Background Emoji'), findsOneWidget);
      expect(find.byType(ReplyBackgroundEmojiLayer), findsNothing);

      themeProvider.seedOwnCustomizationForTest(
        const PeerCustomization(
          replyEmoji: ReplyEmojiData(
            stickerId: 91,
            stickerUrl: '/uploads/stickers/kitty.webp',
            thumbnailUrl: '/uploads/stickers/kitty_thumb.webp',
            stickerFormat: 'webp',
          ),
        ),
        userId: 'u_self',
      );
      await tester.pump();

      expect(find.byType(ReplyBackgroundEmojiLayer), findsNWidgets(2));
      expect(find.byType(ReplyEmojiGlyph), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(rowFinder);
      await tester.pump();
      await tester.tap(rowFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(FloatingReplyEmojiMenu), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('floating_reply_emoji_clear')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'MessageReplyInfo.forwarded never renders ReplyBackgroundEmojiLayer while reply quotes with replyEmoji do',
    (tester) async {
      final themeProvider = ProfileThemeProvider();
      final preloadedL10n = (await tester.runAsync(
        () => AppLocalizations.delegate.load(const Locale('en')),
      ))!;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProfileThemeProvider>.value(
              value: themeProvider,
            ),
            ChangeNotifierProvider<PeerCustomizationCache>.value(
              value: PeerCustomizationCache.instance,
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: const [Locale('en')],
            localizationsDelegates: [
              _PreloadedAppLocalizationsDelegate(preloadedL10n),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MessageReplyInfo.forwarded(
                      authorName: 'Alice',
                      content: 'Forwarded text',
                    ),
                    const MessageReplyInfo(
                      replyInfo: ReplyInfo(
                        messageId: 'm1',
                        senderId: 'u_bob',
                        senderName: 'Bob',
                        content: 'Original message quote preview',
                        messageType: 'text',
                        replyEmoji: ReplyEmojiData(
                          stickerId: 55,
                          stickerUrl: '/uploads/stickers/star.webp',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final forwardedFinder = find.byWidgetPredicate(
        (w) => w is MessageReplyInfo && w.replyInfo == null,
      );
      final replyFinder = find.byWidgetPredicate(
        (w) => w is MessageReplyInfo && w.replyInfo != null,
      );

      expect(forwardedFinder, findsOneWidget);
      expect(replyFinder, findsOneWidget);

      expect(
        find.descendant(
          of: forwardedFinder,
          matching: find.byType(ReplyBackgroundEmojiLayer),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: replyFinder,
          matching: find.byType(ReplyBackgroundEmojiLayer),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'FloatingEmojiStatusMenu renders clean frosted card without LiquidGlassLens, emoji row has no duplicate emoji, and badge toggle preserves badge',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final devBadge = UserBadge.builtInDefaults.firstWhere(
        (b) => b.id == 'developer',
      );
      final themeProvider = ProfileThemeProvider()
        ..seedOwnCustomizationForTest(
          PeerCustomization(
            badge: devBadge,
            badgeIsDisplayed: true,
            emojiStatus: const EmojiStatusData(
              type: 'unicode',
              emoji: '🔥',
            ),
          ),
          userId: 'u_badge_test_1',
        );

      final glassProvider = LiquidGlassProvider();
      await glassProvider.setMode(GlassMode.full);

      await tester.pumpWidget(
        _buildTestHarness(
          themeProvider: themeProvider,
          glassProvider: glassProvider,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // 1. Emoji Status row:
      final rowFinder = find.byKey(
        const ValueKey<String>('profile_emoji_status_row'),
      );
      expect(rowFinder, findsOneWidget);

      // Exactly ONE EmojiStatusBadge in the row (on the left), NO duplicate on the right
      final badgeInRow = find.descendant(
        of: rowFinder,
        matching: find.byType(EmojiStatusBadge),
      );
      expect(badgeInRow, findsOneWidget);

      // Trailing has EditPencil and Xmark
      expect(
        find.descendant(
          of: rowFinder,
          matching: find.byType(iconoir.EditPencil),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rowFinder,
          matching: find.byType(iconoir.Xmark),
        ),
        findsOneWidget,
      );

      // 2. Open FloatingEmojiStatusMenu:
      await tester.tap(
        find.descendant(
          of: rowFinder,
          matching: find.byType(iconoir.EditPencil),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // In Liquid Glass mode, verify menu card does NOT use LiquidGlassLens (clean Material style)
      expect(find.byType(FloatingEmojiStatusMenu), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FloatingEmojiStatusMenu),
          matching: find.byType(LiquidGlassLens),
        ),
        findsNothing,
      );

      // Close menu by tapping outside
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 3. Badge toggle switch:
      expect(themeProvider.currentOwnBadge, isNotNull);
      final profileListFinder = find.byKey(
        const PageStorageKey<String>('profile_customization_tab_profile'),
      );
      await tester.drag(profileListFinder, const Offset(0, -300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final switchFinder = find.byType(AdaptiveSwitch);
      expect(switchFinder, findsOneWidget);

      // Toggle off
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Badge must STILL exist in themeProvider.currentOwnBadge and the switch stays visible
      expect(themeProvider.currentOwnBadge, isNotNull);
      expect(themeProvider.isBadgeDisplayed, isFalse);
      expect(find.byType(AdaptiveSwitch), findsOneWidget);

      // Let any pending debounce timers settle
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'ReplyBackgroundEmojiLayer slots have zero angle (no tilt) and render directly without Transform.rotate',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(300, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const testEmoji = ReplyEmojiData(
        stickerId: 101,
        stickerUrl: '/stickers/test.webp',
        thumbnailUrl: '/stickers/test_thumb.webp',
        stickerFormat: 'webp',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 250,
              height: 100,
              child: ReplyBackgroundEmojiLayer(
                emoji: testEmoji,
                color: Colors.red,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // With angle == 0.0, zero Transform.rotate widgets are created inside ReplyBackgroundEmojiLayer
      expect(ReplyBackgroundEmojiLayer.slotAngles.every((a) => a == 0.0), isTrue);
      expect(
        find.descendant(
          of: find.byType(ReplyBackgroundEmojiLayer),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
      expect(find.byType(ReplyEmojiGlyph), findsWidgets);
    },
  );

  testWidgets(
    'CollapsibleBlockquoteWidget renders ReplyBackgroundEmojiLayer when quote author has replyEmoji',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 300));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final themeProvider = ProfileThemeProvider();

      const testEmoji = ReplyEmojiData(
        stickerId: 202,
        stickerUrl: '/stickers/author_emoji.webp',
        thumbnailUrl: '/stickers/author_thumb.webp',
        stickerFormat: 'webp',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ProfileThemeProvider>.value(
          value: themeProvider,
          child: const MaterialApp(
            home: Scaffold(
              body: CollapsibleBlockquoteWidget(
                text: 'This is a quote from the author',
                isDark: true,
                isMe: false,
                replyEmoji: testEmoji,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ReplyBackgroundEmojiLayer), findsOneWidget);
    },
  );

  testWidgets(
    'ReplyBackgroundEmojiLayer keeps fixed top-band coordinates and spacing across heights, clips excess rows, and avoids QuoteSolid/footer overlap',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const testEmoji = ReplyEmojiData(
        stickerId: 303,
        stickerUrl: '/stickers/fixed_emoji.webp',
        thumbnailUrl: '/stickers/fixed_emoji_thumb.webp',
        stickerFormat: 'webp',
      );

      Future<List<Rect>> measureRelativeGlyphRects(Size boxSize) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: boxSize.width,
                  height: boxSize.height,
                  child: const ReplyBackgroundEmojiLayer(
                    emoji: testEmoji,
                    color: Colors.teal,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final layerTopLeft = tester.getTopLeft(
          find.byType(ReplyBackgroundEmojiLayer),
        );
        final glyphFinder = find.byType(ReplyEmojiGlyph);
        final rects = <Rect>[];
        for (int i = 0; i < glyphFinder.evaluate().length; i++) {
          rects.add(
            tester.getRect(glyphFinder.at(i)).shift(-layerTopLeft),
          );
        }
        return rects;
      }

      // 1. Fixed top-band coordinates without vertical stretching (64dp vs 280dp)
      final normalRects = await measureRelativeGlyphRects(const Size(250, 64));
      final tallRects = await measureRelativeGlyphRects(const Size(250, 280));

      expect(normalRects, hasLength(10));
      expect(tallRects, hasLength(10));
      for (int i = 0; i < normalRects.length; i++) {
        expect(tallRects[i].left, closeTo(normalRects[i].left, 0.01));
        expect(tallRects[i].top, closeTo(normalRects[i].top, 0.01));
        expect(tallRects[i].bottom, lessThanOrEqualTo(54.0));
      }

      // 2. Organic scatter, varied sizes & comfortable pairwise spacing (no aligned rows/columns, no overlaps)
      expect(normalRects.map((r) => r.top).toSet(), hasLength(10));
      expect(normalRects.map((r) => r.left).toSet(), hasLength(10));
      final widths = normalRects.map((r) => r.width).toSet();
      expect(widths.length, greaterThanOrEqualTo(6));
      expect(
        normalRects.map((r) => r.width).reduce((a, b) => a > b ? a : b),
        greaterThanOrEqualTo(19.0),
      );
      expect(
        normalRects.map((r) => r.width).reduce((a, b) => a < b ? a : b),
        lessThanOrEqualTo(12.5),
      );
      for (int i = 0; i < normalRects.length; i++) {
        for (int j = i + 1; j < normalRects.length; j++) {
          expect(normalRects[i].overlaps(normalRects[j]), isFalse);
          final dx = normalRects[i].center.dx - normalRects[j].center.dx;
          final dy = normalRects[i].center.dy - normalRects[j].center.dy;
          expect(dx * dx + dy * dy, greaterThanOrEqualTo(20.5 * 20.5 - 0.1));
        }
      }

      // 3. Small container heights cut off lower glyphs without vertical compression
      final shortRects = await measureRelativeGlyphRects(const Size(250, 28));
      expect(shortRects, hasLength(5));
      for (final r in shortRects) {
        expect(
          normalRects.any(
            (nr) => (nr.left - r.left).abs() < 0.01 && (nr.top - r.top).abs() < 0.01,
          ),
          isTrue,
        );
      }

      final mediumRects = await measureRelativeGlyphRects(const Size(250, 42));
      expect(mediumRects, hasLength(8));
      for (final r in mediumRects) {
        expect(
          normalRects.any(
            (nr) => (nr.left - r.left).abs() < 0.01 && (nr.top - r.top).abs() < 0.01,
          ),
          isTrue,
        );
      }

      // 4. CollapsibleBlockquoteWidget keeps emojis out of QuoteSolid & footer toggle
      final themeProvider = ProfileThemeProvider();
      final preloadedL10n = (await tester.runAsync(
        () => AppLocalizations.delegate.load(const Locale('en')),
      ))!;

      await tester.pumpWidget(
        ChangeNotifierProvider<ProfileThemeProvider>.value(
          value: themeProvider,
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: const [Locale('en')],
            localizationsDelegates: [
              _PreloadedAppLocalizationsDelegate(preloadedL10n),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(
              body: SizedBox(
                width: 340,
                child: CollapsibleBlockquoteWidget(
                  text: 'First line of a very long collapsible quote block.\n'
                      'Second line that keeps going across the bubble width.\n'
                      'Third line to trigger collapsible blockquote mode.\n'
                      'Fourth line visible when expanded by the user.\n'
                      'Fifth line further down in the quote body.',
                  isCollapsible: true,
                  isDark: true,
                  isMe: false,
                  replyEmoji: testEmoji,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final blockquoteFinder = find.byType(CollapsibleBlockquoteWidget);
      final glyphsInBlockquote = find.descendant(
        of: blockquoteFinder,
        matching: find.byType(ReplyEmojiGlyph),
      );
      expect(glyphsInBlockquote, findsWidgets);

      final quoteIconRect = tester.getRect(
        find.descendant(
          of: blockquoteFinder,
          matching: find.byType(iconoir.QuoteSolid),
        ),
      );
      final footerInkWellRect = tester.getRect(
        find.descendant(
          of: blockquoteFinder,
          matching: find.byType(InkWell),
        ),
      );

      for (int i = 0; i < glyphsInBlockquote.evaluate().length; i++) {
        final glyphRect = tester.getRect(glyphsInBlockquote.at(i));
        expect(glyphRect.overlaps(quoteIconRect), isFalse);
        expect(glyphRect.overlaps(footerInkWellRect), isFalse);
      }
    },
  );

  testWidgets(
    'Chat Name tab adapts panel text & background emoji contrast without altering preview card, shows grey strip mini-pills, and crossfades tab background smoothly over 850ms',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final themeProvider = ProfileThemeProvider()
        ..seedOwnCustomizationForTest(
          const PeerCustomization(
            replyEmoji: ReplyEmojiData(
              stickerId: 404,
              stickerUrl: '/uploads/stickers/adaptive.webp',
              thumbnailUrl: '/uploads/stickers/adaptive_thumb.webp',
              stickerFormat: 'webp',
            ),
            profileBannerUrl: '/uploads/banners/test.jpg',
          ),
          userId: 'u_contrast_test',
        );
      final glassProvider = LiquidGlassProvider();
      await glassProvider.setMode(GlassMode.disabled);

      // 1. Dark cover preset on Chat Name tab -> white contrast panel text & white emoji in row,
      //    while ReplyMessagePreviewCard still renders ReplyBackgroundEmojiLayer in namePreset.primaryColor.
      await tester.pumpWidget(
        _buildTestHarness(
          themeProvider: themeProvider,
          glassProvider: glassProvider,
          initialTab: 1,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final emojiRowFinder = find.byKey(
        const ValueKey<String>('customization_reply_emoji_row'),
      );
      expect(emojiRowFinder, findsOneWidget);

      final darkRowTitle = tester.widget<Text>(
        find.descendant(
          of: emojiRowFinder,
          matching: find.text('Background Emoji'),
        ),
      );
      expect(darkRowTitle.style?.color, equals(Colors.white));

      final darkRowGlyph = tester.widget<ReplyEmojiGlyph>(
        find.descendant(
          of: emojiRowFinder,
          matching: find.byType(ReplyEmojiGlyph),
        ),
      );
      expect(darkRowGlyph.color, equals(Colors.white));
      expect(
        darkRowGlyph.color,
        isNot(equals(themeProvider.currentNameColorPreset.primaryColor)),
      );

      final previewWatermarks = tester
          .widgetList<ReplyBackgroundEmojiLayer>(
            find.descendant(
              of: find.byType(ReplyMessagePreviewCard),
              matching: find.byType(ReplyBackgroundEmojiLayer),
            ),
          )
          .toList();
      expect(previewWatermarks, hasLength(2));
      for (final layer in previewWatermarks) {
        expect(
          layer.color,
          equals(themeProvider.currentNameColorPreset.primaryColor),
        );
      }

      // 2. Verify grey contrast mini-pills under strip-style buttons
      final stripSelectorFinder = find.byType(ReplyStripStyleSelector);
      expect(stripSelectorFinder, findsOneWidget);
      for (final style in ReplyStripStyle.values) {
        final pillFinder = find.descendant(
          of: stripSelectorFinder,
          matching: find.byKey(
            ValueKey<String>('reply_strip_pill_${style.name}'),
          ),
        );
        expect(pillFinder, findsOneWidget);
        final pillBox = tester.widget<DecoratedBox>(pillFinder);
        final pillDeco = pillBox.decoration as BoxDecoration;
        expect(pillDeco.color, isNotNull);
        expect(pillDeco.color!.a, greaterThan(0.0));
        expect(pillDeco.border, isNotNull);
      }
      final selectedPillFinder = find.descendant(
        of: stripSelectorFinder,
        matching: find.byKey(const ValueKey<String>('reply_strip_pill_selected')),
      );
      expect(selectedPillFinder, findsOneWidget);

      // 3. Switch to bright light cover preset -> panel text & trailing emoji adapt to dark #141619
      await themeProvider.setPreset(
        ProfileColorPreset.fromCustomColor(const Color(0xFFF7F5EE)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final lightRowTitle = tester.widget<Text>(
        find.descendant(
          of: emojiRowFinder,
          matching: find.text('Background Emoji'),
        ),
      );
      expect(lightRowTitle.style?.color, equals(const Color(0xFF141619)));

      final lightRowGlyph = tester.widget<ReplyEmojiGlyph>(
        find.descendant(
          of: emojiRowFinder,
          matching: find.byType(ReplyEmojiGlyph),
        ),
      );
      expect(lightRowGlyph.color, equals(const Color(0xFF141619)));

      // 4. Switch from Profile tab to Chat Name tab -> banner stays mounted and both banner & dim overlay crossfade smoothly over 850ms
      await themeProvider.setPreset(ProfileColorPresets.blue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        _buildTestHarness(
          themeProvider: themeProvider,
          glassProvider: glassProvider,
          initialTab: 0,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byKey(const ValueKey<String>('profile_customization_banner')),
        findsOneWidget,
      );

      await tester.tap(find.text('Chat Name'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byKey(const ValueKey<String>('profile_customization_banner')),
        findsOneWidget,
      );

      final dimFadeMid = tester.widget<FadeTransition>(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('profile_customization_tab_dim_overlay'),
          ),
          matching: find.byType(FadeTransition),
        ),
      );
      final bannerFadeMid = tester.widget<FadeTransition>(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('profile_customization_banner_fade'),
          ),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(dimFadeMid.opacity.value, inExclusiveRange(0.05, 0.40));
      expect(bannerFadeMid.opacity.value, inExclusiveRange(0.60, 0.95));

      // Finish 850ms transition cleanly
      await tester.pump(const Duration(milliseconds: 700));
      expect(dimFadeMid.opacity.value, closeTo(1.0, 0.001));
      expect(bannerFadeMid.opacity.value, closeTo(0.0, 0.001));

      // Flush PeerCustomizationCache debounce timer
      await tester.pump(const Duration(milliseconds: 600));
    },
  );
}
