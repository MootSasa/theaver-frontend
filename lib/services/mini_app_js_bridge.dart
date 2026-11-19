import 'dart:convert';
import 'package:flutter/material.dart';

import '../models/theav_theme.dart';
import 'bot_service.dart';

/// Parsed inbound message posted from `Telegram.WebApp` JS code to Flutter
/// via `TheaverWebAppBridge.postMessage(...)`.
class MiniAppBridgeEvent {
  final String eventType;
  final Map<String, dynamic> eventData;
  final String? reqId;

  const MiniAppBridgeEvent({
    required this.eventType,
    this.eventData = const {},
    this.reqId,
  });
}

/// Opaque theme colors resolved dynamically from the active app [ThemeData] / [TheavPalette]
/// for [MiniAppWebViewSheet] chrome, placeholder, and `Telegram.WebApp.themeParams`.
class MiniAppThemeColors {
  final TheavPalette palette;
  final Color bodyBg;
  final Color surfaceBg;
  final Color headerBg;
  final Color headerFg;
  final Color divider;

  const MiniAppThemeColors({
    required this.palette,
    required this.bodyBg,
    required this.surfaceBg,
    required this.headerBg,
    required this.headerFg,
    required this.divider,
  });
}

/// Builds the full `window.Telegram.WebApp` (Bot API v7.10) JS injection bridge,
/// builds CSS/JS `themeParams` from [ThemeData], and parses bridge callbacks.
class MiniAppJsBridge {
  static String colorToHex(Color color) {
    final argb = color.toARGB32();
    final rgb = argb & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  static Color? parseHexColor(String? raw) {
    if (raw == null) return null;
    final clean = raw.trim().replaceFirst('#', '');
    if (clean.length == 6) {
      final val = int.tryParse(clean, radix: 16);
      if (val != null) return Color(0xFF000000 | val);
    } else if (clean.length == 8) {
      final val = int.tryParse(clean, radix: 16);
      if (val != null) return Color(val);
    }
    return null;
  }

  static TheavPalette _extractPalette(ThemeData theme) {
    final ext = theme.extension<TheavThemeExtension>();
    if (ext != null) return ext.palette;
    final cs = theme.colorScheme;
    return TheavPalette(
      primary: cs.primary,
      onPrimary: cs.onPrimary,
      background: theme.scaffoldBackgroundColor,
      surface: cs.surface,
      onSurface: cs.onSurface,
      appBarBackground: theme.appBarTheme.backgroundColor ?? cs.surface,
      appBarForeground: theme.appBarTheme.foregroundColor ?? cs.onSurface,
      chatBubbleOutgoing: cs.primary,
      chatBubbleOutgoingText: cs.onPrimary,
      chatBubbleOutgoingSubtext: cs.onPrimary.withValues(alpha: 0.7),
      chatBubbleIncoming: cs.surface,
      chatBubbleIncomingText: cs.onSurface,
      chatBubbleIncomingSubtext: cs.onSurface.withValues(alpha: 0.6),
      chatDateBadge: cs.surface.withValues(alpha: 0.8),
      chatDateBadgeText: cs.onSurface,
      subtext: cs.onSurfaceVariant,
      divider: cs.outlineVariant,
      error: cs.error,
    );
  }

  /// Resolves opaque Mini App surface and header colors from the active app theme.
  static MiniAppThemeColors resolveThemeColors(ThemeData theme) {
    final palette = _extractPalette(theme);
    final Color bodyBg = palette.background.a > 0
        ? palette.background.withValues(alpha: 1.0)
        : theme.colorScheme.surface.withValues(alpha: 1.0);
    Color surfaceBg = palette.surface.a > 0
        ? Color.alphaBlend(palette.surface, bodyBg)
        : bodyBg;
    if (surfaceBg.toARGB32() == bodyBg.toARGB32()) {
      surfaceBg = Color.alphaBlend(
        palette.onSurface.withValues(alpha: 0.05),
        bodyBg,
      );
    }
    Color headerBg = palette.appBarBackground.a > 0
        ? Color.alphaBlend(palette.appBarBackground, bodyBg)
        : surfaceBg;
    if (headerBg.toARGB32() == bodyBg.toARGB32()) {
      headerBg = surfaceBg;
    }
    final Color headerFg = palette.appBarBackground.a > 0.5
        ? palette.appBarForeground
        : palette.onSurface;
    return MiniAppThemeColors(
      palette: palette,
      bodyBg: bodyBg,
      surfaceBg: surfaceBg,
      headerBg: headerBg,
      headerFg: headerFg,
      divider: palette.divider,
    );
  }

  /// Maps current [ThemeData] & [TheavThemeExtension] colors to opaque Telegram `ThemeParams`.
  static Map<String, String> buildThemeParams(ThemeData theme) {
    final c = resolveThemeColors(theme);
    final p = c.palette;

    return {
      'bg_color': colorToHex(c.bodyBg),
      'secondary_bg_color': colorToHex(c.surfaceBg),
      'text_color': colorToHex(p.onSurface),
      'hint_color': colorToHex(p.subtext),
      'link_color': colorToHex(p.primary),
      'button_color': colorToHex(p.primary),
      'button_text_color': colorToHex(p.onPrimary),
      'header_bg_color': colorToHex(c.headerBg),
      'bottom_bar_bg_color': colorToHex(c.headerBg),
      'accent_text_color': colorToHex(p.primary),
      'section_bg_color': colorToHex(c.surfaceBg),
      'section_header_text_color': colorToHex(p.primary),
      'section_separator_color': colorToHex(c.divider),
      'subtitle_text_color': colorToHex(p.subtext),
      'destructive_text_color': colorToHex(p.error),
    };
  }

  /// Parses JSON bridge payloads coming from JS `TheaverWebAppBridge.postMessage`.
  static MiniAppBridgeEvent? parseBridgeMessage(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final eventType =
          (map['eventType'] ?? map['event_type'] ?? '').toString().trim();
      if (eventType.isEmpty) return null;

      Map<String, dynamic> eventData = const {};
      final rawData = map['eventData'] ?? map['event_data'] ?? map['data'];
      if (rawData is Map) {
        eventData = Map<String, dynamic>.from(rawData);
      } else if (rawData is String && rawData.isNotEmpty) {
        try {
          final inner = jsonDecode(rawData);
          if (inner is Map) {
            eventData = Map<String, dynamic>.from(inner);
          } else {
            eventData = {'value': rawData};
          }
        } catch (_) {
          eventData = {'value': rawData};
        }
      } else if (rawData != null) {
        eventData = {'value': rawData};
      }

      final reqIdRaw = (map['reqId'] ?? map['req_id'])?.toString().trim();
      final reqId = (reqIdRaw == null || reqIdRaw.isEmpty) ? null : reqIdRaw;

      return MiniAppBridgeEvent(
        eventType: eventType,
        eventData: eventData,
        reqId: reqId,
      );
    } catch (_) {
      return null;
    }
  }

