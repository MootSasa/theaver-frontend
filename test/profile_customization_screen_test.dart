import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
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
    'Replaces title capsule with floating 2-tab switcher, hides avatar online dot, and scrolls text underneath the switcher',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final themeProvider = ProfileThemeProvider();
      final glassProvider = LiquidGlassProvider();
      await glassProvider.setMode(GlassMode.lite);

      await tester.pumpWidget(
        _buildTestHarness(
          themeProvider: themeProvider,
          glassProvider: glassProvider,
        ),
      );
      await tester.pump();

      // 1. Floating top bar has back button + 2-tab Liquid Glass switcher (no title pill, no 3rd Status tab)
      expect(find.byType(ProfileFloatingBackButton), findsOneWidget);
      expect(find.byType(ProfileFloatingTopSwitcher), findsOneWidget);
      expect(find.byType(LiquidGlassMotionPill), findsOneWidget);
      expect(find.text('Profile Customization'), findsNothing);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Chat Name'), findsOneWidget);
      expect(find.text('Status'), findsNothing);

      // Anti-AI-slop checks: no AppBar, no Live Preview label, no bottom Save/Reset buttons
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Live Preview'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);

      // 2. Every AvatarWithStatus on screen has isOnline == false (no online circle next to avatar)
      final avatars = tester.widgetList<AvatarWithStatus>(
        find.byType(AvatarWithStatus),
      );
      expect(avatars, isNotEmpty);
      for (final avatar in avatars) {
        expect(avatar.isOnline, isFalse);
      }

      // 3. Translucent profile glass cards + full-screen gradient preset support
      expect(find.byType(ProfileGlassSection), findsAtLeastNWidgets(3));
      await themeProvider.setPreset(ProfileColorPresets.skyBlueGrad);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      // 4. Scrolling moves section text directly underneath the floating switcher
      final switcherRect = tester.getRect(
        find.byType(ProfileFloatingTopSwitcher),
      );
      await tester.drag(
        find.byType(ListView).first,
        const Offset(0, -260),
      );
      await tester.pump();
      final coverHeaderRect = tester.getRect(find.text('Cover & Banner'));
      expect(coverHeaderRect.top, lessThan(switcherRect.bottom));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Renders cleanly across Light/Dark themes and Classic/LiquidGlass modes, supporting both tap and drag on floating switcher',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final themeProvider = ProfileThemeProvider();
      final glassProvider = LiquidGlassProvider();

      for (final mode in <GlassMode>[GlassMode.disabled, GlassMode.lite]) {
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

          // Tap 'Chat Name' in floating top switcher
          await tester.tap(find.text('Chat Name'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.byType(ReplyMessagePreviewCard), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Drag switcher horizontally back to 'Profile'
          await tester.drag(
            find.byType(ProfileFloatingTopSwitcher),
            const Offset(-140, 0),
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
    'Selects and clears Emoji Status right from the Profile tab via glass modal sheet, plus instant frame/badge/name-color updates',
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

      // 1. Emoji Status row is on the Profile tab -> opens glass modal sheet with EmojiStickerPanel
      final statusRow = find.byKey(
        const ValueKey<String>('profile_emoji_status_row'),
      );
      expect(statusRow, findsOneWidget);
      expect(themeProvider.currentEmojiStatus, isNull);

      await tester.tap(statusRow);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(TheavGlassModalSheet), findsOneWidget);
      expect(find.byType(EmojiStickerPanel), findsOneWidget);

      // Tap emoji inside modal sheet -> instant Frame-0 status update
      await tester.tap(find.text('😀').first);
      await tester.pump();
      expect(themeProvider.currentEmojiStatus?.emoji, '😀');

      // Dismiss modal sheet -> clear inline via Xmark on the Profile tab row
      Navigator.of(tester.element(find.byType(TheavGlassModalSheet))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(iconoir.Xmark), findsOneWidget);

      await tester.tap(find.byType(iconoir.Xmark));
      await tester.pump();
      expect(themeProvider.currentEmojiStatus, isNull);

      // 2. Tap an avatar decoration frame in the horizontal carousel -> instant apply
      final firstPreset =
          PeerCustomizationCache.instance.decorationsCatalog.first;
      await tester.scrollUntilVisible(
        find.text(firstPreset.id),
        160.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text(firstPreset.id).hitTestable().first);
      await tester.pump();
      expect(themeProvider.currentAvatarDecoration?.id, firstPreset.id);

      // 3. Scroll to Profile Badge section, toggle AdaptiveSwitch -> hides badge immediately
      await tester.scrollUntilVisible(
        find.text('All Platform Badges'),
        200.0,
        scrollable: find.byType(Scrollable).first,
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

      // 5. Switch to 'Chat Name' tab -> ReplyMessagePreviewCard + instant strip style update
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
