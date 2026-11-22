import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/bot_service.dart';
import '../../services/browser_cookie_jar_vault.dart';
import '../../services/browser_data_service.dart';
import '../../services/browser_site_settings_service.dart';
import '../../services/browser_storage_bridge.dart';
import '../../services/browser_vault_auth_gate.dart';
import '../../services/browser_vault_service.dart';
import '../../services/deep_link_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/mini_app_js_bridge.dart';
import '../../utils/blur_utils.dart';
import '../../utils/browser_autofill_script.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/link_opener.dart';
import '../../utils/safari_url_safety.dart';
import '../browser/in_app_browser_sheet.dart';
import '../browser/safari_browser_dialogs.dart';
import '../design_system/theav_design_system.dart';
import 'thv_invoice_sheet.dart';

/// Launches a bot Mini App (or restores a matching minimized [MiniAppSession])
/// full-screen over the root navigator while preserving any other minimized sessions.
Future<void> openMiniAppSheet(
  BuildContext context, {
  required String botId,
  String? botName,
  String? botUsername,
  bool? isVerified,
  String? url,
  String? appShortName,
  String? chatId,
  String mode = 'menu',
  String? startParam,
  String buttonText = '',
  ValueChanged<String>? onSwitchInlineQuery,
}) async {
  final sessionCtrl = MiniAppSessionController.instance;
  final normalizedId = botId.replaceFirst(RegExp(r'^@+'), '').toLowerCase();
  for (final existing in sessionCtrl.minimizedSessions.reversed) {
    if (existing.isBrowser) continue;
    final sameBot = existing.launchData.botId == botId ||
        (normalizedId.isNotEmpty &&
            existing.botUsername.toLowerCase() == normalizedId);
    final sameUrl =
        url == null || url.isEmpty || url == existing.launchData.url;
    if (sameBot && appShortName == null && sameUrl) {
      await sessionCtrl.restoreSession(existing);
      return;
    }
  }

  final theme = Theme.of(context);
  final themeParams = MiniAppJsBridge.buildThemeParams(theme);
  final cachedLaunch = BotService.getCachedLaunchData(
    botId: botId,
    url: url,
    appShortName: appShortName,
    chatId: chatId,
    mode: mode,
    startParam: startParam,
  );

  final MiniAppLaunchData initialLaunch = cachedLaunch ??
      MiniAppLaunchData(
        url: url ?? '',
        initData: '',
        botId: botId,
        botUsername: botUsername ?? '',
        botDisplayName: botName ?? '',
        botIsVerified: isVerified ?? false,
      );

  final Future<MiniAppLaunchData?>? pendingLaunchFuture = cachedLaunch != null
      ? null
      : BotService.launchWebApp(
          botId: botId,
          url: url,
          appShortName: appShortName,
          chatId: chatId,
          mode: mode,
          startParam: startParam,
          themeParams: themeParams,
        );

  final effectiveBotName = initialLaunch.botDisplayName.isNotEmpty
      ? initialLaunch.botDisplayName
      : (botName ?? '');
  final effectiveBotUser = initialLaunch.botUsername.isNotEmpty
      ? initialLaunch.botUsername
      : (botUsername ?? '');

  final session = MiniAppSession(
    launchData: initialLaunch,
    botName: effectiveBotName,
    botUsername: effectiveBotUser,
    isVerified: isVerified ?? initialLaunch.botIsVerified,
    chatId: chatId,
    mode: mode,
    buttonText: buttonText,
    onSwitchInlineQuery: onSwitchInlineQuery,
    pendingLaunchFuture: pendingLaunchFuture,
  );

  await showTheavModalSheet<void>(
    context: context,
    enableDrag: false,
    barrierDismissible: true,
    useRootNavigator: true,
    customSheetBuilder: (sheetCtx) => MiniAppWebViewSheet(
      launchData: session.launchData,
      botName: session.botName,
      botUsername: session.botUsername,
      isVerified: session.isVerified,
      chatId: chatId,
      mode: mode,
      buttonText: buttonText,
      onSwitchInlineQuery: onSwitchInlineQuery,
      session: session,
    ),
    builder: (_) => const SizedBox.shrink(),
  );
}

class MiniAppActionButtonState {
  bool isVisible = false;
  bool isActive = true;
  bool isProgressVisible = false;
  String text = 'Продолжить';
  Color? color;
  Color? textColor;
}

/// Extracted DOM block from a live Mini App or browser page for rich switcher previews.
class MiniAppDomBlock {
  final String kind;
  final String title;
  final String subtitle;
  final String trailing;
  final String leadingBadge;
  final Color? cardColor;
  final Color? fgColor;

  const MiniAppDomBlock({
    this.kind = 'card',
    required this.title,
    this.subtitle = '',
    this.trailing = '',
    this.leadingBadge = '',
    this.cardColor,
    this.fgColor,
  });
}

/// Snapshot of live page palette and visible DOM cards for the Mini App tabs switcher.
class MiniAppDomPreview {
  final Color? bgColor;
  final Color? textColor;
  final Color? accentColor;
  final List<MiniAppDomBlock> blocks;

  const MiniAppDomPreview({
    this.bgColor,
    this.textColor,
    this.accentColor,
    required this.blocks,
  });
}

/// UI delegate connecting a live [MiniAppSession] WebView to Safari-style
/// security warnings, permissions, JS dialogs, and HTTP auth prompts.
abstract interface class BrowserUiDialogDelegate {
  bool get isDialogHostMounted;

  Future<bool> onSslAuthWarning({required String host});

  Future<bool> onSuspiciousHostWarning({required SafariHostSafetyInfo info});

  Future<bool> onExternalSchemeRequest({
    required Uri uri,
    String? sourceHost,
  });

  Future<bool> onSitePermissionRequest({
    required String host,
    required Set<WebViewPermissionResourceType> types,
  });

  Future<SafariSitePermissionChoice> onSitePermissionChoiceRequest({
    required String host,
    required Set<WebViewPermissionResourceType> types,
    required bool offerPersistentAlways,
  });

  Future<void> onSystemPermissionBlocked({required String resourceLabel});

  Future<void> onJsAlert({
    required String host,
    required bool isSecure,
    required String message,
    required bool offerMute,
    required VoidCallback onMuteHost,
  });

  Future<bool> onJsConfirm({
    required String host,
    required bool isSecure,
    required String message,
    required bool offerMute,
    required VoidCallback onMuteHost,
  });

  Future<String> onJsPrompt({
    required String host,
    required bool isSecure,
    required String message,
    String? defaultText,
    required bool offerMute,
    required VoidCallback onMuteHost,
  });

  Future<WebViewCredential?> onHttpAuthRequest({
    required String host,
    String? realm,
    String? url,
    bool isIncognito = false,
  });
}

/// Shared Safari-styled [BrowserUiDialogDelegate] implementation used by both
/// [InAppBrowserSheet] and [MiniAppWebViewSheet].
class SheetBrowserUiDialogDelegate implements BrowserUiDialogDelegate {
  final BuildContext Function() contextResolver;
  final bool Function() mountedResolver;

  const SheetBrowserUiDialogDelegate({
    required this.contextResolver,
    required this.mountedResolver,
  });

  @override
  bool get isDialogHostMounted => mountedResolver();

  @override
  Future<bool> onSslAuthWarning({required String host}) {
    if (!isDialogHostMounted) return Future<bool>.value(false);
    return showSafariSslWarningDialog(contextResolver(), host: host);
  }

  @override
  Future<bool> onSuspiciousHostWarning({required SafariHostSafetyInfo info}) {
    if (!isDialogHostMounted) return Future<bool>.value(false);
    return showSafariSuspiciousLinkDialog(contextResolver(), info: info);
  }

  @override
  Future<bool> onExternalSchemeRequest({
    required Uri uri,
    String? sourceHost,
  }) {
    if (!isDialogHostMounted) return Future<bool>.value(false);
    return showSafariExternalAppDialog(
      contextResolver(),
      uri: uri,
      sourceHost: sourceHost,
    );
  }

  @override
  Future<bool> onSitePermissionRequest({
    required String host,
    required Set<WebViewPermissionResourceType> types,
  }) {
    if (!isDialogHostMounted) return Future<bool>.value(false);
    return showSafariPermissionDialog(
      contextResolver(),
      host: host,
      types: types,
    );
  }

  @override
  Future<SafariSitePermissionChoice> onSitePermissionChoiceRequest({
    required String host,
    required Set<WebViewPermissionResourceType> types,
    required bool offerPersistentAlways,
  }) {
    if (!isDialogHostMounted) {
      return Future<SafariSitePermissionChoice>.value(
        SafariSitePermissionChoice.deny,
      );
    }
    return showSafariSitePermissionDialog(
      contextResolver(),
      host: host,
      types: types,
      offerPersistentAlways: offerPersistentAlways,
    );
  }

  @override
  Future<void> onSystemPermissionBlocked({required String resourceLabel}) {
    if (!isDialogHostMounted) return Future<void>.value();
    return showSafariSystemPermissionDeniedDialog(
      contextResolver(),
      resourceLabel: resourceLabel,
      onOpenSettings: openAppSettings,
    );
  }

  @override
  Future<void> onJsAlert({
    required String host,
    required bool isSecure,
    required String message,
    required bool offerMute,
    required VoidCallback onMuteHost,
  }) async {
    if (!isDialogHostMounted) return;
    final res = await showSafariJsAlertDialog(
      contextResolver(),
      originHost: host,
      isSecure: isSecure,
      message: message,
      offerMuteOption: offerMute,
    );
    if (res.muteHost) onMuteHost();
  }

  @override
  Future<bool> onJsConfirm({
    required String host,
    required bool isSecure,
    required String message,
    required bool offerMute,
    required VoidCallback onMuteHost,
  }) async {
    if (!isDialogHostMounted) return false;
    final res = await showSafariJsConfirmDialog(
      contextResolver(),
      originHost: host,
      isSecure: isSecure,
      message: message,
      offerMuteOption: offerMute,
    );
    if (res.muteHost) onMuteHost();
    return res.confirmed;
  }

  @override
  Future<String> onJsPrompt({
    required String host,
    required bool isSecure,
    required String message,
    String? defaultText,
    required bool offerMute,
    required VoidCallback onMuteHost,
  }) async {
    if (!isDialogHostMounted) return '';
    final res = await showSafariJsPromptDialog(
      contextResolver(),
      originHost: host,
      isSecure: isSecure,
      message: message,
      defaultText: defaultText,
      offerMuteOption: offerMute,
    );
    if (res.muteHost) onMuteHost();
    return res.value ?? '';
  }

  @override
  Future<WebViewCredential?> onHttpAuthRequest({
    required String host,
    String? realm,
    String? url,
    bool isIncognito = false,
  }) async {
    if (!isDialogHostMounted) return null;
    final cleanHost = host.trim();
    final effectiveUrl = (url != null && url.trim().isNotEmpty)
        ? url.trim()
        : (cleanHost.isNotEmpty ? 'https://$cleanHost/' : '');
    final vault = BrowserVaultService.instance;
    await vault.ensureLoaded();
    await BrowserSiteSettingsService.instance.ensureLoaded();
    if (!isDialogHostMounted) return null;

    final hints = effectiveUrl.isNotEmpty
        ? vault.getHintsForUrl(effectiveUrl, isHttpAuth: true, realm: realm)
        : const <BrowserCredentialHint>[];

    final res = await showSafariHttpAuthDialog(
      contextResolver(),
      host: cleanHost,
      realm: realm,
      savedHints: hints,
      onUnlockSavedHint: hints.isEmpty
          ? null
          : (hint) {
              if (!isDialogHostMounted) {
                return Future<BrowserSavedCredential?>.value(null);
              }
              return vault.unlockAndReadCredential(
                contextResolver(),
                hint.id,
                reason: 'Подтвердите личность для входа на $cleanHost',
                originScope: effectiveUrl,
              );
            },
      offerSaveOption:
          !isIncognito && BrowserSiteSettingsService.instance.savePasswordsEnabled,
    );
    if (res == null) return null;
    if (res.saveCredential &&
        !isIncognito &&
        res.password.isNotEmpty &&
        effectiveUrl.isNotEmpty) {
      unawaited(
        vault.saveOrUpdateCredential(
          url: effectiveUrl,
          username: res.user,
          password: res.password,
          isHttpAuth: true,
          realm: realm,
        ),
      );
    }
    return WebViewCredential(user: res.user, password: res.password);
  }
}

/// Persistent live Mini App state retained across full-screen <-> minimized dock
/// bar <-> tabs switcher transitions so the underlying `WebViewController` and JS session never reload.
class MiniAppSession {
  static const MethodChannel _snapshotChannel =
      MethodChannel('app.theaver.messenger/webview_snapshot');
  static int _nextSessionSeq = 0;

  final String id;
  MiniAppLaunchData launchData;
  String botName;
  String botUsername;
  bool isVerified;
  final String? chatId;
  final String mode;
  final String buttonText;
  final ValueChanged<String>? onSwitchInlineQuery;

  WebViewController? controller;
  final ValueNotifier<double> loadProgressNotifier = ValueNotifier<double>(0.0);
  bool isLaunchPending = false;
  String? launchError;
  bool isWebContentReady = false;
  Uint8List? previewImageBytes;
  MiniAppDomPreview? domPreview;
  Future<void>? _activeSnapshotFuture;
  Uint8List? _cachedPreviewBytesRef;
  ImageProvider? _cachedPreviewProvider;
  Uint8List? _cachedFullPreviewBytesRef;
  ImageProvider? _cachedFullPreviewProvider;

  /// Cached downscaled [ImageProvider] for [previewImageBytes] so 3D switcher
  /// cards reuse decoded raster textures instead of recreating [MemoryImage] instances.
  ImageProvider? get previewImageProvider {
    final bytes = previewImageBytes;
    if (bytes == null || bytes.isEmpty) {
      _cachedPreviewBytesRef = null;
      _cachedPreviewProvider = null;
      return null;
    }
    if (!identical(_cachedPreviewBytesRef, bytes) ||
        _cachedPreviewProvider == null) {
      _cachedPreviewBytesRef = bytes;
      _cachedPreviewProvider =
          ResizeImage.resizeIfNeeded(540, null, MemoryImage(bytes));
    }
    return _cachedPreviewProvider;
  }

  /// Cached full-resolution [ImageProvider] for [previewImageBytes] used as a
  /// zero-stutter viewport stand-in during sheet restore and surface warmup.
  ImageProvider? get fullViewportPreviewProvider {
    final bytes = previewImageBytes;
    if (bytes == null || bytes.isEmpty) {
      _cachedFullPreviewBytesRef = null;
      _cachedFullPreviewProvider = null;
      return null;
    }
    if (!identical(_cachedFullPreviewBytesRef, bytes) ||
        _cachedFullPreviewProvider == null) {
      _cachedFullPreviewBytesRef = bytes;
      _cachedFullPreviewProvider = MemoryImage(bytes);
    }
    return _cachedFullPreviewProvider;
  }
  bool allowVerticalSwipe = true;
  bool backButtonVisible = false;
  bool settingsButtonVisible = false;
  bool closingConfirmation = false;
  Color? customHeaderColor;
  Color? customBackgroundColor;
  Color? customBottomBarColor;
  final MiniAppActionButtonState mainButton = MiniAppActionButtonState()
    ..text = 'Continue';
  final MiniAppActionButtonState secondaryButton = MiniAppActionButtonState()
    ..text = 'Cancel';

  bool isMinimized = false;
  NavigatorState? lastNavigator;

  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  final bool isBrowser;
  final bool isIncognito;
  String currentUrl;
  String pageTitle = '';
  bool canGoBack = false;
  bool canGoForward = false;
  bool isDesktopMode = false;
  double browserTopClearance = 58.0;
  double browserCompactTopClearance = 32.0;
  double browserBottomClearance = 64.0;
  double browserCompactBottomClearance = 0.0;
  double browserViewportHeight = 0.0;
  bool browserForceExpanded = false;
  bool browserChromeCollapsed = false;
  bool? browserTopIsDark;
  Color? browserCanvasColor;
  Color? browserTopPocketColor;
  Color? browserBottomPocketColor;
  int _earlyBrowserInsetsStage = 0;

  BrowserFocusedFieldState? focusedAutofillField;
  BrowserPendingCredentialSubmission? pendingCredentialPrompt;
  String? _lastAutofillOrigin;

  Future<void> setBrowserChromeCollapsed(bool collapsed) async {
    if (browserForceExpanded && collapsed) return;
    if (browserChromeCollapsed != collapsed) {
      browserChromeCollapsed = collapsed;
      onSheetStateChanged?.call();
      MiniAppSessionController.instance.notifySessionUpdated();
    }
    final ctrl = controller;
    if (ctrl != null && isBrowser && WebViewPlatform.instance != null) {
      try {
        await ctrl.runJavaScript(
          'if (window.__theaverSetCollapsedFromHost) { window.__theaverSetCollapsedFromHost(${collapsed ? 'true' : 'false'}); }',
        );
      } catch (_) {}
    }
  }

  VoidCallback? onSheetStateChanged;
  VoidCallback? onPendingLaunchResolved;
  VoidCallback? onRequestBridgeInjection;
  ValueChanged<String>? onInboundBridgeMessage;
  BrowserUiDialogDelegate? uiDialogDelegate;

  final Set<String> acceptedSslWarningHosts = <String>{};
  final Set<String> acceptedSuspiciousHosts = <String>{};
  bool currentPageHasSslWarning = false;
  final Map<String, Map<String, bool>> sessionSitePermissions =
      <String, Map<String, bool>>{};
  final Set<String> mutedJsDialogHosts = <String>{};
  final List<DateTime> _recentJsDialogAt = <DateTime>[];
  bool _webPageInteractionLocked = false;

  bool get isWebPageInteractionLocked => _webPageInteractionLocked;

  /// Freezes webpage scrolling, kinetic flings, touch events, and focus when
  /// any browser/Mini App overlay (popover, menu, or modal alert) is open.
  Future<void> setWebPageInteractionLocked(
    bool locked, {
    bool force = false,
  }) async {
    if (!force && _webPageInteractionLocked == locked) return;
    _webPageInteractionLocked = locked;

    final String targetUrl = isBrowser ? currentUrl : launchData.url;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        WebViewPlatform.instance != null) {
      try {
        await _snapshotChannel.invokeMethod<bool>(
          'setWebViewInteractionLocked',
          <String, dynamic>{
            'url': targetUrl,
            'locked': locked,
          },
        );
      } on MissingPluginException {
        // Non-Android / unit test environment has no native WebView lock channel.
      } on PlatformException {
        // Ignore transient channel errors during route teardown.
      } catch (_) {}
    }

