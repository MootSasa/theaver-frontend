import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:theaver/models/theav_theme.dart';
import 'package:theaver/services/bot_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/mini_app_js_bridge.dart';
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

        await tester.tap(find.text('Частный'));
        await tester.pumpAndSettle();
        expect(selectedSegment, 'b');

        final expectGlassControls =
            mode == GlassMode.lite || mode == GlassMode.full;
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
          'MiniAppWebViewSheet matches Telegram full-screen chrome and applies LiquidGlassLens only on overflow menu',
          (tester) async {
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
              builder: (context) => Center(
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
        );

        await tester.tap(find.text('OpenMiniApp'));
        await tester.pumpAndSettle();

        final sheetFinder = find.byType(MiniAppWebViewSheet);
        expect(sheetFinder, findsOneWidget);

        final double screenHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
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

        // Resting state must not wrap the Mini App viewport in glass shaders or blur.
        expect(
          find.descendant(
            of: sheetFinder,
            matching: find.byType(TheavSheetSurface),
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
        expect(
          find.descendant(
            of: sheetFinder,
            matching: find.byType(LiquidGlassLens),
          ),
          findsNothing,
        );

        // Opening overflow menu surfaces targeted LiquidGlassLens when glass is enabled.
        await tester.tap(
          find.byKey(const ValueKey('mini_app_more_menu_button')),
        );
        await tester.pumpAndSettle();

        final menuFinder = find.byKey(const ValueKey('mini_app_overflow_menu'));
        expect(menuFinder, findsOneWidget);

        final menuLensFinder = find.descendant(
          of: sheetFinder,
          matching: find.byType(LiquidGlassLens),
        );
        if (expectGlass) {
          expect(menuLensFinder, findsOneWidget);
          expect(
            find.ancestor(
              of: menuLensFinder,
              matching: find.descendant(
                of: sheetFinder,
                matching: find.byWidgetPredicate(
                  (w) => w is Opacity || w is FadeTransition,
                ),
              ),
            ),
            findsNothing,
          );
        } else {
          expect(menuLensFinder, findsNothing);
        }

        // Dismiss overflow menu before toggling collapse/expand height.
        await tester.tapAt(tester.getCenter(sheetFinder));
        await tester.pumpAndSettle();
        expect(menuFinder, findsNothing);

        await tester.tap(
          find.byKey(const ValueKey('mini_app_collapse_expand_button')),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(sheetFinder).height,
          lessThan(screenHeight * 0.85),
        );

        await tester.tap(
          find.byKey(const ValueKey('mini_app_collapse_expand_button')),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(sheetFinder).height,
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
        .widgetList<Container>(
          find.descendant(
            of: find.byType(MiniAppWebViewSheet),
            matching: find.byType(Container),
          ),
        )
        .where((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.color == const Color(0xFF4A1B59);
    });
    expect(headerDecorated, isNotEmpty);
  });
}
