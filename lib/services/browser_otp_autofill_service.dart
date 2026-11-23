import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show ChangeNotifier, TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

import 'account_manager.dart';
import 'websocket_service.dart';

/// Ephemeral one-time verification code candidate captured from an incoming
/// chat message, Android SMS User Consent prompt, or desktop/Android clipboard.
class BrowserOtpCandidate {
  final String code;
  final String sourceLabel;
  final String sourceKind;
  final DateTime createdAt;
  final DateTime expiresAt;

  const BrowserOtpCandidate({
    required this.code,
    required this.sourceLabel,
    required this.sourceKind,
    required this.createdAt,
    required this.expiresAt,
  });

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);
}

/// Coordinates OTP detection from incoming chat WebSocket messages, Android SMS
/// User Consent, and privacy-safe clipboard checks for the in-app browser.
class BrowserOtpAutofillService extends ChangeNotifier {
  static const Duration candidateTtl = Duration(minutes: 3);
  static const String _channelName = 'app.theaver.messenger/browser_otp';

  BrowserOtpAutofillService._internal({
    DateTime Function()? clock,
    Stream<WebSocketEvent>? eventStream,
    String? Function()? currentUserIdGetter,
    MethodChannel? methodChannel,
    Future<String?> Function()? clipboardReader,
  })  : _clock = clock ?? DateTime.now,
        _eventStreamOverride = eventStream,
        _currentUserIdGetter = currentUserIdGetter,
        _channel = methodChannel ?? const MethodChannel(_channelName),
        _clipboardReader = clipboardReader;

  static final BrowserOtpAutofillService instance =
      BrowserOtpAutofillService._internal();

  @visibleForTesting
  factory BrowserOtpAutofillService.forTesting({
    DateTime Function()? clock,
    Stream<WebSocketEvent>? eventStream,
    String? Function()? currentUserIdGetter,
    MethodChannel? methodChannel,
    Future<String?> Function()? clipboardReader,
  }) {
    return BrowserOtpAutofillService._internal(
      clock: clock,
      eventStream: eventStream,
      currentUserIdGetter: currentUserIdGetter,
      methodChannel: methodChannel,
      clipboardReader: clipboardReader,
    );
  }

  static final RegExp _contextKeywordRegExp = RegExp(
    r'\b(code|otp|2fa|totp|passcode|verification|verify|confirm(?:ation)?|one[- ]?time)\b|'
    r'код|подтвержд|проверочн|одноразов|авториз|вход',
    caseSensitive: false,
  );

  static final RegExp _adjacentKeywordRegExp = RegExp(
    r'(?:код|code|otp|totp|passcode|pin|2fa)\s*[:=\-–—]?\s*$',
    caseSensitive: false,
  );

  static final RegExp _strictYearLabelRegExp = RegExp(
    r'(?:код|code|otp|totp|passcode|pin)\s*[:=\-–—]\s*$',
    caseSensitive: false,
  );

  static final RegExp _currencySuffixRegExp = RegExp(
    r'^\s*(?:руб\.?|р\.?|rub|usd|eur|kzt|uah|byn|gbp|₽|\$|€|£|₸)(?=$|[\s.,;!?)\]])',
    caseSensitive: false,
  );

  static final RegExp _currencyPrefixRegExp = RegExp(
    r'(?:₽|\$|€|£|usd|eur|rub)\s*$',
    caseSensitive: false,
  );

  static final RegExp _urlRegExp = RegExp(r'https?://\S+', caseSensitive: false);
  static final RegExp _digitSeqRegExp = RegExp(r'\d+');
  static final RegExp _pureOtpRegExp = RegExp(r'^\d{4,8}$');
  static final RegExp _yearRegExp = RegExp(r'^(?:19|20)\d{2}$');

  final DateTime Function() _clock;
  final Stream<WebSocketEvent>? _eventStreamOverride;
  final String? Function()? _currentUserIdGetter;
  final MethodChannel _channel;
  final Future<String?> Function()? _clipboardReader;

