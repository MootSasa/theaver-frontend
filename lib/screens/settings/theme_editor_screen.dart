import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:ios_color_picker/show_ios_color_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import '../../services/glass_toast_service.dart';
import '../../widgets/theme/theme_editor_floating_app_bar.dart';
import '../../models/theav_theme.dart';
import '../../services/theav_theme_service.dart';
import '../../theme/theme_provider.dart';
import '../../widgets/theme/chat_preview_card.dart';
import '../../l10n/app_localizations.dart';
import 'advanced_theme_colors_screen.dart';
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
        name: 'Новая тема',
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
    final l10n = context.l10n;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('theme_enter_name'))),
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
          SnackBar(content: Text(l10n.translate('theme_saved_applied'))),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('theme_save_error').replaceAll('{error}', e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _exportTheme() async {
    final l10n = context.l10n;
    try {
      final bytes = await TheavThemeService().exportThemePackage(_currentTheme);
      final tempDir = await getTemporaryDirectory();
      final cleanName = TheavThemeService.sanitizeFileName(_currentTheme.name);
      final file = File('${tempDir.path}/$cleanName.theavtheme');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, name: '$cleanName.theavtheme')],
        text: 'Тема Theaver: ${_currentTheme.name}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('theme_export_error').replaceAll('{error}', e.toString()))),
        );
      }
    }
  }

  Future<void> _deleteTheme() async {
    final l10n = context.l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('theme_delete')),
        content: Text(l10n.translate('theme_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.translate('common_delete'),
              style: TextStyle(color: _currentTheme.palette.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TheavThemeService().deleteTheme(_currentTheme.id);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _shareThemeLink() async {
    final l10n = context.l10n;
    try {
      final url = await TheavThemeService().sharePublicTheme(_currentTheme);
      if (url != null) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          GlassToastService().show(
            context,
            l10n.translate('theme_link_copied'),
            icon: Icons.link,
          );
        }
        await Share.share(url, subject: _currentTheme.name);
      } else {
        await _exportTheme();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing theme: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEditing = widget.themeToEdit != null;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final topPadding = statusBarHeight + kThemeEditorAppBarTotalHeight;

    final listView = ListView(
      padding: const EdgeInsets.only(
        top: 12,
        bottom: 40,
      ),
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
                  prefixIcon: const Padding(
                    padding: EdgeInsets.all(12),
                    child: iconoir.Palette(width: 20, height: 20),
                  ),
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
                  secondary: _currentTheme.isDark
                      ? iconoir.HalfMoon(color: _currentTheme.palette.primary, width: 22, height: 22)
                      : iconoir.SunLight(color: _currentTheme.palette.primary, width: 22, height: 22),
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
            const SizedBox(height: 16),

            // 5. Advanced Theme Colors Button Tile
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                tileColor: Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: iconoir.Settings(color: _currentTheme.palette.primary, width: 22, height: 22),
                title: Text(
                  l10n.translate('theme_advanced_settings'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  l10n.translate('theme_advanced_settings_desc'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                trailing: const iconoir.NavArrowRight(color: Colors.grey, width: 20, height: 20),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdvancedThemeColorsScreen(
                        initialTheme: _currentTheme,
                        onThemeChanged: (updated) {
                          setState(() => _currentTheme = updated);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),

            // 6. Palette Colors Section (Categorized)
            _buildSectionHeader(l10n.translate('theme_section_interface')),
            _buildColorTile(
              title: l10n.translate('theme_color_primary'),
              color: _currentTheme.palette.primary,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(primary: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_background'),
              color: _currentTheme.palette.background,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(background: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_surface'),
              color: _currentTheme.palette.surface,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(surface: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_on_surface'),
              color: _currentTheme.palette.onSurface,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(onSurface: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_app_bar_bg'),
              color: _currentTheme.palette.appBarBackground,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(appBarBackground: c),
                  )),
            ),

            _buildSectionHeader(l10n.translate('theme_section_outgoing')),
            _buildBubbleFillTypeToggle(l10n),
            if (_isOutgoingGradient) ...[
              _buildGradientEditor(l10n),
            ] else ...[
              _buildColorTile(
                title: l10n.translate('theme_color_bubble_outgoing'),
                color: _currentTheme.palette.chatBubbleOutgoing,
                onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                      palette: _currentTheme.palette.copyWith(chatBubbleOutgoing: c),
                    )),
              ),
            ],
            _buildColorTile(
              title: l10n.translate('theme_color_bubble_outgoing_text'),
              color: _currentTheme.palette.chatBubbleOutgoingText,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatBubbleOutgoingText: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_bubble_outgoing_subtext'),
              color: _currentTheme.palette.chatBubbleOutgoingSubtext,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatBubbleOutgoingSubtext: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_bubble_outgoing_link'),
              color: _currentTheme.palette.chatBubbleOutgoingLink,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatBubbleOutgoingLink: c),
                  )),
            ),

            _buildSectionHeader(l10n.translate('theme_section_incoming')),
            _buildColorTile(
              title: l10n.translate('theme_color_bubble_incoming'),
              color: _currentTheme.palette.chatBubbleIncoming,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatBubbleIncoming: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_bubble_incoming_text'),
              color: _currentTheme.palette.chatBubbleIncomingText,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatBubbleIncomingText: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_bubble_incoming_subtext'),
              color: _currentTheme.palette.chatBubbleIncomingSubtext,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatBubbleIncomingSubtext: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_bubble_incoming_link'),
              color: _currentTheme.palette.chatBubbleIncomingLink,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatBubbleIncomingLink: c),
                  )),
            ),

            _buildSectionHeader(l10n.translate('theme_section_input')),
            _buildColorTile(
              title: l10n.translate('theme_color_input_bg'),
              color: _currentTheme.palette.chatInputBackground,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatInputBackground: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_input_text'),
              color: _currentTheme.palette.chatInputText,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatInputText: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_input_buttons'),
              color: _currentTheme.palette.chatInputButtons,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatInputButtons: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_send_button'),
              color: _currentTheme.palette.chatSendButton,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatSendButton: c),
                  )),
            ),

            _buildSectionHeader(l10n.translate('theme_section_badges')),
            _buildColorTile(
              title: l10n.translate('theme_color_date_badge'),
              color: _currentTheme.palette.chatDateBadge,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatDateBadge: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_date_badge_text'),
              color: _currentTheme.palette.chatDateBadgeText,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(chatDateBadgeText: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_unread_badge'),
              color: _currentTheme.palette.unreadBadge,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(unreadBadge: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_unread_badge_text'),
              color: _currentTheme.palette.unreadBadgeText,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(unreadBadgeText: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_online'),
              color: _currentTheme.palette.onlineIndicator,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(onlineIndicator: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_subtext'),
              color: _currentTheme.palette.subtext,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(subtext: c),
                  )),
            ),
            _buildColorTile(
              title: l10n.translate('theme_color_divider'),
              color: _currentTheme.palette.divider,
              onChanged: (c) => setState(() => _currentTheme = _currentTheme.copyWith(
                    palette: _currentTheme.palette.copyWith(divider: c),
                  )),
            ),

            const SizedBox(height: 16),

            // 7. Wallpaper Customization Tile
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                tileColor: Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: iconoir.MediaImage(color: _currentTheme.palette.primary, width: 22, height: 22),
                title: Text(l10n.translate('wallpaper_title')),
                subtitle: Text(
                  _currentTheme.wallpaper.type == 'pattern'
                      ? (_currentTheme.wallpaper.patternName != null && _currentTheme.wallpaper.patternName != 'none'
                          ? l10n.translate('theme_wallpaper_pattern_desc').replaceAll('{pattern}', _currentTheme.wallpaper.patternName!)
                          : l10n.translate('theme_wallpaper_gradient_desc'))
                      : _currentTheme.wallpaper.type == 'image'
                          ? l10n.translate('theme_wallpaper_photo_desc')
                          : l10n.translate('theme_wallpaper_default_desc'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                trailing: const iconoir.NavArrowRight(color: Colors.grey, width: 20, height: 20),
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

            // 8. Delete Theme Button (if editing existing custom theme)
            if (isEditing && !_currentTheme.isBuiltIn) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListTile(
                  tileColor: Theme.of(context).cardColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: iconoir.Trash(
                    width: 22,
                    height: 22,
                    color: _currentTheme.palette.error,
                  ),
                  title: Text(
                    l10n.translate('theme_delete'),
                    style: TextStyle(
                      color: _currentTheme.palette.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  onTap: _deleteTheme,
                ),
              ),
            ],
          ],
        );

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
            child: ThemeEditorFloatingAppBar(
              title: isEditing
                  ? l10n.translate('theme_edit')
                  : l10n.translate('theme_create_new'),
              onBack: () => Navigator.of(context).pop(),
              onShare: _shareThemeLink,
              onApply: _saveTheme,
              isSaving: _isSaving,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 20, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: _currentTheme.palette.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  bool get _isOutgoingGradient =>
      _currentTheme.palette.chatBubbleOutgoingGradient != null &&
      _currentTheme.palette.chatBubbleOutgoingGradient!.length >= 2;

  Widget _buildBubbleFillTypeToggle(AppLocalizations l10n) {
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
                    l10n.translate('theme_bubble_fill_solid'),
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
                      final currentSolid = _currentTheme.palette.chatBubbleOutgoing;
                      final baseColor = currentSolid;
                      final targetColor = baseColor.withValues(alpha: (baseColor.a * 0.85).clamp(0.2, 1.0));
                      _currentTheme = _currentTheme.copyWith(
                        palette: _currentTheme.palette.copyWith(
                          chatBubbleOutgoingGradient: [baseColor, targetColor],
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
                    l10n.translate('theme_bubble_fill_gradient'),
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

  Widget _buildGradientEditor(AppLocalizations l10n) {
    final colors = _currentTheme.palette.chatBubbleOutgoingGradient ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 38,
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
                  icon: const iconoir.Plus(width: 18, height: 18),
                  label: Text(l10n.translate('theme_gradient_add_point'), style: const TextStyle(fontSize: 12.5)),
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
    final String label = 'Цвет ${index + 1}';
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
                    icon: const iconoir.Xmark(width: 18, height: 18),
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
                const iconoir.ColorWheel(width: 16, height: 16, color: Colors.grey),
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

  Widget _buildColorTile({
    required String title,
    required Color color,
    required ValueChanged<Color> onChanged,
    bool allowOpacity = false,
  }) {
    final hexString = '#${(color.a * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${(color.r * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${(color.g * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${(color.b * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase()}';

    return ListTile(
      dense: true,
      title: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
      subtitle: Text(
        hexString,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
        ),
      ),
      leading: GestureDetector(
        onTap: () => _pickColor(context, title, color, onChanged, allowOpacity: allowOpacity),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 1.5)),
            ],
          ),
        ),
      ),
      trailing: const iconoir.NavArrowRight(width: 18, height: 18, color: Colors.grey),
      onTap: () => _pickColor(context, title, color, onChanged, allowOpacity: allowOpacity),
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
