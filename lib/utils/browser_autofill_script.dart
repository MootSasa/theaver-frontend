import 'dart:convert';

/// Active form field classification pushed from the main-frame JS observer to
/// [MiniAppSession] so [SafariAutofillAccessoryBar] can appear above the keyboard.
class BrowserFocusedFieldState {
  final String kind; // 'login' | 'contact'
  final String subtype; // 'username' | 'password' | 'name' | 'email' | 'tel'
  final String origin;

  const BrowserFocusedFieldState({
    required this.kind,
    required this.subtype,
    required this.origin,
  });

  bool get isLogin => kind == 'login';
  bool get isContact => kind == 'contact';
}

/// Captured login submission pending user confirmation to save or update in
/// [BrowserVaultService].
class BrowserPendingCredentialSubmission {
  final String url;
  final String origin;
  final String displayHost;
  final String username;
  final String password;
  final bool isUpdate;
  final String? existingId;

  const BrowserPendingCredentialSubmission({
    required this.url,
    required this.origin,
    required this.displayHost,
    required this.username,
    required this.password,
    required this.isUpdate,
    this.existingId,
  });
}

/// Safe, main-frame-only JavaScript observer and native-setter form injector for
/// Theaver's in-app WebView browser.
abstract final class BrowserAutofillScript {
  /// Returns the idempotent JS observer injected into top-level web pages.
  ///
  /// Strictly refuses execution in nested frames (`window !== window.top`),
  /// never mutates website DOM attributes, and emits JSON messages through
  /// `window.TheaverBrowserAutofill.postMessage(...)`.
  static String buildObserverScript() {
    return r'''
(function() {
  try {
    if (typeof window === 'undefined' || window !== window.top) return;
    if (window.__theaverAutofillInstalled) return;
    window.__theaverAutofillInstalled = true;

    var lastSubmitSig = '';
    var lastSubmitTs = 0;
    var lastUsernameSeen = '';
    var blurTimer = null;

    function postMsg(obj) {
      try {
        if (window.TheaverBrowserAutofill &&
            typeof window.TheaverBrowserAutofill.postMessage === 'function') {
          window.TheaverBrowserAutofill.postMessage(JSON.stringify(obj));
        }
      } catch (_) {}
    }

    function isVisibleInput(el) {
      if (!el || el.disabled || el.readOnly) return false;
      var t = (el.getAttribute('type') || 'text').toLowerCase();
      if (t === 'hidden' || t === 'submit' || t === 'button' ||
          t === 'checkbox' || t === 'radio' || t === 'file' ||
          t === 'range' || t === 'color' || t === 'search' || t === 'image' || t === 'reset') {
        return false;
      }
      if (typeof el.offsetWidth === 'number' && typeof el.offsetHeight === 'number') {
        if (el.offsetWidth <= 0 || el.offsetHeight <= 0) {
          // Allow headless/virtual DOM tests where layout engine is mocked unless explicitly hidden
          var stInline = el.style || {};
          if (stInline.display === 'none' || stInline.visibility === 'hidden') return false;
        }
      }
      if (typeof window.getComputedStyle === 'function') {
        var cs = window.getComputedStyle(el);
        if (cs && (cs.display === 'none' || cs.visibility === 'hidden')) return false;
      }
      return true;
    }

    function findContainer(el) {
      if (!el) return document;
      if (el.form) return el.form;
      if (typeof el.closest === 'function') {
        var f = el.closest('form');
        if (f) return f;
      }
      var cur = el.parentElement;
      for (var depth = 0; cur && depth < 5; depth++) {
        if (cur.querySelector && cur.querySelector('input[type="password"]')) {
          return cur;
        }
        cur = cur.parentElement;
      }
      return document;
    }

    function hasVisiblePasswordIn(root) {
      if (!root || !root.querySelectorAll) return false;
      var pwds = root.querySelectorAll('input[type="password"]');
      for (var i = 0; i < pwds.length; i++) {
        if (isVisibleInput(pwds[i])) return true;
      }
      return false;
    }

    function classifyInput(el) {
      if (!el || el.tagName !== 'INPUT' || !isVisibleInput(el)) return null;
      var t = (el.getAttribute('type') || 'text').toLowerCase();
      var ac = (el.getAttribute('autocomplete') || '').toLowerCase();
      var nameId = (
        (el.getAttribute('name') || '') + ' ' +
        (el.getAttribute('id') || '') + ' ' +
        (el.getAttribute('placeholder') || '')
      ).toLowerCase();

      if (t === 'password' || ac.indexOf('current-password') !== -1 || ac.indexOf('new-password') !== -1) {
        return { kind: 'login', subtype: 'password' };
      }

      if (ac.indexOf('username') !== -1) {
        return { kind: 'login', subtype: 'username' };
      }

      var container = findContainer(el);
      if (hasVisiblePasswordIn(container)) {
        if (t === 'text' || t === 'email' || t === 'tel' || t === '') {
          return { kind: 'login', subtype: 'username' };
        }
      }

      // Standalone 2-step username/login screen hints
      if (/(login|user|account|signin|логин)/.test(nameId) && (t === 'text' || t === 'email' || t === '')) {
        return { kind: 'login', subtype: 'username' };
      }

      // Contact autofill classification
      if (t === 'email' || ac.indexOf('email') !== -1 || /\b(e-?mail|почт)\b/.test(nameId)) {
        return { kind: 'contact', subtype: 'email' };
      }
      if (t === 'tel' || ac.indexOf('tel') !== -1 || /\b(phone|tel|mobile|телефон)\b/.test(nameId)) {
        return { kind: 'contact', subtype: 'tel' };
      }
      if (ac.indexOf('name') !== -1 || ac.indexOf('given-name') !== -1 || ac.indexOf('family-name') !== -1 ||
          /\b(fullname|full_name|fio|first_?name|your_?name|имя)\b/.test(nameId)) {
        return { kind: 'contact', subtype: 'name' };
      }

      return null;
    }

    function extractCredentialsFrom(root) {
      if (!root || !root.querySelectorAll) return null;
      var inputs = root.querySelectorAll('input');
      var nonEmptyPwds = [];
      var firstNewPwd = null;
      var userEl = null;
      for (var i = 0; i < inputs.length; i++) {
        var inp = inputs[i];
        if (!inp || inp.disabled) continue;
        var t = (inp.getAttribute('type') || 'text').toLowerCase();
        var ac = (inp.getAttribute('autocomplete') || '').toLowerCase();
        if (t === 'password' ||
            ac.indexOf('current-password') !== -1 ||
            ac.indexOf('new-password') !== -1) {
          var stInline = inp.style || {};
          if (stInline.display === 'none' || stInline.visibility === 'hidden') continue;
          if (typeof window.getComputedStyle === 'function') {
            var cs = window.getComputedStyle(inp);
            if (cs && (cs.display === 'none' || cs.visibility === 'hidden')) continue;
          }
          if ((inp.value || '').length > 0) {
            nonEmptyPwds.push(inp);
            if (!firstNewPwd && ac.indexOf('new-password') !== -1) {
              firstNewPwd = inp;
            }
          }
        }
      }
      if (nonEmptyPwds.length === 0) return null;
      var pwdEl = firstNewPwd ||
          (nonEmptyPwds.length >= 2 ? nonEmptyPwds[1] : nonEmptyPwds[0]);

      for (var j = 0; j < inputs.length; j++) {
        var cand = inputs[j];
        if (cand === pwdEl) break;
        if (!isVisibleInput(cand)) continue;
        var ct = (cand.getAttribute('type') || 'text').toLowerCase();
        if (ct === 'text' || ct === 'email' || ct === 'tel' || ct === '') {
          if ((cand.value || '').trim().length > 0) {
            userEl = cand;
          }
        }
      }
      var username = userEl ? (userEl.value || '').trim() : lastUsernameSeen;
      var password = pwdEl.value || '';
      if (!password) return null;
      return { username: username || '', password: password };
    }

    function emitSubmission(root) {
      var creds = extractCredentialsFrom(root);
      if (!creds) return;
      var now = Date.now();
      var sig = window.location.origin + '|' + creds.username + '|' + creds.password.length;
      if (sig === lastSubmitSig && (now - lastSubmitTs) < 800) return;
      lastSubmitSig = sig;
      lastSubmitTs = now;
      postMsg({
        type: 'credentialsSubmitted',
        origin: window.location.origin,
        username: creds.username,
        password: creds.password
      });
    }

    document.addEventListener('focusin', function(e) {
      var target = e && e.target;
      var info = classifyInput(target);
      if (!info) return;
      if (blurTimer) {
        clearTimeout(blurTimer);
        blurTimer = null;
      }
      window.__theaverLastFocusedInput = target;
      postMsg({
        type: 'fieldFocused',
        kind: info.kind,
        subtype: info.subtype,
        origin: window.location.origin
      });
    }, true);

    document.addEventListener('input', function(e) {
      var target = e && e.target;
      var info = classifyInput(target);
      if (info && info.kind === 'login' && info.subtype === 'username') {
        lastUsernameSeen = (target.value || '').trim();
      }
    }, true);

    document.addEventListener('focusout', function() {
      if (blurTimer) clearTimeout(blurTimer);
      blurTimer = setTimeout(function() {
        var active = document.activeElement;
        if (!classifyInput(active)) {
          postMsg({
            type: 'fieldBlurred',
            origin: window.location.origin
          });
        }
      }, 120);
    }, true);

    document.addEventListener('submit', function(e) {
      emitSubmission(e && e.target ? e.target : document);
    }, true);

    document.addEventListener('keydown', function(e) {
      if (e && e.key === 'Enter' && e.target && e.target.tagName === 'INPUT') {
        emitSubmission(findContainer(e.target));
      }
    }, true);

    document.addEventListener('click', function(e) {
      var el = e && e.target;
      if (!el || typeof el.closest !== 'function') return;
      var btn = el.closest('button, input[type="submit"], [role="button"]');
      if (!btn) return;
      emitSubmission(findContainer(btn));
    }, true);
  } catch (_) {}
})();
''';
  }

