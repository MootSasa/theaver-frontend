import 'dart:ui' as ui;
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
import '../../widgets/user/avatar_with_status.dart';

/// Screen allowing granular customization of every single color in [TheavPalette],
/// grouped into logical sections with real-time dedicated pixel-perfect micro-previews
/// rendering the actual UI components of Theaver.
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
                _buildColorTile(
                  title: l10n.translate('theme_color_online'),
                  color: _theme.palette.onlineIndicator,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(onlineIndicator: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_subtext'),
                  color: _theme.palette.subtext,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(subtext: c)),
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
                _buildColorTile(
                  title: l10n.translate('theme_color_selection_overlay'),
                  color: _theme.palette.messageSelectionOverlay,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(messageSelectionOverlay: c)),
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
                _buildColorTile(
                  title: l10n.translate('theme_color_reaction_active'),
                  color: _theme.palette.reactionActiveBackground,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(reactionActiveBackground: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_reaction_inactive'),
                  color: _theme.palette.reactionInactiveBackground,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(reactionInactiveBackground: c)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Section 4: Voice & Audio Player
            _buildSectionCard(
              title: l10n.translate('theme_section_voice_media'),
              icon: const iconoir.Microphone(width: 20, height: 20),
              preview: _VoiceMediaMicroPreview(theme: _theme),
              children: [
                _buildColorTile(
                  title: l10n.translate('theme_color_voice_wave_active'),
                  color: _theme.palette.voiceWaveformActive,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(voiceWaveformActive: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_voice_wave_inactive'),
                  color: _theme.palette.voiceWaveformInactive,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(voiceWaveformInactive: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_voice_play_btn'),
                  color: _theme.palette.voicePlayButton,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(voicePlayButton: c)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Section 5: Replies & Quotes
            _buildSectionCard(
              title: l10n.translate('theme_section_replies'),
              icon: const iconoir.Reply(width: 20, height: 20),
              preview: _RepliesMicroPreview(theme: _theme),
              children: [
                _buildColorTile(
                  title: l10n.translate('theme_color_reply_line'),
                  color: _theme.palette.chatReplyLine,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatReplyLine: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_reply_title'),
                  color: _theme.palette.chatReplyTitle,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatReplyTitle: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_reply_text'),
                  color: _theme.palette.chatReplyText,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(chatReplyText: c)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Section 6: Input Field
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

            // Section 7: Badges & Indicators
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
              ],
            ),

            const SizedBox(height: 16),

            // Section 8: System & Surface Colors
            _buildSectionCard(
              title: l10n.translate('theme_section_other'),
              icon: const iconoir.Palette(width: 20, height: 20),
              preview: _SystemColorsMicroPreview(theme: _theme),
              children: [
                _buildColorTile(
                  title: l10n.translate('theme_primary_color'),
                  color: _theme.palette.primary,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(primary: c)),
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
                  title: l10n.translate('theme_color_divider'),
                  color: _theme.palette.divider,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(divider: c)),
                  ),
                ),
                _buildColorTile(
                  title: l10n.translate('theme_color_error'),
                  color: _theme.palette.error,
                  onChanged: (c) => _updateTheme(
                    _theme.copyWith(palette: _theme.palette.copyWith(error: c)),
                  ),
                ),
              ],
            ),
          ],
        );

        if (glassEnabled) {
          return Scaffold(
            backgroundColor: _theme.palette.background,
            body: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + kToolbarHeight,
                  ),
                  child: bodyList,
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LiquidGlassAppBar(
                    title: Text(l10n.translate('theme_advanced_settings')),
                    leading: IconButton(
                      icon: const iconoir.ArrowLeft(width: 22, height: 22),
                      onPressed: () => Navigator.pop(context),
                    ),
                    centerTitle: true,
                    isLite: glassProvider.isLite,
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: _theme.palette.background,
          appBar: AppBar(
            backgroundColor: _theme.palette.appBarBackground,
            foregroundColor: _theme.palette.appBarForeground,
            elevation: 0,
            leading: IconButton(
              icon: iconoir.ArrowLeft(width: 22, height: 22, color: _theme.palette.appBarForeground),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              l10n.translate('theme_advanced_settings'),
              style: TextStyle(
                color: _theme.palette.appBarForeground,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
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
    final isDark = _theme.isDark;
    final cardColor = _theme.palette.surface;
    final borderColor = _theme.palette.divider;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                IconTheme(
                  data: IconThemeData(color: _theme.palette.primary, size: 20),
                  child: icon,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: _theme.palette.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Real-time Dedicated Micro-Preview
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: borderColor, width: 0.5),
              ),
            ),
            child: preview,
          ),

          // Granular Color Tiles
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: children.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              thickness: 0.5,
              indent: 16,
              endIndent: 16,
              color: borderColor,
            ),
            itemBuilder: (_, index) => children[index],
          ),
        ],
      ),
    );
  }

  Widget _buildColorTile({
    required String title,
    required Color color,
    required ValueChanged<Color> onChanged,
    bool allowOpacity = true,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: _theme.palette.onSurface,
        ),
      ),
      trailing: GestureDetector(
        onTap: () => _pickColor(context, title, color, onChanged, allowOpacity: allowOpacity),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: _theme.palette.divider,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 4,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
        ),
      ),
      onTap: () => _pickColor(context, title, color, onChanged, allowOpacity: allowOpacity),
    );
  }
}

