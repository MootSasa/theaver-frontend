import 'package:flutter/material.dart';
import '../../widgets/settings/settings_floating_header.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/privacy_settings_provider.dart';
import '../../services/settings_service.dart';

/// Экран детальной настройки одного правила приватности.
/// Выбор видимости + исключения (всегда/никогда для конкретных пользователей).
class PrivacyDetailScreen extends StatefulWidget {
  final String field;
  final String title;

  const PrivacyDetailScreen({super.key, required this.field, required this.title});

  @override
  State<PrivacyDetailScreen> createState() => _PrivacyDetailScreenState();
}

class _PrivacyDetailScreenState extends State<PrivacyDetailScreen> {
  List<PrivacyException> _alwaysExceptions = [];
  List<PrivacyException> _neverExceptions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExceptions();
  }

  Future<void> _loadExceptions() async {
    final provider = context.read<PrivacySettingsProvider>();
    final exceptions = await provider.loadExceptions(widget.field);
    if (mounted) {
      setState(() {
        _alwaysExceptions = exceptions.where((e) => e.exceptionType == 'always').toList();
        _neverExceptions = exceptions.where((e) => e.exceptionType == 'never').toList();
        _loading = false;
      });
    }
  }

  PrivacyVisibility _currentValue() {
    final p = context.read<PrivacySettingsProvider>().privacy;
    switch (widget.field) {
      case 'last_seen_visibility': return p.lastSeenVisibility;
      case 'profile_photo_visibility': return p.profilePhotoVisibility;
      case 'phone_number_visibility': return p.phoneNumberVisibility;
      case 'phone_call_privacy': return p.phoneCallPrivacy;
      case 'call_privacy': return p.callPrivacy;
      case 'groups_channels_privacy': return p.groupsChannelsPrivacy;
      case 'bio_visibility': return p.bioVisibility;
      default: return PrivacyVisibility.contacts;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currentValue = _currentValue();

    return SettingsFloatingScaffold(
      title: widget.title,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              // Выбор видимости
              _sectionHeader(l10n.translate('privacy_who_can_see')),
              _radioTile(l10n.translate('privacy_everybody'), PrivacyVisibility.everybody, currentValue),
              _radioTile(l10n.translate('privacy_contacts'), PrivacyVisibility.contacts, currentValue),
              _radioTile(l10n.translate('privacy_nobody'), PrivacyVisibility.nobody, currentValue),

              const Divider(height: 32),

              // Исключения: всегда делиться
              _sectionHeader(l10n.translate('privacy_always_share_with')),
              if (_alwaysExceptions.isEmpty)
                _emptyHint(l10n.translate('privacy_no_exceptions')),
              ..._alwaysExceptions.map((e) => _exceptionTile(e, 'always')),

              ListTile(
                leading: const Icon(Icons.person_add, color: Colors.blue),
                title: Text(l10n.translate('privacy_add_exception')),
                onTap: () => _addException('always'),
              ),

              const Divider(height: 32),

              // Исключения: никогда не делиться
              _sectionHeader(l10n.translate('privacy_never_share_with')),
              if (_neverExceptions.isEmpty)
                _emptyHint(l10n.translate('privacy_no_exceptions')),
              ..._neverExceptions.map((e) => _exceptionTile(e, 'never')),

              ListTile(
                leading: const Icon(Icons.person_add, color: Colors.red),
                title: Text(l10n.translate('privacy_add_exception')),
                onTap: () => _addException('never'),
              ),
            ]),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }

  Widget _radioTile(String label, PrivacyVisibility value, PrivacyVisibility current) {
    return RadioListTile<PrivacyVisibility>(
      title: Text(label),
      value: value,
      groupValue: current,
      onChanged: (v) {
        if (v != null) {
          context.read<PrivacySettingsProvider>().updatePrivacyField(widget.field, v);
        }
      },
    );
  }

  Widget _emptyHint(String text) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(text, style: TextStyle(color: Colors.grey[500])));
  }

  Widget _exceptionTile(PrivacyException e, String type) {
    return ListTile(
      leading: CircleAvatar(child: Text(e.targetUserName.isNotEmpty ? e.targetUserName[0] : '?')),
      title: Text(e.targetUserName),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 20),
        onPressed: () async {
          await context.read<PrivacySettingsProvider>().removeException(e.id, widget.field);
          _loadExceptions();
        },
      ),
    );
  }

  void _addException(String type) {
    // TODO: Show contact picker dialog
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Contact picker — coming soon')),
    );
  }
}
