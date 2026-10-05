import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';
import 'privacy_screen.dart';
import 'storage_screen.dart';
import 'devices_screen.dart';
import 'folders_screen.dart';
import 'power_saving_screen.dart';
import 'language_screen.dart';
import 'chat_settings_screen.dart';
import 'accounts_screen.dart';
import 'wallets_screen.dart';
import 'service_menu_screen.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/account_manager.dart';
import '../../utils/image_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../widgets/chat/liquid_glass_bottom_bar.dart';
import '../../widgets/chat/classic_bottom_bar.dart';
import '../../widgets/chat/liquid_glass_app_bar.dart';
import '../../widgets/settings/settings_group.dart';
import 'package:http/http.dart' as http;
import '../auth/login_screen.dart';
import '../main/main_screen.dart';
import '../../services/database/app_database.dart';
import '../../services/cache_service.dart';
import '../../services/websocket_service.dart';
import '../../services/notification_service.dart';
import '../../utils/swipe_back_route.dart';
import '../../services/update_service.dart';
import 'widgets/update_dialog.dart';

/// Экран настроек.
///
/// Когда [isEmbedded] = true, используется как страница внутри PageView
/// на главном экране — без собственного Scaffold и bottom bar.
/// Когда [isEmbedded] = false (по умолчанию), работает как самостоятельный экран.
class SettingsScreen extends StatefulWidget {
  final bool isEmbedded;

  const SettingsScreen({Key? key, this.isEmbedded = false}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with AutomaticKeepAliveClientMixin {
  final AccountManager _accountManager = AccountManager();
  Account? _currentAccount;

  int _versionTapCount = 0;
  DateTime? _lastTapTime;
  bool _isCheckingUpdate = false;

  Future<void> _checkAppUpdates(BuildContext context) async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);
    HapticUtils.tap();

    try {
      final update = await AppUpdateService.instance.checkForUpdate(silent: false);
      if (!mounted) return;

      if (update.hasUpdate) {
        UpdateDialog.show(context, update, isManual: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('У вас установлена последняя версия Theaver'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось проверить обновления: $e'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
      }
    }
  }

  String _getSystemAbi() {
    if (kIsWeb) return 'web';
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return defaultTargetPlatform.name;
    }
  }

  void _handleVersionTap() {
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) > const Duration(seconds: 2)) {
      _versionTapCount = 0;
    }
    _lastTapTime = now;
    _versionTapCount++;

    HapticUtils.tap();

