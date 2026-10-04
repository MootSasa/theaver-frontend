import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ios_color_picker/show_ios_color_picker.dart';
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
  final IOSColorPickerController _colorPickerController = IOSColorPickerController();
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
    _colorPickerController.dispose();
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
        final savedTheme = TheavThemeService().getAllThemes().firstWhere(
          (t) => t.id == themeToSave.id,
          orElse: () => themeToSave,
        );
        context.read<ThemeProvider>().setActiveTheme(savedTheme);
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
              height: 230,
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
                  color: _currentTheme.palette.primary,
                ),
                value: _currentTheme.isDark,
                activeColor: _currentTheme.palette.primary,
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
                    activeColor: _currentTheme.palette.primary,
                    onChanged: (val) {
                      setState(() => _currentTheme = _currentTheme.copyWith(bubbleRadius: val));
                    },
                  ),
                ],
              ),
            ),
          ),

          // 5. Palette Colors Section (Categorized)
          _buildSectionHeader('Основные цвета'),
          _buildColorTile(
            title: l10n.translate('theme_primary_color'),
            color: _currentTheme.palette.primary,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(primary: c),
                )),
          ),
          _buildColorTile(
            title: 'Фон экрана',
            color: _currentTheme.palette.background,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(background: c),
                )),
          ),
          _buildColorTile(
            title: 'Фон карточек и списков',
            color: _currentTheme.palette.surface,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(surface: c),
                )),
          ),
          _buildColorTile(
            title: 'Основной текст',
            color: _currentTheme.palette.onSurface,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(onSurface: c),
                )),
          ),
          _buildColorTile(
            title: 'Шапка экрана (AppBar)',
            color: _currentTheme.palette.appBarBackground,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(appBarBackground: c),
                )),
          ),

          _buildSectionHeader('Исходящие сообщения'),
          _buildBubbleFillTypeToggle(),
          if (_isOutgoingGradient) ...[
            _buildGradientEditor(),
          ] else ...[
            _buildColorTile(
              title: l10n.translate('theme_bubble_outgoing'),
              color: _currentTheme.palette.chatBubbleOutgoing,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatBubbleOutgoing: c),
                  )),
            ),
          ],
          _buildColorTile(
            title: '${l10n.translate('theme_bubble_outgoing')} — ${l10n.translate('theme_bubble_text')}',
            color: _currentTheme.palette.chatBubbleOutgoingText,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatBubbleOutgoingText: c),
                )),
          ),
          _buildColorTile(
            title: 'Время и галочки статуса',
            color: _currentTheme.palette.chatBubbleOutgoingSubtext,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatBubbleOutgoingSubtext: c),
                )),
          ),
          _buildColorTile(
            title: 'Цвет ссылок в сообщении',
            color: _currentTheme.palette.chatBubbleOutgoingLink,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatBubbleOutgoingLink: c),
                )),
          ),

          _buildSectionHeader('Входящие сообщения'),
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
          _buildColorTile(
            title: 'Время сообщения',
            color: _currentTheme.palette.chatBubbleIncomingSubtext,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatBubbleIncomingSubtext: c),
                )),
          ),
          _buildColorTile(
            title: 'Цвет ссылок в сообщении',
            color: _currentTheme.palette.chatBubbleIncomingLink,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatBubbleIncomingLink: c),
                )),
          ),

          _buildSectionHeader('Панель ввода'),
          _buildColorTile(
            title: 'Фон поля ввода',
            color: _currentTheme.palette.chatInputBackground,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatInputBackground: c),
                )),
          ),
          _buildColorTile(
            title: 'Цвет вводимого текста',
            color: _currentTheme.palette.chatInputText,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatInputText: c),
                )),
          ),
          _buildColorTile(
            title: 'Иконки и кнопки панели',
            color: _currentTheme.palette.chatInputButtons,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatInputButtons: c),
                )),
          ),
          _buildColorTile(
            title: 'Кнопка отправки',
            color: _currentTheme.palette.chatSendButton,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatSendButton: c),
                )),
          ),

          _buildSectionHeader('Служебные элементы'),
          _buildColorTile(
            title: 'Плашка даты в чате',
            color: _currentTheme.palette.chatDateBadge,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatDateBadge: c),
                )),
          ),
          _buildColorTile(
            title: 'Текст даты в чате',
            color: _currentTheme.palette.chatDateBadgeText,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatDateBadgeText: c),
                )),
          ),
          _buildColorTile(
            title: 'Бейдж непрочитанных',
            color: _currentTheme.palette.unreadBadge,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(unreadBadge: c),
                )),
          ),
          _buildColorTile(
            title: 'Текст бейджа непрочитанных',
            color: _currentTheme.palette.unreadBadgeText,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(unreadBadgeText: c),
                )),
          ),
          _buildColorTile(
            title: 'Индикатор «в сети»',
            color: _currentTheme.palette.onlineIndicator,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(onlineIndicator: c),
                )),
          ),
          _buildColorTile(
            title: 'Второстепенный текст',
            color: _currentTheme.palette.subtext,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(subtext: c),
                )),
          ),
          _buildColorTile(
            title: 'Разделители строк',
            color: _currentTheme.palette.divider,
            onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(divider: c),
                )),
          ),

          const SizedBox(height: 16),

          // 6. Wallpaper Customization Tile
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListTile(
              tileColor: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              leading: Icon(Icons.wallpaper, color: _currentTheme.palette.primary),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 18, bottom: 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[400]
              : Colors.grey[700],
        ),
      ),
    );
  }

  Widget _buildColorTile({
    required String title,
    required Color color,
    required ValueChanged<Color> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
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
                BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 4),
              ],
            ),
          ),
          onTap: () => _pickColor(context, title, color, onChanged),
        ),
      ),
    );
  }

  bool get _isOutgoingGradient =>
      _currentTheme.palette.chatBubbleOutgoingGradient != null &&
      _currentTheme.palette.chatBubbleOutgoingGradient!.length >= 2;

  Widget _buildBubbleFillTypeToggle() {
    final isGrad = _isOutgoingGradient;
    final primary = _currentTheme.palette.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (isGrad) {
                    setState(() {
                      _currentTheme = _currentTheme.copyWith(
                        palette: _currentTheme.palette.copyWith(clearOutgoingGradient: true),
                      );
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: !isGrad ? primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Сплошной цвет',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: !isGrad ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (!isGrad) {
                    setState(() {
                      _currentTheme = _currentTheme.copyWith(
                        palette: _currentTheme.palette.copyWith(
                          chatBubbleOutgoingGradient: [
                            _currentTheme.palette.chatBubbleOutgoing,
                            _currentTheme.palette.primary.withValues(alpha: 0.85),
                          ],
                        ),
                      );
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: isGrad ? primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Градиент (экранный)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isGrad ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientEditor() {
    final colors = List<Color>.from(_currentTheme.palette.chatBubbleOutgoingGradient ?? []);
    if (colors.length < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
            child: Text(
              'Градиент растягивается по всей высоте чата. Облачка открывают его часть при скролле. Прозрачность позволяет фону просвечивать.',
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            ),
          ),
          Container(
            height: 36,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: Border.all(color: Colors.white24, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildPresetPill('Синий океан', const [Color(0xFF2A75D3), Color(0xFF00C6FF)]),
                _buildPresetPill('Закат', const [Color(0xFFFF5E36), Color(0xFF9013FE), Color(0xFF2C3E50)]),
                _buildPresetPill('Киберпанк', const [Color(0xFFFF007F), Color(0xFF7928CA), Color(0xFF00DFD8)]),
                _buildPresetPill('Изумруд', const [Color(0xFF0BA360), Color(0xFF3CBA92)]),
                _buildPresetPill('Стекло 80%', const [Color(0xCC0088CC), Color(0x995CB8E6)]),
                _buildPresetPill('Фиолет', const [Color(0xFF8E2DE2), Color(0xFF4A00E0)]),
                _buildPresetPill('Пастель', const [Color(0xFFFFAFBD), Color(0xFFFFC3A0)]),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < colors.length; i++)
            _buildGradientStopTile(i, colors[i], colors),
          if (colors.length < 4)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () {
                    final newColors = List<Color>.from(colors);
                    final last = newColors.last;
                    newColors.add(last.withValues(alpha: (last.a * 0.85).clamp(0.2, 1.0)));
                    setState(() {
                      _currentTheme = _currentTheme.copyWith(
                        palette: _currentTheme.palette.copyWith(
                          chatBubbleOutgoingGradient: newColors,
                        ),
                      );
                    });
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Добавить точку цвета', style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildPresetPill(String name, List<Color> presetColors) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() {
            _currentTheme = _currentTheme.copyWith(
              palette: _currentTheme.palette.copyWith(
                chatBubbleOutgoingGradient: presetColors,
              ),
            );
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: presetColors,
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                name,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGradientStopTile(int index, Color stopColor, List<Color> allColors) {
    final String label = index == 0
        ? 'Цвет 1 (вверху экрана)'
        : (index == allColors.length - 1
            ? 'Цвет ${index + 1} (внизу экрана)'
            : 'Цвет ${index + 1} (середина)');

    final int opacityPercent = (stopColor.a * 100).round();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            subtitle: Text(
              'Непрозрачность: $opacityPercent%',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
              ),
            ),
            leading: GestureDetector(
              onTap: () => _pickColor(context, label, stopColor, (c) {
                final newColors = List<Color>.from(allColors);
                newColors[index] = c;
                setState(() {
                  _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatBubbleOutgoingGradient: newColors),
                  );
                });
              }, allowOpacity: true),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: stopColor,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4),
                  ],
                ),
              ),
            ),
            trailing: allColors.length > 2
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      final newColors = List<Color>.from(allColors);
                      newColors.removeAt(index);
                      setState(() {
                        _currentTheme = _currentTheme.copyWith(
                          palette: _currentTheme.palette.copyWith(
                            chatBubbleOutgoingGradient: newColors,
                          ),
                        );
                      });
                    },
                  )
                : null,
            onTap: () => _pickColor(context, label, stopColor, (c) {
              final newColors = List<Color>.from(allColors);
              newColors[index] = c;
              setState(() {
                _currentTheme = _currentTheme.copyWith(
                  palette: _currentTheme.palette.copyWith(chatBubbleOutgoingGradient: newColors),
                );
              });
            }, allowOpacity: true),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.opacity, size: 16, color: Colors.grey),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: stopColor.a,
                      min: 0.1,
                      max: 1.0,
                      divisions: 18,
                      onChanged: (val) {
                        final newColors = List<Color>.from(allColors);
                        newColors[index] = stopColor.withValues(alpha: val);
                        setState(() {
                          _currentTheme = _currentTheme.copyWith(
                            palette: _currentTheme.palette.copyWith(
                              chatBubbleOutgoingGradient: newColors,
                            ),
                          );
                        });
                      },
                    ),
                  ),
                ),
                Text(
                  '$opacityPercent%',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _pickColor(
    BuildContext context,
    String title,
    Color currentColor,
    ValueChanged<Color> onChanged, {
    bool allowOpacity = false,
  }) {
    _colorPickerController.showIOSCustomColorPicker(
      context: context,
      startingColor: allowOpacity ? currentColor : currentColor.withValues(alpha: 1.0),
      onColorChanged: (c) {
        onChanged(allowOpacity ? c : c.withValues(alpha: 1.0));
      },
    );
  }
}
