import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:path_provider/path_provider.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/avatar_editor_models.dart';
import '../../services/account_manager.dart';
import '../../services/auth_service.dart';
import '../../services/avatar_sync_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/profile_instant_cache.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/avatar_editor/theav_avatar_picker_sheet.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/user/avatar_with_status.dart';
import 'change_email_screen.dart';
import 'privacy_detail_screen.dart';

/// Profile editing screen ("Account") using Theaver's Dual-Mode
/// Liquid Glass / Material 3 Matte design system (`TheavInsetGroup`,
/// `TheavInlineTextField`, `TheavListRow`, `SettingsFloatingScaffold`).
class EditProfileScreen extends StatefulWidget {
  final String? initialName;
  final String? initialSurname;
  final String? initialUsername;
  final String? initialPhone;
  final String? initialBio;
  final DateTime? initialBirthday;
  final String? initialEmail;
  final String? initialAvatarUrl;

  const EditProfileScreen({
    Key? key,
    this.initialName,
    this.initialSurname,
    this.initialUsername,
    this.initialPhone,
    this.initialBio,
    this.initialBirthday,
    this.initialEmail,
    this.initialAvatarUrl,
  }) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const int bioMaxLength = 140;

  final AccountManager _accountManager = AccountManager();

  late TextEditingController _nameController;
  late TextEditingController _surnameController;
  late TextEditingController _usernameController;
  late TextEditingController _phoneController;
  late TextEditingController _bioController;

  DateTime? _selectedBirthday;
  late String _email;
  bool _emailVerified = false;
  bool _isSaving = false;
  bool _isAvatarBusy = false;
  bool _avatarChanged = false;

  String? _avatarUrl;
  List<String> _avatarUrls = <String>[];
  final Map<String, int> _avatarIdByUrl = <String, int>{};

  bool get _hasAvatar =>
      (_avatarUrl != null && _avatarUrl!.trim().isNotEmpty) ||
      _avatarUrls.isNotEmpty;

  String get _avatarFallbackName {
    final full = '${_nameController.text.trim()} ${_surnameController.text.trim()}'
        .trim();
    if (full.isNotEmpty) return full;
    if (_usernameController.text.trim().isNotEmpty) {
      return _usernameController.text.trim();
    }
    return '?';
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _surnameController = TextEditingController(text: widget.initialSurname ?? '');

    final rawUsername = (widget.initialUsername ?? '').trim();
    final cleanUsername = rawUsername.startsWith('@')
        ? rawUsername.substring(1)
        : rawUsername;

    _usernameController = TextEditingController(text: cleanUsername);
    _phoneController = TextEditingController(text: widget.initialPhone ?? '');
    _phoneController.addListener(_onFieldChanged);

    _bioController = TextEditingController(text: widget.initialBio ?? '');
    _bioController.addListener(_onFieldChanged);

    _selectedBirthday = widget.initialBirthday;
    final currentAcc = _accountManager.currentAccount;
    _email = (currentAcc?.email?.isNotEmpty == true
            ? currentAcc!.email!
            : widget.initialEmail) ??
        '';
    _emailVerified = currentAcc?.emailVerified ?? false;

    _hydrateInitialAvatars();
    AvatarSyncService().addListener(_onAvatarSyncChanged);
    unawaited(_loadCurrentAvatars());
  }

