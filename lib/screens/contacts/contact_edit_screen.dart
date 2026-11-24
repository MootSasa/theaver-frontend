import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../l10n/app_localizations.dart';
import '../../models/avatar_editor_models.dart';
import '../../services/contacts_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/avatar_editor/theav_avatar_picker_sheet.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/user/avatar_with_status.dart';
import '../chat/private_chat_screen.dart';

/// Result returned when closing [ContactEditScreen].
class ContactEditResult {
  final ContactItem? contact;
  final bool deleted;
  final String? suggestedChatId;
  final String? suggestedPhotoUrl;
  final bool customAvatarChanged;

  const ContactEditResult({
    this.contact,
    this.deleted = false,
    this.suggestedChatId,
    this.suggestedPhotoUrl,
    this.customAvatarChanged = false,
  });
}

/// Telegram-style Contact Editor screen supporting adding/editing contacts,
/// private notes, suggesting profile photos, and setting/resetting local
/// custom contact avatars.
class ContactEditScreen extends StatefulWidget {
  final String userId;
  final bool? isContact;
  final ContactItem? initialContact;
  final String? initialFirstName;
  final String? initialLastName;
  final String? initialNote;
  final String? username;
  final String? originalDisplayName;
  final String? originalAvatarUrl;
  final String? customAvatarUrl;
  final String? currentChatId;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? lastSeenStatus;
  final bool autofocusNote;
  final ValueChanged<ContactItem?>? onSaved;
  final VoidCallback? onDeleted;

  const ContactEditScreen({
    super.key,
    required this.userId,
    this.isContact,
    this.initialContact,
    this.initialFirstName,
    this.initialLastName,
    this.initialNote,
    this.username,
    this.originalDisplayName,
    this.originalAvatarUrl,
    this.customAvatarUrl,
    this.currentChatId,
    this.isOnline = false,
    this.lastSeen,
    this.lastSeenStatus,
    this.autofocusNote = false,
    this.onSaved,
    this.onDeleted,
  });

  @override
  State<ContactEditScreen> createState() => _ContactEditScreenState();
}

class _ContactEditScreenState extends State<ContactEditScreen> {
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _noteCtrl;

  ContactItem? _contactItem;
  late bool _isContact;
  late String _username;
  late String _originalDisplayName;
  String? _originalAvatarUrl;
  String? _customAvatarUrl;
  late bool _isOnline;
  DateTime? _lastSeen;
  late String _lastSeenStatus;

  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  bool _avatarChanged = false;

  bool get _isBusy => _isSaving || _isUploadingPhoto;

  bool get _hasCustomAvatar =>
      _customAvatarUrl != null && _customAvatarUrl!.trim().isNotEmpty;

  String? get _effectiveAvatarUrl {
    if (_hasCustomAvatar) return _customAvatarUrl!.trim();
    if (_originalAvatarUrl != null && _originalAvatarUrl!.trim().isNotEmpty) {
      return _originalAvatarUrl!.trim();
    }
    return null;
  }

  String get _effectiveDisplayName {
    final full =
        '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim();
    if (full.isNotEmpty) return full;
    if (_originalDisplayName.isNotEmpty) return _originalDisplayName;
    if (_username.isNotEmpty) return '@$_username';
    return 'Пользователь #${widget.userId}';
  }

  String get _avatarPlaceholderName {
    if (_originalDisplayName.isNotEmpty) return _originalDisplayName;
    final typed = _firstNameCtrl.text.trim();
    if (typed.isNotEmpty) return typed;
    if (_username.isNotEmpty) return _username;
    return '?';
  }

  String get _targetLabel {
    final typedFirst = _firstNameCtrl.text.trim();
    if (typedFirst.isNotEmpty) return typedFirst;
    if (_originalDisplayName.isNotEmpty) {
      return _originalDisplayName.split(RegExp(r'\s+')).first;
    }
    if (_username.isNotEmpty) return '@$_username';
    return context.trOr('profile_default_user', 'пользователя');
  }

  String get _headerPrimaryTitle {
    if (_originalDisplayName.isNotEmpty) return _originalDisplayName;
    if (_username.isNotEmpty) return '@$_username';
    return _effectiveDisplayName;
  }

