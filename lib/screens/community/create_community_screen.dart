import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../models/avatar_editor_models.dart';
import '../../models/community_models.dart';
import '../../services/chat_service.dart';
import '../../services/community_service.dart';
import '../../services/file_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/avatar_editor/theav_avatar_picker_sheet.dart';
import '../../widgets/community/community_channel_icon.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../chat/channel_screen.dart';
import '../chat/group_chat_screen.dart';
import 'community_screen.dart';

class _CommunityTemplateChannel {
  final String name;
  final String type; // 'text' | 'voice' | 'stage' | 'announcement' | 'forum'
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
  final Widget Function(Color color, double size) iconBuilder;
  final Color accent;
  final List<_CommunityTemplateCategory> categories;

  const _CommunityTemplate({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconBuilder,
    required this.accent,
    required this.categories,
  });
}

final List<_CommunityTemplate> _kCommunityTemplates = [
  _CommunityTemplate(
    id: 'standard',
    title: 'Стандартный',
    subtitle: 'Текстовые каналы и голосовая комната до 144 FPS',
    iconBuilder: (c, s) => iconoir.Community(color: c, width: s, height: s),
    accent: const Color(0xFF3B82F6),
    categories: const [
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
    iconBuilder: (c, s) => iconoir.Sparks(color: c, width: s, height: s),
    accent: const Color(0xFF8B5CF6),
    categories: const [
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
    iconBuilder: (c, s) => iconoir.Book(color: c, width: s, height: s),
    accent: const Color(0xFF10B981),
    categories: const [
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
            type: 'forum',
            topic: 'Вопросы, ответы и ветки задач',
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
    iconBuilder: (c, s) => iconoir.ViewGrid(color: c, width: s, height: s),
    accent: const Color(0xFFF59E0B),
    categories: const [],
  ),
];

/// Полноценный экран создания сообщества или входа по коду/ссылке
/// в единой дизайн-системе Theaver (Material 3 Matte и Liquid Glass).
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
  Uint8List? _pickedAvatarBytes;
  String? _pickedAvatarFileName;
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

  bool get _hasPickedAvatar =>
      _pickedAvatarFile != null ||
      (_pickedAvatarBytes != null && _pickedAvatarBytes!.isNotEmpty);

  ImageProvider? get _pickedAvatarProvider {
    if (_pickedAvatarBytes != null && _pickedAvatarBytes!.isNotEmpty) {
      return MemoryImage(_pickedAvatarBytes!);
    }
    if (_pickedAvatarFile != null) {
      return FileImage(_pickedAvatarFile!);
    }
    return null;
  }

  Future<void> _pickAvatar() async {
    HapticUtils.tap();
    final trimmedName = _nameController.text.trim();
    final picked = await TheavAvatarPickerSheet.pickAndEdit(
      context: context,
      maskShape: AvatarShapeMask.squircle,
      ctaMode: AvatarEditorCtaMode.done,
      subjectName: trimmedName.isNotEmpty ? trimmedName : null,
      canDeleteCurrent: _pickedAvatarFile != null || _pickedAvatarBytes != null,
    );
    if (picked == null || !mounted) return;
    if (picked.deletedCurrent) {
      setState(() {
        _pickedAvatarFile = null;
        _pickedAvatarBytes = null;
        _pickedAvatarFileName = null;
      });
      return;
    }
    if (picked.hasMedia) {
      setState(() {
        _pickedAvatarFile = picked.file;
        _pickedAvatarBytes = picked.bytes;
        _pickedAvatarFileName = picked.fileName;
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
      if (_hasPickedAvatar) {
        try {
          final uploadFile = _pickedAvatarFile ??
              File(
                (_pickedAvatarFileName != null &&
                        _pickedAvatarFileName!.trim().isNotEmpty)
                    ? _pickedAvatarFileName!.trim()
                    : 'avatar.jpg',
              );
          uploadedAvatarUrl = await FileService().uploadPublicAvatar(
            uploadFile,
            bytes: _pickedAvatarBytes,
            fileName: _pickedAvatarFileName,
          );
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
        skipDefaultChannels: template.categories.isNotEmpty,
      );

      if (created != null && template.categories.isNotEmpty) {
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

      if (created == null) {
        if (mounted) {
          GlassToastService().show(
            context,
            'Не удалось создать сообщество. Проверьте соединение с сервером.',
          );
        }
        return;
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
    final palette = context.theav;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: iconoir.NavArrowLeft(
            width: 24,
            height: 24,
            color: palette.onSurface,
          ),
        ),
        title: Text(
          _isJoinMode ? 'Вход по приглашению' : 'Новое сообщество',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.onSurface,
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
                color: palette.primary,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TheavSegmentedControl<bool>(
              selected: _isJoinMode,
              onChanged: (v) => setState(() => _isJoinMode = v),
              options: const [
                TheavSegmentOption(
                  value: false,
                  label: 'Создать',
                  icon: iconoir.Community(width: 16, height: 16),
                ),
                TheavSegmentOption(
                  value: true,
                  label: 'Войти по коду',
                  icon: iconoir.Link(width: 16, height: 16),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isJoinMode
                ? _buildJoinModeBody(context, palette)
                : _buildCreateModeBody(context, palette),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: TheavFloatingPillButton(
                  height: 50,
                  isPrimary: true,
                  enabled: !_isSubmitting,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : (_isJoinMode
                            ? const iconoir.Link(width: 18, height: 18)
                            : const iconoir.Community(width: 18, height: 18)),
                  label: _isJoinMode
                      ? 'Присоединиться'
                      : 'Создать сообщество',
                  onTap: _submit,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateModeBody(BuildContext context, TheavPalette palette) {
    final trimmedName = _nameController.text.trim();
    final template = _selectedTemplate;
    final avatarProvider = _pickedAvatarProvider;

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 20),
      children: [
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (avatarProvider != null)
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(92 * 0.30),
                          color: palette.primary.withValues(alpha: 0.14),
                          image: DecorationImage(
                            image: avatarProvider,
                            fit: BoxFit.cover,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                            width: 0.5,
                          ),
                        ),
                      )
                    else
                      CommunityAvatar(
                        avatarUrl: null,
                        name: trimmedName,
                        size: 92,
                        accentColor: palette.primary,
                        fontSize: 36,
                      ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: palette.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.background, width: 2.5),
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
                _hasPickedAvatar
                    ? 'Нажмите, чтобы сменить значок'
                    : 'Выбрать значок сообщества',
                style: TextStyle(
                  fontSize: 12.5,
                  color: palette.subtext,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TheavInsetGroup(
          header: 'ОСНОВНАЯ ИНФОРМАЦИЯ',
          children: [
            TheavInlineTextField(
              controller: _nameController,
              autofocus: true,
              label: 'Название сообщества',
              placeholder: 'Например: MIPT Dev & Gaming',
            ),
            TheavInlineTextField(
              controller: _descController,
              maxLines: 3,
              minLines: 1,
              label: 'Описание (необязательно)',
              placeholder:
                  'Расскажите, чему посвящено сообщество и какие комнаты здесь есть',
            ),
          ],
        ),
        TheavInsetGroup(
          header: 'ШАБЛОН КАНАЛОВ И КОМНАТ',
          children: _kCommunityTemplates.map((tpl) {
            final isSelected = tpl.id == _selectedTemplateId;
            return TheavListRow(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tpl.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: tpl.iconBuilder(tpl.accent, 21),
              ),
              title: tpl.title,
              subtitle: tpl.subtitle,
              trailing: TheavCheckCircle(
                selected: isSelected,
                activeColor: tpl.accent,
              ),
              onTap: () => setState(() => _selectedTemplateId = tpl.id),
            );
          }).toList(),
        ),
        if (template.categories.isNotEmpty)
          TheavInsetGroup(
            header: 'БУДУТ СОЗДАНЫ КОМНАТЫ',
            dividerIndent: 16,
            children: template.categories.expand((cat) {
              return [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Text(
                    cat.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: palette.primary,
                    ),
                  ),
                ),
                ...cat.channels.map(
                  (ch) => TheavListRow(
                    minHeight: 42,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    leading: CommunityChannelIcon(
                      channelType: ch.type,
                      size: 17,
                    ),
                    title: ch.name,
                    subtitle: ch.topic.isNotEmpty ? ch.topic : null,
                  ),
                ),
              ];
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildJoinModeBody(BuildContext context, TheavPalette palette) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 20),
      children: [
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(24),
            ),
            alignment: Alignment.center,
            child: iconoir.Link(
              width: 38,
              height: 38,
              color: palette.primary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Text(
                'Присоединиться по коду или ссылке',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Введите инвайт-код сообщества, закрытой группы или канала, чтобы мгновенно вступить.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: palette.subtext,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TheavInsetGroup(
          header: 'ПРИГЛАШЕНИЕ',
          children: [
            TheavInlineTextField(
              controller: _inviteCodeController,
              autofocus: true,
              label: 'Код или ссылка-приглашение',
              placeholder: 'theav-abc123 или https://.../join/...',
              prefix: iconoir.Link(
                width: 19,
                height: 19,
                color: palette.primary,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ],
    );
  }
}
