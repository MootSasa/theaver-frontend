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
import 'package:theaver/widgets/common/adaptive_switch.dart';
import 'package:theaver/widgets/common/glass_modal_sheet.dart';
import 'package:theaver/widgets/profile/name_color_picker.dart';
import 'package:theaver/widgets/profile/profile_segmented_control.dart';
import 'package:theaver/widgets/profile/reply_message_preview_card.dart';
import 'package:theaver/widgets/settings/settings_floating_header.dart';
import 'package:theaver/widgets/settings/settings_group.dart';

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
    'Renders SettingsFloatingHeader over edge-to-edge hero without AppBar, Live Preview tag, or bottom Save buttons',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final themeProvider = ProfileThemeProvider();
      final glassProvider = LiquidGlassProvider();

      await tester.pumpWidget(
        _buildTestHarness(
          themeProvider: themeProvider,
          glassProvider: glassProvider,
        ),
      );
      await tester.pump();

      expect(find.byType(SettingsFloatingScaffold), findsOneWidget);
      expect(find.byType(SettingsFloatingHeader), findsOneWidget);
      expect(find.byType(SettingsFloatingCircleButton), findsOneWidget);
      expect(find.text('Profile Customization'), findsOneWidget);

      // Anti-AI-slop checks: no stock AppBar, no "Live Preview" label, no Save/Reset button bars
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Live Preview'), findsNothing);
      expect(find.text('Предпросмотр'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);

      // 3-section sliding segmented control + SettingsGroup cards
      expect(find.byType(ProfileSegmentedControl), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Chat Name'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.byType(SettingsGroup), findsAtLeastNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Renders cleanly in both Light mode and Liquid Glass mode without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final themeProvider = ProfileThemeProvider();
      final glassProvider = LiquidGlassProvider();
      await glassProvider.setMode(GlassMode.lite);

      for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          _buildTestHarness(
            themeProvider: themeProvider,
            glassProvider: glassProvider,
            brightness: brightness,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Chat Name'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ReplyMessagePreviewCard), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Status'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Instant Frame-0 updates work for avatar frame, badge visibility switch, all-badges sheet, name color, and emoji status',
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

      // 1. Tap an avatar decoration frame in the horizontal carousel -> instant apply
      final firstPreset = PeerCustomizationCache.instance.decorationsCatalog.first;
      await tester.tap(find.text(firstPreset.id).hitTestable().first);
      await tester.pump();
      expect(themeProvider.currentAvatarDecoration?.id, firstPreset.id);

      // 2. Scroll to Profile Badge section, toggle AdaptiveSwitch -> hides badge immediately
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

      // 3. Open All Platform Badges modal sheet -> shows catalog cleanly
      await tester.tap(find.text('All Platform Badges'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(TheavGlassModalSheet), findsOneWidget);
      expect(find.text('CREATOR'), findsWidgets);
      Navigator.of(tester.element(find.byType(TheavGlassModalSheet))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // 4. Switch to "Chat Name" tab -> ReplyMessagePreviewCard + instant strip style update
      await tester.tap(find.text('Chat Name'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(ReplyMessagePreviewCard), findsOneWidget);

      // Tap the second ReplyStripStyle slot
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

      // 5. Switch to "Status" tab -> tap an emoji -> instant status apply + Xmark clear
      await tester.tap(find.text('Status'));
      await tester.pump();
      expect(themeProvider.currentEmojiStatus, isNull);

      await tester.tap(find.text('😀').first);
      await tester.pump();
      expect(themeProvider.currentEmojiStatus?.emoji, '😀');

      // Tap clear icon button -> status cleared immediately
      await tester.tap(find.byType(iconoir.Xmark));
      await tester.pump();
      expect(themeProvider.currentEmojiStatus, isNull);
      await tester.pump(const Duration(milliseconds: 600));
    },
  );
}
