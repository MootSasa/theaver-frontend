import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/theav_theme_service.dart';
import '../../services/wallpaper_provider.dart';
import '../../theme/theme_provider.dart';
import '../../widgets/chat/liquid_glass_app_bar.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../widgets/theme/chat_preview_card.dart';
import '../../widgets/theme/four_corner_gradient.dart';
import '../../widgets/theme/theme_preview_sheet.dart';
import '../../l10n/app_localizations.dart';
import 'advanced_theme_colors_screen.dart';
import 'theme_editor_screen.dart';
import 'wallpaper_screen.dart';
import '../../utils/swipe_back_route.dart';

/// Screen for chat settings: wallpaper constructor, themes carousel,
/// in-app theme editor, .theavtheme import/export, advanced color customization,
/// and Liquid Glass design controls.
class ChatSettingsScreen extends StatelessWidget {
  const ChatSettingsScreen({Key? key}) : super(key: key);

  Future<void> _importTheme(BuildContext context) async {
    final l10n = context.l10n;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty || result.files.single.path == null) {
        return;
      }

      final file = File(result.files.single.path!);
      if (!file.path.toLowerCase().endsWith('.theavtheme')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('theme_select_theavtheme'))),
        );
        return;
      }

      final bytes = await file.readAsBytes();
      final pickedFileName = result.files.single.name;
      final defaultName = pickedFileName.toLowerCase().endsWith('.theavtheme')
          ? pickedFileName.substring(0, pickedFileName.length - '.theavtheme'.length)
          : pickedFileName;
      final imported = await TheavThemeService().importThemePackage(bytes, defaultName: defaultName);

      if (context.mounted) {
        ThemePreviewSheet.show(
          context,
          theme: imported,
          onApply: () async {
            await context.read<ThemeProvider>().setActiveTheme(imported);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.translate('theme_import_success'))),
            );
          },
          onSaveToCloud: () async {
            await TheavThemeService().saveTheme(imported, saveToCloud: true);
            await context.read<ThemeProvider>().setActiveTheme(imported);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.translate('theme_saved_in_cloud'))),
            );
          },
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('theme_import_error').replaceAll('{error}', e.toString()))),
        );
      }
    }
  }

  Future<void> _exportTheme(BuildContext context, TheavTheme themeToExport) async {
    final l10n = context.l10n;
    try {
      final bytes = await TheavThemeService().exportThemePackage(themeToExport);
      final tempDir = await getTemporaryDirectory();
      final cleanName = TheavThemeService.sanitizeFileName(themeToExport.name);
      final file = File('${tempDir.path}/$cleanName.theavtheme');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, name: '$cleanName.theavtheme')],
        text: 'Тема Theaver: ${themeToExport.name}',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('theme_export_error').replaceAll('{error}', e.toString()))),
        );
      }
    }
  }

  Future<void> _exportActiveTheme(BuildContext context) async {
    final themeProvider = context.read<ThemeProvider>();
    final isDark = themeProvider.themeMode == ThemeMode.dark;
    final activeTheme = isDark ? themeProvider.activeDarkTheme : themeProvider.activeLightTheme;
    await _exportTheme(context, activeTheme);
  }

  void _showThemeOptionsModal(BuildContext context, TheavTheme t) {
    final l10n = context.l10n;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                t.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const iconoir.EditPencil(width: 22, height: 22),
              title: Text(l10n.translate('theme_edit')),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  SwipeBackPageRoute(builder: (_) => ThemeEditorScreen(themeToEdit: t)),
                );
              },
            ),
            ListTile(
              leading: const iconoir.ShareAndroid(width: 22, height: 22),
              title: Text(l10n.translate('theme_export')),
              onTap: () {
                Navigator.pop(ctx);
                _exportTheme(context, t);
              },
            ),
            ListTile(
              leading: iconoir.Trash(
                width: 22,
                height: 22,
                color: t.palette.error,
              ),
              title: Text(
                l10n.translate('theme_delete'),
                style: TextStyle(color: t.palette.error, fontWeight: FontWeight.w600),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: Text(l10n.translate('theme_delete')),
                    content: Text(l10n.translate('theme_delete_confirm')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, false),
                        child: Text(l10n.translate('cancel')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, true),
                        child: Text(
                          l10n.translate('common_delete'),
                          style: TextStyle(color: t.palette.error),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await TheavThemeService().deleteTheme(t.id);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.themeMode == ThemeMode.dark;
    final activeTheme = isDark ? themeProvider.activeDarkTheme : themeProvider.activeLightTheme;
    final activePrimary = activeTheme.palette.primary;
    final allThemes = TheavThemeService().getAllThemes();

    return Consumer<LiquidGlassProvider>(
      builder: (context, glassProvider, _) {
        final glassEnabled = glassProvider.enabled;

        final appBarActions = [
          IconButton(
            icon: const iconoir.Download(width: 22, height: 22),
            tooltip: l10n.translate('theme_import'),
            onPressed: () => _importTheme(context),
          ),
          IconButton(
            icon: const iconoir.ShareAndroid(width: 22, height: 22),
            tooltip: l10n.translate('theme_export'),
            onPressed: () => _exportActiveTheme(context),
          ),
        ];

        final listView = ListView(
          padding: EdgeInsets.only(
            top: glassEnabled ? 12 : 0,
            bottom: 30,
          ),
          children: [
            // 1. Live Sticky Interactive Preview Card
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ChatPreviewCard(
                theme: activeTheme,
                height: 230,
              ),
            ),

            // 2. Themes Selection Carousel
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.translate('theme_custom_title'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    icon: const iconoir.Plus(width: 18, height: 18),
                    label: Text(
                      l10n.translate('theme_create_new'),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        SwipeBackPageRoute(builder: (_) => const ThemeEditorScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: allThemes.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  if (index == allThemes.length) {
                    // "+ Create Theme" Card
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          SwipeBackPageRoute(builder: (_) => const ThemeEditorScreen()),
                        );
                      },
                      child: SizedBox(
                        width: 80,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 78,
                              height: 68,
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.grey.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Center(
                                child: iconoir.Plus(color: activePrimary, width: 28, height: 28),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.translate('theme_create_button'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: activePrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final t = allThemes[index];
                  final isSelected = t.id == activeTheme.id;

                  return _ThemeItemBubble(
                    theme: isSelected ? activeTheme : t,
                    isSelected: isSelected,
                    activePrimary: activePrimary,
                    onTap: () {
                      themeProvider.setActiveTheme(t);
                      if (t.wallpaper.type != 'image') {
                        context.read<WallpaperProvider>().removeWallpaper(syncToServer: false);
                      } else if (t.wallpaper.imagePath != null) {
                        context.read<WallpaperProvider>().setWallpaper(t.wallpaper.imagePath!);
                      }
                    },
                    onLongPress: () {
                      if (!t.isBuiltIn) {
                        _showThemeOptionsModal(context, t);
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 14),

            // 3. Wallpaper constructor Tile
            ListTile(
              leading: iconoir.MediaImage(color: activePrimary, width: 22, height: 22),
              title: Text(l10n.translate('wallpaper_title')),
              subtitle: Text(
                activeTheme.wallpaper.type == 'pattern'
                    ? (activeTheme.wallpaper.patternName != null && activeTheme.wallpaper.patternName != 'none'
                        ? l10n.translate('theme_wallpaper_pattern_desc').replaceAll('{pattern}', activeTheme.wallpaper.patternName!)
                        : l10n.translate('theme_wallpaper_gradient_desc'))
                    : activeTheme.wallpaper.type == 'image'
                        ? l10n.translate('theme_wallpaper_photo_desc')
                        : l10n.translate('theme_wallpaper_default_desc'),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              trailing: const iconoir.NavArrowRight(color: Colors.grey, width: 20, height: 20),
              onTap: () {
                Navigator.push(
                  context,
                  SwipeBackPageRoute(
                    builder: (_) => WallpaperScreen(
                      initialWallpaper: activeTheme.wallpaper,
                    ),
                  ),
                );
              },
            ),

            // 4. Bubble Corner Radius Slider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.translate('theme_bubble_radius'),
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        Text('${activeTheme.bubbleRadius.round()} px'),
                      ],
                    ),
                    Slider(
                      value: activeTheme.bubbleRadius,
                      min: 0,
                      max: 24,
                      divisions: 24,
                      activeColor: activePrimary,
                      onChanged: (val) {
                        final updated = activeTheme.copyWith(bubbleRadius: val);
                        themeProvider.setActiveTheme(updated);
                        TheavThemeService().saveTheme(
                          updated,
                          saveToCloud: !activeTheme.isBuiltIn || activeTheme.isCloudSaved,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // 5. Advanced Theme Colors Tile
            ListTile(
              leading: iconoir.Palette(color: activePrimary, width: 22, height: 22),
              title: Text(l10n.translate('theme_advanced_settings')),
              subtitle: Text(
                l10n.translate('theme_advanced_settings_desc'),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              trailing: const iconoir.NavArrowRight(color: Colors.grey, width: 20, height: 20),
              onTap: () {
                Navigator.push(
                  context,
                  SwipeBackPageRoute(
                    builder: (_) => AdvancedThemeColorsScreen(initialTheme: activeTheme),
                  ),
                );
              },
            ),

            const SizedBox(height: 6),

            // 6. Light / Dark / System Switcher
            Column(
              children: [
                ListTile(
                  leading: iconoir.HalfMoon(
                    color: themeProvider.themeMode == ThemeMode.dark
                        ? activePrimary
                        : themeProvider.themeMode == ThemeMode.light
                            ? activePrimary
                            : Colors.grey,
                    width: 22,
                    height: 22,
                  ),
                  title: Text(l10n.translate('settings_theme')),
                  subtitle: Text(
                    _themeModeLabel(themeProvider.themeMode, l10n),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _ThemeButton(
                        icon: const iconoir.SunLight(width: 22, height: 22),
                        label: l10n.translate('theme_light'),
                        isSelected: themeProvider.themeMode == ThemeMode.light,
                        onTap: () => themeProvider.setToLight(),
                      ),
                      const SizedBox(width: 8),
                      _ThemeButton(
                        icon: const iconoir.HalfMoon(width: 22, height: 22),
                        label: l10n.translate('theme_dark'),
                        isSelected: themeProvider.themeMode == ThemeMode.dark,
                        onTap: () => themeProvider.setToDark(),
                      ),
                      const SizedBox(width: 8),
                      _ThemeButton(
                        icon: const iconoir.Laptop(width: 22, height: 22),
                        label: l10n.translate('theme_system'),
                        isSelected: themeProvider.themeMode == ThemeMode.system,
                        onTap: () => themeProvider.setToSystem(),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 7. Liquid Glass Design Controls
            Consumer<LiquidGlassProvider>(
              builder: (context, provider, _) {
                final isSupported = provider.isSupported;
                final mode = provider.mode;

                return Column(
                  children: [
                    ListTile(
                      leading: iconoir.Spark(
                        color: isSupported ? activePrimary : Colors.grey,
                        width: 22,
                        height: 22,
                      ),
                      title: Text(
                        l10n.translate('settings_liquid_glass'),
                        style: TextStyle(color: isSupported ? null : Colors.grey),
                      ),
                      subtitle: Text(
                        isSupported
                            ? l10n.translate('settings_liquid_glass_desc')
                            : l10n.translate('settings_liquid_glass_unsupported'),
                        style: TextStyle(fontSize: 12, color: isSupported ? Colors.grey[600] : Colors.grey),
                      ),
                      trailing: isSupported
                          ? AdaptiveSwitch(
                              value: provider.enabled,
                              onChanged: (val) => provider.setMode(
                                val ? GlassMode.full : GlassMode.disabled,
                              ),
                            )
                          : null,
                    ),
                    if (isSupported)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _GlassModeButton(
                              icon: const iconoir.Xmark(width: 20, height: 20),
                              label: l10n.translate('settings_glass_off'),
                              isSelected: mode == GlassMode.disabled,
                              onTap: () => provider.setMode(GlassMode.disabled),
                            ),
                            const SizedBox(width: 8),
                            _GlassModeButton(
                              icon: const iconoir.Spark(width: 20, height: 20),
                              label: l10n.translate('settings_glass_lite'),
                              isSelected: mode == GlassMode.lite,
                              onTap: () => provider.setMode(GlassMode.lite),
                            ),
                            const SizedBox(width: 8),
                            _GlassModeButton(
                              icon: const iconoir.Spark(width: 20, height: 20),
                              label: l10n.translate('settings_glass_full'),
                              isSelected: mode == GlassMode.full,
                              onTap: () => provider.setMode(GlassMode.full),
                            ),
                          ],
                        ),
                      ),
                    if (isSupported && mode != GlassMode.disabled) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.translate('theme_glass_light_angle').replaceAll('{value}', '${provider.manualLightAngle.round()}'),
                              style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: AdaptiveSlider(
                          value: provider.manualLightAngle,
                          min: 0,
                          max: 360,
                          divisions: 72,
                          activeColor: activePrimary,
                          label: '${provider.manualLightAngle.round()}°',
                          onChanged: (val) => provider.setManualLightAngle(val),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.translate('theme_glass_blur').replaceAll('{value}', provider.blur.toStringAsFixed(1)),
                              style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: AdaptiveSlider(
                          value: provider.blur,
                          min: 0,
                          max: 30,
                          divisions: 60,
                          activeColor: activePrimary,
                          label: provider.blur.toStringAsFixed(1),
                          onChanged: (val) => provider.setBlur(val),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        );

        if (glassEnabled) {
          final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight;
          return Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(top: topPadding),
                    child: listView,
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LiquidGlassAppBar(
                    title: Text(l10n.translate('settings_chat_settings')),
                    actions: appBarActions,
                    centerTitle: true,
                    isLite: glassProvider.isLite,
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.translate('settings_chat_settings')),
            actions: appBarActions,
          ),
          body: listView,
        );
      },
    );
  }

  String _themeModeLabel(ThemeMode mode, AppLocalizations l10n) {
    switch (mode) {
      case ThemeMode.light:
        return l10n.translate('theme_light');
      case ThemeMode.dark:
        return l10n.translate('theme_dark');
      case ThemeMode.system:
        return l10n.translate('theme_system');
    }
  }
}

class _ThemeButton extends StatelessWidget {
  const _ThemeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? primary : Colors.grey.withValues(alpha: 0.3),
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            children: [
              icon,
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? primary : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassModeButton extends StatelessWidget {
  const _GlassModeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? primary : Colors.grey.withValues(alpha: 0.3),
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            children: [
              icon,
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? primary : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Theme carousel item: wallpaper background with 2 empty message ovals.
class _ThemeItemBubble extends StatelessWidget {
  final TheavTheme theme;
  final bool isSelected;
  final Color activePrimary;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ThemeItemBubble({
    required this.theme,
    required this.isSelected,
    required this.activePrimary,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final wp = theme.wallpaper;

    Widget wallpaperBg;
    if (wp.type == 'image') {
      final imgProvider = wp.getImageProvider();
      if (imgProvider != null) {
        Widget img = Image(
          image: imgProvider,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) => Container(color: wp.backgroundColor),
        );
        if (wp.blurRadius > 0) {
          img = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: (wp.blurRadius / 4).clamp(0.5, 4.0),
              sigmaY: (wp.blurRadius / 4).clamp(0.5, 4.0),
            ),
            child: img,
          );
        }
        if (wp.dimming > 0) {
          img = Stack(
            fit: StackFit.expand,
            children: [
              img,
              Container(
                color: Colors.black.withValues(alpha: wp.dimming.clamp(0.0, 1.0)),
              ),
            ],
          );
        }
        wallpaperBg = img;
      } else {
        wallpaperBg = Container(color: wp.backgroundColor);
      }
    } else if (wp.type == 'color') {
      wallpaperBg = Container(color: wp.backgroundColor);
    } else if (wp.fourCornerGradient != null) {
      wallpaperBg = CustomPaint(
        painter: FourCornerGradientPainter(
          topLeft: wp.fourCornerGradient!.topLeft,
          topRight: wp.fourCornerGradient!.topRight,
          bottomLeft: wp.fourCornerGradient!.bottomLeft,
          bottomRight: wp.fourCornerGradient!.bottomRight,
        ),
        child: const SizedBox.expand(),
      );
    } else {
      wallpaperBg = Container(color: wp.backgroundColor);
    }

    Widget? patternOverlay;
    if (wp.patternOpacity > 0) {
      final double buttonPatternOpacity = (wp.patternOpacity * 1.6).clamp(0.24, 0.60);
      Widget? svgWidget;
      if (!kIsWeb && wp.customSvgPath != null && File(wp.customSvgPath!).existsSync()) {
        svgWidget = SvgPicture.file(
          File(wp.customSvgPath!) as dynamic,
          width: 210.0,
          height: 210.0,
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            wp.patternColor.withValues(alpha: buttonPatternOpacity),
            BlendMode.srcIn,
          ),
        );
      } else if (wp.assetSvgPath != null && wp.assetSvgPath!.isNotEmpty) {
        svgWidget = SvgPicture.asset(
          wp.assetSvgPath!,
          width: 210.0,
          height: 210.0,
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            wp.patternColor.withValues(alpha: buttonPatternOpacity),
            BlendMode.srcIn,
          ),
        );
      }
      if (svgWidget != null) {
        patternOverlay = OverflowBox(
          minWidth: 0.0,
          maxWidth: 210.0,
          minHeight: 0.0,
          maxHeight: 210.0,
          child: svgWidget,
        );
      }
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Theme button bubble: wallpaper background + 2 empty message ovals
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 78,
              height: 68,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? activePrimary : (Theme.of(context).brightness == Brightness.dark ? Colors.white24 : Colors.black12),
                  width: isSelected ? 2.5 : 1.0,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: activePrimary.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13.5),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Wallpaper
                    wallpaperBg,
                    if (patternOverlay != null) patternOverlay,

                    // Two empty message ovals showing bubble colors
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Top: Incoming empty oval
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: 38,
                              height: 14,
                              decoration: BoxDecoration(
                                color: theme.palette.chatBubbleIncoming,
                                borderRadius: BorderRadius.circular(7),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Bottom: Outgoing empty oval
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              width: 38,
                              height: 14,
                              decoration: BoxDecoration(
                                color: (theme.palette.chatBubbleOutgoingGradient != null &&
                                        theme.palette.chatBubbleOutgoingGradient!.length >= 2)
                                    ? null
                                    : theme.palette.chatBubbleOutgoing,
                                gradient: (theme.palette.chatBubbleOutgoingGradient != null &&
                                        theme.palette.chatBubbleOutgoingGradient!.length >= 2)
                                    ? LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: theme.palette.chatBubbleOutgoingGradient!,
                                      )
                                    : null,
                                borderRadius: BorderRadius.circular(7),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Selected checkmark badge
                    if (isSelected)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: activePrimary,
                            shape: BoxShape.circle,
                          ),
                          child: iconoir.Check(
                            width: 11,
                            height: 11,
                            color: theme.palette.onPrimary,
                          ),
                        ),
                      ),

                    // Cloud synced indicator
                    if (theme.isCloudSaved)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const iconoir.CloudCheck(
                            width: 10,
                            height: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Theme Name
            Text(
              theme.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? activePrimary : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
