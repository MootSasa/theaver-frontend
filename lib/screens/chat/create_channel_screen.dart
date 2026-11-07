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
import '../../services/tiling_layout_controller.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/common/adaptive_switch.dart';
import 'channel_screen.dart';

class CreateChannelScreen extends StatefulWidget {
  const CreateChannelScreen({Key? key}) : super(key: key);

  @override
  State<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends State<CreateChannelScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  File? _pickedAvatarFile;
  bool _isPublic = true;
  bool _enableSignatures = false;
  bool _enableComments = true;
  bool _enableHistory = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      if (mounted) setState(() {});
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

      final rawUsername = _usernameController.text.trim().replaceAll('@', '');
      final desc = _descriptionController.text.trim();

      final result = await ChatService.createChat(
        chatType: 'channel',
        name: name,
        description: desc,
        isPublic: _isPublic,
        username: _isPublic && rawUsername.isNotEmpty ? rawUsername : null,
        participantIds: const [],
      );

      if (!mounted) return;
      if (result['success'] == true) {
        Chat chat = result['chat'] as Chat;

        // Если выбран аватар — сохраняем в настройки канала и локальную БД
        if (uploadedAvatarUrl != null && uploadedAvatarUrl.isNotEmpty) {
          try {
            final token = await AuthService.getToken();
            final dio = Dio();
            await dio.put(
              '${AppConfig.baseUrl}/api/chats/${chat.id}/group-settings',
              data: {
                'name': name,
                'description': desc,
                'avatar_url': uploadedAvatarUrl,
                'is_public': _isPublic,
                'username': _isPublic ? rawUsername : '',
                'history_for_new': _enableHistory,
              },
              options: Options(headers: {'Authorization': 'Bearer $token'}),
            );
            await AppDatabase().updateChatAvatar(chat.id, uploadedAvatarUrl);
            chat = chat.copyWith(avatarUrl: uploadedAvatarUrl);
          } catch (e) {
            debugPrint('[CreateChannelScreen] Set avatar error: $e');
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
        GlassToastService().show(
          context,
          result['message']?.toString() ?? 'Не удалось создать канал',
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        GlassToastService().show(context, 'Ошибка: $e');
        setState(() => _isLoading = false);
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
          _tr('chat_new_channel', 'Новый канал'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          if (_isLoading)
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
              onPressed: _createChannel,
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
                _buildSectionHeader('О КАНАЛЕ', palette),
                const SizedBox(height: 8),
                _buildSurfaceCard(
                  context,
                  isGlass: isGlass,
                  isLite: isLite,
                  isDark: isDark,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
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
                            labelText: _tr('channel_name', 'Название канала'),
                            hintText: _tr(
                              'channel_name_hint',
                              'Например: Новости проекта',
                            ),
                            hintStyle: TextStyle(color: palette.textTertiary),
                            border: InputBorder.none,
                          ),
                        ),
                        Divider(height: 1, color: palette.borderSubtle),
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
                              'channel_description',
                              'Описание (необязательно)',
                            ),
                            hintText: _tr(
                              'channel_description_hint',
                              'Расскажите подписчикам о тематике канала',
                            ),
                            hintStyle: TextStyle(color: palette.textTertiary),
                            border: InputBorder.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 3. Тип канала (Публичный / Частный) + @username
                _buildSectionHeader(
                  _tr('channel_type', 'ТИП КАНАЛА').toUpperCase(),
                  palette,
                ),
                const SizedBox(height: 8),
                _buildSurfaceCard(
                  context,
                  isGlass: isGlass,
                  isLite: isLite,
                  isDark: isDark,
                  child: Column(
                    children: [
                      _buildTypeOptionTile(
                        title: _tr('channel_public', 'Публичный канал'),
                        subtitle: _tr(
                          'channel_public_desc',
                          'Канал можно найти в поиске, подписаться может любой',
                        ),
                        icon: Icons.public_rounded,
                        selected: _isPublic,
                        primaryColor: primaryColor,
                        palette: palette,
                        onTap: () {
                          HapticUtils.selection();
                          setState(() => _isPublic = true);
                        },
                      ),
                      Divider(
                        height: 1,
                        indent: 56,
                        color: palette.borderSubtle,
                      ),
                      _buildTypeOptionTile(
                        title: _tr('channel_private', 'Частный канал'),
                        subtitle: _tr(
                          'channel_private_desc',
                          'Подписаться можно только по пригласительной ссылке',
                        ),
                        icon: Icons.lock_outline_rounded,
                        selected: !_isPublic,
                        primaryColor: primaryColor,
                        palette: palette,
                        onTap: () {
                          HapticUtils.selection();
                          setState(() => _isPublic = false);
                        },
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: _isPublic
                            ? Column(
                                children: [
                                  Divider(
                                    height: 1,
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
                                        labelText: 'Публичная ссылка (@username)',
                                        hintText: 'channel_username',
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
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 4. Настройки вещания канала
                _buildSectionHeader(
                  _tr('channel_settings', 'НАСТРОЙКИ ВЕЩАНИЯ').toUpperCase(),
                  palette,
                ),
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
                          Icons.edit_outlined,
                          color: primaryColor,
                        ),
                        title: Text(
                          _tr('channel_signatures', 'Подписи авторов'),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          _tr(
                            'channel_signatures_desc',
                            'Указывать имя администратора под публикациями',
                          ),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        value: _enableSignatures,
                        onChanged: (v) => setState(() => _enableSignatures = v),
                      ),
                      Divider(
                        height: 1,
                        indent: 56,
                        color: palette.borderSubtle,
                      ),
                      AdaptiveSwitchListTile(
                        secondary: Icon(
                          Icons.forum_outlined,
                          color: primaryColor,
                        ),
                        title: Text(
                          _tr('channel_comments', 'Комментарии к постам'),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          _tr(
                            'channel_comments_desc',
                            'Разрешить подписчикам обсуждать публикации',
                          ),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        value: _enableComments,
                        onChanged: (v) => setState(() => _enableComments = v),
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
                          _tr('channel_history', 'История публикаций'),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          _tr(
                            'channel_history_desc',
                            'Новые подписчики увидят предыдущие посты',
                          ),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        value: _enableHistory,
                        onChanged: (v) => setState(() => _enableHistory = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 5. Адаптивная инфо-подсказка
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: isDark ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _tr(
                            'channel_info_box',
                            'Каналы предназначены для вещания сообщений неограниченной аудитории. Публиковать посты могут только администраторы.',
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Нижняя кнопка создания
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : _createChannel,
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const iconoir.Megaphone(
                          width: 20,
                          height: 20,
                          color: Colors.white,
                        ),
                  label: Text(
                    _tr('chat_new_channel', 'Создать канал'),
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

  Widget _buildTypeOptionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required Color primaryColor,
    required TheavPalette palette,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? primaryColor.withValues(alpha: 0.16)
                    : palette.surfaceSecondary,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                icon,
                size: 20,
                color: selected ? primaryColor : palette.textSecondary,
              ),
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
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? primaryColor : palette.textTertiary,
              size: 22,
            ),
          ],
        ),
      ),
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
