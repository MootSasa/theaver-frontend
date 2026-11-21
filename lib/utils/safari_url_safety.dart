/// Connection security state resolved for the active page or link.
enum SafariConnectionSecurityLevel {
  secureHttps,
  sslCertificateWarning,
  insecureHttp,
  externalScheme,
}

/// Classification of external or restricted URI schemes encountered during
/// web navigation or link activation.
enum ExternalSchemeKind {
  none,
  blocked,
  tel,
  mailto,
  sms,
  telegram,
  appIntent,
  customApp,
}

/// Analyzed host, Punycode decoding, homograph flag, and transport security info.
class SafariHostSafetyInfo {
  final String rawUrl;
  final String scheme;
  final String asciiHost;
  final String unicodeHost;
  final bool isInternationalized;
  final bool isSuspiciousHomograph;
  final SafariConnectionSecurityLevel securityLevel;

  const SafariHostSafetyInfo({
    required this.rawUrl,
    required this.scheme,
    required this.asciiHost,
    required this.unicodeHost,
    required this.isInternationalized,
    required this.isSuspiciousHomograph,
    required this.securityLevel,
  });

  String get displayHost {
    final raw = unicodeHost.isNotEmpty ? unicodeHost : asciiHost;
    return raw.replaceFirst(RegExp(r'^www\.'), '');
  }
}

/// Localized presentation details for an external URI scheme prompt or block.
class SafariExternalSchemeInfo {
  final ExternalSchemeKind kind;
  final String scheme;
  final String title;
  final String message;
  final String confirmLabel;

  const SafariExternalSchemeInfo({
    required this.kind,
    required this.scheme,
    required this.title,
    required this.message,
    required this.confirmLabel,
  });
}

/// Pure-Dart analyzer for Safari-style URL security, Punycode/IDN decoding,
/// mixed-script homograph detection, HTTPS upgrade, and external scheme safety.
abstract final class SafariUrlSafetyAnalyzer {
  static const int _punyBase = 36;
  static const int _punyTMin = 1;
  static const int _punyTMax = 26;
  static const int _punySkew = 38;
  static const int _punyDamp = 700;
  static const int _punyInitialBias = 72;
  static const int _punyInitialN = 0x80;

  static const Set<String> _knownCyrillicTlds = <String>{
    'рф',
    'бел',
    'укр',
    'срб',
    'қаз',
    'бг',
    'мон',
    'мкд',
    'москва',
    'дети',
    'онлайн',
    'орг',
    'сайт',
    'ком',
    'нет',
    'рус',
    'tatar',
  };

  /// Cyrillic code points visually similar to ASCII Latin letters.
  static const Set<int> _cyrillicConfusables = <int>{
    0x0430, // а
    0x0435, // е
    0x043E, // о
    0x0440, // р
    0x0441, // с
    0x0443, // у
    0x0445, // х
    0x0456, // і
    0x0458, // ј
    0x0455, // ѕ
    0x04CF, // ӏ
    0x0432, // в
    0x043A, // к
    0x043C, // м
    0x043D, // н
    0x0442, // т
    0x0410, // А
    0x0412, // В
    0x0415, // Е
    0x041A, // К
    0x041C, // М
    0x041D, // Н
    0x041E, // О
    0x0420, // Р
    0x0421, // С
    0x0422, // Т
    0x0425, // Х
    0x0406, // І
    0x0408, // Ј
    0x0405, // Ѕ
    0x04C0, // Ӏ
  };

  static bool isLoopbackHost(String host) {
    final clean = host.trim().toLowerCase();
    return clean == 'localhost' ||
        clean == '127.0.0.1' ||
        clean == '[::1]' ||
        clean == '::1';
  }

  /// Decodes a dot-separated hostname containing `xn--` Punycode labels
  /// according to RFC 3492. Malformed labels fall back safely to their input.
  static String decodePunycodeHost(String host) {
    final clean = host.trim();
    if (clean.isEmpty || !clean.toLowerCase().contains('xn--')) {
      return clean;
    }
    final labels = clean.split('.');
    return labels.map(_decodePunycodeLabel).join('.');
  }

