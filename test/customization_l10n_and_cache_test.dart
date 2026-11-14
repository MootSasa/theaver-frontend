import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/models/profile_customization.dart';
import 'package:theaver/services/peer_customization_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const expectedKeys = <String>[
    'customizationTitle',
    'customizationTabFrame',
    'customizationTabStatus',
    'customizationTabBanner',
    'customizationTabBadges',
    'customizationTabColors',
    'customizationPreviewLabel',
    'customizationSave',
    'customizationSaved',
    'customizationReset',
    'customizationRemove',
    'decoNone',
    'decoNeonPulse',
    'decoAuroraHalo',
    'decoSakuraPetals',
    'decoCyberGrid',
    'decoGoldenLaurel',
    'decoFrostCrystal',
    'decoPrismGlass',
    'decoEmberFlame',
    'decoStarlightOrbit',
    'decoCatGlow',
    'decoCatFrame',
    'decoCatSeasonal',
    'decoCatAnimated',
    'emojiStatusTitle',
    'emojiStatusClear',
    'emojiStatusNoteHint',
    'emojiStatusSelectHint',
    'emojiStatusUnicodeTab',
    'emojiStatusCustomTab',
    'emojiStatusExpiryLabel',
    'emojiStatusExpiryNever',
    'emojiStatusExpiry1h',
    'emojiStatusExpiry4h',
    'emojiStatusExpiry24h',
    'emojiStatusExpiry7d',
    'emojiStatusExpiresIn',
    'bannerTitle',
    'bannerUpload',
    'bannerRemove',
    'bannerHint',
    'bannerAdjust',
    'bannerAdjustHint',
    'bannerReplace',
    'bannerDragZoomHint',
    'bannerHeightLabel',
    'bannerHeightCompact',
    'bannerHeightStandard',
    'bannerHeightTall',
    'bannerZoomLabel',
    'bannerDimLabel',
    'bannerBlurLabel',
    'bannerSave',
    'badgesTitle',
    'badgesEmpty',
    'badgesDisplaySwitch',
    'badgesSingleHint',
    'badgeCreatorName',
    'badgeCreatorDesc',
    'badgeDeveloperName',
    'badgeDeveloperDesc',
    'badgeDesignerName',
    'badgeDesignerDesc',
    'badgeEarlyName',
    'badgeEarlyDesc',
    'badgeSupporterName',
    'badgeSupporterDesc',
    'badgeBugHunterName',
    'badgeBugHunterDesc',
    'badgeGrantedAt',
    'manageBadgeMenu',
    'manageBadgeTitle',
    'manageBadgeRevoke',
    'manageBadgeUpdated',
    'manageBadgeCreatorNote',
    'channelShowAuthorProfiles',
    'channelShowAuthorProfilesDesc',
    'customizationUploadError',
    'customizationSegmentProfile',
    'customizationSegmentName',
    'customizationSegmentStatus',
    'customizationSectionCoverBanner',
    'customizationSectionAvatarFrame',
    'customizationSectionBadge',
    'customizationAllBadges',
    'customizationNameColorTitle',
    'customizationReplyStripTitle',
    'customizationResetCover',
    'customizationResetNameColor',
    'customizationGradientSheetTitle',
    'customizationFirstColor',
    'customizationSecondColor',
    'customizationThirdColor',
    'customizationChatPreviewQuote',
    'customizationChatPreviewMessage',
    'customizationReplyEmoji',
    'customizationReplyEmojiEmptyTitle',
    'customizationReplyEmojiEmptyHint',
  ];

  test('All 10 l10n locale files include every customization/badge/channel key and follow copy constraints', () {
    final l10nDir = Directory('assets/l10n');
    expect(l10nDir.existsSync(), isTrue);

    final localeFiles = l10nDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    expect(localeFiles.length, 10);

    for (final file in localeFiles) {
      final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final key in expectedKeys) {
        expect(
          map.containsKey(key) && map[key].toString().trim().isNotEmpty,
          isTrue,
          reason: '${file.path} is missing or has empty value for key "$key"',
        );
      }

      final devDesc = map['badgeDeveloperDesc']!.toString().toLowerCase();
      expect(
        devDesc.contains('контрибьютор') || devDesc.contains('contributor'),
        isFalse,
        reason: '${file.path} badgeDeveloperDesc must not mention contributor',
      );
    }

    final ruMap = jsonDecode(File('assets/l10n/ru.json').readAsStringSync()) as Map<String, dynamic>;
    final ruDesignerDesc = ruMap['badgeDesignerDesc']!.toString().toLowerCase();
    expect(
      ruDesignerDesc.contains('визуал') || ruDesignerDesc.contains('стил') || ruDesignerDesc.contains('дизайн'),
      isTrue,
    );
  });

  test('PeerCustomization JSON roundtrip filters expired emoji status and hidden badge', () {
    final futureIso = DateTime.now().toUtc().add(const Duration(hours: 2)).toIso8601String();
    final pastIso = DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String();

    final activeCust = PeerCustomization.fromJson({
      'avatar_decoration': {
        'id': 'neon_pulse',
        'name_key': 'decoNeonPulse',
        'category': 'glow',
        'render_mode': 'procedural',
        'procedural_style': 'neon_pulse',
        'primary_color': '#7C4DFF',
        'secondary_color': '#00E5FF',
      },
      'emoji_status': {
        'type': 'unicode',
        'emoji': '🔥',
        'note': 'Building',
        'expires_at': futureIso,
      },
      'badge': {
        'id': 'developer',
        'short_tag': 'DEV',
        'name_key': 'badgeDeveloperName',
        'desc_key': 'badgeDeveloperDesc',
        'category': 'system',
        'accent_color': '#7C4DFF',
      },
      'badge_is_displayed': true,
      'profile_banner_url': 'https://example.com/banner.webp',
    });

    expect(activeCust.avatarDecoration?.id, 'neon_pulse');
    expect(activeCust.activeEmojiStatus?.emoji, '🔥');
    expect(activeCust.visibleBadge?.shortTag, 'DEV');
    expect(activeCust.profileBannerUrl, 'https://example.com/banner.webp');

    final roundtrip = PeerCustomization.fromJson(activeCust.toJson());
    expect(roundtrip.avatarDecoration?.id, 'neon_pulse');
    expect(roundtrip.activeEmojiStatus?.emoji, '🔥');
    expect(roundtrip.visibleBadge?.id, 'developer');

    final hiddenOrExpired = PeerCustomization.fromJson({
      'emoji_status': {
        'type': 'unicode',
        'emoji': '😴',
        'expires_at': pastIso,
      },
      'badge': {
        'id': 'early_adopter',
        'short_tag': 'EARLY',
        'name_key': 'badgeEarlyName',
        'desc_key': 'badgeEarlyDesc',
      },
      'badge_is_displayed': false,
    });

    expect(hiddenOrExpired.activeEmojiStatus, isNull);
    expect(hiddenOrExpired.badge?.id, 'early_adopter');
    expect(hiddenOrExpired.visibleBadge, isNull);
  });

  test('PeerCustomizationCache notifies listeners and drops expired status on getSync', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = PeerCustomizationCache.instance;
    var notifyCount = 0;
    void listener() => notifyCount++;
    cache.addListener(listener);
    addTearDown(() => cache.removeListener(listener));

    final futureStatus = EmojiStatusData(
      type: 'unicode',
      emoji: '🚀',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
    );
    cache.put(
      'user_42',
      PeerCustomization(emojiStatus: futureStatus, badge: UserBadge.builtInDefaults.first),
    );
    expect(notifyCount, greaterThanOrEqualTo(1));
    expect(cache.getSync('user_42')?.activeEmojiStatus?.emoji, '🚀');
    expect(cache.getSync('user_42')?.visibleBadge?.shortTag, 'CREATOR');

    final expiredStatus = EmojiStatusData(
      type: 'unicode',
      emoji: '⌛',
      expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
    );
    cache.put(
      'user_expired',
      PeerCustomization(emojiStatus: expiredStatus),
      notify: false,
    );
    expect(cache.getSync('user_expired')?.activeEmojiStatus, isNull);
  });

  test(
    'ProfileBannerLayout clamping, PeerCustomization roundtrip, partial merge preservation, clear reset, and expired-status cache clone',
    () {
      SharedPreferences.setMockInitialValues({});
      final clamped = ProfileBannerLayout.fromAppearanceMap({
        'profile_banner_scale': 8.0,
        'profile_banner_pos_x': -4.5,
        'profile_banner_pos_y': 2.2,
        'profile_banner_dim': 0.99,
        'profile_banner_blur': -5.0,
        'profile_banner_height': 'giant',
      });
      expect(clamped.scale, 3.0);
      expect(clamped.posX, -1.0);
      expect(clamped.posY, 1.0);
      expect(clamped.dim, 0.75);
      expect(clamped.blur, 0.0);
      expect(clamped.heightMode, ProfileBannerHeightMode.standard);

      final custom = PeerCustomization.fromJson({
        'profile_banner_url': 'https://example.com/banner.webp',
        'profile_banner_scale': 1.8,
        'profile_banner_pos_x': -0.35,
        'profile_banner_pos_y': 0.42,
        'profile_banner_dim': 0.55,
        'profile_banner_blur': 8.5,
        'profile_banner_height': 'tall',
      });
      expect(custom.bannerLayout.scale, closeTo(1.8, 0.001));
      expect(custom.bannerLayout.posX, closeTo(-0.35, 0.001));
      expect(custom.bannerLayout.posY, closeTo(0.42, 0.001));
      expect(custom.bannerLayout.dim, closeTo(0.55, 0.001));
      expect(custom.bannerLayout.blur, closeTo(8.5, 0.01));
      expect(custom.bannerLayout.heightMode, ProfileBannerHeightMode.tall);

      final roundtrip = PeerCustomization.fromJson(custom.toJson());
      expect(roundtrip.bannerLayout, custom.bannerLayout);

      // Partial chat-list appearance merge without profile_banner_* preserves layout
      final partialMerged = custom.mergeAppearanceMap({
        'name_color_preset_id': 'name_green',
      });
      expect(partialMerged.nameColorPresetId, 'name_green');
      expect(partialMerged.profileBannerUrl, 'https://example.com/banner.webp');
      expect(partialMerged.bannerLayout, custom.bannerLayout);

      // Clearing profile_banner_url resets bannerLayout back to default
      final cleared = partialMerged.mergeAppearanceMap({
        'profile_banner_url': null,
      });
      expect(cleared.profileBannerUrl, isNull);
      expect(cleared.bannerLayout.isDefault, isTrue);

      // Cache getSync strips expired emojiStatus without dropping bannerLayout
      final expiredWithLayout = PeerCustomization(
        profileBannerUrl: 'https://example.com/b.gif',
        bannerLayout: custom.bannerLayout,
        emojiStatus: EmojiStatusData(
          type: 'unicode',
          emoji: '⏳',
          expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 5)),
        ),
      );
      PeerCustomizationCache.instance.put(
        'u_banner_cache',
        expiredWithLayout,
        notify: false,
      );
      final cached = PeerCustomizationCache.instance.getSync('u_banner_cache');
      expect(cached?.activeEmojiStatus, isNull);
      expect(cached?.bannerLayout, custom.bannerLayout);
    },
  );

  test(
    'PeerCustomization bannerLayout getter falls back to default when backing field is null',
    () {
      const emptyDefault = PeerCustomization();
      const explicitNull = PeerCustomization(bannerLayout: null);
      const expected = ProfileBannerLayout();

      expect(emptyDefault.bannerLayout, expected);
      expect(emptyDefault.bannerLayout.isDefault, isTrue);
      expect(explicitNull.bannerLayout, expected);
      expect(explicitNull.isEmpty, isTrue);
    },
  );

  test(
    'ProfileBannerHeightMode snaps heights to physical pixels across fractional DPIs and avoids landmark collisions',
    () {
      const fractionalDprs = <double>[1.25, 1.5, 1.75, 2.625, 2.75, 3.5];
      const topSpacerHeight = 188.727272;
      const topContentPadding = 94.727272;

      for (final dpr in fractionalDprs) {
        final compactProfile = ProfileBannerHeightMode.compact
            .resolveProfileHeight(topSpacerHeight, devicePixelRatio: dpr);
        final standardProfile = ProfileBannerHeightMode.standard
            .resolveProfileHeight(topSpacerHeight, devicePixelRatio: dpr);
        final tallProfile = ProfileBannerHeightMode.tall
            .resolveProfileHeight(topSpacerHeight, devicePixelRatio: dpr);

        final compactCustom = ProfileBannerHeightMode.compact
            .resolveCustomizationHeight(topContentPadding, devicePixelRatio: dpr);
        final standardCustom = ProfileBannerHeightMode.standard
            .resolveCustomizationHeight(topContentPadding, devicePixelRatio: dpr);
        final tallCustom = ProfileBannerHeightMode.tall
            .resolveCustomizationHeight(topContentPadding, devicePixelRatio: dpr);

        for (final h in <double>[
          compactProfile,
          standardProfile,
          tallProfile,
          compactCustom,
          standardCustom,
          tallCustom,
        ]) {
          final physical = h * dpr;
          expect(
            (physical - physical.roundToDouble()).abs(),
            lessThan(1e-6),
            reason: 'Expected $h * $dpr = $physical to align to pixel grid',
          );
        }

        expect(compactProfile, lessThan(standardProfile));
        expect(standardProfile, lessThan(tallProfile));
        expect(compactCustom, lessThan(standardCustom));
        expect(standardCustom, lessThan(tallCustom));

        // Landmark clearance on ProfileScreen:
        // compact clears bottom of avatar (topSpacerHeight),
        // standard clears above LiquidGlassProfileButtons (+80),
        // tall clears below LiquidGlassProfileButtons (+138).
        expect(compactProfile, greaterThan(topSpacerHeight));
        expect(standardProfile, lessThan(topSpacerHeight + 80.0));
        expect(tallProfile, greaterThan(topSpacerHeight + 138.0));
      }

      expect(ProfileBannerHeightMode.snapToPixelGrid(175.4, 0), 175.0);
      expect(ProfileBannerHeightMode.snapToPixelGrid(175.4, double.nan), 175.0);
    },
  );

  test(
    'ReplyEmojiData & PeerCustomization.mergeAppearanceMap round-trip set and explicit null clear',
    () {
      const emojiJson = <String, dynamic>{
        'sticker_id': 77,
        'sticker_url': '/uploads/stickers/hello.webp',
        'thumbnail_url': '/uploads/stickers/hello_thumb.webp',
        'sticker_format': 'webp',
      };
      final cust = PeerCustomization.fromJson(<String, dynamic>{
        'name_color_preset_id': 'name_blue',
        'reply_strip_style': 'gradient',
        'reply_emoji': emojiJson,
      });

      expect(cust.replyEmoji, isNotNull);
      expect(cust.replyEmoji!.stickerId, 77);
      expect(cust.replyEmoji!.stickerUrl, '/uploads/stickers/hello.webp');
      expect(cust.replyEmoji!.thumbnailUrl, '/uploads/stickers/hello_thumb.webp');
      expect(cust.replyEmoji!.stickerFormat, 'webp');

      final roundtrip = PeerCustomization.fromJson(cust.toJson());
      expect(roundtrip.replyEmoji, equals(cust.replyEmoji));

      const emptyBaseline = PeerCustomization();
      final mergedWithEmoji = emptyBaseline.mergeAppearanceMap(<String, dynamic>{
        'reply_emoji': emojiJson,
      });
      expect(mergedWithEmoji.replyEmoji?.stickerId, 77);
      expect(mergedWithEmoji.isEmpty, isFalse);

      final mergedPreserved = mergedWithEmoji.mergeAppearanceMap(<String, dynamic>{
        'name_color_preset_id': 'name_green',
      });
      expect(mergedPreserved.replyEmoji?.stickerId, 77);
      expect(mergedPreserved.nameColorPresetId, 'name_green');

      final cleared = mergedPreserved.mergeAppearanceMap(<String, dynamic>{
        'reply_emoji': null,
      });
      expect(cleared.replyEmoji, isNull);
      expect(cleared.nameColorPresetId, 'name_green');
    },
  );
}
