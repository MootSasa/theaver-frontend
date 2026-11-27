import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';

/// Класс для управления локализацией приложения
class AppLocalizations {
  static AppLocalizations? _current;

  /// Текущий загруженный экземпляр локализации (может быть null до вызова [load]).
  static AppLocalizations? get current => _current;

  @visibleForTesting
  static set debugCurrent(AppLocalizations? value) => _current = value;

  final Locale locale;
  Map<String, String> _localizedStrings = const {};
  Map<String, String> _fallbackStrings = const {};

  AppLocalizations(this.locale);

  /// Получить экземпляр локализации из контекста
  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  /// Проверяет, определён ли ключ [key] в активном или резервном словаре.
  bool hasKey(String key) =>
      _localizedStrings.containsKey(key) || _fallbackStrings.containsKey(key);

  /// Translates [key] if present, otherwise interpolates [fallback].
  String trOr(String key, String fallback, [Map<String, String>? params]) =>
      hasKey(key)
          ? translate(key, params)
          : _interpolate(fallback, params);

  static String _interpolate(String raw, [Map<String, String>? params]) {
    if (params == null || params.isEmpty) return raw;
    String str = raw;
    params.forEach((paramKey, paramValue) {
      str = str.replaceAll('{$paramKey}', paramValue);
    });
    return str;
  }

  /// Переводит [key] через [current], либо возвращает интерполированный [fallback].
  static String trStatic(
    String key,
    String fallback, [
    Map<String, String>? params,
  ]) {
    final cur = _current;
    if (cur != null && cur.hasKey(key)) {
      return cur.translate(key, params);
    }
    return _interpolate(fallback, params);
  }

  /// Получить локализованный текст по ключу с поддержкой параметров
  String translate(String key, [Map<String, String>? params]) {
    final String str = _localizedStrings[key] ?? _fallbackStrings[key] ?? key;
    return _interpolate(str, params);
  }

  /// Загрузить файл локализации (с резервным fallback на EN при отсутствующих ключах)
  Future<bool> load() async {
    String jsonString = await rootBundle.loadString(
      'assets/l10n/${locale.languageCode}.json',
    );
    Map<String, dynamic> jsonMap = json.decode(jsonString);
    _localizedStrings = jsonMap.map((key, value) {
      return MapEntry(key, value.toString());
    });
    if (locale.languageCode != 'en') {
      try {
        final fallbackRaw = await rootBundle.loadString('assets/l10n/en.json');
        final fallbackMap = json.decode(fallbackRaw) as Map<String, dynamic>;
        _fallbackStrings = fallbackMap.map(
          (key, value) => MapEntry(key, value.toString()),
        );
      } catch (_) {
        _fallbackStrings = const {};
      }
    } else {
      _fallbackStrings = const {};
    }
    _current = this;
    return true;
  }

  /// Делегат для загрузки локализаций
  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'ru', 'es', 'fr', 'de', 'it', 'pt', 'zh', 'ja', 'ko']
        .contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    AppLocalizations localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Расширение для удобного доступа к переводам
extension AppLocalizationsExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;

  /// Получить перевод по ключу с поддержкой параметров
  String tr(String key, [Map<String, String>? params]) => l10n.translate(key, params);

  /// Безопасный перевод с fallback-строкой (не бросает исключение в изолированных
  /// виджет-тестах без делегата [AppLocalizations.delegate]).
  String trOr(
    String key,
    String fallback, [
    Map<String, String>? params,
  ]) {
    final loc = AppLocalizations.of(this);
    if (loc != null && loc.hasKey(key)) {
      return loc.translate(key, params);
    }
    return AppLocalizations._interpolate(fallback, params);
  }
}

/// Провайдер для управления языком приложения
class LocaleProvider extends ChangeNotifier {
  static const String _languageKey = 'selected_language';
  static const List<String> supportedLanguageCodes = [
    'en',
    'ru',
    'es',
    'fr',
    'de',
    'it',
    'pt',
    'zh',
    'ja',
    'ko',
  ];

  static String resolveSystemLanguageCode([Locale? systemLocale]) {
    final code = (systemLocale ?? WidgetsBinding.instance.platformDispatcher.locale)
        .languageCode
        .toLowerCase()
        .trim();
    if (supportedLanguageCodes.contains(code)) {
      return code;
    }
    return 'en';
  }

  Locale _locale = Locale(resolveSystemLanguageCode());
  bool _hasExplicitSelection = false;
  final Completer<void> _readyCompleter = Completer<void>();

  /// Future, который завершается когда язык загружен из SharedPreferences
  Future<void> get ready => _readyCompleter.future;

  Locale get locale => _locale;
  bool get hasExplicitSelection => _hasExplicitSelection;

  LocaleProvider() {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_languageKey);
    if (stored != null && stored.trim().isNotEmpty) {
      _hasExplicitSelection = true;
      _locale = Locale(stored.trim());
    } else {
      _hasExplicitSelection = false;
      _locale = Locale(resolveSystemLanguageCode());
    }
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    _hasExplicitSelection = true;
    await _persistAndSyncLocale(locale.languageCode);
  }

  Future<void> setLocaleByCode(String languageCode) async {
    _locale = Locale(languageCode);
    _hasExplicitSelection = true;
    await _persistAndSyncLocale(languageCode);
  }

  Future<void> _persistAndSyncLocale(String languageCode) async {
    _hasExplicitSelection = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
    notifyListeners();
    unawaited(AuthService.syncSessionLocale(languageCode));
  }
}
