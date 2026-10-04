import 'package:flutter/material.dart';
import '../animations/screen_transitions.dart';
import '../models/theav_theme.dart';

class AppTheme {
  // === Цвета бренда ===
  static const Color brand = Color(0xFF0088CC);

  // === Светлая тема ===
  static ThemeData light() {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: brand,
      colorScheme: const ColorScheme.light(
        primary: brand,
        secondary: Color(0xFF5CB8E6),
        surface: Color(0xFFF5F5F5),
        error: Color(0xFFD32F2F),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Color(0xFF1C1C1E),
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFFFFFFF),
      pageTransitionsTheme: CustomPageTransitionsTheme.customTheme,
      cardColor: const Color(0xFFF2F2F7),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFFFFFF),
        foregroundColor: Color(0xFF1C1C1E),
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: const Color(0xFFF2F2F7),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: Color(0xFF1C1C1E),
        iconColor: brand,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1C1C1E),
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1C1C1E),
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1C1C1E),
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: Color(0xFF1C1C1E),
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: Color(0xFF3C3C43),
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Color(0xFF3C3C43),
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Color(0xFF8E8E93),
        ),
      ),
      iconTheme: const IconThemeData(
        color: Color(0xFF1C1C1E),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey[200],
        thickness: 0.5,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return brand;
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return brand.withValues(alpha: 0.4);
          }
          return Colors.grey.withValues(alpha: 0.3);
        }),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey[200],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: brand,
        selectionColor: Color(0x470088CC),
        selectionHandleColor: brand,
      ),
    );
  }

  // === Тёмная тема ===
  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: brand,
      colorScheme: const ColorScheme.dark(
        primary: brand,
        secondary: brand,
        surface: Color(0xFF2C2C2E),
        error: Color(0xFFEF5350),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Color(0xFFE5E5EA),
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFF1C1C1E),
      pageTransitionsTheme: CustomPageTransitionsTheme.customTheme,
      cardColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1C1C1E),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: const Color(0xFF121212),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: Color(0xFFE5E5EA),
        iconColor: Color(0xFF5CB8E6),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: Color(0xFFE5E5EA),
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: Color(0xFF8E8E93),
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Color(0xFF8E8E93),
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Color(0xFF636366),
        ),
      ),
      iconTheme: const IconThemeData(
        color: Color(0xFFE5E5EA),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF38383A),
        thickness: 0.5,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return brand;
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return brand.withValues(alpha: 0.4);
          }
          return Colors.grey.withValues(alpha: 0.3);
        }),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1C1C1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: const TextStyle(
          color: Color(0xFF636366),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Color(0xFF7BE5DA),
        selectionColor: Color(0x597BE5DA),
        selectionHandleColor: Color(0xFF7BE5DA),
      ),
    );
  }

  // === Dynamic TheavTheme application ===
  static ThemeData fromTheavTheme(TheavTheme theme) {
    final base = theme.isDark ? dark() : light();
    final p = theme.palette;
    final colorScheme = theme.isDark
        ? ColorScheme.dark(
            primary: p.primary,
            secondary: p.primary,
            surface: p.surface,
            error: p.error,
            onPrimary: p.onPrimary,
            onSecondary: p.onPrimary,
            onSurface: p.onSurface,
            onError: Colors.white,
          )
        : ColorScheme.light(
            primary: p.primary,
            secondary: p.primary,
            surface: p.surface,
            error: p.error,
            onPrimary: p.onPrimary,
            onSecondary: p.onPrimary,
            onSurface: p.onSurface,
            onError: Colors.white,
          );

    return base.copyWith(
      primaryColor: p.primary,
      indicatorColor: p.primary,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: p.background,
      cardColor: p.surface,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: p.appBarBackground,
        foregroundColor: p.appBarForeground,
        iconTheme: IconThemeData(color: p.appBarForeground),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.primary;
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return p.primary.withValues(alpha: 0.4);
          }
          return Colors.grey.withValues(alpha: 0.3);
        }),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: p.primary,
        thumbColor: p.primary,
        overlayColor: p.primary.withValues(alpha: 0.2),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.primary;
          return null;
        }),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.primary;
          return null;
        }),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        iconColor: p.primary,
        textColor: p.onSurface,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        circularTrackColor: p.primary.withValues(alpha: 0.2),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.primary,
        selectionColor: p.primary.withValues(alpha: 0.3),
        selectionHandleColor: p.primary,
      ),
      tabBarTheme: base.tabBarTheme.copyWith(
        indicatorColor: p.primary,
        labelColor: p.primary,
      ),
      bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
        selectedItemColor: p.primary,
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        indicatorColor: p.primary.withValues(alpha: 0.2),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: p.divider,
        thickness: 0.5,
      ),
      extensions: [
        TheavThemeExtension(
          palette: p,
          wallpaper: theme.wallpaper,
          bubbleRadius: theme.bubbleRadius,
        ),
      ],
    );
  }
}
