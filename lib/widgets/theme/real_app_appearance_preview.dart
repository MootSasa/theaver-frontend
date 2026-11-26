import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/profile_theme_provider.dart';
import '../../theme/theme_provider.dart';
import '../chat/chat_list_item.dart';
import '../chat/chat_scaffold.dart';
import '../chat/classic_bottom_bar.dart';
import '../chat/floating_glass_app_bar.dart';
import '../chat/liquid_glass_bottom_bar.dart';
import '../chat/liquid_glass_filter_chips.dart';
import '../chat/liquid_glass_input_field.dart';
import '../design_system/theav_design_system.dart';
import '../message/message_bubble.dart';
import '../tiling/tile_viewport_scope.dart';
import 'baked_chat_wallpaper.dart';
import 'motion_wallpaper_wrapper.dart';

/// Scene rendered inside [RealAppAppearancePreview].
enum AppearancePreviewScene {
  dialog,
  workspace,
}

/// Interactive live preview of the real Theaver UI using actual production
/// widgets ([BakedChatWallpaper], [FloatingGlassAppBar], [MessageBubble],
/// [LiquidGlassInputField], [ChatListItem], [LiquidGlassBottomBar], and
/// [ClassicBottomBar]) inside a bounded [TileViewportScope].
///
/// Shader-safe: never wraps [LiquidGlassLens] or [LiquidGlassMorph] descendants
/// in [Opacity] or [FadeTransition].
class RealAppAppearancePreview extends StatefulWidget {
  final double height;
  final AppearancePreviewScene initialScene;
  final ValueChanged<AppearancePreviewScene>? onSceneChanged;

  const RealAppAppearancePreview({
    super.key,
    this.height = 356,
    this.initialScene = AppearancePreviewScene.dialog,
    this.onSceneChanged,
  });

  @override
  State<RealAppAppearancePreview> createState() =>
      _RealAppAppearancePreviewState();
}

class _RealAppAppearancePreviewState extends State<RealAppAppearancePreview> {
  late AppearancePreviewScene _scene = widget.initialScene;
  final TextEditingController _previewInputCtrl = TextEditingController();
  final FocusNode _previewFocusNode = FocusNode(canRequestFocus: false);
  final ScrollController _dialogScrollCtrl = ScrollController();
  final ScrollController _workspaceScrollCtrl = ScrollController();
  int _workspaceTabIndex = 1;
  int _workspaceFilterIndex = 0;

  @override
  void dispose() {
    _previewInputCtrl.dispose();
    _previewFocusNode.dispose();
    _dialogScrollCtrl.dispose();
    _workspaceScrollCtrl.dispose();
    super.dispose();
  }

