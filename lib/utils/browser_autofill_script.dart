import 'dart:convert';

/// Active form field classification pushed from the main-frame JS observer to
/// [MiniAppSession] so [SafariAutofillAccessoryBar] can appear above the keyboard.
class BrowserFocusedFieldState {
  final String kind; // 'login' | 'contact' | 'address' | 'card' | 'otp'
  final String subtype;
  final String origin;
  final bool isSplitOtp;

  const BrowserFocusedFieldState({
    required this.kind,
    required this.subtype,
    required this.origin,
    this.isSplitOtp = false,
  });

  bool get isLogin => kind == 'login';
  bool get isCard => kind == 'card';
  bool get isOtp => kind == 'otp';
  bool get isAddress => kind == 'address' || kind == 'contact';
  bool get isContact => kind == 'contact' || kind == 'address';
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

/// Captured payment card submission pending user confirmation to save or update
/// in the vault. Never stores or captures CVV/CVC security codes.
class BrowserPendingCardSubmission {
  final String url;
  final String origin;
  final String displayHost;
  final String cardNumber;
  final String holderName;
  final int expMonth;
  final int expYear;
  final bool isUpdate;
  final String? existingId;

  const BrowserPendingCardSubmission({
    required this.url,
    required this.origin,
    required this.displayHost,
    required this.cardNumber,
    required this.holderName,
    required this.expMonth,
    required this.expYear,
    required this.isUpdate,
    this.existingId,
  });
}

/// Safe, main-frame-only JavaScript observer and native-setter form injector for
/// Theaver's in-app WebView browser.
abstract final class BrowserAutofillScript {
  static const String _sharedClassifierJsHelpers = r'''
function getFieldSignature(el) {
  if (!el) return '';
  return (
    (el.getAttribute('name') || '') + ' ' +
    (el.getAttribute('id') || '') + ' ' +
    (el.getAttribute('placeholder') || '') + ' ' +
    (el.getAttribute('aria-label') || '')
  ).toLowerCase();
}

function hasAcToken(ac, token) {
  if (!ac) return false;
  var parts = ac.trim().split(/\s+/);
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === token) return true;
  }
  return false;
}

function isCscField(el) {
  if (!el) return false;
  var ac = (el.getAttribute('autocomplete') || '').toLowerCase();
  if (hasAcToken(ac, 'cc-csc') || ac.indexOf('cc-csc') !== -1) return true;
  var sig = getFieldSignature(el);
  return /\b(cvv|cvc|csc|cvn|security[-_ ]?code|card[-_ ]?code)\b|код[-_ ]?безопасност/i.test(sig);
}

function isVisibleControl(el) {
  if (!el || el.disabled || el.readOnly) return false;
  var tag = (el.tagName || '').toUpperCase();
  if (tag !== 'INPUT' && tag !== 'TEXTAREA' && tag !== 'SELECT') return false;
  if (tag === 'INPUT') {
    var t = (el.getAttribute('type') || 'text').toLowerCase();
    if (t === 'hidden' || t === 'submit' || t === 'button' ||
        t === 'checkbox' || t === 'radio' || t === 'file' ||
        t === 'range' || t === 'color' || t === 'search' ||
        t === 'image' || t === 'reset') {
      return false;
    }
  }
  var stInline = el.style || {};
  if (stInline.display === 'none' || stInline.visibility === 'hidden') return false;
  if (typeof window.getComputedStyle === 'function') {
    var cs = window.getComputedStyle(el);
    if (cs && (cs.display === 'none' || cs.visibility === 'hidden')) return false;
  }
  return true;
}

function isSingleCharMaxLen(el) {
  if (!el || el.tagName !== 'INPUT') return false;
  if (el.maxLength === 1) return true;
  return el.getAttribute('maxlength') === '1';
}

function findSplitOtpGroup(el) {
  if (!isSingleCharMaxLen(el) || !isVisibleControl(el)) return null;
  var candidates = [];
  if (el.form) candidates.push(el.form);
  var cur = el.parentElement;
  for (var d = 0; cur && d < 5; d++) {
    if (cur.tagName === 'BODY' || cur.tagName === 'HTML') break;
    candidates.push(cur);
    cur = cur.parentElement;
  }
  for (var c = 0; c < candidates.length; c++) {
    var root = candidates[c];
    if (!root || !root.querySelectorAll) continue;
    var inputs = root.querySelectorAll('input');
    var group = [];
    var hasDisallowedPassword = false;
    for (var i = 0; i < inputs.length; i++) {
      var inp = inputs[i];
      if (!isVisibleControl(inp) || !isSingleCharMaxLen(inp)) continue;
      var t = (inp.getAttribute('type') || 'text').toLowerCase();
      if (t === 'password') {
        var im = (inp.getAttribute('inputmode') || '').toLowerCase();
        var pat = inp.getAttribute('pattern') || '';
        if (im !== 'numeric' && im !== 'decimal' && !/\[0-9\]|\\d/.test(pat)) {
          hasDisallowedPassword = true;
          break;
        }
      } else if (t !== 'text' && t !== 'tel' && t !== 'number' && t !== '') {
        continue;
      }
      group.push(inp);
    }
    if (!hasDisallowedPassword && group.length >= 4 && group.length <= 8 && group.indexOf(el) !== -1) {
      return group;
    }
  }
  return null;
}

function classifyCardSubtype(el, allowGenericDateTokens) {
  if (!el || isCscField(el) || !isVisibleControl(el)) return null;
  var tag = (el.tagName || '').toUpperCase();
  if (tag !== 'INPUT' && tag !== 'SELECT') return null;
  var t = tag === 'INPUT' ? (el.getAttribute('type') || 'text').toLowerCase() : '';
  if (t === 'password' || t === 'email') return null;
  var ac = (el.getAttribute('autocomplete') || '').toLowerCase();
  var sig = getFieldSignature(el);

  if (hasAcToken(ac, 'cc-number') || /card[-_ ]?(number|num|pan)|cc[-_ ]?(number|num)|номер[-_ ]*карты/i.test(sig)) {
    return 'cc-number';
  }
  if (hasAcToken(ac, 'cc-name') || hasAcToken(ac, 'cc-given-name') || hasAcToken(ac, 'cc-family-name') ||
      /card[-_ ]?(holder|owner|name)|name[-_ ]*on[-_ ]*card|владелец[-_ ]*карты/i.test(sig)) {
    return 'cc-name';
  }
  if (hasAcToken(ac, 'cc-exp-month') || /\b(exp[-_ ]*month|card[-_ ]*month|cc[-_ ]*month)\b/i.test(sig) ||
      (allowGenericDateTokens && (/\b(month|mm)\b|месяц/i.test(sig)))) {
    return 'cc-exp-month';
  }
  if (hasAcToken(ac, 'cc-exp-year') || /\b(exp[-_ ]*year|card[-_ ]*year|cc[-_ ]*year)\b/i.test(sig) ||
      (allowGenericDateTokens && (/\b(year|yy|yyyy)\b|год/i.test(sig)))) {
    return 'cc-exp-year';
  }
  if (hasAcToken(ac, 'cc-exp') || t === 'month' ||
      /\b(expir(y|ation)|valid[-_ ]*thru|mm\s*\/\s*yy(yy)?)\b|срок[-_ ]*действия/i.test(sig)) {
    return 'cc-exp';
  }
  return null;
}

function classifyAddressOrContactSubtype(el) {
  if (!el || isCscField(el) || !isVisibleControl(el)) return null;
  var tag = (el.tagName || '').toUpperCase();
  var t = tag === 'INPUT' ? (el.getAttribute('type') || 'text').toLowerCase() : '';
  if (t === 'password') return null;
  var ac = (el.getAttribute('autocomplete') || '').toLowerCase();
  var sig = getFieldSignature(el);

  if (hasAcToken(ac, 'street-address') || hasAcToken(ac, 'address-line1') ||
      /\b(street[-_ ]*address|address[-_ ]*(1|line1)|street)\b|улица|адрес/i.test(sig)) {
    return 'address-line1';
  }
  if (hasAcToken(ac, 'address-line2') ||
      /\b(address[-_ ]*(2|line2)|apt|suite|flat|building)\b|квартир|подъезд|корпус/i.test(sig)) {
    return 'address-line2';
  }
  if (hasAcToken(ac, 'address-level2') || /\b(city|town|locality)\b|город/i.test(sig)) {
    return 'address-level2';
  }
  if (hasAcToken(ac, 'address-level1') || /\b(state|province|region|oblast)\b|область|регион|край/i.test(sig)) {
    return 'address-level1';
  }
  if (hasAcToken(ac, 'postal-code') || /\b(zip|postal[-_ ]*code|postcode)\b|индекс|почтовый/i.test(sig)) {
    return 'postal-code';
  }
  if (hasAcToken(ac, 'country') || hasAcToken(ac, 'country-name') || /\bcountry\b|страна/i.test(sig)) {
    return 'country';
  }
  if (hasAcToken(ac, 'organization') || /\b(organization|company)\b|компания|организация/i.test(sig)) {
    return 'organization';
  }
  if (t === 'email' || hasAcToken(ac, 'email') || /\b(e-?mail|почт)\b/i.test(sig)) {
    return 'email';
  }
  if (t === 'tel' || hasAcToken(ac, 'tel') || hasAcToken(ac, 'tel-national') || /\b(phone|tel|mobile|телефон)\b/i.test(sig)) {
    return 'tel';
  }
  if (hasAcToken(ac, 'name') || hasAcToken(ac, 'given-name') || hasAcToken(ac, 'family-name') ||
      /\b(fullname|full_name|fio|first_?name|last_?name|your_?name|имя|фио|фамилия)\b/i.test(sig)) {
    return 'name';
  }
  return null;
}
''';

