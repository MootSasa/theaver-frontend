import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/widgets/design_system/theav_design_system.dart';

class _TestLiquidGlassProvider extends LiquidGlassProvider {
  _TestLiquidGlassProvider(this._mode);

  final GlassMode _mode;

  @override
  GlassMode get mode => _mode;

  @override
  bool get enabled => _mode != GlassMode.disabled;
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
    });
  }
}