    final ctrl = controller;
    if (ctrl != null && WebViewPlatform.instance != null) {
      final String lockJs = '''
(function(lock) {
  try {
    window.__theaverInteractionLocked = !!lock;
    if (lock) {
      window.scrollTo(window.scrollX || 0, window.scrollY || 0);
      if (!window.__theaverLockGuardInstalled) {
        window.__theaverLockGuardInstalled = true;
        var blockEvt = function(e) {
          if (!window.__theaverInteractionLocked) return;
          if (e.cancelable) e.preventDefault();
          e.stopImmediatePropagation();
        };
        var blockKeys = function(e) {
          if (!window.__theaverInteractionLocked) return;
          var k = e.key || '';
          if (k === 'ArrowDown' || k === 'ArrowUp' || k === 'PageDown' || k === 'PageUp' || k === ' ' || k === 'Home' || k === 'End') {
            if (e.cancelable) e.preventDefault();
            e.stopImmediatePropagation();
          }
        };
        var opts = { passive: false, capture: true };
        window.addEventListener('touchstart', blockEvt, opts);
        window.addEventListener('touchmove', blockEvt, opts);
        window.addEventListener('wheel', blockEvt, opts);
        window.addEventListener('pointerdown', blockEvt, opts);
        window.addEventListener('click', blockEvt, opts);
        window.addEventListener('keydown', blockKeys, opts);
      }
      if (document.documentElement) {
        document.documentElement.style.setProperty('touch-action', 'none', 'important');
      }
    } else if (document.documentElement) {
      document.documentElement.style.removeProperty('touch-action');
    }
  } catch (_) {}
})(${locked ? 'true' : 'false'});
''';
      try {
        await ctrl.runJavaScript(lockJs);
      } catch (_) {}
    }
  }

  String _hostKeyForUrl(String? rawUrl) {
    final target = (rawUrl ?? '').trim().isNotEmpty
        ? rawUrl!.trim()
        : (isBrowser ? currentUrl : launchData.url);
    final info = SafariUrlSafetyAnalyzer.analyzeUrl(target);
    if (info.asciiHost.isNotEmpty) return info.asciiHost.toLowerCase();
    return BrowserDataService.extractHost(target).toLowerCase();
  }

  ({String label, bool isSecure, String hostKey}) _resolveDialogOrigin(
    String? rawUrl,
  ) {
    final target = (rawUrl ?? '').trim().isNotEmpty
        ? rawUrl!.trim()
        : (isBrowser ? currentUrl : launchData.url);
    final info = SafariUrlSafetyAnalyzer.analyzeUrl(
      target,
      hasSslWarning: currentPageHasSslWarning,
    );
    final String hostKey = info.asciiHost.isNotEmpty
        ? info.asciiHost.toLowerCase()
        : BrowserDataService.extractHost(target).toLowerCase();
    final bool isSecure =
        info.securityLevel == SafariConnectionSecurityLevel.secureHttps;
    final String label;
    if (!isBrowser && botUsername.trim().isNotEmpty) {
      label = '@${botUsername.trim()}';
    } else if (info.displayHost.isNotEmpty) {
      label = info.displayHost;
    } else {
      label = displayTitle;
    }
    return (label: label, isSecure: isSecure, hostKey: hostKey);
  }

  /// Records a JS dialog attempt and returns `true` if the page triggered
  /// 3+ dialogs within 3 seconds (activating the Safari mute toggle option).
  bool recordJsDialogAndShouldOfferMute([DateTime? now]) {
    final DateTime ts = now ?? DateTime.now();
    _recentJsDialogAt.removeWhere(
      (prev) => ts.difference(prev).inMilliseconds > 3000,
    );
    _recentJsDialogAt.add(ts);
    return _recentJsDialogAt.length >= 3;
  }

  void clearAutofillOverlays({bool notify = true}) {
    final bool changed =
        focusedAutofillField != null || pendingCredentialPrompt != null;
    focusedAutofillField = null;
    pendingCredentialPrompt = null;
    if (changed && notify) {
      onSheetStateChanged?.call();
    }
  }

  /// Processes JSON messages sent by [BrowserAutofillScript] on the top-level
  /// web document for autofill bar presentation and login save prompts.
  Future<void> handleAutofillChannelMessage(String rawMessage) async {
    if (!isBrowser) return;
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is! Map) return;
      final type = decoded['type']?.toString() ?? '';
      final msgOrigin = decoded['origin']?.toString() ?? '';
      final pageOrigin = BrowserVaultService.normalizeOrigin(currentUrl);
      if (pageOrigin == null || msgOrigin != pageOrigin) return;

      if (type == 'fieldFocused') {
        if (isIncognito) {
          focusedAutofillField = null;
          onSheetStateChanged?.call();
          return;
        }
        final kind = decoded['kind']?.toString() ?? '';
        final subtype = decoded['subtype']?.toString() ?? '';
        if (kind != 'login' && kind != 'contact') return;
        focusedAutofillField = BrowserFocusedFieldState(
          kind: kind,
          subtype: subtype,
          origin: pageOrigin,
        );
        onSheetStateChanged?.call();
      } else if (type == 'fieldBlurred') {
        if (focusedAutofillField != null) {
          focusedAutofillField = null;
          onSheetStateChanged?.call();
        }
      } else if (type == 'credentialsSubmitted') {
        if (isIncognito) return;
        await BrowserSiteSettingsService.instance.ensureLoaded();
        if (!BrowserSiteSettingsService.instance.savePasswordsEnabled) return;
        final username = decoded['username']?.toString() ?? '';
        final password = decoded['password']?.toString() ?? '';
        final evaluation = await BrowserVaultService.instance.inspectCandidate(
          url: currentUrl,
          username: username,
          password: password,
        );
        if (evaluation.status == BrowserVaultSaveStatus.newCredential ||
            evaluation.status == BrowserVaultSaveStatus.updatePassword) {
          focusedAutofillField = null;
          pendingCredentialPrompt = BrowserPendingCredentialSubmission(
            url: currentUrl,
            origin: evaluation.normalizedOrigin ?? pageOrigin,
            displayHost: evaluation.displayHost ?? displayTitle,
            username: username.trim(),
            password: password,
            isUpdate:
                evaluation.status == BrowserVaultSaveStatus.updatePassword,
            existingId: evaluation.existingId,
          );
          onSheetStateChanged?.call();
        }
      }
    } catch (_) {}
  }

  List<String> grantedPermissionLabelsForUrl(String rawUrl) {
    final hostKey = _hostKeyForUrl(rawUrl);
    final perms = sessionSitePermissions[hostKey];
    final persistent = !isIncognito
        ? BrowserSiteSettingsService.instance.preferenceForHost(hostKey)
        : null;
    final bool hasCam =
        perms?[WebViewPermissionResourceType.camera.name] == true ||
            persistent?.cameraPolicy == SitePermissionDecision.allow;
    final bool hasMic =
        perms?[WebViewPermissionResourceType.microphone.name] == true ||
            persistent?.microphonePolicy == SitePermissionDecision.allow;
    final labels = <String>[];
    if (hasCam) labels.add('Камера');
    if (hasMic) labels.add('Микрофон');
    return labels;
  }

  bool hasMutedJsDialogsForUrl(String rawUrl) {
    final hostKey = _hostKeyForUrl(rawUrl);
    if (mutedJsDialogHosts.contains(hostKey)) return true;
    if (!isIncognito) {
      return BrowserSiteSettingsService.instance
              .preferenceForHost(hostKey)
              ?.muteJsDialogs ??
          false;
    }
    return false;
  }

  bool hasAcceptedSslWarningForUrl(String rawUrl) =>
      acceptedSslWarningHosts.contains(_hostKeyForUrl(rawUrl));

  void resetSessionPermissionsForUrl(String rawUrl) {
    final hostKey = _hostKeyForUrl(rawUrl);
    sessionSitePermissions.remove(hostKey);
    mutedJsDialogHosts.remove(hostKey);
    acceptedSslWarningHosts.remove(hostKey);
    acceptedSuspiciousHosts.remove(hostKey);
    if (isBrowser && !isIncognito && hostKey.isNotEmpty) {
      unawaited(BrowserSiteSettingsService.instance.resetHost(hostKey));
    }
    if (_hostKeyForUrl(currentUrl) == hostKey) {
      currentPageHasSslWarning = false;
    }
    onSheetStateChanged?.call();
    MiniAppSessionController.instance.notifySessionUpdated();
  }

  bool get _hasActiveDialogHost =>
      !isMinimized &&
      uiDialogDelegate != null &&
      uiDialogDelegate!.isDialogHostMounted;

  Future<void> handleSslAuthError(SslAuthError error) async {
    final origin = _resolveDialogOrigin(null);
    if (!_hasActiveDialogHost) {
      try {
        await error.cancel();
      } catch (_) {}
      return;
    }
    if (origin.hostKey.isNotEmpty &&
        acceptedSslWarningHosts.contains(origin.hostKey)) {
      currentPageHasSslWarning = true;
      onSheetStateChanged?.call();
      try {
        await error.proceed();
      } catch (_) {}
      return;
    }
    final bool proceed = await uiDialogDelegate!.onSslAuthWarning(
      host: origin.label,
    );
    if (proceed) {
      if (origin.hostKey.isNotEmpty) {
        acceptedSslWarningHosts.add(origin.hostKey);
      }
      currentPageHasSslWarning = true;
      onSheetStateChanged?.call();
      try {
        await error.proceed();
      } catch (_) {}
    } else {
      try {
        await error.cancel();
      } catch (_) {}
    }
  }

  Future<void> handleWebPermissionRequest(
    WebViewPermissionRequest request,
  ) async {
    if (!_hasActiveDialogHost) {
      try {
        await request.deny();
      } catch (_) {}
      return;
    }
    final origin = _resolveDialogOrigin(null);
    if (isBrowser && !isIncognito) {
      await BrowserSiteSettingsService.instance.ensureLoaded();
    }
    final persistentPref = (isBrowser && !isIncognito)
        ? BrowserSiteSettingsService.instance.preferenceForHost(origin.hostKey)
        : null;
    final hostPerms = sessionSitePermissions.putIfAbsent(
      origin.hostKey,
      () => <String, bool>{},
    );

    bool hasAllCachedGrants = request.types.isNotEmpty;
    bool hasAnyCachedDeny = false;
    for (final t in request.types) {
      bool? cached = hostPerms[t.name];
      if (cached == null && persistentPref != null) {
        if (t == WebViewPermissionResourceType.camera) {
          if (persistentPref.cameraPolicy == SitePermissionDecision.allow) {
            cached = true;
          } else if (persistentPref.cameraPolicy ==
              SitePermissionDecision.deny) {
            cached = false;
          }
        } else if (t == WebViewPermissionResourceType.microphone) {
          if (persistentPref.microphonePolicy == SitePermissionDecision.allow) {
            cached = true;
          } else if (persistentPref.microphonePolicy ==
              SitePermissionDecision.deny) {
            cached = false;
          }
        }
      }
      if (cached == false) {
        hasAnyCachedDeny = true;
      }
      if (cached != true) {
        hasAllCachedGrants = false;
      }
    }
    if (hasAnyCachedDeny) {
      try {
        await request.deny();
      } catch (_) {}
      return;
    }

    if (!hasAllCachedGrants) {
      final SafariSitePermissionChoice choice =
          await uiDialogDelegate!.onSitePermissionChoiceRequest(
        host: origin.label,
        types: request.types,
        offerPersistentAlways: isBrowser && !isIncognito,
      );
      final bool siteAllowed = choice != SafariSitePermissionChoice.deny;
      for (final t in request.types) {
        hostPerms[t.name] = siteAllowed;
      }
      if (choice == SafariSitePermissionChoice.allowAlways &&
          isBrowser &&
          !isIncognito &&
          origin.hostKey.isNotEmpty) {
        await BrowserSiteSettingsService.instance.setPermissionForHost(
          origin.hostKey,
          camera: request.types.contains(WebViewPermissionResourceType.camera)
              ? SitePermissionDecision.allow
              : null,
          microphone:
              request.types.contains(WebViewPermissionResourceType.microphone)
                  ? SitePermissionDecision.allow
                  : null,
        );
      }
      onSheetStateChanged?.call();
      if (!siteAllowed) {
        try {
          await request.deny();
        } catch (_) {}
        return;
      }
    }

    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final neededOs = <Permission>[];
      if (request.types.contains(WebViewPermissionResourceType.camera)) {
        neededOs.add(Permission.camera);
      }
      if (request.types.contains(WebViewPermissionResourceType.microphone)) {
        neededOs.add(Permission.microphone);
      }
      if (neededOs.isNotEmpty) {
        try {
          final statuses = await neededOs.request();
          bool allOk = true;
          bool anyPermanentlyDenied = false;
          for (final perm in neededOs) {
            final st = statuses[perm];
            if (st == null || (!st.isGranted && !st.isLimited)) {
              allOk = false;
              if (st?.isPermanentlyDenied == true) {
                anyPermanentlyDenied = true;
              }
            }
          }
          if (!allOk) {
            for (final t in request.types) {
              hostPerms[t.name] = false;
            }
            onSheetStateChanged?.call();
            if (anyPermanentlyDenied && _hasActiveDialogHost) {
              final label = neededOs.length > 1
                  ? 'камере и микрофону'
                  : (neededOs.contains(Permission.microphone)
                      ? 'микрофону'
                      : 'камере');
              await uiDialogDelegate!.onSystemPermissionBlocked(
                resourceLabel: label,
              );
            }
            try {
              await request.deny();
            } catch (_) {}
            return;
          }
        } catch (_) {
          // Platform channel unavailable in test/desktop environments.
        }
      }
    }

    try {
      await request.grant();
    } catch (_) {}
  }

  Future<void> handleJavaScriptAlert(
    JavaScriptAlertDialogRequest request,
  ) async {
    final origin = _resolveDialogOrigin(request.url);
    final bool isMuted = origin.hostKey.isNotEmpty &&
        (mutedJsDialogHosts.contains(origin.hostKey) ||
            (!isIncognito &&
                (BrowserSiteSettingsService.instance
                        .preferenceForHost(origin.hostKey)
                        ?.muteJsDialogs ??
                    false)));
    if (!_hasActiveDialogHost || isMuted) {
      return;
    }
    final bool offerMute = recordJsDialogAndShouldOfferMute();
    await uiDialogDelegate!.onJsAlert(
      host: origin.label,
      isSecure: origin.isSecure,
      message: request.message,
      offerMute: offerMute,
      onMuteHost: () {
        if (origin.hostKey.isNotEmpty) {
          mutedJsDialogHosts.add(origin.hostKey);
          if (isBrowser && !isIncognito) {
            unawaited(
              BrowserSiteSettingsService.instance
                  .setMuteJsDialogsForHost(origin.hostKey, true),
            );
          }
          onSheetStateChanged?.call();
        }
      },
    );
  }

  Future<bool> handleJavaScriptConfirm(
    JavaScriptConfirmDialogRequest request,
  ) async {
    final origin = _resolveDialogOrigin(request.url);
    final bool isMuted = origin.hostKey.isNotEmpty &&
        (mutedJsDialogHosts.contains(origin.hostKey) ||
            (!isIncognito &&
                (BrowserSiteSettingsService.instance
                        .preferenceForHost(origin.hostKey)
                        ?.muteJsDialogs ??
                    false)));
    if (!_hasActiveDialogHost || isMuted) {
      return false;
    }
    final bool offerMute = recordJsDialogAndShouldOfferMute();
    return uiDialogDelegate!.onJsConfirm(
      host: origin.label,
      isSecure: origin.isSecure,
      message: request.message,
      offerMute: offerMute,
      onMuteHost: () {
        if (origin.hostKey.isNotEmpty) {
          mutedJsDialogHosts.add(origin.hostKey);
          if (isBrowser && !isIncognito) {
            unawaited(
              BrowserSiteSettingsService.instance
                  .setMuteJsDialogsForHost(origin.hostKey, true),
            );
          }
          onSheetStateChanged?.call();
        }
      },
    );
  }

  Future<String> handleJavaScriptPrompt(
    JavaScriptTextInputDialogRequest request,
  ) async {
    final origin = _resolveDialogOrigin(request.url);
    final bool isMuted = origin.hostKey.isNotEmpty &&
        (mutedJsDialogHosts.contains(origin.hostKey) ||
            (!isIncognito &&
                (BrowserSiteSettingsService.instance
                        .preferenceForHost(origin.hostKey)
                        ?.muteJsDialogs ??
                    false)));
    if (!_hasActiveDialogHost || isMuted) {
      return '';
    }
    final bool offerMute = recordJsDialogAndShouldOfferMute();
    return uiDialogDelegate!.onJsPrompt(
      host: origin.label,
      isSecure: origin.isSecure,
      message: request.message,
      defaultText: request.defaultText,
      offerMute: offerMute,
      onMuteHost: () {
        if (origin.hostKey.isNotEmpty) {
          mutedJsDialogHosts.add(origin.hostKey);
          if (isBrowser && !isIncognito) {
            unawaited(
              BrowserSiteSettingsService.instance
                  .setMuteJsDialogsForHost(origin.hostKey, true),
            );
          }
          onSheetStateChanged?.call();
        }
      },
    );
  }

  Future<void> handleHttpAuth(HttpAuthRequest request) async {
    if (!_hasActiveDialogHost) {
      request.onCancel();
      return;
    }
    final String cleanHost = request.host.trim().isNotEmpty
        ? request.host.trim()
        : _resolveDialogOrigin(null).label;
    final WebViewCredential? cred = await uiDialogDelegate!.onHttpAuthRequest(
      host: cleanHost,
      realm: request.realm,
      url: isBrowser ? currentUrl : launchData.url,
      isIncognito: isIncognito,
    );
    if (cred != null) {
      request.onProceed(cred);
    } else {
      request.onCancel();
    }
  }

  int _lastReportedPercent = -1;

  double get loadProgress => loadProgressNotifier.value;
  set loadProgress(double value) {
    final next = value.clamp(0.0, 1.0);
    _lastReportedPercent = (next * 100).round();
    if (loadProgressNotifier.value != next) {
      loadProgressNotifier.value = next;
    }
  }

  /// Updates [loadProgressNotifier] only when progress advances meaningfully (>= 2%)
  /// or hits boundaries (`0` / `100`), avoiding high-frequency rebuild storms.
  void updateLoadProgress(int percent) {
    final int clamped = percent.clamp(0, 100);
    final double next = clamped / 100.0;
    if (_lastReportedPercent < 0 ||
        clamped == 0 ||
        clamped == 100 ||
        (clamped - _lastReportedPercent).abs() >= 2) {
      _lastReportedPercent = clamped;
      if (loadProgressNotifier.value != next) {
        loadProgressNotifier.value = next;
      }
    }
  }

  MiniAppSession({
    String? id,
    required this.launchData,
    this.botName = '',
    this.botUsername = '',
    this.isVerified = false,
    this.chatId,
    this.mode = 'menu',
    this.buttonText = '',
    this.onSwitchInlineQuery,
    this.isBrowser = false,
    this.isIncognito = false,
    String? initialUrl,
    Future<MiniAppLaunchData?>? pendingLaunchFuture,
  })  : id = id ?? '${isBrowser ? 'browser_tab' : 'mini_app'}_${++_nextSessionSeq}',
        currentUrl = (initialUrl != null && initialUrl.trim().isNotEmpty)
            ? initialUrl.trim()
            : launchData.url {
    MiniAppSessionController.instance.ensureInitialized();
    if (pendingLaunchFuture != null) {
      isLaunchPending = true;
      pendingLaunchFuture.then((resolved) {
        isLaunchPending = false;
        if (resolved == null || resolved.url.trim().isEmpty) {
          launchError = 'Не удалось открыть Mini App';
          onSheetStateChanged?.call();
          return;
        }
        launchData = resolved;
        launchError = null;
        if (currentUrl.trim().isEmpty) {
          currentUrl = resolved.url;
        }
        if (resolved.botDisplayName.isNotEmpty) {
          botName = resolved.botDisplayName;
        }
        if (resolved.botUsername.isNotEmpty) {
          botUsername = resolved.botUsername;
        }
        if (resolved.botIsVerified) {
          isVerified = true;
        }
        onPendingLaunchResolved?.call();
        onSheetStateChanged?.call();
        MiniAppSessionController.instance.notifySessionUpdated();
      }).catchError((_) {
        isLaunchPending = false;
        launchError = 'Не удалось открыть Mini App';
        onSheetStateChanged?.call();
      });
    }
  }

  String get displayTitle {
    if (isBrowser) {
      if (pageTitle.trim().isNotEmpty) return pageTitle.trim();
      return BrowserDataService.extractHost(currentUrl);
    }
    return botName.isNotEmpty
        ? botName
        : (launchData.botDisplayName.isNotEmpty
            ? launchData.botDisplayName
            : 'Mini App');
  }

  /// Builds an idempotent JS pass + observer matching Safari iOS 26 ("Top")
  /// ergonomics: keeps feeds full-screen edge-to-edge under the 3 top glass
  /// capsules, polyfills `env(safe-area-inset-bottom/top)` with dynamic host
  /// variables, adjusts only root scroll start/end padding and a single primary
  /// top-0 navbar (no nested `bottom-pinned`, `top-abs`, or drawer shifting),
  /// detects downward/upward scroll to collapse/expand browser chrome, and
  /// samples top/bottom pocket background colors.
  static String buildBrowserSafeInsetsScript({
    required int topPx,
    required int bottomPx,
    int? compactTopPx,
    int? compactBottomPx,
    int flutterViewportHeight = 0,
    bool forceExpanded = false,
  }) {
    final int safeTop = topPx.clamp(0, 320);
    final int safeBottom = bottomPx.clamp(0, 320);
    final int safeCompactTop =
        (compactTopPx ?? math.max(0, safeTop - 26)).clamp(0, safeTop);
    final int safeCompactBottom = (compactBottomPx ?? 0).clamp(0, safeBottom);
    final int safeFlutterVh = flutterViewportHeight.clamp(0, 4096);
    final String forceExpandedLit = forceExpanded ? 'true' : 'false';
    const String template = r'''
(function() {
  try {
    if (!document || !document.documentElement) return null;
    window.__theaverTopClear = __TOP_PX__;
    window.__theaverCompactTopClear = __COMPACT_TOP_PX__;
    window.__theaverBottomClear = __BOTTOM_PX__;
    window.__theaverCompactBottomClear = __COMPACT_BOTTOM_PX__;
    window.__theaverFlutterVh = __FLUTTER_VH__;
    window.__theaverForceExpanded = __FORCE_EXPANDED__;

    var collapseState = window.__theaverCollapseState;
    if (!collapseState) {
      collapseState = window.__theaverCollapseState = {
        collapsed: false,
        docLastTop: Math.max(0, window.scrollY || window.pageYOffset || document.documentElement.scrollTop || 0),
        accDy: 0,
        scrollerTops: typeof WeakMap === 'function' ? new WeakMap() : null
      };
    }

    function parseCssColor(raw) {
      if (!raw || typeof raw !== 'string') return null;
      var s = raw.trim().toLowerCase();
      if (!s || s === 'transparent' || s === 'none' || s === 'initial' || s === 'inherit') {
        return null;
      }
      if (s === 'white') return { r: 255, g: 255, b: 255, a: 1 };
      if (s === 'black') return { r: 0, g: 0, b: 0, a: 1 };
      if (s.charAt(0) === '#') {
        var hex = s.slice(1);
        if (hex.length === 3 || hex.length === 4) {
          var r3 = parseInt(hex.charAt(0) + hex.charAt(0), 16);
          var g3 = parseInt(hex.charAt(1) + hex.charAt(1), 16);
          var b3 = parseInt(hex.charAt(2) + hex.charAt(2), 16);
          var a3 = hex.length === 4 ? parseInt(hex.charAt(3) + hex.charAt(3), 16) / 255 : 1;
          if (!isNaN(r3) && !isNaN(g3) && !isNaN(b3) && !isNaN(a3) && a3 > 0.04) {
            return { r: r3, g: g3, b: b3, a: a3 };
          }
          return null;
        }
        if (hex.length === 6 || hex.length === 8) {
          var r6 = parseInt(hex.slice(0, 2), 16);
          var g6 = parseInt(hex.slice(2, 4), 16);
          var b6 = parseInt(hex.slice(4, 6), 16);
          var a6 = hex.length === 8 ? parseInt(hex.slice(6, 8), 16) / 255 : 1;
          if (!isNaN(r6) && !isNaN(g6) && !isNaN(b6) && !isNaN(a6) && a6 > 0.04) {
            return { r: r6, g: g6, b: b6, a: a6 };
          }
          return null;
        }
        return null;
      }
      var m = s.match(/rgba?\(\s*([\d.]+)\s*[,\s]\s*([\d.]+)\s*[,\s]\s*([\d.]+)(?:\s*[,/]\s*([\d.]+))?/i);
      if (!m) return null;
      var a = m[4] !== undefined ? parseFloat(m[4]) : 1.0;
      if (isNaN(a) || a <= 0.04) return null;
      return {
        r: Math.max(0, Math.min(255, Math.round(parseFloat(m[1]) || 0))),
        g: Math.max(0, Math.min(255, Math.round(parseFloat(m[2]) || 0))),
        b: Math.max(0, Math.min(255, Math.round(parseFloat(m[3]) || 0))),
        a: Math.max(0, Math.min(1, a))
      };
    }

    function blendOver(fg, bg) {
      if (!fg) return bg;
      var a = fg.a !== undefined ? fg.a : 1;
      if (a >= 0.99 || !bg) {
        return { r: fg.r, g: fg.g, b: fg.b, a: 1 };
      }
      return {
        r: Math.round(fg.r * a + bg.r * (1 - a)),
        g: Math.round(fg.g * a + bg.g * (1 - a)),
        b: Math.round(fg.b * a + bg.b * (1 - a)),
        a: 1
      };
    }

    function formatRgb(c) {
      if (!c) return 'rgb(255, 255, 255)';
      return 'rgb(' + Math.round(c.r) + ', ' + Math.round(c.g) + ', ' + Math.round(c.b) + ')';
    }

    function setImp(el, prop, val) {
      if (!el || !el.style) return;
      if (el.style.getPropertyValue(prop) !== val || el.style.getPropertyPriority(prop) !== 'important') {
        el.style.setProperty(prop, val, 'important');
      }
    }

    function parseNum(v) {
      var n = parseFloat(v);
      return isNaN(n) || !isFinite(n) ? null : n;
    }

    function parseTransformTy(rawTransform, refHeight) {
      if (!rawTransform || typeof rawTransform !== 'string') return 0;
      var s = rawTransform.trim();
      if (!s || s === 'none') return 0;
      if (s.indexOf('matrix3d(') === 0) {
        var parts3d = s.slice(9, -1).split(',');
        if (parts3d.length >= 14) {
          var m3y = parseFloat(parts3d[13]);
          return isNaN(m3y) ? 0 : m3y;
        }
        return 0;
      }
      if (s.indexOf('matrix(') === 0) {
        var parts2d = s.slice(7, -1).split(',');
        if (parts2d.length >= 6) {
          var m2y = parseFloat(parts2d[5]);
          return isNaN(m2y) ? 0 : m2y;
        }
        return 0;
      }
      var totalY = 0;
      var matched = false;
      var fnRe = /(translateY|translate3d|translate)\(\s*([^)]+)\)/gi;
      var m;
      while ((m = fnRe.exec(s)) !== null) {
        var fn = m[1].toLowerCase();
        var args = m[2].split(',');
        var yToken = null;
        if (fn === 'translatey') {
          yToken = args[0];
        } else if (args.length >= 2) {
          yToken = args[1];
        }
        if (!yToken) continue;
        yToken = yToken.trim();
        var num = parseFloat(yToken);
        if (isNaN(num) || !isFinite(num)) continue;
        matched = true;
        if (yToken.slice(-1) === '%') {
          totalY += (num / 100) * (refHeight || 0);
        } else {
          totalY += num;
        }
      }
      return matched ? totalY : 0;
    }

    function getTargetTranslateY(el, cs, refHeight) {
      try {
        if (el && typeof el.getAnimations === 'function') {
          var anims = el.getAnimations();
          for (var ai = anims.length - 1; ai >= 0; ai--) {
            var anim = anims[ai];
            if (!anim) continue;
            var ps = anim.playState;
            if (ps !== 'running' && ps !== 'pending') continue;
            var eff = anim.effect;
            if (!eff || typeof eff.getKeyframes !== 'function') continue;
            var kfs = eff.getKeyframes();
            if (!kfs || kfs.length === 0) continue;
            var lastKf = kfs[kfs.length - 1];
            if (lastKf && lastKf.transform !== undefined && lastKf.transform !== null) {
              return parseTransformTy(String(lastKf.transform), refHeight);
            }
          }
        }
      } catch (e) {}
      return parseTransformTy((cs && (cs.transform || cs.webkitTransform)) || 'none', refHeight);
    }

    function isPinnedElementHiding(el, cs, pos, effH) {
      if (pos === 'fixed' && cs.top !== 'auto') {
        var liveTop = parseNum(cs.top);
        if (liveTop !== null && liveTop < -8) return true;
      }
      if (getTargetTranslateY(el, cs, effH) < -12) return true;
      if (el.children && el.children.length === 1) {
        var tcEl = el.firstElementChild;
        if (tcEl && tcEl.tagName) {
          var tcCs = window.getComputedStyle(tcEl);
          if (tcCs.display !== 'none') {
            var tcH = Math.max(effH, tcEl.offsetHeight || 0);
            if (getTargetTranslateY(tcEl, tcCs, tcH) < -12) return true;
          }
        }
      }
      return false;
    }

    function applyPinnedOffset(el, cs, pos, origTopRaw, origTopNum, effH, activeTop) {
      var hiding = isPinnedElementHiding(el, cs, pos, effH);
      var wasInit = el.dataset.theaverHideInit === '1';
      var prevHiding = el.dataset.theaverIsHiding === '1';
      var prevTopOffset = el.dataset.theaverPrevTopOffset;
      var activeTopStr = String(activeTop);
      el.dataset.theaverHideInit = '1';
      el.dataset.theaverIsHiding = hiding ? '1' : '0';
      el.dataset.theaverPrevTopOffset = activeTopStr;

      if (wasInit && (prevHiding !== hiding || prevTopOffset !== activeTopStr)) {
        if (el.dataset.theaverOrigInlineTrans === undefined) {
          el.dataset.theaverOrigInlineTrans = el.style.getPropertyValue('transition') || '';
        }
        if (el.dataset.theaverAddedTrans === '1') {
          var savedTrans = el.dataset.theaverOrigInlineTrans || '';
          if (savedTrans) {
            el.style.setProperty('transition', savedTrans);
          } else {
            el.style.removeProperty('transition');
          }
          el.dataset.theaverAddedTrans = '0';
        }
        var liveTransCs = window.getComputedStyle(el);
        var siteTrans = liveTransCs.transition || '';
        var siteDur = parseFloat(liveTransCs.transitionDuration) || 0;
        if (
          siteDur > 0 &&
          siteTrans.indexOf('all') === -1 &&
          siteTrans.indexOf('translate') === -1
        ) {
          el.style.setProperty(
            'transition',
            siteTrans + ', translate 0.24s cubic-bezier(0.22, 1, 0.36, 1)'
          );
          el.dataset.theaverAddedTrans = '1';
        } else if (siteDur === 0 && prevTopOffset !== undefined && prevTopOffset !== activeTopStr) {
          var baseT = siteTrans && siteTrans !== 'none' ? (siteTrans + ', ') : '';
          el.style.setProperty(
            'transition',
            baseT +
              (pos === 'fixed'
                ? 'translate 0.22s cubic-bezier(0.22, 1, 0.36, 1)'
                : 'top 0.22s cubic-bezier(0.22, 1, 0.36, 1), translate 0.22s cubic-bezier(0.22, 1, 0.36, 1)')
          );
          el.dataset.theaverAddedTrans = '1';
        }
      }

      if (pos === 'fixed' && origTopRaw !== 'auto-top') {
        setImp(el, 'translate', hiding ? '0px 0px' : ('0px ' + activeTop + 'px'));
      } else {
        var nextTopVal = origTopRaw === 'auto-top' ? activeTop : Math.round((origTopNum || 0) + activeTop);
        setImp(el, 'top', nextTopVal + 'px');
        setImp(el, 'translate', hiding ? ('0px ' + (-activeTop) + 'px') : '0px 0px');
      }
    }

    function getEffectiveSize(el, rect) {
      var effW = Math.max(rect.width || 0, el.offsetWidth || 0);
      var effH = Math.max(rect.height || 0, el.offsetHeight || 0);
      if (effH >= 16 && effW >= 16) {
        return { w: effW, h: effH };
      }
      var stack = [];
      var c1 = el.children || [];
      for (var i = 0; i < c1.length; i++) {
        stack.push({ node: c1[i], depth: 1 });
      }
      while (stack.length > 0) {
        var cur = stack.shift();
        var child = cur.node;
        if (!child || !child.tagName) continue;
        var cCs = window.getComputedStyle(child);
        if (cCs.display === 'none') continue;
        var cRect = child.getBoundingClientRect();
        effW = Math.max(effW, cRect.width || 0, child.offsetWidth || 0);
        effH = Math.max(effH, cRect.height || 0, child.offsetHeight || 0);
        if (cur.depth < 2 && child.children) {
          for (var j = 0; j < child.children.length; j++) {
            stack.push({ node: child.children[j], depth: cur.depth + 1 });
          }
        }
      }
      return { w: effW, h: effH };
    }

    function collectCandidates(root, outList) {
      if (!root) return;
      var kids = root.children;
      if (!kids) return;
      for (var k = 0; k < kids.length; k++) {
        var node = kids[k];
        if (!node || !node.tagName) continue;
        var t = node.tagName;
        if (
          t === 'SCRIPT' ||
          t === 'STYLE' ||
          t === 'LINK' ||
          t === 'META' ||
          t === 'SVG' ||
          t === 'PATH'
        ) {
          continue;
        }
        outList.push(node);
        if (node.shadowRoot) {
          collectCandidates(node.shadowRoot, outList);
        }
        collectCandidates(node, outList);
      }
    }

    function replaceSafeAreaEnvStr(cssStr) {
      if (!cssStr) return cssStr;
      var out = cssStr;
      if (out.indexOf('safe-area-inset-bottom') !== -1) {
        out = out.replace(
          /(?:env|constant)\(\s*safe-area-inset-bottom(?:\s*,\s*([^()]+(?:\([^()]*\)[^()]*)*))?\s*\)/gi,
          function(_, fb) {
            return 'var(--theaver-safe-bottom, ' + (fb ? fb.trim() : '0px') + ')';
          }
        );
      }
      if (out.indexOf('safe-area-inset-top') !== -1) {
        out = out.replace(
          /(?:env|constant)\(\s*safe-area-inset-top(?:\s*,\s*([^()]+(?:\([^()]*\)[^()]*)*))?\s*\)/gi,
          function(_, fb) {
            return 'var(--theaver-top-obscured, ' + (fb ? fb.trim() : '0px') + ')';
          }
        );
      }
      return out;
    }

    function markSelectorEnvTop(selectorText) {
      if (!selectorText) return;
      try {
        var matched = document.querySelectorAll(selectorText);
        for (var i = 0; i < matched.length; i++) {
          if (matched[i] && matched[i].dataset) {
            matched[i].dataset.theaverUsesEnvTop = '1';
          }
        }
      } catch (e) {}
    }

    function markSelectorEnvBottom(selectorText) {
      if (!selectorText) return;
      try {
        var matched = document.querySelectorAll(selectorText);
        for (var i = 0; i < matched.length; i++) {
          if (matched[i] && matched[i].dataset) {
            matched[i].dataset.theaverUsesEnvBottom = '1';
          }
        }
      } catch (e) {}
    }

    function scanStyleRulesForEnv(ruleList) {
      if (!ruleList) return;
      for (var ri = 0; ri < ruleList.length; ri++) {
        var rule = ruleList[ri];
        if (!rule) continue;
        if (rule.style) {
          var csTxt = '';
          try {
            csTxt = rule.style.cssText || '';
          } catch (e) {
            csTxt = '';
          }
          if (csTxt.indexOf('safe-area-inset-bottom') !== -1 || csTxt.indexOf('safe-area-inset-top') !== -1) {
            if (csTxt.indexOf('safe-area-inset-top') !== -1 && rule.selectorText) {
              markSelectorEnvTop(rule.selectorText);
            }
            if (csTxt.indexOf('safe-area-inset-bottom') !== -1 && rule.selectorText) {
              markSelectorEnvBottom(rule.selectorText);
            }
            for (var pi = 0; pi < rule.style.length; pi++) {
              var prop = rule.style.item(pi);
              if (!prop) continue;
              var val = rule.style.getPropertyValue(prop);
              if (!val || (val.indexOf('safe-area-inset-bottom') === -1 && val.indexOf('safe-area-inset-top') === -1)) {
                continue;
              }
              var prio = rule.style.getPropertyPriority(prop);
              var repl = replaceSafeAreaEnvStr(val);
              if (repl !== val) {
                rule.style.setProperty(prop, repl, prio);
              }
            }
          } else {
            if (csTxt.indexOf('--theaver-top-obscured') !== -1 && rule.selectorText) {
              markSelectorEnvTop(rule.selectorText);
            }
            if (csTxt.indexOf('--theaver-safe-bottom') !== -1 && rule.selectorText) {
              markSelectorEnvBottom(rule.selectorText);
            }
          }
        } else if (rule.cssRules) {
          try {
            scanStyleRulesForEnv(rule.cssRules);
          } catch (e) {}
        }
      }
    }

    function polyfillSafeAreaEnv() {
      var styleNodes = document.querySelectorAll ? document.querySelectorAll('style') : [];
      for (var si = 0; si < styleNodes.length; si++) {
        var sNode = styleNodes[si];
        if (!sNode || sNode.id === '__theaver_browser_insets') continue;
        if (sNode.dataset && sNode.dataset.theaverEnvPolyfilled === '1') continue;
        var txt = sNode.textContent || '';
        if (txt.indexOf('safe-area-inset-bottom') !== -1 || txt.indexOf('safe-area-inset-top') !== -1) {
          var nextTxt = replaceSafeAreaEnvStr(txt);
          if (nextTxt !== txt) {
            sNode.textContent = nextTxt;
          }
        }
        if (sNode.dataset) {
          sNode.dataset.theaverEnvPolyfilled = '1';
        }
      }
      var sheets = document.styleSheets || [];
      for (var ji = 0; ji < sheets.length; ji++) {
        var sheet = sheets[ji];
        if (!sheet || sheet.__theaverEnvPolyfilled) continue;
        if (sheet.ownerNode && sheet.ownerNode.id === '__theaver_browser_insets') {
          sheet.__theaverEnvPolyfilled = true;
          continue;
        }
        try {
          var rules = sheet.cssRules;
          if (rules) {
            scanStyleRulesForEnv(rules);
          }
        } catch (e) {
          // Cross-origin CSSStyleSheet raises SecurityError; intentionally skipped.
        }
        sheet.__theaverEnvPolyfilled = true;
      }
    }

    function getScaledMetrics() {
      var vw = window.innerWidth || document.documentElement.clientWidth || 0;
      var vh = window.innerHeight || document.documentElement.clientHeight || 0;
      var fvh = Number(window.__theaverFlutterVh) || 0;
      var scale = (fvh > 0 && vh > fvh * 1.15) ? (vh / fvh) : 1.0;
      var tc = Math.round(Math.max(0, Number(window.__theaverTopClear) || 0) * scale);
      var ctc = Math.round(Math.max(0, Number(window.__theaverCompactTopClear) || 0) * scale);
      var bc = Math.round(Math.max(0, Number(window.__theaverBottomClear) || 0) * scale);
      var cbc = Math.round(Math.max(0, Number(window.__theaverCompactBottomClear) || 0) * scale);
      var isCol = !!(collapseState && collapseState.collapsed && !window.__theaverForceExpanded);
      return {
        vw: vw,
        vh: vh,
        tc: tc,
        ctc: ctc,
        bc: bc,
        cbc: cbc,
        collapsed: isCol,
        activeTop: isCol ? ctc : tc,
        activeBottom: isCol ? cbc : bc
      };
    }

    function applyCssInsetVariables(m) {
      var rootStyle = document.documentElement.style;
      rootStyle.setProperty('--theaver-top-obscured', m.activeTop + 'px');
      rootStyle.setProperty('--theaver-safe-bottom', m.activeBottom + 'px');
      rootStyle.setProperty('--theaver-header-clearance', m.tc + 'px');
      rootStyle.setProperty('--theaver-bottom-clearance', m.bc + 'px');
      rootStyle.setProperty('--tg-safe-area-inset-top', m.activeTop + 'px');
      rootStyle.setProperty('--tg-safe-area-inset-bottom', m.activeBottom + 'px');

      var st = document.getElementById('__theaver_browser_insets');
      if (!st && document.head) {
        st = document.createElement('style');
        st.id = '__theaver_browser_insets';
        document.head.appendChild(st);
      }
      var insetCss =
        ':root { ' +
          '--theaver-top-obscured: ' + m.activeTop + 'px; ' +
          '--theaver-safe-bottom: ' + m.activeBottom + 'px; ' +
          '--theaver-header-clearance: ' + m.tc + 'px; ' +
          '--theaver-bottom-clearance: ' + m.bc + 'px; ' +
          '--tg-safe-area-inset-top: ' + m.activeTop + 'px; ' +
          '--tg-safe-area-inset-bottom: ' + m.activeBottom + 'px; ' +
        '} ' +
        'html { scroll-padding-top: var(--theaver-top-obscured) !important; scroll-padding-bottom: var(--theaver-safe-bottom) !important; }';
      if (st && st.textContent !== insetCss) {
        st.textContent = insetCss;
      }
    }

    function sampleBandColor(vw, yPx, fallbackBg) {
      var result = fallbackBg;
      var hitWide = false;
      if (typeof document.elementsFromPoint === 'function' && vw > 0) {
        try {
          var stack = document.elementsFromPoint(Math.round(vw * 0.5), yPx) || [];
          var layers = [];
          for (var si = 0; si < stack.length; si++) {
            var el = stack[si];
            if (!el || !el.tagName) continue;
            var tag = el.tagName;
            if (tag === 'HTML' || tag === 'SCRIPT' || tag === 'STYLE') continue;
            var r = el.getBoundingClientRect();
            if (r.width >= vw * 0.65 && r.height >= 28) {
              var cs = window.getComputedStyle(el);
              var c = parseCssColor(cs.backgroundColor);
              if (c) {
                layers.push(c);
                hitWide = true;
                if (c.a >= 0.96) break;
              }
            }
          }
          for (var li = layers.length - 1; li >= 0; li--) {
            result = blendOver(layers[li], result);
          }
        } catch (e) {}
      }
      return { color: result, hitWide: hitWide };
    }

    function computePageMeta(m) {
      if (!document.body) return null;
      var htmlCs = window.getComputedStyle(document.documentElement);
      var bodyCs = window.getComputedStyle(document.body);
      var scheme = (htmlCs.colorScheme || '').toLowerCase();
      var baseTheme = scheme.indexOf('dark') !== -1 && scheme.indexOf('light') === -1
        ? { r: 18, g: 18, b: 18, a: 1 }
        : { r: 255, g: 255, b: 255, a: 1 };
      var canvasBg = blendOver(parseCssColor(htmlCs.backgroundColor), baseTheme);
      canvasBg = blendOver(parseCssColor(bodyCs.backgroundColor), canvasBg);

      var vw = m.vw || window.innerWidth || document.documentElement.clientWidth || 0;
      var vh = m.vh || window.innerHeight || document.documentElement.clientHeight || 0;
      var scrollY = Math.max(0, window.scrollY || window.pageYOffset || document.documentElement.scrollTop || 0);

      var topProbe = sampleBandColor(vw, 6, canvasBg);
      var topColorObj = topProbe.color;
      if (!topProbe.hitWide && scrollY <= 8) {
        var matchedMeta = false;
        if (document.querySelectorAll) {
          try {
            var metas = document.querySelectorAll('meta[name="theme-color"]');
            for (var mi = 0; mi < metas.length; mi++) {
              var metaEl = metas[mi];
              var mediaAttr = metaEl.getAttribute('media');
              if (mediaAttr && typeof window.matchMedia === 'function') {
                if (!window.matchMedia(mediaAttr).matches) continue;
              }
              var mc = parseCssColor(metaEl.getAttribute('content'));
              if (mc) {
                topColorObj = blendOver(mc, canvasBg);
                matchedMeta = true;
                break;
              }
            }
          } catch (e) {}
        }
        if (!matchedMeta && vh > 16) {
          var navProbeY = Math.min(vh - 6, Math.max(8, (m.activeTop || 0) + 8));
          var navProbe = sampleBandColor(vw, navProbeY, canvasBg);
          if (navProbe.hitWide) {
            topColorObj = navProbe.color;
          }
        }
      }
      var bottomProbe = vh > 12 ? sampleBandColor(vw, Math.max(0, vh - 6), canvasBg) : { color: canvasBg };
      var lum = (0.2126 * topColorObj.r + 0.7152 * topColorObj.g + 0.0722 * topColorObj.b) / 255;

      return JSON.stringify({
        collapsed: !!m.collapsed,
        topIsDark: lum <= 0.55,
        topColor: formatRgb(topColorObj),
        bottomColor: formatRgb(bottomProbe.color),
        canvasColor: formatRgb(canvasBg)
      });
    }

    function emitPageMeta(m) {
      var metaPayload = computePageMeta(m || getScaledMetrics());
      if (!metaPayload) return null;
      if (
        window.TheaverBrowserTheme &&
        typeof window.TheaverBrowserTheme.postMessage === 'function' &&
        window.__theaverLastPageMeta !== metaPayload
      ) {
        window.__theaverLastPageMeta = metaPayload;
        window.TheaverBrowserTheme.postMessage(metaPayload);
      }
      return metaPayload;
    }

    function usesEnvTopVar(el) {
      if (!el || !el.dataset) return false;
      if (el.dataset.theaverUsesEnvTop === '1') return true;
      var inlineStyle = (el.getAttribute && el.getAttribute('style')) || '';
      if (inlineStyle.indexOf('--theaver-top-obscured') !== -1 || inlineStyle.indexOf('safe-area-inset-top') !== -1) {
        return true;
      }
      if (el.querySelector && el.querySelector('[data-theaver-uses-env-top="1"]')) {
        return true;
      }
      return false;
    }

    function usesEnvBottomVar(el) {
      if (!el || !el.dataset) return false;
      if (el.dataset.theaverUsesEnvBottom === '1') return true;
      var inlineStyle = (el.getAttribute && el.getAttribute('style')) || '';
      if (inlineStyle.indexOf('--theaver-safe-bottom') !== -1 || inlineStyle.indexOf('safe-area-inset-bottom') !== -1) {
        return true;
      }
      if (el.querySelector && el.querySelector('[data-theaver-uses-env-bottom="1"]')) {
        return true;
      }
      return false;
    }

    function hasTrackedTopAncestor(el) {
      var cur = el ? (el.parentElement || (el.getRootNode && el.getRootNode().host) || null) : null;
      while (cur && cur.nodeType === 1 && cur !== document.body && cur !== document.documentElement) {
        if (
          cur.dataset &&
          (cur.dataset.theaverSafeRole === 'top-pinned' ||
            cur.dataset.theaverSafeRole === 'top-sheet' ||
            cur.dataset.theaverPrimaryScroller === '1')
        ) {
          return true;
        }
        cur = cur.parentElement || (cur.getRootNode && cur.getRootNode().host) || null;
      }
      return false;
    }

    function clearTrackedPinnedElement(el) {
      if (!el || !el.dataset) return;
      if (el.dataset.theaverOrigTop && el.dataset.theaverOrigTop !== 'auto' && el.dataset.theaverOrigTop !== 'auto-top') {
        setImp(el, 'top', el.dataset.theaverOrigTop + 'px');
      } else if (el.dataset.theaverOrigTop === 'auto-top') {
        el.style.removeProperty('top');
      }
      el.style.removeProperty('translate');
      delete el.dataset.theaverSafeRole;
      delete el.dataset.theaverHideInit;
      delete el.dataset.theaverIsHiding;
      delete el.dataset.theaverPrevTopOffset;
    }

    function clearTrackedSheetElement(sheetEl) {
      if (!sheetEl || !sheetEl.dataset) return;
      if (sheetEl.dataset.theaverAppliedSheetPt === '1') {
        var origPt = parseFloat(sheetEl.dataset.theaverSheetOrigPt) || 0;
        setImp(sheetEl, 'padding-top', Math.round(origPt) + 'px');
        delete sheetEl.dataset.theaverAppliedSheetPt;
      }
      if (sheetEl.dataset.theaverAppliedSheetPb === '1') {
        var origPb = parseFloat(sheetEl.dataset.theaverSheetOrigPb) || 0;
        setImp(sheetEl, 'padding-bottom', Math.round(origPb) + 'px');
        delete sheetEl.dataset.theaverAppliedSheetPb;
      }
      var kids = sheetEl.children || [];
      for (var ci = 0; ci < kids.length; ci++) {
        var kEl = kids[ci];
        if (kEl && kEl.dataset && kEl.dataset.theaverSheetAbsChild === '1') {
          var origCTop = parseFloat(kEl.dataset.theaverOrigAbsTop) || 0;
          setImp(kEl, 'top', Math.round(origCTop) + 'px');
          delete kEl.dataset.theaverSheetAbsChild;
        }
      }
      delete sheetEl.dataset.theaverSafeRole;
    }

    function applyTopSheetInset(sheetEl, activeTop, activeBottom) {
      if (!sheetEl || !sheetEl.dataset) return;
      var sCs = window.getComputedStyle(sheetEl);
      if (sCs.display === 'none') return;
      if (sheetEl.dataset.theaverSheetOrigRecorded !== '1') {
        sheetEl.dataset.theaverSheetOrigRecorded = '1';
        sheetEl.dataset.theaverSheetOrigPt = String(parseFloat(sCs.paddingTop) || 0);
        sheetEl.dataset.theaverSheetOrigPb = String(parseFloat(sCs.paddingBottom) || 0);
      }
      sheetEl.dataset.theaverSafeRole = 'top-sheet';
      var origPt = parseFloat(sheetEl.dataset.theaverSheetOrigPt) || 0;
      var origPb = parseFloat(sheetEl.dataset.theaverSheetOrigPb) || 0;
      setImp(sheetEl, 'box-sizing', 'border-box');
      if (origPt <= 160) {
        sheetEl.dataset.theaverAppliedSheetPt = '1';
        setImp(sheetEl, 'padding-top', Math.round(origPt + activeTop) + 'px');
      } else {
        setImp(sheetEl, 'padding-top', Math.round(Math.max(origPt, activeTop)) + 'px');
      }
      if (!usesEnvBottomVar(sheetEl) && origPb < activeBottom * 0.6) {
        sheetEl.dataset.theaverAppliedSheetPb = '1';
        setImp(sheetEl, 'padding-bottom', Math.round(origPb + activeBottom) + 'px');
      }
      var kids = sheetEl.children || [];
      for (var ci = 0; ci < kids.length; ci++) {
        var cEl = kids[ci];
        if (!cEl || !cEl.tagName) continue;
        var cCs = window.getComputedStyle(cEl);
        if (cCs.display === 'none' || cCs.position !== 'absolute') continue;
        if (usesEnvTopVar(cEl)) continue;
        if (cEl.dataset.theaverOrigAbsRecorded !== '1') {
          var cTop = parseNum(cCs.top);
          if (cTop === null || cTop < -2 || cTop > 36) continue;
          var cRect = cEl.getBoundingClientRect();
          var cSz = getEffectiveSize(cEl, cRect);
          if (cSz.w <= 0 || cSz.h <= 0 || cSz.w > 96 || cSz.h > 64) continue;
          cEl.dataset.theaverOrigAbsRecorded = '1';
          cEl.dataset.theaverOrigAbsTop = String(cTop);
        }
        cEl.dataset.theaverSheetAbsChild = '1';
        var baseAbsTop = parseFloat(cEl.dataset.theaverOrigAbsTop) || 0;
        setImp(cEl, 'top', Math.round(baseAbsTop + activeTop) + 'px');
      }
    }

    function collectSheetPanels(rootEl, vw, vh) {
      var panels = [];
      if (!rootEl || !rootEl.children) return panels;
      var queue = [];
      var rootKids = rootEl.children || [];
      for (var i = 0; i < rootKids.length; i++) {
        queue.push({ node: rootKids[i], depth: 1 });
      }
      while (queue.length > 0) {
        var cur = queue.shift();
        var kEl = cur.node;
        if (!kEl || !kEl.tagName) continue;
        var tag = kEl.tagName;
        if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'SVG' || tag === 'PATH') continue;
        var kCs = window.getComputedStyle(kEl);
        if (kCs.display === 'none') continue;
        if (usesEnvTopVar(kEl) || hasTrackedTopAncestor(kEl)) continue;
        var kRect = kEl.getBoundingClientRect();
        var kEff = getEffectiveSize(kEl, kRect);
        if (
          kRect.top >= -4 &&
          kRect.top <= 24 &&
          kEff.h >= vh * 0.50 &&
          kEff.w >= 140 &&
          kEl.children &&
          kEl.children.length > 0
        ) {
          var kBg = parseCssColor(kCs.backgroundColor);
          if (kBg && kBg.a >= 0.72) {
            panels.push(kEl);
            continue;
          }
          var pushedSub = false;
          if (cur.depth < 3 && kEl.children) {
            for (var j = 0; j < kEl.children.length; j++) {
              var subEl = kEl.children[j];
              if (!subEl || !subEl.tagName) continue;
              var subCs = window.getComputedStyle(subEl);
              if (subCs.display === 'none') continue;
              var subRect = subEl.getBoundingClientRect();
              var subEff = getEffectiveSize(subEl, subRect);
              if (
                subRect.top >= -4 &&
                subRect.top <= 24 &&
                subEff.h >= vh * 0.50 &&
                subEff.w >= 140 &&
                subEl.children &&
                subEl.children.length > 0
              ) {
                queue.push({ node: subEl, depth: cur.depth + 1 });
                pushedSub = true;
              }
            }
          }
          if (!pushedSub) {
            panels.push(kEl);
          }
        }
      }
      return panels;
    }

    function restoreRootTopInset(docEl) {
      if (!docEl || !docEl.dataset) return;
      if (docEl.dataset.theaverAppliedTopMargin === '1') {
        var origMt = parseFloat(docEl.dataset.theaverBaseMt) || 0;
        setImp(docEl, 'margin-top', Math.round(origMt) + 'px');
        delete docEl.dataset.theaverAppliedTopMargin;
      }
      if (docEl.dataset.theaverSetRel === '1') {
        docEl.style.removeProperty('position');
        delete docEl.dataset.theaverSetRel;
      }
    }

    window.__theaverSyncSafeZones = function(
      rawTopClear,
      rawBottomClear,
      rawFlutterVh,
      rawCompactTopClear,
      rawCompactBottomClear,
      rawForceExpanded
    ) {
      if (window.__theaverApplyingSafeZones) return null;
      window.__theaverApplyingSafeZones = true;
      try {
        if (!document || !document.documentElement) return null;
        if (rawTopClear !== undefined) window.__theaverTopClear = rawTopClear;
        if (rawBottomClear !== undefined) window.__theaverBottomClear = rawBottomClear;
        if (rawFlutterVh !== undefined) window.__theaverFlutterVh = rawFlutterVh;
        if (rawCompactTopClear !== undefined) window.__theaverCompactTopClear = rawCompactTopClear;
        if (rawCompactBottomClear !== undefined) window.__theaverCompactBottomClear = rawCompactBottomClear;
        if (rawForceExpanded !== undefined) window.__theaverForceExpanded = !!rawForceExpanded;
        if (window.__theaverForceExpanded && collapseState) {
          collapseState.collapsed = false;
          collapseState.accDy = 0;
        }

        var vw = window.innerWidth || document.documentElement.clientWidth || 0;
        var vh = window.innerHeight || document.documentElement.clientHeight || 0;
        if (!document.body || vw <= 0 || vh <= 0) return null;

        var m = getScaledMetrics();
        var hasTopInset = (m.tc > 0 || m.ctc > 0);
        var docEl = document.documentElement;
        var body = document.body;
        var htmlCs = window.getComputedStyle(docEl);
        var bodyCs = window.getComputedStyle(body);

        if (docEl.dataset.theaverBaseMt === undefined) {
          docEl.dataset.theaverBaseMt = String(parseFloat(htmlCs.marginTop) || 0);
          docEl.dataset.theaverOrigPos = htmlCs.position || 'static';
        }
        if (body.dataset.theaverBasePt === undefined) {
          body.dataset.theaverBasePt = String(parseFloat(bodyCs.paddingTop) || 0);
          body.dataset.theaverBasePb = String(parseFloat(bodyCs.paddingBottom) || 0);
        }

        var isLockedViewport =
          (htmlCs.overflowY === 'hidden' || bodyCs.overflowY === 'hidden') &&
          docEl.scrollHeight <= vh + 8;

        var all = [];
        collectCandidates(body, all);

        if (isLockedViewport) {
          restoreRootTopInset(docEl);
          for (var li = 0; li < all.length; li++) {
            var lel = all[li];
            if (!lel || !lel.tagName) continue;
            var lcs = window.getComputedStyle(lel);
            if (lcs.display === 'none') continue;
            var loy = lcs.overflowY;
            if (loy !== 'auto' && loy !== 'scroll' && loy !== 'overlay') continue;
            var lrect = lel.getBoundingClientRect();
            var lsz = getEffectiveSize(lel, lrect);
            if (lsz.w >= vw * 0.75 && lsz.h >= vh * 0.70) {
              if (lel.dataset.theaverScrollContainerPt === undefined) {
                lel.dataset.theaverScrollContainerPt = String(parseFloat(lcs.paddingTop) || 0);
                lel.dataset.theaverScrollContainerPb = String(parseFloat(lcs.paddingBottom) || 0);
              }
              lel.dataset.theaverPrimaryScroller = '1';
              var lpt = parseFloat(lel.dataset.theaverScrollContainerPt) || 0;
              var lpb = parseFloat(lel.dataset.theaverScrollContainerPb) || 0;
              setImp(lel, 'box-sizing', 'border-box');
              if (hasTopInset) {
                lel.dataset.theaverAppliedTopPad = '1';
                setImp(lel, 'padding-top', Math.round(lpt <= 180 ? lpt + m.tc : Math.max(lpt, m.tc)) + 'px');
              } else if (lel.dataset.theaverAppliedTopPad === '1') {
                setImp(lel, 'padding-top', Math.round(lpt) + 'px');
                delete lel.dataset.theaverAppliedTopPad;
              }
              setImp(lel, 'padding-bottom', Math.round(lpb <= 180 ? lpb + m.bc : Math.max(lpb, m.bc)) + 'px');
              break;
            }
          }
        } else {
          var baseMt = parseFloat(docEl.dataset.theaverBaseMt) || 0;
          var basePb = parseFloat(body.dataset.theaverBasePb) || 0;
          var nextPb = basePb <= 180 ? basePb + m.bc : Math.max(basePb, m.bc);
          setImp(body, 'box-sizing', 'border-box');
          if (body.dataset.theaverAppliedTopPad === '1') {
            var basePt = parseFloat(body.dataset.theaverBasePt) || 0;
            setImp(body, 'padding-top', Math.round(basePt) + 'px');
            delete body.dataset.theaverAppliedTopPad;
          }
          if (hasTopInset) {
            if (docEl.dataset.theaverOrigPos === 'static' || htmlCs.position === 'static') {
              docEl.dataset.theaverSetRel = '1';
              setImp(docEl, 'position', 'relative');
            }
            var nextMt = baseMt <= 180 ? baseMt + m.tc : Math.max(baseMt, m.tc);
            docEl.dataset.theaverAppliedTopMargin = '1';
            setImp(docEl, 'margin-top', Math.round(nextMt) + 'px');
          } else {
            restoreRootTopInset(docEl);
          }
          setImp(body, 'padding-bottom', Math.round(nextPb) + 'px');

          var htmlColRaw = parseCssColor(htmlCs.backgroundColor);
          var bodyColRaw = parseCssColor(bodyCs.backgroundColor);
          if (!htmlColRaw && !bodyColRaw && body.dataset.theaverMirroredBg !== '1') {
            var kids = body.children || [];
            for (var bk = 0; bk < kids.length; bk++) {
              var kEl = kids[bk];
              if (!kEl || !kEl.tagName) continue;
              if (kEl.tagName === 'SCRIPT' || kEl.tagName === 'STYLE') continue;
              var kCs = window.getComputedStyle(kEl);
              if (kCs.display === 'none') continue;
              var kRect = kEl.getBoundingClientRect();
              if (kRect.width >= vw * 0.90) {
                var kBg = parseCssColor(kCs.backgroundColor);
                if (kBg && kBg.a > 0.75) {
                  body.dataset.theaverMirroredBg = '1';
                  setImp(body, 'background-color', kCs.backgroundColor);
                  setImp(docEl, 'background-color', kCs.backgroundColor);
                  break;
                }
              }
            }
          }
        }

        applyCssInsetVariables(m);
        polyfillSafeAreaEnv();

        if (!hasTopInset) {
          var prevPinnedList = window.__theaverTrackedTopPinned || [];
          for (var rp = 0; rp < prevPinnedList.length; rp++) {
            clearTrackedPinnedElement(prevPinnedList[rp]);
          }
          if (document.querySelectorAll) {
            var leftoverPinned = document.querySelectorAll('[data-theaver-safe-role="top-pinned"]');
            for (var lp = 0; lp < leftoverPinned.length; lp++) {
              clearTrackedPinnedElement(leftoverPinned[lp]);
            }
            var leftoverSheets = document.querySelectorAll('[data-theaver-safe-role="top-sheet"]');
            for (var ls = 0; ls < leftoverSheets.length; ls++) {
              clearTrackedSheetElement(leftoverSheets[ls]);
            }
          }
          window.__theaverTrackedTopPinned = [];
          window.__theaverTrackedTopSheets = [];
        } else {
          var trackedPinned = [];
          var trackedSheets = [];
          for (var i = 0; i < all.length; i++) {
            var el = all[i];
            if (!el || !el.tagName) continue;
            var tName = el.tagName;
            if (tName === 'CANVAS' || tName === 'VIDEO' || tName === 'IMG' || tName === 'PICTURE') continue;
            var cs = window.getComputedStyle(el);
            if (cs.display === 'none') continue;
            var pos = cs.position;
            if (pos !== 'fixed' && pos !== 'sticky') continue;
            var opVal = parseFloat(cs.opacity);
            if (!isNaN(opVal) && opVal === 0 && cs.pointerEvents === 'none') continue;
            if (cs.pointerEvents === 'none' && (!el.children || el.children.length === 0)) continue;
            var zNum = parseInt(cs.zIndex, 10);
            if (!isNaN(zNum) && zNum < 0) continue;
            if (usesEnvTopVar(el) || hasTrackedTopAncestor(el)) continue;

            var rect = el.getBoundingClientRect();
            var eff = getEffectiveSize(el, rect);
            if (eff.w < 24 || eff.h < 20) continue;

            if (el.dataset.theaverOrigRecorded !== '1') {
              var inlineTopNum = parseNum(el.style.top || '');
              if (inlineTopNum !== null && inlineTopNum < -12) continue;

              var origTopStr = 'auto';
              if (cs.top !== 'auto') {
                var topVal = parseNum(cs.top);
                if (topVal !== null) origTopStr = String(topVal);
              } else if (pos === 'fixed' && cs.bottom === 'auto' && rect.top >= -2 && rect.top <= 20) {
                origTopStr = 'auto-top';
              }

              var origBottomStr = 'auto';
              if (cs.bottom !== 'auto') {
                var botVal = parseNum(cs.bottom);
                if (botVal !== null) origBottomStr = String(botVal);
              }

              var tNum0 = origTopStr === 'auto' || origTopStr === 'auto-top' ? null : parseNum(origTopStr);
              if (origTopStr !== 'auto-top' && (tNum0 === null || tNum0 < -2 || tNum0 > 20)) continue;

              el.dataset.theaverOrigRecorded = '1';
              el.dataset.theaverOrigTop = origTopStr;
              el.dataset.theaverOrigBottom = origBottomStr;
              el.dataset.theaverPos = pos;
            }

            var recPos = el.dataset.theaverPos || pos;
            var recTopRaw = el.dataset.theaverOrigTop || 'auto';
            var recBottomRaw = el.dataset.theaverOrigBottom || 'auto';
            var recTopNum = recTopRaw === 'auto' || recTopRaw === 'auto-top' ? null : parseNum(recTopRaw);
            var recBotNum = recBottomRaw === 'auto' ? null : parseNum(recBottomRaw);

            if (recBotNum === null && eff.h < vh * 0.55 && trackedPinned.length < 10) {
              el.dataset.theaverSafeRole = 'top-pinned';
              trackedPinned.push(el);
              applyPinnedOffset(el, cs, recPos, recTopRaw, recTopNum, eff.h, m.activeTop);
            } else if (
              recPos === 'fixed' &&
              (recBotNum !== null || eff.h >= vh * 0.55) &&
              eff.w >= 140 &&
              el.children &&
              el.children.length > 0 &&
              !(el.querySelector && el.querySelector('[data-theaver-primary-scroller="1"]'))
            ) {
              var elBg = parseCssColor(cs.backgroundColor);
              var isWrapper = !elBg || elBg.a < 0.72;
              if (isWrapper) {
                var innerPanels = collectSheetPanels(el, vw, vh);
                if (innerPanels.length > 0) {
                  for (var ip = 0; ip < innerPanels.length; ip++) {
                    if (trackedSheets.length >= 6) break;
                    applyTopSheetInset(innerPanels[ip], m.activeTop, m.activeBottom);
                    trackedSheets.push(innerPanels[ip]);
                  }
                } else if (trackedSheets.length < 6) {
                  applyTopSheetInset(el, m.activeTop, m.activeBottom);
                  trackedSheets.push(el);
                }
              } else if (trackedSheets.length < 6) {
                applyTopSheetInset(el, m.activeTop, m.activeBottom);
                trackedSheets.push(el);
              }
            }
          }
          window.__theaverTrackedTopPinned = trackedPinned;
          window.__theaverTrackedTopSheets = trackedSheets;
        }

        return emitPageMeta(m);
      } catch (e) {
        return null;
      } finally {
        if (window.__theaverSafeZoneObs && typeof window.__theaverSafeZoneObs.takeRecords === 'function') {
          window.__theaverSafeZoneObs.takeRecords();
        }
        window.__theaverApplyingSafeZones = false;
      }
    };

    window.__theaverRefreshTrackedPinned = function() {
      if (window.__theaverApplyingSafeZones) return;
      window.__theaverApplyingSafeZones = true;
      try {
        var m = getScaledMetrics();
        var hasTopInset = (m.tc > 0 || m.ctc > 0);
        var pinnedNodes = document && document.querySelectorAll
          ? document.querySelectorAll('[data-theaver-safe-role="top-pinned"]')
          : (window.__theaverTrackedTopPinned || []);
        var sheetNodes = document && document.querySelectorAll
          ? document.querySelectorAll('[data-theaver-safe-role="top-sheet"]')
          : (window.__theaverTrackedTopSheets || []);

        if (!hasTopInset) {
          for (var cp = 0; cp < pinnedNodes.length; cp++) {
            clearTrackedPinnedElement(pinnedNodes[cp]);
          }
          for (var csIdx = 0; csIdx < sheetNodes.length; csIdx++) {
            clearTrackedSheetElement(sheetNodes[csIdx]);
          }
          window.__theaverTrackedTopPinned = [];
          window.__theaverTrackedTopSheets = [];
          return;
        }

        for (var pi = 0; pi < pinnedNodes.length; pi++) {
          var pEl = pinnedNodes[pi];
          if (!pEl || !pEl.isConnected) continue;
          var cs = window.getComputedStyle(pEl);
          if (cs.display === 'none') continue;
          var pos = pEl.dataset.theaverPos || cs.position;
          var origTopRaw = pEl.dataset.theaverOrigTop || 'auto';
          var origTopNum = origTopRaw === 'auto' || origTopRaw === 'auto-top' ? null : parseNum(origTopRaw);
          var eff = getEffectiveSize(pEl, pEl.getBoundingClientRect());
          if (eff.h > 0) {
            applyPinnedOffset(pEl, cs, pos, origTopRaw, origTopNum, eff.h, m.activeTop);
          }
        }

        for (var si = 0; si < sheetNodes.length; si++) {
          var sEl = sheetNodes[si];
          if (!sEl || !sEl.isConnected) continue;
          applyTopSheetInset(sEl, m.activeTop, m.activeBottom);
        }
      } catch (e) {
      } finally {
        if (window.__theaverSafeZoneObs && typeof window.__theaverSafeZoneObs.takeRecords === 'function') {
          window.__theaverSafeZoneObs.takeRecords();
        }
        window.__theaverApplyingSafeZones = false;
      }
    };

    function setCollapsed(nextFlag) {
      var effective = window.__theaverForceExpanded ? false : !!nextFlag;
      if (!!collapseState.collapsed === effective) return false;
      collapseState.collapsed = effective;
      var m = getScaledMetrics();
      window.__theaverApplyingSafeZones = true;
      try {
        applyCssInsetVariables(m);
      } finally {
        if (window.__theaverSafeZoneObs && typeof window.__theaverSafeZoneObs.takeRecords === 'function') {
          window.__theaverSafeZoneObs.takeRecords();
        }
        window.__theaverApplyingSafeZones = false;
      }
      window.__theaverRefreshTrackedPinned();
      emitPageMeta(m);
      return true;
    }

    window.__theaverSetCollapsedFromHost = function(flag) {
      collapseState.accDy = 0;
      return setCollapsed(!!flag);
    };

    function onScrollCollapseCheck(ev) {
      if (window.__theaverApplyingSafeZones) return;
      var vw = window.innerWidth || document.documentElement.clientWidth || 0;
      var vh = window.innerHeight || document.documentElement.clientHeight || 0;
      if (vw <= 0 || vh <= 0) return;

      var target = ev ? ev.target : document;
      var isDocTarget = !target || target === window || target === document || target === document.documentElement || target === document.body;
      var curTop = 0;
      var prevTop = 0;
      var maxScroll = 0;

      if (isDocTarget) {
        curTop = Math.max(0, window.scrollY || window.pageYOffset || document.documentElement.scrollTop || 0);
        maxScroll = Math.max(0, (document.documentElement.scrollHeight || 0) - vh);
        prevTop = collapseState.docLastTop || 0;
        collapseState.docLastTop = curTop;
      } else if (
        target.nodeType === 1 &&
        target.clientHeight >= vh * 0.45 &&
        target.clientWidth >= vw * 0.60 &&
        target.scrollHeight > target.clientHeight + 40
      ) {
        curTop = Math.max(0, target.scrollTop || 0);
        maxScroll = Math.max(0, target.scrollHeight - target.clientHeight);
        if (collapseState.scrollerTops) {
          prevTop = collapseState.scrollerTops.has(target) ? collapseState.scrollerTops.get(target) : curTop;
          collapseState.scrollerTops.set(target, curTop);
        } else {
          prevTop = parseNum(target.dataset && target.dataset.theaverPrevScrollTop) || curTop;
          if (target.dataset) target.dataset.theaverPrevScrollTop = String(curTop);
        }
      } else {
        return;
      }

      if (maxScroll > 0 && curTop > maxScroll + 2) return;

      if (window.__theaverForceExpanded || curTop <= 20) {
        collapseState.accDy = 0;
        setCollapsed(false);
        return;
      }

      var dy = curTop - prevTop;
      if (Math.abs(dy) < 1.5) return;
      if ((dy > 0 && collapseState.accDy < 0) || (dy < 0 && collapseState.accDy > 0)) {
        collapseState.accDy = 0;
      }
      collapseState.accDy += dy;

      if (!collapseState.collapsed && curTop > 36 && collapseState.accDy >= 22) {
        collapseState.accDy = 0;
        setCollapsed(true);
      } else if (collapseState.collapsed && collapseState.accDy <= -18) {
        collapseState.accDy = 0;
        setCollapsed(false);
      }
    }

    var initialMeta = window.__theaverSyncSafeZones(
      __TOP_PX__,
      __BOTTOM_PX__,
      __FLUTTER_VH__,
      __COMPACT_TOP_PX__,
      __COMPACT_BOTTOM_PX__,
      __FORCE_EXPANDED__
    );

    if (!window.__theaverSafeZoneObserverInstalled) {
      window.__theaverSafeZoneObserverInstalled = true;
      var syncTimer = null;
      var pinnedRaf = 0;
      var rafFn = typeof window.requestAnimationFrame === 'function'
        ? function(cb) { return window.requestAnimationFrame(cb); }
        : function(cb) { return setTimeout(cb, 16); };

      var schedulePinnedRefresh = function() {
        if (window.__theaverApplyingSafeZones || pinnedRaf) return;
        pinnedRaf = rafFn(function() {
          pinnedRaf = 0;
          if (typeof window.__theaverRefreshTrackedPinned === 'function') {
            window.__theaverRefreshTrackedPinned();
          }
        });
      };

      var scheduleSync = function() {
        if (window.__theaverApplyingSafeZones || syncTimer) return;
        syncTimer = setTimeout(function() {
          syncTimer = null;
          if (typeof window.__theaverSyncSafeZones === 'function') {
            window.__theaverSyncSafeZones(
              window.__theaverTopClear || 0,
              window.__theaverBottomClear || 0,
              window.__theaverFlutterVh || 0,
              window.__theaverCompactTopClear || 0,
              window.__theaverCompactBottomClear || 0,
              !!window.__theaverForceExpanded
            );
          }
        }, 160);
      };

      var isTrackedOrDescendant = function(target) {
        var cur = target;
        var steps = 0;
        while (cur && cur.nodeType === 1 && steps < 5) {
          if (
            cur.dataset &&
            (cur.dataset.theaverSafeRole === 'top-pinned' ||
              cur.dataset.theaverSafeRole === 'top-sheet')
          ) {
            return true;
          }
          cur = cur.parentElement || (cur.getRootNode && cur.getRootNode().host) || null;
          steps++;
        }
        return false;
      };

      if (typeof MutationObserver === 'function') {
        var onDomMutate = function(mutations) {
          if (window.__theaverApplyingSafeZones) return;
          var hitTracked = false;
          if (mutations && mutations.length) {
            for (var mi = 0; mi < mutations.length; mi++) {
              var mut = mutations[mi];
              if (mut && mut.type === 'attributes' && isTrackedOrDescendant(mut.target)) {
                hitTracked = true;
                break;
              }
            }
          }
          if (hitTracked) {
            schedulePinnedRefresh();
          }
          scheduleSync();
        };
        var obs = new MutationObserver(onDomMutate);
        window.__theaverSafeZoneObs = obs;
        obs.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['class', 'style']
        });
      }

      var onTransitionEvt = function(ev) {
        if (window.__theaverApplyingSafeZones) return;
        if (ev && isTrackedOrDescendant(ev.target)) {
          schedulePinnedRefresh();
        }
      };
      var onScrollEvt = function(ev) {
        onScrollCollapseCheck(ev);
        schedulePinnedRefresh();
        scheduleSync();
      };

      document.addEventListener('transitionrun', onTransitionEvt, { passive: true, capture: true });
      document.addEventListener('transitionstart', onTransitionEvt, { passive: true, capture: true });
      document.addEventListener('transitionend', onTransitionEvt, { passive: true, capture: true });
      window.addEventListener('resize', scheduleSync, { passive: true });
      window.addEventListener('scroll', onScrollEvt, { passive: true });
      document.addEventListener('scroll', onScrollEvt, { passive: true, capture: true });
    }
    return initialMeta;
  } catch (e) {
    return null;
  }
})();
''';
    return template
        .replaceAll('__TOP_PX__', safeTop.toString())
        .replaceAll('__COMPACT_TOP_PX__', safeCompactTop.toString())
        .replaceAll('__BOTTOM_PX__', safeBottom.toString())
        .replaceAll('__COMPACT_BOTTOM_PX__', safeCompactBottom.toString())
        .replaceAll('__FLUTTER_VH__', safeFlutterVh.toString())
        .replaceAll('__FORCE_EXPANDED__', forceExpandedLit);
  }

  /// Parses and applies scroll-collapse, top-luminance, and Scroll Pocket
  /// background metadata returned by [buildBrowserSafeInsetsScript] or posted
  /// via `TheaverBrowserTheme`.
  void applyBrowserPageMetaPayload(dynamic rawResult) {
    try {
      dynamic decoded = rawResult;
      for (int i = 0; i < 2 && decoded is String; i++) {
        final trimmed = decoded.trim();
        if (trimmed.isEmpty || trimmed == 'null') {
          decoded = null;
          break;
        }
        decoded = jsonDecode(trimmed);
      }
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final dynamic rawCollapsed = map['collapsed'];
      final bool? nextCollapsed = browserForceExpanded
          ? false
          : (rawCollapsed is bool ? rawCollapsed : null);
      final dynamic rawDark = map['topIsDark'];
      final bool? nextDark = rawDark is bool ? rawDark : null;
      final Color? nextCanvas =
          _parseCssColor(map['canvasColor']?.toString())?.withValues(alpha: 1.0);
      final Color? nextTopPocket =
          _parseCssColor(map['topColor']?.toString())?.withValues(alpha: 1.0) ??
              nextCanvas;
      final Color? nextBottomPocket =
          _parseCssColor(map['bottomColor']?.toString())?.withValues(alpha: 1.0) ??
              nextCanvas;

      final bool changed =
          (nextCollapsed != null && nextCollapsed != browserChromeCollapsed) ||
              (nextDark != null && nextDark != browserTopIsDark) ||
              (nextCanvas != null && nextCanvas != browserCanvasColor) ||
              (nextTopPocket != null && nextTopPocket != browserTopPocketColor) ||
              (nextBottomPocket != null &&
                  nextBottomPocket != browserBottomPocketColor);
      if (!changed) return;

      if (nextCollapsed != null) {
        browserChromeCollapsed = nextCollapsed;
      }
      if (nextDark != null) {
        browserTopIsDark = nextDark;
      }
      if (nextCanvas != null) {
        browserCanvasColor = nextCanvas;
      }
      if (nextTopPocket != null) {
        browserTopPocketColor = nextTopPocket;
      }
      if (nextBottomPocket != null) {
        browserBottomPocketColor = nextBottomPocket;
      }
      onSheetStateChanged?.call();
      MiniAppSessionController.instance.notifySessionUpdated();
    } catch (_) {}
  }

  Future<void> injectBrowserSafeInsets() async {
    final ctrl = controller;
    if (ctrl == null || !isBrowser || WebViewPlatform.instance == null) return;
    final int topPx = browserTopClearance.round().clamp(0, 320);
    final int compactTopPx = browserCompactTopClearance.round().clamp(0, 320);
    final int bottomPx = browserBottomClearance.round().clamp(0, 320);
    final int compactBottomPx =
        browserCompactBottomClearance.round().clamp(0, 320);
    final int vhPx = browserViewportHeight.round().clamp(0, 4096);
    final js = buildBrowserSafeInsetsScript(
      topPx: topPx,
      compactTopPx: compactTopPx,
      bottomPx: bottomPx,
      compactBottomPx: compactBottomPx,
      flutterViewportHeight: vhPx,
      forceExpanded: browserForceExpanded,
    );
    try {
      final raw = await ctrl.runJavaScriptReturningResult(js);
      applyBrowserPageMetaPayload(raw);
    } catch (_) {}
  }

  Future<void> refreshBrowserNavState() async {
    final ctrl = controller;
    if (ctrl == null || !isBrowser || WebViewPlatform.instance == null) return;
    try {
      canGoBack = await ctrl.canGoBack();
      canGoForward = await ctrl.canGoForward();
      final t = await ctrl.getTitle();
      if (t != null && t.trim().isNotEmpty) {
        pageTitle = t.trim();
      }
      onSheetStateChanged?.call();
      MiniAppSessionController.instance.notifySessionUpdated();
    } catch (_) {}
  }

  /// Navigates one step back inside the hosted web page or Mini App without
  /// dismissing the container sheet. Returns `true` when back navigation or a
  /// Mini App `back_button_pressed` event was dispatched.
  Future<bool> performWebBack({VoidCallback? onDispatchedBackEvent}) async {
    if (!isBrowser && backButtonVisible) {
      if (onDispatchedBackEvent != null) {
        onDispatchedBackEvent();
      } else {
        await dispatchEvent('back_button_pressed');
      }
      return true;
    }
    final ctrl = controller;
    if (ctrl != null && WebViewPlatform.instance != null) {
      try {
        if (await ctrl.canGoBack()) {
          await ctrl.goBack();
          if (isBrowser) {
            await refreshBrowserNavState();
          }
          return true;
        }
      } catch (_) {}
      return false;
    }
    if (canGoBack) {
      canGoBack = false;
      onSheetStateChanged?.call();
      MiniAppSessionController.instance.notifySessionUpdated();
      return true;
    }
    return false;
  }

  NavigationDecision _evaluateNavigationDecision(
    NavigationRequest req, {
    required bool handleDeepLinks,
  }) {
    final targetUri = Uri.tryParse(req.url);
    if (targetUri == null) return NavigationDecision.prevent;

    final schemeInfo = SafariUrlSafetyAnalyzer.classifyExternalUri(targetUri);
    if (schemeInfo.kind == ExternalSchemeKind.blocked) {
      return NavigationDecision.prevent;
    }

    if (handleDeepLinks && DeepLinkService.parseUri(targetUri) != null) {
      DeepLinkService().handleLink(targetUri);
      return NavigationDecision.prevent;
    }

    final sch = targetUri.scheme.toLowerCase();
    if (sch == 'http' || sch == 'https') {
      final safety = SafariUrlSafetyAnalyzer.analyzeUrl(req.url);
      final hostKey = safety.asciiHost.toLowerCase();
      if (safety.isSuspiciousHomograph &&
          !acceptedSuspiciousHosts.contains(hostKey)) {
        Future<void>(() async {
          if (!_hasActiveDialogHost) return;
          final ok = await uiDialogDelegate!.onSuspiciousHostWarning(info: safety);
          if (ok && controller != null) {
            acceptedSuspiciousHosts.add(hostKey);
            try {
              await controller!.loadRequest(targetUri);
            } catch (_) {}
          }
        });
        return NavigationDecision.prevent;
      }
      return NavigationDecision.navigate;
    }

    Future<void>(() async {
      if (!_hasActiveDialogHost) return;
      final origin = _resolveDialogOrigin(null);
      final ok = await uiDialogDelegate!.onExternalSchemeRequest(
        uri: targetUri,
        sourceHost: origin.label,
      );
      if (ok) {
        try {
          await launchUrl(targetUri, mode: LaunchMode.externalApplication);
        } catch (_) {}
      }
    });
    return NavigationDecision.prevent;
  }

  void _attachSharedDialogCallbacks(WebViewController ctrl) {
    ctrl
      ..setOnJavaScriptAlertDialog(handleJavaScriptAlert)
      ..setOnJavaScriptConfirmDialog(handleJavaScriptConfirm)
      ..setOnJavaScriptTextInputDialog(handleJavaScriptPrompt);
  }

  Future<void> _syncNativeBrowserPolicies(String rawUrl) async {
    await BrowserSiteSettingsService.instance.ensureLoaded();
    final settings = BrowserSiteSettingsService.instance;
    await BrowserStorageBridge.instance.configureWebViewPolicies(
      url: rawUrl,
      acceptThirdPartyCookies:
          settings.cookiePolicy == BrowserCookiePolicy.allowAll,
      blockAllCookies: settings.cookiePolicy == BrowserCookiePolicy.blockAll,
      enableOsAutofill: settings.osAutofillEnabled,
      isIncognito: isIncognito,
    );
  }

  void _handleBrowserOriginTransition(String nextUrl) {
    final nextOrigin = BrowserVaultService.normalizeOrigin(nextUrl);
    if (nextOrigin != _lastAutofillOrigin) {
      _lastAutofillOrigin = nextOrigin;
      if (focusedAutofillField != null) {
        focusedAutofillField = null;
      }
      BrowserVaultAuthGate.instance.onOriginChanged(nextUrl);
    }
  }

  void ensureWebViewInitialized() {
    if (controller != null || isLaunchPending || WebViewPlatform.instance == null) {
      return;
    }
    final targetUrl = isBrowser ? currentUrl : launchData.url;
    if (targetUrl.trim().isEmpty) return;
    final uri = Uri.tryParse(targetUrl);
    if (uri == null) return;

    if (isBrowser) {
      if (isIncognito) {
        unawaited(BrowserCookieJarVault.instance.onIncognitoSessionOpened(id));
      } else {
        unawaited(BrowserVaultService.instance.ensureLoaded());
        final savedDesktop = BrowserSiteSettingsService.instance
            .preferenceForUrl(targetUrl)
            ?.desktopMode;
        if (savedDesktop != null) {
          isDesktopMode = savedDesktop;
        }
      }
      _lastAutofillOrigin = BrowserVaultService.normalizeOrigin(targetUrl);

      final ctrl = WebViewController(
        onPermissionRequest: (req) => unawaited(handleWebPermissionRequest(req)),
      )
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'TheaverBrowserTheme',
          onMessageReceived: (JavaScriptMessage msg) {
            applyBrowserPageMetaPayload(msg.message);
          },
        )
        ..addJavaScriptChannel(
          'TheaverBrowserAutofill',
          onMessageReceived: (JavaScriptMessage msg) {
            unawaited(handleAutofillChannelMessage(msg.message));
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (p) {
              updateLoadProgress(p);
              if (p >= 35 && _earlyBrowserInsetsStage < 1) {
                _earlyBrowserInsetsStage = 1;
                unawaited(injectBrowserSafeInsets());
              } else if (p >= 75 && _earlyBrowserInsetsStage < 2) {
                _earlyBrowserInsetsStage = 2;
                unawaited(injectBrowserSafeInsets());
              }
            },
            onPageStarted: (urlStr) {
              _earlyBrowserInsetsStage = 0;
              browserChromeCollapsed = false;
              final nextUrl = urlStr.trim();
              if (nextUrl.isNotEmpty) {
                final prevHost = BrowserDataService.extractHost(currentUrl);
                final nextHost = BrowserDataService.extractHost(nextUrl);
                if (prevHost != nextHost) {
                  browserTopIsDark = null;
                  browserCanvasColor = null;
                  browserTopPocketColor = null;
                  browserBottomPocketColor = null;
                  if (!isIncognito) {
                    final siteDesktop = BrowserSiteSettingsService.instance
                        .preferenceForUrl(nextUrl)
                        ?.desktopMode;
                    if (siteDesktop != null && siteDesktop != isDesktopMode) {
                      isDesktopMode = siteDesktop;
                      unawaited(
                        controller?.setUserAgent(
                          siteDesktop ? desktopUserAgent : null,
                        ) ??
                            Future<void>.value(),
                      );
                    }
                  }
                }
                currentUrl = nextUrl;
                _handleBrowserOriginTransition(nextUrl);
              }
              currentPageHasSslWarning =
                  acceptedSslWarningHosts.contains(_hostKeyForUrl(currentUrl));
              loadProgress = 0.08;
              onSheetStateChanged?.call();
              unawaited(_syncNativeBrowserPolicies(currentUrl));
              unawaited(refreshBrowserNavState());
            },
            onUrlChange: (change) {
              final next = change.url?.trim() ?? '';
              if (next.isNotEmpty && next != currentUrl) {
                currentUrl = next;
                _handleBrowserOriginTransition(next);
                currentPageHasSslWarning =
                    acceptedSslWarningHosts.contains(_hostKeyForUrl(currentUrl));
                onSheetStateChanged?.call();
                MiniAppSessionController.instance.notifySessionUpdated();
                unawaited(refreshBrowserNavState());
                Future<void>.delayed(const Duration(milliseconds: 150), () {
                  if (controller != null) {
                    unawaited(injectBrowserSafeInsets());
                    unawaited(refreshBrowserNavState());
                  }
                });
              }
            },
            onPageFinished: (urlStr) async {
              if (urlStr.trim().isNotEmpty) {
                currentUrl = urlStr.trim();
                _handleBrowserOriginTransition(currentUrl);
              }
              loadProgress = 1.0;
              isWebContentReady = true;
              await _syncNativeBrowserPolicies(currentUrl);
              await injectBrowserSafeInsets();
              try {
                await controller?.runJavaScript(
                  BrowserAutofillScript.buildObserverScript(),
                );
              } catch (_) {}
              await refreshBrowserNavState();
              if (isIncognito) {
                BrowserCookieJarVault.instance.onIncognitoUrlVisited(currentUrl);
              } else {
                await BrowserDataService.instance
                    .recordVisit(currentUrl, displayTitle);
                unawaited(BrowserStorageBridge.instance.flushCookies());
              }
              Future<void>.delayed(const Duration(milliseconds: 300), () {
                if (controller != null && !isMinimized) {
                  unawaited(injectBrowserSafeInsets());
                }
              });
              Future<void>.delayed(const Duration(milliseconds: 500), () {
                if (controller != null && !isMinimized) {
                  unawaited(capturePreviewSnapshot());
                }
              });
              if (_webPageInteractionLocked) {
                unawaited(setWebPageInteractionLocked(true, force: true));
              }
            },
            onSslAuthError: (err) => unawaited(handleSslAuthError(err)),
            onHttpAuthRequest: (req) => unawaited(handleHttpAuth(req)),
            onNavigationRequest: (req) => _evaluateNavigationDecision(
              req,
              handleDeepLinks: true,
            ),
          ),
        );
      _attachSharedDialogCallbacks(ctrl);
      if (isDesktopMode) {
        unawaited(ctrl.setUserAgent(desktopUserAgent));
      }
      unawaited(_syncNativeBrowserPolicies(targetUrl));
      ctrl.loadRequest(uri);
      controller = ctrl;
      return;
    }

    final ctrl = WebViewController(
      onPermissionRequest: (req) => unawaited(handleWebPermissionRequest(req)),
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'TheaverWebAppBridge',
        onMessageReceived: (JavaScriptMessage msg) {
          handleBridgeMessageFromJs(msg.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            updateLoadProgress(p);
          },
          onPageStarted: (urlStr) {
            if (urlStr.trim().isNotEmpty) {
              currentUrl = urlStr.trim();
            }
            currentPageHasSslWarning =
                acceptedSslWarningHosts.contains(_hostKeyForUrl(currentUrl));
            onRequestBridgeInjection?.call();
          },
          onPageFinished: (_) {
            loadProgress = 1.0;
            isWebContentReady = true;
            onSheetStateChanged?.call();
            onRequestBridgeInjection?.call();
            Future<void>.delayed(const Duration(milliseconds: 500), () {
              if (controller != null && !isMinimized) {
                unawaited(capturePreviewSnapshot());
              }
            });
            if (_webPageInteractionLocked) {
              unawaited(setWebPageInteractionLocked(true, force: true));
            }
          },
          onSslAuthError: (err) => unawaited(handleSslAuthError(err)),
          onHttpAuthRequest: (req) => unawaited(handleHttpAuth(req)),
          onNavigationRequest: (req) => _evaluateNavigationDecision(
            req,
            handleDeepLinks: false,
          ),
        ),
      );
    _attachSharedDialogCallbacks(ctrl);
    ctrl.loadRequest(uri);
    controller = ctrl;
  }

  void handleBridgeMessageFromJs(String raw) {
    final handler = onInboundBridgeMessage;
    if (handler != null) {
      handler(raw);
      return;
    }
    final evt = MiniAppJsBridge.parseBridgeMessage(raw);
    if (evt == null) return;
    if (evt.eventType == 'web_app_set_header_color') {
      final col = MiniAppJsBridge.parseHexColor(
        (evt.eventData['color'] ?? evt.eventData['value'])?.toString(),
      );
      if (col != null) {
        customHeaderColor = col;
        MiniAppSessionController.instance.notifySessionUpdated();
      }
    } else if (evt.eventType == 'web_app_close') {
      MiniAppSessionController.instance.closeSession(this);
    }
  }

  Future<void> dispatchEvent(
    String eventType, [
    Map<String, dynamic> eventData = const {},
    String? reqId,
  ]) async {
    final ctrl = controller;
    if (ctrl == null) return;
    final js =
        'if (window.__theaverWebAppReceive) { window.__theaverWebAppReceive(${jsonEncode(eventType)}, ${jsonEncode(eventData)}, ${jsonEncode(reqId ?? '')}); }';
    try {
      await ctrl.runJavaScript(js);
    } catch (_) {}
  }

  static Color? _parseCssColor(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty || s == 'transparent' || s == 'rgba(0, 0, 0, 0)') {
      return null;
    }
    if (s.startsWith('#')) {
      return MiniAppJsBridge.parseHexColor(s);
    }
    final rgbMatch = RegExp(
      r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([0-9.]+))?\s*\)$',
      caseSensitive: false,
    ).firstMatch(s);
    if (rgbMatch == null) return null;
    final int r = int.parse(rgbMatch.group(1)!).clamp(0, 255);
    final int g = int.parse(rgbMatch.group(2)!).clamp(0, 255);
    final int b = int.parse(rgbMatch.group(3)!).clamp(0, 255);
    final double a = rgbMatch.group(4) != null
        ? (double.tryParse(rgbMatch.group(4)!) ?? 1.0).clamp(0.0, 1.0)
        : 1.0;
    if (a <= 0.02) return null;
    return Color.fromRGBO(r, g, b, a);
  }

  /// Captures a live viewport snapshot via the native Android WebView channel and/or
  /// visible DOM content metadata so [MiniAppTabsSwitcher] shows actual app contents.
  Future<void> capturePreviewSnapshot() {
    final existing = _activeSnapshotFuture;
    if (existing != null) return existing;
    late final Future<void> run;
    run = _performCapturePreviewSnapshot().whenComplete(() {
      if (identical(_activeSnapshotFuture, run)) {
        _activeSnapshotFuture = null;
      }
    });
    _activeSnapshotFuture = run;
    return run;
  }

  Future<void> _performCapturePreviewSnapshot() async {
    final ctrl = controller;
    if (ctrl == null || WebViewPlatform.instance == null) return;

    bool updated = false;
    final String targetUrl = isBrowser ? currentUrl : launchData.url;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final bytes = await _snapshotChannel.invokeMethod<Uint8List>(
          'captureWebView',
          <String, dynamic>{
            'url': targetUrl,
            'maxWidth': 960,
            'quality': 86,
            'topCropDp': 0.0,
          },
        );
        if (bytes != null && bytes.isNotEmpty) {
          previewImageBytes = bytes;
          updated = true;
        }
      } on MissingPluginException {
        // Non-Android / unit test environment cleanly falls back to DOM or contextual preview.
      } on PlatformException {
        // Native bitmap draw unavailable on current surface.
      } catch (_) {}
    }

    if (!updated) {
      const String js = r'''
(function() {
  try {
    if (!document || !document.body) return null;
    var rootStyle = getComputedStyle(document.documentElement);
    var bodyStyle = getComputedStyle(document.body);
    var bg = bodyStyle.backgroundColor;
    if (!bg || bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent') {
      bg = rootStyle.backgroundColor || '';
    }
    var accent = rootStyle.getPropertyValue('--tg-theme-button-color') || rootStyle.getPropertyValue('--btn') || '';
    var vh = window.innerHeight || 0;
    var hasLayout = vh > 100 && document.body.clientHeight > 40;
    var selectors = '.hero, .bot-row, .asset-row, .tx-row, .user-row, .card, h1, h2, h3, article, section, button, .btn, p';
    var nodes = document.querySelectorAll(selectors);
    var blocks = [];
    var seen = {};
    for (var i = 0; i < nodes.length && blocks.length < 8; i++) {
      var el = nodes[i];
      if (!el || el.classList.contains('hidden')) continue;
      if (el.matches('.card, article, section') && el.querySelector('.bot-row, .asset-row, .tx-row, .user-row')) {
        continue;
      }
      var cs = getComputedStyle(el);
      if (cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity) === 0) continue;
      if (hasLayout) {
        var rect = el.getBoundingClientRect();
        if (rect.height < 14 || rect.width < 60 || rect.bottom <= 44 || rect.top >= vh) continue;
      } else {
        var rawCheck = (el.innerText || '').trim();
        if (rawCheck.length < 2) continue;
      }

      var title = '';
      var subtitle = '';
      var trailing = '';
      var badge = '';
      var kind = 'card';

      if (el.matches('.bot-row, .asset-row, .tx-row, .user-row')) {
        kind = 'row';
        var bEl = el.querySelector('.avatar, .coin-icon');
        if (bEl) badge = (bEl.innerText || '').trim().slice(0, 3);
        var nEl = el.querySelector('.name, strong, b');
        var sEl = el.querySelector('.sub, small');
        title = ((nEl ? nEl.innerText : el.innerText) || '').trim().replace(/\s+/g, ' ');
        subtitle = sEl ? (sEl.innerText || '').trim().replace(/\s+/g, ' ') : '';
        var rEl = el.lastElementChild;
        if (rEl && rEl !== bEl && rEl !== nEl && !rEl.contains(nEl)) {
          trailing = (rEl.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 24);
        }
      } else if (el.matches('.hero')) {
        kind = 'hero';
        var hEl = el.querySelector('h1, h2, .bal, .title, .name');
        var subEl = el.querySelector('.sub, p');
        title = ((hEl ? hEl.innerText : el.innerText) || '').trim().replace(/\s+/g, ' ');
        subtitle = subEl ? (subEl.innerText || '').trim().replace(/\s+/g, ' ') : '';
      } else if (el.matches('button, .btn')) {
        kind = 'button';
        title = (el.innerText || '').trim().replace(/\s+/g, ' ');
      } else if (el.matches('h1, h2, h3')) {
        kind = 'heading';
        title = (el.innerText || '').trim().replace(/\s+/g, ' ');
      } else {
        kind = el.matches('p') ? 'text' : 'card';
        var rawTxt = (el.innerText || '').trim().replace(/\s+/g, ' ');
        var parts = (el.innerText || '').split(/\n+/).map(function(x){ return x.trim(); }).filter(Boolean);
        title = parts.length ? parts[0] : rawTxt;
        subtitle = parts.length > 1 ? parts[1] : '';
      }
      title = title.slice(0, 68);
      subtitle = subtitle.slice(0, 88);
      if (!title || seen[title]) continue;
      seen[title] = 1;
      blocks.push({
        kind: kind,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        leadingBadge: badge,
        cardColor: cs.backgroundColor || '',
        fgColor: cs.color || ''
      });
    }
    return JSON.stringify({
      bgColor: bg,
      textColor: bodyStyle.color || '',
      accentColor: (accent || '').trim(),
      blocks: blocks
    });
  } catch (e) {
    return null;
  }
})();
''';
      try {
        final dynamic rawResult = await ctrl.runJavaScriptReturningResult(js);
        dynamic decoded = rawResult;
        if (decoded is String) {
          final trimmed = decoded.trim();
          if (trimmed.isNotEmpty && trimmed != 'null') {
            decoded = jsonDecode(trimmed);
            if (decoded is String) {
              decoded = jsonDecode(decoded);
            }
          } else {
            decoded = null;
          }
        }
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          final rawBlocks = map['blocks'];
          final parsedBlocks = <MiniAppDomBlock>[];
          if (rawBlocks is List) {
            for (final item in rawBlocks) {
              if (item is Map) {
                final b = Map<String, dynamic>.from(item);
                final t = (b['title'] ?? '').toString().trim();
                if (t.isEmpty) continue;
                parsedBlocks.add(
                  MiniAppDomBlock(
                    kind: (b['kind'] ?? 'card').toString(),
                    title: t,
                    subtitle: (b['subtitle'] ?? '').toString().trim(),
                    trailing: (b['trailing'] ?? '').toString().trim(),
                    leadingBadge: (b['leadingBadge'] ?? '').toString().trim(),
                    cardColor: _parseCssColor(b['cardColor']?.toString()),
                    fgColor: _parseCssColor(b['fgColor']?.toString()),
                  ),
                );
              }
            }
          }
          if (parsedBlocks.isNotEmpty) {
            domPreview = MiniAppDomPreview(
              bgColor: _parseCssColor(map['bgColor']?.toString()),
              textColor: _parseCssColor(map['textColor']?.toString()),
              accentColor: _parseCssColor(map['accentColor']?.toString()),
              blocks: parsedBlocks,
            );
            updated = true;
          }
        }
      } catch (_) {}
    }
    if (updated) {
      MiniAppSessionController.instance.notifySessionUpdated();
    }
  }
}