  StreamSubscription<WebSocketEvent>? _wsSub;
  int _observerRefCount = 0;
  bool _methodHandlerRegistered = false;
  BrowserOtpCandidate? _candidate;
  bool _showExplicitPasteOtpAction = false;

  /// Current active (unexpired) OTP candidate, or `null` if none or expired.
  BrowserOtpCandidate? get activeCandidate {
    final c = _candidate;
    if (c == null) return null;
    if (c.isExpiredAt(_clock())) {
      _candidate = null;
      return null;
    }
    return c;
  }

  /// Whether the UI should show an explicit user-tappable "Paste OTP" action
  /// instead of reading the system pasteboard automatically (true on iOS).
  bool get showExplicitPasteOtpAction => _showExplicitPasteOtpAction;

  static bool _isWordOrDigitChar(String ch) {
    if (ch.isEmpty) return false;
    final code = ch.codeUnitAt(0);
    if (code >= 0x30 && code <= 0x39) return true; // 0-9
    if (code >= 0x41 && code <= 0x5A) return true; // A-Z
    if (code >= 0x61 && code <= 0x7A) return true; // a-z
    if (code == 0x5F) return true; // _
    if (code >= 0x0400 && code <= 0x04FF) return true; // Cyrillic
    return false;
  }

  static String? _extractOtpCandidate(
    String text, {
    required bool requireContextKeyword,
  }) {
    if (text.trim().isEmpty) return null;
    if (requireContextKeyword && !_contextKeywordRegExp.hasMatch(text)) {
      return null;
    }
    final sanitized = text.replaceAll(_urlRegExp, ' ');
    String? firstFallback;

    for (final match in _digitSeqRegExp.allMatches(sanitized)) {
      final token = match.group(0)!;
      if (token.length < 4 || token.length > 8) continue;

      final start = match.start;
      final end = match.end;
      final beforeChar = start > 0 ? sanitized[start - 1] : '';
      final afterChar = end < sanitized.length ? sanitized[end] : '';

      if (beforeChar.isNotEmpty) {
        if (_isWordOrDigitChar(beforeChar) ||
            beforeChar == '.' ||
            beforeChar == '/' ||
            beforeChar == '+' ||
            beforeChar == r'$' ||
            beforeChar == '€' ||
            beforeChar == '£' ||
            beforeChar == '₽') {
          continue;
        }
        if (beforeChar == '-') {
          // Allow single-letter prefix codes like G-123456 or spaced dash "код - 123456",
          // while rejecting hyphenated numbers/identifiers like "495-1234" or "order-1234".
          final beforeDash = start >= 2 ? sanitized[start - 2] : '';
          final beforeTwo = start >= 3 ? sanitized[start - 3] : '';
          final isSingleLetterPrefix =
              RegExp(r'[A-Za-z]').hasMatch(beforeDash) &&
                  (beforeTwo.isEmpty || !RegExp(r'[A-Za-z0-9]').hasMatch(beforeTwo));
          if (beforeDash.isNotEmpty &&
              beforeDash.trim().isNotEmpty &&
              !isSingleLetterPrefix) {
            continue;
          }
        }
      }

      if (afterChar.isNotEmpty) {
        final bool isDotDecimalOrHost = afterChar == '.' &&
            end + 1 < sanitized.length &&
            _isWordOrDigitChar(sanitized[end + 1]);
        if (_isWordOrDigitChar(afterChar) ||
            isDotDecimalOrHost ||
            afterChar == '/' ||
            afterChar == '%' ||
            afterChar == r'$' ||
            afterChar == '€' ||
            afterChar == '£' ||
            afterChar == '₽') {
          continue;
        }
        if (afterChar == '-' &&
            end + 1 < sanitized.length &&
            _isWordOrDigitChar(sanitized[end + 1])) {
          continue;
        }
      }

      final afterSlice = sanitized.substring(end);
      if (_currencySuffixRegExp.hasMatch(afterSlice)) {
        continue;
      }

      final beforeSlice =
          sanitized.substring(math.max(0, start - 28), start);
      if (_currencyPrefixRegExp.hasMatch(beforeSlice)) {
        continue;
      }

      if (_yearRegExp.hasMatch(token) &&
          !_strictYearLabelRegExp.hasMatch(beforeSlice)) {
        continue;
      }

      if (_adjacentKeywordRegExp.hasMatch(beforeSlice)) {
        return token;
      }
      firstFallback ??= token;
    }

    return firstFallback;
  }