  static String _decodePunycodeLabel(String label) {
    if (label.length <= 4 || !label.toLowerCase().startsWith('xn--')) {
      return label;
    }
    final encoded = label.substring(4);
    if (encoded.isEmpty) return label;

    final int delim = encoded.lastIndexOf('-');
    final List<int> output = <int>[];
    int inIdx = 0;

    if (delim > 0) {
      for (int j = 0; j < delim; j++) {
        final int code = encoded.codeUnitAt(j);
        if (code >= 0x80) return label;
        output.add(code);
      }
      inIdx = delim + 1;
    }

    int n = _punyInitialN;
    int i = 0;
    int bias = _punyInitialBias;

    while (inIdx < encoded.length) {
      final int oldi = i;
      int w = 1;
      for (int k = _punyBase;; k += _punyBase) {
        if (inIdx >= encoded.length) return label;
        final int digit = _punyDecodeDigit(encoded.codeUnitAt(inIdx++));
        if (digit >= _punyBase) return label;
        i += digit * w;
        final int t = k <= bias
            ? _punyTMin
            : (k >= bias + _punyTMax ? _punyTMax : k - bias);
        if (digit < t) break;
        w *= _punyBase - t;
      }

      final int nextLen = output.length + 1;
      bias = _punyAdapt(i - oldi, nextLen, oldi == 0);
      n += i ~/ nextLen;
      i %= nextLen;
      if (n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF)) {
        return label;
      }
      output.insert(i, n);
      i++;
    }

