import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../utils/blur_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/safari_url_safety.dart';
import '../design_system/theav_design_system.dart';

/// Tracks the number of currently presented [showSafariWebAlert] dialogs so
/// underlying WebView sheets can freeze page scrolling, focus, and input.
final ValueNotifier<int> activeSafariWebAlertCount = ValueNotifier<int>(0);

void _adjustSafariWebAlertCount(int delta) {
  final int next = (activeSafariWebAlertCount.value + delta).clamp(0, 999);
  if (activeSafariWebAlertCount.value == next) return;
  final phase = SchedulerBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.persistentCallbacks ||
      phase == SchedulerPhase.midFrameMicrotasks) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      activeSafariWebAlertCount.value = next;
    });
  } else {
    activeSafariWebAlertCount.value = next;
  }
}

/// Semantic tone driving badge icon and accent color inside Safari iOS 26
/// browser and Mini App alerts.
enum SafariAlertTone {
  neutral,
  info,
  securityWarning,
  permission,
  externalApp,
  auth,
}

/// Action capsule descriptor for [showSafariWebAlert] and [SafariWebAlertCard].
class SafariAlertAction<T> {
  final String label;
  final T? result;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isDestructive;
  final Key? buttonKey;

  const SafariAlertAction({
    required this.label,
    this.result,
    this.onPressed,
    this.isPrimary = false,
    this.isDestructive = false,
    this.buttonKey,
  });
}

class _SafariAlertDismissScope extends StatefulWidget {
  final bool barrierDismissible;
  final Widget child;

  const _SafariAlertDismissScope({
    required this.barrierDismissible,
    required this.child,
  });

  @override
  State<_SafariAlertDismissScope> createState() =>
      _SafariAlertDismissScopeState();
}

class _SafariAlertDismissScopeState extends State<_SafariAlertDismissScope> {
  bool _didRequestDismiss = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    super.dispose();
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (!mounted || !widget.barrierDismissible || _didRequestDismiss) {
      return false;
    }
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    final route = ModalRoute.of(context);
    if (route != null && (!route.isCurrent || !route.isActive)) {
      return false;
    }
    _didRequestDismiss = true;
    Navigator.of(context).maybePop();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Presents a centered Safari iOS 26 style alert (`LiquidGlassLens` when Glass
/// mode is active, or frosted single-pass Material 3 fallback).
///
/// Uses spring [ScaleTransition] without any enclosing `Opacity`/`FadeTransition`
/// so real-time backdrop refraction stays intact during transitions.
Future<T?> showSafariWebAlert<T>({
  required BuildContext context,
  String? title,
  String? message,
  Widget? customBody,
  SafariAlertTone tone = SafariAlertTone.neutral,
  IconData? iconOverride,
  String? originLabel,
  bool originIsSecure = true,
  required List<SafariAlertAction<T>> actions,
  bool barrierDismissible = true,
  Key? dialogKey,
}) async {
  final bool isGlass = TheavSurfaceStyle.of(context, listen: false).isGlass;
  _adjustSafariWebAlertCount(1);
  try {
    return await showGeneralDialog<T>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: barrierDismissible,
      barrierLabel: Localizations.of<MaterialLocalizations>(
            context,
            MaterialLocalizations,
          )?.modalBarrierDismissLabel ??
          'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.36),
      transitionDuration: const Duration(milliseconds: 230),
      pageBuilder: (ctx, _, __) {
        final Widget card = SafariWebAlertCard<T>(
          key: dialogKey,
          title: title,
          message: message,
          customBody: customBody,
          tone: tone,
          iconOverride: iconOverride,
          originLabel: originLabel,
          originIsSecure: originIsSecure,
          actions: actions,
        );
        final Widget centered = Center(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              24 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SingleChildScrollView(
              clipBehavior: Clip.none,
              child: card,
            ),
          ),
        );
        final Widget scoped = _SafariAlertDismissScope(
          barrierDismissible: barrierDismissible,
          child: centered,
        );
        return isGlass ? scoped : BackdropGroup(child: scoped);
      },
      transitionBuilder: (ctx, animation, _, child) {
        if (MediaQuery.maybeDisableAnimationsOf(ctx) ?? false) {
          return child;
        }
        final bool isReversing = animation.status == AnimationStatus.reverse;
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: isReversing ? Curves.easeInCubic : Curves.easeOutBack,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
          child: child,
        );
      },
    );
  } finally {
    _adjustSafariWebAlertCount(-1);
  }
}

