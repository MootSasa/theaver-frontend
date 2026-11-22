import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:theaver/models/theav_theme.dart';
import 'package:theaver/services/bot_service.dart';
import 'package:theaver/services/glass_toast_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/mini_app_js_bridge.dart';
import 'package:theaver/services/theav_theme_service.dart';
import 'package:theaver/widgets/bot/mini_app_webview_sheet.dart';
import 'package:theaver/widgets/common/adaptive_switch.dart';
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

Widget _buildHost({
  required Widget child,
  GlassMode? glassMode,
  Brightness brightness = Brightness.dark,
}) {
  final app = MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF1C1C1E),
      ),
    ),
    builder: (context, appChild) => MinimizedMiniAppHost(
      child: appChild ?? const SizedBox.shrink(),
    ),
    home: Scaffold(
      body: SafeArea(child: child),
    ),
  );

  if (glassMode == null) {
    // Intentionally omit LiquidGlassProvider to verify safe fallback.
    return app;
  }

  return ChangeNotifierProvider<LiquidGlassProvider>.value(
    value: _TestLiquidGlassProvider(glassMode),
    child: app,
  );
}

void main() {
  for (final GlassMode? mode in <GlassMode?>[
    null,
    GlassMode.disabled,
    GlassMode.lite,
    GlassMode.full,
  ]) {
    final modeLabel = mode == null
        ? 'without LiquidGlassProvider (fallback)'
        : 'with GlassMode.${mode.name}';

    group('Design System $modeLabel', () {
      testWidgets('renders inset group, rows, and inline field',
          (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        var rowTapped = false;

        await tester.pumpWidget(
          _buildHost(
            glassMode: mode,
            brightness: mode == GlassMode.lite
                ? Brightness.light
                : Brightness.dark,
            child: SingleChildScrollView(
              child: TheavInsetGroup(
                header: 'Основные настройки',
                footer: 'Подпись под группой',
                children: [
                  TheavListRow(
                    leading: const Icon(Icons.tune),
                    title: 'Права участников',
                    subtitle: 'Управление доступом',
                    valueText: 'Все',
                    showChevron: true,
                    onTap: () => rowTapped = true,
                  ),
                  TheavInlineTextField(
                    controller: controller,
                    label: 'Название',
                    placeholder: 'Введите название',
                    prefix: const Icon(Icons.edit, size: 18),
                    suffix: const Text('32'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Основные настройки'), findsOneWidget);
        expect(find.text('Подпись под группой'), findsOneWidget);
        expect(find.text('Права участников'), findsOneWidget);
        expect(find.text('Все'), findsOneWidget);

        await tester.tap(find.text('Права участников'));
        await tester.pump();
        expect(rowTapped, isTrue);

        await tester.enterText(find.byType(TextField), 'Канал новостей');
        expect(controller.text, 'Канал новостей');

        final tf = tester.widget<TextField>(find.byType(TextField));
        expect(tf.decoration?.filled, isFalse);
      });

      testWidgets(
          'interactive controls (segmented, switch, check, slider, pills)',
          (tester) async {
        var selectedSegment = 'a';
        var switchValue = false;
        var checked = false;
        var sliderIndex = 0;
        var headerTapped = false;
        var pillTapped = false;

        await tester.pumpWidget(
          _buildHost(
            glassMode: mode,
            child: StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          TheavHeaderIconButton(
                            icon: const Icon(Icons.check),
                            tooltip: 'Готово',
                            onTap: () => headerTapped = true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TheavSegmentedControl<String>(
                        options: const [
                          TheavSegmentOption(value: 'a', label: 'Публичный'),
                          TheavSegmentOption(value: 'b', label: 'Частный'),
                        ],
                        selected: selectedSegment,
                        onChanged: (v) => setState(() => selectedSegment = v),
                      ),
                      const SizedBox(height: 12),
                      TheavInsetGroup(
                        children: [
                          TheavListRow(
                            title: 'Защита контента',
                            trailing: TheavSwitch(
                              value: switchValue,
                              semanticLabel: 'Защита контента',
                              onChanged: (v) => setState(() => switchValue = v),
                            ),
                          ),
                          TheavListRow(
                            title: 'Выбор элемента',
                            trailing: TheavCheckCircle(
                              selected: checked,
                              onTap: () => setState(() => checked = !checked),
                            ),
                            onTap: () => setState(() => checked = !checked),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TheavSteppedSlider(
                        title: 'Медленный режим',
                        selectedIndex: sliderIndex,
                        labels: const ['Выкл', '10с', '30с', '1м'],
                        onChanged: (i) => setState(() => sliderIndex = i),
                      ),
                      const SizedBox(height: 12),
                      TheavFloatingPillButton(
                        label: 'Применить',
                        isPrimary: true,
                        onTap: () => pillTapped = true,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(TheavHeaderIconButton));
        await tester.pump();
        expect(headerTapped, isTrue);

        await tester.tap(find.text('Частный'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(selectedSegment, 'b');

        final expectGlassControls =
            mode == GlassMode.lite || mode == GlassMode.full;
        expect(
          find.byKey(const ValueKey('lg-animated-nav-gesture-overlay')),
          expectGlassControls ? findsOneWidget : findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(TheavSegmentedControl<String>),
            matching: find.byType(ClipRRect),
          ),
          findsNothing,
        );
        expect(
          find.byType(LiquidGlassSwitch),
          expectGlassControls ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(LiquidGlassSlider),
          expectGlassControls ? findsOneWidget : findsNothing,
        );

        await tester.tap(find.byType(TheavSwitch));
        await tester.pumpAndSettle();
        expect(switchValue, isTrue);

        await tester.tap(find.text('Выбор элемента'));
        await tester.pumpAndSettle();
        expect(checked, isTrue);

        await tester.tap(find.text('30с'));
        await tester.pumpAndSettle();
        expect(sliderIndex, 2);

        await tester.tap(find.text('Применить'));
        await tester.pump();
        expect(pillTapped, isTrue);
      });

      testWidgets('showTheavDialog and showTheavModalSheet open and return values',
          (tester) async {
        String? dialogResult;
        String? sheetResult;

        await tester.pumpWidget(
          _buildHost(
            glassMode: mode,
            child: Builder(
              builder: (context) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        dialogResult = await showTheavDialog<String>(
                          context: context,
                          title: 'Удалить чат?',
                          message: 'Действие необратимо',
                          actions: const [
                            TheavDialogAction<String>(
                              label: 'Отмена',
                              result: 'cancel',
                            ),
                            TheavDialogAction<String>(
                              label: 'Удалить',
                              result: 'delete',
                              isDestructive: true,
                            ),
                          ],
                        );
                      },
                      child: const Text('OpenDialog'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        sheetResult = await showTheavModalSheet<String>(
                          context: context,
                          title: 'Параметры',
                          showCloseButton: true,
                          builder: (sheetCtx) {
                            return TheavFloatingPillButton(
                              label: 'Выбрать',
                              isPrimary: true,
                              onTap: () =>
                                  Navigator.of(sheetCtx).pop('selected'),
                            );
                          },
                        );
                      },
                      child: const Text('OpenSheet'),
                    ),
                  ],
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('OpenDialog'));
        await tester.pumpAndSettle();
        expect(find.text('Удалить чат?'), findsOneWidget);
        expect(find.text('Действие необратимо'), findsOneWidget);

        await tester.tap(find.text('Удалить'));
        await tester.pumpAndSettle();
        expect(dialogResult, 'delete');

        await tester.tap(find.text('OpenSheet'));
        await tester.pumpAndSettle();
        expect(find.text('Параметры'), findsOneWidget);

        await tester.tap(find.text('Выбрать'));
        await tester.pumpAndSettle();
        expect(sheetResult, 'selected');
      });

      testWidgets(
          'disabled TheavSwitch, AdaptiveSwitch, and AdaptiveSlider still use liquid_glass_easy in glass modes',
          (tester) async {
        await tester.pumpWidget(
          _buildHost(
            glassMode: mode,
            child: const SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TheavSwitch(
                    value: false,
                    onChanged: null,
                    semanticLabel: 'Disabled off',
                  ),
                  SizedBox(height: 8),
                  TheavSwitch(
                    value: true,
                    onChanged: null,
                    semanticLabel: 'Disabled on',
                  ),
                  SizedBox(height: 8),
                  AdaptiveSwitch(
                    value: false,
                    onChanged: null,
                  ),
                  SizedBox(height: 12),
                  AdaptiveSlider(
                    value: 0.5,
                    onChanged: null,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final expectGlassControls =
            mode == GlassMode.lite || mode == GlassMode.full;
        expect(
          find.byType(LiquidGlassSwitch),
          expectGlassControls ? findsNWidgets(3) : findsNothing,
        );
        expect(
          find.byType(LiquidGlassSlider),
          expectGlassControls ? findsOneWidget : findsNothing,
        );

        await tester.tap(find.byType(TheavSwitch).first, warnIfMissed: false);
        await tester.tap(find.byType(AdaptiveSwitch), warnIfMissed: false);
        await tester.pump();
      });

      testWidgets(
          'TheavModalSheet stretches ONLY via drag handle bar, settles without spring overshoot, and dismisses on handle fling',
          (tester) async {
        await tester.pumpWidget(
          _buildHost(
            glassMode: mode,
            child: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showTheavModalSheet<void>(
                      context: context,
                      title: 'Панель без пружины',
                      showCloseButton: true,
                      builder: (_) => const SizedBox(
                        height: 160,
                        child: Center(child: Text('Контент панели')),
                      ),
                    );
                  },
                  child: const Text('OpenHandleSheet'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('OpenHandleSheet'));
        await tester.pumpAndSettle();
        expect(find.byType(TheavModalSheet), findsOneWidget);

        final cardFinder = find
            .descendant(
              of: find.byType(TheavModalSheet),
              matching: find.byWidgetPredicate(
                (w) => w is Container && w.constraints != null,
              ),
            )
            .first;

        final Rect restRect = tester.getRect(cardFinder);

        // Dragging body or header must NOT stretch or drag the sheet.
        final bodyGesture = await tester.startGesture(
          tester.getCenter(find.text('Контент панели')),
        );
        await bodyGesture.moveBy(const Offset(0, -60));
        await tester.pump();
        expect(tester.getRect(cardFinder).top, closeTo(restRect.top, 0.1));
        await bodyGesture.up();
        await tester.pumpAndSettle();

        final headerGesture = await tester.startGesture(
          tester.getCenter(find.text('Панель без пружины')),
        );
        await headerGesture.moveBy(const Offset(0, -60));
        await tester.pump();
        expect(tester.getRect(cardFinder).top, closeTo(restRect.top, 0.1));
        await headerGesture.up();
        await tester.pumpAndSettle();

        // Pulling upward ONLY on the handle bar stretches the sheet upward.
        final handleFinder =
            find.byKey(const ValueKey('theav_sheet_drag_handle'));
        expect(handleFinder, findsOneWidget);
        final gesture = await tester.startGesture(
          tester.getCenter(handleFinder),
        );
        for (int i = 0; i < 4; i++) {
          await gesture.moveBy(const Offset(0, -30));
          await tester.pump();
        }
        final Rect stretchedRect = tester.getRect(cardFinder);
        expect(stretchedRect.top, lessThan(restRect.top));
        expect(stretchedRect.bottom, closeTo(restRect.bottom, 1.0));

        // Release: settles monotonically back to rest with zero spring overshoot.
        await gesture.up();
        double prevTop = stretchedRect.top;
        for (int i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          final Rect frameRect = tester.getRect(cardFinder);
          expect(frameRect.top, lessThanOrEqualTo(restRect.top + 0.05));
          expect(frameRect.top, greaterThanOrEqualTo(prevTop - 0.05));
          prevTop = frameRect.top;
        }
        await tester.pumpAndSettle();
        final Rect settledRect = tester.getRect(cardFinder);
        expect(settledRect.top, closeTo(restRect.top, 0.5));

        // Fling downward on the handle bar: dismisses cleanly.
        await tester.fling(
          handleFinder,
          const Offset(0, 320),
          1200,
        );
        await tester.pumpAndSettle();
        expect(find.byType(TheavModalSheet), findsNothing);
      });

      testWidgets(
          'TheavModalSheet uses LiquidGlassLens without BackdropFilter/Opacity and applies library LiquidGlassFlexDeform on handle stretch',
          (tester) async {
        final bool expectGlass =
            mode == GlassMode.lite || mode == GlassMode.full;

        await tester.pumpWidget(
          _buildHost(
            glassMode: mode,
            child: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showTheavModalSheet<void>(
                      context: context,
                      title: 'Тест стекла',
                      builder: (_) => const SizedBox(
                        height: 180,
                        child: Center(child: Text('Содержимое')),
                      ),
                    );
                  },
                  child: const Text('OpenGlassSheet'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('OpenGlassSheet'));
        await tester.pumpAndSettle();

        expect(find.byType(TheavSheetSurface), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(TheavModalSheet),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
        );

        final lensFinder = find.descendant(
          of: find.byType(TheavSheetSurface),
          matching: find.byType(LiquidGlassLens),
        );

        if (expectGlass) {
          expect(lensFinder, findsOneWidget);
          expect(
            find.ancestor(
              of: lensFinder,
              matching: find.byType(Opacity),
            ),
            findsNothing,
          );
          expect(
            find.ancestor(
              of: lensFinder,
              matching: find.byType(FadeTransition),
            ),
            findsNothing,
          );
          expect(
            tester.widget<LiquidGlassLens>(lensFinder).deform,
            LiquidGlassFlexDeform.none,
          );

          // Dragging body must not deform lens.
          final bodyGesture = await tester.startGesture(
            tester.getCenter(find.text('Содержимое')),
          );
          await bodyGesture.moveBy(const Offset(0, -60));
          await tester.pump();
          expect(
            tester.widget<LiquidGlassLens>(lensFinder).deform,
            LiquidGlassFlexDeform.none,
          );
          await bodyGesture.up();
          await tester.pumpAndSettle();

          // Dragging handle bar upward drives library-native LiquidGlassFlexDeform.
          final handleFinder =
              find.byKey(const ValueKey('theav_sheet_drag_handle'));
          final handleGesture = await tester.startGesture(
            tester.getCenter(handleFinder),
          );
          await handleGesture.moveBy(const Offset(0, -80));
          await tester.pump();
          final LiquidGlassFlexDeform? deform =
              tester.widget<LiquidGlassLens>(lensFinder).deform;
          expect(deform, isNotNull);
          expect(deform!.top, greaterThan(0.0));
          expect(deform.top, lessThanOrEqualTo(40.0));
          await handleGesture.up();
          await tester.pumpAndSettle();
          expect(
            tester.widget<LiquidGlassLens>(lensFinder).deform,
            LiquidGlassFlexDeform.none,
          );
        } else {
          expect(lensFinder, findsNothing);
        }
      });

      testWidgets(
          'MiniAppWebViewSheet matches Telegram chrome, minimizes to bottom bar, restores, and closes cleanly',
          (tester) async {
        addTearDown(MiniAppSessionController.instance.resetForTesting);

        final bool expectGlass =
            mode == GlassMode.lite || mode == GlassMode.full;

        const launchData = MiniAppLaunchData(
          url: 'https://api.theaver.app/api/miniapps/studio',
          initData: 'user=%7B%7D&hash=abc',
          botId: '1',
          botUsername: 'BotMother',
          botDisplayName: 'BotMother',
          botIsVerified: true,
        );

        await tester.pumpWidget(
          _buildHost(
            glassMode: mode,
            child: Builder(
              builder: (context) => SizedBox.expand(
                key: const ValueKey('mini_app_safe_body'),
                child: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showTheavModalSheet<void>(
                        context: context,
                        enableDrag: false,
                        useRootNavigator: true,
                        builder: (_) => const SizedBox.shrink(),
                        customSheetBuilder: (_) => const MiniAppWebViewSheet(
                          launchData: launchData,
                          botName: 'BotMother',
                          botUsername: 'BotMother',
                          isVerified: true,
                        ),
                      );
                    },
                    child: const Text('OpenMiniApp'),
                  ),
                ),
              ),
            ),
          ),
        );

        final double screenHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        expect(
          tester.getSize(find.byKey(const ValueKey('mini_app_safe_body'))).height,
          moreOrLessEquals(screenHeight, epsilon: 0.5),
        );
        expect(
          find.byKey(const ValueKey('minimized_mini_app_bar')),
          findsNothing,
        );

        await tester.tap(find.text('OpenMiniApp'));
        await tester.pumpAndSettle();

        final sheetFinder = find.byType(MiniAppWebViewSheet);
        expect(sheetFinder, findsOneWidget);
        expect(
          find.byKey(const ValueKey('minimized_mini_app_bar')),
          findsNothing,
        );
        expect(
          tester.getSize(sheetFinder).height,
          moreOrLessEquals(screenHeight, epsilon: 0.5),
        );

        expect(find.text('BotMother'), findsWidgets);
        expect(
          find.byKey(const ValueKey('mini_app_verified_seal')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('mini_app_close_or_back_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('mini_app_collapse_expand_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('mini_app_more_menu_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('mini_app_grid_loader')),
          findsOneWidget,
        );
        expect(find.byType(MiniAppGridPlaceholder), findsOneWidget);

        // Floating oval header must sit over an unblurred full-bleed viewport.
        expect(
          find.descendant(
            of: sheetFinder,
            matching: find.byType(TheavSheetSurface),
          ),
          findsNothing,
        );
        final headerFinder = find.descendant(
          of: sheetFinder,
          matching: find.byType(WebViewFloatingHeader),
        );
        expect(headerFinder, findsOneWidget);
        final viewportFinder = find.descendant(
          of: sheetFinder,
          matching: find.byKey(const ValueKey('mini_app_viewport_container')),
        );
        expect(viewportFinder, findsOneWidget);
        expect(
          find.descendant(
            of: viewportFinder,
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: viewportFinder,
            matching: find.byType(LiquidGlassLens),
          ),
          findsNothing,
        );
        if (expectGlass) {
          expect(
            find.descendant(
              of: headerFinder,
              matching: find.byKey(const ValueKey('webview_center_morph')),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: headerFinder,
              matching: find.byKey(const ValueKey('webview_right_morph')),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: headerFinder,
              matching: find.byType(LiquidGlassMorph),
            ),
            findsNWidgets(2),
          );
          expect(
            find.descendant(
              of: headerFinder,
              matching: find.byType(LiquidGlassBlender),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: sheetFinder,
              matching: find.byType(BackdropFilter),
            ),
            findsNothing,
          );
        } else {
          expect(
            find.descendant(
              of: headerFinder,
              matching: find.byKey(
                const ValueKey('webview_center_matte_morph'),
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: headerFinder,
              matching: find.byKey(const ValueKey('webview_right_matte_morph')),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: headerFinder,
              matching: find.byType(LiquidGlassLens),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: headerFinder,
              matching: find.byType(LiquidGlassMorph),
            ),
            findsNothing,
          );
        }

        final morphKey = ValueKey(
          expectGlass ? 'webview_right_morph' : 'webview_right_matte_morph',
        );
        final State rightMorphStateBefore = tester.state(
          find.descendant(of: headerFinder, matching: find.byKey(morphKey)),
        );

        // Opening overflow menu morphs inline out of WebViewFloatingHeader's right capsule.
        await tester.tap(
          find.byKey(const ValueKey('mini_app_more_menu_button')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));

        expect(
          identical(
            tester.state(
              find.descendant(of: headerFinder, matching: find.byKey(morphKey)),
            ),
            rightMorphStateBefore,
          ),
          isTrue,
        );
        if (!expectGlass) {
          final midOpenSize = tester.getSize(find.byKey(morphKey));
          expect(midOpenSize.width, greaterThan(84.5));
          expect(midOpenSize.width, lessThan(243.5));
          expect(midOpenSize.height, greaterThan(44.5));
          expect(midOpenSize.height, lessThan(187.5));
        }

        await tester.pumpAndSettle();

        final menuFinder = find.descendant(
          of: headerFinder,
          matching: find.byKey(const ValueKey('mini_app_overflow_menu')),
        );
        expect(menuFinder, findsOneWidget);

        // Dismiss overflow menu smoothly before tapping downward chevron to minimize.
        await tester.tapAt(tester.getCenter(sheetFinder));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));
        expect(
          identical(
            tester.state(
              find.descendant(of: headerFinder, matching: find.byKey(morphKey)),
            ),
            rightMorphStateBefore,
          ),
          isTrue,
        );
        if (!expectGlass) {
          final midCloseSize = tester.getSize(find.byKey(morphKey));
          expect(midCloseSize.width, greaterThan(84.5));
          expect(midCloseSize.width, lessThan(243.5));
          expect(midCloseSize.height, greaterThan(44.5));
          expect(midCloseSize.height, lessThan(187.5));
        }
        await tester.pumpAndSettle();
        expect(menuFinder, findsNothing);

        // Minimize via downward chevron -> collapses into Telegram-style bottom bar.
        await tester.tap(
          find.byKey(const ValueKey('mini_app_collapse_expand_button')),
        );
        await tester.pumpAndSettle();

        expect(sheetFinder, findsNothing);
        final miniBarFinder =
            find.byKey(const ValueKey('minimized_mini_app_bar'));
        expect(miniBarFinder, findsOneWidget);
        expect(find.text('BotMother'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('minimized_mini_app_close_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('minimized_mini_app_expand_button')),
          findsOneWidget,
        );

        // Dedicated dock region shrinks Scaffold cleanly without overlapping it,
        // has no top border, and adds upward concave corner fillets into main screen.
        final dockFinder =
            find.byKey(const ValueKey('minimized_mini_app_dock_region'));
        final filletsFinder =
            find.byKey(const ValueKey('minimized_mini_app_dock_fillets'));
        expect(dockFinder, findsOneWidget);
        expect(tester.widget(dockFinder), isA<ColoredBox>());
        final dockBox = tester.widget<ColoredBox>(dockFinder);
        final dockTheme = Theme.of(tester.element(dockFinder));
        final dockResolved = MiniAppJsBridge.resolveThemeColors(dockTheme);
        expect(dockBox.color, equals(dockResolved.dockBg));
        expect(dockBox.color, isNot(equals(dockResolved.bodyBg)));
        expect(
          dockBox.color,
          isNot(equals(dockTheme.scaffoldBackgroundColor)),
        );
        expect(dockBox.color, isNot(equals(dockResolved.headerBg)));
        expect(filletsFinder, findsOneWidget);
        final Rect scaffoldRect = tester.getRect(find.byType(Scaffold));
        expect(scaffoldRect.height, lessThan(screenHeight - 48.0));
        expect(
          scaffoldRect.bottom,
          lessThanOrEqualTo(tester.getTopLeft(dockFinder).dy + 0.5),
        );
        expect(
          screenHeight -
              tester
                  .getSize(find.byKey(const ValueKey('mini_app_safe_body')))
                  .height,
          greaterThan(48.0),
        );

        // LiquidGlassLens on minimized bar in glass mode (without Opacity/FadeTransition); matte otherwise.
        final barLensFinder = find.descendant(
          of: miniBarFinder,
          matching: find.byType(LiquidGlassLens),
        );
        if (expectGlass) {
          expect(barLensFinder, findsOneWidget);
          expect(
            find.ancestor(
              of: barLensFinder,
              matching: find.descendant(
                of: miniBarFinder,
                matching: find.byWidgetPredicate(
                  (w) => w is Opacity || w is FadeTransition,
                ),
              ),
            ),
            findsNothing,
          );
        } else {
          expect(barLensFinder, findsNothing);
        }

        // Expand back to full-screen Mini App via upward chevron.
        await tester.tap(
          find.byKey(const ValueKey('minimized_mini_app_expand_button')),
        );
        await tester.pumpAndSettle();

        expect(sheetFinder, findsOneWidget);
        expect(
          tester.getSize(sheetFinder).height,
          moreOrLessEquals(screenHeight, epsilon: 0.5),
        );
        expect(miniBarFinder, findsNothing);
        expect(dockFinder, findsNothing);
        expect(filletsFinder, findsNothing);

        // Minimize again and close via minimized bar close button.
        await tester.tap(
          find.byKey(const ValueKey('mini_app_collapse_expand_button')),
        );
        await tester.pumpAndSettle();
        expect(miniBarFinder, findsOneWidget);
        expect(dockFinder, findsOneWidget);
        expect(filletsFinder, findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('minimized_mini_app_close_button')),
        );
        await tester.pumpAndSettle();

        expect(miniBarFinder, findsNothing);
        expect(dockFinder, findsNothing);
        expect(filletsFinder, findsNothing);
        expect(sheetFinder, findsNothing);
        expect(
          tester.getSize(find.byType(Scaffold)).height,
          moreOrLessEquals(screenHeight, epsilon: 0.5),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('mini_app_safe_body'))).height,
          moreOrLessEquals(screenHeight, epsilon: 0.5),
        );
      });
    });
  }

  testWidgets(
      'MiniAppWebViewSheet and MiniAppJsBridge derive palette dynamically from active app theme',
      (tester) async {
    const customPalette = TheavPalette(
      primary: Color(0xFFE91E63),
      onPrimary: Color(0xFFFFFFFF),
      background: Color(0xFF2B1035),
      surface: Color(0xFF3A1647),
      onSurface: Color(0xFFFCE4EC),
      appBarBackground: Color(0xFF4A1B59),
      appBarForeground: Color(0xFFFFD54F),
      chatBubbleOutgoing: Color(0xFFE91E63),
      chatBubbleOutgoingText: Color(0xFFFFFFFF),
      chatBubbleOutgoingSubtext: Color(0xB3FFFFFF),
      chatBubbleIncoming: Color(0xFF3A1647),
      chatBubbleIncomingText: Color(0xFFFCE4EC),
      chatBubbleIncomingSubtext: Color(0xB3FCE4EC),
      chatDateBadge: Color(0xFF4A1B59),
      chatDateBadgeText: Color(0xFFFFD54F),
    );
    final customTheme = const TheavTheme(
      id: 'custom_sunset_test',
      name: 'Sunset Test',
      author: 'Test',
      isDark: true,
      palette: customPalette,
      wallpaper: TheavWallpaper(),
    ).toThemeData();

    final themeParams = MiniAppJsBridge.buildThemeParams(customTheme);
    expect(themeParams['bg_color'], '#2b1035');
    expect(themeParams['secondary_bg_color'], '#3a1647');
    expect(themeParams['header_bg_color'], '#4a1b59');
    expect(themeParams['bottom_bar_bg_color'], '#4a1b59');
    expect(themeParams['button_color'], '#e91e63');
    expect(themeParams['text_color'], '#fce4ec');

    final resolvedCustom = MiniAppJsBridge.resolveThemeColors(customTheme);
    expect(resolvedCustom.dockBg, isNot(equals(resolvedCustom.bodyBg)));
    expect(resolvedCustom.dockBg, isNot(equals(resolvedCustom.headerBg)));
    for (final builtIn in TheavThemeService.builtInThemes) {
      final resolvedBuiltIn =
          MiniAppJsBridge.resolveThemeColors(builtIn.toThemeData());
      expect(
        resolvedBuiltIn.dockBg,
        isNot(equals(resolvedBuiltIn.bodyBg)),
        reason: 'dockBg should differ from bodyBg for ${builtIn.id}',
      );
      expect(
        resolvedBuiltIn.dockBg,
        isNot(equals(resolvedBuiltIn.headerBg)),
        reason: 'dockBg should differ from headerBg for ${builtIn.id}',
      );
    }

    const launchData = MiniAppLaunchData(
      url: 'https://api.theaver.app/api/miniapps/studio',
      initData: 'hash=test',
      botId: '1',
      botUsername: 'BotMother',
      botDisplayName: 'BotMother',
      botIsVerified: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: customTheme,
        home: const Scaffold(
          body: MiniAppWebViewSheet(
            launchData: launchData,
            botName: 'BotMother',
            botUsername: 'BotMother',
            isVerified: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final seal = tester.widget<MiniAppVerifiedSeal>(
      find.byKey(const ValueKey('mini_app_verified_seal')),
    );
    expect(seal.color, const Color(0xFFE91E63));
    expect(seal.checkColor, customPalette.onPrimary);

    final titleTexts = tester.widgetList<Text>(find.text('BotMother')).toList();
    expect(
      titleTexts.any((t) => t.style?.color == const Color(0xFFFFD54F)),
      isTrue,
    );

    final bodyMaterials = tester
        .widgetList<Material>(
          find.descendant(
            of: find.byType(MiniAppWebViewSheet),
            matching: find.byType(Material),
          ),
        )
        .toList();
    expect(
      bodyMaterials.any((m) => m.color == const Color(0xFF2B1035)),
      isTrue,
    );

    final headerDecorated = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(WebViewFloatingHeader),
            matching: find.byType(DecoratedBox),
          ),
        )
        .where((box) {
      final d = box.decoration;
      return d is BoxDecoration &&
          d.color != null &&
          (d.color!.toARGB32() & 0x00FFFFFF) ==
              (const Color(0xFF4A1B59).toARGB32() & 0x00FFFFFF);
    });
    expect(headerDecorated, isNotEmpty);
  });

  testWidgets(
      'Multiple minimized Mini Apps render stacked counter bar and open 3D tabs switcher',
      (tester) async {
    addTearDown(MiniAppSessionController.instance.resetForTesting);

    const launch1 = MiniAppLaunchData(
      url: 'https://api.theaver.app/api/miniapps/studio',
      initData: 'user=%7B%7D&hash=1',
      botId: '1',
      botUsername: 'BotFather',
      botDisplayName: 'BotFather',
      botIsVerified: true,
    );
    const launch2 = MiniAppLaunchData(
      url: 'https://wallet.example.com/app',
      initData: 'user=%7B%7D&hash=2',
      botId: '2',
      botUsername: 'walt_bot',
      botDisplayName: 'Walt (ранее Кошелёк)',
    );

    final session1 = MiniAppSession(
      id: 'tab_botfather',
      launchData: launch1,
      botName: 'BotFather',
      botUsername: 'BotFather',
      isVerified: true,
    );
    final session2 = MiniAppSession(
      id: 'tab_walt',
      launchData: launch2,
      botName: 'Walt (ранее Кошелёк)',
      botUsername: 'walt_bot',
    );

    await tester.pumpWidget(
      _buildHost(
        glassMode: GlassMode.full,
        child: Builder(
          builder: (context) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () {
                    showTheavModalSheet<void>(
                      context: context,
                      enableDrag: false,
                      useRootNavigator: true,
                      builder: (_) => const SizedBox.shrink(),
                      customSheetBuilder: (_) => MiniAppWebViewSheet(
                        launchData: launch1,
                        botName: 'BotFather',
                        botUsername: 'BotFather',
                        isVerified: true,
                        session: session1,
                      ),
                    );
                  },
                  child: const Text('OpenOne'),
                ),
                ElevatedButton(
                  onPressed: () {
                    showTheavModalSheet<void>(
                      context: context,
                      enableDrag: false,
                      useRootNavigator: true,
                      builder: (_) => const SizedBox.shrink(),
                      customSheetBuilder: (_) => MiniAppWebViewSheet(
                        launchData: launch2,
                        botName: 'Walt (ранее Кошелёк)',
                        botUsername: 'walt_bot',
                        session: session2,
                      ),
                    );
                  },
                  child: const Text('OpenTwo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // 1. Open and minimize Mini App 1.
    await tester.tap(find.text('OpenOne'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mini_app_collapse_expand_button')));
    await tester.pumpAndSettle();

    final barFinder = find.byKey(const ValueKey('minimized_mini_app_bar'));
    expect(barFinder, findsOneWidget);
    expect(find.text('BotFather'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('minimized_mini_app_extra_count')),
      findsNothing,
    );

    // 2. Open and minimize Mini App 2 -> stacked bar displays "Walt (ранее Кошелёк) и ещё 1".
    await tester.tap(find.text('OpenTwo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mini_app_collapse_expand_button')));
    await tester.pumpAndSettle();

    expect(MiniAppSessionController.instance.minimizedCount, 2);
    expect(barFinder, findsOneWidget);
    final dockFinder =
        find.byKey(const ValueKey('minimized_mini_app_dock_region'));
    expect(dockFinder, findsOneWidget);
    expect(tester.widget(dockFinder), isA<ColoredBox>());
    expect(
      find.byKey(const ValueKey('minimized_mini_app_dock_fillets')),
      findsOneWidget,
    );
    final double screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final Rect scaffoldRect = tester.getRect(find.byType(Scaffold));
    expect(
      scaffoldRect.bottom,
      lessThanOrEqualTo(tester.getTopLeft(dockFinder).dy + 0.5),
    );
    expect(scaffoldRect.height, lessThan(screenHeight - 55.0));
    expect(find.text('Walt (ранее Кошелёк)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('minimized_mini_app_extra_count')),
      findsOneWidget,
    );
    expect(find.text(' и ещё 1'), findsOneWidget);

    // 3. Tapping minimized bar opens MiniAppTabsSwitcher instead of a single sheet.
    await tester.tap(find.byKey(const ValueKey('minimized_mini_app_expand_button')));
    await tester.pumpAndSettle();

    final switcherFinder = find.byKey(const ValueKey('mini_app_tabs_switcher'));
    expect(switcherFinder, findsOneWidget);
    expect(find.byType(MiniAppWebViewSheet), findsNothing);
    expect(
      find.byKey(const ValueKey('mini_app_close_all_tabs_button')),
      findsOneWidget,
    );
    expect(find.text('Закрыть все вкладки'), findsOneWidget);
    expect(find.text('BotFather'), findsOneWidget);
    expect(find.text('Walt (ранее Кошелёк)'), findsOneWidget);

    final switcherLensFinder = find.descendant(
      of: switcherFinder,
      matching: find.byType(LiquidGlassLens),
    );
    expect(switcherLensFinder, findsOneWidget);
    expect(
      find.ancestor(
        of: switcherLensFinder,
        matching: find.descendant(
          of: switcherFinder,
          matching: find.byWidgetPredicate(
            (w) => w is Opacity || w is FadeTransition,
          ),
        ),
      ),
      findsNothing,
    );

    // 4. Selecting BotFather restores it full-screen while keeping Walt minimized.
    await tester.tap(find.text('BotFather'));
    await tester.pumpAndSettle();

    expect(switcherFinder, findsNothing);
    expect(find.byType(MiniAppWebViewSheet), findsOneWidget);
    expect(MiniAppSessionController.instance.minimizedSessions, [session2]);

    // 5. Minimize BotFather again -> front title flips to "BotFather и ещё 1".
    await tester.tap(find.byKey(const ValueKey('mini_app_collapse_expand_button')));
    await tester.pumpAndSettle();

    expect(MiniAppSessionController.instance.minimizedCount, 2);
    expect(barFinder, findsOneWidget);
    expect(find.text('BotFather'), findsOneWidget);
    expect(find.text(' и ещё 1'), findsOneWidget);

    // 6. Reopen switcher via bar title tap and close BotFather card via X.
    await tester.tap(find.text('BotFather'));
    await tester.pumpAndSettle();
    expect(switcherFinder, findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mini_app_tab_close_tab_botfather')),
    );
    await tester.pumpAndSettle();

    expect(MiniAppSessionController.instance.minimizedSessions, [session2]);
    expect(switcherFinder, findsOneWidget);
    expect(find.text('BotFather'), findsNothing);
    expect(find.text('Walt (ранее Кошелёк)'), findsOneWidget);

    // 7. Tap "Закрыть все вкладки" -> closes remaining sessions and clears UI.
    await tester.tap(
      find.byKey(const ValueKey('mini_app_close_all_tabs_button')),
    );
    await tester.pumpAndSettle();

    expect(MiniAppSessionController.instance.minimizedCount, 0);
    expect(switcherFinder, findsNothing);
    expect(barFinder, findsNothing);
  });

  testWidgets(
      'Tapping center title pill opens switcher with real image and DOM content previews',
      (tester) async {
    addTearDown(MiniAppSessionController.instance.resetForTesting);

    // Minimal valid 1x1 PNG image payload to test native screenshot preview tier.
    final samplePng = Uint8List.fromList(const <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x00, 0x00,
      0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

    final studioSession = MiniAppSession(
      id: 'tab_studio_dom',
      launchData: const MiniAppLaunchData(
        url: 'https://api.theaver.app/api/miniapps/studio',
        initData: 'hash=studio',
        botId: '1',
        botUsername: 'BotMother',
        botDisplayName: 'BotMother',
        botIsVerified: true,
      ),
      botName: 'BotMother',
      botUsername: 'BotMother',
      isVerified: true,
    )..domPreview = const MiniAppDomPreview(
        bgColor: Color(0xFF161B22),
        textColor: Colors.white,
        accentColor: Color(0xFF2EA6FF),
        blocks: [
          MiniAppDomBlock(
            kind: 'hero',
            title: 'My Bot Studio',
            subtitle: 'Active bots & tokens',
          ),
          MiniAppDomBlock(
            kind: 'row',
            title: '@helper_bot',
            subtitle: 'Webhook OK',
            trailing: 'Active',
            leadingBadge: 'HB',
          ),
        ],
      );

    final walletSession = MiniAppSession(
      id: 'tab_wallet_img',
      launchData: const MiniAppLaunchData(
        url: 'https://api.theaver.app/api/miniapps/wallet',
        initData: 'hash=walt',
        botId: '2',
        botUsername: 'walt',
        botDisplayName: 'Walt',
        botIsVerified: true,
      ),
      botName: 'Walt',
      botUsername: 'walt',
      isVerified: true,
    )..previewImageBytes = samplePng;

    await tester.pumpWidget(
      _buildHost(
        glassMode: GlassMode.lite,
        child: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                showTheavModalSheet<void>(
                  context: context,
                  enableDrag: false,
                  useRootNavigator: true,
                  builder: (_) => const SizedBox.shrink(),
                  customSheetBuilder: (_) => MiniAppWebViewSheet(
                    launchData: studioSession.launchData,
                    botName: 'BotMother',
                    botUsername: 'BotMother',
                    isVerified: true,
                    session: studioSession,
                  ),
                );
              },
              child: const Text('LaunchStudio'),
            ),
          ),
        ),
      ),
    );

    MiniAppSessionController.instance.minimize(walletSession);
    await tester.pumpAndSettle();

    await tester.tap(find.text('LaunchStudio'));
    await tester.pumpAndSettle();

    expect(find.byType(MiniAppWebViewSheet), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('webview_header_center_pill')));
    await tester.pumpAndSettle();

    final switcherFinder = find.byKey(const ValueKey('mini_app_tabs_switcher'));
    expect(switcherFinder, findsOneWidget);
    final scrollRect = tester.getRect(
      find
          .descendant(
            of: switcherFinder,
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    expect(scrollRect.top, lessThanOrEqualTo(0.5));
    expect(
      find.byKey(const ValueKey('mini_app_tab_preview_tab_studio_dom')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mini_app_tab_preview_tab_wallet_img')),
      findsOneWidget,
    );
    final studioRect = tester.getRect(
      find.byKey(const ValueKey('mini_app_tab_card_tab_studio_dom')),
    );
    final walletPreviewRect = tester.getRect(
      find.byKey(const ValueKey('mini_app_tab_preview_tab_wallet_img')),
    );
    final studioPreviewRect = tester.getRect(
      find.byKey(const ValueKey('mini_app_tab_preview_tab_studio_dom')),
    );
    expect(walletPreviewRect.height, greaterThan(100.0));
    expect(studioPreviewRect.height, greaterThan(100.0));
    expect(studioRect.top - walletPreviewRect.top, greaterThan(100.0));
    // Live DOM snapshot renders extracted bot studio rows inside the preview card.
    expect(find.text('My Bot Studio'), findsOneWidget);
    expect(find.text('Active bots & tokens'), findsOneWidget);
    expect(find.text('@helper_bot'), findsOneWidget);
    // Native screenshot tier renders Image.memory for @walt card.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mini_app_tab_preview_tab_wallet_img')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'MiniAppTabsSwitcher dismisses on empty-area tap and applies subtle 3D gyroscope card tilt',
      (tester) async {
    final gyroController = StreamController<GyroscopeEvent>.broadcast();
    MiniAppTabsSwitcher.debugGyroscopeStreamOverride = gyroController.stream;
    addTearDown(() async {
      MiniAppTabsSwitcher.debugGyroscopeStreamOverride = null;
      MiniAppSessionController.instance.resetForTesting();
      await gyroController.close();
    });

    final session1 = MiniAppSession(
      id: 'gyro_tab_1',
      launchData: const MiniAppLaunchData(
        url: 'https://api.theaver.app/api/miniapps/studio',
        initData: 'hash=studio',
        botId: '1',
        botUsername: 'BotMother',
        botDisplayName: 'BotMother',
        botIsVerified: true,
      ),
      botName: 'BotMother',
      botUsername: 'BotMother',
      isVerified: true,
    );

    final session2 = MiniAppSession(
      id: 'gyro_tab_2',
      launchData: const MiniAppLaunchData(
        url: 'https://api.theaver.app/api/miniapps/wallet',
        initData: 'hash=walt',
        botId: '2',
        botUsername: 'walt',
        botDisplayName: 'Walt',
        botIsVerified: true,
      ),
      botName: 'Walt',
      botUsername: 'walt',
      isVerified: true,
    );

    await tester.pumpWidget(
      _buildHost(
        glassMode: GlassMode.lite,
        child: const Center(child: Text('Home')),
      ),
    );

    MiniAppSessionController.instance.minimize(session1);
    MiniAppSessionController.instance.minimize(session2);
    MiniAppSessionController.instance.openSwitcher();
    await tester.pumpAndSettle();

    final switcherFinder = find.byKey(const ValueKey('mini_app_tabs_switcher'));
    expect(switcherFinder, findsOneWidget);

    final transformFinder = find.byKey(const ValueKey('mini_app_tab_transform_gyro_tab_2'));
    expect(transformFinder, findsOneWidget);
    final Matrix4 restingMatrix =
        Matrix4.copy(tester.widget<Transform>(transformFinder).transform);

    // Emit gyroscope impulse and advance a few frames -> card tilts subtly in 3D.
    gyroController.add(GyroscopeEvent(0.9, -1.1, 0.0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 64));

    final Matrix4 tiltedMatrix =
        tester.widget<Transform>(transformFinder).transform;
    expect(tiltedMatrix, isNot(equals(restingMatrix)));
    final translation = tiltedMatrix.getTranslation();
    expect(translation.x.isFinite && translation.y.isFinite, isTrue);
    expect(translation.x, lessThan(0.0));
    expect(translation.y, lessThan(0.0));
    expect(translation.x.abs(), lessThan(3.0));
    expect(translation.y.abs(), lessThan(3.0));

    // Gyro ticker decays back to resting orientation and stops cleanly without hanging pumpAndSettle.
    await tester.pumpAndSettle();
    final Matrix4 settledMatrix =
        tester.widget<Transform>(transformFinder).transform;
    expect(settledMatrix, equals(restingMatrix));

    // Tapping empty space beside "Закрыть все вкладки" collapses switcher back to minimized dock bar.
    await tester.tapAt(const Offset(24, 28));
    await tester.pumpAndSettle();
    expect(switcherFinder, findsNothing);
    expect(MiniAppSessionController.instance.minimizedCount, 2);
    expect(find.byKey(const ValueKey('minimized_mini_app_bar')), findsOneWidget);

    // Re-open with a single card and tap empty area below the card -> dismisses cleanly.
    MiniAppSessionController.instance.closeSession(session1);
    MiniAppSessionController.instance.openSwitcher();
    await tester.pumpAndSettle();
    expect(switcherFinder, findsOneWidget);

    await tester.tapAt(const Offset(400, 580));
    await tester.pumpAndSettle();
    expect(switcherFinder, findsNothing);
    expect(MiniAppSessionController.instance.minimizedCount, 1);
  });

  testWidgets(
      'MiniAppTabsSwitcher closes on native system back without popping underlying route and keeps gyro active during scroll',
      (tester) async {
    final gyroController = StreamController<GyroscopeEvent>.broadcast();
    MiniAppTabsSwitcher.debugGyroscopeStreamOverride = gyroController.stream;
    MiniAppSessionController.instance.ensureInitialized();
    addTearDown(() async {
      MiniAppTabsSwitcher.debugGyroscopeStreamOverride = null;
      MiniAppSessionController.instance.resetForTesting();
      await gyroController.close();
    });

    await tester.pumpWidget(
      _buildHost(
        glassMode: GlassMode.lite,
        child: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('Chat Screen')),
                    ),
                  ),
                );
              },
              child: const Text('OpenChat'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('OpenChat'));
    await tester.pumpAndSettle();
    expect(find.text('Chat Screen'), findsOneWidget);

    for (int i = 0; i < 6; i++) {
      final session = MiniAppSession(
        id: 'back_tab_$i',
        launchData: MiniAppLaunchData(
          url: 'https://api.theaver.app/api/miniapps/studio?tab=$i',
          initData: 'hash=$i',
          botId: 'bot_$i',
          botUsername: 'bot_$i',
          botDisplayName: 'Mini App $i',
        ),
        botName: 'Mini App $i',
        botUsername: 'bot_$i',
      );
      MiniAppSessionController.instance.minimize(session);
    }
    MiniAppSessionController.instance.openSwitcher();
    await tester.pumpAndSettle();

    final switcherFinder = find.byKey(const ValueKey('mini_app_tabs_switcher'));
    expect(switcherFinder, findsOneWidget);

    final scrollFinder = find
        .descendant(
          of: switcherFinder,
          matching: find.byType(SingleChildScrollView),
        )
        .first;

    // Scroll vertically and emit gyro events mid-scroll -> gyroscope keeps tilting smoothly while scrolling.
    final lastCardTransformFinder =
        find.byKey(const ValueKey('mini_app_tab_transform_back_tab_5'));
    await tester.drag(scrollFinder, const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(lastCardTransformFinder, findsOneWidget);

    final Matrix4 restingAfterScroll = Matrix4.copy(
      tester.widget<Transform>(lastCardTransformFinder).transform,
    );
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    gyroController.add(GyroscopeEvent(1.2, -1.2, 0.0));
    await tester.pump(const Duration(milliseconds: 32));
    expect(
      tester.widget<Transform>(lastCardTransformFinder).transform,
      isNot(equals(restingAfterScroll)),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    // First system Back closes MiniAppTabsSwitcher without popping 'Chat Screen'.
    final bool handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(switcherFinder, findsNothing);
    expect(find.text('Chat Screen'), findsOneWidget);
    expect(MiniAppSessionController.instance.minimizedCount, 6);

    // Second system Back pops 'Chat Screen' back to home route.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Chat Screen'), findsNothing);
    expect(find.text('OpenChat'), findsOneWidget);
  });

  testWidgets(
      'MinimizedMiniAppHost keeps minimized bar rendered beneath soft keyboard without jump on open/close',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => MiniAppSessionController.instance.resetForTesting());

    EdgeInsets mqViewInsets = EdgeInsets.zero;
    EdgeInsets mqPadding = const EdgeInsets.only(bottom: 24);
    late StateSetter outerSetState;
    double? lastInnerViewInsetsBottom;

    final session = MiniAppSession(
      id: 'kb_dock_session',
      launchData: const MiniAppLaunchData(
        url: 'https://api.theaver.app/api/miniapps/studio',
        initData: 'hash=kb',
        botId: 'bot_kb',
        botUsername: 'studio_bot',
        botDisplayName: 'Studio',
      ),
      botName: 'Studio',
      botUsername: 'studio_bot',
    );

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          outerSetState = setState;
          return MediaQuery(
            data: MediaQueryData(
              size: const Size(400, 800),
              padding: mqPadding,
              viewPadding: const EdgeInsets.only(bottom: 24),
              viewInsets: mqViewInsets,
            ),
            child: ChangeNotifierProvider<LiquidGlassProvider>.value(
              value: _TestLiquidGlassProvider(GlassMode.lite),
              child: MaterialApp(
                theme: ThemeData.dark(useMaterial3: true),
                builder: (context, appChild) => MinimizedMiniAppHost(
                  child: appChild ?? const SizedBox.shrink(),
                ),
                home: Builder(
                  builder: (innerCtx) {
                    lastInnerViewInsetsBottom =
                        MediaQuery.viewInsetsOf(innerCtx).bottom;
                    return Scaffold(
                      body: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.viewInsetsOf(innerCtx).bottom,
                          ),
                          child: const SizedBox(
                            key: ValueKey('chat_composer_box'),
                            height: 48,
                            child: Text('Composer'),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    MiniAppSessionController.instance.minimize(session);
    await tester.pumpAndSettle();

    final barFinder = find.byKey(const ValueKey('minimized_mini_app_bar'));
    final dockFinder =
        find.byKey(const ValueKey('minimized_mini_app_dock_region'));
    expect(barFinder, findsOneWidget);
    expect(dockFinder, findsOneWidget);

    final double initialDockHeight = tester.getSize(dockFinder).height;
    final double initialScaffoldHeight =
        tester.getSize(find.byType(Scaffold)).height;
    expect(initialDockHeight, closeTo(82.0, 1.0));
    expect(lastInnerViewInsetsBottom, closeTo(0.0, 0.01));

    void updateKeyboard(double imeBottom) {
      outerSetState(() {
        mqViewInsets = EdgeInsets.only(bottom: imeBottom);
        mqPadding = EdgeInsets.only(
          bottom: (24.0 - imeBottom).clamp(0.0, 24.0),
        );
      });
    }

    // Opening keyboard in stages (24 -> 72 -> 300): dock remains mounted and
    // keeps constant height while IME rises smoothly over it.
    for (final double ime in const <double>[24.0, 72.0]) {
      updateKeyboard(ime);
      await tester.pump();
      expect(barFinder, findsOneWidget);
      expect(dockFinder, findsOneWidget);
      expect(tester.getSize(dockFinder).height,
          closeTo(initialDockHeight, 0.5));
      expect(tester.getSize(find.byType(Scaffold)).height,
          closeTo(initialScaffoldHeight, 0.5));
      expect(lastInnerViewInsetsBottom, closeTo(0.0, 0.01));
    }

    updateKeyboard(300.0);
    await tester.pump();
    expect(barFinder, findsOneWidget);
    expect(dockFinder, findsOneWidget);
    expect(
      lastInnerViewInsetsBottom,
      closeTo(300.0 - initialDockHeight, 0.5),
    );
    // Taps through IME zone are ignored while full keyboard covers dock.
    expect(
      tester
          .widget<IgnorePointer>(
            find.ancestor(
              of: dockFinder,
              matching: find.byType(IgnorePointer),
            ).first,
          )
          .ignoring,
      isTrue,
    );

    // Closing keyboard (72 -> 16 -> 0): zero height jump at 16 -> 0 boundary.
    updateKeyboard(72.0);
    await tester.pump();
    expect(barFinder, findsOneWidget);
    final double scaffoldHeightAt72 =
        tester.getSize(find.byType(Scaffold)).height;

    updateKeyboard(16.0);
    await tester.pump();
    expect(barFinder, findsOneWidget);
    final double scaffoldHeightAt16 =
        tester.getSize(find.byType(Scaffold)).height;

    updateKeyboard(0.0);
    await tester.pump();
    expect(barFinder, findsOneWidget);
    final double scaffoldHeightAt0 =
        tester.getSize(find.byType(Scaffold)).height;

    expect((scaffoldHeightAt72 - initialScaffoldHeight).abs(), lessThan(0.5));
    expect((scaffoldHeightAt16 - scaffoldHeightAt0).abs(), lessThan(0.5));
    expect(tester.getSize(dockFinder).height, closeTo(initialDockHeight, 0.5));
    expect(lastInnerViewInsetsBottom, closeTo(0.0, 0.01));
  });

  for (final mode in const <GlassMode>[GlassMode.full, GlassMode.lite]) {
    testWidgets(
      'TheavFloatingSurface shrink-wraps under loose constraints in $mode',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _buildHost(
            glassMode: mode,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: const TheavFloatingSurface(
                  key: ValueKey('loose_floating_surface'),
                  borderRadius: 24,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Ссылка скопирована'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surfaceFinder = find.byKey(const ValueKey('loose_floating_surface'));
        final lensFinder = find.descendant(
          of: surfaceFinder,
          matching: find.byType(LiquidGlassLens),
        );
        expect(lensFinder, findsOneWidget);

        final Size lensSize = tester.getSize(lensFinder);
        expect(lensSize.height, lessThan(80.0));
        expect(lensSize.height, greaterThan(20.0));
        expect(lensSize.width, lessThan(320.0));
        expect(lensSize.width, greaterThan(80.0));
      },
    );
  }

  for (final mode in const <GlassMode>[
    GlassMode.full,
    GlassMode.lite,
    GlassMode.disabled,
  ]) {
    testWidgets(
      'GlassToastService displays compact pill, passes outside taps, and animates close on timer & swipe in $mode',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(GlassToastService().hide);

        late BuildContext hostContext;
        int backgroundTaps = 0;

        await tester.pumpWidget(
          _buildHost(
            glassMode: mode,
            child: Builder(
              builder: (ctx) {
                hostContext = ctx;
                return Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: ElevatedButton(
                      key: const ValueKey('toast_bg_action_btn'),
                      onPressed: () => backgroundTaps++,
                      child: const Text('Background Action'),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Auto-timer dismissal check + compact bounds + zero Fade/Opacity above glass.
        GlassToastService().show(
          hostContext,
          'Ссылка скопирована',
          duration: const Duration(seconds: 3),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpAndSettle(const Duration(milliseconds: 16));

        final overlayFinder = find.byKey(const ValueKey('glass_toast_overlay'));
        final pillFinder = find.byKey(const ValueKey('glass_toast_pill'));
        expect(overlayFinder, findsOneWidget);
        expect(pillFinder, findsOneWidget);
        expect(find.text('Ссылка скопирована'), findsOneWidget);

        final Size pillSize = tester.getSize(pillFinder);
        expect(pillSize.height, lessThan(80.0));
        expect(pillSize.width, lessThan(320.0));

        if (mode != GlassMode.disabled) {
          final morphFinder = find.descendant(
            of: overlayFinder,
            matching: find.byType(LiquidGlassMorph),
          );
          expect(morphFinder, findsOneWidget);
          expect(
            find.ancestor(
              of: morphFinder,
              matching: find.descendant(
                of: overlayFinder,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is FadeTransition ||
                      (w is Opacity && w.opacity > 0.0 && w.opacity < 1.0),
                ),
              ),
            ),
            findsNothing,
          );
          final lensFinder = find.descendant(
            of: morphFinder,
            matching: find.byType(LiquidGlassLens),
          );
          expect(lensFinder, findsWidgets);
          expect(
            find.ancestor(
              of: lensFinder.first,
              matching: find.descendant(
                of: overlayFinder,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is FadeTransition ||
                      (w is Opacity && w.opacity > 0.0 && w.opacity < 1.0),
                ),
              ),
            ),
            findsNothing,
          );
        }

        // Outside taps must still pass straight through to the page below.
        await tester.tap(find.byKey(const ValueKey('toast_bg_action_btn')));
        await tester.pump();
        expect(backgroundTaps, equals(1));

        // Let the 3s timer trigger dismissal; mid-exit must remain animating,
        // then vanish cleanly after pumpAndSettle().
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 60));
        expect(overlayFinder, findsOneWidget);
        await tester.pumpAndSettle(const Duration(milliseconds: 16));
        expect(overlayFinder, findsNothing);
        expect(pillFinder, findsNothing);

        // 2. Swipe-down gesture dismisses smoothly.
        GlassToastService().show(
          hostContext,
          'Свайп вниз',
          duration: const Duration(seconds: 5),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpAndSettle(const Duration(milliseconds: 16));
        expect(find.text('Свайп вниз'), findsOneWidget);

        await tester.drag(pillFinder, const Offset(0, 68));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle(const Duration(milliseconds: 16));
        expect(pillFinder, findsNothing);
        expect(find.text('Свайп вниз'), findsNothing);
      },
    );
  }
}
