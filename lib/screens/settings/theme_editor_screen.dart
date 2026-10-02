import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/theav_theme.dart';
import '../../services/theav_theme_service.dart';
import '../../theme/theme_provider.dart';
import '../../widgets/theme/chat_preview_card.dart';
import '../../l10n/app_localizations.dart';
import 'wallpaper_screen.dart';

/// Visual editor for creating or customizing Theaver themes.
class ThemeEditorScreen extends StatefulWidget {
  final TheavTheme? themeToEdit;

  const ThemeEditorScreen({
    Key? key,
    this.themeToEdit,
  }) : super(key: key);

  @override
  State<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends State<ThemeEditorScreen> {
  late TextEditingController _nameController;
  late TheavTheme _currentTheme;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final active = TheavThemeService().activeLightTheme;
    if (widget.themeToEdit != null) {
      _currentTheme = widget.themeToEdit!;
    } else {
      _currentTheme = active.copyWith(
        id: 'theme_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Моя новая тема',
        author: 'User',
        isBuiltIn: false,
        isCloudSaved: false,
      );
    }

    _nameController = TextEditingController(text: _currentTheme.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveTheme() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название темы')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final themeToSave = _currentTheme.copyWith(name: name);

    try {
      await TheavThemeService().saveTheme(themeToSave, saveToCloud: true);
      if (mounted) {
        context.read<ThemeProvider>().setActiveTheme(themeToSave);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Тема сохранена и применена!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _exportTheme() async {
    try {
      final bytes = await TheavThemeService().exportThemePackage(_currentTheme);
      final tempDir = await getTemporaryDirectory();
      final cleanName = _currentTheme.name.replaceAll(RegExp(r'[^\w\s]+'), '').trim().replaceAll(' ', '_');
      final file = File('${tempDir.path}/${cleanName.isEmpty ? "theme" : cleanName}.theavtheme');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Тема Theaver: ${_currentTheme.name}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта темы: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEditing = widget.themeToEdit != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? l10n.translate('theme_edit') : l10n.translate('theme_create_new')),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: l10n.translate('theme_export'),
            onPressed: _exportTheme,
          ),
          TextButton(
            onPressed: _isSaving ? null : _saveTheme,
            child: Text(
              l10n.translate('theme_apply'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
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
              theme: _currentTheme,
              height: 220,
            ),
          ),

          // 2. Theme Name Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.translate('theme_name'),
                prefixIcon: const Icon(Icons.palette_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onChanged: (val) {
                setState(() => _currentTheme = _currentTheme.copyWith(name: val));
              },
            ),
          ),
          const SizedBox(height: 16),

          // 3. Brightness switch (Light / Dark base)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SwitchListTile(
                title: Text(
                  _currentTheme.isDark ? l10n.translate('theme_dark') : l10n.translate('theme_light'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                secondary: Icon(
                  _currentTheme.isDark ? Icons.dark_mode : Icons.light_mode,
                  color: const Color(0xFF0088CC),
                ),
                value: _currentTheme.isDark,
                activeColor: const Color(0xFF0088CC),
                onChanged: (val) {
                  setState(() {
                    _currentTheme = _currentTheme.copyWith(
                      isDark: val,
                      palette: _currentTheme.palette.copyWith(
                        background: val ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF),
                        surface: val ? const Color(0xFF2C2C2E) : const Color(0xFFF5F5F5),
                        onSurface: val ? const Color(0xFFE5E5EA) : const Color(0xFF1C1C1E),
                        appBarBackground: val ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF),
                        appBarForeground: val ? Colors.white : const Color(0xFF1C1C1E),
                      ),
                    );
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 4. Bubble Corner Radius Slider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.translate('theme_bubble_radius'),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text('${_currentTheme.bubbleRadius.round()} px'),
                    ],
                  ),
                  Slider(
                    value: _currentTheme.bubbleRadius,
                    min: 0,
                    max: 24,
                    divisions: 24,
                    activeColor: const Color(0xFF0088CC),
                    onChanged: (val) {
                      setState(() => _currentTheme = _currentTheme.copyWith(bubbleRadius: val));
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 5. Palette Colors Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Цвета оформления',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700]),
            ),
          ),
          const SizedBox(height: 8),

          _buildColorTile(
            title: l10n.translate('theme_primary_color'),
            color: _currentTheme.palette.primary,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(primary: c),
                )),
          ),
          _buildColorTile(
            title: l10n.translate('theme_bubble_outgoing'),
            color: _currentTheme.palette.chatBubbleOutgoing,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatBubbleOutgoing: c),
                )),
          ),
          _buildColorTile(
            title: '${l10n.translate('theme_bubble_outgoing')} — ${l10n.translate('theme_bubble_text')}',
            color: _currentTheme.palette.chatBubbleOutgoingText,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatBubbleOutgoingText: c),
                )),
          ),
          _buildColorTile(
            title: l10n.translate('theme_bubble_incoming'),
            color: _currentTheme.palette.chatBubbleIncoming,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatBubbleIncoming: c),
                )),
          ),
          _buildColorTile(
            title: '${l10n.translate('theme_bubble_incoming')} — ${l10n.translate('theme_bubble_text')}',
            color: _currentTheme.palette.chatBubbleIncomingText,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatBubbleIncomingText: c),
                )),
          ),

          const SizedBox(height: 16),

          // 6. Wallpaper Customization Tile
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListTile(
              tileColor: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              leading: const Icon(Icons.wallpaper, color: Color(0xFF0088CC)),
              title: Text(l10n.translate('wallpaper_title')),
              subtitle: Text(
                _currentTheme.wallpaper.type == 'pattern'
                    ? 'Узор: ${_currentTheme.wallpaper.patternName ?? "space"}'
                    : _currentTheme.wallpaper.type == 'gradient4'
                        ? '4-точечный градиент'
                        : 'Цвет/Фото',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WallpaperScreen(
                      initialWallpaper: _currentTheme.wallpaper,
                      onWallpaperConfigured: (newWp) {
                        setState(() => _currentTheme = _currentTheme.copyWith(wallpaper: newWp));
                      },
                    ),
                  ),
                );
              },
            ),
          ),

          // 7. Delete Theme Button (if editing existing custom theme)
          if (isEditing && !_currentTheme.isBuiltIn) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.translate('theme_delete')),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l10n.translate('theme_delete')),
                      content: Text(l10n.translate('theme_delete_confirm')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Удалить', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await TheavThemeService().deleteTheme(_currentTheme.id);
                    if (mounted) Navigator.pop(context);
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildColorTile({
    required String title,
    required Color color,
    required ValueChanged<Color> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          title: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
          trailing: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
              ],
            ),
          ),
          onTap: () => _pickColor(context, title, color, onChanged),
        ),
      ),
    );
  }

  void _pickColor(BuildContext context, String title, Color currentColor, ValueChanged<Color> onChanged) {
    final palette = [
      const Color(0xFF0088CC),
      const Color(0xFF5CB8E6),
      const Color(0xFF0288D1),
      const Color(0xFF0D47A1),
      const Color(0xFF2E7D32),
      const Color(0xFF4CAF50),
      const Color(0xFF8BC34A),
      const Color(0xFFE91E63),
      const Color(0xFF9C27B0),
      const Color(0xFF673AB7),
      const Color(0xFF7C4DFF),
      const Color(0xFFFF9800),
      const Color(0xFFFF5722),
      const Color(0xFFF2F2F7),
      const Color(0xFF2C2C2E),
      const Color(0xFF1C1C1E),
      const Color(0xFF000000),
      const Color(0xFFFFFFFF),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: palette.map((c) {
                    final isSel = c.toARGB32() == currentColor.toARGB32();
                    return GestureDetector(
                      onTap: () {
                        onChanged(c);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSel ? const Color(0xFF0088CC) : Colors.grey.withValues(alpha: 0.3),
                            width: isSel ? 3 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
                          ],
                        ),
                        child: isSel
                            ? Icon(
                                Icons.check,
                                size: 20,
                                color: c.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
