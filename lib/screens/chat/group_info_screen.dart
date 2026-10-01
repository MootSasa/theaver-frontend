import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../services/auth_service.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/user/avatar_with_status.dart';
import '../../widgets/common/adaptive_switch.dart';

/// Экран информации о группе — фото, имя, описание, ссылка, участники, настройки
class GroupInfoScreen extends StatefulWidget {
  final String chatId;
  final String? groupName;
  final String? groupAvatar;

  const GroupInfoScreen({
    Key? key,
    required this.chatId,
    this.groupName,
    this.groupAvatar,
  }) : super(key: key);

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  bool _isLoading = true;
  String _name = '';
  String _description = '';
  String _inviteLink = '';
  bool _isPublic = false;
  bool _historyForNew = true;
  int _slowModeInterval = 0;
  int _memberCount = 0;
  List<_GroupMember> _members = [];

  @override
  void initState() {
    super.initState();
    _loadGroupInfo();
  }

  Future<void> _loadGroupInfo() async {
    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      final response = await dio.get(
        '${AppConfig.baseUrl}/api/chats/${widget.chatId}/group-settings',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data;
      final membersResp = await dio.get(
        '${AppConfig.baseUrl}/api/chats/${widget.chatId}/members',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (mounted) {
        setState(() {
          _name = data['name'] ?? widget.groupName ?? '';
          _description = data['description'] ?? '';
          _inviteLink = data['invite_link'] ?? '';
          _isPublic = data['is_public'] ?? false;
          _historyForNew = data['history_for_new'] ?? true;
          _slowModeInterval = data['slow_mode_interval'] ?? 0;
          _memberCount = data['member_count'] ?? 0;
          _members = (membersResp.data['members'] as List?)
                  ?.map((e) => _GroupMember.fromJson(e))
                  .toList() ??
              [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.translate('group_info_title'))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              // Avatar + Name
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(children: [
                    AvatarWithStatus(
                      avatarUrl: widget.groupAvatar,
                      name: _name,
                      radius: 48,
                      isOnline: false,
                    ),
                    const SizedBox(height: 12),
                    Text(_name, style: theme.textTheme.headlineSmall),
                    Text('$_memberCount ${l10n.translate('group_info_members')}',
                        style: TextStyle(color: Colors.grey[600])),
                  ]),
                ),
              ),
              const Divider(),

              // Description
              if (_description.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.translate('group_info_description')),
                  subtitle: Text(_description),
                ),

              // Invite link
              if (_inviteLink.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(l10n.translate('group_info_invite_link')),
                  subtitle: Text(_inviteLink),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      // Copy to clipboard
                    },
                  ),
                ),

              // Public/Private
              ListTile(
                leading: Icon(_isPublic ? Icons.public : Icons.lock),
                title: Text(_isPublic
                    ? l10n.translate('group_info_public')
                    : l10n.translate('group_info_private')),
              ),

              // History for new members
              AdaptiveSwitchListTile(
                secondary: const Icon(Icons.history),
                title: Text(l10n.translate('group_info_history_for_new')),
                value: _historyForNew,
                onChanged: (v) => _updateSetting(historyForNew: v),
              ),

              // Slow mode
              ListTile(
                leading: const Icon(Icons.speed),
                title: Text(l10n.translate('group_info_slow_mode')),
                trailing: Text(_slowModeLabel(l10n),
                    style: TextStyle(color: Colors.grey[600])),
                onTap: _showSlowModePicker,
              ),

              const Divider(),

              // Members section
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  Text('${l10n.translate('group_info_members_section')} ($_memberCount)',
                      style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      // Navigate to full members screen
                    },
                    child: Text(l10n.translate('group_info_view_all')),
                  ),
                ]),
              ),

              // Show first 5 members
              for (final m in _members.take(5))
                ListTile(
                  leading: CircleAvatar(
                    child: Text(m.displayName.isNotEmpty ? m.displayName[0] : '?'),
                  ),
                  title: Text(m.displayName.isNotEmpty ? m.displayName : m.username),
                  subtitle: Text('@${m.username}'),
                  trailing: _roleBadge(m.role),
                ),
            ]),
    );
  }

  Widget _roleBadge(String role) {
    final color = role == 'owner' ? Colors.orange : role == 'admin' ? Colors.blue : Colors.transparent;
    if (role == 'member') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(role.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }

  String _slowModeLabel(AppLocalizations l10n) {
    switch (_slowModeInterval) {
      case 0: return l10n.translate('group_slow_off');
      case 10: return '10с';
      case 30: return '30с';
      case 60: return '1м';
      case 300: return '5м';
      case 900: return '15м';
      default: return '${_slowModeInterval}с';
    }
  }

  void _showSlowModePicker() {
    final l10n = context.l10n;
    final options = [0, 10, 30, 60, 300, 900];
    final labels = options.map((v) => _slowModeLabel(l10n)).toList();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(options.length, (i) => ListTile(
          title: Text(labels[i]),
          trailing: _slowModeInterval == options[i] ? const Icon(Icons.check) : null,
          onTap: () {
            _updateSetting(slowModeInterval: options[i]);
            Navigator.pop(ctx);
          },
        )),
      ),
    );
  }

  Future<void> _updateSetting({bool? historyForNew, int? slowModeInterval}) async {
    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      await dio.put(
        '${AppConfig.baseUrl}/api/chats/${widget.chatId}/group-settings',
        data: {
          if (historyForNew != null) 'history_for_new': historyForNew,
          if (slowModeInterval != null) 'slow_mode_interval': slowModeInterval,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      setState(() {
        if (historyForNew != null) _historyForNew = historyForNew;
        if (slowModeInterval != null) _slowModeInterval = slowModeInterval;
      });
    } catch (_) {}
  }
}

class _GroupMember {
  final String userId;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final String role;

  _GroupMember({required this.userId, required this.displayName, required this.username, this.avatarUrl, required this.role});

  factory _GroupMember.fromJson(Map<String, dynamic> json) => _GroupMember(
    userId: json['user_id'] ?? '',
    displayName: json['display_name'] ?? '',
    username: json['username'] ?? '',
    avatarUrl: json['avatar_url'],
    role: json['role'] ?? 'member',
  );
}
