import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// Launches a bot Mini App by signing `initData` via `/api/bots/:botId/webapp/launch`
/// and opening [MiniAppWebViewSheet] full-screen over the root navigator.
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

  await showTheavModalSheet<void>(
    context: context,
    enableDrag: false,
    barrierDismissible: true,
    useRootNavigator: true,
    customSheetBuilder: (sheetCtx) => MiniAppWebViewSheet(
      launchData: launch,
      botName: effectiveBotName,
      botUsername: effectiveBotUser,
      isVerified: isVerified ?? launch.botIsVerified,
      chatId: chatId,
      mode: mode,
      buttonText: buttonText,
      onSwitchInlineQuery: onSwitchInlineQuery,
    ),
    builder: (_) => const SizedBox.shrink(),
  );
}

class _ButtonState {
  bool isVisible = false;
  bool isActive = true;
  bool isProgressVisible = false;
  String text = 'Продолжить';
  Color? color;
  Color? textColor;
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

/// Telegram-style Mini App container with opaque WebView viewport, status-bar-aware
/// full-screen / compact collapse transitions, centered title + verified seal,
/// 2x2 placeholder loader, and targeted Liquid Glass ONLY on the transient
/// overflow menu and optional secondary action button.
class MiniAppWebViewSheet extends StatefulWidget {
  final MiniAppLaunchData launchData;
  final String botName;
  final String botUsername;
  final bool isVerified;
  final bool initialExpanded;
  final String? chatId;
  final String mode;
  final String buttonText;
  final ValueChanged<String>? onSwitchInlineQuery;

  const MiniAppWebViewSheet({
    super.key,
    required this.launchData,
    this.botName = '',
    this.botUsername = '',
    this.isVerified = false,
    this.initialExpanded = true,
    this.chatId,
    this.mode = 'menu',
    this.buttonText = '',
    this.onSwitchInlineQuery,
  });

