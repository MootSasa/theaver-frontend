import 'package:flutter/material.dart';
import '../../widgets/settings/settings_floating_header.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/privacy_settings_provider.dart';
import '../../services/settings_service.dart';

/// Экран «Заблокированные пользователи» — список, разблокировка
class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsFloatingScaffold(
      title: l10n.translate('security_blocked_users'),
      body: Consumer<PrivacySettingsProvider>(
        builder: (context, provider, _) {
          final blocked = provider.blockedUsers;
          if (blocked.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.block, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(l10n.translate('security_no_blocked_users'),
                    style: TextStyle(color: Colors.grey[500])),
              ]),
            );
          }
          return ListView.builder(
            itemCount: blocked.length,
            itemBuilder: (context, index) {
              final user = blocked[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(user.displayName.isNotEmpty ? user.displayName[0] : '?'),
                ),
                title: Text(user.displayName.isNotEmpty ? user.displayName : user.username),
                subtitle: Text('@${user.username}'),
                trailing: TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(l10n.translate('security_unblock_confirm_title')),
                        content: Text(l10n.translate('security_unblock_confirm_body')
                            .replaceAll('{name}', user.displayName)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.translate('cancel'))),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.translate('security_unblock'))),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await provider.unblockUser(user.userId);
                    }
                  },
                  child: Text(l10n.translate('security_unblock'), style: TextStyle(color: Colors.blue)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
