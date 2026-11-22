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

import '../../screens/settings/browser_vault_and_data_screen.dart';
import '../../services/bot_service.dart';
import '../../services/browser_cookie_jar_vault.dart';
import '../../services/browser_data_service.dart';
import '../../services/browser_site_settings_service.dart';
import '../../services/browser_vault_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/mini_app_js_bridge.dart';
import '../../utils/browser_autofill_script.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/safari_url_safety.dart';
import '../bot/mini_app_webview_sheet.dart';
import '../design_system/theav_design_system.dart';
import 'safari_autofill_overlays.dart';
import 'safari_browser_dialogs.dart';
import 'safari_library_sheet.dart';

/// Opens [url] inside Theaver's Telegram-style full-screen WebView browser,
/// or restores an already minimized browser tab with the same URL and privacy mode.
Future<void> openInAppBrowser(
  BuildContext context, {
  required String url,
  bool isIncognito = false,
}) async {
  final cleanUrl = url.trim();
  if (cleanUrl.isEmpty) return;

  final sessionCtrl = MiniAppSessionController.instance;
  for (final existing in sessionCtrl.minimizedSessions.reversed) {
    if (existing.isBrowser &&
        existing.isIncognito == isIncognito &&
        existing.currentUrl == cleanUrl) {
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
    isIncognito: isIncognito,
    initialUrl: cleanUrl,
  );
  if (isIncognito) {
    await BrowserCookieJarVault.instance.onIncognitoSessionOpened(session.id);
  }
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

/// Prompts the user for a website URL or search query (with bookmark shortcuts)
/// and opens a new normal or «Частный доступ» browser tab.
Future<void> openNewBrowserTabPrompt(
  BuildContext context, {
  bool isIncognito = false,
}) async {
  await BrowserDataService.instance.ensureLoaded();
  if (!context.mounted) return;

  final ctrl = TextEditingController();
  final bookmarks = BrowserDataService.instance.bookmarks.take(4).toList();
  final String? entered = await showTheavModalSheet<String>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    maxHeightFactor: 0.56,
    title: isIncognito ? 'Новая частная вкладка' : 'Новая вкладка',
    padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
    builder: (sheetCtx) {
      final pal = TheavSurfaceStyle.of(sheetCtx).palette;
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isIncognito)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'История, cookie и пароли в частном доступе не сохраняются.',
                  style: TextStyle(fontSize: 12.5, color: pal.subtext),
                ),
              ),
            TextField(
              key: const ValueKey('browser_new_tab_url_input'),
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(
                hintText: 'Введите адрес или поисковый запрос',
                prefixIcon: Icon(
                  isIncognito ? Icons.visibility_off_rounded : Icons.search_rounded,
                  size: 19,
                ),
                filled: true,
                fillColor: pal.onSurface.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (v) => Navigator.of(sheetCtx).pop(v.trim()),
            ),
            if (bookmarks.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final bm in bookmarks)
                    ActionChip(
                      label: Text(
                        bm.title.isNotEmpty
                            ? bm.title
                            : BrowserDataService.extractHost(bm.url),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => Navigator.of(sheetCtx).pop(bm.url),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 44,
              child: Material(
                color: pal.primary,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  key: const ValueKey('browser_new_tab_go_btn'),
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => Navigator.of(sheetCtx).pop(ctrl.text.trim()),
                  child: Center(
                    child: Text(
                      'Открыть',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: pal.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  ctrl.dispose();

  if (!context.mounted || entered == null) return;
  final raw = entered.trim();
  if (raw.isEmpty) return;

  final String targetUrl;
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    targetUrl = raw;
  } else if (!raw.contains(' ') && raw.contains('.')) {
    targetUrl = 'https://$raw';
  } else {
    targetUrl = 'https://ya.ru/search/?text=${Uri.encodeQueryComponent(raw)}';
  }
  await openInAppBrowser(
    context,
    url: targetUrl,
    isIncognito: isIncognito,
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
  final ValueNotifier<double> _dragOffsetNotifier = ValueNotifier<double>(0.0);
  final TextEditingController _findCtrl = TextEditingController();

  BrowserContactProfile _contactProfile = const BrowserContactProfile();
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
    unawaited(BrowserVaultService.instance.ensureLoaded());
    unawaited(
      BrowserSiteSettingsService.instance.ensureLoaded().then((_) {
        if (!mounted || _session.isIncognito || _session.controller != null) {
          return;
        }
        final savedDesktop = BrowserSiteSettingsService.instance
            .preferenceForUrl(_session.currentUrl)
            ?.desktopMode;
        if (savedDesktop != null && savedDesktop != _session.isDesktopMode) {
          setState(() => _session.isDesktopMode = savedDesktop);
        }
      }),
    );
    unawaited(_reloadContactProfile());
    BrowserDataService.instance.addListener(_onBrowserDataChanged);
    BrowserVaultService.instance.addListener(_onVaultOrSettingsChanged);
    BrowserSiteSettingsService.instance.addListener(_onVaultOrSettingsChanged);
  }

  Future<void> _reloadContactProfile() async {
    final profile = await BrowserVaultService.instance.getContactProfile();
    if (!mounted) return;
    setState(() => _contactProfile = profile);
  }

  void _onVaultOrSettingsChanged() {
    unawaited(_reloadContactProfile());
    if (mounted) setState(() {});
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (!mounted || activeSafariWebAlertCount.value > 0) return false;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (_session.pendingCredentialPrompt != null) {
      setState(() => _session.pendingCredentialPrompt = null);
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
    BrowserVaultService.instance.removeListener(_onVaultOrSettingsChanged);
    BrowserSiteSettingsService.instance
        .removeListener(_onVaultOrSettingsChanged);
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
          initialPrivateMode: _session.isIncognito,
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
          onOpenNewBrowserTab: (isPrivate) {
            Navigator.of(routeCtx).maybePop();
            if (mounted) {
              unawaited(openNewBrowserTabPrompt(context, isIncognito: isPrivate));
            }
          },
        ),
      ),
    );
  }

  void _closeTab() {
    _closeMenu();
    _isSiteInfoOpen = false;
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
    if (!_session.isIncognito) {
      unawaited(
        BrowserSiteSettingsService.instance
            .setDesktopModeForUrl(_session.currentUrl, nextDesktop),
      );
    }
    final ctrl = _session.controller;
    if (ctrl != null && _hasPlatformWebView) {
      await ctrl.setUserAgent(
        nextDesktop ? MiniAppSession.desktopUserAgent : null,
      );
      await ctrl.reload();
    }
    if (mounted) {
      GlassToastService().show(
        context,
        nextDesktop ? 'Включена версия для ПК' : 'Включена мобильная версия',
      );
    }
  }

  Future<void> _handleAutofillSelectCredential(
    BrowserCredentialHint hint,
  ) async {
    final cred = await BrowserVaultService.instance.unlockAndReadCredential(
      context,
      hint.id,
      reason: 'Подтвердите личность для входа на ${hint.displayHost}',
      originScope: hint.origin,
    );
    if (!mounted || cred == null) return;
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
        candidate.isUpdate ? 'Пароль обновлён' : 'Пароль сохранён',
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
        'Пароли для ${candidate.displayHost} не будут сохраняться',
        icon: Icons.block_rounded,
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

    final List<BrowserCredentialHint> savedHintsForCurrent = _session.isIncognito
        ? const <BrowserCredentialHint>[]
        : BrowserVaultService.instance.getHintsForUrl(currentUrl);
    final Widget expandedMenuContent = Padding(
      key: const ValueKey('in_app_browser_overflow_menu'),
      padding: const EdgeInsets.symmetric(vertical: 6),
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
              icon: Icons.key_rounded,
              label: 'Пароли и автозаполнение',
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
              icon: Icons.visibility_off_outlined,
              label: 'Новая частная вкладка',
              fg: resolved.headerFg,
              onTap: () {
                _closeMenu();
                unawaited(openNewBrowserTabPrompt(context, isIncognito: true));
              },
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
      isIncognito: _session.isIncognito,
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
            'Разрешения сайта сброшены',
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
          if (_session.isIncognito) ...[
            Icon(
              Icons.visibility_off_rounded,
              size: 10.5,
              color: resolved.palette.primary,
            ),
            const SizedBox(width: 3),
          ],
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
      expandedMenuHeight: 10 * 34.0 + 12.0,
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_session.isIncognito) ...[
                      Container(
                        key: const ValueKey('in_app_browser_incognito_badge'),
                        margin: const EdgeInsets.only(right: 5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: resolved.palette.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Частный',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                            color: resolved.palette.primary,
                          ),
                        ),
                      ),
                    ],
                    Flexible(
                      child: Text(
                        host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.15,
                          color: resolved.headerFg.withValues(alpha: 0.68),
                        ),
                      ),
                    ),
                  ],
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
        if (!_session.isIncognito && _session.focusedAutofillField != null)
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
                  ),
                ),
                onFillContact: () => unawaited(_handleAutofillFillContact()),
                onDismiss: () {
                  setState(() => _session.focusedAutofillField = null);
                },
              ),
            ),
          ),
        if (!_session.isIncognito && _session.pendingCredentialPrompt != null)
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
              child: _BrowserScrollPocket(
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
              child: _BrowserScrollPocket(
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
            if (_session.pendingCredentialPrompt != null) {
              setState(() => _session.pendingCredentialPrompt = null);
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
        height: 34,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
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
