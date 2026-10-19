import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class WebNotificationHelper {
  static bool _initialized = false;
  static bool _isWindowFocused = true;

  static void init({
    required VoidCallback onTabHidden,
    required VoidCallback onTabVisible,
  }) {
    if (_initialized) return;
    _initialized = true;

    try {
      _isWindowFocused = web.document.hasFocus();
    } catch (_) {
      _isWindowFocused = true;
    }

    try {
      web.document.addEventListener(
        'visibilitychange',
        ((web.Event _) {
          if (web.document.visibilityState == 'hidden') {
            _isWindowFocused = false;
            onTabHidden();
          } else {
            _isWindowFocused = true;
            onTabVisible();
          }
        }).toJS,
      );

      web.window.addEventListener(
        'blur',
        ((web.Event _) {
          _isWindowFocused = false;
          onTabHidden();
        }).toJS,
      );

      web.window.addEventListener(
        'focus',
        ((web.Event _) {
          _isWindowFocused = true;
          onTabVisible();
        }).toJS,
      );
    } catch (e) {
      debugPrint('WebNotificationHelper: visibility listener error: $e');
    }

    // Request browser notification permission on first user interaction
    // (modern browsers require a user gesture for requestPermission)
    _setupPermissionOnFirstInteraction();
    // Also try immediately in case browser allows it
    requestPermission();
  }

  static void _setupPermissionOnFirstInteraction() {
    try {
      late JSFunction handler;
      handler = ((web.Event _) {
        try {
          web.document.removeEventListener('click', handler);
          web.document.removeEventListener('keydown', handler);
        } catch (_) {}
        requestPermission();
      }).toJS;

      web.document.addEventListener('click', handler);
      web.document.addEventListener('keydown', handler);
    } catch (_) {}
  }

  static Future<bool> requestPermission() async {
    try {
      final current = web.Notification.permission;
      if (current == 'granted') return true;
      if (current == 'denied') return false;

      final resultJs = await web.Notification.requestPermission().toDart;
      return resultJs.toDart == 'granted';
    } catch (e) {
      debugPrint('WebNotificationHelper: requestPermission error: $e');
      return false;
    }
  }

  static bool get isTabFocused {
    try {
      return web.document.visibilityState == 'visible' &&
          web.document.hasFocus() &&
          _isWindowFocused;
    } catch (_) {
      return _isWindowFocused;
    }
  }

  static void showBrowserNotification({
    required String title,
    required String body,
    String? iconUrl,
    String? tag,
    VoidCallback? onTap,
  }) {
    try {
      if (web.Notification.permission != 'granted') {
        requestPermission();
        return;
      }

      final icon = (iconUrl != null && iconUrl.isNotEmpty)
          ? iconUrl
          : '/icons/Icon-192.png';

      final options = web.NotificationOptions(
        body: body,
        icon: icon,
        tag: tag ?? 'theaver-msg',
      );

      final notif = web.Notification(title, options);
      notif.onclick = ((web.Event event) {
        try {
          event.preventDefault();
          web.window.focus();
          notif.close();
        } catch (_) {}
        onTap?.call();
      }).toJS;

      Timer(const Duration(seconds: 6), () {
        try {
          notif.close();
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('WebNotificationHelper: showBrowserNotification error: $e');
    }
  }

  static void playNotificationSound() {
    try {
      final ctx = web.AudioContext();
      final now = ctx.currentTime;

      final osc = ctx.createOscillator();
      final gain = ctx.createGain();

      osc.type = 'sine';
      osc.frequency.setValueAtTime(587.33, now); // D5
      osc.frequency.setValueAtTime(880.0, now + 0.09); // A5

      gain.gain.setValueAtTime(0.001, now);
      gain.gain.exponentialRampToValueAtTime(0.12, now + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.25);

      osc.connect(gain);
      gain.connect(ctx.destination);

      osc.start(now);
      osc.stop(now + 0.26);

      Timer(const Duration(milliseconds: 400), () {
        try {
          ctx.close();
        } catch (_) {}
      });
    } catch (_) {}
  }
}
