import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/glass_toast_service.dart';
import '../../../services/update_service.dart';
import '../../../theme/theav_theme.dart';
import '../../../utils/haptic_utils.dart';
import '../../../widgets/settings/settings_floating_header.dart';

/// Attached bottom sheet presenting available app updates, Markdown release
/// notes, download progress, and install/snooze actions.
class UpdateDialog extends StatefulWidget {
  final AppUpdateInfo update;
  final bool isManual;

  const UpdateDialog({
    super.key,
    required this.update,
    this.isManual = false,
  });

  /// Shows the update sheet attached flush to the bottom edge.
  static Future<void> show(
    BuildContext context,
    AppUpdateInfo update, {
    bool isManual = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: !update.forceUpdate,
      enableDrag: !update.forceUpdate,
      useSafeArea: false,
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
  String? _localError;
  String? _permissionHint;
  bool _isTriggering = false;

  Future<void> _handleDownloadAndInstall() async {
    if (_isTriggering) return;
    HapticUtils.tap();
    setState(() {
      _isTriggering = true;
      _localError = null;
      _permissionHint = null;
    });
    try {
      final res =
          await AppUpdateService.instance.downloadAndInstall(widget.update);
      if (!mounted) return;
      _handleInstallOutcome(res);
    } finally {
      if (mounted) {
        setState(() => _isTriggering = false);
      }
    }
  }

  Future<void> _handleInstallExisting(String path) async {
    if (_isTriggering) return;
    HapticUtils.tap();
    setState(() {
      _isTriggering = true;
      _localError = null;
      _permissionHint = null;
    });
    try {
      final res = await AppUpdateService.instance.installApk(path);
      if (!mounted) return;
      _handleInstallOutcome(res);
    } finally {
      if (mounted) {
        setState(() => _isTriggering = false);
      }
    }
  }

  void _handleInstallOutcome(UpdateInstallResult res) {
    final l10n = context.l10n;
    if (res.status == UpdateInstallStatus.permissionRequested) {
      setState(() {
        _permissionHint = _tr(
          l10n,
          'update_allow_unknown_sources_hint',
          'Разрешите установку из этого источника в настройках и вернитесь в приложение',
        );
      });
      return;
    }
    if (res.status == UpdateInstallStatus.failed) {
      setState(() {
        _localError = res.message.isNotEmpty
            ? res.message
            : 'Не удалось запустить установку обновления';
      });
      return;
    }
    if (res.status == UpdateInstallStatus.launched ||
        res.status == UpdateInstallStatus.openedExternally) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _snoozeUpdate() async {
    if (widget.update.forceUpdate) return;
    HapticUtils.tap();
    await AppUpdateService.instance.snoozeUpdate(widget.update.latestBuild);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _skipBuild() async {
    if (widget.update.forceUpdate) return;
    HapticUtils.tap();
    await AppUpdateService.instance.ignoreBuild(widget.update.latestBuild);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _copySha256() async {
    final hash = widget.update.sha256.trim();
    if (hash.isEmpty) return;
    HapticUtils.tap();
    await Clipboard.setData(ClipboardData(text: hash));
    if (!mounted) return;
    final l10n = context.l10n;
    GlassToastService().show(
      context,
      _tr(l10n, 'update_hash_copied', 'SHA-256 скопирован в буфер обмена'),
      duration: const Duration(seconds: 2),
    );
  }

  String _tr(AppLocalizations l10n, String key, String fallback) {
    final translated = l10n.translate(key);
    return (translated == key || translated.isEmpty) ? fallback : translated;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final theav = TheavTheme.of(context);
    final accent = theav.accent;
    final errorColor = theav.palette.error;
    final textPrimary = theav.textPrimary;
    final textSecondary = theav.textSecondary;
    final cardSurface = (isDark ? Colors.white : Colors.black)
        .withValues(alpha: isDark ? 0.06 : 0.04);
    final hairline = (isDark ? Colors.white : Colors.black)
        .withValues(alpha: isDark ? 0.10 : 0.08);

    final isForce = widget.update.forceUpdate;
    final hasSha = widget.update.sha256.trim().length >= 8;
    final shortSha = hasSha ? widget.update.sha256.trim().substring(0, 8) : '';
    final notes = widget.update.releaseNotes.trim().isNotEmpty
        ? widget.update.releaseNotes.trim()
        : _tr(
            l10n,
            'update_default_notes',
            'Улучшения стабильности, безопасности и производительности.',
          );

    return PopScope(
      canPop: !isForce,
      child: SettingsAttachedSheet(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header row: outline Iconoir icon (no box) + title + version line
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: isForce
                          ? iconoir.WarningTriangle(
                              width: 28,
                              height: 28,
                              color: errorColor,
                            )
                          : iconoir.CloudDownload(
                              width: 28,
                              height: 28,
                              color: accent,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
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
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Theaver ${widget.update.latestVersion}'
                          '${widget.update.latestBuild > 0 ? ' (#${widget.update.latestBuild})' : ''}',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: isForce ? errorColor : accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isForce)
                    GestureDetector(
                      onTap: () {
                        HapticUtils.tap();
                        Navigator.of(context).maybePop();
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cardSurface,
                          border: Border.all(color: hairline, width: 0.6),
                        ),
                        child: Center(
                          child: iconoir.Xmark(
                            width: 18,
                            height: 18,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Metadata pills
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaPill(
                    background: cardSurface,
                    borderColor: hairline,
                    icon: iconoir.Package(
                      width: 14,
                      height: 14,
                      color: accent,
                    ),
                    label: widget.update.channel.toUpperCase(),
                    textColor: textPrimary,
                  ),
                  if (!kIsWeb && widget.update.architecture.isNotEmpty)
                    _MetaPill(
                      background: cardSurface,
                      borderColor: hairline,
                      icon: iconoir.ControlSlider(
                        width: 14,
                        height: 14,
                        color: textSecondary,
                      ),
                      label: widget.update.architecture,
                      textColor: textSecondary,
                    ),
                  if (!kIsWeb && widget.update.formattedSize.isNotEmpty)
                    _MetaPill(
                      background: cardSurface,
                      borderColor: hairline,
                      icon: iconoir.HardDrive(
                        width: 14,
                        height: 14,
                        color: textSecondary,
                      ),
                      label: widget.update.formattedSize,
                      textColor: textSecondary,
                    ),
                  if (!kIsWeb && hasSha)
                    GestureDetector(
                      onTap: _copySha256,
                      child: _MetaPill(
                        background: cardSurface,
                        borderColor: hairline,
                        icon: iconoir.ShieldCheck(
                          width: 14,
                          height: 14,
                          color: accent,
                        ),
                        trailingIcon: iconoir.Copy(
                          width: 13,
                          height: 13,
                          color: textSecondary,
                        ),
                        label: 'SHA $shortSha',
                        textColor: textPrimary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // What's new section
              Text(
                _tr(l10n, 'update_whats_new', 'Что нового'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: hairline, width: 0.7),
                ),
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: notes,
                    selectable: true,
                    onTapLink: (text, href, title) {
                      if (href != null && href.isNotEmpty) {
                        unawaited(
                          launchUrl(
                            Uri.parse(href),
                            mode: LaunchMode.externalApplication,
                          ),
                        );
                      }
                    },
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: textPrimary.withValues(alpha: 0.9),
                      ),
                      listBullet: TextStyle(
                        fontSize: 14,
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                      a: TextStyle(
                        color: accent,
                        decoration: TextDecoration.underline,
                      ),
                      code: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        color: accent,
                        backgroundColor: accent.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                ),
              ),

              if (_permissionHint != null) ...[
                const SizedBox(height: 12),
                _InlineNoticeBanner(
                  color: accent,
                  icon: iconoir.ShieldCheck(
                    width: 18,
                    height: 18,
                    color: accent,
                  ),
                  text: _permissionHint!,
                ),
              ],

              const SizedBox(height: 16),

              // Reactive download & action controls
              ValueListenableBuilder<AppUpdateDownloadState>(
                valueListenable: AppUpdateService.instance.stateNotifier,
                builder: (context, state, _) {
                  final sameBuild = state.availableUpdate?.latestBuild ==
                      widget.update.latestBuild;
                  final isDownloading = sameBuild &&
                      state.status == AppUpdateStatus.downloading;
                  final isReadyToInstall = !kIsWeb &&
                      sameBuild &&
                      state.status == AppUpdateStatus.readyToInstall &&
                      (state.downloadedFilePath?.isNotEmpty ?? false);
                  final isInstalling = sameBuild &&
                      state.status == AppUpdateStatus.installing;
                  final effectiveError = _localError ??
                      (state.status == AppUpdateStatus.error
                          ? state.errorMessage
                          : null);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (effectiveError != null && effectiveError.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _InlineNoticeBanner(
                            color: errorColor,
                            icon: iconoir.WarningTriangle(
                              width: 18,
                              height: 18,
                              color: errorColor,
                            ),
                            text: effectiveError,
                          ),
                        ),
                      if (isDownloading) ...[
                        _DownloadProgressPanel(
                          progress: state.progress,
                          label: _buildProgressLabel(state),
                          accent: accent,
                          trackColor: cardSurface,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          onCancel: () {
                            HapticUtils.tap();
                            AppUpdateService.instance.cancelDownload();
                          },
                        ),
                      ] else ...[
                        _PrimarySheetButton(
                          label: kIsWeb
                              ? _tr(
                                  l10n,
                                  'update_reload_web',
                                  'Обновить сейчас',
                                )
                              : isReadyToInstall
                                  ? _tr(
                                      l10n,
                                      'update_install_now',
                                      'Установить',
                                    )
                                  : _tr(
                                      l10n,
                                      'update_download_and_install',
                                      'Скачать и установить',
                                    ),
                          accent: isForce ? errorColor : accent,
                          isBusy: isInstalling || _isTriggering,
                          icon: kIsWeb
                              ? const iconoir.RefreshDouble(
                                  width: 20,
                                  height: 20,
                                  color: Colors.white,
                                )
                              : isReadyToInstall
                                  ? const iconoir.Package(
                                      width: 20,
                                      height: 20,
                                      color: Colors.white,
                                    )
                                  : const iconoir.Download(
                                      width: 20,
                                      height: 20,
                                      color: Colors.white,
                                    ),
                          onTap: isInstalling || _isTriggering
                              ? null
                              : () {
                                  if (kIsWeb) {
                                    HapticUtils.tap();
                                    AppUpdateService.instance.applyWebUpdate();
                                  } else if (isReadyToInstall) {
                                    _handleInstallExisting(
                                      state.downloadedFilePath!,
                                    );
                                  } else {
                                    _handleDownloadAndInstall();
                                  }
                                },
                        ),
                        if (!isForce && !isInstalling) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _SecondarySheetButton(
                                  label: _tr(
                                    l10n,
                                    'update_remind_later',
                                    'Напомнить позже',
                                  ),
                                  textColor: textPrimary,
                                  surface: cardSurface,
                                  borderColor: hairline,
                                  onTap: _snoozeUpdate,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _SecondarySheetButton(
                                  label: _tr(
                                    l10n,
                                    'update_skip_build',
                                    'Пропустить сборку',
                                  ),
                                  textColor: textSecondary,
                                  surface: cardSurface,
                                  borderColor: hairline,
                                  onTap: _skipBuild,
                                ),
                              ),
                            ],
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
    );
  }

  String _buildProgressLabel(AppUpdateDownloadState state) {
    final downloadedMb =
        (state.downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
    final totalMb = state.totalBytes > 0
        ? (state.totalBytes / (1024 * 1024)).toStringAsFixed(1)
        : widget.update.formattedSize.replaceAll(' MB', '');
    final speedKbps = state.speedBytesPerSec / 1024;
    final speedLabel = speedKbps >= 1024
        ? '${(speedKbps / 1024).toStringAsFixed(1)} MB/s'
        : '${speedKbps.toStringAsFixed(0)} KB/s';
    if (totalMb.isNotEmpty) {
      return '$downloadedMb / $totalMb MB • $speedLabel';
    }
    return '$downloadedMb MB • $speedLabel';
  }
}

class _MetaPill extends StatelessWidget {
  final Color background;
  final Color borderColor;
  final Widget icon;
  final Widget? trailingIcon;
  final String label;
  final Color textColor;

  const _MetaPill({
    required this.background,
    required this.borderColor,
    required this.icon,
    this.trailingIcon,
    required this.label,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 6),
            trailingIcon!,
          ],
        ],
      ),
    );
  }
}

class _InlineNoticeBanner extends StatelessWidget {
  final Color color;
  final Widget icon;
  final String text;

  const _InlineNoticeBanner({
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 0.7),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadProgressPanel extends StatelessWidget {
  final double progress;
  final String label;
  final Color accent;
  final Color trackColor;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onCancel;

  const _DownloadProgressPanel({
    required this.progress,
    required this.label,
    required this.accent,
    required this.trackColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final percent = (clamped * 100).round();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onCancel,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: iconoir.Xmark(
                    width: 18,
                    height: 18,
                    color: textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        color: textPrimary.withValues(alpha: 0.10),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: constraints.maxWidth * clamped,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimarySheetButton extends StatelessWidget {
  final String label;
  final Color accent;
  final bool isBusy;
  final Widget icon;
  final VoidCallback? onTap;

  const _PrimarySheetButton({
    required this.label,
    required this.accent,
    required this.isBusy,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              else
                icon,
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondarySheetButton extends StatelessWidget {
  final String label;
  final Color textColor;
  final Color surface;
  final Color borderColor;
  final VoidCallback onTap;

  const _SecondarySheetButton({
    required this.label,
    required this.textColor,
    required this.surface,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 0.7),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