class _MiniAppSwitcherBackObserver with WidgetsBindingObserver {
  _MiniAppSwitcherBackObserver(this._controller);

  final MiniAppSessionController _controller;

  @override
  Future<bool> didPopRoute() async => _controller.handleSystemBack();
}

/// Coordinates multiple minimized [MiniAppSession] entries, the bottom stacked
/// capsule bar, and the 3D tabs switcher across navigation routes.
class MiniAppSessionController extends ChangeNotifier {
  MiniAppSessionController._() {
    ensureInitialized();
  }

  static final MiniAppSessionController instance = MiniAppSessionController._();

  final List<MiniAppSession> _minimizedSessions = <MiniAppSession>[];
  bool _isSwitcherOpen = false;
  int _activeFullScreenCount = 0;
  int _settledFullScreenCount = 0;
  bool _pendingSheetMinimizeFastLayout = false;
  bool _pendingRestoreTransition = false;
  DateTime? _lastMinimizeToSwitcherAt;
  bool _backObserverRegistered = false;
  late final _MiniAppSwitcherBackObserver _backObserver =
      _MiniAppSwitcherBackObserver(this);

  /// Delay before snapshotting the underlying route into a frozen blurred
  /// backdrop so an active sheet pop animation finishes clearing first.
  Duration get backdropCaptureDelay {
    final at = _lastMinimizeToSwitcherAt;
    if (at == null) return Duration.zero;
    final elapsed = DateTime.now().difference(at);
    const total = Duration(milliseconds: 260);
    return elapsed >= total ? Duration.zero : (total - elapsed);
  }

