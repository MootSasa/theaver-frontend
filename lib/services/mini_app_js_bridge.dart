import 'dart:convert';
import 'dart:math' as math;

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
  final Color dockBg;
  final Color divider;

  const MiniAppThemeColors({
    required this.palette,
    required this.bodyBg,
    required this.surfaceBg,
    required this.headerBg,
    required this.headerFg,
    required this.dockBg,
    required this.divider,
  });
}

/// Builds the full `window.Telegram.WebApp` (Bot API v8.0) JS injection bridge,
/// builds CSS/JS `themeParams` and launch hash URLs from [ThemeData], and parses
/// bridge callbacks.
class MiniAppJsBridge {
  static const String kWebAppVersion = '8.0';

  static double _rgbDistance(Color a, Color b) {
    final dr = (a.r - b.r) * 255.0;
    final dg = (a.g - b.g) * 255.0;
    final db = (a.b - b.b) * 255.0;
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  /// Numeric `major.minor` version comparison matching `Telegram.WebApp.isVersionAtLeast`.
  static bool isVersionAtLeast(String currentVersion, String requiredVersion) {
    List<int> parseParts(String raw) {
      final cleaned = raw.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '');
      if (cleaned.isEmpty) return const [0];
      return cleaned
          .split('.')
          .map((part) => int.tryParse(part.trim()) ?? 0)
          .toList();
    }

    final a = parseParts(currentVersion);
    final b = parseParts(requiredVersion);
    final maxLen = math.max(a.length, b.length);
    for (var i = 0; i < maxLen; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av > bv) return true;
      if (av < bv) return false;
    }
    return true;
  }

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
    final bool isDark = bodyBg.computeLuminance() < 0.5;
    final Color primaryOpaque = palette.primary.withValues(alpha: 1.0);
    final bool brightPrimary = primaryOpaque.computeLuminance() > 0.45;
    Color dockBg;
    if (isDark) {
      final Color midBase = Color.lerp(bodyBg, surfaceBg, 0.5)!;
      final double primaryAlpha = bodyBg.computeLuminance() < 0.008
          ? (brightPrimary ? 0.11 : 0.16)
          : (brightPrimary ? 0.09 : 0.14);
      dockBg = Color.alphaBlend(
        primaryOpaque.withValues(alpha: primaryAlpha),
        midBase,
      );
    } else {
      dockBg = Color.alphaBlend(
        primaryOpaque.withValues(alpha: 0.08),
        Color.alphaBlend(
          palette.onSurface.withValues(alpha: 0.04),
          surfaceBg,
        ),
      );
    }
    if (_rgbDistance(dockBg, bodyBg) < 18.0) {
      dockBg = Color.alphaBlend(
        palette.onSurface.withValues(alpha: isDark ? 0.10 : 0.08),
        dockBg,
      );
    }
    if (_rgbDistance(dockBg, headerBg) < 12.0) {
      dockBg = Color.alphaBlend(
        palette.onSurface.withValues(alpha: isDark ? 0.07 : 0.06),
        dockBg,
      );
    }
    dockBg = dockBg.withValues(alpha: 1.0);
    return MiniAppThemeColors(
      palette: palette,
      bodyBg: bodyBg,
      surfaceBg: surfaceBg,
      headerBg: headerBg,
      headerFg: headerFg,
      dockBg: dockBg,
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

  static String _mergeFragmentQuery(
    String rawQuery,
    Map<String, String> overrides,
  ) {
    final mergedTokens = <String>[];
    final appliedKeys = <String>{};

    if (rawQuery.isNotEmpty) {
      for (final part in rawQuery.split('&')) {
        if (part.isEmpty) continue;
        final eqIdx = part.indexOf('=');
        if (eqIdx < 0) {
          mergedTokens.add(part);
          continue;
        }
        final rawKey = part.substring(0, eqIdx);
        String decodedKey = rawKey;
        try {
          decodedKey = Uri.decodeComponent(rawKey);
        } catch (_) {}
        if (overrides.containsKey(decodedKey)) {
          if (!appliedKeys.contains(decodedKey)) {
            mergedTokens.add(
              '${Uri.encodeComponent(decodedKey)}=${Uri.encodeComponent(overrides[decodedKey]!)}',
            );
            appliedKeys.add(decodedKey);
          }
        } else {
          mergedTokens.add(part);
        }
      }
    }

    for (final entry in overrides.entries) {
      if (!appliedKeys.contains(entry.key)) {
        mergedTokens.add(
          '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
        );
      }
    }
    return mergedTokens.join('&');
  }

  /// Appends or merges standard Telegram launch hash parameters
  /// (`#tgWebAppData=...&tgWebAppVersion=8.0&tgWebAppPlatform=...&tgWebAppThemeParams=...`)
  /// into [rawUrl] while safely preserving existing hash routes or custom params.
  static Uri buildLaunchUriWithHashParams(
    String rawUrl, {
    required String initData,
    required Map<String, dynamic> themeParams,
    required String platform,
    String version = kWebAppVersion,
  }) {
    final trimmed = rawUrl.trim();
    final uri = Uri.tryParse(trimmed) ?? Uri.parse(Uri.encodeFull(trimmed));

    final effectiveVersion =
        version.trim().isNotEmpty ? version.trim() : kWebAppVersion;
    final effectivePlatform =
        platform.trim().isNotEmpty ? platform.trim() : 'android';

    final tgParams = <String, String>{
      'tgWebAppData': initData,
      'tgWebAppVersion': effectiveVersion,
      'tgWebAppPlatform': effectivePlatform,
      'tgWebAppThemeParams': jsonEncode(themeParams),
    };

    final existingFragment = uri.hasFragment ? uri.fragment : '';
    final String mergedFragment;
    if (existingFragment.isEmpty) {
      mergedFragment = _mergeFragmentQuery('', tgParams);
    } else {
      final qIdx = existingFragment.indexOf('?');
      if (qIdx >= 0) {
        final routePrefix = existingFragment.substring(0, qIdx);
        final queryPart = existingFragment.substring(qIdx + 1);
        mergedFragment =
            '$routePrefix?${_mergeFragmentQuery(queryPart, tgParams)}';
      } else if (!existingFragment.startsWith('/') &&
          existingFragment.contains('=')) {
        mergedFragment = _mergeFragmentQuery(existingFragment, tgParams);
      } else {
        // Hash route (e.g. `#/shop`) or anchor (`#section`): keep prefix before `?`
        // so both official `telegram-web-app.js` `_path` and SPA HashRouters work.
        mergedFragment =
            '$existingFragment?${_mergeFragmentQuery('', tgParams)}';
      }
    }

    return uri.replace(fragment: mergedFragment);
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

      var reqIdRaw = (map['reqId'] ?? map['req_id'])?.toString().trim();
      if ((reqIdRaw == null || reqIdRaw.isEmpty) &&
          eventData['req_id'] != null) {
        reqIdRaw = eventData['req_id']?.toString().trim();
      }
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

  /// Generates JS code injecting `window.TelegramWebviewProxy`, `window.Telegram.WebView`,
  /// and `window.Telegram.WebApp` v8.0.
  static String buildInjectionScript(
    MiniAppLaunchData launch,
    Map<String, String> themeParams, {
    required String colorScheme,
    required double viewportHeight,
    bool isExpanded = false,
    String platform = 'android',
    double topClearance = 0,
    double bottomClearance = 0,
    double systemTopInset = 0,
    double systemBottomInset = 0,
  }) {
    final initDataJson = jsonEncode(launch.initData);
    final initDataUnsafeJson = jsonEncode(launch.initDataUnsafe);
    final themeJson = jsonEncode(themeParams);
    final colorSchemeJson = jsonEncode(colorScheme);
    final platformJson = jsonEncode(platform);
    final versionJson = jsonEncode(
      launch.version.isNotEmpty ? launch.version : kWebAppVersion,
    );
    final headerBgJson = jsonEncode(themeParams['header_bg_color'] ?? '#ffffff');
    final bgJson = jsonEncode(themeParams['bg_color'] ?? '#ffffff');
    final secondaryBgJson = jsonEncode(
      themeParams['secondary_bg_color'] ?? themeParams['bg_color'] ?? '#ffffff',
    );
    final bottomBarBgJson = jsonEncode(
      themeParams['bottom_bar_bg_color'] ??
          themeParams['header_bg_color'] ??
          '#ffffff',
    );
    final btnColorJson = jsonEncode(themeParams['button_color'] ?? '#3390ec');
    final btnTextColorJson =
        jsonEncode(themeParams['button_text_color'] ?? '#ffffff');
    final secondaryBtnTextColorJson = jsonEncode(
      themeParams['button_color'] ?? themeParams['text_color'] ?? '#3390ec',
    );
    final vpHeight = viewportHeight.round();
    final topSafe = topClearance > 0 ? topClearance.round() : 0;
    final bottomSafe = bottomClearance > 0 ? bottomClearance.round() : 0;
    final sysTop = systemTopInset > 0 ? systemTopInset.round() : 0;
    final sysBottom = systemBottomInset > 0 ? systemBottomInset.round() : 0;
    final contentTop = math.max(0, topSafe - sysTop);
    final contentBottom = math.max(0, bottomSafe - sysBottom);
    final initialContentTopCss = sysTop > 0 ? contentTop : topSafe;
    final initialContentBottomCss = sysBottom > 0 ? contentBottom : bottomSafe;

    return '''
(function() {
  var _theme = $themeJson;
  if (!window.Telegram) window.Telegram = {};
  if (!window.TelegramWebviewProxy) window.TelegramWebviewProxy = {};
  if (!window.Telegram.WebView) window.Telegram.WebView = {};

  var _listeners = window.__theaverWaListeners || {};
  var _pendingCallbacks = window.__theaverWaPending || {};
  var _reqCounter = window.__theaverWaReqSeq || 1;
  window.__theaverWaListeners = _listeners;
  window.__theaverWaPending = _pendingCallbacks;

  var existingWa = window.Telegram.WebApp;
  var hasOfficialWa = !!(existingWa && !existingWa.__theaverInjected);
  var origOffEvent = (hasOfficialWa && typeof existingWa.offEvent === 'function')
    ? existingWa.offEvent.bind(existingWa)
    : null;

  var existingWv = window.Telegram.WebView;
  if (typeof existingWv.receiveEvent === 'function' && !existingWv.receiveEvent.__theaverWrapped) {
    window.__theaverOrigWebViewReceive = existingWv.receiveEvent;
  }

  if (!existingWv.initParams) {
    existingWv.initParams = {
      tgWebAppData: $initDataJson,
      tgWebAppVersion: $versionJson,
      tgWebAppPlatform: $platformJson,
      tgWebAppThemeParams: JSON.stringify(_theme)
    };
  }

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

  function _emit(eventType, eventData) {
    var list = _listeners[eventType];
    if (!list || !list.length) return;
    var snapshot = list.slice();
    for (var i = 0; i < snapshot.length; i++) {
      try { snapshot[i](eventData); } catch (e) {}
    }
  }

  function _dispatchOrigWebViewReceive(eventType, eventData) {
    var orig = window.__theaverOrigWebViewReceive;
    if (typeof orig === 'function') {
      try { orig(eventType, eventData); } catch (e) {}
    }
  }

  function _handleCustomStorageMethod(parsed) {
    var method = parsed && parsed.method ? String(parsed.method) : '';
    var customReqId = (parsed && parsed.req_id !== undefined && parsed.req_id !== null)
      ? String(parsed.req_id)
      : '';
    var params = (parsed && parsed.params && typeof parsed.params === 'object')
      ? parsed.params
      : {};
    var nativeEvent = null;
    var nativeData = {};
    var mapRes = null;

    if (method === 'saveStorageValue') {
      nativeEvent = 'cloud_storage_set';
      nativeData = {
        key: String(params.key !== undefined ? params.key : ''),
        value: String(params.value !== undefined ? params.value : '')
      };
      mapRes = function(res) {
        return (res && res.error)
          ? { req_id: customReqId, error: res.error }
          : { req_id: customReqId, result: !!(res && res.ok) };
      };
    } else if (method === 'getStorageValues') {
      nativeEvent = 'cloud_storage_get';
      nativeData = {
        keys: Array.isArray(params.keys) ? params.keys.map(String) : []
      };
      mapRes = function(res) {
        return (res && res.error)
          ? { req_id: customReqId, error: res.error }
          : { req_id: customReqId, result: (res && res.items) || {} };
      };
    } else if (method === 'deleteStorageValues') {
      nativeEvent = 'cloud_storage_remove';
      nativeData = {
        keys: Array.isArray(params.keys) ? params.keys.map(String) : []
      };
      mapRes = function(res) {
        return (res && res.error)
          ? { req_id: customReqId, error: res.error }
          : { req_id: customReqId, result: !!(res && res.ok) };
      };
    } else if (method === 'getStorageKeys') {
      nativeEvent = 'cloud_storage_keys';
      nativeData = {};
      mapRes = function(res) {
        return (res && res.error)
          ? { req_id: customReqId, error: res.error }
          : { req_id: customReqId, result: (res && res.keys) || [] };
      };
    }

    if (!nativeEvent) return false;
    var internalReqId = _nextReqId();
    _pendingCallbacks[internalReqId] = function(res) {
      var payload = mapRes(res);
      _emit('custom_method_invoked', payload);
      _emit('customMethodInvoked', payload);
      _dispatchOrigWebViewReceive('custom_method_invoked', payload);
    };
    _postToNative(nativeEvent, nativeData, internalReqId);
    return true;
  }

  window.TelegramWebviewProxy.postEvent = function(eventType, eventData) {
    var parsed = eventData;
    if (typeof eventData === 'string') {
      try { parsed = JSON.parse(eventData); } catch (e) { parsed = { value: eventData }; }
    }
    parsed = parsed || {};
    if (eventType === 'web_app_invoke_custom_method' && _handleCustomStorageMethod(parsed)) {
      return;
    }
    var reqId = (parsed && parsed.req_id !== undefined && parsed.req_id !== null)
      ? String(parsed.req_id)
      : '';
    _postToNative(eventType, parsed, reqId);
  };

  if (typeof existingWv.postEvent !== 'function') {
    existingWv.postEvent = function(eventType, callback, eventData) {
      if (typeof callback !== 'function' && eventData === undefined) {
        eventData = callback;
        callback = null;
      }
      window.TelegramWebviewProxy.postEvent(eventType, eventData || {});
      if (typeof callback === 'function') {
        try { callback(); } catch (e) {}
      }
    };
  }

  function _applyInsetCssVars(prefix, insets) {
    try {
      if (typeof document === 'undefined' || !document.documentElement || !insets || typeof insets !== 'object') return;
      var rootStyle = document.documentElement.style;
      if (typeof insets.top === 'number') rootStyle.setProperty(prefix + '-top', Math.round(insets.top) + 'px');
      if (typeof insets.bottom === 'number') rootStyle.setProperty(prefix + '-bottom', Math.round(insets.bottom) + 'px');
      if (typeof insets.left === 'number') rootStyle.setProperty(prefix + '-left', Math.round(insets.left) + 'px');
      if (typeof insets.right === 'number') rootStyle.setProperty(prefix + '-right', Math.round(insets.right) + 'px');
    } catch (e) {}
  }

  function _applyThemeCssVars(tp, scheme, vpH, vpStableH, topClear, bottomClear, contentTopClear, contentBottomClear) {
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
      if (typeof topClear === 'number' && topClear >= 0) {
        var roundedTop = Math.round(topClear);
        var topPx = roundedTop + 'px';
        var contentTopPx = Math.round(typeof contentTopClear === 'number' && contentTopClear >= 0 ? contentTopClear : topClear) + 'px';
        window.__theaverTopClear = roundedTop;
        rootStyle.setProperty('--theaver-header-clearance', topPx);
        rootStyle.setProperty('--theaver-top-obscured', topPx);
        rootStyle.setProperty('--tg-safe-area-inset-top', topPx);
        rootStyle.setProperty('--tg-safe-area-inset-left', '0px');
        rootStyle.setProperty('--tg-safe-area-inset-right', '0px');
        rootStyle.setProperty('--tg-content-safe-area-inset-top', contentTopPx);
        rootStyle.setProperty('--tg-content-safe-area-inset-left', '0px');
        rootStyle.setProperty('--tg-content-safe-area-inset-right', '0px');
      }
      if (typeof bottomClear === 'number' && bottomClear >= 0) {
        var roundedBottom = Math.round(bottomClear);
        var bottomPx = roundedBottom + 'px';
        var contentBottomPx = Math.round(typeof contentBottomClear === 'number' && contentBottomClear >= 0 ? contentBottomClear : bottomClear) + 'px';
        window.__theaverBottomClear = roundedBottom;
        rootStyle.setProperty('--theaver-bottom-clearance', bottomPx);
        rootStyle.setProperty('--theaver-safe-bottom', bottomPx);
        rootStyle.setProperty('--tg-safe-area-inset-bottom', bottomPx);
        rootStyle.setProperty('--tg-content-safe-area-inset-bottom', contentBottomPx);
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

  _applyThemeCssVars(_theme, $colorSchemeJson, $vpHeight, $vpHeight, $topSafe, $bottomSafe, $initialContentTopCss, $initialContentBottomCss);
  try {
    if (typeof document !== 'undefined' && document.head) {
      var insetStyle = document.getElementById('__theaver_hud_insets');
      if (!insetStyle) {
        insetStyle = document.createElement('style');
        insetStyle.id = '__theaver_hud_insets';
        document.head.appendChild(insetStyle);
      }
      insetStyle.textContent = 'html { scroll-padding-top: var(--theaver-header-clearance, 0px); scroll-padding-bottom: var(--theaver-bottom-clearance, 0px); }';
    }
  } catch (e) {}

  var _activeQrCallback = null;

  function _applyBiometryInfo(data) {
    if (!data || typeof data !== 'object') return;
    biometricManager.isInited = true;
    if (data.available !== undefined) biometricManager.isBiometricAvailable = !!data.available;
    if (data.is_biometric_available !== undefined) biometricManager.isBiometricAvailable = !!data.is_biometric_available;
    if (data.type !== undefined) biometricManager.biometricType = String(data.type || 'unknown');
    if (data.biometric_type !== undefined) biometricManager.biometricType = String(data.biometric_type || 'unknown');
    if (data.access_requested !== undefined) biometricManager.isAccessRequested = !!data.access_requested;
    if (data.is_access_requested !== undefined) biometricManager.isAccessRequested = !!data.is_access_requested;
    if (data.access_granted !== undefined) biometricManager.isAccessGranted = !!data.access_granted;
    if (data.is_access_granted !== undefined) biometricManager.isAccessGranted = !!data.is_access_granted;
    if (data.token_saved !== undefined) biometricManager.isBiometricTokenSaved = !!data.token_saved;
    if (data.is_biometric_token_saved !== undefined) biometricManager.isBiometricTokenSaved = !!data.is_biometric_token_saved;
    if (data.device_id !== undefined) biometricManager.deviceId = String(data.device_id || '');
  }

  function _applyLocationChecked(data) {
    if (!data || typeof data !== 'object') return;
    locationManager.isInited = true;
    if (data.available !== undefined) locationManager.isLocationAvailable = !!data.available;
    if (data.is_location_available !== undefined) locationManager.isLocationAvailable = !!data.is_location_available;
    if (data.access_requested !== undefined) locationManager.isAccessRequested = !!data.access_requested;
    if (data.is_access_requested !== undefined) locationManager.isAccessRequested = !!data.is_access_requested;
    if (data.access_granted !== undefined) locationManager.isAccessGranted = !!data.access_granted;
    if (data.is_access_granted !== undefined) locationManager.isAccessGranted = !!data.is_access_granted;
  }

  function _wrappedWebViewReceive(eventType, eventData) {
    window.__theaverWebAppReceive(eventType, eventData, '');
  }
  _wrappedWebViewReceive.__theaverWrapped = true;
  window.Telegram.WebView.receiveEvent = _wrappedWebViewReceive;

  function _safeAssign(obj, key, val) {
    if (!obj) return;
    try {
      var desc = Object.getOwnPropertyDescriptor(obj, key);
      if (!desc || desc.writable || desc.set) {
        obj[key] = val;
      }
    } catch (e) {}
  }

  window.__theaverWebAppReceive = function(eventType, eventData, reqId) {
    var curWv = window.Telegram && window.Telegram.WebView;
    if (curWv && typeof curWv.receiveEvent === 'function' && !curWv.receiveEvent.__theaverWrapped) {
      window.__theaverOrigWebViewReceive = curWv.receiveEvent;
      curWv.receiveEvent = _wrappedWebViewReceive;
    }

    if (eventType === 'theme_changed' && eventData && eventData.theme_params) {
      _theme = eventData.theme_params;
      _safeAssign(webApp, 'themeParams', eventData.theme_params);
      if (eventData.color_scheme) _safeAssign(webApp, 'colorScheme', eventData.color_scheme);
      _applyThemeCssVars(webApp.themeParams, webApp.colorScheme, webApp.viewportHeight, webApp.viewportStableHeight);
    } else if (eventType === 'viewport_changed' && eventData) {
      if (typeof eventData.height === 'number') _safeAssign(webApp, 'viewportHeight', eventData.height);
      if (eventData.is_state_stable && typeof eventData.height === 'number') {
        _safeAssign(webApp, 'viewportStableHeight', eventData.height);
      }
      if (typeof eventData.is_expanded === 'boolean') _safeAssign(webApp, 'isExpanded', eventData.is_expanded);
      _applyThemeCssVars(webApp.themeParams, webApp.colorScheme, webApp.viewportHeight, webApp.viewportStableHeight);
    } else if (eventType === 'safe_area_changed' && eventData && typeof eventData === 'object') {
      _safeAssign(webApp, 'safeAreaInset', eventData);
      _applyInsetCssVars('--tg-safe-area-inset', eventData);
    } else if (eventType === 'content_safe_area_changed' && eventData && typeof eventData === 'object') {
      _safeAssign(webApp, 'contentSafeAreaInset', eventData);
      _applyInsetCssVars('--tg-content-safe-area-inset', eventData);
    } else if (eventType === 'activated') {
      _safeAssign(webApp, 'isActive', true);
    } else if (eventType === 'deactivated') {
      _safeAssign(webApp, 'isActive', false);
    } else if (eventType === 'fullscreen_changed' && eventData) {
      if (eventData.is_fullscreen !== undefined) _safeAssign(webApp, 'isFullscreen', !!eventData.is_fullscreen);
    } else if (eventType === 'biometry_info_received') {
      _applyBiometryInfo(eventData);
    } else if (eventType === 'biometry_token_updated' && eventData) {
      if (eventData.status === 'updated') biometricManager.isBiometricTokenSaved = true;
      else if (eventData.status === 'removed') biometricManager.isBiometricTokenSaved = false;
    } else if (eventType === 'location_checked') {
      _applyLocationChecked(eventData);
    } else if (eventType === 'accelerometer_started') {
      accelerometer.isStarted = true;
    } else if (eventType === 'accelerometer_stopped' || eventType === 'accelerometer_failed') {
      accelerometer.isStarted = false;
    } else if (eventType === 'accelerometer_changed' && eventData) {
      if (typeof eventData.x === 'number') accelerometer.x = eventData.x;
      if (typeof eventData.y === 'number') accelerometer.y = eventData.y;
      if (typeof eventData.z === 'number') accelerometer.z = eventData.z;
    } else if (eventType === 'gyroscope_started') {
      gyroscope.isStarted = true;
    } else if (eventType === 'gyroscope_stopped' || eventType === 'gyroscope_failed') {
      gyroscope.isStarted = false;
    } else if (eventType === 'gyroscope_changed' && eventData) {
      if (typeof eventData.x === 'number') gyroscope.x = eventData.x;
      if (typeof eventData.y === 'number') gyroscope.y = eventData.y;
      if (typeof eventData.z === 'number') gyroscope.z = eventData.z;
    } else if (eventType === 'device_orientation_started') {
      deviceOrientation.isStarted = true;
    } else if (eventType === 'device_orientation_stopped' || eventType === 'device_orientation_failed') {
      deviceOrientation.isStarted = false;
    } else if (eventType === 'device_orientation_changed' && eventData) {
      if (typeof eventData.alpha === 'number') deviceOrientation.alpha = eventData.alpha;
      if (typeof eventData.beta === 'number') deviceOrientation.beta = eventData.beta;
      if (typeof eventData.gamma === 'number') deviceOrientation.gamma = eventData.gamma;
      if (eventData.absolute !== undefined) deviceOrientation.absolute = !!eventData.absolute;
    } else if (eventType === 'qr_text_received' && !reqId && typeof _activeQrCallback === 'function') {
      var qrData = (eventData && eventData.data !== undefined) ? String(eventData.data) : '';
      try {
        if (_activeQrCallback(qrData) === true) {
          _activeQrCallback = null;
          webApp.closeScanQrPopup();
        }
      } catch (e) {}
    } else if (eventType === 'scan_qr_popup_closed' && !reqId) {
      _activeQrCallback = null;
    }

    if (reqId && _pendingCallbacks[reqId]) {
      var pending = _pendingCallbacks[reqId];
      delete _pendingCallbacks[reqId];
      try { pending(eventData, eventType); } catch (e) {}
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
      contact_requested: 'contactRequested',
      invoice_closed: 'invoiceClosed',
      safe_area_changed: 'safeAreaChanged',
      content_safe_area_changed: 'contentSafeAreaChanged',
      qr_text_received: 'qrTextReceived',
      scan_qr_popup_closed: 'scanQrPopupClosed',
      biometry_info_received: 'biometricManagerUpdated',
      biometry_auth_requested: 'biometricAuthRequested',
      biometry_token_updated: 'biometricTokenUpdated',
      location_checked: 'locationManagerUpdated',
      location_requested: 'locationRequested',
      accelerometer_started: 'accelerometerStarted',
      accelerometer_stopped: 'accelerometerStopped',
      accelerometer_failed: 'accelerometerFailed',
      accelerometer_changed: 'accelerometerChanged',
      gyroscope_started: 'gyroscopeStarted',
      gyroscope_stopped: 'gyroscopeStopped',
      gyroscope_failed: 'gyroscopeFailed',
      gyroscope_changed: 'gyroscopeChanged',
      device_orientation_started: 'deviceOrientationStarted',
      device_orientation_stopped: 'deviceOrientationStopped',
      device_orientation_failed: 'deviceOrientationFailed',
      device_orientation_changed: 'deviceOrientationChanged',
      fullscreen_changed: 'fullscreenChanged',
      fullscreen_failed: 'fullscreenFailed',
      file_download_requested: 'fileDownloadRequested',
      prepared_message_sent: 'shareMessageSent',
      prepared_message_failed: 'shareMessageFailed',
      home_screen_checked: 'homeScreenChecked',
      home_screen_added: 'homeScreenAdded',
      emoji_status_set: 'emojiStatusSet',
      emoji_status_failed: 'emojiStatusFailed',
      emoji_status_access_requested: 'emojiStatusAccessRequested',
      custom_method_invoked: 'customMethodInvoked'
    };
    if (camelMap[eventType]) {
      _emit(camelMap[eventType], eventData);
    }

    _dispatchOrigWebViewReceive(eventType, eventData);
  };

  function _sendButtonUpdate(which, btn) {
    _postToNative(which === 'secondary' ? 'web_app_setup_secondary_button' : 'web_app_setup_main_button', {
      is_visible: !!btn.isVisible,
      is_active: !!btn.isActive,
      is_progress_visible: !!btn.isProgressVisible,
      leave_active: !!btn._leaveActive,
      text: btn.text || '',
      color: btn._hasCustomColor ? (btn.color || '') : '',
      text_color: btn._hasCustomTextColor ? (btn.textColor || '') : '',
      is_default_color: !btn._hasCustomColor,
      has_shine_effect: !!btn.hasShineEffect,
      position: btn.position || 'left'
    }, '');
  }

  function _createActionButton(which, defaultText, defaultVisible) {
    var isSecondary = which === 'secondary';
    var defaultColor = isSecondary ? $secondaryBgJson : $btnColorJson;
    var defaultTextColor = isSecondary ? $secondaryBtnTextColorJson : $btnTextColorJson;
    var btn = {
      type: isSecondary ? 'secondary' : 'main',
      text: defaultText,
      color: defaultColor,
      textColor: defaultTextColor,
      _hasCustomColor: !isSecondary,
      _hasCustomTextColor: !isSecondary,
      _leaveActive: false,
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
      showProgress: function(leaveActive) {
        btn.isProgressVisible = true;
        btn._leaveActive = !!leaveActive;
        _sendButtonUpdate(which, btn);
        return btn;
      },
      hideProgress: function() {
        btn.isProgressVisible = false;
        btn._leaveActive = false;
        _sendButtonUpdate(which, btn);
        return btn;
      },
      setParams: function(p) {
        if (!p) return btn;
        if (p.text !== undefined) btn.text = String(p.text);
        if (p.color !== undefined) {
          if (p.color === null || String(p.color).trim() === '') {
            btn._hasCustomColor = false;
            btn.color = defaultColor;
          } else {
            btn._hasCustomColor = true;
            btn.color = String(p.color);
          }
        }
        if (p.text_color !== undefined) {
          if (p.text_color === null || String(p.text_color).trim() === '') {
            btn._hasCustomTextColor = false;
            btn.textColor = defaultTextColor;
          } else {
            btn._hasCustomTextColor = true;
            btn.textColor = String(p.text_color);
          }
        }
        if (p.is_active !== undefined) btn.isActive = !!p.is_active;
        if (p.is_visible !== undefined) btn.isVisible = !!p.is_visible;
        if (p.has_shine_effect !== undefined) btn.hasShineEffect = !!p.has_shine_effect;
        if (p.position !== undefined) btn.position = String(p.position);
        _sendButtonUpdate(which, btn);
        return btn;
      },
      onClick: function(cb) { webApp.onEvent(isSecondary ? 'secondaryButtonClicked' : 'mainButtonClicked', cb); return btn; },
      offClick: function(cb) { webApp.offEvent(isSecondary ? 'secondaryButtonClicked' : 'mainButtonClicked', cb); return btn; }
    };
    return btn;
  }

  function _invokeAsync(eventType, eventData, cb, mapResult) {
    var reqId = _nextReqId();
    return new Promise(function(resolve) {
      _pendingCallbacks[reqId] = function(res, evType) {
        var mapped = mapResult ? mapResult(res, evType) : res;
        if (typeof cb === 'function') {
          try {
            if (Array.isArray(mapped) && mapped.__spreadArgs) {
              cb.apply(null, mapped);
            } else {
              cb(mapped);
            }
          } catch (e) {}
        }
        if (mapped && mapped.__resolveVal !== undefined) {
          resolve(mapped.__resolveVal);
        } else if (Array.isArray(mapped) && mapped.__spreadArgs) {
          resolve(mapped[1]);
        } else {
          resolve(mapped);
        }
      };
      _postToNative(eventType, eventData, reqId);
    });
  }

  var mainBtn = (existingWa && existingWa.MainButton) || _createActionButton('main', 'Continue', false);
  var secondaryBtn = (existingWa && existingWa.SecondaryButton) || _createActionButton('secondary', 'Cancel', false);

  var backBtn = (existingWa && existingWa.BackButton) || {
    isVisible: false,
    show: function() { backBtn.isVisible = true; _postToNative('web_app_setup_back_button', { is_visible: true }, ''); return backBtn; },
    hide: function() { backBtn.isVisible = false; _postToNative('web_app_setup_back_button', { is_visible: false }, ''); return backBtn; },
    onClick: function(cb) { webApp.onEvent('backButtonClicked', cb); return backBtn; },
    offClick: function(cb) { webApp.offEvent('backButtonClicked', cb); return backBtn; }
  };

  var settingsBtn = (existingWa && existingWa.SettingsButton) || {
    isVisible: false,
    show: function() { settingsBtn.isVisible = true; _postToNative('web_app_setup_settings_button', { is_visible: true }, ''); return settingsBtn; },
    hide: function() { settingsBtn.isVisible = false; _postToNative('web_app_setup_settings_button', { is_visible: false }, ''); return settingsBtn; },
    onClick: function(cb) { webApp.onEvent('settingsButtonClicked', cb); return settingsBtn; },
    offClick: function(cb) { webApp.offEvent('settingsButtonClicked', cb); return settingsBtn; }
  };

  var biometricManager = (existingWa && existingWa.BiometricManager) || {
    isInited: false,
    isBiometricAvailable: false,
    biometricType: 'unknown',
    isAccessRequested: false,
    isAccessGranted: false,
    isBiometricTokenSaved: false,
    deviceId: '',
    init: function(cb) {
      return _invokeAsync('web_app_biometry_get_info', {}, cb, function(res) {
        _applyBiometryInfo(res);
        return biometricManager;
      });
    },
    requestAccess: function(params, cb) {
      if (typeof params === 'function') { cb = params; params = {}; }
      var p = params || {};
      return _invokeAsync('web_app_biometry_request_access', {
        reason: p.reason ? String(p.reason) : ''
      }, cb, function(res) {
        _applyBiometryInfo(res);
        return !!biometricManager.isAccessGranted;
      });
    },
    authenticate: function(params, cb) {
      if (typeof params === 'function') { cb = params; params = {}; }
      var p = params || {};
      return _invokeAsync('web_app_biometry_request_auth', {
        reason: p.reason ? String(p.reason) : ''
      }, cb, function(res) {
        var ok = !!(res && (res.status === 'authorized' || res.authenticated === true));
        var token = (res && res.token !== undefined && res.token !== null) ? String(res.token) : '';
        var arr = [ok, token];
        arr.__spreadArgs = true;
        arr.__resolveVal = ok;
        return arr;
      });
    },
    updateBiometricToken: function(token, cb) {
      return _invokeAsync('web_app_biometry_update_token', {
        token: String(token || '')
      }, cb, function(res) {
        var st = res && res.status ? String(res.status) : 'failed';
        if (st === 'updated') biometricManager.isBiometricTokenSaved = true;
        else if (st === 'removed') biometricManager.isBiometricTokenSaved = false;
        return st === 'updated' || st === 'removed';
      });
    },
    openSettings: function() {
      _postToNative('web_app_biometry_open_settings', {}, '');
      return biometricManager;
    }
  };

  var locationManager = (existingWa && existingWa.LocationManager) || {
    isInited: false,
    isLocationAvailable: false,
    isAccessRequested: false,
    isAccessGranted: false,
    init: function(cb) {
      return _invokeAsync('web_app_check_location', {}, cb, function(res) {
        _applyLocationChecked(res);
        return locationManager;
      });
    },
    getLocation: function(cb) {
      return _invokeAsync('web_app_request_location', {}, cb, function(res) {
        if (!res || res.available === false) return null;
        return res;
      });
    },
    openSettings: function() {
      _postToNative('web_app_open_location_settings', {}, '');
      return locationManager;
    }
  };

  var accelerometer = (existingWa && existingWa.Accelerometer) || {
    isStarted: false,
    x: 0,
    y: 0,
    z: 0,
    start: function(params, cb) {
      if (typeof params === 'function') { cb = params; params = {}; }
      var p = params || {};
      var rate = (p.refresh_rate !== undefined && p.refresh_rate !== null) ? Number(p.refresh_rate) : 1000;
      return _invokeAsync('web_app_start_accelerometer', { refresh_rate: rate }, cb, function(res, evType) {
        var started = evType !== 'accelerometer_failed' && !(res && res.error);
        accelerometer.isStarted = started;
        return started;
      });
    },
    stop: function(cb) {
      return _invokeAsync('web_app_stop_accelerometer', {}, cb, function() {
        accelerometer.isStarted = false;
        return true;
      });
    }
  };

  var gyroscope = (existingWa && existingWa.Gyroscope) || {
    isStarted: false,
    x: 0,
    y: 0,
    z: 0,
    start: function(params, cb) {
      if (typeof params === 'function') { cb = params; params = {}; }
      var p = params || {};
      var rate = (p.refresh_rate !== undefined && p.refresh_rate !== null) ? Number(p.refresh_rate) : 1000;
      return _invokeAsync('web_app_start_gyroscope', { refresh_rate: rate }, cb, function(res, evType) {
        var started = evType !== 'gyroscope_failed' && !(res && res.error);
        gyroscope.isStarted = started;
        return started;
      });
    },
    stop: function(cb) {
      return _invokeAsync('web_app_stop_gyroscope', {}, cb, function() {
        gyroscope.isStarted = false;
        return true;
      });
    }
  };

  var deviceOrientation = (existingWa && existingWa.DeviceOrientation) || {
    isStarted: false,
    isNeedAbsolute: false,
    alpha: 0,
    beta: 0,
    gamma: 0,
    absolute: false,
    start: function(params, cb) {
      if (typeof params === 'function') { cb = params; params = {}; }
      var p = params || {};
      var rate = (p.refresh_rate !== undefined && p.refresh_rate !== null) ? Number(p.refresh_rate) : 1000;
      var needAbs = !!p.need_absolute;
      deviceOrientation.isNeedAbsolute = needAbs;
      return _invokeAsync('web_app_start_device_orientation', {
        refresh_rate: rate,
        need_absolute: needAbs
      }, cb, function(res, evType) {
        var started = evType !== 'device_orientation_failed' && !(res && res.error);
        deviceOrientation.isStarted = started;
        return started;
      });
    },
    stop: function(cb) {
      return _invokeAsync('web_app_stop_device_orientation', {}, cb, function() {
        deviceOrientation.isStarted = false;
        return true;
      });
    }
  };

  function _resolveThemeColorInput(color) {
    var val = String(color || '').trim();
    var isKey = val === 'bg_color' ||
      val === 'secondary_bg_color' ||
      val === 'bottom_bar_bg_color' ||
      val === 'header_bg_color';
    if (isKey) {
      var tp = (webApp && webApp.themeParams) || _theme || {};
      var resolved = tp[val] || _theme[val] || '';
      return { colorKey: val, hex: resolved || val };
    }
    return { colorKey: '', hex: val };
  }

  var webAppDefaults = {
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
    bottomBarColor: $bottomBarBgJson,
    isClosingConfirmationEnabled: false,
    isVerticalSwipesEnabled: true,
    isActive: true,
    isFullscreen: (existingWa && typeof existingWa.isFullscreen === 'boolean') ? existingWa.isFullscreen : false,
    isOrientationLocked: (existingWa && typeof existingWa.isOrientationLocked === 'boolean') ? existingWa.isOrientationLocked : false,
    safeAreaInset: (existingWa && existingWa.safeAreaInset) || { top: $sysTop, bottom: $sysBottom, left: 0, right: 0 },
    contentSafeAreaInset: (existingWa && existingWa.contentSafeAreaInset) || { top: $contentTop, bottom: $contentBottom, left: 0, right: 0 },
    BackButton: backBtn,
    MainButton: mainBtn,
    BottomButton: mainBtn,
    SecondaryButton: secondaryBtn,
    SettingsButton: settingsBtn,
    BiometricManager: biometricManager,
    LocationManager: locationManager,
    Accelerometer: accelerometer,
    Gyroscope: gyroscope,
    DeviceOrientation: deviceOrientation,
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
      function parseParts(v) {
        return String(v || '0').replace(/^v/i, '').split('.').map(function(part) {
          var n = parseInt(part, 10);
          return isNaN(n) ? 0 : n;
        });
      }
      var a = parseParts(webApp.version);
      var b = parseParts(ver);
      var len = Math.max(a.length, b.length);
      for (var i = 0; i < len; i++) {
        var av = i < a.length ? a[i] : 0;
        var bv = i < b.length ? b[i] : 0;
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
      if (list) {
        var idx = list.indexOf(cb);
        if (idx !== -1) list.splice(idx, 1);
      }
      if (origOffEvent) {
        try { origOffEvent(eventType, cb); } catch (e) {}
      }
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
    openInvoice: function(url, cb) {
      var invUrl = String(url || '');
      return _invokeAsync('web_app_open_invoice', { url: invUrl }, cb, function(res) {
        return (res && res.status) ? String(res.status) : 'cancelled';
      });
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
    showScanQrPopup: function(params, cb) {
      if (typeof params === 'function') { cb = params; params = {}; }
      var p = (params && typeof params === 'object') ? params : {};
      var reqId = _nextReqId();
      _activeQrCallback = typeof cb === 'function' ? cb : null;
      return new Promise(function(resolve) {
        _pendingCallbacks[reqId] = function(res, evType) {
          if (evType === 'scan_qr_popup_closed') {
            _activeQrCallback = null;
            resolve(null);
            return;
          }
          var text = (res && res.data !== undefined) ? String(res.data) : '';
          var fn = _activeQrCallback;
          var shouldClose = false;
          if (typeof fn === 'function') {
            try { shouldClose = fn(text) === true; } catch (e) {}
          }
          if (shouldClose) {
            _activeQrCallback = null;
            webApp.closeScanQrPopup();
          }
          resolve(text);
        };
        _postToNative('web_app_open_scan_qr_popup', { text: p.text ? String(p.text) : '' }, reqId);
      });
    },
    closeScanQrPopup: function() {
      _activeQrCallback = null;
      _postToNative('web_app_close_scan_qr_popup', {}, '');
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
    setHeaderColor: function(color) {
      var c = _resolveThemeColorInput(color);
      webApp.headerColor = c.hex;
      _postToNative('web_app_set_header_color', c.colorKey ? { color_key: c.colorKey, color: c.hex } : { color: c.hex }, '');
    },
    setBackgroundColor: function(color) {
      var c = _resolveThemeColorInput(color);
      webApp.backgroundColor = c.hex;
      _postToNative('web_app_set_background_color', c.colorKey ? { color_key: c.colorKey, color: c.hex } : { color: c.hex }, '');
    },
    setBottomBarColor: function(color) {
      var c = _resolveThemeColorInput(color);
      webApp.bottomBarColor = c.hex;
      _postToNative('web_app_set_bottom_bar_color', c.colorKey ? { color_key: c.colorKey, color: c.hex } : { color: c.hex }, '');
    },
    enableClosingConfirmation: function() { webApp.isClosingConfirmationEnabled = true; _postToNative('web_app_setup_closing_behavior', { need_confirmation: true }, ''); },
    disableClosingConfirmation: function() { webApp.isClosingConfirmationEnabled = false; _postToNative('web_app_setup_closing_behavior', { need_confirmation: false }, ''); },
    enableVerticalSwipes: function() { webApp.isVerticalSwipesEnabled = true; _postToNative('web_app_setup_swipe_behavior', { allow_vertical_swipe: true }, ''); },
    disableVerticalSwipes: function() { webApp.isVerticalSwipesEnabled = false; _postToNative('web_app_setup_swipe_behavior', { allow_vertical_swipe: false }, ''); },
    requestFullscreen: function() { _postToNative('web_app_request_fullscreen', {}, ''); },
    exitFullscreen: function() { _postToNative('web_app_exit_fullscreen', {}, ''); },
    lockOrientation: function() { webApp.isOrientationLocked = true; _postToNative('web_app_toggle_orientation_lock', { locked: true }, ''); },
    unlockOrientation: function() { webApp.isOrientationLocked = false; _postToNative('web_app_toggle_orientation_lock', { locked: false }, ''); },
    downloadFile: function(params, cb) {
      var p = (params && typeof params === 'object') ? params : {};
      return _invokeAsync('web_app_request_file_download', {
        url: String(p.url || ''),
        file_name: String(p.file_name || '')
      }, cb, function(res) {
        return !!(res && res.status === 'downloading');
      });
    },
    shareMessage: function(msgId, cb) {
      return _invokeAsync('web_app_send_prepared_message', {
        id: String(msgId || '')
      }, cb, function(res, evType) {
        return evType === 'prepared_message_sent' || !!(res && res.sent === true);
      });
    },
    shareToStory: function(mediaUrl, params) {
      var p = (params && typeof params === 'object') ? params : {};
      _postToNative('web_app_share_to_story', {
        media_url: String(mediaUrl || ''),
        text: p.text ? String(p.text) : '',
        widget_link: p.widget_link || null
      }, '');
    },
    addToHomeScreen: function() {
      _postToNative('web_app_add_to_home_screen', {}, '');
    },
    checkHomeScreenStatus: function(cb) {
      return _invokeAsync('web_app_check_home_screen', {}, cb, function(res) {
        return (res && res.status) ? String(res.status) : 'unknown';
      });
    },
    setEmojiStatus: function(customEmojiId, params, cb) {
      if (typeof params === 'function') { cb = params; params = {}; }
      var p = (params && typeof params === 'object') ? params : {};
      return _invokeAsync('web_app_set_emoji_status', {
        custom_emoji_id: String(customEmojiId || ''),
        duration: p.duration !== undefined && p.duration !== null ? Number(p.duration) : 0
      }, cb, function(res, evType) {
        return evType === 'emoji_status_set' || !!(res && res.ok === true);
      });
    },
    requestEmojiStatusAccess: function(cb) {
      return _invokeAsync('web_app_request_emoji_status_access', {}, cb, function(res) {
        return !!(res && res.status === 'allowed');
      });
    }
  };

  var webApp;
  if (hasOfficialWa) {
    // Preserve official telegram-web-app.js object identity and pre-registered handlers,
    // while wiring host theme/insets and backfilling any missing v8.0 APIs.
    webApp = existingWa;
    var defKeys = Object.keys(webAppDefaults);
    for (var di = 0; di < defKeys.length; di++) {
      var dk = defKeys[di];
      if (webApp[dk] === undefined) {
        _safeAssign(webApp, dk, webAppDefaults[dk]);
      }
    }
    if (!webApp.initData && webAppDefaults.initData) {
      _safeAssign(webApp, 'initData', webAppDefaults.initData);
      _safeAssign(webApp, 'initDataUnsafe', webAppDefaults.initDataUnsafe);
    }
    _safeAssign(webApp, 'platform', webAppDefaults.platform);
    _safeAssign(webApp, 'colorScheme', webAppDefaults.colorScheme);
    _safeAssign(webApp, 'themeParams', _theme);
    _safeAssign(webApp, 'viewportHeight', webAppDefaults.viewportHeight);
    _safeAssign(webApp, 'viewportStableHeight', webAppDefaults.viewportStableHeight);
    _safeAssign(webApp, 'safeAreaInset', webAppDefaults.safeAreaInset);
    _safeAssign(webApp, 'contentSafeAreaInset', webAppDefaults.contentSafeAreaInset);
    if (!webApp.BottomButton) _safeAssign(webApp, 'BottomButton', webApp.MainButton);
    if (!webApp.isVersionAtLeast || !webApp.isVersionAtLeast($versionJson)) {
      _safeAssign(webApp, 'version', $versionJson);
      _safeAssign(webApp, 'isVersionAtLeast', webAppDefaults.isVersionAtLeast);
    }
    _safeAssign(webApp, 'onEvent', webAppDefaults.onEvent);
    _safeAssign(webApp, 'offEvent', webAppDefaults.offEvent);
  } else {
    webApp = webAppDefaults;
  }

  _safeAssign(webApp, '__theaverInjected', true);
  window.Telegram.WebApp = webApp;
  window.__theaverWebAppInitialized = true;
  try {
    if (typeof window.CustomEvent === 'function') {
      window.dispatchEvent(new CustomEvent('theaver_webapp_ready'));
    }
  } catch (e) {}
})();
''';
  }
}
