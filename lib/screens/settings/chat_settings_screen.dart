import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/theav_theme_service.dart';
import '../../services/wallpaper_provider.dart';
import '../../theme/theme_provider.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../widgets/theme/chat_preview_card.dart';
import '../../widgets/theme/theme_preview_sheet.dart';
import '../../l10n/app_localizations.dart';
import 'theme_editor_screen.dart';
import 'wallpaper_screen.dart';
import '../../utils/swipe_back_route.dart';

/// Screen for chat settings: wallpaper constructor, themes carousel,
/// in-app theme editor, .theavtheme import/export, and Liquid Glass design controls.
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
          const SnackBar(content: Text('Пожалуйста, выберите файл с расширением .theavtheme')),
        );
        return;
      }

      final bytes = await file.readAsBytes();
      final imported = await TheavThemeService().importThemePackage(bytes);

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
          SnackBar(content: Text('Ошибка импорта темы: $e')),
        );
      }
    }
  }

  Future<void> _exportActiveTheme(BuildContext context) async {
    final l10n = context.l10n;
    try {
      final themeProvider = context.read<ThemeProvider>();
      final isDark = themeProvider.themeMode == ThemeMode.dark;
      final activeTheme = isDark ? themeProvider.activeDarkTheme : themeProvider.activeLightTheme;

      final bytes = await TheavThemeService().exportThemePackage(activeTheme);
      final tempDir = await getTemporaryDirectory();
      final cleanName = activeTheme.name.replaceAll(RegExp(r'[^\w\s]+'), '').trim().replaceAll(' ', '_');
      final file = File('${tempDir.path}/${cleanName.isEmpty ? "theme" : cleanName}.theavtheme');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Тема Theaver: ${activeTheme.name}',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.themeMode == ThemeMode.dark;
    final activeTheme = isDark ? themeProvider.activeDarkTheme : themeProvider.activeLightTheme;
    final allThemes = TheavThemeService().getAllThemes();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('settings_chat_settings')),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: l10n.translate('theme_import'),
            onPressed: () => _importTheme(context),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: l10n.translate('theme_export'),
            onPressed: () => _exportActiveTheme(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          // 1. Live Sticky Interactive Preview Card
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ChatPreviewCard(
              theme: activeTheme,
              height: 210,
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
                  icon: const Icon(Icons.add, size: 18),
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
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: allThemes.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
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
                    child: Container(
                      width: 84,
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.3),
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline, color: Theme.of(context).primaryColor, size: 28),
                          const SizedBox(height: 6),
                          Text(
                            'Создать',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final t = allThemes[index];
                final isSelected = t.id == activeTheme.id;

                return GestureDetector(
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
                      Navigator.push(
                        context,
                        SwipeBackPageRoute(builder: (_) => ThemeEditorScreen(themeToEdit: t)),
                      );
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 86,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF0088CC) : Colors.grey.withValues(alpha: 0.25),
                        width: isSelected ? 2.5 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Thumbnail of theme palette
                        Stack(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: t.palette.primary,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
                                ],
                              ),
                              child: Center(
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: t.palette.chatBubbleOutgoing,
                                  ),
                                ),
                              ),
                            ),
                            if (t.isCloudSaved)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.cloud_done, size: 12, color: Color(0xFF0088CC)),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t.name,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            color: isSelected ? const Color(0xFF0088CC) : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // 3. Wallpaper constructor Tile
          ListTile(
            leading: const Icon(Icons.wallpaper, color: Color(0xFF0088CC)),
            title: Text(l10n.translate('wallpaper_title')),
            subtitle: Text(
              activeTheme.wallpaper.type == 'pattern'
                  ? (activeTheme.wallpaper.patternName != null && activeTheme.wallpaper.patternName != 'none'
                      ? 'Узор: ${activeTheme.wallpaper.patternName}, 4-точечный градиент'
                      : '4-точечный градиент фона')
                  : activeTheme.wallpaper.type == 'image'
                      ? 'Фото из галереи'
                      : 'Обои чата',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                SwipeBackPageRoute(builder: (_) => const WallpaperScreen()),
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
                    activeColor: const Color(0xFF0088CC),
                    onChanged: (val) {
                      final updated = activeTheme.copyWith(bubbleRadius: val);
                      themeProvider.setActiveTheme(updated);
                      TheavThemeService().saveTheme(updated, saveToCloud: false);
                    },
                  ),
                ],
              ),
            ),
          ),

          // 5. Light / Dark / System Switcher
          Column(
            children: [
              ListTile(
                leading: Icon(
                  Icons.dark_mode,
                  color: themeProvider.themeMode == ThemeMode.dark
                      ? const Color(0xFF0088CC)
                      : themeProvider.themeMode == ThemeMode.light
                          ? const Color(0xFF0088CC)
                          : Colors.grey,
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
                      icon: Icons.light_mode,
                      label: l10n.translate('theme_light'),
                      isSelected: themeProvider.themeMode == ThemeMode.light,
                      onTap: () => themeProvider.setToLight(),
                    ),
                    const SizedBox(width: 8),
                    _ThemeButton(
                      icon: Icons.dark_mode,
                      label: l10n.translate('theme_dark'),
                      isSelected: themeProvider.themeMode == ThemeMode.dark,
                      onTap: () => themeProvider.setToDark(),
                    ),
                    const SizedBox(width: 8),
                    _ThemeButton(
                      icon: Icons.brightness_auto,
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

          // 6. Liquid Glass Design Controls
          Consumer<LiquidGlassProvider>(
            builder: (context, provider, _) {
              final isSupported = provider.isSupported;
              final mode = provider.mode;

              return Column(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.auto_awesome,
                      color: isSupported ? const Color(0xFF0088CC) : Colors.grey,
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
                            icon: Icons.block,
                            label: l10n.translate('settings_glass_off'),
                            isSelected: mode == GlassMode.disabled,
                            onTap: () => provider.setMode(GlassMode.disabled),
                          ),
                          const SizedBox(width: 8),
                          _GlassModeButton(
                            icon: Icons.auto_awesome_outlined,
                            label: l10n.translate('settings_glass_lite'),
                            isSelected: mode == GlassMode.lite,
                            onTap: () => provider.setMode(GlassMode.lite),
                          ),
                          const SizedBox(width: 8),
                          _GlassModeButton(
                            icon: Icons.auto_awesome,
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
                            'Угол освещения: ${provider.manualLightAngle.round()}°',
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
                        activeColor: const Color(0xFF0088CC),
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
                            'Степень размытия (блюр): ${provider.blur.toStringAsFixed(1)}',
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
                        activeColor: const Color(0xFF0088CC),
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
      ),
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

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0088CC).withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF0088CC) : Colors.grey.withValues(alpha: 0.3),
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF0088CC) : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? const Color(0xFF0088CC) : theme.colorScheme.onSurface.withValues(alpha: 0.6),
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

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0088CC).withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF0088CC) : Colors.grey.withValues(alpha: 0.3),
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF0088CC) : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? const Color(0xFF0088CC) : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
