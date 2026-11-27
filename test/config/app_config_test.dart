import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/config/app_config.dart';
import 'package:theaver/services/account_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppConfig Helper Methods', () {
    test('deriveWsUrl converts http/https endpoints correctly', () {
      expect(
        AppConfig.deriveWsUrl('http://localhost:8080'),
        equals('ws://localhost:8080/api/ws'),
      );
      expect(
        AppConfig.deriveWsUrl('https://api.theaver.app'),
        equals('wss://api.theaver.app/api/ws'),
      );
      expect(
        AppConfig.deriveWsUrl('http://192.168.1.50:8080/api'),
        equals('ws://192.168.1.50:8080/api/ws'),
      );
      expect(
        AppConfig.deriveWsUrl('http://192.168.1.50:8080/api/ws'),
        equals('ws://192.168.1.50:8080/api/ws'),
      );
      expect(
        AppConfig.deriveWsUrl('https://custom.domain.com:8443'),
        equals('wss://custom.domain.com:8443/api/ws'),
      );
    });

    test('deriveStorageUrl resolves SeaweedFS S3 storage endpoints correctly', () {
      expect(
        AppConfig.deriveStorageUrl('https://api.theaver.app'),
        equals('https://storage.theaver.app'),
      );
      expect(
        AppConfig.deriveStorageUrl('http://localhost:8080'),
        equals('http://localhost:8333'),
      );
      expect(
        AppConfig.deriveStorageUrl('http://192.168.1.50:8080'),
        equals('http://192.168.1.50:8333'),
      );
      expect(
        AppConfig.deriveStorageUrl('http://10.0.2.2:8080'),
        equals('http://10.0.2.2:8333'),
      );
    });

    test('getProfileUrl and getInviteUrl format deep links', () {
      final profileUrl = AppConfig.getProfileUrl('test_user_123');
      expect(profileUrl, contains('/u/test_user_123'));

      final inviteUrl = AppConfig.getInviteUrl('invite_abc_789');
      expect(inviteUrl, contains('/join/invite_abc_789'));
    });

    test('resolveMediaUrl handles relative and absolute paths', () {
      expect(AppConfig.resolveMediaUrl(null), isNull);
      expect(AppConfig.resolveMediaUrl(''), isNull);
      expect(
        AppConfig.resolveMediaUrl('https://example.com/image.png'),
        equals('https://example.com/image.png'),
      );
      expect(
        AppConfig.resolveMediaUrl('http://example.com/image.png'),
        equals('http://example.com/image.png'),
      );
      expect(
        AppConfig.resolveMediaUrl('data:image/png;base64,iVBORw0KGgo='),
        equals('data:image/png;base64,iVBORw0KGgo='),
      );

      final resolvedRelative = AppConfig.resolveMediaUrl('/avatars/user1.jpg');
      expect(resolvedRelative, isNotNull);
      expect(resolvedRelative, endsWith('/api/files/avatar/user1.jpg'));
      expect(resolvedRelative, startsWith('http'));

      final resolvedWithoutLeadingSlash = AppConfig.resolveMediaUrl('avatars/user2.jpg');
      expect(resolvedWithoutLeadingSlash, isNotNull);
      expect(resolvedWithoutLeadingSlash, endsWith('/api/files/avatar/user2.jpg'));

      final resolvedLegacyStorageAvatar = AppConfig.resolveMediaUrl(
        'https://storage.theaver.app/avatars/u1/a.png',
      );
      expect(
        resolvedLegacyStorageAvatar,
        equals('${AppConfig.baseUrl}/api/files/avatar/u1/a.png'),
      );

      const presignedAvatar =
          'https://storage.theaver.app/avatars/u1/a.png?X-Amz-Signature=deadbeef&X-Amz-Expires=300';
      expect(AppConfig.resolveMediaUrl(presignedAvatar), equals(presignedAvatar));

      expect(
        AppConfig.resolveMediaUrl('https://storage.theaver.app/stickers/1.webp'),
        equals('https://storage.theaver.app/stickers/1.webp'),
      );
    });

    test('authHeadersForUrl and cacheKeyForUrl enforce protected API scoping', () {
      final apiUrl = '${AppConfig.baseUrl}/api/files/avatar/u1/pic.png?mt=12345';
      expect(
        AppConfig.authHeadersForUrl(apiUrl, tokenOverride: 'jwt-secret'),
        equals({'Authorization': 'Bearer jwt-secret'}),
      );
      expect(
        AppConfig.authHeadersForUrl(
          'https://storage.theaver.app/media/x.png?X-Amz-Signature=abc',
          tokenOverride: 'jwt-secret',
        ),
        isNull,
      );
      expect(
        AppConfig.authHeadersForUrl(
          'https://evil.example/api/files/avatar/u1/pic.png',
          tokenOverride: 'jwt-secret',
        ),
        isNull,
      );
      expect(
        AppConfig.cacheKeyForUrl('$apiUrl#acrop=0.1,0.1,0.8,0.8'),
        equals('${AppConfig.baseUrl}/api/files/avatar/u1/pic.png'),
      );
    });
  });

  group('AppConfig Dynamic Runtime Overrides', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppConfig.init();
    });

    tearDown(() async {
      await AppConfig.resetToDefaults();
    });

    test('custom server URL overrides baseUrl, wsUrl, and storageUrl', () async {
      const customIp = 'http://192.168.1.120:8080';
      await AppConfig.setCustomServerUrl(customIp);

      expect(AppConfig.baseUrl, equals(customIp));
      expect(AppConfig.wsUrl, equals('ws://192.168.1.120:8080/api/ws'));
      expect(AppConfig.storageUrl, equals('http://192.168.1.120:8333'));

      // Verify persistence in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppConfig.prefCustomServerUrlKey), equals(customIp));

      // Reset
      await AppConfig.resetToDefaults();
      expect(AppConfig.baseUrl, equals(AppConfig.prodApiBaseUrl));
    });

    test('AccountManager.init purges legacy offline test account', () async {
      SharedPreferences.setMockInitialValues({
        'accounts': [
          jsonEncode({
            'userId': 'test_user_001',
            'token': 'test_token_offline_mode',
            'username': 'admin',
            'displayName': 'Test Admin',
            'lastLogin': DateTime.now().toIso8601String(),
          }),
          jsonEncode({
            'userId': 'real_user_1',
            'token': 'real_jwt_token',
            'username': 'alice',
            'displayName': 'Alice',
            'lastLogin': DateTime.now().toIso8601String(),
          }),
        ],
        'current_account_id': 'test_user_001',
      });

      await AccountManager().init();
      expect(AccountManager().hasAccount('test_user_001'), isFalse);
      expect(AccountManager().hasAccount('real_user_1'), isTrue);
      expect(AccountManager().currentAccount, isNull);
    });
  });
}
