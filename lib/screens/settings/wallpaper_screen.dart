import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ios_color_picker/show_ios_color_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../models/theav_theme.dart';
import '../../services/theav_theme_service.dart';
import '../../services/wallpaper_provider.dart';
import '../../theme/theme_provider.dart';
import '../../widgets/theme/chat_preview_card.dart';
import '../../widgets/theme/four_corner_gradient.dart';
import '../../l10n/app_localizations.dart';

/// Full-featured Wallpaper Constructor supporting SVG patterns, 4-corner gradients,
/// solid colors, gallery photos, and gyroscope-driven motion parallax.
class WallpaperScreen extends StatefulWidget {
  final TheavWallpaper? initialWallpaper;
  final ValueChanged<TheavWallpaper>? onWallpaperConfigured;

  const WallpaperScreen({
    Key? key,
    this.initialWallpaper,
    this.onWallpaperConfigured,
  }) : super(key: key);

  @override
  State<WallpaperScreen> createState() => _WallpaperScreenState();
}

class _WallpaperScreenState extends State<WallpaperScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TheavWallpaper _currentWallpaper;
  bool _isLoading = false;
  bool _isMobile = false;

  @override
  void initState() {
    super.initState();
    _isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    final activeTheme = TheavThemeService().activeLightTheme;
    var wp = widget.initialWallpaper ?? activeTheme.wallpaper;

    // Normalize: ensure gradient and pattern are unified
    if (wp.type != 'image') {
      final grad = wp.fourCornerGradient ??
          (wp.type == 'color'
              ? FourCornerGradient.fromSingleColor(wp.backgroundColor)
              : FourCornerGradient.defaultClassic);
      wp = wp.copyWith(
        type: 'pattern',
        fourCornerGradient: grad,
        patternName: wp.type == 'gradient4' || wp.type == 'color' ? 'none' : (wp.patternName ?? 'flowers'),
        patternColor: wp.patternColor ?? const Color(0xFF5A8FB8),
        patternOpacity: wp.patternOpacity > 0 ? wp.patternOpacity : 0.15,
      );
    }
    _currentWallpaper = wp;

    _tabController = TabController(length: 2, vsync: this);
    if (_currentWallpaper.type == 'image') {
      _tabController.index = 1;
    } else {
      _tabController.index = 0;
    }

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == 0 && _currentWallpaper.type == 'image') {
        setState(() {
          _currentWallpaper = _currentWallpaper.copyWith(type: 'pattern');
        });
      } else if (_tabController.index == 1 && _currentWallpaper.type != 'image') {
        setState(() {
          _currentWallpaper = _currentWallpaper.copyWith(type: 'image');
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final wallpaperDir = Directory('${appDir.path}/wallpapers');
    if (!await wallpaperDir.exists()) {
      await wallpaperDir.create(recursive: true);
    }

    final localFile = File('${wallpaperDir.path}/chat_wallpaper_${DateTime.now().millisecondsSinceEpoch}.png');
    await localFile.writeAsBytes(await image.readAsBytes());

    setState(() {
      _currentWallpaper = _currentWallpaper.copyWith(
        type: 'image',
        imagePath: localFile.path,
      );
    });
  }

  Future<void> _applyWallpaper() async {
    setState(() => _isLoading = true);

    try {
      if (widget.onWallpaperConfigured != null) {
        widget.onWallpaperConfigured!(_currentWallpaper);
        Navigator.pop(context);
        return;
      }

      final themeProvider = context.read<ThemeProvider>();
      final isDark = themeProvider.themeMode == ThemeMode.dark ||
          (themeProvider.themeMode == ThemeMode.system &&
              MediaQuery.platformBrightnessOf(context) == Brightness.dark);
      final currentTheme = isDark ? themeProvider.activeDarkTheme : themeProvider.activeLightTheme;

      final updatedTheme = currentTheme.copyWith(wallpaper: _currentWallpaper);
      await themeProvider.setActiveTheme(updatedTheme);
      await TheavThemeService().saveTheme(updatedTheme, saveToCloud: false);

      // Also sync WallpaperProvider
      if (_currentWallpaper.type == 'image' && _currentWallpaper.imagePath != null) {
        await context.read<WallpaperProvider>().setWallpaper(_currentWallpaper.imagePath!);
      } else {
        await context.read<WallpaperProvider>().removeWallpaper(syncToServer: false);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Обои успешно применены!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error applying wallpaper: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка применения обоев: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final themeProvider = context.watch<ThemeProvider>();
    final activeTheme = (themeProvider.themeMode == ThemeMode.dark)
        ? themeProvider.activeDarkTheme
        : themeProvider.activeLightTheme;
    final previewTheme = activeTheme.copyWith(wallpaper: _currentWallpaper);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('wallpaper_title')),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _applyWallpaper,
            child: Text(
              l10n.translate('wallpaper_apply'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Live Sticky Interactive Preview Card
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: ChatPreviewCard(
              theme: previewTheme,
              height: 200,
            ),
          ),

          // 2. Segmented Mode Tabs: [ Pattern & Gradient | Gallery Photo ]
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF0088CC),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF0088CC),
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: [
                Tab(
                  icon: const Icon(Icons.palette_outlined, size: 20),
                  text: l10n.translate('wallpaper_mode_pattern'),
                ),
                Tab(
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  text: l10n.translate('wallpaper_mode_gallery'),
                ),
              ],
              onTap: (index) {
                if (index == 0) {
                  setState(() => _currentWallpaper = _currentWallpaper.copyWith(type: 'pattern'));
                } else {
                  setState(() => _currentWallpaper = _currentWallpaper.copyWith(type: 'image'));
                }
              },
            ),
          ),
          const SizedBox(height: 12),

          // 3. Tab contents
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (_currentWallpaper.type != 'image')
                  _buildPatternAndGradientControls(context, l10n)
                else
                  _buildImageControls(l10n),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // === Unified Pattern & 4-Corner Mesh Gradient Controls ===
  Widget _buildPatternAndGradientControls(BuildContext context, AppLocalizations l10n) {
    final patterns = [
      {'id': 'none', 'name': 'Без узора', 'icon': Icons.texture},
      {'id': 'space', 'name': l10n.translate('wallpaper_pattern_space'), 'icon': Icons.public},
      {'id': 'science', 'name': l10n.translate('wallpaper_pattern_science'), 'icon': Icons.science},
      {'id': 'flowers', 'name': l10n.translate('wallpaper_pattern_flowers'), 'icon': Icons.local_florist},
      {'id': 'love', 'name': l10n.translate('wallpaper_pattern_love'), 'icon': Icons.favorite},
      {'id': 'christmas', 'name': l10n.translate('wallpaper_pattern_christmas'), 'icon': Icons.ac_unit},
    ];

    final isPatternActive = _currentWallpaper.patternName != null &&
        _currentWallpaper.patternName != 'none';

    final effectiveGradient = _currentWallpaper.fourCornerGradient ??
        FourCornerGradient.defaultClassic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Motion Toggle (Mobile platforms only)
        if (_isMobile) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SwitchListTile(
                title: Text(
                  l10n.translate('wallpaper_motion'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: Text(
                  l10n.translate('wallpaper_motion_desc'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                secondary: const Icon(Icons.screen_rotation, color: Color(0xFF0088CC)),
                value: _currentWallpaper.motionEnabled,
                activeColor: const Color(0xFF0088CC),
                onChanged: (val) {
                  setState(() {
                    _currentWallpaper = _currentWallpaper.copyWith(motionEnabled: val);
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 1. Pattern selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Узор фона',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700]),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: patterns.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final p = patterns[index];
              final isSel = (_currentWallpaper.patternName ?? 'none') == p['id'];

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _currentWallpaper = _currentWallpaper.copyWith(
                      type: 'pattern',
                      patternName: p['id'] as String,
                    );
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 78,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSel ? const Color(0xFF0088CC) : Colors.grey.withValues(alpha: 0.3),
                      width: isSel ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        p['icon'] as IconData,
                        color: isSel ? const Color(0xFF0088CC) : Colors.grey[600],
                        size: 26,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p['name'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                          color: isSel ? const Color(0xFF0088CC) : null,
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

        // Pattern Color & Opacity (only if pattern chosen)
        if (isPatternActive) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _ColorSelectTile(
                    label: l10n.translate('wallpaper_pattern_color'),
                    color: _currentWallpaper.patternColor ?? const Color(0xFF5A8FB8),
                    onChanged: (c) => setState(() => _currentWallpaper = _currentWallpaper.copyWith(patternColor: c)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.translate('wallpaper_pattern_opacity'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                    ),
                    Text('${(_currentWallpaper.patternOpacity * 100).round()}%'),
                  ],
                ),
                Slider(
                  value: _currentWallpaper.patternOpacity.clamp(0.04, 0.50),
                  min: 0.04,
                  max: 0.50,
                  divisions: 46,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (val) {
                    setState(() => _currentWallpaper = _currentWallpaper.copyWith(patternOpacity: val));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 2. 4-Corner Mesh Gradient (bound underneath pattern)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Градиент фона (4 угла)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700]),
              ),
              const SizedBox(height: 2),
              Text(
                'Настройте цвета 4 углов или выберите готовый пресет',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        FourCornerGradientSelector(
          gradient: effectiveGradient,
          patternSvgPath: _currentWallpaper.assetSvgPath,
          patternColor: _currentWallpaper.patternColor,
          patternOpacity: _currentWallpaper.patternOpacity,
          onChanged: (newGrad) {
            setState(() {
              _currentWallpaper = _currentWallpaper.copyWith(
                type: 'pattern',
                fourCornerGradient: newGrad,
                backgroundColor: newGrad.topLeft,
              );
            });
          },
        ),
      ],
    );
  }

  // === Gallery Image Controls ===
  Widget _buildImageControls(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0088CC),
                side: const BorderSide(color: Color(0xFF0088CC), width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(l10n.translate('chat_open_gallery')),
              onPressed: _pickImage,
            ),
          ),
          const SizedBox(height: 16),

          // Blur slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.translate('wallpaper_blur'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700]),
              ),
              Text('${_currentWallpaper.blurRadius.toStringAsFixed(1)} px'),
            ],
          ),
          Slider(
            value: _currentWallpaper.blurRadius,
            min: 0.0,
            max: 25.0,
            divisions: 25,
            activeColor: const Color(0xFF0088CC),
            onChanged: (val) => setState(() => _currentWallpaper = _currentWallpaper.copyWith(blurRadius: val)),
          ),
          const SizedBox(height: 8),

          // Dimming slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.translate('wallpaper_dimming'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700]),
              ),
              Text('${(_currentWallpaper.dimming * 100).round()}%'),
            ],
          ),
          Slider(
            value: _currentWallpaper.dimming,
            min: 0.0,
            max: 0.75,
            divisions: 15,
            activeColor: const Color(0xFF0088CC),
            onChanged: (val) => setState(() => _currentWallpaper = _currentWallpaper.copyWith(dimming: val)),
          ),
        ],
      ),
    );
  }
}

class _ColorSelectTile extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  const _ColorSelectTile({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showColorPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    IOSColorPickerController().showIOSCustomColorPicker(
      context: context,
      startingColor: color.withValues(alpha: 1.0),
      onColorChanged: (c) {
        onChanged(c.withValues(alpha: 1.0));
      },
    );
  }
}