  static String _nativeValueSetterJsHelper() => r'''
function setNativeValue(input, val) {
  if (!input || val === null || val === undefined) return false;
  var str = String(val);
  var proto = window.HTMLInputElement && window.HTMLInputElement.prototype;
  var desc = proto ? Object.getOwnPropertyDescriptor(proto, 'value') : null;
  if (desc && typeof desc.set === 'function') {
    desc.set.call(input, str);
  } else {
    input.value = str;
  }
  try { input.dispatchEvent(new Event('input', { bubbles: true })); } catch (_) {}
  try { input.dispatchEvent(new Event('change', { bubbles: true })); } catch (_) {}
  return true;
}
''';

  /// Injects [username] and [password] ONLY into top-level pages whose
  /// `window.location.origin` strictly equals [expectedOrigin].
  static String buildFillCredentialsScript({
    required String expectedOrigin,
    required String username,
    required String password,
  }) {
    final encodedOrigin = jsonEncode(expectedOrigin);
    final encodedUser = jsonEncode(username);
    final encodedPass = jsonEncode(password);
    return '''
(function() {
  try {
    if (typeof window === 'undefined' || window !== window.top) return false;
    if (window.location.origin !== $encodedOrigin) return false;
    ${_nativeValueSetterJsHelper()}

    var focused = window.__theaverLastFocusedInput || document.activeElement;
    var container = (focused && focused.form) ? focused.form : document;
    var inputs = container.querySelectorAll('input');
    var pwdEl = null;
    var userEl = null;

    for (var i = 0; i < inputs.length; i++) {
      var inp = inputs[i];
      if (inp.disabled || inp.readOnly) continue;
      var t = (inp.getAttribute('type') || 'text').toLowerCase();
      var ac = (inp.getAttribute('autocomplete') || '').toLowerCase();
      if (!pwdEl && (t === 'password' || ac.indexOf('current-password') !== -1 || ac.indexOf('new-password') !== -1)) {
        pwdEl = inp;
      } else if (!userEl && (t === 'text' || t === 'email' || t === 'tel' || t === '')) {
        if (ac.indexOf('username') !== -1 || t === 'email' || inp === focused || (!pwdEl)) {
          userEl = inp;
        }
      }
    }

    if (!userEl && focused && focused.tagName === 'INPUT' && focused !== pwdEl) {
      var ft = (focused.getAttribute('type') || 'text').toLowerCase();
      if (ft === 'text' || ft === 'email' || ft === 'tel' || ft === '') {
        userEl = focused;
      }
    }

    var filled = false;
    if (userEl && $encodedUser) {
      filled = setNativeValue(userEl, $encodedUser) || filled;
    }
    if (pwdEl && $encodedPass) {
      filled = setNativeValue(pwdEl, $encodedPass) || filled;
    }
    return filled;
  } catch (_) {
    return false;
  }
})();
''';
  }