  /// Extracts a standalone 4..8 digit verification code from message [text]
  /// when verification keywords are present, ignoring URLs, currency amounts,
  /// and standalone years `19xx`/`20xx` unless explicitly prefixed (`код:`/`code:`).
  static String? extractOtpFromMessageText(String text) {
    return _extractOtpCandidate(text, requireContextKeyword: true);
  }

  /// Returns trimmed [raw] only if it consists purely of 4..8 digits.
  static String? extractPureClipboardOtp(String raw) {
    final trimmed = raw.trim();
    if (_pureOtpRegExp.hasMatch(trimmed)) {
      return trimmed;
    }
    return null;
  }

  void _ensureMethodHandlerRegistered() {
    if (_methodHandlerRegistered || kIsWeb) return;
    _methodHandlerRegistered = true;
    try {
      _channel.setMethodCallHandler((MethodCall call) async {
        if (call.method == 'onSmsReceived') {
          final args = call.arguments;
          final message =
              args is Map ? (args['message']?.toString() ?? '') : '';
          _handleIncomingSms(message);
        }
      });
    } catch (_) {}
  }

  void _handleIncomingSms(String message) {
    if (message.trim().isEmpty) return;
    final code = extractOtpFromMessageText(message) ??
        _extractOtpCandidate(message, requireContextKeyword: false);
    if (code == null) return;
    _setCandidate(
      code: code,
      sourceLabel: 'SMS',
      sourceKind: 'sms',
    );
  }

  /// Reference-counted subscription to incoming WebSocket messages while an
  /// in-app browser sheet is open.
  void attachBrowserObserver() {
    _ensureMethodHandlerRegistered();
    _observerRefCount += 1;
    if (_wsSub != null) return;
    try {
      final stream = _eventStreamOverride ?? WebSocketService().eventStream;
      _wsSub = stream.listen(_handleWsEvent, onError: (_) {});
    } catch (_) {}
  }

  /// Decrements the active browser observer count and closes the WebSocket
  /// subscription when zero.
  void detachBrowserObserver() {
    if (_observerRefCount > 0) {
      _observerRefCount -= 1;
    }
    if (_observerRefCount == 0) {
      _wsSub?.cancel();
      _wsSub = null;
    }
  }

  String? _resolveCurrentUserId() {
    if (_currentUserIdGetter != null) {
      return _currentUserIdGetter!.call();
    }
    try {
      final accUid = AccountManager().currentAccount?.userId;
      if (accUid != null && accUid.trim().isNotEmpty) {
        return accUid.trim();
      }
    } catch (_) {}
    try {
      final wsUid = WebSocketService().currentUserId;
      if (wsUid != null && wsUid.trim().isNotEmpty) {
        return wsUid.trim();
      }
    } catch (_) {}
    return null;
  }

  void _handleWsEvent(WebSocketEvent event) {
    final isMessageEvent = event.type == WebSocketEventType.newMessage ||
        event.rawType == 'new_message' ||
        event.rawType == 'message';
    if (!isMessageEvent) return;

    final rawMsg = event.data['message'];
    final Map<dynamic, dynamic> msgMap =
        rawMsg is Map ? rawMsg : event.data;

    final senderId =
        (msgMap['sender_id'] ?? event.data['sender_id'] ?? '').toString().trim();
    final myUid = _resolveCurrentUserId()?.trim();
    if (myUid != null &&
        myUid.isNotEmpty &&
        senderId.isNotEmpty &&
        senderId == myUid) {
      return;
    }

    final text = (msgMap['content'] ??
            msgMap['text'] ??
            event.data['content'] ??
            event.data['text'] ??
            '')
        .toString();
    final code = extractOtpFromMessageText(text);
    if (code == null) return;

    final senderName =
        (msgMap['sender_name'] ?? event.data['sender_name'] ?? '')
            .toString()
            .trim();
    final label = senderName.isNotEmpty ? 'Чат: $senderName' : 'Чат';
    _setCandidate(
      code: code,
      sourceLabel: label,
      sourceKind: 'chat',
    );
  }

