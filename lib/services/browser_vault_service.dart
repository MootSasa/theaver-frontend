import 'dart:convert';
import 'dart:math';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart'
    show ChangeNotifier, Uint8List, visibleForTesting;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../utils/safari_url_safety.dart';
import 'account_manager.dart';
import 'browser_vault_auth_gate.dart';

/// Non-secret credential index entry kept in memory so the browser can detect
/// matching logins for an origin without decrypting passwords prior to auth.
class BrowserCredentialHint {
  final String id;
  final String origin;
  final String asciiHost;
  final String displayHost;
  final String username;
  final bool isHttpAuth;
  final String realm;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;

  const BrowserCredentialHint({
    required this.id,
    required this.origin,
    required this.asciiHost,
    required this.displayHost,
    required this.username,
    this.isHttpAuth = false,
    this.realm = '',
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
  });

  BrowserCredentialHint copyWith({
    String? username,
    String? realm,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
  }) {
    return BrowserCredentialHint(
      id: id,
      origin: origin,
      asciiHost: asciiHost,
      displayHost: displayHost,
      username: username ?? this.username,
      isHttpAuth: isHttpAuth,
      realm: realm ?? this.realm,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'origin': origin,
        'asciiHost': asciiHost,
        'displayHost': displayHost,
        'username': username,
        'isHttpAuth': isHttpAuth,
        'realm': realm,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
      };

  factory BrowserCredentialHint.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return BrowserCredentialHint(
      id: json['id']?.toString() ?? '',
      origin: json['origin']?.toString() ?? '',
      asciiHost: json['asciiHost']?.toString() ?? '',
      displayHost: json['displayHost']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      isHttpAuth: json['isHttpAuth'] == true,
      realm: json['realm']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
      lastUsedAt: DateTime.tryParse(json['lastUsedAt']?.toString() ?? ''),
    );
  }
}

/// Decrypted browser credential returned ONLY after passing [BrowserVaultAuthGate].
class BrowserSavedCredential {
  final BrowserCredentialHint hint;
  final String password;

  const BrowserSavedCredential({
    required this.hint,
    required this.password,
  });

  String get id => hint.id;
  String get origin => hint.origin;
  String get asciiHost => hint.asciiHost;
  String get displayHost => hint.displayHost;
  String get username => hint.username;
  bool get isHttpAuth => hint.isHttpAuth;
  String get realm => hint.realm;
}

/// User contact profile offered as 1-tap autofill on non-password web forms.
class BrowserContactProfile {
  final String fullName;
  final String email;
  final String phone;
  final bool enabled;

  const BrowserContactProfile({
    this.fullName = '',
    this.email = '',
    this.phone = '',
    this.enabled = true,
  });

  bool get hasAnyField =>
      fullName.trim().isNotEmpty ||
      email.trim().isNotEmpty ||
      phone.trim().isNotEmpty;