  /// Registers a high-priority [WidgetsBindingObserver] before [MaterialApp]
  /// mounts so native Android system Back closes [MiniAppTabsSwitcher] first.
  void ensureInitialized() {
    if (_backObserverRegistered) return;
    try {
      WidgetsBinding.instance.addObserver(_backObserver);
      _backObserverRegistered = true;
    } catch (_) {}
  }

  /// Handles native back / Escape when [MiniAppTabsSwitcher] is open.
  bool handleSystemBack() {
    if (activeSafariWebAlertCount.value > 0) return false;
    if (!isSwitcherOpen) return false;
    HapticUtils.tap();
    closeSwitcher();
    return true;
  }

  void _syncPlatformBackState() {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        isSwitcherOpen) {
      try {
        SystemNavigator.setFrameworkHandlesBack(true);
      } catch (_) {}
    }
  }

  List<MiniAppSession> get minimizedSessions =>
      List<MiniAppSession>.unmodifiable(_minimizedSessions);

  int get minimizedCount => _minimizedSessions.length;

  MiniAppSession? get minimizedSession =>
      _minimizedSessions.isEmpty ? null : _minimizedSessions.last;

  bool get hasMinimizedSession => _minimizedSessions.isNotEmpty;

  bool get isSwitcherOpen =>
      _isSwitcherOpen && _minimizedSessions.isNotEmpty;

  int get activeFullScreenCount => _activeFullScreenCount;

  int get settledFullScreenCount => _settledFullScreenCount;

  bool get isFullScreenTransitioningIn =>
      _pendingRestoreTransition ||
      _activeFullScreenCount > _settledFullScreenCount;

  bool consumeSheetMinimizeFastLayout() {
    final bool value = _pendingSheetMinimizeFastLayout;
    _pendingSheetMinimizeFastLayout = false;
    return value;
  }

  bool get shouldShowMinimizedBar =>
      _minimizedSessions.isNotEmpty &&
      _activeFullScreenCount == 0 &&
      !_isSwitcherOpen;

  void _notifySafely() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  void registerFullScreenOpen() {
    _pendingRestoreTransition = false;
    _activeFullScreenCount += 1;
    if (_minimizedSessions.isNotEmpty) {
      _notifySafely();
    }
  }

  void markFullScreenSettled() {
    _pendingRestoreTransition = false;
    _settledFullScreenCount += 1;
    _notifySafely();
  }

  void unmarkFullScreenSettled() {
    if (_settledFullScreenCount > 0) {
      _settledFullScreenCount -= 1;
    }
  }

  void unregisterFullScreenOpen() {
    _pendingRestoreTransition = false;
    if (_activeFullScreenCount > 0) {
      _activeFullScreenCount -= 1;
    }
    _notifySafely();
  }

  void minimize(MiniAppSession session, {NavigatorState? navigator}) {
    session.isMinimized = true;
    if (navigator != null) {
      session.lastNavigator = navigator;
    }
    _minimizedSessions.removeWhere(
      (s) =>
          identical(s, session) ||
          (!session.isBrowser &&
              !s.isBrowser &&
              session.launchData.botId.isNotEmpty &&
              s.launchData.botId == session.launchData.botId &&
              s.launchData.url == session.launchData.url) ||
          (session.isBrowser &&
              s.isBrowser &&
              s.isIncognito == session.isIncognito &&
              s.currentUrl.isNotEmpty &&
              s.currentUrl == session.currentUrl),
    );
    _minimizedSessions.add(session);
    _isSwitcherOpen = false;
    if (navigator != null) {
      _pendingSheetMinimizeFastLayout = true;
    }
    if (!session.isBrowser) {
      session.dispatchEvent('deactivated');
      session.dispatchEvent('viewport_changed', const {
        'height': 0,
        'is_expanded': false,
        'is_state_stable': true,
      });
    }
    notifyListeners();
  }

  void notifySessionUpdated() {
    notifyListeners();
  }

  void openSwitcher() {
    if (_minimizedSessions.isEmpty || _isSwitcherOpen) return;
    _lastMinimizeToSwitcherAt = null;
    _isSwitcherOpen = true;
    _syncPlatformBackState();
    notifyListeners();
  }

  /// Registers [session] in the minimized stack and opens [MiniAppTabsSwitcher]
  /// directly (used when tapping the floating header title pill).
  void minimizeAndOpenSwitcher(
    MiniAppSession session, {
    NavigatorState? navigator,
  }) {
    session.isMinimized = true;
    if (navigator != null) {
      session.lastNavigator = navigator;
    }
    _minimizedSessions.removeWhere(
      (s) =>
          identical(s, session) ||
          (!session.isBrowser &&
              !s.isBrowser &&
              session.launchData.botId.isNotEmpty &&
              s.launchData.botId == session.launchData.botId &&
              s.launchData.url == session.launchData.url) ||
          (session.isBrowser &&
              s.isBrowser &&
              s.isIncognito == session.isIncognito &&
              s.currentUrl.isNotEmpty &&
              s.currentUrl == session.currentUrl),
    );
    _minimizedSessions.add(session);
    _lastMinimizeToSwitcherAt = DateTime.now();
    _isSwitcherOpen = true;
    _syncPlatformBackState();
    if (!session.isBrowser) {
      session.dispatchEvent('deactivated');
    }
    notifyListeners();
  }

  void closeSwitcher() {
    if (!_isSwitcherOpen) return;
    _lastMinimizeToSwitcherAt = null;
    _isSwitcherOpen = false;
    notifyListeners();
  }

  Future<void> onMinimizedBarActivate({
    GlobalKey<NavigatorState>? fallbackNavigatorKey,
  }) async {
    if (_minimizedSessions.isEmpty) return;
    if (_minimizedSessions.length == 1) {
      await restoreSession(
        _minimizedSessions.last,
        fallbackNavigatorKey: fallbackNavigatorKey,
      );
      return;
    }
    openSwitcher();
  }

  Future<void> restore({
    GlobalKey<NavigatorState>? fallbackNavigatorKey,
  }) async {
    final session = minimizedSession;
    if (session == null) return;
    await restoreSession(session, fallbackNavigatorKey: fallbackNavigatorKey);
  }

  Future<void> restoreSession(
    MiniAppSession session, {
    GlobalKey<NavigatorState>? fallbackNavigatorKey,
  }) async {
    NavigatorState? nav;
    if (session.lastNavigator != null && session.lastNavigator!.mounted) {
      nav = session.lastNavigator;
    } else {
      for (final other in _minimizedSessions.reversed) {
        if (other.lastNavigator != null && other.lastNavigator!.mounted) {
          nav = other.lastNavigator;
          break;
        }
      }
      nav ??= fallbackNavigatorKey?.currentState;
    }
    if (nav == null || !nav.mounted) return;

    final BuildContext? restoreContext = nav.overlay?.context;
    if (restoreContext == null || !restoreContext.mounted) return;

    _minimizedSessions.removeWhere((s) => identical(s, session));
    session.isMinimized = false;
    _isSwitcherOpen = false;
    _pendingRestoreTransition = true;
    notifyListeners();
    if (!session.isBrowser) {
      session.dispatchEvent('activated');
    }

    try {
      await showTheavModalSheet<void>(
        context: restoreContext,
        enableDrag: false,
        barrierDismissible: true,
        useRootNavigator: true,
        customSheetBuilder: (_) => session.isBrowser
            ? InAppBrowserSheet(session: session)
            : MiniAppWebViewSheet(
                launchData: session.launchData,
                botName: session.botName,
                botUsername: session.botUsername,
                isVerified: session.isVerified,
                chatId: session.chatId,
                mode: session.mode,
                buttonText: session.buttonText,
                onSwitchInlineQuery: session.onSwitchInlineQuery,
                session: session,
              ),
        builder: (_) => const SizedBox.shrink(),
      );
    } finally {
      _pendingRestoreTransition = false;
    }
  }

  void closeSession(MiniAppSession session) {
    session.clearAutofillOverlays(notify: false);
    if (session.isBrowser && session.isIncognito) {
      unawaited(BrowserCookieJarVault.instance.onIncognitoSessionClosed(session.id));
    }
    final idx = _minimizedSessions.indexWhere((s) => identical(s, session));
    if (idx == -1) return;
    _minimizedSessions.removeAt(idx);
    session.isMinimized = false;
    if (_minimizedSessions.isEmpty) {
      _isSwitcherOpen = false;
    }
    notifyListeners();
  }

  void closeMinimized([MiniAppSession? target]) {
    if (target != null) {
      closeSession(target);
    } else {
      closeAllMinimized();
    }
  }

  void closeAllMinimized() {
    if (_minimizedSessions.isEmpty && !_isSwitcherOpen) return;
    for (final s in _minimizedSessions) {
      s.clearAutofillOverlays(notify: false);
      if (s.isBrowser && s.isIncognito) {
        unawaited(BrowserCookieJarVault.instance.onIncognitoSessionClosed(s.id));
      }
      s.isMinimized = false;
    }
    _minimizedSessions.clear();
    _isSwitcherOpen = false;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTesting() {
    for (final s in _minimizedSessions) {
      s.isMinimized = false;
    }
    _minimizedSessions.clear();
    _isSwitcherOpen = false;
    _activeFullScreenCount = 0;
    _settledFullScreenCount = 0;
    _pendingSheetMinimizeFastLayout = false;
    _pendingRestoreTransition = false;
    notifyListeners();
  }
}

