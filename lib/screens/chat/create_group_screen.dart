import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:image_picker/image_picker.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/database/app_database.dart';
import '../../services/file_service.dart';
import '../../services/glass_toast_service.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../services/search_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/swipe_back_route.dart';
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
    const options = [0, 10, 30, 60, 300, 900];

    showTheavModalSheet<void>(
      context: context,
      title: 'Медленный режим',
      showCloseButton: true,
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 20),
      builder: (ctx) {
        return SingleChildScrollView(
          child: TheavInsetGroup(
            dividerIndent: 16,
            children: [
              for (final opt in options)
                TheavListRow(
                  title: _slowModeLabel(opt),
                  trailing: TheavCheckCircle(
                    selected: _slowModeInterval == opt,
                    onTap: () {
                      setState(() => _slowModeInterval = opt);
                      Navigator.pop(ctx);
                    },
                  ),
                  onTap: () {
                    setState(() => _slowModeInterval = opt);
                    Navigator.pop(ctx);
                  },
                ),
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
    final palette = context.theav;
    final primaryColor = palette.primary;
    final trimmedName = _nameController.text.trim();

    return SettingsFloatingScaffold(
      title: _tr('chat_new_group', 'Новая группа'),
      backgroundColor: palette.bgBase,
      actions: [
        if (_isCreating)
          SettingsHeaderAction(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: primaryColor,
              ),
            ),
          )
        else
          SettingsHeaderAction(
            tooltip: _tr('create', 'Создать'),
            foregroundColor: primaryColor,
            icon: iconoir.Check(width: 22, height: 22, color: primaryColor),
            onTap: _createGroup,
          ),
      ],
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          SettingsFloatingHeader.topClearanceOf(context) + 12,
          16,
          MediaQuery.paddingOf(context).bottom + 28,
        ),
        children: [
                // 1. Профиль группы (аватар + название + описание)
                _buildSurfaceCard(
                  context,
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
                              child: TheavInlineTextField(
                                controller: _nameController,
                                autofocus: true,
                                padding: EdgeInsets.zero,
                                label: _tr(
                                  'group_name_hint',
                                  'Название группы',
                                ),
                                placeholder: 'Например: Друзья / Команда',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Divider(height: 0.5, color: palette.divider),
                        const SizedBox(height: 6),
                        TheavInlineTextField(
                          controller: _descriptionController,
                          maxLines: 3,
                          minLines: 1,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          label: _tr(
                            'group_description_hint',
                            'Описание группы (необязательно)',
                          ),
                          placeholder: 'О чём эта группа и правила общения',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Настройки группы
                TheavInsetGroup(
                  margin: EdgeInsets.zero,
                  header: 'НАСТРОЙКИ И ДОСТУП',
                  children: [
                    TheavListRow(
                      leading: iconoir.Globe(
                        width: 20,
                        height: 20,
                        color: primaryColor,
                      ),
                      title: _tr('group_public', 'Публичная группа'),
                      subtitle: _tr(
                        'group_public_desc',
                        'Доступна в глобальном поиске по @username',
                      ),
                      trailing: TheavSwitch(
                        value: _isPublic,
                        onChanged: (v) => setState(() => _isPublic = v),
                      ),
                      onTap: () => setState(() => _isPublic = !_isPublic),
                    ),
                    if (_isPublic)
                      TheavInlineTextField(
                        controller: _usernameController,
                        label: 'Публичная ссылка (@username)',
                        placeholder: 'group_username',
                        prefix: iconoir.AtSign(
                          width: 19,
                          height: 19,
                          color: primaryColor,
                        ),
                      ),
                    TheavListRow(
                      leading: iconoir.Clock(
                        width: 20,
                        height: 20,
                        color: primaryColor,
                      ),
                      title: _tr(
                        'group_enable_history',
                        'История для новых участников',
                      ),
                      subtitle: _tr(
                        'group_enable_history_desc',
                        'Показывать предыдущие сообщения при вступлении',
                      ),
                      trailing: TheavSwitch(
                        value: _enableHistory,
                        onChanged: (v) => setState(() => _enableHistory = v),
                      ),
                      onTap: () =>
                          setState(() => _enableHistory = !_enableHistory),
                    ),
                    TheavListRow(
                      leading: iconoir.UserPlus(
                        width: 20,
                        height: 20,
                        color: primaryColor,
                      ),
                      title: _tr(
                        'group_allow_invites',
                        'Разрешить приглашать участников',
                      ),
                      subtitle: _tr(
                        'group_allow_invites_desc',
                        'Участники смогут добавлять своих друзей',
                      ),
                      trailing: TheavSwitch(
                        value: _allowInvites,
                        onChanged: (v) => setState(() => _allowInvites = v),
                      ),
                      onTap: () =>
                          setState(() => _allowInvites = !_allowInvites),
                    ),
                    TheavListRow(
                      leading: iconoir.Timer(
                        width: 20,
                        height: 20,
                        color: primaryColor,
                      ),
                      title: 'Медленный режим',
                      subtitle: 'Интервал между отправкой сообщений участниками',
                      valueText: _slowModeLabel(_slowModeInterval),
                      showChevron: true,
                      onTap: _showSlowModeSheet,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 3. Выбранные участники
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
                                      userId: member.id,
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
                                          color: palette.error,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: palette.background,
                                            width: 1.8,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: const iconoir.Xmark(
                                          width: 12,
                                          height: 12,
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
                                    color: palette.onSurface,
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

                // 4. Поиск и список пользователей
                TheavInsetGroup(
                  margin: EdgeInsets.zero,
                  header: _selectedMembers.isNotEmpty
                      ? 'УЧАСТНИКИ (${_selectedMembers.length})'
                      : 'УЧАСТНИКИ',
                  children: [
                    TheavInlineTextField(
                      controller: _searchController,
                      placeholder: _tr(
                        'search_user_hint',
                        'Поиск людей по имени или @username...',
                      ),
                      prefix: iconoir.Search(
                        width: 18,
                        height: 18,
                        color: palette.subtext,
                      ),
                      suffix: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () => _searchController.clear(),
                              child: iconoir.XmarkCircle(
                                width: 18,
                                height: 18,
                                color: palette.subtext,
                              ),
                            )
                          : null,
                    ),
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
                              color: palette.subtext,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      )
                    else
                      for (final user in _filteredUsers)
                        _buildUserSelectTile(
                          user,
                          primaryColor: primaryColor,
                          palette: palette,
                        ),
                  ],
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

    return TheavListRow(
      leading: AvatarWithStatus(
        userId: user.id,
        avatarUrl: getValidAvatarUrl(user.avatarUrl),
        name: user.name,
        radius: 21,
        isOnline: user.isOnline,
      ),
      titleWidget: Row(
        children: [
          Flexible(
            child: Text(
              user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: palette.onSurface,
              ),
            ),
          ),
          PeerBadgesRow(isBot: user.isBot, isVerified: user.isVerified),
        ],
      ),
      subtitle: user.username.isNotEmpty ? '@${user.username}' : null,
      trailing: TheavCheckCircle(
        selected: isSelected,
        onTap: () => _toggleMember(user),
      ),
      onTap: () => _toggleMember(user),
    );
  }

  Widget _buildSurfaceCard(
    BuildContext context, {
    required Widget child,
    double cornerRadius = 20,
  }) {
    return TheavInsetGroup(
      margin: EdgeInsets.zero,
      borderRadius: cornerRadius,
      children: [child],
    );
  }
}
