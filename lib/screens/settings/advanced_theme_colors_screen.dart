import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:ios_color_picker/show_ios_color_picker.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/theav_theme_service.dart';
import '../../theme/theme_provider.dart';
import '../../widgets/chat/liquid_glass_app_bar.dart';

/// Screen allowing granular customization of every single color in [TheavPalette],
/// grouped into logical sections with real-time dedicated micro-previews.
class AdvancedThemeColorsScreen extends StatefulWidget {
  final TheavTheme? initialTheme;
  final ValueChanged<TheavTheme>? onThemeChanged;

  const AdvancedThemeColorsScreen({
    Key? key,
    this.initialTheme,
    this.onThemeChanged,
  }) : super(key: key);

  @override
  State<AdvancedThemeColorsScreen> createState() => _AdvancedThemeColorsScreenState();
}

class _AdvancedThemeColorsScreenState extends State<AdvancedThemeColorsScreen> {
  late TheavTheme _theme;
  final IOSColorPickerController _colorPickerController = IOSColorPickerController();

  @override
  void initState() {
    super.initState();
    if (widget.initialTheme != null) {
      _theme = widget.initialTheme!;
    } else {
      final themeProvider = context.read<ThemeProvider>();
      final isDark = themeProvider.themeMode == ThemeMode.dark;
      _theme = isDark ? themeProvider.activeDarkTheme : themeProvider.activeLightTheme;
    }
  }

  @override
  void dispose() {
    _colorPickerController.dispose();
    super.dispose();
  }

  void _updateTheme(TheavTheme newTheme) {
    setState(() => _theme = newTheme);
    if (widget.onThemeChanged != null) {
      widget.onThemeChanged!(newTheme);
    } else {
      final themeProvider = context.read<ThemeProvider>();
      themeProvider.setActiveTheme(newTheme);
      TheavThemeService().saveTheme(
        newTheme,
        saveToCloud: !newTheme.isBuiltIn || newTheme.isCloudSaved,
      );
    }
  }