    if (_versionTapCount >= 5) {
      _versionTapCount = 0;
      Navigator.push(
        context,
        SwipeBackPageRoute(
          builder: (_) => const ServiceMenuScreen(),
        ),
      );
    }
  }

  String _updateChannel = 'stable';

  Future<void> _loadUpdateChannel() async {
    final ch = await AppUpdateService.instance.getChannel();
    if (mounted) {
      setState(() => _updateChannel = ch);
    }
  }

  Future<void> _selectUpdateChannel(BuildContext context) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => SimpleDialog(
        title: const Text('Канал обновлений'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogCtx, 'stable'),
            child: Row(
              children: [
                Icon(
                  _updateChannel == 'stable' ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: Theme.of(dialogCtx).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stable (Стабильный)', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('Рекомендуется для всех пользователей', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogCtx, 'beta'),
            child: Row(
              children: [
                Icon(
                  _updateChannel == 'beta' ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: Theme.of(dialogCtx).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Beta (Бета-тестирование)', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('Новые функции до официального релиза', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogCtx, 'alpha'),
            child: Row(
              children: [
                Icon(
                  _updateChannel == 'alpha' ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: Theme.of(dialogCtx).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Alpha / Dev (Разработка)', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('Ранние сборки для тестирования', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (selected != null && selected != _updateChannel) {
      await AppUpdateService.instance.setChannel(selected);
      if (mounted) {
        setState(() => _updateChannel = selected);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Выбран канал обновлений: ${_getChannelTitle(selected)}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _getChannelTitle(String ch) {
    switch (ch) {
      case 'beta':
        return 'Beta';
      case 'alpha':
        return 'Alpha';
      default:
        return 'Stable';
    }
  }

  Widget _buildVersionInfoSection(ThemeData theme, AppLocalizations l10n) {
    final systemAbi = _getSystemAbi();
    final buildDate = AppConfig.buildDate;
    final appVersion = AppConfig.currentVersion;
    final appBuild = AppConfig.currentBuildNumber;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleVersionTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Theaver v$appVersion (#$appBuild) ($systemAbi)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.translate('build_date').replaceAll('{date}', buildDate),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                TextButton.icon(
                  onPressed: _isCheckingUpdate ? null : () => _checkAppUpdates(context),
                  icon: _isCheckingUpdate
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(
                    _isCheckingUpdate ? 'Проверка...' : 'Проверить обновления',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _selectUpdateChannel(context),
                  icon: Icon(
                    _updateChannel == 'beta'
                        ? Icons.science_outlined
                        : (_updateChannel == 'alpha'
                            ? Icons.developer_mode_outlined
                            : Icons.verified_outlined),
                    size: 16,
                  ),
                  label: Text(
                    'Канал: ${_getChannelTitle(_updateChannel)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    backgroundColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentAccount = _accountManager.currentAccount;
    _accountManager.addListener(_onAccountChanged);
    _loadUpdateChannel();
  }

  void _onAccountChanged() {
    if (mounted) {
      setState(() {
        _currentAccount = _accountManager.currentAccount;
      });
    }
  }

  @override
  void dispose() {
    _accountManager.removeListener(_onAccountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final currentAccount = _currentAccount;

    // Меню «три точки» — содержит «Выйти» и «Очистить данные»
    final appBarActions = [
      PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'logout':
              _handleLogout(context);
              break;
            case 'clear_data':
              _showClearDataDialog(context);
              break;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'logout',
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(
                l10n.translate('menu_logout'),
                style: const TextStyle(color: Colors.red),
              ),
              contentPadding: EdgeInsets.zero,
              minLeadingWidth: 24,
            ),
          ),
          PopupMenuItem(
            value: 'clear_data',
            child: ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.orange),
              title: Text(
                l10n.translate('clear_data_title'),
                style: const TextStyle(color: Colors.orange),
              ),
              contentPadding: EdgeInsets.zero,
              minLeadingWidth: 24,
            ),
          ),
        ],
        icon: const Icon(Icons.more_vert),
      ),
    ];

    // AppBar title — крупная надпись «Настройки»
    final appBarTitle = Text(
      l10n.translate('settings_title'),
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
      ),
    );

    // Содержимое списка настроек (без обёртки ListView)
    final listChildren = <Widget>[
      // Current Account Section
      if (currentAccount != null) ...[
        _buildCurrentAccountSection(theme, l10n, currentAccount),
        const SizedBox(height: 8),
      ],

      SettingsGroup(
        children: [
          // Profile Section
          ListTile(
            leading: const Icon(Icons.person, color: Color(0xFF0088CC)),
            title: Text(l10n.translate('settings_profile')),
            onTap: () {
              HapticUtils.tap();
              Navigator.push(
                context,
                SwipeBackPageRoute(
                  builder: (_) => const ProfileScreen(),
                ),
              ).then((_) {
                if (mounted) {
                  setState(() {
                    _currentAccount = _accountManager.currentAccount;
                  });
                }
              });
            },
          ),

          // Accounts Section
          ListTile(
            leading: const Icon(Icons.switch_account, color: Color(0xFF0088CC)),
            title: Text(l10n.translate('accounts_title')),
            subtitle: Text(
              '${_accountManager.accounts.length} ${l10n.translate('accounts_count')}',
            ),
            onTap: () {
              HapticUtils.tap();
              Navigator.push(
                context,
                SwipeBackPageRoute(
                  builder: (_) => const AccountsScreen(),
                ),
              ).then((_) {
                if (mounted) {
                  setState(() {
                    _currentAccount = _accountManager.currentAccount;
                  });
                }
              });
            },
          ),

          // Add Account Section
          ListTile(
            leading:
                const Icon(Icons.add_circle_outline, color: Color(0xFF0088CC)),
            title: Text(l10n.translate('settings_add_account')),
            onTap: () {
              HapticUtils.tap();
              Navigator.push(
                context,
                SwipeBackPageRoute(
                  builder: (_) => const LoginScreen(),
                ),
              );
            },
          ),
        ],
      ),

      SettingsGroup(
        children: [
          // Chat Settings Section (Wallpaper + Liquid Glass)
          ListTile(
            leading: const Icon(Icons.chat, color: Color(0xFF0088CC)),
            title: Text(l10n.translate('settings_chat_settings')),
            onTap: () {
              HapticUtils.tap();
              Navigator.push(
                context,
                SwipeBackPageRoute(builder: (_) => const ChatSettingsScreen()),
              );
            },
          ),

          // Privacy Section
          ListTile(
            leading: const Icon(Icons.privacy_tip, color: Color(0xFF0088CC)),
            title: Text(l10n.translate('settings_privacy')),
            onTap: () {
              HapticUtils.tap();
              Navigator.push(
                context,
                SwipeBackPageRoute(builder: (_) => const PrivacyScreen()),
              );
            },
          ),

          // Notifications Section
          ListTile(
            leading: const Icon(Icons.notifications, color: Color(0xFF0088CC)),
            title: Text(l10n.translate('settings_notifications')),
            onTap: () {
              HapticUtils.tap();
              Navigator.push(
                context,
                SwipeBackPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
        ],
      ),

      SettingsGroup(
        children: [
          // Data & Storage Section
          ListTile(
            leading: const Icon(Icons.storage, color: Color(0xFF0088CC)),
            title: Text(l10n.translate('settings_data_storage')),
            onTap: () {
              HapticUtils.tap();
              Navigator.push(
                context,
                SwipeBackPageRoute(builder: (_) => const StorageScreen()),
              );
            },
          ),

          // Devices Section
          ListTile(
            leading: const Icon(Icons.devices, color: Color(0xFF0088CC)),
            title: Text(l10n.translate('settings_devices')),
            onTap: () {
              HapticUtils.tap();
              Navigator.push(
                context,
                SwipeBackPageRoute(builder: (_) => const DevicesScreen()),
              );
            },
          ),

          // Chat Folders Section
          ListTile(
            leading: const Icon(Icons.folder, color: Color(0xFF0088CC)),
            title: Text(l10n.translate('settings_folders')),
            onTap: () {
              HapticUtils.tap();
              Navigator.push(
                context,
                SwipeBackPageRoute(builder: (_) => const FoldersScreen()),
              );
            },
          ),
        ],
      ),

      SettingsGroup(
        children: [
          // Wallets and Cards Section
          ListTile(
            leading: const Icon(Icons.account_balance_wallet,
                color: Color(0xFF0088CC)),
            title: Text(l10n.translate('settings_wallets_cards')),
            onTap: () {
              HapticUtils.tap();
              Navigator.push(
                context,
                SwipeBackPageRoute(builder: (_) => const WalletsScreen()),
              );
            },
          ),
        ],
      ),

      SettingsGroup(
        children: [
          // Power Saving Section
          ListTile(
            leading: const Icon(Icons.battery_saver, color: Color(0xFF0088CC)),
            title: Text(l10n.translate('settings_power_saving')),
            onTap: () {
              HapticUtils.tap();
              Navigator.push(
                context,
                SwipeBackPageRoute(builder: (_) => const PowerSavingScreen()),
              );
            },
          ),

          // Language Section
          ListTile(
            leading: const Icon(Icons.language, color: Color(0xFF0088CC)),
            title: Text(l10n.translate('settings_language')),
            onTap: () {
              HapticUtils.tap();
              Navigator.push(
                context,
                SwipeBackPageRoute(builder: (_) => const LanguageScreen()),
              );
            },
          ),
        ],
      ),

      const SizedBox(height: 24),
      _buildVersionInfoSection(theme, l10n),
      const SizedBox(height: 24),
    ];

    // ListView для classic-режима
    final listView = ListView(
      physics: const ClampingScrollPhysics(),
      padding: widget.isEmbedded
          ? const EdgeInsets.only(bottom: 120)
          : null,
      children: listChildren,
    );

    // Встроенный режим — используется внутри PageView на главном экране
    if (widget.isEmbedded) {
      final topPadding = MediaQuery.of(context).padding.top + 52.0;
      return ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          SizedBox(height: topPadding),
          ...listChildren,
        ],
      );
    }

    // Самостоятельный экран (не встроенный)
    return Consumer<LiquidGlassProvider>(
      builder: (context, glassProvider, _) {
        final glassEnabled = glassProvider.enabled;

        if (glassEnabled) {
          final topPadding =
              MediaQuery.of(context).padding.top + kToolbarHeight;

          return Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(top: topPadding),
                    child: listView,
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LiquidGlassAppBar(
                    title: appBarTitle,
                    actions: appBarActions,
                    centerTitle: true,
                    isLite: glassProvider.isLite,
                  ),
                ),
              ],
            ),
            bottomNavigationBar: LiquidGlassBottomBar(
              selectedIndex: 0,
              onTabSelected: (index) {
                if (index != 0) {
                  Navigator.pop(context);
                }
              },
              isLite: glassProvider.isLite,
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: appBarTitle,
            actions: appBarActions,
            centerTitle: true,
          ),
          body: listView,
          bottomNavigationBar: ClassicBottomBar(
            selectedIndex: 0,
            onTabSelected: (index) {
              if (index != 0) {
                Navigator.pop(context);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildCurrentAccountSection(ThemeData theme, AppLocalizations l10n, Account account) {
    return SettingsGroup(
      children: [
        InkWell(
          onTap: () {
            Navigator.push(
              context,
              SwipeBackPageRoute(
                builder: (_) => const AccountsScreen(),
              ),
            ).then((_) {
              if (mounted) {
                setState(() {
                  _currentAccount = _accountManager.currentAccount;
                });
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  key: ValueKey('settings_avatar_${account.userId}_${account.avatarUrl}_${account.localAvatarPath}'),
                  radius: 28,
                  backgroundImage: avatarImageProvider(account.avatarUrl, localFallbackPath: account.localAvatarPath),
                  backgroundColor: const Color(0xFF0088CC),
                  onBackgroundImageError: (e, s) {
                    debugPrint('[SettingsScreen] Failed to render avatar: $e');
                  },
                  child: (account.avatarUrl == null || account.avatarUrl!.isEmpty) &&
                          (account.localAvatarPath == null || !File(account.localAvatarPath!).existsSync())
                      ? Text(
                          (account.displayName ?? account.username ?? '?')[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 28,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.displayName ?? l10n.translate('accounts_unknown'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${account.username ?? account.userId}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final l10n = context.l10n;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('menu_logout')),
        content: Text(l10n.translate('accounts_logout_confirm')),
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
            child: Text(l10n.translate('menu_logout')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService.logout();
      
      if (!context.mounted) return;
      
      final nextAccount = _accountManager.currentAccount;
      if (nextAccount != null) {
        // Multi-account: switch to the next active account
        try {
          await WebSocketService().updateUserId(nextAccount.userId);
        } catch (_) {}
        Navigator.of(context).pushAndRemoveUntil(
          SwipeBackPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      } else {
        // No accounts left: go to login screen
        Navigator.of(context).pushAndRemoveUntil(
          SwipeBackPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  void _showClearDataDialog(BuildContext context) {
    final l10n = context.l10n;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('clear_data_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.translate('clear_data_message')),
            const SizedBox(height: 12),
            Text(
              l10n.translate('clear_data_warning'),
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.translate('common_cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _clearAllData(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.translate('clear_data_button')),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllData(BuildContext context) async {
    final l10n = context.l10n;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // 1. Disconnect WebSocket
      try {
        WebSocketService().disconnect();
      } catch (_) {}

      // 2. Unregister push tokens and notify server of logout
      try {
        await NotificationService().unregisterPushToken();
        final token = await AuthService.getToken();
        if (token != null) {
          await http.post(
            Uri.parse('${AppConfig.baseUrl}/api/auth/logout'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );
        }
      } catch (e) {
        debugPrint('_clearAllData: server logout error: $e');
      }

      // 3. Clear SQLite database (all chats, messages, sync states, cards)
      try {
        await AppDatabase().clearAllData();
      } catch (e) {
        debugPrint('_clearAllData: error clearing AppDatabase: $e');
      }

      // 4. Clear disk and image cache
      try {
        await CacheService().clearCache();
      } catch (e) {
        debugPrint('_clearAllData: error clearing CacheService: $e');
      }

      // 5. Clear all accounts
      await _accountManager.clearAll();

      // 6. Clear app settings
      final settingsService = SettingsService();
      await settingsService.clearAllSettings();

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (context.mounted) {
        Navigator.of(context).pop();
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.translate('clear_data_success'))),
      );

      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          SwipeBackPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(l10n.translate('clear_data_error').replaceAll('{error}', e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
