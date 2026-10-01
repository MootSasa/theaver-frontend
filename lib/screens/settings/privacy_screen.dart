import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/privacy_settings_provider.dart';
import '../../services/settings_service.dart';
import '../../widgets/settings/settings_group.dart';
import '../../widgets/common/adaptive_switch.dart';
import 'privacy_detail_screen.dart';
import 'security_screen.dart';

/// Экран «Приватность» — 7 пунктов приватности + секция «Безопасность»
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.translate('privacy_title'))),
      body: Consumer<PrivacySettingsProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final p = provider.privacy;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // Секция «Кто видит»
              SettingsGroup(
                title: l10n.translate('privacy_section_visibility'),
                children: [
                  _privacyTile(context, l10n.translate('privacy_last_seen'),
                      p.lastSeenVisibility, 'last_seen_visibility'),
                  _privacyTile(context, l10n.translate('privacy_profile_photo'),
                      p.profilePhotoVisibility, 'profile_photo_visibility'),
                  _privacyTile(context, l10n.translate('privacy_phone_number'),
                      p.phoneNumberVisibility, 'phone_number_visibility'),
                  _privacyTile(context, l10n.translate('privacy_phone_call'),
                      p.phoneCallPrivacy, 'phone_call_privacy'),
                  _privacyTile(context, l10n.translate('privacy_calls'),
                      p.callPrivacy, 'call_privacy'),
                  _privacyTile(context, l10n.translate('privacy_groups_channels'),
                      p.groupsChannelsPrivacy, 'groups_channels_privacy'),
                  _privacyTile(context, l10n.translate('privacy_bio'),
                      p.bioVisibility, 'bio_visibility'),
                ],
              ),

              SettingsGroup(
                children: [
                  // Пересланные сообщения
                  AdaptiveSwitchListTile(
                    title: Text(l10n.translate('privacy_forwarded_messages')),
                    subtitle: Text(p.forwardedMessages == PrivacyVisibility.nobody
                        ? l10n.translate('privacy_forward_anonymous')
                        : l10n.translate('privacy_forward_show_sender')),
                    value: p.forwardedMessages == PrivacyVisibility.everybody,
                    onChanged: (v) => provider.updatePrivacyField(
                        'forwarded_messages',
                        v ? PrivacyVisibility.everybody : PrivacyVisibility.nobody),
                  ),
                ],
              ),

              // Логические переключатели
              SettingsGroup(
                title: l10n.translate('privacy_section_toggles'),
                children: [
                  AdaptiveSwitchListTile(
                    title: Text(l10n.translate('privacy_show_online_status')),
                    value: p.showOnlineStatus,
                    onChanged: (v) =>
                        provider.updatePrivacyField('show_online_status', v),
                  ),
                  AdaptiveSwitchListTile(
                    title: Text(l10n.translate('privacy_show_read_receipts')),
                    value: p.showReadReceipts,
                    onChanged: (v) =>
                        provider.updatePrivacyField('show_read_receipts', v),
                  ),
                ],
              ),

              // Секция «Безопасность»
              SettingsGroup(
                title: l10n.translate('security_title'),
                children: [
                  ListTile(
                    leading: const Icon(Icons.security),
                    title: Text(l10n.translate('security_title')),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SecurityScreen())),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _privacyTile(BuildContext context, String title, PrivacyVisibility value, String field) {
    final l10n = context.l10n;
    final valueText = _visibilityLabel(l10n, value);
    return ListTile(
      title: Text(title),
      trailing: Text(valueText, style: TextStyle(color: Colors.grey[600])),
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PrivacyDetailScreen(field: field, title: title))),
    );
  }

  String _visibilityLabel(AppLocalizations l10n, PrivacyVisibility v) => switch (v) {
    PrivacyVisibility.everybody => l10n.translate('privacy_everybody'),
    PrivacyVisibility.contacts => l10n.translate('privacy_contacts'),
    PrivacyVisibility.nobody => l10n.translate('privacy_nobody'),
  };
}
