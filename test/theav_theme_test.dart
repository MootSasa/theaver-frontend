import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/models/theav_theme.dart';
import 'package:theaver/services/theav_theme_service.dart';

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
  });
}
