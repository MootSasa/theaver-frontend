import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:image_picker/image_picker.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../../models/community_models.dart';
import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/community_service.dart';
import '../../services/file_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../chat/channel_screen.dart';
import '../chat/group_chat_screen.dart';
import 'community_screen.dart';

class _CommunityTemplateChannel {
  final String name;
  final String type; // 'text' | 'voice' | 'stage' | 'announcement'
  final String topic;

  const _CommunityTemplateChannel({
    required this.name,
    required this.type,
    this.topic = '',
  });
}

class _CommunityTemplateCategory {
  final String name;
  final List<_CommunityTemplateChannel> channels;

  const _CommunityTemplateCategory({
    required this.name,
    required this.channels,
  });
}

class _CommunityTemplate {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<_CommunityTemplateCategory> categories;

  const _CommunityTemplate({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.categories,
  });
}

const List<_CommunityTemplate> _kCommunityTemplates = [
  _CommunityTemplate(
    id: 'standard',
    title: 'Стандартный',
    subtitle: 'Текстовые каналы и голосовая комната до 144 FPS',
    icon: Icons.hub_rounded,
    accent: Color(0xFF3B82F6),
    categories: [
      _CommunityTemplateCategory(
        name: 'Инфо и общение',
        channels: [
          _CommunityTemplateChannel(
            name: 'новости',
            type: 'announcement',
            topic: 'Важные объявления сообщества',
          ),
          _CommunityTemplateChannel(
            name: 'общий',
            type: 'text',
            topic: 'Основной чат для всех участников',
          ),
        ],
      ),
      _CommunityTemplateCategory(
        name: 'Голосовые комнаты',
        channels: [
          _CommunityTemplateChannel(
            name: 'Основная • 144 FPS',
            type: 'voice',
            topic: 'Голосовой чат и демонстрация экрана',
          ),
        ],
      ),
    ],
  ),
  _CommunityTemplate(
    id: 'gaming',
    title: 'Гейминг & Стримы',
    subtitle: 'Комнаты для 144 FPS стримов, пати и хайлайтов',
    icon: Icons.sports_esports_rounded,
    accent: Color(0xFF8B5CF6),
    categories: [
      _CommunityTemplateCategory(
        name: 'Текстовые каналы',
        channels: [
          _CommunityTemplateChannel(
            name: 'анонсы',
            type: 'announcement',
            topic: 'Расписание игр и турниров',
          ),
          _CommunityTemplateChannel(
            name: 'чат-игроков',
            type: 'text',
            topic: 'Обсуждение игр и поиск тиммейтов',
          ),
          _CommunityTemplateChannel(
            name: 'клипы-и-скрины',
            type: 'text',
            topic: 'Лучшие моменты и медиа',
          ),
        ],
      ),
      _CommunityTemplateCategory(
        name: 'Стримы и Голос (144 FPS)',
        channels: [
          _CommunityTemplateChannel(
            name: 'Стрим-зал 144 FPS',
            type: 'voice',
            topic: 'Трансляции экрана вплоть до 4K 144 FPS',
          ),
          _CommunityTemplateChannel(
            name: 'Пати #1',
            type: 'voice',
            topic: 'Командная комната',
          ),
        ],
      ),
    ],
  ),
  _CommunityTemplate(
    id: 'study',
    title: 'Учёба & Команда',
    subtitle: 'Трибуна для лекций, материалы и рабочие созвоны',
    icon: Icons.school_rounded,
    accent: Color(0xFF10B981),
    categories: [
      _CommunityTemplateCategory(
        name: 'Материалы и задачи',
        channels: [
          _CommunityTemplateChannel(
            name: 'объявления',
            type: 'announcement',
            topic: 'Дедлайны и важные новости курса/проекта',
          ),
          _CommunityTemplateChannel(
            name: 'обсуждение',
            type: 'text',
            topic: 'Вопросы, ответы и обсуждение задач',
          ),
          _CommunityTemplateChannel(
            name: 'конспекты-и-код',
            type: 'text',
            topic: 'Полезные ссылки и файлы',
          ),
        ],
      ),
      _CommunityTemplateCategory(
        name: 'Аудитории',
        channels: [
          _CommunityTemplateChannel(
            name: 'Лекторий (Трибуна)',
            type: 'stage',
            topic: 'Выступления спикеров с поднятием руки',
          ),
          _CommunityTemplateChannel(
            name: 'Рабочая комната',
            type: 'voice',
            topic: 'Совместный кодинг и демонстрация экрана',
          ),
        ],
      ),
    ],
  ),
  _CommunityTemplate(
    id: 'empty',
    title: 'С нуля',
    subtitle: 'Чистое сообщество для ручной настройки структуры',
    icon: Icons.grid_view_rounded,
    accent: Color(0xFFF59E0B),
    categories: [],
  ),
];

