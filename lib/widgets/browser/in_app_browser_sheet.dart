import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../l10n/app_localizations.dart';
import '../../screens/settings/browser_vault_and_data_screen.dart';
import '../../services/bot_service.dart';
import '../../services/browser_data_service.dart';
import '../../services/browser_otp_autofill_service.dart';
import '../../services/browser_site_settings_service.dart';
import '../../services/browser_vault_service.dart';
import '../../services/file_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/mini_app_js_bridge.dart';
import '../../utils/browser_autofill_script.dart';
import '../../utils/browser_context_menu_script.dart';
import '../../utils/browser_find_in_page_script.dart';
import '../../utils/browser_reader_mode_script.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/safari_url_safety.dart';
import '../bot/mini_app_webview_sheet.dart';
import '../design_system/theav_design_system.dart';
import 'safari_autofill_overlays.dart';
import 'safari_browser_dialogs.dart';
import 'safari_element_context_sheet.dart';
import 'safari_library_sheet.dart';
import 'safari_reader_mode_view.dart';

/// Opens [url] inside Theaver's Telegram-style full-screen WebView browser,
/// or restores an already minimized browser tab with the same URL.
Future<void> openInAppBrowser(
  BuildContext context, {
  required String url,
}) async {
  final cleanUrl = url.trim();
  if (cleanUrl.isEmpty) return;

  final sessionCtrl = MiniAppSessionController.instance;
  for (final existing in sessionCtrl.minimizedSessions.reversed) {
    if (existing.isBrowser && existing.currentUrl == cleanUrl) {
      await sessionCtrl.restoreSession(existing);
      return;
    }
  }

  final session = MiniAppSession(
    launchData: MiniAppLaunchData(
      url: cleanUrl,
      initData: '',
      botId: '',
      botUsername: '',
      botDisplayName: BrowserDataService.extractHost(cleanUrl),
    ),
    isBrowser: true,
    initialUrl: cleanUrl,
  );
  if (!context.mounted) return;

  await showTheavModalSheet<void>(
    context: context,
    enableDrag: false,
    barrierDismissible: true,
    useRootNavigator: true,
    customSheetBuilder: (_) => InAppBrowserSheet(session: session),
    builder: (_) => const SizedBox.shrink(),
  );
}

class InAppBrowserSheet extends StatefulWidget {
  final MiniAppSession session;

  const InAppBrowserSheet({
    super.key,
    required this.session,
  });

  @override
  State<InAppBrowserSheet> createState() => _InAppBrowserSheetState();
}