  /// Returns the idempotent JS observer injected into top-level web pages.
  ///
  /// Strictly refuses execution in nested frames (`window !== window.top`),
  /// never mutates website DOM attributes, ignores CVV/CVC security code fields,
  /// and emits JSON messages through `window.TheaverBrowserAutofill.postMessage(...)`.
  static String buildObserverScript() {
    return '''
(function() {
  try {
    if (typeof window === 'undefined' || window !== window.top) return;
    if (window.__theaverAutofillInstalled) return;
    window.__theaverAutofillInstalled = true;

    var lastSubmitSig = '';
    var lastSubmitTs = 0;
    var lastCardSubmitSig = '';
    var lastCardSubmitTs = 0;
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

$_sharedClassifierJsHelpers

    var otpRegex = /\\b(otp|totp|2fa|passcode)\\b|sms.?code|verif(y|ication).?code|confirm(ation)?.?code|auth.?code|код.*смс|код.*подтвержд|однораз/i;

    function isAddressSpecificSubtype(st) {
      return st === 'address-line1' || st === 'address-line2' ||
             st === 'address-level2' || st === 'address-level1' ||
             st === 'postal-code' || st === 'country' || st === 'organization';
    }

    function findContainer(el) {
      if (!el) return document;
      if (el.form) return el.form;
      if (typeof el.closest === 'function') {
        var f = el.closest('form');
        if (f) return f;
      }
      var cur = el.parentElement;
      var bestMulti = null;
      for (var depth = 0; cur && depth < 5; depth++) {
        if (cur.tagName === 'BODY' || cur.tagName === 'HTML') break;
        if (cur.querySelector && cur.querySelector('input[type="password"]')) {
          return cur;
        }
        if (cur.querySelectorAll) {
          var cnt = cur.querySelectorAll('input, select, textarea').length;
          if (cnt >= 2 && cnt <= 20) {
            bestMulti = cur;
          }
        }
        cur = cur.parentElement;
      }
      return bestMulti || document;
    }

    function findCardContainer(el) {
      if (!el) return document;
      if (el.form) return el.form;
      if (typeof el.closest === 'function') {
        var f = el.closest('form');
        if (f) return f;
      }
      var cur = el.parentElement;
      var best = null;
      for (var depth = 0; cur && depth < 6; depth++) {
        if (cur.tagName === 'BODY' || cur.tagName === 'HTML') break;
        if (cur.querySelectorAll) {
          var ctrls = cur.querySelectorAll('input, select');
          if (ctrls.length >= 2 && ctrls.length <= 20) {
            best = cur;
            for (var i = 0; i < ctrls.length; i++) {
              if (classifyCardSubtype(ctrls[i], false) === 'cc-number') {
                return cur;
              }
            }
          }
        }
        cur = cur.parentElement;
      }
      return best || findContainer(el);
    }

    function hasVisiblePasswordIn(root) {
      if (!root || !root.querySelectorAll) return false;
      var pwds = root.querySelectorAll('input[type="password"]');
      for (var i = 0; i < pwds.length; i++) {
        if (isVisibleControl(pwds[i])) return true;
      }
      return false;
    }

    function hasCardFieldIn(root) {
      if (!root || !root.querySelectorAll) return false;
      var ctrls = root.querySelectorAll('input, select');
      for (var i = 0; i < ctrls.length; i++) {
        if (classifyCardSubtype(ctrls[i], false) !== null) return true;
      }
      return false;
    }

    function hasAddressSpecificIn(root) {
      if (!root || !root.querySelectorAll) return false;
      var ctrls = root.querySelectorAll('input, textarea, select');
      for (var i = 0; i < ctrls.length; i++) {
        var st = classifyAddressOrContactSubtype(ctrls[i]);
        if (isAddressSpecificSubtype(st)) return true;
      }
      return false;
    }

    function classifyInput(el) {
      if (!isVisibleControl(el)) return null;
      if (isCscField(el)) return null;

      var tag = (el.tagName || '').toUpperCase();
      var t = tag === 'INPUT' ? (el.getAttribute('type') || 'text').toLowerCase() : '';
      var ac = (el.getAttribute('autocomplete') || '').toLowerCase();
      var sig = getFieldSignature(el);

      // 1. OTP / 2FA detection (single or 4..8 split boxes)
      if (tag === 'INPUT') {
        var splitGroup = findSplitOtpGroup(el);
        if (hasAcToken(ac, 'one-time-code') || ac.indexOf('one-time-code') !== -1) {
          return { kind: 'otp', subtype: 'one-time-code', isSplitOtp: !!splitGroup };
        }
        if (splitGroup) {
          return { kind: 'otp', subtype: 'one-time-code', isSplitOtp: true };
        }
        var im = (el.getAttribute('inputmode') || '').toLowerCase();
        var allowOtpOnType = (t === 'text' || t === 'tel' || t === 'number' || t === '' ||
            (t === 'password' && (im === 'numeric' || im === 'decimal')));
        if (allowOtpOnType && otpRegex.test(sig)) {
          return { kind: 'otp', subtype: 'one-time-code', isSplitOtp: false };
        }
      }

      // 2. Login password & explicit username
      if (tag === 'INPUT' && (t === 'password' || hasAcToken(ac, 'current-password') || hasAcToken(ac, 'new-password') ||
          ac.indexOf('current-password') !== -1 || ac.indexOf('new-password') !== -1)) {
        return { kind: 'login', subtype: 'password', isSplitOtp: false };
      }
      if (tag === 'INPUT' && (hasAcToken(ac, 'username') || ac.indexOf('username') !== -1)) {
        return { kind: 'login', subtype: 'username', isSplitOtp: false };
      }

      var container = findContainer(el);

      // 3. Payment card detection (STRICTLY https: only)
      if (window.location.protocol === 'https:') {
        var cardSub = classifyCardSubtype(el, false);
        if (!cardSub && hasCardFieldIn(container)) {
          cardSub = classifyCardSubtype(el, true);
        }
        if (cardSub) {
          return { kind: 'card', subtype: cardSub, isSplitOtp: false };
        }
      }

      // 4. Login username fallback inside password form / 2-step login hints
      if (tag === 'INPUT' && hasVisiblePasswordIn(container)) {
        if (t === 'text' || t === 'email' || t === 'tel' || t === '') {
          return { kind: 'login', subtype: 'username', isSplitOtp: false };
        }
      }
      if (tag === 'INPUT' && /(login|user|account|signin|логин)/.test(sig) && (t === 'text' || t === 'email' || t === '')) {
        return { kind: 'login', subtype: 'username', isSplitOtp: false };
      }

      // 5. Address & contact autofill classification
      var addrSub = classifyAddressOrContactSubtype(el);
      if (addrSub) {
        var isAddr = isAddressSpecificSubtype(addrSub) || hasAddressSpecificIn(container);
        return {
          kind: isAddr ? 'address' : 'contact',
          subtype: addrSub,
          isSplitOtp: false
        };
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
        if (!inp || inp.disabled || isCscField(inp)) continue;
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
        if (!isVisibleControl(cand) || isCscField(cand)) continue;
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

    function isValidLuhn(digits) {
      if (!/^\\d{13,19}\$/.test(digits)) return false;
      var sum = 0;
      var alt = false;
      for (var i = digits.length - 1; i >= 0; i--) {
        var d = digits.charCodeAt(i) - 48;
        if (alt) {
          d *= 2;
          if (d > 9) d -= 9;
        }
        sum += d;
        alt = !alt;
      }
      return (sum % 10) === 0;
    }

    function parseCombinedExpiry(raw) {
      var s = (raw || '').trim();
      if (!s) return null;
      var mIso = s.match(/^(\\d{4})[-\\/](\\d{1,2})\$/);
      if (mIso) {
        var iy = parseInt(mIso[1], 10);
        var im = parseInt(mIso[2], 10);
        if (im >= 1 && im <= 12 && iy >= 2000 && iy <= 2100) {
          return { month: im, year: iy };
        }
      }
      var mSep = s.match(/^(\\d{1,2})\\s*[\\/\\-.]\\s*(\\d{2,4})\$/);
      if (mSep) {
        var m = parseInt(mSep[1], 10);
        var y = parseInt(mSep[2], 10);
        if (y < 100) y += 2000;
        if (m >= 1 && m <= 12 && y >= 2000 && y <= 2100) {
          return { month: m, year: y };
        }
      }
      var digits = s.replace(/\\D/g, '');
      if (digits.length === 4) {
        var m4 = parseInt(digits.slice(0, 2), 10);
        var y4 = 2000 + parseInt(digits.slice(2, 4), 10);
        if (m4 >= 1 && m4 <= 12) return { month: m4, year: y4 };
      } else if (digits.length === 6) {
        var m6 = parseInt(digits.slice(0, 2), 10);
        var y6 = parseInt(digits.slice(2, 6), 10);
        if (m6 >= 1 && m6 <= 12 && y6 >= 2000 && y6 <= 2100) return { month: m6, year: y6 };
      }
      return null;
    }

    function extractCardSubmissionFrom(root) {
      if (window.location.protocol !== 'https:') return null;
      if (!root || !root.querySelectorAll) return null;
      var ctrls = root.querySelectorAll('input, select');
      var pan = '';
      var holderName = '';
      var givenName = '';
      var familyName = '';
      var expMonth = 0;
      var expYear = 0;
      var combinedExp = null;

      for (var i = 0; i < ctrls.length; i++) {
        var el = ctrls[i];
        if (!el || el.disabled || isCscField(el)) continue;
        var tag = (el.tagName || '').toUpperCase();
        var t = tag === 'INPUT' ? (el.getAttribute('type') || 'text').toLowerCase() : '';
        if (t === 'hidden' || t === 'password' || t === 'submit' || t === 'button' ||
            t === 'checkbox' || t === 'radio' || t === 'file') {
          continue;
        }
        var stInline = el.style || {};
        if (stInline.display === 'none' || stInline.visibility === 'hidden') continue;

        var rawVal = (el.value || '').trim();
        if (!rawVal) continue;

        var ac = (el.getAttribute('autocomplete') || '').toLowerCase();
        var cardSub = classifyCardSubtype(el, true);

        if (cardSub === 'cc-number') {
          var digits = rawVal.replace(/\\D/g, '');
          if (isValidLuhn(digits)) pan = digits;
        } else if (cardSub === 'cc-name') {
          if (hasAcToken(ac, 'cc-given-name')) {
            givenName = rawVal;
          } else if (hasAcToken(ac, 'cc-family-name')) {
            familyName = rawVal;
          } else {
            holderName = rawVal;
          }
        } else if (cardSub === 'cc-exp') {
          combinedExp = parseCombinedExpiry(rawVal) || combinedExp;
        } else if (cardSub === 'cc-exp-month') {
          var pm = parseInt(rawVal.replace(/\\D/g, ''), 10);
          if (pm >= 1 && pm <= 12) expMonth = pm;
        } else if (cardSub === 'cc-exp-year') {
          var py = parseInt(rawVal.replace(/\\D/g, ''), 10);
          if (!isNaN(py)) {
            if (py >= 0 && py < 100) py += 2000;
            if (py >= 2000 && py <= 2100) expYear = py;
          }
        }
      }

      if (!pan) return null;
      if ((expMonth < 1 || expMonth > 12 || expYear < 2000) && combinedExp) {
        if (expMonth < 1 || expMonth > 12) expMonth = combinedExp.month;
        if (expYear < 2000) expYear = combinedExp.year;
      }
      if (expMonth < 1 || expMonth > 12 || expYear < 2000 || expYear > 2100) return null;
      if (!holderName && (givenName || familyName)) {
        holderName = (givenName + ' ' + familyName).trim();
      }
      return {
        cardNumber: pan,
        holderName: holderName || '',
        expMonth: expMonth,
        expYear: expYear
      };
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

    function emitCardSubmission(root) {
      if (window.location.protocol !== 'https:') return;
      var card = extractCardSubmissionFrom(root);
      if (!card) return;
      var now = Date.now();
      var sig = window.location.origin + '|' + card.cardNumber.slice(-4) + '|' + card.expMonth + '|' + card.expYear;
      if (sig === lastCardSubmitSig && (now - lastCardSubmitTs) < 900) return;
      lastCardSubmitSig = sig;
      lastCardSubmitTs = now;
      postMsg({
        type: 'cardSubmitted',
        origin: window.location.origin,
        cardNumber: card.cardNumber,
        holderName: card.holderName,
        expMonth: card.expMonth,
        expYear: card.expYear
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
        isSplitOtp: !!info.isSplitOtp,
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
      var root = e && e.target ? e.target : document;
      emitSubmission(root);
      emitCardSubmission(root);
    }, true);

    document.addEventListener('keydown', function(e) {
      if (e && e.key === 'Enter' && e.target &&
          (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT')) {
        emitSubmission(findContainer(e.target));
        emitCardSubmission(findCardContainer(e.target));
      }
    }, true);

    document.addEventListener('click', function(e) {
      var el = e && e.target;
      if (!el || typeof el.closest !== 'function') return;
      var btn = el.closest('button, input[type="submit"], input[type="button"], [role="button"]');
      if (!btn) return;
      emitSubmission(findContainer(btn));
      emitCardSubmission(findCardContainer(btn));
    }, true);
  } catch (_) {}
})();
''';
  }