  BrowserContactProfile copyWith({
    String? fullName,
    String? email,
    String? phone,
    bool? enabled,
  }) {
    return BrowserContactProfile(
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'enabled': enabled,
      };

  factory BrowserContactProfile.fromJson(Map<String, dynamic> json) {
    return BrowserContactProfile(
      fullName: json['fullName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      enabled: json['enabled'] != false,
    );
  }

  /// Builds contact autofill defaults from the active Theaver [Account].
  static BrowserContactProfile fromCurrentAccount() {
    try {
      final acc = AccountManager().currentAccount;
      if (acc == null) return const BrowserContactProfile();
      final parts = <String>[
        if ((acc.name ?? '').trim().isNotEmpty) acc.name!.trim(),
        if ((acc.surname ?? '').trim().isNotEmpty) acc.surname!.trim(),
      ];
      final fullName = parts.isNotEmpty
          ? parts.join(' ')
          : ((acc.displayName ?? '').trim().isNotEmpty
              ? acc.displayName!.trim()
              : (acc.username ?? '').trim());
      return BrowserContactProfile(
        fullName: fullName,
        email: (acc.email ?? '').trim(),
        phone: (acc.phone ?? '').trim(),
        enabled: true,
      );
    } catch (_) {
      return const BrowserContactProfile();
    }
  }
}

enum BrowserVaultSaveStatus {
  ignoredEmpty,
  ignoredNeverSave,
  ignoredSuspiciousOrigin,
  newCredential,
  updatePassword,
  alreadyUpToDate,
}

class BrowserVaultSaveEvaluation {
  final BrowserVaultSaveStatus status;
  final String? existingId;
  final String? normalizedOrigin;
  final String? displayHost;

  const BrowserVaultSaveEvaluation({
    required this.status,
    this.existingId,
    this.normalizedOrigin,
    this.displayHost,
  });
}

/// Encrypted AES-256-GCM browser credential vault & contact autofill storage,
/// strictly scoped per active Theaver account (`u_<userId>`).
class BrowserVaultService extends ChangeNotifier {
  BrowserVaultService._internal({
    FlutterSecureStorage? secureStorage,
    BrowserVaultAuthGate? authGate,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _authGate = authGate ?? BrowserVaultAuthGate.instance;

  static final BrowserVaultService instance = BrowserVaultService._internal();

  /// Test-only isolated instance with injected dependencies.
  @visibleForTesting
  factory BrowserVaultService.forTesting({
    FlutterSecureStorage? secureStorage,
    BrowserVaultAuthGate? authGate,
    Map<String, String>? secureStore,
    String? userId,
  }) {
    return BrowserVaultService._internal(
      secureStorage: secureStorage,
      authGate: authGate,
    )
      ..debugSecureStoreOverride = secureStore ?? <String, String>{}
      ..debugUserIdOverride = userId;
  }

  static const String _cipherPrefix = 'v1:';
  static const String _masterKeyPrefix = 'browser_vault_mk_u_';
  static const String _indexKeyPrefix = 'browser_vault_index_v1_u_';
  static const String _secretKeyPrefix = 'browser_vault_secret_v1_u_';
  static const String _contactKeyPrefix = 'browser_vault_contact_v1_u_';

  final FlutterSecureStorage _secureStorage;
  BrowserVaultAuthGate _authGate;
  final Random _secureRandom = Random.secure();
  final Uuid _uuid = const Uuid();
  final Map<String, String> _fallbackKeyStore = <String, String>{};

  @visibleForTesting
  Map<String, String>? debugSecureStoreOverride;

  @visibleForTesting
  String? debugUserIdOverride;

  @visibleForTesting
  set debugAuthGate(BrowserVaultAuthGate gate) => _authGate = gate;

  List<BrowserCredentialHint> _hints = <BrowserCredentialHint>[];
  List<String> _neverSaveOrigins = <String>[];
  String? _loadedUserId;

  List<BrowserCredentialHint> get hints => List.unmodifiable(_hints);
  List<String> get neverSaveOrigins => List.unmodifiable(_neverSaveOrigins);

  /// Returns the normalized active user identifier (`guest` if signed out).
  String get activeAccountUserId {
    if (debugUserIdOverride != null && debugUserIdOverride!.trim().isNotEmpty) {
      return debugUserIdOverride!.trim();
    }
    try {
      final uid = AccountManager().currentAccount?.userId;
      if (uid != null && uid.trim().isNotEmpty) return uid.trim();
    } catch (_) {}
    return 'guest';
  }

  /// Normalizes [rawUrl] to canonical `scheme://asciiHost[:nonDefaultPort]`.
  /// Returns `null` if not an `http` or `https` URL with a valid host.
  static String? normalizeOrigin(String rawUrl) {
    final clean = rawUrl.trim();
    if (clean.isEmpty) return null;
    final uri = Uri.tryParse(clean);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    final safety = SafariUrlSafetyAnalyzer.analyzeUrl(clean);
    final host = safety.asciiHost.isNotEmpty
        ? safety.asciiHost.toLowerCase()
        : uri.host.trim().toLowerCase();
    if (host.isEmpty) return null;
    final String portPart;
    if (uri.hasPort &&
        !((scheme == 'https' && uri.port == 443) ||
            (scheme == 'http' && uri.port == 80))) {
      portPart = ':${uri.port}';
    } else {
      portPart = '';
    }
    return '$scheme://$host$portPart';
  }

  static String _displayHostForUrl(String rawUrl) {
    final safety = SafariUrlSafetyAnalyzer.analyzeUrl(rawUrl);
    if (safety.displayHost.isNotEmpty) return safety.displayHost;
    final uri = Uri.tryParse(rawUrl.trim());
    return (uri?.host ?? rawUrl.trim()).replaceFirst(RegExp(r'^www\.'), '');
  }

  static String _asciiHostForUrl(String rawUrl) {
    final safety = SafariUrlSafetyAnalyzer.analyzeUrl(rawUrl);
    if (safety.asciiHost.isNotEmpty) return safety.asciiHost.toLowerCase();
    return (Uri.tryParse(rawUrl.trim())?.host ?? '').toLowerCase();
  }

  Future<String?> _readSecureKey(String key) async {
    final override = debugSecureStoreOverride;
    if (override != null) return override[key];
    try {
      return await _secureStorage.read(key: key);
    } on MissingPluginException {
      return _fallbackKeyStore[key];
    } on UnimplementedError {
      return _fallbackKeyStore[key];
    }
  }

  Future<void> _writeSecureKey(String key, String value) async {
    final override = debugSecureStoreOverride;
    if (override != null) {
      override[key] = value;
      return;
    }
    try {
      await _secureStorage.write(key: key, value: value);
    } on MissingPluginException {
      _fallbackKeyStore[key] = value;
    } on UnimplementedError {
      _fallbackKeyStore[key] = value;
    }
  }

  Future<void> _deleteSecureKey(String key) async {
    final override = debugSecureStoreOverride;
    if (override != null) {
      override.remove(key);
      return;
    }
    try {
      await _secureStorage.delete(key: key);
    } on MissingPluginException {
      _fallbackKeyStore.remove(key);
    } on UnimplementedError {
      _fallbackKeyStore.remove(key);
    }
  }

  /// Returns the 256-bit hardware-backed master key for [userId], creating one
  /// on first use via `Random.secure()`.
  Future<Uint8List> getOrCreateAccountMasterKey(String userId) async {
    final storageKey = '$_masterKeyPrefix$userId';
    final existingB64 = await _readSecureKey(storageKey);
    if (existingB64 != null && existingB64.isNotEmpty) {
      try {
        final decoded = base64Decode(existingB64);
        if (decoded.length == 32) {
          return Uint8List.fromList(decoded);
        }
      } catch (_) {}
    }
    final generated = Uint8List(32);
    for (int i = 0; i < generated.length; i++) {
      generated[i] = _secureRandom.nextInt(256);
    }
    await _writeSecureKey(storageKey, base64Encode(generated));
    return generated;
  }

  /// Deletes the per-account 256-bit master key from secure storage.
  Future<void> deleteAccountMasterKey(String userId) =>
      _deleteSecureKey('$_masterKeyPrefix$userId');

  /// Encrypts [plainText] using AES-256-GCM with a fresh random 96-bit IV.
  String encryptWithMasterKey(Uint8List keyBytes, String plainText) {
    final ivBytes = Uint8List(12);
    for (int i = 0; i < ivBytes.length; i++) {
      ivBytes[i] = _secureRandom.nextInt(256);
    }
    final key = encrypt.Key(keyBytes);
    final iv = encrypt.IV(ivBytes);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.gcm),
    );
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '$_cipherPrefix${base64Encode(ivBytes)}:${encrypted.base64}';
  }

  /// Decrypts an `AES-256-GCM` payload produced by [encryptWithMasterKey].
  String decryptWithMasterKey(Uint8List keyBytes, String payload) {
    if (!payload.startsWith(_cipherPrefix)) {
      throw const FormatException('Unsupported browser vault payload format');
    }
    final rest = payload.substring(_cipherPrefix.length);
    final sep = rest.indexOf(':');
    if (sep <= 0) {
      throw const FormatException('Malformed browser vault ciphertext');
    }
    final ivBytes = base64Decode(rest.substring(0, sep));
    final cipherB64 = rest.substring(sep + 1);
    final key = encrypt.Key(keyBytes);
    final iv = encrypt.IV(ivBytes);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.gcm),
    );
    return encrypter.decrypt64(cipherB64, iv: iv);
  }

