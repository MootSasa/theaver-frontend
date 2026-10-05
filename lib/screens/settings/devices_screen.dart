import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:iconoir_flutter/regular/laptop.dart';
import 'package:iconoir_flutter/regular/smartphone_device.dart';
import 'package:iconoir_flutter/regular/globe.dart';
import 'package:iconoir_flutter/regular/help_circle.dart';
import 'package:iconoir_flutter/regular/log_out.dart';
import 'package:iconoir_flutter/regular/edit_pencil.dart';
import 'package:iconoir_flutter/regular/map_pin.dart';
import 'package:iconoir_flutter/regular/clock.dart';
import 'package:iconoir_flutter/regular/timer.dart';
import 'package:iconoir_flutter/regular/refresh.dart';
import 'package:iconoir_flutter/regular/nav_arrow_right.dart';
import 'package:iconoir_flutter/regular/check.dart';
import 'package:iconoir_flutter/regular/info_circle.dart';

import '../../l10n/app_localizations.dart';
import '../../services/account_manager.dart';
import '../../services/auth_service.dart';
import '../../services/deep_link_service.dart';
import '../../config/app_config.dart';
import '../../widgets/settings/settings_group.dart';
import '../../utils/swipe_back_route.dart';
import '../auth/login_screen.dart';

/// Screen displaying all active device sessions for the current account.
/// Allows users to view, rename, and terminate sessions on other devices,
/// and configure automatic session termination TTL.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({Key? key}) : super(key: key);

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<DeviceSession> _sessions = [];
  bool _isLoading = true;
  String? _error;
  int _sessionsTTLDays = 180;
  final AccountManager _accountManager = AccountManager();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    await Future.wait([
      _loadSessions(),
      _loadTTL(),
    ]);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTTL() async {
    final ttl = await AuthService.getSessionsTTL();
    if (mounted) {
      setState(() {
        _sessionsTTLDays = ttl;
      });
    }
  }

  Future<void> _loadSessions() async {
    final currentDeviceId = _accountManager.currentDeviceId ?? '';

    try {
      final result = await AuthService.getActiveSessions();

      if (result['success'] == true) {
        final serverSessions = result['sessions'] as List<dynamic>? ?? [];
        final sessions = <DeviceSession>[];

        for (final serverSession in serverSessions) {
          final sessionId = serverSession['id']?.toString() ?? '';
          final deviceId = serverSession['device_id']?.toString() ?? '';
          final deviceTypeStr = serverSession['device_type']?.toString() ?? 'unknown';
          final deviceType = _parseDeviceType(deviceTypeStr);

          DateTime lastActive;
          try {
            lastActive = DateTime.parse(serverSession['last_active']?.toString() ?? '');
          } catch (_) {
            lastActive = DateTime.now();
          }

          final deviceName = serverSession['device_name']?.toString() ?? 'Unknown Device';
          
          // Prefer OS metadata directly from server
          String os = serverSession['os_name']?.toString() ?? '';
          String osVersion = serverSession['os_version']?.toString() ?? '';
          if (os.isEmpty) {
            final userAgent = serverSession['user_agent']?.toString() ?? '';
            if (userAgent.isNotEmpty) {
              final osInfo = _parseUserAgent(userAgent);
              os = osInfo['os'] ?? 'Unknown';
              osVersion = osInfo['osVersion'] ?? '';
            } else {
              os = deviceTypeStr.toUpperCase();
            }
          }

          final city = serverSession['city']?.toString();
          final country = serverSession['country']?.toString();
          final ip = serverSession['ip_address']?.toString();

          String? loc;
          if (city != null && city.isNotEmpty && country != null && country.isNotEmpty) {
            loc = '$city, $country';
          } else if (city != null && city.isNotEmpty) {
            loc = city;
          } else if (country != null && country.isNotEmpty) {
            loc = country;
          }

          final isCurrentDevice = (serverSession['is_current'] == true) || (deviceId == currentDeviceId);

          sessions.add(DeviceSession(
            id: sessionId,
            deviceId: deviceId,
            userId: serverSession['user_id']?.toString() ?? '',
            deviceName: deviceName,
            deviceType: deviceType,
            os: os,
            osVersion: osVersion,
            lastActive: lastActive,
            isCurrent: isCurrentDevice,
            location: loc,
            ipAddress: ip,
            city: city,
            country: country,
            countryCode: serverSession['country_code']?.toString(),
            appVersion: serverSession['app_version']?.toString(),
          ));
        }

        if (mounted) {
          setState(() {
            _sessions = sessions;
          });
        }
      } else {
        final localSessions = _accountManager.getDeviceSessionsForAccount(
          _accountManager.currentAccount?.userId ?? '',
        );
        if (mounted) {
          setState(() {
            _sessions = localSessions;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  Map<String, String> _parseUserAgent(String userAgent) {
    final result = <String, String>{'os': 'Unknown', 'osVersion': ''};
    if (userAgent.contains('Android')) {
      result['os'] = 'Android';
      final match = RegExp(r'Android\s+([0-9.]+)').firstMatch(userAgent);
      if (match != null) result['osVersion'] = match.group(1) ?? '';
    } else if (userAgent.contains('iPhone') || userAgent.contains('iPad')) {
      result['os'] = 'iOS';
      final match = RegExp(r'OS\s+([0-9_]+)').firstMatch(userAgent);
      if (match != null) result['osVersion'] = match.group(1)?.replaceAll('_', '.') ?? '';
    } else if (userAgent.contains('Windows')) {
      result['os'] = 'Windows';
      if (userAgent.contains('Windows NT 10.0')) result['osVersion'] = '10/11';
    } else if (userAgent.contains('Macintosh') || userAgent.contains('Mac OS')) {
      result['os'] = 'macOS';
      final match = RegExp(r'Mac OS X (\d+(?:[._]\d+)*)').firstMatch(userAgent);
      if (match != null) result['osVersion'] = match.group(1)?.replaceAll('_', '.') ?? '';
    } else if (userAgent.contains('Linux')) {
      result['os'] = 'Linux';
    }
    return result;
  }

  DeviceType _parseDeviceType(String? type) {
    switch (type?.toLowerCase()) {
      case 'android': return DeviceType.android;
      case 'ios': return DeviceType.ios;
      case 'web': return DeviceType.web;
      case 'windows': return DeviceType.windows;
      case 'macos': return DeviceType.macos;
      case 'linux': return DeviceType.linux;
      default: return DeviceType.unknown;
    }
  }

  Future<void> _handleLogout(String sessionId, String deviceId) async {
    final l10n = context.l10n;
    HapticFeedback.lightImpact();

    final isCurrent = _sessions.any((s) => s.deviceId == deviceId && s.isCurrent);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('devices_terminate_title')),
        content: Text(isCurrent
            ? l10n.translate('devices_terminate_current_warning')
            : l10n.translate('devices_terminate_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.translate('common_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.translate('devices_terminate')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (isCurrent) {
        final nav = DeepLinkService().navigatorKey.currentState ??
            Navigator.of(context, rootNavigator: true);
        nav.pushAndRemoveUntil(
          SwipeBackPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        await AuthService.logout();
        return;
      }

      final scaffoldMessenger = ScaffoldMessenger.of(context);
      try {
        final success = await AuthService.logoutDevice(deviceId);
        if (!mounted) return;
        if (success) {
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text(l10n.translate('devices_terminate_success'))),
          );
          await _loadSessions();
        } else {
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text(l10n.translate('devices_terminate_error')), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(l10n.translate('devices_error').replaceAll('{error}', e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleTerminateOthers() async {
    final l10n = context.l10n;
    HapticFeedback.lightImpact();

    final currentDevice = _sessions.where((s) => s.isCurrent).firstOrNull;
    final currentDeviceId = currentDevice?.deviceId ?? _accountManager.currentDeviceId ?? '';
    final otherCount = _sessions.where((s) => !s.isCurrent).length;

    if (otherCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('devices_no_other_sessions'))),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('devices_terminate_all_title')),
        content: Text(l10n.translate('devices_terminate_all_message')
            .replaceAll('{count}', otherCount.toString())),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.translate('common_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.translate('devices_terminate_all_short')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      try {
        final success = await AuthService.terminateOtherSessions(currentDeviceId);
        if (!mounted) return;
        if (success) {
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text(l10n.translate('devices_terminate_all_success'))),
          );
          await _loadSessions();
        } else {
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text(l10n.translate('devices_terminate_error')), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleRename(DeviceSession session) async {
    final l10n = context.l10n;
    HapticFeedback.lightImpact();

    final controller = TextEditingController(text: session.deviceName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('devices_rename_title')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: l10n.translate('devices_rename_label'),
            hintText: session.deviceName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(l10n.translate('common_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n.translate('devices_rename_save')),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && mounted) {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      try {
        final token = await AuthService.getToken();
        final dio = Dio();
        final response = await dio.put(
          '${AppConfig.baseUrl}/api/auth/sessions/${session.deviceId}/rename',
          data: {'device_name': newName},
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        if (!mounted) return;
        if (response.data['success'] == true) {
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text(l10n.translate('devices_rename_success'))),
          );
          await _loadSessions();
        } else {
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text(l10n.translate('devices_rename_error')), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showTTLDialog() {
    final l10n = context.l10n;
    HapticFeedback.lightImpact();

    final options = [
      {'days': 7, 'label': l10n.translate('devices_ttl_1_week')},
      {'days': 30, 'label': l10n.translate('devices_ttl_1_month')},
      {'days': 90, 'label': l10n.translate('devices_ttl_3_months')},
      {'days': 180, 'label': l10n.translate('devices_ttl_6_months')},
      {'days': 365, 'label': l10n.translate('devices_ttl_1_year')},
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    l10n.translate('devices_auto_terminate_title'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const Divider(),
                ...options.map((opt) {
                  final days = opt['days'] as int;
                  final label = opt['label'] as String;
                  final isSelected = _sessionsTTLDays == days;

                  return ListTile(
                    title: Text(label),
                    trailing: isSelected
                        ? Check(
                            width: 20,
                            height: 20,
                            color: Theme.of(context).primaryColor,
                          )
                        : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      HapticFeedback.lightImpact();
                      setState(() {
                        _sessionsTTLDays = days;
                      });
                      final success = await AuthService.setSessionsTTL(days);
                      if (mounted && success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.translate('settings_saved')),
                          ),
                        );
                      }
                    },
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTTLString(int days) {
    final l10n = context.l10n;
    switch (days) {
      case 7:
        return l10n.translate('devices_ttl_1_week');
      case 30:
        return l10n.translate('devices_ttl_1_month');
      case 90:
        return l10n.translate('devices_ttl_3_months');
      case 180:
        return l10n.translate('devices_ttl_6_months');
      case 365:
        return l10n.translate('devices_ttl_1_year');
      default:
        return '$days ${l10n.translate('devices_days_ago')}';
    }
  }

  String _formatLastActive(DateTime lastActive) {
    final now = DateTime.now();
    final difference = now.difference(lastActive);
    final l10n = context.l10n;

    if (difference.inMinutes < 1) {
      return l10n.translate('devices_just_now');
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} ${l10n.translate('devices_minutes_ago')}';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} ${l10n.translate('devices_hours_ago')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ${l10n.translate('devices_days_ago')}';
    } else {
      return '${lastActive.day.toString().padLeft(2, '0')}.${lastActive.month.toString().padLeft(2, '0')}.${lastActive.year}';
    }
  }

  Widget _buildDeviceIcon(DeviceType type, Color color) {
    switch (type) {
      case DeviceType.android:
      case DeviceType.ios:
        return SmartphoneDevice(width: 24, height: 24, color: color);
      case DeviceType.web:
        return Globe(width: 24, height: 24, color: color);
      case DeviceType.windows:
      case DeviceType.macos:
      case DeviceType.linux:
        return Laptop(width: 24, height: 24, color: color);
      case DeviceType.unknown:
        return HelpCircle(width: 24, height: 24, color: color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('devices_title')),
        actions: [
          IconButton(
            icon: Refresh(width: 22, height: 22, color: theme.colorScheme.onSurface),
            onPressed: _loadData,
            tooltip: l10n.translate('devices_refresh'),
          ),
        ],
      ),
      body: _buildBody(theme, l10n),
    );
  }

  Widget _buildBody(ThemeData theme, AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HelpCircle(width: 64, height: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(l10n.translate('devices_error').replaceAll('{error}', _error!),
                style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: Text(l10n.translate('devices_retry'))),
          ],
        ),
      );
    }

    final currentSession = _sessions.where((s) => s.isCurrent).firstOrNull;
    final otherSessions = _sessions.where((s) => !s.isCurrent).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        // Current Device Group
        if (currentSession != null) ...[
          SettingsGroup(
            title: l10n.translate('devices_this_device'),
            children: [
              _buildSessionTile(
                session: currentSession,
                isCurrent: true,
                onRename: () => _handleRename(currentSession),
                onLogout: null,
              ),
            ],
          ),
        ],

        // Session Auto-Termination TTL Group
        SettingsGroup(
          title: l10n.translate('devices_auto_terminate_section'),
          children: [
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Timer(
                  width: 22,
                  height: 22,
                  color: theme.colorScheme.primary,
                ),
              ),
              title: Text(l10n.translate('devices_auto_terminate_title')),
              subtitle: Text(_formatTTLString(_sessionsTTLDays)),
              trailing: NavArrowRight(
                width: 18,
                height: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onTap: _showTTLDialog,
            ),
          ],
        ),

        // Other Sessions Group
        if (otherSessions.isNotEmpty) ...[
          SettingsGroup(
            title: l10n.translate('devices_other_sessions'),
            children: [
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const LogOut(
                    width: 22,
                    height: 22,
                    color: Colors.red,
                  ),
                ),
                title: Text(
                  l10n.translate('devices_terminate_all_short'),
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: _handleTerminateOthers,
              ),
              ...otherSessions.map((session) => _buildSessionTile(
                session: session,
                isCurrent: false,
                onRename: () => _handleRename(session),
                onLogout: () => _handleLogout(session.id, session.deviceId),
              )),
            ],
          ),
        ],

        // Security Info Group
        SettingsGroup(
          title: l10n.translate('devices_info_title'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoCircle(
                    width: 22,
                    height: 22,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.translate('devices_info_description'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSessionTile({
    required DeviceSession session,
    required bool isCurrent,
    required VoidCallback onRename,
    required VoidCallback? onLogout,
  }) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final locationDisplay = <String>[];
    if (session.location != null && session.location!.isNotEmpty) {
      locationDisplay.add(session.location!);
    }
    if (session.ipAddress != null && session.ipAddress!.isNotEmpty) {
      locationDisplay.add(session.ipAddress!);
    }
    final locationText = locationDisplay.join(' • ');

    final osText = session.osVersion.isNotEmpty
        ? '${session.os} ${session.osVersion}'
        : session.os;

    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isCurrent
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: _buildDeviceIcon(
          session.deviceType,
          isCurrent
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              session.deviceName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCurrent)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                l10n.translate('devices_active_now'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              osText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Clock(
                  width: 14,
                  height: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatLastActive(session.lastActive),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (locationText.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  MapPin(
                    width: 14,
                    height: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      locationText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      trailing: isCurrent
          ? IconButton(
              icon: EditPencil(
                width: 20,
                height: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: onRename,
              tooltip: l10n.translate('devices_rename_title'),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: EditPencil(
                    width: 20,
                    height: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: onRename,
                  tooltip: l10n.translate('devices_rename_title'),
                ),
                IconButton(
                  icon: const LogOut(
                    width: 20,
                    height: 20,
                    color: Colors.red,
                  ),
                  onPressed: onLogout,
                  tooltip: l10n.translate('devices_terminate'),
                ),
              ],
            ),
      onLongPress: onRename,
    );
  }
}