  void _pickColor(BuildContext context, String title, Color currentColor, ValueChanged<Color> onChanged, {bool allowOpacity = true}) {
    _colorPickerController.showIOSCustomColorPicker(
      context: context,
      startingColor: allowOpacity ? currentColor : currentColor.withValues(alpha: 1.0),
      onColorChanged: (c) {
        onChanged(allowOpacity ? c : c.withValues(alpha: 1.0));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Consumer<LiquidGlassProvider>(
      builder: (context, glassProvider, _) {
        final glassEnabled = glassProvider.enabled;

        final bodyList = ListView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: glassEnabled ? 12 : 8,
            bottom: 40,
          ),
          children: [
            // Section 1: Interface & App Bar
            _buildSectionCard(
              title: l10n.translate('theme_section_interface'),
              icon: const iconoir.ViewColumns2(width: 20, height: 20),
              preview: _AppBarMicroPreview(theme: _theme),
              children: [
                _buildColorTile(
                  title: l10n.translate('theme_color_app_bar_bg'),
                  color: _theme.palette.appBarBackground,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(appBarBackground: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_app_bar_fg'),
                  color: _theme.palette.appBarForeground,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(appBarForeground: c)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Section 2: Outgoing Messages
            _buildSectionCard(
              title: l10n.translate('theme_section_outgoing'),
              icon: const iconoir.ChatBubbleCheck(width: 20, height: 20),
              preview: _OutgoingBubbleMicroPreview(theme: _theme),
              children: [
                _buildColorTile(
                  title: l10n.translate('theme_color_bubble_outgoing'),
                  color: _theme.palette.chatBubbleOutgoing,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatBubbleOutgoing: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_bubble_outgoing_text'),
                  color: _theme.palette.chatBubbleOutgoingText,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatBubbleOutgoingText: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_bubble_outgoing_subtext'),
                  color: _theme.palette.chatBubbleOutgoingSubtext,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatBubbleOutgoingSubtext: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_bubble_outgoing_link'),
                  color: _theme.palette.chatBubbleOutgoingLink,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatBubbleOutgoingLink: c)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Section 3: Incoming Messages
            _buildSectionCard(
              title: l10n.translate('theme_section_incoming'),
              icon: const iconoir.ChatBubble(width: 20, height: 20),
              preview: _IncomingBubbleMicroPreview(theme: _theme),
              children: [
                _buildColorTile(
                  title: l10n.translate('theme_color_bubble_incoming'),
                  color: _theme.palette.chatBubbleIncoming,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatBubbleIncoming: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_bubble_incoming_text'),
                  color: _theme.palette.chatBubbleIncomingText,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatBubbleIncomingText: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_bubble_incoming_subtext'),
                  color: _theme.palette.chatBubbleIncomingSubtext,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatBubbleIncomingSubtext: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_bubble_incoming_link'),
                  color: _theme.palette.chatBubbleIncomingLink,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatBubbleIncomingLink: c)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Section 4: Input Field
            _buildSectionCard(
              title: l10n.translate('theme_section_input'),
              icon: const iconoir.EditPencil(width: 20, height: 20),
              preview: _InputBarMicroPreview(theme: _theme),
              children: [
                _buildColorTile(
                  title: l10n.translate('theme_color_input_bg'),
                  color: _theme.palette.chatInputBackground,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatInputBackground: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_input_text'),
                  color: _theme.palette.chatInputText,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatInputText: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_input_buttons'),
                  color: _theme.palette.chatInputButtons,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatInputButtons: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_send_button'),
                  color: _theme.palette.chatSendButton,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatSendButton: c)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Section 5: Badges & Indicators
            _buildSectionCard(
              title: l10n.translate('theme_section_badges'),
              icon: const iconoir.BellNotification(width: 20, height: 20),
              preview: _BadgesMicroPreview(theme: _theme),
              children: [
                _buildColorTile(
                  title: l10n.translate('theme_color_date_badge'),
                  color: _theme.palette.chatDateBadge,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatDateBadge: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_date_badge_text'),
                  color: _theme.palette.chatDateBadgeText,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatDateBadgeText: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_unread_badge'),
                  color: _theme.palette.unreadBadge,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(unreadBadge: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_unread_badge_text'),
                  color: _theme.palette.unreadBadgeText,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(unreadBadgeText: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_online'),
                  color: _theme.palette.onlineIndicator,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(onlineIndicator: c)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Section 6: System & Surface Colors
            _buildSectionCard(
              title: l10n.translate('theme_section_other'),
              icon: const iconoir.Palette(width: 20, height: 20),
              preview: _SystemColorsMicroPreview(theme: _theme),
              children: [
                _buildColorTile(
                  title: l10n.translate('theme_color_primary'),
                  color: _theme.palette.primary,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(primary: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_on_primary'),
                  color: _theme.palette.onPrimary,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(onPrimary: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_background'),
                  color: _theme.palette.background,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(background: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_surface'),
                  color: _theme.palette.surface,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(surface: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_on_surface'),
                  color: _theme.palette.onSurface,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(onSurface: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_subtext'),
                  color: _theme.palette.subtext,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(subtext: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_divider'),
                  color: _theme.palette.divider,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(divider: c)),
                  ),
                ),
              ],
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
                    child: bodyList,
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LiquidGlassAppBar(
                    title: Text(l10n.translate('theme_advanced_settings')),
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
            title: Text(l10n.translate('theme_advanced_settings')),
            centerTitle: true,
          ),
          body: bodyList,
        );
      },
    );
  }

  Widget _buildSectionCard({
    required String title,
    required Widget icon,
    required Widget preview,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title Header
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 10),
            child: Row(
              children: [
                icon,
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Micro-Preview box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: preview,
            ),
          ),

          const SizedBox(height: 8),

          // Color tiles
          ...children,

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildColorTile({
    required String title,
    required Color color,
    required ValueChanged<Color> onChanged,
  }) {
    final hexString = '#${(color.a * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${(color.r * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${(color.g * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${(color.b * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase()}';

    return ListTile(
      dense: true,
      title: Text(
        title,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        hexString,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
        ),
      ),
      leading: GestureDetector(
        onTap: () => _pickColor(context, title, color, onChanged),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: Colors.white,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
        ),
      ),
      trailing: const iconoir.NavArrowRight(
        width: 16,
        height: 16,
        color: Colors.grey,
      ),
      onTap: () => _pickColor(context, title, color, onChanged),
    );
  }
}

// ---------------------------------------------------------------------------
// Dedicated Micro-Previews for Each Section
// ---------------------------------------------------------------------------

/// 1. App Bar Micro Preview
class _AppBarMicroPreview extends StatelessWidget {
  final TheavTheme theme;
  const _AppBarMicroPreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.appBarBackground,
        border: Border(
          bottom: BorderSide(
            color: p.divider,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          iconoir.ArrowLeft(
            width: 20,
            height: 20,
            color: p.appBarForeground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Theaver',
                  style: TextStyle(
                    color: p.appBarForeground,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'online',
                  style: TextStyle(
                    color: p.appBarForeground.withValues(alpha: 0.7),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          iconoir.MoreVert(
            width: 20,
            height: 20,
            color: p.appBarForeground,
          ),
        ],
      ),
    );
  }
}

/// 2. Outgoing Bubble Micro Preview
class _OutgoingBubbleMicroPreview extends StatelessWidget {
  final TheavTheme theme;
  const _OutgoingBubbleMicroPreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final isGrad = p.chatBubbleOutgoingGradient != null && p.chatBubbleOutgoingGradient!.length >= 2;

    return Container(
      padding: const EdgeInsets.all(12),
      color: theme.wallpaper.backgroundColor,
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isGrad ? null : p.chatBubbleOutgoing,
          gradient: isGrad
              ? LinearGradient(
                  colors: p.chatBubbleOutgoingGradient!,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : null,
          borderRadius: BorderRadius.circular(theme.bubbleRadius.clamp(4.0, 18.0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Привет! Посмотри сайт Theaver:',
              style: TextStyle(
                color: p.chatBubbleOutgoingText,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'https://theaver.app',
              style: TextStyle(
                color: p.chatBubbleOutgoingLink,
                fontSize: 12,
                decoration: TextDecoration.underline,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '12:45',
                  style: TextStyle(
                    color: p.chatBubbleOutgoingSubtext,
                    fontSize: 9.5,
                  ),
                ),
                const SizedBox(width: 4),
                iconoir.Check(
                  width: 12,
                  height: 12,
                  color: p.chatBubbleOutgoingSubtext,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 3. Incoming Bubble Micro Preview
class _IncomingBubbleMicroPreview extends StatelessWidget {
  final TheavTheme theme;
  const _IncomingBubbleMicroPreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;

    return Container(
      padding: const EdgeInsets.all(12),
      color: theme.wallpaper.backgroundColor,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: p.primary,
            child: Text(
              'A',
              style: TextStyle(
                color: p.onPrimary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: p.chatBubbleIncoming,
              borderRadius: BorderRadius.circular(theme.bubbleRadius.clamp(4.0, 18.0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Все работает отлично! Подробнее:',
                  style: TextStyle(
                    color: p.chatBubbleIncomingText,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'https://theaver.org/docs',
                  style: TextStyle(
                    color: p.chatBubbleIncomingLink,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
                const SizedBox(height: 3),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    '12:46',
                    style: TextStyle(
                      color: p.chatBubbleIncomingSubtext,
                      fontSize: 9.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 4. Input Bar Micro Preview
class _InputBarMicroPreview extends StatelessWidget {
  final TheavTheme theme;
  const _InputBarMicroPreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final isDark = theme.isDark;
    final defaultBg = isDark
        ? Colors.black.withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.65);
    final inputBg = p.explicitChatInputBackground ?? defaultBg;

    return Container(
      padding: const EdgeInsets.all(10),
      color: theme.wallpaper.backgroundColor,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: inputBg,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  iconoir.Attachment(
                    width: 17,
                    height: 17,
                    color: p.chatInputButtons,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Сообщение...',
                      style: TextStyle(
                        color: p.chatInputText.withValues(alpha: 0.65),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  iconoir.Emoji(
                    width: 17,
                    height: 17,
                    color: p.chatInputButtons,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.chatSendButton,
              boxShadow: [
                BoxShadow(
                  color: p.chatSendButton.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: iconoir.ArrowUp(
                width: 18,
                height: 18,
                color: p.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 5. Badges & Indicators Micro Preview
class _BadgesMicroPreview extends StatelessWidget {
  final TheavTheme theme;
  const _BadgesMicroPreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: theme.wallpaper.backgroundColor,
      child: Column(
        children: [
          // Floating Date Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: p.chatDateBadge,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 3,
                ),
              ],
            ),
            child: Text(
              'Сегодня',
              style: TextStyle(
                color: p.chatDateBadgeText,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Chat Row Item
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.divider, width: 0.5),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: p.primary.withValues(alpha: 0.2),
                      child: Text(
                        'T',
                        style: TextStyle(
                          color: p.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: p.onlineIndicator,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.surface, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Команда Theaver',
                        style: TextStyle(
                          color: p.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'Новое обновление уже доступно',
                        style: TextStyle(
                          color: p.subtext,
                          fontSize: 10.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: p.unreadBadge,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '3',
                    style: TextStyle(
                      color: p.unreadBadgeText,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 6. System & Surface Micro Preview
class _SystemColorsMicroPreview extends StatelessWidget {
  final TheavTheme theme;
  const _SystemColorsMicroPreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;

    return Container(
      padding: const EdgeInsets.all(12),
      color: p.background,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.divider, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Основной заголовок',
              style: TextStyle(
                color: p.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Второстепенный поясняющий текст',
              style: TextStyle(
                color: p.subtext,
                fontSize: 11,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(
                height: 1,
                color: p.divider,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Настройки профиля',
                  style: TextStyle(
                    color: p.onSurface,
                    fontSize: 11.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: p.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Действие',
                    style: TextStyle(
                      color: p.onPrimary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
