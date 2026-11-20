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
    with SingleTickerProviderStateMixin {
  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  late final MiniAppSession _session;
  late final AnimationController _menuAnimController;
  final TextEditingController _findCtrl = TextEditingController();

  bool _isMenuOpen = false;
  bool _isFindOpen = false;
  String _findStatus = '';
  double _dragOffsetY = 0.0;
  bool _isMinimizing = false;

  bool get _hasPlatformWebView => !kIsWeb && WebViewPlatform.instance != null;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    MiniAppSessionController.instance.registerFullScreenOpen();
    _menuAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 170),
    );
    _session.onSheetStateChanged = () {
      if (mounted) setState(() {});
    };
    _session.ensureWebViewInitialized();
    unawaited(BrowserDataService.instance.ensureLoaded());
    BrowserDataService.instance.addListener(_onBrowserDataChanged);
  }

  void _onBrowserDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    BrowserDataService.instance.removeListener(_onBrowserDataChanged);
    _session.onSheetStateChanged = null;
    _menuAnimController.dispose();
    _findCtrl.dispose();
    MiniAppSessionController.instance.unregisterFullScreenOpen();
    super.dispose();
  }

  void _minimizeToDock() {
    if (_isMinimizing) return;
    _isMinimizing = true;
    _closeMenu();
    HapticUtils.selection();
    final nav = Navigator.of(context, rootNavigator: true);
    MiniAppSessionController.instance.minimize(_session, navigator: nav);
    nav.pop();
  }

  void _closeTab() {
    _closeMenu();
    HapticUtils.tap();
    MiniAppSessionController.instance.closeSession(_session);
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  void _toggleMenu() {
    HapticUtils.tap();
    if (_isMenuOpen) {
      _closeMenu();
    } else {
      setState(() => _isMenuOpen = true);
      _menuAnimController.forward(from: 0.0);
    }
  }

  void _closeMenu() {
    if (!_isMenuOpen) return;
    _menuAnimController.reverse().whenComplete(() {
      if (mounted) setState(() => _isMenuOpen = false);
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = MiniAppJsBridge.resolveThemeColors(theme);
    final style = TheavSurfaceStyle.of(context);
    final mq = MediaQuery.of(context);
    final topInset = mq.padding.top;
    final bottomInset = mq.padding.bottom;

    final String currentUrl = _session.currentUrl;
    final bool isHttps = currentUrl.toLowerCase().startsWith('https://');
    final String host = BrowserDataService.extractHost(currentUrl);
    final String title = _session.displayTitle;
    final bool isLoading =
        _session.loadProgress > 0.0 && _session.loadProgress < 1.0;
    final bool bookmarked = BrowserDataService.instance.isBookmarked(currentUrl);

    final Widget headerBar = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) {
        if (d.delta.dy > 0 || _dragOffsetY > 0) {
          setState(() {
            _dragOffsetY = (_dragOffsetY + d.delta.dy).clamp(0.0, 220.0);
          });
        }
      },
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0.0) > 450 || _dragOffsetY > 90) {
          _minimizeToDock();
        } else {
          setState(() => _dragOffsetY = 0.0);
        }
      },
      onVerticalDragCancel: () {
        if (mounted) setState(() => _dragOffsetY = 0.0);
      },
      child: Container(
        decoration: BoxDecoration(
          color: resolved.headerBg,
          border: Border(
            bottom: BorderSide(color: resolved.divider, width: 0.75),
          ),
        ),
        padding: EdgeInsets.only(top: topInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 54,
                    child: IconButton(
                      key: const ValueKey('in_app_browser_close_button'),
                      tooltip: 'Закрыть',
                      icon: Icon(Icons.close_rounded, color: resolved.headerFg),
                      onPressed: _closeTab,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _copyCurrentUrl,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: resolved.headerFg,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isHttps
                                    ? Icons.lock_rounded
                                    : Icons.warning_amber_rounded,
                                size: 12,
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
                                    fontSize: 12,
                                    color:
                                        resolved.headerFg.withValues(alpha: 0.65),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    height: 54,
                    child: IconButton(
                      key: const ValueKey('in_app_browser_minimize_button'),
                      tooltip: 'Свернуть',
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 26,
                        color: resolved.headerFg,
                      ),
                      onPressed: _minimizeToDock,
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    height: 54,
                    child: IconButton(
                      key: const ValueKey('in_app_browser_menu_button'),
                      tooltip: 'Меню',
                      icon: Icon(Icons.more_vert_rounded, color: resolved.headerFg),
                      onPressed: _toggleMenu,
                    ),
                  ),
                ],
              ),
            ),
            if (_isFindOpen)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 36,
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
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            filled: true,
                            fillColor: resolved.bodyBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (v) => _findInPage(v),
                        ),
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
                      icon: Icon(Icons.keyboard_arrow_up_rounded,
                          color: resolved.headerFg),
                      onPressed: () =>
                          _findInPage(_findCtrl.text, backwards: true),
                    ),
                    IconButton(
                      icon: Icon(Icons.keyboard_arrow_down_rounded,
                          color: resolved.headerFg),
                      onPressed: () => _findInPage(_findCtrl.text),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          size: 20, color: resolved.headerFg),
                      onPressed: () => setState(() {
                        _isFindOpen = false;
                        _findStatus = '';
                      }),
                    ),
                  ],
                ),
              ),
            if (isLoading)
              LinearProgressIndicator(
                minHeight: 2.2,
                value: _session.loadProgress,
                backgroundColor: Colors.transparent,
                valueColor:
                    AlwaysStoppedAnimation<Color>(resolved.palette.primary),
              ),
          ],
        ),
      ),
    );

    final Widget webBody = _hasPlatformWebView && _session.controller != null
        ? WebViewWidget(controller: _session.controller!)
        : Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
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

    final Widget bottomBar = Container(
      key: const ValueKey('in_app_browser_bottom_bar'),
      decoration: BoxDecoration(
        color: resolved.headerBg,
        border: Border(top: BorderSide(color: resolved.divider, width: 0.7)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              tooltip: 'Назад',
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
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
                size: 20,
                color: _session.canGoForward
                    ? resolved.headerFg
                    : resolved.headerFg.withValues(alpha: 0.35),
              ),
              onPressed: _session.canGoForward ? _goForward : null,
            ),
            IconButton(
              tooltip: 'Поделиться',
              icon: Icon(Icons.ios_share_rounded,
                  size: 21, color: resolved.headerFg),
              onPressed: _shareCurrentUrl,
            ),
            IconButton(
              tooltip: 'Закладки и история',
              icon: Icon(
                bookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmarks_outlined,
                size: 22,
                color: bookmarked ? resolved.palette.primary : resolved.headerFg,
              ),
              onPressed: _openBookmarksAndHistorySheet,
            ),
            IconButton(
              tooltip: isLoading ? 'Стоп' : 'Обновить',
              icon: Icon(
                isLoading ? Icons.close_rounded : Icons.refresh_rounded,
                size: 22,
                color: resolved.headerFg,
              ),
              onPressed: _reloadOrStop,
            ),
          ],
        ),
      ),
    );

    final Widget menuItemsColumn = Column(
      mainAxisSize: MainAxisSize.min,
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
    );

    final Widget menuCard = (style.isGlass && style.glassProvider != null)
        ? LiquidGlassLens(
            style: style.glassProvider!.createStyle(
              context: context,
              cornerRadius: 18,
              isLiteOverride: _hasPlatformWebView ? true : null,
              refractionIndex: 1.08,
              refractionWidth: 16.0,
              borderWidth: 1.1,
              color: resolved.headerBg
                  .withValues(alpha: style.isDark ? 0.88 : 0.92),
            ),
            child: menuItemsColumn,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: resolved.headerBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: style.hairlineBorder, width: 0.6),
              boxShadow: style.floatingShadow,
            ),
            child: menuItemsColumn,
          );

    return PopScope(
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
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      },
      child: Transform.translate(
        offset: Offset(0, _dragOffsetY),
        child: Material(
          key: const ValueKey('in_app_browser_sheet'),
          color: resolved.bodyBg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  headerBar,
                  Expanded(child: webBody),
                  bottomBar,
                ],
              ),
              if (_isMenuOpen) ...[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _closeMenu,
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  top: topInset + 58,
                  right: 10,
                  width: 256,
                  child: ScaleTransition(
                    alignment: Alignment.topRight,
                    scale: CurvedAnimation(
                      parent: _menuAnimController,
                      curve: Curves.easeOutCubic,
                    ).drive(Tween<double>(begin: 0.92, end: 1.0)),
                    child: menuCard,
                  ),
                ),
              ],
            ],
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
