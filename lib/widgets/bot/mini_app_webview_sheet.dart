import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/bot_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/mini_app_js_bridge.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';

/// Launches a bot Mini App by signing `initData` via `/api/bots/:botId/webapp/launch`
/// and opening [MiniAppWebViewSheet] inside a dual-mode [TheavModalSheet].
Future<void> openMiniAppSheet(
  BuildContext context, {
  required String botId,
  String? botName,
  String? botUsername,
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
    customSheetBuilder: (sheetCtx) => MiniAppWebViewSheet(
      launchData: launch,
      botName: effectiveBotName,
      botUsername: effectiveBotUser,
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

/// Full Telegram-parity Mini App container with `WebViewWidget` (when a platform
/// WebView implementation is active), `Telegram.WebApp` JS bridge, dynamic
/// `HeaderBar`/`BackButton`/`SettingsButton`/`MainButton`/`SecondaryButton`, and
/// handle-only stretch/dismiss physics (no bouncy spring).
class MiniAppWebViewSheet extends StatefulWidget {
  final MiniAppLaunchData launchData;
  final String botName;
  final String botUsername;
  final String? chatId;
  final String mode;
  final String buttonText;
  final ValueChanged<String>? onSwitchInlineQuery;

  const MiniAppWebViewSheet({
    super.key,
    required this.launchData,
    this.botName = '',
    this.botUsername = '',
    this.chatId,
    this.mode = 'menu',
    this.buttonText = '',
    this.onSwitchInlineQuery,
  });

  @override
  State<MiniAppWebViewSheet> createState() => _MiniAppWebViewSheetState();
}

class _MiniAppWebViewSheetState extends State<MiniAppWebViewSheet> {
  WebViewController? _controller;
  double _loadProgress = 0.0;
  bool _isExpanded = false;
  double _dragAccumulated = 0.0;

  bool _backButtonVisible = false;
  bool _settingsButtonVisible = false;
  bool _closingConfirmation = false;
  Color? _customHeaderColor;
  Color? _customBackgroundColor;

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
    if (_hasPlatformWebView) {
      _initWebView();
    }
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
              setState(() => _loadProgress = 1.0);
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
      )
      ..loadRequest(uri);
    _controller = ctrl;
  }

  Future<void> _injectBridge() async {
    final ctrl = _controller;
    if (ctrl == null || !mounted) return;
    final theme = Theme.of(context);
    final themeParams = MiniAppJsBridge.buildThemeParams(theme);
    final screenH = MediaQuery.sizeOf(context).height;
    final vpHeight = screenH * (_isExpanded ? 0.86 : 0.72);
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
              message:
                  'Mini App запрашивает ваш номер телефона.',
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
    final h = MediaQuery.sizeOf(context).height * (_isExpanded ? 0.86 : 0.72);
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

  void _handleHandleDragUpdate(DragUpdateDetails details) {
    _dragAccumulated += details.delta.dy;
  }

  void _handleHandleDragEnd(DragEndDetails details) {
    final dy = _dragAccumulated;
    final vy = details.primaryVelocity ?? 0.0;
    _dragAccumulated = 0.0;
    if (dy < -36 || vy < -320) {
      if (!_isExpanded) {
        setState(() => _isExpanded = true);
        _notifyViewportChanged();
      }
      return;
    }
    if (dy > 90 || vy > 620) {
      if (_isExpanded && dy < 160 && vy < 900) {
        setState(() => _isExpanded = false);
        _notifyViewportChanged();
      } else {
        _attemptClose();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final media = MediaQuery.of(context);
    final heightFactor = _isExpanded ? 0.96 : 0.82;
    final sheetHeight = media.size.height * heightFactor;

    final Color? explicitHeaderColor = _customHeaderColor;
    final headerBg = explicitHeaderColor ??
        (style.isGlass ? Colors.transparent : style.overlayFill);
    final bodyBg = _customBackgroundColor ?? theme.colorScheme.surface;
    final headerFg = explicitHeaderColor != null
        ? (explicitHeaderColor.computeLuminance() > 0.55
            ? Colors.black87
            : Colors.white)
        : palette.onSurface;

    final displayTitle = widget.botName.isNotEmpty
        ? widget.botName
        : (widget.launchData.botDisplayName.isNotEmpty
            ? widget.launchData.botDisplayName
            : 'Mini App');
    final displayHandle = widget.botUsername.isNotEmpty
        ? '@${widget.botUsername}'
        : (widget.launchData.botUsername.isNotEmpty
            ? '@${widget.launchData.botUsername}'
            : '');

    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: sheetHeight,
        width: double.infinity,
        child: TheavSheetSurface(
          cornerRadius: 22.0,
          constraints: BoxConstraints(
            minHeight: sheetHeight,
            maxHeight: sheetHeight,
          ),
          matteColor: bodyBg,
          child: Column(
            children: [
              // Drag handle + Header Bar (handle-only expand/dismiss)
              Container(
                color: headerBg,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: _handleHandleDragUpdate,
                      onVerticalDragEnd: _handleHandleDragEnd,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.only(top: 10, bottom: 4),
                        alignment: Alignment.center,
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: headerFg.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: _backButtonVisible ? 'Назад' : 'Закрыть',
                            onPressed: _backButtonVisible
                                ? () => _dispatchEventToWebView(
                                    'back_button_pressed')
                                : () => _attemptClose(),
                            icon: _backButtonVisible
                                ? iconoir.NavArrowLeft(
                                    width: 22,
                                    height: 22,
                                    color: headerFg,
                                  )
                                : iconoir.Xmark(
                                    width: 20,
                                    height: 20,
                                    color: headerFg,
                                  ),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: headerFg,
                                  ),
                                ),
                                if (displayHandle.isNotEmpty)
                                  Text(
                                    '$displayHandle • mini app',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: headerFg.withValues(alpha: 0.72),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: iconoir.MoreVert(
                              width: 20,
                              height: 20,
                              color: headerFg,
                            ),
                            onSelected: (action) async {
                              switch (action) {
                                case 'reload':
                                  await _controller?.reload();
                                  break;
                                case 'settings':
                                  await _dispatchEventToWebView(
                                    'settings_button_pressed',
                                  );
                                  break;
                                case 'browser':
                                  final u = Uri.tryParse(widget.launchData.url);
                                  if (u != null) {
                                    await launchUrl(
                                      u,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                  break;
                                case 'copy':
                                  await Clipboard.setData(
                                    ClipboardData(text: widget.launchData.url),
                                  );
                                  if (context.mounted) {
                                    GlassToastService().show(
                                      context,
                                      'Ссылка скопирована',
                                    );
                                  }
                                  break;
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'reload',
                                child: Text('Обновить страницу'),
                              ),
                              if (_settingsButtonVisible)
                                const PopupMenuItem(
                                  value: 'settings',
                                  child: Text('Настройки приложения'),
                                ),
                              const PopupMenuItem(
                                value: 'browser',
                                child: Text('Открыть в браузере'),
                              ),
                              const PopupMenuItem(
                                value: 'copy',
                                child: Text('Скопировать ссылку'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_hasPlatformWebView &&
                        _loadProgress > 0 &&
                        _loadProgress < 1.0)
                      LinearProgressIndicator(
                        value: _loadProgress,
                        minHeight: 2,
                        color: palette.primary,
                        backgroundColor: Colors.transparent,
                      ),
                  ],
                ),
              ),

              // WebView Body or Desktop/Test Fallback Card
              Expanded(
                child: ColoredBox(
                  color: _customBackgroundColor ??
                      (style.isGlass ? Colors.transparent : bodyBg),
                  child: _hasPlatformWebView && _controller != null
                      ? ColoredBox(
                          color: bodyBg,
                          child: WebViewWidget(controller: _controller!),
                        )
                      : _buildDesktopOrTestFallback(
                          context,
                          displayTitle,
                          palette,
                        ),
                ),
              ),

              // Native MainButton & SecondaryButton Bar
              if (_mainButton.isVisible || _secondaryButton.isVisible)
                Container(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    10,
                    14,
                    10 + media.padding.bottom,
                  ),
                  decoration: BoxDecoration(
                    color: headerBg,
                    border: Border(
                      top: BorderSide(color: style.hairlineBorder, width: 0.6),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (_secondaryButton.isVisible)
                        Expanded(
                          child: _buildActionButton(
                            _secondaryButton,
                            palette.primary.withValues(alpha: 0.14),
                            palette.primary,
                            () => _dispatchEventToWebView(
                              'secondary_button_pressed',
                            ),
                          ),
                        ),
                      if (_secondaryButton.isVisible && _mainButton.isVisible)
                        const SizedBox(width: 10),
                      if (_mainButton.isVisible)
                        Expanded(
                          child: _buildActionButton(
                            _mainButton,
                            palette.primary,
                            theme.colorScheme.onPrimary,
                            () => _dispatchEventToWebView(
                              'main_button_pressed',
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              else if (media.padding.bottom > 0)
                SizedBox(height: media.padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    _ButtonState state,
    Color defaultBg,
    Color defaultFg,
    VoidCallback onPressed,
  ) {
    final bg = state.color ?? defaultBg;
    final fg = state.textColor ?? defaultFg;
    return SizedBox(
      height: 46,
      child: FilledButton(
        onPressed: (state.isActive && !state.isProgressVisible)
            ? () {
                HapticUtils.tap();
                onPressed();
              }
            : null,
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
    BuildContext context,
    String title,
    TheavPalette palette,
  ) {
    final uri = Uri.tryParse(widget.launchData.url);
    final host = uri?.host ?? widget.launchData.url;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHigh
                  .withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: palette.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: iconoir.AppWindow(
                    width: 26,
                    height: 26,
                    color: palette.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  host,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.subtext,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Подпись Telegram.WebApp initData сформирована. Встроенный WebView недоступен на текущей платформе — откройте Mini App во внешнем браузере.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.subtext,
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
                    icon: const iconoir.OpenNewWindow(
                      width: 17,
                      height: 17,
                      color: Colors.white,
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