    return String.fromCharCodes(output);
  }

  static int _punyDecodeDigit(int cp) {
    if (cp - 0x30 < 10) return cp - 0x16; // 0..9 -> 26..35
    if (cp - 0x41 < 26) return cp - 0x41; // A..Z -> 0..25
    if (cp - 0x61 < 26) return cp - 0x61; // a..z -> 0..25
    return _punyBase;
  }

  static int _punyAdapt(int delta, int numPoints, bool firstTime) {
    int d = firstTime ? delta ~/ _punyDamp : delta >> 1;
    d += d ~/ numPoints;
    int k = 0;
    while (d > ((_punyBase - _punyTMin) * _punyTMax) ~/ 2) {
      d ~/= (_punyBase - _punyTMin);
      k += _punyBase;
    }
    return k + (((_punyBase - _punyTMin + 1) * d) ~/ (d + _punySkew));
  }

  static SafariHostSafetyInfo analyzeUrl(
    String rawUrl, {
    bool hasSslWarning = false,
  }) {
    final clean = rawUrl.trim();
    final uri = Uri.tryParse(clean);
    final String scheme = uri?.scheme.toLowerCase() ?? '';
    final String asciiHost = (uri?.host ?? '').trim().toLowerCase();
    final String unicodeHost = decodePunycodeHost(asciiHost);
    final bool hasUnicodeNonAscii =
        unicodeHost.runes.any((r) => r > 0x7F);
    final bool isInternationalized =
        asciiHost.contains('xn--') || hasUnicodeNonAscii;

    final SafariConnectionSecurityLevel level;
    if (scheme == 'https') {
      level = hasSslWarning
          ? SafariConnectionSecurityLevel.sslCertificateWarning
          : SafariConnectionSecurityLevel.secureHttps;
    } else if (scheme == 'http') {
      level = (asciiHost.isEmpty || isLoopbackHost(asciiHost))
          ? SafariConnectionSecurityLevel.secureHttps
          : SafariConnectionSecurityLevel.insecureHttp;
    } else {
      level = SafariConnectionSecurityLevel.externalScheme;
    }

    final bool suspicious =
        _isSuspiciousHomographHost(unicodeHost, asciiHost);

    return SafariHostSafetyInfo(
      rawUrl: clean,
      scheme: scheme,
      asciiHost: asciiHost,
      unicodeHost: unicodeHost,
      isInternationalized: isInternationalized,
      isSuspiciousHomograph: suspicious,
      securityLevel: level,
    );
  }

  static bool _isSuspiciousHomographHost(String unicodeHost, String asciiHost) {
    if (unicodeHost.isEmpty) return false;
    final labels = unicodeHost
        .split('.')
        .where((l) => l.isNotEmpty)
        .toList(growable: false);
    if (labels.isEmpty) return false;

    final String tld = labels.last.toLowerCase();
    final bool isCyrillicTld = _knownCyrillicTlds.contains(tld);

    // Check every label (and if ASCII Punycode failed decoding, remain safe).
    final int checkCount = labels.length > 1 ? labels.length - 1 : labels.length;
    for (int idx = 0; idx < checkCount; idx++) {
      final String label = labels[idx];
      bool hasLatin = false;
      bool hasCyrillic = false;
      bool hasGreek = false;
      bool allCyrillicAreConfusables = true;

      for (final int cp in label.runes) {
        if ((cp >= 0x41 && cp <= 0x5A) || (cp >= 0x61 && cp <= 0x7A)) {
          hasLatin = true;
        } else if (cp >= 0x0400 && cp <= 0x04FF) {
          hasCyrillic = true;
          if (!_cyrillicConfusables.contains(cp)) {
            allCyrillicAreConfusables = false;
          }
        } else if (cp >= 0x0370 && cp <= 0x03FF) {
          hasGreek = true;
        }
      }

      if (hasLatin && (hasCyrillic || hasGreek)) {
        return true;
      }
      if (!isCyrillicTld && hasCyrillic && allCyrillicAreConfusables) {
        return true;
      }
    }

    if (asciiHost != unicodeHost &&
        (tld == 'com' || tld == 'net' || tld == 'org')) {
      // Whole Greek lookalike domain under classic Latin TLDs.
      for (int idx = 0; idx < checkCount; idx++) {
        if (labels[idx].runes.any((cp) => cp >= 0x0370 && cp <= 0x03FF)) {
          return true;
        }
      }
    }
    return false;
  }

  static String _extractOpaqueTarget(Uri uri) {
    final raw = uri.path.isNotEmpty
        ? uri.path
        : uri.toString().replaceFirst(RegExp(r'^[^:]*:'), '');
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  /// Classifies non-HTTP navigation targets for confirmation vs blocking.
  static SafariExternalSchemeInfo classifyExternalUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase().trim();
    final rawLower = uri.toString().trim().toLowerCase();

    if (scheme == 'javascript' ||
        scheme == 'vbscript' ||
        scheme == 'file' ||
        (scheme == 'data' && rawLower.startsWith('data:text/html'))) {
      return SafariExternalSchemeInfo(
        kind: ExternalSchemeKind.blocked,
        scheme: scheme,
        title: 'Переход заблокирован',
        message:
            'Небезопасная схема «$scheme:» заблокирована встроенным браузером.',
        confirmLabel: 'Понятно',
      );
    }

    if (scheme == 'http' || scheme == 'https') {
      return SafariExternalSchemeInfo(
        kind: ExternalSchemeKind.none,
        scheme: scheme,
        title: '',
        message: '',
        confirmLabel: '',
      );
    }

    if (scheme == 'tel') {
      final target = _extractOpaqueTarget(uri);
      return SafariExternalSchemeInfo(
        kind: ExternalSchemeKind.tel,
        scheme: scheme,
        title: 'Позвонить по номеру?',
        message: 'Эта страница хочет совершить вызов на номер $target.',
        confirmLabel: 'Позвонить',
      );
    }

    if (scheme == 'mailto') {
      final target = _extractOpaqueTarget(uri);
      return SafariExternalSchemeInfo(
        kind: ExternalSchemeKind.mailto,
        scheme: scheme,
        title: 'Написать письмо?',
        message: 'Открыть почтовое приложение для адреса $target?',
        confirmLabel: 'Открыть',
      );
    }

    if (scheme == 'sms') {
      final target = _extractOpaqueTarget(uri);
      return SafariExternalSchemeInfo(
        kind: ExternalSchemeKind.sms,
        scheme: scheme,
        title: 'Отправить сообщение?',
        message: 'Открыть приложение SMS для номера $target?',
        confirmLabel: 'Открыть',
      );
    }

    if (scheme == 'tg' || scheme == 'ton') {
      return SafariExternalSchemeInfo(
        kind: ExternalSchemeKind.telegram,
        scheme: scheme,
        title: 'Открыть в другом приложении?',
        message:
            'Эта страница хочет перейти во внешнее приложение ($scheme://).',
        confirmLabel: 'Открыть',
      );
    }

    if (scheme == 'intent' || scheme == 'market') {
      return SafariExternalSchemeInfo(
        kind: ExternalSchemeKind.appIntent,
        scheme: scheme,
        title: 'Открыть внешнее приложение?',
        message:
            'Сайт запрашивает переход в стороннее приложение или магазин приложений.',
        confirmLabel: 'Открыть',
      );
    }

    return SafariExternalSchemeInfo(
      kind: ExternalSchemeKind.customApp,
      scheme: scheme,
      title: 'Открыть в другом приложении?',
      message: 'Эта страница хочет открыть приложение «$scheme».',
      confirmLabel: 'Открыть',
    );
  }

  /// Converts an `http://` URL to `https://` while preserving host, custom
  /// non-80 port, path, query, and fragment.
  static String? tryBuildHttpsUpgrade(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'http') return null;
    if (uri.host.isEmpty) return null;
    return Uri(
      scheme: 'https',
      userInfo: uri.userInfo.isNotEmpty ? uri.userInfo : null,
      host: uri.host,
      port: (uri.hasPort && uri.port != 80) ? uri.port : null,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    ).toString();
  }
}
