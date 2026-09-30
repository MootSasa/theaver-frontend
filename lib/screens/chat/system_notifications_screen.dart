import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/regular/shield_check.dart';
import 'package:iconoir_flutter/regular/laptop.dart';
import 'package:iconoir_flutter/regular/check.dart';
import 'package:iconoir_flutter/regular/lock.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/chat_service.dart';
import '../../services/websocket_service.dart';
import '../../services/wallpaper_provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../widgets/chat/floating_glass_app_bar.dart';
import '../../widgets/chat/unread_separator.dart';
import '../../widgets/message/message_bubble.dart';
import '../../utils/swipe_back_route.dart';
import '../../utils/date_time_utils.dart';
import '../settings/devices_screen.dart';

/// Screen for the dedicated "System Notifications" ("Системные уведомления") chat.
/// Designed to visually match personal chats (PrivateChatScreen) in both Liquid Glass
/// and classic/matte (non-Liquid Glass) modes with wallpaper, floating cloud AppBar,
/// standard MessageBubble incoming message styling, date separators, and a matching bottom bar.
class SystemNotificationsScreen extends StatefulWidget {
  final String chatId;
  final String chatName;

  const SystemNotificationsScreen({
    Key? key,
    required this.chatId,
    required this.chatName,
  }) : super(key: key);

  @override
  State<SystemNotificationsScreen> createState() =>
      _SystemNotificationsScreenState();
}

