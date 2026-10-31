import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:image_picker/image_picker.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/database/app_database.dart';
import '../../services/file_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../widgets/common/adaptive_switch.dart';

/// Экран редактирования группы или канала (для владельцев и администраторов).
///
/// Позволяет изменить:
/// - Фотографию группы/канала
/// - Название и описание
/// - Публичность (`is_public`)
/// - Историю сообщений для новых участников (`history_for_new`, для групп)
/// - Медленный режим (`slow_mode_interval`, для групп)
class EditGroupChannelScreen extends StatefulWidget {
  final String chatId;
  final bool isChannel;
  final String initialName;
  final String initialDescription;
  final String? initialAvatarUrl;
  final bool initialIsPublic;
  final String? initialUsername;
  final bool initialHistoryForNew;
  final int initialSlowModeInterval;
  final String? inviteLink;

  const EditGroupChannelScreen({
    Key? key,
    required this.chatId,
    this.isChannel = false,
    required this.initialName,
    this.initialDescription = '',
    this.initialAvatarUrl,
    this.initialIsPublic = false,
    this.initialUsername,
    this.initialHistoryForNew = true,
    this.initialSlowModeInterval = 0,
    this.inviteLink,
  }) : super(key: key);

  @override
  State<EditGroupChannelScreen> createState() => _EditGroupChannelScreenState();
}