  static const String _nativeValueSetterJsHelper = r'''
function setNativeValue(el, val) {
  if (!el || val === null || val === undefined) return false;
  var str = String(val);
  var tag = (el.tagName || '').toUpperCase();
  var proto = null;
  if (tag === 'TEXTAREA' && window.HTMLTextAreaElement) {
    proto = window.HTMLTextAreaElement.prototype;
  } else if (tag === 'SELECT' && window.HTMLSelectElement) {
    proto = window.HTMLSelectElement.prototype;
  } else if (window.HTMLInputElement) {
    proto = window.HTMLInputElement.prototype;
  }
  var desc = proto ? Object.getOwnPropertyDescriptor(proto, 'value') : null;
  if (desc && typeof desc.set === 'function') {
    desc.set.call(el, str);
  } else {
    el.value = str;
  }
  try { el.dispatchEvent(new Event('input', { bubbles: true })); } catch (_) {}
  try { el.dispatchEvent(new Event('change', { bubbles: true })); } catch (_) {}
  return true;
}

function setSelectMatch(selectEl, candidates) {
  if (!selectEl || !selectEl.options) return false;
  var normList = [];
  for (var i = 0; i < candidates.length; i++) {
    var c = String(candidates[i] || '').trim().toLowerCase();
    if (c) normList.push(c);
  }
  if (normList.length === 0) return false;
  for (var k = 0; k < normList.length; k++) {
    var needle = normList[k];
    for (var j = 0; j < selectEl.options.length; j++) {
      var opt = selectEl.options[j];
      var ov = String(opt.value || '').trim().toLowerCase();
      var ot = String(opt.text || '').trim().toLowerCase();
      if (ov === needle || ot === needle) {
        return setNativeValue(selectEl, opt.value);
      }
    }
  }
  return false;
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
$_nativeValueSetterJsHelper

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

  /// Injects payment card fields ONLY on `https:` top-level pages whose
  /// `window.location.origin` strictly equals [expectedOrigin]. Never touches
  /// CVV/CVC (`cc-csc`) inputs.
  static String buildFillCardScript({
    required String expectedOrigin,
    required String cardNumber,
    required String holderName,
    required int expMonth,
    required int expYear,
  }) {
    final digitsPan = cardNumber.replaceAll(RegExp(r'\D'), '');
    final normalizedYear = expYear < 100 ? 2000 + expYear : expYear;
    final mmPadded = expMonth.clamp(1, 12).toString().padLeft(2, '0');
    final mmUnpadded = expMonth.clamp(1, 12).toString();
    final yy4 = normalizedYear.toString().padLeft(4, '0');
    final yy2 = (normalizedYear % 100).toString().padLeft(2, '0');

    final encodedOrigin = jsonEncode(expectedOrigin);
    final encodedPan = jsonEncode(digitsPan);
    final encodedHolder = jsonEncode(holderName.trim());
    final encodedMmPadded = jsonEncode(mmPadded);
    final encodedMmUnpadded = jsonEncode(mmUnpadded);
    final encodedYy4 = jsonEncode(yy4);
    final encodedYy2 = jsonEncode(yy2);
    final encodedExpCombined = jsonEncode('$mmPadded/$yy2');
    final encodedExpIsoMonth = jsonEncode('$yy4-$mmPadded');

    return '''
(function() {
  try {
    if (typeof window === 'undefined' || window !== window.top) return false;
    if (window.location.protocol !== 'https:') return false;
    if (window.location.origin !== $encodedOrigin) return false;
$_sharedClassifierJsHelpers
$_nativeValueSetterJsHelper

    var focused = window.__theaverLastFocusedInput || document.activeElement;
    var root = (focused && focused.form) ? focused.form : document;
    var ctrls = root.querySelectorAll('input, select');
    var filled = false;

    var holderStr = String($encodedHolder || '').trim();
    var holderParts = holderStr ? holderStr.split(/\\s+/) : [];
    var givenStr = holderParts.length > 0 ? holderParts[0] : '';
    var familyStr = holderParts.length > 1 ? holderParts.slice(1).join(' ') : '';

    for (var i = 0; i < ctrls.length; i++) {
      var el = ctrls[i];
      if (!isVisibleControl(el) || isCscField(el)) continue;
      var tag = (el.tagName || '').toUpperCase();
      var t = tag === 'INPUT' ? (el.getAttribute('type') || 'text').toLowerCase() : '';
      if (t === 'password') continue;

      var ac = (el.getAttribute('autocomplete') || '').toLowerCase();
      var sig = getFieldSignature(el);
      var sub = classifyCardSubtype(el, true);
      if (!sub) continue;

      if (sub === 'cc-number' && $encodedPan) {
        filled = setNativeValue(el, $encodedPan) || filled;
      } else if (sub === 'cc-name' && holderStr) {
        if (hasAcToken(ac, 'cc-given-name') && givenStr) {
          filled = setNativeValue(el, givenStr) || filled;
        } else if (hasAcToken(ac, 'cc-family-name') && familyStr) {
          filled = setNativeValue(el, familyStr) || filled;
        } else {
          filled = setNativeValue(el, holderStr) || filled;
        }
      } else if (sub === 'cc-exp') {
        var expVal = t === 'month' ? $encodedExpIsoMonth : $encodedExpCombined;
        filled = setNativeValue(el, expVal) || filled;
      } else if (sub === 'cc-exp-month') {
        if (tag === 'SELECT') {
          filled = setSelectMatch(el, [$encodedMmPadded, $encodedMmUnpadded]) || filled;
        } else {
          filled = setNativeValue(el, $encodedMmPadded) || filled;
        }
      } else if (sub === 'cc-exp-year') {
        if (tag === 'SELECT') {
          filled = setSelectMatch(el, [$encodedYy4, $encodedYy2]) || filled;
        } else {
          var ml = el.maxLength;
          var useTwo = (ml === 2) || (/\\byy\\b|гг/i.test(sig) && !/yyyy|гггг/i.test(sig));
          filled = setNativeValue(el, useTwo ? $encodedYy2 : $encodedYy4) || filled;
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

  /// Injects address and/or contact fields into matching `<input>`, `<textarea>`,
  /// and `<select>` controls on [expectedOrigin] without overwriting non-empty
  /// unrelated inputs unless empty or currently focused.
  static String buildFillAddressScript({
    required String expectedOrigin,
    String? fullName,
    String? organization,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? region,
    String? postalCode,
    String? country,
    String? phone,
    String? email,
  }) {
    final encodedOrigin = jsonEncode(expectedOrigin);
    final encodedName = jsonEncode((fullName ?? '').trim());
    final encodedOrg = jsonEncode((organization ?? '').trim());
    final encodedLine1 = jsonEncode((addressLine1 ?? '').trim());
    final encodedLine2 = jsonEncode((addressLine2 ?? '').trim());
    final encodedCity = jsonEncode((city ?? '').trim());
    final encodedRegion = jsonEncode((region ?? '').trim());
    final encodedPostal = jsonEncode((postalCode ?? '').trim());
    final encodedCountry = jsonEncode((country ?? '').trim());
    final encodedPhone = jsonEncode((phone ?? '').trim());
    final encodedEmail = jsonEncode((email ?? '').trim());

    return '''
(function() {
  try {
    if (typeof window === 'undefined' || window !== window.top) return false;
    if (window.location.origin !== $encodedOrigin) return false;
$_sharedClassifierJsHelpers
$_nativeValueSetterJsHelper

    var focused = window.__theaverLastFocusedInput || document.activeElement;
    var root = (focused && focused.form) ? focused.form : document;
    var ctrls = root.querySelectorAll('input, textarea, select');
    var filled = false;

    var valuesBySub = {
      'name': $encodedName,
      'organization': $encodedOrg,
      'address-line1': $encodedLine1,
      'address-line2': $encodedLine2,
      'address-level2': $encodedCity,
      'address-level1': $encodedRegion,
      'postal-code': $encodedPostal,
      'country': $encodedCountry,
      'tel': $encodedPhone,
      'email': $encodedEmail
    };

    var nameStr = String($encodedName || '');
    var nameParts = nameStr ? nameStr.split(/\\s+/) : [];
    var givenName = nameParts.length > 0 ? nameParts[0] : '';
    var familyName = nameParts.length > 1 ? nameParts.slice(1).join(' ') : '';

    for (var i = 0; i < ctrls.length; i++) {
      var el = ctrls[i];
      if (!isVisibleControl(el) || isCscField(el)) continue;
      var tag = (el.tagName || '').toUpperCase();
      var t = tag === 'INPUT' ? (el.getAttribute('type') || 'text').toLowerCase() : '';
      if (t === 'password') continue;

      var sub = classifyAddressOrContactSubtype(el);
      if (!sub) continue;

      var targetVal = valuesBySub[sub] || '';
      if (sub === 'name') {
        var ac = (el.getAttribute('autocomplete') || '').toLowerCase();
        var sig = getFieldSignature(el);
        if ((hasAcToken(ac, 'given-name') || /\\bfirst[-_ ]?name\\b|имя/i.test(sig)) &&
            !/full|fio|фио/i.test(sig) && givenName && familyName) {
          targetVal = givenName;
        } else if ((hasAcToken(ac, 'family-name') || /\\blast[-_ ]?name\\b|фамилия/i.test(sig)) &&
            familyName) {
          targetVal = familyName;
        }
      }
      if (!targetVal) continue;

      var curVal = (el.value || '').trim();
      var canOverwrite = (el === focused) || !curVal;
      if (!canOverwrite && tag === 'SELECT' && el.selectedIndex === 0) {
        // Placeholder first option without meaningful value
        canOverwrite = !curVal;
      }
      if (!canOverwrite) continue;

      if (tag === 'SELECT') {
        filled = setSelectMatch(el, [targetVal]) || filled;
      } else {
        filled = setNativeValue(el, targetVal) || filled;
      }
    }
    return filled;
  } catch (_) {
    return false;
  }
})();
''';
  }

  /// Injects contact fields into matching visible controls on [expectedOrigin].
  static String buildFillContactScript({
    required String expectedOrigin,
    String? fullName,
    String? email,
    String? phone,
  }) {
    return buildFillAddressScript(
      expectedOrigin: expectedOrigin,
      fullName: fullName,
      email: email,
      phone: phone,
    );
  }

  /// Injects a numeric OTP [code] into either a 4..8 split-OTP box group or the
  /// active OTP input on [expectedOrigin].
  static String buildFillOtpScript({
    required String expectedOrigin,
    required String code,
  }) {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    final encodedOrigin = jsonEncode(expectedOrigin);
    final encodedDigits = jsonEncode(digits);
    return '''
(function() {
  try {
    if (typeof window === 'undefined' || window !== window.top) return false;
    if (window.location.origin !== $encodedOrigin) return false;
    var digits = String($encodedDigits || '').replace(/\\D/g, '');
    if (!digits) return false;
$_sharedClassifierJsHelpers
$_nativeValueSetterJsHelper

    function dispatchKey(el, type, ch) {
      try {
        el.dispatchEvent(new KeyboardEvent(type, {
          key: ch,
          bubbles: true,
          cancelable: true
        }));
      } catch (_) {
        try {
          el.dispatchEvent(new Event(type, { bubbles: true }));
        } catch (_) {}
      }
    }

    var focused = window.__theaverLastFocusedInput || document.activeElement;
    var splitBoxes = focused ? findSplitOtpGroup(focused) : null;
    if (splitBoxes && splitBoxes.length >= 4 && splitBoxes.length <= 8) {
      var lastFilled = null;
      var count = Math.min(digits.length, splitBoxes.length);
      for (var i = 0; i < count; i++) {
        var box = splitBoxes[i];
        var ch = digits.charAt(i);
        dispatchKey(box, 'keydown', ch);
        setNativeValue(box, ch);
        dispatchKey(box, 'keyup', ch);
        lastFilled = box;
      }
      if (lastFilled && typeof lastFilled.focus === 'function') {
        try { lastFilled.focus(); } catch (_) {}
      }
      return count > 0;
    }

    var target = null;
    if (focused && focused.tagName === 'INPUT' && isVisibleControl(focused) && !isCscField(focused)) {
      target = focused;
    } else {
      var all = document.querySelectorAll('input');
      for (var j = 0; j < all.length; j++) {
        var inp = all[j];
        if (!isVisibleControl(inp) || isCscField(inp)) continue;
        var ac = (inp.getAttribute('autocomplete') || '').toLowerCase();
        var sig = getFieldSignature(inp);
        if (ac.indexOf('one-time-code') !== -1 ||
            /\\b(otp|totp|2fa|passcode)\\b|sms.?code|verif(y|ication).?code|confirm(ation)?.?code|auth.?code|код.*смс|код.*подтвержд|однораз/i.test(sig)) {
          target = inp;
          break;
        }
      }
    }
    if (!target) return false;
    var ok = setNativeValue(target, digits);
    dispatchKey(target, 'keyup', digits.charAt(digits.length - 1));
    return ok;
  } catch (_) {
    return false;
  }
})();
''';
  }
}
