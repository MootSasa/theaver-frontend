import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/community_models.dart';
import '../../models/theav_theme.dart';
import '../../services/account_manager.dart';
import '../../services/chat_service.dart';
import '../../services/database/app_database.dart';
import '../../services/glass_toast_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/search_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/common/peer_badges_widget.dart';
import '../../widgets/user/avatar_with_status.dart';
import '../community/create_community_screen.dart';
import 'create_channel_screen.dart';
import 'create_group_screen.dart';
import 'private_chat_screen.dart';

class CreatePrivateChatScreen extends StatefulWidget {
  final ValueChanged<Community>? onCommunityCreated;

  const CreatePrivateChatScreen({
    Key? key,
    this.onCommunityCreated,
  }) : super(key: key);

  @override
  State<CreatePrivateChatScreen> createState() =>
      _CreatePrivateChatScreenState();
}

class _CreatePrivateChatScreenState extends State<CreatePrivateChatScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  String _searchQuery = '';
  List<SearchResultUser> _recentUsers = [];
  List<SearchResultUser> _searchResults = [];
  bool _isLoading = false;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadInitialUsers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _tr(String key, String fallback) {
    try {
      final val = context.l10n.translate(key);
      if (val.isNotEmpty && val != key) return val;
    } catch (_) {}
    return fallback;
  }

  Future<void> _loadInitialUsers() async {
    setState(() => _isLoading = true);
    try {
      final merged = <String, SearchResultUser>{};

      // 1. Локальные собеседники из SQLite (мгновенно)
      try {
        final dbChats = await AppDatabase().getChats();
        for (final c in dbChats) {
          if (c.chatType == 'private' &&
              c.otherUserId != null &&
              c.otherUserId!.isNotEmpty) {
            merged[c.otherUserId!] = SearchResultUser(
              id: c.otherUserId!,
              username: c.username ?? '',
              name: c.name,
              avatarUrl: c.avatarUrl ?? '',
              bio: '',
              isOnline: c.isOnline,
              isBot: c.isBot,
              isVerified: c.isVerified,
            );
          }
        }
      } catch (_) {}

      if (mounted && merged.isNotEmpty) {
        setState(() {
          _recentUsers = merged.values.toList();
        });
      }

      // 2. Пользователи с сервера
      final remote = await SearchService.searchUsers(query: '');
      for (final u in remote) {
        merged[u.id] = u;
      }

      if (mounted) {
        setState(() {
          _recentUsers = merged.values.toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged() {
    final newQuery = _searchController.text;
    if (newQuery != _searchQuery) {
      setState(() {
        _searchQuery = newQuery;
      });
      _searchDebounce?.cancel();
      final q = _searchQuery.trim();
      if (q.isEmpty) {
        setState(() {
          _searchResults = [];
          _isLoading = false;
        });
        return;
      }
      final lower = q.toLowerCase();
      setState(() {
        _searchResults = _recentUsers
            .where((u) =>
                u.name.toLowerCase().contains(lower) ||
                u.username.toLowerCase().contains(lower))
            .toList();
      });
      _searchDebounce =
          Timer(const Duration(milliseconds: 220), _performRemoteSearch);
    }
  }

  Future<void> _performRemoteSearch() async {
    final q = _searchQuery.trim();
    if (q.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final users = await SearchService.searchUsers(query: q);
      if (mounted && _searchQuery.trim() == q) {
        final merged = <String, SearchResultUser>{};
        for (final u in _searchResults) {
          merged[u.id] = u;
        }
        for (final u in users) {
          merged[u.id] = u;
        }
        setState(() {
          _searchResults = merged.values.toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openSavedMessages() async {
    if (_isCreating) return;
    HapticUtils.tap();
    setState(() => _isCreating = true);
    try {
      final result = await ChatService.getOrCreateSavedChat();
      if (!mounted) return;
      if (result['success'] == true && result['chat'] != null) {
        final chat = result['chat'] as Chat;
        final savedAvatar = AccountManager().currentAccount?.avatarUrl ??
            AccountManager().currentAccount?.localAvatarPath;
        if (TilingLayoutController.instance.isWorkspaceMounted) {
          Navigator.of(context).pop();
          TilingLayoutController.instance.openChatInActiveTile(
            chatId: chat.id,
            chatType: 'saved',
            chatName: _tr('chat_saved_messages', 'Избранное'),
            avatarUrl: savedAvatar,
          );
          return;
        }
        Navigator.pushReplacement(
          context,
          SwipeBackPageRoute(
            builder: (_) => PrivateChatScreen(
              chatId: chat.id,
              otherUserName: _tr('chat_saved_messages', 'Избранное'),
              otherUserAvatar: savedAvatar,
            ),
          ),
        );
      } else {
        setState(() => _isCreating = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _onUserTap(SearchResultUser user) async {
    if (_isCreating) return;
    HapticUtils.tap();
    setState(() => _isCreating = true);

    try {
      final result = await ChatService.createChat(
        chatType: 'private',
        participantIds: [user.id],
      );

      if (!mounted) return;
      if (result['success'] == true) {
        final chat = result['chat'] as Chat;
        if (TilingLayoutController.instance.isWorkspaceMounted) {
          Navigator.of(context).pop();
          TilingLayoutController.instance.openChatInActiveTile(
            chatId: chat.id,
            chatType: 'private',
            chatName: user.name,
            avatarUrl: user.avatarUrl,
            otherUserId: user.id,
          );
          return;
        }
        Navigator.pushReplacement(
          context,
          SwipeBackPageRoute(
            builder: (_) => PrivateChatScreen(
              chatId: chat.id,
              otherUserName: user.name,
              otherUserAvatar: user.avatarUrl,
              otherUserOnline: user.isOnline,
              otherUserId: user.id,
            ),
          ),
        );
      } else {
        GlassToastService().show(
          context,
          result['message']?.toString() ?? 'Не удалось открыть чат',
        );
        setState(() => _isCreating = false);
      }
    } catch (e) {
      if (mounted) {
        GlassToastService().show(context, 'Ошибка: $e');
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = context.theav;
    final glassProvider = context.watch<LiquidGlassProvider>();
    final isGlass = glassProvider.enabled;
    final isLite = glassProvider.isLite;
    final primaryColor = theme.colorScheme.primary;
    final isSearching = _searchQuery.trim().isNotEmpty;
    final displayUsers = isSearching ? _searchResults : _recentUsers;

    return Scaffold(
      backgroundColor: palette.bgBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: iconoir.NavArrowLeft(
            width: 24,
            height: 24,
            color: palette.textPrimary,
          ),
        ),
        title: Text(
          _tr('chat_new_private', 'Новое сообщение'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 1. Стеклянная / матовая капсула поиска
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: _buildSurfaceCard(
                  context,
                  isGlass: isGlass,
                  isLite: isLite,
                  isDark: isDark,
                  cornerRadius: 18,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: TextStyle(
                        fontSize: 15.5,
                        color: palette.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: _tr(
                          'search_user_hint',
                          'Поиск по имени или @username...',
                        ),
                        hintStyle: TextStyle(color: palette.textTertiary),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: primaryColor,
                          size: 21,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.clear_rounded,
                                  size: 18,
                                  color: palette.textSecondary,
                                ),
                                onPressed: () => _searchController.clear(),
                              )
                            : null,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ),

              // 2. Список быстрых действий и контактов
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    // Быстрый переход к остальным типам чатов (когда строка поиска пуста)
                    if (!isSearching) ...[
                      _buildSurfaceCard(
                        context,
                        isGlass: isGlass,
                        isLite: isLite,
                        isDark: isDark,
                        child: Column(
                          children: [
                            _buildQuickTypeTile(
                              icon: const iconoir.Group(
                                width: 20,
                                height: 20,
                                color: Color(0xFF10B981),
                              ),
                              badgeColor: const Color(0xFF10B981),
                              title: _tr('chat_new_group', 'Создать группу'),
                              subtitle:
                                  'Беседа для друзей, команды и групповых звонков',
                              palette: palette,
                              onTap: () {
                                HapticUtils.tap();
                                Navigator.pushReplacement(
                                  context,
                                  SwipeBackPageRoute(
                                    builder: (_) => const CreateGroupScreen(),
                                  ),
                                );
                              },
                            ),
                            Divider(
                              height: 1,
                              indent: 62,
                              color: palette.borderSubtle,
                            ),
                            _buildQuickTypeTile(
                              icon: const iconoir.Megaphone(
                                width: 20,
                                height: 20,
                                color: Color(0xFF8B5CF6),
                              ),
                              badgeColor: const Color(0xFF8B5CF6),
                              title: _tr('chat_new_channel', 'Создать канал'),
                              subtitle:
                                  'Публикации и вещание на неограниченную аудиторию',
                              palette: palette,
                              onTap: () {
                                HapticUtils.tap();
                                Navigator.pushReplacement(
                                  context,
                                  SwipeBackPageRoute(
                                    builder: (_) => const CreateChannelScreen(),
                                  ),
                                );
                              },
                            ),
                            Divider(
                              height: 1,
                              indent: 62,
                              color: palette.borderSubtle,
                            ),
                            _buildQuickTypeTile(
                              icon: const Icon(
                                Icons.hub_rounded,
                                size: 20,
                                color: Color(0xFFF59E0B),
                              ),
                              badgeColor: const Color(0xFFF59E0B),
                              title: 'Создать сообщество',
                              subtitle:
                                  'Категории, текстовые/голосовые комнаты и стримы 144 FPS',
                              palette: palette,
                              onTap: () {
                                HapticUtils.tap();
                                Navigator.pushReplacement(
                                  context,
                                  SwipeBackPageRoute(
                                    builder: (_) => CreateCommunityScreen(
                                      onCommunityCreated:
                                          widget.onCommunityCreated,
                                    ),
                                  ),
                                );
                              },
                            ),
                            Divider(
                              height: 1,
                              indent: 62,
                              color: palette.borderSubtle,
                            ),
                            _buildQuickTypeTile(
                              icon: const Icon(
                                Icons.link_rounded,
                                size: 20,
                                color: Color(0xFFEC4899),
                              ),
                              badgeColor: const Color(0xFFEC4899),
                              title: 'Войти по коду или ссылке',
                              subtitle:
                                  'Присоединиться к сообществу, группе или каналу',
                              palette: palette,
                              onTap: () {
                                HapticUtils.tap();
                                Navigator.pushReplacement(
                                  context,
                                  SwipeBackPageRoute(
                                    builder: (_) => CreateCommunityScreen(
                                      initialJoinMode: true,
                                      onCommunityCreated:
                                          widget.onCommunityCreated,
                                    ),
                                  ),
                                );
                              },
                            ),
                            Divider(
                              height: 1,
                              indent: 62,
                              color: palette.borderSubtle,
                            ),
                            _buildQuickTypeTile(
                              icon: Icon(
                                Icons.bookmark_rounded,
                                size: 20,
                                color: primaryColor,
                              ),
                              badgeColor: primaryColor,
                              title: _tr('chat_saved_messages', 'Избранное'),
                              subtitle:
                                  'Личное облако для заметок, медиа и файлов',
                              palette: palette,
                              onTap: _openSavedMessages,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Заголовок секции контактов / результатов поиска
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Text(
                            isSearching
                                ? 'РЕЗУЛЬТАТЫ ПОИСКА'
                                : 'КОНТАКТЫ И НЕДАВНИЕ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: palette.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          if (_isLoading)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),

                    if (displayUsers.isEmpty && !_isLoading)
                      _buildSurfaceCard(
                        context,
                        isGlass: isGlass,
                        isLite: isLite,
                        isDark: isDark,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 36,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                isSearching
                                    ? Icons.person_off_outlined
                                    : Icons.person_search_rounded,
                                size: 48,
                                color: palette.textTertiary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isSearching
                                    ? _tr(
                                        'search_no_users',
                                        'Пользователи по запросу «{query}» не найдены',
                                      ).replaceAll('{query}', _searchQuery)
                                    : _tr(
                                        'search_user_start_typing',
                                        'Введите имя или @username пользователя в строке поиска выше',
                                      ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (displayUsers.isNotEmpty)
                      _buildSurfaceCard(
                        context,
                        isGlass: isGlass,
                        isLite: isLite,
                        isDark: isDark,
                        child: Column(
                          children: [
                            for (int i = 0; i < displayUsers.length; i++) ...[
                              if (i > 0)
                                Divider(
                                  height: 1,
                                  indent: 68,
                                  color: palette.borderSubtle,
                                ),
                              _buildUserTile(
                                displayUsers[i],
                                palette: palette,
                                primaryColor: primaryColor,
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_isCreating)
            Container(
              color: Colors.black38,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickTypeTile({
    required Widget icon,
    required Color badgeColor,
    required String title,
    required String subtitle,
    required TheavPalette palette,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: icon,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            iconoir.NavArrowRight(
              width: 18,
              height: 18,
              color: palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserTile(
    SearchResultUser user, {
    required TheavPalette palette,
    required Color primaryColor,
  }) {
    final subtitleParts = <String>[];
    if (user.username.isNotEmpty) {
      subtitleParts.add('@${user.username}');
    }
    if (user.bio.isNotEmpty) {
      subtitleParts.add(user.bio);
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: AvatarWithStatus(
        avatarUrl: getValidAvatarUrl(user.avatarUrl),
        name: user.name,
        radius: 21,
        isOnline: user.isOnline,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: palette.textPrimary,
              ),
            ),
          ),
          PeerBadgesRow(isBot: user.isBot, isVerified: user.isVerified),
        ],
      ),
      subtitle: subtitleParts.isNotEmpty
          ? Text(
              subtitleParts.join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: palette.textSecondary,
              ),
            )
          : null,
      trailing: iconoir.NavArrowRight(
        width: 18,
        height: 18,
        color: palette.textTertiary,
      ),
      onTap: _isCreating ? null : () => _onUserTap(user),
    );
  }

  Widget _buildSurfaceCard(
    BuildContext context, {
    required bool isGlass,
    required bool isLite,
    required bool isDark,
    required Widget child,
    double cornerRadius = 20,
  }) {
    if (isGlass) {
      final glassProvider = context.watch<LiquidGlassProvider>();
      final style = glassProvider.createStyle(
        context: context,
        isLiteOverride: isLite,
        shape: LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: cornerRadius,
        ),
      );
      return LiquidGlassLens(
        style: style,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(cornerRadius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.08),
              width: 0.6,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: child,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(cornerRadius),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.6,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }
}