  void _setScene(AppearancePreviewScene next) {
    if (_scene == next) return;
    setState(() => _scene = next);
    widget.onSceneChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final themeProvider = context.watch<ThemeProvider>();
    final glassProvider = context.watch<LiquidGlassProvider?>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeTheme =
        isDark ? themeProvider.activeDarkTheme : themeProvider.activeLightTheme;
    final palette = activeTheme.palette;
    final glassEnabled = glassProvider?.enabled ?? false;
    final isLite = glassProvider?.isLite ?? false;

    final Widget previewContent = _scene == AppearancePreviewScene.dialog
        ? _DialogPreviewScene(
            theme: activeTheme,
            glassEnabled: glassEnabled,
            isLite: isLite,
            controller: _previewInputCtrl,
            focusNode: _previewFocusNode,
            scrollController: _dialogScrollCtrl,
          )
        : _WorkspacePreviewScene(
            theme: activeTheme,
            glassEnabled: glassEnabled,
            isLite: isLite,
            scrollController: _workspaceScrollCtrl,
            selectedTabIndex: _workspaceTabIndex,
            activeFilterIndex: _workspaceFilterIndex,
            onTabSelected: (idx) => setState(() => _workspaceTabIndex = idx),
            onFilterSelected: (idx) =>
                setState(() => _workspaceFilterIndex = idx),
          );

    final Widget framedScene = Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: palette.onSurface.withValues(alpha: isDark ? 0.14 : 0.08),
          width: 0.75,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27.25),
        child: TileViewportScope(
          tileId: 'appearance_preview_tile',
          isChatTile: _scene == AppearancePreviewScene.dialog,
          child: MediaQuery(
            // Preserve window MediaQuery.sizeOf so liquid_glass_easy shaders map
            // backdrop coordinates without offset, while compacting inner edge
            // padding to match the preview card frame.
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              viewPadding: const EdgeInsets.only(top: 6, bottom: 6),
              viewInsets: EdgeInsets.zero,
            ),
            child: BackdropGroup.of(context) == null
                ? BackdropGroup(child: previewContent)
                : previewContent,
          ),
        ),
      ),
    );

    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        framedScene,
        const SizedBox(height: 12),
        Center(
          child: SizedBox(
            width: 280,
            child: TheavSegmentedControl<AppearancePreviewScene>(
              selected: _scene,
              onChanged: _setScene,
              height: 36,
              expand: true,
              useGlass: glassEnabled,
              options: [
                TheavSegmentOption(
                  value: AppearancePreviewScene.dialog,
                  label: l10n.trOr('onboarding_preview_dialog', 'Dialog'),
                ),
                TheavSegmentOption(
                  value: AppearancePreviewScene.workspace,
                  label: l10n.trOr('onboarding_preview_workspace', 'Main Screen'),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (_hasProfileThemeProvider(context)) {
      return content;
    }
    return ChangeNotifierProvider<ProfileThemeProvider>(
      create: (_) => ProfileThemeProvider(),
      child: content,
    );
  }

  static bool _hasProfileThemeProvider(BuildContext context) {
    try {
      Provider.of<ProfileThemeProvider>(context, listen: false);
      return true;
    } on ProviderNotFoundException {
      return false;
    }
  }
}

class _DialogPreviewScene extends StatelessWidget {
  final TheavTheme theme;
  final bool glassEnabled;
  final bool isLite;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;

  const _DialogPreviewScene({
    required this.theme,
    required this.glassEnabled,
    required this.isLite,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = theme.palette;
    final contactName = l10n.trOr('onboarding_preview_contact_name', 'Anna');
    final onlineText = l10n.trOr('online', 'online');

    final msg1 = l10n.trOr(
      'onboarding_preview_msg_1',
      'Look how smooth the glass bar and message gradient look over this wallpaper.',
    );
    final msg2 = l10n.trOr(
      'onboarding_preview_msg_2',
      'And when scrolling under the header and input bar, the refraction updates live.',
    );
    final msg3 = l10n.trOr(
      'onboarding_preview_msg_3',
      'Everything switches cleanly between Material and Liquid Glass modes.',
    );
    final quoteTitle = l10n.trOr('onboarding_preview_quote', 'This theme looks great');

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: MotionWallpaperWrapper(
            enabled: theme.wallpaper.motionEnabled,
            child: BakedChatWallpaper(wallpaper: theme.wallpaper),
          ),
        ),
        Positioned.fill(
          child: ListView(
            controller: scrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(10, 74, 10, 80),
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: palette.chatDateBadge,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    l10n.trOr('today', 'Today'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: palette.chatDateBadgeText,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              MessageBubble(
                message: Message(
                  id: 'onb_prev_1',
                  chatId: 'onb_preview',
                  senderId: 'anna',
                  senderName: contactName,
                  content: msg1,
                  messageType: 'text',
                  createdAt: '10:14',
                  isRead: true,
                  isEdited: false,
                ),
                isMe: false,
                currentUserId: 'me',
                formatTime: (ts) => ts,
              ),
              const SizedBox(height: 8),
              MessageBubble(
                message: Message(
                  id: 'onb_prev_2',
                  chatId: 'onb_preview',
                  senderId: 'anna',
                  senderName: contactName,
                  content: '',
                  messageType: 'voice',
                  fileUrl: 'preview_voice.m4a',
                  duration: 12,
                  waveform: const [
                    5, 9, 14, 19, 11, 16, 24, 29, 21, 15,
                    12, 18, 26, 28, 22, 16, 10, 14, 21, 27,
                    23, 17, 11, 15, 22, 26, 19, 12, 8,
                  ],
                  createdAt: '10:15',
                  isRead: true,
                  isEdited: false,
                ),
                isMe: false,
                currentUserId: 'me',
                formatTime: (ts) => ts,
              ),
              const SizedBox(height: 8),
              MessageBubble(
                message: Message(
                  id: 'onb_prev_3',
                  chatId: 'onb_preview',
                  senderId: 'me',
                  senderName: 'Me',
                  content: msg2,
                  messageType: 'text',
                  replyToMessageId: 'onb_prev_1',
                  isQuote: true,
                  quoteText: quoteTitle,
                  replyInfo: ReplyInfo(
                    messageId: 'onb_prev_1',
                    senderId: 'anna',
                    senderName: contactName,
                    content: quoteTitle,
                    messageType: 'text',
                  ),
                  createdAt: '10:16',
                  isRead: true,
                  isEdited: false,
                ),
                isMe: true,
                currentUserId: 'me',
                formatTime: (ts) => ts,
              ),
              const SizedBox(height: 8),
              MessageBubble(
                message: Message(
                  id: 'onb_prev_4',
                  chatId: 'onb_preview',
                  senderId: 'me',
                  senderName: 'Me',
                  content: msg3,
                  messageType: 'text',
                  createdAt: '10:17',
                  isRead: true,
                  isEdited: false,
                ),
                isMe: true,
                currentUserId: 'me',
                formatTime: (ts) => ts,
              ),
            ],
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ChatBottomScrollEdge(height: 66),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: FloatingGlassAppBar(
            name: contactName,
            isOnline: true,
            statusText: onlineText,
            onBack: () {},
            onTitleTap: () {},
            onVoiceCall: () {},
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 6,
          child: LiquidGlassInputField(
            enabled: glassEnabled,
            isLite: isLite,
            controller: controller,
            focusNode: focusNode,
            hintText: l10n.trOr('chat_type_message', 'Message'),
            onEmoji: () {},
            onAttach: () {},
            onVoice: () {},
            onSend: () {},
          ),
        ),
      ],
    );
  }
}

class _WorkspacePreviewScene extends StatelessWidget {
  final TheavTheme theme;
  final bool glassEnabled;
  final bool isLite;
  final ScrollController scrollController;
  final int selectedTabIndex;
  final int activeFilterIndex;
  final ValueChanged<int> onTabSelected;
  final ValueChanged<int> onFilterSelected;

  const _WorkspacePreviewScene({
    required this.theme,
    required this.glassEnabled,
    required this.isLite,
    required this.scrollController,
    required this.selectedTabIndex,
    required this.activeFilterIndex,
    required this.onTabSelected,
    required this.onFilterSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = theme.palette;
    final filters = [
      l10n.trOr('filter_all', 'All'),
      l10n.trOr('filter_private', 'Personal'),
      l10n.trOr('filter_groups', 'Groups'),
    ];
    final now = DateTime.now();

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Container(color: palette.background),
        ),
        Positioned.fill(
          child: ListView(
            controller: scrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.only(top: 102, bottom: 86),
            children: [
              ChatListItem(
                chatName: l10n.trOr('chat_saved', 'Saved Messages'),
                lastMessage: l10n.trOr(
                  'onboarding_preview_saved_subtitle',
                  'Notes, media, and links',
                ),
                lastMessageTime: now.subtract(const Duration(minutes: 2)),
                avatarUrl: '',
                isOnline: false,
                isGroup: false,
                unreadCount: 0,
                onTap: () {},
              ),
              ChatListItem(
                chatName: l10n.trOr('onboarding_preview_contact_name', 'Anna'),
                lastMessage: l10n.trOr(
                  'onboarding_preview_msg_1',
                  'Look how smooth the glass bar looks over this wallpaper.',
                ),
                lastMessageTime: now.subtract(const Duration(minutes: 9)),
                avatarUrl: '',
                isOnline: true,
                isGroup: false,
                unreadCount: 2,
                onTap: () {},
              ),
              ChatListItem(
                chatName: 'Theaver News',
                lastMessage: l10n.trOr(
                  'onboarding_preview_news_subtitle',
                  'Themes, glass refraction, and instant cross-device sync.',
                ),
                lastMessageTime: now.subtract(const Duration(minutes: 26)),
                avatarUrl: '',
                isOnline: false,
                isGroup: true,
                unreadCount: 1,
                onTap: () {},
              ),
              ChatListItem(
                chatName: 'Design Team',
                lastMessage: l10n.trOr(
                  'onboarding_preview_team_subtitle',
                  'Updated palette contrast for light and OLED themes.',
                ),
                lastMessageTime: now.subtract(const Duration(hours: 2)),
                avatarUrl: '',
                isOnline: true,
                isGroup: true,
                unreadCount: 0,
                onTap: () {},
              ),
            ],
          ),
        ),
        Positioned(
          top: 8,
          left: 12,
          right: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40),
                  TheavFloatingSurface(
                    borderRadius: 20.0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      'Theaver',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: palette.onSurface,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: TheavFloatingSurface(
                      borderRadius: 20.0,
                      child: Center(
                        child: iconoir.MoreVert(
                          width: 19,
                          height: 19,
                          color: palette.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LiquidGlassFilterChips(
                enabled: glassEnabled,
                isLite: isLite,
                filters: filters,
                activeFilter: activeFilterIndex,
                unreadCounts: const [3, 2, 1],
                onFilterSelected: onFilterSelected,
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: glassEnabled
              ? LiquidGlassBottomBar(
                  selectedIndex: selectedTabIndex,
                  onTabSelected: onTabSelected,
                  onAddTap: () {},
                  isLite: isLite,
                  horizontalPadding: 14,
                  bottomPadding: 10,
                  barHeight: 58,
                )
              : ClassicBottomBar(
                  selectedIndex: selectedTabIndex,
                  onTabSelected: onTabSelected,
                  onAddTap: () {},
                  unreadCount: 3,
                  horizontalPadding: 14,
                  bottomPadding: 10,
                  barHeight: 58,
                ),
        ),
      ],
    );
  }
}
