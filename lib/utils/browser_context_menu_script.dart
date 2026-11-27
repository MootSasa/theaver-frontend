import 'dart:convert';

/// Link and/or image target resolved from a long-press or context-menu gesture
/// on the top-level browser page.
class BrowserContextMenuTarget {
  final String linkUrl;
  final String linkText;
  final String imageUrl;
  final String imageAlt;

  const BrowserContextMenuTarget({
    this.linkUrl = '',
    this.linkText = '',
    this.imageUrl = '',
    this.imageAlt = '',
  });

  bool get hasLink => linkUrl.isNotEmpty;
  bool get hasImage => imageUrl.isNotEmpty;

  static String _sanitizeLinkUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('javascript:') ||
        lower.startsWith('vbscript:') ||
        lower.startsWith('data:')) {
      return '';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return '';
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
      return '';
    }
    return uri.toString();
  }

  static String _sanitizeImageUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('javascript:') ||
        lower.startsWith('vbscript:') ||
        lower.startsWith('data:text/html') ||
        lower.startsWith('data:image/svg')) {
      return '';
    }
    if (lower.startsWith('data:')) {
      if (RegExp(r'^data:image/[a-z0-9.+-]+(?:;[^,]*)?,', caseSensitive: false)
          .hasMatch(trimmed)) {
        return trimmed;
      }
      return '';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return '';
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
      return '';
    }
    return uri.toString();
  }

  /// Parses JSON sent by `window.TheaverBrowserContextMenu.postMessage(...)`.
  /// Returns `null` if malformed or if neither a safe link nor a safe image
  /// was resolved.
  static BrowserContextMenuTarget? tryParseJson(String raw) {
    try {
      dynamic decoded = jsonDecode(raw);
      if (decoded is String) {
        decoded = jsonDecode(decoded);
      }
      if (decoded is! Map) return null;
      final linkUrl = _sanitizeLinkUrl(decoded['linkUrl']?.toString() ?? '');
      final imageUrl = _sanitizeImageUrl(decoded['imageUrl']?.toString() ?? '');
      if (linkUrl.isEmpty && imageUrl.isEmpty) {
        return null;
      }
      final linkText = linkUrl.isNotEmpty
          ? (decoded['linkText']?.toString().trim() ?? '')
          : '';
      final imageAlt = imageUrl.isNotEmpty
          ? (decoded['imageAlt']?.toString().trim() ?? '')
          : '';
      return BrowserContextMenuTarget(
        linkUrl: linkUrl,
        linkText: linkText,
        imageUrl: imageUrl,
        imageAlt: imageAlt,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Safe, main-frame-only JavaScript observer for Safari-style link and image
/// long-press / context-menu previews.
abstract final class BrowserContextMenuScript {
  /// Returns the idempotent JS observer posting resolved link/image targets to
  /// `window.TheaverBrowserContextMenu.postMessage(...)`.
  static String buildObserverScript() {
    return r'''
(function() {
  try {
    if (typeof window === 'undefined' || window !== window.top) return;
    if (window.__theaverContextMenuInstalled) return;
    window.__theaverContextMenuInstalled = true;

    var HOLD_MS = 480;
    var MOVE_TOLERANCE_PX = 10;
    var holdTimer = null;
    var startX = 0;
    var startY = 0;
    var lastFiredAt = 0;

    function postTarget(target) {
      try {
        if (window.TheaverBrowserContextMenu &&
            typeof window.TheaverBrowserContextMenu.postMessage === 'function') {
          window.TheaverBrowserContextMenu.postMessage(JSON.stringify(target));
        }
      } catch (_) {}
    }

    function hasActiveTextSelection() {
      try {
        if (typeof window.getSelection === 'function') {
          var sel = window.getSelection();
          if (sel && String(sel.toString() || '').trim().length > 0) {
            return true;
          }
        }
      } catch (_) {}
      return false;
    }

    function resolveSafeLinkUrl(rawHref) {
      var raw = String(rawHref || '').trim();
      if (!raw) return '';
      if (/^(javascript|vbscript|data):/i.test(raw)) return '';
      try {
        var u = new URL(raw, document.baseURI);
        if (u.protocol === 'http:' || u.protocol === 'https:') {
          return u.href;
        }
      } catch (_) {}
      return '';
    }

    function resolveSafeImageUrl(rawSrc) {
      var raw = String(rawSrc || '').trim();
      if (!raw) return '';
      if (/^(javascript|vbscript):/i.test(raw)) return '';
      if (/^data:text\/html/i.test(raw)) return '';
      if (/^data:image\/svg/i.test(raw)) return '';
      if (/^data:/i.test(raw)) {
        if (/^data:image\/[a-z0-9.+-]+(?:;[^,]*)?,/i.test(raw)) {
          return raw;
        }
        return '';
      }
      try {
        var u = new URL(raw, document.baseURI);
        if (u.protocol === 'http:' || u.protocol === 'https:') {
          return u.href;
        }
      } catch (_) {}
      return '';
    }

    function resolveTarget(node) {
      if (!node || typeof node.closest !== 'function') return null;
      var linkEl = node.closest('a[href]');
      var imgEl = (node.tagName === 'IMG' && node.getAttribute('src'))
          ? node
          : node.closest('img[src]');

      var linkUrl = linkEl ? resolveSafeLinkUrl(linkEl.getAttribute('href')) : '';
      var imageUrl = imgEl ? resolveSafeImageUrl(imgEl.getAttribute('src')) : '';
      if (!linkUrl && !imageUrl) return null;

      var linkText = '';
      if (linkEl && linkUrl) {
        linkText = String(linkEl.textContent || linkEl.getAttribute('title') || '').replace(/\s+/g, ' ').trim();
        if (linkText.length > 240) linkText = linkText.slice(0, 240);
      }
      var imageAlt = '';
      if (imgEl && imageUrl) {
        imageAlt = String(imgEl.getAttribute('alt') || imgEl.getAttribute('title') || '').replace(/\s+/g, ' ').trim();
        if (imageAlt.length > 240) imageAlt = imageAlt.slice(0, 240);
      }

      return {
        linkUrl: linkUrl,
        linkText: linkText,
        imageUrl: imageUrl,
        imageAlt: imageAlt
      };
    }

    function clearHoldTimer() {
      if (holdTimer !== null) {
        clearTimeout(holdTimer);
        holdTimer = null;
      }
    }

    document.addEventListener('touchstart', function(e) {
      clearHoldTimer();
      if (!e || (e.touches && e.touches.length > 1)) return;
      if (hasActiveTextSelection()) return;

      var resolved = resolveTarget(e.target);
      if (!resolved) return;

      var touch = e.touches && e.touches[0] ? e.touches[0] : e;
      startX = typeof touch.clientX === 'number' ? touch.clientX : 0;
      startY = typeof touch.clientY === 'number' ? touch.clientY : 0;

      holdTimer = setTimeout(function() {
        holdTimer = null;
        if (hasActiveTextSelection()) return;
        lastFiredAt = Date.now();
        postTarget(resolved);
      }, HOLD_MS);
    }, { passive: true, capture: true });

    document.addEventListener('touchmove', function(e) {
      if (holdTimer === null) return;
      if (!e || (e.touches && e.touches.length > 1)) {
        clearHoldTimer();
        return;
      }
      var touch = e.touches && e.touches[0] ? e.touches[0] : e;
      var cx = typeof touch.clientX === 'number' ? touch.clientX : startX;
      var cy = typeof touch.clientY === 'number' ? touch.clientY : startY;
      if (Math.abs(cx - startX) > MOVE_TOLERANCE_PX ||
          Math.abs(cy - startY) > MOVE_TOLERANCE_PX) {
        clearHoldTimer();
      }
    }, { passive: true, capture: true });

    document.addEventListener('touchend', clearHoldTimer, { passive: true, capture: true });
    document.addEventListener('touchcancel', clearHoldTimer, { passive: true, capture: true });
    window.addEventListener('scroll', clearHoldTimer, { passive: true, capture: true });

    document.addEventListener('contextmenu', function(e) {
      clearHoldTimer();
      if (hasActiveTextSelection()) return;
      var resolved = resolveTarget(e && e.target);
      if (!resolved) return;
      if (typeof e.preventDefault === 'function') {
        e.preventDefault();
      }
      if ((Date.now() - lastFiredAt) > 650) {
        lastFiredAt = Date.now();
        postTarget(resolved);
      }
    }, true);
  } catch (_) {}
})();
''';
  }
}
