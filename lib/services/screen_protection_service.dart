import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ref-counted native screen protection controller (`WindowManager.LayoutParams.FLAG_SECURE`
/// on Android) for chats/channels with `hasProtectedContent == true`.
class ScreenProtectionService {
  ScreenProtectionService._();
  static final ScreenProtectionService instance = ScreenProtectionService._();

  static const MethodChannel _channel =
      MethodChannel('app.theaver.messenger/screen_security');

  final Set<String> _activeOwners = <String>{};
  bool _isSecured = false;

  @visibleForTesting
  bool get isSecured => _isSecured;

  @visibleForTesting
  int get activeOwnerCount => _activeOwners.length;

  /// Acquires screenshot/screen-recording protection for [ownerKey].
  Future<void> acquire(String ownerKey) async {
    if (ownerKey.isEmpty) return;
    final added = _activeOwners.add(ownerKey);
    if (added && !_isSecured) {
      await _applyPlatformFlag(true);
    }
  }

  /// Releases protection for [ownerKey]; clears `FLAG_SECURE` only when no owners remain.
  Future<void> release(String ownerKey) async {
    if (ownerKey.isEmpty) return;
    _activeOwners.remove(ownerKey);
    if (_activeOwners.isEmpty && _isSecured) {
      await _applyPlatformFlag(false);
    }
  }

  /// Synchronizes [ownerKey] protection with [protected].
  Future<void> sync(String ownerKey, bool protected) async {
    if (protected) {
      await acquire(ownerKey);
    } else {
      await release(ownerKey);
    }
  }

  /// Clears all active protection owners (used in tests/session reset).
  @visibleForTesting
  Future<void> resetForTesting() async {
    _activeOwners.clear();
    _isSecured = false;
    await _applyPlatformFlag(false);
  }

  Future<void> _applyPlatformFlag(bool enabled) async {
    _isSecured = enabled;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>(
        'setSecureFlag',
        <String, dynamic>{'enabled': enabled},
      );
    } on MissingPluginException {
      // Safe no-op in widget/unit test bindings.
    } on PlatformException catch (e) {
      debugPrint('ScreenProtectionService platform error: ${e.message}');
    } catch (_) {}
  }
}
