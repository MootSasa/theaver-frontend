import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/deep_link_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/update_service.dart';
import '../../theme/theav_theme.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/chat/liquid_glass_app_bar.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../widgets/settings/settings_group.dart';
import 'service_menu_screen.dart';
import 'widgets/update_dialog.dart';

class AboutTheaverScreen extends StatefulWidget {
  const AboutTheaverScreen({super.key});

  static const String debugMenuUnlockedKey = 'debug_menu_unlocked';

  @override
  State<AboutTheaverScreen> createState() => _AboutTheaverScreenState();
}

class _AboutTheaverScreenState extends State<AboutTheaverScreen> {
  bool _debugUnlocked = false;
  bool _autoCheck = true;
  String _updateChannel = 'stable';
  bool _isChecking = false;

  int _versionTapCount = 0;
  DateTime? _lastTapTime;

  @override
  void initState() {
    super.initState();
    unawaited(AppUpdateService.instance.init());
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final unlocked =
          prefs.getBool(AboutTheaverScreen.debugMenuUnlockedKey) ?? false;
      final autoCheck = await AppUpdateService.instance.isAutoCheckEnabled();
      final channel = await AppUpdateService.instance.getChannel();
      if (kIsWeb) {
        await AppConfig.syncWebVersionFromServer(channel: channel);
      }
      if (!mounted) return;
      setState(() {
        _debugUnlocked = unlocked;
        _autoCheck = autoCheck;
        _updateChannel = channel;
      });
    } catch (e) {
      debugPrint('[AboutTheaverScreen] Failed to load prefs: $e');
    }
  }

  Future<void> _onVersionHeaderTap() async {
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) > const Duration(seconds: 2)) {
      _versionTapCount = 0;
    }
    _lastTapTime = now;
    _versionTapCount++;
    HapticUtils.tap();

    if (_versionTapCount < 5) return;
    _versionTapCount = 0;

    final l10n = context.l10n;
    if (!_debugUnlocked) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AboutTheaverScreen.debugMenuUnlockedKey, true);
      if (!mounted) return;
      setState(() => _debugUnlocked = true);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.translate('about_debug_unlocked')),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _hideDebugMenu() async {
    HapticUtils.tap();
    final l10n = context.l10n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AboutTheaverScreen.debugMenuUnlockedKey, false);
    if (!mounted) return;
    setState(() => _debugUnlocked = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.translate('about_debug_hidden')),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleManualUpdateCheck() async {
    if (_isChecking) return;
    HapticUtils.tap();
    final l10n = context.l10n;
    setState(() => _isChecking = true);

    try {
      if (kIsWeb) {
        await AppConfig.syncWebVersionFromServer(channel: _updateChannel);
      }
      final info =
          await AppUpdateService.instance.checkForUpdate(silent: false);
      if (!mounted) return;

      if (info.hasUpdate) {
        await UpdateDialog.show(context, info, isManual: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('update_up_to_date')),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.translate('update_check_error', {'error': e.toString()}),
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _openLink(String rawUrl) async {
    HapticUtils.tap();
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;

    if (DeepLinkService.parseUri(uri) != null) {
      await DeepLinkService().handleLink(uri);
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openSourceCode() async {
    final commit = AppConfig.gitCommit.trim();
    final url = commit.isNotEmpty
        ? '${AppConfig.sourceCodeUrl}/commit/$commit'
        : AppConfig.sourceCodeUrl;
    await _openLink(url);
  }

  void _showPrivacyPolicySheet() {
    HapticUtils.tap();
    final theav = TheavTheme.of(context);
    final l10n = context.l10n;
    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Material(
            color: theav.secondaryBg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: theav.dividerColor.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: theav.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.verified_user_outlined,
                          color: theav.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.translate('about_privacy_policy'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theav.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.translate('about_privacy_summary'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theav.textSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetCtx).pop();
                      _openLink(AppConfig.privacyPolicyUrl);
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(l10n.translate('about_open_in_browser')),
                    style: FilledButton.styleFrom(
                      backgroundColor: theav.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showUpdateSettingsSheet() {
    HapticUtils.tap();
    final hasGlassProvider = _maybeGlassProvider(context) != null;

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final theav = TheavTheme.of(sheetCtx);
        final l10n = sheetCtx.l10n;
        final theme = Theme.of(sheetCtx);

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> selectChannel(String channel) async {
              if (channel == _updateChannel) return;
              HapticUtils.tap();
              await AppUpdateService.instance.setChannel(channel);
              if (kIsWeb && AppConfig.webDomainChannel != null) {
                final targetUrl = AppConfig.getWebChannelUrl(channel);
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                await launchUrl(
                  Uri.parse(targetUrl),
                  webOnlyWindowName: '_self',
                );
                return;
              }
              if (kIsWeb) {
                await AppConfig.syncWebVersionFromServer(channel: channel);
              }
              if (mounted) {
                setState(() => _updateChannel = channel);
              }
              setSheetState(() {});
            }

            final autoCheckTile = hasGlassProvider
                ? AdaptiveSwitchListTile(
                    title: Text(l10n.translate('about_auto_check_updates')),
                    subtitle: Text(
                      l10n.translate('about_auto_check_updates_desc'),
                    ),
                    value: _autoCheck,
                    onChanged: (value) async {
                      HapticUtils.tap();
                      await AppUpdateService.instance
                          .setAutoCheckEnabled(value);
                      if (mounted) {
                        setState(() => _autoCheck = value);
                      }
                      setSheetState(() {});
                    },
                  )
                : SwitchListTile(
                    title: Text(l10n.translate('about_auto_check_updates')),
                    subtitle: Text(
                      l10n.translate('about_auto_check_updates_desc'),
                    ),
                    value: _autoCheck,
                    onChanged: (value) async {
                      HapticUtils.tap();
                      await AppUpdateService.instance
                          .setAutoCheckEnabled(value);
                      if (mounted) {
                        setState(() => _autoCheck = value);
                      }
                      setSheetState(() {});
                    },
                  );

            return Align(
              alignment: Alignment.bottomCenter,
              heightFactor: 1.0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Material(
                  color: theav.secondaryBg,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: theav.dividerColor.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            l10n.translate('about_update_settings'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theav.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        autoCheckTile,
                        Divider(
                          color: theav.dividerColor.withValues(alpha: 0.25),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            l10n.translate('about_update_channel'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theav.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _ChannelOptionTile(
                          title: kIsWeb
                              ? 'Stable — theaver.app'
                              : 'Stable',
                          subtitle:
                              l10n.translate('about_channel_stable_desc'),
                          selected: _updateChannel == 'stable',
                          accent: theav.accent,
                          onTap: () => selectChannel('stable'),
                        ),
                        _ChannelOptionTile(
                          title: kIsWeb
                              ? 'Beta — beta.theaver.app'
                              : 'Beta',
                          subtitle: l10n.translate('about_channel_beta_desc'),
                          selected: _updateChannel == 'beta',
                          accent: theav.accent,
                          onTap: () => selectChannel('beta'),
                        ),
                        _ChannelOptionTile(
                          title: kIsWeb
                              ? 'Alpha — alpha.theaver.app'
                              : 'Alpha / Dev',
                          subtitle: l10n.translate('about_channel_alpha_desc'),
                          selected: _updateChannel == 'alpha',
                          accent: theav.accent,
                          onTap: () => selectChannel('alpha'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatLastChecked(AppLocalizations l10n, DateTime? dt) {
    if (dt == null) {
      return l10n.translate('about_last_checked_never');
    }
    final local = dt.toLocal();
    final monthName = l10n.translate('month_gen_${local.month}');
    final dateStr = '${local.day} $monthName';
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final timeStr = '$hh:$mm';
    return l10n.translate('about_last_checked', {
      'date': dateStr,
      'time': timeStr,
    });
  }

  LiquidGlassProvider? _maybeGlassProvider(BuildContext context) {
    try {
      return Provider.of<LiquidGlassProvider>(context);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final theav = TheavTheme.of(context);
    final glassProvider = _maybeGlassProvider(context);
    final glassEnabled = glassProvider?.enabled ?? false;

    final listView = ListView(
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.only(
        top: glassEnabled
            ? MediaQuery.of(context).padding.top + kToolbarHeight + 8
            : 8,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      children: [
        // 1. Информация
        SettingsGroup(
          title: l10n.translate('about_info_section'),
          children: [
            InkWell(
              onTap: _onVersionHeaderTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Theaver ${AppConfig.currentVersion} (${AppConfig.currentBuildNumber})',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theav.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.translate('about_app_description'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theav.textSecondary,
                        height: 1.38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ValueListenableBuilder<AppUpdateDownloadState>(
              valueListenable: AppUpdateService.instance.stateNotifier,
              builder: (context, state, _) {
                final checking =
                    _isChecking || state.status == AppUpdateStatus.checking;
                final update = state.availableUpdate;
                final hasUpdate = state.hasAvailableUpdate && update != null;

                return ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: checking
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.sync_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                  ),
                  title: Text(l10n.translate('about_updates_title')),
                  subtitle: Text(
                    hasUpdate
                        ? l10n.translate('about_update_available_sub', {
                            'version': update.latestVersion,
                            'build': update.latestBuild.toString(),
                          })
                        : _formatLastChecked(l10n, state.lastCheckedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hasUpdate ? theav.accent : theav.textSecondary,
                      fontWeight: hasUpdate ? FontWeight.w600 : null,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasUpdate)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: theav.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      IconButton(
                        icon: Icon(
                          Icons.tune_rounded,
                          color: theav.textSecondary,
                        ),
                        tooltip: l10n.translate('about_update_settings'),
                        onPressed: _showUpdateSettingsSheet,
                      ),
                    ],
                  ),
                  onTap: _handleManualUpdateCheck,
                  onLongPress: _showUpdateSettingsSheet,
                );
              },
            ),
            if (_debugUnlocked)
              ListTile(
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFAF52DE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.science_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                title: const Text('Debug // W.I.P'),
                subtitle: Text(l10n.translate('about_debug_subtitle')),
                onTap: () async {
                  HapticUtils.tap();
                  await Navigator.push(
                    context,
                    SwipeBackPageRoute(
                      builder: (_) => const ServiceMenuScreen(),
                    ),
                  );
                  await _loadPreferences();
                },
                onLongPress: _hideDebugMenu,
              ),
          ],
        ),

        const SizedBox(height: 8),

        // 2. Ссылки
        SettingsGroup(
          title: l10n.translate('about_links_section'),
          children: [
            ListTile(
              leading: Icon(Icons.campaign_outlined, color: theav.accent),
              title: Text(l10n.translate('about_news_channel')),
              onTap: () => _openLink(AppConfig.newsChannelUrl),
            ),
            ListTile(
              leading: Icon(Icons.campaign_outlined, color: theav.accent),
              title: Text(l10n.translate('about_beta_channel')),
              onTap: () => _openLink(AppConfig.betaChannelUrl),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // 3. Сообщество
        SettingsGroup(
          children: [
            ListTile(
              leading: Icon(Icons.forum_outlined, color: theav.accent),
              title: Text(l10n.translate('about_official_chat')),
              onTap: () => _openLink(AppConfig.officialChatUrl),
            ),
            ListTile(
              leading: Icon(
                Icons.chat_bubble_outline_rounded,
                color: theav.accent,
              ),
              title: Text(l10n.translate('about_discussion_chat')),
              onTap: () => _openLink(AppConfig.floodChatUrl),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // 4. Исходный код и политика
        SettingsGroup(
          children: [
            ListTile(
              leading: Icon(Icons.code_rounded, color: theav.accent),
              title: Text(l10n.translate('about_source_code')),
              trailing: Text(
                'commit ${AppConfig.shortGitCommit}',
                style: TextStyle(
                  color: theav.accent,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              onTap: _openSourceCode,
            ),
            ListTile(
              leading: Icon(
                Icons.verified_user_outlined,
                color: theav.accent,
              ),
              title: Text(l10n.translate('about_privacy_policy')),
              onTap: _showPrivacyPolicySheet,
            ),
          ],
        ),
      ],
    );

    final titleWidget = Text(
      l10n.translate('about_title'),
      style: const TextStyle(fontWeight: FontWeight.w700),
    );

    if (glassEnabled && glassProvider != null) {
      return Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: listView),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LiquidGlassAppBar(
                title: titleWidget,
                centerTitle: true,
                isLite: glassProvider.isLite,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: titleWidget,
        centerTitle: true,
      ),
      body: listView,
    );
  }
}

class _ChannelOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ChannelOptionTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? accent : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
