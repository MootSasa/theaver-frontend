import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/screens/settings/widgets/update_dialog.dart';
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
    return SynchronousFuture<AppLocalizations>(
      _TestAppLocalizations(locale, strings),
    );
  }

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> ruStrings;
  String? copiedClipboardText;

  setUpAll(() {
    final raw = File('assets/l10n/ru.json').readAsStringSync();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    ruStrings = decoded.map((k, v) => MapEntry(k, v.toString()));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppUpdateService.instance.resetForTesting();
    GlassToastService().hide();
    copiedClipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        copiedClipboardText = args?['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    GlassToastService().hide();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  AppUpdateInfo buildSampleUpdate({
    bool forceUpdate = false,
    String sha256 = 'deadbeefdeadbeefdeadbeef',
  }) {
    return AppUpdateInfo(
      hasUpdate: true,
      latestVersion: '1.25.0',
      latestBuild: 1250,
      minSupportedBuild: 100,
      forceUpdate: forceUpdate,
      channel: 'beta',
      architecture: 'arm64-v8a',
      downloadUrl: 'https://storage.theaver.app/releases/theaver-1.25.0.apk',
      apkSizeBytes: 10485760,
      sha256: sha256,
      releaseNotes: '### Исправления\n- Стабильность уведомлений\n- Быстрее запуск',
    );
  }

  Widget wrapSheetApp(Widget child) {
    return MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: [
        _TestAppLocalizationsDelegate(ruStrings),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );
  }

  group('UpdateDialog Widget Tests', () {
    testWidgets(
      'renders SettingsAttachedSheet, Markdown notes, SHA-256 copy, and Iconoir icons without Material Icons',
      (tester) async {
        final update = buildSampleUpdate(forceUpdate: false);

        await tester.pumpWidget(
          wrapSheetApp(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => UpdateDialog.show(context, update),
                child: const Text('Open Update'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Update'));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsAttachedSheet), findsOneWidget);
        expect(find.text('Доступно обновление'), findsOneWidget);
        expect(find.text('Theaver 1.25.0 (#1250)'), findsOneWidget);
        expect(find.text('Стабильность уведомлений'), findsOneWidget);
        expect(find.text('BETA'), findsOneWidget);
        expect(find.text('10.0 MB'), findsOneWidget);
        expect(find.text('SHA deadbeef'), findsOneWidget);
        expect(find.text('Скачать и установить'), findsOneWidget);
        expect(find.text('Напомнить позже'), findsOneWidget);
        expect(find.text('Пропустить сборку'), findsOneWidget);
        expect(find.byType(iconoir.Xmark), findsOneWidget);
        expect(find.byType(Icon), findsNothing);

        await tester.tap(find.text('SHA deadbeef'));
        await tester.pump();
        expect(copiedClipboardText, equals('deadbeefdeadbeefdeadbeef'));

        GlassToastService().hide();
        await tester.pump();
      },
    );

    testWidgets('hides dismiss, snooze, and skip controls when forceUpdate is true',
        (tester) async {
      final forcedUpdate = buildSampleUpdate(forceUpdate: true);

      await tester.pumpWidget(
        wrapSheetApp(
          Align(
            alignment: Alignment.bottomCenter,
            child: UpdateDialog(update: forcedUpdate),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SettingsAttachedSheet), findsOneWidget);
      expect(find.text('Обязательное обновление'), findsOneWidget);
      expect(find.text('Скачать и установить'), findsOneWidget);
      expect(find.text('Напомнить позже'), findsNothing);
      expect(find.text('Пропустить сборку'), findsNothing);
      expect(find.byType(iconoir.Xmark), findsNothing);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets(
      'reacts to AppUpdateService downloading and readyToInstall states',
      (tester) async {
        final update = buildSampleUpdate();

        await tester.pumpWidget(
          wrapSheetApp(
            Align(
              alignment: Alignment.bottomCenter,
              child: UpdateDialog(update: update),
            ),
          ),
        );
        await tester.pumpAndSettle();

        AppUpdateService.instance.stateNotifier.value = AppUpdateDownloadState(
          status: AppUpdateStatus.downloading,
          availableUpdate: update,
          progress: 0.45,
          downloadedBytes: 4718592,
          totalBytes: 10485760,
          speedBytesPerSec: 1048576,
        );
        await tester.pump();

        expect(find.text('45%'), findsOneWidget);
        expect(find.text('4.5 / 10.0 MB • 1.0 MB/s'), findsOneWidget);
        expect(find.byType(Icon), findsNothing);

        AppUpdateService.instance.stateNotifier.value = AppUpdateDownloadState(
          status: AppUpdateStatus.readyToInstall,
          availableUpdate: update,
          downloadedFilePath: '/tmp/theaver-1.25.0.apk',
          progress: 1.0,
        );
        await tester.pump();

        expect(find.text('Установить'), findsOneWidget);
        expect(find.byType(Icon), findsNothing);
      },
    );
  });
}