  /// Injects contact fields into matching visible `<input>` controls on
  /// [expectedOrigin] using native property descriptors for SPA compatibility.
  static String buildFillContactScript({
    required String expectedOrigin,
    String? fullName,
    String? email,
    String? phone,
  }) {
    final encodedOrigin = jsonEncode(expectedOrigin);
    final encodedName = jsonEncode(fullName ?? '');
    final encodedEmail = jsonEncode(email ?? '');
    final encodedPhone = jsonEncode(phone ?? '');
    return '''
(function() {
  try {
    if (typeof window === 'undefined' || window !== window.top) return false;
    if (window.location.origin !== $encodedOrigin) return false;
    ${_nativeValueSetterJsHelper()}

    var focused = window.__theaverLastFocusedInput || document.activeElement;
    var root = (focused && focused.form) ? focused.form : document;
    var inputs = root.querySelectorAll('input');
    var filled = false;

    for (var i = 0; i < inputs.length; i++) {
      var el = inputs[i];
      if (!el || el.disabled || el.readOnly) continue;
      var t = (el.getAttribute('type') || 'text').toLowerCase();
      if (t === 'password' || t === 'hidden' || t === 'submit' || t === 'button') continue;
      var ac = (el.getAttribute('autocomplete') || '').toLowerCase();
      var sig = ((el.getAttribute('name') || '') + ' ' + (el.getAttribute('id') || '') + ' ' + (el.getAttribute('placeholder') || '')).toLowerCase();

      if ($encodedEmail && (t === 'email' || ac.indexOf('email') !== -1 || /\\b(e-?mail|почт)\\b/.test(sig))) {
        if (el === focused || !(el.value || '').trim()) {
          filled = setNativeValue(el, $encodedEmail) || filled;
        }
      } else if ($encodedPhone && (t === 'tel' || ac.indexOf('tel') !== -1 || /\\b(phone|tel|mobile|телефон)\\b/.test(sig))) {
        if (el === focused || !(el.value || '').trim()) {
          filled = setNativeValue(el, $encodedPhone) || filled;
        }
      } else if ($encodedName && (ac.indexOf('name') !== -1 || ac.indexOf('given-name') !== -1 || ac.indexOf('family-name') !== -1 || /\\b(fullname|full_name|fio|first_?name|your_?name|имя)\\b/.test(sig))) {
        if (el === focused || !(el.value || '').trim()) {
          filled = setNativeValue(el, $encodedName) || filled;
        }
      }
    }
    return filled;
  } catch (_) {
    return false;
  }
})();
''';
  }
}
