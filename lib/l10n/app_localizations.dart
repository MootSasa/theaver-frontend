import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';

/// Класс для управления локализацией приложения
class AppLocalizations {
  final Locale locale;
  late Map<String, String> _localizedStrings;
  Map<String, String> _fallbackStrings = const {};

  AppLocalizations(this.locale);

  /// Получить экземпляр локализации из контекста
  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  /// Получить локализованный текст по ключу с поддержкой параметров
  String translate(String key, [Map<String, String>? params]) {
    String str = _localizedStrings[key] ?? _fallbackStrings[key] ?? key;
    if (params != null) {
      params.forEach((paramKey, paramValue) {
        str = str.replaceAll('{$paramKey}', paramValue);
      });
    }
    return str;
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
}

/// Провайдер для управления языком приложения
class LocaleProvider extends ChangeNotifier {
  static const String _languageKey = 'selected_language';
  Locale _locale = const Locale('en');
  final Completer<void> _readyCompleter = Completer<void>();

  /// Future, который завершается когда язык загружен из SharedPreferences
  Future<void> get ready => _readyCompleter.future;

  Locale get locale => _locale;

  LocaleProvider() {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString(_languageKey) ?? 'en';
    _locale = Locale(languageCode);
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    await _persistAndSyncLocale(locale.languageCode);
  }

  Future<void> setLocaleByCode(String languageCode) async {
    _locale = Locale(languageCode);
    await _persistAndSyncLocale(languageCode);
  }

  Future<void> _persistAndSyncLocale(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
    notifyListeners();
    unawaited(AuthService.syncSessionLocale(languageCode));
  }
}
