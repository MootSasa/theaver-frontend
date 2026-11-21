import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/bot_service.dart';
import '../../services/browser_data_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/mini_app_js_bridge.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/safari_url_safety.dart';
import '../bot/mini_app_webview_sheet.dart';
import '../design_system/theav_design_system.dart';
import 'safari_browser_dialogs.dart';
import 'safari_library_sheet.dart';

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
  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  late final MiniAppSession _session;
  late final BrowserUiDialogDelegate _dialogDelegate;
  late final AnimationController _dragResetController;
  final ValueNotifier<double> _dragOffsetNotifier = ValueNotifier<double>(0.0);
  final TextEditingController _findCtrl = TextEditingController();

  bool _isMenuOpen = false;
  bool _isSiteInfoOpen = false;
  bool _isFindOpen = false;
  String _findStatus = '';
  double _dragResetFrom = 0.0;
  double _dragAccumulated = 0.0;
  bool _isMinimizing = false;
  bool _allowRoutePop = false;
  bool _hasFullScreenRegistration = false;
  bool _hasSettledRegistration = false;
  bool _isTransitionReady = false;
  bool _isWebViewSurfacePainted = false;
  bool _didInjectInsetsOnMount = false;
  Timer? _earlyWebViewWarmupTimer;
  Animation<double>? _routeAnimation;
  bool? _lastRequestedRestingOpaque;

  bool get _hasPlatformWebView => !kIsWeb && WebViewPlatform.instance != null;

  void _onSessionStateChanged() {
    if (mounted) setState(() {});
  }

  void _onActiveSafariAlertChanged() {
    if (mounted) setState(() {});
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
    _dialogDelegate = SheetBrowserUiDialogDelegate(
      contextResolver: () => context,
      mountedResolver: () => mounted,
    );
    _session.uiDialogDelegate = _dialogDelegate;
    _session.onSheetStateChanged = _onSessionStateChanged;
    activeSafariWebAlertCount.addListener(_onActiveSafariAlertChanged);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    unawaited(BrowserDataService.instance.ensureLoaded());
    BrowserDataService.instance.addListener(_onBrowserDataChanged);
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (!mounted || activeSafariWebAlertCount.value > 0) return false;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (_isSiteInfoOpen) {
      _closeSiteInfoPopover();
      return true;
    }
    if (_isMenuOpen) {
      _closeMenu();
      return true;
    }
    if (_isFindOpen) {
      setState(() {
        _isFindOpen = false;
        _findStatus = '';
      });
      _updateBrowserSafeClearances();
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
  }

  void _onBrowserDataChanged() {
    if (mounted) setState(() {});
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
    BrowserDataService.instance.removeListener(_onBrowserDataChanged);
    if (identical(_session.uiDialogDelegate, _dialogDelegate)) {
      _session.uiDialogDelegate = null;
    }
    if (identical(_session.onSheetStateChanged, _onSessionStateChanged)) {
      _session.onSheetStateChanged = null;
    }
    _dragOffsetNotifier.dispose();
    _dragResetController.dispose();
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
    _closeMenu();
    _closeSiteInfoPopover();
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
    _closeMenu();
    _closeSiteInfoPopover();
    unawaited(_session.setWebPageInteractionLocked(false));
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
      if (_isSiteInfoOpen) _isSiteInfoOpen = false;
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
        await ctrl.reload();
      } catch (_) {}
    }
    if (mounted) {
      GlassToastService().show(
        context,
        'Данные сайта очищены',
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
    } else {
      await ctrl.reload();
    }
  }

  Future<void> _toggleDesktopMode() async {
    _closeMenu();
    final nextDesktop = !_session.isDesktopMode;
    setState(() => _session.isDesktopMode = nextDesktop);
    final ctrl = _session.controller;
    if (ctrl != null && _hasPlatformWebView) {
      await ctrl.setUserAgent(nextDesktop ? _desktopUserAgent : null);
      await ctrl.reload();
    }
    if (mounted) {
      GlassToastService().show(
        context,
        nextDesktop ? 'Включена версия для ПК' : 'Включена мобильная версия',
      );
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
        added ? 'Добавлено в закладки' : 'Удалено из закладок',
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
      GlassToastService().show(context, 'Ссылка скопирована', icon: Icons.check);
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

  Future<void> _findInPage(String query, {bool backwards = false}) async {
    final ctrl = _session.controller;
    final clean = query.trim();
    if (clean.isEmpty) {
      if (mounted) setState(() => _findStatus = '');
      return;
    }
    if (ctrl == null || !_hasPlatformWebView) return;
    try {
      final js =
          '(function(){ return !!window.find(${jsonEncode(clean)}, false, ${backwards ? 'true' : 'false'}, true, false, false, false); })();';
      final res = await ctrl.runJavaScriptReturningResult(js);
      if (mounted) {
        final found = res == true || res.toString() == 'true';
        setState(() => _findStatus = found ? 'Найдено' : 'Не найдено');
      }
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
    setState(() {
      _session.currentUrl = rawUrl;
      _session.pageTitle = '';
      final nextHost = SafariUrlSafetyAnalyzer.analyzeUrl(rawUrl).asciiHost;
      _session.currentPageHasSslWarning =
          _session.acceptedSslWarningHosts.contains(nextHost.toLowerCase());
    });
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
    final bool isTopDark = _session.browserTopIsDark ?? style.isDark;
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
        !_isSiteInfoOpen;
    final bool isRouteCovered = !(ModalRoute.isCurrentOf(context) ?? true);
    final bool isPageInteractionBlocked = isRouteCovered ||
        _isSiteInfoOpen ||
        _isMenuOpen ||
        activeSafariWebAlertCount.value > 0;
    unawaited(_session.setWebPageInteractionLocked(isPageInteractionBlocked));
    final Color topPocketBase = _session.browserTopPocketColor ??
        _session.browserCanvasColor ??
        resolved.bodyBg;
    final Color bottomPocketBase = _session.browserBottomPocketColor ??
        _session.browserCanvasColor ??
        resolved.bodyBg;
    final bool allowEdgeBlur = style.allowBlur || style.allowMaterialBlur;

    final Widget expandedMenuContent = Padding(
      key: const ValueKey('in_app_browser_overflow_menu'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _browserMenuItem(
              icon: isFullySecure
                  ? Icons.lock_outline_rounded
                  : Icons.gpp_maybe_rounded,
              label: 'Сведения о сайте',
              fg: isFullySecure ? resolved.headerFg : resolved.palette.error,
              onTap: () {
                _closeMenu();
                _toggleSiteInfoPopover();
              },
            ),
            _browserMenuItem(
              icon: Icons.refresh_rounded,
              label: 'Обновить',
              fg: resolved.headerFg,
              onTap: () {
                _closeMenu();
                _reloadOrStop();
              },
            ),
            _browserMenuItem(
              icon: bookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              label: bookmarked ? 'Убрать из закладок' : 'В закладки',
              fg: resolved.headerFg,
              onTap: _toggleBookmark,
            ),
            _browserMenuItem(
              icon: Icons.history_rounded,
              label: 'Закладки и история',
              fg: resolved.headerFg,
              onTap: _openBookmarksAndHistorySheet,
            ),
            _browserMenuItem(
              icon: Icons.search_rounded,
              label: 'Найти на странице',
              fg: resolved.headerFg,
              onTap: () {
                _closeMenu();
                setState(() => _isFindOpen = true);
                _updateBrowserSafeClearances();
                if (_session.browserChromeCollapsed) {
                  unawaited(_session.setBrowserChromeCollapsed(false));
                }
              },
            ),
            _browserMenuItem(
              icon: _session.isDesktopMode
                  ? Icons.phone_android_rounded
                  : Icons.desktop_windows_rounded,
              label: _session.isDesktopMode
                  ? 'Мобильная версия'
                  : 'Версия для ПК',
              fg: resolved.headerFg,
              onTap: _toggleDesktopMode,
            ),
            _browserMenuItem(
              icon: Icons.copy_rounded,
              label: 'Копировать ссылку',
              fg: resolved.headerFg,
              onTap: _copyCurrentUrl,
            ),
            _browserMenuItem(
              icon: Icons.open_in_browser_rounded,
              label: 'Открыть во внешнем браузере',
              fg: resolved.headerFg,
              onTap: _openExternalBrowser,
            ),
          ],
        ),
      ),
    );

    final Widget floatingHeader = WebViewFloatingHeader(
      topInset: topInset,
      progressListenable: _session.loadProgressNotifier,
      progressColor: resolved.palette.primary,
      onCenterTap: _openTabsSwitcherFromHeader,
      onCenterLongPress: _copyCurrentUrl,
      isCompact: isCompact,
      onExpandCompact: _expandBrowserChrome,
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
      expandedMenuWidth: 260.0,
      expandedMenuHeight: 8 * 44.0 + 12.0,
      expandedMenuChild: expandedMenuContent,
      onVerticalDragStart: _handleHeaderDragStart,
      onVerticalDragUpdate: _handleHeaderDragUpdate,
      onVerticalDragEnd: _handleHeaderDragEnd,
      onVerticalDragCancel: _resetDragOffset,
      leadingChild: IconButton(
        key: const ValueKey('in_app_browser_close_button'),
        tooltip: 'Закрыть',
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
        ],
      ),
      trailingActions: [
        SizedBox(
          width: 40,
          height: 44,
          child: IconButton(
            key: const ValueKey('in_app_browser_minimize_button'),
            tooltip: 'Свернуть',
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
            tooltip: 'Меню',
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

    final Widget? floatingFindBar = _isFindOpen
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: WebViewFloatingCapsule(
              height: 46,
              borderRadius: 22,
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _findCtrl,
                      autofocus: true,
                      style: TextStyle(
                        fontSize: 14,
                        color: resolved.headerFg,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Найти на странице...',
                        hintStyle: TextStyle(
                          fontSize: 13.5,
                          color: resolved.headerFg.withValues(alpha: 0.55),
                        ),
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (v) => _findInPage(v),
                    ),
                  ),
                  if (_findStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        _findStatus,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: resolved.headerFg.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(
                      Icons.keyboard_arrow_up_rounded,
                      size: 21,
                      color: resolved.headerFg,
                    ),
                    onPressed: () =>
                        _findInPage(_findCtrl.text, backwards: true),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 21,
                      color: resolved.headerFg,
                    ),
                    onPressed: () => _findInPage(_findCtrl.text),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 19,
                      color: resolved.headerFg,
                    ),
                    onPressed: () {
                      setState(() {
                        _isFindOpen = false;
                        _findStatus = '';
                      });
                      _updateBrowserSafeClearances();
                    },
                  ),
                ],
              ),
            ),
          )
        : null;

    final ImageProvider? standInSnapshot =
        (!_isTransitionReady || !_isWebViewSurfacePainted)
            ? _session.fullViewportPreviewProvider
            : null;
    final bool mountWebView = _isTransitionReady && _session.controller != null;

    final Widget webBody = _hasPlatformWebView
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
              if (standInSnapshot == null && !mountWebView)
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
                      label: 'Открыть во внешнем браузере',
                      isPrimary: true,
                      onTap: _openExternalBrowser,
                    ),
                  ],
                ),
              ),
            ),
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
                          tooltip: 'Назад',
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
                          tooltip: 'Вперёд',
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
                          tooltip: 'Поделиться',
                          icon: Icon(
                            Icons.ios_share_rounded,
                            size: 20,
                            color: resolved.headerFg,
                          ),
                          onPressed: _shareCurrentUrl,
                        ),
                        IconButton(
                          tooltip: 'Закладки и история',
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
                              tooltip: isLoading ? 'Стоп' : 'Обновить',
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
              ignoring: isPageInteractionBlocked,
              child: ExcludeFocus(
                excluding: isPageInteractionBlocked,
                child: floatingFindBar,
              ),
            ),
          ),
        floatingBottomBar,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: floatingHeader,
        ),
        if (_isSiteInfoOpen) ...[
          Positioned.fill(
            key: const ValueKey('in_app_browser_site_info_backdrop'),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeSiteInfoPopover,
              onVerticalDragStart: (_) {},
              onVerticalDragUpdate: (_) {},
              onHorizontalDragStart: (_) {},
              onHorizontalDragUpdate: (_) {},
            ),
          ),
          Positioned(
            top: topInset + 58.0,
            left: 16.0,
            right: 16.0,
            child: Align(
              alignment: Alignment.topCenter,
              child: LiquidGlassBatch.exclude(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  builder: (context, v, child) {
                    final double scale = 0.88 + 0.12 * v;
                    final double dy = -10.0 * (1.0 - v.clamp(0.0, 1.0));
                    return Transform.translate(
                      offset: Offset(0.0, dy),
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.topCenter,
                        child: child,
                      ),
                    );
                  },
                  child: SafariSiteInfoPopover(
                    safetyInfo: safetyInfo,
                    isDesktopMode: _session.isDesktopMode,
                    grantedPermissionLabels:
                        _session.grantedPermissionLabelsForUrl(currentUrl),
                    hasMutedJsDialogs:
                        _session.hasMutedJsDialogsForUrl(currentUrl),
                    hasAcceptedSslWarning:
                        _session.hasAcceptedSslWarningForUrl(currentUrl),
                    onCopyUrl: () {
                      _closeSiteInfoPopover();
                      unawaited(_copyCurrentUrl());
                    },
                    onUpgradeToHttps: SafariUrlSafetyAnalyzer
                                .tryBuildHttpsUpgrade(currentUrl) !=
                            null
                        ? _upgradeCurrentUrlToHttps
                        : null,
                    onResetPermissions: () {
                      _session.resetSessionPermissionsForUrl(currentUrl);
                      _closeSiteInfoPopover();
                      if (mounted) {
                        GlassToastService().show(
                          context,
                          'Разрешения сайта сброшены',
                          icon: Icons.restart_alt_rounded,
                        );
                      }
                    },
                    onToggleDesktopMode: () {
                      _closeSiteInfoPopover();
                      unawaited(_toggleDesktopMode());
                    },
                    onClearSiteDataAndReload: () {
                      unawaited(_clearCurrentSiteDataAndReload());
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
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
              child: _BrowserScrollPocket(
                edge: LiquidGlassEdge.top,
                height: topInset + (isCompact ? 22.0 : 26.0),
                color: topPocketBase.withValues(alpha: 0.90),
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
              child: _BrowserScrollPocket(
                edge: LiquidGlassEdge.bottom,
                height: math.max(
                  isCompact
                      ? (bottomInset > 0 ? bottomInset + 8.0 : 0.0)
                      : (bottomInset + 24.0),
                  0.0,
                ),
                color: bottomPocketBase.withValues(alpha: isCompact ? 0.65 : 0.84),
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
            if (_isSiteInfoOpen) {
              _closeSiteInfoPopover();
              return;
            }
            if (_isMenuOpen) {
              _closeMenu();
              return;
            }
            if (_isFindOpen) {
              setState(() {
                _isFindOpen = false;
                _findStatus = '';
              });
              _updateBrowserSafeClearances();
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
    required IconData icon,
    required String label,
    required Color fg,
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
              Icon(icon, size: 19, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: fg,
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

/// Smoothly adapts Safari iOS 26 style feathered edge "Scroll Pocket" color
/// and height over the top status bar and bottom gesture area.
class _BrowserScrollPocket extends StatelessWidget {
  final LiquidGlassEdge edge;
  final double height;
  final Color color;
  final double blurSigma;

  const _BrowserScrollPocket({
    required this.edge,
    required this.height,
    required this.color,
    required this.blurSigma,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(begin: color, end: color),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, animatedColor, _) {
        final Color resolvedColor = animatedColor ?? color;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: height,
          child: height <= 0.5
              ? const SizedBox.shrink()
              : LiquidGlassScrollEdge(
                  edge: edge,
                  color: resolvedColor,
                  blur: blurSigma,
                  style: LiquidGlassScrollEdgeStyle.soft,
                ),
        );
      },
    );
  }
}
