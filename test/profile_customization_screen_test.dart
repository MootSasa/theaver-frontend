import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/models/name_color_preset.dart';
import 'package:theaver/models/profile_customization.dart';
import 'package:theaver/screens/settings/profile_customization_screen.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/peer_customization_cache.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/widgets/chat/emoji_sticker_panel.dart';
import 'package:theaver/widgets/common/adaptive_switch.dart';
import 'package:theaver/widgets/common/glass_modal_sheet.dart';
import 'package:theaver/widgets/profile/name_color_picker.dart';
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

      // 1. Emoji Status row on Profile tab opens glass modal sheet WITHOUT any short-note input
      final statusRow = find.byKey(
        const ValueKey<String>('profile_emoji_status_row'),
      );
      expect(statusRow, findsOneWidget);
      expect(themeProvider.currentEmojiStatus, isNull);
      expect(find.text('Choose emoji and note'), findsNothing);

      await tester.tap(statusRow);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(TheavGlassModalSheet), findsOneWidget);
      expect(find.byType(EmojiStickerPanel), findsOneWidget);
      expect(find.text('Add a short note (up to 64 chars)'), findsNothing);

      // Tap emoji inside modal sheet -> instant Frame-0 status update with empty note
      await tester.tap(find.text('😀').first);
      await tester.pump();
      expect(themeProvider.currentEmojiStatus?.emoji, '😀');
      expect(themeProvider.currentEmojiStatus?.note, isEmpty);

      // Dismiss modal sheet -> clear inline via Xmark on the Profile tab row
      Navigator.of(tester.element(find.byType(TheavGlassModalSheet))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(iconoir.Xmark), findsOneWidget);

      await tester.tap(find.byType(iconoir.Xmark));
      await tester.pump();
      expect(themeProvider.currentEmojiStatus, isNull);

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
}