  @override
  State<MiniAppWebViewSheet> createState() => _MiniAppWebViewSheetState();
}

class _MiniAppWebViewSheetState extends State<MiniAppWebViewSheet>
    with TickerProviderStateMixin {
  WebViewController? _controller;
  double _loadProgress = 0.0;
  bool _isWebContentReady = false;
  late bool _isExpanded;
  bool _isMenuOpen = false;
  bool _allowVerticalSwipe = true;

  double _dragOffsetY = 0.0;
  double _dragResetFrom = 0.0;
  double _dragAccumulated = 0.0;
  late final AnimationController _dragResetController;
  late final AnimationController _menuAnimController;

  bool _backButtonVisible = false;
  bool _settingsButtonVisible = false;
  bool _closingConfirmation = false;
  Color? _customHeaderColor;
  Color? _customBackgroundColor;
  Color? _customBottomBarColor;
  Color? _lastSyncedWebViewBg;
  Map<String, String>? _lastThemeParams;

  final _ButtonState _mainButton = _ButtonState()..text = 'Continue';
  final _ButtonState _secondaryButton = _ButtonState()..text = 'Cancel';

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

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initialExpanded;
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
    if (_hasPlatformWebView) {
      _initWebView();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncThemeWithWebView();
  }

  @override
  void dispose() {
    _dragResetController.dispose();
    _menuAnimController.dispose();
    super.dispose();
  }

  void _syncWebViewBg() {
    final ctrl = _controller;
    if (ctrl == null || !mounted) return;
    final themeColors = MiniAppJsBridge.resolveThemeColors(Theme.of(context));
    final effectiveBg = _customBackgroundColor ?? themeColors.bodyBg;
    if (_lastSyncedWebViewBg != effectiveBg) {
      _lastSyncedWebViewBg = effectiveBg;
      try {
        ctrl.setBackgroundColor(effectiveBg);
      } catch (_) {}
    }
  }

  void _syncThemeWithWebView() {
    _syncWebViewBg();
    final ctrl = _controller;
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

  void _initWebView() {
    final uri = Uri.tryParse(widget.launchData.url);
    if (uri == null) return;

    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'TheaverWebAppBridge',
        onMessageReceived: (JavaScriptMessage msg) {
          _handleBridgeMessage(msg.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) {
              setState(() => _loadProgress = p / 100.0);
            }
          },
          onPageStarted: (_) {
            _injectBridge();
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() {
                _loadProgress = 1.0;
                _isWebContentReady = true;
              });
            }
            _injectBridge();
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
    _controller = ctrl;
  }

  Future<void> _injectBridge() async {
    final ctrl = _controller;
    if (ctrl == null || !mounted) return;
    final theme = Theme.of(context);
    final themeParams = MiniAppJsBridge.buildThemeParams(theme);
    final screenH = MediaQuery.sizeOf(context).height;
    final vpHeight = screenH * (_isExpanded ? 1.0 : 0.78);
    final js = MiniAppJsBridge.buildInjectionScript(
      widget.launchData,
      themeParams,
      colorScheme: theme.brightness == Brightness.dark ? 'dark' : 'light',
      viewportHeight: vpHeight,
      isExpanded: _isExpanded,
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
  ]) async {
    final ctrl = _controller;
    if (ctrl == null) return;
    final js =
        'if (window.__theaverWebAppReceive) { window.__theaverWebAppReceive(${jsonEncode(eventType)}, ${jsonEncode(eventData)}, ${jsonEncode(reqId ?? '')}); }';
    try {
      await ctrl.runJavaScript(js);
    } catch (_) {}
  }

  Future<void> _handleBridgeMessage(String raw) async {
    final evt = MiniAppJsBridge.parseBridgeMessage(raw);
    if (evt == null || !mounted) return;
    final data = evt.eventData;

    switch (evt.eventType) {
      case 'web_app_ready':
        if (!_isWebContentReady && mounted) {
          setState(() => _isWebContentReady = true);
        }
        break;

      case 'web_app_expand':
        if (!_isExpanded && mounted) {
          setState(() => _isExpanded = true);
          _notifyViewportChanged();
        }
        break;

      case 'web_app_close':
        await _attemptClose(force: true);
        break;

      case 'web_app_data_send':
        final payload = (data['data'] ?? '').toString();
        if (payload.isNotEmpty) {
          final res = await BotService.sendWebAppData(
            botId: widget.launchData.botId,
            data: payload,
            buttonText: widget.buttonText,
            chatId: widget.chatId,
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
        final uname = widget.botUsername.isNotEmpty
            ? widget.botUsername
            : widget.launchData.botUsername;
        final text = uname.isNotEmpty ? '@$uname $query' : query;
        if (mounted) {
          Navigator.of(context).maybePop();
          widget.onSwitchInlineQuery?.call(text);
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
          setState(() => _customHeaderColor = col);
        }
        break;

      case 'web_app_set_background_color':
        final col = _resolveSpecialColor(data);
        if (mounted) {
          setState(() => _customBackgroundColor = col);
          _syncWebViewBg();
        }
        break;

      case 'web_app_set_bottom_bar_color':
        final col = _resolveSpecialColor(data);
        if (mounted) {
          setState(() => _customBottomBarColor = col);
        }
        break;

      case 'web_app_setup_back_button':
        if (mounted) {
          setState(() => _backButtonVisible = data['is_visible'] == true);
        }
        break;

      case 'web_app_setup_settings_button':
        if (mounted) {
          setState(() => _settingsButtonVisible = data['is_visible'] == true);
        }
        break;

      case 'web_app_setup_closing_behavior':
        _closingConfirmation = data['need_confirmation'] == true;
        break;

      case 'web_app_setup_swipe_behavior':
        if (data.containsKey('allow_vertical_swipe')) {
          _allowVerticalSwipe = data['allow_vertical_swipe'] != false;
        }
        break;

      case 'web_app_setup_main_button':
        if (mounted) {
          setState(() => _applyButtonSetup(_mainButton, data));
        }
        break;

      case 'web_app_setup_secondary_button':
        if (mounted) {
          setState(() => _applyButtonSetup(_secondaryButton, data));
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
                  'Бот @${widget.botUsername.isNotEmpty ? widget.botUsername : widget.launchData.botUsername} запрашивает разрешение отправлять вам сообщения.',
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
            botId: widget.launchData.botId,
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
        final keys = await BotService.cloudStorageKeys(widget.launchData.botId);
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
        final items =
            await BotService.cloudStorageGet(widget.launchData.botId, rawKeys);
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
          widget.launchData.botId,
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
          widget.launchData.botId,
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

  void _applyButtonSetup(_ButtonState state, Map<String, dynamic> data) {
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
    final h = MediaQuery.sizeOf(context).height * (_isExpanded ? 1.0 : 0.78);
    _dispatchEventToWebView('viewport_changed', {
      'height': h.round(),
      'is_expanded': _isExpanded,
      'is_state_stable': true,
    });
  }

  Future<void> _attemptClose({bool force = false}) async {
    if (!force && _closingConfirmation) {
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
    if (mounted) {
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

  void _toggleExpandState() {
    HapticUtils.selection();
    setState(() {
      _isMenuOpen = false;
      _isExpanded = !_isExpanded;
      _dragOffsetY = 0.0;
    });
    _notifyViewportChanged();
  }

  void _handleHeaderDragStart(DragStartDetails _) {
    if (!_allowVerticalSwipe) return;
    _dragResetController.stop();
    _dragAccumulated = 0.0;
  }

  void _handleHeaderDragUpdate(DragUpdateDetails details) {
    if (!_allowVerticalSwipe) return;
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
    if (!_allowVerticalSwipe) return;
    final double dy = _dragAccumulated;
    final double vy = details.primaryVelocity ?? 0.0;
    _dragAccumulated = 0.0;

    if (!_isExpanded) {
      if (dy < -36 || vy < -320) {
        setState(() {
          _isExpanded = true;
          _dragOffsetY = 0.0;
        });
        _notifyViewportChanged();
        return;
      }
      if (dy > 90 || vy > 620) {
        _attemptClose();
        return;
      }
      _resetDragOffset();
      return;
    }

    if (dy >= 175 || vy >= 850) {
      _attemptClose();
      return;
    }
    if (dy > 70 && dy < 175 && vy < 850) {
      setState(() {
        _isExpanded = false;
        _dragOffsetY = 0.0;
      });
      _notifyViewportChanged();
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
    final double sheetHeight =
        media.size.height * (_isExpanded ? 1.0 : 0.78);
    final double topInset = _isExpanded ? media.padding.top : 0.0;
    final double topRadius = _isExpanded ? 0.0 : 18.0;

    final Color bodyBg = _customBackgroundColor ?? resolved.bodyBg;
    final Color bodyFg = _customBackgroundColor != null
        ? (_customBackgroundColor!.computeLuminance() <= 0.55
            ? Colors.white
            : Colors.black87)
        : palette.onSurface;
    final Color headerBg = _customHeaderColor ?? resolved.headerBg;
    final bool isHeaderDark = headerBg.computeLuminance() <= 0.55;
    final Color headerFg = _customHeaderColor != null
        ? (isHeaderDark ? Colors.white : Colors.black87)
        : resolved.headerFg;
    final Color headerDivider = _customHeaderColor != null
        ? headerFg.withValues(alpha: 0.12)
        : resolved.divider;
    final Color sealColor =
        _customHeaderColor != null ? headerFg.withValues(alpha: 0.85) : palette.primary;
    final Color sealCheckColor =
        (sealColor.computeLuminance() - headerBg.computeLuminance()).abs() > 0.18
            ? headerBg
            : palette.onPrimary;

    final String displayTitle = widget.botName.isNotEmpty
        ? widget.botName
        : (widget.launchData.botDisplayName.isNotEmpty
            ? widget.launchData.botDisplayName
            : 'Mini App');
    final String effectiveUsername = widget.botUsername.isNotEmpty
        ? widget.botUsername
        : widget.launchData.botUsername;
    final String unameLower = effectiveUsername.toLowerCase().trim();
    final String displayHandle =
        effectiveUsername.isNotEmpty ? '@$effectiveUsername' : '';
    final bool effectiveIsVerified = widget.isVerified ||
        widget.launchData.botIsVerified ||
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isExpanded)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 9, bottom: 4),
                  alignment: Alignment.center,
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: headerFg.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              SizedBox(
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
                          tooltip: _backButtonVisible ? 'Назад' : 'Закрыть',
                          onPressed: _backButtonVisible
                              ? () {
                                  _closeMenu();
                                  _dispatchEventToWebView(
                                    'back_button_pressed',
                                  );
                                }
                              : () => _attemptClose(),
                          icon: Icon(
                            _backButtonVisible
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
                                tooltip: _isExpanded ? 'Свернуть' : 'Развернуть',
                                padding: EdgeInsets.zero,
                                onPressed: _toggleExpandState,
                                icon: AnimatedRotation(
                                  turns: _isExpanded ? 0.0 : 0.5,
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOutCubic,
                                  child: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 26,
                                    color: headerFg,
                                  ),
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
            ],
          ),
        ),
      ),
    );

    final Widget viewportBody = Expanded(
      child: ColoredBox(
        color: bodyBg,
        child: _hasPlatformWebView && _controller != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: ColoredBox(
                      color: bodyBg,
                      child: WebViewWidget(controller: _controller!),
                    ),
                  ),
                  if (!_isWebContentReady)
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
                  if (_loadProgress > 0 && _loadProgress < 1.0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: _loadProgress.clamp(0.06, 1.0),
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

    final Color bottomBarBg = _customBottomBarColor ?? headerBg;
    final Color bottomDivider = _customBottomBarColor != null
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
          if (_mainButton.isVisible || _secondaryButton.isVisible)
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
                  if (_secondaryButton.isVisible)
                    Expanded(
                      child: _buildActionButton(
                        _secondaryButton,
                        defaultBg: palette.primary.withValues(alpha: 0.14),
                        defaultFg: palette.primary,
                        onPressed: () => _dispatchEventToWebView(
                          'secondary_button_pressed',
                        ),
                        style: style,
                        isSecondaryGlassCandidate: true,
                      ),
                    ),
                  if (_secondaryButton.isVisible && _mainButton.isVisible)
                    const SizedBox(width: 10),
                  if (_mainButton.isVisible)
                    Expanded(
                      child: _buildActionButton(
                        _mainButton,
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

    final Widget roundedSheetBody = topRadius > 0.0
        ? ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
            child: sheetBody,
          )
        : sheetBody;

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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: sheetHeight,
            width: double.infinity,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: roundedSheetBody),
                if (_isMenuOpen) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _closeMenu,
                    ),
                  ),
                  _buildOverflowMenu(
                    context,
                    topOffset: topInset + (_isExpanded ? 0.0 : 17.0) + 52.0,
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
                if (_controller != null) {
                  setState(() {
                    _isWebContentReady = false;
                    _loadProgress = 0.08;
                  });
                  await _controller!.reload();
                }
              },
            ),
            if (_settingsButtonVisible)
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
              icon: _isExpanded
                  ? iconoir.NavArrowDown(
                      width: 18,
                      height: 18,
                      color: headerFg,
                    )
                  : iconoir.NavArrowUp(
                      width: 18,
                      height: 18,
                      color: headerFg,
                    ),
              label: _isExpanded ? 'Компактный вид' : 'На весь экран',
              fgColor: headerFg,
              onTap: _toggleExpandState,
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
                  ClipboardData(text: widget.launchData.url),
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
                final u = Uri.tryParse(widget.launchData.url);
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
    _ButtonState state, {
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
    final uri = Uri.tryParse(widget.launchData.url);
    final host = uri?.host ?? widget.launchData.url;
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