class _SystemNotificationsScreenState extends State<SystemNotificationsScreen> {
  final List<Message> _messages = [];
  bool _isLoading = true;
  StreamSubscription? _wsSubscription;
  final ScrollController _scrollController = ScrollController();
  bool _showScrollDownFab = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeWebSocket();
    _markChatAsRead();

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _wsSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final shouldShow = offset > 150;
    if (shouldShow != _showScrollDownFab) {
      setState(() {
        _showScrollDownFab = shouldShow;
      });
    }
  }

  Future<void> _markChatAsRead() async {
    try {
      await ChatService.markMessagesAsRead(chatId: widget.chatId);
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final res = await ChatService.getMessages(chatId: widget.chatId, limit: 100);
      if (res['success'] == true && res['messages'] != null) {
        final msgs = res['messages'] as List<Message>;
        if (mounted) {
          setState(() {
            _messages.clear();
            _messages.addAll(msgs);
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _subscribeWebSocket() {
    _wsSubscription = WebSocketService().eventStream.listen((event) {
      if (event.type == WebSocketEventType.newMessage) {
        final cId = event.data['chat_id']?.toString();
        if (cId == widget.chatId && event.data['message'] != null) {
          final msgMap = event.data['message'] as Map<String, dynamic>;
          final msg = Message.fromJson(msgMap);
          if (mounted) {
            setState(() {
              if (!_messages.any((m) => m.id == msg.id)) {
                _messages.insert(0, msg);
              }
            });
            _markChatAsRead();
          }
        }
      }
    });
  }

  DateTime _dateOnly(DateTime dt) => DateTimeUtils.startOfDay(dt);

  String _formatDateLabel(DateTime dt, AppLocalizations l10n) {
    return DateTimeUtils.formatDateSeparator(dt, context: context);
  }

  String _formatTime(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final localDateTime = dateTime.toLocal();
      final hour = localDateTime.hour.toString().padLeft(2, '0');
      final minute = localDateTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final wallpaperPath = context.watch<WallpaperProvider>().wallpaperPath;
    final glassEnabled = context.watch<LiquidGlassProvider>().enabled;
    final mediaQuery = MediaQuery.of(context);

    // Height offset for floating cloud app bar (same as in PrivateChatScreen)
    final topPadding = mediaQuery.padding.top + 54.0 + 16.0;

    final String chatTitle = widget.chatName.isNotEmpty
        ? widget.chatName
        : l10n.translate('system_notifications_title');
    final String chatSubtitle = l10n.translate('system_notifications_subtitle');

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. Wallpaper background (exact match with PrivateChatScreen)
          if (wallpaperPath != null)
            Positioned.fill(
              child: Image.file(
                File(wallpaperPath),
                fit: BoxFit.cover,
              ),
            )
          else
            Positioned.fill(
              child: Container(
                color: theme.scaffoldBackgroundColor,
              ),
            ),

          // 2. Messages List with top shader fade under Floating AppBar
          Positioned.fill(
            child: ShaderMask(
              shaderCallback: (Rect bounds) {
                final statusBarHeight = mediaQuery.padding.top;
                final appBarBottom = statusBarHeight + 54 + 8;
                final fadeStart = appBarBottom + 20;
                final fadeEnd = statusBarHeight;

                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: const [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black,
                    Colors.black,
                  ],
                  stops: [
                    0.0,
                    (fadeEnd / bounds.height).clamp(0.0, 1.0),
                    (fadeStart / bounds.height).clamp(0.0, 1.0),
                    1.0,
                  ],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? _buildEmptyState(theme, l10n)
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: EdgeInsets.only(
                            top: topPadding,
                            bottom: 74.0,
                            left: 8.0,
                            right: 8.0,
                          ),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            return _buildMessageItem(index, theme, l10n);
                          },
                        ),
            ),
          ),

          // 3. Scroll Down FAB button
          Positioned(
            right: 14,
            bottom: 74,
            child: ScrollDownFab(
              visible: _showScrollDownFab,
              unreadCount: 0,
              onPressed: () {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              },
            ),
          ),

          // 4. Floating Cloud AppBar (used in BOTH glass and regular design,
          // matching PrivateChatScreen exactly)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FloatingGlassAppBar(
              name: chatTitle,
              isOnline: false,
              titleWidget: _buildAppBarTitle(theme, chatTitle),
              statusText: chatSubtitle,
              avatarWidget: _buildServiceAvatar(theme),
              isChannel: true,
              onBack: () => Navigator.pop(context),
              onTitleTap: () => _showChatInfoDialog(context, l10n),
              onAvatarTap: () => _showChatInfoDialog(context, l10n),
            ),
          ),

          // 5. Read-only bottom bar matching the exact slot, size, and styling
          // of the input field in both glass and regular/matte design
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomBar(glassEnabled, isDark, theme, l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarTitle(ThemeData theme, String title) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17.0,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: const Check(
            width: 10,
            height: 10,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildServiceAvatar(ThemeData theme) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.75),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: const ShieldCheck(
        width: 24,
        height: 24,
        color: Colors.white,
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: ShieldCheck(
              width: 40,
              height: 40,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.translate('system_no_notifications'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.translate('system_no_notifications_desc'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(int index, ThemeData theme, AppLocalizations l10n) {
    final message = _messages[index];
    final prevMessage =
        index < _messages.length - 1 ? _messages[index + 1] : null;

    final currentDt = DateTime.tryParse(message.createdAt) ?? DateTime.now();
    final prevDt = prevMessage != null
        ? (DateTime.tryParse(prevMessage.createdAt) ?? DateTime.now())
        : null;

    final currentDate = _dateOnly(currentDt);
    final prevDate = prevDt != null ? _dateOnly(prevDt) : null;

    final items = <Widget>[];

    // Date separator between messages of different days
    if (currentDate != prevDate) {
      items.add(DateSeparator(dateLabel: _formatDateLabel(currentDt, l10n)));
    }

    final bool isLoginAlert = message.content.contains('🔔 Новый вход') ||
        message.content.contains('New login') ||
        message.content.contains('Устройства');

    // Render using the exact same MessageBubble widget used in personal chat
    Widget messageWidget = MessageBubble(
      message: message,
      isMe: false,
      currentUserId: '',
      chatType: 'system',
      formatTime: _formatTime,
    );

    // If it's a login security alert, add an interactive shortcut button
    // beneath the bubble for quick navigation to Active Sessions
    if (isLoginAlert) {
      messageWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          messageWidget,
          Padding(
            padding: const EdgeInsets.only(left: 12.0, top: 4.0, bottom: 4.0),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  SwipeBackPageRoute(builder: (_) => const DevicesScreen()),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Laptop(
                      width: 15,
                      height: 15,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.translate('devices_title'),
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    items.add(messageWidget);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items,
    );
  }

  Widget _buildBottomBar(
    bool glassEnabled,
    bool isDark,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    const double kInputFillBorderRadius = 26.0;
    const double kInputHeight = 52.0;

    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Lock(
          width: 16,
          height: 16,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            l10n.translate('system_read_only_banner'),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    if (glassEnabled) {
      final glassSettings = LiquidGlassSettings(
        refractiveIndex: 1.15,
        thickness: 20,
        blur: 8,
        saturation: 1.5,
        lightIntensity: isDark ? 0.7 : 1.0,
        ambientStrength: isDark ? 0.2 : 0.5,
        lightAngle: math.pi / 2,
        glassColor: isDark
            ? const Color.fromARGB(40, 30, 30, 40)
            : const Color.fromARGB(50, 255, 255, 255),
      );

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        child: LiquidGlassLayer(
          settings: glassSettings,
          child: FakeGlass(
            settings: glassSettings,
            shape: const LiquidRoundedSuperellipse(
                borderRadius: kInputFillBorderRadius),
            child: Container(
              height: kInputHeight,
              alignment: Alignment.center,
              child: content,
            ),
          ),
        ),
      );
    }

    // Classic / Regular (non-liquid-glass) design:
    // Matches the exact styling of LiquidGlassInputField._buildClassicInput
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kInputFillBorderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            height: kInputHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(kInputFillBorderRadius),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black12,
                width: 0.5,
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
  }

  void _showChatInfoDialog(BuildContext context, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const ShieldCheck(width: 24, height: 24, color: Colors.blue),
            const SizedBox(width: 10),
            Text(l10n.translate('system_notifications_title')),
          ],
        ),
        content: Text(
          '${l10n.translate('system_notifications_subtitle')}\n\n${l10n.translate('system_read_only_banner')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('ok')),
          ),
        ],
      ),
    );
  }
}
