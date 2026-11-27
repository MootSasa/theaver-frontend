// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/settings/settings_floating_header.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({Key? key}) : super(key: key);

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String? _selectedLanguage;

  static const _languages = {
    'en': 'English',
    'ru': 'Русский',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'it': 'Italiano',
    'pt': 'Português',
    'zh': '中文',
    'ja': '日本語',
    'ko': '한국어',
  };

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  void _loadLanguage() {
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    setState(() {
      _selectedLanguage = localeProvider.locale.languageCode;
    });
  }

  void _onLanguageChanged(String? value) {
    if (value != null) {
      setState(() {
        _selectedLanguage = value;
      });
      final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
      localeProvider.setLocaleByCode(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    
    return SettingsFloatingScaffold(
      title: l10n.translate('language_title'),
      body: ListView(
        children: _languages.entries.map((entry) {
          final languageCode = entry.key;
          final languageName = entry.value;
          return RadioListTile<String>(
            title: Text(languageName),
            value: languageCode,
            groupValue: _selectedLanguage,
            onChanged: _onLanguageChanged,
          );
        }).toList(),
      ),
    );
  }
}