Future<bool> _confirmMiniAppCloseDialog(
  BuildContext context, {
  bool closeAll = false,
  String? originLabel,
}) async {
  return await showSafariWebAlert<bool>(
        context: context,
        tone: SafariAlertTone.securityWarning,
        iconOverride: Icons.warning_amber_rounded,
        originLabel: (originLabel != null && originLabel.trim().isNotEmpty)
            ? originLabel.trim()
            : null,
        title: closeAll ? 'Закрыть все Mini Apps?' : 'Закрыть Mini App?',
        message: 'Внесённые изменения могут не сохраниться.',
        actions: [
          const SafariAlertAction<bool>(label: 'Остаться', result: false),
          SafariAlertAction<bool>(
            label: closeAll ? 'Закрыть все' : 'Закрыть',
            result: true,
            isDestructive: true,
          ),
        ],
      ) ??
      false;
}

class _MinimizedMiniAppHostScope extends InheritedWidget {
  const _MinimizedMiniAppHostScope({required super.child});

  static bool maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_MinimizedMiniAppHostScope>() !=
      null;

  @override
  bool updateShouldNotify(_MinimizedMiniAppHostScope oldWidget) => false;
}

/// Wraps the app navigator subtree to present a Telegram-style minimized bottom
/// Mini App bar (including stacked counter indicator when 2+ apps are open) and
/// the full-screen 3D Mini App tabs switcher.
class MinimizedMiniAppHost extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  const MinimizedMiniAppHost({
    super.key,
    required this.child,
    this.navigatorKey,
  });

  static bool isMountedIn(BuildContext context) =>
      _MinimizedMiniAppHostScope.maybeOf(context);

  @override
  State<MinimizedMiniAppHost> createState() => _MinimizedMiniAppHostState();
}

