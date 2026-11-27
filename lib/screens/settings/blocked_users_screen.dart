import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/account_manager.dart';
import '../../services/contacts_service.dart';
import '../../services/privacy_settings_provider.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/settings/user_search_picker_dialog.dart';
import '../../widgets/user/avatar_with_status.dart';

/// Screen "Blocked Users" — list, search/add block, and unblock with confirmation.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PrivacySettingsProvider>().loadBlockedUsers();
    });
  }

  Future<void> _pickAndBlockUser() async {
    final l10n = context.l10n;
    final provider = context.read<PrivacySettingsProvider>();
    final selfId = AccountManager().currentAccount?.userId;
    final exclude = <String>{
      if (selfId != null && selfId.isNotEmpty) selfId,
      ...provider.blockedUsers.map((u) => u.userId),
    };
    final picked = await showUserSearchPickerDialog(
      context,
      title: l10n.translate('security_block_user_title'),
      excludeUserIds: exclude,
    );
    if (picked == null || !mounted) return;
    final ok = await provider.blockUser(picked.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? l10n.translate('security_user_blocked')
              : l10n.translate('common_error'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final headerFg = SettingsFloatingHeader.foregroundColorOf(context);
    return SettingsFloatingScaffold(
      title: l10n.translate('security_blocked_users'),
      actions: [
        SettingsHeaderAction(
          icon: Icon(Icons.person_add_outlined, size: 22, color: headerFg),
          onTap: _pickAndBlockUser,
          tooltip: l10n.translate('security_block_user_title'),
        ),
      ],
      body: Consumer<PrivacySettingsProvider>(
        builder: (context, provider, _) {
          final blocked = provider.blockedUsers;
          if (blocked.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(
                      l10n.translate('security_no_blocked_users'),
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _pickAndBlockUser,
                      icon: const Icon(Icons.person_add_outlined),
                      label: Text(l10n.translate('security_block_user_title')),
                    ),
                  ],
                ),
              ),
            );
          }
          return ValueListenableBuilder<int>(
            valueListenable: ContactsService.revisionNotifier,
            builder: (context, _, __) => ListView.builder(
              padding: EdgeInsets.only(
                top: SettingsFloatingHeader.topClearanceOf(context) + 8,
                bottom: 24,
              ),
              itemCount: blocked.length,
              itemBuilder: (context, index) {
                final user = blocked[index];
                final rawLabel = user.displayName.isNotEmpty
                    ? user.displayName
                    : user.username;
                final label = ContactsService.resolvePeerName(
                  user.userId,
                  rawLabel,
                );
                final avatarUrl = ContactsService.resolvePeerAvatarUrl(
                  user.userId,
                  user.avatarUrl,
                );
                return ListTile(
                  leading: AvatarWithStatus(
                    userId: user.userId,
                    avatarUrl: avatarUrl,
                    name: label,
                    radius: 20,
                  ),
                  title: Text(label),
                  subtitle: Text('@${user.username}'),
                  trailing: TextButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(l10n.translate('security_unblock_confirm_title')),
                          content: Text(
                            l10n
                                .translate('security_unblock_confirm_body')
                                .replaceAll('{name}', label),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(l10n.translate('cancel')),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(l10n.translate('security_unblock')),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await provider.unblockUser(user.userId);
                      }
                    },
                    child: Text(
                      l10n.translate('security_unblock'),
                      style: const TextStyle(color: Colors.blue),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