class _InAppBrowserSheetState extends State<InAppBrowserSheet>
    with TickerProviderStateMixin {

  late final MiniAppSession _session;
  late final BrowserUiDialogDelegate _dialogDelegate;
  late final AnimationController _dragResetController;
  late final AnimationController _findBarController;
  late final CurvedAnimation _findBarAnimation;
  final ValueNotifier<double> _dragOffsetNotifier = ValueNotifier<double>(0.0);
  final TextEditingController _findCtrl = TextEditingController();
  final FocusNode _findFocusNode = FocusNode();
  final ScrollController _readerScrollCtrl = ScrollController();

  BrowserContactProfile _contactProfile = const BrowserContactProfile();
  bool _isMenuOpen = false;
  bool _isSiteInfoOpen = false;
  bool _isFindOpen = false;
  double _pullRefreshProgress = 0.0;
  bool _pullRefreshThresholdHapticFired = false;
  Timer? _findDebounceTimer;
  int _findRequestSeq = 0;
  int _findCurrentMatch = 0;
  int _findTotalMatches = 0;
  bool _hasCompletedFindForQuery = false;
  String _lastSearchedFindQuery = '';
  double _dragResetFrom = 0.0;
  double _dragAccumulated = 0.0;
  bool _isMinimizing = false;
  bool _isDisposing = false;
  bool _allowRoutePop = false;
  bool _hasFullScreenRegistration = false;
  bool _hasSettledRegistration = false;
  bool _isTransitionReady = false;
  bool _isWebViewSurfacePainted = false;
  bool _didInjectInsetsOnMount = false;
  Timer? _earlyWebViewWarmupTimer;
  ModalRoute<dynamic>? _enclosingRoute;
  Animation<double>? _routeAnimation;
  bool? _lastRequestedRestingOpaque;
  bool? _lastScheduledInteractionLock;

  bool get _hasPlatformWebView => !kIsWeb && WebViewPlatform.instance != null;

  OverlayState? _resolveRootOverlay() =>
      mounted ? Overlay.maybeOf(context, rootOverlay: true) : null;

  void _onSessionStateChanged() {
    if (mounted && !_isDisposing) setState(() {});
  }

  void _onActiveSafariAlertChanged() {
    if (mounted) setState(() {});
  }

  void _setRouteRestingOpaque(bool opaque) {
    if (!mounted || !context.mounted || _lastRequestedRestingOpaque == opaque) {
      return;
    }
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

  void _releaseFullScreenRegistration() {
    _markRouteSettled(false);
    if (_hasFullScreenRegistration) {
      _hasFullScreenRegistration = false;
      MiniAppSessionController.instance.unregisterFullScreenOpen();
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
    if (!mounted || !_isTransitionReady || !_hasPlatformWebView) return;
    if (_session.controller == null) {
      _session.ensureWebViewInitialized();
      if (_session.controller != null) {
        _didInjectInsetsOnMount = true;
        _scheduleWebViewSurfacePainted();
        unawaited(_session.injectBrowserSafeInsets());
        if (shouldRebuild) {
          setState(() {});
        }
      }
    } else {
      _scheduleWebViewSurfacePainted();
      if (!_didInjectInsetsOnMount) {
        _didInjectInsetsOnMount = true;
        unawaited(_session.injectBrowserSafeInsets());
      }
      if (shouldRebuild) {
        setState(() {});
      }
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    if (_session.controller != null && _hasPlatformWebView) {
      unawaited(_session.injectBrowserSafeInsets());
    }
  }

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _hasFullScreenRegistration = true;
    MiniAppSessionController.instance.registerFullScreenOpen();
    _dragResetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        if (!mounted) return;
        final double t =
            Curves.easeOutCubic.transform(_dragResetController.value);
        _dragOffsetNotifier.value = _dragResetFrom * (1.0 - t);
      });
    _findBarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 220),
    )..addStatusListener((status) {
        if (!mounted) return;
        if (status == AnimationStatus.dismissed && !_isFindOpen) {
          setState(() {});
        }
      });
    _findBarAnimation = CurvedAnimation(
      parent: _findBarController,
      curve: const Cubic(0.22, 1.06, 0.32, 1.0),
      reverseCurve: Curves.easeInCubic,
    );
    _dialogDelegate = SheetBrowserUiDialogDelegate(
      contextResolver: () => context,
      mountedResolver: () => mounted && context.mounted,
    );
    _session.uiDialogDelegate = _dialogDelegate;
    _session.overlayResolver = _resolveRootOverlay;
    _session.onSheetStateChanged = _onSessionStateChanged;
    _session.onBrowserPageFinished = _handleBrowserPageFinished;
    _session.onBrowserContextMenuRequested = _handleContextMenuRequested;
    _session.onBrowserPullToRefreshEvent = _handlePullToRefreshEvent;
    activeSafariWebAlertCount.addListener(_onActiveSafariAlertChanged);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    BrowserOtpAutofillService.instance.attachBrowserObserver();
    BrowserOtpAutofillService.instance.addListener(_onOtpChanged);
    unawaited(BrowserDataService.instance.ensureLoaded());
    unawaited(BrowserVaultService.instance.ensureLoaded());
    unawaited(
      BrowserSiteSettingsService.instance.ensureLoaded().then((_) {
        if (!mounted || _session.controller != null) {
          return;
        }
        final savedPref = BrowserSiteSettingsService.instance
            .preferenceForUrl(_session.currentUrl);
        final savedDesktop = savedPref?.desktopMode;
        final savedZoom = savedPref?.textZoom;
        if ((savedDesktop != null && savedDesktop != _session.isDesktopMode) ||
            (savedZoom != null &&
                (savedZoom - _session.pageTextZoom).abs() > 0.005)) {
          setState(() {
            if (savedDesktop != null) _session.isDesktopMode = savedDesktop;
            if (savedZoom != null) {
              _session.pageTextZoom = savedZoom.clamp(0.85, 1.50).toDouble();
            }
          });
        }
      }),
    );
    unawaited(_reloadContactProfile());
    BrowserDataService.instance.addListener(_onBrowserDataChanged);
    BrowserVaultService.instance.addListener(_onVaultOrSettingsChanged);
    BrowserSiteSettingsService.instance.addListener(_onVaultOrSettingsChanged);
  }

  void _onOtpChanged() {
    if (mounted && !_isDisposing) {
      setState(() {});
    }
  }

  Future<void> _reloadContactProfile() async {
    final profile = await BrowserVaultService.instance.getContactProfile();
    if (!mounted) return;
    setState(() => _contactProfile = profile);
  }

  void _onVaultOrSettingsChanged() {
    unawaited(_reloadContactProfile());
    unawaited(_session.syncNativeBrowserPolicies(_session.currentUrl));
    if (mounted) setState(() {});
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (!mounted ||
        !context.mounted ||
        activeSafariWebAlertCount.value > 0) {
      return false;
    }
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    final route = _enclosingRoute;
    if (route != null && !route.isCurrent) return false;
    if (_session.pendingCredentialPrompt != null) {
      setState(() => _session.pendingCredentialPrompt = null);
      return true;
    }
    if (_session.pendingCardPrompt != null) {
      setState(() => _session.pendingCardPrompt = null);
      return true;
    }
    if (_isSiteInfoOpen) {
      _closeSiteInfoPopover();
      return true;
    }
    if (_isMenuOpen) {
      _closeMenu();
      return true;
    }
    if (_isFindOpen) {
      _closeFindBar();
      return true;
    }
    if (_session.isReaderModeActive) {
      _exitReaderMode();
      return true;
    }
    return false;
  }

  void _updateBrowserSafeClearances({EdgeInsets? paddingOverride}) {
    final size = MediaQuery.sizeOf(context);
    final padding = paddingOverride ?? MediaQuery.paddingOf(context);
    final double nextTop = padding.top + (_isFindOpen ? 110.0 : 58.0);
    final double nextCompactTop = padding.top + (_isFindOpen ? 110.0 : 38.0);
    final double nextBottom = padding.bottom + 64.0;
    final double nextCompactBottom = padding.bottom;
    final double nextVh = size.height;
    final bool nextForceExpanded = _isFindOpen;
    final bool clearanceChanged =
        (nextTop - _session.browserTopClearance).abs() > 0.5 ||
            (nextCompactTop - _session.browserCompactTopClearance).abs() > 0.5 ||
            (nextBottom - _session.browserBottomClearance).abs() > 0.5 ||
            (nextCompactBottom - _session.browserCompactBottomClearance).abs() >
                0.5 ||
            (nextVh - _session.browserViewportHeight).abs() > 0.5 ||
            nextForceExpanded != _session.browserForceExpanded;
    _session.browserTopClearance = nextTop;
    _session.browserCompactTopClearance = nextCompactTop;
    _session.browserBottomClearance = nextBottom;
    _session.browserCompactBottomClearance = nextCompactBottom;
    _session.browserViewportHeight = nextVh;
    _session.browserForceExpanded = nextForceExpanded;
    if (nextForceExpanded && _session.browserChromeCollapsed) {
      _session.browserChromeCollapsed = false;
    }
    if (clearanceChanged && _isTransitionReady && _session.controller != null) {
      unawaited(_session.injectBrowserSafeInsets());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateBrowserSafeClearances();

    final route = ModalRoute.of(context);
    _enclosingRoute = route;
    final nextRouteAnim = route?.animation;
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
  }

  @override
  void deactivate() {
    _enclosingRoute = null;
    super.deactivate();
  }

  void _onBrowserDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _isDisposing = true;
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    activeSafariWebAlertCount.removeListener(_onActiveSafariAlertChanged);
    unawaited(_session.setWebPageInteractionLocked(false));
    _earlyWebViewWarmupTimer?.cancel();
    _earlyWebViewWarmupTimer = null;
    _findDebounceTimer?.cancel();
    _findDebounceTimer = null;
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatusChanged);
    _routeAnimation = null;
    BrowserDataService.instance.removeListener(_onBrowserDataChanged);
    BrowserVaultService.instance.removeListener(_onVaultOrSettingsChanged);
    BrowserSiteSettingsService.instance
        .removeListener(_onVaultOrSettingsChanged);
    BrowserOtpAutofillService.instance.removeListener(_onOtpChanged);
    BrowserOtpAutofillService.instance.detachBrowserObserver();
    if (identical(_session.uiDialogDelegate, _dialogDelegate)) {
      _session.uiDialogDelegate = null;
    }
    if (identical(_session.overlayResolver, _resolveRootOverlay)) {
      _session.overlayResolver = null;
    }
    if (identical(_session.onSheetStateChanged, _onSessionStateChanged)) {
      _session.onSheetStateChanged = null;
    }
    if (identical(_session.onBrowserPageFinished, _handleBrowserPageFinished)) {
      _session.onBrowserPageFinished = null;
    }
    if (_session.onBrowserContextMenuRequested == _handleContextMenuRequested) {
      _session.onBrowserContextMenuRequested = null;
    }
    if (_session.onBrowserPullToRefreshEvent == _handlePullToRefreshEvent) {
      _session.onBrowserPullToRefreshEvent = null;
    }
    if (!_isMinimizing) {
      _session.disposeResources();
    }
    _readerScrollCtrl.dispose();
    _dragOffsetNotifier.dispose();
    _dragResetController.dispose();
    _findBarAnimation.dispose();
    _findBarController.dispose();
    _findFocusNode.dispose();
    _findCtrl.dispose();
    _releaseFullScreenRegistration();
    super.dispose();
  }

  Future<void> _minimizeToDock({
    double dragOffsetPx = 0.0,
    double velocityPxPerSec = 0.0,
  }) async {
    if (_isMinimizing) return;
    _isMinimizing = true;
    _findFocusNode.unfocus();
    _closeMenu();
    _closeSiteInfoPopover();
    await _session.dismissFullscreenVideoOverlay();
    if (!mounted) return;
    unawaited(_session.setWebPageInteractionLocked(false));
    _markRouteSettled(false);
    _setRouteRestingOpaque(false);
    HapticUtils.selection();
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
    _releaseFullScreenRegistration();
    _allowRoutePop = true;
    final nav = Navigator.of(context, rootNavigator: true);
    MiniAppSessionController.instance.minimize(_session, navigator: nav);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  Future<void> _openTabsSwitcherFromHeader() async {
    if (_isMinimizing) return;
    HapticUtils.selection();
    _closeMenu();
    _closeSiteInfoPopover();
    await _session.dismissFullscreenVideoOverlay();
    if (!mounted) return;
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
    if (MinimizedMiniAppHost.isMountedIn(context)) {
      _isMinimizing = true;
      _setRouteRestingOpaque(false);
      _releaseFullScreenRegistration();
      _allowRoutePop = true;
      TheavSheetRoutePerfControl.prepareInstantSwitcherDismiss(context);
      final nav = Navigator.of(context, rootNavigator: true);
      MiniAppSessionController.instance.minimizeAndOpenSwitcher(
        _session,
        navigator: nav,
      );
      if (nav.canPop()) {
        nav.pop();
      }
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
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (routeCtx, _, __) => MiniAppTabsSwitcher(
          key: const ValueKey('mini_app_tabs_switcher'),
          sessions: sessions,
          enterSpec: MiniAppSwitcherEnterSpec(
            source: MiniAppSwitcherOpenSource.fromActiveSession,
            outgoingSession: _session,
          ),
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
              _closeTab();
            }
          },
          onCloseAll: () {
            MiniAppSessionController.instance.closeAllMinimized();
            Navigator.of(routeCtx).maybePop();
            if (mounted) {
              _closeTab();
            }
          },
        ),
      ),
    );
  }

  void _closeTab() {
    _findDebounceTimer?.cancel();
    _findDebounceTimer = null;
    _findFocusNode.unfocus();
    _closeMenu();
    _isSiteInfoOpen = false;
    unawaited(_session.setWebPageInteractionLocked(false));
    unawaited(_session.dismissFullscreenVideoOverlay());
    _markRouteSettled(false);
    _setRouteRestingOpaque(false);
    HapticUtils.tap();
    MiniAppSessionController.instance.closeSession(_session);
    _allowRoutePop = true;
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  void _expandBrowserChrome() {
    HapticUtils.selection();
    unawaited(_session.setBrowserChromeCollapsed(false));
  }

  void _toggleMenu() {
    HapticUtils.tap();
    if (!_isMenuOpen) {
      if (_isSiteInfoOpen) {
        _isSiteInfoOpen = false;
      }
      if (_session.browserChromeCollapsed) {
        unawaited(_session.setBrowserChromeCollapsed(false));
      }
    }
    setState(() => _isMenuOpen = !_isMenuOpen);
  }

  void _closeMenu() {
    if (_isMenuOpen) {
      setState(() => _isMenuOpen = false);
    }
  }

  void _toggleSiteInfoPopover() {
    HapticUtils.tap();
    if (!_isSiteInfoOpen) {
      if (_isMenuOpen) _isMenuOpen = false;
      if (_session.browserChromeCollapsed) {
        unawaited(_session.setBrowserChromeCollapsed(false));
      }
      setState(() => _isSiteInfoOpen = true);
    } else {
      setState(() => _isSiteInfoOpen = false);
    }
  }

  void _closeSiteInfoPopover() {
    if (_isSiteInfoOpen) {
      setState(() => _isSiteInfoOpen = false);
    }
  }

  void _openFindBar() {
    final bool disableAnims =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    setState(() => _isFindOpen = true);
    _updateBrowserSafeClearances();
    if (_session.browserChromeCollapsed) {
      unawaited(_session.setBrowserChromeCollapsed(false));
    }
    if (disableAnims) {
      _findBarController.value = 1.0;
    } else {
      _findBarController.forward();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isFindOpen) {
        _findFocusNode.requestFocus();
      }
    });
    if (_findCtrl.text.trim().isNotEmpty) {
      unawaited(_runFindSearch(_findCtrl.text, preserveViewportMatch: true));
    }
  }

  void _closeFindBar() {
    if (!_isFindOpen) return;
    final bool disableAnims =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _findDebounceTimer?.cancel();
    _findDebounceTimer = null;
    _findRequestSeq++;
    _findFocusNode.unfocus();
    setState(() {
      _isFindOpen = false;
      _findCurrentMatch = 0;
      _findTotalMatches = 0;
      _hasCompletedFindForQuery = false;
      _lastSearchedFindQuery = '';
    });
    unawaited(_clearFindInPage());
    _updateBrowserSafeClearances();
    if (disableAnims) {
      _findBarController.value = 0.0;
    } else {
      _findBarController.reverse();
    }
  }

  void _upgradeCurrentUrlToHttps() {
    final upgraded =
        SafariUrlSafetyAnalyzer.tryBuildHttpsUpgrade(_session.currentUrl);
    _closeSiteInfoPopover();
    if (upgraded == null) return;
    _navigateToUrl(upgraded);
  }

  Future<void> _clearCurrentSiteDataAndReload() async {
    _closeSiteInfoPopover();
    final ctrl = _session.controller;
    if (ctrl != null && _hasPlatformWebView) {
      try {
        await ctrl.runJavaScript('''
          (function(){
            try {
              if (window.localStorage) localStorage.clear();
              if (window.sessionStorage) sessionStorage.clear();
              var cookies = (document.cookie || '').split(';');
              for (var i = 0; i < cookies.length; i++) {
                var eq = cookies[i].indexOf('=');
                var name = (eq > -1 ? cookies[i].substr(0, eq) : cookies[i]).trim();
                if (name) {
                  document.cookie = name + '=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/';
                }
              }
            } catch (e) {}
          })();
        ''');
      } catch (_) {}
    }
    await BrowserDataService.instance.clearSiteData(_session.currentUrl);
    if (ctrl != null && _hasPlatformWebView) {
      try {
        await ctrl.reload();
      } catch (_) {}
    }
    if (mounted) {
      GlassToastService().show(
        context,
        context.trOr('browser_site_data_cleared', 'Данные сайта очищены'),
        icon: Icons.cleaning_services_rounded,
      );
    }
  }

  Future<void> _goBack() async {
    final movedBack = await _session.performWebBack();
    if (movedBack) {
      HapticUtils.tap();
      if (_session.browserChromeCollapsed) {
        unawaited(_session.setBrowserChromeCollapsed(false));
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _goForward() async {
    final ctrl = _session.controller;
    if (ctrl == null || !_hasPlatformWebView) return;
    if (await ctrl.canGoForward()) {
      HapticUtils.tap();
      await ctrl.goForward();
      await _session.refreshBrowserNavState();
      if (mounted) setState(() {});
    }
  }

  Future<void> _reloadOrStop() async {
    final ctrl = _session.controller;
    if (ctrl == null || !_hasPlatformWebView) return;
    HapticUtils.tap();
    if (_session.loadProgress > 0.0 && _session.loadProgress < 1.0) {
      await ctrl.runJavaScript('window.stop();');
      if (mounted) setState(() => _session.loadProgress = 1.0);
    } else if (_session.webResourceErrorDescription != null) {
      await _session.retryMainFrameLoad();
    } else {
      await ctrl.reload();
    }
  }

  Future<void> _toggleDesktopMode() async {
    _closeMenu();
    final nextDesktop = !_session.isDesktopMode;
    setState(() => _session.isDesktopMode = nextDesktop);
    unawaited(
      BrowserSiteSettingsService.instance
          .setDesktopModeForUrl(_session.currentUrl, nextDesktop),
    );
    final ctrl = _session.controller;
    if (ctrl != null && _hasPlatformWebView) {
      await ctrl.setUserAgent(
        nextDesktop ? MiniAppSession.desktopUserAgent : null,
      );
      final plat = ctrl.platform;
      if (plat is AndroidWebViewController) {
        await plat.setUseWideViewPort(nextDesktop);
      }
      await ctrl.reload();
    }
    if (mounted) {
      GlassToastService().show(
        context,
        nextDesktop
            ? context.trOr(
                'browser_desktop_mode_enabled',
                'Включена версия для ПК',
              )
            : context.trOr(
                'browser_mobile_mode_enabled',
                'Включена мобильная версия',
              ),
      );
    }
  }

  Future<void> _handleAutofillSelectCredential(
    BrowserCredentialHint hint,
  ) async {
    final cred = await BrowserVaultService.instance.unlockAndReadCredential(
      context,
      hint.id,
      reason: context.trOr(
        'browser_autofill_login_unlock_reason',
        'Подтвердите личность для входа на {host}',
        <String, String>{'host': hint.displayHost},
      ),
      originScope: hint.origin,
    );
    if (!mounted || cred == null) return;
    if (cred.username.trim().isNotEmpty) {
      _session.recordPendingStep1Username(cred.username, cred.origin);
    }
    final ctrl = _session.controller;
    if (ctrl != null && _hasPlatformWebView) {
      try {
        await ctrl.runJavaScript(
          BrowserAutofillScript.buildFillCredentialsScript(
            expectedOrigin: cred.origin,
            username: cred.username,
            password: cred.password,
          ),
        );
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _session.focusedAutofillField = null);
    }
  }

  Future<void> _handleAutofillSelectCard(BrowserCardHint hint) async {
    final bool isSecureBefore =
        _session.currentUrl.toLowerCase().startsWith('https://') &&
            !_session.currentPageHasSslWarning &&
            !SafariUrlSafetyAnalyzer.analyzeUrl(_session.currentUrl)
                .isSuspiciousHomograph;
    if (!isSecureBefore) return;
    final String? originBefore =
        BrowserVaultService.normalizeOrigin(_session.currentUrl);
    if (originBefore == null) return;

    final String cardLabel = '${hint.brand.displayName} •••• ${hint.last4}';
    final BrowserSavedCard? card =
        await BrowserVaultService.instance.unlockAndReadCard(
      context,
      hint.id,
      reason: context.trOr(
        'browser_autofill_card_unlock_reason',
        'Подтвердите личность для автозаполнения карты {card}',
        <String, String>{'card': cardLabel},
      ),
      originScope: originBefore,
    );
    if (!mounted || card == null) return;
    final bool isSecureAfter =
        _session.currentUrl.toLowerCase().startsWith('https://') &&
            !_session.currentPageHasSslWarning &&
            !SafariUrlSafetyAnalyzer.analyzeUrl(_session.currentUrl)
                .isSuspiciousHomograph;
    final String? currentOrigin =
        BrowserVaultService.normalizeOrigin(_session.currentUrl);
    if (!isSecureAfter || currentOrigin == null || currentOrigin != originBefore) {
      return;
    }

    final ctrl = _session.controller;
    if (ctrl != null && _hasPlatformWebView) {
      try {
        await ctrl.runJavaScript(
          BrowserAutofillScript.buildFillCardScript(
            expectedOrigin: currentOrigin,
            cardNumber: card.cardNumber,
            holderName: card.holderName,
            expMonth: card.expMonth,
            expYear: card.expYear,
          ),
        );
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _session.focusedAutofillField = null);
    }
  }

  Future<void> _handleAutofillSelectAddress(BrowserSavedAddress addr) async {
    final String? currentOrigin =
        BrowserVaultService.normalizeOrigin(_session.currentUrl);
    final String? origin =
        _session.focusedAutofillField?.origin ?? currentOrigin;
    if (origin == null || currentOrigin == null || origin != currentOrigin) {
      return;
    }
    final ctrl = _session.controller;
    if (ctrl != null && _hasPlatformWebView) {
      try {
        await ctrl.runJavaScript(
          BrowserAutofillScript.buildFillAddressScript(
            expectedOrigin: origin,
            fullName: addr.fullName,
            organization: addr.organization,
            addressLine1: addr.addressLine1,
            addressLine2: addr.addressLine2,
            city: addr.city,
            region: addr.region,
            postalCode: addr.postalCode,
            country: addr.country,
            phone: addr.phone,
            email: addr.email,
          ),
        );
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _session.focusedAutofillField = null);
    }
  }

  Future<void> _handleAutofillFillOtp(String code) async {
    final String? currentOrigin =
        BrowserVaultService.normalizeOrigin(_session.currentUrl);
    final String? origin =
        _session.focusedAutofillField?.origin ?? currentOrigin;
    if (origin == null || currentOrigin == null || origin != currentOrigin) {
      return;
    }
    final ctrl = _session.controller;
    if (ctrl != null && _hasPlatformWebView) {
      try {
        await ctrl.runJavaScript(
          BrowserAutofillScript.buildFillOtpScript(
            expectedOrigin: origin,
            code: code,
          ),
        );
      } catch (_) {}
    }
    BrowserOtpAutofillService.instance.consumeCandidate();
    if (mounted) {
      setState(() => _session.focusedAutofillField = null);
    }
  }

  Future<void> _handlePasteOtpFromClipboard() async {
    final String? code =
        await BrowserOtpAutofillService.instance.readOtpFromClipboardByUserTap();
    if (!mounted) return;
    if (code != null && code.isNotEmpty) {
      await _handleAutofillFillOtp(code);
    } else {
      GlassToastService().show(
        context,
        context.trOr(
          'browser_otp_not_found_clipboard',
          'Код не найден в буфере обмена',
        ),
        icon: Icons.info_outline_rounded,
      );
    }
  }

  Future<void> _handleSavePendingCard() async {
    final BrowserPendingCardSubmission? candidate = _session.pendingCardPrompt;
    if (candidate == null) return;
    setState(() => _session.pendingCardPrompt = null);
    await BrowserVaultService.instance.saveOrUpdateCard(
      cardNumber: candidate.cardNumber,
      holderName: candidate.holderName,
      expMonth: candidate.expMonth,
      expYear: candidate.expYear,
      existingId: candidate.existingId,
    );
    if (mounted) {
      GlassToastService().show(
        context,
        candidate.isUpdate
            ? context.trOr('browser_card_updated', 'Карта обновлена')
            : context.trOr('browser_card_saved', 'Карта сохранена'),
        icon: Icons.credit_card_rounded,
      );
    }
  }

  Future<void> _handleAutofillFillContact() async {
    final origin = _session.focusedAutofillField?.origin ??
        BrowserVaultService.normalizeOrigin(_session.currentUrl);
    if (origin == null) return;
    final ctrl = _session.controller;
    if (ctrl != null && _hasPlatformWebView) {
      try {
        await ctrl.runJavaScript(
          BrowserAutofillScript.buildFillContactScript(
            expectedOrigin: origin,
            fullName: _contactProfile.fullName,
            email: _contactProfile.email,
            phone: _contactProfile.phone,
          ),
        );
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _session.focusedAutofillField = null);
    }
  }

  Future<void> _handleSavePendingPassword(String finalUsername) async {
    final candidate = _session.pendingCredentialPrompt;
    if (candidate == null) return;
    setState(() => _session.pendingCredentialPrompt = null);
    await BrowserVaultService.instance.saveOrUpdateCredential(
      url: candidate.url,
      username: finalUsername,
      password: candidate.password,
      existingId: candidate.existingId,
    );
    if (mounted) {
      GlassToastService().show(
        context,
        candidate.isUpdate
            ? context.trOr('browser_password_updated', 'Пароль обновлён')
            : context.trOr('browser_password_saved', 'Пароль сохранён'),
        icon: Icons.key_rounded,
      );
    }
  }

  Future<void> _handleNeverSavePendingPassword() async {
    final candidate = _session.pendingCredentialPrompt;
    if (candidate == null) return;
    setState(() => _session.pendingCredentialPrompt = null);
    await BrowserVaultService.instance.markNeverSaveForUrl(candidate.url);
    if (mounted) {
      GlassToastService().show(
        context,
        context.trOr(
          'browser_password_never_save_toast',
          'Пароли для {host} не будут сохраняться',
          <String, String>{'host': candidate.displayHost},
        ),
        icon: Icons.block_rounded,
      );
    }
  }

  Future<void> _enterReaderMode() async {
    if (_session.isReaderModeActive) return;
    final BrowserReaderArticle? article = await _session.extractReaderArticle();
    if (!mounted) return;
    if (article != null) {
      setState(() {
        _session.isReaderModeActive = true;
        _session.activeReaderArticle = article;
        _session.focusedAutofillField = null;
        _pullRefreshProgress = 0.0;
        _pullRefreshThresholdHapticFired = false;
      });
      if (_session.browserChromeCollapsed) {
        unawaited(_session.setBrowserChromeCollapsed(false));
      }
      unawaited(_session.syncNativeBrowserPolicies(_session.currentUrl));
    } else {
      GlassToastService().show(
        context,
        context.trOr(
          'browser_reader_open_failed',
          'Не удалось открыть режим чтения',
        ),
        icon: Icons.article_outlined,
      );
    }
  }

  void _exitReaderMode() {
    if (!_session.isReaderModeActive) return;
    setState(() {
      _session.isReaderModeActive = false;
    });
    unawaited(_session.syncNativeBrowserPolicies(_session.currentUrl));
  }

  Future<void> _toggleReaderMode() async {
    if (_session.isReaderModeActive) {
      _exitReaderMode();
    } else {
      await _enterReaderMode();
    }
  }

  Future<void> _openTypographySheet() async {
    _closeMenu();
    _closeSiteInfoPopover();
    HapticUtils.tap();
    await BrowserSiteSettingsService.instance.ensureLoaded();
    if (!mounted) return;
    final settings = BrowserSiteSettingsService.instance;
    await showSafariTypographySheet(
      context,
      fontScale: _session.isReaderModeActive
          ? settings.readerFontScale
          : _session.pageTextZoom,
      themeId: settings.readerTheme,
      fontFamilyId: settings.readerFontFamily,
      isReaderMode: _session.isReaderModeActive,
      readerAvailable: _session.isReaderAvailable || _session.isReaderModeActive,
      onFontScaleChanged: (scale) {
        if (_session.isReaderModeActive) {
          unawaited(settings.setReaderFontScale(scale));
        } else {
          unawaited(settings.setTextZoomForUrl(_session.currentUrl, scale));
          unawaited(_session.applyBrowserPageTextZoom(scale));
          if (mounted) setState(() {});
        }
      },
      onThemeChanged: (themeId) {
        unawaited(settings.setReaderTheme(themeId));
      },
      onFontFamilyChanged: (fontFamilyId) {
        unawaited(settings.setReaderFontFamily(fontFamilyId));
      },
      onToggleReaderMode: () {
        unawaited(_toggleReaderMode());
      },
    );
  }

  void _handlePullToRefreshEvent(double progress, bool released) {
    if (!mounted || _isDisposing) return;
    final bool isRouteCovered = !(ModalRoute.isCurrentOf(context) ?? true);
    final bool blocked = _session.isReaderModeActive ||
        _isMenuOpen ||
        _isFindOpen ||
        _isSiteInfoOpen ||
        isRouteCovered ||
        activeSafariWebAlertCount.value > 0;
    if (blocked) {
      if (_pullRefreshProgress != 0.0 || _pullRefreshThresholdHapticFired) {
        setState(() {
          _pullRefreshProgress = 0.0;
          _pullRefreshThresholdHapticFired = false;
        });
      }
      return;
    }

    final double clamped =
        (progress.isFinite ? progress : 0.0).clamp(0.0, 1.0).toDouble();
    if (released) {
      final bool shouldReload = clamped >= 1.0;
      if (_pullRefreshProgress != 0.0 || _pullRefreshThresholdHapticFired) {
        setState(() {
          _pullRefreshProgress = 0.0;
          _pullRefreshThresholdHapticFired = false;
        });
      }
      if (shouldReload) {
        unawaited(_reloadOrStop());
      }
      return;
    }

    if (clamped >= 1.0 && !_pullRefreshThresholdHapticFired) {
      _pullRefreshThresholdHapticFired = true;
      HapticUtils.selection();
    } else if (clamped < 0.88 && _pullRefreshThresholdHapticFired) {
      _pullRefreshThresholdHapticFired = false;
    }
    if ((clamped - _pullRefreshProgress).abs() > 0.005 ||
        (clamped == 0.0 && _pullRefreshProgress != 0.0)) {
      setState(() => _pullRefreshProgress = clamped);
    }
  }

  ({Uint8List bytes, String ext})? _decodeDataImage(String rawUrl) {
    final match = RegExp(
      r'^data:image/([a-z0-9.+-]+)(?:;[^,]*)?;base64,(.+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(rawUrl.trim());
    if (match == null) return null;
    final String subtype = (match.group(1) ?? '').toLowerCase();
    final String rawB64 =
        (match.group(2) ?? '').replaceAll(RegExp(r'\s+'), '');
    if (rawB64.isEmpty) return null;
    final Uint8List bytes = base64Decode(rawB64);
    if (bytes.isEmpty) return null;
    final String ext = switch (subtype) {
      'jpeg' || 'jpg' => '.jpg',
      'png' => '.png',
      'webp' => '.webp',
      'gif' => '.gif',
      'svg+xml' => '.svg',
      'bmp' => '.bmp',
      'avif' => '.avif',
      _ => '.png',
    };
    return (bytes: bytes, ext: ext);
  }

  Future<void> _saveContextImage(BrowserContextMenuTarget target) async {
    final String rawUrl = target.imageUrl.trim();
    if (rawUrl.isEmpty) return;
    try {
      if (rawUrl.toLowerCase().startsWith('data:image/')) {
        final decoded = _decodeDataImage(rawUrl);
        if (decoded == null) {
          throw const FormatException('Invalid base64 image');
        }
        final String dirPath = await FileService().getDefaultDownloadDirectory();
        final Directory dir = Directory(dirPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final String fileName =
            'image_${DateTime.now().millisecondsSinceEpoch}${decoded.ext}';
        final File outFile = File(p.join(dirPath, fileName));
        await outFile.writeAsBytes(decoded.bytes, flush: true);
      } else {
        final Uri? uri = Uri.tryParse(rawUrl);
        if (uri == null ||
            (uri.scheme.toLowerCase() != 'http' &&
                uri.scheme.toLowerCase() != 'https')) {
          throw const FormatException('Unsupported image URL');
        }
        String rawName = '';
        if (uri.pathSegments.isNotEmpty) {
          try {
            rawName = Uri.decodeComponent(uri.pathSegments.last.trim());
          } catch (_) {
            rawName = uri.pathSegments.last.trim();
          }
        }
        String safeName = rawName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
        if (safeName.isEmpty || safeName == '.' || safeName == '..') {
          safeName = 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        } else if (p.extension(safeName).isEmpty) {
          safeName = '$safeName.jpg';
        }
        await FileService().downloadToDownloads(rawUrl, safeName);
      }
      if (mounted) {
        GlassToastService().show(
          context,
          context.trOr('browser_image_saved', 'Изображение сохранено'),
          icon: Icons.download_done_rounded,
        );
      }
    } catch (_) {
      if (mounted) {
        GlassToastService().show(
          context,
          context.trOr(
            'browser_image_save_failed',
            'Не удалось сохранить изображение',
          ),
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  Future<void> _shareContextImage(BrowserContextMenuTarget target) async {
    final String rawUrl = target.imageUrl.trim();
    if (rawUrl.isEmpty) return;
    HapticUtils.tap();
    try {
      if (rawUrl.toLowerCase().startsWith('data:image/')) {
        final decoded = _decodeDataImage(rawUrl);
        if (decoded != null) {
          final File tmpFile = File(
            p.join(
              Directory.systemTemp.path,
              'share_${DateTime.now().millisecondsSinceEpoch}${decoded.ext}',
            ),
          );
          await tmpFile.writeAsBytes(decoded.bytes, flush: true);
          await SharePlus.instance.share(
            ShareParams(files: <XFile>[XFile(tmpFile.path)]),
          );
          return;
        }
      }
      await SharePlus.instance.share(ShareParams(text: rawUrl));
    } catch (_) {}
  }

  Future<void> _openUrlInNewTab(String targetUrl) async {
    final String cleanUrl = targetUrl.trim();
    final Uri? parsed = Uri.tryParse(cleanUrl);
    final String scheme = parsed?.scheme.toLowerCase() ?? '';
    if (parsed == null || (scheme != 'http' && scheme != 'https')) {
      return;
    }
    final NavigatorState rootNav = Navigator.of(context, rootNavigator: true);
    final BuildContext? hostCtx = rootNav.overlay?.context;
    if (hostCtx == null || !hostCtx.mounted) return;
    if (rootNav.canPop()) {
      if (_isMinimizing) return;
      _isMinimizing = true;
      _findFocusNode.unfocus();
      _closeMenu();
      _closeSiteInfoPopover();
      await _session.dismissFullscreenVideoOverlay();
      if (!mounted) return;
      if (_session.previewImageBytes == null) {
        await _session.capturePreviewSnapshot().timeout(
              const Duration(milliseconds: 60),
              onTimeout: () {},
            );
      } else {
        unawaited(_session.capturePreviewSnapshot());
      }
      if (!mounted) return;
      unawaited(_session.setWebPageInteractionLocked(false));
      _markRouteSettled(false);
      _setRouteRestingOpaque(false);
      _releaseFullScreenRegistration();
      _allowRoutePop = true;
      MiniAppSessionController.instance.minimize(_session, navigator: rootNav);
      if (rootNav.canPop()) {
        rootNav.pop();
      }
    }
    if (hostCtx.mounted) {
      unawaited(openInAppBrowser(hostCtx, url: cleanUrl));
    }
  }

  Future<void> _handleContextMenuRequested(
    BrowserContextMenuTarget target,
  ) async {
    if (!mounted ||
        _isDisposing ||
        _isMinimizing ||
        _session.isReaderModeActive ||
        _isMenuOpen ||
        _isSiteInfoOpen ||
        activeSafariWebAlertCount.value > 0 ||
        !(ModalRoute.isCurrentOf(context) ?? true)) {
      return;
    }
    if (!target.hasLink && !target.hasImage) return;
    HapticUtils.selection();
    final SafariElementContextAction? action =
        await showSafariElementContextSheet(
      context,
      target: target,
      alreadyBookmarked: target.hasLink &&
          BrowserDataService.instance.isBookmarked(target.linkUrl),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case SafariElementContextAction.openInNewTab:
        await _openUrlInNewTab(target.linkUrl);
        break;
      case SafariElementContextAction.openImageInNewTab:
        await _openUrlInNewTab(target.imageUrl);
        break;
      case SafariElementContextAction.addBookmark:
        final String title = target.linkText.trim().isNotEmpty
            ? target.linkText.trim()
            : BrowserDataService.extractHost(target.linkUrl);
        final bool added = await BrowserDataService.instance.toggleBookmark(
          target.linkUrl,
          title,
        );
        if (mounted) {
          GlassToastService().show(
            context,
            added
                ? context.trOr('browser_bookmark_added', 'Добавлено в закладки')
                : context.trOr('browser_bookmark_removed', 'Удалено из закладок'),
            icon: added
                ? Icons.bookmark_added_rounded
                : Icons.bookmark_remove_rounded,
          );
        }
        break;
      case SafariElementContextAction.copyLink:
        await Clipboard.setData(ClipboardData(text: target.linkUrl));
        HapticUtils.selection();
        if (mounted) {
          GlassToastService().show(
            context,
            context.trOr('browser_link_copied', 'Ссылка скопирована'),
            icon: Icons.check,
          );
        }
        break;
      case SafariElementContextAction.copyImageUrl:
        await Clipboard.setData(ClipboardData(text: target.imageUrl));
        HapticUtils.selection();
        if (mounted) {
          GlassToastService().show(
            context,
            context.trOr(
              'browser_image_url_copied',
              'Ссылка на изображение скопирована',
            ),
            icon: Icons.check,
          );
        }
        break;
      case SafariElementContextAction.shareLink:
        HapticUtils.tap();
        try {
          await SharePlus.instance.share(ShareParams(text: target.linkUrl));
        } catch (_) {}
        break;
      case SafariElementContextAction.shareImage:
        await _shareContextImage(target);
        break;
      case SafariElementContextAction.saveImage:
        await _saveContextImage(target);
        break;
    }
  }

  Future<void> _toggleBookmark() async {
    _closeMenu();
    final added = await BrowserDataService.instance.toggleBookmark(
      _session.currentUrl,
      _session.displayTitle,
    );
    if (mounted) {
      GlassToastService().show(
        context,
        added
            ? context.trOr('browser_bookmark_added', 'Добавлено в закладки')
            : context.trOr('browser_bookmark_removed', 'Удалено из закладок'),
        icon: added ? Icons.bookmark_added_rounded : Icons.bookmark_remove_rounded,
      );
    }
  }

  Future<void> _shareCurrentUrl() async {
    _closeMenu();
    HapticUtils.tap();
    try {
      await SharePlus.instance.share(
        ShareParams(text: _session.currentUrl),
      );
    } catch (_) {}
  }

  Future<void> _copyCurrentUrl() async {
    _closeMenu();
    await Clipboard.setData(ClipboardData(text: _session.currentUrl));
    HapticUtils.selection();
    if (mounted) {
      GlassToastService().show(
        context,
        context.trOr('browser_link_copied', 'Ссылка скопирована'),
        icon: Icons.check,
      );
    }
  }

  Future<void> _openExternalBrowser() async {
    _closeMenu();
    final uri = Uri.tryParse(_session.currentUrl);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  void _handleBrowserPageFinished() {
    if (!mounted || !_isFindOpen || _findCtrl.text.trim().isEmpty) return;
    _findDebounceTimer?.cancel();
    _findDebounceTimer = null;
    unawaited(_runFindSearch(_findCtrl.text, preserveViewportMatch: false));
  }

  void _onFindQueryChanged(String value) {
    _findDebounceTimer?.cancel();
    _findDebounceTimer = null;
    if (value.trim().isEmpty) {
      _findRequestSeq++;
      _lastSearchedFindQuery = '';
      setState(() {
        _findCurrentMatch = 0;
        _findTotalMatches = 0;
        _hasCompletedFindForQuery = false;
      });
      unawaited(_clearFindInPage());
      return;
    }
    setState(() {
      _hasCompletedFindForQuery = false;
    });
    _findDebounceTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || !_isFindOpen) return;
      unawaited(_runFindSearch(_findCtrl.text, preserveViewportMatch: true));
    });
  }

  Future<BrowserFindInPageResult> _executeFindScript(
    String query, {
    required bool isStep,
    required bool backwards,
    required bool preserveViewportMatch,
  }) async {
    final debugOverride = _session.debugFindInPageOverride;
    if (debugOverride != null) {
      return debugOverride(
        query,
        isStep: isStep,
        backwards: backwards,
        preserveViewportMatch: preserveViewportMatch,
      );
    }
    final ctrl = _session.controller;
    if (ctrl == null || !_hasPlatformWebView) {
      return BrowserFindInPageResult.empty;
    }
    try {
      final String js = isStep
          ? BrowserFindInPageScript.buildStepScript(
              query: query,
              backwards: backwards,
            )
          : BrowserFindInPageScript.buildSearchScript(
              query: query,
              preserveViewportMatch: preserveViewportMatch,
            );
      final Object raw = await ctrl.runJavaScriptReturningResult(js);
      return BrowserFindInPageResult.tryParseJsResult(raw) ??
          BrowserFindInPageResult.empty;
    } catch (_) {
      return BrowserFindInPageResult.empty;
    }
  }

  Future<void> _runFindSearch(
    String rawQuery, {
    required bool preserveViewportMatch,
  }) async {
    if (rawQuery.trim().isEmpty) {
      await _clearFindInPage();
      return;
    }
    final int seq = ++_findRequestSeq;
    final BrowserFindInPageResult result = await _executeFindScript(
      rawQuery,
      isStep: false,
      backwards: false,
      preserveViewportMatch: preserveViewportMatch,
    );
    if (!mounted || !_isFindOpen || seq != _findRequestSeq) return;
    setState(() {
      _lastSearchedFindQuery = rawQuery;
      _findCurrentMatch = result.current;
      _findTotalMatches = result.total;
      _hasCompletedFindForQuery = true;
    });
  }

  Future<void> _stepFindMatch({required bool backwards}) async {
    final String rawQuery = _findCtrl.text;
    if (rawQuery.trim().isEmpty) return;
    _findDebounceTimer?.cancel();
    _findDebounceTimer = null;
    if (_lastSearchedFindQuery != rawQuery || !_hasCompletedFindForQuery) {
      await _runFindSearch(rawQuery, preserveViewportMatch: true);
      return;
    }
    if (_findTotalMatches <= 0) return;
    final int seq = ++_findRequestSeq;
    final BrowserFindInPageResult result = await _executeFindScript(
      rawQuery,
      isStep: true,
      backwards: backwards,
      preserveViewportMatch: false,
    );
    if (!mounted || !_isFindOpen || seq != _findRequestSeq) return;
    setState(() {
      _findCurrentMatch = result.current;
      _findTotalMatches = result.total;
      _hasCompletedFindForQuery = true;
    });
  }

  Future<void> _clearFindInPage() async {
    _session.debugClearFindInPageOverride?.call();
    final ctrl = _session.controller;
    if (ctrl == null || !_hasPlatformWebView) return;
    try {
      await ctrl.runJavaScript(BrowserFindInPageScript.buildClearScript());
    } catch (_) {}
  }

  Future<void> _openBookmarksAndHistorySheet() async {
    _closeMenu();
    _closeSiteInfoPopover();
    HapticUtils.tap();
    if (!mounted) return;
    await showSafariLibrarySheet(
      context,
      currentUrl: _session.currentUrl,
      currentTitle: _session.displayTitle,
      onSelectUrl: _navigateToUrl,
    );
  }

  void _navigateToUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    _isSiteInfoOpen = false;
    final prevHost = BrowserDataService.extractHost(_session.currentUrl);
    final nextHost = BrowserDataService.extractHost(rawUrl);
    final bool hostChanged = prevHost != nextHost;
    setState(() {
      _session.currentUrl = rawUrl;
      _session.pageTitle = '';
      _session.webResourceErrorDescription = null;
      _session.webResourceErrorUrl = null;
      _session.browserChromeCollapsed = false;
      _session.isReaderModeActive = false;
      _session.activeReaderArticle = null;
      _session.isReaderAvailable = false;
      _session.pendingCardPrompt = null;
      _pullRefreshProgress = 0.0;
      _pullRefreshThresholdHapticFired = false;
      if (hostChanged) {
        _session.browserTopIsDark = null;
        _session.browserCanvasColor = null;
        _session.browserTopPocketColor = null;
        _session.browserBottomPocketColor = null;
      }
      final nextAsciiHost = SafariUrlSafetyAnalyzer.analyzeUrl(rawUrl).asciiHost;
      _session.currentPageHasSslWarning =
          _session.acceptedSslWarningHosts.contains(nextAsciiHost.toLowerCase());
    });
    if (hostChanged) {
      final sitePref =
          BrowserSiteSettingsService.instance.preferenceForUrl(rawUrl);
      _session.pageTextZoom =
          (sitePref?.textZoom ?? 1.0).clamp(0.85, 1.50).toDouble();
      final bool nextDesktop = sitePref?.desktopMode ?? false;
      if (nextDesktop != _session.isDesktopMode) {
        _session.isDesktopMode = nextDesktop;
        final ctrl = _session.controller;
        if (ctrl != null && _hasPlatformWebView) {
          unawaited(
            ctrl.setUserAgent(
              nextDesktop ? MiniAppSession.desktopUserAgent : null,
            ),
          );
          final plat = ctrl.platform;
          if (plat is AndroidWebViewController) {
            unawaited(plat.setUseWideViewPort(nextDesktop));
          }
        }
      }
    }
    _session.controller?.loadRequest(uri);
  }

  void _handleHeaderDragStart(DragStartDetails _) {
    _dragResetController.stop();
    _dragAccumulated = 0.0;
  }

  void _handleHeaderDragUpdate(DragUpdateDetails details) {
    _dragAccumulated += details.delta.dy;
    final double current = _dragOffsetNotifier.value;
    final double nextOffset = (current + details.delta.dy).clamp(0.0, 260.0);
    if ((nextOffset - current).abs() > 0.1) {
      if (_isMenuOpen) {
        _closeMenu();
      }
      if (_isSiteInfoOpen) {
        _closeSiteInfoPopover();
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
      if (_routeAnimation?.status == AnimationStatus.completed &&
          !_isMinimizing) {
        _setRouteRestingOpaque(true);
      }
    });
  }

  void _handleHeaderDragEnd(DragEndDetails details) {
    final double dy = _dragAccumulated;
    final double vy = details.primaryVelocity ?? 0.0;
    _dragAccumulated = 0.0;
    if (dy >= 90 || vy >= 450) {
      unawaited(
        _minimizeToDock(
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
    final resolved = MiniAppJsBridge.resolveThemeColors(theme);
    final style = TheavSurfaceStyle.of(context);
    final mq = MediaQuery.of(context);
    final topInset = mq.padding.top;
    final bottomInset = mq.padding.bottom;
    final bool isReaderActive =
        _session.isReaderModeActive && _session.activeReaderArticle != null;
    final SafariReaderThemeColors? readerColors = isReaderActive
        ? SafariReaderThemeColors.resolve(
            BrowserSiteSettingsService.instance.readerTheme,
            resolved.palette,
          )
        : null;
    final bool isTopDark =
        readerColors?.isDark ?? _session.browserTopIsDark ?? style.isDark;
    final SystemUiOverlayStyle overlayStyle =
        (isTopDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isTopDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isTopDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          isTopDark ? Brightness.light : Brightness.dark,
    );

    final String currentUrl = _session.currentUrl;
    final SafariHostSafetyInfo safetyInfo = SafariUrlSafetyAnalyzer.analyzeUrl(
      currentUrl,
      hasSslWarning: _session.currentPageHasSslWarning,
    );
    final bool isFullySecure =
        safetyInfo.securityLevel == SafariConnectionSecurityLevel.secureHttps;
    final String host = safetyInfo.displayHost.isNotEmpty
        ? safetyInfo.displayHost
        : BrowserDataService.extractHost(currentUrl);
    final String title = _session.displayTitle;
    final bool bookmarked = BrowserDataService.instance.isBookmarked(currentUrl);
    final bool isCompact = _session.browserChromeCollapsed &&
        !_isMenuOpen &&
        !_isFindOpen &&
        !_isSiteInfoOpen &&
        !isReaderActive;
    final bool isRouteCovered = !(ModalRoute.isCurrentOf(context) ?? true);
    final bool isPageInteractionBlocked = isRouteCovered ||
        _isSiteInfoOpen ||
        _isMenuOpen ||
        activeSafariWebAlertCount.value > 0;
    if (_lastScheduledInteractionLock != isPageInteractionBlocked) {
      _lastScheduledInteractionLock = isPageInteractionBlocked;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_session.setWebPageInteractionLocked(isPageInteractionBlocked));
      });
    }
    final Color topPocketBase = readerColors?.background ??
        _session.browserTopPocketColor ??
        _session.browserCanvasColor ??
        resolved.bodyBg;
    final Color bottomPocketBase = readerColors?.background ??
        _session.browserBottomPocketColor ??
        _session.browserCanvasColor ??
        resolved.bodyBg;
    final bool allowEdgeBlur = style.allowBlur || style.allowMaterialBlur;

    final List<BrowserCredentialHint> savedHintsForCurrent =
        BrowserVaultService.instance.getHintsForUrl(currentUrl);
    final bool readerToggleEnabled =
        _session.isReaderAvailable || _session.isReaderModeActive;
    final Widget expandedMenuContent = Padding(
      key: const ValueKey('in_app_browser_overflow_menu'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _browserMenuItem(
              icon: isFullySecure
                  ? Icons.lock_outline_rounded
                  : Icons.gpp_maybe_rounded,
              label: context.trOr('browser_menu_site_info', 'Сведения о сайте'),
              fg: isFullySecure ? resolved.headerFg : resolved.palette.error,
              onTap: () {
                _closeMenu();
                _toggleSiteInfoPopover();
              },
            ),
            _browserMenuItem(
              icon: Icons.refresh_rounded,
              label: context.trOr('browser_menu_refresh', 'Обновить'),
              fg: resolved.headerFg,
              onTap: () {
                _closeMenu();
                _reloadOrStop();
              },
            ),
            _browserMenuItem(
              itemKey: const ValueKey('in_app_browser_menu_reader'),
              icon: _session.isReaderModeActive
                  ? Icons.menu_book_rounded
                  : Icons.article_outlined,
              label: _session.isReaderModeActive
                  ? context.trOr(
                      'browser_reader_exit_mode',
                      'Выйти из режима чтения',
                    )
                  : context.trOr(
                      'browser_reader_enter_mode',
                      'Режим чтения',
                    ),
              fg: _session.isReaderModeActive
                  ? resolved.palette.primary
                  : resolved.headerFg,
              onTap: readerToggleEnabled
                  ? () {
                      _closeMenu();
                      unawaited(_toggleReaderMode());
                    }
                  : null,
            ),
            _browserMenuItem(
              itemKey: const ValueKey('in_app_browser_menu_typography'),
              icon: Icons.text_fields_rounded,
              label: context.trOr(
                'browser_menu_typography',
                'Вид и размер текста (Aa)',
              ),
              fg: resolved.headerFg,
              onTap: _openTypographySheet,
            ),
            _browserMenuItem(
              icon: bookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              label: bookmarked
                  ? context.trOr(
                      'browser_menu_remove_bookmark',
                      'Убрать из закладок',
                    )
                  : context.trOr('browser_menu_add_bookmark', 'В закладки'),
              fg: resolved.headerFg,
              onTap: _toggleBookmark,
            ),
            _browserMenuItem(
              icon: Icons.history_rounded,
              label: context.trOr(
                'browser_menu_library',
                'Закладки и история',
              ),
              fg: resolved.headerFg,
              onTap: _openBookmarksAndHistorySheet,
            ),
            _browserMenuItem(
              icon: Icons.key_rounded,
              label: context.trOr(
                'browser_menu_passwords',
                'Пароли и автозаполнение',
              ),
              fg: resolved.headerFg,
              onTap: () {
                _closeMenu();
                unawaited(
                  showBrowserVaultAndDataSheet(
                    context,
                    initialSection: 0,
                    initialSearchQuery: host,
                  ),
                );
              },
            ),
            _browserMenuItem(
              icon: Icons.search_rounded,
              label: context.trOr(
                'browser_menu_find_in_page',
                'Найти на странице',
              ),
              fg: resolved.headerFg,
              onTap: () {
                _closeMenu();
                _openFindBar();
              },
            ),
            _browserMenuItem(
              icon: _session.isDesktopMode
                  ? Icons.phone_android_rounded
                  : Icons.desktop_windows_rounded,
              label: _session.isDesktopMode
                  ? context.trOr(
                      'browser_menu_mobile_version',
                      'Мобильная версия',
                    )
                  : context.trOr(
                      'browser_menu_desktop_version',
                      'Версия для ПК',
                    ),
              fg: resolved.headerFg,
              onTap: _toggleDesktopMode,
            ),
            _browserMenuItem(
              icon: Icons.copy_rounded,
              label: context.trOr(
                'browser_context_copy_link',
                'Копировать ссылку',
              ),
              fg: resolved.headerFg,
              onTap: _copyCurrentUrl,
            ),
            _browserMenuItem(
              icon: Icons.open_in_browser_rounded,
              label: context.trOr(
                'browser_menu_open_external',
                'Открыть во внешнем браузере',
              ),
              fg: resolved.headerFg,
              onTap: _openExternalBrowser,
            ),
          ],
        ),
      ),
    );

    final Widget expandedSiteInfoContent = SafariSiteInfoPopover(
      bareContent: true,
      safetyInfo: safetyInfo,
      isDesktopMode: _session.isDesktopMode,
      grantedPermissionLabels:
          _session.grantedPermissionLabelsForUrl(currentUrl),
      hasMutedJsDialogs: _session.hasMutedJsDialogsForUrl(currentUrl),
      hasAcceptedSslWarning: _session.hasAcceptedSslWarningForUrl(currentUrl),
      savedPasswordCount: savedHintsForCurrent.length,
      cookiePolicy: BrowserSiteSettingsService.instance.cookiePolicy,
      onCopyUrl: () {
        _closeSiteInfoPopover();
        unawaited(_copyCurrentUrl());
      },
      onUpgradeToHttps:
          SafariUrlSafetyAnalyzer.tryBuildHttpsUpgrade(currentUrl) != null
              ? _upgradeCurrentUrlToHttps
              : null,
      onResetPermissions: () {
        _session.resetSessionPermissionsForUrl(currentUrl);
        _closeSiteInfoPopover();
        if (mounted) {
          GlassToastService().show(
            context,
            context.trOr(
              'browser_site_permissions_reset',
              'Разрешения сайта сброшены',
            ),
            icon: Icons.restart_alt_rounded,
          );
        }
      },
      onOpenSitePasswords: () {
        _closeSiteInfoPopover();
        unawaited(
          showBrowserVaultAndDataSheet(
            context,
            initialSection: 0,
            initialSearchQuery: host,
          ),
        );
      },
      onToggleDesktopMode: () {
        _closeSiteInfoPopover();
        unawaited(_toggleDesktopMode());
      },
      onClearSiteDataAndReload: () {
        unawaited(_clearCurrentSiteDataAndReload());
      },
    );

    final Widget floatingHeader = WebViewFloatingHeader(
      topInset: topInset,
      progressListenable: _session.loadProgressNotifier,
      progressColor: resolved.palette.primary,
      onCenterTap: _openTabsSwitcherFromHeader,
      onCenterLongPress: _copyCurrentUrl,
      isCompact: isCompact,
      onExpandCompact: _expandBrowserChrome,
      isCenterPopoverOpen: _isSiteInfoOpen,
      onDismissCenterPopover: _closeSiteInfoPopover,
      expandedCenterPopoverChild: expandedSiteInfoContent,
      compactCenterChild: Row(
        key: const ValueKey('in_app_browser_compact_domain_row'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFullySecure ? Icons.lock_rounded : Icons.warning_amber_rounded,
            size: 10.5,
            color: isFullySecure
                ? resolved.palette.primary
                : resolved.palette.error,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              host,
              key: const ValueKey('in_app_browser_compact_domain'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
                height: 1.1,
                color: resolved.headerFg,
              ),
            ),
          ),
        ],
      ),
      isMenuOpen: _isMenuOpen,
      onDismissMenu: _closeMenu,
      expandedMenuWidth: 264.0,
      expandedMenuHeight: math.min(
        11 * 44.0 + 16.0,
        math.max(180.0, mq.size.height - topInset - bottomInset - 24.0),
      ),
      expandedMenuChild: expandedMenuContent,
      onVerticalDragStart: _handleHeaderDragStart,
      onVerticalDragUpdate: _handleHeaderDragUpdate,
      onVerticalDragEnd: _handleHeaderDragEnd,
      onVerticalDragCancel: _resetDragOffset,
      leadingChild: IconButton(
        key: const ValueKey('in_app_browser_close_button'),
        tooltip: context.trOr('common_close', 'Закрыть'),
        padding: EdgeInsets.zero,
        icon: Icon(Icons.close_rounded, size: 22, color: resolved.headerFg),
        onPressed: _closeTab,
      ),
      centerChild: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            key: const ValueKey('in_app_browser_security_badge_button'),
            behavior: HitTestBehavior.opaque,
            onTap: _toggleSiteInfoPopover,
            child: Padding(
              padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
              child: Icon(
                isFullySecure
                    ? Icons.lock_rounded
                    : Icons.warning_amber_rounded,
                size: 14,
                color: isFullySecure
                    ? resolved.palette.primary
                    : resolved.palette.error,
              ),
            ),
          ),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: resolved.headerFg,
                  ),
                ),
                Text(
                  host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.15,
                    color: resolved.headerFg.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          ),
          if (readerToggleEnabled)
            Tooltip(
              message: _session.isReaderModeActive
                  ? context.trOr(
                      'browser_reader_exit_mode',
                      'Выйти из режима чтения',
                    )
                  : context.trOr(
                      'browser_reader_enter_mode',
                      'Режим чтения',
                    ),
              child: GestureDetector(
                key: const ValueKey('in_app_browser_reader_button'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticUtils.tap();
                  unawaited(_toggleReaderMode());
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 6, top: 6, bottom: 6),
                  child: Icon(
                    _session.isReaderModeActive
                        ? Icons.menu_book_rounded
                        : Icons.article_outlined,
                    size: 16,
                    color: _session.isReaderModeActive
                        ? resolved.palette.primary
                        : resolved.headerFg.withValues(alpha: 0.78),
                  ),
                ),
              ),
            ),
        ],
      ),
      trailingActions: [
        SizedBox(
          width: 40,
          height: 44,
          child: IconButton(
            key: const ValueKey('in_app_browser_minimize_button'),
            tooltip: context.trOr('miniapp_menu_minimize', 'Свернуть'),
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 24,
              color: resolved.headerFg,
            ),
            onPressed: _minimizeToDock,
          ),
        ),
        SizedBox(
          width: 40,
          height: 44,
          child: IconButton(
            key: const ValueKey('in_app_browser_menu_button'),
            tooltip: context.trOr('browser_header_menu', 'Меню'),
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.more_vert_rounded,
              size: 21,
              color: resolved.headerFg,
            ),
            onPressed: _toggleMenu,
          ),
        ),
      ],
    );

    final bool mountFindBar = _isFindOpen || !_findBarController.isDismissed;
    final bool hasFindQuery = _findCtrl.text.trim().isNotEmpty;
    final bool canStepFind =
        hasFindQuery && (!_hasCompletedFindForQuery || _findTotalMatches > 0);
    final Widget? floatingFindBar = mountFindBar
        ? AnimatedBuilder(
            animation: _findBarAnimation,
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: resolved.headerFg.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    key: const ValueKey('in_app_browser_find_input'),
                    controller: _findCtrl,
                    focusNode: _findFocusNode,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    cursorColor: resolved.palette.primary,
                    style: TextStyle(
                      fontSize: 14,
                      color: resolved.headerFg,
                    ),
                    decoration: InputDecoration(
                      hintText: context.trOr(
                        'browser_find_hint',
                        'Найти на странице...',
                      ),
                      hintStyle: TextStyle(
                        fontSize: 13.5,
                        color: resolved.headerFg.withValues(alpha: 0.55),
                      ),
                      isDense: true,
                      filled: false,
                      fillColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                    ),
                    onChanged: _onFindQueryChanged,
                    onSubmitted: (_) =>
                        unawaited(_stepFindMatch(backwards: false)),
                  ),
                ),
                if (hasFindQuery && _hasCompletedFindForQuery)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      _findTotalMatches > 0
                          ? context.trOr(
                              'browser_find_counter',
                              '{current} из {total}',
                              <String, String>{
                                'current': '$_findCurrentMatch',
                                'total': '$_findTotalMatches',
                              },
                            )
                          : context.trOr('browser_find_zero', '0 из 0'),
                      key: const ValueKey('in_app_browser_find_counter'),
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: resolved.headerFg.withValues(
                          alpha: _findTotalMatches > 0 ? 0.78 : 0.48,
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  key: const ValueKey('in_app_browser_find_prev_btn'),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 21,
                    color: resolved.headerFg.withValues(
                      alpha: canStepFind ? 1.0 : 0.32,
                    ),
                  ),
                  onPressed: canStepFind
                      ? () => unawaited(_stepFindMatch(backwards: true))
                      : null,
                ),
                IconButton(
                  key: const ValueKey('in_app_browser_find_next_btn'),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 21,
                    color: resolved.headerFg.withValues(
                      alpha: canStepFind ? 1.0 : 0.32,
                    ),
                  ),
                  onPressed: canStepFind
                      ? () => unawaited(_stepFindMatch(backwards: false))
                      : null,
                ),
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 19,
                    color: resolved.headerFg,
                  ),
                  onPressed: _closeFindBar,
                ),
              ],
            ),
            builder: (context, rowChild) {
              final double rawT = _findBarController.value;
              final double eased = _findBarAnimation.value;
              final double travelY = topInset + 116.0;
              final double dy = -travelY * (1.0 - eased);
              final double clamped = eased.clamp(0.0, 1.03);
              final double scaleX = 0.90 + 0.10 * clamped.clamp(0.0, 1.015);
              final double scaleY = 0.84 + 0.16 * clamped;
              final double visualBottomY =
                  (topInset + 60.0) + dy + 46.0 * scaleY;
              final bool capsuleVisible =
                  rawT > 0.01 && visualBottomY > -2.0;

              return Transform.translate(
                offset: Offset(0.0, dy),
                child: Transform(
                  alignment: Alignment.topCenter,
                  transform: Matrix4.diagonal3Values(scaleX, scaleY, 1.0),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: WebViewFloatingCapsule(
                      key: const ValueKey('in_app_browser_find_bar'),
                      height: 46,
                      borderRadius: 22,
                      visible: capsuleVisible,
                      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                      child: rowChild!,
                    ),
                  ),
                ),
              );
            },
          )
        : null;

    final ImageProvider? standInSnapshot =
        (!_isTransitionReady || !_isWebViewSurfacePainted)
            ? _session.fullViewportPreviewProvider
            : null;
    final bool mountWebView = _isTransitionReady && _session.controller != null;

    final Widget baseWebLayer = _hasPlatformWebView
        ? Stack(
            fit: StackFit.expand,
            children: [
              if (standInSnapshot != null)
                Positioned.fill(
                  key: const ValueKey('in_app_browser_restore_snapshot'),
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
                          color: resolved.bodyBg,
                          child: WebViewWidget(controller: _session.controller!),
                        ),
                ),
              if (standInSnapshot == null &&
                  !mountWebView &&
                  _session.webResourceErrorDescription == null)
                Positioned.fill(
                  child: ColoredBox(
                    color: resolved.bodyBg,
                    child: Center(
                      child: MiniAppGridPlaceholder(
                        key: const ValueKey('in_app_browser_loader'),
                        bodyColor: resolved.bodyBg,
                        foregroundColor: resolved.headerFg,
                        animate: true,
                      ),
                    ),
                  ),
                ),
              if (_session.webResourceErrorDescription != null)
                Positioned.fill(
                  key: const ValueKey('in_app_browser_web_error_overlay'),
                  child: ColoredBox(
                    color: resolved.bodyBg,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          topInset + (_isFindOpen ? 124 : 72),
                          24,
                          bottomInset + 80,
                        ),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 340),
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: resolved.surfaceBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: resolved.divider),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.wifi_off_rounded,
                                size: 36,
                                color: resolved.palette.subtext,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                context.trOr(
                                  'browser_error_load_title',
                                  'Не удалось открыть страницу',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: resolved.headerFg,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _session.webResourceErrorDescription!,
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: resolved.palette.subtext,
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                key: const ValueKey(
                                  'in_app_browser_web_retry_button',
                                ),
                                onPressed: () =>
                                    unawaited(_session.retryMainFrameLoad()),
                                icon:
                                    const Icon(Icons.refresh_rounded, size: 18),
                                label: Text(
                                  context.trOr('common_retry', 'Повторить'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          )
        : Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                topInset + (_isFindOpen ? 124 : 72),
                24,
                bottomInset + 80,
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: resolved.surfaceBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: resolved.divider, width: 0.8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconoir.Internet(
                      width: 38,
                      height: 38,
                      color: resolved.palette.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      host,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: resolved.palette.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      currentUrl,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: resolved.palette.subtext,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TheavFloatingPillButton(
                      label: context.trOr(
                        'browser_menu_open_external',
                        'Открыть во внешнем браузере',
                      ),
                      isPrimary: true,
                      onTap: _openExternalBrowser,
                    ),
                  ],
                ),
              ),
            ),
          );

    final Widget webBody = Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: isReaderActive,
          child: baseWebLayer,
        ),
        if (isReaderActive)
          Positioned.fill(
            child: SafariReaderModeView(
              article: _session.activeReaderArticle!,
              themeId: BrowserSiteSettingsService.instance.readerTheme,
              fontFamilyId:
                  BrowserSiteSettingsService.instance.readerFontFamily,
              fontScale: BrowserSiteSettingsService.instance.readerFontScale,
              topClearance: topInset + 58.0,
              bottomClearance: bottomInset + 64.0,
              scrollController: _readerScrollCtrl,
              onExitReader: _exitReaderMode,
            ),
          ),
      ],
    );

    final double bottomExpandTarget = isCompact ? 0.0 : 1.0;
    final Widget floatingBottomBar = Positioned(
      left: 16,
      right: 16,
      bottom: bottomInset + 9.0,
      child: IgnorePointer(
        key: const ValueKey('in_app_browser_bottom_bar_ignore'),
        ignoring: isCompact || isPageInteractionBlocked,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: bottomExpandTarget,
            end: bottomExpandTarget,
          ),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            final bool visible = t > 0.02;
            return Transform.translate(
              offset: Offset(0.0, (bottomInset + 68.0) * (1.0 - t)),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: WebViewFloatingCapsule(
                    key: const ValueKey('in_app_browser_bottom_bar'),
                    height: 48,
                    borderRadius: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visible: visible,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          tooltip: context.trOr('common_back', 'Назад'),
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 19,
                            color: _session.canGoBack
                                ? resolved.headerFg
                                : resolved.headerFg.withValues(alpha: 0.35),
                          ),
                          onPressed: _session.canGoBack ? _goBack : null,
                        ),
                        IconButton(
                          tooltip:
                              context.trOr('browser_nav_forward', 'Вперёд'),
                          icon: Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 19,
                            color: _session.canGoForward
                                ? resolved.headerFg
                                : resolved.headerFg.withValues(alpha: 0.35),
                          ),
                          onPressed: _session.canGoForward ? _goForward : null,
                        ),
                        IconButton(
                          tooltip:
                              context.trOr('browser_nav_share', 'Поделиться'),
                          icon: Icon(
                            Icons.ios_share_rounded,
                            size: 20,
                            color: resolved.headerFg,
                          ),
                          onPressed: _shareCurrentUrl,
                        ),
                        IconButton(
                          tooltip: context.trOr(
                            'browser_menu_library',
                            'Закладки и история',
                          ),
                          icon: Icon(
                            bookmarked
                                ? Icons.bookmark_rounded
                                : Icons.bookmarks_outlined,
                            size: 21,
                            color: bookmarked
                                ? resolved.palette.primary
                                : resolved.headerFg,
                          ),
                          onPressed: _openBookmarksAndHistorySheet,
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: _session.loadProgressNotifier,
                          builder: (context, progress, _) {
                            final bool isLoading =
                                progress > 0.0 && progress < 1.0;
                            return IconButton(
                              tooltip: isLoading
                                  ? context.trOr('browser_nav_stop', 'Стоп')
                                  : context.trOr(
                                      'browser_menu_refresh',
                                      'Обновить',
                                    ),
                              icon: Icon(
                                isLoading
                                    ? Icons.close_rounded
                                    : Icons.refresh_rounded,
                                size: 21,
                                color: resolved.headerFg,
                              ),
                              onPressed: _reloadOrStop,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    final Widget hudOverlayStack = Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        if (floatingFindBar != null)
          Positioned(
            top: topInset + 60.0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_isFindOpen || isPageInteractionBlocked,
              child: ExcludeFocus(
                excluding: !_isFindOpen || isPageInteractionBlocked,
                child: floatingFindBar,
              ),
            ),
          ),
        floatingBottomBar,
        if (_session.focusedAutofillField != null && !isReaderActive)
          Positioned(
            left: 0,
            right: 0,
            bottom: mq.viewInsets.bottom > 0
                ? mq.viewInsets.bottom + 8.0
                : bottomInset + 64.0,
            child: IgnorePointer(
              ignoring: isPageInteractionBlocked,
              child: SafariAutofillAccessoryBar(
                focusedField: _session.focusedAutofillField!,
                hints: savedHintsForCurrent,
                contactProfile: _contactProfile,
                totalSavedCount: BrowserVaultService.instance.hints.length,
                onSelectCredential: (hint) =>
                    unawaited(_handleAutofillSelectCredential(hint)),
                onOpenPasswordPicker: () => unawaited(
                  showBrowserVaultAndDataSheet(
                    context,
                    initialSection: 0,
                    initialSearchQuery: host,
                    onSelectForAutofill: (hint) =>
                        unawaited(_handleAutofillSelectCredential(hint)),
                  ),
                ),
                onFillContact: () => unawaited(_handleAutofillFillContact()),
                cards: BrowserVaultService.instance.cardHints,
                totalSavedCardsCount:
                    BrowserVaultService.instance.cardHints.length,
                onSelectCard: (card) =>
                    unawaited(_handleAutofillSelectCard(card)),
                onOpenCardPicker: () => unawaited(
                  showBrowserVaultAndDataSheet(
                    context,
                    initialSection: 1,
                    autoUnlockPasswords: false,
                    onSelectCardForAutofill: (card) =>
                        unawaited(_handleAutofillSelectCard(card)),
                  ),
                ),
                addresses: BrowserVaultService.instance.addresses,
                onSelectAddress: (addr) =>
                    unawaited(_handleAutofillSelectAddress(addr)),
                onOpenAddressPicker: () => unawaited(
                  showBrowserVaultAndDataSheet(
                    context,
                    initialSection: 1,
                    autoUnlockPasswords: false,
                    onSelectAddressForAutofill: (addr) =>
                        unawaited(_handleAutofillSelectAddress(addr)),
                  ),
                ),
                otpCandidateCode:
                    BrowserOtpAutofillService.instance.activeCandidate?.code,
                showExplicitPasteOtpChip: BrowserOtpAutofillService
                    .instance.showExplicitPasteOtpAction,
                onFillOtp: (code) => unawaited(_handleAutofillFillOtp(code)),
                onPasteOtpFromClipboard: () =>
                    unawaited(_handlePasteOtpFromClipboard()),
                onDismiss: () {
                  setState(() => _session.focusedAutofillField = null);
                },
              ),
            ),
          ),
        if (_session.pendingCredentialPrompt != null && !isReaderActive)
          Positioned(
            left: 0,
            right: 0,
            bottom: math.max(
              bottomInset + 66.0,
              mq.viewInsets.bottom + 12.0,
            ),
            child: IgnorePointer(
              ignoring: isPageInteractionBlocked,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SafariSavePasswordSheet(
                  candidate: _session.pendingCredentialPrompt!,
                  onSave: (u) => unawaited(_handleSavePendingPassword(u)),
                  onNeverSave: () => unawaited(_handleNeverSavePendingPassword()),
                  onDismiss: () {
                    setState(() => _session.pendingCredentialPrompt = null);
                  },
                ),
              ),
            ),
          ),
        if (_session.pendingCardPrompt != null &&
            _session.pendingCredentialPrompt == null &&
            !isReaderActive)
          Positioned(
            left: 0,
            right: 0,
            bottom: math.max(
              bottomInset + 66.0,
              mq.viewInsets.bottom + 12.0,
            ),
            child: IgnorePointer(
              ignoring: isPageInteractionBlocked,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SafariSaveCardSheet(
                  candidate: _session.pendingCardPrompt!,
                  onSave: () => unawaited(_handleSavePendingCard()),
                  onDismiss: () {
                    setState(() => _session.pendingCardPrompt = null);
                  },
                ),
              ),
            ),
          ),
        if (_pullRefreshProgress > 0.02 && !isReaderActive)
          Positioned(
            key: const ValueKey('in_app_browser_ptr_capsule'),
            top: topInset + 62.0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Transform.translate(
                  offset: Offset(0.0, -16.0 * (1.0 - _pullRefreshProgress)),
                  child: Transform.scale(
                    scale: 0.85 + 0.15 * _pullRefreshProgress,
                    child: WebViewFloatingCapsule(
                      height: 36,
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              value: _pullRefreshProgress >= 1.0
                                  ? null
                                  : _pullRefreshProgress,
                              strokeWidth: 2.0,
                              color: _pullRefreshProgress >= 1.0
                                  ? resolved.palette.primary
                                  : resolved.headerFg.withValues(alpha: 0.82),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Transform.rotate(
                            angle: _pullRefreshProgress * math.pi * 1.5,
                            child: Icon(
                              Icons.refresh_rounded,
                              size: 16,
                              color: _pullRefreshProgress >= 1.0
                                  ? resolved.palette.primary
                                  : resolved.headerFg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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

    final Widget sheetBody = Material(
      key: const ValueKey('in_app_browser_sheet'),
      color: resolved.bodyBg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              key: const ValueKey('in_app_browser_web_interaction_guard'),
              ignoring: isPageInteractionBlocked,
              child: ExcludeFocus(
                excluding: isPageInteractionBlocked,
                child: webBody,
              ),
            ),
          ),
          Positioned(
            key: const ValueKey('in_app_browser_top_scroll_pocket'),
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: BrowserScrollPocket(
                edge: LiquidGlassEdge.top,
                height: topInset + (isCompact ? 20.0 : 24.0),
                color: topPocketBase.withValues(alpha: 0.88),
                blurSigma: allowEdgeBlur ? 3.5 : 0.0,
              ),
            ),
          ),
          Positioned(
            key: const ValueKey('in_app_browser_bottom_scroll_pocket'),
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: BrowserScrollPocket(
                edge: LiquidGlassEdge.bottom,
                height: math.max(
                  isCompact
                      ? (bottomInset > 0 ? bottomInset + 8.0 : 0.0)
                      : (bottomInset + 24.0),
                  0.0,
                ),
                color: bottomPocketBase.withValues(
                  alpha: isCompact ? 0.65 : 0.84,
                ),
                blurSigma: allowEdgeBlur ? 3.0 : 0.0,
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
    );

    return BackdropGroup(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: PopScope(
          canPop: _allowRoutePop,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (await _session.dismissFullscreenVideoOverlay()) {
              HapticUtils.tap();
              return;
            }
            if (_session.pendingCredentialPrompt != null) {
              setState(() => _session.pendingCredentialPrompt = null);
              return;
            }
            if (_session.pendingCardPrompt != null) {
              setState(() => _session.pendingCardPrompt = null);
              return;
            }
            if (_isSiteInfoOpen) {
              _closeSiteInfoPopover();
              return;
            }
            if (_isMenuOpen) {
              _closeMenu();
              return;
            }
            if (_isFindOpen) {
              _closeFindBar();
              return;
            }
            if (_session.isReaderModeActive) {
              HapticUtils.tap();
              _exitReaderMode();
              return;
            }
            final movedBack = await _session.performWebBack();
            if (movedBack) {
              HapticUtils.tap();
              if (_session.browserChromeCollapsed) {
                unawaited(_session.setBrowserChromeCollapsed(false));
              }
              if (mounted) setState(() {});
            } else if (_session.browserChromeCollapsed) {
              _expandBrowserChrome();
            }
            // System Back stays within browser history/controls; [×] closes the sheet.
          },
          child: ValueListenableBuilder<double>(
            valueListenable: _dragOffsetNotifier,
            builder: (context, offsetY, child) => MiniAppDragOffset(
              offsetY: offsetY,
              child: child!,
            ),
            child: sheetBody,
          ),
        ),
      ),
    );
  }

  Widget _browserMenuItem({
    Key? itemKey,
    required IconData icon,
    required String label,
    required Color fg,
    VoidCallback? onTap,
  }) {
    final bool enabled = onTap != null;
    final Color effectiveFg = enabled ? fg : fg.withValues(alpha: 0.36);
    return InkWell(
      key: itemKey,
      onTap: enabled
          ? () {
              HapticUtils.tap();
              onTap();
            }
          : null,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 19, color: effectiveFg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: effectiveFg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