  static String? _nonEmpty(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isNotEmpty ? t : null;
  }

  @override
  void initState() {
    super.initState();
    final cached = widget.initialContact ?? ContactsService.getCached(widget.userId);
    _contactItem = cached;
    _isContact = widget.isContact ?? (cached?.isContact ?? false);
    _username = _nonEmpty(widget.username) ?? _nonEmpty(cached?.username) ?? '';
    _originalDisplayName = _nonEmpty(widget.originalDisplayName) ??
        _nonEmpty(cached?.originalDisplayName) ??
        _nonEmpty(cached?.displayName) ??
        '';
    _originalAvatarUrl = _nonEmpty(widget.originalAvatarUrl) ??
        _nonEmpty(cached?.originalAvatarUrl) ??
        ((cached != null && !cached.hasCustomAvatar)
            ? _nonEmpty(cached.avatarUrl)
            : null);
    _customAvatarUrl =
        _nonEmpty(widget.customAvatarUrl) ?? _nonEmpty(cached?.customAvatarUrl);
    _isOnline = widget.isOnline || (cached?.isOnline ?? false);
    _lastSeen = widget.lastSeen ?? cached?.lastSeen;
    _lastSeenStatus =
        _nonEmpty(widget.lastSeenStatus) ?? _nonEmpty(cached?.lastSeenStatus) ?? '';

    String initFirst = '';
    String initLast = '';
    if (cached != null &&
        (cached.customFirstName.trim().isNotEmpty ||
            cached.customLastName.trim().isNotEmpty)) {
      initFirst = cached.customFirstName.trim();
      initLast = cached.customLastName.trim();
    } else if (_nonEmpty(widget.initialFirstName) != null ||
        _nonEmpty(widget.initialLastName) != null) {
      initFirst = (widget.initialFirstName ?? '').trim();
      initLast = (widget.initialLastName ?? '').trim();
    } else if (_originalDisplayName.isNotEmpty) {
      final parts = _originalDisplayName.split(RegExp(r'\s+'));
      initFirst = parts.first;
      if (parts.length > 1) {
        initLast = parts.sublist(1).join(' ');
      }
    }

    _firstNameCtrl = TextEditingController(text: initFirst);
    _lastNameCtrl = TextEditingController(text: initLast);
    _noteCtrl = TextEditingController(
      text: widget.initialNote ?? cached?.note ?? '',
    );

    _firstNameCtrl.addListener(_onNameInputChanged);
  }

  void _onNameInputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _firstNameCtrl.removeListener(_onNameInputChanged);
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String _buildStatusSubtitle(BuildContext context) {
    if (_isOnline) {
      return context.trOr('chat_online', 'в сети');
    }
    if (_lastSeen != null) {
      return DateTimeUtils.formatLastSeen(_lastSeen, context);
    }
    switch (_lastSeenStatus) {
      case 'recently':
        return 'был(а) недавно';
      case 'within_week':
        return 'был(а) на этой неделе';
      case 'within_month':
        return 'был(а) в этом месяце';
      case 'long_time_ago':
        return 'был(а) давно';
      default:
        return context.trOr('chat_offline', 'был(а) недавно');
    }
  }

