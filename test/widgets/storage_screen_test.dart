import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/screens/settings/storage_screen.dart';
import 'package:theaver/services/cache_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/l10n/app_localizations.dart';

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
  Future<AppLocalizations> load(Locale locale) async {
    return _TestAppLocalizations(locale, translations);
  }

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

final Map<String, String> _kStorageTranslations = {
  'storage_title': 'Данные и хранилище',
  'storage_device_cache': 'Память устройства',
  'storage_device_cache_desc': 'Временные медиафайлы, сохранённые на вашем устройстве',
  'storage_clear_cache': 'Очистить кэш',
  'storage_clear_cache_title': 'Очистить кэш',
  'storage_photos': 'Фотографии',
  'storage_videos': 'Видеозаписи',
  'storage_audio': 'Аудио / Голосовые',
  'storage_files': 'Файлы / Документы',
  'storage_other': 'Прочее',
  'storage_cloud_note': 'Все медиафайлы останутся в облаке Theaver и при необходимости загрузятся снова.',
  'storage_keep_media_section': 'Хранить медиа',
  'storage_keep_media_desc': 'Файлы, к которым вы не обращались, будут удалены с устройства.',
  'storage_keep_3days': '3 дня',
  'storage_keep_1week': '1 неделя',
  'storage_keep_1month': '1 месяц',
  'storage_keep_forever': 'Всегда',
  'storage_max_cache_size': 'Максимальный размер кэша',
  'storage_max_cache_size_desc': 'При превышении лимита самые старые файлы будут удалены.',
  'storage_no_limit': 'Без ограничений',
  'storage_auto_download': 'Автозагрузка медиа',
  'storage_on_wifi': 'Через Wi-Fi',
  'storage_on_cellular': 'Через мобильную сеть',
  'storage_on_roaming': 'В роуминге',
  'storage_additional_section': 'Дополнительно',
  'storage_compress_images': 'Сжимать изображения',
  'storage_compress_images_desc': 'Уменьшать качество фото перед отправкой',
  'storage_auto_download_stickers': 'Автозагрузка стикеров',
  'storage_suggest_stickers': 'Подсказывать стикеры',
  'storage_suggest_emoji': 'Подсказывать эмодзи',
  'storage_download_path': 'Путь сохранения',
  'storage_download_path_default': 'По умолчанию (Загрузки)',
  'storage_select_all': 'Выбрать все',
  'storage_deselect_all': 'Снять все',
  'storage_clear': 'Очистить',
  'storage_cancel': 'Отмена',
  'storage_files_count': 'файлов',
  'storage_cache_cleared': 'Кэш успешно очищен',
};

