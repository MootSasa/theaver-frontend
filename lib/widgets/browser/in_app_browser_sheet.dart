import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/bot_service.dart';
import '../../services/browser_data_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/mini_app_js_bridge.dart';
import '../../utils/haptic_utils.dart';
import '../bot/mini_app_webview_sheet.dart';
import '../design_system/theav_design_system.dart';

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
  late final AnimationController _dragResetController;
  final ValueNotifier<double> _dragOffsetNotifier = ValueNotifier<double>(0.0);
  final TextEditingController _findCtrl = TextEditingController();

  bool _isMenuOpen = false;
  bool _isFindOpen = false;
  String _findStatus = '';
  double _dragResetFrom = 0.0;
  double _dragAccumulated = 0.0;
  bool _isMinimizing = false;
  bool _isTransitionReady = false;
  Animation<double>? _routeAnimation;
  bool? _lastRequestedRestingOpaque;

  bool get _hasPlatformWebView => !kIsWeb && WebViewPlatform.instance != null;

  void _onSessionStateChanged() {
    if (mounted) setState(() {});
  }

  void _setRouteRestingOpaque(bool opaque) {
    if (!mounted || _lastRequestedRestingOpaque == opaque) return;
    _lastRequestedRestingOpaque = opaque;
    TheavSheetRoutePerfControl.setRestingOpaque(context, opaque);
  }

  void _onRouteAnimationStatusChanged(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed) {
      _isTransitionReady = true;
      _maybeInitWebView();
      if (_dragOffsetNotifier.value <= 0.5 && !_isMinimizing) {
        _setRouteRestingOpaque(true);
      }
    } else if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      _setRouteRestingOpaque(false);
    }
  }

  void _maybeInitWebView({bool shouldRebuild = true}) {
    if (!mounted) return;
    if (_session.controller == null && _isTransitionReady && _hasPlatformWebView) {
      _session.ensureWebViewInitialized();
      if (_session.controller != null && shouldRebuild) {
        setState(() {});
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _session = widget.session;
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
    _session.onSheetStateChanged = _onSessionStateChanged;
    unawaited(BrowserDataService.instance.ensureLoaded());
    BrowserDataService.instance.addListener(_onBrowserDataChanged);
  }

  void _updateBrowserSafeClearances({EdgeInsets? paddingOverride}) {
    final size = MediaQuery.sizeOf(context);
    final padding = paddingOverride ?? MediaQuery.paddingOf(context);
    final double nextTop = padding.top + (_isFindOpen ? 116.0 : 64.0);
    final double nextBottom = padding.bottom + 72.0;
    final double nextVh = size.height;
    final bool clearanceChanged =
        (nextTop - _session.browserTopClearance).abs() > 0.5 ||
            (nextBottom - _session.browserBottomClearance).abs() > 0.5 ||
            (nextVh - _session.browserViewportHeight).abs() > 0.5;
    _session.browserTopClearance = nextTop;
    _session.browserBottomClearance = nextBottom;
    _session.browserViewportHeight = nextVh;
    if (clearanceChanged && _session.controller != null) {
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
        _isTransitionReady = true;
        _maybeInitWebView(shouldRebuild: false);
        if (_dragOffsetNotifier.value <= 0.5 && !_isMinimizing) {
          _setRouteRestingOpaque(true);
        }
      } else {
        if (!_hasPlatformWebView) {
          _isTransitionReady = true;
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
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatusChanged);
    _routeAnimation = null;
    BrowserDataService.instance.removeListener(_onBrowserDataChanged);
    if (identical(_session.onSheetStateChanged, _onSessionStateChanged)) {
      _session.onSheetStateChanged = null;
    }
    _dragOffsetNotifier.dispose();
    _dragResetController.dispose();
    _findCtrl.dispose();
    MiniAppSessionController.instance.unregisterFullScreenOpen();
    super.dispose();
  }

  Future<void> _minimizeToDock() async {
    if (_isMinimizing) return;
    _isMinimizing = true;
    _closeMenu();
    await _session.capturePreviewSnapshot().timeout(
          const Duration(milliseconds: 90),
          onTimeout: () {},
        );
    if (!mounted) return;
    _setRouteRestingOpaque(false);
    HapticUtils.selection();
    final nav = Navigator.of(context, rootNavigator: true);
    MiniAppSessionController.instance.minimize(_session, navigator: nav);
    nav.pop();
  }

  Future<void> _openTabsSwitcherFromHeader() async {
    if (_isMinimizing) return;
    HapticUtils.selection();
    _closeMenu();
    await _session.capturePreviewSnapshot().timeout(
          const Duration(milliseconds: 90),
          onTimeout: () {},
        );
    if (!mounted) return;
    if (MinimizedMiniAppHost.isMountedIn(context)) {
      _isMinimizing = true;
      _setRouteRestingOpaque(false);
      final nav = Navigator.of(context, rootNavigator: true);
      MiniAppSessionController.instance.minimizeAndOpenSwitcher(
        _session,
        navigator: nav,
      );
      nav.pop();
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
    _setRouteRestingOpaque(false);
    HapticUtils.tap();
    MiniAppSessionController.instance.closeSession(_session);
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  void _toggleMenu() {
    HapticUtils.tap();
    setState(() => _isMenuOpen = !_isMenuOpen);
  }

  void _closeMenu() {
    if (_isMenuOpen) {
      setState(() => _isMenuOpen = false);
    }
  }

  Future<void> _goBack() async {
    final ctrl = _session.controller;
    if (ctrl == null || !_hasPlatformWebView) return;
    if (await ctrl.canGoBack()) {
      HapticUtils.tap();
      await ctrl.goBack();
      await _session.refreshBrowserNavState();
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
    HapticUtils.tap();
    await BrowserDataService.instance.ensureLoaded();
    if (!mounted) return;

    await showTheavModalSheet<void>(
      context: context,
      useRootNavigator: true,
      title: 'Закладки и история',
      showCloseButton: true,
      builder: (sheetCtx) => DefaultTabController(
        length: 2,
        child: SizedBox(
          height: math.min(MediaQuery.of(sheetCtx).size.height * 0.56, 420),
          child: Column(
            children: [
              TabBar(
                labelColor: sheetCtx.theav.primary,
                unselectedLabelColor: sheetCtx.theav.subtext,
                indicatorColor: sheetCtx.theav.primary,
                tabs: const [
                  Tab(text: 'Закладки'),
                  Tab(text: 'История'),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedBuilder(
                  animation: BrowserDataService.instance,
                  builder: (_, __) {
                    final bm = BrowserDataService.instance.bookmarks;
                    final hist = BrowserDataService.instance.history;
                    return TabBarView(
                      children: [
                        bm.isEmpty
                            ? Center(
                                child: Text(
                                  'Нет сохранённых закладок',
                                  style: TextStyle(color: sheetCtx.theav.subtext),
                                ),
                              )
                            : ListView.builder(
                                itemCount: bm.length,
                                itemBuilder: (_, i) {
                                  final item = bm[i];
                                  return ListTile(
                                    leading: const Icon(Icons.bookmark_rounded),
                                    title: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      item.url,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () => BrowserDataService.instance
                                          .removeBookmark(item.url),
                                    ),
                                    onTap: () {
                                      Navigator.of(sheetCtx).pop();
                                      _navigateToUrl(item.url);
                                    },
                                  );
                                },
                              ),
                        hist.isEmpty
                            ? Center(
                                child: Text(
                                  'История браузера пуста',
                                  style: TextStyle(color: sheetCtx.theav.subtext),
                                ),
                              )
                            : ListView.builder(
                                itemCount: hist.length,
                                itemBuilder: (_, i) {
                                  final item = hist[i];
                                  return ListTile(
                                    leading: const Icon(Icons.history_rounded),
                                    title: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      item.url,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () => BrowserDataService.instance
                                          .deleteHistoryAt(i),
                                    ),
                                    onTap: () {
                                      Navigator.of(sheetCtx).pop();
                                      _navigateToUrl(item.url);
                                    },
                                  );
                                },
                              ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    setState(() {
      _session.currentUrl = rawUrl;
      _session.pageTitle = '';
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
      _minimizeToDock();
      return;
    }
    _resetDragOffset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = MiniAppJsBridge.resolveThemeColors(theme);
    final mq = MediaQuery.of(context);
    final topInset = mq.padding.top;
    final bottomInset = mq.padding.bottom;

    final String currentUrl = _session.currentUrl;
    final bool isHttps = currentUrl.toLowerCase().startsWith('https://');
    final String host = BrowserDataService.extractHost(currentUrl);
    final String title = _session.displayTitle;
    final bool bookmarked = BrowserDataService.instance.isBookmarked(currentUrl);

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
      isMenuOpen: _isMenuOpen,
      onDismissMenu: _closeMenu,
      expandedMenuWidth: 260.0,
      expandedMenuHeight: 7 * 44.0 + 12.0,
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
      centerChild: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
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
              Icon(
                isHttps ? Icons.lock_rounded : Icons.warning_amber_rounded,
                size: 11,
                color: isHttps
                    ? resolved.palette.primary
                    : resolved.palette.error,
              ),
              const SizedBox(width: 4),
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

    final Widget webBody = _hasPlatformWebView
        ? Stack(
            fit: StackFit.expand,
            children: [
              if (_session.controller != null)
                RepaintBoundary(
                  child: ColoredBox(
                    color: resolved.bodyBg,
                    child: WebViewWidget(controller: _session.controller!),
                  ),
                )
              else
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
                topInset + 76,
                24,
                bottomInset + 84,
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

    final Widget floatingBottomBar = Positioned(
      left: 16,
      right: 16,
      bottom: bottomInset + 10,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: WebViewFloatingCapsule(
            key: const ValueKey('in_app_browser_bottom_bar'),
            height: 48,
            borderRadius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
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
                    color:
                        bookmarked ? resolved.palette.primary : resolved.headerFg,
                  ),
                  onPressed: _openBookmarksAndHistorySheet,
                ),
                ValueListenableBuilder<double>(
                  valueListenable: _session.loadProgressNotifier,
                  builder: (context, progress, _) {
                    final bool isLoading = progress > 0.0 && progress < 1.0;
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

    final Widget sheetBody = Material(
      key: const ValueKey('in_app_browser_sheet'),
      color: resolved.bodyBg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: webBody),
          if (floatingFindBar != null)
            Positioned(
              top: topInset + 60.0,
              left: 0,
              right: 0,
              child: floatingFindBar,
            ),
          floatingBottomBar,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: floatingHeader,
          ),
        ],
      ),
    );

    return BackdropGroup(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (_isMenuOpen) {
            _closeMenu();
            return;
          }
          if (_hasPlatformWebView && _session.canGoBack) {
            await _goBack();
            return;
          }
          _setRouteRestingOpaque(false);
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }
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