  Future<void> _save() async {
    if (_isBusy) return;
    HapticUtils.tap();

    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final note = _noteCtrl.text.trim();

    if (firstName.isEmpty && !(!_isContact && widget.autofocusNote && note.isNotEmpty)) {
      GlassToastService().showError(
        context,
        context.trOr('contact_first_name', 'Имя'),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final Map<String, dynamic> res;
      if (_isContact) {
        res = await ContactsService.updateContact(
          widget.userId,
          firstName: firstName,
          lastName: lastName,
          note: note,
          isContact: true,
        );
      } else {
        final saveAsContact = firstName.isNotEmpty;
        res = await ContactsService.addContact(
          userId: widget.userId,
          firstName: firstName,
          lastName: lastName,
          note: note,
          isContact: saveAsContact,
        );
      }

      if (!mounted) return;
      if (res['success'] == true) {
        final saved =
            (res['contact'] as ContactItem?) ?? ContactsService.getCached(widget.userId);
        _contactItem = saved;
        _isContact = saved?.isContact ?? _isContact;
        widget.onSaved?.call(saved);
        GlassToastService().show(
          context,
          _isContact
              ? context.trOr('profile_saved', 'Сохранено')
              : 'Заметка сохранена',
        );
        Navigator.of(context).pop(
          ContactEditResult(
            contact: saved,
            customAvatarChanged: _avatarChanged,
          ),
        );
      } else {
        GlassToastService().showError(
          context,
          res['message']?.toString() ?? 'Не удалось сохранить контакт',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _suggestPhoto() async {
    if (_isBusy) return;
    HapticUtils.tap();

    final AvatarPickResult? pick = await TheavAvatarPickerSheet.pickAndEdit(
      context: context,
      maskShape: AvatarShapeMask.circle,
      ctaMode: AvatarEditorCtaMode.suggestPhoto,
      subjectName: _targetLabel,
    );
    if (!mounted || pick == null || !pick.hasMedia) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final res = await ContactsService.suggestPhoto(
        widget.userId,
        pick.file ?? File(pick.fileName),
        bytes: pick.bytes,
        fileName: pick.fileName,
      );
      if (!mounted) return;

      if (res['success'] == true) {
        final chatId = (res['chat_id'] ?? res['chatId'] ?? '').toString().trim();
        final photoUrl = (res['photo_url'] ?? res['photoUrl'] ?? '').toString().trim();
        GlassToastService().show(
          context,
          context.trOr('contact_suggest_photo_sent', 'Предложение фото отправлено'),
        );

        if (chatId.isNotEmpty) {
          if (widget.currentChatId != null && widget.currentChatId == chatId) {
            Navigator.of(context).pop(
              ContactEditResult(
                contact: _contactItem,
                suggestedChatId: chatId,
                suggestedPhotoUrl: photoUrl.isNotEmpty ? photoUrl : null,
                customAvatarChanged: _avatarChanged,
              ),
            );
            return;
          }
          if (TilingLayoutController.instance.isWorkspaceMounted) {
            Navigator.of(context).pop(
              ContactEditResult(
                contact: _contactItem,
                suggestedChatId: chatId,
                suggestedPhotoUrl: photoUrl.isNotEmpty ? photoUrl : null,
                customAvatarChanged: _avatarChanged,
              ),
            );
            TilingLayoutController.instance.openChatInActiveTile(
              chatId: chatId,
              chatType: 'private',
              chatName: _effectiveDisplayName,
              avatarUrl: _effectiveAvatarUrl,
              isOnline: _isOnline,
              lastSeen: _lastSeen,
              otherUserId: widget.userId,
            );
            return;
          }
          Navigator.of(context).pushReplacement(
            SwipeBackPageRoute(
              builder: (_) => PrivateChatScreen(
                chatId: chatId,
                otherUserId: widget.userId,
                otherUserName: _effectiveDisplayName,
                otherUserAvatar: _effectiveAvatarUrl,
                otherUserOnline: _isOnline,
                otherUserLastSeen: _lastSeen,
              ),
            ),
          );
        }
      } else {
        GlassToastService().showError(
          context,
          res['message']?.toString() ?? 'Не удалось предложить фото',
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _setCustomPhoto() async {
    if (_isBusy) return;
    HapticUtils.tap();

    final AvatarPickResult? pick = await TheavAvatarPickerSheet.pickAndEdit(
      context: context,
      maskShape: AvatarShapeMask.circle,
      ctaMode: AvatarEditorCtaMode.setPhoto,
      subjectName: _targetLabel,
      canDeleteCurrent: _hasCustomAvatar,
    );
    if (!mounted || pick == null) return;

    if (pick.deletedCurrent) {
      await _resetCustomPhoto(skipConfirm: true);
      return;
    }
    if (!pick.hasMedia) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final res = await ContactsService.setCustomAvatar(
        widget.userId,
        pick.file ?? File(pick.fileName),
        bytes: pick.bytes,
        fileName: pick.fileName,
      );
      if (!mounted) return;

      if (res['success'] == true) {
        final updatedContact =
            (res['contact'] as ContactItem?) ?? ContactsService.getCached(widget.userId);
        final nextCustom = _nonEmpty(res['custom_avatar_url']?.toString()) ??
            _nonEmpty(updatedContact?.customAvatarUrl);
        setState(() {
          _contactItem = updatedContact ?? _contactItem;
          _customAvatarUrl = nextCustom;
          _avatarChanged = true;
          if (_originalAvatarUrl == null &&
              updatedContact?.originalAvatarUrl != null) {
            _originalAvatarUrl = updatedContact!.originalAvatarUrl;
          }
        });
        GlassToastService().show(
          context,
          context.trOr(
            'contact_custom_photo_set',
            'Индивидуальное фото установлено',
          ),
        );
      } else {
        GlassToastService().showError(
          context,
          res['message']?.toString() ?? 'Не удалось установить фото',
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _resetCustomPhoto({bool skipConfirm = false}) async {
    if (_isBusy || !_hasCustomAvatar) return;

    if (!skipConfirm) {
      final confirmed = await showTheavDialog<bool>(
        context: context,
        title: context.trOr(
          'contact_reset_photo_confirm_title',
          'Сбросить фото?',
        ),
        message: context.trOr(
          'contact_reset_photo_confirm_body',
          'Вернуть исходное фото профиля для {name}?',
          {'name': _targetLabel},
        ),
        actions: [
          TheavDialogAction<bool>(
            label: context.trOr('profile_cancel', 'Отмена'),
            result: false,
          ),
          TheavDialogAction<bool>(
            label: context.trOr(
              'contact_reset_original_photo',
              'Вернуть исходное фото',
            ),
            result: true,
            isDestructive: true,
          ),
        ],
      );
      if (confirmed != true || !mounted) return;
    }

    HapticUtils.heavy();
    setState(() => _isUploadingPhoto = true);
    try {
      final res = await ContactsService.resetCustomAvatar(widget.userId);
      if (!mounted) return;

      if (res['success'] == true) {
        final updated =
            (res['contact'] as ContactItem?) ?? ContactsService.getCached(widget.userId);
        setState(() {
          _contactItem = updated;
          _customAvatarUrl = null;
          _avatarChanged = true;
          if (updated?.originalAvatarUrl != null &&
              updated!.originalAvatarUrl!.trim().isNotEmpty) {
            _originalAvatarUrl = updated.originalAvatarUrl!.trim();
          }
        });
        GlassToastService().show(
          context,
          context.trOr(
            'contact_custom_photo_reset',
            'Исходное фото восстановлено',
          ),
        );
      } else {
        GlassToastService().showError(
          context,
          res['message']?.toString() ?? 'Не удалось сбросить фото',
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _confirmDeleteContact() async {
    if (_isBusy || !_isContact) return;
    HapticUtils.tap();

    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: context.trOr('contact_delete_button', 'Удалить контакт'),
      message: context.trOr(
        'contact_delete_confirm_body',
        'Контакт «{name}» будет удалён из вашего списка контактов.',
        {'name': _effectiveDisplayName},
      ),
      actions: [
        TheavDialogAction<bool>(
          label: context.trOr('profile_cancel', 'Отмена'),
          result: false,
        ),
        TheavDialogAction<bool>(
          label: context.trOr('profile_delete_action', 'Удалить'),
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final res = await ContactsService.deleteContact(widget.userId);
      if (!mounted) return;
      if (res['success'] == true) {
        widget.onDeleted?.call();
        GlassToastService().show(context, 'Контакт удалён');
        Navigator.of(context).pop(
          const ContactEditResult(deleted: true),
        );
      } else {
        GlassToastService().showError(
          context,
          res['message']?.toString() ?? 'Не удалось удалить контакт',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final title = _isContact
        ? context.trOr('contact_edit_title', 'Изменить контакт')
        : context.trOr('contact_new_title', 'Новый контакт');
    final targetLabel = _targetLabel;

    return SettingsFloatingScaffold(
      title: title,
      backgroundColor: palette.bgBase,
      onBack: () {
        Navigator.of(context).pop(
          _avatarChanged
              ? ContactEditResult(
                  contact: _contactItem,
                  customAvatarChanged: true,
                )
              : null,
        );
      },
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
            tooltip: context.trOr('profile_save', 'Сохранить'),
            foregroundColor: palette.primary,
            icon: iconoir.Check(
              width: 22,
              height: 22,
              color: palette.primary,
            ),
            onTap: _save,
          ),
      ],
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(
              0,
              SettingsFloatingHeader.topClearanceOf(context) + 8,
              0,
              MediaQuery.paddingOf(context).bottom + 32,
            ),
            children: [
              // Card 1: Avatar + original identity + First/Last name fields
              TheavInsetGroup(
                dividerIndent: 16,
                children: [
                  InkWell(
                    onTap: _isBusy ? null : _setCustomPhoto,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Row(
                        children: [
                          AvatarWithStatus(
                            radius: 32,
                            userId: widget.userId,
                            avatarUrl: _effectiveAvatarUrl,
                            name: _avatarPlaceholderName,
                            isOnline: _isOnline,
                            showDecoration: false,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _headerPrimaryTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: palette.onSurface,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _buildStatusSubtitle(context),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: _isOnline
                                        ? palette.primary
                                        : palette.subtext,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  TheavInlineTextField(
                    controller: _firstNameCtrl,
                    placeholder: context.trOr('contact_first_name', 'Имя'),
                    textInputAction: TextInputAction.next,
                    enabled: !_isBusy,
                  ),
                  TheavInlineTextField(
                    controller: _lastNameCtrl,
                    placeholder: context.trOr(
                      'contact_last_name_optional',
                      'Фамилия (необязательно)',
                    ),
                    textInputAction: TextInputAction.next,
                    enabled: !_isBusy,
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Card 2: Private note
              TheavInsetGroup(
                footer: context.trOr(
                  'contact_note_hint',
                  'Заметку видите только Вы.',
                ),
                children: [
                  TheavInlineTextField(
                    controller: _noteCtrl,
                    placeholder: context.trOr(
                      'contact_note_placeholder',
                      'Заметка',
                    ),
                    maxLines: 4,
                    minLines: 1,
                    maxLength: 512,
                    autofocus: widget.autofocusNote,
                    keyboardType: TextInputType.multiline,
                    enabled: !_isBusy,
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Card 3: Photo actions (Suggest / Set Custom / Reset Original)
              TheavInsetGroup(
                dividerIndent: 54,
                children: [
                  TheavListRow(
                    leading: iconoir.Camera(
                      width: 22,
                      height: 22,
                      color: palette.primary,
                    ),
                    title: context.trOr(
                      'contact_suggest_photo_for',
                      'Предложить фото для {name}',
                      {'name': targetLabel},
                    ),
                    enabled: !_isBusy,
                    onTap: _suggestPhoto,
                  ),
                  TheavListRow(
                    leading: iconoir.MediaImagePlus(
                      width: 22,
                      height: 22,
                      color: palette.primary,
                    ),
                    title: context.trOr(
                      'contact_set_photo_for',
                      'Установить фото для {name}',
                      {'name': targetLabel},
                    ),
                    enabled: !_isBusy,
                    onTap: _setCustomPhoto,
                  ),
                  if (_hasCustomAvatar)
                    TheavListRow(
                      leading: AvatarWithStatus(
                        radius: 14,
                        avatarUrl: _originalAvatarUrl,
                        name: _avatarPlaceholderName,
                        showDecoration: false,
                      ),
                      title: context.trOr(
                        'contact_reset_original_photo',
                        'Вернуть исходное фото',
                      ),
                      enabled: !_isBusy,
                      onTap: () => _resetCustomPhoto(),
                    ),
                ],
              ),

              // Card 4: Delete contact (only when saved as contact)
              if (_isContact) ...[
                const SizedBox(height: 6),
                TheavInsetGroup(
                  children: [
                    TheavListRow(
                      isDestructive: true,
                      leading: iconoir.Trash(
                        width: 22,
                        height: 22,
                        color: palette.error,
                      ),
                      title: context.trOr(
                        'contact_delete_button',
                        'Удалить контакт',
                      ),
                      enabled: !_isBusy,
                      onTap: _confirmDeleteContact,
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (_isUploadingPhoto)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.24),
                child: Center(
                  child: CircularProgressIndicator(color: palette.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