  Future<String?> _readClipboardText() async {
    if (_clipboardReader != null) {
      try {
        return await _clipboardReader!.call();
      } catch (_) {
        return null;
      }
    }
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text;
    } catch (_) {
      return null;
    }
  }

  /// Called when an OTP input field gains focus in the browser.
  ///
  /// Starts Android SMS User Consent on Android, checks pure-digit clipboard OTP
  /// ONLY on Android & Desktop (never automatically on iOS to avoid iOS 16+
  /// paste banners), and exposes [showExplicitPasteOtpAction] on iOS.
  Future<void> onOtpFieldFocused({bool? isIosPlatform}) async {
    final bool isIos = isIosPlatform ??
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
    final bool isAndroid = !isIos &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android;

    if (_showExplicitPasteOtpAction != isIos) {
      _showExplicitPasteOtpAction = isIos;
      notifyListeners();
    }

    if (isAndroid) {
      _ensureMethodHandlerRegistered();
      try {
        await _channel.invokeMethod<bool>('startSmsConsent');
      } on MissingPluginException {
        // Unsupported runtime / unit test without platform handler.
      } on PlatformException {
        // GMS unavailable (e.g. Huawei / AOSP) — degrade gracefully.
      } catch (_) {}
    }

    if (!isIos) {
      final clipRaw = await _readClipboardText();
      if (clipRaw != null) {
        final clipOtp = extractPureClipboardOtp(clipRaw);
        if (clipOtp != null) {
          final current = activeCandidate;
          if (current == null || current.sourceKind == 'clipboard') {
            _setCandidate(
              code: clipOtp,
              sourceLabel: 'Буфер обмена',
              sourceKind: 'clipboard',
            );
          }
        }
      }
    }
  }

  /// Reads an OTP from the system clipboard on an explicit user tap.
  Future<String?> readOtpFromClipboardByUserTap() async {
    final clipRaw = await _readClipboardText();
    if (clipRaw == null || clipRaw.trim().isEmpty) return null;
    final code = extractPureClipboardOtp(clipRaw) ??
        extractOtpFromMessageText(clipRaw);
    if (code == null) return null;
    _setCandidate(
      code: code,
      sourceLabel: 'Буфер обмена',
      sourceKind: 'clipboard',
    );
    return code;
  }

  void _setCandidate({
    required String code,
    required String sourceLabel,
    required String sourceKind,
    DateTime? now,
  }) {
    final ts = now ?? _clock();
    _candidate = BrowserOtpCandidate(
      code: code,
      sourceLabel: sourceLabel,
      sourceKind: sourceKind,
      createdAt: ts,
      expiresAt: ts.add(candidateTtl),
    );
    notifyListeners();
  }

  /// Seeds an OTP candidate directly for unit and widget tests.
  @visibleForTesting
  void setCandidateForTesting(
    String code, {
    String sourceLabel = 'SMS',
    String sourceKind = 'sms',
    DateTime? now,
  }) {
    _setCandidate(
      code: code,
      sourceLabel: sourceLabel,
      sourceKind: sourceKind,
      now: now,
    );
  }

  /// Clears the active candidate after it has been filled or dismissed.
  void consumeCandidate() {
    if (_candidate == null) return;
    _candidate = null;
    notifyListeners();
  }

  /// Clears all transient OTP state when switching Theaver accounts.
  void clearOnAccountSwitch() {
    final hadState = _candidate != null || _showExplicitPasteOtpAction;
    _candidate = null;
    _showExplicitPasteOtpAction = false;
    if (hadState) {
      notifyListeners();
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _wsSub?.cancel();
    _wsSub = null;
    _observerRefCount = 0;
    _candidate = null;
    _showExplicitPasteOtpAction = false;
  }
}