  Future<void> ensureLoaded({bool forceReload = false}) async {
    final uid = activeAccountUserId;
    if (!forceReload && _loadedUserId == uid) return;
    _loadedUserId = uid;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_indexKeyPrefix$uid');
      if (raw == null || raw.isEmpty) {
        _hints = <BrowserCredentialHint>[];
        _neverSaveOrigins = <String>[];
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final rawHints = decoded['hints'];
          if (rawHints is List) {
            _hints = rawHints
                .whereType<Map>()
                .map(
                  (e) => BrowserCredentialHint.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .where((h) => h.id.isNotEmpty && h.origin.isNotEmpty)
                .toList();
          } else {
            _hints = <BrowserCredentialHint>[];
          }
          final rawNever = decoded['neverSaveOrigins'];
          if (rawNever is List) {
            _neverSaveOrigins = rawNever
                .map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList();
          } else {
            _neverSaveOrigins = <String>[];
          }
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveIndex(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_indexKeyPrefix$uid',
        jsonEncode(<String, dynamic>{
          'hints': _hints.map((h) => h.toJson()).toList(),
          'neverSaveOrigins': _neverSaveOrigins,
        }),
      );
    } catch (_) {}
  }

  String _secretPrefsKey(String uid, String credId) =>
      '$_secretKeyPrefix${uid}_$credId';

  static const Set<String> _multiLabelSuffixes = <String>{
    'co.uk',
    'org.uk',
    'gov.uk',
    'ac.uk',
    'net.uk',
    'com.au',
    'net.au',
    'org.au',
    'co.jp',
    'ne.jp',
    'or.jp',
    'com.br',
    'com.tr',
    'com.cn',
    'com.ua',
    'co.za',
    'co.kr',
    'com.mx',
    'co.in',
    'net.ru',
    'com.ru',
    'org.ru',
    'github.io',
    'gitlab.io',
    'pages.dev',
    'vercel.app',
    'netlify.app',
    'herokuapp.com',
    'appspot.com',
  };

  static final RegExp _ipv4RegExp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  static String? _registrableBaseDomain(String host) {
    final clean = host.trim().toLowerCase();
    if (clean.isEmpty ||
        clean == 'localhost' ||
        clean.contains(':') ||
        _ipv4RegExp.hasMatch(clean)) {
      return null;
    }
    final labels = clean.split('.').where((l) => l.isNotEmpty).toList();
    if (labels.length < 2) return null;
    if (labels.length >= 3) {
      final lastTwo = '${labels[labels.length - 2]}.${labels.last}';
      if (_multiLabelSuffixes.contains(lastTwo)) {
        return '${labels[labels.length - 3]}.$lastTwo';
      }
    }
    return '${labels[labels.length - 2]}.${labels.last}';
  }

  static bool _hostsShareRegistrableDomain(String a, String b) {
    if (a == b) return true;
    final baseA = _registrableBaseDomain(a);
    final baseB = _registrableBaseDomain(b);
    if (baseA != null && baseB != null && baseA == baseB) {
      return true;
    }
    if (baseB != null && b == baseB && a.endsWith('.$b')) return true;
    if (baseA != null && a == baseA && b.endsWith('.$a')) return true;
    return false;
  }

  static int _effectivePortFor(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }

  /// Returns non-secret credential hints matching [rawUrl], prioritizing exact
  /// normalized origin (`scheme://asciiHost[:port]`) matches first, followed by
  /// same-scheme, same-port registrable/base-domain matches (so `www.example.com`
  /// and `login.example.com` find `example.com` logins cleanly).
  ///
  /// Never returns `https://` hints for `http://` pages, different ports, or
  /// homograph-flagged domains.
  List<BrowserCredentialHint> getHintsForUrl(
    String rawUrl, {
    bool isHttpAuth = false,
    String? realm,
    bool includeSubdomains = true,
  }) {
    final safety = SafariUrlSafetyAnalyzer.analyzeUrl(rawUrl);
    if (safety.isSuspiciousHomograph) return const <BrowserCredentialHint>[];
    final origin = normalizeOrigin(rawUrl);
    if (origin == null) return const <BrowserCredentialHint>[];
    final targetUri = Uri.tryParse(origin);
    if (targetUri == null) return const <BrowserCredentialHint>[];
    final targetScheme = targetUri.scheme.toLowerCase();
    final targetHost = targetUri.host.toLowerCase();
    final targetPort = _effectivePortFor(targetUri);
    final cleanRealm = realm?.trim() ?? '';

    bool matchesRealm(BrowserCredentialHint h) {
      if (h.isHttpAuth != isHttpAuth) return false;
      if (isHttpAuth && cleanRealm.isNotEmpty && h.realm.isNotEmpty) {
        return h.realm == cleanRealm;
      }
      return true;
    }

    int compareRecency(BrowserCredentialHint a, BrowserCredentialHint b) {
      final aTs = a.lastUsedAt ?? a.updatedAt;
      final bTs = b.lastUsedAt ?? b.updatedAt;
      return bTs.compareTo(aTs);
    }

    final exactMatches = <BrowserCredentialHint>[];
    final relatedMatches = <BrowserCredentialHint>[];

    for (final h in _hints) {
      if (!matchesRealm(h)) continue;
      if (h.origin == origin) {
        exactMatches.add(h);
        continue;
      }
      if (!includeSubdomains) continue;
      final credUri = Uri.tryParse(h.origin);
      if (credUri == null) continue;
      if (credUri.scheme.toLowerCase() != targetScheme) continue;
      if (_effectivePortFor(credUri) != targetPort) continue;
      if (SafariUrlSafetyAnalyzer.analyzeUrl(h.origin).isSuspiciousHomograph) {
        continue;
      }
      final credHost = credUri.host.toLowerCase();
      if (_hostsShareRegistrableDomain(targetHost, credHost)) {
        relatedMatches.add(h);
      }
    }

    exactMatches.sort(compareRecency);
    relatedMatches.sort(compareRecency);
    return List<BrowserCredentialHint>.unmodifiable(
      <BrowserCredentialHint>[...exactMatches, ...relatedMatches],
    );
  }

  bool isNeverSaveUrl(String rawUrl) {
    final origin = normalizeOrigin(rawUrl);
    if (origin == null) return false;
    return _neverSaveOrigins.contains(origin);
  }

  Future<String?> _readDecryptedPasswordRaw(String uid, BrowserCredentialHint hint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString(_secretPrefsKey(uid, hint.id));
      if (payload == null || payload.isEmpty) return null;
      final keyBytes = await getOrCreateAccountMasterKey(uid);
      final plainJson = decryptWithMasterKey(keyBytes, payload);
      final map = jsonDecode(plainJson);
      if (map is! Map) return null;
      if (map['id']?.toString() != hint.id ||
          map['origin']?.toString() != hint.origin) {
        return null;
      }
      return map['password']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Decrypts and returns a single credential after passing [BrowserVaultAuthGate].
  Future<BrowserSavedCredential?> unlockAndReadCredential(
    BuildContext context,
    String id, {
    required String reason,
    String? originScope,
  }) async {
    await ensureLoaded();
    if (!context.mounted) return null;
    final uid = activeAccountUserId;
    final idx = _hints.indexWhere((h) => h.id == id);
    if (idx < 0) return null;
    final hint = _hints[idx];

    final effectiveScope = originScope ?? hint.origin;
    final ok = await _authGate.authenticate(
      context,
      reason: reason,
      originScope: effectiveScope,
    );
    if (!ok) return null;

    final password = await _readDecryptedPasswordRaw(uid, hint);
    if (password == null) return null;

    final updated = hint.copyWith(lastUsedAt: DateTime.now());
    _hints[idx] = updated;
    await _saveIndex(uid);
    notifyListeners();
    return BrowserSavedCredential(hint: updated, password: password);
  }

  /// Authenticates via [BrowserVaultAuthGate] and decrypts all saved credentials
  /// for management in Settings.
  Future<List<BrowserSavedCredential>?> unlockAndReadAllCredentials(
    BuildContext context, {
    required String reason,
  }) async {
    await ensureLoaded();
    if (!context.mounted) return null;
    final ok = await _authGate.authenticate(context, reason: reason);
    if (!ok) return null;

    final uid = activeAccountUserId;
    final results = <BrowserSavedCredential>[];
    for (final hint in _hints) {
      final pass = await _readDecryptedPasswordRaw(uid, hint);
      if (pass != null) {
        results.add(BrowserSavedCredential(hint: hint, password: pass));
      }
    }
    return results;
  }

  /// Evaluates a captured form submission against the vault without exposing
  /// stored plaintext passwords.
  Future<BrowserVaultSaveEvaluation> inspectCandidate({
    required String url,
    required String username,
    required String password,
    bool isHttpAuth = false,
    String? realm,
  }) async {
    await ensureLoaded();
    if (password.isEmpty) {
      return const BrowserVaultSaveEvaluation(
        status: BrowserVaultSaveStatus.ignoredEmpty,
      );
    }
    final safety = SafariUrlSafetyAnalyzer.analyzeUrl(url);
    if (safety.isSuspiciousHomograph) {
      return const BrowserVaultSaveEvaluation(
        status: BrowserVaultSaveStatus.ignoredSuspiciousOrigin,
      );
    }
    final origin = normalizeOrigin(url);
    if (origin == null) {
      return const BrowserVaultSaveEvaluation(
        status: BrowserVaultSaveStatus.ignoredEmpty,
      );
    }
    if (_neverSaveOrigins.contains(origin)) {
      return BrowserVaultSaveEvaluation(
        status: BrowserVaultSaveStatus.ignoredNeverSave,
        normalizedOrigin: origin,
      );
    }

    final cleanUser = username.trim();
    final cleanRealm = realm?.trim() ?? '';
    final uid = activeAccountUserId;
    final existingIdx = _hints.indexWhere(
      (h) =>
          h.origin == origin &&
          h.isHttpAuth == isHttpAuth &&
          h.username.toLowerCase() == cleanUser.toLowerCase() &&
          (!isHttpAuth || cleanRealm.isEmpty || h.realm == cleanRealm || h.realm.isEmpty),
    );
    final displayHost = _displayHostForUrl(url);
    if (existingIdx < 0) {
      return BrowserVaultSaveEvaluation(
        status: BrowserVaultSaveStatus.newCredential,
        normalizedOrigin: origin,
        displayHost: displayHost,
      );
    }

    final existingHint = _hints[existingIdx];
    final currentSecret = await _readDecryptedPasswordRaw(uid, existingHint);
    if (currentSecret == password) {
      return BrowserVaultSaveEvaluation(
        status: BrowserVaultSaveStatus.alreadyUpToDate,
        existingId: existingHint.id,
        normalizedOrigin: origin,
        displayHost: displayHost,
      );
    }
    return BrowserVaultSaveEvaluation(
      status: BrowserVaultSaveStatus.updatePassword,
      existingId: existingHint.id,
      normalizedOrigin: origin,
      displayHost: displayHost,
    );
  }

  /// Encrypts and persists a new or updated credential into the active account vault.
  Future<BrowserCredentialHint> saveOrUpdateCredential({
    required String url,
    required String username,
    required String password,
    bool isHttpAuth = false,
    String? realm,
    String? existingId,
  }) async {
    await ensureLoaded();
    final origin = normalizeOrigin(url);
    if (origin == null) {
      throw ArgumentError('Invalid browser credential URL: $url');
    }
    if (password.isEmpty) {
      throw ArgumentError('Password must not be empty');
    }

    final uid = activeAccountUserId;
    final cleanUser = username.trim();
    final cleanRealm = realm?.trim() ?? '';
    final asciiHost = _asciiHostForUrl(url);
    final displayHost = _displayHostForUrl(url);
    final now = DateTime.now();

    int matchIdx = existingId != null
        ? _hints.indexWhere((h) => h.id == existingId)
        : -1;
    if (matchIdx < 0) {
      matchIdx = _hints.indexWhere(
        (h) =>
            h.origin == origin &&
            h.isHttpAuth == isHttpAuth &&
            h.username.toLowerCase() == cleanUser.toLowerCase(),
      );
    }

    final BrowserCredentialHint savedHint;
    if (matchIdx >= 0) {
      savedHint = _hints[matchIdx].copyWith(
        username: cleanUser,
        realm: cleanRealm.isNotEmpty ? cleanRealm : _hints[matchIdx].realm,
        updatedAt: now,
        lastUsedAt: now,
      );
      _hints[matchIdx] = savedHint;
    } else {
      savedHint = BrowserCredentialHint(
        id: _uuid.v4(),
        origin: origin,
        asciiHost: asciiHost,
        displayHost: displayHost,
        username: cleanUser,
        isHttpAuth: isHttpAuth,
        realm: cleanRealm,
        createdAt: now,
        updatedAt: now,
        lastUsedAt: now,
      );
      _hints.insert(0, savedHint);
    }

    // Encrypt secret payload with per-account AES-256-GCM key.
    final keyBytes = await getOrCreateAccountMasterKey(uid);
    final encryptedSecret = encryptWithMasterKey(
      keyBytes,
      jsonEncode(<String, dynamic>{
        'id': savedHint.id,
        'origin': savedHint.origin,
        'username': savedHint.username,
        'password': password,
      }),
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_secretPrefsKey(uid, savedHint.id), encryptedSecret);
    _neverSaveOrigins.remove(origin);
    await _saveIndex(uid);
    notifyListeners();
    return savedHint;
  }

  Future<void> deleteCredential(String id) async {
    await ensureLoaded();
    final uid = activeAccountUserId;
    final removed = _hints.where((h) => h.id == id).toList();
    if (removed.isEmpty) return;
    _hints.removeWhere((h) => h.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_secretPrefsKey(uid, id));
    await _saveIndex(uid);
    notifyListeners();
  }

  Future<void> markNeverSaveForUrl(String url) async {
    await ensureLoaded();
    final origin = normalizeOrigin(url);
    if (origin == null) return;
    if (!_neverSaveOrigins.contains(origin)) {
      _neverSaveOrigins.insert(0, origin);
      await _saveIndex(activeAccountUserId);
      notifyListeners();
    }
  }

  Future<void> removeNeverSaveOrigin(String origin) async {
    await ensureLoaded();
    if (_neverSaveOrigins.remove(origin.trim())) {
      await _saveIndex(activeAccountUserId);
      notifyListeners();
    }
  }

  Future<BrowserContactProfile> getContactProfile() async {
    await ensureLoaded();
    final uid = activeAccountUserId;
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString('$_contactKeyPrefix$uid');
      if (payload == null || payload.isEmpty) {
        return const BrowserContactProfile();
      }
      final keyBytes = await getOrCreateAccountMasterKey(uid);
      final plain = decryptWithMasterKey(keyBytes, payload);
      final map = jsonDecode(plain);
      if (map is Map) {
        return BrowserContactProfile.fromJson(Map<String, dynamic>.from(map));
      }
    } catch (_) {}
    return const BrowserContactProfile();
  }

  Future<void> saveContactProfile(BrowserContactProfile profile) async {
    await ensureLoaded();
    final uid = activeAccountUserId;
    final keyBytes = await getOrCreateAccountMasterKey(uid);
    final encrypted = encryptWithMasterKey(
      keyBytes,
      jsonEncode(profile.toJson()),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_contactKeyPrefix$uid', encrypted);
    notifyListeners();
  }

  /// Wipes all saved passwords, master key, and contact autofill profile for [userId].
  Future<void> wipeAccountVault(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawIndex = prefs.getString('$_indexKeyPrefix$uid');
      if (rawIndex != null && rawIndex.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawIndex);
          if (decoded is Map && decoded['hints'] is List) {
            for (final item in decoded['hints'] as List) {
              if (item is Map && item['id'] != null) {
                await prefs.remove(_secretPrefsKey(uid, item['id'].toString()));
              }
            }
          }
        } catch (_) {}
      }
      final prefix = '$_secretKeyPrefix${uid}_';
      for (final k in prefs.getKeys().toList()) {
        if (k.startsWith(prefix)) {
          await prefs.remove(k);
        }
      }
      await prefs.remove('$_indexKeyPrefix$uid');
      await prefs.remove('$_contactKeyPrefix$uid');
    } catch (_) {}

    await deleteAccountMasterKey(uid);

    if (_loadedUserId == uid || activeAccountUserId == uid) {
      _hints = <BrowserCredentialHint>[];
      _neverSaveOrigins = <String>[];
      _loadedUserId = null;
      notifyListeners();
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _hints = <BrowserCredentialHint>[];
    _neverSaveOrigins = <String>[];
    _loadedUserId = null;
    _fallbackKeyStore.clear();
    debugSecureStoreOverride = null;
    debugUserIdOverride = null;
  }
}
