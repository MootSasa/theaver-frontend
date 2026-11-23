import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/profile_customization.dart';
import 'package:theaver/screens/settings/profile_screen.dart';
import 'package:theaver/services/display_cutout_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/peer_customization_cache.dart';
import 'package:theaver/services/power_saving_provider.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/widgets/profile/expandable_avatar.dart';
import 'package:theaver/widgets/profile/profile_avatar_metaball_layer.dart';
import 'package:theaver/widgets/tiling/tile_viewport_scope.dart';
import 'package:theaver/widgets/user/avatar_decoration_frame.dart';

class _TestAppLocalizations extends AppLocalizations {
  final Map<String, String> translations;
  _TestAppLocalizations(Locale locale, this.translations) : super(locale);

  @override
  String translate(String key, [Map<String, String>? params]) =>
      translations[key] ?? key;
}

class _TestAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  final Map<String, String> translations;
  const _TestAppLocalizationsDelegate([this.translations = const {}]);

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(_TestAppLocalizations(locale, translations));
  }

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

const Map<String, String> _kTranslations = {
  'profile_online': 'в сети',
  'chat_online': 'в сети',
  'chat_offline': 'не в сети',
  'chat_title': 'Чат',
  'call': 'Звонок',
  'video': 'Видео',
  'chat_mute': 'Заглушить',
  'chat_unmute': 'Включить звук',
  'profile_choose_photo': 'Выбрать фото',
  'profile_qr_code': 'QR-код',
  'profile_edit_btn': 'Изменить',
  'profile_delete_photo': 'Удалить',
  'profile_music': 'Музыка',
  'profile_phone': 'Телефон',
  'profile_bio': 'О себе',
  'profile_username': 'Имя пользователя',
  'profile_birthday': 'Дата рождения',
  'profile_age': 'Возраст',
  'profile_tab_wall': 'Стена',
  'profile_tab_gifts': 'Подарки',
};

