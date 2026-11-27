import 'dart:convert';
import 'dart:math';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart'
    show ChangeNotifier, Uint8List, kDebugMode, visibleForTesting;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter/widgets.dart' show BuildContext, WidgetsBinding;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import '../utils/safari_url_safety.dart';
import 'account_manager.dart';
import 'browser_site_settings_service.dart';
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

/// Supported payment card networks detected from BIN prefixes.
enum BrowserCardBrand {
  visa,
  mastercard,
  mir,
  unionpay,
  amex,
  jcb,
  unknown;

  String get displayName => switch (this) {
        BrowserCardBrand.visa => 'Visa',
        BrowserCardBrand.mastercard => 'Mastercard',
        BrowserCardBrand.mir => 'Мир',
        BrowserCardBrand.unionpay => 'UnionPay',
        BrowserCardBrand.amex => 'American Express',
        BrowserCardBrand.jcb => 'JCB',
        BrowserCardBrand.unknown => 'Карта',
      };
}

/// Non-secret payment card index entry kept in memory so the browser can offer
/// card autofill hints without decrypting full card numbers prior to auth.
class BrowserCardHint {
  final String id;
  final BrowserCardBrand brand;
  final String last4;
  final String holderName;
  final int expMonth;
  final int expYear;
  final String nickname;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;

  const BrowserCardHint({
    required this.id,
    required this.brand,
    required this.last4,
    this.holderName = '',
    required this.expMonth,
    required this.expYear,
    this.nickname = '',
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
  });

  String get formattedExpiry =>
      '${expMonth.toString().padLeft(2, '0')}/${(expYear % 100).toString().padLeft(2, '0')}';

  String get maskedNumber => '•••• $last4';

  BrowserCardHint copyWith({
    BrowserCardBrand? brand,
    String? last4,
    String? holderName,
    int? expMonth,
    int? expYear,
    String? nickname,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
  }) {
    return BrowserCardHint(
      id: id,
      brand: brand ?? this.brand,
      last4: last4 ?? this.last4,
      holderName: holderName ?? this.holderName,
      expMonth: expMonth ?? this.expMonth,
      expYear: expYear ?? this.expYear,
      nickname: nickname ?? this.nickname,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'brand': brand.name,
        'last4': last4,
        'holderName': holderName,
        'expMonth': expMonth,
        'expYear': expYear,
        'nickname': nickname,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
      };

  factory BrowserCardHint.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final rawMonth = int.tryParse(json['expMonth']?.toString() ?? '') ?? 1;
    final rawYear = int.tryParse(json['expYear']?.toString() ?? '') ?? now.year;
    return BrowserCardHint(
      id: json['id']?.toString() ?? '',
      brand: BrowserCardBrand.values.firstWhere(
        (b) => b.name == json['brand']?.toString(),
        orElse: () => BrowserCardBrand.unknown,
      ),
      last4: json['last4']?.toString() ?? '',
      holderName: json['holderName']?.toString() ?? '',
      expMonth: rawMonth.clamp(1, 12),
      expYear: BrowserVaultService.normalizeExpiryYear(rawYear),
      nickname: json['nickname']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
      lastUsedAt: DateTime.tryParse(json['lastUsedAt']?.toString() ?? ''),
    );
  }
}

/// Decrypted payment card returned ONLY after passing [BrowserVaultAuthGate].
/// Never stores CVV/CVC.
class BrowserSavedCard {
  final BrowserCardHint hint;
  final String cardNumber;

  const BrowserSavedCard({
    required this.hint,
    required this.cardNumber,
  });

  String get id => hint.id;
  BrowserCardBrand get brand => hint.brand;
  String get last4 => hint.last4;
  String get holderName => hint.holderName;
  int get expMonth => hint.expMonth;
  int get expYear => hint.expYear;
  String get nickname => hint.nickname;
  String get formattedExpiry => hint.formattedExpiry;
  String get maskedNumber => hint.maskedNumber;
}