/// Dual-mode Safari iOS 26 card container shared by modal alerts and the
/// anchored "Site Info" popover.
class _SafariGlassSurface extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const _SafariGlassSurface({
    super.key,
    required this.child,
    required this.maxWidth,
    required this.borderRadius,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final Widget body = Material(
      type: MaterialType.transparency,
      child: Padding(padding: padding, child: child),
    );

    if (style.isGlass && style.glassProvider != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: LiquidGlassLens(
          style: style.glassProvider!.createStyle(
            context: context,
            cornerRadius: borderRadius,
            refractionIndex: 1.1,
            refractionWidth: 20.0,
            borderWidth: 1.1,
            color: style.hudFill.withValues(alpha: style.isDark ? 0.82 : 0.88),
          ),
          child: body,
        ),
      );
    }

    final blurFilter = style.getMaterialHudBlurFilter(sigma: 14.0);
    final Color fill = BlurUtils.resolveMaterialHudColor(
      style.overlayFill,
      isDark: style.isDark,
      blurEnabled: blurFilter != null,
      darkAlpha: 0.86,
      lightAlpha: 0.90,
    );
    final Color borderColor = blurFilter != null
        ? (style.isDark
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.black.withValues(alpha: 0.08))
        : style.hairlineBorder;

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor,
          width: blurFilter != null ? 0.7 : 0.55,
        ),
      ),
      child: body,
    );

    if (blurFilter != null) {
      surface = BackdropFilter.grouped(
        filter: blurFilter,
        child: surface,
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: style.floatingShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: surface,
        ),
      ),
    );
  }
}

/// Centered Safari iOS 26 alert surface with optional origin pill, icon badge,
/// scrollable body text, and capsule pill actions.
class SafariWebAlertCard<T> extends StatelessWidget {
  final String? title;
  final String? message;
  final Widget? customBody;
  final SafariAlertTone tone;
  final IconData? iconOverride;
  final String? originLabel;
  final bool originIsSecure;
  final List<SafariAlertAction<T>> actions;

  const SafariWebAlertCard({
    super.key,
    this.title,
    this.message,
    this.customBody,
    this.tone = SafariAlertTone.neutral,
    this.iconOverride,
    this.originLabel,
    this.originIsSecure = true,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final IconData? resolvedIcon = iconOverride ?? _defaultIconForTone(tone);
    final Color badgeTint = _badgeColorForTone(tone, palette);
    final bool hasOrigin = originLabel != null && originLabel!.trim().isNotEmpty;
    final bool hasTitle = title != null && title!.trim().isNotEmpty;
    final bool hasMessage = message != null && message!.trim().isNotEmpty;

    final bool sideBySide = actions.length == 2 &&
        actions.every((a) => a.label.trim().length <= 15);

    return _SafariGlassSurface(
      maxWidth: 312.0,
      borderRadius: 28.0,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (resolvedIcon != null) ...[
            Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: badgeTint.withValues(alpha: style.isDark ? 0.22 : 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(resolvedIcon, size: 21, color: badgeTint),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (hasOrigin) ...[
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.onSurface
                      .withValues(alpha: style.isDark ? 0.10 : 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      originIsSecure
                          ? Icons.lock_rounded
                          : Icons.warning_amber_rounded,
                      size: 12,
                      color: originIsSecure ? palette.primary : palette.error,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        originLabel!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: palette.onSurface.withValues(alpha: 0.82),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (hasTitle)
            Text(
              title!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.24,
                letterSpacing: -0.25,
              ),
            ),
          if (hasMessage) ...[
            if (hasTitle) const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.subtext,
                    fontSize: 13.5,
                    height: 1.38,
                  ),
                ),
              ),
            ),
          ],
          if (customBody != null) ...[
            if (hasTitle || hasMessage) const SizedBox(height: 14),
            customBody!,
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            if (sideBySide)
              Row(
                children: [
                  Expanded(
                    child: _SafariCapsuleActionButton<T>(action: actions[0]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SafariCapsuleActionButton<T>(action: actions[1]),
                  ),
                ],
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _SafariCapsuleActionButton<T>(action: actions[i]),
                  ],
                ],
              ),
          ],
        ],
      ),
    );
  }

  static IconData? _defaultIconForTone(SafariAlertTone tone) {
    switch (tone) {
      case SafariAlertTone.neutral:
        return null;
      case SafariAlertTone.info:
        return Icons.info_outline_rounded;
      case SafariAlertTone.securityWarning:
        return Icons.gpp_maybe_rounded;
      case SafariAlertTone.permission:
        return Icons.videocam_rounded;
      case SafariAlertTone.externalApp:
        return Icons.open_in_new_rounded;
      case SafariAlertTone.auth:
        return Icons.key_rounded;
    }
  }

  static Color _badgeColorForTone(SafariAlertTone tone, TheavPalette palette) {
    switch (tone) {
      case SafariAlertTone.securityWarning:
        return palette.error;
      case SafariAlertTone.neutral:
      case SafariAlertTone.info:
      case SafariAlertTone.permission:
      case SafariAlertTone.externalApp:
      case SafariAlertTone.auth:
        return palette.primary;
    }
  }
}

