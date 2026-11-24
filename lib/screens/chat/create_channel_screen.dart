import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../services/chat_service.dart';
import '../../services/database/app_database.dart';
import '../../services/file_service.dart';
import '../../services/glass_toast_service.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import 'channel_screen.dart';

class CreateChannelScreen extends StatefulWidget {
  const CreateChannelScreen({Key? key}) : super(key: key);

  @override
  State<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends State<CreateChannelScreen> {
  static final RegExp _usernameRegex = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{2,63}$');

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  File? _pickedAvatarFile;
  bool _isPublic = true;
  bool _enableSignatures = false;
  bool _enableComments = true;
  bool _enableHistory = true;
  bool _isLoading = false;
  String? _usernameServerError;

  String get _cleanUsername =>
      _usernameController.text.trim().replaceAll('@', '');

  bool get _isUsernameValid {
    if (!_isPublic) return true;
    final clean = _cleanUsername;
    return clean.isEmpty || _usernameRegex.hasMatch(clean);
  }

  String? get _usernameValidationMessage {
    if (!_isPublic) return null;
    if (_usernameServerError != null) return _usernameServerError;
    final clean = _cleanUsername;
    if (clean.isEmpty) return null;
    if (!_usernameRegex.hasMatch(clean)) {
      return 'От 3 до 64 символов: латинские буквы, цифры и _, начинается с буквы';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      if (mounted) setState(() {});
    });
    _usernameController.addListener(() {
      if (!mounted) return;
      if (_usernameServerError != null) {
        setState(() => _usernameServerError = null);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _usernameController.dispose();
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
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 90,
    );
    if (picked != null && mounted) {
      setState(() {
        _pickedAvatarFile = File(picked.path);
      });
    }
  }

  Future<void> _createChannel() async {
    if (_isLoading) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      GlassToastService().show(
        context,
        _tr('channel_name_required', 'Введите название канала'),
      );
      return;
    }

    final rawUsername = _cleanUsername;
    if (_isPublic && !_isUsernameValid) {
      GlassToastService().showError(
        context,
        _usernameValidationMessage ?? 'Некорректный формат @username',
      );
      return;
    }

    HapticUtils.tap();
    setState(() => _isLoading = true);

    try {
      String? uploadedAvatarUrl;
      if (_pickedAvatarFile != null) {
        try {
          final uploadRes = await FileService().uploadFile(_pickedAvatarFile!);
          if (uploadRes.url.isNotEmpty) {
            uploadedAvatarUrl = uploadRes.url;
          }
        } catch (e) {
          debugPrint('[CreateChannelScreen] Avatar upload error: $e');
        }
      }

      final desc = _descriptionController.text.trim();

      final result = await ChatService.createChat(
        chatType: 'channel',
        name: name,
        description: desc,
        isPublic: _isPublic,
        username: _isPublic && rawUsername.isNotEmpty ? rawUsername : null,
        signMessages: _enableSignatures,
        historyForNewMembers: _enableHistory,
        createDiscussionGroup: _enableComments,
        participantIds: const [],
      );

      if (!mounted) return;
      if (result['success'] == true) {
        Chat chat = result['chat'] as Chat;

        // Если выбран аватар — сохраняем в настройки канала и локальную БД через ChatService
        if (uploadedAvatarUrl != null && uploadedAvatarUrl.isNotEmpty) {
          final settingsRes = await ChatService.updateGroupSettings(chat.id, {
            'name': name,
            'description': desc,
            'avatar_url': uploadedAvatarUrl,
            'is_public': _isPublic,
            'username': _isPublic ? rawUsername : '',
            'history_for_new': _enableHistory,
            'sign_messages': _enableSignatures,
          });
          if (settingsRes['success'] == true) {
            await AppDatabase().updateChatAvatar(chat.id, uploadedAvatarUrl);
            chat = chat.copyWith(avatarUrl: uploadedAvatarUrl);
          } else if (mounted) {
            GlassToastService().showError(
              context,
              settingsRes['message']?.toString() ??
                  'Не удалось сохранить аватар канала',
            );
          }
        }

        if (!mounted) return;
        if (TilingLayoutController.instance.isWorkspaceMounted) {
          Navigator.of(context).pop();
          TilingLayoutController.instance.openChatInActiveTile(
            chatId: chat.id,
            chatType: 'channel',
            chatName: chat.name,
            avatarUrl: chat.avatarUrl,
          );
          return;
        }
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
        final errMsg =
            result['message']?.toString() ?? 'Не удалось создать канал';
        final errCode = result['error_code']?.toString().toLowerCase() ?? '';
        if (errMsg.toLowerCase().contains('username') ||
            errCode.contains('username')) {
          setState(() {
            _usernameServerError = errMsg;
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
        GlassToastService().showError(context, errMsg);
      }
    } catch (e) {
      if (mounted) {
        GlassToastService().showError(context, 'Ошибка: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final primaryColor = palette.primary;
    final trimmedName = _nameController.text.trim();

    return SettingsFloatingScaffold(
      title: _tr('chat_new_channel', 'Новый канал'),
      backgroundColor: palette.bgBase,
      actions: [
        if (_isLoading)
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
            onTap: _createChannel,
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
                // 1. Герой-блок выбора аватара канала
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
                                shape: BoxShape.circle,
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
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withValues(alpha: 0.26),
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
                                          trimmedName[0].toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 38,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const iconoir.Megaphone(
                                          width: 40,
                                          height: 40,
                                          color: Colors.white,
                                        ))
                                  : null,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: primaryColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: palette.bgBase,
                                    width: 2.5,
                                  ),
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
                            ? 'Нажмите, чтобы изменить фотографию'
                            : _tr('channel_add_photo', 'Выбрать фото канала'),
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

                // 2. Название и описание канала
                TheavInsetGroup(
                  margin: EdgeInsets.zero,
                  header: 'О КАНАЛЕ',
                  dividerIndent: 16,
                  children: [
                    TheavInlineTextField(
                      controller: _nameController,
                      autofocus: true,
                      label: _tr('channel_name', 'Название канала'),
                      placeholder: _tr(
                        'channel_name_hint',
                        'Например: Новости проекта',
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.onSurface,
                      ),
                    ),
                    TheavInlineTextField(
                      controller: _descriptionController,
                      maxLines: 3,
                      minLines: 1,
                      label: _tr(
                        'channel_description',
                        'Описание (необязательно)',
                      ),
                      placeholder: _tr(
                        'channel_description_hint',
                        'Расскажите подписчикам о тематике канала',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 3. Тип канала (Публичный / Частный) + @username
                TheavInsetGroup(
                  margin: EdgeInsets.zero,
                  header: _tr('channel_type', 'ТИП КАНАЛА').toUpperCase(),
                  footer: _usernameValidationMessage,
                  children: [
                    TheavListRow(
                      leading: iconoir.Globe(
                        width: 20,
                        height: 20,
                        color: _isPublic ? primaryColor : palette.subtext,
                      ),
                      title: _tr('channel_public', 'Публичный канал'),
                      subtitle: _tr(
                        'channel_public_desc',
                        'Канал можно найти в поиске, подписаться может любой',
                      ),
                      trailing: TheavCheckCircle(
                        selected: _isPublic,
                        onTap: () => setState(() => _isPublic = true),
                      ),
                      onTap: () => setState(() => _isPublic = true),
                    ),
                    TheavListRow(
                      leading: iconoir.Lock(
                        width: 20,
                        height: 20,
                        color: !_isPublic ? primaryColor : palette.subtext,
                      ),
                      title: _tr('channel_private', 'Частный канал'),
                      subtitle: _tr(
                        'channel_private_desc',
                        'Подписаться можно только по пригласительной ссылке',
                      ),
                      trailing: TheavCheckCircle(
                        selected: !_isPublic,
                        onTap: () => setState(() => _isPublic = false),
                      ),
                      onTap: () => setState(() => _isPublic = false),
                    ),
                    if (_isPublic)
                      TheavInlineTextField(
                        controller: _usernameController,
                        label: 'Публичная ссылка (@username)',
                        placeholder: 'channel_username',
                        prefix: iconoir.AtSign(
                          width: 19,
                          height: 19,
                          color: primaryColor,
                        ),
                        suffix: _cleanUsername.isNotEmpty
                            ? (_isUsernameValid && _usernameServerError == null
                                ? const iconoir.CheckCircle(
                                    width: 18,
                                    height: 18,
                                    color: Color(0xFF34C759),
                                  )
                                : iconoir.WarningCircle(
                                    width: 18,
                                    height: 18,
                                    color: palette.error,
                                  ))
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // 4. Настройки вещания канала
                TheavInsetGroup(
                  margin: EdgeInsets.zero,
                  header: _tr('channel_settings', 'НАСТРОЙКИ ВЕЩАНИЯ').toUpperCase(),
                  footer: _tr(
                    'channel_info_box',
                    'Каналы предназначены для вещания сообщений неограниченной аудитории. Публиковать посты могут только администраторы.',
                  ),
                  children: [
                    TheavListRow(
                      leading: iconoir.EditPencil(
                        width: 20,
                        height: 20,
                        color: primaryColor,
                      ),
                      title: _tr('channel_signatures', 'Подписи авторов'),
                      subtitle: _tr(
                        'channel_signatures_desc',
                        'Указывать имя администратора под публикациями',
                      ),
                      trailing: TheavSwitch(
                        value: _enableSignatures,
                        onChanged: (v) => setState(() => _enableSignatures = v),
                      ),
                      onTap: () =>
                          setState(() => _enableSignatures = !_enableSignatures),
                    ),
                    TheavListRow(
                      leading: iconoir.ChatBubble(
                        width: 20,
                        height: 20,
                        color: primaryColor,
                      ),
                      title: _tr('channel_comments', 'Комментарии к постам'),
                      subtitle: _tr(
                        'channel_comments_desc',
                        'Разрешить подписчикам обсуждать публикации',
                      ),
                      trailing: TheavSwitch(
                        value: _enableComments,
                        onChanged: (v) => setState(() => _enableComments = v),
                      ),
                      onTap: () =>
                          setState(() => _enableComments = !_enableComments),
                    ),
                    TheavListRow(
                      leading: iconoir.Clock(
                        width: 20,
                        height: 20,
                        color: primaryColor,
                      ),
                      title: _tr('channel_history', 'История публикаций'),
                      subtitle: _tr(
                        'channel_history_desc',
                        'Новые подписчики увидят предыдущие посты',
                      ),
                      trailing: TheavSwitch(
                        value: _enableHistory,
                        onChanged: (v) => setState(() => _enableHistory = v),
                      ),
                      onTap: () =>
                          setState(() => _enableHistory = !_enableHistory),
                    ),
                  ],
                ),
              ],
      ),
    );
  }
}
