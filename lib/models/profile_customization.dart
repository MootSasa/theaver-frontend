import 'dart:convert';
import 'package:flutter/material.dart';

/// Parses `#RRGGBB` or `#AARRGGBB` hex colors safely with a fallback.
Color parseHexColor(String? hex, Color fallback) {
  if (hex == null || hex.isEmpty) return fallback;
  var cleaned = hex.trim().replaceFirst('#', '');
  if (cleaned.length == 6) {
    cleaned = 'FF$cleaned';
  }
  if (cleaned.length != 8) return fallback;
  final parsed = int.tryParse(cleaned, radix: 16);
  return parsed != null ? Color(parsed) : fallback;
}

int? _tryParseInt(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}

DateTime? _tryParseDateTime(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toUtc();
}

/// Avatar frame decoration preset from `avatar_decorations`.
class AvatarDecorationPreset {
  final String id;
  final String nameKey;
  final String category;
  final String renderMode;
  final String proceduralStyle;
  final String mediaUrl;
  final String mediaFormat;
  final String primaryColorHex;
  final String secondaryColorHex;
  final bool isAnimated;

  const AvatarDecorationPreset({
    required this.id,
    required this.nameKey,
    this.category = 'glow',
    this.renderMode = 'procedural',
    this.proceduralStyle = '',
    this.mediaUrl = '',
    this.mediaFormat = 'lottie',
    this.primaryColorHex = '#7C4DFF',
    this.secondaryColorHex = '#00E5FF',
    this.isAnimated = true,
  });

  Color get primaryColor => parseHexColor(primaryColorHex, const Color(0xFF7C4DFF));
  Color get secondaryColor => parseHexColor(secondaryColorHex, const Color(0xFF00E5FF));
  bool get isMedia => renderMode == 'media' && mediaUrl.isNotEmpty;