class _MinimizedMiniAppHostState extends State<MinimizedMiniAppHost>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animController;
  late final Animation<double> _curvedAnim;
  late final Animation<Offset> _slideAnim;
  List<MiniAppSession> _displayedSessions = const [];
  bool _snapLayoutFull = false;
  final GlobalKey _backdropBoundaryKey = GlobalKey();
  ui.Image? _frozenBackdropImage;
  Timer? _backdropCaptureTimer;
  bool _backdropCaptureInFlight = false;

  @override
  void initState() {
    super.initState();
    MiniAppSessionController.instance.ensureInitialized();
    WidgetsBinding.instance.addObserver(this);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _curvedAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0.0, 1.0),
      end: Offset.zero,
    ).animate(_curvedAnim);

    MiniAppSessionController.instance.addListener(_onSessionChanged);
    final ctrl = MiniAppSessionController.instance;
    if (ctrl.shouldShowMinimizedBar) {
      _displayedSessions = ctrl.minimizedSessions;
      _animController.value = 1.0;
    }
  }

  @override
  Future<bool> didPopRoute() async =>
      MiniAppSessionController.instance.handleSystemBack();

  void _disposeFrozenBackdrop() {
    _backdropCaptureTimer?.cancel();
    _backdropCaptureTimer = null;
    _frozenBackdropImage?.dispose();
    _frozenBackdropImage = null;
  }

  void _captureFrozenBackdropIfNeeded({
    required double devicePixelRatio,
    required Color fallbackBg,
  }) {
    if (kIsWeb ||
        WidgetsBinding.instance is! WidgetsFlutterBinding ||
        _backdropCaptureInFlight ||
        _backdropCaptureTimer != null ||
        _frozenBackdropImage != null ||
        !MiniAppSessionController.instance.isSwitcherOpen) {
      return;
    }
    final Duration delay =
        MiniAppSessionController.instance.backdropCaptureDelay;
    void runCapture() {
      _backdropCaptureInFlight = true;
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        try {
          if (!mounted || !MiniAppSessionController.instance.isSwitcherOpen) {
            return;
          }
          final RenderObject? ro =
              _backdropBoundaryKey.currentContext?.findRenderObject();
          if (ro is! RenderRepaintBoundary ||
              !ro.hasSize ||
              ro.debugNeedsPaint) {
            return;
          }
          final double captureRatio =
              (devicePixelRatio * 0.5).clamp(0.85, 1.5);
          final ui.Image rawImg = await ro.toImage(pixelRatio: captureRatio);
          if (!mounted || !MiniAppSessionController.instance.isSwitcherOpen) {
            rawImg.dispose();
            return;
          }
          final int w = rawImg.width;
          final int h = rawImg.height;
          final Rect dst = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
          final double sigmaPx = 16.0 * captureRatio;
          final ui.PictureRecorder recorder = ui.PictureRecorder();
          final Canvas canvas = Canvas(recorder);
          canvas.drawRect(dst, Paint()..color = fallbackBg);
          canvas.drawImageRect(
            rawImg,
            dst,
            dst,
            Paint()
              ..filterQuality = FilterQuality.medium
              ..imageFilter = ui.ImageFilter.blur(
                sigmaX: sigmaPx,
                sigmaY: sigmaPx,
                tileMode: ui.TileMode.clamp,
              ),
          );
          final ui.Picture picture = recorder.endRecording();
          final ui.Image blurredImg = await picture.toImage(w, h);
          picture.dispose();
          rawImg.dispose();
          if (!mounted || !MiniAppSessionController.instance.isSwitcherOpen) {
            blurredImg.dispose();
            return;
          }
          setState(() {
            _frozenBackdropImage?.dispose();
            _frozenBackdropImage = blurredImg;
          });
        } catch (_) {
          // Fallback to live BackdropFilter when boundary snapshot is unavailable.
        } finally {
          _backdropCaptureInFlight = false;
        }
      });
    }

    if (delay == Duration.zero) {
      runCapture();
    } else {
      _backdropCaptureTimer = Timer(delay, () {
        _backdropCaptureTimer = null;
        if (!mounted || !MiniAppSessionController.instance.isSwitcherOpen) {
          return;
        }
        runCapture();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeFrozenBackdrop();
    MiniAppSessionController.instance.removeListener(_onSessionChanged);
    _animController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final ctrl = MiniAppSessionController.instance;
    if (!ctrl.isSwitcherOpen) {
      _disposeFrozenBackdrop();
    }
    if (ctrl.shouldShowMinimizedBar) {
      final bool fastLayout = ctrl.consumeSheetMinimizeFastLayout();
      final bool willRunForward =
          _animController.status != AnimationStatus.forward &&
              _animController.status != AnimationStatus.completed;
      setState(() {
        _displayedSessions = ctrl.minimizedSessions;
        if (willRunForward) {
          _snapLayoutFull = fastLayout;
        }
      });
      if (willRunForward) {
        _animController
            .forward(from: fastLayout ? 0.0 : null)
            .whenComplete(() {
          if (mounted && _snapLayoutFull) {
            _snapLayoutFull = false;
          }
        });
      }
    } else if (_displayedSessions.isNotEmpty) {
      // Keep the underlying screen layout rock-steady while a full-screen sheet
      // slides up over it, avoiding 20+ full chat tree relayout passes.
      if (ctrl.isFullScreenTransitioningIn && !ctrl.isSwitcherOpen) {
        return;
      }
      // Once covered by a settled full-screen sheet or the tabs switcher,
      // collapse immediately in a single frame without animating layout behind it.
      if (ctrl.settledFullScreenCount > 0 || ctrl.isSwitcherOpen) {
        _snapLayoutFull = false;
        _animController.value = 0.0;
        setState(() => _displayedSessions = const []);
        return;
      }
      _snapLayoutFull = false;
      if (_animController.status == AnimationStatus.dismissed) {
        setState(() => _displayedSessions = const []);
      } else if (_animController.status != AnimationStatus.reverse) {
        _animController.reverse().whenComplete(() {
          if (mounted && !MiniAppSessionController.instance.shouldShowMinimizedBar) {
            _snapLayoutFull = false;
            setState(() => _displayedSessions = const []);
          }
        });
      } else {
        setState(() {});
      }
    } else {
      _snapLayoutFull = false;
      setState(() {});
    }
  }

  NavigatorState? _resolveNavigatorFor(MiniAppSession session) {
    if (session.lastNavigator != null && session.lastNavigator!.mounted) {
      return session.lastNavigator;
    }
    for (final other in MiniAppSessionController.instance.minimizedSessions.reversed) {
      if (other.lastNavigator != null && other.lastNavigator!.mounted) {
        return other.lastNavigator;
      }
    }
    return widget.navigatorKey?.currentState;
  }

  Future<void> _handleCloseSession(MiniAppSession session) async {
    if (session.closingConfirmation) {
      final BuildContext? dialogCtx = _resolveNavigatorFor(session)?.overlay?.context;
      if (dialogCtx != null && dialogCtx.mounted) {
        final String origin = session.botUsername.trim().isNotEmpty
            ? '@${session.botUsername.trim()}'
            : session.displayTitle;
        final confirm = await _confirmMiniAppCloseDialog(
          dialogCtx,
          originLabel: origin,
        );
        if (!confirm || !mounted) return;
      }
    }
    MiniAppSessionController.instance.closeSession(session);
  }

  Future<void> _handleCloseAllSessions() async {
    final sessions = MiniAppSessionController.instance.minimizedSessions;
    final needsConfirm = sessions.any((s) => s.closingConfirmation);
    if (needsConfirm && sessions.isNotEmpty) {
      final BuildContext? dialogCtx =
          _resolveNavigatorFor(sessions.last)?.overlay?.context;
      if (dialogCtx != null && dialogCtx.mounted) {
        final confirm = await _confirmMiniAppCloseDialog(
          dialogCtx,
          closeAll: true,
        );
        if (!confirm || !mounted) return;
      }
    }
    MiniAppSessionController.instance.closeAllMinimized();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = MiniAppSessionController.instance;
    final bool switcherOpen = ctrl.isSwitcherOpen;
    if (_displayedSessions.isEmpty &&
        _animController.isDismissed &&
        !switcherOpen) {
      return _MinimizedMiniAppHostScope(child: widget.child);
    }

    final resolved = MiniAppJsBridge.resolveThemeColors(Theme.of(context));
    final mq = MediaQuery.of(context);
    final double effectiveSafeBottom =
        math.max(mq.padding.bottom, mq.viewPadding.bottom);
    final double barBottomInset = math.max(6.0, effectiveSafeBottom + 4.0);
    const double topPad = 6.0;

    return _MinimizedMiniAppHostScope(
      child: AnimatedBuilder(
        animation: _curvedAnim,
        child: widget.child,
        builder: (context, staticChild) {
          final double rawT = _curvedAnim.value.clamp(0.0, 1.0);
          final double layoutT = _snapLayoutFull ? 1.0 : rawT;
          final double insetFactor = (1.0 - layoutT).clamp(0.0, 1.0);

          final int extraCount = math.max(0, _displayedSessions.length - 1);
          final double deckOffset =
              extraCount >= 2 ? 12.0 : (extraCount == 1 ? 7.0 : 0.0);
          final double dockFullHeight =
              topPad + deckOffset + 48.0 + barBottomInset;
          final double dockLayoutHeight =
              _displayedSessions.isNotEmpty ? (dockFullHeight * layoutT) : 0.0;
          final double childViewInsetsBottom =
              math.max(0.0, mq.viewInsets.bottom - dockLayoutHeight);

          final Widget adjustedChild =
              (_displayedSessions.isNotEmpty && layoutT > 0.001)
                  ? MediaQuery(
                      data: mq.copyWith(
                        padding: mq.padding.copyWith(
                          bottom: mq.padding.bottom * insetFactor,
                        ),
                        viewPadding: mq.viewPadding.copyWith(
                          bottom: mq.viewPadding.bottom * insetFactor,
                        ),
                        viewInsets: mq.viewInsets.copyWith(
                          bottom: childViewInsetsBottom,
                        ),
                      ),
                      child: staticChild!,
                    )
                  : staticChild!;

          final double cornerRadius = 14.0 * layoutT;
          final bool hidePointerBehindKeyboard =
              mq.viewInsets.bottom > dockLayoutHeight * 0.4;
          final Widget? dockRegion = (_displayedSessions.isNotEmpty &&
                  layoutT > 0.0)
              ? IgnorePointer(
                  ignoring: hidePointerBehindKeyboard,
                  child: ClipRect(
                    clipBehavior:
                        (layoutT < 0.999 || rawT < 0.999) ? Clip.hardEdge : Clip.none,
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: layoutT,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: ColoredBox(
                          key: const ValueKey('minimized_mini_app_dock_region'),
                          color: resolved.dockBg,
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: topPad,
                              bottom: barBottomInset,
                            ),
                            child: MinimizedMiniAppBar(
                              key: const ValueKey('minimized_mini_app_bar'),
                              sessions: _displayedSessions,
                              onActivate: () => MiniAppSessionController.instance
                                  .onMinimizedBarActivate(
                                fallbackNavigatorKey: widget.navigatorKey,
                              ),
                              onClose: () =>
                                  _handleCloseSession(_displayedSessions.last),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : null;

          final Widget columnLayout = Column(
            children: [
              Expanded(
                child: dockRegion != null
                    ? Stack(
                        fit: StackFit.expand,
                        clipBehavior: Clip.none,
                        children: [
                          adjustedChild,
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: cornerRadius,
                            child: IgnorePointer(
                              key: const ValueKey(
                                'minimized_mini_app_dock_fillets',
                              ),
                              child: CustomPaint(
                                painter: _DockUpwardFilletsPainter(
                                  color: resolved.dockBg,
                                  radius: cornerRadius,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : adjustedChild,
              ),
              if (dockRegion != null) dockRegion,
            ],
          );

          if (switcherOpen) {
            if (BlurUtils.shouldBlurMaterialHud(context, listen: false)) {
              _captureFrozenBackdropIfNeeded(
                devicePixelRatio: mq.devicePixelRatio,
                fallbackBg: resolved.bodyBg,
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                Offstage(
                  offstage: _frozenBackdropImage != null,
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      key: _backdropBoundaryKey,
                      child: columnLayout,
                    ),
                  ),
                ),
                MiniAppTabsSwitcher(
                  key: const ValueKey('mini_app_tabs_switcher'),
                  sessions: ctrl.minimizedSessions,
                  frozenBackdropImage: _frozenBackdropImage,
                  initialPrivateMode: ctrl.minimizedSessions.isNotEmpty &&
                      ctrl.minimizedSessions.last.isBrowser &&
                      ctrl.minimizedSessions.last.isIncognito,
                  onDismiss: ctrl.closeSwitcher,
                  onSelectSession: (s) => ctrl.restoreSession(
                    s,
                    fallbackNavigatorKey: widget.navigatorKey,
                  ),
                  onCloseSession: _handleCloseSession,
                  onCloseAll: _handleCloseAllSessions,
                  onOpenNewBrowserTab: (isPrivate) {
                    final BuildContext targetCtx = (ctrl
                                .minimizedSessions.isNotEmpty
                            ? _resolveNavigatorFor(ctrl.minimizedSessions.last)
                                ?.overlay
                                ?.context
                            : null) ??
                        widget.navigatorKey?.currentState?.overlay?.context ??
                        context;
                    ctrl.closeSwitcher();
                    if (targetCtx.mounted) {
                      unawaited(
                        openNewBrowserTabPrompt(
                          targetCtx,
                          isIncognito: isPrivate,
                        ),
                      );
                    }
                  },
                ),
              ],
            );
          }
          return columnLayout;
        },
      ),
    );
  }
}

/// Paints small concave corner fillets at the bottom-left and bottom-right of
/// the main screen area curving upward from the minimized dock surface.
class _DockUpwardFilletsPainter extends CustomPainter {
  const _DockUpwardFilletsPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final double r = math.min(radius, math.min(size.height, size.width * 0.5));
    if (r <= 0.1) return;

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final double overlap = math.min(1.0, r);
    final Path leftFillet = Path()
      ..moveTo(0, size.height + overlap)
      ..lineTo(0, size.height - r)
      ..arcToPoint(
        Offset(r, size.height),
        radius: Radius.circular(r),
        clockwise: false,
      )
      ..lineTo(r, size.height + overlap)
      ..close();

    final Path rightFillet = Path()
      ..moveTo(size.width - r, size.height + overlap)
      ..lineTo(size.width - r, size.height)
      ..arcToPoint(
        Offset(size.width, size.height - r),
        radius: Radius.circular(r),
        clockwise: false,
      )
      ..lineTo(size.width, size.height + overlap)
      ..close();

    canvas.drawPath(leftFillet, paint);
    canvas.drawPath(rightFillet, paint);
  }

  @override
  bool shouldRepaint(covariant _DockUpwardFilletsPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}

/// Telegram-style minimized bottom bar (`[ x BotName (и ещё N) ^ ]`) supporting
/// stacked back-card rim indicators when 2+ Mini Apps are minimized.
class MinimizedMiniAppBar extends StatelessWidget {
  final List<MiniAppSession> sessions;
  final VoidCallback onActivate;
  final VoidCallback onClose;

  const MinimizedMiniAppBar({
    super.key,
    required this.sessions,
    required this.onActivate,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) return const SizedBox.shrink();
    final MiniAppSession front = sessions.last;
    final int extraCount = sessions.length - 1;
    final double deckOffset =
        extraCount >= 2 ? 12.0 : (extraCount == 1 ? 7.0 : 0.0);

    final resolved = MiniAppJsBridge.resolveThemeColors(Theme.of(context));
    final style = TheavSurfaceStyle.of(context);

    final Color barBg = front.customHeaderColor ?? resolved.headerBg;
    final Color barFg = front.customHeaderColor != null
        ? (barBg.computeLuminance() <= 0.55 ? Colors.white : Colors.black87)
        : resolved.headerFg;
    final Color barDivider = front.customHeaderColor != null
        ? barFg.withValues(alpha: 0.14)
        : resolved.divider;

    final bool useGlassBar = style.isGlass &&
        style.glassProvider != null &&
        front.customHeaderColor == null;

    final Widget frontContent = Material(
      type: MaterialType.transparency,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            SizedBox(
              width: 46,
              height: 48,
              child: Semantics(
                button: true,
                label: 'Закрыть',
                child: InkWell(
                  key: const ValueKey('minimized_mini_app_close_button'),
                  borderRadius: BorderRadius.circular(24),
                  onTap: () {
                    HapticUtils.tap();
                    onClose();
                  },
                  child: Center(
                    child: Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: barFg,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticUtils.selection();
                  onActivate();
                },
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0.0) < -200.0) {
                    HapticUtils.selection();
                    onActivate();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, right: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (front.isBrowser) ...[
                          Icon(
                            front.currentUrl.toLowerCase().startsWith('https://')
                                ? Icons.lock_outline_rounded
                                : Icons.public_rounded,
                            size: 16,
                            color: barFg.withValues(alpha: 0.78),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            front.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.15,
                              color: barFg,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                        if (extraCount > 0)
                          Text(
                            ' и ещё $extraCount',
                            key: const ValueKey('minimized_mini_app_extra_count'),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.15,
                              color: barFg.withValues(alpha: 0.78),
                              decoration: TextDecoration.none,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 46,
              height: 48,
              child: Semantics(
                button: true,
                label: 'Развернуть',
                child: InkWell(
                  key: const ValueKey('minimized_mini_app_expand_button'),
                  borderRadius: BorderRadius.circular(24),
                  onTap: () {
                    HapticUtils.selection();
                    onActivate();
                  },
                  child: Center(
                    child: Icon(
                      Icons.keyboard_arrow_up_rounded,
                      size: 26,
                      color: barFg,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return SizedBox(
      height: deckOffset + 48.0,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (extraCount >= 2)
            Positioned(
              left: 26,
              right: 26,
              top: 0,
              height: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    barFg.withValues(alpha: style.isDark ? 0.04 : 0.03),
                    barBg,
                  ).withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: barDivider, width: 0.65),
                ),
              ),
            ),
          if (extraCount >= 1)
            Positioned(
              left: 15,
              right: 15,
              top: extraCount >= 2 ? 5.5 : 0.0,
              height: 26,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    barFg.withValues(alpha: style.isDark ? 0.07 : 0.05),
                    barBg,
                  ).withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: barDivider, width: 0.75),
                ),
              ),
            ),
          Positioned(
            left: 6,
            right: 6,
            top: deckOffset,
            height: 48,
            child: useGlassBar
                ? LiquidGlassLens(
                    style: style.glassProvider!.createStyle(
                      context: context,
                      cornerRadius: 18,
                      isLiteOverride: true,
                      refractionIndex: style.isFull ? 1.10 : 1.05,
                      refractionWidth: 18.0,
                      borderWidth: 1.0,
                      color: barBg.withValues(alpha: style.isDark ? 0.78 : 0.86),
                    ),
                    child: frontContent,
                  )
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: barBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: barDivider, width: 0.85),
                      boxShadow: style.floatingShadow,
                    ),
                    child: frontContent,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Telegram-style full-screen 3D perspective card switcher for multiple open
/// minimized Mini Apps and browser tabs, including a Safari-style Regular /
/// Private («Частный доступ») switcher toggle when browser tabs are open.
class MiniAppTabsSwitcher extends StatefulWidget {
  final List<MiniAppSession> sessions;
  final ui.Image? frozenBackdropImage;
  final bool initialPrivateMode;
  final VoidCallback onDismiss;
  final ValueChanged<MiniAppSession> onSelectSession;
  final ValueChanged<MiniAppSession> onCloseSession;
  final VoidCallback onCloseAll;
  final ValueChanged<bool>? onOpenNewBrowserTab;

  /// Test-only override for supplying synthetic gyroscope events without native sensors.
  @visibleForTesting
  static Stream<GyroscopeEvent>? debugGyroscopeStreamOverride;

  const MiniAppTabsSwitcher({
    super.key,
    required this.sessions,
    this.frozenBackdropImage,
    this.initialPrivateMode = false,
    required this.onDismiss,
    required this.onSelectSession,
    required this.onCloseSession,
    required this.onCloseAll,
    this.onOpenNewBrowserTab,
  });

  @override
  State<MiniAppTabsSwitcher> createState() => _MiniAppTabsSwitcherState();
}

class _MiniAppTabsSwitcherState extends State<MiniAppTabsSwitcher>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _kBasePitchX = 0.14;
  static const double _kMaxGyroPitch = 0.055;
  static const double _kMaxGyroYaw = 0.075;
  static const double _kGyroDeadzone = 0.045;

  final ScrollController _scrollController = ScrollController();
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  late final AnimationController _gyroTicker;
  final ValueNotifier<Offset> _gyroTiltNotifier =
      ValueNotifier<Offset>(Offset.zero);
  late bool _privateMode;
  double _targetPitch = 0.0;
  double _targetYaw = 0.0;
  double _currentPitch = 0.0;
  double _currentYaw = 0.0;
  double _lastCullingOffset = 0.0;

  bool get _shouldUseGyro =>
      MiniAppTabsSwitcher.debugGyroscopeStreamOverride != null ||
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS));

  @override
  void initState() {
    super.initState();
    _privateMode = widget.initialPrivateMode;
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _gyroTicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onGyroTick);
    MiniAppSessionController.instance.addListener(_onControllerUpdated);
    _captureMissingPreviews();
    _syncGyroSubscription();
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (activeSafariWebAlertCount.value > 0) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.browserBack)) {
      _handleDismissTap();
      return true;
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant MiniAppTabsSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    _captureMissingPreviews();
    _syncGyroSubscription();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncGyroSubscription();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _stopGyroListening(resetTilt: false);
      _gyroTicker.stop();
    }
  }

  void _syncGyroSubscription() {
    if (!_shouldUseGyro) {
      _stopGyroListening(resetTilt: true);
      return;
    }
    if (_gyroSub != null) return;
    try {
      final stream = MiniAppTabsSwitcher.debugGyroscopeStreamOverride ??
          gyroscopeEventStream(samplingPeriod: SensorInterval.uiInterval);
      _gyroSub = stream.listen(
        (GyroscopeEvent event) {
          if (!_shouldUseGyro) {
            _stopGyroListening(resetTilt: true);
            return;
          }
          if (event.x.abs() < _kGyroDeadzone &&
              event.y.abs() < _kGyroDeadzone) {
            return;
          }
          _targetPitch = (_targetPitch - event.x * 0.022)
              .clamp(-_kMaxGyroPitch, _kMaxGyroPitch);
          _targetYaw = (_targetYaw + event.y * 0.028)
              .clamp(-_kMaxGyroYaw, _kMaxGyroYaw);
          if (!_gyroTicker.isAnimating && mounted) {
            _gyroTicker.repeat();
          }
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {}
  }

  void _stopGyroListening({bool resetTilt = true}) {
    _gyroSub?.cancel();
    _gyroSub = null;
    if (resetTilt) {
      if (_gyroTicker.isAnimating) {
        _gyroTicker.stop();
      }
      _targetPitch = 0.0;
      _targetYaw = 0.0;
      _currentPitch = 0.0;
      _currentYaw = 0.0;
      if (_gyroTiltNotifier.value != Offset.zero) {
        _gyroTiltNotifier.value = Offset.zero;
      }
    }
  }

  void _onGyroTick() {
    if (!mounted) return;
    _targetPitch *= 0.955;
    _targetYaw *= 0.955;

    final double nextPitch =
        _currentPitch + (_targetPitch - _currentPitch) * 0.24;
    final double nextYaw = _currentYaw + (_targetYaw - _currentYaw) * 0.24;
    _currentPitch = nextPitch;
    _currentYaw = nextYaw;

    final Offset prev = _gyroTiltNotifier.value;
    if ((prev.dx - nextPitch).abs() >= 0.0003 ||
        (prev.dy - nextYaw).abs() >= 0.0003) {
      _gyroTiltNotifier.value = Offset(nextPitch, nextYaw);
    }

    if (_currentPitch.abs() < 0.0005 &&
        _currentYaw.abs() < 0.0005 &&
        _targetPitch.abs() < 0.0008 &&
        _targetYaw.abs() < 0.0008) {
      _targetPitch = 0.0;
      _targetYaw = 0.0;
      _currentPitch = 0.0;
      _currentYaw = 0.0;
      if (_gyroTiltNotifier.value != Offset.zero) {
        _gyroTiltNotifier.value = Offset.zero;
      }
      if (_gyroTicker.isAnimating) {
        _gyroTicker.stop();
      }
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _stopGyroListening(resetTilt: false);
    _gyroTicker.dispose();
    _gyroTiltNotifier.dispose();
    MiniAppSessionController.instance.removeListener(_onControllerUpdated);
    super.dispose();
  }

  void _onControllerUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleDismissTap() {
    HapticUtils.tap();
    widget.onDismiss();
  }

  void _captureMissingPreviews() {
    for (final s in widget.sessions) {
      if (s.previewImageBytes == null &&
          s.domPreview == null &&
          s.controller != null) {
        unawaited(s.capturePreviewSnapshot());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = MiniAppJsBridge.resolveThemeColors(theme);
    final style = TheavSurfaceStyle.of(context);
    final mq = MediaQuery.of(context);
    final bool allowBlur = BlurUtils.shouldBlurMaterialHud(context);
    final ui.Image? frozenBg = widget.frozenBackdropImage;
    final Color dimTint = resolved.bodyBg.withValues(
      alpha: allowBlur ? (style.isDark ? 0.76 : 0.70) : 0.95,
    );

    final Widget backdrop;
    if (frozenBg != null && allowBlur) {
      backdrop = RepaintBoundary(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleDismissTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RawImage(
                image: frozenBg,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
              ColoredBox(color: dimTint),
            ],
          ),
        ),
      );
    } else {
      final blurFilter =
          allowBlur ? BlurUtils.createMaterialHudBlur(sigma: 16.0) : null;
      Widget liveBackdrop = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleDismissTap,
        child: ColoredBox(color: dimTint),
      );
      if (blurFilter != null) {
        liveBackdrop = ClipRect(
          child: BackdropFilter(
            filter: blurFilter,
            child: liveBackdrop,
          ),
        );
      }
      backdrop = RepaintBoundary(child: liveBackdrop);
    }

    final Widget closeAllChild = Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const ValueKey('mini_app_close_all_tabs_button'),
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          HapticUtils.tap();
          widget.onCloseAll();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Text(
            'Закрыть все вкладки',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: resolved.headerFg,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );

    final Widget closeAllPill = (style.isGlass && style.glassProvider != null)
        ? LiquidGlassLens(
            style: style.glassProvider!.createStyle(
              context: context,
              cornerRadius: 18,
              isLiteOverride: true,
              refractionIndex: 1.06,
              refractionWidth: 14.0,
              borderWidth: 1.0,
              color: resolved.headerBg
                  .withValues(alpha: style.isDark ? 0.72 : 0.84),
            ),
            child: closeAllChild,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: resolved.surfaceBg.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: resolved.divider, width: 0.7),
              boxShadow: style.floatingShadow,
            ),
            child: closeAllChild,
          );

    final bool showBrowserControls = widget.sessions.any((s) => s.isBrowser);
    final List<MiniAppSession> visibleSessions = showBrowserControls
        ? (_privateMode
            ? widget.sessions
                .where((s) => s.isBrowser && s.isIncognito)
                .toList()
            : widget.sessions
                .where((s) => !s.isBrowser || !s.isIncognito)
                .toList())
        : widget.sessions;

    final Widget? browserModeDock = showBrowserControls
        ? Positioned(
            bottom: math.max(14.0, mq.padding.bottom + 10.0),
            left: 16,
            right: 16,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: TheavSegmentedControl<bool>(
                      key: const ValueKey('browser_switcher_mode_segment'),
                      height: 38.0,
                      options: const [
                        TheavSegmentOption<bool>(
                          value: false,
                          label: 'Вкладки',
                        ),
                        TheavSegmentOption<bool>(
                          value: true,
                          label: 'Частный доступ',
                        ),
                      ],
                      selected: _privateMode,
                      onChanged: (nextPrivate) {
                        if (_privateMode == nextPrivate) return;
                        HapticUtils.selection();
                        setState(() => _privateMode = nextPrivate);
                      },
                    ),
                  ),
                  if (widget.onOpenNewBrowserTab != null) ...[
                    const SizedBox(width: 8),
                    TheavFloatingSurface(
                      borderRadius: 19,
                      enableFlex: false,
                      refractionIndex: 1.06,
                      refractionWidth: 14.0,
                      padding: EdgeInsets.zero,
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          key: const ValueKey(
                            'browser_switcher_new_tab_button',
                          ),
                          borderRadius: BorderRadius.circular(19),
                          onTap: () {
                            HapticUtils.tap();
                            widget.onOpenNewBrowserTab!(_privateMode);
                          },
                          child: SizedBox(
                            width: 38,
                            height: 38,
                            child: Icon(
                              Icons.add_rounded,
                              size: 22,
                              color: resolved.headerFg,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )
        : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: backdrop),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double availH = constraints.maxHeight;
              final double cardHeight = (availH * 0.56).clamp(240.0, 380.0);
              final int n = visibleSessions.length;
              final double stepY = n <= 1
                  ? 0.0
                  : ((availH - cardHeight - (showBrowserControls ? 78.0 : 24.0)) /
                          (n - 1))
                      .clamp(200.0, 268.0);
              final double stackHeight =
                  n == 0 ? 0.0 : cardHeight + (n - 1) * stepY;
              final double topPad =
                  ((availH - mq.padding.top - 72.0 - stackHeight) * 0.30)
                      .clamp(4.0, 48.0);
              final double contentTopOffset = mq.padding.top + 64 + topPad;
              final double scrollOffset = _scrollController.hasClients
                  ? _scrollController.offset
                  : _lastCullingOffset;
              final int firstIdx;
              final int lastIdx;
              if (n == 0) {
                firstIdx = 0;
                lastIdx = -1;
              } else if (n <= 4 || stepY <= 0.0) {
                firstIdx = 0;
                lastIdx = n - 1;
              } else {
                final double viewTop = scrollOffset - contentTopOffset;
                final double viewBottom =
                    scrollOffset + availH - contentTopOffset;
                firstIdx = (((viewTop - cardHeight) / stepY).floor() - 1)
                    .clamp(0, n - 1);
                lastIdx =
                    ((viewBottom / stepY).ceil() + 1).clamp(firstIdx, n - 1);
              }

              if (n == 0 && showBrowserControls) {
                return Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _handleDismissTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _privateMode
                                ? Icons.visibility_off_rounded
                                : Icons.tab_rounded,
                            size: 40,
                            color: resolved.palette.subtext,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _privateMode
                                ? 'Частный доступ'
                                : 'Нет открытых вкладок',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: resolved.headerFg,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _privateMode
                                ? 'История посещений, cookie и пароли не сохраняются, а данные удаляются при закрытии.'
                                : 'Откройте новую вкладку или перейдите в частный доступ.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.38,
                              color: resolved.palette.subtext,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          if (widget.onOpenNewBrowserTab != null) ...[
                            const SizedBox(height: 18),
                            TheavFloatingPillButton(
                              key: const ValueKey(
                                'browser_switcher_empty_new_tab_btn',
                              ),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: _privateMode
                                  ? 'Открыть частную вкладку'
                                  : 'Новая вкладка',
                              isPrimary: true,
                              onTap: () =>
                                  widget.onOpenNewBrowserTab!(_privateMode),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }

              return RepaintBoundary(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification notification) {
                    if (notification is ScrollUpdateNotification &&
                        n > 4 &&
                        stepY > 0.0 &&
                        (notification.metrics.pixels - _lastCullingOffset)
                                .abs() >=
                            stepY * 0.45) {
                      _lastCullingOffset = notification.metrics.pixels;
                      if (mounted) {
                        setState(() {});
                      }
                    }
                    return false;
                  },
                  child: GestureDetector(
                    key: const ValueKey('mini_app_tabs_empty_area_detector'),
                    behavior: HitTestBehavior.translucent,
                    onTap: _handleDismissTap,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        contentTopOffset,
                        16,
                        math.max(
                          showBrowserControls ? 76.0 : 24.0,
                          mq.padding.bottom + (showBrowserControls ? 68 : 16),
                        ),
                      ),
                      child: SizedBox(
                        height: stackHeight,
                        width: double.infinity,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (int i = firstIdx; i <= lastIdx; i++)
                              _buildStackedCard(
                                context,
                                session: visibleSessions[i],
                                index: i,
                                totalCount: n,
                                top: i * stepY,
                                cardHeight: cardHeight,
                                resolved: resolved,
                                style: style,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (visibleSessions.isNotEmpty)
          Positioned(
            top: mq.padding.top + 14,
            left: 0,
            right: 0,
            child: Center(
              child: RepaintBoundary(
                child: SizedBox(height: 36, child: closeAllPill),
              ),
            ),
          ),
        if (browserModeDock != null) browserModeDock,
      ],
    );
  }

  Widget _buildStackedCard(
    BuildContext context, {
    required MiniAppSession session,
    required int index,
    required int totalCount,
    required double top,
    required double cardHeight,
    required MiniAppThemeColors resolved,
    required TheavSurfaceStyle style,
  }) {
    final Color cardBodyBg = session.customBackgroundColor ?? resolved.bodyBg;
    final Color cardHeaderBg = session.customHeaderColor ?? resolved.headerBg;
    final bool isCardHeaderDark = cardHeaderBg.computeLuminance() <= 0.55;
    final Color cardHeaderFg = session.customHeaderColor != null
        ? (isCardHeaderDark ? Colors.white : Colors.black87)
        : resolved.headerFg;
    final Color cardDivider = session.customHeaderColor != null
        ? cardHeaderFg.withValues(alpha: 0.14)
        : resolved.divider;
    final Color sealColor = session.customHeaderColor != null
        ? cardHeaderFg.withValues(alpha: 0.85)
        : resolved.palette.primary;
    final Color sealCheckColor =
        (sealColor.computeLuminance() - cardHeaderBg.computeLuminance()).abs() >
                0.18
            ? cardHeaderBg
            : resolved.palette.onPrimary;
    final String unameLower = (session.botUsername.isNotEmpty
            ? session.botUsername
            : session.launchData.botUsername)
        .toLowerCase()
        .trim();
    final bool isVerified = !session.isBrowser &&
        (session.isVerified ||
            session.launchData.botIsVerified ||
            unameLower == 'botmother' ||
            unameLower == 'botfather' ||
            unameLower == 'walt');

    final double depthFactor =
        totalCount <= 1 ? 1.0 : (0.82 + 0.18 * (index / (totalCount - 1)));

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      height: cardHeight,
      child: Dismissible(
        key: ValueKey('mini_app_tab_dismiss_${session.id}'),
        direction: DismissDirection.horizontal,
        onDismissed: (_) => widget.onCloseSession(session),
        child: ValueListenableBuilder<Offset>(
          valueListenable: _gyroTiltNotifier,
          child: RepaintBoundary(
            child: GestureDetector(
              key: ValueKey('mini_app_tab_card_${session.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticUtils.selection();
                widget.onSelectSession(session);
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cardBodyBg,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: style.isDark ? 0.36 : 0.14),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cardDivider, width: 0.8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.hardEdge,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: cardHeaderBg,
                            border: Border(
                              bottom: BorderSide(color: cardDivider, width: 0.75),
                            ),
                          ),
                          child: Material(
                            type: MaterialType.transparency,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 46,
                                  height: 48,
                                  child: Semantics(
                                    button: true,
                                    label: 'Закрыть',
                                    child: InkWell(
                                      key: ValueKey(
                                          'mini_app_tab_close_${session.id}'),
                                      borderRadius: BorderRadius.circular(24),
                                      onTap: () {
                                        HapticUtils.tap();
                                        widget.onCloseSession(session);
                                      },
                                      child: Center(
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 22,
                                          color: cardHeaderFg,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 14),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (session.isBrowser) ...[
                                          Icon(
                                            session.isIncognito
                                                ? Icons.visibility_off_rounded
                                                : (session.currentUrl
                                                        .toLowerCase()
                                                        .startsWith('https://')
                                                    ? Icons.lock_outline_rounded
                                                    : Icons.public_rounded),
                                            size: 16,
                                            color: session.isIncognito
                                                ? resolved.palette.primary
                                                : cardHeaderFg
                                                    .withValues(alpha: 0.78),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Flexible(
                                          child: Text(
                                            session.displayTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 16.5,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.15,
                                              color: cardHeaderFg,
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                        ),
                                        if (session.isBrowser &&
                                            session.isIncognito) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            key: ValueKey(
                                              'mini_app_tab_incognito_badge_${session.id}',
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: resolved.palette.primary
                                                  .withValues(alpha: 0.16),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              'Частный',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: resolved.palette.primary,
                                                decoration: TextDecoration.none,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (isVerified) ...[
                                          const SizedBox(width: 6),
                                          MiniAppVerifiedSeal(
                                            size: 17,
                                            color: sealColor,
                                            checkColor: sealCheckColor,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: _MiniAppSessionCardPreview(
                            key: ValueKey('mini_app_tab_preview_${session.id}'),
                            session: session,
                            resolved: resolved,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          builder: (context, gyroTilt, cardChild) {
            final double pitch = _kBasePitchX + gyroTilt.dx * depthFactor;
            final double yaw = gyroTilt.dy * depthFactor;
            final double shiftX = yaw * 18.0;
            final double shiftY = (gyroTilt.dx * depthFactor) * 10.0;
            final Matrix4 tiltMatrix = Matrix4.identity()
              ..translateByDouble(shiftX, shiftY, 0.0, 1.0)
              ..setEntry(3, 2, 0.0011)
              ..rotateX(pitch)
              ..rotateY(yaw);
            return Transform(
              key: ValueKey('mini_app_tab_transform_${session.id}'),
              alignment: Alignment.topCenter,
              transform: tiltMatrix,
              child: cardChild,
            );
          },
        ),
      ),
    );
  }
}

/// Renders the content body of a [MiniAppTabsSwitcher] card in 3 tiers:
/// 1) native viewport screenshot [MiniAppSession.previewImageBytes],
/// 2) extracted visible DOM blocks [MiniAppSession.domPreview], or
/// 3) rich contextual preview tailored to the app or webpage.
class _MiniAppSessionCardPreview extends StatelessWidget {
  final MiniAppSession session;
  final MiniAppThemeColors resolved;

  const _MiniAppSessionCardPreview({
    super.key,
    required this.session,
    required this.resolved,
  });

  @override
  Widget build(BuildContext context) {
    final Color cardBg = session.domPreview?.bgColor ??
        session.browserCanvasColor ??
        session.customBackgroundColor ??
        resolved.bodyBg;
    final ImageProvider? provider = session.previewImageProvider;
    if (provider != null) {
      return ColoredBox(
        color: cardBg,
        child: Image(
          image: provider,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          width: double.infinity,
          height: double.infinity,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
        ),
      );
    }

    final MiniAppDomPreview? dom = session.domPreview;
    if (dom != null && dom.blocks.isNotEmpty) {
      return _MiniAppDomSnapshotView(
        preview: dom,
        fallbackBg: cardBg,
        resolved: resolved,
      );
    }

    return _MiniAppContextualFallbackView(
      session: session,
      cardBg: cardBg,
      resolved: resolved,
    );
  }
}

class _MiniAppDomSnapshotView extends StatelessWidget {
  final MiniAppDomPreview preview;
  final Color fallbackBg;
  final MiniAppThemeColors resolved;

  const _MiniAppDomSnapshotView({
    required this.preview,
    required this.fallbackBg,
    required this.resolved,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = preview.bgColor ?? fallbackBg;
    final bool isBgDark = bg.computeLuminance() <= 0.55;
    final Color defaultFg = preview.textColor ??
        (isBgDark ? Colors.white : const Color(0xFF111827));
    final Color subFg = defaultFg.withValues(alpha: 0.65);
    final Color surface = isBgDark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.06), bg)
        : Color.alphaBlend(Colors.black.withValues(alpha: 0.04), bg);
    final Color accent = preview.accentColor ?? resolved.palette.primary;
    final Color borderColor = defaultFg.withValues(alpha: 0.12);

    return ColoredBox(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final block in preview.blocks.take(6)) ...[
                  _buildBlock(
                    block,
                    defaultFg: defaultFg,
                    subFg: subFg,
                    surface: surface,
                    accent: accent,
                    borderColor: borderColor,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlock(
    MiniAppDomBlock block, {
    required Color defaultFg,
    required Color subFg,
    required Color surface,
    required Color accent,
    required Color borderColor,
  }) {
    final Color itemBg = block.cardColor ?? surface;
    final Color itemFg = block.fgColor ?? defaultFg;
    final Color itemSub = itemFg.withValues(alpha: 0.64);

    if (block.kind == 'button') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: block.cardColor ?? accent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          block.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: block.fgColor ?? Colors.white,
            decoration: TextDecoration.none,
          ),
        ),
      );
    }

    if (block.kind == 'hero') {
      return Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(accent.withValues(alpha: 0.18), itemBg),
              itemBg,
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 0.7),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              block.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: itemFg,
                decoration: TextDecoration.none,
              ),
            ),
            if (block.subtitle.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                block.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: itemSub,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (block.kind == 'row') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: itemBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 0.6),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Text(
                block.leadingBadge.isNotEmpty
                    ? block.leadingBadge
                    : block.title.characters.first.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accent,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    block.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: itemFg,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (block.subtitle.isNotEmpty)
                    Text(
                      block.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: itemSub,
                        decoration: TextDecoration.none,
                      ),
                    ),
                ],
              ),
            ),
            if (block.trailing.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                block.trailing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: itemFg,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (block.kind == 'heading') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Text(
          block.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: itemFg,
            decoration: TextDecoration.none,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: itemBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            block.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: itemFg,
              decoration: TextDecoration.none,
            ),
          ),
          if (block.subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              block.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: itemSub,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniAppContextualFallbackView extends StatelessWidget {
  final MiniAppSession session;
  final Color cardBg;
  final MiniAppThemeColors resolved;

  const _MiniAppContextualFallbackView({
    required this.session,
    required this.cardBg,
    required this.resolved,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = cardBg.computeLuminance() <= 0.55;
    final Color fg = isDark ? Colors.white : const Color(0xFF111827);
    final Color sub = fg.withValues(alpha: 0.58);
    final Color card = isDark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.06), cardBg)
        : Color.alphaBlend(Colors.black.withValues(alpha: 0.04), cardBg);
    final Color border = fg.withValues(alpha: 0.11);
    final Color primary = resolved.palette.primary;

    final String unameLower = (session.botUsername.isNotEmpty
            ? session.botUsername
            : session.launchData.botUsername)
        .toLowerCase()
        .trim();
    final String urlLower = session.launchData.url.toLowerCase();

    if (session.isBrowser) {
      final String host = BrowserDataService.extractHost(session.currentUrl);
      return ColoredBox(
        color: cardBg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: border, width: 0.6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.public_rounded, size: 14, color: primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: sub,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border, width: 0.6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _previewBar(widthFactor: 0.72, height: 11, color: fg.withValues(alpha: 0.22)),
                      const SizedBox(height: 8),
                      _previewBar(widthFactor: 0.94, height: 8, color: fg.withValues(alpha: 0.12)),
                      const SizedBox(height: 5),
                      _previewBar(widthFactor: 0.85, height: 8, color: fg.withValues(alpha: 0.12)),
                      const SizedBox(height: 5),
                      _previewBar(widthFactor: 0.60, height: 8, color: fg.withValues(alpha: 0.12)),
                      const Spacer(),
                      Container(
                        height: 26,
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          session.currentUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: primary,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (unameLower == 'walt' ||
        unameLower == 'walt_bot' ||
        urlLower.contains('/miniapps/wallet')) {
      return ColoredBox(
        color: cardBg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color.alphaBlend(primary.withValues(alpha: 0.20), card),
                      card,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border, width: 0.7),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Кошелёк • Баланс счёта',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: sub,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _previewBar(
                      widthFactor: 0.45,
                      height: 14,
                      color: fg.withValues(alpha: 0.26),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _chipBadge('Пополнить', primary),
                        const SizedBox(width: 6),
                        _chipBadge('Перевод', fg.withValues(alpha: 0.14), textColor: fg),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _miniRowTile('THV', 'Theav Coin', const Color(0xFF00B4D8), fg, sub, card, border),
              const SizedBox(height: 6),
              _miniRowTile('\$', 'US Dollar', const Color(0xFF10B981), fg, sub, card, border),
            ],
          ),
        ),
      );
    }

    if (unameLower == 'botmother' ||
        unameLower == 'botfather' ||
        urlLower.contains('/miniapps/studio')) {
      return ColoredBox(
        color: cardBg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color.alphaBlend(primary.withValues(alpha: 0.20), card),
                      card,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border, width: 0.7),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bot Studio • Управление ботами',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fg,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _previewBar(widthFactor: 0.68, height: 8, color: fg.withValues(alpha: 0.16)),
                    const SizedBox(height: 8),
                    _chipBadge('Создать бота', primary),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _miniRowTile('BM', 'Мои боты и команды', primary, fg, sub, card, border),
              const SizedBox(height: 6),
              _miniRowTile('WA', 'WebApp & Webhook', const Color(0xFF7C3AED), fg, sub, card, border),
            ],
          ),
        ),
      );
    }

    final String handleLabel = unameLower.isNotEmpty ? '@$unameLower' : 'Mini App';
    return ColoredBox(
      color: cardBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border, width: 0.7),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    handleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: primary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _previewBar(widthFactor: 0.76, height: 10, color: fg.withValues(alpha: 0.22)),
                  const SizedBox(height: 5),
                  _previewBar(widthFactor: 0.52, height: 8, color: fg.withValues(alpha: 0.14)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border, width: 0.6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _previewBar(widthFactor: 0.88, height: 9, color: fg.withValues(alpha: 0.14)),
                    const SizedBox(height: 6),
                    _previewBar(widthFactor: 0.64, height: 9, color: fg.withValues(alpha: 0.12)),
                    const Spacer(),
                    Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewBar({
    required double widthFactor,
    required double height,
    required Color color,
  }) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }

  Widget _chipBadge(String text, Color bg, {Color textColor = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: textColor,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  Widget _miniRowTile(
    String code,
    String label,
    Color badgeColor,
    Color fg,
    Color sub,
    Color card,
    Color border,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: border, width: 0.6),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: Text(
              code,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: fg,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Container(
            width: 38,
            height: 8,
            decoration: BoxDecoration(
              color: sub.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Zero-rebuild vertical drag offset wrapper shared by full-screen WebView sheets.
class MiniAppDragOffset extends SingleChildRenderObjectWidget {
  final double offsetY;

  const MiniAppDragOffset({
    super.key,
    required this.offsetY,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderMiniAppDragOffset(offsetY);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderMiniAppDragOffset renderObject,
  ) {
    renderObject.offsetY = offsetY;
  }
}

class RenderMiniAppDragOffset extends RenderProxyBox {
  RenderMiniAppDragOffset(this._offsetY);

  final LayerHandle<TransformLayer> _transformHandle =
      LayerHandle<TransformLayer>();

  double _offsetY;
  double get offsetY => _offsetY;
  set offsetY(double value) {
    if ((_offsetY - value).abs() < 0.001) return;
    _offsetY = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _offsetY.abs() > 0.01;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_offsetY.abs() <= 0.01) {
      _transformHandle.layer = null;
      super.paint(context, offset);
      return;
    }
    _transformHandle.layer = context.pushTransform(
      needsCompositing,
      offset,
      Matrix4.translationValues(0.0, _offsetY, 0.0),
      super.paint,
      oldLayer: _transformHandle.layer,
    );
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    if (_offsetY.abs() > 0.01) {
      transform.translateByDouble(0.0, _offsetY, 0.0, 1.0);
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      hitTestChildren(result, position: position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_offsetY.abs() <= 0.01) {
      return super.hitTestChildren(result, position: position);
    }
    return result.addWithPaintOffset(
      offset: Offset(0.0, _offsetY),
      position: position,
      hitTest: (BoxHitTestResult r, Offset p) =>
          super.hitTestChildren(r, position: p),
    );
  }

  @override
  void dispose() {
    _transformHandle.layer = null;
    super.dispose();
  }
}

/// Shrink-wraps width to [child] while ensuring a minimum vertical layout budget
/// ([minContentHeight]) so a cross-fading two-line pill never overflows during
/// height transitions between expanded (`44dp`) and compact (`26dp`) states.
class _ShrinkWrapVerticalClip extends SingleChildRenderObjectWidget {
  final double minContentHeight;

  const _ShrinkWrapVerticalClip({
    required this.minContentHeight,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderShrinkWrapVerticalClip(minContentHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderShrinkWrapVerticalClip renderObject,
  ) {
    renderObject.minContentHeight = minContentHeight;
  }
}

class _RenderShrinkWrapVerticalClip extends RenderShiftedBox {
  _RenderShrinkWrapVerticalClip(this._minContentHeight) : super(null);

  double _minContentHeight;
  double get minContentHeight => _minContentHeight;
  set minContentHeight(double value) {
    if (_minContentHeight == value) return;
    _minContentHeight = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final RenderBox? child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    final double boundedH = constraints.hasBoundedHeight
        ? math.max(constraints.maxHeight, minContentHeight)
        : double.infinity;
    child.layout(
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
        minHeight: 0.0,
        maxHeight: boundedH,
      ),
      parentUsesSize: true,
    );
    size = constraints.constrain(child.size);
    final double dy = (size.height - child.size.height) * 0.5;
    (child.parentData! as BoxParentData).offset = Offset(0.0, dy);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final RenderBox? child = this.child;
    if (child == null) return;
    if (child.size.height > size.height + 0.01) {
      context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        super.paint,
      );
    } else {
      super.paint(context, offset);
    }
  }
}

/// Floating oval HUD capsule shared between [MiniAppWebViewSheet] and [InAppBrowserSheet].
///
/// Renders lightweight `isLiteOverride` [LiquidGlassLens] islands in glass mode,
/// single-pass grouped frosted Material HUD (`BackdropFilter.grouped`) when
/// [PowerSavingProvider] allows blur in Material mode, or an opaque elevated
/// capsule when blur is disabled. Never mounts inside WebView viewport containers.
class WebViewFloatingCapsule extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double? minWidth;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final Color? colorOverride;
  final bool visible;

  const WebViewFloatingCapsule({
    super.key,
    required this.child,
    this.borderRadius = 22.0,
    this.minWidth,
    this.height = 44.0,
    this.padding,
    this.colorOverride,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }
    if (minWidth != null || height != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minWidth ?? 0.0,
          minHeight: height ?? 0.0,
          maxHeight: height ?? double.infinity,
        ),
        child: content,
      );
    }

    if (style.isGlass && style.glassProvider != null) {
      final Color glassFill = colorOverride != null
          ? colorOverride!.withValues(
              alpha: math.min(colorOverride!.a, style.isDark ? 0.78 : 0.84),
            )
          : style.hudFill;
      return LiquidGlassLens(
        visibility: visible,
        style: style.glassProvider!.createStyle(
          context: context,
          cornerRadius: borderRadius,
          refractionIndex: 1.1,
          refractionWidth: 22.0,
          borderWidth: 1.1,
          color: glassFill,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: content,
        ),
      );
    }

    if (!visible) {
      return SizedBox(width: minWidth, height: height);
    }

    final blurFilter = style.getMaterialHudBlurFilter(sigma: 10.0);
    final Color fill = colorOverride != null
        ? BlurUtils.resolveMaterialHudColor(
            colorOverride!,
            isDark: style.isDark,
            blurEnabled: blurFilter != null,
            darkAlpha: 0.86,
            lightAlpha: 0.88,
          )
        : style.hudFill;
    final Color borderColor = colorOverride != null
        ? (colorOverride!.computeLuminance() <= 0.55
            ? Colors.white.withValues(alpha: blurFilter != null ? 0.14 : 0.10)
            : Colors.black.withValues(alpha: blurFilter != null ? 0.10 : 0.08))
        : style.hudBorder;

    Widget box = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor,
          width: blurFilter != null ? 0.65 : 0.55,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: content,
      ),
    );

    if (blurFilter != null) {
      box = BackdropFilter.grouped(
        filter: blurFilter,
        child: box,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: style.floatingShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: box,
      ),
    );
  }
}

/// Three-island floating oval header (`[close/back]`, `[title/domain + progress]`,
/// `[minimize | more]`) matching the floating chat chrome aesthetic, with an
/// inline morphing right menu (`LiquidGlassMorph` / animated Material morph)
/// and optional Safari iOS 26 compact domain-pill mode.
class WebViewFloatingHeader extends StatelessWidget {
  final double topInset;
  final Widget leadingChild;
  final Widget centerChild;
  final List<Widget> trailingActions;
  final ValueListenable<double>? progressListenable;
  final Color? capsuleColorOverride;
  final Color? progressColor;
  final VoidCallback? onCenterTap;
  final VoidCallback? onCenterLongPress;
  final bool isCompact;
  final VoidCallback? onExpandCompact;
  final Widget? compactCenterChild;
  final bool isMenuOpen;
  final VoidCallback? onDismissMenu;
  final Widget? expandedMenuChild;
  final double expandedMenuWidth;
  final double expandedMenuHeight;
  final double collapsedRightWidth;
  final bool isCenterPopoverOpen;
  final VoidCallback? onDismissCenterPopover;
  final Widget? expandedCenterPopoverChild;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureDragCancelCallback? onVerticalDragCancel;

  const WebViewFloatingHeader({
    super.key,
    required this.topInset,
    required this.leadingChild,
    required this.centerChild,
    required this.trailingActions,
    this.progressListenable,
    this.capsuleColorOverride,
    this.progressColor,
    this.onCenterTap,
    this.onCenterLongPress,
    this.isCompact = false,
    this.onExpandCompact,
    this.compactCenterChild,
    this.isMenuOpen = false,
    this.onDismissMenu,
    this.expandedMenuChild,
    this.expandedMenuWidth = 248.0,
    this.expandedMenuHeight = 240.0,
    this.collapsedRightWidth = 84.0,
    this.isCenterPopoverOpen = false,
    this.onDismissCenterPopover,
    this.expandedCenterPopoverChild,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onVerticalDragCancel,
  });

  Widget _buildPillBody(
    Widget inner, {
    required double horizontalPad,
    required Color barAccent,
  }) {
    final Widget centered = _ShrinkWrapVerticalClip(
      minContentHeight: 40.0,
      child: Center(
        widthFactor: 1.0,
        child: inner,
      ),
    );
    if (progressListenable == null) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPad),
        child: centered,
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPad),
          child: centered,
        ),
        Positioned(
          left: 10,
          right: 10,
          bottom: 0,
          child: ValueListenableBuilder<double>(
            valueListenable: progressListenable!,
            builder: (context, value, _) {
              if (value <= 0.0 || value >= 1.0) {
                return const SizedBox.shrink();
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: value.clamp(0.06, 1.0),
                    child: SizedBox(
                      height: 2.2,
                      child: ColoredBox(color: barAccent),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final Color barAccent = progressColor ?? palette.primary;
    final media = MediaQuery.of(context);
    final double screenWidth = media.size.width;
    final double fullHeight = media.size.height;
    final double adaptiveMenuWidth = math.min(
      expandedMenuWidth,
      math.max(collapsedRightWidth + 40.0, screenWidth - 24.0),
    );
    final bool menuExpanded = isMenuOpen && expandedMenuChild != null;
    final bool centerPopoverExpanded =
        isCenterPopoverOpen && expandedCenterPopoverChild != null;
    final bool anyHeaderOverlayOpen = menuExpanded || centerPopoverExpanded;
    final bool effectiveCompact = isCompact && !anyHeaderOverlayOpen;
    final double normalHeight = topInset + 60.0;
    final double compactHeight = topInset + 42.0;
    final double centerFieldHeight =
        math.max(44.0, fullHeight - topInset - 16.0);

    final Widget expandedPillBody = KeyedSubtree(
      key: const ValueKey('webview_center_expanded'),
      child: _buildPillBody(
        centerChild,
        horizontalPad: 14.0,
        barAccent: barAccent,
      ),
    );

    final Widget collapsedBox = SizedBox(
      key: const ValueKey('webview_right_pill_collapsed'),
      width: collapsedRightWidth,
      height: 44.0,
      child: OverflowBox(
        minWidth: collapsedRightWidth,
        maxWidth: collapsedRightWidth,
        minHeight: 44.0,
        maxHeight: 44.0,
        alignment: Alignment.centerRight,
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: trailingActions,
            ),
          ),
        ),
      ),
    );

    final Widget expandedBox = expandedMenuChild != null
        ? SizedBox(
            key: const ValueKey('webview_right_pill_expanded'),
            width: adaptiveMenuWidth,
            height: expandedMenuHeight,
            child: OverflowBox(
              minWidth: adaptiveMenuWidth,
              maxWidth: adaptiveMenuWidth,
              minHeight: expandedMenuHeight,
              maxHeight: expandedMenuHeight,
              alignment: Alignment.topRight,
              child: Material(
                type: MaterialType.transparency,
                child: expandedMenuChild,
              ),
            ),
          )
        : collapsedBox;

    final bool useGlass = style.isGlass && style.glassProvider != null;
    final LiquidGlassStyle? morphStyle;
    final Widget rightMorphChild;

    if (useGlass) {
      final Color glassFill = capsuleColorOverride != null
          ? capsuleColorOverride!.withValues(
              alpha: math.min(
                capsuleColorOverride!.a,
                style.isDark ? 0.78 : 0.84,
              ),
            )
          : style.hudFill;
      morphStyle = style.glassProvider!.createStyle(
        context: context,
        cornerRadius: 22.0,
        refractionIndex: 1.1,
        refractionWidth: 22.0,
        borderWidth: 1.1,
        color: glassFill,
      );
      rightMorphChild = LiquidGlassBatch.exclude(
        child: SizedBox(
          width: adaptiveMenuWidth,
          height: expandedMenuHeight,
          child: LiquidGlassMorph(
            key: const ValueKey('webview_right_morph'),
            alignment: Alignment.topRight,
            motion: const LiquidGlassMorphMotion(
              stiffness: 265,
              damping: 26.5,
              stretch: 0.22,
              anchor: Alignment.topRight,
              blended: false,
              advanced: LiquidGlassMorphAdvanced(
                leadBounce: 0.03,
                followDelay: 0.0,
                newScaleFrom: 0.90,
                oldScaleTo: 0.92,
                contentBlur: 6.5,
                contentInStart: 0.18,
                contentInEnd: 0.78,
                contentOutEnd: 0.28,
                thickenBlur: 0.28,
                thickenRefraction: 0.22,
              ),
            ),
            smoothness: 0,
            style: morphStyle,
            child: menuExpanded ? expandedBox : collapsedBox,
          ),
        ),
      );
    } else {
      morphStyle = null;
      final blurFilter = style.getMaterialHudBlurFilter(sigma: 10.0);
      final Color fill = capsuleColorOverride != null
          ? BlurUtils.resolveMaterialHudColor(
              capsuleColorOverride!,
              isDark: style.isDark,
              blurEnabled: blurFilter != null,
              darkAlpha: 0.86,
              lightAlpha: 0.88,
            )
          : style.hudFill;
      final Color borderColor = capsuleColorOverride != null
          ? (capsuleColorOverride!.computeLuminance() <= 0.55
              ? Colors.white.withValues(alpha: blurFilter != null ? 0.14 : 0.10)
              : Colors.black.withValues(alpha: blurFilter != null ? 0.10 : 0.08))
          : style.hudBorder;
      Widget surfaceBox = DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(22.0),
          border: Border.all(
            color: borderColor,
            width: blurFilter != null ? 0.65 : 0.55,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 170),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                alignment: Alignment.topRight,
                scale: Tween<double>(begin: 0.92, end: 1.0).animate(anim),
                child: child,
              ),
            ),
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.topRight,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            child: menuExpanded ? expandedBox : collapsedBox,
          ),
        ),
      );
      if (blurFilter != null) {
        surfaceBox = BackdropFilter.grouped(
          filter: blurFilter,
          child: surfaceBox,
        );
      }
      rightMorphChild = AnimatedContainer(
        key: const ValueKey('webview_right_matte_morph'),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: menuExpanded ? adaptiveMenuWidth : collapsedRightWidth,
        height: menuExpanded ? expandedMenuHeight : 44.0,
        alignment: Alignment.topRight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22.0),
            boxShadow: style.floatingShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22.0),
            child: surfaceBox,
          ),
        ),
      );
    }

    final Widget leadingBox = SizedBox(
      width: 44,
      height: 44,
      child: Center(child: leadingChild),
    );

    final double expandTarget = effectiveCompact ? 0.0 : 1.0;
    const double expandedLeft = 12.0 + 44.0 + 8.0;
    final double expandedRight = 12.0 + collapsedRightWidth + 8.0;
    const double compactHoriz = 44.0;
    final double maxExpandedWidth =
        math.max(96.0, screenWidth - expandedLeft - expandedRight);
    final double maxCompactWidth =
        math.max(84.0, screenWidth - compactHoriz * 2.0);
    final double expandedShiftX = (expandedLeft - expandedRight) * 0.5;
    final bool hasCompactCenter = compactCenterChild != null;
    final bool hasCenterMorph =
        hasCompactCenter || expandedCenterPopoverChild != null;

    Widget? glassCenterMorph;
    if (useGlass && morphStyle != null && hasCenterMorph) {
      final Widget expandedCenterMorphBox = ConstrainedBox(
        key: const ValueKey('webview_center_morph_expanded'),
        constraints: BoxConstraints(
          minWidth: 88.0,
          maxWidth: maxExpandedWidth,
          minHeight: 44.0,
          maxHeight: 44.0,
        ),
        child: GestureDetector(
          key: const ValueKey('webview_header_center_pill'),
          behavior: HitTestBehavior.opaque,
          onTap: onCenterTap,
          onLongPress: onCenterLongPress,
          onVerticalDragStart: anyHeaderOverlayOpen ? null : onVerticalDragStart,
          onVerticalDragUpdate:
              anyHeaderOverlayOpen ? null : onVerticalDragUpdate,
          onVerticalDragEnd: anyHeaderOverlayOpen ? null : onVerticalDragEnd,
          onVerticalDragCancel:
              anyHeaderOverlayOpen ? null : onVerticalDragCancel,
          child: Material(
            type: MaterialType.transparency,
            child: _buildPillBody(
              centerChild,
              horizontalPad: 14.0,
              barAccent: barAccent,
            ),
          ),
        ),
      );

      final Widget? compactCenterMorphBox = compactCenterChild != null
          ? ConstrainedBox(
              key: const ValueKey('webview_center_morph_compact'),
              constraints: BoxConstraints(
                minWidth: 72.0,
                maxWidth: maxCompactWidth,
                minHeight: 26.0,
                maxHeight: 26.0,
              ),
              child: GestureDetector(
                key: const ValueKey('webview_header_center_pill'),
                behavior: HitTestBehavior.opaque,
                onTap: onExpandCompact ?? onCenterTap,
                onLongPress: onCenterLongPress,
                child: Material(
                  type: MaterialType.transparency,
                  child: _buildPillBody(
                    compactCenterChild!,
                    horizontalPad: 11.0,
                    barAccent: barAccent,
                  ),
                ),
              ),
            )
          : null;

      final Widget? popoverCenterMorphBox = expandedCenterPopoverChild != null
          ? KeyedSubtree(
              key: const ValueKey('webview_center_morph_popover'),
              child: Material(
                type: MaterialType.transparency,
                child: expandedCenterPopoverChild!,
              ),
            )
          : null;

      final Widget activeGlassCenterChild = centerPopoverExpanded
          ? popoverCenterMorphBox!
          : (effectiveCompact && compactCenterMorphBox != null
              ? compactCenterMorphBox
              : expandedCenterMorphBox);

      final LiquidGlassStyle centerPopoverGlassStyle =
          style.glassProvider!.createStyle(
        context: context,
        cornerRadius: 26.0,
        refractionIndex: 1.1,
        refractionWidth: 22.0,
        borderWidth: 1.1,
        color: style.hudFill.withValues(alpha: style.isDark ? 0.82 : 0.88),
      );

      glassCenterMorph = LiquidGlassBatch.exclude(
        child: LiquidGlassMorph(
          key: const ValueKey('webview_center_morph'),
          alignment: Alignment.topCenter,
          motion: centerPopoverExpanded
              ? const LiquidGlassMorphMotion(
                  stiffness: 245,
                  damping: 24.5,
                  stretch: 0.26,
                  anchor: Alignment.topCenter,
                  blended: false,
                  advanced: LiquidGlassMorphAdvanced(
                    leadBounce: 0.04,
                    followDelay: 0.0,
                    newScaleFrom: 0.88,
                    oldScaleTo: 0.90,
                    contentBlur: 7.0,
                    contentInStart: 0.20,
                    contentInEnd: 0.78,
                    contentOutEnd: 0.30,
                    thickenBlur: 0.30,
                    thickenRefraction: 0.25,
                  ),
                )
              : const LiquidGlassMorphMotion(
                  stiffness: 320,
                  damping: 35.8,
                  stretch: 0.12,
                  blended: false,
                  advanced: LiquidGlassMorphAdvanced(
                    leadBounce: 0.0,
                    followDelay: 0.0,
                    contentFollow: 1.0,
                    contentBlur: 6.0,
                  ),
                ),
          smoothness: 0,
          style: centerPopoverExpanded ? centerPopoverGlassStyle : morphStyle,
          child: activeGlassCenterChild,
        ),
      );
    }

    Widget? matteCenterMorphContent;
    if (!useGlass && hasCenterMorph) {
      final Widget expandedMatteBody = ConstrainedBox(
        key: const ValueKey('webview_center_expanded'),
        constraints: BoxConstraints(
          minWidth: 88.0,
          maxWidth: maxExpandedWidth,
          minHeight: 44.0,
          maxHeight: 44.0,
        ),
        child: _buildPillBody(
          centerChild,
          horizontalPad: 14.0,
          barAccent: barAccent,
        ),
      );
      final Widget? compactMatteBody = compactCenterChild != null
          ? ConstrainedBox(
              key: const ValueKey('webview_center_compact'),
              constraints: BoxConstraints(
                minWidth: 72.0,
                maxWidth: maxCompactWidth,
                minHeight: 26.0,
                maxHeight: 26.0,
              ),
              child: _buildPillBody(
                compactCenterChild!,
                horizontalPad: 11.0,
                barAccent: barAccent,
              ),
            )
          : null;
      final Widget? popoverMatteBody = expandedCenterPopoverChild != null
          ? KeyedSubtree(
              key: const ValueKey('webview_center_popover'),
              child: expandedCenterPopoverChild!,
            )
          : null;
      final Widget activeMatteCenterChild = centerPopoverExpanded
          ? popoverMatteBody!
          : (effectiveCompact && compactMatteBody != null
              ? compactMatteBody
              : expandedMatteBody);
      matteCenterMorphContent = AnimatedSize(
        key: const ValueKey('webview_center_matte_morph'),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 170),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              alignment: Alignment.topCenter,
              scale: Tween<double>(begin: 0.90, end: 1.0).animate(anim),
              child: child,
            ),
          ),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              for (final prev in previousChildren)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minWidth: 0.0,
                      maxWidth: math.max(maxExpandedWidth, 328.0),
                      minHeight: 0.0,
                      maxHeight: centerFieldHeight,
                      child: prev,
                    ),
                  ),
                ),
              if (currentChild != null) currentChild,
            ],
          ),
          child: activeMatteCenterChild,
        ),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: expandTarget, end: expandTarget),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: glassCenterMorph,
      builder: (context, t, stableGlassCenter) {
        final double headerHeight = anyHeaderOverlayOpen
            ? fullHeight
            : ui.lerpDouble(compactHeight, normalHeight, t)!;
        final double pillHeight = ui.lerpDouble(26.0, 44.0, t)!;
        final double pillRadius = pillHeight * 0.5;
        final double sideScale = 0.72 + 0.28 * t;
        final double leftCapsuleRightX = 12.0 - 56.0 * (1.0 - t) + 44.0 * sideScale;
        final bool leftSideVisible = t > 0.02 && leftCapsuleRightX > -6.0;
        final double rightCapsuleLeftOffsetFromEdge =
            -12.0 +
            (collapsedRightWidth + 24.0) * (1.0 - t) -
            collapsedRightWidth * sideScale;
        final bool rightSideVisible =
            menuExpanded || (t > 0.02 && rightCapsuleLeftOffsetFromEdge < 6.0);

        final Widget leftWidget = Positioned(
          key: const ValueKey('webview_header_left_pos'),
          top: topInset + 8,
          left: 12,
          width: 44,
          height: 44,
          child: IgnorePointer(
            key: const ValueKey('webview_header_left_ignore'),
            ignoring: effectiveCompact,
            child: Transform.translate(
              offset: Offset(-56.0 * (1.0 - t), -8.0 * (1.0 - t)),
              child: Transform.scale(
                scale: sideScale,
                alignment: Alignment.topLeft,
                child: WebViewFloatingCapsule(
                  minWidth: 44,
                  height: 44,
                  borderRadius: 22,
                  colorOverride: capsuleColorOverride,
                  visible: leftSideVisible,
                  child: leadingBox,
                ),
              ),
            ),
          ),
        );

        final Widget centerWidget;
        if (!hasCenterMorph) {
          centerWidget = Positioned(
            key: const ValueKey('webview_header_center_pos'),
            top: topInset + 8,
            left: expandedLeft,
            right: expandedRight,
            height: 44,
            child: Center(
              child: GestureDetector(
                key: const ValueKey('webview_header_center_pill'),
                behavior: HitTestBehavior.opaque,
                onTap: onCenterTap,
                onLongPress: onCenterLongPress,
                onVerticalDragStart:
                    anyHeaderOverlayOpen ? null : onVerticalDragStart,
                onVerticalDragUpdate:
                    anyHeaderOverlayOpen ? null : onVerticalDragUpdate,
                onVerticalDragEnd:
                    anyHeaderOverlayOpen ? null : onVerticalDragEnd,
                onVerticalDragCancel:
                    anyHeaderOverlayOpen ? null : onVerticalDragCancel,
                child: WebViewFloatingCapsule(
                  height: 44,
                  borderRadius: 22,
                  colorOverride: capsuleColorOverride,
                  child: expandedPillBody,
                ),
              ),
            ),
          );
        } else if (stableGlassCenter != null) {
          centerWidget = Positioned(
            key: const ValueKey('webview_header_center_pos'),
            top: topInset + 8.0,
            left: 16.0,
            right: 16.0,
            height: centerFieldHeight,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: centerPopoverExpanded ? 0.0 : 1.0,
                end: centerPopoverExpanded ? 0.0 : 1.0,
              ),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: stableGlassCenter,
              builder: (context, shiftFactor, morphChild) => Transform.translate(
                offset: Offset(expandedShiftX * t * shiftFactor, 0.0),
                child: morphChild,
              ),
            ),
          );
        } else {
          centerWidget = Positioned(
            key: const ValueKey('webview_header_center_pos'),
            top: topInset + 8.0,
            left: 16.0,
            right: 16.0,
            height: centerFieldHeight,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: centerPopoverExpanded ? 0.0 : 1.0,
                end: centerPopoverExpanded ? 0.0 : 1.0,
              ),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              builder: (context, shiftFactor, _) => Transform.translate(
                offset: Offset(expandedShiftX * t * shiftFactor, 0.0),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    key: const ValueKey('webview_header_center_pill'),
                    behavior: HitTestBehavior.opaque,
                    onTap: centerPopoverExpanded
                        ? null
                        : (effectiveCompact
                            ? (onExpandCompact ?? onCenterTap)
                            : onCenterTap),
                    onLongPress:
                        centerPopoverExpanded ? null : onCenterLongPress,
                    onVerticalDragStart:
                        (anyHeaderOverlayOpen || effectiveCompact)
                            ? null
                            : onVerticalDragStart,
                    onVerticalDragUpdate:
                        (anyHeaderOverlayOpen || effectiveCompact)
                            ? null
                            : onVerticalDragUpdate,
                    onVerticalDragEnd:
                        (anyHeaderOverlayOpen || effectiveCompact)
                            ? null
                            : onVerticalDragEnd,
                    onVerticalDragCancel:
                        (anyHeaderOverlayOpen || effectiveCompact)
                            ? null
                            : onVerticalDragCancel,
                    child: WebViewFloatingCapsule(
                      height: null,
                      borderRadius: centerPopoverExpanded ? 26.0 : pillRadius,
                      colorOverride: capsuleColorOverride,
                      child: matteCenterMorphContent!,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final Widget rightWidget = Positioned(
          key: const ValueKey('webview_header_right_pos'),
          top: topInset + 8,
          right: 12,
          child: IgnorePointer(
            key: const ValueKey('webview_header_right_ignore'),
            ignoring: effectiveCompact,
            child: rightSideVisible
                ? Transform.translate(
                    offset: Offset(
                      (collapsedRightWidth + 24.0) * (1.0 - t),
                      -8.0 * (1.0 - t),
                    ),
                    child: Transform.scale(
                      scale: sideScale,
                      alignment: Alignment.topRight,
                      child: rightMorphChild,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        );

        final Widget siteInfoBackdrop = Positioned.fill(
          key: const ValueKey('in_app_browser_site_info_backdrop'),
          child: IgnorePointer(
            ignoring: !centerPopoverExpanded,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismissCenterPopover,
              onVerticalDragStart: (_) {},
              onVerticalDragUpdate: (_) {},
              onHorizontalDragStart: (_) {},
              onHorizontalDragUpdate: (_) {},
            ),
          ),
        );

        final Widget menuBackdrop = Positioned.fill(
          key: const ValueKey('webview_header_menu_backdrop'),
          child: IgnorePointer(
            ignoring: !menuExpanded,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismissMenu,
              onVerticalDragStart: (_) {},
              onVerticalDragUpdate: (_) {},
              onHorizontalDragStart: (_) {},
              onHorizontalDragUpdate: (_) {},
            ),
          ),
        );

        final Widget stackContent = Stack(
          clipBehavior: Clip.none,
          children: menuExpanded
              ? [
                  leftWidget,
                  centerWidget,
                  siteInfoBackdrop,
                  menuBackdrop,
                  rightWidget,
                ]
              : [
                  leftWidget,
                  rightWidget,
                  menuBackdrop,
                  siteInfoBackdrop,
                  centerWidget,
                ],
        );

        final Widget framedHeader = SizedBox(
          width: double.infinity,
          height: headerHeight,
          child: morphStyle != null
              ? LiquidGlassBatch(child: stackContent)
              : stackContent,
        );

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (anyHeaderOverlayOpen || effectiveCompact)
              ? null
              : onVerticalDragStart,
          onVerticalDragUpdate: (anyHeaderOverlayOpen || effectiveCompact)
              ? null
              : onVerticalDragUpdate,
          onVerticalDragEnd: (anyHeaderOverlayOpen || effectiveCompact)
              ? null
              : onVerticalDragEnd,
          onVerticalDragCancel: (anyHeaderOverlayOpen || effectiveCompact)
              ? null
              : onVerticalDragCancel,
          child: framedHeader,
        );
      },
    );
  }
}