Widget createStorageScreenTestWidget({
  required LiquidGlassProvider glassProvider,
}) {
  const sampleBreakdown = CacheBreakdown(
    totalBytes: 157286400, // 150 MB
    photos: CacheCategoryInfo(key: 'photos', sizeBytes: 52428800, fileCount: 120),
    videos: CacheCategoryInfo(key: 'videos', sizeBytes: 73400320, fileCount: 15),
    audio: CacheCategoryInfo(key: 'audio', sizeBytes: 15728640, fileCount: 40),
    files: CacheCategoryInfo(key: 'files', sizeBytes: 10485760, fileCount: 5),
    other: CacheCategoryInfo(key: 'other', sizeBytes: 5242880, fileCount: 2),
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LiquidGlassProvider>.value(value: glassProvider),
    ],
    child: MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: [
        _TestAppLocalizationsDelegate(_kStorageTranslations),
      ],
      home: const StorageScreen(
        skipNetworkLoad: true,
        initialBreakdown: sampleBreakdown,
      ),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'storage_keep_media': '1month',
      'storage_max_cache_size': 1073741824,
    });
    await SettingsService().init();
  });

  group('StorageScreen Dual-Design Widget Tests', () {
    testWidgets('Renders Standard Material 3 design when glass is disabled',
        (WidgetTester tester) async {
      final glassProvider = LiquidGlassProvider();
      // Ensure glass is disabled (standard mode)
      await glassProvider.setMode(GlassMode.disabled);

      await tester.pumpWidget(createStorageScreenTestWidget(glassProvider: glassProvider));
      await tester.pumpAndSettle();

      // Verify title in standard AppBar
      expect(find.text('Данные и хранилище'), findsOneWidget);

      // Verify Storage Meter card
      expect(find.text('Память устройства'), findsOneWidget);
      expect(find.text('Фотографии: '), findsOneWidget);
      expect(find.text('Видеозаписи: '), findsOneWidget);
      expect(find.text('Аудио / Голосовые: '), findsOneWidget);
      expect(find.text('Файлы / Документы: '), findsOneWidget);
      expect(find.text('Прочее: '), findsOneWidget);

      // Verify Clear Cache button
      expect(find.widgetWithText(FilledButton, 'Очистить кэш'), findsOneWidget);

      // Verify Keep Media section
      expect(find.text('Хранить медиа'), findsOneWidget);
      expect(find.text('3 дня'), findsOneWidget);
      expect(find.text('1 неделя'), findsOneWidget);
      expect(find.text('1 месяц'), findsOneWidget);
      expect(find.text('Всегда'), findsOneWidget);

      // Verify Maximum Cache Size section
      expect(find.text('Максимальный размер кэша'), findsOneWidget);
      expect(find.text('500 MB'), findsOneWidget);
      expect(find.text('1 GB'), findsOneWidget);
      expect(find.text('2 GB'), findsOneWidget);
      expect(find.text('Без ограничений'), findsOneWidget);

      // Open Clear Cache bottom sheet
      await tester.tap(find.widgetWithText(FilledButton, 'Очистить кэш'));
      await tester.pumpAndSettle();

      // Check bottom sheet contents
      expect(find.text('Очистить кэш'), findsWidgets);
      expect(find.text('Все медиафайлы останутся в облаке Theaver и при необходимости загрузятся снова.'), findsOneWidget);
      expect(find.text('Снять все'), findsOneWidget);
    });

    testWidgets('Renders properly and interactions work smoothly',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final glassProvider = LiquidGlassProvider();
      await glassProvider.setMode(GlassMode.disabled);

      await tester.pumpWidget(createStorageScreenTestWidget(glassProvider: glassProvider));
      await tester.pumpAndSettle();

      // Tap on Keep Media option "3 дня"
      await tester.tap(find.text('3 дня'));
      await tester.pumpAndSettle();

      // Scroll until Maximum Cache Size option "2 GB" is visible
      await tester.scrollUntilVisible(find.text('2 GB'), 100);
      await tester.tap(find.text('2 GB'));
      await tester.pumpAndSettle();

      // Verify settings persisted
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('storage_keep_media'), equals('3days'));
      expect(prefs.getInt('storage_max_cache_size'), equals(2147483648));
    });

    testWidgets('Renders Liquid Glass design when glass is enabled',
        (WidgetTester tester) async {
      final glassProvider = LiquidGlassProvider();
      await glassProvider.setMode(GlassMode.full);

      await tester.pumpWidget(createStorageScreenTestWidget(glassProvider: glassProvider));
      await tester.pumpAndSettle();

      // Verify title
      expect(find.text('Данные и хранилище'), findsOneWidget);

      // Verify Storage Meter card with glass styling
      expect(find.text('Память устройства'), findsOneWidget);
      expect(find.text('Фотографии: '), findsOneWidget);

      // Verify Keep Media and Max Cache Size
      expect(find.text('Хранить медиа'), findsOneWidget);
      expect(find.text('Максимальный размер кэша'), findsOneWidget);

      // Tap Clear Cache to open glass bottom sheet
      await tester.tap(find.text('Очистить кэш').first);
      await tester.pumpAndSettle();

      expect(find.text('Все медиафайлы останутся в облаке Theaver и при необходимости загрузятся снова.'), findsOneWidget);
    });
  });
}
