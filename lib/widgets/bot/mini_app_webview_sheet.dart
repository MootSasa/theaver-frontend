import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/bot_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/mini_app_js_bridge.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';

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
  final launch = await BotService.launchWebApp(
    botId: botId,
    url: url,
    appShortName: appShortName,
    chatId: chatId,
    mode: mode,
    startParam: startParam,
    themeParams: themeParams,
  );
  if (!context.mounted) return;
  if (launch == null || launch.url.isEmpty) {
    GlassToastService().show(context, 'Не удалось открыть Mini App');
    return;
  }

  final effectiveBotName = launch.botDisplayName.isNotEmpty
      ? launch.botDisplayName
      : (botName ?? '');
  final effectiveBotUser = launch.botUsername.isNotEmpty
      ? launch.botUsername
      : (botUsername ?? '');

  final session = MiniAppSession(
    launchData: launch,
    botName: effectiveBotName,
    botUsername: effectiveBotUser,
    isVerified: isVerified ?? launch.botIsVerified,
    chatId: chatId,
    mode: mode,
    buttonText: buttonText,
    onSwitchInlineQuery: onSwitchInlineQuery,
  );

  await showTheavModalSheet<void>(
    context: context,
    enableDrag: false,
    barrierDismissible: true,
    useRootNavigator: true,
    customSheetBuilder: (sheetCtx) => MiniAppWebViewSheet(
      launchData: launch,
      botName: effectiveBotName,
      botUsername: effectiveBotUser,
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

/// Persistent live Mini App state retained across full-screen <-> minimized dock
/// bar <-> tabs switcher transitions so the underlying `WebViewController` and JS session never reload.
class MiniAppSession {
  static int _nextSessionSeq = 0;

  final String id;
  final MiniAppLaunchData launchData;
  final String botName;
  final String botUsername;
  final bool isVerified;
  final String? chatId;
  final String mode;
  final String buttonText;
  final ValueChanged<String>? onSwitchInlineQuery;

  WebViewController? controller;
  double loadProgress = 0.0;
  bool isWebContentReady = false;
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

  VoidCallback? onSheetStateChanged;
  VoidCallback? onRequestBridgeInjection;
  ValueChanged<String>? onInboundBridgeMessage;

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
  }) : id = id ?? 'mini_app_${++_nextSessionSeq}';

  String get displayTitle => botName.isNotEmpty
      ? botName
      : (launchData.botDisplayName.isNotEmpty
          ? launchData.botDisplayName
          : 'Mini App');

  void ensureWebViewInitialized() {
    if (controller != null || WebViewPlatform.instance == null) return;
    final uri = Uri.tryParse(launchData.url);
    if (uri == null) return;

    final ctrl = WebViewController()
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
            loadProgress = p / 100.0;
            onSheetStateChanged?.call();
          },
          onPageStarted: (_) {
            onRequestBridgeInjection?.call();
          },
          onPageFinished: (_) {
            loadProgress = 1.0;
            isWebContentReady = true;
            onSheetStateChanged?.call();
            onRequestBridgeInjection?.call();
          },
          onNavigationRequest: (req) {
            final targetUri = Uri.tryParse(req.url);
            if (targetUri == null) return NavigationDecision.prevent;
            final sch = targetUri.scheme.toLowerCase();
            if (sch == 'http' || sch == 'https') {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      );
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
}

/// Coordinates multiple minimized [MiniAppSession] entries, the bottom stacked
/// capsule bar, and the 3D tabs switcher across navigation routes.
class MiniAppSessionController extends ChangeNotifier {
  MiniAppSessionController._();

  static final MiniAppSessionController instance = MiniAppSessionController._();

  final List<MiniAppSession> _minimizedSessions = <MiniAppSession>[];
  bool _isSwitcherOpen = false;
  int _activeFullScreenCount = 0;

  List<MiniAppSession> get minimizedSessions =>
      List<MiniAppSession>.unmodifiable(_minimizedSessions);

  int get minimizedCount => _minimizedSessions.length;

  MiniAppSession? get minimizedSession =>
      _minimizedSessions.isEmpty ? null : _minimizedSessions.last;

  bool get hasMinimizedSession => _minimizedSessions.isNotEmpty;

  bool get isSwitcherOpen =>
      _isSwitcherOpen && _minimizedSessions.isNotEmpty;

  int get activeFullScreenCount => _activeFullScreenCount;

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
    _activeFullScreenCount += 1;
    if (_minimizedSessions.isNotEmpty) {
      _notifySafely();
    }
  }

  void unregisterFullScreenOpen() {
    if (_activeFullScreenCount > 0) {
      _activeFullScreenCount -= 1;
    }
    if (_minimizedSessions.isNotEmpty) {
      _notifySafely();
    }
  }

  void minimize(MiniAppSession session, {NavigatorState? navigator}) {
    session.isMinimized = true;
    if (navigator != null) {
      session.lastNavigator = navigator;
    }
    _minimizedSessions.removeWhere(
      (s) =>
          identical(s, session) ||
          (session.launchData.botId.isNotEmpty &&
              s.launchData.botId == session.launchData.botId &&
              s.launchData.url == session.launchData.url),
    );
    _minimizedSessions.add(session);
    _isSwitcherOpen = false;
    session.dispatchEvent('deactivated');
    session.dispatchEvent('viewport_changed', const {
      'height': 0,
      'is_expanded': false,
      'is_state_stable': true,
    });
    notifyListeners();
  }

  void notifySessionUpdated() {
    notifyListeners();
  }

  void openSwitcher() {
    if (_minimizedSessions.isEmpty || _isSwitcherOpen) return;
    _isSwitcherOpen = true;
    notifyListeners();
  }

  void closeSwitcher() {
    if (!_isSwitcherOpen) return;
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
    notifyListeners();
    session.dispatchEvent('activated');

    await showTheavModalSheet<void>(
      context: restoreContext,
      enableDrag: false,
      barrierDismissible: true,
      useRootNavigator: true,
      customSheetBuilder: (_) => MiniAppWebViewSheet(
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
  }

  void closeSession(MiniAppSession session) {
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
    notifyListeners();
  }
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

  @override
  State<MinimizedMiniAppHost> createState() => _MinimizedMiniAppHostState();
}

class _MinimizedMiniAppHostState extends State<MinimizedMiniAppHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _curvedAnim;
  late final Animation<Offset> _slideAnim;
  List<MiniAppSession> _displayedSessions = const [];

  @override
  void initState() {
    super.initState();
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
  void dispose() {
    MiniAppSessionController.instance.removeListener(_onSessionChanged);
    _animController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final ctrl = MiniAppSessionController.instance;
    if (ctrl.shouldShowMinimizedBar) {
      setState(() {
        _displayedSessions = ctrl.minimizedSessions;
      });
      if (_animController.status != AnimationStatus.forward &&
          _animController.status != AnimationStatus.completed) {
        _animController.forward();
      }
    } else if (_displayedSessions.isNotEmpty) {
      if (_animController.status == AnimationStatus.dismissed) {
        setState(() => _displayedSessions = const []);
      } else if (_animController.status != AnimationStatus.reverse) {
        _animController.reverse().whenComplete(() {
          if (mounted && !MiniAppSessionController.instance.shouldShowMinimizedBar) {
            setState(() => _displayedSessions = const []);
          }
        });
      } else {
        setState(() {});
      }
    } else {
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
        final confirm = await showTheavDialog<bool>(
              context: dialogCtx,
              title: 'Закрыть Mini App?',
              message: 'Внесённые изменения могут не сохраниться.',
              actions: const [
                TheavDialogAction<bool>(label: 'Остаться', result: false),
                TheavDialogAction<bool>(
                  label: 'Закрыть',
                  result: true,
                  isDestructive: true,
                ),
              ],
            ) ??
            false;
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
        final confirm = await showTheavDialog<bool>(
              context: dialogCtx,
              title: 'Закрыть все Mini Apps?',
              message: 'Внесённые изменения могут не сохраниться.',
              actions: const [
                TheavDialogAction<bool>(label: 'Остаться', result: false),
                TheavDialogAction<bool>(
                  label: 'Закрыть все',
                  result: true,
                  isDestructive: true,
                ),
              ],
            ) ??
            false;
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
    final bool keyboardVisible = mq.viewInsets.bottom > 0;
    final double barBottomInset = math.max(6.0, mq.padding.bottom + 4.0);
    const double topPad = 6.0;

    return _MinimizedMiniAppHostScope(
      child: AnimatedBuilder(
        animation: _curvedAnim,
        builder: (context, _) {
          final double rawT = _curvedAnim.value.clamp(0.0, 1.0);
          final double effectiveT = keyboardVisible ? 0.0 : rawT;
          final double insetFactor = (1.0 - effectiveT).clamp(0.0, 1.0);

          final Widget adjustedChild = (!keyboardVisible && effectiveT > 0.001)
              ? MediaQuery(
                  data: mq.copyWith(
                    padding: mq.padding.copyWith(
                      bottom: mq.padding.bottom * insetFactor,
                    ),
                    viewPadding: mq.viewPadding.copyWith(
                      bottom: mq.viewPadding.bottom * insetFactor,
                    ),
                  ),
                  child: widget.child,
                )
              : widget.child;

          final Widget? dockRegion = (!keyboardVisible &&
                  _displayedSessions.isNotEmpty &&
                  effectiveT > 0.0)
              ? ClipRect(
                  clipBehavior: effectiveT < 0.999 ? Clip.hardEdge : Clip.none,
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: effectiveT,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: DecoratedBox(
                        key: const ValueKey('minimized_mini_app_dock_region'),
                        decoration: BoxDecoration(
                          color: resolved.bodyBg,
                          border: Border(
                            top: BorderSide(color: resolved.divider, width: 0.6),
                          ),
                        ),
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
                )
              : null;

          final Widget columnLayout = Column(
            children: [
              Expanded(child: adjustedChild),
              if (dockRegion != null) dockRegion,
            ],
          );

          if (switcherOpen) {
            return Stack(
              fit: StackFit.expand,
              children: [
                columnLayout,
                MiniAppTabsSwitcher(
                  key: const ValueKey('mini_app_tabs_switcher'),
                  sessions: ctrl.minimizedSessions,
                  onDismiss: ctrl.closeSwitcher,
                  onSelectSession: (s) => ctrl.restoreSession(
                    s,
                    fallbackNavigatorKey: widget.navigatorKey,
                  ),
                  onCloseSession: _handleCloseSession,
                  onCloseAll: _handleCloseAllSessions,
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
/// minimized Mini Apps with a top `Закрыть все вкладки` pill.
class MiniAppTabsSwitcher extends StatelessWidget {
  final List<MiniAppSession> sessions;
  final VoidCallback onDismiss;
  final ValueChanged<MiniAppSession> onSelectSession;
  final ValueChanged<MiniAppSession> onCloseSession;
  final VoidCallback onCloseAll;

  const MiniAppTabsSwitcher({
    super.key,
    required this.sessions,
    required this.onDismiss,
    required this.onSelectSession,
    required this.onCloseSession,
    required this.onCloseAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = MiniAppJsBridge.resolveThemeColors(theme);
    final style = TheavSurfaceStyle.of(context);
    final mq = MediaQuery.of(context);
    final blurFilter = style.getBlurFilter(sigma: 16.0);

    final Color dimTint =
        resolved.bodyBg.withValues(alpha: style.isDark ? 0.74 : 0.64);
    Widget backdrop = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: ColoredBox(color: dimTint),
    );
    if (blurFilter != null) {
      backdrop = ClipRect(
        child: BackdropFilter(
          filter: blurFilter,
          child: backdrop,
        ),
      );
    }

    final Widget closeAllChild = Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const ValueKey('mini_app_close_all_tabs_button'),
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          HapticUtils.tap();
          onCloseAll();
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

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: backdrop),
        Positioned(
          top: mq.padding.top + 18,
          left: 0,
          right: 0,
          child: Center(
            child: SizedBox(height: 36, child: closeAllPill),
          ),
        ),
        Positioned(
          top: mq.padding.top + 72,
          left: 0,
          right: 0,
          bottom: 0,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double availH = constraints.maxHeight;
              final double cardHeight = (availH * 0.56).clamp(220.0, 390.0);
              final int n = sessions.length;
              final double stepY = n <= 1
                  ? 0.0
                  : ((availH - cardHeight - 28.0) / (n - 1))
                      .clamp(132.0, 220.0);
              final double stackHeight = cardHeight + (n - 1) * stepY;
              final double topPad =
                  ((availH - stackHeight) * 0.45).clamp(8.0, 64.0);

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  topPad,
                  16,
                  math.max(20.0, mq.padding.bottom + 12),
                ),
                child: SizedBox(
                  height: stackHeight,
                  width: double.infinity,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (int i = 0; i < n; i++)
                        _buildStackedCard(
                          context,
                          session: sessions[i],
                          top: i * stepY,
                          cardHeight: cardHeight,
                          resolved: resolved,
                          style: style,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStackedCard(
    BuildContext context, {
    required MiniAppSession session,
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
    final bool isVerified = session.isVerified ||
        session.launchData.botIsVerified ||
        unameLower == 'botmother' ||
        unameLower == 'botfather';

    final Matrix4 tiltMatrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0010)
      ..rotateX(0.14);

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      height: cardHeight,
      child: Dismissible(
        key: ValueKey('mini_app_tab_dismiss_${session.id}'),
        direction: DismissDirection.horizontal,
        onDismissed: (_) => onCloseSession(session),
        child: Transform(
          alignment: Alignment.topCenter,
          transform: tiltMatrix,
          child: GestureDetector(
            key: ValueKey('mini_app_tab_card_${session.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticUtils.selection();
              onSelectSession(session);
            },
            child: Container(
              decoration: BoxDecoration(
                color: cardBodyBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cardDivider, width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: style.isDark ? 0.45 : 0.16),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
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
                                key: ValueKey('mini_app_tab_close_${session.id}'),
                                borderRadius: BorderRadius.circular(24),
                                onTap: () {
                                  HapticUtils.tap();
                                  onCloseSession(session);
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
                    child: ColoredBox(color: cardBodyBg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniAppDragOffset extends SingleChildRenderObjectWidget {
  final double offsetY;

  const _MiniAppDragOffset({
    required this.offsetY,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMiniAppDragOffset(offsetY);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMiniAppDragOffset renderObject,
  ) {
    renderObject.offsetY = offsetY;
  }
}

class _RenderMiniAppDragOffset extends RenderShiftedBox {
  _RenderMiniAppDragOffset(this._offsetY) : super(null);

  double _offsetY;
  double get offsetY => _offsetY;
  set offsetY(double value) {
    if (_offsetY == value) return;
    _offsetY = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final RenderBox? child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(child.size);
    (child.parentData! as BoxParentData).offset = Offset(0.0, _offsetY);
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
  bool _isMenuOpen = false;
  bool _isMinimizing = false;
  bool _hasFullScreenRegistration = false;

  double _dragOffsetY = 0.0;
  double _dragResetFrom = 0.0;
  double _dragAccumulated = 0.0;
  late final AnimationController _dragResetController;
  late final AnimationController _menuAnimController;

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
        setState(() {
          _dragOffsetY = _dragResetFrom * (1.0 - t);
        });
      });
    _menuAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );

    _session.onSheetStateChanged = _onSessionStateChanged;
    _session.onRequestBridgeInjection = _injectBridge;
    _session.onInboundBridgeMessage = _handleBridgeMessage;
    _session.ensureWebViewInitialized();
    _hasFullScreenRegistration = true;
    MiniAppSessionController.instance.registerFullScreenOpen();
  }

  void _releaseFullScreenRegistration() {
    if (_hasFullScreenRegistration) {
      _hasFullScreenRegistration = false;
      MiniAppSessionController.instance.unregisterFullScreenOpen();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncThemeWithWebView();
  }

  @override
  void dispose() {
    _releaseFullScreenRegistration();
    if (identical(_session.onSheetStateChanged, _onSessionStateChanged)) {
      _session.onSheetStateChanged = null;
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
    _dragResetController.dispose();
    _menuAnimController.dispose();
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
              Navigator.of(context).maybePop();
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
          Navigator.of(context).maybePop();
          _session.onSwitchInlineQuery?.call(text);
        }
        break;

      case 'web_app_open_link':
      case 'web_app_open_tg_link':
        final url = (data['url'] ?? '').toString().trim();
        final uri = Uri.tryParse(url);
        if (uri != null &&
            (uri.scheme == 'http' || uri.scheme == 'https')) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
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
        final allowed = await showTheavDialog<bool>(
              context: context,
              title: 'Разрешить сообщения?',
              message:
                  'Бот @${_session.botUsername.isNotEmpty ? _session.botUsername : _session.launchData.botUsername} запрашивает разрешение отправлять вам сообщения.',
              actions: const [
                TheavDialogAction<bool>(label: 'Запретить', result: false),
                TheavDialogAction<bool>(
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
        final sent = await showTheavDialog<bool>(
              context: context,
              title: 'Поделиться контактом?',
              message: 'Mini App запрашивает ваш номер телефона.',
              actions: const [
                TheavDialogAction<bool>(label: 'Отмена', result: false),
                TheavDialogAction<bool>(
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
    final actions = <TheavDialogAction<String>>[];
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
          TheavDialogAction<String>(
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
        const TheavDialogAction<String>(
          label: 'ОК',
          result: 'ok',
          isPrimary: true,
        ),
      );
    }
    return showTheavDialog<String>(
      context: context,
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

  Future<void> _attemptClose({bool force = false}) async {
    if (!force && _session.closingConfirmation) {
      final confirm = await showTheavDialog<bool>(
            context: context,
            title: 'Закрыть Mini App?',
            message: 'Внесённые изменения могут не сохраниться.',
            actions: const [
              TheavDialogAction<bool>(label: 'Остаться', result: false),
              TheavDialogAction<bool>(
                label: 'Закрыть',
                result: true,
                isDestructive: true,
              ),
            ],
          ) ??
          false;
      if (!confirm || !mounted) return;
    }
    _isMinimizing = false;
    MiniAppSessionController.instance.closeMinimized(_session);
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  void _minimizeMiniApp() {
    HapticUtils.selection();
    _closeMenu();
    if (_MinimizedMiniAppHostScope.maybeOf(context)) {
      _isMinimizing = true;
      _releaseFullScreenRegistration();
      final nav = Navigator.of(context, rootNavigator: true);
      MiniAppSessionController.instance.minimize(_session, navigator: nav);
      nav.maybePop();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
    });
    if (_isMenuOpen) {
      _menuAnimController.forward(from: 0.0);
    }
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
    final double nextOffset = (_dragOffsetY + details.delta.dy).clamp(0.0, 260.0);
    if ((nextOffset - _dragOffsetY).abs() > 0.1) {
      setState(() {
        _isMenuOpen = false;
        _dragOffsetY = nextOffset;
      });
    }
  }

  void _resetDragOffset() {
    if (_dragOffsetY <= 0.5) {
      if (_dragOffsetY != 0.0) {
        setState(() => _dragOffsetY = 0.0);
      }
      return;
    }
    _dragResetFrom = _dragOffsetY;
    _dragResetController.forward(from: 0.0).whenComplete(() {
      if (mounted && _dragOffsetY != 0.0) {
        setState(() => _dragOffsetY = 0.0);
      }
    });
  }

  void _handleHeaderDragEnd(DragEndDetails details) {
    if (!_session.allowVerticalSwipe) return;
    final double dy = _dragAccumulated;
    final double vy = details.primaryVelocity ?? 0.0;
    _dragAccumulated = 0.0;

    if (dy >= 90 || vy >= 620) {
      _minimizeMiniApp();
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
    final Color headerDivider = _session.customHeaderColor != null
        ? headerFg.withValues(alpha: 0.12)
        : resolved.divider;
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
        unameLower == 'botfather';

    final Widget headerBlock = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: _handleHeaderDragStart,
      onVerticalDragUpdate: _handleHeaderDragUpdate,
      onVerticalDragEnd: _handleHeaderDragEnd,
      onVerticalDragCancel: _resetDragOffset,
      child: Container(
        decoration: BoxDecoration(
          color: headerBg,
          border: Border(
            bottom: BorderSide(
              color: headerDivider,
              width: 0.75,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: topInset),
          child: SizedBox(
            height: 54,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: IconButton(
                      key: const ValueKey('mini_app_close_or_back_button'),
                      tooltip:
                          _session.backButtonVisible ? 'Назад' : 'Закрыть',
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
                        size: 24,
                        color: headerFg,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 96),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.15,
                            color: headerFg,
                          ),
                        ),
                      ),
                      if (effectiveIsVerified) ...[
                        const SizedBox(width: 6),
                        MiniAppVerifiedSeal(
                          key: const ValueKey('mini_app_verified_seal'),
                          size: 19,
                          color: sealColor,
                          checkColor: sealCheckColor,
                        ),
                      ],
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 42,
                          height: 42,
                          child: IconButton(
                            key: const ValueKey(
                              'mini_app_collapse_expand_button',
                            ),
                            tooltip: 'Свернуть',
                            padding: EdgeInsets.zero,
                            onPressed: _minimizeMiniApp,
                            icon: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 26,
                              color: headerFg,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 42,
                          height: 42,
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
                              size: 23,
                              color: headerFg,
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
        ),
      ),
    );

    final Widget viewportBody = Expanded(
      child: ColoredBox(
        color: bodyBg,
        child: _hasPlatformWebView && _session.controller != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: ColoredBox(
                      color: bodyBg,
                      child: WebViewWidget(controller: _session.controller!),
                    ),
                  ),
                  if (!_session.isWebContentReady)
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
                  if (_session.loadProgress > 0 &&
                      _session.loadProgress < 1.0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: _session.loadProgress.clamp(0.06, 1.0),
                          child: SizedBox(
                            height: 2.5,
                            child: ColoredBox(
                              color: palette.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              )
            : _buildDesktopOrTestFallback(
                context,
                displayTitle: displayTitle,
                displayHandle: displayHandle,
                resolved: resolved,
              ),
      ),
    );

    final Color bottomBarBg = _session.customBottomBarColor ?? headerBg;
    final Color bottomDivider = _session.customBottomBarColor != null
        ? (bottomBarBg.computeLuminance() <= 0.55
            ? Colors.white12
            : Colors.black12)
        : resolved.divider;

    final Widget sheetBody = Material(
      color: bodyBg,
      child: Column(
        children: [
          headerBlock,
          viewportBody,
          if (_session.mainButton.isVisible ||
              _session.secondaryButton.isVisible)
            Container(
              padding: EdgeInsets.fromLTRB(
                14,
                10,
                14,
                10 + media.padding.bottom,
              ),
              decoration: BoxDecoration(
                color: bottomBarBg,
                border: Border(
                  top: BorderSide(
                    color: bottomDivider,
                    width: 0.6,
                  ),
                ),
              ),
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
            )
          else if (media.padding.bottom > 0)
            SizedBox(height: media.padding.bottom),
        ],
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isHeaderDark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
            ),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1.0,
        child: _MiniAppDragOffset(
          offsetY: _dragOffsetY,
          child: SizedBox(
            height: sheetHeight,
            width: double.infinity,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: sheetBody),
                if (_isMenuOpen) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _closeMenu,
                    ),
                  ),
                  _buildOverflowMenu(
                    context,
                    topOffset: topInset + 52.0,
                    style: style,
                    headerBg: headerBg,
                    headerFg: headerFg,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverflowMenu(
    BuildContext context, {
    required double topOffset,
    required TheavSurfaceStyle style,
    required Color headerBg,
    required Color headerFg,
  }) {
    final menuItemsColumn = Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
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

    final Widget surface = (style.isGlass && style.glassProvider != null)
        ? LiquidGlassLens(
            key: const ValueKey('mini_app_overflow_menu'),
            style: style.glassProvider!.createStyle(
              context: context,
              cornerRadius: 18,
              isLiteOverride: _hasPlatformWebView ? true : null,
              refractionIndex: 1.08,
              refractionWidth: 16.0,
              borderWidth: 1.1,
              color: headerBg.withValues(alpha: style.isDark ? 0.86 : 0.90),
            ),
            child: menuItemsColumn,
          )
        : DecoratedBox(
            key: const ValueKey('mini_app_overflow_menu'),
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: style.hairlineBorder,
                width: 0.6,
              ),
              boxShadow: style.floatingShadow,
            ),
            child: menuItemsColumn,
          );

    return Positioned(
      top: topOffset,
      right: 10,
      width: 236,
      child: ScaleTransition(
        alignment: Alignment.topRight,
        scale: CurvedAnimation(
          parent: _menuAnimController,
          curve: Curves.easeOutCubic,
        ).drive(Tween<double>(begin: 0.92, end: 1.0)),
        child: surface,
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
  }) {
    final uri = Uri.tryParse(_session.launchData.url);
    final host = uri?.host ?? _session.launchData.url;
    final palette = resolved.palette;
    final Color cardBg = resolved.surfaceBg;
    final Color titleColor = palette.onSurface;
    final Color subtitleColor = palette.subtext;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
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
