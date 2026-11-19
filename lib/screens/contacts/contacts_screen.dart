import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/chat_service.dart';
import '../../services/contacts_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/common/peer_badges_widget.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/user/avatar_with_status.dart';
import '../chat/private_chat_screen.dart';

/// Telegram-style Contacts screen backed by `/api/contacts`, built with
/// Theaver's Dual-Mode Liquid Glass / Material 3 Matte design system.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<ContactItem> _contacts = const [];
  bool _isLoading = true;
  bool _isOpeningChat = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() => _query = _searchController.text.trim());
    });
    _loadContacts(forceRefresh: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts({bool forceRefresh = false}) async {
    if (mounted) setState(() => _isLoading = _contacts.isEmpty);
    final list = await ContactsService.getContacts(forceRefresh: forceRefresh);
    if (!mounted) return;
    setState(() {
      _contacts = list;
      _isLoading = false;
    });
  }

  List<ContactItem> get _filteredContacts {
    if (_query.isEmpty) return _contacts;
    final q = _query.toLowerCase();
    return _contacts.where((c) {
      return c.effectiveName.toLowerCase().contains(q) ||
          c.username.toLowerCase().contains(q) ||
          c.displayName.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openContactChat(ContactItem contact) async {
    if (_isOpeningChat) return;
    HapticUtils.tap();
    setState(() => _isOpeningChat = true);
    try {
      final result = await ChatService.createChat(
        chatType: 'private',
        participantIds: [contact.contactUserId],
      );
      if (!mounted) return;
      if (result['success'] == true) {
        final chat = result['chat'] as Chat;
        if (TilingLayoutController.instance.isWorkspaceMounted) {
          Navigator.of(context).pop();
          TilingLayoutController.instance.openChatInActiveTile(
            chatId: chat.id,
            chatType: 'private',
            chatName: contact.effectiveName,
            avatarUrl: contact.avatarUrl,
            otherUserId: contact.contactUserId,
          );
          return;
        }
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => PrivateChatScreen(
              chatId: chat.id,
              otherUserName: contact.effectiveName,
              otherUserAvatar:
                  contact.avatarUrl.isNotEmpty ? contact.avatarUrl : null,
              otherUserOnline: contact.isOnline,
              otherUserId: contact.contactUserId,
            ),
          ),
        );
      } else {
        GlassToastService().showError(
          context,
          result['message']?.toString() ?? 'Не удалось открыть чат',
        );
      }
    } catch (e) {
      if (mounted) GlassToastService().showError(context, 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _isOpeningChat = false);
    }
  }

  Future<void> _showAddContactDialog() async {
    final usernameCtrl = TextEditingController();
    final firstNameCtrl = TextEditingController();
    final lastNameCtrl = TextEditingController();
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Новый контакт',
      content: TheavInsetGroup(
        margin: EdgeInsets.zero,
        dividerIndent: 16,
        children: [
          TheavInlineTextField(
            controller: usernameCtrl,
            placeholder: '@username',
            autofocus: true,
          ),
          TheavInlineTextField(
            controller: firstNameCtrl,
            placeholder: 'Имя (необязательно)',
          ),
          TheavInlineTextField(
            controller: lastNameCtrl,
            placeholder: 'Фамилия (необязательно)',
          ),
        ],
      ),
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(label: 'Добавить', result: true, isPrimary: true),
      ],
    );
    final username = usernameCtrl.text.trim();
    final firstName = firstNameCtrl.text.trim();
    final lastName = lastNameCtrl.text.trim();
    usernameCtrl.dispose();
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();

    if (confirmed != true || username.isEmpty || !mounted) return;
    final res = await ContactsService.addContact(
      username: username,
      firstName: firstName.isNotEmpty ? firstName : null,
      lastName: lastName.isNotEmpty ? lastName : null,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      GlassToastService().show(context, 'Контакт добавлен');
      await _loadContacts(forceRefresh: true);
    } else {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось добавить контакт',
      );
    }
  }

  Future<void> _showEditContactDialog(ContactItem contact) async {
    final firstNameCtrl = TextEditingController(text: contact.customFirstName);
    final lastNameCtrl = TextEditingController(text: contact.customLastName);
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Изменить контакт',
      content: TheavInsetGroup(
        margin: EdgeInsets.zero,
        dividerIndent: 16,
        children: [
          TheavInlineTextField(
            controller: firstNameCtrl,
            placeholder: 'Имя',
            autofocus: true,
          ),
          TheavInlineTextField(
            controller: lastNameCtrl,
            placeholder: 'Фамилия',
          ),
        ],
      ),
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(label: 'Сохранить', result: true, isPrimary: true),
      ],
    );
    final firstName = firstNameCtrl.text.trim();
    final lastName = lastNameCtrl.text.trim();
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();

    if (confirmed != true || !mounted) return;
    final res = await ContactsService.updateContact(
      contact.contactUserId,
      firstName: firstName,
      lastName: lastName,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      GlassToastService().show(context, 'Контакт обновлён');
      await _loadContacts(forceRefresh: true);
    } else {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось обновить контакт',
      );
    }
  }

  Future<void> _confirmRemoveContact(ContactItem contact) async {
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Удалить из контактов?',
      message:
          'Контакт «${contact.effectiveName}» будет удалён из вашего списка контактов.',
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(
          label: 'Удалить',
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    final res = await ContactsService.deleteContact(contact.contactUserId);
    if (!mounted) return;
    if (res['success'] == true) {
      GlassToastService().show(context, 'Контакт удалён');
      await _loadContacts(forceRefresh: true);
    } else {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось удалить контакт',
      );
    }
  }

  Future<void> _showContactActions(ContactItem contact) async {
    HapticUtils.selection();
    final action = await showTheavModalSheet<String>(
      context: context,
      title: contact.effectiveName,
      builder: (sheetCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            children: [
              TheavListRow(
                leading: iconoir.ChatBubble(
                  width: 20,
                  height: 20,
                  color: context.theav.primary,
                ),
                title: 'Написать сообщение',
                onTap: () => Navigator.of(sheetCtx).pop('chat'),
              ),
              TheavListRow(
                leading: iconoir.EditPencil(
                  width: 20,
                  height: 20,
                  color: context.theav.primary,
                ),
                title: 'Изменить имя контакта',
                onTap: () => Navigator.of(sheetCtx).pop('edit'),
              ),
              TheavListRow(
                leading: iconoir.Trash(
                  width: 20,
                  height: 20,
                  color: context.theav.error,
                ),
                title: 'Удалить из контактов',
                isDestructive: true,
                onTap: () => Navigator.of(sheetCtx).pop('delete'),
              ),
            ],
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'chat':
        await _openContactChat(contact);
        break;
      case 'edit':
        await _showEditContactDialog(contact);
        break;
      case 'delete':
        await _confirmRemoveContact(contact);
        break;
    }
  }

  String _subtitleFor(ContactItem c) {
    final status = c.isOnline
        ? 'в сети'
        : (c.lastSeen != null
            ? DateTimeUtils.formatLastSeen(c.lastSeen!, context)
            : 'не в сети');
    if (c.isMutual) return '$status • взаимный контакт';
    return status;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final items = _filteredContacts;

    return SettingsFloatingScaffold(
      title: 'Контакты',
      backgroundColor: palette.bgBase,
      actions: [
        SettingsHeaderAction(
          tooltip: 'Добавить контакт',
          foregroundColor: palette.primary,
          icon: iconoir.UserPlus(width: 21, height: 21, color: palette.primary),
          onTap: _showAddContactDialog,
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () => _loadContacts(forceRefresh: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
          children: [
            TheavInsetGroup(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              children: [
                TheavInlineTextField(
                  controller: _searchController,
                  placeholder: 'Поиск контактов...',
                  prefix: Icon(
                    Icons.search_rounded,
                    color: palette.primary,
                    size: 20,
                  ),
                  suffix: _query.isNotEmpty
                      ? GestureDetector(
                          onTap: () => _searchController.clear(),
                          child: Icon(
                            Icons.clear_rounded,
                            size: 18,
                            color: palette.subtext,
                          ),
                        )
                      : null,
                ),
              ],
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                child: Column(
                  children: [
                    iconoir.UserCircle(
                      width: 56,
                      height: 56,
                      color: palette.subtext.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _query.isEmpty
                          ? 'Список контактов пока пуст'
                          : 'Контакты не найдены',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _query.isEmpty
                          ? 'Нажмите +, чтобы добавить пользователя по @username или из профиля'
                          : 'Попробуйте другой запрос',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: palette.subtext,
                      ),
                    ),
                  ],
                ),
              )
            else
              TheavInsetGroup(
                header: 'КОНТАКТЫ (${items.length})',
                dividerIndent: 70,
                children: [
                  for (final contact in items)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () => _showContactActions(contact),
                      child: TheavListRow(
                        leading: AvatarWithStatus(
                          avatarUrl: contact.avatarUrl.isNotEmpty
                              ? contact.avatarUrl
                              : null,
                          name: contact.effectiveName,
                          radius: 21,
                          isOnline: contact.isOnline,
                        ),
                        titleWidget: Row(
                          children: [
                            Flexible(
                              child: Text(
                                contact.effectiveName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w500,
                                  color: palette.textPrimary,
                                ),
                              ),
                            ),
                            if (contact.isVerified || contact.isBot) ...[
                              const SizedBox(width: 4),
                              PeerBadgesRow(
                                isVerified: contact.isVerified,
                                isBot: contact.isBot,
                                iconSize: 15,
                              ),
                            ],
                          ],
                        ),
                        subtitle: _subtitleFor(contact),
                        trailing: IconButton(
                          icon: iconoir.MoreHoriz(
                            width: 20,
                            height: 20,
                            color: palette.subtext,
                          ),
                          onPressed: () => _showContactActions(contact),
                        ),
                        onTap: () => _openContactChat(contact),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
