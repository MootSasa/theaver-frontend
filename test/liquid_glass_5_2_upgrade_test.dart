import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/services/call_state_provider.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/widgets/bot/mini_app_webview_sheet.dart';
import 'package:theaver/widgets/browser/safari_browser_dialogs.dart';
import 'package:theaver/widgets/call/active_call_top_banner.dart';
import 'package:theaver/widgets/chat/chat_input_bar.dart';
import 'package:theaver/widgets/chat/liquid_glass_input_field.dart';
import 'package:theaver/widgets/design_system/theav_design_system.dart';

class _ForcedGlassProvider extends LiquidGlassProvider {
  _ForcedGlassProvider(this._forcedMode);

  final GlassMode _forcedMode;

  @override
  GlassMode get mode => _forcedMode;

  @override
  bool get enabled => _forcedMode != GlassMode.disabled;

  @override
  bool get isLite => _forcedMode == GlassMode.lite;

  @override
  bool get isFull => _forcedMode == GlassMode.full;
}

class _MorphProbeChild extends StatefulWidget {
  const _MorphProbeChild({super.key, required this.width});

  final double width;

  @override
  State<_MorphProbeChild> createState() => _MorphProbeChildState();
}

class _MorphProbeChildState extends State<_MorphProbeChild> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(width: widget.width, height: 40, child: const Text('Probe'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
  });

  group('liquid_glass_easy 5.2.0 patched core behaviors', () {
    test('LiquidGlassShape and LiquidGlassStyle implement structural == and hashCode', () {
      const shapeA = LiquidGlassShape.continuousRoundedRectangle(
        cornerRadius: 24,
        clipQuality: LiquidGlassClipQuality.roundedRectangle,
      );
      const shapeB = LiquidGlassShape.continuousRoundedRectangle(
        cornerRadius: 24,
        clipQuality: LiquidGlassClipQuality.roundedRectangle,
      );
      const shapeC = LiquidGlassShape.continuousRoundedRectangle(
        cornerRadius: 16,
        clipQuality: LiquidGlassClipQuality.roundedRectangle,
      );

      expect(shapeA, equals(shapeB));
      expect(shapeA.hashCode, equals(shapeB.hashCode));
      expect(shapeA, isNot(equals(shapeC)));

      const styleA = LiquidGlassStyle(
        shape: shapeA,
        blur: 8.0,
        color: Color(0x66FFFFFF),
        refractionIndex: 1.1,
        refractionWidth: 20.0,
        specular: LiquidGlassLight.specular(thickness: 5.0, angle: 62.0),
      );
      final styleB = styleA.copyWith();
      final styleC = styleA.copyWith(blur: 12.0);

      expect(styleA, equals(styleB));
      expect(styleA.hashCode, equals(styleB.hashCode));
      expect(styleA, isNot(equals(styleC)));
    });

    testWidgets(
      'LiquidGlassTabBar handles negative margin, zero iconSize, and onReselected',
      (tester) async {
        int selected = 0;
        int? changedTo;
        int? reselectedIdx;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  LiquidGlassTabBar(
                    selectedIndex: selected,
                    onChanged: (idx) => changedTo = idx,
                    onReselected: (idx) => reselectedIdx = idx,
                    margin: const EdgeInsets.only(bottom: -48, left: -12),
                    swell: null,
                    pillStyle: const LiquidGlassTabPillStyle(
                      mode: LiquidGlassPillMode.none,
                    ),
                    itemStyle: const LiquidGlassTabItemStyle(
                      iconSize: 0,
                      underGlassIconSize: 0,
                      iconLabelGap: 0,
                      labelFontSize: 13,
                    ),
                    items: [
                      LiquidGlassTabBarItem(
                        label: 'Эмодзи',
                        iconBuilder: (_, __) => const SizedBox.shrink(),
                      ),
                      LiquidGlassTabBarItem(
                        label: 'Стикеры',
                        iconBuilder: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Эмодзи'));
        await tester.pump();
        expect(reselectedIdx, 0);
        expect(changedTo, 0);

        await tester.tap(find.text('Стикеры'));
        await tester.pump();
        expect(changedTo, 1);
      },
    );

    testWidgets(
      'LiquidGlassMorph handles rapid child reversals, opacity, LiquidGlassMorphShared, and touch',
      (tester) async {
        bool expanded = false;

        Widget buildSubject(StateSetter setLocalState) {
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 220,
                  child: StatefulBuilder(
                    builder: (context, innerSetState) {
                      return GestureDetector(
                        key: const ValueKey('morph_tap_surface'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => innerSetState(() => expanded = !expanded),
                        child: LiquidGlassMorph(
                          key: const ValueKey('morph_under_test'),
                          alignment: Alignment.topCenter,
                          opacity: 0.72,
                          motion: LiquidGlassMorphMotion.fluid,
                          touch: const LiquidGlassTouch.flexing(
                            LiquidGlassFlex(stretch: 5, squeeze: 0.72),
                          ),
                          child: expanded
                              ? Container(
                                  key: const ValueKey('morph_expanded'),
                                  width: 240,
                                  height: 120,
                                  padding: const EdgeInsets.all(12),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      LiquidGlassMorphShared(
                                        tag: 'lock_icon',
                                        child: Icon(Icons.lock, size: 16),
                                      ),
                                      SizedBox(width: 8),
                                      Text('Expanded'),
                                    ],
                                  ),
                                )
                              : const Padding(
                                  key: ValueKey('morph_compact'),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      LiquidGlassMorphShared(
                                        tag: 'lock_icon',
                                        child: Icon(Icons.lock, size: 12),
                                      ),
                                      SizedBox(width: 6),
                                      Text('Compact'),
                                    ],
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        }

        await tester.pumpWidget(buildSubject((_) {}));
        await tester.pump(const Duration(milliseconds: 16));

        final morphFinder = find.byKey(const ValueKey('morph_under_test'));
        final morphBlenderFinder = find.descendant(
          of: morphFinder,
          matching: find.byType(LiquidGlassBlender),
        );
        final morphLensFinder = find.descendant(
          of: morphFinder,
          matching: find.byType(LiquidGlassLens),
        );

        // Idle at rest: single LiquidGlassLens, no LiquidGlassBlender overhead.
        expect(morphBlenderFinder, findsNothing);
        expect(morphLensFinder, findsOneWidget);

        // Trigger rapid A -> B -> A -> B reversals mid-flight.
        await tester.tap(find.byKey(const ValueKey('morph_tap_surface')));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 32));
        expect(morphBlenderFinder, findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('morph_tap_surface')));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.tap(find.byKey(const ValueKey('morph_tap_surface')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Expanded'), findsOneWidget);
        expect(morphBlenderFinder, findsNothing);
        expect(morphLensFinder, findsOneWidget);

        // Exercise LiquidGlassTouch.flexing drag & release on the settled glass.
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Expanded')),
        );
        await tester.pump(const Duration(milliseconds: 32));
        await gesture.moveBy(const Offset(18, 6));
        await tester.pump(const Duration(milliseconds: 32));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Theaver LiquidGlassProvider 5.2 configuration & opacity scaling', () {
    test('setShaderBlur updates LiquidGlassConfiguration and persists', () async {
      final provider = LiquidGlassProvider()..init();
      await provider.setMode(GlassMode.full);

      expect(LiquidGlassConfiguration.shapeCache, isTrue);
      expect(provider.shaderBlur, isTrue);
      expect(LiquidGlassConfiguration.blurMethod, LiquidGlassBlurMethod.shader);
      expect(
        LiquidGlassConfiguration.batchBlurMethod,
        LiquidGlassBlurMethod.shader,
      );

      await provider.setShaderBlur(false);
      expect(provider.shaderBlur, isFalse);
      expect(LiquidGlassConfiguration.blurMethod, LiquidGlassBlurMethod.engine);
      expect(
        LiquidGlassConfiguration.batchBlurMethod,
        LiquidGlassBlurMethod.engine,
      );

      await SettingsService().init();
      final reloaded = LiquidGlassProvider()..init();
      expect(reloaded.shaderBlur, isFalse);
    });

    test('scaleStyleForLensOpacity scales blur only for engine blur and always scales shadow', () async {
      final provider = _ForcedGlassProvider(GlassMode.full);
      const base = LiquidGlassStyle(
        blur: 10.0,
        shadow: LiquidGlassShadow(opacity: 0.4),
      );

      await provider.setShaderBlur(true);
      final shaderScaled = provider.scaleStyleForLensOpacity(base, 0.5);
      expect(shaderScaled.blur, 10.0);
      expect(shaderScaled.shadow!.opacity, closeTo(0.2, 0.001));

      await provider.setShaderBlur(false);
      final engineScaled = provider.scaleStyleForLensOpacity(base, 0.5);
      expect(engineScaled.blur, closeTo(5.0, 0.001));
      expect(engineScaled.shadow!.opacity, closeTo(0.2, 0.001));

      // Reset to default for subsequent tests.
      await provider.setShaderBlur(true);
    });

    testWidgets(
      'WebViewFloatingCapsule & TheavDialog pass native opacity to LiquidGlassLens without outer FadeTransition',
      (tester) async {
        final provider = _ForcedGlassProvider(GlassMode.full)..init();
        await provider.setShaderBlur(false);

        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: provider,
            child: const MaterialApp(
              home: Scaffold(
                body: Center(
                  child: WebViewFloatingCapsule(
                    opacity: 0.5,
                    child: Text('Find bar'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        final lens = tester.widget<LiquidGlassLens>(find.byType(LiquidGlassLens));
        expect(lens.opacity, closeTo(0.5, 0.001));
        expect(lens.style.blur, closeTo(4.0, 0.001));

        // Verify showTheavDialog presents LiquidGlassLens without outer FadeTransition in Glass mode.
        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: provider,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () {
                      showTheavDialog<void>(
                        context: context,
                        title: 'Glass Dialog',
                        message: 'Body',
                        actions: const [
                          TheavDialogAction(label: 'OK'),
                        ],
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 110));

        expect(find.byType(TheavDialog<void>), findsOneWidget);
        expect(find.byType(LiquidGlassLens), findsOneWidget);
        expect(
          find.ancestor(
            of: find.byType(LiquidGlassLens),
            matching: find.byType(FadeTransition),
          ),
          findsNothing,
        );

        await provider.setShaderBlur(true);
      },
    );

    testWidgets(
      'SafariWebAlertCard renders cleanly with custom opacity in Glass mode',
      (tester) async {
        final provider = _ForcedGlassProvider(GlassMode.full)..init();
        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: provider,
            child: const MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SafariWebAlertCard<bool>(
                    title: 'Confirm',
                    message: 'Proceed?',
                    opacity: 0.6,
                    actions: [
                      SafariAlertAction<bool>(label: 'OK', result: true),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        final lens = tester.widget<LiquidGlassLens>(find.byType(LiquidGlassLens));
        expect(lens.opacity, closeTo(0.6, 0.001));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'LiquidGlassBatch renders single-lens ChatInputBar in Glass mode and minLensCount stays 1',
      (tester) async {
        expect(LiquidGlassBlender.minLensCount, 1);

        final provider = _ForcedGlassProvider(GlassMode.full)..init();
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: provider,
            child: MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: ChatInputBar(
                    controller: controller,
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(LiquidGlassBatch), findsOneWidget);
        expect(find.byType(LiquidGlassBlender), findsNothing);
        expect(find.byType(LiquidGlassInputField), findsOneWidget);
        expect(find.byType(LiquidGlassLens), findsOneWidget);
        expect(find.byType(EditableText), findsOneWidget);

        await tester.enterText(find.byType(EditableText), 'Привет');
        await tester.pump();
        expect(controller.text, 'Привет');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'LiquidGlassMorph preserves stateful child across idle -> morph -> idle transitions',
      (tester) async {
        bool wide = false;
        late StateSetter rebuild;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 120,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      rebuild = setState;
                      return LiquidGlassMorph(
                        motion: LiquidGlassMorphMotion.fluid,
                        child: _MorphProbeChild(
                          key: const ValueKey('probe_child'),
                          width: wide ? 220 : 100,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 16));
        final State initialState = tester.state(find.byType(_MorphProbeChild));
        expect(find.byType(LiquidGlassBlender), findsNothing);

        rebuild(() => wide = true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 32));
        expect(find.byType(LiquidGlassBlender), findsOneWidget);
        expect(
          identical(tester.state(find.byType(_MorphProbeChild)), initialState),
          isTrue,
        );

        await tester.pumpAndSettle();
        expect(find.byType(LiquidGlassBlender), findsNothing);
        expect(
          identical(tester.state(find.byType(_MorphProbeChild)), initialState),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ActiveCallTopBanner keeps zero running animations when no call is active',
      (tester) async {
        final provider = _ForcedGlassProvider(GlassMode.disabled)..init();
        final callProvider = CallStateProvider();
        addTearDown(callProvider.dispose);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<LiquidGlassProvider>.value(value: provider),
              ChangeNotifierProvider<CallStateProvider>.value(value: callProvider),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ActiveCallTopBanner(
                  onRestoreCall: () {},
                  child: const Center(child: Text('Idle chat')),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('Idle chat'), findsOneWidget);
        expect(tester.hasRunningAnimations, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