/// Telegram-style scalloped verified seal with rounded checkmark.
class MiniAppVerifiedSeal extends StatelessWidget {
  final double size;
  final Color color;
  final Color checkColor;

  const MiniAppVerifiedSeal({
    super.key,
    this.size = 19.0,
    required this.color,
    required this.checkColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MiniAppVerifiedSealPainter(
          color: color,
          checkColor: checkColor,
        ),
      ),
    );
  }
}

class _MiniAppVerifiedSealPainter extends CustomPainter {
  final Color color;
  final Color checkColor;

  const _MiniAppVerifiedSealPainter({
    required this.color,
    required this.checkColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Offset center = Offset(w * 0.5, h * 0.5);
    final double radius = math.min(w, h) * 0.5;

    final Path rosette = Path();
    const int segments = 64;
    for (int i = 0; i <= segments; i++) {
      final double theta = (2.0 * math.pi * i) / segments;
      final double r = radius * (0.86 + 0.14 * math.cos(8.0 * theta));
      final double x = center.dx + r * math.cos(theta);
      final double y = center.dy + r * math.sin(theta);
      if (i == 0) {
        rosette.moveTo(x, y);
      } else {
        rosette.lineTo(x, y);
      }
    }
    rosette.close();

    canvas.drawPath(
      rosette,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    final Path check = Path()
      ..moveTo(w * 0.30, h * 0.51)
      ..lineTo(w * 0.44, h * 0.65)
      ..lineTo(w * 0.70, h * 0.37);

    canvas.drawPath(
      check,
      Paint()
        ..color = checkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.min(w, h) * 0.125
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_MiniAppVerifiedSealPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.checkColor != checkColor;
}

/// Telegram-style 2x2 rounded squares Mini App placeholder / loading emblem.
class MiniAppGridPlaceholder extends StatefulWidget {
  final Color bodyColor;
  final Color? foregroundColor;
  final bool animate;

  const MiniAppGridPlaceholder({
    super.key,
    required this.bodyColor,
    this.foregroundColor,
    this.animate = false,
  });

  @override
  State<MiniAppGridPlaceholder> createState() => _MiniAppGridPlaceholderState();
}

class _MiniAppGridPlaceholderState extends State<MiniAppGridPlaceholder>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(MiniAppGridPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    final bool disableAnims =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final bool shouldAnimate = widget.animate && !disableAnims;
    if (shouldAnimate) {
      _pulseController ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      );
      if (!_pulseController!.isAnimating) {
        _pulseController!.repeat(reverse: true);
      }
    } else {
      _pulseController?.stop();
    }
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  Widget _buildGrid(double t) {
    final Color overlayBase = widget.foregroundColor ??
        (widget.bodyColor.computeLuminance() <= 0.55
            ? Colors.white
            : Colors.black);

    Widget buildTile(int index) {
      final double alpha = widget.animate
          ? 0.045 +
              0.05 *
                  (0.5 + 0.5 * math.sin(t * 2.0 * math.pi - index * 0.75))
          : 0.065;
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            overlayBase.withValues(alpha: alpha),
            widget.bodyColor,
          ),
          borderRadius: BorderRadius.circular(7.5),
        ),
      );
    }

    return SizedBox(
      width: 64,
      height: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildTile(0),
              const SizedBox(width: 8),
              buildTile(1),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildTile(2),
              const SizedBox(width: 8),
              buildTile(3),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _pulseController;
    if (ctrl == null || !widget.animate) {
      return _buildGrid(0.0);
    }
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) => _buildGrid(ctrl.value),
    );
  }
}

/// Full-screen Telegram-style Mini App container with theme-derived palette,
/// centered title + verified seal, 2x2 placeholder loader, minimize-to-bottom-bar
/// support, and targeted Liquid Glass on transient overflow menu & secondary button.
class MiniAppWebViewSheet extends StatefulWidget {
  final MiniAppLaunchData launchData;
  final String botName;
  final String botUsername;
  final bool isVerified;
  final String? chatId;
  final String mode;
  final String buttonText;
  final ValueChanged<String>? onSwitchInlineQuery;
  final MiniAppSession? session;

  const MiniAppWebViewSheet({
    super.key,
    required this.launchData,
    this.botName = '',
    this.botUsername = '',
    this.isVerified = false,
    this.chatId,
    this.mode = 'menu',
    this.buttonText = '',
    this.onSwitchInlineQuery,
    this.session,
  });

  @override
  State<MiniAppWebViewSheet> createState() => _MiniAppWebViewSheetState();
}