Widget _buildProfileTestApp({
  required Widget child,
  required LiquidGlassProvider glassProvider,
  Size size = const Size(393.0, 852.0),
  EdgeInsets padding = const EdgeInsets.only(top: 54.0, bottom: 34.0),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LiquidGlassProvider>.value(value: glassProvider),
      ChangeNotifierProvider(create: (_) => ProfileThemeProvider()),
      ChangeNotifierProvider<PeerCustomizationCache>.value(
        value: PeerCustomizationCache.instance,
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        _TestAppLocalizationsDelegate(_kTranslations),
      ],
      builder: (context, appChild) {
        return MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: padding,
            viewPadding: padding,
          ),
          child: appChild ?? const SizedBox.shrink(),
        );
      },
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SettingsService().init();
    DisplayCutoutService.instance.resetForTesting();
    PeerCustomizationCache.instance.clearForTesting();
    PowerSavingProvider.instance.setSettingsForTest(
      PowerSavingSettings.defaults(),
    );
  });

  tearDown(() {
    DisplayCutoutService.instance.resetForTesting();
    PeerCustomizationCache.instance.clearForTesting();
    PowerSavingProvider.instance.setSettingsForTest(
      PowerSavingSettings.defaults(),
    );
  });

  group('DisplayCutoutService classification & dual-sensor oval unification', () {
    test('unifies dual corner front cameras (gap <= 28dp) into one stadium oval', () {
      const windowSize = Size(393.0, 852.0);
      final features = <ui.DisplayFeature>[
        const ui.DisplayFeature(
          bounds: Rect.fromLTWH(18.0, 10.0, 22.0, 22.0),
          type: ui.DisplayFeatureType.cutout,
          state: ui.DisplayFeatureState.unknown,
        ),
        const ui.DisplayFeature(
          bounds: Rect.fromLTWH(48.0, 10.0, 22.0, 22.0), // gap = 8dp <= 28dp
          type: ui.DisplayFeatureType.cutout,
          state: ui.DisplayFeatureState.unknown,
        ),
      ];

      final spec = DisplayCutoutService.fromDisplayFeatures(features, windowSize);
      expect(spec.hasCutout, isTrue);
      expect(spec.kind, CutoutAnchorKind.punchHole);
      expect(spec.gravity, CutoutHorizontalGravity.left);
      expect(spec.isOval, isTrue);
      expect(spec.bounds, const Rect.fromLTWH(18.0, 10.0, 52.0, 22.0));
      expect(spec.cornerRadius, closeTo(11.0, 0.001));
      expect(spec.bounds.center, const Offset(44.0, 21.0));
    });

    test('unifies dual centered cameras and classifies right-corner dual oval', () {
      const windowSize = Size(412.0, 915.0);
      final centerDual = DisplayCutoutService.fromDisplayFeatures(
        const <ui.DisplayFeature>[
          ui.DisplayFeature(
            bounds: Rect.fromLTWH(176.0, 9.0, 20.0, 20.0),
            type: ui.DisplayFeatureType.cutout,
            state: ui.DisplayFeatureState.unknown,
          ),
          ui.DisplayFeature(
            bounds: Rect.fromLTWH(216.0, 9.0, 20.0, 20.0), // gap = 20dp <= 28dp
            type: ui.DisplayFeatureType.cutout,
            state: ui.DisplayFeatureState.unknown,
          ),
        ],
        windowSize,
      );
      expect(centerDual.kind, CutoutAnchorKind.punchHole);
      expect(centerDual.gravity, CutoutHorizontalGravity.center);
      expect(centerDual.isOval, isTrue);
      expect(centerDual.bounds, const Rect.fromLTWH(176.0, 9.0, 60.0, 20.0));
      expect(centerDual.bounds.center, const Offset(206.0, 19.0));

      final rightDual = DisplayCutoutService.fromDisplayFeatures(
        const <ui.DisplayFeature>[
          ui.DisplayFeature(
            bounds: Rect.fromLTWH(332.0, 12.0, 20.0, 20.0),
            type: ui.DisplayFeatureType.cutout,
            state: ui.DisplayFeatureState.unknown,
          ),
          ui.DisplayFeature(
            bounds: Rect.fromLTWH(362.0, 12.0, 20.0, 20.0),
            type: ui.DisplayFeatureType.cutout,
            state: ui.DisplayFeatureState.unknown,
          ),
        ],
        windowSize,
      );
      expect(rightDual.kind, CutoutAnchorKind.punchHole);
      expect(rightDual.gravity, CutoutHorizontalGravity.right);
      expect(rightDual.isOval, isTrue);
      expect(rightDual.bounds.center, const Offset(357.0, 22.0));
    });

    test('parses iOS Dynamic Island and Android curved polygon notch payloads', () {
      final island = DisplayCutoutSpec.fromChannelMap(
        const <Object?, Object?>{
          'hasCutout': true,
          'kind': 'dynamicIsland',
          'gravity': 'center',
          'left': 133.5,
          'top': 11.0,
          'width': 126.0,
          'height': 37.333,
          'cornerRadius': 18.666,
          'isOval': true,
        },
        windowWidth: 393.0,
      );
      expect(island.kind, CutoutAnchorKind.dynamicIsland);
      expect(island.gravity, CutoutHorizontalGravity.center);
      expect(island.isOval, isTrue);
      expect(island.bounds.top, closeTo(11.0, 0.01));

      final polygonNotch = DisplayCutoutSpec.fromChannelMap(
        const <Object?, Object?>{
          'hasCutout': true,
          'kind': 'topNotch',
          'gravity': 'center',
          'left': 160.0,
          'top': 0.0,
          'width': 72.0,
          'height': 28.0,
          'cornerRadius': 14.0,
          'isOval': false,
          'polygonDp': <double>[
            160, 0, 172, 16, 186, 26, 196, 28, 206, 26, 220, 16, 232, 0,
          ],
        },
        windowWidth: 392.0,
      );
      expect(polygonNotch.kind, CutoutAnchorKind.topNotch);
      expect(polygonNotch.polygonDp, isNotNull);
      expect(polygonNotch.polygonDp!.length, 7);
    });

    testWidgets('falls back to CutoutAnchorKind.none in landscape and lower split tile', (tester) async {
      DisplayCutoutService.instance.debugOverrideSpec = const DisplayCutoutSpec(
        kind: CutoutAnchorKind.dynamicIsland,
        gravity: CutoutHorizontalGravity.center,
        bounds: Rect.fromLTWH(133.5, 11.0, 126.0, 37.33),
        cornerRadius: 18.67,
        isOval: true,
      );

      late DisplayCutoutSpec landscapeResolved;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(852.0, 393.0)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                landscapeResolved =
                    DisplayCutoutService.instance.resolveForContext(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(landscapeResolved.kind, CutoutAnchorKind.none);

      late DisplayCutoutSpec lowerTileResolved;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(393.0, 852.0)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TileViewportScope(
              tileId: 'bottom_tile',
              isChatTile: false,
              hasTopNeighbor: true,
              child: Builder(
                builder: (context) {
                  lowerTileResolved =
                      DisplayCutoutService.instance.resolveForContext(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      expect(lowerTileResolved.kind, CutoutAnchorKind.none);
    });
  });

  group('ProfileAvatarMetaballGeometry trajectory & Bezier corner math', () {
    test('computes quadratic Bezier into unified left/right corner oval while avoiding status-bar center', () {
      const screenWidth = 393.0;
      const statusBarHeight = 40.0;
      const topOffset = 86.0; // headerTopY (54) + 44 - 12

      const leftDualOval = DisplayCutoutSpec(
        kind: CutoutAnchorKind.punchHole,
        gravity: CutoutHorizontalGravity.left,
        bounds: Rect.fromLTWH(18.0, 10.0, 52.0, 22.0), // center = (44, 21)
        cornerRadius: 11.0,
        isOval: true,
      );

      final start = ProfileAvatarMetaballGeometry.compute(
        scrollOffset: 0.0,
        screenWidth: screenWidth,
        statusBarHeight: statusBarHeight,
        topOffset: topOffset,
        cutout: leftDualOval,
      );
      expect(start.avatarCenter, const Offset(196.5, 141.0));
      expect(start.isScalarFieldActive, isFalse);

      double prevX = start.avatarCenter.dx;
      double prevY = start.avatarCenter.dy;
      for (int i = 1; i <= 10; i++) {
        final g = ProfileAvatarMetaballGeometry.compute(
          scrollOffset: 155.0 * (i / 10.0),
          screenWidth: screenWidth,
          statusBarHeight: statusBarHeight,
          topOffset: topOffset,
          cutout: leftDualOval,
        );
        expect(g.isCornerTrajectory, isTrue);
        expect(g.avatarCenter.dx, lessThanOrEqualTo(prevX + 0.001));
        expect(g.avatarCenter.dy, lessThanOrEqualTo(prevY + 0.001));
        expect(g.suctionDirection.distance, closeTo(1.0, 0.001));
        // When crossing the central status-bar clock/icons region (x > 95),
        // center stays safely below the top status bar band (y > statusBarHeight).
        if (g.avatarCenter.dx > 95.0) {
          expect(g.avatarCenter.dy, greaterThan(statusBarHeight));
        }
        prevX = g.avatarCenter.dx;
        prevY = g.avatarCenter.dy;
      }

      final end = ProfileAvatarMetaballGeometry.compute(
        scrollOffset: 155.0,
        screenWidth: screenWidth,
        statusBarHeight: statusBarHeight,
        topOffset: topOffset,
        cutout: leftDualOval,
      );
      // Lands exactly on the geometric center of the unified dual-camera oval.
      expect(end.avatarCenter.dx, closeTo(44.0, 0.01));
      expect(end.avatarCenter.dy, closeTo(21.0, 0.01));

      // Symmetric check for right-corner cutout.
      const rightCorner = DisplayCutoutSpec(
        kind: CutoutAnchorKind.punchHole,
        gravity: CutoutHorizontalGravity.right,
        bounds: Rect.fromLTWH(345.0, 12.0, 24.0, 24.0), // center = (357, 24)
        cornerRadius: 12.0,
      );
      final rightEnd = ProfileAvatarMetaballGeometry.compute(
        scrollOffset: 155.0,
        screenWidth: screenWidth,
        statusBarHeight: statusBarHeight,
        topOffset: topOffset,
        cutout: rightCorner,
      );
      expect(rightEnd.avatarCenter.dx, closeTo(357.0, 0.01));
      expect(rightEnd.avatarCenter.dy, closeTo(24.0, 0.01));
    });

    test('clips floating Dynamic Island top edge, keeps photo full-color until p > 0.72, and lazy-activates scalar field within 24dp', () {
      const island = DisplayCutoutSpec(
        kind: CutoutAnchorKind.dynamicIsland,
        gravity: CutoutHorizontalGravity.center,
        bounds: Rect.fromLTWH(133.5, 11.0, 126.0, 37.33),
        cornerRadius: 18.67,
        isOval: true,
      );

      final early = ProfileAvatarMetaballGeometry.compute(
        scrollOffset: 35.0, // p ≈ 0.226 <= 0.45
        screenWidth: 393.0,
        statusBarHeight: 54.0,
        topOffset: 100.0,
        cutout: island,
      );
      expect(early.cutoutClipTopY, closeTo(11.0, 0.01));
      expect(early.edgeGapDp, greaterThan(24.0));
      expect(early.isScalarFieldActive, isFalse);
      expect(early.avatarBlurSigma, equals(0.0));
      expect(early.avatarRgbScale, equals(1.0));

      final preContact = ProfileAvatarMetaballGeometry.compute(
        scrollOffset: 105.0, // p ≈ 0.677 <= 0.72: approaching cutout, still 100% colored!
        screenWidth: 393.0,
        statusBarHeight: 54.0,
        topOffset: 100.0,
        cutout: island,
      );
      expect(preContact.edgeGapDp, lessThanOrEqualTo(24.0));
      expect(preContact.isScalarFieldActive, isTrue);
      expect(preContact.avatarRgbScale, equals(1.0));
      expect(preContact.avatarAlpha, equals(1.0));
      expect(preContact.avatarBlurSigma, lessThanOrEqualTo(4.5));
      expect(preContact.avatarCenter.dx, closeTo(196.5, 0.01));

      final absorbing = ProfileAvatarMetaballGeometry.compute(
        scrollOffset: 140.0, // p ≈ 0.903: inside cutout, darkening into #000
        screenWidth: 393.0,
        statusBarHeight: 54.0,
        topOffset: 100.0,
        cutout: island,
      );
      expect(absorbing.avatarRgbScale, lessThan(0.55));
    });

    test('normalizes Android vertical OEM slot (top = 0, height > width) to bottom circular camera and scales referenceWidthDp', () {
      final normalized = DisplayCutoutSpec.fromChannelMap(
        const <Object?, Object?>{
          'hasCutout': true,
          'kind': 'punchHole',
          'gravity': 'center',
          'left': 184.0,
          'top': 0.0,
          'width': 24.0,
          'height': 32.0,
          'cornerRadius': 12.0,
          'isOval': false,
          'referenceWidthDp': 392.0,
        },
        windowWidth: 392.0,
      );
      expect(normalized.bounds, const Rect.fromLTWH(184.0, 8.0, 24.0, 24.0));
      expect(normalized.bounds.center, const Offset(196.0, 20.0));

      final scaled = DisplayCutoutSpec.fromChannelMap(
        const <Object?, Object?>{
          'hasCutout': true,
          'kind': 'punchHole',
          'gravity': 'center',
          'left': 180.0,
          'top': 10.0,
          'width': 24.0,
          'height': 24.0,
          'cornerRadius': 12.0,
          'isOval': false,
          'referenceWidthDp': 384.0,
        },
        windowWidth: 412.0,
      );
      expect(scaled.bounds.center.dx, closeTo(192.0 * (412.0 / 384.0), 0.05));
    });
  });

  group('Custom AvatarDecorationFrame phase freeze & contraction into droplet', () {
    testWidgets('pausing AvatarDecorationFrame freezes current phase instead of snapping to 0.25', (tester) async {
      final preset = AvatarDecorationPreset.builtInDefaults.firstWhere(
        (d) => d.id == 'neon_pulse',
      );
      final stateKey = GlobalKey<AvatarDecorationFrameState>();

      Widget buildHarness({required bool animate}) {
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: AvatarDecorationFrame(
                key: stateKey,
                decoration: preset,
                avatarDiameter: 110.0,
                animate: animate,
                child: const SizedBox(width: 110.0, height: 110.0),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildHarness(animate: true));
      await tester.pump(const Duration(milliseconds: 900));
      final livePhase = stateKey.currentState!.debugAnimationValue;
      expect((livePhase - 0.25).abs(), greaterThan(0.10));

      // Pause animation (simulating p >= 0.08 scroll threshold): phase must NOT snap back to 0.25.
      await tester.pumpWidget(buildHarness(animate: false));
      await tester.pump();
      expect(
        stateKey.currentState!.debugAnimationValue,
        closeTo(livePhase, 0.001),
      );
    });

    testWidgets('contracts procedural & media frames 1.0 -> 0.81 without clipping, unmounts at p >= 0.36, and blooms back', (tester) async {
      DisplayCutoutService.instance.debugOverrideSpec = const DisplayCutoutSpec(
        kind: CutoutAnchorKind.punchHole,
        gravity: CutoutHorizontalGravity.left,
        bounds: Rect.fromLTWH(20.0, 12.0, 48.0, 22.0),
        cornerRadius: 11.0,
        isOval: true,
      );

      final proceduralPreset = AvatarDecorationPreset.builtInDefaults.firstWhere(
        (d) => d.id == 'starlight_orbit',
      );
      const mediaPreset = AvatarDecorationPreset(
        id: 'custom_lottie_ring',
        nameKey: 'customRing',
        category: 'animated',
        mediaUrl: '',
        mediaFormat: 'webp',
        isAnimated: true,
      );

      for (final preset in <AvatarDecorationPreset>[proceduralPreset, mediaPreset]) {
        Widget buildLayer(double scrollOffset) {
          return MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 393.0,
                height: 852.0,
                child: Stack(
                  children: [
                    ProfileAvatarMetaballLayer(
                      scrollOffset: scrollOffset,
                      screenWidth: 393.0,
                      statusBarHeight: 44.0,
                      topOffset: 90.0,
                      displayName: 'Theaver',
                      decoration: preset,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // p = 0.0: exactly one unclipped AvatarDecorationFrame (outerSize = 136.4), inner ExpandableAvatar frame suppressed.
        await tester.pumpWidget(buildLayer(0.0));
        await tester.pump();
        expect(find.byType(AvatarDecorationFrame), findsOneWidget);
        final idleSize = tester.getSize(find.byType(AvatarDecorationFrame));
        expect(idleSize.width, closeTo(110.0 * 1.24, 0.05));
        final idleExpandable =
            tester.widget<ExpandableAvatar>(find.byType(ExpandableAvatar));
        expect(idleExpandable.showDecoration, isFalse);

        // Mid-contraction (scrollOffset = 34 -> p ≈ 0.219 < 0.36): frame contracts & fades outside ImageFiltered.
        await tester.pumpWidget(buildLayer(34.0));
        await tester.pump();
        expect(find.byType(AvatarDecorationFrame), findsOneWidget);
        final midFrame = tester
            .widget<AvatarDecorationFrame>(find.byType(AvatarDecorationFrame));
        expect(midFrame.opacity, lessThan(1.0));
        expect(midFrame.opacity, greaterThan(0.0));
        expect(midFrame.animate, isFalse);
        // Ensure AvatarDecorationFrame is NOT clipped inside an ImageFiltered ancestor.
        expect(
          find.ancestor(
            of: find.byType(AvatarDecorationFrame),
            matching: find.byType(ImageFiltered),
          ),
          findsNothing,
        );

        // Past p >= 0.36 (scrollOffset = 65 -> p ≈ 0.419): frame unmounts completely before black merge peaks.
        await tester.pumpWidget(buildLayer(65.0));
        await tester.pump();
        expect(find.byType(AvatarDecorationFrame), findsNothing);
        expect(find.byType(ExpandableAvatar), findsOneWidget);

        // Reverse scroll back to 0: frame blooms back to full opacity & size.
        await tester.pumpWidget(buildLayer(0.0));
        await tester.pump();
        expect(find.byType(AvatarDecorationFrame), findsOneWidget);
        final restoredFrame = tester
            .widget<AvatarDecorationFrame>(find.byType(AvatarDecorationFrame));
        expect(restoredFrame.opacity, closeTo(1.0, 0.001));
      }
    });
  });

  group('ProfileScreen integration across LiquidGlass (full/lite), Material & PowerSaving', () {
    for (final mode in <GlassMode>[
      GlassMode.disabled,
      GlassMode.lite,
      GlassMode.full,
    ]) {
      testWidgets('renders idle fast-path, mid-scroll metaball, and full unmount in $mode', (tester) async {
        DisplayCutoutService.instance.debugOverrideSpec = const DisplayCutoutSpec(
          kind: CutoutAnchorKind.dynamicIsland,
          gravity: CutoutHorizontalGravity.center,
          bounds: Rect.fromLTWH(133.5, 11.0, 126.0, 37.33),
          cornerRadius: 18.67,
          isOval: true,
        );
        PeerCustomizationCache.instance.put(
          'peer_metaball_user',
          PeerCustomization(
            avatarDecoration: AvatarDecorationPreset.builtInDefaults.first,
          ),
          notify: false,
        );

        final glassProvider = LiquidGlassProvider();
        await glassProvider.setMode(mode);

        await tester.pumpWidget(
          _buildProfileTestApp(
            glassProvider: glassProvider,
            child: const ProfileScreen(
              userId: 'peer_metaball_user',
              initialName: 'Pavel Durov',
              initialIsOnline: true,
              heroTag: 'peer_metaball_user',
            ),
          ),
        );
        await tester.pump();

        final metaballLayerFinder = find.byType(ProfileAvatarMetaballLayer);
        expect(metaballLayerFinder, findsOneWidget);

        // 1. At scrollOffset == 0: zero ImageFiltered / ColorFiltered inside metaball layer, Hero active.
        expect(
          find.descendant(
            of: metaballLayerFinder,
            matching: find.byType(ImageFiltered),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: metaballLayerFinder,
            matching: find.byType(ColorFiltered),
          ),
          findsNothing,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is Hero && w.tag == 'profile_avatar_peer_metaball_user',
          ),
          findsOneWidget,
        );

        // Verify zero translucent Opacity ancestor above any LiquidGlassLens.
        final lenses = find.byType(LiquidGlassLens);
        for (final lensElement in lenses.evaluate()) {
          lensElement.visitAncestorElements((ancestor) {
            final widget = ancestor.widget;
            if (widget is Opacity) {
              expect(
                widget.opacity == 0.0 || widget.opacity == 1.0,
                isTrue,
                reason: 'Translucent Opacity found above LiquidGlassLens',
              );
            }
            return true;
          });
        }

        // 2. Scroll to 120dp (p ≈ 0.774): GPU metaball scalar field + absorption darkening active; Hero tag disabled (> 0.55).
        final scrollableFinder = find.byType(Scrollable).first;
        final scrollableState = tester.state<ScrollableState>(scrollableFinder);
        scrollableState.position.jumpTo(120.0);
        await tester.pump();

        expect(
          find.descendant(
            of: metaballLayerFinder,
            matching: find.byType(ImageFiltered),
          ),
          findsWidgets,
        );
        expect(
          find.descendant(
            of: metaballLayerFinder,
            matching: find.byType(ColorFiltered),
          ),
          findsWidgets,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is Hero && w.tag == 'profile_avatar_peer_metaball_user',
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);

        // 3. Scroll past 155dp (180dp): ExpandableAvatar unmounts cleanly from metaball layer.
        scrollableState.position.jumpTo(180.0);
        await tester.pump();
        expect(
          find.descendant(
            of: metaballLayerFinder,
            matching: find.byType(ExpandableAvatar),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        PeerCustomizationCache.instance.clearForTesting();
      });
    }

    testWidgets('PowerSavingProvider(allowBlur: false) skips GPU blur & color-matrix passes during scroll', (tester) async {
      DisplayCutoutService.instance.debugOverrideSpec = const DisplayCutoutSpec(
        kind: CutoutAnchorKind.punchHole,
        gravity: CutoutHorizontalGravity.right,
        bounds: Rect.fromLTWH(340.0, 12.0, 24.0, 24.0),
        cornerRadius: 12.0,
      );
      PowerSavingProvider.instance.setSettingsForTest(
        PowerSavingSettings(
          powerSavingEnabled: true,
          batteryThreshold: 20,
          reduceBackgroundActivity: true,
          lowerScreenBrightness: false,
          limitFrameRate: true,
          disableVibrations: true,
          disableLocationServices: false,
        ),
      );

      final glassProvider = LiquidGlassProvider();
      await glassProvider.setMode(GlassMode.full);

      await tester.pumpWidget(
        _buildProfileTestApp(
          glassProvider: glassProvider,
          child: const ProfileScreen(
            userId: 'low_power_peer',
            initialName: 'Low Power User',
            initialIsOnline: false,
            heroTag: 'low_power_peer',
          ),
        ),
      );
      await tester.pump();

      final scrollableState =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      scrollableState.position.jumpTo(95.0);
      await tester.pump();

      final metaballLayerFinder = find.byType(ProfileAvatarMetaballLayer);
      expect(
        find.descendant(
          of: metaballLayerFinder,
          matching: find.byType(ImageFiltered),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: metaballLayerFinder,
          matching: find.byType(ExpandableAvatar),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    test('ExpandableAvatar morphs size and borderRadius continuously without 0.38 kink', () {
      const w = 393.0;
      // Pull-down preview swells circle smoothly 110 -> 138dp while remaining 100% round.
      final swollen = ExpandableAvatar.calculateAvatarSize(
        w,
        0.0,
        pullPreviewProgress: 1.0,
      );
      expect(swollen, closeTo(138.0, 0.01));
      expect(
        ExpandableAvatar.calculateBorderRadius(swollen, 0.0),
        closeTo(swollen * 0.5, 0.01),
      );

      // Collapsing from square (1.0) immediately rounds corners & shrinks proportionally at 0.75 (no sharp-square freeze).
      final sizeAt75 = ExpandableAvatar.calculateAvatarSize(w, 0.75);
      final radiusAt75 = ExpandableAvatar.calculateBorderRadius(sizeAt75, 0.75);
      expect(sizeAt75, closeTo(110.0 + (w - 110.0) * 0.75, 0.05));
      expect(radiusAt75, greaterThan(30.0));
    });

    testWidgets('Telegram two-phase avatar: damped pull-to-expand and slide-up crop before circle collapse', (tester) async {
      final glassProvider = LiquidGlassProvider();
      await glassProvider.setMode(GlassMode.disabled);

      await tester.pumpWidget(
        _buildProfileTestApp(
          glassProvider: glassProvider,
          child: const ProfileScreen(
            userId: 'tg_morph_peer',
            initialName: 'Telegram Morph',
            initialIsOnline: true,
            heroTag: 'tg_morph_peer',
          ),
        ),
      );
      await tester.pump();

      // 1. Small pull-down (+65px < ~135px damped threshold) swells as a pure circle and does NOT pop open 1:1 square.
      final smallPull = await tester.startGesture(const Offset(196.0, 220.0));
      await smallPull.moveBy(const Offset(0.0, 65.0));
      await tester.pump(const Duration(milliseconds: 16));
      final previewSize = tester.getSize(find.byType(ExpandableAvatar));
      expect(previewSize.width, greaterThan(110.5));
      expect(previewSize.width, lessThan(138.0));
      expect(previewSize.height, closeTo(previewSize.width, 0.05));
      await tester.pump(const Duration(milliseconds: 120));
      await smallPull.up();
      await tester.pumpAndSettle();
      expect(find.byType(ProfileAvatarMetaballLayer), findsOneWidget);

      // 2. Intentional pull-down past weighted threshold expands into full 393x393 (1:1) square.
      final gestureDown = await tester.startGesture(const Offset(196.0, 220.0));
      await gestureDown.moveBy(const Offset(0.0, 175.0));
      await tester.pump();
      await gestureDown.up();
      await tester.pumpAndSettle();

      final expandedAvatar =
          tester.widget<ExpandableAvatar>(find.byType(ExpandableAvatar));
      expect(expandedAvatar.expandFactor, closeTo(1.0, 0.005));
      expect(tester.getSize(find.byType(ExpandableAvatar)), const Size(393.0, 393.0));

      // 3. Phase 1 upward drag (-85px < collapseTrigger ~119dp):
      // Avatar slides/crops upward (height decreases) while keeping 100% full screenWidth (393.0),
      // and releasing without a fast flick glides height smoothly back to 393x393!
      final partialSlideUp = await tester.startGesture(const Offset(196.0, 300.0));
      for (int i = 0; i < 5; i++) {
        await partialSlideUp.moveBy(const Offset(0.0, -17.0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final croppedSize = tester.getSize(find.byType(ExpandableAvatar));
      expect(croppedSize.width, closeTo(393.0, 0.5));
      expect(croppedSize.height, lessThan(345.0));
      expect(croppedSize.height, greaterThan(260.0));

      // Pause finger briefly so release velocity is near 0 -> settles back to full 393x393 square.
      await tester.pump(const Duration(milliseconds: 140));
      await partialSlideUp.up();
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ExpandableAvatar)), const Size(393.0, 393.0));

      // 4. Phase 2 full upward drag past collapseTrigger (~119dp) WHILE holding finger down:
      // Crosses trigger and morphs all the way into 110dp circle, then continues scrolling the profile list!
      final gestureUp = await tester.startGesture(const Offset(196.0, 300.0));
      for (int i = 0; i < 8; i++) {
        await gestureUp.moveBy(const Offset(0.0, -22.0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(find.byType(ProfileAvatarMetaballLayer), findsOneWidget);

      await gestureUp.moveBy(const Offset(0.0, -60.0));
      await tester.pump(const Duration(milliseconds: 16));
      final scrollableState =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(scrollableState.position.pixels, greaterThan(40.0));

      await gestureUp.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
