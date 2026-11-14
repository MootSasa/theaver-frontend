import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/deep_link_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/update_service.dart';
import '../../theme/theav_theme.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../widgets/settings/settings_floating_header.dart';
import 'service_menu_screen.dart';
import 'widgets/update_dialog.dart';

/// "About Theaver" settings screen modeled after clean grouped translucent cards
/// with Iconoir outline icons, floating pill header, update channel controls,
/// and 5-tap hidden debug menu activation.
class AboutTheaverScreen extends StatefulWidget {
  static const String debugMenuUnlockedKey = 'debug_menu_unlocked';

  const AboutTheaverScreen({super.key});

  @override
  State<AboutTheaverScreen> createState() => _AboutTheaverScreenState();
}

class _AboutTheaverScreenState extends State<AboutTheaverScreen> {
  bool _debugUnlocked = false;
  bool _autoCheckEnabled = true;
  String _selectedChannel = 'beta';
  bool _isChecking = false;

  int _tapCount = 0;
  DateTime? _lastTapTime;

  @override
  void initState() {
    super.initState();
    unawaited(AppUpdateService.instance.init());
    unawaited(_loadPrefs());
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final unlocked =
          prefs.getBool(AboutTheaverScreen.debugMenuUnlockedKey) ?? false;
      final autoCheck = await AppUpdateService.instance.isAutoCheckEnabled();
      final channel = await AppUpdateService.instance.getChannel();
      final effectiveChannel =
          kIsWeb ? (AppConfig.webDomainChannel ?? channel) : channel;
      if (!mounted) return;
      setState(() {
        _debugUnlocked = unlocked;
        _autoCheckEnabled = autoCheck;
        _selectedChannel = effectiveChannel;
      });
    } catch (e) {
      debugPrint('[AboutTheaverScreen] Failed to load prefs: $e');
    }
  }

  Future<void> _handleInfoTap() async {
    HapticUtils.tap();
    final now = DateTime.now();
    if (_lastTapTime == null ||
        now.difference(_lastTapTime!) > const Duration(seconds: 2)) {
      _tapCount = 0;
    }
    _lastTapTime = now;
    _tapCount++;

    if (_tapCount < 5) return;
    _tapCount = 0;

    if (!_debugUnlocked) {
      final l10n = context.l10n;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(AboutTheaverScreen.debugMenuUnlockedKey, true);
      } catch (e) {
        debugPrint('[AboutTheaverScreen] Failed to persist debug unlock: $e');
      }
      if (!mounted) return;
      setState(() => _debugUnlocked = true);
      GlassToastService().show(
        context,
        l10n.translate('about_debug_unlocked'),
      );
    } else {
      await _openServiceMenu();
    }
  }

  Future<void> _openServiceMenu() async {
    HapticUtils.tap();
    await Navigator.of(context).push(
      SwipeBackPageRoute(
        builder: (_) => const ServiceMenuScreen(),
      ),
    );
    await _loadPrefs();
  }

  Future<void> _checkForUpdates() async {
    if (_isChecking) return;
    HapticUtils.tap();
    final l10n = context.l10n;
    setState(() => _isChecking = true);
    try {
      final info = await AppUpdateService.instance.checkForUpdate(silent: false);
      if (!mounted) return;
      if (info.hasUpdate) {
        await UpdateDialog.show(context, info, isManual: true);
      } else {
        GlassToastService().show(
          context,
          l10n.translate('update_up_to_date'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      GlassToastService().show(
        context,
        l10n.translate('update_check_error', {'error': e.toString()}),
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
    await _openExternalUri(uri);
  }

  Future<void> _openExternalUri(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[AboutTheaverScreen] Failed to open $uri: $e');
    }
  }

  Future<void> _openSourceCommit() async {
    HapticUtils.tap();
    final commit = AppConfig.gitCommit.trim();
    final url = commit.isNotEmpty
        ? '${AppConfig.sourceCodeUrl}/commit/$commit'
        : AppConfig.sourceCodeUrl;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await _openExternalUri(uri);
    }
  }

  void _showPrivacySheet() {
    HapticUtils.tap();
    final l10n = context.l10n;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      builder: (sheetCtx) {
        final theav = TheavTheme.of(sheetCtx);
        final accent = theav.accent;
        final textPrimary = theav.textPrimary;
        final textSecondary = theav.textSecondary;
        final hairline = theav.dividerColor;

        return SettingsAttachedSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  iconoir.ShieldCheck(
                    width: 24,
                    height: 24,
                    color: accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.translate('about_privacy_policy'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  _SheetCloseButton(
                    iconColor: textSecondary,
                    borderColor: hairline,
                    onTap: () => Navigator.of(sheetCtx).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                l10n.translate('about_privacy_summary'),
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.48,
                  color: textPrimary.withValues(alpha: 0.88),
                ),
              ),
              const SizedBox(height: 20),
              Material(
                color: accent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    HapticUtils.tap();
                    Navigator.of(sheetCtx).maybePop();
                    final uri = Uri.tryParse(AppConfig.privacyPolicyUrl);
                    if (uri != null) {
                      await _openExternalUri(uri);
                    }
                  },
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const iconoir.OpenNewWindow(
                          width: 18,
                          height: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.translate('about_open_in_browser'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showUpdateSettingsSheet() {
    HapticUtils.tap();
    final hasGlassProvider = maybeLiquidGlassProvider(context, listen: false) != null;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      builder: (sheetCtx) {
        final l10n = sheetCtx.l10n;
        final theav = TheavTheme.of(sheetCtx);
        final isDark = Theme.of(sheetCtx).brightness == Brightness.dark;
        final accent = theav.accent;
        final textPrimary = theav.textPrimary;
        final textSecondary = theav.textSecondary;
        final hairline = theav.dividerColor;
        final cardBg = (isDark ? Colors.white : Colors.black)
            .withValues(alpha: isDark ? 0.06 : 0.04);

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> selectChannel(String channel) async {
              HapticUtils.tap();
              if (kIsWeb && AppConfig.webDomainChannel != null) {
                final targetUrl = AppConfig.getWebChannelUrl(channel);
                final uri = Uri.tryParse(targetUrl);
                if (uri != null) {
                  Navigator.of(sheetCtx).maybePop();
                  await _openExternalUri(uri);
                  return;
                }
              }
              await AppUpdateService.instance.setChannel(channel);
              if (mounted) {
                setState(() => _selectedChannel = channel);
              }
              setSheetState(() {});
            }

            Future<void> toggleAutoCheck(bool value) async {
              HapticUtils.tap();
              await AppUpdateService.instance.setAutoCheckEnabled(value);
              if (mounted) {
                setState(() => _autoCheckEnabled = value);
              }
              setSheetState(() {});
            }

            return SettingsAttachedSheet(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        iconoir.ControlSlider(
                          width: 22,
                          height: 22,
                          color: accent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.translate('about_update_settings'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        _SheetCloseButton(
                          iconColor: textSecondary,
                          borderColor: hairline,
                          onTap: () => Navigator.of(sheetCtx).maybePop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Auto-check toggle card (hidden switch only if fixed; matches previous behavior)
                    if (!kIsWeb) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: hairline, width: 0.7),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.translate('about_auto_check_updates'),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    l10n.translate(
                                      'about_auto_check_updates_desc',
                                    ),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.35,
                                      color: textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (hasGlassProvider)
                              AdaptiveSwitch(
                                value: _autoCheckEnabled,
                                onChanged: toggleAutoCheck,
                              )
                            else
                              Switch.adaptive(
                                value: _autoCheckEnabled,
                                onChanged: toggleAutoCheck,
                                activeTrackColor: accent,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        l10n.translate('about_update_channel'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: accent,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),

                    _ChannelOptionTile(
                      title: kIsWeb ? 'Stable (theaver.app)' : 'Stable',
                      subtitle: l10n.translate('about_channel_stable_desc'),
                      selected: _selectedChannel == 'stable',
                      accent: accent,
                      cardBg: cardBg,
                      hairline: hairline,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      onTap: () => selectChannel('stable'),
                    ),
                    const SizedBox(height: 8),
                    _ChannelOptionTile(
                      title: kIsWeb ? 'Beta (beta.theaver.app)' : 'Beta',
                      subtitle: l10n.translate('about_channel_beta_desc'),
                      selected: _selectedChannel == 'beta',
                      accent: accent,
                      cardBg: cardBg,
                      hairline: hairline,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      onTap: () => selectChannel('beta'),
                    ),
                    const SizedBox(height: 8),
                    _ChannelOptionTile(
                      title: kIsWeb ? 'Alpha (alpha.theaver.app)' : 'Alpha',
                      subtitle: l10n.translate('about_channel_alpha_desc'),
                      selected: _selectedChannel == 'alpha',
                      accent: accent,
                      cardBg: cardBg,
                      hairline: hairline,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      onTap: () => selectChannel('alpha'),
                    ),
                  ],
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theav = TheavTheme.of(context);
    final accent = theav.accent;
    final textPrimary = theav.textPrimary;
    final textSecondary = theav.textSecondary;
    final topClearance = SettingsFloatingHeader.topClearanceOf(context);
    final bottomPadding =
        math.max(32.0, MediaQuery.paddingOf(context).bottom + 24.0);

    final versionTitle =
        'Theaver ${AppConfig.currentVersion}${AppConfig.currentBuildNumber > 0 ? ' (${AppConfig.currentBuildNumber})' : ''}';

    return SettingsFloatingScaffold(
      title: l10n.translate('about_title'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          topClearance + 8,
          16,
          bottomPadding,
        ),
        children: [
          // 1. Information + Updates + Debug // W.I.P
          _AboutCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AboutSectionHeader(
                  title: l10n.translate('about_info_section'),
                  accent: accent,
                ),
                GestureDetector(
                  onTap: _handleInfoTap,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          versionTitle,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.translate('about_app_description'),
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.4,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _CardHairline(color: theav.dividerColor),
                ValueListenableBuilder<AppUpdateDownloadState>(
                  valueListenable: AppUpdateService.instance.stateNotifier,
                  builder: (context, state, _) {
                    final checking =
                        _isChecking || state.status == AppUpdateStatus.checking;
                    final update = state.availableUpdate;
                    final hasUpdate = state.hasAvailableUpdate && update != null;
                    final subtitleText = hasUpdate
                        ? l10n.translate('about_update_available_sub', {
                            'version': update.latestVersion,
                            'build': update.latestBuild.toString(),
                          })
                        : _formatLastChecked(l10n, state.lastCheckedAt);

                    return _AboutRow(
                      leading: checking
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(accent),
                              ),
                            )
                          : iconoir.RefreshDouble(
                              width: 22,
                              height: 22,
                              color: accent,
                            ),
                      title: l10n.translate('about_updates_title'),
                      subtitle: subtitleText,
                      subtitleColor: hasUpdate ? accent : textSecondary,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasUpdate)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          Tooltip(
                            message: l10n.translate('about_update_settings'),
                            child: GestureDetector(
                              onTap: _showUpdateSettingsSheet,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: iconoir.ControlSlider(
                                  width: 20,
                                  height: 20,
                                  color: accent,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      onTap: _checkForUpdates,
                    );
                  },
                ),
                if (_debugUnlocked) ...[
                  _CardHairline(color: theav.dividerColor),
                  _AboutRow(
                    leading: iconoir.Flask(
                      width: 22,
                      height: 22,
                      color: accent,
                    ),
                    title: 'Debug // W.I.P',
                    subtitle: l10n.translate('about_debug_subtitle'),
                    subtitleColor: textSecondary,
                    trailing: iconoir.NavArrowRight(
                      width: 18,
                      height: 18,
                      color: textSecondary,
                    ),
                    onTap: _openServiceMenu,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2. Channels ("Ссылки")
          _AboutCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AboutSectionHeader(
                  title: l10n.translate('about_links_section'),
                  accent: accent,
                ),
                _AboutRow(
                  leading: iconoir.Megaphone(
                    width: 22,
                    height: 22,
                    color: accent,
                  ),
                  title: l10n.translate('about_news_channel'),
                  onTap: () => _openLink(AppConfig.newsChannelUrl),
                ),
                _CardHairline(color: theav.dividerColor),
                _AboutRow(
                  leading: iconoir.Megaphone(
                    width: 22,
                    height: 22,
                    color: accent,
                  ),
                  title: l10n.translate('about_beta_channel'),
                  onTap: () => _openLink(AppConfig.betaChannelUrl),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 3. Community Chats
          _AboutCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AboutRow(
                  leading: iconoir.Community(
                    width: 22,
                    height: 22,
                    color: accent,
                  ),
                  title: l10n.translate('about_official_chat'),
                  onTap: () => _openLink(AppConfig.officialChatUrl),
                ),
                _CardHairline(color: theav.dividerColor),
                _AboutRow(
                  leading: iconoir.ChatBubble(
                    width: 22,
                    height: 22,
                    color: accent,
                  ),
                  title: l10n.translate('about_discussion_chat'),
                  onTap: () => _openLink(AppConfig.floodChatUrl),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 4. Source Code & Privacy Policy
          _AboutCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AboutRow(
                  leading: iconoir.Github(
                    width: 22,
                    height: 22,
                    color: accent,
                  ),
                  title: l10n.translate('about_source_code'),
                  trailing: Text(
                    'commit ${AppConfig.shortGitCommit}',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                  onTap: _openSourceCommit,
                ),
                _CardHairline(color: theav.dividerColor),
                _AboutRow(
                  leading: iconoir.ShieldCheck(
                    width: 22,
                    height: 22,
                    color: accent,
                  ),
                  title: l10n.translate('about_privacy_policy'),
                  trailing: iconoir.NavArrowRight(
                    width: 18,
                    height: 18,
                    color: textSecondary,
                  ),
                  onTap: _showPrivacySheet,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  final Widget child;

  const _AboutCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final theav = TheavTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.cardColor;
    final borderColor = theav.dividerColor.withValues(
      alpha: isDark ? 0.55 : 0.70,
    );

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 0.6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _AboutSectionHeader extends StatelessWidget {
  final String title;
  final Color accent;

  const _AboutSectionHeader({
    required this.title,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: accent,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? trailing;
  final VoidCallback onTap;

  const _AboutRow({
    required this.leading,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theav = TheavTheme.of(context);
    final textPrimary = theav.textPrimary;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: Center(child: leading),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                        color: textPrimary,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          color: subtitleColor ?? theav.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CardHairline extends StatelessWidget {
  final Color color;

  const _CardHairline({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 58),
      color: color.withValues(alpha: 0.55),
    );
  }
}

class _SheetCloseButton extends StatelessWidget {
  final Color iconColor;
  final Color borderColor;
  final VoidCallback onTap;

  const _SheetCloseButton({
    required this.iconColor,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticUtils.tap();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 0.7),
        ),
        child: Center(
          child: iconoir.Xmark(
            width: 17,
            height: 17,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}

class _ChannelOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final Color accent;
  final Color cardBg;
  final Color hairline;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;

  const _ChannelOptionTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.accent,
    required this.cardBg,
    required this.hairline,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent.withValues(alpha: 0.12) : cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent : hairline,
              width: selected ? 1.1 : 0.7,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: selected ? accent : textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (selected)
                iconoir.Check(
                  width: 20,
                  height: 20,
                  color: accent,
                )
              else
                const SizedBox(width: 20, height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
