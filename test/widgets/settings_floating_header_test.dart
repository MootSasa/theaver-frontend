import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/widgets/settings/settings_floating_header.dart';

void main() {
  Widget buildHeaderHost({
    required double width,
    required String title,
    List<SettingsHeaderAction> actions = const [],
  }) {
    return ChangeNotifierProvider(
      create: (_) => LiquidGlassProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                padding: const EdgeInsets.only(top: 24),
              ),
              child: SizedBox(
                width: width,
                height: 800,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SettingsFloatingHeader(
                    title: title,
                    onBack: () {},
                    actions: actions,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('SettingsFloatingHeader Widget Tests', () {
    testWidgets(
      'renders 44x44 back circle and hugging centered title capsule >= 120px',
      (tester) async {
        await tester.pumpWidget(
          buildHeaderHost(width: 400, title: 'Chat'),
        );
        await tester.pumpAndSettle();

        final circleButtons = find.byType(SettingsFloatingCircleButton);
        expect(circleButtons, findsOneWidget);
        expect(tester.getSize(circleButtons.first), equals(const Size(44, 44)));
        expect(find.byType(iconoir.NavArrowLeft), findsOneWidget);
        expect(find.byType(Icon), findsNothing);

        final surfaces = find.byType(SettingsFloatingSurface);
        expect(surfaces, findsNWidgets(2));

        final backRect = tester.getRect(surfaces.at(0));
        final titleRect = tester.getRect(surfaces.at(1));
        expect(titleRect.height, equals(44));
        expect(titleRect.width, greaterThanOrEqualTo(120));
        // Hugs title rather than stretching across entire remaining width
        expect(titleRect.width, lessThan(200));
        expect(titleRect.center.dx, closeTo(200, 1.0));
        expect(titleRect.left, greaterThanOrEqualTo(backRect.right));
      },
    );

    testWidgets('renders 1 action as a 44x44 circle', (tester) async {
      await tester.pumpWidget(
        buildHeaderHost(
          width: 400,
          title: 'Devices',
          actions: [
            SettingsHeaderAction(
              icon: const iconoir.RefreshDouble(
                key: Key('single_action'),
                width: 20,
                height: 20,
                color: Colors.black,
              ),
              onTap: () {},
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final circles = find.byType(SettingsFloatingCircleButton);
      expect(circles, findsNWidgets(2));
      expect(tester.getSize(circles.at(0)), equals(const Size(44, 44)));
      expect(tester.getSize(circles.at(1)), equals(const Size(44, 44)));
      expect(find.byKey(const Key('single_action')), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('renders 2 actions inside an 88x44 stadium capsule',
        (tester) async {
      await tester.pumpWidget(
        buildHeaderHost(
          width: 400,
          title: 'Theme',
          actions: [
            SettingsHeaderAction(
              icon: const iconoir.Download(
                key: Key('action_1'),
                width: 20,
                height: 20,
                color: Colors.black,
              ),
              onTap: () {},
            ),
            SettingsHeaderAction(
              icon: const iconoir.ShareAndroid(
                key: Key('action_2'),
                width: 20,
                height: 20,
                color: Colors.black,
              ),
              onTap: () {},
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Back circle only; 2 actions share the stadium capsule.
      expect(find.byType(SettingsFloatingCircleButton), findsOneWidget);

      final actionSurface = find.ancestor(
        of: find.byKey(const Key('action_1')),
        matching: find.byType(SettingsFloatingSurface),
      );
      expect(actionSurface, findsOneWidget);
      final capsuleSize = tester.getSize(actionSurface);
      expect(capsuleSize.height, equals(44));
      expect(capsuleSize.width, closeTo(88, 1.0));
      expect(find.byKey(const Key('action_2')), findsOneWidget);
    });

    testWidgets('clamps long title without overlapping at 320px and 800px',
        (tester) async {
      for (final width in [320.0, 800.0]) {
        await tester.pumpWidget(
          buildHeaderHost(
            width: width,
            title: 'Очень длинный заголовок экрана настроек уведомлений',
            actions: [
              SettingsHeaderAction(
                icon: const iconoir.Download(
                  width: 20,
                  height: 20,
                  color: Colors.black,
                ),
                onTap: () {},
              ),
              SettingsHeaderAction(
                icon: const iconoir.ShareAndroid(
                  width: 20,
                  height: 20,
                  color: Colors.black,
                ),
                onTap: () {},
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final surfaces = find.byType(SettingsFloatingSurface);
        expect(surfaces, findsNWidgets(3));

        final leftRect = tester.getRect(surfaces.at(0));
        final titleRect = tester.getRect(surfaces.at(1));
        final rightRect = tester.getRect(surfaces.at(2));

        expect(titleRect.left, greaterThanOrEqualTo(leftRect.right));
        expect(rightRect.left, greaterThanOrEqualTo(titleRect.right));
        expect(tester.takeException(), isNull);
      }
    });
  });
}