  /// Generates JS code injecting `window.TelegramWebviewProxy` and `window.Telegram.WebApp` v7.10.
  static String buildInjectionScript(
    MiniAppLaunchData launch,
    Map<String, String> themeParams, {
    required String colorScheme,
    required double viewportHeight,
    bool isExpanded = false,
    String platform = 'android',
  }) {
    final initDataJson = jsonEncode(launch.initData);
    final initDataUnsafeJson = jsonEncode(launch.initDataUnsafe);
    final themeJson = jsonEncode(themeParams);
    final colorSchemeJson = jsonEncode(colorScheme);
    final platformJson = jsonEncode(platform);
    final versionJson = jsonEncode(launch.version.isNotEmpty ? launch.version : '7.10');
    final headerBgJson = jsonEncode(themeParams['header_bg_color'] ?? '#ffffff');
    final bgJson = jsonEncode(themeParams['bg_color'] ?? '#ffffff');
    final btnColorJson = jsonEncode(themeParams['button_color'] ?? '#3390ec');
    final btnTextColorJson = jsonEncode(themeParams['button_text_color'] ?? '#ffffff');
    final vpHeight = viewportHeight.round();

    return '''
(function() {
  var _theme = $themeJson;
  if (!window.Telegram) window.Telegram = {};
  if (!window.TelegramWebviewProxy) window.TelegramWebviewProxy = {};

  var _listeners = window.__theaverWaListeners || {};
  var _pendingCallbacks = window.__theaverWaPending || {};
  var _reqCounter = window.__theaverWaReqSeq || 1;
  window.__theaverWaListeners = _listeners;
  window.__theaverWaPending = _pendingCallbacks;

  function _nextReqId() {
    _reqCounter += 1;
    window.__theaverWaReqSeq = _reqCounter;
    return 'req_' + _reqCounter + '_' + Date.now();
  }

  function _postToNative(eventType, eventData, reqId) {
    var payload = JSON.stringify({
      eventType: eventType,
      eventData: eventData || {},
      reqId: reqId || ''
    });
    if (window.TheaverWebAppBridge && typeof window.TheaverWebAppBridge.postMessage === 'function') {
      window.TheaverWebAppBridge.postMessage(payload);
    }
  }

  window.TelegramWebviewProxy.postEvent = function(eventType, eventData) {
    var parsed = eventData;
    if (typeof eventData === 'string') {
      try { parsed = JSON.parse(eventData); } catch (e) { parsed = { value: eventData }; }
    }
    _postToNative(eventType, parsed || {}, '');
  };

  function _emit(eventType, eventData) {
    var list = _listeners[eventType];
    if (!list || !list.length) return;
    for (var i = 0; i < list.length; i++) {
      try { list[i](eventData); } catch (e) {}
    }
  }

  function _applyThemeCssVars(tp, scheme, vpH, vpStableH) {
    try {
      if (typeof document === 'undefined' || !document.documentElement) return;
      var rootStyle = document.documentElement.style;
      if (scheme) rootStyle.setProperty('--tg-color-scheme', String(scheme));
      if (typeof vpH === 'number' && vpH > 0) {
        rootStyle.setProperty('--tg-viewport-height', Math.round(vpH) + 'px');
      }
      if (typeof vpStableH === 'number' && vpStableH > 0) {
        rootStyle.setProperty('--tg-viewport-stable-height', Math.round(vpStableH) + 'px');
      }
      if (tp && typeof tp === 'object') {
        var keys = Object.keys(tp);
        for (var i = 0; i < keys.length; i++) {
          var k = keys[i];
          if (tp[k] != null && tp[k] !== '') {
            var cssVar = '--tg-theme-' + String(k).replace(/_/g, '-');
            rootStyle.setProperty(cssVar, String(tp[k]));
          }
        }
      }
    } catch (e) {}
  }

  _applyThemeCssVars(_theme, $colorSchemeJson, $vpHeight, $vpHeight);

  window.__theaverWebAppReceive = function(eventType, eventData, reqId) {
    if (reqId && _pendingCallbacks[reqId]) {
      var pending = _pendingCallbacks[reqId];
      delete _pendingCallbacks[reqId];
      try { pending(eventData); } catch (e) {}
    }
    if (eventType === 'theme_changed' && eventData && eventData.theme_params) {
      webApp.themeParams = eventData.theme_params;
      if (eventData.color_scheme) webApp.colorScheme = eventData.color_scheme;
      _applyThemeCssVars(webApp.themeParams, webApp.colorScheme, webApp.viewportHeight, webApp.viewportStableHeight);
    } else if (eventType === 'viewport_changed' && eventData) {
      if (typeof eventData.height === 'number') webApp.viewportHeight = eventData.height;
      if (eventData.is_state_stable && typeof eventData.height === 'number') {
        webApp.viewportStableHeight = eventData.height;
      }
      if (typeof eventData.is_expanded === 'boolean') webApp.isExpanded = eventData.is_expanded;
      _applyThemeCssVars(webApp.themeParams, webApp.colorScheme, webApp.viewportHeight, webApp.viewportStableHeight);
    }
    _emit(eventType, eventData);
    var camelMap = {
      main_button_pressed: 'mainButtonClicked',
      secondary_button_pressed: 'secondaryButtonClicked',
      back_button_pressed: 'backButtonClicked',
      settings_button_pressed: 'settingsButtonClicked',
      theme_changed: 'themeChanged',
      viewport_changed: 'viewportChanged',
      popup_closed: 'popupClosed',
      clipboard_text_received: 'clipboardTextReceived',
      write_access_requested: 'writeAccessRequested',
      contact_requested: 'contactRequested'
    };
    if (camelMap[eventType]) {
      _emit(camelMap[eventType], eventData);
    }
  };

  function _sendButtonUpdate(which, btn) {
    _postToNative(which === 'secondary' ? 'web_app_setup_secondary_button' : 'web_app_setup_main_button', {
      is_visible: !!btn.isVisible,
      is_active: !!btn.isActive,
      is_progress_visible: !!btn.isProgressVisible,
      text: btn.text || '',
      color: btn.color || '',
      text_color: btn.textColor || '',
      has_shine_effect: !!btn.hasShineEffect,
      position: btn.position || 'left'
    }, '');
  }

  function _createActionButton(which, defaultText, defaultVisible) {
    var btn = {
      type: which === 'secondary' ? 'secondary' : 'main',
      text: defaultText,
      color: $btnColorJson,
      textColor: $btnTextColorJson,
      isVisible: !!defaultVisible,
      isActive: true,
      isProgressVisible: false,
      hasShineEffect: false,
      position: 'left',
      setText: function(t) { btn.text = String(t || ''); _sendButtonUpdate(which, btn); return btn; },
      show: function() { btn.isVisible = true; _sendButtonUpdate(which, btn); return btn; },
      hide: function() { btn.isVisible = false; _sendButtonUpdate(which, btn); return btn; },
      enable: function() { btn.isActive = true; _sendButtonUpdate(which, btn); return btn; },
      disable: function() { btn.isActive = false; _sendButtonUpdate(which, btn); return btn; },
      showProgress: function() { btn.isProgressVisible = true; _sendButtonUpdate(which, btn); return btn; },
      hideProgress: function() { btn.isProgressVisible = false; _sendButtonUpdate(which, btn); return btn; },
      setParams: function(p) {
        if (!p) return btn;
        if (p.text !== undefined) btn.text = String(p.text);
        if (p.color !== undefined) btn.color = String(p.color);
        if (p.text_color !== undefined) btn.textColor = String(p.text_color);
        if (p.is_active !== undefined) btn.isActive = !!p.is_active;
        if (p.is_visible !== undefined) btn.isVisible = !!p.is_visible;
        if (p.has_shine_effect !== undefined) btn.hasShineEffect = !!p.has_shine_effect;
        if (p.position !== undefined) btn.position = String(p.position);
        _sendButtonUpdate(which, btn);
        return btn;
      },
      onClick: function(cb) { webApp.onEvent(which === 'secondary' ? 'secondaryButtonClicked' : 'mainButtonClicked', cb); return btn; },
      offClick: function(cb) { webApp.offEvent(which === 'secondary' ? 'secondaryButtonClicked' : 'mainButtonClicked', cb); return btn; }
    };
    return btn;
  }

  var mainBtn = (window.Telegram.WebApp && window.Telegram.WebApp.MainButton) || _createActionButton('main', 'Continue', false);
  var secondaryBtn = (window.Telegram.WebApp && window.Telegram.WebApp.SecondaryButton) || _createActionButton('secondary', 'Cancel', false);

  var backBtn = (window.Telegram.WebApp && window.Telegram.WebApp.BackButton) || {
    isVisible: false,
    show: function() { backBtn.isVisible = true; _postToNative('web_app_setup_back_button', { is_visible: true }, ''); return backBtn; },
    hide: function() { backBtn.isVisible = false; _postToNative('web_app_setup_back_button', { is_visible: false }, ''); return backBtn; },
    onClick: function(cb) { webApp.onEvent('backButtonClicked', cb); return backBtn; },
    offClick: function(cb) { webApp.offEvent('backButtonClicked', cb); return backBtn; }
  };

  var settingsBtn = (window.Telegram.WebApp && window.Telegram.WebApp.SettingsButton) || {
    isVisible: false,
    show: function() { settingsBtn.isVisible = true; _postToNative('web_app_setup_settings_button', { is_visible: true }, ''); return settingsBtn; },
    hide: function() { settingsBtn.isVisible = false; _postToNative('web_app_setup_settings_button', { is_visible: false }, ''); return settingsBtn; },
    onClick: function(cb) { webApp.onEvent('settingsButtonClicked', cb); return settingsBtn; },
    offClick: function(cb) { webApp.offEvent('settingsButtonClicked', cb); return settingsBtn; }
  };

  function _invokeAsync(eventType, eventData, cb, mapResult) {
    var reqId = _nextReqId();
    return new Promise(function(resolve) {
      _pendingCallbacks[reqId] = function(res) {
        var mapped = mapResult ? mapResult(res) : res;
        if (typeof cb === 'function') {
          try {
            if (Array.isArray(mapped) && mapped.__spreadArgs) {
              cb.apply(null, mapped);
            } else {
              cb(mapped);
            }
          } catch (e) {}
        }
        resolve(Array.isArray(mapped) && mapped.__spreadArgs ? mapped[1] : mapped);
      };
      _postToNative(eventType, eventData, reqId);
    });
  }

  var webApp = {
    initData: $initDataJson,
    initDataUnsafe: $initDataUnsafeJson,
    version: $versionJson,
    platform: $platformJson,
    colorScheme: $colorSchemeJson,
    themeParams: _theme,
    isExpanded: ${isExpanded ? 'true' : 'false'},
    viewportHeight: $vpHeight,
    viewportStableHeight: $vpHeight,
    headerColor: $headerBgJson,
    backgroundColor: $bgJson,
    bottomBarColor: $headerBgJson,
    isClosingConfirmationEnabled: false,
    isVerticalSwipesEnabled: true,
    isActive: true,
    BackButton: backBtn,
    MainButton: mainBtn,
    SecondaryButton: secondaryBtn,
    SettingsButton: settingsBtn,
    HapticFeedback: {
      impactOccurred: function(style) { _postToNative('web_app_trigger_haptic_feedback', { type: 'impact', impact_style: style || 'medium' }, ''); return webApp.HapticFeedback; },
      notificationOccurred: function(type) { _postToNative('web_app_trigger_haptic_feedback', { type: 'notification', notification_type: type || 'success' }, ''); return webApp.HapticFeedback; },
      selectionChanged: function() { _postToNative('web_app_trigger_haptic_feedback', { type: 'selection_change' }, ''); return webApp.HapticFeedback; }
    },
    CloudStorage: {
      setItem: function(key, value, cb) {
        return _invokeAsync('cloud_storage_set', { key: String(key), value: String(value) }, cb, function(res) {
          var arr = [res && res.error ? res.error : null, !!(res && res.ok)];
          arr.__spreadArgs = true;
          return arr;
        });
      },
      getItem: function(key, cb) {
        return _invokeAsync('cloud_storage_get', { keys: [String(key)] }, cb, function(res) {
          var items = (res && res.items) || {};
          var arr = [res && res.error ? res.error : null, items[String(key)] !== undefined ? items[String(key)] : ''];
          arr.__spreadArgs = true;
          return arr;
        });
      },
      getItems: function(keys, cb) {
        var keyList = Array.isArray(keys) ? keys.map(String) : [];
        return _invokeAsync('cloud_storage_get', { keys: keyList }, cb, function(res) {
          var arr = [res && res.error ? res.error : null, (res && res.items) || {}];
          arr.__spreadArgs = true;
          return arr;
        });
      },
      removeItem: function(key, cb) {
        return _invokeAsync('cloud_storage_remove', { keys: [String(key)] }, cb, function(res) {
          var arr = [res && res.error ? res.error : null, !!(res && res.ok)];
          arr.__spreadArgs = true;
          return arr;
        });
      },
      removeItems: function(keys, cb) {
        var keyList = Array.isArray(keys) ? keys.map(String) : [];
        return _invokeAsync('cloud_storage_remove', { keys: keyList }, cb, function(res) {
          var arr = [res && res.error ? res.error : null, !!(res && res.ok)];
          arr.__spreadArgs = true;
          return arr;
        });
      },
      getKeys: function(cb) {
        return _invokeAsync('cloud_storage_keys', {}, cb, function(res) {
          var arr = [res && res.error ? res.error : null, (res && res.keys) || []];
          arr.__spreadArgs = true;
          return arr;
        });
      }
    },
    isVersionAtLeast: function(ver) {
      var a = String(webApp.version).split('.').map(Number);
      var b = String(ver || '0').split('.').map(Number);
      for (var i = 0; i < Math.max(a.length, b.length); i++) {
        var av = a[i] || 0, bv = b[i] || 0;
        if (av > bv) return true;
        if (av < bv) return false;
      }
      return true;
    },
    onEvent: function(eventType, cb) {
      if (typeof cb !== 'function') return;
      if (!_listeners[eventType]) _listeners[eventType] = [];
      if (_listeners[eventType].indexOf(cb) === -1) _listeners[eventType].push(cb);
    },
    offEvent: function(eventType, cb) {
      var list = _listeners[eventType];
      if (!list) return;
      var idx = list.indexOf(cb);
      if (idx !== -1) list.splice(idx, 1);
    },
    ready: function() { _postToNative('web_app_ready', {}, ''); },
    expand: function() { webApp.isExpanded = true; _postToNative('web_app_expand', {}, ''); },
    close: function() { _postToNative('web_app_close', {}, ''); },
    sendData: function(data) { _postToNative('web_app_data_send', { data: String(data || '') }, ''); },
    switchInlineQuery: function(query, chooseChatTypes) {
      _postToNative('web_app_switch_inline_query', { query: String(query || ''), chat_types: chooseChatTypes || [] }, '');
    },
    openLink: function(url, options) {
      _postToNative('web_app_open_link', { url: String(url || ''), try_instant_view: !!(options && options.try_instant_view) }, '');
    },
    openTelegramLink: function(url) {
      _postToNative('web_app_open_tg_link', { url: String(url || '') }, '');
    },
    showPopup: function(params, cb) {
      return _invokeAsync('web_app_open_popup', params || {}, cb, function(res) { return res ? res.button_id : null; });
    },
    showAlert: function(message, cb) {
      return _invokeAsync('web_app_open_popup', { message: String(message || ''), buttons: [{ id: 'ok', type: 'ok' }] }, function() {
        if (typeof cb === 'function') cb();
      });
    },
    showConfirm: function(message, cb) {
      return _invokeAsync('web_app_open_popup', { message: String(message || ''), buttons: [{ id: 'cancel', type: 'cancel' }, { id: 'ok', type: 'ok' }] }, cb, function(res) {
        return !!(res && res.button_id === 'ok');
      });
    },
    readTextFromClipboard: function(cb) {
      return _invokeAsync('web_app_read_text_from_clipboard', {}, cb, function(res) { return res ? (res.data || '') : ''; });
    },
    requestWriteAccess: function(cb) {
      return _invokeAsync('web_app_request_write_access', {}, cb, function(res) { return !!(res && res.status === 'allowed'); });
    },
    requestContact: function(cb) {
      return _invokeAsync('web_app_request_phone', {}, cb, function(res) { return !!(res && res.status === 'sent'); });
    },
    setHeaderColor: function(color) { webApp.headerColor = String(color || ''); _postToNative('web_app_set_header_color', { color: webApp.headerColor }, ''); },
    setBackgroundColor: function(color) { webApp.backgroundColor = String(color || ''); _postToNative('web_app_set_background_color', { color: webApp.backgroundColor }, ''); },
    setBottomBarColor: function(color) { webApp.bottomBarColor = String(color || ''); _postToNative('web_app_set_bottom_bar_color', { color: webApp.bottomBarColor }, ''); },
    enableClosingConfirmation: function() { webApp.isClosingConfirmationEnabled = true; _postToNative('web_app_setup_closing_behavior', { need_confirmation: true }, ''); },
    disableClosingConfirmation: function() { webApp.isClosingConfirmationEnabled = false; _postToNative('web_app_setup_closing_behavior', { need_confirmation: false }, ''); },
    enableVerticalSwipes: function() { webApp.isVerticalSwipesEnabled = true; _postToNative('web_app_setup_swipe_behavior', { allow_vertical_swipe: true }, ''); },
    disableVerticalSwipes: function() { webApp.isVerticalSwipesEnabled = false; _postToNative('web_app_setup_swipe_behavior', { allow_vertical_swipe: false }, ''); }
  };

  window.Telegram.WebApp = webApp;
  window.__theaverWebAppInitialized = true;
})();
''';
  }
}
