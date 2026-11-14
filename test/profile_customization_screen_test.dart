import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/models/name_color_preset.dart';
import 'package:theaver/models/profile_customization.dart';
import 'package:theaver/screens/settings/profile_banner_editor_screen.dart';
import 'package:theaver/screens/settings/profile_customization_screen.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/peer_customization_cache.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/widgets/common/adaptive_switch.dart';
import 'package:theaver/widgets/common/glass_modal_sheet.dart';
import 'package:theaver/widgets/profile/floating_emoji_status_menu.dart';
import 'package:theaver/widgets/profile/name_color_picker.dart';
import 'package:theaver/widgets/profile/profile_banner_layer.dart';
import 'package:theaver/widgets/profile/profile_floating_top_switcher.dart';
import 'package:theaver/widgets/profile/reply_message_preview_card.dart';
import 'package:theaver/widgets/user/avatar_with_status.dart';

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

          // Swipe PageView horizontally back to 'Profile'
          await tester.drag(
            find.byType(PageView).first,
            const Offset(320, 0),
          );
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
      await tester.pump(const Duration(milliseconds: 350));
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
}