/// Полноценный экран создания сообщества или входа по коду/ссылке
/// с поддержкой Material Matte и Liquid Glass (Full / Lite).
class CreateCommunityScreen extends StatefulWidget {
  final bool initialJoinMode;
  final ValueChanged<Community>? onCommunityCreated;

  const CreateCommunityScreen({
    super.key,
    this.initialJoinMode = false,
    this.onCommunityCreated,
  });

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();

  late bool _isJoinMode;
  String _selectedTemplateId = 'standard';
  File? _pickedAvatarFile;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _isJoinMode = widget.initialJoinMode;
    _nameController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  _CommunityTemplate get _selectedTemplate => _kCommunityTemplates.firstWhere(
        (t) => t.id == _selectedTemplateId,
        orElse: () => _kCommunityTemplates.first,
      );

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

  String _extractCleanCode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.contains('/')) {
      final parts = trimmed
          .split('/')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) {
        return parts.last.split('?').first;
      }
    }
    return trimmed;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    HapticUtils.tap();

    if (_isJoinMode) {
      await _handleJoinByCode();
    } else {
      await _handleCreateCommunity();
    }
  }

  Future<void> _handleJoinByCode() async {
    final code = _extractCleanCode(_inviteCodeController.text);
    if (code.isEmpty) {
      GlassToastService().show(context, 'Введите код приглашения или ссылку');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // 1. Попробовать войти в сообщество по коду
      final comm = await CommunityService.joinByCode(code);
      if (comm != null && mounted) {
        CommunityService.cacheCommunity(comm);
        widget.onCommunityCreated?.call(comm);
        if (TilingLayoutController.instance.isWorkspaceMounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          TilingLayoutController.instance.openChatInActiveTile(
            chatId: 'community_${comm.id}',
            chatType: 'community',
            chatName: comm.name,
            avatarUrl: comm.avatarUrl,
            otherUserId: comm.id,
          );
          return;
        }
        Navigator.pushReplacement(
          context,
          SwipeBackPageRoute(
            builder: (_) => CommunityScreen(community: comm),
          ),
        );
        return;
      }

      // 2. Если это инвайт в группу или канал — пробуем через ChatService
      final chatJoin = await ChatService.joinByInviteLink(code);
      if (!mounted) return;
      if (chatJoin['success'] == true && chatJoin['chat'] != null) {
        final rawChat = chatJoin['chat'];
        final chat = rawChat is Chat
            ? rawChat
            : Chat.fromJson(Map<String, dynamic>.from(rawChat as Map));
        if (TilingLayoutController.instance.isWorkspaceMounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          TilingLayoutController.instance.openChatInActiveTile(
            chatId: chat.id,
            chatType: chat.chatType,
            chatName: chat.name,
            avatarUrl: chat.avatarUrl,
          );
          return;
        }
        if (chat.chatType == 'channel') {
          Navigator.pushReplacement(
            context,
            SwipeBackPageRoute(
              builder: (_) => ChannelScreen(
                channelId: chat.id,
                channelName: chat.name,
                channelAvatar: chat.avatarUrl,
              ),
            ),
          );
        } else {
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
        }
        return;
      }

      GlassToastService().show(
        context,
        chatJoin['message']?.toString() ??
            'Не удалось найти сообщество или чат по этому коду',
      );
    } catch (e) {
      if (mounted) {
        GlassToastService().show(context, 'Ошибка: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _handleCreateCommunity() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      GlassToastService().show(context, 'Введите название сообщества');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      String? uploadedAvatarUrl;
      if (_pickedAvatarFile != null) {
        try {
          final uploadRes = await FileService().uploadFile(_pickedAvatarFile!);
          if (uploadRes.url.isNotEmpty) {
            uploadedAvatarUrl = uploadRes.url;
          }
        } catch (e) {
          debugPrint('[CreateCommunityScreen] Avatar upload error: $e');
        }
      }

      final desc = _descController.text.trim();
      final template = _selectedTemplate;

      Community? created = await CommunityService.createCommunity(
        name: name,
        description: desc,
        avatarUrl: uploadedAvatarUrl,
      );

      // Если выбран шаблон и сообщество создано на сервере — создадим стартовые категории и каналы
      if (created != null &&
          template.categories.isNotEmpty &&
          created.categories.isEmpty &&
          created.channels.length <= 1) {
        for (int cIdx = 0; cIdx < template.categories.length; cIdx++) {
          final catSpec = template.categories[cIdx];
          final createdCat = await CommunityService.createCategory(
            created.id,
            name: catSpec.name,
            position: cIdx,
          );
          for (final chSpec in catSpec.channels) {
            await CommunityService.createChannel(
              created.id,
              name: chSpec.name,
              channelType: chSpec.type,
              categoryId: createdCat?.id,
              topic: chSpec.topic,
            );
          }
        }
        final refreshed = await CommunityService.getCommunity(created.id);
        if (refreshed != null) {
          created = refreshed;
        }
      }

      // Локальный fallback если сервер временно недоступен
      if (created == null) {
        final now = DateTime.now();
        final fallbackId = 'comm_${now.millisecondsSinceEpoch}';
        final localCats = <CommunityCategory>[];
        final localChans = <CommunityChannel>[];

        for (int cIdx = 0; cIdx < template.categories.length; cIdx++) {
          final catSpec = template.categories[cIdx];
          final catId = '${fallbackId}_cat_$cIdx';
          for (int chIdx = 0; chIdx < catSpec.channels.length; chIdx++) {
            final chSpec = catSpec.channels[chIdx];
            final ch = CommunityChannel(
              id: '${catId}_ch_$chIdx',
              communityId: fallbackId,
              categoryId: catId,
              name: chSpec.name,
              channelType: chSpec.type,
              topic: chSpec.topic,
              position: chIdx,
            );
            localChans.add(ch);
          }
          localCats.add(
            CommunityCategory(
              id: catId,
              communityId: fallbackId,
              name: catSpec.name,
              position: cIdx,
            ),
          );
        }

        created = Community(
          id: fallbackId,
          name: name,
          description: desc,
          avatarUrl: uploadedAvatarUrl ?? _pickedAvatarFile?.path,
          memberCount: 1,
          categories: localCats,
          channels: localChans,
          createdAt: now,
        );
      }

      CommunityService.cacheCommunity(created);
      if (!mounted) return;
      widget.onCommunityCreated?.call(created);
      if (TilingLayoutController.instance.isWorkspaceMounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        TilingLayoutController.instance.openChatInActiveTile(
          chatId: 'community_${created.id}',
          chatType: 'community',
          chatName: created.name,
          avatarUrl: created.avatarUrl,
          otherUserId: created.id,
        );
        return;
      }
      Navigator.pushReplacement(
        context,
        SwipeBackPageRoute(
          builder: (_) => CommunityScreen(community: created!),
        ),
      );
    } catch (e) {
      if (mounted) {
        GlassToastService().show(context, 'Ошибка создания сообщества: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
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
          _isJoinMode ? 'Вход по приглашению' : 'Новое сообщество',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          if (_isSubmitting)
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
              onPressed: _submit,
              tooltip: _isJoinMode ? 'Присоединиться' : 'Создать',
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
          // Переключатель режима: Создать / Войти по коду
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _buildModeSelector(
              context,
              isGlass: isGlass,
              isLite: isLite,
              isDark: isDark,
              palette: palette,
              primaryColor: primaryColor,
            ),
          ),
          Expanded(
            child: _isJoinMode
                ? _buildJoinModeBody(
                    context,
                    isGlass: isGlass,
                    isLite: isLite,
                    isDark: isDark,
                    palette: palette,
                    primaryColor: primaryColor,
                  )
                : _buildCreateModeBody(
                    context,
                    isGlass: isGlass,
                    isLite: isLite,
                    isDark: isDark,
                    palette: palette,
                    primaryColor: primaryColor,
                  ),
          ),
          // Нижняя кнопка действия
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _isJoinMode
                              ? Icons.login_rounded
                              : Icons.hub_rounded,
                          size: 20,
                        ),
                  label: Text(
                    _isJoinMode
                        ? 'Присоединиться'
                        : 'Создать сообщество',
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

  Widget _buildModeSelector(
    BuildContext context, {
    required bool isGlass,
    required bool isLite,
    required bool isDark,
    required TheavPalette palette,
    required Color primaryColor,
  }) {
    return _buildSurfaceCard(
      context,
      isGlass: isGlass,
      isLite: isLite,
      isDark: isDark,
      cornerRadius: 18,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Expanded(
              child: _buildModeTab(
                label: 'Создать сообщество',
                icon: Icons.hub_rounded,
                selected: !_isJoinMode,
                primaryColor: primaryColor,
                palette: palette,
                onTap: () {
                  if (_isJoinMode) {
                    HapticUtils.selection();
                    setState(() => _isJoinMode = false);
                  }
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildModeTab(
                label: 'Войти по коду',
                icon: Icons.link_rounded,
                selected: _isJoinMode,
                primaryColor: primaryColor,
                palette: palette,
                onTap: () {
                  if (!_isJoinMode) {
                    HapticUtils.selection();
                    setState(() => _isJoinMode = true);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTab({
    required String label,
    required IconData icon,
    required bool selected,
    required Color primaryColor,
    required TheavPalette palette,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? Colors.white : palette.textSecondary,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.white : palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateModeBody(
    BuildContext context, {
    required bool isGlass,
    required bool isLite,
    required bool isDark,
    required TheavPalette palette,
    required Color primaryColor,
  }) {
    final trimmedName = _nameController.text.trim();
    final initialLetter =
        trimmedName.isNotEmpty ? trimmedName[0].toUpperCase() : 'C';
    final template = _selectedTemplate;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        // 1. Squircle аватар сообщества
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        gradient: _pickedAvatarFile == null
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  primaryColor,
                                  primaryColor.withValues(alpha: 0.72),
                                ],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withValues(alpha: 0.28),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                        image: _pickedAvatarFile != null
                            ? DecorationImage(
                                image: FileImage(_pickedAvatarFile!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: _pickedAvatarFile == null
                          ? (trimmedName.isNotEmpty
                              ? Text(
                                  initialLetter,
                                  style: const TextStyle(
                                    fontSize: 38,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.hub_rounded,
                                  size: 42,
                                  color: Colors.white,
                                ))
                          : null,
                    ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.bgBase, width: 2.5),
                        ),
                        alignment: Alignment.center,
                        child: const iconoir.Camera(
                          width: 16,
                          height: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _pickedAvatarFile != null
                    ? 'Нажмите, чтобы сменить значок'
                    : 'Выбрать значок сообщества',
                style: TextStyle(
                  fontSize: 12.5,
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 2. Название и описание
        _buildSectionHeader('ОСНОВНАЯ ИНФОРМАЦИЯ', palette),
        const SizedBox(height: 8),
        _buildSurfaceCard(
          context,
          isGlass: isGlass,
          isLite: isLite,
          isDark: isDark,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Название сообщества',
                    hintText: 'Например: MIPT Dev & Gaming',
                    hintStyle: TextStyle(color: palette.textTertiary),
                    border: InputBorder.none,
                  ),
                ),
                Divider(height: 1, color: palette.borderSubtle),
                TextField(
                  controller: _descController,
                  maxLines: 3,
                  minLines: 1,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: palette.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Описание (необязательно)',
                    hintText:
                        'Расскажите, чему посвящено сообщество и какие комнаты здесь есть',
                    hintStyle: TextStyle(color: palette.textTertiary),
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 3. Выбор шаблона комнат
        _buildSectionHeader('ШАБЛОН КАНАЛОВ И КОМНАТ', palette),
        const SizedBox(height: 8),
        ..._kCommunityTemplates.map((tpl) {
          final isSelected = tpl.id == _selectedTemplateId;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildSurfaceCard(
              context,
              isGlass: isGlass,
              isLite: isLite,
              isDark: isDark,
              borderColorOverride:
                  isSelected ? tpl.accent.withValues(alpha: 0.75) : null,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  HapticUtils.selection();
                  setState(() => _selectedTemplateId = tpl.id);
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: tpl.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(tpl.icon, color: tpl.accent, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tpl.title,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: palette.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              tpl.subtitle,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isSelected ? tpl.accent : palette.textTertiary,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),

        // 4. Предпросмотр стартовой структуры
        if (template.categories.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildSectionHeader('БУДУТ СОЗДАНЫ КОМНАТЫ', palette),
          const SizedBox(height: 8),
          _buildSurfaceCard(
            context,
            isGlass: isGlass,
            isLite: isLite,
            isDark: isDark,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < template.categories.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    Text(
                      template.categories[i].name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final ch in template.categories[i].channels)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              ch.type == 'voice'
                                  ? Icons.volume_up_rounded
                                  : ch.type == 'stage'
                                      ? Icons.podcasts_rounded
                                      : ch.type == 'announcement'
                                          ? Icons.campaign_rounded
                                          : Icons.tag_rounded,
                              size: 18,
                              color: ch.type == 'voice'
                                  ? const Color(0xFF10B981)
                                  : ch.type == 'stage'
                                      ? const Color(0xFFF59E0B)
                                      : primaryColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                ch.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textPrimary,
                                ),
                              ),
                            ),
                            if (ch.topic.isNotEmpty)
                              Flexible(
                                child: Text(
                                  ch.topic,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: palette.textTertiary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildJoinModeBody(
    BuildContext context, {
    required bool isGlass,
    required bool isLite,
    required bool isDark,
    required TheavPalette palette,
    required Color primaryColor,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.link_rounded,
              size: 40,
              color: primaryColor,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Присоединиться по коду или ссылке',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Введите инвайт-код сообщества, закрытой группы или канала, чтобы мгновенно вступить.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        _buildSurfaceCard(
          context,
          isGlass: isGlass,
          isLite: isLite,
          isDark: isDark,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _inviteCodeController,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: 'Код или ссылка-приглашение',
                hintText: 'theav-abc123 или https://.../join/...',
                hintStyle: TextStyle(color: palette.textTertiary),
                border: InputBorder.none,
                prefixIcon: Icon(Icons.vpn_key_rounded, color: primaryColor),
              ),
            ),
          ),
        ),
      ],
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
    Color? borderColorOverride,
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
              color: borderColorOverride ??
                  (isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.08)),
              width: borderColorOverride != null ? 1.4 : 0.6,
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
          color: borderColorOverride ??
              (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06)),
          width: borderColorOverride != null ? 1.4 : 0.6,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }
}