class _EditGroupChannelScreenState extends State<EditGroupChannelScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _usernameController;

  String? _avatarUrl;
  File? _pickedAvatarFile;
  late bool _isPublic;
  late bool _historyForNew;
  late int _slowModeInterval;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController = TextEditingController(text: widget.initialDescription);
    _usernameController = TextEditingController(text: widget.initialUsername ?? '');
    _avatarUrl = widget.initialAvatarUrl;
    _isPublic = widget.initialIsPublic;
    _historyForNew = widget.initialHistoryForNew;
    _slowModeInterval = widget.initialSlowModeInterval;
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

  Future<void> _saveChanges() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      GlassToastService().show(
        context,
        _tr('group_name_empty_error', 'Введите название'),
      );
      return;
    }

    HapticUtils.tap();
    setState(() => _isSaving = true);

    try {
      String? finalAvatarUrl = _avatarUrl;
      if (_pickedAvatarFile != null) {
        final uploadRes = await FileService().uploadFile(_pickedAvatarFile!);
        finalAvatarUrl = uploadRes.url;
      }

      final cleanUsername = _usernameController.text.trim().replaceAll('@', '');
      final token = await AuthService.getToken();
      final dio = Dio();
      await dio.put(
        '${AppConfig.baseUrl}/api/chats/${widget.chatId}/group-settings',
        data: {
          'name': newName,
          'description': _descriptionController.text.trim(),
          if (finalAvatarUrl != null) 'avatar_url': finalAvatarUrl,
          'is_public': _isPublic,
          'username': _isPublic ? cleanUsername : '',
          'history_for_new': _historyForNew,
          'slow_mode_interval': _slowModeInterval,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      // Обновляем локальную БД Drift
      try {
        await AppDatabase().updateChatAvatar(widget.chatId, finalAvatarUrl);
      } catch (_) {}

      if (!mounted) return;
      Navigator.pop<Map<String, dynamic>>(context, {
        'name': newName,
        'description': _descriptionController.text.trim(),
        'avatar_url': finalAvatarUrl,
        'is_public': _isPublic,
        'username': _isPublic ? cleanUsername : '',
        'history_for_new': _historyForNew,
        'slow_mode_interval': _slowModeInterval,
      });
    } catch (e) {
      if (!mounted) return;
      GlassToastService().show(
        context,
        'Ошибка сохранения: $e',
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _slowModeLabel(int interval) {
    switch (interval) {
      case 0:
        return _tr('group_slow_off', 'Выкл.');
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC);
    const options = [0, 10, 30, 60, 300, 900];

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              for (final opt in options)
                ListTile(
                  title: Text(_slowModeLabel(opt)),
                  trailing: _slowModeInterval == opt
                      ? iconoir.Check(width: 20, height: 20, color: accentColor)
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glassProvider = context.watch<LiquidGlassProvider>();
    final isGlass = glassProvider.enabled;
    final isLite = glassProvider.isLite;

    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F7);
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final accentColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC);
    final validAvatar = getValidAvatarUrl(_avatarUrl);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: iconoir.NavArrowLeft(
            width: 24,
            height: 24,
            color: textColor,
          ),
        ),
        title: Text(
          widget.isChannel
              ? _tr('edit_channel_title', 'Изменить канал')
              : _tr('edit_group_title', 'Изменить группу'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        actions: [
          if (_isSaving)
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
              onPressed: _saveChanges,
              icon: iconoir.Check(
                width: 24,
                height: 24,
                color: accentColor,
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Аватар
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: accentColor.withValues(alpha: 0.2),
                    backgroundImage: _pickedAvatarFile != null
                        ? FileImage(_pickedAvatarFile!) as ImageProvider
                        : (validAvatar != null && validAvatar.isNotEmpty
                            ? CachedNetworkImageProvider(validAvatar)
                            : null),
                    child: (_pickedAvatarFile == null && (validAvatar == null || validAvatar.isEmpty))
                        ? Text(
                            _nameController.text.isNotEmpty
                                ? _nameController.text[0].toUpperCase()
                                : 'G',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w600,
                              color: accentColor,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: bgColor, width: 2),
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
          ),
          const SizedBox(height: 24),

          // 2. Поля ввода названия и описания
          _buildCard(
            context,
            isGlass: isGlass,
            isLite: isLite,
            isDark: isDark,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  TextField(
                    controller: _nameController,
                    style: TextStyle(fontSize: 16, color: textColor),
                    decoration: InputDecoration(
                      labelText: widget.isChannel
                          ? _tr('channel_name_label', 'Название канала')
                          : _tr('group_name_label', 'Название группы'),
                      border: InputBorder.none,
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    minLines: 1,
                    style: TextStyle(fontSize: 15, color: textColor),
                    decoration: InputDecoration(
                      labelText: _tr('group_info_description', 'Описание (необязательно)'),
                      border: InputBorder.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3. Настройки группы/канала
          _buildCard(
            context,
            isGlass: isGlass,
            isLite: isLite,
            isDark: isDark,
            child: Column(
              children: [
                AdaptiveSwitchListTile(
                  title: Text(
                    widget.isChannel
                        ? _tr('channel_public_toggle', 'Публичный канал')
                        : _tr('group_info_public', 'Публичная группа'),
                    style: TextStyle(color: textColor, fontSize: 15.5),
                  ),
                  value: _isPublic,
                  onChanged: (v) => setState(() => _isPublic = v),
                ),
                if (_isPublic) ...[
                  Divider(
                    height: 1,
                    indent: 16,
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: _usernameController,
                      style: TextStyle(fontSize: 15, color: textColor),
                      decoration: InputDecoration(
                        labelText: 'Публичный @username',
                        prefixText: '@',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
                if (!widget.isChannel) ...[
                  Divider(
                    height: 1,
                    indent: 16,
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  AdaptiveSwitchListTile(
                    title: Text(
                      _tr('group_info_history_for_new', 'История чата для новых участников'),
                      style: TextStyle(color: textColor, fontSize: 15.5),
                    ),
                    value: _historyForNew,
                    onChanged: (v) => setState(() => _historyForNew = v),
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  ListTile(
                    title: Text(
                      _tr('group_info_slow_mode', 'Медленный режим'),
                      style: TextStyle(color: textColor, fontSize: 15.5),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _slowModeLabel(_slowModeInterval),
                          style: TextStyle(color: accentColor, fontSize: 14.5),
                        ),
                        const SizedBox(width: 4),
                        iconoir.NavArrowRight(
                          width: 18,
                          height: 18,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ],
                    ),
                    onTap: _showSlowModeSheet,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required bool isGlass,
    required bool isLite,
    required bool isDark,
    required Widget child,
  }) {
    if (isGlass) {
      final glassProvider = context.watch<LiquidGlassProvider>();
      final style = glassProvider.createStyle(
        context: context,
        isLiteOverride: isLite,
        shape: const LiquidGlassShape.continuousRoundedRectangle(cornerRadius: 22),
      );
      return LiquidGlassLens(
        style: style,
        child: Container(
          decoration: isDark
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 0.5,
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }
}