// ============================================================================
// PIXEL-PERFECT REAL COMPONENT MICRO PREVIEWS
// ============================================================================

/// 1. Floating Glass App Bar Micro Preview (Exact Floating 3-Pill Layout)
class _AppBarMicroPreview extends StatelessWidget {
  final TheavTheme theme;
  const _AppBarMicroPreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final isDark = theme.isDark;
    final pillBg = p.appBarBackground;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      color: theme.wallpaper.backgroundColor,
      child: Row(
        children: [
          // Left Pill: Back Button (40x40 circle)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 0.5,
                  ),
                ),
                child: Center(
                  child: iconoir.NavArrowLeft(
                    width: 20,
                    height: 20,
                    color: p.appBarForeground,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Center Pill: Avatar + Title + Status
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: p.primary,
                            child: Text(
                              'A',
                              style: TextStyle(
                                color: p.onPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: p.onlineIndicator,
                                shape: BoxShape.circle,
                                border: Border.all(color: p.surface, width: 1.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Александр',
                              style: TextStyle(
                                color: p.appBarForeground,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'в сети',
                              style: TextStyle(
                                color: p.onlineIndicator,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Right Pill: Call + More
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconoir.Phone(
                      width: 17,
                      height: 17,
                      color: p.appBarForeground,
                    ),
                    const SizedBox(width: 8),
                    iconoir.MoreVert(
                      width: 17,
                      height: 17,
                      color: p.appBarForeground,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 2. Outgoing Bubble Micro Preview (Exact MessageBubble Structure)
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
        constraints: const BoxConstraints(maxWidth: 250),
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
          borderRadius: BorderRadius.circular(theme.bubbleRadius.clamp(4.0, 22.0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 5,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reply Preview Header inside Outgoing Bubble
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 3,
                    height: 24,
                    decoration: BoxDecoration(
                      color: p.chatReplyLine,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Александр',
                          style: TextStyle(
                            color: p.chatReplyTitle,
                            fontWeight: FontWeight.bold,
                            fontSize: 10.5,
                          ),
                          maxLines: 1,
                        ),
                        Text(
                          'Где посмотреть исходники?',
                          style: TextStyle(
                            color: p.chatReplyText,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Message text with link
            Text(
              'Привет! Посмотри сайт Theaver:',
              style: TextStyle(
                color: p.chatBubbleOutgoingText,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'https://theaver.app',
              style: TextStyle(
                color: p.chatBubbleOutgoingLink,
                fontSize: 13,
                decoration: TextDecoration.underline,
              ),
            ),
            const SizedBox(height: 4),

            // Metadata row: Time + Double Check
            Align(
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '12:45',
                    style: TextStyle(
                      color: p.chatBubbleOutgoingSubtext,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 4),
                  iconoir.DoubleCheck(
                    width: 14,
                    height: 14,
                    color: p.chatBubbleOutgoingSubtext,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 3. Incoming Bubble Micro Preview (Exact MessageBubble with Avatar and Reaction)
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const AvatarWithStatus(
                avatarUrl: null,
                name: 'Александр',
                radius: 14,
                isOnline: true,
              ),
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(maxWidth: 240),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: p.chatBubbleIncoming,
                  borderRadius: BorderRadius.circular(theme.bubbleRadius.clamp(4.0, 22.0)),
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
                      'Александр',
                      style: TextStyle(
                        color: p.primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Все работает отлично! Подробнее:',
                      style: TextStyle(
                        color: p.chatBubbleIncomingText,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'https://theaver.app/docs',
                      style: TextStyle(
                        color: p.chatBubbleIncomingLink,
                        fontSize: 12.5,
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
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Real Reactions Row
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.reactionActiveBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.reactionActiveText, width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('👍', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        '2',
                        style: TextStyle(
                          color: p.reactionActiveText,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.reactionInactiveBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        '1',
                        style: TextStyle(
                          color: p.subtext,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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

/// 4. Voice & Audio Player Micro Preview (Real VoiceMessageWidget Layout)
class _VoiceMediaMicroPreview extends StatelessWidget {
  final TheavTheme theme;
  const _VoiceMediaMicroPreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;

    return Container(
      padding: const EdgeInsets.all(12),
      color: theme.wallpaper.backgroundColor,
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: p.chatBubbleIncoming,
          borderRadius: BorderRadius.circular(theme.bubbleRadius.clamp(4.0, 22.0)),
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
            Row(
              children: [
                // Play / Pause Circle Button
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: p.voicePlayButton,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: iconoir.PlaySolid(
                      width: 18,
                      height: 18,
                      color: p.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Multi-bar Waveform
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 22,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(24, (i) {
                            final heights = [
                              8.0, 12.0, 18.0, 14.0, 10.0, 16.0, 20.0, 15.0,
                              11.0, 19.0, 14.0, 9.0, 16.0, 22.0, 17.0, 11.0,
                              13.0, 18.0, 12.0, 15.0, 10.0, 16.0, 12.0, 7.0
                            ];
                            final h = heights[i % heights.length];
                            final isPlayed = i < 10;
                            return Expanded(
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                height: h,
                                decoration: BoxDecoration(
                                  color: isPlayed ? p.voiceWaveformActive : p.voiceWaveformInactive,
                                  borderRadius: BorderRadius.circular(1.5),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: p.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(
                            '0:18',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: p.subtext,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: p.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '2X',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: p.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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

/// 5. Replies & Quotes Micro Preview (Real MessageReplyInfo Layout)
class _RepliesMicroPreview extends StatelessWidget {
  final TheavTheme theme;
  const _RepliesMicroPreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;

    return Container(
      padding: const EdgeInsets.all(12),
      color: theme.wallpaper.backgroundColor,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 3.5,
              height: 36,
              decoration: BoxDecoration(
                color: p.chatReplyLine,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      iconoir.Reply(width: 13, height: 13, color: p.chatReplyTitle),
                      const SizedBox(width: 4),
                      Text(
                        'Мария Иванова',
                        style: TextStyle(
                          color: p.chatReplyTitle,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Отправила макет дизайна в новом обновлении Theaver',
                    style: TextStyle(
                      color: p.chatReplyText,
                      fontSize: 11.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 6. Input Bar Micro Preview (Exact LiquidGlassInputField / ChatInputBar Structure)
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      color: theme.wallpaper.backgroundColor,
      child: Row(
        children: [
          // Main Pill Container (24px radius, Emoji on left, Hint, Attach on right)
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Emoji on Left
                      iconoir.Emoji(
                        width: 22,
                        height: 22,
                        color: p.chatInputButtons,
                      ),
                      const SizedBox(width: 8),
                      // Message TextField Hint
                      Expanded(
                        child: Text(
                          'Сообщение...',
                          style: TextStyle(
                            color: p.chatInputText.withValues(alpha: 0.6),
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      // Attachment on Right
                      iconoir.Attachment(
                        width: 20,
                        height: 20,
                        color: p.chatInputButtons,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send Button Circle (38x38)
          Container(
            width: 40,
            height: 40,
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
                width: 20,
                height: 20,
                color: p.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 7. Badges & Indicators Micro Preview (Real DateSeparator & ChatListItem Layout)
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
          // Floating Date Badge Pill (Exact DateSeparator)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3.5),
            decoration: BoxDecoration(
              color: p.chatDateBadge,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 3,
                ),
              ],
            ),
            child: Text(
              'Сегодня',
              style: TextStyle(
                color: p.chatDateBadgeText,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Real ChatListItem Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.divider, width: 0.5),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: p.primary,
                      child: Text(
                        'T',
                        style: TextStyle(
                          color: p.onPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: p.onlineIndicator,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.surface, width: 2),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Команда Theaver',
                            style: TextStyle(
                              color: p.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '12:48',
                            style: TextStyle(
                              color: p.subtext,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Новое обновление уже доступно для загрузки',
                              style: TextStyle(
                                color: p.subtext,
                                fontSize: 11.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: p.unreadBadge,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '3',
                              style: TextStyle(
                                color: p.unreadBadgeText,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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

/// 8. System & Surface Micro Preview (Real Card and Action Layout)
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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.divider, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: p.primary.withValues(alpha: 0.15),
                  child: iconoir.User(width: 14, height: 14, color: p.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Настройки профиля',
                    style: TextStyle(
                      color: p.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  'Изменить',
                  style: TextStyle(
                    color: p.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Управляйте персональными параметрами и внешним видом.',
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
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: p.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Сохранить',
                    style: TextStyle(
                      color: p.onPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: p.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      iconoir.Trash(width: 13, height: 13, color: p.error),
                      const SizedBox(width: 4),
                      Text(
                        'Удалить',
                        style: TextStyle(
                          color: p.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
