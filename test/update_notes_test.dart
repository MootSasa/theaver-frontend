import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/services/update_service.dart';

void main() {
  const bilingualNotes = '''
<!-- lang:ru -->
<!-- summary: Удаление аккаунта и быстрые реакции -->
### Новое
- **Удаление аккаунта:** можно запросить удаление профиля в настройках безопасности.

### Исправления
- Исправлено отображение длинных ссылок в чатах.
<!-- /lang:ru -->

<!-- lang:en -->
<!-- summary: Account deletion and quick reactions -->
### Added
- **Account deletion:** request account deletion directly in Security Settings.

### Fixed
- Fixed rendering of long URLs in chat bubbles.
<!-- /lang:en -->
''';

  const legacyNotes = '''
# Theaver v1.20.3-beta.429 (Beta)

### 🐛 Исправления ошибок (Bug Fixes)
- **emojis**: fix fallback link previews (`efa8fc95`)
- Update animations smoothly (`123456ab`)
''';

  test('extracts localized markdown notes without HTML comments', () {
    final ru = AppUpdateInfo.extractLocalizedNotes(bilingualNotes, languageCode: 'ru');
    expect(ru, contains('### Новое'));
    expect(ru, contains('Удаление аккаунта'));
    expect(ru, isNot(contains('<!--')));
    expect(ru, isNot(contains('### Added')));

    final en = AppUpdateInfo.extractLocalizedNotes(bilingualNotes, languageCode: 'en');
    expect(en, contains('### Added'));
    expect(en, contains('Account deletion'));
    expect(en, isNot(contains('### Новое')));

    // Non-RU locales cleanly resolve to English notes
    final de = AppUpdateInfo.extractLocalizedNotes(bilingualNotes, languageCode: 'de');
    expect(de, contains('### Added'));
  });

  test('extracts plain summary for push and desktop notifications', () {
    expect(
      AppUpdateInfo.extractPlainSummary(bilingualNotes, languageCode: 'ru'),
      'Удаление аккаунта и быстрые реакции',
    );
    expect(
      AppUpdateInfo.extractPlainSummary(bilingualNotes, languageCode: 'en'),
      'Account deletion and quick reactions',
    );
  });

  test('falls back cleanly on legacy commit-based release notes', () {
    final localized = AppUpdateInfo.extractLocalizedNotes(legacyNotes, languageCode: 'en');
    expect(localized, contains('Bug Fixes'));

    final summary = AppUpdateInfo.extractPlainSummary(legacyNotes, languageCode: 'ru');
    expect(summary, isNot(contains('#')));
    expect(summary, isNot(contains('efa8fc95')));
    expect(summary, isNot(contains('123456ab')));
    expect(summary, contains('emojis: fix fallback link previews'));
    expect(summary, contains('Update animations smoothly'));
  });

  test('AppUpdateInfo convenience methods delegate to extractors', () {
    const info = AppUpdateInfo(
      hasUpdate: true,
      latestVersion: '1.21.0',
      latestBuild: 450,
      minSupportedBuild: 400,
      forceUpdate: false,
      downloadUrl: 'https://storage.theaver.app/releases/theaver.apk',
      apkSizeBytes: 10485760,
      sha256: 'deadbeef',
      releaseNotes: bilingualNotes,
      channel: 'stable',
    );

    expect(info.localizedNotes('ru'), contains('### Новое'));
    expect(info.plainSummary(languageCode: 'en'), 'Account deletion and quick reactions');
  });
}
