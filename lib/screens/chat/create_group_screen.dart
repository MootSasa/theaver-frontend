import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:image_picker/image_picker.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/theav_theme.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/database/app_database.dart';
import '../../services/file_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/search_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../widgets/common/peer_badges_widget.dart';
import '../../widgets/user/avatar_with_status.dart';
import 'group_chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({Key? key}) : super(key: key);

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  File? _pickedAvatarFile;
  List<SearchResultUser> _allUsers = [];
  List<SearchResultUser> _filteredUsers = [];
  final List<SearchResultUser> _selectedMembers = [];
  bool _isLoadingUsers = false;
  bool _isCreating = false;
  String _searchQuery = '';

  // Group settings
  bool _isPublic = false;
  bool _allowInvites = true;
  bool _enableHistory = true;
  int _slowModeInterval = 0;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      if (mounted) setState(() {});
    });
    _searchController.addListener(_onSearchChanged);
    _loadInitialUsers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameController.dispose();
    _descriptionController.dispose();
    _usernameController.dispose();
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

  Future<void> _pickAvatar() async {
    HapticUtils.tap();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 88,
    );
    if (picked != null && mounted) {
      setState(() {
        _pickedAvatarFile = File(picked.path);
      });
    }
  }

  void _onSearchChanged() {
    final newQuery = _searchController.text;
    if (newQuery != _searchQuery) {
      setState(() {
        _searchQuery = newQuery;
      });
      _searchDebounce?.cancel();
      final q = _searchQuery.trim().toLowerCase();
      if (q.isEmpty) {
        setState(() => _filteredUsers = _allUsers);
      } else {
        // Мгновенная локальная фильтрация
        setState(() {
          _filteredUsers = _allUsers
              .where((u) =>
                  u.name.toLowerCase().contains(q) ||
                  u.username.toLowerCase().contains(q))
              .toList();
        });
        _searchDebounce =
            Timer(const Duration(milliseconds: 220), _filterUsersRemote);
      }
    }
  }

  Future<void> _loadInitialUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final merged = <String, SearchResultUser>{};

      // 1. Локальные собеседники из базы данных (мгновенно)
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
          _allUsers = merged.values.toList();
          if (_searchQuery.trim().isEmpty) {
            _filteredUsers = _allUsers;
          }
        });
      }

      // 2. Пользователи с сервера
      final remote = await SearchService.searchUsers(query: '');
      for (final u in remote) {
        merged[u.id] = u;
      }

      if (mounted) {
        setState(() {
          _allUsers = merged.values.toList();
          if (_searchQuery.trim().isEmpty) {
            _filteredUsers = _allUsers;
          }
          _isLoadingUsers = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingUsers = false);
      }
    }
  }

  Future<void> _filterUsersRemote() async {
    final q = _searchQuery.trim();
    if (q.isEmpty) return;
    setState(() => _isLoadingUsers = true);
    try {
      final remote = await SearchService.searchUsers(query: q);
      if (mounted && _searchQuery.trim() == q) {
        final merged = <String, SearchResultUser>{};
        for (final u in _filteredUsers) {
          merged[u.id] = u;
        }
        for (final u in remote) {
          merged[u.id] = u;
        }
        setState(() {
          _filteredUsers = merged.values.toList();
          _isLoadingUsers = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingUsers = false);
      }
    }
  }

  void _toggleMember(SearchResultUser user) {
    HapticUtils.selection();
    setState(() {
      final idx = _selectedMembers.indexWhere((m) => m.id == user.id);
      if (idx != -1) {
        _selectedMembers.removeAt(idx);
      } else {
        _selectedMembers.add(user);
      }
    });
  }

  void _removeMember(SearchResultUser user) {
    HapticUtils.tap();
    setState(() {
      _selectedMembers.removeWhere((m) => m.id == user.id);
    });
  }

  String _slowModeLabel(int interval) {
    switch (interval) {
      case 0:
        return 'Выкл.';
      case 10:
        return '10 с';
      case 30:
        return '30 с';
      case 60:
        return '1 мин';
      case 300:
        return '5 мин';
      case 900:
        return '15 мин';
      default:
        return '$interval с';
    }
  }

  void _showSlowModeSheet() {
    final palette = context.theav;
    final primaryColor = Theme.of(context).colorScheme.primary;
    const options = [0, 10, 30, 60, 300, 900];

    showModalBottomSheet(
      context: context,
      backgroundColor: palette.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Медленный режим',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              for (final opt in options)
                ListTile(
                  title: Text(
                    _slowModeLabel(opt),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: _slowModeInterval == opt
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  trailing: _slowModeInterval == opt
                      ? iconoir.Check(
                          width: 20,
                          height: 20,
                          color: primaryColor,
                        )
                      : null,
                  onTap: () {
                    HapticUtils.selection();
                    setState(() => _slowModeInterval = opt);
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createGroup() async {
    if (_isCreating) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      GlassToastService().show(
        context,
        _tr('group_name_required', 'Введите название группы'),
      );
      return;
    }

    HapticUtils.tap();
    setState(() => _isCreating = true);

    try {
      String? uploadedAvatarUrl;
      if (_pickedAvatarFile != null) {
        try {
          final uploadRes = await FileService().uploadFile(_pickedAvatarFile!);
          if (uploadRes.url.isNotEmpty) {
            uploadedAvatarUrl = uploadRes.url;
          }
        } catch (e) {
          debugPrint('[CreateGroupScreen] Avatar upload error: $e');
        }
      }

      final participantIds = _selectedMembers.map((u) => u.id).toList();
      final desc = _descriptionController.text.trim();
      final cleanUsername =
          _usernameController.text.trim().replaceAll('@', '');

      final result = await ChatService.createChat(
        chatType: 'group',
        name: name,
        description: desc.isNotEmpty ? desc : null,
        username: _isPublic && cleanUsername.isNotEmpty ? cleanUsername : null,
        isPublic: _isPublic,
        participantIds: participantIds,
      );

      if (!mounted) return;
      if (result['success'] == true) {
        Chat chat = result['chat'] as Chat;

        // Сохраняем аватар, историю и медленный режим через group-settings
        if (uploadedAvatarUrl != null ||
            !_enableHistory ||
            _slowModeInterval > 0) {
          try {
            final token = await AuthService.getToken();
            final dio = Dio();
            await dio.put(
              '${AppConfig.baseUrl}/api/chats/${chat.id}/group-settings',
              data: {
                'name': name,
                'description': desc,
                if (uploadedAvatarUrl != null) 'avatar_url': uploadedAvatarUrl,
                'is_public': _isPublic,
                'username': _isPublic ? cleanUsername : '',
                'history_for_new': _enableHistory,
                'slow_mode_interval': _slowModeInterval,
              },
              options: Options(headers: {'Authorization': 'Bearer $token'}),
            );
            if (uploadedAvatarUrl != null) {
              await AppDatabase().updateChatAvatar(chat.id, uploadedAvatarUrl);
              chat = chat.copyWith(avatarUrl: uploadedAvatarUrl);
            }
          } catch (e) {
            debugPrint('[CreateGroupScreen] Update group settings error: $e');
          }
        }

        if (!mounted) return;
        if (TilingLayoutController.instance.isWorkspaceMounted) {
          Navigator.of(context).pop();
          TilingLayoutController.instance.openChatInActiveTile(
            chatId: chat.id,
            chatType: 'group',
            chatName: chat.name,
            avatarUrl: chat.avatarUrl,
          );
          return;
        }
        Navigator.pushReplacement(
          context,
          SwipeBackPageRoute(
            builder: (_) => GroupChatScreen(
              chatId: chat.id,
              groupName: chat.name,
              groupAvatar: chat.avatarUrl,
            ),
          ),
        );
      } else {
        GlassToastService().show(
          context,
          result['message']?.toString() ?? 'Не удалось создать группу',
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
    final trimmedName = _nameController.text.trim();

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
          _tr('chat_new_group', 'Новая группа'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          if (_isCreating)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _createGroup,
              tooltip: _tr('create', 'Создать'),
              icon: iconoir.Check(
                width: 24,
                height: 24,
                color: primaryColor,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                // 1. Профиль группы (аватар + название + описание)
                _buildSurfaceCard(
                  context,
                  isGlass: isGlass,
                  isLite: isLite,
                  isDark: isDark,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: _pickAvatar,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 68,
                                    height: 68,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: _pickedAvatarFile == null
                                          ? LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                primaryColor,
                                                primaryColor.withValues(
                                                  alpha: 0.72,
                                                ),
                                              ],
                                            )
                                          : null,
                                      image: _pickedAvatarFile != null
                                          ? DecorationImage(
                                              image:
                                                  FileImage(_pickedAvatarFile!),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    alignment: Alignment.center,
                                    child: _pickedAvatarFile == null
                                        ? (trimmedName.isNotEmpty
                                            ? Text(
                                                trimmedName[0].toUpperCase(),
                                                style: const TextStyle(
                                                  fontSize: 26,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const iconoir.Group(
                                                width: 28,
                                                height: 28,
                                                color: Colors.white,
                                              ))
                                        : null,
                                  ),
                                  Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: primaryColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: palette.surfaceElevated,
                                          width: 2,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: const iconoir.Camera(
                                        width: 13,
                                        height: 13,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: TextField(
                                controller: _nameController,
                                autofocus: true,
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  labelText: _tr(
                                    'group_name_hint',
                                    'Название группы',
                                  ),
                                  hintText: 'Например: Друзья / Команда',
                                  hintStyle:
                                      TextStyle(color: palette.textTertiary),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Divider(height: 16, color: palette.borderSubtle),
                        TextField(
                          controller: _descriptionController,
                          maxLines: 3,
                          minLines: 1,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: palette.textPrimary,
                          ),
                          decoration: InputDecoration(
                            labelText: _tr(
                              'group_description_hint',
                              'Описание группы (необязательно)',
                            ),
                            hintText: 'О чём эта группа и правила общения',
                            hintStyle: TextStyle(color: palette.textTertiary),
                            border: InputBorder.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // 2. Настройки группы
                _buildSectionHeader('НАСТРОЙКИ И ДОСТУП', palette),
                const SizedBox(height: 8),
                _buildSurfaceCard(
                  context,
                  isGlass: isGlass,
                  isLite: isLite,
                  isDark: isDark,
                  child: Column(
                    children: [
                      AdaptiveSwitchListTile(
                        secondary: Icon(
                          Icons.public_rounded,
                          color: primaryColor,
                        ),
                        title: Text(
                          _tr('group_public', 'Публичная группа'),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          _tr(
                            'group_public_desc',
                            'Доступна в глобальном поиске по @username',
                          ),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        value: _isPublic,
                        onChanged: (v) => setState(() => _isPublic = v),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: _isPublic
                            ? Column(
                                children: [
                                  Divider(
                                    height: 1,
                                    indent: 56,
                                    color: palette.borderSubtle,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    child: TextField(
                                      controller: _usernameController,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: palette.textPrimary,
                                      ),
                                      decoration: InputDecoration(
                                        labelText:
                                            'Публичная ссылка (@username)',
                                        hintText: 'group_username',
                                        hintStyle: TextStyle(
                                          color: palette.textTertiary,
                                        ),
                                        prefixText: '@',
                                        prefixIcon: Icon(
                                          Icons.alternate_email_rounded,
                                          size: 20,
                                          color: primaryColor,
                                        ),
                                        border: InputBorder.none,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                      Divider(
                        height: 1,
                        indent: 56,
                        color: palette.borderSubtle,
                      ),
                      AdaptiveSwitchListTile(
                        secondary: Icon(
                          Icons.history_rounded,
                          color: primaryColor,
                        ),
                        title: Text(
                          _tr(
                            'group_enable_history',
                            'История для новых участников',
                          ),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          _tr(
                            'group_enable_history_desc',
                            'Показывать предыдущие сообщения при вступлении',
                          ),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        value: _enableHistory,
                        onChanged: (v) => setState(() => _enableHistory = v),
                      ),
                      Divider(
                        height: 1,
                        indent: 56,
                        color: palette.borderSubtle,
                      ),
                      AdaptiveSwitchListTile(
                        secondary: Icon(
                          Icons.person_add_alt_1_rounded,
                          color: primaryColor,
                        ),
                        title: Text(
                          _tr(
                            'group_allow_invites',
                            'Разрешить приглашать участников',
                          ),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          _tr(
                            'group_allow_invites_desc',
                            'Участники смогут добавлять своих друзей',
                          ),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        value: _allowInvites,
                        onChanged: (v) => setState(() => _allowInvites = v),
                      ),
                      Divider(
                        height: 1,
                        indent: 56,
                        color: palette.borderSubtle,
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.timer_outlined,
                          color: primaryColor,
                        ),
                        title: Text(
                          'Медленный режим',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          'Интервал между отправкой сообщений участниками',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _slowModeLabel(_slowModeInterval),
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 4),
                            iconoir.NavArrowRight(
                              width: 18,
                              height: 18,
                              color: palette.textTertiary,
                            ),
                          ],
                        ),
                        onTap: _showSlowModeSheet,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 3. Участники группы
                Row(
                  children: [
                    _buildSectionHeader('УЧАСТНИКИ', palette),
                    const Spacer(),
                    if (_selectedMembers.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          'Выбрано: ${_selectedMembers.length}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: primaryColor,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Выбранные участники
                if (_selectedMembers.isNotEmpty) ...[
                  SizedBox(
                    height: 82,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedMembers.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final member = _selectedMembers[index];
                        return GestureDetector(
                          onTap: () => _removeMember(member),
                          child: SizedBox(
                            width: 64,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    AvatarWithStatus(
                                      avatarUrl: member.avatarUrl,
                                      name: member.name,
                                      radius: 24,
                                      isOnline: member.isOnline,
                                    ),
                                    Positioned(
                                      right: -2,
                                      top: -2,
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: palette.bgBase,
                                            width: 1.8,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  member.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: palette.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Поиск и список пользователей
                _buildSurfaceCard(
                  context,
                  isGlass: isGlass,
                  isLite: isLite,
                  isDark: isDark,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(
                            fontSize: 15,
                            color: palette.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: _tr(
                              'search_user_hint',
                              'Поиск людей по имени или @username...',
                            ),
                            hintStyle: TextStyle(color: palette.textTertiary),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: palette.textSecondary,
                              size: 20,
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
                      Divider(height: 1, color: palette.borderSubtle),
                      if (_isLoadingUsers && _filteredUsers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(28),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_filteredUsers.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(28),
                          child: Center(
                            child: Text(
                              _searchQuery.isEmpty
                                  ? 'Введите имя или @username, чтобы пригласить участников'
                                  : 'Пользователи не найдены',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        )
                      else
                        for (int i = 0; i < _filteredUsers.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 68,
                              color: palette.borderSubtle,
                            ),
                          _buildUserSelectTile(
                            _filteredUsers[i],
                            primaryColor: primaryColor,
                            palette: palette,
                          ),
                        ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Нижняя кнопка создания группы
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _isCreating ? null : _createGroup,
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: _isCreating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const iconoir.Group(
                          width: 20,
                          height: 20,
                          color: Colors.white,
                        ),
                  label: Text(
                    _selectedMembers.isEmpty
                        ? _tr('chat_new_group', 'Создать группу')
                        : 'Создать группу (${_selectedMembers.length + 1})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserSelectTile(
    SearchResultUser user, {
    required Color primaryColor,
    required TheavPalette palette,
  }) {
    final isSelected = _selectedMembers.any((m) => m.id == user.id);

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
      subtitle: user.username.isNotEmpty
          ? Text(
              '@${user.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: palette.textSecondary,
              ),
            )
          : null,
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? primaryColor : palette.textTertiary,
            width: 1.8,
          ),
        ),
        child: isSelected
            ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
            : null,
      ),
      onTap: () => _toggleMember(user),
    );
  }

  Widget _buildSectionHeader(String title, TheavPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: palette.textSecondary,
        ),
      ),
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
