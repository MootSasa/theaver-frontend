import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_config.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/update_service.dart';
import '../../../theme/theav_theme.dart';
import '../../../utils/haptic_utils.dart';

class UpdateDialog extends StatefulWidget {
  final AppUpdateInfo update;
  final bool isManual;

  const UpdateDialog({
    super.key,
    required this.update,
    this.isManual = false,
  });

  static Future<void> show(
    BuildContext context,
    AppUpdateInfo update, {
    bool isManual = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: !update.forceUpdate,
      enableDrag: !update.forceUpdate,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UpdateDialog(
        update: update,
        isManual: isManual,
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _permissionHintVisible = false;

  Future<void> _handleDownloadAndInstall() async {
    HapticUtils.tap();
    if (_permissionHintVisible) {
      setState(() => _permissionHintVisible = false);
    }
    final res = await AppUpdateService.instance.downloadAndInstall(widget.update);
    if (!mounted) return;
    if (res.status == UpdateInstallStatus.permissionRequested) {
      setState(() => _permissionHintVisible = true);
    }
  }

  Future<void> _handleInstall(String path) async {
    HapticUtils.tap();
    if (_permissionHintVisible) {
      setState(() => _permissionHintVisible = false);
    }
    final res = await AppUpdateService.instance.installApk(path);
    if (!mounted) return;
    if (res.status == UpdateInstallStatus.permissionRequested) {
      setState(() => _permissionHintVisible = true);
    }
  }

  Future<void> _snoozeUpdate() async {
    HapticUtils.tap();
    if (widget.update.forceUpdate) return;
    await AppUpdateService.instance.snoozeUpdate(widget.update.latestBuild);
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _skipBuild() async {
    HapticUtils.tap();
    if (widget.update.forceUpdate) return;
    await AppUpdateService.instance.ignoreBuild(widget.update.latestBuild);
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _copySha256(AppLocalizations l10n) async {
    final hash = widget.update.sha256.trim();
    if (hash.isEmpty) return;
    HapticUtils.tap();
    await Clipboard.setData(ClipboardData(text: hash));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.translate('update_hash_copied')),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0.0 MB';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String _tr(AppLocalizations l10n, String key, String fallback) {
    final translated = l10n.translate(key);
    return translated == key ? fallback : translated;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final theav = TheavTheme.of(context);
    final l10n = context.l10n;
    final mediaQuery = MediaQuery.of(context);
    final isWide = mediaQuery.size.width > 560;
    final isForce = widget.update.forceUpdate;
    final hasSha = widget.update.sha256.trim().length >= 8;
    final shaPrefix =
        hasSha ? widget.update.sha256.trim().substring(0, 8) : '';
    final releaseNotes = widget.update.releaseNotes.trim();
    final effectiveNotes = releaseNotes.isNotEmpty
        ? releaseNotes
        : _tr(
            l10n,
            'update_default_notes',
            'Улучшения стабильности и производительности.',
          );

    return PopScope(
      canPop: !isForce,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: mediaQuery.viewInsets.bottom + (isWide ? 24 : 0),
          left: isWide ? 16 : 0,
          right: isWide ? 16 : 0,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Material(
              color: theav.secondaryBg,
              elevation: 16,
              borderRadius: isWide
                  ? BorderRadius.circular(24)
                  : const BorderRadius.vertical(top: Radius.circular(24)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!isForce)
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
                        )
                      else
                        const SizedBox(height: 6),

                      // Header
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: (isForce
                                      ? theav.colorScheme.error
                                      : theav.accent)
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              isForce
                                  ? Icons.warning_amber_rounded
                                  : Icons.system_update_alt_rounded,
                              size: 28,
                              color: isForce
                                  ? theav.colorScheme.error
                                  : theav.accent,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isForce
                                      ? _tr(
                                          l10n,
                                          'update_force_title',
                                          'Обязательное обновление',
                                        )
                                      : _tr(
                                          l10n,
                                          'update_available_title',
                                          'Доступно обновление',
                                        ),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theav.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theav.inputBg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: theav.dividerColor
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    'v${AppConfig.currentVersion} → v${widget.update.latestVersion} (#${widget.update.latestBuild})',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: theav.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Metadata chips (channel, size, SHA-256)
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _MetaChip(
                            label: widget.update.channel.toUpperCase(),
                            backgroundColor:
                                theav.accent.withValues(alpha: 0.12),
                            textColor: theav.accent,
                          ),
                          if (widget.update.formattedSize.isNotEmpty)
                            _MetaChip(
                              icon: Icons.sd_storage_outlined,
                              label: widget.update.formattedSize,
                              backgroundColor: theav.inputBg,
                              textColor: theav.textSecondary,
                            ),
                          if (hasSha)
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _copySha256(l10n),
                              child: _MetaChip(
                                icon: Icons.verified_outlined,
                                label: 'SHA-256: $shaPrefix…',
                                backgroundColor: const Color(0xFF34C759)
                                    .withValues(alpha: 0.14),
                                textColor: const Color(0xFF28A745),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Changelog Header
                      Text(
                        _tr(l10n, 'update_whats_new', 'Что нового'),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theav.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Markdown Changelog Box
                      Container(
                        constraints: const BoxConstraints(maxHeight: 220),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theav.inputBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: theav.dividerColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: MarkdownBody(
                            data: effectiveNotes,
                            selectable: true,
                            onTapLink: (_, href, __) {
                              if (href == null || href.isEmpty) return;
                              final uri = Uri.tryParse(href);
                              if (uri != null) {
                                launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                            styleSheet:
                                MarkdownStyleSheet.fromTheme(theme).copyWith(
                              p: theme.textTheme.bodySmall?.copyWith(
                                color: theav.textPrimary,
                                height: 1.45,
                              ),
                              h1: theme.textTheme.titleSmall?.copyWith(
                                color: theav.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                              h2: theme.textTheme.titleSmall?.copyWith(
                                color: theav.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                              h3: theme.textTheme.bodyMedium?.copyWith(
                                color: theav.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                              listBullet: theme.textTheme.bodySmall?.copyWith(
                                color: theav.accent,
                              ),
                              a: theme.textTheme.bodySmall?.copyWith(
                                color: theav.accent,
                                decoration: TextDecoration.underline,
                              ),
                              code: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theav.textPrimary,
                                backgroundColor:
                                    theav.secondaryBg.withValues(alpha: 0.7),
                              ),
                              blockquoteDecoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: theav.accent,
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Reactive Download & Action Area
                      ValueListenableBuilder<AppUpdateDownloadState>(
                        valueListenable: AppUpdateService.instance.stateNotifier,
                        builder: (context, state, _) {
                          final isSameBuild =
                              state.availableUpdate?.latestBuild ==
                                  widget.update.latestBuild;
                          final isDownloading = isSameBuild &&
                              state.status == AppUpdateStatus.downloading;
                          final isReadyToInstall = !kIsWeb &&
                              isSameBuild &&
                              state.status == AppUpdateStatus.readyToInstall &&
                              state.downloadedFilePath != null;
                          final isInstalling = isSameBuild &&
                              state.status == AppUpdateStatus.installing;
                          final errorMsg =
                              isSameBuild ? state.errorMessage : null;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_permissionHintVisible) ...[
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: theav.accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          theav.accent.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.admin_panel_settings_outlined,
                                        color: theav.accent,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _tr(
                                            l10n,
                                            'update_allow_unknown_sources_hint',
                                            'Разрешите установку из этого источника в настройках и вернитесь в приложение',
                                          ),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: theav.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (errorMsg != null &&
                                  errorMsg.isNotEmpty) ...[
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: theav.colorScheme.error
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    errorMsg,
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: theav.colorScheme.error,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],

                              if (isDownloading) ...[
                                LinearProgressIndicator(
                                  value: state.progress > 0
                                      ? state.progress
                                      : null,
                                  borderRadius: BorderRadius.circular(8),
                                  minHeight: 8,
                                  color: theav.accent,
                                  backgroundColor: theav.inputBg,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _buildProgressLabel(state),
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: theav.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      _formatSpeed(state.speedBytesPerSec),
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: theav.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    HapticUtils.tap();
                                    AppUpdateService.instance.cancelDownload();
                                  },
                                  icon: const Icon(Icons.close_rounded,
                                      size: 18),
                                  label: Text(
                                    _tr(l10n, 'common_cancel', 'Отмена'),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ] else ...[
                                FilledButton.icon(
                                  onPressed: isInstalling
                                      ? null
                                      : () {
                                          if (kIsWeb) {
                                            HapticUtils.tap();
                                            AppUpdateService.instance
                                                .applyWebUpdate();
                                          } else if (isReadyToInstall) {
                                            _handleInstall(
                                              state.downloadedFilePath!,
                                            );
                                          } else {
                                            _handleDownloadAndInstall();
                                          }
                                        },
                                  icon: isInstalling
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Icon(
                                          kIsWeb
                                              ? Icons.refresh_rounded
                                              : (isReadyToInstall
                                                  ? Icons.install_mobile_rounded
                                                  : Icons.download_rounded),
                                          size: 20,
                                        ),
                                  label: Text(
                                    kIsWeb
                                        ? _tr(
                                            l10n,
                                            'update_reload_web',
                                            'Обновить сейчас',
                                          )
                                        : (isReadyToInstall
                                            ? _tr(
                                                l10n,
                                                'update_install_now',
                                                'Установить',
                                              )
                                            : _tr(
                                                l10n,
                                                'update_download_and_install',
                                                'Скачать и установить',
                                              )),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: isForce
                                        ? theav.colorScheme.error
                                        : theav.accent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                                if (!isForce) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: _snoozeUpdate,
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                          child: Text(
                                            _tr(
                                              l10n,
                                              'update_remind_later',
                                              'Напомнить позже',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Center(
                                    child: TextButton(
                                      onPressed: _skipBuild,
                                      child: Text(
                                        _tr(
                                          l10n,
                                          'update_skip_build',
                                          'Пропустить сборку',
                                        ),
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theav.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _buildProgressLabel(AppUpdateDownloadState state) {
    final pct = state.progress > 0 ? '${(state.progress * 100).round()}% · ' : '';
    final rec = _formatBytes(state.downloadedBytes);
    final total = state.totalBytes > 0
        ? state.totalBytes
        : widget.update.apkSizeBytes;
    if (total > 0) {
      return '$pct$rec / ${_formatBytes(total)}';
    }
    return '$pct$rec';
  }
}

class _MetaChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const _MetaChip({
    this.icon,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
