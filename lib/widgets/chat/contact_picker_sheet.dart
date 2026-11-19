import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/contacts_service.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../design_system/theav_design_system.dart';

class ContactPickResult {
  final String? userId;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String username;
  final String avatarUrl;

  const ContactPickResult({
    this.userId,
    required this.firstName,
    this.lastName = '',
    this.phoneNumber = '',
    this.username = '',
    this.avatarUrl = '',
  });

  String get displayName {
    final full = '$firstName $lastName'.trim();
    if (full.isNotEmpty) return full;
    if (username.isNotEmpty) return '@$username';
    if (phoneNumber.isNotEmpty) return phoneNumber;
    return 'Контакт';
  }

  Map<String, dynamic> toPayload() => {
        if (userId != null && userId!.isNotEmpty) 'user_id': userId,
        'first_name': firstName,
        if (lastName.isNotEmpty) 'last_name': lastName,
        if (phoneNumber.isNotEmpty) 'phone_number': phoneNumber,
        if (username.isNotEmpty) 'username': username,
        if (avatarUrl.isNotEmpty) 'avatar_url': avatarUrl,
      };
}

Future<ContactPickResult?> showContactPickerSheet(BuildContext context) {
  return showTheavModalSheet<ContactPickResult>(
    context: context,
    title: 'Отправить контакт',
    showCloseButton: true,
    builder: (ctx) => const _ContactPickerSheetBody(),
  );
}

class _ContactPickerSheetBody extends StatefulWidget {
  const _ContactPickerSheetBody();

  @override
  State<_ContactPickerSheetBody> createState() =>
      _ContactPickerSheetBodyState();
}

class _ContactPickerSheetBodyState extends State<_ContactPickerSheetBody> {
  int _tab = 0; // 0 = contacts list, 1 = manual entry
  bool _loading = true;
  List<ContactItem> _contacts = const [];
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final list = await ContactsService.getContacts();
    if (!mounted) return;
    setState(() {
      _contacts = list;
      _loading = false;
    });
  }

  List<ContactItem> get _filteredContacts {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _contacts;
    return _contacts.where((c) {
      return c.effectiveName.toLowerCase().contains(q) ||
          c.username.toLowerCase().contains(q) ||
          c.displayName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TheavSegmentedControl<int>(
          options: const [
            TheavSegmentOption(value: 0, label: 'Из контактов'),
            TheavSegmentOption(value: 1, label: 'Вручную'),
          ],
          selected: _tab,
          onChanged: (v) => setState(() => _tab = v),
          margin: const EdgeInsets.only(bottom: 12),
        ),
        if (_tab == 0) ...[
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Поиск контакта...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: palette.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.divider, width: 0.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.divider, width: 0.5),
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320, minHeight: 160),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredContacts.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _contacts.isEmpty
                                ? 'Список контактов пуст — можно ввести контакт вручную'
                                : 'Контакты не найдены',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: palette.subtext),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _filteredContacts.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 0.5,
                          indent: 58,
                          color: palette.divider,
                        ),
                        itemBuilder: (ctx, idx) {
                          final c = _filteredContacts[idx];
                          final name = c.effectiveName;
                          final sub = c.username.isNotEmpty
                              ? '@${c.username}'
                              : 'Контакт Theaver';
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor:
                                  palette.primary.withValues(alpha: 0.14),
                              backgroundImage: c.avatarUrl.isNotEmpty
                                  ? avatarImageProvider(c.avatarUrl)
                                  : null,
                              child: c.avatarUrl.isEmpty
                                  ? Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: palette.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(
                              name,
                              style: TextStyle(
                                color: palette.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              sub,
                              style: TextStyle(
                                color: palette.subtext,
                                fontSize: 12.5,
                              ),
                            ),
                            onTap: () {
                              HapticUtils.selection();
                              final first = c.customFirstName.isNotEmpty
                                  ? c.customFirstName
                                  : name;
                              Navigator.of(context).pop(
                                ContactPickResult(
                                  userId: c.contactUserId,
                                  firstName: first,
                                  lastName: c.customLastName,
                                  username: c.username,
                                  avatarUrl: c.avatarUrl,
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ] else ...[
          TheavInsetGroup(
            margin: const EdgeInsets.only(bottom: 12),
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: TextField(
                  controller: _firstNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                    border: InputBorder.none,
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: TextField(
                  controller: _lastNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Фамилия (необязательно)',
                    border: InputBorder.none,
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Номер телефона',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          TheavFloatingPillButton(
            label: 'Отправить контакт',
            icon: iconoir.User(
              width: 18,
              height: 18,
              color: palette.onPrimary,
            ),
            isPrimary: true,
            onTap: () {
              final first = _firstNameCtrl.text.trim();
              final last = _lastNameCtrl.text.trim();
              final phone = _phoneCtrl.text.trim();
              if (first.isEmpty && phone.isEmpty) return;
              HapticUtils.selection();
              Navigator.of(context).pop(
                ContactPickResult(
                  firstName: first.isNotEmpty ? first : phone,
                  lastName: last,
                  phoneNumber: phone,
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