class _MiniAppWebViewSheetState extends State<MiniAppWebViewSheet>
    with TickerProviderStateMixin {
  late final MiniAppSession _session;
  late final BrowserUiDialogDelegate _dialogDelegate;
  bool _isMenuOpen = false;
  bool _isMinimizing = false;
  bool _allowRoutePop = false;
  bool _hasFullScreenRegistration = false;
  bool _hasSettledRegistration = false;
  bool _isTransitionReady = false;
  bool _isWebViewSurfacePainted = false;
  Timer? _earlyWebViewWarmupTimer;

  final ValueNotifier<double> _dragOffsetNotifier = ValueNotifier<double>(0.0);
  double _dragResetFrom = 0.0;
  double _dragAccumulated = 0.0;
  late final AnimationController _dragResetController;
  Animation<double>? _routeAnimation;
  bool? _lastRequestedRestingOpaque;
  double _computedTopClearance = 64.0;
  double _computedBottomClearance = 0.0;

  Color? _lastSyncedWebViewBg;
  Map<String, String>? _lastThemeParams;

  bool get _hasPlatformWebView => WebViewPlatform.instance != null;

  String get _runtimePlatformName {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return 'tdesktop';
      default:
        return 'android';
    }
  }

  void _onSessionStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onActiveSafariAlertChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onPendingLaunchResolved() {
    if (!mounted) return;
    if (_isTransitionReady) {
      _maybeInitWebView();
    } else {
      _scheduleEarlyWebViewWarmup();
    }
  }

  void _setRouteRestingOpaque(bool opaque) {
    if (!mounted || _lastRequestedRestingOpaque == opaque) return;
    _lastRequestedRestingOpaque = opaque;
    TheavSheetRoutePerfControl.setRestingOpaque(context, opaque);
  }

  void _markRouteSettled(bool settled) {
    if (settled) {
      if (!_hasSettledRegistration) {
        _hasSettledRegistration = true;
        MiniAppSessionController.instance.markFullScreenSettled();
      }
    } else {
      if (_hasSettledRegistration) {
        _hasSettledRegistration = false;
        MiniAppSessionController.instance.unmarkFullScreenSettled();
      }
    }
  }

  void _scheduleEarlyWebViewWarmup() {
    if (!_hasPlatformWebView ||
        _isTransitionReady ||
        _session.isLaunchPending ||
        _session.controller != null ||
        _earlyWebViewWarmupTimer != null) {
      return;
    }
    _earlyWebViewWarmupTimer = Timer(const Duration(milliseconds: 48), () {
      _earlyWebViewWarmupTimer = null;
      if (!mounted ||
          !_hasPlatformWebView ||
          _session.isLaunchPending ||
          _session.controller != null) {
        return;
      }
      _session.ensureWebViewInitialized();
      _syncWebViewBg();
    });
  }

  void _scheduleWebViewSurfacePainted() {
    if (_isWebViewSurfacePainted || !_hasPlatformWebView) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isWebViewSurfacePainted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isWebViewSurfacePainted) return;
        setState(() => _isWebViewSurfacePainted = true);
      });
    });
  }

  void _onRouteAnimationStatusChanged(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed) {
      _earlyWebViewWarmupTimer?.cancel();
      _earlyWebViewWarmupTimer = null;
      _isTransitionReady = true;
      _markRouteSettled(true);
      _maybeInitWebView();
      if (_dragOffsetNotifier.value <= 0.5 && !_isMinimizing) {
        _setRouteRestingOpaque(true);
      }
    } else if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      _markRouteSettled(false);
      _setRouteRestingOpaque(false);
    }
  }

  void _maybeInitWebView({bool shouldRebuild = true}) {
    if (!mounted || _session.isLaunchPending || !_isTransitionReady) return;
    if (_session.controller == null && _hasPlatformWebView) {
      _session.ensureWebViewInitialized();
      if (_session.controller != null) {
        _syncWebViewBg();
        _scheduleWebViewSurfacePainted();
        if (shouldRebuild) {
          setState(() {});
        }
      }
    } else if (_session.controller != null && _hasPlatformWebView) {
      _syncWebViewBg();
      _scheduleWebViewSurfacePainted();
      if (shouldRebuild) {
        setState(() {});
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _session = widget.session ??
        MiniAppSession(
          launchData: widget.launchData,
          botName: widget.botName,
          botUsername: widget.botUsername,
          isVerified: widget.isVerified,
          chatId: widget.chatId,
          mode: widget.mode,
          buttonText: widget.buttonText,
          onSwitchInlineQuery: widget.onSwitchInlineQuery,
        );
    _dragResetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        if (!mounted) return;
        final double t =
            Curves.easeOutCubic.transform(_dragResetController.value);
        final double next = _dragResetFrom * (1.0 - t);
        _dragOffsetNotifier.value = next;
      });

    _dialogDelegate = SheetBrowserUiDialogDelegate(
      contextResolver: () => context,
      mountedResolver: () => mounted,
    );
    _session.uiDialogDelegate = _dialogDelegate;
    _session.onSheetStateChanged = _onSessionStateChanged;
    _session.onPendingLaunchResolved = _onPendingLaunchResolved;
    _session.onRequestBridgeInjection = _injectBridge;
    _session.onInboundBridgeMessage = _handleBridgeMessage;
    activeSafariWebAlertCount.addListener(_onActiveSafariAlertChanged);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _hasFullScreenRegistration = true;
    MiniAppSessionController.instance.registerFullScreenOpen();
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (!mounted || activeSafariWebAlertCount.value > 0) return false;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (_isMenuOpen) {
      _closeMenu();
      return true;
    }
    return false;
  }

  void _releaseFullScreenRegistration() {
    _markRouteSettled(false);
    if (_hasFullScreenRegistration) {
      _hasFullScreenRegistration = false;
      MiniAppSessionController.instance.unregisterFullScreenOpen();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaPadding = MediaQuery.paddingOf(context);
    _computedTopClearance = mediaPadding.top + 60.0;
    _computedBottomClearance = mediaPadding.bottom +
        ((_session.mainButton.isVisible || _session.secondaryButton.isVisible)
            ? 64.0
            : 0.0);

    final nextRouteAnim = ModalRoute.of(context)?.animation;
    if (!identical(nextRouteAnim, _routeAnimation)) {
      _routeAnimation?.removeStatusListener(_onRouteAnimationStatusChanged);
      _routeAnimation = nextRouteAnim;
      if (nextRouteAnim == null ||
          nextRouteAnim.status == AnimationStatus.completed) {
        _earlyWebViewWarmupTimer?.cancel();
        _earlyWebViewWarmupTimer = null;
        _isTransitionReady = true;
        _markRouteSettled(true);
        _maybeInitWebView(shouldRebuild: false);
        if (_dragOffsetNotifier.value <= 0.5 && !_isMinimizing) {
          _setRouteRestingOpaque(true);
        }
      } else {
        if (!_hasPlatformWebView) {
          _isTransitionReady = true;
        } else {
          _scheduleEarlyWebViewWarmup();
        }
        nextRouteAnim.addStatusListener(_onRouteAnimationStatusChanged);
      }
    }
    _syncThemeWithWebView();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    activeSafariWebAlertCount.removeListener(_onActiveSafariAlertChanged);
    unawaited(_session.setWebPageInteractionLocked(false));
    _earlyWebViewWarmupTimer?.cancel();
    _earlyWebViewWarmupTimer = null;
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatusChanged);
    _routeAnimation = null;
    _releaseFullScreenRegistration();
    if (identical(_session.uiDialogDelegate, _dialogDelegate)) {
      _session.uiDialogDelegate = null;
    }
    if (identical(_session.onSheetStateChanged, _onSessionStateChanged)) {
      _session.onSheetStateChanged = null;
    }
    if (identical(_session.onPendingLaunchResolved, _onPendingLaunchResolved)) {
      _session.onPendingLaunchResolved = null;
    }
    if (identical(_session.onRequestBridgeInjection, _injectBridge)) {
      _session.onRequestBridgeInjection = null;
    }
    if (identical(_session.onInboundBridgeMessage, _handleBridgeMessage)) {
      _session.onInboundBridgeMessage = null;
    }
    if (!_isMinimizing) {
      MiniAppSessionController.instance.closeMinimized(_session);
    }
    _dragOffsetNotifier.dispose();
    _dragResetController.dispose();
    super.dispose();
  }

  void _syncWebViewBg() {
    final ctrl = _session.controller;
    if (ctrl == null || !mounted) return;
    final themeColors = MiniAppJsBridge.resolveThemeColors(Theme.of(context));
    final effectiveBg = _session.customBackgroundColor ?? themeColors.bodyBg;
    if (_lastSyncedWebViewBg != effectiveBg) {
      _lastSyncedWebViewBg = effectiveBg;
      try {
        ctrl.setBackgroundColor(effectiveBg);
      } catch (_) {}
    }
  }

  void _syncThemeWithWebView() {
    _syncWebViewBg();
    final ctrl = _session.controller;
    if (ctrl == null || !mounted) return;
    final theme = Theme.of(context);
    final nextParams = MiniAppJsBridge.buildThemeParams(theme);
    if (_lastThemeParams != null && !mapEquals(_lastThemeParams, nextParams)) {
      _dispatchEventToWebView('theme_changed', {
        'theme_params': nextParams,
        'color_scheme':
            theme.brightness == Brightness.dark ? 'dark' : 'light',
      });
    }
    _lastThemeParams = nextParams;
  }

  Future<void> _injectBridge() async {
    final ctrl = _session.controller;
    if (ctrl == null || !mounted) return;
    final theme = Theme.of(context);
    final themeParams = MiniAppJsBridge.buildThemeParams(theme);
    final vpHeight = MediaQuery.sizeOf(context).height;
    final js = MiniAppJsBridge.buildInjectionScript(
      _session.launchData,
      themeParams,
      colorScheme: theme.brightness == Brightness.dark ? 'dark' : 'light',
      viewportHeight: vpHeight,
      isExpanded: true,
      platform: _runtimePlatformName,
      topClearance: _computedTopClearance,
      bottomClearance: _computedBottomClearance,
    );
    try {
      await ctrl.runJavaScript(js);
    } catch (e) {
      debugPrint('MiniApp JS injection warning: $e');
    }
  }

  Future<void> _dispatchEventToWebView(
    String eventType, [
    Map<String, dynamic> eventData = const {},
    String? reqId,
  ]) =>
      _session.dispatchEvent(eventType, eventData, reqId);

  Future<void> _handleBridgeMessage(String raw) async {
    final evt = MiniAppJsBridge.parseBridgeMessage(raw);
    if (evt == null || !mounted) return;
    final data = evt.eventData;

    switch (evt.eventType) {
      case 'web_app_ready':
        if (!_session.isWebContentReady && mounted) {
          setState(() => _session.isWebContentReady = true);
        }
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          if (mounted && _session.controller != null) {
            unawaited(_session.capturePreviewSnapshot());
          }
        });
        break;

      case 'web_app_expand':
        _notifyViewportChanged();
        break;

      case 'web_app_close':
        await _attemptClose(force: true);
        break;

      case 'web_app_data_send':
        final payload = (data['data'] ?? '').toString();
        if (payload.isNotEmpty) {
          final res = await BotService.sendWebAppData(
            botId: _session.launchData.botId,
            data: payload,
            buttonText: _session.buttonText,
            chatId: _session.chatId,
          );
          if (mounted) {
            if (res['success'] == true) {
              _popSheetRoute();
            } else {
              GlassToastService().show(
                context,
                res['message']?.toString() ?? 'Ошибка отправки данных',
              );
            }
          }
        }
        break;

      case 'web_app_switch_inline_query':
        final query = (data['query'] ?? '').toString();
        final uname = _session.botUsername.isNotEmpty
            ? _session.botUsername
            : _session.launchData.botUsername;
        final text = uname.isNotEmpty ? '@$uname $query' : query;
        if (mounted) {
          _popSheetRoute();
          _session.onSwitchInlineQuery?.call(text);
        }
        break;

      case 'web_app_open_link':
        final linkUrl = (data['url'] ?? '').toString().trim();
        if (linkUrl.isNotEmpty && mounted) {
          await LinkOpener.openUrl(
            context,
            linkUrl,
            forceInApp: data['try_instant_view'] == true,
            confirmExternalApp: true,
          );
        }
        break;

      case 'web_app_open_tg_link':
        final tgUrl = (data['url'] ?? '').toString().trim();
        if (tgUrl.isNotEmpty && mounted) {
          await LinkOpener.openUrl(
            context,
            tgUrl,
            confirmExternalApp: true,
          );
        }
        break;

      case 'web_app_open_invoice':
        final invUrl = (data['url'] ?? '').toString().trim();
        String invStatus = 'cancelled';
        if (invUrl.isNotEmpty && mounted) {
          invStatus = await openThvInvoiceSheet(context, slugOrUrl: invUrl);
        }
        await _dispatchEventToWebView(
          'invoice_closed',
          {'url': invUrl, 'status': invStatus},
          evt.reqId,
        );
        break;

      case 'web_app_set_header_color':
        final col = _resolveSpecialColor(data);
        if (mounted) {
          setState(() => _session.customHeaderColor = col);
        }
        break;

      case 'web_app_set_background_color':
        final col = _resolveSpecialColor(data);
        if (mounted) {
          setState(() => _session.customBackgroundColor = col);
          _syncWebViewBg();
        }
        break;

      case 'web_app_set_bottom_bar_color':
        final col = _resolveSpecialColor(data);
        if (mounted) {
          setState(() => _session.customBottomBarColor = col);
        }
        break;

      case 'web_app_setup_back_button':
        if (mounted) {
          setState(
            () => _session.backButtonVisible = data['is_visible'] == true,
          );
          Future<void>.delayed(const Duration(milliseconds: 400), () {
            if (mounted && _session.controller != null) {
              unawaited(_session.capturePreviewSnapshot());
            }
          });
        }
        break;

      case 'web_app_setup_settings_button':
        if (mounted) {
          setState(
            () => _session.settingsButtonVisible = data['is_visible'] == true,
          );
        }
        break;

      case 'web_app_setup_closing_behavior':
        _session.closingConfirmation = data['need_confirmation'] == true;
        break;

      case 'web_app_setup_swipe_behavior':
        if (data.containsKey('allow_vertical_swipe')) {
          _session.allowVerticalSwipe = data['allow_vertical_swipe'] != false;
        }
        break;

      case 'web_app_setup_main_button':
        if (mounted) {
          setState(() => _applyButtonSetup(_session.mainButton, data));
          Future<void>.delayed(const Duration(milliseconds: 400), () {
            if (mounted && _session.controller != null) {
              unawaited(_session.capturePreviewSnapshot());
            }
          });
        }
        break;

      case 'web_app_setup_secondary_button':
        if (mounted) {
          setState(() => _applyButtonSetup(_session.secondaryButton, data));
        }
        break;

      case 'web_app_trigger_haptic_feedback':
        final type = (data['type'] ?? '').toString();
        if (type == 'selection_change') {
          HapticUtils.selection();
        } else {
          HapticUtils.tap();
        }
        break;

      case 'web_app_open_popup':
        final popupRes = await _showNativePopup(data);
        await _dispatchEventToWebView(
          'popup_closed',
          {'button_id': popupRes},
          evt.reqId,
        );
        break;

      case 'web_app_read_text_from_clipboard':
        final clip = await Clipboard.getData(Clipboard.kTextPlain);
        await _dispatchEventToWebView(
          'clipboard_text_received',
          {'data': clip?.text ?? ''},
          evt.reqId,
        );
        break;

      case 'web_app_request_write_access':
        final botHandle = _session.botUsername.isNotEmpty
            ? _session.botUsername
            : _session.launchData.botUsername;
        final allowed = await showSafariWebAlert<bool>(
              context: context,
              tone: SafariAlertTone.permission,
              iconOverride: Icons.mark_chat_unread_rounded,
              originLabel: botHandle.isNotEmpty ? '@$botHandle' : null,
              title: 'Разрешить сообщения?',
              message:
                  'Бот @$botHandle запрашивает разрешение отправлять вам сообщения.',
              actions: const [
                SafariAlertAction<bool>(label: 'Запретить', result: false),
                SafariAlertAction<bool>(
                  label: 'Разрешить',
                  result: true,
                  isPrimary: true,
                ),
              ],
            ) ??
            false;
        if (allowed) {
          await BotService.setWriteAccess(
            botId: _session.launchData.botId,
            allowed: true,
          );
        }
        await _dispatchEventToWebView(
          'write_access_requested',
          {'status': allowed ? 'allowed' : 'cancelled'},
          evt.reqId,
        );
        break;

      case 'web_app_request_phone':
        final botHandle = _session.botUsername.isNotEmpty
            ? _session.botUsername
            : _session.launchData.botUsername;
        final sent = await showSafariWebAlert<bool>(
              context: context,
              tone: SafariAlertTone.permission,
              iconOverride: Icons.phone_rounded,
              originLabel: botHandle.isNotEmpty ? '@$botHandle' : null,
              title: 'Поделиться контактом?',
              message: 'Mini App запрашивает ваш номер телефона.',
              actions: const [
                SafariAlertAction<bool>(label: 'Отмена', result: false),
                SafariAlertAction<bool>(
                  label: 'Отправить',
                  result: true,
                  isPrimary: true,
                ),
              ],
            ) ??
            false;
        await _dispatchEventToWebView(
          'contact_requested',
          {'status': sent ? 'sent' : 'cancelled'},
          evt.reqId,
        );
        break;

      case 'cloud_storage_keys':
        final keys =
            await BotService.cloudStorageKeys(_session.launchData.botId);
        await _dispatchEventToWebView(
          'cloud_storage_result',
          keys == null
              ? {'error': 'STORAGE_FAILED'}
              : {'keys': keys},
          evt.reqId,
        );
        break;

      case 'cloud_storage_get':
        final rawKeys = data['keys'] is List
            ? (data['keys'] as List).map((e) => e.toString()).toList()
            : <String>[];
        final items = await BotService.cloudStorageGet(
          _session.launchData.botId,
          rawKeys,
        );
        await _dispatchEventToWebView(
          'cloud_storage_result',
          items == null
              ? {'error': 'STORAGE_FAILED'}
              : {'items': items},
          evt.reqId,
        );
        break;

      case 'cloud_storage_set':
        final ok = await BotService.cloudStorageSet(
          _session.launchData.botId,
          (data['key'] ?? '').toString(),
          (data['value'] ?? '').toString(),
        );
        await _dispatchEventToWebView(
          'cloud_storage_result',
          ok ? {'ok': true} : {'error': 'STORAGE_FAILED', 'ok': false},
          evt.reqId,
        );
        break;

      case 'cloud_storage_remove':
        final rawKeys = data['keys'] is List
            ? (data['keys'] as List).map((e) => e.toString()).toList()
            : <String>[];
        final ok = await BotService.cloudStorageRemove(
          _session.launchData.botId,
          rawKeys,
        );
        await _dispatchEventToWebView(
          'cloud_storage_result',
          ok ? {'ok': true} : {'error': 'STORAGE_FAILED', 'ok': false},
          evt.reqId,
        );
        break;
    }
  }

  void _applyButtonSetup(MiniAppActionButtonState state, Map<String, dynamic> data) {
    if (data.containsKey('is_visible')) {
      state.isVisible = data['is_visible'] == true;
    }
    if (data.containsKey('is_active')) {
      state.isActive = data['is_active'] != false;
    }
    if (data.containsKey('is_progress_visible')) {
      state.isProgressVisible = data['is_progress_visible'] == true;
    }
    final t = data['text']?.toString();
    if (t != null && t.isNotEmpty) {
      state.text = t;
    }
    final c = MiniAppJsBridge.parseHexColor(data['color']?.toString());
    if (c != null) state.color = c;
    final tc = MiniAppJsBridge.parseHexColor(data['text_color']?.toString());
    if (tc != null) state.textColor = tc;
  }

  Color? _resolveSpecialColor(Map<String, dynamic> data) {
    final key = (data['color_key'] ?? '').toString();
    if (key.isNotEmpty && mounted) {
      final tp = MiniAppJsBridge.buildThemeParams(Theme.of(context));
      final hex = tp[key];
      if (hex != null) return MiniAppJsBridge.parseHexColor(hex);
    }
    return MiniAppJsBridge.parseHexColor(
      (data['color'] ?? data['value'])?.toString(),
    );
  }

  Future<String?> _showNativePopup(Map<String, dynamic> data) async {
    final title = data['title']?.toString();
    final msg = data['message']?.toString() ?? '';
    final rawButtons = data['buttons'] is List ? data['buttons'] as List : const [];
    final actions = <SafariAlertAction<String>>[];
    for (final raw in rawButtons) {
      if (raw is Map) {
        final id = (raw['id'] ?? '').toString();
        final type = (raw['type'] ?? 'default').toString();
        var text = (raw['text'] ?? '').toString().trim();
        if (text.isEmpty) {
          text = type == 'cancel'
              ? 'Отмена'
              : (type == 'close' ? 'Закрыть' : 'ОК');
        }
        actions.add(
          SafariAlertAction<String>(
            label: text,
            result: id.isNotEmpty ? id : type,
            isDestructive: type == 'destructive',
            isPrimary: type == 'ok' || type == 'default',
          ),
        );
      }
    }
    if (actions.isEmpty) {
      actions.add(
        const SafariAlertAction<String>(
          label: 'ОК',
          result: 'ok',
          isPrimary: true,
        ),
      );
    }
    final botHandle = _session.botUsername.isNotEmpty
        ? _session.botUsername
        : _session.launchData.botUsername;
    return showSafariWebAlert<String>(
      context: context,
      tone: SafariAlertTone.info,
      originLabel: botHandle.isNotEmpty ? '@$botHandle' : null,
      title: (title != null && title.isNotEmpty) ? title : null,
      message: msg,
      actions: actions,
    );
  }

  void _notifyViewportChanged() {
    if (!mounted) return;
    final h = MediaQuery.sizeOf(context).height;
    _dispatchEventToWebView('viewport_changed', {
      'height': h.round(),
      'is_expanded': true,
      'is_state_stable': true,
    });
  }

  void _popSheetRoute([NavigatorState? targetNavigator]) {
    _allowRoutePop = true;
    final nav = targetNavigator ?? Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) {
      nav.pop();
    }
  }

  Future<void> _handleSystemBack() async {
    if (_isMenuOpen) {
      _closeMenu();
      return;
    }
    final bool didGoBack = await _session.performWebBack(
      onDispatchedBackEvent: () => _dispatchEventToWebView('back_button_pressed'),
    );
    if (didGoBack) {
      HapticUtils.tap();
      if (mounted) setState(() {});
    }
  }

  Future<void> _attemptClose({bool force = false}) async {
    if (!force && _session.closingConfirmation) {
      final botHandle = _session.botUsername.isNotEmpty
          ? _session.botUsername
          : _session.launchData.botUsername;
      final confirm = await _confirmMiniAppCloseDialog(
        context,
        originLabel: botHandle.isNotEmpty ? '@$botHandle' : _session.displayTitle,
      );
      if (!confirm || !mounted) return;
    }
    _isMinimizing = false;
    _markRouteSettled(false);
    _setRouteRestingOpaque(false);
    MiniAppSessionController.instance.closeMinimized(_session);
    if (mounted) {
      _popSheetRoute();
    }
  }

  Future<void> _minimizeMiniApp({
    double dragOffsetPx = 0.0,
    double velocityPxPerSec = 0.0,
  }) async {
    if (_isMinimizing) return;
    HapticUtils.selection();
    _closeMenu();
    if (!mounted) return;
    unawaited(_session.setWebPageInteractionLocked(false));
    _markRouteSettled(false);
    _setRouteRestingOpaque(false);
    if (dragOffsetPx > 0.5) {
      final double sheetH = MediaQuery.sizeOf(context).height;
      if (TheavSheetRoutePerfControl.prepareDragDismiss(
        context,
        dragOffsetPx: dragOffsetPx,
        sheetHeight: sheetH,
        velocityPxPerSec: velocityPxPerSec,
      )) {
        _dragOffsetNotifier.value = 0.0;
      }
    }
    if (_MinimizedMiniAppHostScope.maybeOf(context)) {
      _isMinimizing = true;
      _releaseFullScreenRegistration();
      final nav = Navigator.of(context, rootNavigator: true);
      MiniAppSessionController.instance.minimize(_session, navigator: nav);
      _popSheetRoute(nav);
    } else {
      _popSheetRoute();
    }
  }

  Future<void> _openTabsSwitcherFromHeader() async {
    HapticUtils.selection();
    _closeMenu();
    if (_session.previewImageBytes == null) {
      await _session.capturePreviewSnapshot().timeout(
            const Duration(milliseconds: 45),
            onTimeout: () {},
          );
    } else {
      unawaited(_session.capturePreviewSnapshot());
    }
    if (!mounted) return;
    unawaited(_session.setWebPageInteractionLocked(false));
    _markRouteSettled(false);
    if (_MinimizedMiniAppHostScope.maybeOf(context)) {
      _isMinimizing = true;
      _setRouteRestingOpaque(false);
      _releaseFullScreenRegistration();
      final nav = Navigator.of(context, rootNavigator: true);
      MiniAppSessionController.instance.minimizeAndOpenSwitcher(
        _session,
        navigator: nav,
      );
      _popSheetRoute(nav);
      return;
    }

    final navigator = Navigator.of(context);
    final sessions = <MiniAppSession>[
      ...MiniAppSessionController.instance.minimizedSessions
          .where((s) => !identical(s, _session)),
      _session,
    ];
    await navigator.push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (routeCtx, _, __) => MiniAppTabsSwitcher(
          key: const ValueKey('mini_app_tabs_switcher'),
          sessions: sessions,
          onDismiss: () => Navigator.of(routeCtx).maybePop(),
          onSelectSession: (selected) {
            Navigator.of(routeCtx).maybePop();
            if (!identical(selected, _session)) {
              unawaited(
                MiniAppSessionController.instance.restoreSession(selected),
              );
            }
          },
          onCloseSession: (target) {
            MiniAppSessionController.instance.closeSession(target);
            Navigator.of(routeCtx).maybePop();
            if (identical(target, _session) && mounted) {
              _attemptClose(force: true);
            }
          },
          onCloseAll: () {
            MiniAppSessionController.instance.closeAllMinimized();
            Navigator.of(routeCtx).maybePop();
            if (mounted) {
              _attemptClose(force: true);
            }
          },
        ),
      ),
    );
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
    });
  }

  void _closeMenu() {
    if (_isMenuOpen) {
      setState(() => _isMenuOpen = false);
    }
  }

  void _handleHeaderDragStart(DragStartDetails _) {
    if (!_session.allowVerticalSwipe) return;
    _dragResetController.stop();
    _dragAccumulated = 0.0;
  }

  void _handleHeaderDragUpdate(DragUpdateDetails details) {
    if (!_session.allowVerticalSwipe) return;
    _dragAccumulated += details.delta.dy;
    final double current = _dragOffsetNotifier.value;
    final double nextOffset = (current + details.delta.dy).clamp(0.0, 260.0);
    if ((nextOffset - current).abs() > 0.1) {
      if (_isMenuOpen) {
        setState(() => _isMenuOpen = false);
      }
      if (nextOffset > 0.5) {
        _setRouteRestingOpaque(false);
      } else if (_routeAnimation?.status == AnimationStatus.completed) {
        _setRouteRestingOpaque(true);
      }
      _dragOffsetNotifier.value = nextOffset;
    }
  }

  void _resetDragOffset() {
    final double current = _dragOffsetNotifier.value;
    if (current <= 0.5) {
      if (current != 0.0) {
        _dragOffsetNotifier.value = 0.0;
      }
      if (_routeAnimation?.status == AnimationStatus.completed) {
        _setRouteRestingOpaque(true);
      }
      return;
    }
    _dragResetFrom = current;
    _dragResetController.forward(from: 0.0).whenComplete(() {
      if (!mounted) return;
      if (_dragOffsetNotifier.value != 0.0) {
        _dragOffsetNotifier.value = 0.0;
      }
      if (_routeAnimation?.status == AnimationStatus.completed && !_isMinimizing) {
        _setRouteRestingOpaque(true);
      }
    });
  }

  void _handleHeaderDragEnd(DragEndDetails details) {
    if (!_session.allowVerticalSwipe) return;
    final double dy = _dragAccumulated;
    final double vy = details.primaryVelocity ?? 0.0;
    _dragAccumulated = 0.0;

    if (dy >= 90 || vy >= 620) {
      unawaited(
        _minimizeMiniApp(
          dragOffsetPx: _dragOffsetNotifier.value,
          velocityPxPerSec: math.max(0.0, vy),
        ),
      );
      return;
    }
    _resetDragOffset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = TheavSurfaceStyle.of(context);
    final resolved = MiniAppJsBridge.resolveThemeColors(theme);
    final palette = resolved.palette;
    final media = MediaQuery.of(context);
    final double sheetHeight = media.size.height;
    final double topInset = media.padding.top;
    final bool isRouteCovered = !(ModalRoute.isCurrentOf(context) ?? true);
    final bool isPageInteractionBlocked =
        isRouteCovered || _isMenuOpen || activeSafariWebAlertCount.value > 0;
    unawaited(_session.setWebPageInteractionLocked(isPageInteractionBlocked));

    final Color bodyBg = _session.customBackgroundColor ?? resolved.bodyBg;
    final Color bodyFg = _session.customBackgroundColor != null
        ? (_session.customBackgroundColor!.computeLuminance() <= 0.55
            ? Colors.white
            : Colors.black87)
        : palette.onSurface;
    final Color headerBg = _session.customHeaderColor ?? resolved.headerBg;
    final bool isHeaderDark = headerBg.computeLuminance() <= 0.55;
    final Color headerFg = _session.customHeaderColor != null
        ? (isHeaderDark ? Colors.white : Colors.black87)
        : resolved.headerFg;
    final Color sealColor = _session.customHeaderColor != null
        ? headerFg.withValues(alpha: 0.85)
        : palette.primary;
    final Color sealCheckColor =
        (sealColor.computeLuminance() - headerBg.computeLuminance()).abs() > 0.18
            ? headerBg
            : palette.onPrimary;

    final String displayTitle = _session.displayTitle;
    final String effectiveUsername = _session.botUsername.isNotEmpty
        ? _session.botUsername
        : _session.launchData.botUsername;
    final String unameLower = effectiveUsername.toLowerCase().trim();
    final String displayHandle =
        effectiveUsername.isNotEmpty ? '@$effectiveUsername' : '';
    final bool effectiveIsVerified = _session.isVerified ||
        _session.launchData.botIsVerified ||
        unameLower == 'botmother' ||
        unameLower == 'botfather' ||
        unameLower == 'walt';

    final double bottomClearance = media.padding.bottom +
        ((_session.mainButton.isVisible || _session.secondaryButton.isVisible)
            ? 66.0
            : 0.0);
    final double topHudClearance = topInset + 60.0;
    _computedTopClearance = topHudClearance;
    _computedBottomClearance = bottomClearance;

    final double expandedMenuHeight =
        (_session.settingsButtonVisible ? 5 : 4) * 44.0 + 12.0;

    final Widget expandedMenuContent = Padding(
      key: const ValueKey('mini_app_overflow_menu'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMenuItem(
              icon: iconoir.RefreshDouble(
                width: 18,
                height: 18,
                color: headerFg,
              ),
              label: 'Обновить страницу',
              fgColor: headerFg,
              onTap: () async {
                _closeMenu();
                if (_session.controller != null) {
                  setState(() {
                    _session.isWebContentReady = false;
                    _session.loadProgress = 0.08;
                  });
                  await _session.controller!.reload();
                }
              },
            ),
            if (_session.settingsButtonVisible)
              _buildMenuItem(
                icon: iconoir.Settings(
                  width: 18,
                  height: 18,
                  color: headerFg,
                ),
                label: 'Настройки приложения',
                fgColor: headerFg,
                onTap: () async {
                  _closeMenu();
                  await _dispatchEventToWebView('settings_button_pressed');
                },
              ),
            _buildMenuItem(
              icon: iconoir.NavArrowDown(
                width: 18,
                height: 18,
                color: headerFg,
              ),
              label: 'Свернуть',
              fgColor: headerFg,
              onTap: _minimizeMiniApp,
            ),
            _buildMenuItem(
              icon: iconoir.Copy(
                width: 18,
                height: 18,
                color: headerFg,
              ),
              label: 'Скопировать ссылку',
              fgColor: headerFg,
              onTap: () async {
                _closeMenu();
                await Clipboard.setData(
                  ClipboardData(text: _session.launchData.url),
                );
                if (context.mounted) {
                  GlassToastService().show(context, 'Ссылка скопирована');
                }
              },
            ),
            _buildMenuItem(
              icon: iconoir.OpenNewWindow(
                width: 18,
                height: 18,
                color: headerFg,
              ),
              label: 'Открыть в браузере',
              fgColor: headerFg,
              onTap: () async {
                _closeMenu();
                final u = Uri.tryParse(_session.launchData.url);
                if (u != null) {
                  await launchUrl(u, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
      ),
    );

    final Widget floatingHeader = WebViewFloatingHeader(
      topInset: topInset,
      capsuleColorOverride: _session.customHeaderColor,
      progressColor: palette.primary,
      progressListenable: _session.loadProgressNotifier,
      onCenterTap: _openTabsSwitcherFromHeader,
      isMenuOpen: _isMenuOpen,
      onDismissMenu: _closeMenu,
      expandedMenuWidth: 244.0,
      expandedMenuHeight: expandedMenuHeight,
      expandedMenuChild: expandedMenuContent,
      onVerticalDragStart: _handleHeaderDragStart,
      onVerticalDragUpdate: _handleHeaderDragUpdate,
      onVerticalDragEnd: _handleHeaderDragEnd,
      onVerticalDragCancel: _resetDragOffset,
      leadingChild: IconButton(
        key: const ValueKey('mini_app_close_or_back_button'),
        tooltip: _session.backButtonVisible ? 'Назад' : 'Закрыть',
        padding: EdgeInsets.zero,
        onPressed: _session.backButtonVisible
            ? () {
                _closeMenu();
                _dispatchEventToWebView('back_button_pressed');
              }
            : () => _attemptClose(),
        icon: Icon(
          _session.backButtonVisible
              ? Icons.arrow_back_rounded
              : Icons.close_rounded,
          size: 22,
          color: headerFg,
        ),
      ),
      centerChild: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.15,
                color: headerFg,
              ),
            ),
          ),
          if (effectiveIsVerified) ...[
            const SizedBox(width: 5),
            MiniAppVerifiedSeal(
              key: const ValueKey('mini_app_verified_seal'),
              size: 17,
              color: sealColor,
              checkColor: sealCheckColor,
            ),
          ],
        ],
      ),
      trailingActions: [
        SizedBox(
          width: 40,
          height: 44,
          child: IconButton(
            key: const ValueKey('mini_app_collapse_expand_button'),
            tooltip: 'Свернуть',
            padding: EdgeInsets.zero,
            onPressed: _minimizeMiniApp,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 24,
              color: headerFg,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          height: 44,
          child: IconButton(
            key: const ValueKey('mini_app_more_menu_button'),
            tooltip: 'Ещё',
            padding: EdgeInsets.zero,
            onPressed: () {
              HapticUtils.tap();
              _toggleMenu();
            },
            icon: Icon(
              Icons.more_vert_rounded,
              size: 21,
              color: headerFg,
            ),
          ),
        ),
      ],
    );

    final Widget viewportContent;
    if (_session.launchError != null && !_hasPlatformWebView) {
      viewportContent = _buildDesktopOrTestFallback(
        context,
        displayTitle: displayTitle,
        displayHandle: displayHandle,
        resolved: resolved,
        topClearance: topHudClearance,
        bottomClearance: bottomClearance,
      );
    } else if (_session.launchError != null) {
      viewportContent = Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            topHudClearance + 16,
            24,
            bottomClearance + 24,
          ),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: resolved.surfaceBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: resolved.divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _session.launchError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: bodyFg,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => _attemptClose(force: true),
                  child: const Text('Закрыть'),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (_hasPlatformWebView) {
      final ImageProvider? standInSnapshot =
          (!_isTransitionReady || !_isWebViewSurfacePainted)
              ? _session.fullViewportPreviewProvider
              : null;
      final bool mountWebView =
          _isTransitionReady && _session.controller != null;
      viewportContent = Stack(
        fit: StackFit.expand,
        children: [
          if (standInSnapshot != null)
            Positioned.fill(
              key: const ValueKey('mini_app_restore_snapshot'),
              child: Image(
                image: standInSnapshot,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
              ),
            ),
          if (mountWebView)
            RepaintBoundary(
              child: standInSnapshot != null
                  ? WebViewWidget(controller: _session.controller!)
                  : ColoredBox(
                      color: bodyBg,
                      child: WebViewWidget(controller: _session.controller!),
                    ),
            ),
          if (standInSnapshot == null &&
              (!mountWebView || !_session.isWebContentReady))
            Positioned.fill(
              child: ColoredBox(
                color: bodyBg,
                child: Center(
                  child: MiniAppGridPlaceholder(
                    key: const ValueKey('mini_app_grid_loader'),
                    bodyColor: bodyBg,
                    foregroundColor: bodyFg,
                    animate: true,
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      viewportContent = _buildDesktopOrTestFallback(
        context,
        displayTitle: displayTitle,
        displayHandle: displayHandle,
        resolved: resolved,
        topClearance: topHudClearance,
        bottomClearance: bottomClearance,
      );
    }

    final Widget viewportBody = KeyedSubtree(
      key: const ValueKey('mini_app_viewport_container'),
      child: ColoredBox(
        color: bodyBg,
        child: viewportContent,
      ),
    );

    final Widget hudOverlayStack = Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        if (_session.mainButton.isVisible ||
            _session.secondaryButton.isVisible)
          Positioned(
            left: 12,
            right: 12,
            bottom: media.padding.bottom + 10,
            child: IgnorePointer(
              ignoring: isPageInteractionBlocked,
              child: Row(
                children: [
                  if (_session.secondaryButton.isVisible)
                    Expanded(
                      child: _buildActionButton(
                        _session.secondaryButton,
                        defaultBg: palette.primary.withValues(alpha: 0.14),
                        defaultFg: palette.primary,
                        onPressed: () => _dispatchEventToWebView(
                          'secondary_button_pressed',
                        ),
                        style: style,
                        isSecondaryGlassCandidate: true,
                      ),
                    ),
                  if (_session.secondaryButton.isVisible &&
                      _session.mainButton.isVisible)
                    const SizedBox(width: 10),
                  if (_session.mainButton.isVisible)
                    Expanded(
                      child: _buildActionButton(
                        _session.mainButton,
                        defaultBg: palette.primary,
                        defaultFg: theme.colorScheme.onPrimary,
                        onPressed: () => _dispatchEventToWebView(
                          'main_button_pressed',
                        ),
                        style: style,
                        isSecondaryGlassCandidate: false,
                      ),
                    ),
                ],
              ),
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: floatingHeader,
        ),
      ],
    );

    final Widget sheetStackChild = Material(
      color: bodyBg,
      child: SizedBox(
        height: sheetHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                key: const ValueKey('mini_app_web_interaction_guard'),
                ignoring: isPageInteractionBlocked,
                child: ExcludeFocus(
                  excluding: isPageInteractionBlocked,
                  child: viewportBody,
                ),
              ),
            ),
            Positioned.fill(
              child: style.isGlass
                  ? LiquidGlassBatch(child: hudOverlayStack)
                  : hudOverlayStack,
            ),
          ],
        ),
      ),
    );

    return BackdropGroup(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: isHeaderDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
              ),
        child: PopScope(
          canPop: _allowRoutePop,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            unawaited(_handleSystemBack());
          },
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1.0,
            child: ValueListenableBuilder<double>(
              valueListenable: _dragOffsetNotifier,
              builder: (context, offsetY, child) => MiniAppDragOffset(
                offsetY: offsetY,
                child: child!,
              ),
              child: sheetStackChild,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required Widget icon,
    required String label,
    required Color fgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticUtils.tap();
        onTap();
      },
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: fgColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    MiniAppActionButtonState state, {
    required Color defaultBg,
    required Color defaultFg,
    required VoidCallback onPressed,
    required TheavSurfaceStyle style,
    required bool isSecondaryGlassCandidate,
  }) {
    final bg = state.color ?? defaultBg;
    final fg = state.textColor ?? defaultFg;
    final VoidCallback? tapHandler =
        (state.isActive && !state.isProgressVisible)
            ? () {
                HapticUtils.tap();
                onPressed();
              }
            : null;

    if (isSecondaryGlassCandidate &&
        state.color == null &&
        style.isGlass &&
        style.glassProvider != null) {
      return SizedBox(
        height: 46,
        child: LiquidGlassLens(
          style: style.glassProvider!.createStyle(
            context: context,
            cornerRadius: 13,
            isLiteOverride: true,
            refractionIndex: 1.06,
            refractionWidth: 14.0,
            borderWidth: 1.0,
            color: defaultBg,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: tapHandler,
              child: Center(
                child: state.isProgressVisible
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: fg,
                        ),
                      )
                    : Text(
                        state.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: tapHandler != null
                              ? fg
                              : fg.withValues(alpha: 0.45),
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 46,
      child: FilledButton(
        onPressed: tapHandler,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        child: state.isProgressVisible
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
            : Text(
                state.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
      ),
    );
  }

  Widget _buildDesktopOrTestFallback(
    BuildContext context, {
    required String displayTitle,
    required String displayHandle,
    required MiniAppThemeColors resolved,
    required double topClearance,
    required double bottomClearance,
  }) {
    final uri = Uri.tryParse(_session.launchData.url);
    final host = uri?.host ?? _session.launchData.url;
    final palette = resolved.palette;
    final Color cardBg = resolved.surfaceBg;
    final Color titleColor = palette.onSurface;
    final Color subtitleColor = palette.subtext;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          topClearance + 16,
          24,
          bottomClearance + 24,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: resolved.divider,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiniAppGridPlaceholder(
                  key: const ValueKey('mini_app_grid_loader'),
                  bodyColor: cardBg,
                  foregroundColor: palette.onSurface,
                  animate: false,
                ),
                const SizedBox(height: 16),
                Text(
                  displayTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                ),
                if (displayHandle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$displayHandle • mini app',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: subtitleColor,
                        ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  host,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: subtitleColor,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Подпись Telegram.WebApp initData сформирована. Встроенный WebView недоступен на текущей платформе — откройте Mini App во внешнем браузере.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: subtitleColor,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: uri == null
                        ? null
                        : () => launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            ),
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.primary,
                      foregroundColor: palette.onPrimary,
                    ),
                    icon: iconoir.OpenNewWindow(
                      width: 17,
                      height: 17,
                      color: palette.onPrimary,
                    ),
                    label: const Text('Открыть в браузере'),
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