  factory AvatarDecorationPreset.fromJson(Map<String, dynamic> json) {
    return AvatarDecorationPreset(
      id: (json['id'] ?? '').toString(),
      nameKey: (json['name_key'] ?? '').toString(),
      category: (json['category'] ?? 'glow').toString(),
      renderMode: (json['render_mode'] ?? 'procedural').toString(),
      proceduralStyle: (json['procedural_style'] ?? json['id'] ?? '').toString(),
      mediaUrl: (json['media_url'] ?? '').toString(),
      mediaFormat: (json['media_format'] ?? 'lottie').toString(),
      primaryColorHex: (json['primary_color'] ?? '#7C4DFF').toString(),
      secondaryColorHex: (json['secondary_color'] ?? '#00E5FF').toString(),
      isAnimated: json['is_animated'] == null ? true : json['is_animated'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name_key': nameKey,
        'category': category,
        'render_mode': renderMode,
        'procedural_style': proceduralStyle,
        'media_url': mediaUrl,
        'media_format': mediaFormat,
        'primary_color': primaryColorHex,
        'secondary_color': secondaryColorHex,
        'is_animated': isAnimated,
      };

  static const List<AvatarDecorationPreset> builtInDefaults = [
    AvatarDecorationPreset(
      id: 'neon_pulse',
      nameKey: 'decoNeonPulse',
      category: 'glow',
      proceduralStyle: 'neon_pulse',
      primaryColorHex: '#7C4DFF',
      secondaryColorHex: '#00E5FF',
    ),
    AvatarDecorationPreset(
      id: 'aurora_halo',
      nameKey: 'decoAuroraHalo',
      category: 'glow',
      proceduralStyle: 'aurora_halo',
      primaryColorHex: '#00E676',
      secondaryColorHex: '#7C4DFF',
    ),
    AvatarDecorationPreset(
      id: 'sakura_petals',
      nameKey: 'decoSakuraPetals',
      category: 'seasonal',
      proceduralStyle: 'sakura_petals',
      primaryColorHex: '#FF80AB',
      secondaryColorHex: '#FCE4EC',
    ),
    AvatarDecorationPreset(
      id: 'cyber_grid',
      nameKey: 'decoCyberGrid',
      category: 'frame',
      proceduralStyle: 'cyber_grid',
      primaryColorHex: '#00E5FF',
      secondaryColorHex: '#18FFFF',
    ),
    AvatarDecorationPreset(
      id: 'golden_laurel',
      nameKey: 'decoGoldenLaurel',
      category: 'frame',
      proceduralStyle: 'golden_laurel',
      primaryColorHex: '#FFD740',
      secondaryColorHex: '#FFAB00',
      isAnimated: false,
    ),
    AvatarDecorationPreset(
      id: 'frost_crystal',
      nameKey: 'decoFrostCrystal',
      category: 'seasonal',
      proceduralStyle: 'frost_crystal',
      primaryColorHex: '#80D8FF',
      secondaryColorHex: '#E1F5FE',
    ),
    AvatarDecorationPreset(
      id: 'prism_glass',
      nameKey: 'decoPrismGlass',
      category: 'animated',
      proceduralStyle: 'prism_glass',
      primaryColorHex: '#FF4081',
      secondaryColorHex: '#00E5FF',
    ),
    AvatarDecorationPreset(
      id: 'ember_flame',
      nameKey: 'decoEmberFlame',
      category: 'animated',
      proceduralStyle: 'ember_flame',
      primaryColorHex: '#FF6D00',
      secondaryColorHex: '#FFD180',
    ),
    AvatarDecorationPreset(
      id: 'starlight_orbit',
      nameKey: 'decoStarlightOrbit',
      category: 'animated',
      proceduralStyle: 'starlight_orbit',
      primaryColorHex: '#B388FF',
      secondaryColorHex: '#80D8FF',
    ),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvatarDecorationPreset &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          renderMode == other.renderMode &&
          proceduralStyle == other.proceduralStyle &&
          mediaUrl == other.mediaUrl;

  @override
  int get hashCode => Object.hash(id, renderMode, proceduralStyle, mediaUrl);
}

/// Active emoji status attached next to user's name.
class EmojiStatusData {
  final String type; // "unicode" or "sticker"
  final String? emoji;
  final int? stickerId;
  final String? stickerUrl;
  final String? thumbnailUrl;
  final String? stickerFormat;
  final String note;
  final DateTime? expiresAt;

  const EmojiStatusData({
    required this.type,
    this.emoji,
    this.stickerId,
    this.stickerUrl,
    this.thumbnailUrl,
    this.stickerFormat,
    this.note = '',
    this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now().toUtc());

  bool get isValid =>
      !isExpired &&
      ((type == 'unicode' && emoji != null && emoji!.isNotEmpty) ||
          (type == 'sticker' && stickerId != null && stickerId! > 0));

  EmojiStatusData? get activeOrNull => isValid ? this : null;

  factory EmojiStatusData.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? '').toString();
    final stickerId = _tryParseInt(json['sticker_id']);
    final emoji = json['emoji']?.toString();
    final inferredType = rawType.isNotEmpty
        ? rawType
        : ((stickerId != null && stickerId > 0) ? 'sticker' : 'unicode');
    return EmojiStatusData(
      type: inferredType,
      emoji: (emoji != null && emoji.isNotEmpty) ? emoji : null,
      stickerId: stickerId,
      stickerUrl: json['sticker_url']?.toString(),
      thumbnailUrl: json['thumbnail_url']?.toString(),
      stickerFormat: json['sticker_format']?.toString(),
      note: (json['note'] ?? '').toString(),
      expiresAt: _tryParseDateTime(json['expires_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (emoji != null) 'emoji': emoji,
        if (stickerId != null) 'sticker_id': stickerId,
        if (stickerUrl != null) 'sticker_url': stickerUrl,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
        if (stickerFormat != null) 'sticker_format': stickerFormat,
        if (note.isNotEmpty) 'note': note,
        if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmojiStatusData &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          emoji == other.emoji &&
          stickerId == other.stickerId &&
          note == other.note &&
          expiresAt == other.expiresAt;

  @override
  int get hashCode => Object.hash(type, emoji, stickerId, note, expiresAt);
}

/// Single role/achievement badge rendered as a short capsule (`CREATOR`, `DEV`, etc.).
class UserBadge {
  final String id;
  final String shortTag;
  final String nameKey;
  final String descKey;
  final String category;
  final String accentColorHex;
  final DateTime? grantedAt;
  final bool isAssignableByCreator;
  final int? autoGrantLimit;
  final int autoGrantedCount;

  const UserBadge({
    required this.id,
    required this.shortTag,
    required this.nameKey,
    required this.descKey,
    this.category = 'system',
    this.accentColorHex = '#7C4DFF',
    this.grantedAt,
    this.isAssignableByCreator = true,
    this.autoGrantLimit,
    this.autoGrantedCount = 0,
  });

  Color get accentColor => parseHexColor(accentColorHex, const Color(0xFF7C4DFF));

  factory UserBadge.fromJson(Map<String, dynamic> json) {
    return UserBadge(
      id: (json['id'] ?? '').toString(),
      shortTag: (json['short_tag'] ?? '').toString(),
      nameKey: (json['name_key'] ?? '').toString(),
      descKey: (json['desc_key'] ?? '').toString(),
      category: (json['category'] ?? 'system').toString(),
      accentColorHex: (json['accent_color'] ?? '#7C4DFF').toString(),
      grantedAt: _tryParseDateTime(json['granted_at']),
      isAssignableByCreator: json['is_assignable_by_creator'] == null
          ? (json['id']?.toString() != 'creator')
          : json['is_assignable_by_creator'] == true,
      autoGrantLimit: _tryParseInt(json['auto_grant_limit']),
      autoGrantedCount: _tryParseInt(json['auto_granted_count']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'short_tag': shortTag,
        'name_key': nameKey,
        'desc_key': descKey,
        'category': category,
        'accent_color': accentColorHex,
        if (grantedAt != null) 'granted_at': grantedAt!.toUtc().toIso8601String(),
        'is_assignable_by_creator': isAssignableByCreator,
        if (autoGrantLimit != null) 'auto_grant_limit': autoGrantLimit,
        'auto_granted_count': autoGrantedCount,
      };

  static const List<UserBadge> builtInDefaults = [
    UserBadge(
      id: 'creator',
      shortTag: 'CREATOR',
      nameKey: 'badgeCreatorName',
      descKey: 'badgeCreatorDesc',
      category: 'system',
      accentColorHex: '#FF6D00',
      isAssignableByCreator: false,
    ),
    UserBadge(
      id: 'developer',
      shortTag: 'DEV',
      nameKey: 'badgeDeveloperName',
      descKey: 'badgeDeveloperDesc',
      category: 'system',
      accentColorHex: '#7C4DFF',
    ),
    UserBadge(
      id: 'designer',
      shortTag: 'DESIGN',
      nameKey: 'badgeDesignerName',
      descKey: 'badgeDesignerDesc',
      category: 'achievement',
      accentColorHex: '#00E676',
    ),
    UserBadge(
      id: 'early_adopter',
      shortTag: 'EARLY',
      nameKey: 'badgeEarlyName',
      descKey: 'badgeEarlyDesc',
      category: 'achievement',
      accentColorHex: '#FFD600',
      autoGrantLimit: 100,
    ),
    UserBadge(
      id: 'supporter',
      shortTag: 'BOOST',
      nameKey: 'badgeSupporterName',
      descKey: 'badgeSupporterDesc',
      category: 'support',
      accentColorHex: '#FF4081',
    ),
    UserBadge(
      id: 'bug_hunter',
      shortTag: 'BUG',
      nameKey: 'badgeBugHunterName',
      descKey: 'badgeBugHunterDesc',
      category: 'achievement',
      accentColorHex: '#00B0FF',
    ),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserBadge &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          shortTag == other.shortTag &&
          accentColorHex == other.accentColorHex;

  @override
  int get hashCode => Object.hash(id, shortTag, accentColorHex);
}

/// Complete compact customization object carried across chats, messages, members, and cache.
class PeerCustomization {
  final String? nameColorPresetId;
  final String? replyStripStyle;
  final String? profileColorPresetId;
  final AvatarDecorationPreset? avatarDecoration;
  final EmojiStatusData? emojiStatus;
  final UserBadge? badge;
  final bool badgeIsDisplayed;
  final String? profileBannerUrl;

  const PeerCustomization({
    this.nameColorPresetId,
    this.replyStripStyle,
    this.profileColorPresetId,
    this.avatarDecoration,
    this.emojiStatus,
    this.badge,
    this.badgeIsDisplayed = true,
    this.profileBannerUrl,
  });

  EmojiStatusData? get activeEmojiStatus => emojiStatus?.activeOrNull;

  UserBadge? get visibleBadge =>
      (badge != null && badge!.id.isNotEmpty && badgeIsDisplayed) ? badge : null;

  bool get isEmpty =>
      (nameColorPresetId == null || nameColorPresetId!.isEmpty) &&
      (replyStripStyle == null || replyStripStyle!.isEmpty) &&
      (profileColorPresetId == null || profileColorPresetId!.isEmpty) &&
      avatarDecoration == null &&
      activeEmojiStatus == null &&
      badge == null &&
      (profileBannerUrl == null || profileBannerUrl!.isEmpty);

  factory PeerCustomization.fromJson(Map<String, dynamic> json) {
    final decRaw = json['avatar_decoration'];
    final statusRaw = json['emoji_status'];
    final badgeRaw = json['badge'];

    AvatarDecorationPreset? parsedDec;
    if (decRaw is Map<String, dynamic>) {
      parsedDec = AvatarDecorationPreset.fromJson(decRaw);
      if (parsedDec.id.isEmpty) parsedDec = null;
    } else if (decRaw is Map) {
      parsedDec = AvatarDecorationPreset.fromJson(Map<String, dynamic>.from(decRaw));
      if (parsedDec.id.isEmpty) parsedDec = null;
    }

    EmojiStatusData? parsedStatus;
    if (statusRaw is Map<String, dynamic>) {
      parsedStatus = EmojiStatusData.fromJson(statusRaw).activeOrNull;
    } else if (statusRaw is Map) {
      parsedStatus = EmojiStatusData.fromJson(Map<String, dynamic>.from(statusRaw)).activeOrNull;
    }

    UserBadge? parsedBadge;
    if (badgeRaw is Map<String, dynamic>) {
      parsedBadge = UserBadge.fromJson(badgeRaw);
      if (parsedBadge.id.isEmpty) parsedBadge = null;
    } else if (badgeRaw is Map) {
      parsedBadge = UserBadge.fromJson(Map<String, dynamic>.from(badgeRaw));
      if (parsedBadge.id.isEmpty) parsedBadge = null;
    }

    final banner = json['profile_banner_url']?.toString();
    return PeerCustomization(
      nameColorPresetId: json['name_color_preset_id']?.toString(),
      replyStripStyle: json['reply_strip_style']?.toString(),
      profileColorPresetId: json['profile_color_preset_id']?.toString(),
      avatarDecoration: parsedDec,
      emojiStatus: parsedStatus,
      badge: parsedBadge,
      badgeIsDisplayed:
          json['badge_is_displayed'] == null ? true : json['badge_is_displayed'] == true,
      profileBannerUrl: (banner != null && banner.isNotEmpty) ? banner : null,
    );
  }

  static PeerCustomization? tryParseJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return PeerCustomization.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }

  /// Applies a partial/full appearance update where explicit keys with `null` values clear prior values.
  PeerCustomization mergeAppearanceMap(Map<String, dynamic> map) {
    return PeerCustomization(
      nameColorPresetId: map.containsKey('name_color_preset_id')
          ? map['name_color_preset_id']?.toString()
          : nameColorPresetId,
      replyStripStyle: map.containsKey('reply_strip_style')
          ? map['reply_strip_style']?.toString()
          : replyStripStyle,
      profileColorPresetId: map.containsKey('profile_color_preset_id')
          ? map['profile_color_preset_id']?.toString()
          : profileColorPresetId,
      avatarDecoration: map.containsKey('avatar_decoration')
          ? (map['avatar_decoration'] is Map
              ? AvatarDecorationPreset.fromJson(
                  Map<String, dynamic>.from(map['avatar_decoration'] as Map))
              : null)
          : avatarDecoration,
      emojiStatus: map.containsKey('emoji_status')
          ? (map['emoji_status'] is Map
              ? EmojiStatusData.fromJson(
                  Map<String, dynamic>.from(map['emoji_status'] as Map)).activeOrNull
              : null)
          : activeEmojiStatus,
      badge: map.containsKey('badge')
          ? (map['badge'] is Map
              ? UserBadge.fromJson(Map<String, dynamic>.from(map['badge'] as Map))
              : null)
          : badge,
      badgeIsDisplayed: map.containsKey('badge_is_displayed')
          ? (map['badge_is_displayed'] == null ? true : map['badge_is_displayed'] == true)
          : badgeIsDisplayed,
      profileBannerUrl: map.containsKey('profile_banner_url')
          ? (map['profile_banner_url']?.toString().isNotEmpty == true
              ? map['profile_banner_url'].toString()
              : null)
          : profileBannerUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        if (nameColorPresetId != null && nameColorPresetId!.isNotEmpty)
          'name_color_preset_id': nameColorPresetId,
        if (replyStripStyle != null && replyStripStyle!.isNotEmpty)
          'reply_strip_style': replyStripStyle,
        if (profileColorPresetId != null && profileColorPresetId!.isNotEmpty)
          'profile_color_preset_id': profileColorPresetId,
        'avatar_decoration': avatarDecoration?.toJson(),
        'emoji_status': activeEmojiStatus?.toJson(),
        'badge': badge?.toJson(),
        'badge_is_displayed': badgeIsDisplayed,
        if (profileBannerUrl != null && profileBannerUrl!.isNotEmpty)
          'profile_banner_url': profileBannerUrl,
      };

  String toJsonString() => jsonEncode(toJson());
}
