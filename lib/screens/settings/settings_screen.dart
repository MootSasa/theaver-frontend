import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'about_theaver_screen.dart';
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
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/account_manager.dart';
import '../../utils/image_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../services/auth_service.dart';
import '../../services/deep_link_service.dart';
import '../../services/settings_service.dart';
import '../../services/profile_instant_cache.dart';
import '../../services/liquid_glass_provider.dart';
import '../../widgets/chat/liquid_glass_bottom_bar.dart';
import '../../widgets/chat/classic_bottom_bar.dart';
import '../../widgets/chat/liquid_glass_app_bar.dart';
import '../../widgets/settings/settings_group.dart';
import 'package:http/http.dart' as http;
import '../auth/login_screen.dart';
import '../../services/database/app_database.dart';
import '../../services/cache_service.dart';
import '../../services/websocket_service.dart';
import '../../services/notification_service.dart';
import '../../utils/swipe_back_route.dart';
import '../../services/update_service.dart';
import '../../services/tiling_layout_controller.dart';

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

  void _openAboutTheaver() {
    HapticUtils.tap();
    Navigator.push(
      context,
      SwipeBackPageRoute(builder: (_) => const AboutTheaverScreen()),
    );
  }

  Widget _buildVersionInfoSection(ThemeData theme) {
    final appVersion = AppConfig.currentVersion;
    final appBuild = AppConfig.currentBuildNumber;

    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openAboutTheaver,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 20.0),
          child: Text(
            'Theaver v$appVersion ($appBuild)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
            ),
            textAlign: TextAlign.center,
          ),
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
    ProfileInstantCache.instance.warmupSelf();
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

          // About Theaver Section
          ListTile(
            leading: const Icon(Icons.info_outline_rounded, color: Color(0xFF0088CC)),
            title: Text(l10n.translate('settings_about_theaver')),
            trailing: ValueListenableBuilder<AppUpdateDownloadState>(
              valueListenable: AppUpdateService.instance.stateNotifier,
              builder: (context, state, _) {
                final update = state.availableUpdate;
                if (!state.hasAvailableUpdate || update == null) {
                  return const SizedBox.shrink();
                }
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'v${update.latestVersion}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
            onTap: _openAboutTheaver,
          ),
        ],
      ),

      const SizedBox(height: 24),
      _buildVersionInfoSection(theme),
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
                Builder(
                  builder: (context) {
                    final avatarProvider = avatarImageProvider(
                      account.avatarUrl,
                      localFallbackPath: account.localAvatarPath,
                    );
                    final rawName = (account.displayName?.trim().isNotEmpty == true)
                        ? account.displayName!.trim()
                        : (account.username?.trim().isNotEmpty == true
                            ? account.username!.trim()
                            : '?');
                    return CircleAvatar(
                      key: ValueKey('settings_avatar_${account.userId}_${account.avatarUrl}_${account.localAvatarPath}'),
                      radius: 28,
                      backgroundImage: avatarProvider,
                      backgroundColor: const Color(0xFF0088CC),
                      onBackgroundImageError: avatarProvider != null
                          ? (e, s) {
                              debugPrint('[SettingsScreen] Failed to render avatar: $e');
                            }
                          : null,
                      child: avatarProvider == null
                          ? Text(
                              rawName[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 28,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    );
                  },
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
      TilingLayoutController.instance.closeAllChats();
      // 1. Immediately kick user to LoginScreen using root navigator
      final nav = DeepLinkService().navigatorKey.currentState ??
          Navigator.of(context, rootNavigator: true);
      nav.pushAndRemoveUntil(
        SwipeBackPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );

      // 2. Perform logout and local data wipe in background
      await AuthService.logout();
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
        await AppDatabase.deleteAllDatabases();
      } catch (e) {
        debugPrint('_clearAllData: error clearing AppDatabase: $e');
      }

      // 4. Clear disk, image cache, and permanent user directories (avatars, wallpapers)
      try {
        await CacheService().clearCache();
        await CacheService().clearAllPermanentUserDirs();
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

      TilingLayoutController.instance.closeAllChats();
      final nav = DeepLinkService().navigatorKey.currentState ??
          (context.mounted ? Navigator.of(context, rootNavigator: true) : null);
      nav?.pushAndRemoveUntil(
        SwipeBackPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
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