enum BrowserCardSaveStatus {
  ignoredInsecureOrigin,
  ignoredInvalid,
  newCard,
  updateCard,
  alreadyUpToDate,
}

class BrowserCardSaveEvaluation {
  final BrowserCardSaveStatus status;
  final String? existingId;
  final BrowserCardBrand? brand;
  final String? last4;

  const BrowserCardSaveEvaluation({
    required this.status,
    this.existingId,
    this.brand,
    this.last4,
  });
}

/// Encrypted multi-address / contact autofill profile stored per account.
class BrowserSavedAddress {
  final String id;
  final String label;
  final String fullName;
  final String organization;
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String region;
  final String postalCode;
  final String country;
  final String phone;
  final String email;
  final bool isDefault;
  final DateTime updatedAt;

  BrowserSavedAddress({
    this.id = '',
    this.label = '',
    this.fullName = '',
    this.organization = '',
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.city = '',
    this.region = '',
    this.postalCode = '',
    this.country = '',
    this.phone = '',
    this.email = '',
    this.isDefault = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get hasAnyField =>
      fullName.trim().isNotEmpty ||
      organization.trim().isNotEmpty ||
      addressLine1.trim().isNotEmpty ||
      addressLine2.trim().isNotEmpty ||
      city.trim().isNotEmpty ||
      region.trim().isNotEmpty ||
      postalCode.trim().isNotEmpty ||
      country.trim().isNotEmpty ||
      phone.trim().isNotEmpty ||
      email.trim().isNotEmpty;

  String get displayTitle {
    if (label.trim().isNotEmpty) return label.trim();
    if (fullName.trim().isNotEmpty) return fullName.trim();
    if (addressLine1.trim().isNotEmpty) return addressLine1.trim();
    if (organization.trim().isNotEmpty) return organization.trim();
    if (email.trim().isNotEmpty) return email.trim();
    if (phone.trim().isNotEmpty) return phone.trim();
    return '';
  }

  String get summarySubtitle {
    final parts = <String>[
      if (addressLine1.trim().isNotEmpty) addressLine1.trim(),
      if (city.trim().isNotEmpty) city.trim(),
      if (postalCode.trim().isNotEmpty) postalCode.trim(),
      if (phone.trim().isNotEmpty) phone.trim(),
      if (email.trim().isNotEmpty) email.trim(),
    ];
    return parts.join(', ');
  }

  BrowserSavedAddress copyWith({
    String? id,
    String? label,
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
    bool? isDefault,
    DateTime? updatedAt,
  }) {
    return BrowserSavedAddress(
      id: id ?? this.id,
      label: label ?? this.label,
      fullName: fullName ?? this.fullName,
      organization: organization ?? this.organization,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      region: region ?? this.region,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      isDefault: isDefault ?? this.isDefault,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'fullName': fullName,
        'organization': organization,
        'addressLine1': addressLine1,
        'addressLine2': addressLine2,
        'city': city,
        'region': region,
        'postalCode': postalCode,
        'country': country,
        'phone': phone,
        'email': email,
        'isDefault': isDefault,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory BrowserSavedAddress.fromJson(Map<String, dynamic> json) {
    return BrowserSavedAddress(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      organization: json['organization']?.toString() ?? '',
      addressLine1: json['addressLine1']?.toString() ?? '',
      addressLine2: json['addressLine2']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      region: json['region']?.toString() ?? '',
      postalCode: json['postalCode']?.toString() ?? '',
      country: json['country']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      isDefault: json['isDefault'] == true,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}

/// Encrypted AES-256-GCM browser credential, payment card, and address vault,
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
  static const String _cardIndexKeyPrefix = 'browser_vault_cards_index_v1_u_';
  static const String _cardSecretKeyPrefix = 'browser_vault_card_secret_v1_u_';
  static const String _addressesSecretKeyPrefix =
      'browser_vault_addresses_enc_v1_u_';

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
  List<BrowserCardHint> _cardHints = <BrowserCardHint>[];
  List<BrowserSavedAddress> _addresses = <BrowserSavedAddress>[];
  String? _loadedUserId;

  List<BrowserCredentialHint> get hints => List.unmodifiable(_hints);
  List<String> get neverSaveOrigins => List.unmodifiable(_neverSaveOrigins);
  List<BrowserCardHint> get cardHints => List.unmodifiable(_cardHints);
  List<BrowserSavedAddress> get addresses => List.unmodifiable(_addresses);

  BrowserSavedAddress? get defaultAddress {
    if (_addresses.isEmpty) return null;
    return _addresses.firstWhere(
      (a) => a.isDefault,
      orElse: () => _addresses.first,
    );
  }

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

  static bool get _isFlutterTestBinding {
    if (!kDebugMode) return false;
    try {
      final name = WidgetsBinding.instance.runtimeType.toString();
      return name.contains('TestWidgetsFlutterBinding') ||
          name.contains('AutomatedTestWidgetsFlutterBinding');
    } catch (_) {
      return false;
    }
  }

  Future<String?> _readSecureKey(String key) async {
    final override = debugSecureStoreOverride;
    if (override != null) return override[key];
    if (_isFlutterTestBinding) {
      return _fallbackKeyStore[key];
    }
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
    if (_isFlutterTestBinding) {
      _fallbackKeyStore[key] = value;
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
    if (_isFlutterTestBinding) {
      _fallbackKeyStore.remove(key);
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
      _loadCredentialIndexFromPrefs(prefs, uid);
      _loadCardIndexFromPrefs(prefs, uid);
      await _loadOrMigrateAddresses(prefs, uid);
      notifyListeners();
    } catch (_) {}
  }

  void _loadCredentialIndexFromPrefs(SharedPreferences prefs, String uid) {
    _hints = <BrowserCredentialHint>[];
    _neverSaveOrigins = <String>[];
    final raw = prefs.getString('$_indexKeyPrefix$uid');
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
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
      }
      final rawNever = decoded['neverSaveOrigins'];
      if (rawNever is List) {
        _neverSaveOrigins = rawNever
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {}
  }

  void _loadCardIndexFromPrefs(SharedPreferences prefs, String uid) {
    _cardHints = <BrowserCardHint>[];
    final raw = prefs.getString('$_cardIndexKeyPrefix$uid');
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      final dynamic rawCards = decoded is Map ? decoded['cards'] : decoded;
      if (rawCards is List) {
        _cardHints = rawCards
            .whereType<Map>()
            .map(
              (e) => BrowserCardHint.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .where((c) => c.id.isNotEmpty && c.last4.isNotEmpty)
            .toList()
          ..sort(_compareCardRecency);
      }
    } catch (_) {}
  }

  Future<void> _loadOrMigrateAddresses(
    SharedPreferences prefs,
    String uid,
  ) async {
    final addrKey = '$_addressesSecretKeyPrefix$uid';
    if (prefs.containsKey(addrKey)) {
      final payload = prefs.getString(addrKey);
      if (payload == null || payload.isEmpty) {
        _addresses = <BrowserSavedAddress>[];
        return;
      }
      try {
        final keyBytes = await getOrCreateAccountMasterKey(uid);
        final plain = decryptWithMasterKey(keyBytes, payload);
        final decoded = jsonDecode(plain);
        if (decoded is List) {
          _addresses = decoded
              .whereType<Map>()
              .map(
                (e) => BrowserSavedAddress.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .where((a) => a.id.isNotEmpty)
              .toList();
          if (_addresses.isNotEmpty && !_addresses.any((a) => a.isDefault)) {
            _addresses[0] = _addresses[0].copyWith(isDefault: true);
          }
          return;
        }
      } catch (_) {}
      _addresses = <BrowserSavedAddress>[];
      return;
    }

    // Legacy migration from single contact profile or current account profile.
    final legacyKey = '$_contactKeyPrefix$uid';
    final legacyRaw = prefs.getString(legacyKey);
    BrowserContactProfile? candidate;
    if (legacyRaw != null && legacyRaw.isNotEmpty) {
      try {
        final keyBytes = await getOrCreateAccountMasterKey(uid);
        final plain = decryptWithMasterKey(keyBytes, legacyRaw);
        final decoded = jsonDecode(plain);
        if (decoded is Map) {
          candidate = BrowserContactProfile.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      } catch (_) {}
    } else {
      final currentAccountId = AccountManager().currentAccount?.userId.trim();
      if (debugUserIdOverride == null || currentAccountId == uid) {
        candidate = BrowserContactProfile.fromCurrentAccount();
      }
    }

    if (candidate != null && candidate.hasAnyField) {
      final migrated = BrowserSavedAddress(
        id: _uuid.v4(),
        label: AppLocalizations.trStatic(
          'browser_address_default_label',
          'Основной профиль',
        ),
        fullName: candidate.fullName.trim(),
        email: candidate.email.trim(),
        phone: candidate.phone.trim(),
        isDefault: true,
        updatedAt: DateTime.now(),
      );
      _addresses = <BrowserSavedAddress>[migrated];
      await _saveAddresses(uid, prefs: prefs);
    } else {
      _addresses = <BrowserSavedAddress>[];
    }

    if (legacyRaw != null) {
      await prefs.remove(legacyKey);
    }
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

  Future<void> _saveCardIndex(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_cardIndexKeyPrefix$uid',
        jsonEncode(<String, dynamic>{
          'cards': _cardHints.map((c) => c.toJson()).toList(),
        }),
      );
    } catch (_) {}
  }

  Future<void> _saveAddresses(
    String uid, {
    SharedPreferences? prefs,
  }) async {
    final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
    final keyBytes = await getOrCreateAccountMasterKey(uid);
    final encrypted = encryptWithMasterKey(
      keyBytes,
      jsonEncode(_addresses.map((a) => a.toJson()).toList()),
    );
    await resolvedPrefs.setString('$_addressesSecretKeyPrefix$uid', encrypted);
  }

  String _secretPrefsKey(String uid, String credId) =>
      '$_secretKeyPrefix${uid}_$credId';

  String _cardSecretPrefsKey(String uid, String cardId) =>
      '$_cardSecretKeyPrefix${uid}_$cardId';

  static int _compareCardRecency(BrowserCardHint a, BrowserCardHint b) {
    final aTs = a.lastUsedAt ?? a.updatedAt;
    final bTs = b.lastUsedAt ?? b.updatedAt;
    return bTs.compareTo(aTs);
  }

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

  // ==================== Payment Cards ====================

  static String stripCardDigits(String raw) =>
      raw.replaceAll(RegExp(r'\D'), '');

  static bool isValidLuhn(String rawDigits) {
    final digits = stripCardDigits(rawDigits);
    if (digits.length < 13 || digits.length > 19) return false;
    int sum = 0;
    bool alternate = false;
    for (int i = digits.length - 1; i >= 0; i--) {
      int n = digits.codeUnitAt(i) - 48;
      if (n < 0 || n > 9) return false;
      if (alternate) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alternate = !alternate;
    }
    return sum % 10 == 0;
  }

  static BrowserCardBrand detectCardBrand(String rawDigits) {
    final digits = stripCardDigits(rawDigits);
    if (digits.isEmpty) return BrowserCardBrand.unknown;
    if (digits.startsWith('4')) return BrowserCardBrand.visa;

    if (digits.length >= 4) {
      final p4 = int.tryParse(digits.substring(0, 4)) ?? -1;
      if (p4 >= 2200 && p4 <= 2204) return BrowserCardBrand.mir;
      if (p4 >= 2221 && p4 <= 2720) return BrowserCardBrand.mastercard;
      if (p4 >= 3528 && p4 <= 3589) return BrowserCardBrand.jcb;
    }

    if (digits.length >= 2) {
      final p2 = int.tryParse(digits.substring(0, 2)) ?? -1;
      if (p2 == 34 || p2 == 37) return BrowserCardBrand.amex;
      if (p2 >= 51 && p2 <= 55) return BrowserCardBrand.mastercard;
      if (p2 == 62 || p2 == 81) return BrowserCardBrand.unionpay;
    }

    return BrowserCardBrand.unknown;
  }

  static String formatCardNumberGroups(String rawDigits) {
    final digits = stripCardDigits(rawDigits);
    if (digits.isEmpty) return '';
    final brand = detectCardBrand(digits);
    final buf = StringBuffer();
    if (brand == BrowserCardBrand.amex) {
      for (int i = 0; i < digits.length; i++) {
        if (i == 4 || i == 10) buf.write(' ');
        buf.write(digits[i]);
      }
      return buf.toString();
    }
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  static int normalizeExpiryYear(int year) {
    if (year >= 0 && year < 100) return 2000 + year;
    return year;
  }

  static bool isCardExpired(int expMonth, int expYear, {DateTime? now}) {
    if (expMonth < 1 || expMonth > 12) return true;
    final normalizedYear = normalizeExpiryYear(expYear);
    final refNow = now ?? DateTime.now();
    final nextMonthStart = refNow.isUtc
        ? DateTime.utc(normalizedYear, expMonth + 1, 1)
        : DateTime(normalizedYear, expMonth + 1, 1);
    return !refNow.isBefore(nextMonthStart);
  }

  static String _normalizeHolderName(String raw) =>
      raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<String?> _readDecryptedCardNumberRaw(
    String uid,
    BrowserCardHint hint,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString(_cardSecretPrefsKey(uid, hint.id));
      if (payload == null || payload.isEmpty) return null;
      final keyBytes = await getOrCreateAccountMasterKey(uid);
      final plainJson = decryptWithMasterKey(keyBytes, payload);
      final map = jsonDecode(plainJson);
      if (map is! Map) return null;
      if (map['id']?.toString() != hint.id) return null;
      return map['cardNumber']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Evaluates a submitted payment card on an HTTPS page without storing CVV
  /// or triggering an interactive auth prompt.
  Future<BrowserCardSaveEvaluation> evaluateCardSubmission({
    required String url,
    required String cardNumber,
    required String holderName,
    required int expMonth,
    required int expYear,
    bool hasSslWarning = false,
  }) async {
    await ensureLoaded();
    final uri = Uri.tryParse(url.trim());
    final scheme = uri?.scheme.toLowerCase() ?? '';
    final safety = SafariUrlSafetyAnalyzer.analyzeUrl(
      url,
      hasSslWarning: hasSslWarning,
    );
    if (scheme != 'https' ||
        hasSslWarning ||
        safety.isSuspiciousHomograph ||
        safety.asciiHost.isEmpty) {
      return const BrowserCardSaveEvaluation(
        status: BrowserCardSaveStatus.ignoredInsecureOrigin,
      );
    }

    final digits = stripCardDigits(cardNumber);
    final normalizedYear = normalizeExpiryYear(expYear);
    if (!isValidLuhn(digits) ||
        expMonth < 1 ||
        expMonth > 12 ||
        isCardExpired(expMonth, normalizedYear)) {
      return const BrowserCardSaveEvaluation(
        status: BrowserCardSaveStatus.ignoredInvalid,
      );
    }

    final brand = detectCardBrand(digits);
    final last4 = digits.substring(digits.length - 4);
    final normalizedHolder = _normalizeHolderName(holderName);
    final uid = activeAccountUserId;

    for (final existing in _cardHints) {
      if (existing.last4 != last4 || existing.brand != brand) continue;
      final existingPan = await _readDecryptedCardNumberRaw(uid, existing);
      if (existingPan == null || stripCardDigits(existingPan) != digits) {
        continue;
      }
      final sameHolder =
          _normalizeHolderName(existing.holderName) == normalizedHolder;
      final sameExpiry = existing.expMonth == expMonth &&
          normalizeExpiryYear(existing.expYear) == normalizedYear;
      if (sameHolder && sameExpiry) {
        return BrowserCardSaveEvaluation(
          status: BrowserCardSaveStatus.alreadyUpToDate,
          existingId: existing.id,
          brand: brand,
          last4: last4,
        );
      }
      return BrowserCardSaveEvaluation(
        status: BrowserCardSaveStatus.updateCard,
        existingId: existing.id,
        brand: brand,
        last4: last4,
      );
    }

    return BrowserCardSaveEvaluation(
      status: BrowserCardSaveStatus.newCard,
      brand: brand,
      last4: last4,
    );
  }

  /// Encrypts and persists a payment card (PAN only; never CVV/CVC).
  Future<BrowserCardHint> saveOrUpdateCard({
    required String cardNumber,
    required String holderName,
    required int expMonth,
    required int expYear,
    String nickname = '',
    String? existingId,
    bool clearNickname = false,
  }) async {
    await ensureLoaded();
    final digits = stripCardDigits(cardNumber);
    final normalizedYear = normalizeExpiryYear(expYear);
    if (!isValidLuhn(digits)) {
      throw ArgumentError('Invalid payment card number');
    }
    if (expMonth < 1 ||
        expMonth > 12 ||
        isCardExpired(expMonth, normalizedYear)) {
      throw ArgumentError('Invalid or expired card expiration date');
    }

    final uid = activeAccountUserId;
    final brand = detectCardBrand(digits);
    final last4 = digits.substring(digits.length - 4);
    final cleanHolder = holderName.trim();
    final cleanNickname = nickname.trim();
    final now = DateTime.now();

    int matchIdx = existingId != null
        ? _cardHints.indexWhere((c) => c.id == existingId)
        : -1;
    if (matchIdx < 0) {
      for (int i = 0; i < _cardHints.length; i++) {
        final candidate = _cardHints[i];
        if (candidate.last4 != last4 || candidate.brand != brand) continue;
        final pan = await _readDecryptedCardNumberRaw(uid, candidate);
        if (pan != null && stripCardDigits(pan) == digits) {
          matchIdx = i;
          break;
        }
      }
    }

    final BrowserCardHint savedHint;
    if (matchIdx >= 0) {
      final existing = _cardHints[matchIdx];
      savedHint = existing.copyWith(
        brand: brand,
        last4: last4,
        holderName: cleanHolder,
        expMonth: expMonth,
        expYear: normalizedYear,
        nickname: clearNickname
            ? ''
            : (cleanNickname.isNotEmpty ? cleanNickname : existing.nickname),
        updatedAt: now,
        lastUsedAt: now,
      );
      _cardHints[matchIdx] = savedHint;
    } else {
      savedHint = BrowserCardHint(
        id: _uuid.v4(),
        brand: brand,
        last4: last4,
        holderName: cleanHolder,
        expMonth: expMonth,
        expYear: normalizedYear,
        nickname: cleanNickname,
        createdAt: now,
        updatedAt: now,
        lastUsedAt: now,
      );
      _cardHints.insert(0, savedHint);
    }

    final keyBytes = await getOrCreateAccountMasterKey(uid);
    final encryptedSecret = encryptWithMasterKey(
      keyBytes,
      jsonEncode(<String, dynamic>{
        'id': savedHint.id,
        'cardNumber': digits,
      }),
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cardSecretPrefsKey(uid, savedHint.id),
      encryptedSecret,
    );
    _cardHints.sort(_compareCardRecency);
    await _saveCardIndex(uid);
    notifyListeners();
    return savedHint;
  }

  /// Decrypts and returns a single payment card after passing [BrowserVaultAuthGate].
  Future<BrowserSavedCard?> unlockAndReadCard(
    BuildContext context,
    String id, {
    required String reason,
    String? originScope,
  }) async {
    await ensureLoaded();
    if (!context.mounted) return null;
    final uid = activeAccountUserId;
    final idx = _cardHints.indexWhere((c) => c.id == id);
    if (idx < 0) return null;
    final hint = _cardHints[idx];

    final ok = await _authGate.authenticate(
      context,
      reason: reason,
      originScope: originScope,
    );
    if (!ok) return null;

    final cardNumber = await _readDecryptedCardNumberRaw(uid, hint);
    if (cardNumber == null) return null;

    final updated = hint.copyWith(lastUsedAt: DateTime.now());
    _cardHints[idx] = updated;
    _cardHints.sort(_compareCardRecency);
    await _saveCardIndex(uid);
    notifyListeners();
    return BrowserSavedCard(hint: updated, cardNumber: cardNumber);
  }

  /// Authenticates via [BrowserVaultAuthGate] and decrypts all saved payment cards.
  Future<List<BrowserSavedCard>?> unlockAndReadAllCards(
    BuildContext context, {
    required String reason,
  }) async {
    await ensureLoaded();
    if (!context.mounted) return null;
    final ok = await _authGate.authenticate(context, reason: reason);
    if (!ok) return null;

    final uid = activeAccountUserId;
    final results = <BrowserSavedCard>[];
    for (final hint in _cardHints) {
      final cardNumber = await _readDecryptedCardNumberRaw(uid, hint);
      if (cardNumber != null) {
        results.add(BrowserSavedCard(hint: hint, cardNumber: cardNumber));
      }
    }
    return results;
  }

  Future<void> deleteCard(String id) async {
    await ensureLoaded();
    final uid = activeAccountUserId;
    final hadMatch = _cardHints.any((c) => c.id == id);
    if (!hadMatch) return;
    _cardHints.removeWhere((c) => c.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cardSecretPrefsKey(uid, id));
    await _saveCardIndex(uid);
    notifyListeners();
  }

  // ==================== Postal Addresses & Contact Compatibility ====================

  Future<BrowserSavedAddress> saveOrUpdateAddress(
    BrowserSavedAddress address,
  ) async {
    await ensureLoaded();
    final uid = activeAccountUserId;
    final targetId =
        address.id.trim().isNotEmpty ? address.id.trim() : _uuid.v4();
    final bool shouldBeDefault = address.isDefault || _addresses.isEmpty;
    final saved = address.copyWith(
      id: targetId,
      isDefault: shouldBeDefault,
      updatedAt: DateTime.now(),
    );

    if (shouldBeDefault) {
      for (int i = 0; i < _addresses.length; i++) {
        if (_addresses[i].id != targetId && _addresses[i].isDefault) {
          _addresses[i] = _addresses[i].copyWith(isDefault: false);
        }
      }
    }

    final existingIdx = _addresses.indexWhere((a) => a.id == targetId);
    if (existingIdx >= 0) {
      _addresses[existingIdx] = saved;
    } else {
      _addresses.insert(0, saved);
    }

    if (_addresses.isNotEmpty && !_addresses.any((a) => a.isDefault)) {
      _addresses[0] = _addresses[0].copyWith(isDefault: true);
    }

    await _saveAddresses(uid);
    notifyListeners();
    return saved;
  }

  Future<void> deleteAddress(String id) async {
    await ensureLoaded();
    final uid = activeAccountUserId;
    final beforeLen = _addresses.length;
    _addresses.removeWhere((a) => a.id == id);
    if (_addresses.length == beforeLen) return;
    if (_addresses.isNotEmpty && !_addresses.any((a) => a.isDefault)) {
      _addresses[0] = _addresses[0].copyWith(isDefault: true);
    }
    await _saveAddresses(uid);
    notifyListeners();
  }

  Future<void> setDefaultAddress(String id) async {
    await ensureLoaded();
    final uid = activeAccountUserId;
    if (!_addresses.any((a) => a.id == id)) return;
    bool changed = false;
    for (int i = 0; i < _addresses.length; i++) {
      final shouldDefault = _addresses[i].id == id;
      if (_addresses[i].isDefault != shouldDefault) {
        _addresses[i] = _addresses[i].copyWith(isDefault: shouldDefault);
        changed = true;
      }
    }
    if (!changed) return;
    await _saveAddresses(uid);
    notifyListeners();
  }

  Future<BrowserContactProfile> getContactProfile() async {
    await ensureLoaded();
    await BrowserSiteSettingsService.instance.ensureLoaded();
    final def = defaultAddress;
    final enabled = BrowserSiteSettingsService.instance.addressAutofillEnabled;
    if (def == null) {
      return BrowserContactProfile(enabled: enabled);
    }
    return BrowserContactProfile(
      fullName: def.fullName,
      email: def.email,
      phone: def.phone,
      enabled: enabled,
    );
  }

  Future<void> saveContactProfile(BrowserContactProfile profile) async {
    await ensureLoaded();
    final def = defaultAddress;
    if (def != null) {
      await saveOrUpdateAddress(
        def.copyWith(
          fullName: profile.fullName.trim(),
          email: profile.email.trim(),
          phone: profile.phone.trim(),
          isDefault: true,
          updatedAt: DateTime.now(),
        ),
      );
    } else if (profile.hasAnyField) {
      await saveOrUpdateAddress(
        BrowserSavedAddress(
          id: _uuid.v4(),
          label: AppLocalizations.trStatic(
            'browser_address_default_label',
            'Основной профиль',
          ),
          fullName: profile.fullName.trim(),
          email: profile.email.trim(),
          phone: profile.phone.trim(),
          isDefault: true,
          updatedAt: DateTime.now(),
        ),
      );
    }
    await BrowserSiteSettingsService.instance
        .setAddressAutofillEnabled(profile.enabled);
  }

  /// Wipes all saved passwords, cards, addresses, master key, and vault PIN for [userId].
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
      final rawCardIndex = prefs.getString('$_cardIndexKeyPrefix$uid');
      if (rawCardIndex != null && rawCardIndex.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawCardIndex);
          final dynamic cards = decoded is Map ? decoded['cards'] : decoded;
          if (cards is List) {
            for (final item in cards) {
              if (item is Map && item['id'] != null) {
                await prefs.remove(
                  _cardSecretPrefsKey(uid, item['id'].toString()),
                );
              }
            }
          }
        } catch (_) {}
      }
      final secretPrefix = '$_secretKeyPrefix${uid}_';
      final cardSecretPrefix = '$_cardSecretKeyPrefix${uid}_';
      for (final k in prefs.getKeys().toList()) {
        if (k.startsWith(secretPrefix) || k.startsWith(cardSecretPrefix)) {
          await prefs.remove(k);
        }
      }
      await prefs.remove('$_indexKeyPrefix$uid');
      await prefs.remove('$_cardIndexKeyPrefix$uid');
      await prefs.remove('$_addressesSecretKeyPrefix$uid');
      await prefs.remove('$_contactKeyPrefix$uid');
    } catch (_) {}

    await deleteAccountMasterKey(uid);
    await _authGate.clearVaultPinForAccount(uid);

    if (_loadedUserId == uid || activeAccountUserId == uid) {
      _hints = <BrowserCredentialHint>[];
      _neverSaveOrigins = <String>[];
      _cardHints = <BrowserCardHint>[];
      _addresses = <BrowserSavedAddress>[];
      _loadedUserId = null;
      notifyListeners();
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _hints = <BrowserCredentialHint>[];
    _neverSaveOrigins = <String>[];
    _cardHints = <BrowserCardHint>[];
    _addresses = <BrowserSavedAddress>[];
    _loadedUserId = null;
    _fallbackKeyStore.clear();
    debugSecureStoreOverride = null;
    debugUserIdOverride = null;
  }
}
