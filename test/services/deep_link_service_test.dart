import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/services/deep_link_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeepLinkService URI Parsing', () {
    test('parses web production profile URLs', () {
      final parsed = DeepLinkService.parseUri(Uri.parse('https://theaver.app/u/user_prod_123'));
      expect(parsed, isNotNull);
      expect(parsed!.type, equals(DeepLinkType.userProfile));
      expect(parsed.identifier, equals('user_prod_123'));
    });

    test('parses web production group invite URLs', () {
      final parsed = DeepLinkService.parseUri(Uri.parse('https://theaver.app/join/inv_code_456'));
      expect(parsed, isNotNull);
      expect(parsed!.type, equals(DeepLinkType.groupInvite));
      expect(parsed.identifier, equals('inv_code_456'));
    });

    test('parses web production channel URLs', () {
      final parsed = DeepLinkService.parseUri(Uri.parse('https://theaver.app/c/general_channel'));
      expect(parsed, isNotNull);
      expect(parsed!.type, equals(DeepLinkType.channel));
      expect(parsed.identifier, equals('general_channel'));
    });

    test('parses custom LAN IP and port web links', () {
      final profile = DeepLinkService.parseUri(Uri.parse('http://192.168.1.50:3000/u/lan_user_99'));
      expect(profile, isNotNull);
      expect(profile!.type, equals(DeepLinkType.userProfile));
      expect(profile.identifier, equals('lan_user_99'));

      final invite = DeepLinkService.parseUri(Uri.parse('http://192.168.1.50:3000/join/lan_invite_88'));
      expect(invite, isNotNull);
      expect(invite!.type, equals(DeepLinkType.groupInvite));
      expect(invite.identifier, equals('lan_invite_88'));

      final channel = DeepLinkService.parseUri(Uri.parse('http://192.168.1.50:3000/c/lan_news'));
      expect(channel, isNotNull);
      expect(channel!.type, equals(DeepLinkType.channel));
      expect(channel.identifier, equals('lan_news'));
    });

    test('parses custom scheme theaver:// URLs', () {
      final profile = DeepLinkService.parseUri(Uri.parse('theaver://u/custom_user_1'));
      expect(profile, isNotNull);
      expect(profile!.type, equals(DeepLinkType.userProfile));
      expect(profile.identifier, equals('custom_user_1'));

      final invite = DeepLinkService.parseUri(Uri.parse('theaver://join/custom_invite_2'));
      expect(invite, isNotNull);
      expect(invite!.type, equals(DeepLinkType.groupInvite));
      expect(invite.identifier, equals('custom_invite_2'));

      final channel = DeepLinkService.parseUri(Uri.parse('theaver://c/custom_channel_3'));
      expect(channel, isNotNull);
      expect(channel!.type, equals(DeepLinkType.channel));
      expect(channel.identifier, equals('custom_channel_3'));
    });

    test('parses custom scheme miptgram:// URLs', () {
      final profile = DeepLinkService.parseUri(Uri.parse('miptgram://u/custom_user_1'));
      expect(profile, isNotNull);
      expect(profile!.type, equals(DeepLinkType.userProfile));
      expect(profile.identifier, equals('custom_user_1'));

      final invite = DeepLinkService.parseUri(Uri.parse('miptgram://join/custom_invite_2'));
      expect(invite, isNotNull);
      expect(invite!.type, equals(DeepLinkType.groupInvite));
      expect(invite.identifier, equals('custom_invite_2'));

      final channel = DeepLinkService.parseUri(Uri.parse('miptgram://c/custom_channel_3'));
      expect(channel, isNotNull);
      expect(channel!.type, equals(DeepLinkType.channel));
      expect(channel.identifier, equals('custom_channel_3'));
    });

    test('parses custom scheme miptgram:/// with leading slash path segments', () {
      final profile = DeepLinkService.parseUri(Uri.parse('miptgram:///u/custom_user_4'));
      expect(profile, isNotNull);
      expect(profile!.type, equals(DeepLinkType.userProfile));
      expect(profile.identifier, equals('custom_user_4'));

      final invite = DeepLinkService.parseUri(Uri.parse('miptgram:///join/custom_invite_5'));
      expect(invite, isNotNull);
      expect(invite!.type, equals(DeepLinkType.groupInvite));
      expect(invite.identifier, equals('custom_invite_5'));

      final channel = DeepLinkService.parseUri(Uri.parse('miptgram:///c/custom_channel_6'));
      expect(channel, isNotNull);
      expect(channel!.type, equals(DeepLinkType.channel));
      expect(channel.identifier, equals('custom_channel_6'));
    });

    test('parses web hash routing fragments (#/u/..., #/join/..., #/c/...)', () {
      final profile = DeepLinkService.parseUri(Uri.parse('http://localhost:3000/#/u/hash_user'));
      expect(profile, isNotNull);
      expect(profile!.type, equals(DeepLinkType.userProfile));
      expect(profile.identifier, equals('hash_user'));

      final invite = DeepLinkService.parseUri(Uri.parse('http://localhost:3000/#/join/hash_invite'));
      expect(invite, isNotNull);
      expect(invite!.type, equals(DeepLinkType.groupInvite));
      expect(invite.identifier, equals('hash_invite'));

      final channel = DeepLinkService.parseUri(Uri.parse('http://localhost:3000/#/c/hash_channel'));
      expect(channel, isNotNull);
      expect(channel!.type, equals(DeepLinkType.channel));
      expect(channel.identifier, equals('hash_channel'));
    });

    test('parses web production addtheme URLs', () {
      final parsed = DeepLinkService.parseUri(Uri.parse('https://theaver.app/addtheme/cKQjOAcSGnlLUJMb'));
      expect(parsed, isNotNull);
      expect(parsed!.type, equals(DeepLinkType.addTheme));
      expect(parsed.identifier, equals('cKQjOAcSGnlLUJMb'));
    });

    test('parses custom scheme theaver://addtheme URLs', () {
      final parsed = DeepLinkService.parseUri(Uri.parse('theaver://addtheme/customTheme123'));
      expect(parsed, isNotNull);
      expect(parsed!.type, equals(DeepLinkType.addTheme));
      expect(parsed.identifier, equals('customTheme123'));
    });

    test('parses web hash routing fragments for addtheme', () {
      final parsed = DeepLinkService.parseUri(Uri.parse('http://localhost:3000/#/addtheme/hashTheme456'));
      expect(parsed, isNotNull);
      expect(parsed!.type, equals(DeepLinkType.addTheme));
      expect(parsed.identifier, equals('hashTheme456'));
    });

    test('returns null for unrecognized paths', () {
      final result = DeepLinkService.parseUri(Uri.parse('https://example.com/other/path'));
      expect(result, isNull);
    });
  });
}
