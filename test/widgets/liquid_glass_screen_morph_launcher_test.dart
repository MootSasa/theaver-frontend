import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/widgets/chat/liquid_glass_screen_morph_launcher.dart';
import 'package:theaver/widgets/chat/floating_glass_app_bar.dart';

class _TestAppLocalizations extends AppLocalizations {
  final Map<String, String> translations;
  _TestAppLocalizations(Locale locale, this.translations) : super(locale);

  @override
  String translate(String key) => translations[key] ?? key;
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

final Map<String, String> _kTranslations = {
  'chat_menu_profile': 'Профиль',
  'chat_menu_search_messages': 'Поиск',
  'chat_menu_mute': 'Без звука',
  'chat_menu_unmute': 'Включить звук',
  'chat_menu_clear_history': 'Очистить историю',
  'chat_menu_report': 'Пожаловаться',
};

Widget _wrapWithApp(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LiquidGlassProvider()),
    ],
    child: MaterialApp(
      localizationsDelegates: [
        _TestAppLocalizationsDelegate(_kTranslations),
      ],
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LiquidGlassScreenMorphLauncher Widget Tests', () {
    testWidgets('Renders collapsed child at rest', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          LiquidGlassScreenMorphLauncher(
            style: const LiquidGlassStyle(),
            destinationBuilder: (_) => const Scaffold(body: Text('Profile Screen')),
            child: const Text('Center Pill Header'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Center Pill Header'), findsOneWidget);
      expect(find.text('Profile Screen'), findsNothing);
    });

    testWidgets('Tapping when enabled: false pushes destination directly', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          LiquidGlassScreenMorphLauncher(
            enabled: false,
            style: const LiquidGlassStyle(),
            destinationBuilder: (_) => const Scaffold(body: Text('Profile Screen Target')),
            child: const Text('Tap Me'),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Tap Me'));
      await tester.pumpAndSettle();

      expect(find.text('Profile Screen Target'), findsOneWidget);
    });

    testWidgets('Tapping when enabled: true shows overlay and transitions to destination', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          Center(
            child: SizedBox(
              width: 200,
              height: 44,
              child: LiquidGlassScreenMorphLauncher(
                enabled: true,
                style: const LiquidGlassStyle(),
                destinationBuilder: (_) => const Scaffold(
                  body: Text('HandOff Destination Screen'),
                ),
                child: const Text('Collapsed Header Content'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Collapsed Header Content'), findsOneWidget);
      expect(find.text('HandOff Destination Screen'), findsNothing);

      // Tap to start morph
      await tester.tap(find.text('Collapsed Header Content'));
      await tester.pump(); // Frame 0: overlay is shown

      // Post-frame callback triggers expansion
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(LiquidGlassMorph), findsOneWidget);

      // Settle spring physics and hand-off
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.text('HandOff Destination Screen'), findsOneWidget);
    });

    testWidgets('FloatingGlassAppBar integrates profileScreenBuilder cleanly', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          FloatingGlassAppBar(
            name: 'Pavel Durov',
            isOnline: true,
            onBack: () {},
            onTitleTap: () {},
            profileScreenBuilder: (context) => const Scaffold(
              body: Text('Durov Profile Screen'),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Pavel Durov'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('chat_appbar_center_pill')), findsOneWidget);
    });

    testWidgets('Tapping center pill in FloatingGlassAppBar navigates to profile screen', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          FloatingGlassAppBar(
            name: 'Pavel Durov',
            isOnline: true,
            onBack: () {},
            onTitleTap: () {},
            profileScreenBuilder: (context) => const Scaffold(
              body: Text('Durov Profile Screen Target'),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Pavel Durov'), findsOneWidget);
      expect(find.text('Durov Profile Screen Target'), findsNothing);

      // Tap center pill (which previously was swallowed by inner GestureDetector)
      await tester.tap(find.text('Pavel Durov'));
      await tester.pumpAndSettle();

      expect(find.text('Durov Profile Screen Target'), findsOneWidget);
    });
  });
}
