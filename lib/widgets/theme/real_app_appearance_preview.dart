import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/profile_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_provider.dart';
import '../chat/chat_list_tile_item.dart';
import '../chat/chat_scaffold.dart';
import '../chat/chat_selection_header.dart';
import '../chat/classic_bottom_bar.dart';
import '../chat/floating_glass_app_bar.dart';
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
  bool _isTopMenuOpen = false;

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
    setState(() {
      _scene = next;
      _isTopMenuOpen = false;
    });
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

    final Widget rawScene = _scene == AppearancePreviewScene.dialog
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
            isTopMenuOpen: _isTopMenuOpen,
            onTabSelected: (idx) => setState(() => _workspaceTabIndex = idx),
            onTopMenuOpenChanged: (open) =>
                setState(() => _isTopMenuOpen = open),
          );

    final Widget previewContent = Theme(
      data: AppTheme.fromTheavTheme(activeTheme),
      child: rawScene,
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
        const ChatBottomScrollEdge(height: 66),
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
  final bool isTopMenuOpen;
  final ValueChanged<int> onTabSelected;
  final ValueChanged<bool> onTopMenuOpenChanged;

  const _WorkspacePreviewScene({
    required this.theme,
    required this.glassEnabled,
    required this.isLite,
    required this.scrollController,
    required this.selectedTabIndex,
    required this.isTopMenuOpen,
    required this.onTabSelected,
    required this.onTopMenuOpenChanged,
  });

  List<Chat> _buildPreviewChats(AppLocalizations l10n) {
    final now = DateTime.now().toUtc();
    String isoAgo(Duration delta) => now.subtract(delta).toIso8601String();
    return [
      Chat(
        id: 'onb_ws_saved',
        chatType: 'saved',
        name: l10n.trOr('chat_saved', 'Saved Messages'),
        lastMessage: l10n.trOr(
          'onboarding_preview_saved_subtitle',
          'Notes, media, and links',
        ),
        lastMessageTime: isoAgo(const Duration(minutes: 2)),
        lastMessageType: 'text',
        updatedAt: isoAgo(const Duration(minutes: 2)),
        unreadCount: 0,
      ),
      Chat(
        id: 'onb_ws_anna',
        chatType: 'private',
        name: l10n.trOr('onboarding_preview_contact_name', 'Anna'),
        lastMessage: l10n.trOr(
          'onboarding_preview_msg_1',
          'Look how smooth the glass bar looks over this wallpaper.',
        ),
        lastMessageTime: isoAgo(const Duration(minutes: 9)),
        lastMessageType: 'text',
        updatedAt: isoAgo(const Duration(minutes: 9)),
        unreadCount: 2,
        isOnline: true,
      ),
      Chat(
        id: 'onb_ws_news',
        chatType: 'channel',
        name: l10n.trOr('onboarding_preview_news_name', 'Theaver News'),
        lastMessage: l10n.trOr(
          'onboarding_preview_news_subtitle',
          'Themes, glass refraction, and instant cross-device sync.',
        ),
        lastMessageTime: isoAgo(const Duration(minutes: 26)),
        lastMessageType: 'text',
        updatedAt: isoAgo(const Duration(minutes: 26)),
        unreadCount: 1,
      ),
      Chat(
        id: 'onb_ws_team',
        chatType: 'group',
        name: l10n.trOr('onboarding_preview_team_name', 'Design Team'),
        lastMessage: l10n.trOr(
          'onboarding_preview_team_subtitle',
          'Updated palette contrast for light and OLED themes.',
        ),
        lastMessageTime: isoAgo(const Duration(hours: 2)),
        lastMessageType: 'text',
        updatedAt: isoAgo(const Duration(hours: 2)),
        lastMessageSenderId: 'me',
        lastReadOutboxMessageId: 10,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = theme.palette;
    final glassProvider = context.watch<LiquidGlassProvider?>();
    final isDark = theme.isDark;
    final chats = _buildPreviewChats(l10n);

    final topMenuItems = <SelectionMorphMenuItem>[
      SelectionMorphMenuItem(
        id: 'saved',
        label: l10n.trOr('chat_saved', 'Saved Messages'),
        iconBuilder: (color, size) =>
            iconoir.Bookmark(color: color, width: size, height: size),
      ),
      SelectionMorphMenuItem(
        id: 'contacts',
        label: l10n.trOr('contacts_title', 'Contacts'),
        iconBuilder: (color, size) =>
            iconoir.Group(color: color, width: size, height: size),
      ),
      SelectionMorphMenuItem(
        id: 'settings',
        label: l10n.trOr('nav_settings', 'Settings'),
        iconBuilder: (color, size) =>
            iconoir.Settings(color: color, width: size, height: size),
      ),
    ];

    final Widget topBar = ChatListAdaptiveTopBar(
      isSelectMode: false,
      selectedCount: 0,
      onCancelSelection: () {},
      normalTitle: l10n.trOr('nav_chats', 'Chats'),
      normalTitleKey: 'preview_chats',
      isTitleConnected: true,
      normalMenuItems: topMenuItems,
      isNormalMenuOpen: isTopMenuOpen,
      onNormalMenuOpenChanged: onTopMenuOpenChanged,
      onNormalMenuAction: (_) => onTopMenuOpenChanged(false),
    );

    final Widget chatListView = ListView.builder(
      controller: scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.only(top: 66, bottom: 84),
      itemCount: chats.length,
      itemBuilder: (ctx, i) {
        final chat = chats[i];
        return ChatListTileItem(
          chat: chat,
          isSelectMode: false,
          isSelected: false,
          isMuted: false,
          currentUserId: 'me',
          lastMessageIsRead: chat.lastMessageSenderId == 'me',
          onTap: () {
            if (isTopMenuOpen) onTopMenuOpenChanged(false);
          },
          onLongPress: () {},
          onSwipeAction: (_) async {},
        );
      },
    );

    if (glassEnabled && glassProvider != null) {
      return LayoutBuilder(
        builder: (layoutCtx, constraints) {
          final double width = constraints.maxWidth.isFinite &&
                  constraints.maxWidth > 0
              ? constraints.maxWidth
              : TileViewportScope.widthOf(layoutCtx);
          const double barHeight = 56.0;
          const double edgePadding = 12.0;
          const double spacing = 8.0;
          const double actionSize = 56.0;
          const double bottomMargin = 10.0;
          final double barWidth = math.max(
            120.0,
            width - edgePadding * 2 - actionSize - spacing,
          );

          final barStyle = glassProvider.createStyle(
            context: layoutCtx,
            cornerRadius: barHeight / 2,
            refractionIndex: 1.1,
            refractionWidth: 24.0,
            isLiteOverride: isLite,
          );
          final actionStyle = glassProvider.createStyle(
            context: layoutCtx,
            cornerRadius: barHeight / 2,
            refractionIndex: 1.1,
            refractionWidth: 24.0,
            isLiteOverride: isLite,
          );

          return LiquidGlassScaffold(
            key: ValueKey<String>(
              'preview_ws_glass_${isLite}_${isDark}_${theme.id}',
            ),
            pixelRatio: 1.0,
            useSync: true,
            batch: false,
            backgroundColor: palette.background,
            appBar: topBar,
            appBarTopMargin: 8.0,
            body: Stack(
              fit: StackFit.expand,
              children: [
                chatListView,
                if (isTopMenuOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => onTopMenuOpenChanged(false),
                    ),
                  ),
              ],
            ),
            bottomNavigationBarActionMargin: edgePadding,
            floatingActionButtonMargin: edgePadding,
            bottomNavigationBar: LiquidGlassTabBar(
              items: [
                LiquidGlassTabBarItem(
                  iconBuilder: (_, glyph) => iconoir.Settings(
                    color: glyph.color,
                    width: glyph.size,
                    height: glyph.size,
                  ),
                ),
                LiquidGlassTabBarItem(
                  iconBuilder: (_, glyph) => Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      iconoir.ChatBubble(
                        color: glyph.color,
                        width: glyph.size,
                        height: glyph.size,
                      ),
                      Positioned(
                        top: -4,
                        right: -10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: palette.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: const Text(
                            '3',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                LiquidGlassTabBarItem(
                  iconBuilder: (_, glyph) => iconoir.Search(
                    color: glyph.color,
                    width: glyph.size,
                    height: glyph.size,
                  ),
                ),
              ],
              selectedIndex: selectedTabIndex,
              onChanged: onTabSelected,
              width: barWidth,
              height: barHeight,
              alignment: Alignment.bottomLeft,
              margin: const EdgeInsets.only(
                left: edgePadding,
                bottom: bottomMargin,
              ),
              itemPadding: 3,
              swell: const LiquidGlassTabBarSwell(scale: 0.024),
              style: barStyle,
              itemStyle: LiquidGlassTabItemStyle(
                selectedColor: palette.primary,
                unselectedColor: isDark
                    ? const Color(0xFF8E8E93)
                    : const Color(0xFF636366),
                iconSize: 24,
                labelFontSize: 10,
                iconLabelGap: 0,
                underGlassIconSize: 28,
                underGlassLabelFontSize: 10,
                selectedFontWeight: FontWeight.w700,
                unselectedFontWeight: FontWeight.w600,
              ),
              pillStyle: LiquidGlassTabPillStyle(
                mode: LiquidGlassPillMode.both,
                show: true,
                animated: true,
                growHeight: isLite ? 0.0 : 6.0,
                rest: LiquidGlassStyle(
                  shape: const LiquidGlassShape.continuousRoundedRectangle(
                    cornerRadius: 28,
                    clipQuality: LiquidGlassClipQuality.roundedRectangle,
                  ),
                  color: isDark
                      ? const Color(0x38FFFFFF)
                      : const Color(0x2EAEAEB2),
                  liteGlass: isLite,
                ),
              ),
            ),
            bottomNavigationBarAction: SizedBox(
              width: actionSize,
              height: actionSize,
              child: LiquidGlassMorph(
                key: ValueKey<String>('preview_ws_plus_${isLite}_$isDark'),
                alignment: Alignment.bottomRight,
                motion: LiquidGlassMorphMotion.fluid,
                smoothness: 28,
                style: actionStyle,
                child: SizedBox(
                  width: actionSize,
                  height: actionSize,
                  child: Center(
                    child: iconoir.Plus(
                      width: 26,
                      height: 26,
                      color: isDark ? Colors.white : const Color(0xFF121215),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: ColoredBox(color: palette.background)),
        Positioned.fill(child: chatListView),
        if (isTopMenuOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => onTopMenuOpenChanged(false),
            ),
          ),
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: topBar,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ClassicBottomBar(
            selectedIndex: selectedTabIndex,
            onTabSelected: onTabSelected,
            onAddTap: () {},
            unreadCount: 3,
            horizontalPadding: 12,
            bottomPadding: 10,
            barHeight: 56,
            spacing: 8,
          ),
        ),
      ],
    );
  }
}