class _SafariCapsuleActionButton<T> extends StatelessWidget {
  final SafariAlertAction<T> action;

  const _SafariCapsuleActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;

    final Color bgColor;
    final Color fgColor;
    if (action.isDestructive) {
      bgColor = palette.error.withValues(alpha: style.isDark ? 0.22 : 0.14);
      fgColor = palette.error;
    } else if (action.isPrimary) {
      bgColor = palette.primary;
      fgColor = palette.onPrimary;
    } else {
      bgColor = palette.onSurface.withValues(alpha: style.isDark ? 0.11 : 0.07);
      fgColor = palette.onSurface;
    }

    return SizedBox(
      height: 42,
      child: Material(
        key: action.buttonKey,
        color: bgColor,
        borderRadius: BorderRadius.circular(21),
        child: InkWell(
          borderRadius: BorderRadius.circular(21),
          onTap: () {
            HapticUtils.tap();
            if (action.onPressed != null) {
              action.onPressed!();
            } else {
              Navigator.of(context).pop(action.result);
            }
          },
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fgColor,
                  fontSize: 14.5,
                  fontWeight: (action.isPrimary || action.isDestructive)
                      ? FontWeight.w600
                      : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a Safari-style SSL certificate warning dialog when a site presents an
/// untrusted, expired, or mismatched TLS certificate.
Future<bool> showSafariSslWarningDialog(
  BuildContext context, {
  required String host,
}) async {
  final String displayHost =
      SafariUrlSafetyAnalyzer.decodePunycodeHost(host.trim());
  final res = await showSafariWebAlert<bool>(
    context: context,
    dialogKey: const ValueKey('safari_ssl_warning_dialog'),
    tone: SafariAlertTone.securityWarning,
    originLabel: displayHost.isNotEmpty ? displayHost : null,
    originIsSecure: false,
    title: 'Соединение не защищено',
    message:
        'Сертификат безопасности этого сайта не прошёл проверку. Злоумышленники могут перехватить или подменить передаваемые данные.',
    actions: const [
      SafariAlertAction<bool>(
        label: 'Вернуться назад',
        result: false,
        isPrimary: true,
        buttonKey: ValueKey('safari_ssl_go_back_btn'),
      ),
      SafariAlertAction<bool>(
        label: 'Посетить сайт (небезопасно)',
        result: true,
        isDestructive: true,
        buttonKey: ValueKey('safari_ssl_proceed_btn'),
      ),
    ],
  );
  return res ?? false;
}

/// Shows a Safari-style warning before opening a suspicious mixed-script or
/// homograph Punycode domain.
Future<bool> showSafariSuspiciousLinkDialog(
  BuildContext context, {
  required SafariHostSafetyInfo info,
}) async {
  final String hostDetails = info.asciiHost != info.unicodeHost
      ? '${info.displayHost} (${info.asciiHost})'
      : info.displayHost;
  final res = await showSafariWebAlert<bool>(
    context: context,
    dialogKey: const ValueKey('safari_suspicious_link_dialog'),
    tone: SafariAlertTone.securityWarning,
    originLabel: hostDetails,
    originIsSecure: info.securityLevel == SafariConnectionSecurityLevel.secureHttps,
    title: 'Подозрительный адрес сайта',
    message:
        'Домен содержит смешанные символы разных алфавитов и может имитировать известный сайт.\n\nРеальный адрес: ${info.asciiHost}',
    actions: const [
      SafariAlertAction<bool>(
        label: 'Отмена',
        result: false,
        isPrimary: true,
        buttonKey: ValueKey('safari_suspicious_cancel_btn'),
      ),
      SafariAlertAction<bool>(
        label: 'Всё равно открыть',
        result: true,
        isDestructive: true,
        buttonKey: ValueKey('safari_suspicious_proceed_btn'),
      ),
    ],
  );
  return res ?? false;
}

/// Shows a Safari-style confirmation before launching an external application
/// (such as `tel:`, `mailto:`, `tg:`, or `intent:` links).
Future<bool> showSafariExternalAppDialog(
  BuildContext context, {
  required Uri uri,
  String? sourceHost,
}) async {
  final schemeInfo = SafariUrlSafetyAnalyzer.classifyExternalUri(uri);
  final res = await showSafariWebAlert<bool>(
    context: context,
    dialogKey: const ValueKey('safari_external_app_dialog'),
    tone: SafariAlertTone.externalApp,
    originLabel: (sourceHost != null && sourceHost.trim().isNotEmpty)
        ? sourceHost.trim()
        : null,
    originIsSecure: true,
    title: schemeInfo.title,
    message: schemeInfo.message,
    actions: [
      const SafariAlertAction<bool>(
        label: 'Отмена',
        result: false,
        buttonKey: ValueKey('safari_external_cancel_btn'),
      ),
      SafariAlertAction<bool>(
        label: schemeInfo.confirmLabel,
        result: true,
        isPrimary: true,
        buttonKey: const ValueKey('safari_external_confirm_btn'),
      ),
    ],
  );
  return res ?? false;
}

/// Shows a Safari-style permission request when a website requests access to
/// the device camera or microphone.
Future<bool> showSafariPermissionDialog(
  BuildContext context, {
  required String host,
  required Set<WebViewPermissionResourceType> types,
}) async {
  final bool wantsCam = types.contains(WebViewPermissionResourceType.camera);
  final bool wantsMic =
      types.contains(WebViewPermissionResourceType.microphone);
  final IconData icon;
  final String resourcePhrase;
  if (wantsCam && wantsMic) {
    icon = Icons.videocam_rounded;
    resourcePhrase = 'камере и микрофону';
  } else if (wantsMic) {
    icon = Icons.mic_rounded;
    resourcePhrase = 'микрофону';
  } else if (wantsCam) {
    icon = Icons.camera_alt_rounded;
    resourcePhrase = 'камере';
  } else {
    icon = Icons.sensors_rounded;
    resourcePhrase = 'защищённым функциям устройства';
  }

  final cleanHost = host.trim().isNotEmpty
      ? SafariUrlSafetyAnalyzer.decodePunycodeHost(host.trim())
      : 'этот сайт';
  final res = await showSafariWebAlert<bool>(
    context: context,
    dialogKey: const ValueKey('safari_permission_dialog'),
    tone: SafariAlertTone.permission,
    iconOverride: icon,
    originLabel: cleanHost,
    originIsSecure: true,
    title: 'Доступ к $resourcePhrase',
    message: 'Разрешить сайту «$cleanHost» использовать доступ к $resourcePhrase?',
    actions: const [
      SafariAlertAction<bool>(
        label: 'Не разрешать',
        result: false,
        buttonKey: ValueKey('safari_permission_deny_btn'),
      ),
      SafariAlertAction<bool>(
        label: 'Разрешить',
        result: true,
        isPrimary: true,
        buttonKey: ValueKey('safari_permission_allow_btn'),
      ),
    ],
  );
  return res ?? false;
}

/// Shows an informational Safari alert when OS-level camera/microphone
/// permission is blocked and directs the user to system settings.
Future<void> showSafariSystemPermissionDeniedDialog(
  BuildContext context, {
  required String resourceLabel,
  VoidCallback? onOpenSettings,
}) async {
  await showSafariWebAlert<void>(
    context: context,
    dialogKey: const ValueKey('safari_os_permission_denied_dialog'),
    tone: SafariAlertTone.securityWarning,
    iconOverride: Icons.settings_rounded,
    title: 'Доступ запрещён системой',
    message:
        'Для использования $resourceLabel включите разрешение для приложения Theaver в системных настройках.',
    actions: [
      const SafariAlertAction<void>(
        label: 'Понятно',
        result: null,
      ),
      if (onOpenSettings != null)
        SafariAlertAction<void>(
          label: 'Настройки',
          isPrimary: true,
          onPressed: () {
            Navigator.of(context).pop();
            onOpenSettings();
          },
        ),
    ],
  );
}

class _MuteCheckboxBody extends StatefulWidget {
  final ValueChanged<bool> onChanged;
  final Widget? upperContent;

  const _MuteCheckboxBody({
    required this.onChanged,
    this.upperContent,
  });

  @override
  State<_MuteCheckboxBody> createState() => _MuteCheckboxBodyState();
}

class _MuteCheckboxBodyState extends State<_MuteCheckboxBody> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.upperContent != null) ...[
          widget.upperContent!,
          const SizedBox(height: 10),
        ],
        InkWell(
          key: const ValueKey('safari_js_mute_checkbox'),
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _checked = !_checked);
            widget.onChanged(_checked);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Icon(
                  _checked
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 20,
                  color: _checked ? palette.primary : palette.subtext,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Блокировать повторные окна от этого сайта',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: palette.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows a Safari-style JavaScript `window.alert()` dialog.
Future<({bool muteHost})> showSafariJsAlertDialog(
  BuildContext context, {
  required String originHost,
  required bool isSecure,
  required String message,
  bool offerMuteOption = false,
}) async {
  bool mute = false;
  await showSafariWebAlert<void>(
    context: context,
    dialogKey: const ValueKey('safari_js_alert_dialog'),
    tone: SafariAlertTone.info,
    iconOverride: Icons.chat_bubble_outline_rounded,
    originLabel: originHost.isNotEmpty ? originHost : 'Веб-страница',
    originIsSecure: isSecure,
    title: 'Сообщение со страницы',
    message: message,
    customBody: offerMuteOption
        ? _MuteCheckboxBody(onChanged: (v) => mute = v)
        : null,
    actions: const [
      SafariAlertAction<void>(
        label: 'ОК',
        result: null,
        isPrimary: true,
        buttonKey: ValueKey('safari_js_alert_ok_btn'),
      ),
    ],
  );
  return (muteHost: mute);
}

/// Shows a Safari-style JavaScript `window.confirm()` dialog.
Future<({bool confirmed, bool muteHost})> showSafariJsConfirmDialog(
  BuildContext context, {
  required String originHost,
  required bool isSecure,
  required String message,
  bool offerMuteOption = false,
}) async {
  bool mute = false;
  final res = await showSafariWebAlert<bool>(
    context: context,
    dialogKey: const ValueKey('safari_js_confirm_dialog'),
    tone: SafariAlertTone.info,
    iconOverride: Icons.help_outline_rounded,
    originLabel: originHost.isNotEmpty ? originHost : 'Веб-страница',
    originIsSecure: isSecure,
    title: 'Подтвердите действие',
    message: message,
    customBody: offerMuteOption
        ? _MuteCheckboxBody(onChanged: (v) => mute = v)
        : null,
    actions: const [
      SafariAlertAction<bool>(
        label: 'Отмена',
        result: false,
        buttonKey: ValueKey('safari_js_confirm_cancel_btn'),
      ),
      SafariAlertAction<bool>(
        label: 'ОК',
        result: true,
        isPrimary: true,
        buttonKey: ValueKey('safari_js_confirm_ok_btn'),
      ),
    ],
  );
  return (confirmed: res ?? false, muteHost: mute);
}

InputDecoration _buildSafariDialogInputDecoration(
  TheavSurfaceStyle style, {
  required String hintText,
  Widget? suffixIcon,
}) {
  final palette = style.palette;
  return InputDecoration(
    filled: true,
    fillColor: palette.onSurface.withValues(alpha: style.isDark ? 0.10 : 0.06),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    hintText: hintText,
    hintStyle: TextStyle(color: palette.subtext, fontSize: 14),
    suffixIcon: suffixIcon,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
  );
}

class _SafariJsPromptBody extends StatefulWidget {
  final String initialText;
  final bool offerMuteOption;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<bool> onMuteChanged;

  const _SafariJsPromptBody({
    required this.initialText,
    required this.offerMuteOption,
    required this.onTextChanged,
    required this.onMuteChanged,
  });

  @override
  State<_SafariJsPromptBody> createState() => _SafariJsPromptBodyState();
}

class _SafariJsPromptBodyState extends State<_SafariJsPromptBody> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText)
      ..addListener(() => widget.onTextChanged(_ctrl.text));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final Widget inputField = TextField(
      key: const ValueKey('safari_js_prompt_input'),
      controller: _ctrl,
      autofocus: true,
      style: TextStyle(fontSize: 14.5, color: style.palette.onSurface),
      decoration: _buildSafariDialogInputDecoration(
        style,
        hintText: 'Введите ответ...',
      ),
      onSubmitted: (_) => Navigator.of(context).pop(true),
    );
    return widget.offerMuteOption
        ? _MuteCheckboxBody(
            upperContent: inputField,
            onChanged: widget.onMuteChanged,
          )
        : inputField;
  }
}

class _SafariHttpAuthBody extends StatefulWidget {
  final ValueChanged<String> onUserChanged;
  final ValueChanged<String> onPasswordChanged;

