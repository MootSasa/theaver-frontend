import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../theme/theme_provider.dart';
import '../../l10n/app_localizations.dart';
import 'wallpaper_screen.dart';
import '../../utils/swipe_back_route.dart';

/// Экран настроек чатов — содержит обои, переключатель Liquid Glass дизайна
/// и переключатель темы (светлая/тёмная/системная).
class ChatSettingsScreen extends StatelessWidget {
  const ChatSettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('settings_chat_settings')),
      ),
      body: ListView(
        children: [
          // Wallpaper
          ListTile(
            leading: const Icon(Icons.wallpaper, color: Color(0xFF0088CC)),
            title: Text(l10n.translate('wallpaper_title')),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                SwipeBackPageRoute(builder: (_) => const WallpaperScreen()),
              );
            },
          ),

          // Liquid Glass Design — выбор режима (только для поддерживаемых платформ)
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
                      style: TextStyle(
                        color: isSupported ? null : Colors.grey,
                      ),
                    ),
                    subtitle: Text(
                      isSupported
                          ? l10n.translate('settings_liquid_glass_desc')
                          : l10n.translate('settings_liquid_glass_unsupported'),
                      style: TextStyle(
                        fontSize: 12,
                        color: isSupported ? Colors.grey[600] : Colors.grey,
                      ),
                    ),
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
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _GlassModeButton(
                            icon: Icons.screen_rotation,
                            label: 'Гироскоп',
                            isSelected:
                                provider.lightAngleMode == LightAngleMode.gyroscope,
                            onTap: () =>
                                provider.setLightAngleMode(LightAngleMode.gyroscope),
                          ),
                          const SizedBox(width: 8),
                          _GlassModeButton(
                            icon: Icons.tune,
                            label: 'Вручную',
                            isSelected:
                                provider.lightAngleMode == LightAngleMode.manual,
                            onTap: () =>
                                provider.setLightAngleMode(LightAngleMode.manual),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (provider.lightAngleMode == LightAngleMode.gyroscope)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Builder(
                          builder: (context) {
                            final reduceMotion =
                                MediaQuery.disableAnimationsOf(context);
                            if (reduceMotion) {
                              return Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 16, color: Colors.orange[700]),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'В системе включено «Уменьшение движения»: гироскоп отключён (фиксированный угол 62°)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.orange[700],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Text(
                              'Блики плавно адаптируются при наклоне устройства',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            );
                          },
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Угол освещения: ${provider.manualLightAngle.round()}°',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Slider(
                        value: provider.manualLightAngle,
                        min: 0,
                        max: 360,
                        divisions: 72,
                        activeColor: const Color(0xFF0088CC),
                        label: '${provider.manualLightAngle.round()}°',
                        onChanged: (val) => provider.setManualLightAngle(val),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            ActionChip(
                              label: const Text('По умолчанию (62°)',
                                  style: TextStyle(fontSize: 11)),
                              onPressed: () => provider.setManualLightAngle(62),
                            ),
                            ActionChip(
                              label: const Text('Сверху (90°)',
                                  style: TextStyle(fontSize: 11)),
                              onPressed: () => provider.setManualLightAngle(90),
                            ),
                            ActionChip(
                              label: const Text('Слева (180°)',
                                  style: TextStyle(fontSize: 11)),
                              onPressed: () => provider.setManualLightAngle(180),
                            ),
                            ActionChip(
                              label: const Text('Снизу (270°)',
                                  style: TextStyle(fontSize: 11)),
                              onPressed: () => provider.setManualLightAngle(270),
                            ),
                            ActionChip(
                              label: const Text('Справа (0°)',
                                  style: TextStyle(fontSize: 11)),
                              onPressed: () => provider.setManualLightAngle(0),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Степень размытия (блюр): ${provider.blur.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Slider(
                      value: provider.blur,
                      min: 0,
                      max: 30,
                      divisions: 60,
                      activeColor: const Color(0xFF0088CC),
                      label: provider.blur.toStringAsFixed(1),
                      onChanged: (val) => provider.setBlur(val),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          ActionChip(
                            label: const Text('Слабое (4)',
                                style: TextStyle(fontSize: 11)),
                            onPressed: () => provider.setBlur(4.0),
                          ),
                          ActionChip(
                            label: const Text('Стандарт (8)',
                                style: TextStyle(fontSize: 11)),
                            onPressed: () => provider.setBlur(8.0),
                          ),
                          ActionChip(
                            label: const Text('Сильное (16)',
                                style: TextStyle(fontSize: 11)),
                            onPressed: () => provider.setBlur(16.0),
                          ),
                          ActionChip(
                            label: const Text('Максимум (24)',
                                style: TextStyle(fontSize: 11)),
                            onPressed: () => provider.setBlur(24.0),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              );
            },
          ),

          // Переключатель темы
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              return Column(
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
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
                          isSelected:
                              themeProvider.themeMode == ThemeMode.system,
                          onTap: () => themeProvider.setToSystem(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
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

/// Кнопка выбора темы (светлая/тёмная/системная)
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
            color: isSelected
                ? const Color(0xFF0088CC).withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF0088CC)
                  : Colors.grey.withValues(alpha: 0.3),
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? const Color(0xFF0088CC)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? const Color(0xFF0088CC)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Кнопка выбора режима стекла (выкл / облегчённый / полный)
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
            color: isSelected
                ? const Color(0xFF0088CC).withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF0088CC)
                  : Colors.grey.withValues(alpha: 0.3),
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? const Color(0xFF0088CC)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? const Color(0xFF0088CC)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
