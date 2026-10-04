import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/models/theav_theme.dart';
import 'package:theaver/services/account_manager.dart';
import 'package:theaver/services/theav_theme_service.dart';
import 'package:theaver/theme/theme_provider.dart';

void main() {
  group('TheavTheme Model & Packaging Tests', () {
    test('FourCornerGradient JSON serialization roundtrip', () {
      final gradient = FourCornerGradient.defaultSunset;
      final json = gradient.toJson();

      expect(json['topLeft'], '#7B1FA2');
      expect(json['topRight'], '#FF7043');
      expect(json['bottomLeft'], '#E91E63');
      expect(json['bottomRight'], '#FFD54F');

      final reconstructed = FourCornerGradient.fromJson(json);
      expect(reconstructed.topLeft.toARGB32(), gradient.topLeft.toARGB32());
      expect(reconstructed.topRight.toARGB32(), gradient.topRight.toARGB32());
      expect(reconstructed.bottomLeft.toARGB32(), gradient.bottomLeft.toARGB32());
      expect(reconstructed.bottomRight.toARGB32(), gradient.bottomRight.toARGB32());
    });

    test('TheavTheme JSON serialization roundtrip', () {
      const original = TheavTheme(
        id: 'test_theme_1',
        name: 'Space Neon',
        author: 'Tester',
        isDark: true,
        bubbleRadius: 18.0,
        palette: TheavPalette(
          primary: Color(0xFF0088CC),
          onPrimary: Colors.white,
          background: Color(0xFF14181E),
          surface: Color(0xFF2C2C2E),
          onSurface: Colors.white,
          appBarBackground: Color(0xFF14181E),
          appBarForeground: Colors.white,
          chatBubbleOutgoing: Color(0xFF0088CC),
          chatBubbleOutgoingText: Colors.white,
          chatBubbleOutgoingSubtext: Color(0xB3FFFFFF),
          chatBubbleIncoming: Color(0xFF2C2C2E),
          chatBubbleIncomingText: Colors.white,
          chatBubbleIncomingSubtext: Color(0xFF8E8E93),
          chatDateBadge: Color(0x66000000),
          chatDateBadgeText: Colors.white,
        ),
        wallpaper: TheavWallpaper(
          type: 'pattern',
          patternName: 'space',
          backgroundColor: Color(0xFF14181E),
          patternColor: Color(0xFF5CB8E6),
          patternOpacity: 0.18,
          motionEnabled: true,
        ),
      );

      final json = original.toJson();
      final fromJson = TheavTheme.fromJson(json);

      expect(fromJson.id, original.id);
      expect(fromJson.name, original.name);
      expect(fromJson.author, original.author);
      expect(fromJson.isDark, original.isDark);
      expect(fromJson.bubbleRadius, original.bubbleRadius);
      expect(fromJson.palette.primary.toARGB32(), original.palette.primary.toARGB32());
      expect(fromJson.wallpaper.type, original.wallpaper.type);
      expect(fromJson.wallpaper.patternName, 'space');
      expect(fromJson.wallpaper.motionEnabled, true);
    });

    test('TheavWallpaper image & imageUrl serialization roundtrip', () {
      const wallpaper = TheavWallpaper(
        type: 'image',
        imagePath: '/local/test/path.png',
        imageUrl: 'https://storage.theaver.app/wallpapers/user1/test.png',
        blurRadius: 10.0,
        dimming: 0.3,
      );

      final json = wallpaper.toJson();
      expect(json['type'], 'image');
      expect(json['imagePath'], '/local/test/path.png');
      expect(json['imageUrl'], 'https://storage.theaver.app/wallpapers/user1/test.png');
      expect(json['blurRadius'], 10.0);
      expect(json['dimming'], 0.3);

      final fromJson = TheavWallpaper.fromJson(json);
      expect(fromJson.type, 'image');
      expect(fromJson.imagePath, '/local/test/path.png');
      expect(fromJson.imageUrl, 'https://storage.theaver.app/wallpapers/user1/test.png');
      expect(fromJson.blurRadius, 10.0);
      expect(fromJson.dimming, 0.3);
      expect(fromJson.hasImage, true);
    });

    test('TheavWallpaper copyWith clearImageUrl', () {
      const wallpaper = TheavWallpaper(
        type: 'image',
        imagePath: '/old/path.png',
        imageUrl: 'https://storage.theaver.app/wallpapers/old.png',
      );

      final updated = wallpaper.copyWith(
        imagePath: '/new/path.png',
        clearImageUrl: true,
      );

      expect(updated.imagePath, '/new/path.png');
      expect(updated.imageUrl, isNull);
    });

    test('TheavWallpaper copyWith clearFourCornerGradient', () {
      final wallpaper = TheavWallpaper(
        type: 'color',
        fourCornerGradient: FourCornerGradient.defaultSunset,
      );
      expect(wallpaper.fourCornerGradient, isNotNull);

      final cleared = wallpaper.copyWith(
        type: 'image',
        clearFourCornerGradient: true,
      );
      expect(cleared.fourCornerGradient, isNull);
      expect(cleared.type, 'image');
    });

    test('TheavTheme ZIP packaging roundtrip', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final service = TheavThemeService();
      final theme = TheavThemeService.builtInThemes[0];

      // Export to ZIP
      final zipBytes = await service.exportThemePackage(theme);
      expect(zipBytes.isNotEmpty, true);

      // Import from ZIP
      final imported = await service.importThemePackage(zipBytes);
      expect(imported.name, theme.name);
      expect(imported.isDark, theme.isDark);
      expect(imported.palette.primary.toARGB32(), theme.palette.primary.toARGB32());
      expect(imported.wallpaper.type, theme.wallpaper.type);
      expect(imported.wallpaper.patternName, theme.wallpaper.patternName);
    });

    test('TheavTheme ZIP packaging preserves Cyrillic and emoji theme names', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final service = TheavThemeService();
      final theme = TheavThemeService.builtInThemes[0].copyWith(
        id: 'cyrillic_theme_test',
        name: 'Моя русская тема 🌸 №1',
      );

      final zipBytes = await service.exportThemePackage(theme);
      final imported = await service.importThemePackage(zipBytes);
      expect(imported.name, 'Моя русская тема 🌸 №1');
    });

    test('TheavTheme importThemePackage uses defaultName fallback if manifest name is empty', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final service = TheavThemeService();
      final theme = TheavThemeService.builtInThemes[0].copyWith(
        id: 'empty_name_theme',
        name: '   ',
      );

      final zipBytes = await service.exportThemePackage(theme);
      final imported = await service.importThemePackage(zipBytes, defaultName: 'Импортированная тема');
      expect(imported.name, 'Импортированная тема');
    });

    test('TheavTheme.fromJson handles missing fields with safe defaults', () {
      final minimalJson = <String, dynamic>{};
      final theme = TheavTheme.fromJson(minimalJson);

      expect(theme.name, 'Custom Theme');
      expect(theme.author, 'Theaver User');
      expect(theme.isDark, false);
      expect(theme.bubbleRadius, 16.0);
      expect(theme.palette.primary, const Color(0xFF0088CC));
      expect(theme.palette.background, const Color(0xFFFFFFFF));
      expect(theme.palette.error, const Color(0xFFEF5350));
      expect(theme.wallpaper.type, 'pattern');
      expect(theme.wallpaper.backgroundColor, const Color(0xFFEAF2F8));
    });

    test('TheavTheme.fromJson ignores extra unknown fields without errors', () {
      final jsonWithExtras = <String, dynamic>{
        'name': 'Future Theme',
        'extraFutureSetting': true,
        'someRandomList': [1, 2, 3],
        'palette': {
          'primary': '#FF0000',
          'nonExistentColorKey': '#123456',
          'futureGradientMode': 'mesh',
        },
        'wallpaper': {
          'type': 'pattern',
          'extraWallpaperParam': 42,
        },
      };

      final theme = TheavTheme.fromJson(jsonWithExtras);
      expect(theme.name, 'Future Theme');
      expect(theme.palette.primary, const Color(0xFFFF0000));
      expect(theme.wallpaper.type, 'pattern');
    });

    test('TheavColorUtils handles invalid hex strings gracefully', () {
      expect(TheavColorUtils.fromHex('not-a-hex'), const Color(0xFF0088CC));
      expect(TheavColorUtils.fromHex(''), const Color(0xFF0088CC));
      expect(TheavColorUtils.fromHex('#XYZ123'), const Color(0xFF0088CC));
    });
  });

  group('TheavThemeService Filename Sanitization Tests', () {
    test('Preserves Cyrillic characters in filename', () {
      expect(TheavThemeService.sanitizeFileName('Моя новая тема'), equals('Моя новая тема'));
      expect(TheavThemeService.sanitizeFileName('Тема для лета 2026'), equals('Тема для лета 2026'));
    });

    test('Preserves emojis, symbols, and punctuation in filename', () {
      expect(TheavThemeService.sanitizeFileName('🌸 Sakura Bloom (Dark) #1!'), equals('🌸 Sakura Bloom (Dark) #1!'));
    });

    test('Replaces filesystem-illegal characters safely', () {
      expect(TheavThemeService.sanitizeFileName('Theme:Sub/Name*With?Invalid"Chars|<>'), equals('Theme_Sub_Name_With_Invalid_Chars___'));
    });

    test('Removes trailing spaces and dots', () {
      expect(TheavThemeService.sanitizeFileName('My Theme . . '), equals('My Theme'));
    });

    test('Falls back to default name when all characters are illegal or empty', () {
      expect(TheavThemeService.sanitizeFileName(''), equals('theme'));
      expect(TheavThemeService.sanitizeFileName('   '), equals('theme'));
      expect(TheavThemeService.sanitizeFileName('///:::***???'), equals('theme'));
      expect(TheavThemeService.sanitizeFileName('///', fallback: 'custom_fallback'), equals('custom_fallback'));
    });
  });

  group('TheavThemeService Multi-Account Isolation Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Each account maintains isolated active themes without leaking', () async {
      SharedPreferences.setMockInitialValues({});
      final service = TheavThemeService();

      // Account 1: Switch and set Arctic Frost (Light)
      await service.switchUser('user_A', force: true);
      expect(service.currentUserId, equals('user_A'));
      final arcticFrost = TheavThemeService.builtInThemes.firstWhere((t) => t.id == 'arctic_frost');
      await service.setActiveTheme(arcticFrost);
      expect(service.activeLightThemeId, equals('arctic_frost'));

      // Save a custom theme for Account 1
      final customA = arcticFrost.copyWith(
        id: 'custom_user_a_theme',
        name: 'Тема Пользователя А',
        isBuiltIn: false,
      );
      await service.saveTheme(customA, saveToCloud: false);
      expect(service.customThemes.any((t) => t.id == 'custom_user_a_theme'), isTrue);

      // Account 2: Switch to user_B
      await service.switchUser('user_B', force: true);
      expect(service.currentUserId, equals('user_B'));
      // user_B must have fresh defaults, NOT user_A's theme or custom themes
      expect(service.activeLightThemeId, equals('theaver_classic'));
      expect(service.customThemes.any((t) => t.id == 'custom_user_a_theme'), isFalse);

      // Set Emerald Nature for Account 2
      final emeraldNature = TheavThemeService.builtInThemes.firstWhere((t) => t.id == 'emerald_nature');
      await service.setActiveTheme(emeraldNature);
      expect(service.activeLightThemeId, equals('emerald_nature'));

      // Switch back to Account 1: must still have Arctic Frost and its custom theme
      await service.switchUser('user_A', force: true);
      expect(service.activeLightThemeId, equals('arctic_frost'));
      expect(service.customThemes.any((t) => t.id == 'custom_user_a_theme'), isTrue);

      // Switch back to Account 2: must still have Emerald Nature
      await service.switchUser('user_B', force: true);
      expect(service.activeLightThemeId, equals('emerald_nature'));
      expect(service.customThemes.any((t) => t.id == 'custom_user_a_theme'), isFalse);
    });

    test('Legacy device keys migrate seamlessly to the first user', () async {
      SharedPreferences.setMockInitialValues({
        'device_active_light_theme_id': 'warm_romance',
      });
      final service = TheavThemeService();

      // First user logs in -> legacy keys migrated
      await service.switchUser('migrated_user', force: true);
      expect(service.activeLightThemeId, equals('warm_romance'));

      // Second user logs in -> starts fresh with default, not legacy
      await service.switchUser('second_user', force: true);
      expect(service.activeLightThemeId, equals('theaver_classic'));
    });

    test('ThemeProvider isolates themeMode across accounts', () async {
      SharedPreferences.setMockInitialValues({
        'user_user_A_theme_mode': ThemeMode.dark.index,
        'user_user_B_theme_mode': ThemeMode.light.index,
      });

      final accountManager = AccountManager();
      await accountManager.init();

      // Ensure Account A exists and is active
      if (accountManager.hasAccount('user_A')) {
        await accountManager.removeAccount('user_A');
      }
      if (accountManager.hasAccount('user_B')) {
        await accountManager.removeAccount('user_B');
      }

      await accountManager.addAccount(Account(
        userId: 'user_A',
        token: 'token_A',
        username: 'userA',
        displayName: 'User A',
        lastLogin: DateTime.now(),
      ));

      await accountManager.addAccount(Account(
        userId: 'user_B',
        token: 'token_B',
        username: 'userB',
        displayName: 'User B',
        lastLogin: DateTime.now(),
      ));

      await accountManager.setCurrentAccount('user_A');
      final provider = ThemeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.themeMode, equals(ThemeMode.dark));

      // Switch to User B in AccountManager
      await accountManager.setCurrentAccount('user_B');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.themeMode, equals(ThemeMode.light));

      // Change User B mode to system
      await provider.setToSystem();
      expect(provider.themeMode, equals(ThemeMode.system));

      // Switch back to User A
      await accountManager.setCurrentAccount('user_A');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.themeMode, equals(ThemeMode.dark));
    });
  });
}