  const _SafariHttpAuthBody({
    required this.onUserChanged,
    required this.onPasswordChanged,
  });

  @override
  State<_SafariHttpAuthBody> createState() => _SafariHttpAuthBodyState();
}

class _SafariHttpAuthBodyState extends State<_SafariHttpAuthBody> {
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _userCtrl = TextEditingController()
      ..addListener(() => widget.onUserChanged(_userCtrl.text));
    _passCtrl = TextEditingController()
      ..addListener(() => widget.onPasswordChanged(_passCtrl.text));
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('safari_http_auth_user'),
          controller: _userCtrl,
          autofocus: true,
          textInputAction: TextInputAction.next,
          style: TextStyle(fontSize: 14.5, color: palette.onSurface),
          decoration: _buildSafariDialogInputDecoration(
            style,
            hintText: 'Имя пользователя',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('safari_http_auth_password'),
          controller: _passCtrl,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          style: TextStyle(fontSize: 14.5, color: palette.onSurface),
          decoration: _buildSafariDialogInputDecoration(
            style,
            hintText: 'Пароль',
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                size: 19,
                color: palette.subtext,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onSubmitted: (_) => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// Shows a Safari-style JavaScript `window.prompt()` dialog with a capsule text
/// field. Returns `value == null` when dismissed/cancelled.
Future<({String? value, bool muteHost})> showSafariJsPromptDialog(
  BuildContext context, {
  required String originHost,
  required bool isSecure,
  required String message,
  String? defaultText,
  bool offerMuteOption = false,
}) async {
  String currentValue = defaultText ?? '';
  bool mute = false;
  final bool submitted = await showSafariWebAlert<bool>(
        context: context,
        dialogKey: const ValueKey('safari_js_prompt_dialog'),
        tone: SafariAlertTone.info,
        iconOverride: Icons.edit_rounded,
        originLabel: originHost.isNotEmpty ? originHost : 'Веб-страница',
        originIsSecure: isSecure,
        title: 'Запрос данных со страницы',
        message: message,
        customBody: _SafariJsPromptBody(
          initialText: defaultText ?? '',
          offerMuteOption: offerMuteOption,
          onTextChanged: (v) => currentValue = v,
          onMuteChanged: (v) => mute = v,
        ),
        actions: const [
          SafariAlertAction<bool>(
            label: 'Отмена',
            result: false,
            buttonKey: ValueKey('safari_js_prompt_cancel_btn'),
          ),
          SafariAlertAction<bool>(
            label: 'ОК',
            result: true,
            isPrimary: true,
            buttonKey: ValueKey('safari_js_prompt_ok_btn'),
          ),
        ],
      ) ??
      false;
  return (
    value: submitted ? currentValue : null,
    muteHost: mute,
  );
}

/// Shows a Safari-style HTTP Basic/Digest Authentication prompt returning a
/// username/password tuple or `null` when cancelled.
Future<({String user, String password})?> showSafariHttpAuthDialog(
  BuildContext context, {
  required String host,
  String? realm,
}) async {
  String userValue = '';
  String passValue = '';
  final cleanHost = SafariUrlSafetyAnalyzer.decodePunycodeHost(host.trim());
  final String realmSuffix = (realm != null && realm.trim().isNotEmpty)
      ? '\nОбласть: ${realm.trim()}'
      : '';

  final bool confirmed = await showSafariWebAlert<bool>(
        context: context,
        dialogKey: const ValueKey('safari_http_auth_dialog'),
        tone: SafariAlertTone.auth,
        originLabel: cleanHost.isNotEmpty ? cleanHost : null,
        originIsSecure: true,
        title: 'Требуется вход',
        message: 'Введите имя пользователя и пароль для входа.$realmSuffix',
        customBody: _SafariHttpAuthBody(
          onUserChanged: (v) => userValue = v,
          onPasswordChanged: (v) => passValue = v,
        ),
        actions: const [
          SafariAlertAction<bool>(
            label: 'Отмена',
            result: false,
            buttonKey: ValueKey('safari_http_auth_cancel_btn'),
          ),
          SafariAlertAction<bool>(
            label: 'Войти',
            result: true,
            isPrimary: true,
            buttonKey: ValueKey('safari_http_auth_submit_btn'),
          ),
        ],
      ) ??
      false;
  if (!confirmed) return null;
  return (user: userValue, password: passValue);
}

/// Anchored Safari iOS 26 "Site Info" popover shown below the floating domain
/// capsule when tapping the lock/warning icon or choosing "Сведения о сайте".
class SafariSiteInfoPopover extends StatelessWidget {
  final SafariHostSafetyInfo safetyInfo;
  final bool isDesktopMode;
  final List<String> grantedPermissionLabels;
  final bool hasMutedJsDialogs;
  final bool hasAcceptedSslWarning;
  final VoidCallback onCopyUrl;
  final VoidCallback? onUpgradeToHttps;
  final VoidCallback? onResetPermissions;
  final VoidCallback onToggleDesktopMode;
  final VoidCallback onClearSiteDataAndReload;
  final bool bareContent;

  const SafariSiteInfoPopover({
    super.key,
    required this.safetyInfo,
    required this.isDesktopMode,
    this.grantedPermissionLabels = const [],
    this.hasMutedJsDialogs = false,
    this.hasAcceptedSslWarning = false,
    required this.onCopyUrl,
    this.onUpgradeToHttps,
    this.onResetPermissions,
    required this.onToggleDesktopMode,
    required this.onClearSiteDataAndReload,
    this.bareContent = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;

    final IconData statusIcon;
    final Color statusColor;
    final String statusTitle;
    final String statusDesc;

    switch (safetyInfo.securityLevel) {
      case SafariConnectionSecurityLevel.secureHttps:
        statusIcon = Icons.lock_rounded;
        statusColor = palette.primary;
        statusTitle = 'Соединение защищено';
        statusDesc =
            'Шифрование HTTPS активно для ${safetyInfo.displayHost.isNotEmpty ? safetyInfo.displayHost : 'этой страницы'}.';
        break;
      case SafariConnectionSecurityLevel.sslCertificateWarning:
        statusIcon = Icons.gpp_bad_rounded;
        statusColor = palette.error;
        statusTitle = 'Сертификат не проверен';
        statusDesc =
            'Вы продолжили просмотр, несмотря на ошибку сертификата безопасности.';
        break;
      case SafariConnectionSecurityLevel.insecureHttp:
      case SafariConnectionSecurityLevel.externalScheme:
        statusIcon = Icons.warning_amber_rounded;
        statusColor = palette.error;
        statusTitle = 'Соединение не защищено';
        statusDesc =
            'Страница загружена по открытому протоколу HTTP. Передаваемые данные не шифруются.';
        break;
    }

    final bool showCustomStateReset = grantedPermissionLabels.isNotEmpty ||
        hasMutedJsDialogs ||
        hasAcceptedSslWarning;

    final Widget contentColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      safetyInfo.displayHost.isNotEmpty
                          ? safetyInfo.displayHost
                          : 'Текущая страница',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: palette.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      safetyInfo.rawUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: palette.subtext,
                      ),
                    ),
                    if (safetyInfo.isInternationalized &&
                        safetyInfo.asciiHost != safetyInfo.unicodeHost)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Punycode: ${safetyInfo.asciiHost}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: safetyInfo.isSuspiciousHomograph
                                ? palette.error
                                : palette.subtext,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                height: 36,
                child: Material(
                  color: palette.onSurface
                      .withValues(alpha: style.isDark ? 0.10 : 0.06),
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const ValueKey('safari_site_info_copy_url'),
                    customBorder: const CircleBorder(),
                    onTap: onCopyUrl,
                    child: Icon(
                      Icons.copy_rounded,
                      size: 17,
                      color: palette.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: style.isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(statusIcon, size: 19, color: statusColor),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusTitle,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            statusDesc,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: palette.onSurface.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (onUpgradeToHttps != null &&
                    safetyInfo.securityLevel ==
                        SafariConnectionSecurityLevel.insecureHttp) ...[
                  const SizedBox(height: 10),
                  _SafariPopoverPillButton(
                    key: const ValueKey('safari_site_info_upgrade_https'),
                    icon: Icons.lock_rounded,
                    label: 'Открыть по защищённому HTTPS',
                    isAccent: true,
                    onTap: onUpgradeToHttps!,
                  ),
                ],
              ],
            ),
          ),
          if (showCustomStateReset && onResetPermissions != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: palette.onSurface
                    .withValues(alpha: style.isDark ? 0.08 : 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    [
                      if (grantedPermissionLabels.isNotEmpty)
                        'Разрешения: ${grantedPermissionLabels.join(', ')}',
                      if (hasMutedJsDialogs) 'JS-окна заблокированы в сессии',
                      if (hasAcceptedSslWarning) 'Исключение SSL активно',
                    ].join(' • '),
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.onSurface.withValues(alpha: 0.82),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SafariPopoverPillButton(
                    key: const ValueKey('safari_site_info_reset_permissions'),
                    icon: Icons.restart_alt_rounded,
                    label: 'Сбросить разрешения',
                    onTap: onResetPermissions!,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          _SafariPopoverPillButton(
            key: const ValueKey('safari_site_info_toggle_desktop'),
            icon: isDesktopMode
                ? Icons.phone_android_rounded
                : Icons.desktop_windows_rounded,
            label: isDesktopMode ? 'Мобильная версия' : 'Версия для ПК',
            onTap: onToggleDesktopMode,
          ),
          const SizedBox(height: 6),
          _SafariPopoverPillButton(
            key: const ValueKey('safari_site_info_clear_site_data'),
            icon: Icons.delete_sweep_rounded,
            label: 'Очистить данные сайта и обновить',
            isDestructive: true,
            onTap: onClearSiteDataAndReload,
          ),
        ],
    );

    if (bareContent) {
      return ConstrainedBox(
        key: const ValueKey('in_app_browser_site_info_popover'),
        constraints: const BoxConstraints(maxWidth: 328.0),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: contentColumn,
          ),
        ),
      );
    }

    return _SafariGlassSurface(
      key: const ValueKey('in_app_browser_site_info_popover'),
      maxWidth: 328.0,
      borderRadius: 26.0,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: contentColumn,
    );
  }
}

class _SafariPopoverPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isAccent;
  final bool isDestructive;

  const _SafariPopoverPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isAccent = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;

    final Color bgColor;
    final Color fgColor;
    if (isDestructive) {
      bgColor = palette.error.withValues(alpha: style.isDark ? 0.16 : 0.10);
      fgColor = palette.error;
    } else if (isAccent) {
      bgColor = palette.primary;
      fgColor = palette.onPrimary;
    } else {
      bgColor = palette.onSurface.withValues(alpha: style.isDark ? 0.10 : 0.06);
      fgColor = palette.onSurface;
    }

    return SizedBox(
      height: 38,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(19),
        child: InkWell(
          borderRadius: BorderRadius.circular(19),
          onTap: () {
            HapticUtils.tap();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: fgColor),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fgColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