  void _hydrateInitialAvatars() {
    final acc = _accountManager.currentAccount;
    final snap = ProfileInstantCache.instance.getSelfSnapshotSync();

    final rawInitial = (widget.initialAvatarUrl ?? '').trim();
    if (rawInitial.isNotEmpty) {
      _avatarUrl = rawInitial;
    } else if (snap?.avatarUrl != null && snap!.avatarUrl!.trim().isNotEmpty) {
      _avatarUrl = snap.avatarUrl!.trim();
    } else if (acc?.avatarUrl != null && acc!.avatarUrl!.trim().isNotEmpty) {
      _avatarUrl = acc.avatarUrl!.trim();
    }

    if (snap != null && snap.avatarUrls.isNotEmpty) {
      _avatarUrls = List<String>.from(snap.avatarUrls);
      for (int i = 0; i < snap.avatarUrls.length && i < snap.avatarIds.length; i++) {
        final url = snap.avatarUrls[i];
        final id = snap.avatarIds[i];
        if (url.isNotEmpty && id > 0) {
          _avatarIdByUrl[url] = id;
          final valid = getValidAvatarUrl(url);
          if (valid != null) _avatarIdByUrl[valid] = id;
        }
      }
    } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      _avatarUrls = <String>[_avatarUrl!];
    }
  }

  Future<void> _loadCurrentAvatars() async {
    final acc = _accountManager.currentAccount;
    if (acc == null) return;
    try {
      final localHistory =
          await AvatarSyncService().getLocalAvatarUrls(acc.userId);
      final userRes = await AuthService.getCurrentUser();
      if (!mounted) return;

      final combined = <String>[...localHistory];
      if (userRes['success'] == true && userRes['user'] is Map) {
        final user = Map<String, dynamic>.from(userRes['user'] as Map);
        final serverAvatars = user['avatars'];
        if (serverAvatars is List) {
          for (final item in serverAvatars) {
            if (item is! Map) continue;
            final url = (item['avatar_url'] ?? '').toString().trim();
            final rawId = item['id'];
            final id = rawId is int
                ? rawId
                : (rawId is num ? rawId.toInt() : int.tryParse('$rawId'));
            if (url.isNotEmpty) {
              if (!combined.contains(url)) combined.add(url);
              if (id != null && id > 0) {
                _avatarIdByUrl[url] = id;
                final valid = getValidAvatarUrl(url);
                if (valid != null) _avatarIdByUrl[valid] = id;
              }
            }
          }
        }
        final primaryServerUrl = (user['avatar_url'] ?? '').toString().trim();
        if (primaryServerUrl.isNotEmpty && !combined.contains(primaryServerUrl)) {
          combined.add(primaryServerUrl);
        }
      }

      if (!mounted) return;
      setState(() {
        _avatarUrls = combined;
        if (combined.isNotEmpty) {
          _avatarUrl = combined.first;
        }
      });
    } catch (_) {}
  }

  void _onAvatarSyncChanged() async {
    if (!mounted) return;
    final acc = _accountManager.currentAccount;
    if (acc == null) return;
    final localHistory = await AvatarSyncService().getLocalAvatarUrls(acc.userId);
    if (!mounted) return;
    setState(() {
      final combined = <String>[...localHistory];
      for (final existing in _avatarUrls) {
        if (existing.isNotEmpty && !combined.contains(existing)) {
          combined.add(existing);
        }
      }
      _avatarUrls = combined;
      if (acc.avatarUrl != null && acc.avatarUrl!.isNotEmpty) {
        _avatarUrl = acc.avatarUrl;
      } else if (combined.isNotEmpty) {
        _avatarUrl = combined.first;
      } else {
        _avatarUrl = null;
      }
    });
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AvatarSyncService().removeListener(_onAvatarSyncChanged);
    _nameController.dispose();
    _surnameController.dispose();
    _usernameController.dispose();
    _phoneController.removeListener(_onFieldChanged);
    _phoneController.dispose();
    _bioController.removeListener(_onFieldChanged);
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_isAvatarBusy || _isSaving) return;
    final account = _accountManager.currentAccount;
    if (account == null) return;

    final AvatarPickResult? pick = await TheavAvatarPickerSheet.pickAndEdit(
      context: context,
      maskShape: AvatarShapeMask.circle,
      ctaMode: AvatarEditorCtaMode.setPhoto,
      canDeleteCurrent: _hasAvatar,
    );
    if (!mounted || pick == null) return;

    if (pick.deletedCurrent) {
      await _performDeleteCurrentAvatar();
      return;
    }
    if (!pick.hasMedia) return;

    setState(() => _isAvatarBusy = true);
    try {
      if (kIsWeb) {
        final bytes = pick.bytes;
        if (bytes == null || bytes.isEmpty) return;
        final token = await AuthService.getToken();
        if (token == null || token.isEmpty) {
          if (mounted) {
            GlassToastService().showError(context, 'Not authenticated');
          }
          return;
        }
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${AppConfig.baseUrl}/api/files/upload-avatar'),
        );
        request.headers['Authorization'] = 'Bearer $token';
        request.files.add(
          http.MultipartFile.fromBytes(
            'avatar',
            bytes,
            filename: pick.fileName.isNotEmpty ? pick.fileName : 'avatar.jpg',
          ),
        );
        final streamed = await request.send().timeout(const Duration(seconds: 60));
        final response = await http.Response.fromStream(streamed);
        final data = jsonDecode(response.body);
        if (response.statusCode == 200 && data is Map && data['success'] == true) {
          final uploadedUrl = (data['avatar_url'] ?? '').toString().trim();
          final uploadedId = (data['avatar_id'] as num?)?.toInt();
          await _accountManager.updateAccountProfile(
            account.userId,
            avatarUrl: uploadedUrl,
          );
          if (!mounted) return;
          setState(() {
            _avatarUrl = uploadedUrl;
            _avatarUrls.remove(uploadedUrl);
            if (uploadedUrl.isNotEmpty) {
              _avatarUrls.insert(0, uploadedUrl);
              if (uploadedId != null && uploadedId > 0) {
                _avatarIdByUrl[uploadedUrl] = uploadedId;
              }
            }
            _avatarChanged = true;
          });
          GlassToastService().show(
            context,
            context.trOr('profile_photo_updated', 'Фото профиля обновлено'),
          );
        } else if (mounted) {
          GlassToastService().showError(
            context,
            (data is Map ? data['message'] : null)?.toString() ??
                context.trOr('common_error', 'Ошибка'),
          );
        }
        return;
      }

      String? sourcePath = pick.file?.path;
      if (sourcePath == null || sourcePath.isEmpty || !await File(sourcePath).exists()) {
        final bytes = pick.bytes;
        if (bytes == null || bytes.isEmpty) return;
        final tempDir = await getTemporaryDirectory();
        final ext = pick.fileName.contains('.')
            ? '.${pick.fileName.split('.').last}'
            : '.jpg';
        final tempFile = File(
          '${tempDir.path}/avatar_edit_${DateTime.now().millisecondsSinceEpoch}$ext',
        );
        await tempFile.writeAsBytes(bytes, flush: true);
        sourcePath = tempFile.path;
      }

      final permanentPath = await AvatarSyncService().setLocalAvatar(
        account.userId,
        sourcePath,
      );
      if (!mounted) return;
      setState(() {
        _avatarUrl = permanentPath;
        _avatarUrls.remove(permanentPath);
        _avatarUrls.insert(0, permanentPath);
        _avatarChanged = true;
      });
      GlassToastService().show(
        context,
        context.trOr('profile_photo_updated', 'Фото профиля обновлено'),
      );
    } catch (e) {
      if (mounted) {
        GlassToastService().showError(
          context,
          context.trOr('profile_photo_error', 'Ошибка: {error}', {
            'error': e.toString(),
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _isAvatarBusy = false);
    }
  }

  Future<void> _confirmAndDeleteAvatar() async {
    if (_isAvatarBusy || _isSaving || !_hasAvatar) return;

    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: context.trOr('profile_delete_photo_confirm_title', 'Удалить фото?'),
      message: context.trOr(
        'profile_delete_photo_confirm_message',
        'Текущее фото профиля будет удалено.',
      ),
      actions: [
        TheavDialogAction<bool>(
          label: context.trOr('profile_cancel', 'Отмена'),
          result: false,
        ),
        TheavDialogAction<bool>(
          label: context.trOr('profile_delete_photo', 'Удалить фото'),
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed == true && mounted) {
      await _performDeleteCurrentAvatar();
    }
  }

  Future<void> _performDeleteCurrentAvatar() async {
    final account = _accountManager.currentAccount;
    if (account == null) return;

    HapticUtils.heavy();
    setState(() => _isAvatarBusy = true);
    try {
      final topAvatar = _avatarUrls.isNotEmpty ? _avatarUrls.first : _avatarUrl;
      final isLocalAvatar = topAvatar != null &&
          !kIsWeb &&
          (topAvatar.startsWith('/') ||
              topAvatar.startsWith('file:') ||
              File(topAvatar).existsSync());

      if (isLocalAvatar) {
        await AvatarSyncService().removeAvatar(account.userId, topAvatar);
        if (!mounted) return;
        setState(() {
          if (_avatarUrls.isNotEmpty) _avatarUrls.removeAt(0);
          _avatarUrl = _avatarUrls.isNotEmpty ? _avatarUrls.first : null;
          _avatarChanged = true;
        });
        await _accountManager.updateAccountProfile(
          account.userId,
          avatarUrl: _avatarUrl ?? '',
        );
        if (mounted) {
          GlassToastService().show(
            context,
            context.trOr('profile_photo_deleted', 'Фото профиля удалено'),
          );
        }
        return;
      }

      int? avatarId;
      if (topAvatar != null && topAvatar.isNotEmpty) {
        avatarId = _avatarIdByUrl[topAvatar] ??
            _avatarIdByUrl[getValidAvatarUrl(topAvatar) ?? ''];
      }
      final result = await AuthService.deleteAvatar(avatarId: avatarId);
      if (!mounted) return;

      if (result['success'] == true) {
        if (topAvatar != null && topAvatar.isNotEmpty) {
          await AvatarSyncService().removeAvatar(account.userId, topAvatar);
          _avatarIdByUrl.remove(topAvatar);
        }
        if (!mounted) return;
        setState(() {
          if (_avatarUrls.isNotEmpty) _avatarUrls.removeAt(0);
          _avatarUrl = _avatarUrls.isNotEmpty ? _avatarUrls.first : null;
          _avatarChanged = true;
        });
        await _accountManager.updateAccountProfile(
          account.userId,
          avatarUrl: _avatarUrl ?? '',
        );
        if (mounted) {
          GlassToastService().show(
            context,
            context.trOr('profile_photo_deleted', 'Фото профиля удалено'),
          );
        }
      } else {
        GlassToastService().showError(
          context,
          context.trOr('profile_photo_error', 'Ошибка: {error}', {
            'error': (result['message'] ?? '').toString(),
          }),
        );
      }
    } catch (e) {
      if (mounted) {
        GlassToastService().showError(
          context,
          context.trOr('profile_photo_error', 'Ошибка: {error}', {
            'error': e.toString(),
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _isAvatarBusy = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_isSaving || _isAvatarBusy) return;

    final name = _nameController.text.trim();
    final surname = _surnameController.text.trim();

    var username = _usernameController.text.trim();
    if (username.startsWith('@')) {
      username = username.substring(1).trim();
    }

    if (username.isNotEmpty && !RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(username)) {
      GlassToastService().showError(
        context,
        context.trOr(
          'edit_profile_invalid_username',
          'Недопустимое имя пользователя (3–32 символа: a-z, 0-9, _)',
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final phone = _phoneController.text.trim();
    final email = _email;

    final result = await AuthService.updateProfile(
      name: name,
      surname: surname,
      username: username,
      email: email,
      phone: phone,
      bio: _bioController.text.trim(),
      birthday: _selectedBirthday,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result['success'] == true) {
      Navigator.pop(context, {
        'name': name,
        'surname': surname,
        'username': username,
        'phone': phone,
        'bio': _bioController.text.trim(),
        'birthday': _selectedBirthday,
        'synced': result['synced'] ?? true,
        'avatar_changed': _avatarChanged,
        'avatar_url': _avatarUrl,
      });
    } else {
      final l10n = AppLocalizations.of(context)!;
      final errorMessage = result['requiresServer'] == true
          ? l10n.translate('edit_profile_server_required_for_unique_fields')
          : (result['message'] ?? l10n.translate('common_error')).toString();

      GlassToastService().showError(context, errorMessage);
    }
  }

  Future<void> _selectBirthday() async {
    final palette = context.theav;
    final now = DateTime.now();
    final initialDate = _selectedBirthday ?? DateTime(2000, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1920),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: palette.primary,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() => _selectedBirthday = picked);
    }
  }

  void _clearBirthday() {
    setState(() => _selectedBirthday = null);
  }

  void _clearPhone() {
    _phoneController.clear();
  }

  String _formatBirthday(DateTime? date, AppLocalizations l10n) {
    if (date == null) {
      return l10n.translate('edit_profile_birthday_not_set');
    }
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  void _showPersonalChannelTodo(AppLocalizations l10n) {
    GlassToastService().show(
      context,
      l10n.translate('edit_profile_personal_channel_todo'),
      duration: const Duration(seconds: 2),
    );
  }

  void _handleBack() {
    if (_avatarChanged) {
      Navigator.pop(context, {
        'avatar_changed': true,
        'avatar_url': _avatarUrl,
      });
    } else {
      Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = context.theav;
    final bioRemaining = bioMaxLength - _bioController.text.length;
    final currentUserId = _accountManager.currentAccount?.userId;

    return SettingsFloatingScaffold(
      title: l10n.translate('edit_profile_title'),
      backgroundColor: palette.bgBase,
      onBack: _handleBack,
      actions: [
        if (_isSaving)
          SettingsHeaderAction(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.primary,
              ),
            ),
          )
        else
          SettingsHeaderAction(
            icon: iconoir.Check(
              color: palette.primary,
              width: 22,
              height: 22,
            ),
            foregroundColor: palette.primary,
            onTap: _saveProfile,
            tooltip: l10n.translate('edit_profile_save'),
          ),
      ],
      body: ListView(
        padding: EdgeInsets.only(
          top: SettingsFloatingHeader.topClearanceOf(context) + 12,
          bottom: MediaQuery.paddingOf(context).bottom + 32,
        ),
        children: [
          // Top Avatar block
          Center(
            child: GestureDetector(
              onTap: _isAvatarBusy ? null : _pickAvatar,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AvatarWithStatus(
                    radius: 44,
                    userId: currentUserId,
                    avatarUrl: _avatarUrl,
                    name: _avatarFallbackName,
                    showDecoration: true,
                  ),
                  if (_isAvatarBusy)
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black38,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TheavInsetGroup(
            dividerIndent: 54,
            children: [
              TheavListRow(
                leading: iconoir.Camera(
                  width: 22,
                  height: 22,
                  color: palette.primary,
                ),
                title: context.trOr('avatar_choose_photo', 'Выбрать фото'),
                enabled: !_isAvatarBusy && !_isSaving,
                onTap: _pickAvatar,
              ),
              if (_hasAvatar)
                TheavListRow(
                  isDestructive: true,
                  leading: iconoir.Trash(
                    width: 22,
                    height: 22,
                    color: palette.error,
                  ),
                  title: context.trOr('avatar_delete_photo', 'Удалить фото'),
                  enabled: !_isAvatarBusy && !_isSaving,
                  onTap: _confirmAndDeleteAvatar,
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Section 1: Name & Surname
          TheavInsetGroup(
            header: l10n.translate('edit_profile_your_name'),
            dividerIndent: 16,
            children: [
              TheavInlineTextField(
                controller: _nameController,
                placeholder: l10n.translate('edit_profile_first_name'),
                textInputAction: TextInputAction.next,
              ),
              TheavInlineTextField(
                controller: _surnameController,
                placeholder: l10n.translate('edit_profile_last_name'),
                textInputAction: TextInputAction.next,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Section 2: Bio + Privacy link
          TheavInsetGroup(
            dividerIndent: 16,
            children: [
              TheavInlineTextField(
                controller: _bioController,
                maxLength: bioMaxLength,
                maxLines: 3,
                minLines: 1,
                placeholder: l10n.translate('edit_profile_bio_hint'),
                suffix: Text(
                  '$bioRemaining',
                  style: TextStyle(
                    color: bioRemaining < 20 ? palette.error : palette.primary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 4, 32, 12),
            child: RichText(
              text: TextSpan(
                style: TextStyle(color: palette.subtext, fontSize: 12.5, height: 1.35),
                children: [
                  TextSpan(text: '${l10n.translate('edit_profile_bio_visible_info')} '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          SwipeBackPageRoute(
                            builder: (_) => PrivacyDetailScreen(
                              field: 'bio_visibility',
                              title: l10n.translate('privacy_bio'),
                            ),
                          ),
                        );
                      },
                      child: Text(
                        l10n.translate('edit_profile_edit_link'),
                        style: TextStyle(
                          color: palette.primary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Section 3: Information about you
          TheavInsetGroup(
            header: l10n.translate('edit_profile_info_about_you'),
            dividerIndent: 56,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 26),
                      child: Center(
                        widthFactor: 1.0,
                        child: iconoir.Phone(
                          width: 22,
                          height: 22,
                          color: palette.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TheavInlineTextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        placeholder: l10n.translate('edit_profile_birthday_not_set'),
                        label: l10n.translate('edit_profile_phone'),
                        padding: EdgeInsets.zero,
                        suffix: _phoneController.text.isNotEmpty
                            ? GestureDetector(
                                onTap: _clearPhone,
                                child: iconoir.Xmark(
                                  width: 18,
                                  height: 18,
                                  color: palette.subtext,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 26),
                      child: Center(
                        widthFactor: 1.0,
                        child: iconoir.AtSign(
                          width: 22,
                          height: 22,
                          color: palette.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TheavInlineTextField(
                        controller: _usernameController,
                        label: l10n.translate('edit_profile_username'),
                        placeholder: 'username',
                        padding: EdgeInsets.zero,
                        prefix: Text(
                          '@',
                          style: TextStyle(
                            color: palette.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              TheavListRow(
                leading: iconoir.Calendar(
                  width: 22,
                  height: 22,
                  color: palette.primary,
                ),
                titleWidget: Text(
                  _formatBirthday(_selectedBirthday, l10n),
                  style: TextStyle(
                    color: _selectedBirthday != null
                        ? palette.onSurface
                        : palette.subtext.withValues(alpha: 0.72),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: l10n.translate('edit_profile_birthday'),
                trailing: _selectedBirthday != null
                    ? GestureDetector(
                        onTap: _clearBirthday,
                        child: iconoir.Xmark(
                          width: 18,
                          height: 18,
                          color: palette.subtext,
                        ),
                      )
                    : null,
                onTap: _selectBirthday,
              ),
              TheavListRow(
                leading: iconoir.Mail(
                  width: 22,
                  height: 22,
                  color: palette.primary,
                ),
                titleWidget: Text(
                  _email.isNotEmpty
                      ? _email
                      : l10n.translate('security_not_set'),
                  style: TextStyle(
                    color: _email.isNotEmpty
                        ? palette.onSurface
                        : palette.subtext.withValues(alpha: 0.72),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: _email.isNotEmpty
                    ? '${l10n.translate('auth_email')} • ${_emailVerified ? l10n.translate('email_status_verified') : l10n.translate('email_status_unverified')}'
                    : l10n.translate('auth_email'),
                showChevron: true,
                onTap: () async {
                  await Navigator.push(
                    context,
                    SwipeBackPageRoute(
                      builder: (_) => const ChangeEmailScreen(),
                    ),
                  );
                  if (!mounted) return;
                  final acc = _accountManager.currentAccount;
                  setState(() {
                    _email = acc?.email ?? _email;
                    _emailVerified = acc?.emailVerified ?? _emailVerified;
                  });
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 4, 32, 12),
            child: RichText(
              text: TextSpan(
                style: TextStyle(color: palette.subtext, fontSize: 12.5, height: 1.35),
                children: [
                  TextSpan(
                    text: l10n.translate('edit_profile_birthday_visibility_info_1'),
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          SwipeBackPageRoute(
                            builder: (_) => PrivacyDetailScreen(
                              field: 'birthday_visibility',
                              title: l10n.translate('privacy_birthday'),
                            ),
                          ),
                        );
                      },
                      child: Text(
                        l10n.translate('edit_profile_settings_link'),
                        style: TextStyle(
                          color: palette.primary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  TextSpan(
                    text: l10n.translate('edit_profile_birthday_visibility_info_2'),
                  ),
                ],
              ),
            ),
          ),

          // Section 4: Personal channel
          TheavInsetGroup(
            children: [
              TheavListRow(
                leading: iconoir.Megaphone(
                  width: 22,
                  height: 22,
                  color: palette.primary,
                ),
                title: l10n.translate('edit_profile_personal_channel'),
                trailing: Text(
                  l10n.translate('edit_profile_add_btn'),
                  style: TextStyle(
                    color: palette.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => _showPersonalChannelTodo(l10n),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
