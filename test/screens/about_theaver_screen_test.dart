import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/config/app_config.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/screens/settings/about_theaver_screen.dart';
import 'package:theaver/services/glass_toast_service.dart';
import 'package:theaver/services/update_service.dart';
import 'package:theaver/widgets/settings/settings_floating_header.dart';

class _TestAppLocalizations extends AppLocalizations {
  final Map<String, String> _strings;

  _TestAppLocalizations(super.locale, this._strings);

  @override
  String translate(String key, [Map<String, String>? params]) {
    var str = _strings[key] ?? key;
    if (params != null) {
      params.forEach((paramKey, paramValue) {
        str = str.replaceAll('{$paramKey}', paramValue);
      });
    }
    return str;
  }
}

class _TestAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  final Map<String, String> strings;

  const _TestAppLocalizationsDelegate(this.strings);

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<_AppLocalizationsCompat>(
      _AppLocalizationsCompat(locale, strings),
    );
  }

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

typedef _AppLocalizationsCompat = _TestAppLocalizations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> ruStrings;

  setUpAll(() {
    final raw = File('assets/l10n/ru.json').readAsStringSync();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    ruStrings = decoded.map((k, v) => MapEntry(k, v.toString()));
  });

  Widget buildTestableScreen() {
    return MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: [
        _TestAppLocalizationsDelegate(ruStrings),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AboutTheaverScreen(),
    );
  }

  group('AboutTheaverScreen Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AppUpdateService.instance.resetForTesting();
      GlassToastService().hide();
    });

    tearDown(() {
      GlassToastService().hide();
    });

    testWidgets(
      'renders floating pill header, Iconoir icons, sections, and unlocks Debug // W.I.P after 5 taps',
      (tester) async {
        await tester.pumpWidget(buildTestableScreen());
        await tester.pumpAndSettle();

        expect(find.byType(SettingsFloatingHeader), findsOneWidget);
        expect(find.byType(SettingsFloatingCircleButton), findsOneWidget);
        expect(find.byType(iconoir.NavArrowLeft), findsOneWidget);
        expect(find.byType(Icon), findsNothing);

        final versionHeaderText =
            'Theaver ${AppConfig.currentVersion} (${AppConfig.currentBuildNumber})';

        expect(find.text(versionHeaderText), findsOneWidget);
        expect(find.text('Обновления'), findsOneWidget);
        expect(find.text('Новости и обновления'), findsOneWidget);
        expect(find.text('Бета-версии'), findsOneWidget);
        expect(find.text('Основной чат'), findsOneWidget);
        expect(find.text('Чат обсуждений'), findsOneWidget);
        expect(find.text('Исходный код'), findsOneWidget);
        expect(
          find.text('commit ${AppConfig.shortGitCommit}'),
          findsOneWidget,
        );
        expect(find.text('Политика конфиденциальности'), findsOneWidget);

        // Hidden by default
        expect(find.text('Debug // W.I.P'), findsNothing);

        // 5 quick taps on the version header unlock Debug // W.I.P
        for (int i = 0; i < 5; i++) {
          await tester.tap(find.text(versionHeaderText));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();

        expect(find.text('Debug // W.I.P'), findsOneWidget);
        expect(find.byType(Icon), findsNothing);

        GlassToastService().hide();
        await tester.pump();

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getBool(AboutTheaverScreen.debugMenuUnlockedKey),
          isTrue,
        );
      },
    );

    testWidgets(
      'opens Update Settings attached sheet and selects update channel without Material Icons',
      (tester) async {
        await tester.pumpWidget(buildTestableScreen());
        await tester.pumpAndSettle();

        final settingsTooltip = ruStrings['about_update_settings']!;
        await tester.tap(find.byTooltip(settingsTooltip));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsAttachedSheet), findsOneWidget);
        expect(find.text(settingsTooltip), findsOneWidget);
        expect(find.text('Stable'), findsOneWidget);
        expect(find.text('Beta'), findsOneWidget);
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.byType(Icon), findsNothing);

        await tester.ensureVisible(find.text('Stable'));
        await tester.tap(find.text('Stable'));
        await tester.pumpAndSettle();

        expect(await AppUpdateService.instance.getChannel(), equals('stable'));
      },
    );
  });
}
