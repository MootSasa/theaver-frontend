import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/theav_theme_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/chat/chat_list_item.dart';
import '../../widgets/chat/classic_bottom_bar.dart';
import '../../widgets/chat/liquid_glass_filter_chips.dart';
import '../../widgets/chat/liquid_glass_input_field.dart';
import '../../widgets/message/message_bubble.dart';
import '../../widgets/theme/four_corner_gradient.dart';

/// Fullscreen Theme Preview Screen showing two interactive preview tabs:
/// Page 0: Realistic Chat Screen built from real MessageBubble components
/// Page 1: Realistic Main Screen (Chat List) built from real ChatListItem components
class ThemePreviewScreen extends StatefulWidget {
  final String? themeCode;
  final TheavTheme? initialTheme;

  const ThemePreviewScreen({
    Key? key,
    this.themeCode,
    this.initialTheme,
  }) : super(key: key);

  @override
  State<ThemePreviewScreen> createState() => _ThemePreviewScreenState();
}

class _ThemePreviewScreenState extends State<ThemePreviewScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _mockInputController = TextEditingController();
  int _currentPage = 0;
  int _activeMainFilter = 0;
  bool _isLoading = true;
  String? _errorMessage;
  TheavTheme? _theme;
  int _installCount = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialTheme != null) {
      _theme = widget.initialTheme;
      _isLoading = false;
      if (widget.themeCode != null) {
        _fetchPublicDetails(widget.themeCode!);
      }
    } else if (widget.themeCode != null) {
      _loadThemeByCode(widget.themeCode!);
    } else {
      _errorMessage = 'No theme specified';
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _mockInputController.dispose();
    super.dispose();
  }

  Future<void> _loadThemeByCode(String code) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final data = await TheavThemeService().fetchPublicTheme(code);
    if (!mounted) return;

    if (data != null && data['theme_data'] != null) {
      try {
        final parsedTheme = TheavTheme.fromJson(data['theme_data'] as Map<String, dynamic>);
        setState(() {
          _theme = parsedTheme;
          _installCount = (data['install_count'] as num?)?.toInt() ?? 0;
          _isLoading = false;
        });
        return;
      } catch (e) {
        debugPrint('Error parsing public theme: $e');
      }
    }

    setState(() {
      _errorMessage = 'Не удалось загрузить тему';
      _isLoading = false;
    });
  }

  Future<void> _fetchPublicDetails(String code) async {
    final data = await TheavThemeService().fetchPublicTheme(code);
    if (!mounted) return;
    if (data != null) {
      setState(() {
        _installCount = (data['install_count'] as num?)?.toInt() ?? 0;
      });
    }
  }

  Future<void> _applyTheme() async {
    if (_theme == null) return;
    HapticUtils.tap();

    final l10n = context.l10n;
    final themeService = TheavThemeService();

    // 1. Activate theme
    await themeService.setActiveTheme(_theme!);

    // 2. Increment remote install count if code was provided
    if (widget.themeCode != null && widget.themeCode!.isNotEmpty) {
      themeService.installPublicTheme(widget.themeCode!);
    }

    if (mounted) {
      GlassToastService().show(
        context,
        l10n.translate('theme_applied_toast'),
        icon: Icons.check,
      );
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.translate('theme_preview_title')),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null || _theme == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.translate('theme_preview_title')),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage ?? 'Ошибка',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.translate('common_back')),
              ),
            ],
          ),
        ),
      );
    }

    final effectiveTheme = _theme!;
    final themeData = AppTheme.fromTheavTheme(effectiveTheme);

    return Theme(
      data: themeData,
      child: Builder(
        builder: (themedContext) {
          final isDark = effectiveTheme.isDark;
          final bottomBarBg = effectiveTheme.palette.appBarBackground;
          final bottomBarBorder = isDark ? Colors.white12 : Colors.black12;

          return Scaffold(
            body: Stack(
              children: [
                // 1. PageView for Chat & Main Screen previews
                Positioned.fill(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (idx) {
                      setState(() => _currentPage = idx);
                    },
                    children: [
                      _buildChatPreviewPage(themedContext, effectiveTheme),
                      _buildMainScreenPreviewPage(themedContext, effectiveTheme),
                    ],
                  ),
                ),

                // 2. Persistent Bottom Action Bar (Cancel | Dots | Apply)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: bottomBarBg,
                      border: Border(
                        top: BorderSide(color: bottomBarBorder, width: 0.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Container(
                        height: 54,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Cancel Button
                            TextButton(
                              onPressed: () {
                                HapticUtils.tap();
                                Navigator.of(context).pop();
                              },
                              child: Text(
                                l10n.translate('cancel').toUpperCase(),
                                style: TextStyle(
                                  color: effectiveTheme.palette.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),

                            // 2-Dot Page Indicator
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildDot(isActive: _currentPage == 0, color: effectiveTheme.palette.primary),
                                const SizedBox(width: 8),
                                _buildDot(isActive: _currentPage == 1, color: effectiveTheme.palette.primary),
                              ],
                            ),

                            // Apply Button
                            TextButton(
                              onPressed: _applyTheme,
                              child: Text(
                                l10n.translate('theme_apply').toUpperCase(),
                                style: TextStyle(
                                  color: effectiveTheme.palette.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDot({required bool isActive, required Color color}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isActive ? 18.0 : 7.0,
      height: 7.0,
      decoration: BoxDecoration(
        color: isActive ? color : color.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(3.5),
      ),
    );
  }

  // --- PAGE 0: REALISTIC CHAT PREVIEW ---
  Widget _buildChatPreviewPage(BuildContext context, TheavTheme theme) {
    final l10n = context.l10n;
    final p = theme.palette;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // Wallpaper Background
        Positioned.fill(
          child: _buildWallpaperBackground(theme.wallpaper),
        ),

        // Chat Header + Messages + Mock Input
        Positioned.fill(
          child: Column(
            children: [
              // Chat Header
              Container(
                color: p.appBarBackground,
                padding: EdgeInsets.only(
                  top: statusBarHeight + 4,
                  bottom: 8,
                  left: 4,
                  right: 12,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: iconoir.NavArrowLeft(
                        width: 22,
                        height: 22,
                        color: p.appBarForeground,
                      ),
                      onPressed: () {
                        HapticUtils.tap();
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            theme.name,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: p.appBarForeground,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            l10n.translate('theme_installs_count').replaceAll('{count}', '$_installCount'),
                            style: TextStyle(
                              fontSize: 12,
                              color: p.subtext,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Real Message Bubbles List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(
                    left: 12,
                    right: 12,
                    top: 12,
                    bottom: 70, // Leave room for mock input & bottom bar
                  ),
                  children: [
                    // 1. Incoming Text Bubble
                    MessageBubble(
                      message: Message(
                        id: 'prev_1',
                        chatId: 'demo',
                        senderId: 'anna',
                        senderName: 'Анна',
                        content: 'Привет! Как твои дела? Посмотри какую красивую тему я нашел для Theaver.',
                        messageType: 'text',
                        createdAt: '08:01',
                        isRead: true,
                        isEdited: false,
                      ),
                      isMe: false,
                      currentUserId: 'me',
                      formatTime: (ts) => ts,
                    ),
                    const SizedBox(height: 8),

                    // 2. Incoming Voice Message Bubble
                    MessageBubble(
                      message: Message(
                        id: 'prev_2',
                        chatId: 'demo',
                        senderId: 'anna',
                        senderName: 'Анна',
                        content: '',
                        messageType: 'voice',
                        fileUrl: 'demo_voice.m4a',
                        duration: 15,
                        waveform: const [10, 18, 30, 50, 75, 90, 65, 45, 30, 20, 35, 60, 50, 25],
                        createdAt: '08:02',
                        isRead: true,
                        isEdited: false,
                      ),
                      isMe: false,
                      currentUserId: 'me',
                      formatTime: (ts) => ts,
                    ),
                    const SizedBox(height: 8),

                    // 3. Outgoing Reply Quote Message Bubble
                    MessageBubble(
                      message: Message(
                        id: 'prev_3',
                        chatId: 'demo',
                        senderId: 'me',
                        senderName: 'Я',
                        content: 'Это прекрасно! Мне очень нравится эта цветовая палитра.',
                        messageType: 'text',
                        replyToMessageId: 'quote_0',
                        isQuote: true,
                        quoteText: 'Посмотри какую красивую тему...',
                        replyInfo: const ReplyInfo(
                          messageId: 'quote_0',
                          senderId: 'anna',
                          senderName: 'Анна',
                          content: 'Посмотри какую красивую тему...',
                          messageType: 'text',
                        ),
                        createdAt: '08:03',
                        isRead: true,
                        isEdited: false,
                      ),
                      isMe: true,
                      currentUserId: 'me',
                      formatTime: (ts) => ts,
                    ),
                    const SizedBox(height: 8),

                    // 4. Outgoing Text Message Bubble
                    MessageBubble(
                      message: Message(
                        id: 'prev_4',
                        chatId: 'demo',
                        senderId: 'me',
                        senderName: 'Я',
                        content: 'Отличная погода сегодня! ☀️',
                        messageType: 'text',
                        createdAt: '08:04',
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

              // Exact Chat Input Bar from actual app component
              IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: 54.0 + MediaQuery.of(context).padding.bottom + 4.0,
                  ),
                  child: LiquidGlassInputField(
                    enabled: context.watch<LiquidGlassProvider?>()?.enabled ?? false,
                    isLite: context.watch<LiquidGlassProvider?>()?.isLite ?? false,
                    controller: _mockInputController,
                    hintText: l10n.translate('chat_type_message'),
                    onEmoji: () {},
                    onAttach: () {},
                    onVoice: () {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- PAGE 1: REALISTIC MAIN SCREEN (CHAT LIST) PREVIEW ---
  Widget _buildMainScreenPreviewPage(BuildContext context, TheavTheme theme) {
    final l10n = context.l10n;
    final isDark = theme.isDark;
    final p = theme.palette;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final glassProvider = context.watch<LiquidGlassProvider?>();
    final glassEnabled = glassProvider?.enabled ?? false;
    final isLite = glassProvider?.isLite ?? false;

    final filters = [
      l10n.translate('filter_all'),
      l10n.translate('filter_personal'),
      l10n.translate('filter_groups'),
      l10n.translate('filter_channels'),
    ];

    return Stack(
      children: [
        // Main Background
        Positioned.fill(
          child: Container(color: p.background),
        ),

        // Main App Bar + Filter Chips + Chat List
        Positioned.fill(
          child: Column(
            children: [
              // Main Screen App Bar matching actual main screen
              Container(
                color: p.appBarBackground,
                padding: EdgeInsets.only(
                  top: statusBarHeight + 4,
                  bottom: 8,
                  left: 16,
                  right: 8,
                ),
                child: SizedBox(
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Center(
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF2C2C2E)
                                : const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Theaver',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: p.appBarForeground,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        child: IconButton(
                          icon: iconoir.MoreVert(
                            width: 22,
                            height: 22,
                            color: p.appBarForeground,
                          ),
                          onPressed: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Filter chips (matching real main_screen)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: LiquidGlassFilterChips(
                  enabled: glassEnabled,
                  isLite: isLite,
                  filters: filters,
                  activeFilter: _activeMainFilter,
                  unreadCounts: const [3, 2, 1, 0],
                  onFilterSelected: (idx) {
                    setState(() => _activeMainFilter = idx);
                  },
                ),
              ),

              // Real Chat List Items
              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(
                    bottom: 54.0 + MediaQuery.of(context).padding.bottom + 70.0,
                  ),
                  children: [
                    ChatListItem(
                      chatName: l10n.translate('chat_saved') != 'chat_saved'
                          ? l10n.translate('chat_saved')
                          : 'Избранное',
                      lastMessage: 'Заметки, файлы и ссылки',
                      lastMessageTime: DateTime.now().subtract(const Duration(minutes: 2)),
                      avatarUrl: '',
                      isOnline: false,
                      isGroup: false,
                      unreadCount: 0,
                      onTap: () {},
                    ),
                    ChatListItem(
                      chatName: 'Theaver News',
                      lastMessage: 'Вышло обновление Theaver 1.0! Добавлена поддержка кастомных тем и ссылок.',
                      lastMessageTime: DateTime.now().subtract(const Duration(minutes: 15)),
                      avatarUrl: '',
                      isOnline: true,
                      isGroup: false,
                      unreadCount: 1,
                      onTap: () {},
                    ),
                    ChatListItem(
                      chatName: 'Анна',
                      lastMessage: 'Отправила тебе новые фото с прогулки 📸',
                      lastMessageTime: DateTime.now().subtract(const Duration(minutes: 42)),
                      avatarUrl: '',
                      isOnline: true,
                      isGroup: false,
                      unreadCount: 2,
                      onTap: () {},
                    ),
                    ChatListItem(
                      chatName: 'Дизайн и архитектура',
                      lastMessage: 'Обсуждение нового стиля интерфейса и палитры',
                      lastMessageTime: DateTime.now().subtract(const Duration(hours: 3)),
                      avatarUrl: '',
                      isOnline: false,
                      isGroup: true,
                      unreadCount: 0,
                      onTap: () {},
                    ),
                    ChatListItem(
                      chatName: 'Алексей',
                      lastMessage: 'Привет! Посмотри эту новую тему, она супер',
                      lastMessageTime: DateTime.now().subtract(const Duration(hours: 6)),
                      avatarUrl: '',
                      isOnline: false,
                      isGroup: false,
                      unreadCount: 0,
                      onTap: () {},
                    ),
                    ChatListItem(
                      chatName: 'Рабочий чат',
                      lastMessage: 'Встреча перенесена на 15:00',
                      lastMessageTime: DateTime.now().subtract(const Duration(days: 1)),
                      avatarUrl: '',
                      isOnline: false,
                      isGroup: true,
                      unreadCount: 0,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Bottom Navigation Bar matching real main screen
        Positioned(
          left: 0,
          right: 0,
          bottom: 54.0 + MediaQuery.of(context).padding.bottom + 4.0,
          child: IgnorePointer(
            child: ClassicBottomBar(
              selectedIndex: 1, // 'Чаты' selected
              onTabSelected: (_) {},
              onAddTap: () {},
              horizontalPadding: 16,
              bottomPadding: 0,
              barHeight: 56,
            ),
          ),
        ),
      ],
    );
  }

  // Helper to render wallpaper background accurately matching chat
  Widget _buildWallpaperBackground(TheavWallpaper wp) {
    Widget wallpaperBg;

    if (wp.type == 'image') {
      final imgProvider = wp.getImageProvider();
      if (imgProvider != null) {
        Widget img = Image(
          image: imgProvider,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) => Container(color: wp.backgroundColor),
        );
        if (wp.blurRadius > 0) {
          img = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: (wp.blurRadius / 4).clamp(0.5, 4.0),
              sigmaY: (wp.blurRadius / 4).clamp(0.5, 4.0),
            ),
            child: img,
          );
        }
        if (wp.dimming > 0) {
          img = Stack(
            fit: StackFit.expand,
            children: [
              img,
              Container(
                color: Colors.black.withValues(alpha: wp.dimming.clamp(0.0, 1.0)),
              ),
            ],
          );
        }
        wallpaperBg = img;
      } else {
        wallpaperBg = Container(color: wp.backgroundColor);
      }
    } else if (wp.fourCornerGradient != null) {
      wallpaperBg = CustomPaint(
        painter: FourCornerGradientPainter(
          topLeft: wp.fourCornerGradient!.topLeft,
          topRight: wp.fourCornerGradient!.topRight,
          bottomLeft: wp.fourCornerGradient!.bottomLeft,
          bottomRight: wp.fourCornerGradient!.bottomRight,
        ),
        child: const SizedBox.expand(),
      );
    } else {
      wallpaperBg = Container(color: wp.backgroundColor);
    }

    Widget? patternOverlay;
    if (wp.patternOpacity > 0) {
      final double buttonPatternOpacity = (wp.patternOpacity * 1.6).clamp(0.24, 0.60);
      Widget? svgWidget;
      if (wp.customSvgPath != null && File(wp.customSvgPath!).existsSync()) {
        svgWidget = SvgPicture.file(
          File(wp.customSvgPath!),
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            wp.patternColor.withValues(alpha: buttonPatternOpacity),
            BlendMode.srcIn,
          ),
        );
      } else if (wp.assetSvgPath != null && wp.assetSvgPath!.isNotEmpty) {
        svgWidget = SvgPicture.asset(
          wp.assetSvgPath!,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            wp.patternColor.withValues(alpha: buttonPatternOpacity),
            BlendMode.srcIn,
          ),
        );
      }
      if (svgWidget != null) {
        patternOverlay = svgWidget;
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        wallpaperBg,
        if (patternOverlay != null) patternOverlay,
      ],
    );
  }
}
