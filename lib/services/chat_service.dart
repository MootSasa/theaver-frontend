import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:drift/drift.dart' as drift;
import '../config/app_config.dart';
import 'auth_service.dart';
import 'database/app_database.dart';
import 'notification_service.dart';
import 'websocket_service.dart';
import '../utils/date_time_utils.dart';
import '../models/chat_draft.dart';
import '../models/profile_customization.dart';
import '../utils/emoji_utils.dart';
import 'community_service.dart';
import 'peer_customization_cache.dart';

String? _nonEmptyString(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  return s.isNotEmpty ? s : null;
}

bool _parseBoolFlag(dynamic raw, {bool defaultValue = false}) {
  if (raw == null) return defaultValue;
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  final s = raw.toString().trim().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return defaultValue;
}

int? _parseNullableInt(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString().trim());
}

int _parseIntValue(dynamic raw, {int defaultValue = 0}) {
  return _parseNullableInt(raw) ?? defaultValue;
}

List<int> _parseIntList(dynamic raw) {
  if (raw == null) return const [];
  dynamic decoded = raw;
  if (raw is String) {
    final s = raw.trim();
    if (s.isEmpty || s == 'null') return const [];
    try {
      decoded = jsonDecode(s);
    } catch (_) {
      return const [];
    }
  }
  if (decoded is! List) return const [];
  final result = <int>[];
  for (final item in decoded) {
    final parsed = item is num ? item.toInt() : int.tryParse(item.toString());
    if (parsed != null && parsed > 0) {
      result.add(parsed);
    }
  }
  return result;
}

/// Default member permissions for a group chat.
class GroupDefaultPermissions {
  final bool canSendMessages;
  final bool canSendMedia;
  final bool canSendPhotos;
  final bool canSendVideos;
  final bool canSendMusic;
  final bool canSendFiles;
  final bool canSendVoiceNotes;
  final bool canSendVideoNotes;
  final bool canSendStickersGifs;
  final bool canSendPolls;
  final bool canAddWebPagePreviews;
  final bool canPinMessages;
  final bool canInviteUsers;
  final bool canChangeInfo;
  final bool canManageTopics;

  const GroupDefaultPermissions({
    this.canSendMessages = true,
    this.canSendMedia = true,
    this.canSendPhotos = true,
    this.canSendVideos = true,
    this.canSendMusic = true,
    this.canSendFiles = true,
    this.canSendVoiceNotes = true,
    this.canSendVideoNotes = true,
    this.canSendStickersGifs = true,
    this.canSendPolls = true,
    this.canAddWebPagePreviews = true,
    this.canPinMessages = false,
    this.canInviteUsers = true,
    this.canChangeInfo = false,
    this.canManageTopics = false,
  });

  factory GroupDefaultPermissions.fromJson(Map<String, dynamic> json) {
    final legacyMedia = json['can_send_media'] != false;
    final photos = json.containsKey('can_send_photos')
        ? json['can_send_photos'] != false
        : legacyMedia;
    final videos = json.containsKey('can_send_videos')
        ? json['can_send_videos'] != false
        : legacyMedia;
    final music = json.containsKey('can_send_music')
        ? json['can_send_music'] != false
        : legacyMedia;
    final files = json.containsKey('can_send_files')
        ? json['can_send_files'] != false
        : legacyMedia;
    final voiceNotes = json.containsKey('can_send_voice_notes')
        ? json['can_send_voice_notes'] != false
        : legacyMedia;
    final videoNotes = json.containsKey('can_send_video_notes')
        ? json['can_send_video_notes'] != false
        : legacyMedia;
    final anyMedia = json.containsKey('can_send_media')
        ? legacyMedia
        : (photos || videos || music || files || voiceNotes || videoNotes);

    return GroupDefaultPermissions(
      canSendMessages: json['can_send_messages'] != false,
      canSendMedia: anyMedia,
      canSendPhotos: photos,
      canSendVideos: videos,
      canSendMusic: music,
      canSendFiles: files,
      canSendVoiceNotes: voiceNotes,
      canSendVideoNotes: videoNotes,
      canSendStickersGifs: json['can_send_stickers_gifs'] != false,
      canSendPolls: json['can_send_polls'] != false,
      canAddWebPagePreviews: json.containsKey('can_add_web_page_previews')
          ? json['can_add_web_page_previews'] != false
          : true,
      canPinMessages: _parseBoolFlag(json['can_pin_messages']),
      canInviteUsers: json['can_invite_users'] != false,
      canChangeInfo: _parseBoolFlag(json['can_change_info']),
      canManageTopics: _parseBoolFlag(json['can_manage_topics']),
    );
  }

  static GroupDefaultPermissions? tryParse(dynamic raw) {
    if (raw == null) return null;
    if (raw is GroupDefaultPermissions) return raw;
    if (raw is Map<String, dynamic>) {
      return GroupDefaultPermissions.fromJson(raw);
    }
    if (raw is Map) {
      return GroupDefaultPermissions.fromJson(Map<String, dynamic>.from(raw));
    }
    if (raw is String && raw.trim().isNotEmpty && raw != 'null') {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return GroupDefaultPermissions.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      } catch (_) {}
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'can_send_messages': canSendMessages,
        'can_send_media': canSendMedia,
        'can_send_photos': canSendPhotos,
        'can_send_videos': canSendVideos,
        'can_send_music': canSendMusic,
        'can_send_files': canSendFiles,
        'can_send_voice_notes': canSendVoiceNotes,
        'can_send_video_notes': canSendVideoNotes,
        'can_send_stickers_gifs': canSendStickersGifs,
        'can_send_polls': canSendPolls,
        'can_add_web_page_previews': canAddWebPagePreviews,
        'can_pin_messages': canPinMessages,
        'can_invite_users': canInviteUsers,
        'can_change_info': canChangeInfo,
        'can_manage_topics': canManageTopics,
      };

  GroupDefaultPermissions copyWith({
    bool? canSendMessages,
    bool? canSendMedia,
    bool? canSendPhotos,
    bool? canSendVideos,
    bool? canSendMusic,
    bool? canSendFiles,
    bool? canSendVoiceNotes,
    bool? canSendVideoNotes,
    bool? canSendStickersGifs,
    bool? canSendPolls,
    bool? canAddWebPagePreviews,
    bool? canPinMessages,
    bool? canInviteUsers,
    bool? canChangeInfo,
    bool? canManageTopics,
  }) {
    return GroupDefaultPermissions(
      canSendMessages: canSendMessages ?? this.canSendMessages,
      canSendMedia: canSendMedia ?? this.canSendMedia,
      canSendPhotos: canSendPhotos ?? this.canSendPhotos,
      canSendVideos: canSendVideos ?? this.canSendVideos,
      canSendMusic: canSendMusic ?? this.canSendMusic,
      canSendFiles: canSendFiles ?? this.canSendFiles,
      canSendVoiceNotes: canSendVoiceNotes ?? this.canSendVoiceNotes,
      canSendVideoNotes: canSendVideoNotes ?? this.canSendVideoNotes,
      canSendStickersGifs: canSendStickersGifs ?? this.canSendStickersGifs,
      canSendPolls: canSendPolls ?? this.canSendPolls,
      canAddWebPagePreviews:
          canAddWebPagePreviews ?? this.canAddWebPagePreviews,
      canPinMessages: canPinMessages ?? this.canPinMessages,
      canInviteUsers: canInviteUsers ?? this.canInviteUsers,
      canChangeInfo: canChangeInfo ?? this.canChangeInfo,
      canManageTopics: canManageTopics ?? this.canManageTopics,
    );
  }

  /// Intersects group default permissions with individual member restrictions.
  GroupDefaultPermissions intersectWith(MemberRestrictions? restrictions) {
    if (restrictions == null) return this;
    return GroupDefaultPermissions(
      canSendMessages: canSendMessages && restrictions.canSendMessages,
      canSendMedia: canSendMedia && restrictions.canSendMedia,
      canSendPhotos: canSendPhotos && restrictions.canSendPhotos,
      canSendVideos: canSendVideos && restrictions.canSendVideos,
      canSendMusic: canSendMusic && restrictions.canSendMusic,
      canSendFiles: canSendFiles && restrictions.canSendFiles,
      canSendVoiceNotes: canSendVoiceNotes && restrictions.canSendVoiceNotes,
      canSendVideoNotes: canSendVideoNotes && restrictions.canSendVideoNotes,
      canSendStickersGifs:
          canSendStickersGifs && restrictions.canSendStickersGifs,
      canSendPolls: canSendPolls && restrictions.canSendPolls,
      canAddWebPagePreviews:
          canAddWebPagePreviews && restrictions.canAddWebPagePreviews,
      canPinMessages: canPinMessages && restrictions.canPinMessages,
      canInviteUsers: canInviteUsers && restrictions.canInviteUsers,
      canChangeInfo: canChangeInfo && restrictions.canChangeInfo,
      canManageTopics: canManageTopics && restrictions.canManageTopics,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupDefaultPermissions &&
          runtimeType == other.runtimeType &&
          canSendMessages == other.canSendMessages &&
          canSendMedia == other.canSendMedia &&
          canSendPhotos == other.canSendPhotos &&
          canSendVideos == other.canSendVideos &&
          canSendMusic == other.canSendMusic &&
          canSendFiles == other.canSendFiles &&
          canSendVoiceNotes == other.canSendVoiceNotes &&
          canSendVideoNotes == other.canSendVideoNotes &&
          canSendStickersGifs == other.canSendStickersGifs &&
          canSendPolls == other.canSendPolls &&
          canAddWebPagePreviews == other.canAddWebPagePreviews &&
          canPinMessages == other.canPinMessages &&
          canInviteUsers == other.canInviteUsers &&
          canChangeInfo == other.canChangeInfo &&
          canManageTopics == other.canManageTopics;

  @override
  int get hashCode => Object.hash(
        canSendMessages,
        canSendMedia,
        canSendPhotos,
        canSendVideos,
        canSendMusic,
        canSendFiles,
        canSendVoiceNotes,
        canSendVideoNotes,
        canSendStickersGifs,
        canSendPolls,
        canAddWebPagePreviews,
        canPinMessages,
        canInviteUsers,
        canChangeInfo,
        canManageTopics,
      );
}

/// Granular administrator permissions in a group or channel.
class AdminRights {
  final bool canChangeInfo;
  final bool canPostMessages;
  final bool canEditMessages;
  final bool canDeleteMessages;
  final bool canBanUsers;
  final bool canInviteUsers;
  final bool canPinMessages;
  final bool canManageCalls;
  final bool canAddAdmins;
  final bool canManageTopics;

  const AdminRights({
    this.canChangeInfo = false,
    this.canPostMessages = true,
    this.canEditMessages = false,
    this.canDeleteMessages = true,
    this.canBanUsers = true,
    this.canInviteUsers = true,
    this.canPinMessages = true,
    this.canManageCalls = false,
    this.canAddAdmins = false,
    this.canManageTopics = false,
  });

  const AdminRights.all()
      : canChangeInfo = true,
        canPostMessages = true,
        canEditMessages = true,
        canDeleteMessages = true,
        canBanUsers = true,
        canInviteUsers = true,
        canPinMessages = true,
        canManageCalls = true,
        canAddAdmins = true,
        canManageTopics = true;

  factory AdminRights.fromJson(Map<String, dynamic> json) {
    return AdminRights(
      canChangeInfo: _parseBoolFlag(json['can_change_info']),
      canPostMessages: json['can_post_messages'] != false,
      canEditMessages: _parseBoolFlag(json['can_edit_messages']),
      canDeleteMessages: json['can_delete_messages'] != false,
      canBanUsers:
          (json['can_ban_users'] ?? json['can_restrict_members']) != false,
      canInviteUsers: json['can_invite_users'] != false,
      canPinMessages: json['can_pin_messages'] != false,
      canManageCalls: _parseBoolFlag(
        json['can_manage_calls'] ?? json['can_manage_video_chats'],
      ),
      canAddAdmins: _parseBoolFlag(
        json['can_add_admins'] ?? json['can_promote_members'],
      ),
      canManageTopics: _parseBoolFlag(json['can_manage_topics']),
    );
  }

  static AdminRights? tryParse(dynamic raw) {
    if (raw == null) return null;
    if (raw is AdminRights) return raw;
    if (raw is Map<String, dynamic>) return AdminRights.fromJson(raw);
    if (raw is Map) return AdminRights.fromJson(Map<String, dynamic>.from(raw));
    if (raw is String && raw.trim().isNotEmpty && raw != 'null') {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return AdminRights.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'can_change_info': canChangeInfo,
        'can_post_messages': canPostMessages,
        'can_edit_messages': canEditMessages,
        'can_delete_messages': canDeleteMessages,
        'can_ban_users': canBanUsers,
        'can_invite_users': canInviteUsers,
        'can_pin_messages': canPinMessages,
        'can_manage_calls': canManageCalls,
        'can_add_admins': canAddAdmins,
        'can_manage_topics': canManageTopics,
      };

  AdminRights copyWith({
    bool? canChangeInfo,
    bool? canPostMessages,
    bool? canEditMessages,
    bool? canDeleteMessages,
    bool? canBanUsers,
    bool? canInviteUsers,
    bool? canPinMessages,
    bool? canManageCalls,
    bool? canAddAdmins,
    bool? canManageTopics,
  }) {
    return AdminRights(
      canChangeInfo: canChangeInfo ?? this.canChangeInfo,
      canPostMessages: canPostMessages ?? this.canPostMessages,
      canEditMessages: canEditMessages ?? this.canEditMessages,
      canDeleteMessages: canDeleteMessages ?? this.canDeleteMessages,
      canBanUsers: canBanUsers ?? this.canBanUsers,
      canInviteUsers: canInviteUsers ?? this.canInviteUsers,
      canPinMessages: canPinMessages ?? this.canPinMessages,
      canManageCalls: canManageCalls ?? this.canManageCalls,
      canAddAdmins: canAddAdmins ?? this.canAddAdmins,
      canManageTopics: canManageTopics ?? this.canManageTopics,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminRights &&
          runtimeType == other.runtimeType &&
          canChangeInfo == other.canChangeInfo &&
          canPostMessages == other.canPostMessages &&
          canEditMessages == other.canEditMessages &&
          canDeleteMessages == other.canDeleteMessages &&
          canBanUsers == other.canBanUsers &&
          canInviteUsers == other.canInviteUsers &&
          canPinMessages == other.canPinMessages &&
          canManageCalls == other.canManageCalls &&
          canAddAdmins == other.canAddAdmins &&
          canManageTopics == other.canManageTopics;

  @override
  int get hashCode => Object.hash(
        canChangeInfo,
        canPostMessages,
        canEditMessages,
        canDeleteMessages,
        canBanUsers,
        canInviteUsers,
        canPinMessages,
        canManageCalls,
        canAddAdmins,
        canManageTopics,
      );
}

/// Per-member granular restrictions in a group chat.
class MemberRestrictions {
  final bool canSendMessages;
  final bool canSendMedia;
  final bool canSendPhotos;
  final bool canSendVideos;
  final bool canSendMusic;
  final bool canSendFiles;
  final bool canSendVoiceNotes;
  final bool canSendVideoNotes;
  final bool canSendStickersGifs;
  final bool canSendPolls;
  final bool canAddWebPagePreviews;
  final bool canPinMessages;
  final bool canInviteUsers;
  final bool canChangeInfo;
  final bool canManageTopics;

  const MemberRestrictions({
    this.canSendMessages = true,
    this.canSendMedia = true,
    this.canSendPhotos = true,
    this.canSendVideos = true,
    this.canSendMusic = true,
    this.canSendFiles = true,
    this.canSendVoiceNotes = true,
    this.canSendVideoNotes = true,
    this.canSendStickersGifs = true,
    this.canSendPolls = true,
    this.canAddWebPagePreviews = true,
    this.canPinMessages = false,
    this.canInviteUsers = true,
    this.canChangeInfo = false,
    this.canManageTopics = false,
  });

  const MemberRestrictions.readOnly()
      : canSendMessages = false,
        canSendMedia = false,
        canSendPhotos = false,
        canSendVideos = false,
        canSendMusic = false,
        canSendFiles = false,
        canSendVoiceNotes = false,
        canSendVideoNotes = false,
        canSendStickersGifs = false,
        canSendPolls = false,
        canAddWebPagePreviews = false,
        canPinMessages = false,
        canInviteUsers = false,
        canChangeInfo = false,
        canManageTopics = false;

  bool get isReadOnly => !canSendMessages;

  factory MemberRestrictions.fromJson(Map<String, dynamic> json) {
    final legacyMedia = json['can_send_media'] != false;
    final photos = json.containsKey('can_send_photos')
        ? json['can_send_photos'] != false
        : legacyMedia;
    final videos = json.containsKey('can_send_videos')
        ? json['can_send_videos'] != false
        : legacyMedia;
    final music = json.containsKey('can_send_music')
        ? json['can_send_music'] != false
        : legacyMedia;
    final files = json.containsKey('can_send_files')
        ? json['can_send_files'] != false
        : legacyMedia;
    final voiceNotes = json.containsKey('can_send_voice_notes')
        ? json['can_send_voice_notes'] != false
        : legacyMedia;
    final videoNotes = json.containsKey('can_send_video_notes')
        ? json['can_send_video_notes'] != false
        : legacyMedia;
    final anyMedia = json.containsKey('can_send_media')
        ? legacyMedia
        : (photos || videos || music || files || voiceNotes || videoNotes);

    return MemberRestrictions(
      canSendMessages: json['can_send_messages'] != false,
      canSendMedia: anyMedia,
      canSendPhotos: photos,
      canSendVideos: videos,
      canSendMusic: music,
      canSendFiles: files,
      canSendVoiceNotes: voiceNotes,
      canSendVideoNotes: videoNotes,
      canSendStickersGifs: json['can_send_stickers_gifs'] != false,
      canSendPolls: json['can_send_polls'] != false,
      canAddWebPagePreviews: json.containsKey('can_add_web_page_previews')
          ? json['can_add_web_page_previews'] != false
          : true,
      canPinMessages: _parseBoolFlag(json['can_pin_messages']),
      canInviteUsers: json['can_invite_users'] != false,
      canChangeInfo: _parseBoolFlag(json['can_change_info']),
      canManageTopics: _parseBoolFlag(json['can_manage_topics']),
    );
  }

  static MemberRestrictions? tryParse(dynamic raw) {
    if (raw == null) return null;
    if (raw is MemberRestrictions) return raw;
    if (raw is Map<String, dynamic>) return MemberRestrictions.fromJson(raw);
    if (raw is Map) {
      return MemberRestrictions.fromJson(Map<String, dynamic>.from(raw));
    }
    if (raw is String && raw.trim().isNotEmpty && raw != 'null') {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return MemberRestrictions.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      } catch (_) {}
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'can_send_messages': canSendMessages,
        'can_send_media': canSendMedia,
        'can_send_photos': canSendPhotos,
        'can_send_videos': canSendVideos,
        'can_send_music': canSendMusic,
        'can_send_files': canSendFiles,
        'can_send_voice_notes': canSendVoiceNotes,
        'can_send_video_notes': canSendVideoNotes,
        'can_send_stickers_gifs': canSendStickersGifs,
        'can_send_polls': canSendPolls,
        'can_add_web_page_previews': canAddWebPagePreviews,
        'can_pin_messages': canPinMessages,
        'can_invite_users': canInviteUsers,
        'can_change_info': canChangeInfo,
        'can_manage_topics': canManageTopics,
      };

  MemberRestrictions copyWith({
    bool? canSendMessages,
    bool? canSendMedia,
    bool? canSendPhotos,
    bool? canSendVideos,
    bool? canSendMusic,
    bool? canSendFiles,
    bool? canSendVoiceNotes,
    bool? canSendVideoNotes,
    bool? canSendStickersGifs,
    bool? canSendPolls,
    bool? canAddWebPagePreviews,
    bool? canPinMessages,
    bool? canInviteUsers,
    bool? canChangeInfo,
    bool? canManageTopics,
  }) {
    return MemberRestrictions(
      canSendMessages: canSendMessages ?? this.canSendMessages,
      canSendMedia: canSendMedia ?? this.canSendMedia,
      canSendPhotos: canSendPhotos ?? this.canSendPhotos,
      canSendVideos: canSendVideos ?? this.canSendVideos,
      canSendMusic: canSendMusic ?? this.canSendMusic,
      canSendFiles: canSendFiles ?? this.canSendFiles,
      canSendVoiceNotes: canSendVoiceNotes ?? this.canSendVoiceNotes,
      canSendVideoNotes: canSendVideoNotes ?? this.canSendVideoNotes,
      canSendStickersGifs: canSendStickersGifs ?? this.canSendStickersGifs,
      canSendPolls: canSendPolls ?? this.canSendPolls,
      canAddWebPagePreviews:
          canAddWebPagePreviews ?? this.canAddWebPagePreviews,
      canPinMessages: canPinMessages ?? this.canPinMessages,
      canInviteUsers: canInviteUsers ?? this.canInviteUsers,
      canChangeInfo: canChangeInfo ?? this.canChangeInfo,
      canManageTopics: canManageTopics ?? this.canManageTopics,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberRestrictions &&
          runtimeType == other.runtimeType &&
          canSendMessages == other.canSendMessages &&
          canSendMedia == other.canSendMedia &&
          canSendPhotos == other.canSendPhotos &&
          canSendVideos == other.canSendVideos &&
          canSendMusic == other.canSendMusic &&
          canSendFiles == other.canSendFiles &&
          canSendVoiceNotes == other.canSendVoiceNotes &&
          canSendVideoNotes == other.canSendVideoNotes &&
          canSendStickersGifs == other.canSendStickersGifs &&
          canSendPolls == other.canSendPolls &&
          canAddWebPagePreviews == other.canAddWebPagePreviews &&
          canPinMessages == other.canPinMessages &&
          canInviteUsers == other.canInviteUsers &&
          canChangeInfo == other.canChangeInfo &&
          canManageTopics == other.canManageTopics;

  @override
  int get hashCode => Object.hash(
        canSendMessages,
        canSendMedia,
        canSendPhotos,
        canSendVideos,
        canSendMusic,
        canSendFiles,
        canSendVoiceNotes,
        canSendVideoNotes,
        canSendStickersGifs,
        canSendPolls,
        canAddWebPagePreviews,
        canPinMessages,
        canInviteUsers,
        canChangeInfo,
        canManageTopics,
      );
}

/// Reaction configuration for a group or channel ('all' | 'selected' | 'none').
class ReactionSettings {
  final String mode; // 'all' | 'selected' | 'none'
  final List<String> allowedReactions;
  final int maxReactionsPerPost;

  const ReactionSettings({
    this.mode = 'all',
    this.allowedReactions = const [],
    this.maxReactionsPerPost = 11,
  });

  bool get isNone => mode == 'none';
  bool get isAll => mode == 'all';
  bool get isSelected => mode == 'selected';

  bool isReactionAllowed(String emoji) {
    if (mode == 'none') return false;
    if (mode == 'selected') return allowedReactions.contains(emoji);
    return true;
  }

  factory ReactionSettings.fromJson(Map<String, dynamic> json) {
    final rawMode = (json['mode'] ?? json['reaction_mode'] ?? 'all').toString();
    final normalizedMode =
        (rawMode == 'all' || rawMode == 'selected' || rawMode == 'none')
            ? rawMode
            : 'all';
    final rawAllowed = json['allowed_reactions'] ?? json['allowedReactions'];
    final allowed = <String>[];
    if (rawAllowed is List) {
      for (final item in rawAllowed) {
        final s = item?.toString().trim() ?? '';
        if (s.isNotEmpty) allowed.add(s);
      }
    } else if (rawAllowed is String && rawAllowed.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAllowed);
        if (decoded is List) {
          for (final item in decoded) {
            final s = item?.toString().trim() ?? '';
            if (s.isNotEmpty) allowed.add(s);
          }
        }
      } catch (_) {}
    }
    final rawMax = _parseIntValue(
      json['max_reactions_per_post'] ?? json['maxReactionsPerPost'],
      defaultValue: 11,
    );
    final clampedMax = rawMax < 1 ? 1 : (rawMax > 11 ? 11 : rawMax);
    return ReactionSettings(
      mode: normalizedMode,
      allowedReactions: List<String>.unmodifiable(allowed),
      maxReactionsPerPost: clampedMax,
    );
  }

  static ReactionSettings? tryParse(dynamic raw) {
    if (raw == null) return null;
    if (raw is ReactionSettings) return raw;
    if (raw is Map<String, dynamic>) return ReactionSettings.fromJson(raw);
    if (raw is Map) {
      return ReactionSettings.fromJson(Map<String, dynamic>.from(raw));
    }
    if (raw is String && raw.trim().isNotEmpty && raw != 'null') {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return ReactionSettings.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    return null;
  }

  static ReactionSettings? fromChatJson(Map<String, dynamic> json) {
    final nested = tryParse(json['reaction_settings']);
    if (nested != null) {
      if (json.containsKey('max_reactions_per_post')) {
        final rawMax = _parseIntValue(
          json['max_reactions_per_post'],
          defaultValue: nested.maxReactionsPerPost,
        );
        return nested.copyWith(
          maxReactionsPerPost: rawMax < 1 ? 1 : (rawMax > 11 ? 11 : rawMax),
        );
      }
      return nested;
    }
    if (json.containsKey('reaction_mode') ||
        json.containsKey('allowed_reactions') ||
        json.containsKey('max_reactions_per_post')) {
      return ReactionSettings.fromJson(json);
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'reaction_mode': mode,
        'allowed_reactions': allowedReactions,
        'max_reactions_per_post': maxReactionsPerPost,
      };

  ReactionSettings copyWith({
    String? mode,
    List<String>? allowedReactions,
    int? maxReactionsPerPost,
  }) {
    return ReactionSettings(
      mode: mode ?? this.mode,
      allowedReactions: allowedReactions ?? this.allowedReactions,
      maxReactionsPerPost: maxReactionsPerPost ?? this.maxReactionsPerPost,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReactionSettings &&
          runtimeType == other.runtimeType &&
          mode == other.mode &&
          maxReactionsPerPost == other.maxReactionsPerPost &&
          listEquals(allowedReactions, other.allowedReactions);

  @override
  int get hashCode => Object.hash(
        mode,
        maxReactionsPerPost,
        Object.hashAll(allowedReactions),
      );
}

/// Compact summary of a recent commenter on a channel post.
class RecentReplier {
  final String userId;
  final String displayName;
  final String? avatarUrl;

  const RecentReplier({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  factory RecentReplier.fromJson(Map<String, dynamic> json) {
    return RecentReplier(
      userId: (json['user_id'] ?? json['id'] ?? '').toString(),
      displayName: (json['display_name'] ?? json['name'] ?? '').toString(),
      avatarUrl: _nonEmptyString(json['avatar_url']),
    );
  }

  static List<RecentReplier> parseList(dynamic raw) {
    if (raw == null) return const [];
    dynamic listVal = raw;
    if (raw is String && raw.trim().isNotEmpty && raw != 'null') {
      try {
        listVal = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (listVal is! List) return const [];
    final result = <RecentReplier>[];
    for (final item in listVal) {
      if (item is Map) {
        result.add(RecentReplier.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecentReplier &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          displayName == other.displayName &&
          avatarUrl == other.avatarUrl;

  @override
  int get hashCode => Object.hash(userId, displayName, avatarUrl);
}

/// Summary of a linked discussion group (for a channel) or linked channel (for a group).
class LinkedChatSummary {
  final String id;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String chatType;
  final int memberCount;

  const LinkedChatSummary({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
    this.chatType = 'group',
    this.memberCount = 0,
  });

  factory LinkedChatSummary.fromJson(Map<String, dynamic> json) {
    return LinkedChatSummary(
      id: (json['id'] ?? json['chat_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      username: _nonEmptyString(json['username']),
      avatarUrl: _nonEmptyString(json['avatar_url']),
      chatType: (json['chat_type'] ?? 'group').toString(),
      memberCount: _parseIntValue(json['member_count']),
    );
  }

  static LinkedChatSummary? tryParse(dynamic raw) {
    if (raw == null) return null;
    if (raw is LinkedChatSummary) return raw;
    if (raw is Map<String, dynamic>) return LinkedChatSummary.fromJson(raw);
    if (raw is Map) {
      return LinkedChatSummary.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (username != null) 'username': username,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'chat_type': chatType,
        'member_count': memberCount,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkedChatSummary &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          username == other.username &&
          avatarUrl == other.avatarUrl &&
          chatType == other.chatType &&
          memberCount == other.memberCount;

  @override
  int get hashCode =>
      Object.hash(id, name, username, avatarUrl, chatType, memberCount);
}

/// Result returned when fetching comments for a channel post.
class PostCommentsResult {
  final Message? rootPost;
  final List<Message> comments;
  final String? linkedChatId;
  final bool hasMore;
  final bool canComment;
  final bool success;
  final String? errorMessage;

  const PostCommentsResult({
    this.rootPost,
    this.comments = const [],
    this.linkedChatId,
    this.hasMore = false,
    this.canComment = true,
    this.success = true,
    this.errorMessage,
  });

  factory PostCommentsResult.fromJson(Map<String, dynamic> json) {
    Message? parsedRoot;
    if (json['root_post'] is Map) {
      parsedRoot = Message.fromJson(
        Map<String, dynamic>.from(json['root_post'] as Map),
      );
    }
    final parsedComments = <Message>[];
    if (json['comments'] is List) {
      for (final item in json['comments'] as List) {
        if (item is Map) {
          parsedComments.add(Message.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return PostCommentsResult(
      rootPost: parsedRoot,
      comments: parsedComments,
      linkedChatId: _nonEmptyString(json['linked_chat_id']),
      hasMore: json['has_more'] == true,
      canComment: json['can_comment'] != false,
      success: json['success'] != false,
      errorMessage:
          _nonEmptyString(json['message']) ?? _nonEmptyString(json['error']),
    );
  }
}

/// Invite link metadata for groups and channels.
class InviteLinkItem {
  final int id;
  final String link;
  final String title;
  final int uses;
  final int maxUses;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final bool isRevoked;
  final bool requiresApproval;

  const InviteLinkItem({
    required this.id,
    required this.link,
    this.title = '',
    this.uses = 0,
    this.maxUses = 0,
    this.expiresAt,
    this.createdAt,
    this.isRevoked = false,
    this.requiresApproval = false,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isLimitReached => maxUses > 0 && uses >= maxUses;

  bool get isActive => !isRevoked && !isExpired && !isLimitReached;

  factory InviteLinkItem.fromJson(Map<String, dynamic> json) {
    return InviteLinkItem(
      id: _parseIntValue(json['id']),
      link: (json['link'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      uses: _parseIntValue(json['uses']),
      maxUses: _parseIntValue(json['max_uses']),
      expiresAt: DateTimeUtils.parseUtcDateTime(json['expires_at']),
      createdAt: DateTimeUtils.parseUtcDateTime(json['created_at']),
      isRevoked: _parseBoolFlag(json['is_revoked']),
      requiresApproval: _parseBoolFlag(json['requires_approval']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'link': link,
        'title': title,
        'uses': uses,
        'max_uses': maxUses,
        if (expiresAt != null)
          'expires_at': expiresAt!.toUtc().toIso8601String(),
        if (createdAt != null)
          'created_at': createdAt!.toUtc().toIso8601String(),
        'is_revoked': isRevoked,
        'requires_approval': requiresApproval,
      };

  InviteLinkItem copyWith({
    int? id,
    String? link,
    String? title,
    int? uses,
    int? maxUses,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
    DateTime? createdAt,
    bool? isRevoked,
    bool? requiresApproval,
  }) {
    return InviteLinkItem(
      id: id ?? this.id,
      link: link ?? this.link,
      title: title ?? this.title,
      uses: uses ?? this.uses,
      maxUses: maxUses ?? this.maxUses,
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
      createdAt: createdAt ?? this.createdAt,
      isRevoked: isRevoked ?? this.isRevoked,
      requiresApproval: requiresApproval ?? this.requiresApproval,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InviteLinkItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          link == other.link &&
          title == other.title &&
          uses == other.uses &&
          maxUses == other.maxUses &&
          expiresAt == other.expiresAt &&
          createdAt == other.createdAt &&
          isRevoked == other.isRevoked &&
          requiresApproval == other.requiresApproval;

  @override
  int get hashCode => Object.hash(
        id,
        link,
        title,
        uses,
        maxUses,
        expiresAt,
        createdAt,
        isRevoked,
        requiresApproval,
      );
}

/// Scheduled message or send-when-online queue item.
class ScheduledMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String content;
  final String messageType;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final int? width;
  final int? height;
  final int duration;
  final bool isRound;
  final bool hasMediaSpoiler;
  final String? replyToMessageId;
  final bool isQuote;
  final String quoteText;
  final int quoteOffset;
  final int quoteLength;
  final List<MessageEntity> entities;
  final LinkPreviewOptions? linkPreviewOptions;
  final bool invertMedia;
  final Map<String, dynamic>? mediaPayload;
  final String? groupedId;
  final bool isSilent;
  final bool? sendAsAnonymous;
  final DateTime? scheduleAt;
  final bool sendWhenOnline;
  final DateTime? createdAt;

  const ScheduledMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.content = '',
    this.messageType = 'text',
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.width,
    this.height,
    this.duration = 0,
    this.isRound = false,
    this.hasMediaSpoiler = false,
    this.replyToMessageId,
    this.isQuote = false,
    this.quoteText = '',
    this.quoteOffset = 0,
    this.quoteLength = 0,
    this.entities = const [],
    this.linkPreviewOptions,
    this.invertMedia = false,
    this.mediaPayload,
    this.groupedId,
    this.isSilent = false,
    this.sendAsAnonymous,
    this.scheduleAt,
    this.sendWhenOnline = false,
    this.createdAt,
  });

  factory ScheduledMessage.fromJson(Map<String, dynamic> json) {
    final parsedEntities = <MessageEntity>[];
    final rawEntities = json['entities'];
    if (rawEntities is List) {
      for (final item in rawEntities) {
        if (item is Map) {
          parsedEntities.add(
            MessageEntity.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    LinkPreviewOptions? parsedLinkPreview;
    if (json['link_preview_options'] is Map) {
      try {
        parsedLinkPreview = LinkPreviewOptions.fromJson(
          Map<String, dynamic>.from(json['link_preview_options'] as Map),
        );
      } catch (_) {}
    }
    Map<String, dynamic>? parsedMediaPayload;
    if (json['media_payload'] is Map) {
      parsedMediaPayload = Map<String, dynamic>.from(json['media_payload'] as Map);
    }

    return ScheduledMessage(
      id: (json['id'] ?? '').toString(),
      chatId: (json['chat_id'] ?? '').toString(),
      senderId: (json['sender_id'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      messageType: (json['message_type'] ?? 'text').toString(),
      fileUrl: _nonEmptyString(json['file_url']),
      fileName: _nonEmptyString(json['file_name']),
      fileSize: json['file_size'] is num
          ? (json['file_size'] as num).toInt()
          : int.tryParse(json['file_size']?.toString() ?? ''),
      width: json['width'] is num
          ? (json['width'] as num).toInt()
          : int.tryParse(json['width']?.toString() ?? ''),
      height: json['height'] is num
          ? (json['height'] as num).toInt()
          : int.tryParse(json['height']?.toString() ?? ''),
      duration: _parseIntValue(json['duration']),
      isRound: _parseBoolFlag(json['is_round']),
      hasMediaSpoiler: _parseBoolFlag(json['has_media_spoiler']),
      replyToMessageId: _nonEmptyString(json['reply_to_message_id']),
      isQuote: _parseBoolFlag(json['is_quote']),
      quoteText: (json['quote_text'] ?? '').toString(),
      quoteOffset: _parseIntValue(json['quote_offset']),
      quoteLength: _parseIntValue(json['quote_length']),
      entities: parsedEntities,
      linkPreviewOptions: parsedLinkPreview,
      invertMedia: _parseBoolFlag(json['invert_media']),
      mediaPayload: parsedMediaPayload,
      groupedId: _nonEmptyString(json['grouped_id']),
      isSilent: _parseBoolFlag(json['is_silent']),
      sendAsAnonymous: json.containsKey('send_as_anonymous')
          ? _parseBoolFlag(json['send_as_anonymous'])
          : null,
      scheduleAt: DateTimeUtils.parseUtcDateTime(json['schedule_at']),
      sendWhenOnline: _parseBoolFlag(json['send_when_online']),
      createdAt: DateTimeUtils.parseUtcDateTime(json['created_at']),
    );
  }

  Message toMessage({String senderName = ''}) {
    return Message(
      id: 'sched_$id',
      chatId: chatId,
      senderId: senderId,
      content: content,
      messageType: messageType,
      isEdited: false,
      createdAt: (scheduleAt ?? createdAt ?? DateTime.now().toUtc())
          .toIso8601String(),
      senderName: senderName,
      fileUrl: fileUrl,
      fileName: fileName,
      replyToMessageId: replyToMessageId,
      isQuote: isQuote,
      quoteText: quoteText.isNotEmpty ? quoteText : null,
      quoteOffset: quoteOffset,
      quoteLength: quoteLength,
      entities: entities,
      linkPreviewOptions: linkPreviewOptions,
      invertMedia: invertMedia,
      isRound: isRound,
      duration: duration > 0 ? duration : null,
      mediaPayload: mediaPayload,
      groupedId: groupedId,
      isSilent: isSilent,
      hasMediaSpoiler: hasMediaSpoiler,
    );
  }
}

/// Pending invite-link join request item for admins.
class ChatJoinRequest {
  final String id;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final int? inviteLinkId;
  final DateTime? requestedAt;

  const ChatJoinRequest({
    required this.id,
    required this.userId,
    this.username = '',
    this.displayName = '',
    this.avatarUrl,
    this.inviteLinkId,
    this.requestedAt,
  });

  factory ChatJoinRequest.fromJson(Map<String, dynamic> json) {
    final uid = (json['user_id'] ?? json['id'] ?? '').toString();
    return ChatJoinRequest(
      id: (json['id'] ?? uid).toString(),
      userId: uid,
      username: (json['username'] ?? '').toString(),
      displayName: (json['display_name'] ?? json['username'] ?? 'Пользователь')
          .toString(),
      avatarUrl: _nonEmptyString(json['avatar_url']),
      inviteLinkId: json['invite_link_id'] is num
          ? (json['invite_link_id'] as num).toInt()
          : int.tryParse(json['invite_link_id']?.toString() ?? ''),
      requestedAt: DateTimeUtils.parseUtcDateTime(json['requested_at']),
    );
  }
}

/// Real-time update event emitted by [ChatService.realtimeUpdates].
class ChatRealtimeUpdate {
  final WebSocketEventType type;
  final String chatId;
  final Map<String, dynamic> data;

  const ChatRealtimeUpdate({
    required this.type,
    required this.chatId,
    required this.data,
  });
}

/// Chat represents a chat conversation.
class Chat {
  final String id;
  final String chatType; // 'private', 'group', 'channel', 'saved', 'system'
  final String name;
  final String? avatarUrl;
  final String? lastMessage;
  final String? lastMessageTime;
  final String? lastMessageType;
  final bool lastMessageIsRound;
  final String? lastMessageFileUrl;
  final String updatedAt;
  final int unreadCount;
  final bool isOnline; // Online status for private chats
  final String? lastSeen; // Last seen time for private chats
  final bool isPinned; // Whether chat is pinned
  final String? otherUserId;
  final String? lastMessageGroupedId;
  final List<MessageEntity> lastMessageEntities;
  final ChatDraft? draft;
  final int lastReadInboxMessageId;
  final int lastReadOutboxMessageId;
  final int? pinnedMessageId;
  final Message? pinnedMessage;
  final List<int> pinnedMessageIds;
  final bool hasProtectedContent;
  final String? username;
  final bool isPublic;
  final bool isBot;
  final bool isVerified;
  final bool isArchived;
  final int? communityId;
  final bool showAuthorProfiles;
  final bool signMessages;
  final String? linkedChatId;
  final String? myRole;
  final bool isMember;
  final String? lastMessageSenderId;
  final String? lastMessageSenderName;
  final bool hasActiveCall;
  final String? activeCallId;
  final GroupDefaultPermissions? defaultPermissions;
  final ReactionSettings? reactionSettings;
  final PeerCustomization? peerCustomization;
  final int messageAutoDeleteTime;
  final Map<String, dynamic>? appearance;
  final bool isForum;
  final bool participantsHidden;
  final bool hasAggressiveAntiSpamEnabled;
  final int maxReactionsPerPost;
  final int unreadMentionsCount;
  final int unreadReactionsCount;
  final String? mySendAsChatId;
  final String? mySendAsMode;
  late final int updatedAtEpochMs =
      DateTimeUtils.parseUtcDateTime(updatedAt)?.millisecondsSinceEpoch ?? 0;

  Chat({
    required this.id,
    required this.chatType,
    required this.name,
    this.avatarUrl,
    this.lastMessage,
    this.lastMessageTime,
    this.lastMessageType,
    this.lastMessageIsRound = false,
    this.lastMessageFileUrl,
    required this.updatedAt,
    this.unreadCount = 0,
    this.isOnline = false,
    this.lastSeen,
    this.isPinned = false,
    this.otherUserId,
    this.lastMessageGroupedId,
    this.lastMessageEntities = const [],
    this.draft,
    this.lastReadInboxMessageId = 0,
    this.lastReadOutboxMessageId = 0,
    this.pinnedMessageId,
    this.pinnedMessage,
    this.pinnedMessageIds = const [],
    this.hasProtectedContent = false,
    this.username,
    this.isPublic = false,
    this.isBot = false,
    this.isVerified = false,
    this.isArchived = false,
    this.communityId,
    bool? showAuthorProfiles,
    this.signMessages = false,
    this.linkedChatId,
    this.myRole,
    this.isMember = true,
    this.lastMessageSenderId,
    this.lastMessageSenderName,
    this.hasActiveCall = false,
    this.activeCallId,
    this.defaultPermissions,
    this.reactionSettings,
    this.peerCustomization,
    this.messageAutoDeleteTime = 0,
    this.appearance,
    this.isForum = false,
    this.participantsHidden = false,
    this.hasAggressiveAntiSpamEnabled = false,
    this.maxReactionsPerPost = 11,
    this.unreadMentionsCount = 0,
    this.unreadReactionsCount = 0,
    this.mySendAsChatId,
    this.mySendAsMode,
  }) : showAuthorProfiles = showAuthorProfiles ?? (chatType != 'channel');

  /// Whether this chat belongs to a community channel
  bool get isCommunityChannel =>
      (communityId != null && communityId! > 0) ||
      CommunityService.isCommunityChannelId(id);

  /// Whether this chat has been manually marked as unread (represented by unreadCount == -1).
  bool get isMarkedUnread => unreadCount == -1;

  /// Whether this chat has unread messages or is marked as unread.
  bool get hasUnread => unreadCount > 0 || isMarkedUnread;

  /// True if the last message in this chat is a round video note («кружочек»)
  bool get isLastMessageRoundVideo =>
      lastMessageIsRound ||
      lastMessageType == 'round' ||
      (lastMessage != null &&
          (lastMessage!.contains('video_note_') ||
              lastMessage == 'Видеосообщение' ||
              lastMessage == 'Video message'));

  /// True if the last message in this chat has an unsupported type.
  bool get isLastMessageUnsupported {
    if (lastMessageType == null || lastMessageType!.isEmpty) return false;
    if (lastMessageType == 'unsupported') return true;
    const supportedTypes = {
      'text',
      'image',
      'photo',
      'video',
      'voice',
      'audio',
      'round',
      'poll',
      'document',
      'file',
      'dice',
      'call',
      'system',
      'sticker',
      'gif',
      'animation',
      'location',
      'live_location',
      'venue',
      'contact',
    };
    return !supportedTypes.contains(lastMessageType!.toLowerCase());
  }

  /// Formats a raw `message_type == 'call'` JSON content string into a human-readable Russian preview.
  static String formatCallPreview(String? rawContent, {String? currentUserId}) {
    if (rawContent == null || rawContent.trim().isEmpty) {
      return '📞 Звонок';
    }
    try {
      final decoded = jsonDecode(rawContent);
      if (decoded is Map) {
        final status = (decoded['status'] ?? '').toString().toLowerCase();
        final reason = (decoded['end_reason'] ?? '').toString().toLowerCase();
        final initiatorId = (decoded['initiator_id'] ?? '').toString();
        final isVideo =
            decoded['video_enabled'] == true ||
            decoded['is_video'] == true ||
            (decoded['call_type'] ?? '').toString().toLowerCase() == 'video';
        final durationSec = _parseIntValue(decoded['duration_seconds']);
        final isOutgoing =
            currentUserId != null &&
            currentUserId.isNotEmpty &&
            initiatorId == currentUserId;
        final icon = isVideo ? '📹' : '📞';
        final callNoun = isVideo ? 'видеозвонок' : 'звонок';

        if (status == 'declined' || reason == 'declined') {
          return isOutgoing
              ? '$icon Отклонённый $callNoun'
              : '$icon Пропущенный $callNoun';
        }
        if (status == 'missed' ||
            reason == 'missed' ||
            reason == 'timeout' ||
            reason == 'unanswered' ||
            ((status == 'canceled' || reason == 'canceled') && !isOutgoing)) {
          return '$icon Пропущенный $callNoun';
        }
        if (status == 'canceled' || reason == 'canceled' || durationSec <= 0) {
          return isOutgoing
              ? '$icon Отменённый $callNoun'
              : '$icon Пропущенный $callNoun';
        }
        final mins = durationSec ~/ 60;
        final secs = (durationSec % 60).toString().padLeft(2, '0');
        final dir = isOutgoing ? 'Исходящий' : 'Входящий';
        return '$icon $dir $callNoun ($mins:$secs)';
      }
    } catch (_) {}
    if (!rawContent.trim().startsWith('{')) {
      return rawContent;
    }
    return '📞 Звонок';
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    final msgType = json['last_message_type']?.toString();
    final isRound = json['last_message_is_round'] == true ||
        msgType == 'round' ||
        (json['is_round'] == true);

    Message? parsedPinnedMessage;
    int? parsedPinnedMessageId = _parseNullableInt(json['pinned_message_id']);
    if (json['pinned_message'] is Map) {
      try {
        parsedPinnedMessage = Message.fromJson(
          Map<String, dynamic>.from(json['pinned_message'] as Map),
        );
        parsedPinnedMessageId ??= int.tryParse(parsedPinnedMessage.id);
      } catch (_) {}
    }

    final rawLastEntities = json['last_message_entities'];
    final parsedLastEntities = <MessageEntity>[];
    if (rawLastEntities is List) {
      for (final item in rawLastEntities) {
        if (item is Map<String, dynamic>) {
          parsedLastEntities.add(MessageEntity.fromJson(item));
        } else if (item is Map) {
          parsedLastEntities.add(
            MessageEntity.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final rawPeerCust = json['peer_customization'];
    final PeerCustomization? parsedPeerCust = rawPeerCust is Map
        ? PeerCustomization.fromJson(Map<String, dynamic>.from(rawPeerCust))
        : (rawPeerCust is String && rawPeerCust.isNotEmpty
            ? PeerCustomization.tryParseJsonString(rawPeerCust)
            : null);
    final parsedChatType = json['chat_type']?.toString() ?? 'private';
    final parsedOtherUserId =
        json['other_user_id']?.toString() ?? json['otherUserId']?.toString();
    if (parsedChatType == 'private' &&
        parsedOtherUserId != null &&
        parsedOtherUserId.isNotEmpty &&
        parsedPeerCust != null) {
      PeerCustomizationCache.instance.put(
        parsedOtherUserId,
        parsedPeerCust,
        notify: false,
      );
    }

    final bool parsedShowAuthorProfiles =
        json.containsKey('show_author_profiles')
            ? _parseBoolFlag(json['show_author_profiles'])
            : (parsedChatType != 'channel');
    final parsedLinkedChatId = _nonEmptyString(json['linked_chat_id']);
    final parsedMyRole = _nonEmptyString(json['my_role']);
    final parsedActiveCallId = _nonEmptyString(json['active_call_id']);
    final parsedIsMember =
        json.containsKey('is_member') ? _parseBoolFlag(json['is_member'], defaultValue: true) : (parsedMyRole != 'guest');
    final parsedHasProtectedContent = _parseBoolFlag(
      json['has_protected_content'] ?? json['noforwards'],
    );
    final parsedPinnedList = _parseIntList(json['pinned_message_ids']);
    final effectivePinnedIds = parsedPinnedList.isNotEmpty
        ? parsedPinnedList
        : (parsedPinnedMessageId != null && parsedPinnedMessageId > 0
            ? <int>[parsedPinnedMessageId]
            : const <int>[]);
    final bool parsedMarkedUnread = _parseBoolFlag(json['is_marked_unread']);
    final int rawUnreadCount = _parseIntValue(json['unread_count']);
    final int effectiveUnreadCount =
        (parsedMarkedUnread && rawUnreadCount == 0) ? -1 : rawUnreadCount;

    return Chat(
      id: json['id']?.toString() ?? json['chat_id']?.toString() ?? '',
      chatType: parsedChatType,
      name: json['name']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString(),
      lastMessage: json['last_message']?.toString(),
      lastMessageTime: json['last_message_time']?.toString(),
      lastMessageType: msgType,
      lastMessageIsRound: isRound,
      lastMessageFileUrl: json['last_message_file_url']?.toString() ??
          json['file_url']?.toString(),
      updatedAt: json['updated_at']?.toString() ?? '',
      unreadCount: effectiveUnreadCount,
      isOnline: _parseBoolFlag(json['is_online']),
      lastSeen: json['last_seen']?.toString(),
      isPinned: _parseBoolFlag(json['is_pinned']),
      otherUserId: parsedOtherUserId,
      lastMessageGroupedId: json['last_message_grouped_id']?.toString(),
      lastMessageEntities: parsedLastEntities,
      draft: json['draft'] != null && json['draft'] is Map<String, dynamic>
          ? ChatDraft.fromJson(json['draft'] as Map<String, dynamic>)
          : null,
      lastReadInboxMessageId:
          _parseIntValue(json['last_read_inbox_message_id']),
      lastReadOutboxMessageId:
          _parseIntValue(json['last_read_outbox_message_id']),
      pinnedMessageId: parsedPinnedMessageId,
      pinnedMessage: parsedPinnedMessage,
      username: json['username']?.toString(),
      isPublic: json['is_public'] == true,
      isBot: json['is_bot'] == true,
      isVerified: json['is_verified'] == true,
      isArchived: json['is_archived'] == true || json['is_archived'] == 1,
      communityId: _parseNullableInt(json['community_id']),
      showAuthorProfiles: parsedShowAuthorProfiles,
      signMessages: _parseBoolFlag(json['sign_messages']),
      linkedChatId: parsedLinkedChatId,
      myRole: parsedMyRole,
      isMember: parsedIsMember,
      lastMessageSenderId: _nonEmptyString(json['last_message_sender_id']),
      lastMessageSenderName: _nonEmptyString(json['last_message_sender_name']),
      hasActiveCall:
          _parseBoolFlag(json['has_active_call']) || parsedActiveCallId != null,
      activeCallId: parsedActiveCallId,
      defaultPermissions: GroupDefaultPermissions.tryParse(
        json['default_permissions'] ?? json['chat_permissions'],
      ),
      reactionSettings: ReactionSettings.fromChatJson(json),
      peerCustomization: parsedPeerCust,
      hasProtectedContent: parsedHasProtectedContent,
      pinnedMessageIds: effectivePinnedIds,
      messageAutoDeleteTime: _parseIntValue(json['message_auto_delete_time']),
      appearance: json['appearance'] is Map
          ? Map<String, dynamic>.from(json['appearance'] as Map)
          : null,
      isForum: _parseBoolFlag(json['is_forum']),
      participantsHidden: _parseBoolFlag(json['participants_hidden']),
      hasAggressiveAntiSpamEnabled:
          _parseBoolFlag(json['has_aggressive_anti_spam_enabled']),
      maxReactionsPerPost: _parseIntValue(
        json['max_reactions_per_post'],
        defaultValue: 11,
      ).clamp(1, 11),
      unreadMentionsCount: _parseIntValue(json['unread_mentions_count']),
      unreadReactionsCount: _parseIntValue(json['unread_reactions_count']),
      mySendAsChatId: _nonEmptyString(json['my_send_as_chat_id']),
      mySendAsMode: _nonEmptyString(json['my_send_as_mode']),
    );
  }

  /// Creates a [Chat] from a Drift [DbChat] row.
  factory Chat.fromDbChat(
    DbChat model, {
    List<MessageEntity> lastMessageEntities = const [],
    int? unreadCountOverride,
    bool? isOnlineOverride,
    String? lastSeenOverride,
    String? activeCallId,
  }) {
    final dbCust = PeerCustomization.tryParseJsonString(
      model.peerCustomizationJson,
    );
    if (model.chatType == 'private' &&
        model.otherUserId != null &&
        model.otherUserId!.isNotEmpty &&
        dbCust != null) {
      PeerCustomizationCache.instance.put(
        model.otherUserId!,
        dbCust,
        notify: false,
      );
    }
    final dbPinnedList = _parseIntList(model.pinnedMessageIdsJson);
    final effectiveDbPinnedIds = dbPinnedList.isNotEmpty
        ? dbPinnedList
        : (model.pinnedMessageId != null && model.pinnedMessageId! > 0
            ? <int>[model.pinnedMessageId!]
            : const <int>[]);
    Map<String, dynamic>? dbAppearance;
    if (model.appearanceJson != null &&
        model.appearanceJson!.isNotEmpty &&
        model.appearanceJson != 'null') {
      try {
        final dec = jsonDecode(model.appearanceJson!);
        if (dec is Map) dbAppearance = Map<String, dynamic>.from(dec);
      } catch (_) {}
    }
    return Chat(
      id: model.chatId,
      chatType: model.chatType,
      name: model.name,
      avatarUrl: model.avatarUrl,
      lastMessage: model.lastMessage,
      lastMessageTime: model.lastMessageTime,
      lastMessageType: model.lastMessageType,
      lastMessageIsRound: model.lastMessageIsRound,
      lastMessageFileUrl: model.lastMessageFileUrl,
      lastMessageGroupedId: model.lastMessageGroupedId,
      lastMessageEntities: lastMessageEntities,
      otherUserId: model.otherUserId,
      updatedAt: model.updatedAt,
      unreadCount: unreadCountOverride ?? model.unreadCount,
      isOnline: isOnlineOverride ?? model.isOnline,
      lastSeen: lastSeenOverride ?? model.lastSeen,
      isPinned: model.isPinned,
      lastReadInboxMessageId: model.lastReadInboxMessageId,
      lastReadOutboxMessageId: model.lastReadOutboxMessageId,
      pinnedMessageId: model.pinnedMessageId,
      username: model.username,
      isPublic: model.isPublic,
      isBot: model.isBot,
      isVerified: model.isVerified,
      isArchived: model.isArchived,
      showAuthorProfiles: model.showAuthorProfiles,
      signMessages: model.signMessages,
      linkedChatId: _nonEmptyString(model.linkedChatId),
      myRole: _nonEmptyString(model.myRole),
      isMember: model.myRole != 'guest',
      lastMessageSenderId: _nonEmptyString(model.lastMessageSenderId),
      lastMessageSenderName: _nonEmptyString(model.lastMessageSenderName),
      hasActiveCall: model.hasActiveCall,
      activeCallId: activeCallId,
      defaultPermissions: GroupDefaultPermissions.tryParse(
        model.chatPermissionsJson,
      ),
      reactionSettings: ReactionSettings.tryParse(model.reactionSettingsJson),
      peerCustomization: dbCust,
      hasProtectedContent: model.hasProtectedContent,
      pinnedMessageIds: effectiveDbPinnedIds,
      messageAutoDeleteTime: model.messageAutoDeleteTime,
      appearance: dbAppearance,
      isForum: model.isForum,
      participantsHidden: model.participantsHidden,
      hasAggressiveAntiSpamEnabled: model.hasAggressiveAntiSpamEnabled,
      maxReactionsPerPost: model.maxReactionsPerPost.clamp(1, 11),
      unreadMentionsCount: model.unreadMentionsCount,
      unreadReactionsCount: model.unreadReactionsCount,
    );
  }

  /// Converts this [Chat] to a Drift [ChatsCompanion].
  ChatsCompanion toCompanion() {
    return ChatsCompanion(
      chatId: drift.Value(id),
      chatType: drift.Value(
        isCommunityChannel ? 'community_channel' : chatType,
      ),
      name: drift.Value(name),
      avatarUrl: drift.Value(avatarUrl),
      lastMessage: drift.Value(lastMessage),
      lastMessageTime: drift.Value(lastMessageTime),
      lastMessageType: drift.Value(lastMessageType),
      lastMessageIsRound: drift.Value(lastMessageIsRound),
      lastMessageFileUrl: drift.Value(lastMessageFileUrl),
      lastMessageGroupedId: drift.Value(lastMessageGroupedId),
      otherUserId: drift.Value(otherUserId),
      updatedAt: drift.Value(updatedAt),
      unreadCount: drift.Value(unreadCount),
      isOnline: drift.Value(isOnline),
      lastSeen: drift.Value(lastSeen),
      isPinned: drift.Value(isPinned),
      lastReadInboxMessageId: drift.Value(lastReadInboxMessageId),
      lastReadOutboxMessageId: drift.Value(lastReadOutboxMessageId),
      pinnedMessageId: drift.Value(pinnedMessageId),
      username: drift.Value(username),
      isPublic: drift.Value(isPublic),
      isBot: drift.Value(isBot),
      isVerified: drift.Value(isVerified),
      isArchived: drift.Value(isArchived),
      showAuthorProfiles: drift.Value(showAuthorProfiles),
      signMessages: drift.Value(signMessages),
      linkedChatId: drift.Value(linkedChatId),
      myRole: drift.Value(myRole),
      lastMessageSenderId: drift.Value(lastMessageSenderId),
      lastMessageSenderName: drift.Value(lastMessageSenderName),
      hasActiveCall: drift.Value(hasActiveCall),
      chatPermissionsJson: defaultPermissions != null
          ? drift.Value(jsonEncode(defaultPermissions!.toJson()))
          : const drift.Value.absent(),
      reactionSettingsJson: reactionSettings != null
          ? drift.Value(jsonEncode(reactionSettings!.toJson()))
          : const drift.Value.absent(),
      peerCustomizationJson: drift.Value(peerCustomization?.toJsonString()),
      hasProtectedContent: drift.Value(hasProtectedContent),
      pinnedMessageIdsJson: pinnedMessageIds.isNotEmpty
          ? drift.Value(jsonEncode(pinnedMessageIds))
          : const drift.Value.absent(),
      messageAutoDeleteTime: drift.Value(messageAutoDeleteTime),
      appearanceJson: appearance != null
          ? drift.Value(jsonEncode(appearance))
          : const drift.Value.absent(),
      isForum: drift.Value(isForum),
      participantsHidden: drift.Value(participantsHidden),
      hasAggressiveAntiSpamEnabled: drift.Value(hasAggressiveAntiSpamEnabled),
      maxReactionsPerPost: drift.Value(maxReactionsPerPost.clamp(1, 11)),
      unreadMentionsCount: drift.Value(unreadMentionsCount),
      unreadReactionsCount: drift.Value(unreadReactionsCount),
    );
  }

  Chat copyWith({
    String? id,
    String? chatType,
    String? name,
    String? avatarUrl,
    String? lastMessage,
    String? lastMessageTime,
    String? lastMessageType,
    bool? lastMessageIsRound,
    String? lastMessageFileUrl,
    String? updatedAt,
    int? unreadCount,
    bool? isOnline,
    String? lastSeen,
    bool? isPinned,
    String? otherUserId,
    String? lastMessageGroupedId,
    List<MessageEntity>? lastMessageEntities,
    ChatDraft? draft,
    int? lastReadInboxMessageId,
    int? lastReadOutboxMessageId,
    int? pinnedMessageId,
    Message? pinnedMessage,
    List<int>? pinnedMessageIds,
    bool? hasProtectedContent,
    String? username,
    bool? isPublic,
    bool? isBot,
    bool? isVerified,
    bool? isArchived,
    int? communityId,
    bool? showAuthorProfiles,
    bool? signMessages,
    String? linkedChatId,
    bool clearLinkedChatId = false,
    String? myRole,
    bool? isMember,
    String? lastMessageSenderId,
    String? lastMessageSenderName,
    bool? hasActiveCall,
    String? activeCallId,
    bool clearActiveCallId = false,
    GroupDefaultPermissions? defaultPermissions,
    ReactionSettings? reactionSettings,
    PeerCustomization? peerCustomization,
    int? messageAutoDeleteTime,
    Map<String, dynamic>? appearance,
    bool clearAppearance = false,
    bool? isForum,
    bool? participantsHidden,
    bool? hasAggressiveAntiSpamEnabled,
    int? maxReactionsPerPost,
    int? unreadMentionsCount,
    int? unreadReactionsCount,
    String? mySendAsChatId,
    bool clearMySendAsChatId = false,
    String? mySendAsMode,
  }) {
    return Chat(
      id: id ?? this.id,
      chatType: chatType ?? this.chatType,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageIsRound: lastMessageIsRound ?? this.lastMessageIsRound,
      lastMessageFileUrl: lastMessageFileUrl ?? this.lastMessageFileUrl,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      isPinned: isPinned ?? this.isPinned,
      otherUserId: otherUserId ?? this.otherUserId,
      lastMessageGroupedId: lastMessageGroupedId ?? this.lastMessageGroupedId,
      lastMessageEntities: lastMessageEntities ?? this.lastMessageEntities,
      draft: draft ?? this.draft,
      lastReadInboxMessageId:
          lastReadInboxMessageId ?? this.lastReadInboxMessageId,
      lastReadOutboxMessageId:
          lastReadOutboxMessageId ?? this.lastReadOutboxMessageId,
      pinnedMessageId: pinnedMessageId ?? this.pinnedMessageId,
      pinnedMessage: pinnedMessage ?? this.pinnedMessage,
      pinnedMessageIds: pinnedMessageIds ?? this.pinnedMessageIds,
      hasProtectedContent: hasProtectedContent ?? this.hasProtectedContent,
      username: username ?? this.username,
      isPublic: isPublic ?? this.isPublic,
      isBot: isBot ?? this.isBot,
      isVerified: isVerified ?? this.isVerified,
      isArchived: isArchived ?? this.isArchived,
      communityId: communityId ?? this.communityId,
      showAuthorProfiles: showAuthorProfiles ?? this.showAuthorProfiles,
      signMessages: signMessages ?? this.signMessages,
      linkedChatId:
          clearLinkedChatId ? null : (linkedChatId ?? this.linkedChatId),
      myRole: myRole ?? this.myRole,
      isMember: isMember ?? this.isMember,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageSenderName:
          lastMessageSenderName ?? this.lastMessageSenderName,
      hasActiveCall: hasActiveCall ?? this.hasActiveCall,
      activeCallId:
          clearActiveCallId ? null : (activeCallId ?? this.activeCallId),
      defaultPermissions: defaultPermissions ?? this.defaultPermissions,
      reactionSettings: reactionSettings ?? this.reactionSettings,
      peerCustomization: peerCustomization ?? this.peerCustomization,
      messageAutoDeleteTime:
          messageAutoDeleteTime ?? this.messageAutoDeleteTime,
      appearance: clearAppearance ? null : (appearance ?? this.appearance),
      isForum: isForum ?? this.isForum,
      participantsHidden: participantsHidden ?? this.participantsHidden,
      hasAggressiveAntiSpamEnabled:
          hasAggressiveAntiSpamEnabled ?? this.hasAggressiveAntiSpamEnabled,
      maxReactionsPerPost: maxReactionsPerPost ?? this.maxReactionsPerPost,
      unreadMentionsCount: unreadMentionsCount ?? this.unreadMentionsCount,
      unreadReactionsCount: unreadReactionsCount ?? this.unreadReactionsCount,
      mySendAsChatId: clearMySendAsChatId
          ? null
          : (mySendAsChatId ?? this.mySendAsChatId),
      mySendAsMode: mySendAsMode ?? this.mySendAsMode,
    );
  }
}

/// ReplyInfo holds cached preview data for the message being replied to.
/// Stored inline with the message for offline-first display without lookup.
class ReplyInfo {
  final String messageId;
  final String senderId;
  final String senderName;
  final String content; // truncated preview text
  final String messageType; // 'text', 'image', etc.
  final String? chatId; // The chat ID where the original message resides
  final String? nameColorPresetId;
  final String? replyStripStyle;
  final ReplyEmojiData? replyEmoji;
  final List<MessageEntity> entities;

  const ReplyInfo({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.messageType,
    this.chatId,
    this.nameColorPresetId,
    this.replyStripStyle,
    this.replyEmoji,
    this.entities = const [],
  });

  /// True if this reply message type is unsupported in the current app version.
  bool get isUnsupported {
    if (messageType == 'unsupported') return true;
    const supportedTypes = {
      'text',
      'image',
      'photo',
      'video',
      'voice',
      'audio',
      'round',
      'poll',
      'document',
      'file',
      'dice',
      'call',
      'system',
      'sticker',
      'gif',
      'animation',
      'location',
      'live_location',
      'venue',
      'contact',
    };
    return !supportedTypes.contains(messageType.toLowerCase());
  }

  static List<MessageEntity> _parseEntities(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => MessageEntity.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else if (raw is String && raw.isNotEmpty && raw != 'null') {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => MessageEntity.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } catch (_) {}
    }
    return const <MessageEntity>[];
  }

  factory ReplyInfo.fromJson(Map<String, dynamic> json) {
    return ReplyInfo(
      messageId: json['message_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      messageType: json['message_type']?.toString() ?? 'text',
      chatId: json['chat_id']?.toString(),
      nameColorPresetId: json['name_color_preset_id']?.toString() ??
          json['reply_to_sender_name_color_id']?.toString(),
      replyStripStyle: json['reply_strip_style']?.toString() ??
          json['reply_to_sender_strip_style']?.toString(),
      replyEmoji: ReplyEmojiData.fromJson(
        json['reply_emoji'] ?? json['reply_to_sender_reply_emoji'],
      ),
      entities: _parseEntities(json['entities'] ?? json['reply_to_entities']),
    );
  }

  Map<String, dynamic> toJson() => {
        'message_id': messageId,
        'sender_id': senderId,
        'sender_name': senderName,
        'content': content,
        'message_type': messageType,
        if (chatId != null) 'chat_id': chatId,
        if (nameColorPresetId != null) 'name_color_preset_id': nameColorPresetId,
        if (replyStripStyle != null) 'reply_strip_style': replyStripStyle,
        if (replyEmoji != null) 'reply_emoji': replyEmoji!.toJson(),
        if (entities.isNotEmpty)
          'entities': entities.map((e) => e.toJson()).toList(),
      };

  ReplyInfo copyWith({
    String? messageId,
    String? senderId,
    String? senderName,
    String? content,
    String? messageType,
    String? chatId,
    String? nameColorPresetId,
    String? replyStripStyle,
    ReplyEmojiData? replyEmoji,
    bool clearReplyEmoji = false,
    List<MessageEntity>? entities,
  }) {
    return ReplyInfo(
      messageId: messageId ?? this.messageId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      chatId: chatId ?? this.chatId,
      nameColorPresetId: nameColorPresetId ?? this.nameColorPresetId,
      replyStripStyle: replyStripStyle ?? this.replyStripStyle,
      replyEmoji: clearReplyEmoji ? null : (replyEmoji ?? this.replyEmoji),
      entities: entities ?? this.entities,
    );
  }
}

/// MessageEntity represents a formatted range in text (Bold, Italic, Spoiler, Code, Link, Custom Emoji, etc.).
class MessageEntity {
  final String type; // 'bold', 'italic', 'code', 'pre', 'spoiler', 'strikethrough', 'underline', 'link', 'text_link', 'mention', 'blockquote', 'expandable_blockquote', 'custom_emoji'
  final int offset;
  final int length;
  final String? url;
  final String? language; // For 'pre' code blocks
  final bool? collapsed; // For expandable/collapsible blockquotes
  final String? customEmojiId; // For 'custom_emoji' entities
  final String? documentUrl; // Resolved file URL for 'custom_emoji'
  final String? format; // 'webp', 'animated_webp', 'tgs', 'lottie'

  const MessageEntity({
    required this.type,
    required this.offset,
    required this.length,
    this.url,
    this.language,
    this.collapsed,
    this.customEmojiId,
    this.documentUrl,
    this.format,
  });

  factory MessageEntity.fromJson(Map<String, dynamic> json) {
    return MessageEntity(
      type: json['type']?.toString() ?? 'bold',
      offset: _parseIntValue(json['offset']),
      length: _parseIntValue(json['length']),
      url: json['url']?.toString(),
      language: json['language']?.toString(),
      collapsed: json['collapsed'] as bool?,
      customEmojiId: json['custom_emoji_id']?.toString() ?? json['customEmojiId']?.toString(),
      documentUrl: json['document_url']?.toString() ?? json['documentUrl']?.toString() ?? json['file_url']?.toString(),
      format: json['format']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'offset': offset,
        'length': length,
        if (url != null) 'url': url,
        if (language != null) 'language': language,
        if (collapsed != null) 'collapsed': collapsed,
        if (customEmojiId != null) 'custom_emoji_id': customEmojiId,
        if (documentUrl != null) 'document_url': documentUrl,
        if (format != null) 'format': format,
      };

  MessageEntity copyWith({
    String? type,
    int? offset,
    int? length,
    String? url,
    String? language,
    bool? collapsed,
    String? customEmojiId,
    String? documentUrl,
    String? format,
  }) {
    return MessageEntity(
      type: type ?? this.type,
      offset: offset ?? this.offset,
      length: length ?? this.length,
      url: url ?? this.url,
      language: language ?? this.language,
      collapsed: collapsed ?? this.collapsed,
      customEmojiId: customEmojiId ?? this.customEmojiId,
      documentUrl: documentUrl ?? this.documentUrl,
      format: format ?? this.format,
    );
  }
}

/// LinkPreviewOptions controls the presentation of link preview in messages.
class LinkPreviewOptions {
  final bool isDisabled;
  final String? url;
  final bool preferSmallMedia;
  final bool preferLargeMedia;
  final bool showAboveText;

  const LinkPreviewOptions({
    this.isDisabled = false,
    this.url,
    this.preferSmallMedia = false,
    this.preferLargeMedia = false,
    this.showAboveText = false,
  });

  factory LinkPreviewOptions.fromJson(Map<String, dynamic> json) {
    final rawDisabled = json['is_disabled'];
    final bool isDisabled = rawDisabled == true || rawDisabled == 1 || rawDisabled == 'true';
    final rawSmall = json['prefer_small_media'];
    final bool preferSmall = rawSmall == true || rawSmall == 1 || rawSmall == 'true';
    final rawLarge = json['prefer_large_media'];
    final bool preferLarge = rawLarge == true || rawLarge == 1 || rawLarge == 'true';
    final rawAbove = json['show_above_text'];
    final bool showAbove = rawAbove == true || rawAbove == 1 || rawAbove == 'true';

    return LinkPreviewOptions(
      isDisabled: isDisabled,
      url: json['url']?.toString(),
      preferSmallMedia: preferSmall,
      preferLargeMedia: preferLarge,
      showAboveText: showAbove,
    );
  }

  Map<String, dynamic> toJson() => {
        'is_disabled': isDisabled,
        if (url != null) 'url': url,
        'prefer_small_media': preferSmallMedia,
        'prefer_large_media': preferLargeMedia,
        'show_above_text': showAboveText,
      };

  LinkPreviewOptions copyWith({
    bool? isDisabled,
    String? url,
    bool? preferSmallMedia,
    bool? preferLargeMedia,
    bool? showAboveText,
  }) {
    return LinkPreviewOptions(
      isDisabled: isDisabled ?? this.isDisabled,
      url: url ?? this.url,
      preferSmallMedia: preferSmallMedia ?? this.preferSmallMedia,
      preferLargeMedia: preferLargeMedia ?? this.preferLargeMedia,
      showAboveText: showAboveText ?? this.showAboveText,
    );
  }
}

/// Message represents a message in a chat.
class Message {
  final String id; // serverId или localId если pending
  final String chatId;
  final String senderId;
  final String content;
  final String messageType;
  final bool isEdited;
  final String createdAt;
  final String senderName;
  final String? senderAvatarUrl;
  final String? fileUrl;
  final String? fileName;
  final String? replyToMessageId;
  final bool isRead;
  final String? readAt;
  final String? listenedAt;
  final bool isListened;

  // Reply / Quote fields
  final bool isQuote; // true = quote (partial text), false = full reply
  final String? quoteText; // выделенный текст цитаты
  final int quoteOffset; // смещение начала цитаты в оригинальном сообщении
  final int quoteLength; // длина цитируемого фрагмента

  // Cached reply preview (for offline-first display without lookup)
  final ReplyInfo? replyInfo;

  final String? localId; // UUID для pending-сообщений
  final int sendStatus; // 0=sending, 1=sent, 2=failed (MessageSendStatus)

  final String? senderNameColorId;
  final String? senderReplyStripStyle;

  // Forwarding fields
  final bool isForward;
  final String? forwardFromId;
  final String? forwardFromName;
  final String? forwardFromAvatarUrl;
  final PeerCustomization? senderCustomization;

  // Album grouping and text formatting entities
  final String? groupedId;
  final List<MessageEntity> entities;
  final LinkPreviewOptions? linkPreviewOptions;
  final bool invertMedia;

  // Reactions
  final Map<String, int> reactions; // emoji -> count
  final Set<String> myReactions; // emojis selected by current user

  // Round video note flag
  final bool isRound;

  // Voice message waveform and duration
  final List<int>? waveform;
  final int? duration;

  // Media album & message extra payload (dimensions, thumb_base64, file_size, etc.)
  final Map<String, dynamic>? mediaPayload;

  // Channel posts, views, signatures, anonymous admins, silent posts & comments
  final int viewsCount;
  final String? authorSignature;
  final String? postAuthorId;
  final String? senderRole;
  final String? senderAdminTitle;
  final bool isFromAnonymousAdmin;
  final bool isSilent;
  final int commentsCount;
  final bool canComment;
  final List<RecentReplier> recentRepliers;
  final String? channelPostId;
  final String? threadRootMessageId;
  final bool hasMediaSpoiler;
  final String? expiresAt;
  final int ttlSeconds;
  final bool isViewOnce;
  final String? viewedAt;
  final bool isBurned;
  final String? replyToChatId;
  final String? replyToChatName;
  final String? replyToChatType;
  final String? effectId;
  final List<String> savedTags;
  final int? topicId;
  final int forwardsCount;
  final String? senderChatId;
  final String? senderChatName;
  final String? senderChatAvatarUrl;
  final bool isOwn;
  late final int createdAtEpochMs =
      DateTimeUtils.parseUtcDateTime(createdAt)?.millisecondsSinceEpoch ?? 0;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    required this.messageType,
    required this.isEdited,
    required this.createdAt,
    required this.senderName,
    this.senderAvatarUrl,
    this.fileUrl,
    this.fileName,
    this.replyToMessageId,
    this.isRead = false,
    this.readAt,
    this.listenedAt,
    this.isListened = false,
    this.isQuote = false,
    this.quoteText,
    this.quoteOffset = 0,
    this.quoteLength = 0,
    this.replyInfo,
    this.localId,
    this.sendStatus = 1, // по умолчанию sent
    this.senderNameColorId,
    this.senderReplyStripStyle,
    this.isForward = false,
    this.forwardFromId,
    this.forwardFromName,
    this.forwardFromAvatarUrl,
    this.senderCustomization,
    this.groupedId,
    this.entities = const [],
    this.linkPreviewOptions,
    this.invertMedia = false,
    this.reactions = const {},
    this.myReactions = const {},
    this.isRound = false,
    this.waveform,
    this.duration,
    this.mediaPayload,
    this.viewsCount = 0,
    this.authorSignature,
    this.postAuthorId,
    this.senderRole,
    this.senderAdminTitle,
    this.isFromAnonymousAdmin = false,
    this.isSilent = false,
    this.commentsCount = 0,
    this.canComment = false,
    this.recentRepliers = const [],
    this.channelPostId,
    this.threadRootMessageId,
    this.hasMediaSpoiler = false,
    this.expiresAt,
    this.ttlSeconds = 0,
    this.isViewOnce = false,
    this.viewedAt,
    this.isBurned = false,
    this.replyToChatId,
    this.replyToChatName,
    this.replyToChatType,
    this.effectId,
    this.savedTags = const [],
    this.topicId,
    this.forwardsCount = 0,
    this.senderChatId,
    this.senderChatName,
    this.senderChatAvatarUrl,
    this.isOwn = false,
  });

  /// Whether this message has a reply or quote
  bool get hasReply => replyToMessageId != null && replyToMessageId!.isNotEmpty;

  /// True if this message type is unsupported in the current app version.
  bool get isUnsupported {
    if (messageType == 'unsupported') return true;
    const supportedTypes = {
      'text',
      'image',
      'photo',
      'video',
      'voice',
      'audio',
      'round',
      'poll',
      'document',
      'file',
      'dice',
      'call',
      'system',
      'sticker',
      'gif',
      'animation',
      'location',
      'live_location',
      'venue',
      'contact',
    };
    return !supportedTypes.contains(messageType.toLowerCase());
  }

  String? get thumbBase64 => mediaPayload?['thumb_base64'] as String?;
  String? get thumbUrl => mediaPayload?['thumb_url'] as String? ?? mediaPayload?['thumbnail_url'] as String?;
  int? get mediaWidth => _parseNullableInt(mediaPayload?['width']);
  int? get mediaHeight => _parseNullableInt(mediaPayload?['height']);
  int? get mediaDuration => _parseNullableInt(mediaPayload?['duration']);
  int? get mediaFileSize => _parseNullableInt(mediaPayload?['file_size']);

  Map<String, dynamic>? get replyMarkup {
    final raw = mediaPayload?['reply_markup'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  List<List<Map<String, dynamic>>> get inlineKeyboard {
    final rm = replyMarkup;
    final rows = rm?['inline_keyboard'];
    if (rows is! List) return const [];
    final result = <List<Map<String, dynamic>>>[];
    for (final row in rows) {
      if (row is List) {
        final parsedRow = <Map<String, dynamic>>[];
        for (final btn in row) {
          if (btn is Map) {
            parsedRow.add(Map<String, dynamic>.from(btn));
          }
        }
        if (parsedRow.isNotEmpty) {
          result.add(parsedRow);
        }
      }
    }
    return result;
  }

  List<List<Map<String, dynamic>>> get replyKeyboard {
    final rm = replyMarkup;
    final rows = rm?['keyboard'];
    if (rows is! List) return const [];
    final result = <List<Map<String, dynamic>>>[];
    for (final row in rows) {
      if (row is List) {
        final parsedRow = <Map<String, dynamic>>[];
        for (final btn in row) {
          if (btn is Map) {
            parsedRow.add(Map<String, dynamic>.from(btn));
          } else if (btn is String) {
            parsedRow.add({'text': btn});
          }
        }
        if (parsedRow.isNotEmpty) {
          result.add(parsedRow);
        }
      }
    }
    return result;
  }

  bool get removeReplyKeyboard => replyMarkup?['remove_keyboard'] == true;
  bool get oneTimeReplyKeyboard => replyMarkup?['one_time_keyboard'] == true;

  String? get viaBotId => mediaPayload?['via_bot_id']?.toString();
  String? get viaBotUsername => mediaPayload?['via_bot_username']?.toString();
  bool get isViaBot =>
      (viaBotUsername != null && viaBotUsername!.isNotEmpty) ||
      (viaBotId != null && viaBotId!.isNotEmpty);

  Map<String, dynamic>? get webAppData => mediaPayload?['web_app_data'] is Map
      ? Map<String, dynamic>.from(mediaPayload!['web_app_data'] as Map)
      : null;
  bool get hasWebAppData => webAppData != null;

  factory Message.fromJson(
    Map<String, dynamic> json, {
    Map<String, PeerCustomization>? outPeerCustomizations,
  }) {
    // Parse replyInfo from nested object or flat fields
    ReplyInfo? replyInfo;
    if (json['reply_info'] != null && json['reply_info'] is Map) {
      replyInfo = ReplyInfo.fromJson(
        Map<String, dynamic>.from(json['reply_info'] as Map),
      );
    } else if (json['reply_to_message_id'] != null) {
      // Fallback: build ReplyInfo from flat fields
      replyInfo = ReplyInfo(
        messageId: json['reply_to_message_id']?.toString() ?? '',
        senderId: json['reply_to_sender_id']?.toString() ?? '',
        senderName: json['reply_to_sender_name']?.toString() ?? '',
        content: json['reply_to_content']?.toString() ?? '',
        messageType: json['reply_to_message_type']?.toString() ?? 'text',
        nameColorPresetId: json['reply_to_sender_name_color_id']?.toString() ??
            json['reply_to_name_color_preset_id']?.toString(),
        replyStripStyle: json['reply_to_sender_strip_style']?.toString() ??
            json['reply_to_strip_style']?.toString(),
        replyEmoji: ReplyEmojiData.fromJson(
          json['reply_to_sender_reply_emoji'],
        ),
        entities: ReplyInfo._parseEntities(json['reply_to_entities']),
      );
    }

    final replySenderIdStr =
        json['reply_to_sender_id']?.toString() ?? replyInfo?.senderId ?? '';
    final rawReplySenderCust = json['reply_to_sender_customization'];
    PeerCustomization? parsedReplySenderCust;
    if (rawReplySenderCust is Map) {
      parsedReplySenderCust = PeerCustomization.fromJson(
        Map<String, dynamic>.from(rawReplySenderCust),
      );
    } else if (rawReplySenderCust is String && rawReplySenderCust.isNotEmpty) {
      parsedReplySenderCust =
          PeerCustomization.tryParseJsonString(rawReplySenderCust);
    }
    if (replySenderIdStr.isNotEmpty && parsedReplySenderCust != null) {
      if (outPeerCustomizations != null) {
        outPeerCustomizations[replySenderIdStr] = parsedReplySenderCust;
      } else {
        PeerCustomizationCache.instance.put(
          replySenderIdStr,
          parsedReplySenderCust,
          notify: false,
        );
      }
    }
    if (replyInfo != null) {
      final resolvedReplyEmoji = replyInfo.replyEmoji ??
          ReplyEmojiData.fromJson(
            json['reply_to_sender_reply_emoji'] ??
                (rawReplySenderCust is Map
                    ? rawReplySenderCust['reply_emoji']
                    : null),
          ) ??
          parsedReplySenderCust?.replyEmoji ??
          (replySenderIdStr.isNotEmpty
              ? (outPeerCustomizations?[replySenderIdStr]?.replyEmoji ??
                  PeerCustomizationCache.instance
                      .getSync(replySenderIdStr)
                      ?.replyEmoji)
              : null);
      if (resolvedReplyEmoji != null &&
          resolvedReplyEmoji != replyInfo.replyEmoji) {
        replyInfo = replyInfo.copyWith(replyEmoji: resolvedReplyEmoji);
      }
    }

    final Map<String, int> parsedReactions = {};
    final Set<String> parsedMyReactions = {};
    if (json['reactions'] is List) {
      for (final item in json['reactions']) {
        if (item is Map) {
          final emoji = item['emoji']?.toString() ?? '';
          final count = _parseIntValue(item['count']);
          if (emoji.isNotEmpty && count > 0) {
            parsedReactions[emoji] = count;
          }
          if (item['is_mine'] == true && emoji.isNotEmpty) {
            parsedMyReactions.add(emoji);
          }
        }
      }
    } else if (json['reactions'] is Map) {
      (json['reactions'] as Map).forEach((k, v) {
        final emoji = k.toString();
        final count = _parseIntValue(v);
        if (emoji.isNotEmpty && count > 0) {
          parsedReactions[emoji] = count;
        }
      });
      if (json['my_reactions'] is List) {
        for (final e in json['my_reactions']) {
          if (e != null && e.toString().isNotEmpty) {
            parsedMyReactions.add(e.toString());
          }
        }
      } else if (json['my_reaction'] != null) {
        parsedMyReactions.add(json['my_reaction'].toString());
      }
    }

    List<int>? waveform;
    if (json['waveform'] is List) {
      waveform = (json['waveform'] as List).map((e) => (e as num).toInt()).toList();
    } else if (json['media_payload'] is Map && json['media_payload']['waveform'] is List) {
      waveform = (json['media_payload']['waveform'] as List).map((e) => (e as num).toInt()).toList();
    }

    int? duration;
    if (json['duration'] is num) {
      duration = (json['duration'] as num).toInt();
    } else if (json['media_payload'] is Map && json['media_payload']['duration'] is num) {
      duration = (json['media_payload']['duration'] as num).toInt();
    }

    Map<String, dynamic>? parsedMediaPayload = json['media_payload'] is Map
        ? Map<String, dynamic>.from(json['media_payload'] as Map)
        : (json['media_payload'] is String && (json['media_payload'] as String).isNotEmpty
            ? (() {
                try {
                  final decoded = jsonDecode(json['media_payload'] as String);
                  return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
                } catch (_) {
                  return null;
                }
              })()
            : null);

    if (json['reply_markup'] != null) {
      parsedMediaPayload ??= <String, dynamic>{};
      parsedMediaPayload['reply_markup'] = json['reply_markup'];
    }
    if (json['via_bot_id'] != null) {
      parsedMediaPayload ??= <String, dynamic>{};
      parsedMediaPayload['via_bot_id'] = json['via_bot_id'];
    }
    if (json['via_bot_username'] != null) {
      parsedMediaPayload ??= <String, dynamic>{};
      parsedMediaPayload['via_bot_username'] = json['via_bot_username'];
    }

    final String? parsedReadAt =
        json['read_at']?.toString() ?? parsedMediaPayload?['read_at']?.toString();
    final String? parsedListenedAt = json['listened_at']?.toString() ??
        parsedMediaPayload?['listened_at']?.toString();
    final bool parsedIsListened = json['is_listened'] == true ||
        parsedMediaPayload?['is_listened'] == true ||
        parsedListenedAt != null;

    final String parsedSenderId = json['sender_id']?.toString() ?? '';
    final rawSenderCust = json['sender_customization'];
    final PeerCustomization? parsedSenderCust = rawSenderCust is Map
        ? PeerCustomization.fromJson(Map<String, dynamic>.from(rawSenderCust))
        : (rawSenderCust is String && rawSenderCust.isNotEmpty
            ? PeerCustomization.tryParseJsonString(rawSenderCust)
            : null);
    if (parsedSenderId.isNotEmpty && parsedSenderCust != null) {
      if (outPeerCustomizations != null) {
        outPeerCustomizations[parsedSenderId] = parsedSenderCust;
      } else {
        PeerCustomizationCache.instance.put(
          parsedSenderId,
          parsedSenderCust,
          notify: false,
        );
      }
    }

    final String? parsedReplyToChatId = _nonEmptyString(json['reply_to_chat_id']);
    final String? parsedReplyToChatName =
        _nonEmptyString(json['reply_to_chat_name']);
    final String? parsedReplyToChatType =
        _nonEmptyString(json['reply_to_chat_type']);
    if (replyInfo != null &&
        parsedReplyToChatId != null &&
        (replyInfo.chatId == null || replyInfo.chatId!.isEmpty)) {
      replyInfo = replyInfo.copyWith(chatId: parsedReplyToChatId);
    }

    final bool parsedIsViewOnce = _parseBoolFlag(json['is_view_once']);
    final String? parsedViewedAt = _nonEmptyString(json['viewed_at']);
    final bool parsedIsBurned = _parseBoolFlag(json['is_burned']) ||
        (parsedIsViewOnce && parsedViewedAt != null);
    final List<String> parsedSavedTags = json['saved_tags'] is List
        ? (json['saved_tags'] as List)
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList()
        : const <String>[];

    return Message(
      id: json['id']?.toString() ?? '',
      chatId: json['chat_id']?.toString() ?? '',
      senderId: parsedSenderId,
      content: json['content']?.toString() ?? '',
      messageType: json['message_type']?.toString() ?? 'text',
      isEdited: json['is_edited'] ?? false,
      createdAt: json['created_at']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? 'Unknown',
      senderAvatarUrl: json['sender_avatar_url']?.toString(),
      fileUrl: () {
        final raw = json['file_url']?.toString().trim();
        if (raw != null && raw.isNotEmpty) return raw;
        final payloadUrl = (parsedMediaPayload?['url'] ??
                parsedMediaPayload?['file_url'])
            ?.toString()
            .trim();
        return (payloadUrl != null && payloadUrl.isNotEmpty) ? payloadUrl : null;
      }(),
      fileName: () {
        final raw = json['file_name']?.toString().trim();
        return (raw != null && raw.isNotEmpty) ? raw : null;
      }(),
      replyToMessageId: json['reply_to_message_id']?.toString(),
      isRead: (json['is_read'] ?? false) || parsedReadAt != null,
      readAt: parsedReadAt,
      listenedAt: parsedListenedAt,
      isListened: parsedIsListened,
      isQuote: (json['is_quote'] == true) ||
          (parsedMediaPayload?['is_quote'] == true),
      quoteText: json['quote_text']?.toString() ??
          parsedMediaPayload?['quote_text']?.toString(),
      quoteOffset: _parseNullableInt(json['quote_offset']) ??
          _parseNullableInt(parsedMediaPayload?['quote_offset']) ??
          0,
      quoteLength: _parseNullableInt(json['quote_length']) ??
          _parseNullableInt(parsedMediaPayload?['quote_length']) ??
          0,
      replyInfo: replyInfo,
      localId: json['local_id']?.toString(),
      sendStatus: _parseIntValue(json['send_status'], defaultValue: 1),
      senderNameColorId: json['sender_name_color_id']?.toString(),
      senderReplyStripStyle: json['sender_reply_strip_style']?.toString(),
      isForward: (json['is_forward'] == true) ||
          (json['is_forwarded'] == true) ||
          json['forward_from_id'] != null ||
          json['forwarded_from_user_id'] != null ||
          json['forwarded_from_chat_id'] != null ||
          (json['forward_from_name'] != null &&
              json['forward_from_name'].toString().isNotEmpty) ||
          (json['forwarded_from_name'] != null &&
              json['forwarded_from_name'].toString().isNotEmpty),
      forwardFromId: (json['forward_from_id'] ??
              json['forwarded_from_user_id'] ??
              json['forwarded_from_chat_id'])
          ?.toString(),
      forwardFromName:
          (json['forward_from_name'] ?? json['forwarded_from_name'])
              ?.toString(),
      forwardFromAvatarUrl:
          (json['forwarded_from_avatar_url'] ?? json['forward_from_avatar_url'])
              ?.toString(),
      senderCustomization: parsedSenderCust,
      groupedId: json['grouped_id']?.toString(),
      entities: () {
        final raw = json['entities'];
        if (raw is List) {
          return raw
              .whereType<Map>()
              .map((e) => MessageEntity.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        } else if (raw is String && raw.isNotEmpty && raw != 'null') {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              return decoded
                  .whereType<Map>()
                  .map((e) => MessageEntity.fromJson(Map<String, dynamic>.from(e)))
                  .toList();
            }
          } catch (_) {}
        }
        return const <MessageEntity>[];
      }(),
      linkPreviewOptions: () {
        final raw = json['link_preview_options'];
        if (raw == null) return null;
        if (raw is Map) {
          try {
            return LinkPreviewOptions.fromJson(Map<String, dynamic>.from(raw));
          } catch (_) {
            return null;
          }
        }
        if (raw is String && raw.isNotEmpty && raw != 'null' && raw != '{}') {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              return LinkPreviewOptions.fromJson(Map<String, dynamic>.from(decoded));
            }
          } catch (_) {}
        }
        return null;
      }(),
      invertMedia: json['invert_media'] == true ||
          json['invert_media'] == 1 ||
          json['invert_media'] == 'true',
      reactions: parsedReactions,
      myReactions: parsedMyReactions,
      isRound: json['is_round'] == true || json['message_type'] == 'round',
      waveform: waveform,
      duration: duration,
      mediaPayload: parsedMediaPayload,
      viewsCount: _parseIntValue(json['views_count']),
      authorSignature: _nonEmptyString(json['author_signature']),
      postAuthorId: _nonEmptyString(json['post_author_id']),
      senderRole: _nonEmptyString(json['sender_role']),
      senderAdminTitle: _nonEmptyString(json['sender_admin_title']),
      isFromAnonymousAdmin: _parseBoolFlag(json['is_from_anonymous_admin']),
      isSilent: _parseBoolFlag(json['is_silent']),
      commentsCount: _parseIntValue(json['comments_count']),
      canComment: _parseBoolFlag(json['can_comment']),
      recentRepliers: RecentReplier.parseList(json['recent_repliers']),
      channelPostId: _nonEmptyString(json['channel_post_id']),
      threadRootMessageId: _nonEmptyString(json['thread_root_message_id']),
      hasMediaSpoiler: _parseBoolFlag(json['has_media_spoiler']) ||
          _parseBoolFlag(parsedMediaPayload?['has_media_spoiler']),
      expiresAt: _nonEmptyString(json['expires_at']),
      ttlSeconds: _parseIntValue(json['ttl_seconds']),
      isViewOnce: parsedIsViewOnce,
      viewedAt: parsedViewedAt,
      isBurned: parsedIsBurned,
      replyToChatId: parsedReplyToChatId,
      replyToChatName: parsedReplyToChatName,
      replyToChatType: parsedReplyToChatType,
      effectId: _nonEmptyString(json['effect_id']),
      savedTags: parsedSavedTags,
      topicId: _parseNullableInt(json['topic_id']),
      forwardsCount: _parseIntValue(json['forwards_count']),
      senderChatId: _nonEmptyString(json['sender_chat_id']),
      senderChatName: _nonEmptyString(json['sender_chat_name']),
      senderChatAvatarUrl: _nonEmptyString(json['sender_chat_avatar_url']),
      isOwn: _parseBoolFlag(json['is_own']) ||
          _parseBoolFlag(parsedMediaPayload?['is_own']),
    );
  }

  /// Создать Message из Drift DbMessage
  factory Message.fromDbMessage(DbMessage model) {
    // Build ReplyInfo from cached fields
    ReplyInfo? replyInfo;
    if (model.replyToMessageId != null) {
      final replySenderId = model.replyToSenderId ?? '';
      replyInfo = ReplyInfo(
        messageId: model.replyToMessageId!,
        senderId: replySenderId,
        senderName: model.replyToSenderName ?? '',
        content: model.replyToContent ?? '',
        messageType: model.replyToMessageType,
        chatId: model.replyToChatId,
        replyEmoji: replySenderId.isNotEmpty
            ? PeerCustomizationCache.instance.getSync(replySenderId)?.replyEmoji
            : null,
      );
    }

    List<MessageEntity> parsedEntities = [];
    if (model.entities != null && model.entities!.isNotEmpty) {
      try {
        final decoded = jsonDecode(model.entities!) as List;
        parsedEntities = decoded
            .map((e) => MessageEntity.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    final Map<String, int> dbReactions = {};
    final Set<String> dbMyReactions = {};
    if (model.reactions != null && model.reactions!.isNotEmpty) {
      try {
        final decoded = jsonDecode(model.reactions!);
        if (decoded is Map) {
          if (decoded['reactions'] is Map) {
            (decoded['reactions'] as Map).forEach((k, v) {
              final emoji = k.toString();
              final count = _parseIntValue(v);
              if (emoji.isNotEmpty && count > 0) {
                dbReactions[emoji] = count;
              }
            });
          }
          if (decoded['my_reactions'] is List) {
            for (final e in decoded['my_reactions']) {
              if (e != null && e.toString().isNotEmpty) {
                dbMyReactions.add(e.toString());
              }
            }
          }
        }
      } catch (_) {}
    }

    LinkPreviewOptions? parsedLinkPreviewOptions;
    if (model.linkPreviewOptions != null &&
        model.linkPreviewOptions!.isNotEmpty) {
      try {
        final decoded = jsonDecode(model.linkPreviewOptions!);
        if (decoded is Map<String, dynamic>) {
          parsedLinkPreviewOptions = LinkPreviewOptions.fromJson(decoded);
        }
      } catch (_) {}
    }

    Map<String, dynamic>? dbMediaPayload;
    List<int>? dbWaveform;
    int? dbDuration;
    // Prefer dedicated mediaPayload column, fall back to linkPreviewOptions for legacy data
    final rawMediaPayload = (model.mediaPayload != null && model.mediaPayload!.isNotEmpty)
        ? model.mediaPayload
        : (model.messageType == 'voice' ? model.linkPreviewOptions : null);

    if (rawMediaPayload != null && rawMediaPayload.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMediaPayload);
        if (decoded is Map<String, dynamic>) {
          dbMediaPayload = decoded;
        } else if (decoded is Map) {
          dbMediaPayload = Map<String, dynamic>.from(decoded);
        }
        if (dbMediaPayload != null) {
          if (dbMediaPayload['waveform'] is List) {
            dbWaveform = (dbMediaPayload['waveform'] as List)
                .map((e) => (e as num).toInt())
                .toList();
          }
          if (dbMediaPayload['duration'] is num) {
            dbDuration = (dbMediaPayload['duration'] as num).toInt();
          }
        }
      } catch (_) {}
    }

    final dbReadAt = dbMediaPayload?['read_at']?.toString();
    final dbListenedAt = dbMediaPayload?['listened_at']?.toString();
    final dbIsListened =
        dbMediaPayload?['is_listened'] == true || dbListenedAt != null;

    final PeerCustomization? dbSenderCust =
        PeerCustomization.tryParseJsonString(model.senderCustomizationJson);
    if (model.senderId.isNotEmpty && dbSenderCust != null) {
      PeerCustomizationCache.instance.put(
        model.senderId,
        dbSenderCust,
        notify: false,
      );
    }

    return Message(
      id: model.serverId ?? model.localId,
      chatId: model.chatId,
      senderId: model.senderId,
      content: model.content,
      messageType: model.messageType,
      isEdited: model.isEdited,
      createdAt: model.createdAt,
      senderName: model.senderName ?? '',
      senderAvatarUrl: model.senderAvatarUrl,
      fileUrl: (model.fileUrl != null && model.fileUrl!.trim().isNotEmpty)
          ? model.fileUrl!.trim()
          : () {
              final payloadUrl = (dbMediaPayload?['url'] ??
                      dbMediaPayload?['file_url'])
                  ?.toString()
                  .trim();
              return (payloadUrl != null && payloadUrl.isNotEmpty)
                  ? payloadUrl
                  : null;
            }(),
      fileName: (model.fileName != null && model.fileName!.trim().isNotEmpty)
          ? model.fileName!.trim()
          : null,
      replyToMessageId: model.replyToMessageId,
      isRead: model.isRead || dbReadAt != null,
      readAt: dbReadAt,
      listenedAt: dbListenedAt,
      isListened: dbIsListened,
      isQuote: model.isQuote || (dbMediaPayload?['is_quote'] == true),
      quoteText: model.quoteText ?? dbMediaPayload?['quote_text']?.toString(),
      quoteOffset: model.quoteOffset != 0
          ? model.quoteOffset
          : _parseIntValue(dbMediaPayload?['quote_offset']),
      quoteLength: model.quoteLength != 0
          ? model.quoteLength
          : _parseIntValue(dbMediaPayload?['quote_length']),
      replyInfo: replyInfo,
      localId: model.localId,
      sendStatus: model.sendStatus,
      isForward: model.isForward,
      forwardFromId: model.forwardFromId,
      forwardFromName: model.forwardFromName,
      forwardFromAvatarUrl: model.forwardFromAvatarUrl,
      senderCustomization: dbSenderCust,
      groupedId: model.groupedId,
      entities: parsedEntities,
      linkPreviewOptions: parsedLinkPreviewOptions,
      invertMedia: model.invertMedia,
      reactions: dbReactions,
      myReactions: dbMyReactions,
      isRound: model.isRound,
      waveform: dbWaveform,
      duration: dbDuration,
      mediaPayload: dbMediaPayload,
      viewsCount: model.viewsCount,
      authorSignature: _nonEmptyString(model.authorSignature),
      postAuthorId: _nonEmptyString(model.postAuthorId),
      senderRole: _nonEmptyString(model.senderRole),
      senderAdminTitle: _nonEmptyString(model.senderAdminTitle),
      isFromAnonymousAdmin: model.isFromAnonymousAdmin,
      isSilent: model.isSilent,
      commentsCount: model.commentsCount,
      canComment: dbMediaPayload?['can_comment'] == true,
      recentRepliers: RecentReplier.parseList(model.recentRepliersJson),
      channelPostId: _nonEmptyString(dbMediaPayload?['channel_post_id']),
      threadRootMessageId: _nonEmptyString(model.threadRootMessageId),
      hasMediaSpoiler: model.hasMediaSpoiler ||
          (dbMediaPayload?['has_media_spoiler'] == true),
      expiresAt: _nonEmptyString(model.expiresAt),
      ttlSeconds: model.ttlSeconds,
      isViewOnce: model.isViewOnce,
      viewedAt: _nonEmptyString(model.viewedAt),
      isBurned: model.isBurned ||
          (model.isViewOnce &&
              model.viewedAt != null &&
              model.viewedAt!.isNotEmpty),
      replyToChatId: _nonEmptyString(model.replyToChatId),
      replyToChatName: _nonEmptyString(model.replyToChatName),
      replyToChatType: _nonEmptyString(model.replyToChatType),
      effectId: _nonEmptyString(model.effectId),
      topicId: model.topicId,
      forwardsCount: model.forwardsCount,
      senderChatId: _nonEmptyString(model.senderChatId),
      senderChatName: _nonEmptyString(model.senderChatName),
      senderChatAvatarUrl: _nonEmptyString(model.senderChatAvatarUrl),
      isOwn: dbMediaPayload?['is_own'] == true,
      savedTags: () {
        if (model.savedTagsJson == null || model.savedTagsJson!.isEmpty) {
          return const <String>[];
        }
        try {
          final dec = jsonDecode(model.savedTagsJson!);
          if (dec is List) {
            return dec
                .map((e) => e.toString())
                .where((s) => s.isNotEmpty)
                .toList();
          }
        } catch (_) {}
        return const <String>[];
      }(),
    );
  }

  /// Convert Message to Drift MessagesCompanion
  MessagesCompanion toCompanion({String? fallbackChatId}) {
    final effectiveChatId = chatId.isNotEmpty ? chatId : (fallbackChatId ?? '');
    final hasServerId = sendStatus == 1 && id.isNotEmpty;

    final Map<String, dynamic> effectiveMediaPayload = {
      if (mediaPayload != null) ...mediaPayload!,
      if (waveform != null && waveform!.isNotEmpty) 'waveform': waveform,
      if (duration != null && duration! > 0) 'duration': duration,
      if (readAt != null && readAt!.isNotEmpty) 'read_at': readAt,
      if (listenedAt != null && listenedAt!.isNotEmpty)
        'listened_at': listenedAt,
      if (isListened) 'is_listened': true,
      if (canComment) 'can_comment': true,
      if (channelPostId != null && channelPostId!.isNotEmpty)
        'channel_post_id': channelPostId,
      if (isOwn) 'is_own': true,
    };

    return MessagesCompanion(
      serverId: hasServerId ? drift.Value(id) : const drift.Value.absent(),
      localId: drift.Value(localId ?? id),
      chatId: drift.Value(effectiveChatId),
      senderId: drift.Value(senderId),
      content: drift.Value(content),
      messageType: drift.Value(messageType),
      fileUrl: drift.Value(fileUrl),
      fileName: drift.Value(fileName),
      replyToMessageId: drift.Value(replyToMessageId),
      isQuote: drift.Value(isQuote),
      quoteText: drift.Value(quoteText),
      quoteOffset: drift.Value(quoteOffset),
      quoteLength: drift.Value(quoteLength),
      replyToSenderId: drift.Value(replyInfo?.senderId),
      replyToSenderName: drift.Value(replyInfo?.senderName),
      replyToContent: drift.Value(replyInfo?.content),
      replyToMessageType: drift.Value(replyInfo?.messageType ?? 'text'),
      isRead: drift.Value(isRead),
      isEdited: drift.Value(isEdited),
      sendStatus: drift.Value(sendStatus),
      senderName: drift.Value(senderName),
      senderAvatarUrl: drift.Value(senderAvatarUrl),
      createdAt: drift.Value(createdAt),
      isForward: drift.Value(isForward),
      forwardFromId: drift.Value(forwardFromId),
      forwardFromName: drift.Value(forwardFromName),
      forwardFromAvatarUrl: drift.Value(forwardFromAvatarUrl),
      senderCustomizationJson: drift.Value(senderCustomization?.toJsonString()),
      invertMedia: drift.Value(invertMedia),
      reactions: reactions.isNotEmpty || myReactions.isNotEmpty
          ? drift.Value(jsonEncode({
              'reactions': reactions,
              'my_reactions': myReactions.toList(),
            }))
          : const drift.Value.absent(),
      isRound: drift.Value(isRound),
      groupedId: drift.Value(groupedId),
      entities: entities.isNotEmpty
          ? drift.Value(jsonEncode(entities.map((e) => e.toJson()).toList()))
          : const drift.Value.absent(),
      linkPreviewOptions: linkPreviewOptions != null
          ? drift.Value(jsonEncode(linkPreviewOptions!.toJson()))
          : const drift.Value.absent(),
      mediaPayload: effectiveMediaPayload.isNotEmpty
          ? drift.Value(jsonEncode(effectiveMediaPayload))
          : const drift.Value.absent(),
      viewsCount: drift.Value(viewsCount),
      authorSignature: drift.Value(authorSignature),
      postAuthorId: drift.Value(postAuthorId),
      senderRole: drift.Value(senderRole),
      senderAdminTitle: drift.Value(senderAdminTitle),
      isFromAnonymousAdmin: drift.Value(isFromAnonymousAdmin),
      isSilent: drift.Value(isSilent),
      commentsCount: drift.Value(commentsCount),
      recentRepliersJson: drift.Value(
        recentRepliers.isNotEmpty
            ? jsonEncode(recentRepliers.map((r) => r.toJson()).toList())
            : null,
      ),
      threadRootMessageId: drift.Value(threadRootMessageId),
      hasMediaSpoiler: drift.Value(hasMediaSpoiler),
      expiresAt: drift.Value(expiresAt),
      ttlSeconds: drift.Value(ttlSeconds),
      isViewOnce: drift.Value(isViewOnce),
      viewedAt: drift.Value(viewedAt),
      isBurned: drift.Value(isBurned),
      replyToChatId: drift.Value(replyToChatId ?? replyInfo?.chatId),
      replyToChatName: drift.Value(replyToChatName),
      replyToChatType: drift.Value(replyToChatType),
      effectId: drift.Value(effectId),
      topicId: drift.Value(topicId),
      forwardsCount: drift.Value(forwardsCount),
      senderChatId: drift.Value(senderChatId),
      senderChatName: drift.Value(senderChatName),
      senderChatAvatarUrl: drift.Value(senderChatAvatarUrl),
      savedTagsJson: savedTags.isNotEmpty
          ? drift.Value(jsonEncode(savedTags))
          : const drift.Value.absent(),
    );
  }

  /// Copy with method for updating message state
  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? content,
    String? messageType,
    bool? isEdited,
    String? createdAt,
    String? senderName,
    String? senderAvatarUrl,
    String? fileUrl,
    String? fileName,
    String? replyToMessageId,
    bool? isRead,
    String? readAt,
    String? listenedAt,
    bool? isListened,
    bool? isQuote,
    String? quoteText,
    int? quoteOffset,
    int? quoteLength,
    ReplyInfo? replyInfo,
    String? localId,
    int? sendStatus,
    String? senderNameColorId,
    String? senderReplyStripStyle,
    bool? isForward,
    String? forwardFromId,
    String? forwardFromName,
    String? forwardFromAvatarUrl,
    PeerCustomization? senderCustomization,
    String? groupedId,
    List<MessageEntity>? entities,
    LinkPreviewOptions? linkPreviewOptions,
    bool? invertMedia,
    Map<String, int>? reactions,
    Set<String>? myReactions,
    bool? isRound,
    List<int>? waveform,
    int? duration,
    Map<String, dynamic>? mediaPayload,
    int? viewsCount,
    String? authorSignature,
    String? postAuthorId,
    String? senderRole,
    String? senderAdminTitle,
    bool? isFromAnonymousAdmin,
    bool? isSilent,
    int? commentsCount,
    bool? canComment,
    List<RecentReplier>? recentRepliers,
    String? channelPostId,
    String? threadRootMessageId,
    bool? hasMediaSpoiler,
    String? expiresAt,
    int? ttlSeconds,
    bool? isViewOnce,
    String? viewedAt,
    bool? isBurned,
    String? replyToChatId,
    String? replyToChatName,
    String? replyToChatType,
    String? effectId,
    List<String>? savedTags,
    int? topicId,
    int? forwardsCount,
    String? senderChatId,
    String? senderChatName,
    String? senderChatAvatarUrl,
    bool? isOwn,
    bool clearReply = false,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      isEdited: isEdited ?? this.isEdited,
      createdAt: createdAt ?? this.createdAt,
      senderName: senderName ?? this.senderName,
      senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      replyToMessageId:
          clearReply ? null : (replyToMessageId ?? this.replyToMessageId),
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      listenedAt: listenedAt ?? this.listenedAt,
      isListened: isListened ?? this.isListened,
      isQuote: clearReply ? false : (isQuote ?? this.isQuote),
      quoteText: clearReply ? null : (quoteText ?? this.quoteText),
      quoteOffset: clearReply ? 0 : (quoteOffset ?? this.quoteOffset),
      quoteLength: clearReply ? 0 : (quoteLength ?? this.quoteLength),
      replyInfo: clearReply ? null : (replyInfo ?? this.replyInfo),
      localId: localId ?? this.localId,
      sendStatus: sendStatus ?? this.sendStatus,
      senderNameColorId: senderNameColorId ?? this.senderNameColorId,
      senderReplyStripStyle: senderReplyStripStyle ?? this.senderReplyStripStyle,
      isForward: isForward ?? this.isForward,
      forwardFromId: forwardFromId ?? this.forwardFromId,
      forwardFromName: forwardFromName ?? this.forwardFromName,
      forwardFromAvatarUrl: forwardFromAvatarUrl ?? this.forwardFromAvatarUrl,
      senderCustomization: senderCustomization ?? this.senderCustomization,
      groupedId: groupedId ?? this.groupedId,
      entities: entities ?? this.entities,
      linkPreviewOptions: linkPreviewOptions ?? this.linkPreviewOptions,
      invertMedia: invertMedia ?? this.invertMedia,
      reactions: reactions ?? this.reactions,
      myReactions: myReactions ?? this.myReactions,
      isRound: isRound ?? this.isRound,
      waveform: waveform ?? this.waveform,
      duration: duration ?? this.duration,
      mediaPayload: mediaPayload ?? this.mediaPayload,
      viewsCount: viewsCount ?? this.viewsCount,
      authorSignature: authorSignature ?? this.authorSignature,
      postAuthorId: postAuthorId ?? this.postAuthorId,
      senderRole: senderRole ?? this.senderRole,
      senderAdminTitle: senderAdminTitle ?? this.senderAdminTitle,
      isFromAnonymousAdmin: isFromAnonymousAdmin ?? this.isFromAnonymousAdmin,
      isSilent: isSilent ?? this.isSilent,
      commentsCount: commentsCount ?? this.commentsCount,
      canComment: canComment ?? this.canComment,
      recentRepliers: recentRepliers ?? this.recentRepliers,
      channelPostId: channelPostId ?? this.channelPostId,
      threadRootMessageId: threadRootMessageId ?? this.threadRootMessageId,
      hasMediaSpoiler: hasMediaSpoiler ?? this.hasMediaSpoiler,
      expiresAt: expiresAt ?? this.expiresAt,
      ttlSeconds: ttlSeconds ?? this.ttlSeconds,
      isViewOnce: isViewOnce ?? this.isViewOnce,
      viewedAt: viewedAt ?? this.viewedAt,
      isBurned: isBurned ?? this.isBurned,
      replyToChatId: clearReply ? null : (replyToChatId ?? this.replyToChatId),
      replyToChatName:
          clearReply ? null : (replyToChatName ?? this.replyToChatName),
      replyToChatType:
          clearReply ? null : (replyToChatType ?? this.replyToChatType),
      effectId: effectId ?? this.effectId,
      savedTags: savedTags ?? this.savedTags,
      topicId: topicId ?? this.topicId,
      forwardsCount: forwardsCount ?? this.forwardsCount,
      senderChatId: senderChatId ?? this.senderChatId,
      senderChatName: senderChatName ?? this.senderChatName,
      senderChatAvatarUrl: senderChatAvatarUrl ?? this.senderChatAvatarUrl,
      isOwn: isOwn ?? this.isOwn,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// ChatDetails represents detailed information about a chat.
class ChatDetails {
  final String id;
  final String chatType;
  final String name;
  final String? avatarUrl;
  final String createdBy;
  final String createdAt;
  final String updatedAt;
  final List<ChatParticipant> participants;
  final int lastReadInboxMessageId;
  final int lastReadOutboxMessageId;
  final int? pinnedMessageId;
  final Message? pinnedMessage;
  final List<int> pinnedMessageIds;
  final bool hasProtectedContent;
  final String? username;
  final bool isPublic;
  final bool isVerified;
  final bool showAuthorProfiles;
  final String? description;
  final String? myRole;
  final bool isMember;
  final bool signMessages;
  final String? linkedChatId;
  final LinkedChatSummary? linkedChat;
  final GroupDefaultPermissions? defaultPermissions;
  final AdminRights? myAdminPermissions;
  final MemberRestrictions? myRestrictions;
  final DateTime? restrictedUntil;
  final String myAdminTitle;
  final bool myIsAnonymous;
  final ReactionSettings? reactionSettings;
  final int slowModeInterval;
  final int slowModeWaitSeconds;
  final int slowModeNextSendDate;
  final int memberCount;
  final int subscriberCount;
  final int pendingJoinRequestsCount;
  final bool isMarkedUnread;
  final bool historyForNewMembers;
  final bool hasActiveCall;
  final String? activeCallId;
  final int messageAutoDeleteTime;
  final Map<String, dynamic>? appearance;
  final bool isForum;
  final bool participantsHidden;
  final bool hasAggressiveAntiSpamEnabled;
  final int maxReactionsPerPost;
  final int unreadMentionsCount;
  final int unreadReactionsCount;
  final String? mySendAsChatId;
  final String? mySendAsMode;
  late final int updatedAtEpochMs =
      DateTimeUtils.parseUtcDateTime(updatedAt)?.millisecondsSinceEpoch ?? 0;

  ChatDetails({
    required this.id,
    required this.chatType,
    required this.name,
    this.avatarUrl,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.participants,
    this.lastReadInboxMessageId = 0,
    this.lastReadOutboxMessageId = 0,
    this.pinnedMessageId,
    this.pinnedMessage,
    this.pinnedMessageIds = const [],
    this.hasProtectedContent = false,
    this.username,
    this.isPublic = false,
    this.isVerified = false,
    bool? showAuthorProfiles,
    this.description,
    this.myRole,
    this.isMember = true,
    this.signMessages = false,
    this.linkedChatId,
    this.linkedChat,
    this.defaultPermissions,
    this.myAdminPermissions,
    this.myRestrictions,
    this.restrictedUntil,
    this.myAdminTitle = '',
    this.myIsAnonymous = false,
    this.reactionSettings,
    this.slowModeInterval = 0,
    this.slowModeWaitSeconds = 0,
    this.slowModeNextSendDate = 0,
    this.memberCount = 0,
    this.subscriberCount = 0,
    this.pendingJoinRequestsCount = 0,
    this.isMarkedUnread = false,
    this.historyForNewMembers = true,
    this.hasActiveCall = false,
    this.activeCallId,
    this.messageAutoDeleteTime = 0,
    this.appearance,
    this.isForum = false,
    this.participantsHidden = false,
    this.hasAggressiveAntiSpamEnabled = false,
    this.maxReactionsPerPost = 11,
    this.unreadMentionsCount = 0,
    this.unreadReactionsCount = 0,
    this.mySendAsChatId,
    this.mySendAsMode,
  }) : showAuthorProfiles = showAuthorProfiles ?? (chatType != 'channel');

  bool get isOwner => myRole == 'owner';
  bool get isAdmin => myRole == 'owner' || myRole == 'admin';

  int get effectiveMemberCount => subscriberCount > 0
      ? subscriberCount
      : (memberCount > 0 ? memberCount : participants.length);

  bool get canManageCallsEffective =>
      isOwner ||
      (myRole == 'admin' && (myAdminPermissions?.canManageCalls ?? true));

  bool get canChangeInfoEffective {
    if (isOwner) return true;
    if (myRole == 'admin') return myAdminPermissions?.canChangeInfo ?? true;
    if (chatType != 'group' || !isMember) return false;
    final defaultCan = defaultPermissions?.canChangeInfo ?? false;
    if (!defaultCan) return false;
    if (myRestrictions == null) return true;
    if (restrictedUntil != null && DateTime.now().isAfter(restrictedUntil!)) {
      return true;
    }
    return myRestrictions!.canChangeInfo;
  }

  bool get canPostInChannel =>
      chatType != 'channel' ||
      isOwner ||
      (myRole == 'admin' && (myAdminPermissions?.canPostMessages ?? true));

  bool get canManageTopicsEffective =>
      isOwner ||
      (myRole == 'admin' && (myAdminPermissions?.canManageTopics ?? false)) ||
      (chatType == 'group' && isMember && (defaultPermissions?.canManageTopics ?? false));

  GroupDefaultPermissions get effectivePermissions {
    if (isAdmin) {
      return GroupDefaultPermissions(
        canSendMessages: true,
        canSendMedia: true,
        canSendPhotos: true,
        canSendVideos: true,
        canSendMusic: true,
        canSendFiles: true,
        canSendVoiceNotes: true,
        canSendVideoNotes: true,
        canSendStickersGifs: true,
        canSendPolls: true,
        canAddWebPagePreviews: true,
        canPinMessages: true,
        canInviteUsers: true,
        canChangeInfo: true,
        canManageTopics: isOwner || (myAdminPermissions?.canManageTopics ?? true),
      );
    }
    final base = defaultPermissions ?? const GroupDefaultPermissions();
    if (myRestrictions == null) return base;
    if (restrictedUntil != null && DateTime.now().isAfter(restrictedUntil!)) {
      return base;
    }
    return base.intersectWith(myRestrictions);
  }

  ChatDetails copyWith({
    String? id,
    String? chatType,
    String? name,
    String? avatarUrl,
    String? createdBy,
    String? createdAt,
    String? updatedAt,
    List<ChatParticipant>? participants,
    int? lastReadInboxMessageId,
    int? lastReadOutboxMessageId,
    int? pinnedMessageId,
    Message? pinnedMessage,
    List<int>? pinnedMessageIds,
    bool? hasProtectedContent,
    String? username,
    bool? isPublic,
    bool? isVerified,
    bool? showAuthorProfiles,
    String? description,
    String? myRole,
    bool? isMember,
    bool? signMessages,
    String? linkedChatId,
    bool clearLinkedChatId = false,
    LinkedChatSummary? linkedChat,
    bool clearLinkedChat = false,
    GroupDefaultPermissions? defaultPermissions,
    AdminRights? myAdminPermissions,
    MemberRestrictions? myRestrictions,
    DateTime? restrictedUntil,
    String? myAdminTitle,
    bool? myIsAnonymous,
    ReactionSettings? reactionSettings,
    int? slowModeInterval,
    int? slowModeWaitSeconds,
    int? slowModeNextSendDate,
    int? memberCount,
    int? subscriberCount,
    int? pendingJoinRequestsCount,
    bool? isMarkedUnread,
    bool? historyForNewMembers,
    bool? hasActiveCall,
    String? activeCallId,
    bool clearActiveCallId = false,
    int? messageAutoDeleteTime,
    Map<String, dynamic>? appearance,
    bool clearAppearance = false,
    bool? isForum,
    bool? participantsHidden,
    bool? hasAggressiveAntiSpamEnabled,
    int? maxReactionsPerPost,
    int? unreadMentionsCount,
    int? unreadReactionsCount,
    String? mySendAsChatId,
    bool clearMySendAsChatId = false,
    String? mySendAsMode,
  }) {
    return ChatDetails(
      id: id ?? this.id,
      chatType: chatType ?? this.chatType,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      participants: participants ?? this.participants,
      lastReadInboxMessageId:
          lastReadInboxMessageId ?? this.lastReadInboxMessageId,
      lastReadOutboxMessageId:
          lastReadOutboxMessageId ?? this.lastReadOutboxMessageId,
      pinnedMessageId: pinnedMessageId ?? this.pinnedMessageId,
      pinnedMessage: pinnedMessage ?? this.pinnedMessage,
      pinnedMessageIds: pinnedMessageIds ?? this.pinnedMessageIds,
      hasProtectedContent: hasProtectedContent ?? this.hasProtectedContent,
      username: username ?? this.username,
      isPublic: isPublic ?? this.isPublic,
      isVerified: isVerified ?? this.isVerified,
      showAuthorProfiles: showAuthorProfiles ?? this.showAuthorProfiles,
      description: description ?? this.description,
      myRole: myRole ?? this.myRole,
      isMember: isMember ?? this.isMember,
      signMessages: signMessages ?? this.signMessages,
      linkedChatId:
          clearLinkedChatId ? null : (linkedChatId ?? this.linkedChatId),
      linkedChat: clearLinkedChat ? null : (linkedChat ?? this.linkedChat),
      defaultPermissions: defaultPermissions ?? this.defaultPermissions,
      myAdminPermissions: myAdminPermissions ?? this.myAdminPermissions,
      myRestrictions: myRestrictions ?? this.myRestrictions,
      restrictedUntil: restrictedUntil ?? this.restrictedUntil,
      myAdminTitle: myAdminTitle ?? this.myAdminTitle,
      myIsAnonymous: myIsAnonymous ?? this.myIsAnonymous,
      reactionSettings: reactionSettings ?? this.reactionSettings,
      slowModeInterval: slowModeInterval ?? this.slowModeInterval,
      slowModeWaitSeconds: slowModeWaitSeconds ?? this.slowModeWaitSeconds,
      slowModeNextSendDate: slowModeNextSendDate ?? this.slowModeNextSendDate,
      memberCount: memberCount ?? this.memberCount,
      subscriberCount: subscriberCount ?? this.subscriberCount,
      pendingJoinRequestsCount:
          pendingJoinRequestsCount ?? this.pendingJoinRequestsCount,
      isMarkedUnread: isMarkedUnread ?? this.isMarkedUnread,
      historyForNewMembers: historyForNewMembers ?? this.historyForNewMembers,
      hasActiveCall: hasActiveCall ?? this.hasActiveCall,
      activeCallId:
          clearActiveCallId ? null : (activeCallId ?? this.activeCallId),
      messageAutoDeleteTime:
          messageAutoDeleteTime ?? this.messageAutoDeleteTime,
      appearance: clearAppearance ? null : (appearance ?? this.appearance),
      isForum: isForum ?? this.isForum,
      participantsHidden: participantsHidden ?? this.participantsHidden,
      hasAggressiveAntiSpamEnabled:
          hasAggressiveAntiSpamEnabled ?? this.hasAggressiveAntiSpamEnabled,
      maxReactionsPerPost: maxReactionsPerPost ?? this.maxReactionsPerPost,
      unreadMentionsCount: unreadMentionsCount ?? this.unreadMentionsCount,
      unreadReactionsCount: unreadReactionsCount ?? this.unreadReactionsCount,
      mySendAsChatId: clearMySendAsChatId
          ? null
          : (mySendAsChatId ?? this.mySendAsChatId),
      mySendAsMode: mySendAsMode ?? this.mySendAsMode,
    );
  }

  factory ChatDetails.fromJson(Map<String, dynamic> json) {
    var participantsList = <ChatParticipant>[];
    if (json['participants'] != null && json['participants'] is List) {
      for (var p in json['participants']) {
        if (p is Map) {
          participantsList.add(
            ChatParticipant.fromJson(Map<String, dynamic>.from(p)),
          );
        }
      }
    }
    Message? parsedPinnedMessage;
    int? parsedPinnedMessageId = _parseNullableInt(json['pinned_message_id']);
    if (json['pinned_message'] is Map) {
      try {
        parsedPinnedMessage = Message.fromJson(
          Map<String, dynamic>.from(json['pinned_message'] as Map),
        );
        parsedPinnedMessageId ??= int.tryParse(parsedPinnedMessage.id);
      } catch (_) {}
    }

    final parsedChatType = json['chat_type']?.toString() ?? 'private';
    final bool parsedShowAuthorProfiles =
        json.containsKey('show_author_profiles')
            ? _parseBoolFlag(json['show_author_profiles'])
            : (parsedChatType != 'channel');
    final parsedLinkedChat = LinkedChatSummary.tryParse(json['linked_chat']);
    final parsedLinkedChatId =
        _nonEmptyString(json['linked_chat_id']) ?? parsedLinkedChat?.id;
    final parsedMyRole = _nonEmptyString(json['my_role']);
    final parsedActiveCallId = _nonEmptyString(json['active_call_id']);
    final parsedIsMember = json.containsKey('is_member')
        ? _parseBoolFlag(json['is_member'], defaultValue: true)
        : (parsedMyRole != 'guest');

    final parsedPinnedList = _parseIntList(json['pinned_message_ids']);
    final List<int> effectivePinnedIds = parsedPinnedList.isNotEmpty
        ? parsedPinnedList
        : (parsedPinnedMessageId != null && parsedPinnedMessageId > 0
            ? <int>[parsedPinnedMessageId]
            : const <int>[]);
    final bool parsedHasProtectedContent = _parseBoolFlag(
      json['has_protected_content'] ?? json['noforwards'],
    );

    final int parsedMemberCount = _parseIntValue(json['member_count']);
    final int parsedSubscriberCount = _parseIntValue(json['subscriber_count']);
    final int normalizedMemberCount =
        parsedMemberCount > 0 ? parsedMemberCount : participantsList.length;
    final int normalizedSubscriberCount =
        parsedSubscriberCount > 0 ? parsedSubscriberCount : normalizedMemberCount;
    final int parsedSlowWait = _parseIntValue(json['slow_mode_wait_seconds']);
    final int parsedSlowNext = _parseIntValue(json['slow_mode_next_send_date']);
    int effectiveSlowWait = parsedSlowWait;
    if (effectiveSlowWait <= 0 && parsedSlowNext > 0) {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (parsedSlowNext > nowSec) {
        effectiveSlowWait = parsedSlowNext - nowSec;
      }
    }

    return ChatDetails(
      id: json['id']?.toString() ?? '',
      chatType: parsedChatType,
      name: json['name']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString(),
      createdBy: json['created_by']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      participants: participantsList,
      lastReadInboxMessageId:
          _parseIntValue(json['last_read_inbox_message_id']),
      lastReadOutboxMessageId:
          _parseIntValue(json['last_read_outbox_message_id']),
      pinnedMessageId: parsedPinnedMessageId,
      pinnedMessage: parsedPinnedMessage,
      pinnedMessageIds: effectivePinnedIds,
      hasProtectedContent: parsedHasProtectedContent,
      username: json['username']?.toString(),
      isPublic: json['is_public'] == true,
      isVerified: json['is_verified'] == true,
      showAuthorProfiles: parsedShowAuthorProfiles,
      description: json['description']?.toString(),
      myRole: parsedMyRole,
      isMember: parsedIsMember,
      signMessages: _parseBoolFlag(json['sign_messages']),
      linkedChatId: parsedLinkedChatId,
      linkedChat: parsedLinkedChat,
      defaultPermissions: GroupDefaultPermissions.tryParse(
        json['default_permissions'] ?? json['chat_permissions'],
      ),
      myAdminPermissions: AdminRights.tryParse(json['my_admin_permissions']),
      myRestrictions: MemberRestrictions.tryParse(json['my_restrictions']),
      restrictedUntil: DateTimeUtils.parseUtcDateTime(
        json['restricted_until'] ?? json['my_restricted_until'],
      ),
      myAdminTitle: (json['my_admin_title'] ?? '').toString(),
      myIsAnonymous: _parseBoolFlag(json['my_is_anonymous']),
      reactionSettings: ReactionSettings.fromChatJson(json),
      slowModeInterval: _parseIntValue(json['slow_mode_interval']),
      slowModeWaitSeconds: effectiveSlowWait,
      slowModeNextSendDate: parsedSlowNext,
      memberCount: normalizedMemberCount,
      subscriberCount: normalizedSubscriberCount,
      pendingJoinRequestsCount:
          _parseIntValue(json['pending_join_requests_count']),
      isMarkedUnread: _parseBoolFlag(json['is_marked_unread']),
      historyForNewMembers:
          (json['history_for_new_members'] ?? json['history_for_new']) != false,
      hasActiveCall:
          _parseBoolFlag(json['has_active_call']) || parsedActiveCallId != null,
      activeCallId: parsedActiveCallId,
      messageAutoDeleteTime: _parseIntValue(json['message_auto_delete_time']),
      appearance: json['appearance'] is Map
          ? Map<String, dynamic>.from(json['appearance'] as Map)
          : null,
      isForum: _parseBoolFlag(json['is_forum']),
      participantsHidden: _parseBoolFlag(json['participants_hidden']),
      hasAggressiveAntiSpamEnabled:
          _parseBoolFlag(json['has_aggressive_anti_spam_enabled']),
      maxReactionsPerPost: _parseIntValue(
        json['max_reactions_per_post'],
        defaultValue: 11,
      ).clamp(1, 11),
      unreadMentionsCount: _parseIntValue(json['unread_mentions_count']),
      unreadReactionsCount: _parseIntValue(json['unread_reactions_count']),
      mySendAsChatId: _nonEmptyString(json['my_send_as_chat_id']),
      mySendAsMode: _nonEmptyString(json['my_send_as_mode']),
    );
  }
}

/// ChatParticipant represents a participant in a chat.
class ChatParticipant {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String role;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? lastSeenStatus;
  final bool isBot;
  final bool isVerified;
  final String adminTitle;
  final bool isAnonymous;
  final AdminRights? adminPermissions;
  final MemberRestrictions? memberRestrictions;
  final DateTime? restrictedUntil;
  final bool isBanned;
  final PeerCustomization? peerCustomization;
  final int? promotedByUserId;

  ChatParticipant({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.role,
    this.isOnline = false,
    this.lastSeen,
    this.lastSeenStatus,
    this.isBot = false,
    this.isVerified = false,
    this.adminTitle = '',
    this.isAnonymous = false,
    this.adminPermissions,
    this.memberRestrictions,
    this.restrictedUntil,
    this.isBanned = false,
    this.peerCustomization,
    this.promotedByUserId,
  });

  ChatParticipant copyWith({
    String? id,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? role,
    bool? isOnline,
    DateTime? lastSeen,
    String? lastSeenStatus,
    bool? isBot,
    bool? isVerified,
    String? adminTitle,
    bool? isAnonymous,
    AdminRights? adminPermissions,
    MemberRestrictions? memberRestrictions,
    DateTime? restrictedUntil,
    bool? isBanned,
    PeerCustomization? peerCustomization,
    int? promotedByUserId,
  }) {
    return ChatParticipant(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      lastSeenStatus: lastSeenStatus ?? this.lastSeenStatus,
      isBot: isBot ?? this.isBot,
      isVerified: isVerified ?? this.isVerified,
      adminTitle: adminTitle ?? this.adminTitle,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      adminPermissions: adminPermissions ?? this.adminPermissions,
      memberRestrictions: memberRestrictions ?? this.memberRestrictions,
      restrictedUntil: restrictedUntil ?? this.restrictedUntil,
      isBanned: isBanned ?? this.isBanned,
      peerCustomization: peerCustomization ?? this.peerCustomization,
      promotedByUserId: promotedByUserId ?? this.promotedByUserId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'role': role,
        'is_online': isOnline,
        if (lastSeen != null) 'last_seen': lastSeen!.toUtc().toIso8601String(),
        if (lastSeenStatus != null) 'last_seen_status': lastSeenStatus,
        'is_bot': isBot,
        'is_verified': isVerified,
        'admin_title': adminTitle,
        'is_anonymous': isAnonymous,
        if (adminPermissions != null)
          'admin_permissions': adminPermissions!.toJson(),
        if (memberRestrictions != null)
          'member_restrictions': memberRestrictions!.toJson(),
        if (restrictedUntil != null)
          'restricted_until': restrictedUntil!.toUtc().toIso8601String(),
        'is_banned': isBanned,
        if (promotedByUserId != null) 'promoted_by': promotedByUserId,
      };

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    final pid = (json['id'] ?? json['user_id'] ?? '').toString();
    final rawCust = json['peer_customization'];
    final PeerCustomization? parsedCust = rawCust is Map
        ? PeerCustomization.fromJson(Map<String, dynamic>.from(rawCust))
        : (rawCust is String && rawCust.isNotEmpty
            ? PeerCustomization.tryParseJsonString(rawCust)
            : null);
    if (pid.isNotEmpty && parsedCust != null) {
      PeerCustomizationCache.instance.put(pid, parsedCust, notify: false);
    }
    final rawPromotedBy = json['promoted_by'];
    final int? parsedPromotedBy = rawPromotedBy is num
        ? rawPromotedBy.toInt()
        : (rawPromotedBy != null
            ? int.tryParse(rawPromotedBy.toString())
            : null);
    return ChatParticipant(
      id: pid,
      username: json['username']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString(),
      role: json['role']?.toString() ?? 'member',
      isOnline: json['is_online'] == true,
      lastSeen: DateTimeUtils.parseUtcDateTime(json['last_seen']),
      lastSeenStatus: _nonEmptyString(json['last_seen_status']),
      isBot: json['is_bot'] == true,
      isVerified: json['is_verified'] == true,
      adminTitle: (json['admin_title'] ?? '').toString(),
      isAnonymous: _parseBoolFlag(json['is_anonymous']),
      adminPermissions: AdminRights.tryParse(json['admin_permissions']),
      memberRestrictions: MemberRestrictions.tryParse(
        json['member_restrictions'],
      ),
      restrictedUntil: DateTimeUtils.parseUtcDateTime(json['restricted_until']),
      isBanned: _parseBoolFlag(json['is_banned']),
      peerCustomization: parsedCust,
      promotedByUserId: parsedPromotedBy,
    );
  }
}

/// ChatService handles all chat-related API operations.
class ChatService {
  static String _extractErrorMessage(dynamic data, [String fallback = 'Request failed']) {
    if (data is Map) {
      final desc = data['description']?.toString();
      if (desc != null && desc.isNotEmpty) return desc;
      final msg = data['message']?.toString();
      if (msg != null && msg.isNotEmpty) return msg;
      final err = data['error']?.toString();
      if (err != null && err.isNotEmpty) return err;
    }
    return fallback;
  }

  static int? _extractRetryAfter(dynamic data) {
    if (data is Map && data['parameters'] is Map) {
      final ra = data['parameters']['retry_after'];
      if (ra is int) return ra;
      if (ra != null) return int.tryParse(ra.toString());
    }
    return null;
  }

  /// Creates a new chat.
  ///
  /// [chatType] - Type of chat: 'private', 'group', or 'channel'
  /// [name] - Name for group/channel (optional for private)
  /// [participantIds] - List of user IDs to add as participants
  static Future<Map<String, dynamic>> createChat({
    required String chatType,
    String? name,
    String? description,
    String? username,
    bool? isPublic,
    bool? signMessages,
    bool? showAuthorProfiles,
    bool? historyForNewMembers,
    bool? allowInvites,
    bool? hasProtectedContent,
    bool? createDiscussionGroup,
    required List<String> participantIds,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final payload = <String, dynamic>{
        'chat_type': chatType,
        'name': name,
        'participant_ids': participantIds,
        if (description != null && description.isNotEmpty) 'description': description,
        if (username != null && username.isNotEmpty) 'username': username,
        if (isPublic != null) 'is_public': isPublic,
        if (signMessages != null) 'sign_messages': signMessages,
        if (showAuthorProfiles != null) 'show_author_profiles': showAuthorProfiles,
        if (historyForNewMembers != null)
          'history_for_new_members': historyForNewMembers,
        if (allowInvites != null) 'allow_invites': allowInvites,
        if (hasProtectedContent != null)
          'has_protected_content': hasProtectedContent,
        if (createDiscussionGroup != null)
          'create_discussion_group': createDiscussionGroup,
      };

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'chat': Chat.fromJson(data['chat']),
          'message': data['message'] ?? 'Chat created successfully',
        };
      } else {
        return {
          'success': false,
          'message': _extractErrorMessage(data, 'Failed to create chat'),
          'error_code': data is Map ? data['code'] ?? data['error'] : null,
          'retry_after': _extractRetryAfter(data),
        };
      }
    } catch (e) {
      debugPrint('Create chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Gets the list of chats for the current user.
  static Future<Map<String, dynamic>> getChats() async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {
          'success': false,
          'message': 'Not authenticated',
          'chats': <Chat>[]
        };
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        List<Chat> chats = [];
        if (data['chats'] != null && data['chats'] is List) {
          for (var chat in data['chats']) {
            if (chat is! Map) continue;
            if (chat['community_id'] != null) {
              continue;
            }
            try {
              chats.add(Chat.fromJson(Map<String, dynamic>.from(chat)));
            } catch (e) {
              debugPrint('Skipping malformed chat item: $e');
            }
          }
        }
        return {'success': true, 'chats': chats};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to get chats',
          'chats': <Chat>[],
        };
      }
    } catch (e) {
      debugPrint('Get chats error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'chats': <Chat>[]
      };
    }
  }

  /// Gets detailed information about a specific chat.
  static Future<Map<String, dynamic>> getChat(String chatId) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'chat': ChatDetails.fromJson(data['chat']),
        };
      } else {
        return {
          'success': false,
          'status_code': response.statusCode,
          'error_code': data is Map ? (data['error'] ?? data['code']) : null,
          'message': _extractErrorMessage(data, 'Failed to get chat'),
        };
      }
    } catch (e) {
      debugPrint('Get chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Gets messages for a specific chat.
  ///
  /// [chatId] - The ID of the chat
  /// [limit] - Maximum number of messages to return (default: 50)
  /// [offset] - Number of messages to skip (for pagination, legacy)
  /// [beforeMessageId] - Cursor-based pagination: load messages older than this ID
  static Future<Map<String, dynamic>> getMessages({
    required String chatId,
    int limit = 50,
    int offset = 0,
    String? beforeMessageId,
    String? beforeCreatedAt,
    String? untilMessageId,
    String? aroundMessageId,
    String? afterMessageId,
    String? tag,
    String? savedPeerKey,
    int? topicId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {
          'success': false,
          'message': 'Not authenticated',
          'messages': <Message>[]
        };
      }

      var url = '${AppConfig.baseUrl}/api/chats/$chatId/messages?limit=$limit';
      if (topicId != null && topicId > 0) {
        url += '&topic_id=$topicId';
      }
      if (tag != null && tag.isNotEmpty) {
        url += '&tag=${Uri.encodeQueryComponent(tag)}';
      }
      if (savedPeerKey != null && savedPeerKey.isNotEmpty) {
        url += '&saved_peer_key=${Uri.encodeQueryComponent(savedPeerKey)}';
      }
      if (afterMessageId != null && afterMessageId.isNotEmpty) {
        url += '&after_message_id=$afterMessageId';
      } else if (aroundMessageId != null && aroundMessageId.isNotEmpty) {
        url += '&around_message_id=$aroundMessageId';
      } else {
        if (beforeMessageId != null && beforeMessageId.isNotEmpty) {
          url += '&before_message_id=$beforeMessageId';
        }
        if (beforeCreatedAt != null && beforeCreatedAt.isNotEmpty) {
          url += '&before_created_at=${Uri.encodeComponent(beforeCreatedAt)}';
        } else if (beforeMessageId == null && offset > 0) {
          url += '&offset=$offset';
        }
        if (untilMessageId != null && untilMessageId.isNotEmpty) {
          url += '&until_message_id=$untilMessageId';
        }
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final bool useIsolate = !kIsWeb &&
          response.statusCode == 200 &&
          response.body.length >= 4096;
      if (useIsolate) {
        final rawBody = response.body;
        final parsed = await Isolate.run(
          () => _parseMessagesResponseBody((rawBody, chatId, limit)),
        );
        if (parsed.success) {
          parsed.peerCustomizations.forEach((uid, cust) {
            PeerCustomizationCache.instance.put(uid, cust, notify: false);
          });
          return {
            'success': true,
            'messages': parsed.messages,
            'has_more': parsed.hasMore,
            'has_more_newer': parsed.hasMoreNewer,
          };
        }
        return {
          'success': false,
          'status_code': response.statusCode,
          'error_code': parsed.errorCode,
          'message': _extractErrorMessage(
            parsed.errorBody,
            'Failed to get messages',
          ),
          'messages': <Message>[],
        };
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final parsed = _parseMessagesFromDecoded(data, chatId, limit);
        return {
          'success': true,
          'messages': parsed.messages,
          'has_more': parsed.hasMore,
          'has_more_newer': parsed.hasMoreNewer,
        };
      } else {
        return {
          'success': false,
          'status_code': response.statusCode,
          'error_code': data is Map ? (data['error'] ?? data['code']) : null,
          'message': _extractErrorMessage(data, 'Failed to get messages'),
          'messages': <Message>[],
        };
      }
    } catch (e) {
      debugPrint('Get messages error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'messages': <Message>[]
      };
    }
  }

  /// Delta Sync: получить обновления с сервера после указанного USN
  ///
  /// [sinceUsn] - Last known Update Sequence Number
  /// [limit] - Maximum number of events to return (default: 100)
  static Future<Map<String, dynamic>> getUpdates({
    required int sinceUsn,
    int limit = 100,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/api/updates?since_usn=$sinceUsn&limit=$limit'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'events': data['events'] ?? [],
          'max_usn': data['max_usn'] ?? data['current_usn'] ?? sinceUsn,
          'current_usn': data['current_usn'] ?? data['max_usn'] ?? sinceUsn,
          'has_more': data['has_more'] ?? false,
          'too_long': data['too_long'] == true,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to get updates',
        };
      }
    } catch (e) {
      debugPrint('Get updates error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Sends a message to a chat.
  ///
  /// [chatId] - The ID of the chat
  /// [content] - The message content
  /// [messageType] - Type of message: 'text', 'image', 'video', 'file', 'audio', etc.
  /// [fileUrl] - URL of the file (for media messages)
  /// [fileName] - Name of the file (for file messages)
  /// [replyToMessageId] - ID of the message being replied to (optional)
  static void _applySendAsPayload(
    Map<String, dynamic> body, {
    String? sendAsMode,
    String? sendAsChatId,
    required bool sendAsAnonymous,
  }) {
    final trimmedChatId = sendAsChatId?.trim() ?? '';
    final explicitMode = sendAsMode?.trim() ?? '';
    final String resolvedMode = explicitMode.isNotEmpty
        ? explicitMode
        : (trimmedChatId.isNotEmpty
            ? 'channel'
            : (sendAsAnonymous ? 'group' : 'user'));
    final bool effectiveAnonymous = resolvedMode == 'group' ||
        (explicitMode.isEmpty && sendAsAnonymous && trimmedChatId.isEmpty);
    body['send_as_anonymous'] = effectiveAnonymous;
    body['send_as_mode'] = resolvedMode;
    body['send_as_chat_id'] =
        (resolvedMode == 'channel' && trimmedChatId.isNotEmpty)
            ? (int.tryParse(trimmedChatId) ?? trimmedChatId)
            : '';
  }

  /// [localId] - Local message ID for offline-first tracking (optional)
  /// [isQuote] - Whether this is a quote (partial text) reply (optional)
  /// [quoteText] - The quoted text fragment (optional)
  /// [quoteOffset] - Offset of the quote in the original message (optional)
  /// [quoteLength] - Length of the quoted fragment (optional)
  static Future<Map<String, dynamic>> sendMessage({
    required String chatId,
    required String content,
    String messageType = 'text',
    String? fileUrl,
    String? fileName,
    String? replyToMessageId,
    String? replyToChatId,
    String? localId,
    bool isQuote = false,
    String? quoteText,
    int quoteOffset = 0,
    int quoteLength = 0,
    List<MessageEntity>? entities,
    LinkPreviewOptions? linkPreviewOptions,
    bool invertMedia = false,
    bool isRound = false,
    List<int>? waveform,
    int? duration,
    String? groupedId,
    Map<String, dynamic>? mediaPayload,
    bool isSilent = false,
    bool sendAsAnonymous = false,
    bool hasMediaSpoiler = false,
    bool isViewOnce = false,
    int ttlSeconds = 0,
    String? effectId,
    double? latitude,
    double? longitude,
    int? livePeriod,
    int? heading,
    double? horizontalAccuracy,
    String? placeName,
    String? address,
    Map<String, dynamic>? contact,
    int? topicId,
    String? sendAsChatId,
    String? sendAsMode,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      String effectiveMessageType = messageType;
      bool effectiveIsRound = isRound;
      if (effectiveMessageType == 'round') {
        effectiveMessageType = 'video';
        effectiveIsRound = true;
      } else if (fileUrl == null &&
          latitude == null &&
          contact == null &&
          EmojiUtils.isDiceEmoji(content)) {
        effectiveMessageType = 'dice';
      }

      final body = <String, dynamic>{
        'content': content,
        'message_type': effectiveMessageType,
      };
      if (fileUrl != null) body['file_url'] = fileUrl;
      if (fileName != null) body['file_name'] = fileName;
      if (effectiveIsRound) body['is_round'] = true;
      if (waveform != null && waveform.isNotEmpty) body['waveform'] = waveform;
      if (duration != null && duration > 0) body['duration'] = duration;
      if (groupedId != null && groupedId.isNotEmpty) body['grouped_id'] = groupedId;
      final effectiveMediaPayload = <String, dynamic>{
        if (mediaPayload != null) ...mediaPayload,
      };
      if (replyToMessageId != null) {
        body['reply_to_message_id'] = replyToMessageId;
        if (replyToChatId != null && replyToChatId.isNotEmpty) {
          body['reply_to_chat_id'] = int.tryParse(replyToChatId) ?? replyToChatId;
        }
        if (isQuote) {
          body['is_quote'] = true;
          effectiveMediaPayload['is_quote'] = true;
          if (quoteText != null) {
            body['quote_text'] = quoteText;
            effectiveMediaPayload['quote_text'] = quoteText;
          }
          if (quoteOffset > 0) {
            body['quote_offset'] = quoteOffset;
            effectiveMediaPayload['quote_offset'] = quoteOffset;
          }
          if (quoteLength > 0) {
            body['quote_length'] = quoteLength;
            effectiveMediaPayload['quote_length'] = quoteLength;
          }
        }
      }
      if (effectiveMediaPayload.isNotEmpty) {
        body['media_payload'] = effectiveMediaPayload;
      }
      if (localId != null) body['local_id'] = localId;
      if (entities != null && entities.isNotEmpty) {
        body['entities'] = entities.map((e) => e.toJson()).toList();
      }
      if (linkPreviewOptions != null) {
        body['link_preview_options'] = linkPreviewOptions.toJson();
      }
      if (invertMedia) {
        body['invert_media'] = true;
      }
      if (isSilent) {
        body['is_silent'] = true;
      }
      if (hasMediaSpoiler) {
        body['has_media_spoiler'] = true;
      }
      if (isViewOnce) {
        body['is_view_once'] = true;
      }
      if (ttlSeconds > 0) {
        body['ttl_seconds'] = ttlSeconds;
      }
      if (effectId != null && effectId.isNotEmpty) {
        body['effect_id'] = effectId;
      }
      if (latitude != null && longitude != null) {
        body['latitude'] = latitude;
        body['longitude'] = longitude;
      }
      if (livePeriod != null && livePeriod > 0) {
        body['live_period'] = livePeriod;
      }
      if (heading != null) {
        body['heading'] = heading;
      }
      if (horizontalAccuracy != null) {
        body['horizontal_accuracy'] = horizontalAccuracy;
      }
      if (placeName != null && placeName.isNotEmpty) {
        body['place_name'] = placeName;
      }
      if (address != null && address.isNotEmpty) {
        body['address'] = address;
      }
      if (contact != null && contact.isNotEmpty) {
        body['contact'] = contact;
      }
      if (topicId != null && topicId > 0) {
        body['topic_id'] = topicId;
      }
      _applySendAsPayload(
        body,
        sendAsMode: sendAsMode,
        sendAsChatId: sendAsChatId,
        sendAsAnonymous: sendAsAnonymous,
      );

      // Try WebSocket RPC first when connected
      if (WebSocketService().isConnected) {
        try {
          final rpcPayload = <String, dynamic>{
            'chat_id': chatId,
            ...body,
          };
          final rpcResult = await WebSocketService().sendRpc(
            'send_message',
            rpcPayload,
          );
          final rawMsg = rpcResult['message'];
          if (rawMsg is Map) {
            var parsedMessage = Message.fromJson(
              Map<String, dynamic>.from(rawMsg),
            );
            if (isQuote && !parsedMessage.isQuote) {
              parsedMessage = parsedMessage.copyWith(
                isQuote: true,
                quoteText: parsedMessage.quoteText ?? quoteText,
                quoteOffset: parsedMessage.quoteOffset != 0
                    ? parsedMessage.quoteOffset
                    : quoteOffset,
                quoteLength: parsedMessage.quoteLength != 0
                    ? parsedMessage.quoteLength
                    : quoteLength,
              );
            }
            return {
              'success': true,
              'message': parsedMessage,
              'deduplicated': rpcResult['deduplicated'] == true,
            };
          }
        } on WsRpcException catch (e) {
          // 503 (WS disconnected) or 504 (timeout) -> fall back to HTTP REST
          if (e.statusCode != 503 && e.statusCode != 504) {
            return {
              'success': false,
              'message': e.description,
              'error_code': e.errorCode,
              'status_code': e.statusCode,
              if (e.retryAfter != null) 'retry_after': e.retryAfter,
            };
          }
          debugPrint('WS RPC send_message fallback to HTTP: $e');
        } catch (e) {
          debugPrint('WS RPC send_message unexpected error, fallback to HTTP: $e');
        }
      }

      if (AppConfig.enableDebugLogging) {
        debugPrint(
            'SendMessage: POST ${AppConfig.baseUrl}/api/chats/$chatId/messages');
        debugPrint('SendMessage: body = $body');
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      if (AppConfig.enableDebugLogging) {
        debugPrint(
            'SendMessage: Response ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        Message parsedMessage;
        try {
          final rawMsg = data['message'];
          if (rawMsg is Map) {
            parsedMessage = Message.fromJson(Map<String, dynamic>.from(rawMsg));
          } else {
            throw const FormatException('Expected map for message');
          }
        } catch (parseError) {
          debugPrint('Error parsing sent message: $parseError');
          final rawMsg = data['message'] is Map ? (data['message'] as Map) : {};
          parsedMessage = Message(
            id: rawMsg['id']?.toString() ?? localId ?? '',
            chatId: chatId,
            senderId: rawMsg['sender_id']?.toString() ?? '',
            content: rawMsg['content']?.toString() ?? content,
            messageType: rawMsg['message_type']?.toString() ?? effectiveMessageType,
            isEdited: rawMsg['is_edited'] == true,
            createdAt: rawMsg['created_at']?.toString() ?? DateTime.now().toIso8601String(),
            senderName: rawMsg['sender_name']?.toString() ?? 'You',
            fileUrl: rawMsg['file_url']?.toString() ?? fileUrl,
            fileName: rawMsg['file_name']?.toString() ?? fileName,
            localId: localId,
            sendStatus: 1,
            groupedId: rawMsg['grouped_id']?.toString() ?? groupedId,
          );
        }
        if (isQuote && !parsedMessage.isQuote) {
          parsedMessage = parsedMessage.copyWith(
            isQuote: true,
            quoteText: parsedMessage.quoteText ?? quoteText,
            quoteOffset: parsedMessage.quoteOffset != 0 ? parsedMessage.quoteOffset : quoteOffset,
            quoteLength: parsedMessage.quoteLength != 0 ? parsedMessage.quoteLength : quoteLength,
          );
        }
        return {
          'success': true,
          'message': parsedMessage,
        };
      } else {
        final retryAfter = _extractRetryAfter(data);
        return {
          'success': false,
          'message': _extractErrorMessage(data, 'Failed to send message'),
          'error_code': data is Map ? data['error']?.toString() : null,
          'status_code': response.statusCode,
          if (retryAfter != null) 'retry_after': retryAfter,
        };
      }
    } catch (e) {
      debugPrint('Send message error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Отправить медиа-альбом (2-10 фото/видео) с общим grouped_id
  static Future<Map<String, dynamic>> sendMediaAlbum({
    required String chatId,
    required List<Map<String, dynamic>> items,
    String? groupedId,
    String? caption,
    List<MessageEntity>? entities,
    bool invertMedia = false,
    String? replyToMessageId,
    String? replyToChatId,
    String? effectId,
    bool isSilent = false,
    bool sendAsAnonymous = false,
    bool hasMediaSpoiler = false,
    int? topicId,
    String? sendAsChatId,
    String? sendAsMode,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final body = <String, dynamic>{
        'items': items,
      };
      if (groupedId != null && groupedId.isNotEmpty) {
        body['grouped_id'] = groupedId;
      }
      if (caption != null && caption.isNotEmpty) {
        body['caption'] = caption;
      }
      if (entities != null && entities.isNotEmpty) {
        body['entities'] = entities.map((e) => e.toJson()).toList();
      }
      if (invertMedia) {
        body['invert_media'] = true;
      }
      if (isSilent) {
        body['is_silent'] = true;
      }
      if (hasMediaSpoiler) {
        body['has_media_spoiler'] = true;
      }
      if (topicId != null && topicId > 0) {
        body['topic_id'] = topicId;
      }
      _applySendAsPayload(
        body,
        sendAsMode: sendAsMode,
        sendAsChatId: sendAsChatId,
        sendAsAnonymous: sendAsAnonymous,
      );
      if (effectId != null && effectId.isNotEmpty) {
        body['effect_id'] = effectId;
      }
      if (replyToMessageId != null && replyToMessageId.isNotEmpty) {
        body['reply_to_message_id'] = replyToMessageId;
        if (replyToChatId != null && replyToChatId.isNotEmpty) {
          body['reply_to_chat_id'] = int.tryParse(replyToChatId) ?? replyToChatId;
        }
      }

      if (AppConfig.enableDebugLogging) {
        debugPrint(
            'SendMediaAlbum: POST ${AppConfig.baseUrl}/api/chats/$chatId/messages/album');
        debugPrint('SendMediaAlbum: body = $body');
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/album'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      if (AppConfig.enableDebugLogging) {
        debugPrint(
            'SendMediaAlbum: Response ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final rawMessages = data['messages'] as List<dynamic>? ?? [];
        final parsedMessages = <Message>[];
        for (final m in rawMessages) {
          try {
            if (m is Map) {
              parsedMessages.add(Message.fromJson(Map<String, dynamic>.from(m)));
            }
          } catch (e) {
            debugPrint('Failed to parse album message: $e');
          }
        }
        return {
          'success': true,
          'grouped_id': data['grouped_id'],
          'messages': parsedMessages,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to send media album',
        };
      }
    } catch (e) {
      debugPrint('Send media album error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Marks all messages in a chat as read.
  ///
  /// [chatId] - The ID of the chat
  static Future<Map<String, dynamic>> markMessagesAsRead({
    required String chatId,
    String? chatTitle,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/read'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        NotificationService().cancelChatNotifications(chatId, chatTitle: chatTitle);
        return {
          'success': true,
          'marked_count': data['marked_count'] ?? 0,
          'unread_count': data['unread_count'] ?? 0,
          'message': data['message'] ?? 'Messages marked as read',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to mark messages as read',
        };
      }
    } catch (e) {
      debugPrint('Mark messages as read error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Edits a message in a chat.
  ///
  /// [chatId] - The ID of the chat containing the message
  /// [messageId] - The ID of the message to edit
  /// [content] - The new content for the message
  static Future<Map<String, dynamic>> editMessage({
    required String chatId,
    required String messageId,
    required String content,
    List<MessageEntity>? entities,
    bool? hasMediaSpoiler,
    bool? invertMedia,
    String? fileUrl,
    String? fileName,
    String? messageType,
    Map<String, dynamic>? mediaPayload,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final body = <String, dynamic>{
        'content': content,
      };
      if (entities != null) {
        body['entities'] = entities.map((e) => e.toJson()).toList();
      }
      if (hasMediaSpoiler != null) {
        body['has_media_spoiler'] = hasMediaSpoiler;
      }
      if (invertMedia != null) {
        body['invert_media'] = invertMedia;
      }
      if (fileUrl != null && fileUrl.isNotEmpty) {
        body['file_url'] = fileUrl;
      }
      if (fileName != null && fileName.isNotEmpty) {
        body['file_name'] = fileName;
      }
      if (messageType != null && messageType.isNotEmpty) {
        body['message_type'] = messageType;
      }
      if (mediaPayload != null && mediaPayload.isNotEmpty) {
        body['media_payload'] = mediaPayload;
      }

      final response = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Message edited successfully',
          'message_id': data['message_id']?.toString() ?? messageId,
          'content': data['content'] ?? content,
          'is_edited': true,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to edit message',
        };
      }
    } catch (e) {
      debugPrint('Edit message error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Deletes a message from a chat (with optional Telegram revoke for peer).
  static Future<Map<String, dynamic>> deleteMessage({
    required String chatId,
    required String messageId,
    bool revoke = true,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.delete(
        Uri.parse(
          '${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId?revoke=$revoke',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        try {
          await AppDatabase().deleteMessage(messageId);
          await AppDatabase().refreshChatLastMessageFromDb(chatId);
        } catch (_) {}
        return {
          'success': true,
          'message': data['message'] ?? 'Message deleted successfully',
          'message_id': data['message_id']?.toString() ?? messageId,
          'revoked': data['revoked'] ?? revoke,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to delete message',
        };
      }
    } catch (e) {
      debugPrint('Delete message error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Batch deletes multiple messages (`POST /api/chats/:id/messages/delete`)
  /// with Telegram revoke and admin moderation options.
  static Future<Map<String, dynamic>> deleteMessagesBatch({
    required String chatId,
    required List<String> messageIds,
    bool revoke = true,
    bool reportSpam = false,
    bool banUser = false,
    bool deleteAllFromUser = false,
  }) async {
    if (messageIds.isEmpty) {
      return {'success': false, 'message': 'No messages specified'};
    }
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final parsedIds = messageIds
          .map((id) => int.tryParse(id.trim()) ?? id.trim())
          .toList();

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/delete'),
        headers: headers,
        body: jsonEncode({
          'message_ids': parsedIds,
          'revoke': revoke,
          'report_spam': reportSpam,
          'ban_user': banUser,
          'delete_all_from_user': deleteAllFromUser,
        }),
      );

      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        final rawDeleted = data['deleted_ids'];
        final deletedIds = rawDeleted is List
            ? rawDeleted.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
            : messageIds;
        try {
          await AppDatabase().deleteMessagesBatch(deletedIds);
          await AppDatabase().refreshChatLastMessageFromDb(chatId);
        } catch (_) {}
        return {
          'success': true,
          'deleted_ids': deletedIds,
          'deleted_count': data['deleted_count'] ?? deletedIds.length,
          'revoked': data['revoked'] ?? revoke,
        };
      }
      return {
        'success': false,
        'status_code': response.statusCode,
        'message': _extractErrorMessage(data, 'Не удалось удалить сообщения'),
      };
    } catch (e) {
      debugPrint('Batch delete messages error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Save chat draft to server (PUT /api/chats/:id/draft)
  static Future<Map<String, dynamic>> saveDraft({
    required String chatId,
    required String text,
    List<MessageEntity> entities = const [],
    String? replyToMessageId,
    String? quoteText,
    bool isQuote = false,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/draft'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'text': text,
          if (entities.isNotEmpty)
            'entities': entities.map((e) => e.toJson()).toList(),
          'reply_to_message_id': replyToMessageId,
          'quote_text': quoteText,
          'is_quote': isQuote,
        }),
      );

      final data = jsonDecode(response.body);
      return data is Map<String, dynamic>
          ? data
          : {'success': response.statusCode == 200};
    } catch (e) {
      debugPrint('Save draft error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Get chat draft from server
  static Future<ChatDraft?> getDraft({required String chatId}) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/draft'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true &&
            data['draft'] != null &&
            data['draft'] is Map<String, dynamic>) {
          return ChatDraft.fromJson(data['draft'] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Get draft error: $e');
      return null;
    }
  }

  /// Delete chat draft on server
  static Future<void> deleteDraft({required String chatId}) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return;

      await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/draft'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'text': ''}),
      );
    } catch (e) {
      debugPrint('Delete draft error: $e');
    }
  }

  /// Clears the chat history for a specific chat.
  ///
  /// [chatId] - The ID of the chat to clear
  static Future<Map<String, dynamic>> clearChatHistory({
    required String chatId,
    bool revoke = false,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages?revoke=$revoke'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        try {
          await AppDatabase().deleteMessagesForChat(chatId);
          await AppDatabase().refreshChatLastMessageFromDb(chatId, allowClear: true);
        } catch (_) {}
        return {
          'success': true,
          'message': data['message'] ?? 'Chat history cleared',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to clear chat history',
        };
      }
    } catch (e) {
      debugPrint('Clear chat history error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Blocks a user.
  ///
  /// [userId] - The ID of the user to block
  static Future<Map<String, dynamic>> blockUser({
    required String userId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/security/blocked'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'blocked_user_id': userId}),
      );

      final data = jsonDecode(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          (data['success'] == true || data['success'] == null)) {
        return {
          'success': true,
          'message': data['message'] ?? 'User blocked successfully',
        };
      } else {
        return {
          'success': false,
          'message': data['error'] ?? data['message'] ?? 'Failed to block user',
        };
      }
    } catch (e) {
      debugPrint('Block user error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Unblocks a user.
  ///
  /// [userId] - The ID of the user to unblock
  static Future<Map<String, dynamic>> unblockUser({
    required String userId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/security/blocked/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 &&
          (data['success'] == true || data['success'] == null)) {
        return {
          'success': true,
          'message': data['message'] ?? 'User unblocked successfully',
        };
      } else {
        return {
          'success': false,
          'message': data['error'] ?? data['message'] ?? 'Failed to unblock user',
        };
      }
    } catch (e) {
      debugPrint('Unblock user error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Sets mute status for chat notifications.
  ///
  /// [chatId] - The ID of the chat
  /// [muted] - Whether to mute or unmute notifications
  static Future<Map<String, dynamic>> setMuteNotifications({
    required String chatId,
    required bool muted,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'muted': muted}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'muted': data['muted'] ?? muted,
          'message': data['message'] ?? 'Notification settings updated',
        };
      } else {
        return {
          'success': false,
          'message':
              data['message'] ?? 'Failed to update notification settings',
        };
      }
    } catch (e) {
      debugPrint('Set mute notifications error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Marks all messages up to a specific message as read.
  /// Used for progressive read tracking as user scrolls through messages.
  ///
  /// [chatId] - The ID of the chat
  /// [messageId] - The ID of the message up to which all messages should be marked as read
  static Future<Map<String, dynamic>> markMessagesReadUpTo({
    required String chatId,
    required String messageId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      if (WebSocketService().isConnected) {
        try {
          final rpcResult = await WebSocketService().sendRpc(
            'read_history',
            {
              'chat_id': chatId,
              'max_id': messageId,
            },
          );
          return {
            'success': true,
            'marked_count': rpcResult['marked_count'] ?? 0,
            'unread_count': rpcResult['unread_count'] ?? 0,
            'last_read_inbox_message_id':
                rpcResult['last_read_inbox_message_id'] ??
                    int.tryParse(messageId) ??
                    0,
            'message': 'Messages marked as read',
          };
        } on WsRpcException catch (e) {
          if (e.statusCode != 503 && e.statusCode != 504) {
            return {
              'success': false,
              'message': e.description,
            };
          }
        } catch (_) {}
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/read-up-to'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'message_id': messageId}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'marked_count': data['marked_count'] ?? 0,
          'unread_count': data['unread_count'] ?? 0,
          'last_read_inbox_message_id':
              data['last_read_inbox_message_id'] ??
                  int.tryParse(messageId) ??
                  0,
          'message': data['message'] ?? 'Messages marked as read',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to mark messages as read',
        };
      }
    } catch (e) {
      debugPrint('Mark messages read up to error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Gets information about unread messages in a chat.
  /// Returns the ID of the first unread message and total unread count.
  ///
  /// [chatId] - The ID of the chat
  static Future<Map<String, dynamic>> getUnreadInfo({
    required String chatId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/unread-info'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'unread_count': data['unread_count'] ?? 0,
          'unread_mentions_count':
              _parseIntValue(data['unread_mentions_count']),
          'unread_reactions_count':
              _parseIntValue(data['unread_reactions_count']),
          'first_unread_message_id': data['first_unread_message_id'],
          'first_unread_message_created_at':
              data['first_unread_message_created_at'],
          'last_read_inbox_message_id': data['last_read_inbox_message_id'] ?? 0,
          'last_read_outbox_message_id':
              data['last_read_outbox_message_id'] ?? 0,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to get unread info',
        };
      }
    } catch (e) {
      debugPrint('Get unread info error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Pins a chat to the top of the chat list.
  ///
  /// [chatId] - The ID of the chat to pin
  static Future<Map<String, dynamic>> pinChat({
    required String chatId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/pin'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'is_pinned': data['is_pinned'] ?? true,
          'message': data['message'] ?? 'Chat pinned successfully',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to pin chat',
        };
      }
    } catch (e) {
      debugPrint('Pin chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Unpins a chat from the top of the chat list.
  ///
  /// [chatId] - The ID of the chat to unpin
  static Future<Map<String, dynamic>> unpinChat({
    required String chatId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/unpin'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'is_pinned': data['is_pinned'] ?? false,
          'message': data['message'] ?? 'Chat unpinned successfully',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to unpin chat',
        };
      }
    } catch (e) {
      debugPrint('Unpin chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Archives a chat for the current user (`POST /api/chats/:id/archive`).
  static Future<Map<String, dynamic>> archiveChat({
    required String chatId,
  }) =>
      _setChatArchiveState(chatId: chatId, archived: true);

  /// Unarchives a chat for the current user (`DELETE /api/chats/:id/archive`).
  static Future<Map<String, dynamic>> unarchiveChat({
    required String chatId,
  }) =>
      _setChatArchiveState(chatId: chatId, archived: false);

  static Future<Map<String, dynamic>> _setChatArchiveState({
    required String chatId,
    required bool archived,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final uri = Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/archive');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
      final response = archived
          ? await http.post(uri, headers: headers)
          : await http.delete(uri, headers: headers);

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final effectiveArchived = data['is_archived'] == true || archived;
        await AppDatabase().setChatArchived(chatId, effectiveArchived);
        return {
          'success': true,
          'is_archived': effectiveArchived,
          'message': data['message'] ?? 'Archive state updated',
        };
      }
      return {
        'success': false,
        'error': data['error']?.toString(),
        'message': data['message'] ?? 'Failed to update archive state',
      };
    } catch (e) {
      debugPrint('Set archive chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Gets or creates the "Saved Messages" / "Favorites" chat for the current user.
  /// This is a special chat with the user themselves.
  static Future<Map<String, dynamic>> getOrCreateSavedChat() async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/saved'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'chat': Chat.fromJson(data['chat']),
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to get saved chat',
        };
      }
    } catch (e) {
      debugPrint('Get saved chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Delete or leave a chat.
  /// - Private: removes the user from the chat
  /// - Group: if owner, deletes the entire chat; otherwise leaves
  /// - Channel: unsubscribes
  static Future<Map<String, dynamic>> deleteChat(
    String chatId, {
    bool revoke = false,
  }) async {
    try {
      final token = await AuthService.getToken();
      final uri = revoke
          ? Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId?revoke=true')
          : Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId');
      final response = await http.delete(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to delete chat',
        };
      }
    } catch (e) {
      debugPrint('Delete chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Toggle reaction on a message (add or remove)
  static Future<Map<String, dynamic>> toggleReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return {'success': false, 'message': 'Not authenticated'};

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/reactions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'emoji': emoji}),
      );

      if (AppConfig.enableDebugLogging) {
        debugPrint(
            'ToggleReaction: POST ${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/reactions emoji=$emoji');
        debugPrint(
            'ToggleReaction: Response ${response.statusCode}: ${response.body}');
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return {
          'success': data['success'] ?? false,
          'active': data['active'] ?? false,
          'action': data['action'] ?? (data['active'] == true ? 'added' : 'removed'),
          'reactions': data['reactions'],
        };
      } else {
        debugPrint('ToggleReaction failed: ${response.statusCode} ${response.body}');
        final errData = _tryDecodeJson(response.body);
        return {
          'success': false,
          'status_code': response.statusCode,
          'error_code':
              errData is Map ? (errData['error'] ?? errData['code']) : null,
          'message': _extractErrorMessage(
            errData,
            'Server error: ${response.statusCode}',
          ),
        };
      }
    } catch (e) {
      debugPrint('Toggle reaction error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Get reactions for a message
  static Future<Map<String, dynamic>> getReactions({
    required String chatId,
    required String messageId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return {'success': false, 'message': 'Not authenticated'};

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/reactions'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      return data;
    } catch (e) {
      debugPrint('Get reactions error: $e');
      return {'success': false, 'reactions': []};
    }
  }

  /// Marks a voice message or round video message as listened/watched.
  static Future<Map<String, dynamic>> markMessageListened({
    required String chatId,
    required String messageId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse(
            '${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/listened'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        final readAt = data['read_at']?.toString();
        final listenedAt = data['listened_at']?.toString();
        try {
          await AppDatabase().updateMessageReadAndListened(
            messageId,
            readAt: readAt,
            listenedAt: listenedAt,
            isListened: true,
          );
        } catch (_) {}
        return data is Map<String, dynamic>
            ? data
            : {'success': true, 'read_at': readAt, 'listened_at': listenedAt};
      }
      return {'success': false, 'message': 'Server error: ${response.statusCode}'};
    } catch (e) {
      debugPrint('Mark message listened error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Gets the list of users who read and/or listened/watched a message with exact timestamps.
  static Future<Map<String, dynamic>> getMessageReaders({
    required String chatId,
    required String messageId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'readers': []};
      }

      final response = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/readers'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
      return {'success': false, 'readers': []};
    } catch (e) {
      debugPrint('Get message readers error: $e');
      return {'success': false, 'readers': []};
    }
  }

  /// Gets the calendar day index (message counts, first/last message IDs, and media preview URLs)
  /// for a chat, grouped in the user's local timezone.
  static Future<Map<String, ChatCalendarDayInfo>> getChatCalendar({
    required String chatId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return {};

      final tzOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
      final response = await http.get(
        Uri.parse(
          '${AppConfig.baseUrl}/api/chats/$chatId/calendar?tz_offset_minutes=$tzOffsetMinutes',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> &&
            data['success'] == true &&
            data['days'] is List) {
          final result = <String, ChatCalendarDayInfo>{};
          for (final raw in data['days'] as List) {
            if (raw is Map) {
              final info = ChatCalendarDayInfo.fromJson(
                Map<String, dynamic>.from(raw),
              );
              if (info.date.isNotEmpty) {
                result[info.date] = info;
              }
            }
          }
          return result;
        }
      }
    } catch (e) {
      debugPrint('Get chat calendar error: $e');
    }
    return {};
  }

  /// Server-side message forwarding (POST /api/chats/:toChatId/messages/forward)
  static Future<Map<String, dynamic>> forwardMessages({
    required String toChatId,
    required String fromChatId,
    required List<String> messageIds,
    bool hideSender = false,
    bool hideCaption = false,
    int? topicId,
    String? sendAsChatId,
    String? sendAsMode,
    bool sendAsAnonymous = false,
    bool isSilent = false,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final parsedIds = messageIds
          .map((id) => int.tryParse(id) ?? id)
          .toList();

      final body = <String, dynamic>{
        'from_chat_id': int.tryParse(fromChatId) ?? fromChatId,
        'message_ids': parsedIds,
        'hide_sender': hideSender,
        if (hideCaption) 'hide_caption': true,
        if (topicId != null && topicId > 0) 'topic_id': topicId,
        if (isSilent) 'is_silent': true,
      };
      _applySendAsPayload(
        body,
        sendAsMode: sendAsMode,
        sendAsChatId: sendAsChatId,
        sendAsAnonymous: sendAsAnonymous,
      );

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$toChatId/messages/forward'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final rawList = data['messages'] as List<dynamic>? ?? [];
        final messages = <Message>[];
        for (final item in rawList) {
          if (item is Map) {
            try {
              messages.add(Message.fromJson(Map<String, dynamic>.from(item)));
            } catch (_) {}
          }
        }
        return {
          'success': true,
          'messages': messages,
          'forwarded_count': data['forwarded_count'] ?? messages.length,
        };
      } else {
        final retryAfter = _extractRetryAfter(data);
        return {
          'success': false,
          'status_code': response.statusCode,
          if (data is Map && data['error'] != null)
            'error_code': data['error'].toString(),
          'message': _extractErrorMessage(data, 'Не удалось переслать сообщения'),
          if (retryAfter != null) 'retry_after': retryAfter,
        };
      }
    } catch (e) {
      debugPrint('Forward messages error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Pin a message inside a chat (POST /api/chats/:chatId/messages/:messageId/pin)
  static Future<Map<String, dynamic>> pinMessage({
    required String chatId,
    required String messageId,
    bool notify = true,
    bool onlyForMe = false,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse(
            '${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/pin'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'notify': notify,
          if (onlyForMe) 'only_for_me': true,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final nextPinId =
            _parseNullableInt(data['pinned_message_id']) ?? int.tryParse(messageId);
        final pinIds = _parseIntList(data['pinned_message_ids']);
        try {
          await AppDatabase().updateChatPinnedMessageId(
            chatId,
            nextPinId,
            pinnedMessageIds: pinIds,
            updatePinnedMessageIds: data.containsKey('pinned_message_ids'),
          );
        } catch (_) {}
        return {
          'success': true,
          'pinned_message_id': nextPinId,
          if (pinIds.isNotEmpty) 'pinned_message_ids': pinIds,
        };
      } else {
        return {
          'success': false,
          'message': _extractErrorMessage(data, 'Не удалось закрепить сообщение'),
        };
      }
    } catch (e) {
      debugPrint('Pin message error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Unpin a message inside a chat (DELETE /api/chats/:chatId/messages/:messageId/pin)
  static Future<Map<String, dynamic>> unpinMessage({
    required String chatId,
    required String messageId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.delete(
        Uri.parse(
            '${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/pin'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final nextPinId = _parseNullableInt(data['pinned_message_id']);
        final pinIds = _parseIntList(data['pinned_message_ids']);
        try {
          await AppDatabase().updateChatPinnedMessageId(
            chatId,
            nextPinId,
            pinnedMessageIds: pinIds,
            updatePinnedMessageIds: data.containsKey('pinned_message_ids'),
          );
        } catch (_) {}
        return {
          'success': true,
          'pinned_message_id': nextPinId,
          'pinned_message_ids': pinIds,
        };
      } else {
        return {
          'success': false,
          'message': _extractErrorMessage(data, 'Не удалось открепить сообщение'),
        };
      }
    } catch (e) {
      debugPrint('Unpin message error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Get all pinned messages in a chat (GET /api/chats/:chatId/pinned-messages)
  static Future<List<Message>> getPinnedMessages({
    required String chatId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return [];

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/pinned-messages'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawList = (data['pinned_messages'] ?? data['messages']) as List<dynamic>? ?? [];
        final result = <Message>[];
        for (final item in rawList) {
          if (item is Map) {
            try {
              result.add(Message.fromJson(Map<String, dynamic>.from(item)));
            } catch (_) {}
          }
        }
        return result;
      }
      return [];
    } catch (e) {
      debugPrint('Get pinned messages error: $e');
      return [];
    }
  }

  /// Unpins all messages in a chat (`DELETE /api/chats/:chatId/pinned-messages`).
  static Future<bool> unpinAllMessages({
    required String chatId,
  }) async {
    final ok = await _sendBoolRequest(
      'DELETE',
      '/api/chats/$chatId/pinned-messages',
    );
    if (ok) {
      try {
        await AppDatabase().updateChatPinnedMessageId(
          chatId,
          null,
          pinnedMessageIds: const [],
          updatePinnedMessageIds: true,
        );
      } catch (_) {}
    }
    return ok;
  }

  /// Preview an invite link code without joining (GET /api/chats/invite/:code)
  static Future<Map<String, dynamic>> checkInviteLink(String code) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/invite/${Uri.encodeComponent(code)}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return Map<String, dynamic>.from(data);
      } else {
        return {
          'success': false,
          'message': _extractErrorMessage(data, 'Ссылка-приглашение недействительна'),
        };
      }
    } catch (e) {
      debugPrint('Check invite link error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Join a chat by invite link code (POST /api/chats/join/:code)
  static Future<Map<String, dynamic>> joinByInviteLink(String code) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/join/${Uri.encodeComponent(code)}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return Map<String, dynamic>.from(data);
      } else {
        return {
          'success': false,
          'message': _extractErrorMessage(data, 'Не удалось вступить по ссылке'),
        };
      }
    } catch (e) {
      debugPrint('Join by invite link error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  static dynamic _tryDecodeJson(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String>?> _authHeaders() async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) return null;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<bool> _sendBoolRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return false;
      final uri = Uri.parse('${AppConfig.baseUrl}$path');
      final encodedBody = body != null ? jsonEncode(body) : null;
      late final http.Response response;
      switch (method) {
        case 'POST':
          response = await http.post(uri, headers: headers, body: encodedBody);
          break;
        case 'PUT':
          response = await http.put(uri, headers: headers, body: encodedBody);
          break;
        case 'PATCH':
          response = await http.patch(uri, headers: headers, body: encodedBody);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers, body: encodedBody);
          break;
        default:
          return false;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = _tryDecodeJson(response.body);
        if (data is Map) return data['success'] != false;
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('ChatService $method $path error: $e');
      return false;
    }
  }

  static final StreamController<ChatRealtimeUpdate> _realtimeController =
      StreamController<ChatRealtimeUpdate>.broadcast();

  /// Stream of channel/group real-time updates handled by [ChatService].
  static Stream<ChatRealtimeUpdate> get realtimeUpdates =>
      _realtimeController.stream;

  /// Handles Telegram channel/group WebSocket events, syncs Drift, and notifies listeners.
  static Future<void> handleWebSocketEvent(
    WebSocketEvent event, {
    AppDatabase? db,
    String? currentUserId,
  }) async {
    final rawType = (event.rawType.isNotEmpty
            ? event.rawType
            : (event.data['__raw_type'] ?? event.data['type'] ?? '').toString())
        .trim();
    final targetDb = db ?? AppDatabase();
    final chatId =
        (event.data['chat_id'] ?? event.data['id'] ?? '').toString().trim();

    if (event.type == WebSocketEventType.messageViewsUpdated ||
        rawType == 'message_views_updated') {
      final viewsMap = <String, int>{};
      final forwardsMap = <String, int>{};
      final rawViews = event.data['views'];
      if (rawViews is List) {
        for (final item in rawViews) {
          if (item is Map) {
            final msgId = (item['message_id'] ?? item['id'] ?? '').toString();
            final count = _parseIntValue(item['views_count'], defaultValue: -1);
            if (msgId.isNotEmpty && count >= 0) {
              viewsMap[msgId] = count;
            }
            if (msgId.isNotEmpty && item.containsKey('forwards_count')) {
              final fwdCount = _parseIntValue(
                item['forwards_count'],
                defaultValue: -1,
              );
              if (fwdCount >= 0) {
                forwardsMap[msgId] = fwdCount;
              }
            }
          }
        }
      } else if (event.data['message_id'] != null) {
        final msgId = event.data['message_id'].toString();
        final count = _parseIntValue(
          event.data['views_count'],
          defaultValue: -1,
        );
        if (msgId.isNotEmpty && count >= 0) {
          viewsMap[msgId] = count;
        }
        if (msgId.isNotEmpty && event.data.containsKey('forwards_count')) {
          final fwdCount = _parseIntValue(
            event.data['forwards_count'],
            defaultValue: -1,
          );
          if (fwdCount >= 0) {
            forwardsMap[msgId] = fwdCount;
          }
        }
      }
      if (viewsMap.isNotEmpty) {
        try {
          await targetDb.updateMessagesViews(viewsMap);
        } catch (e) {
          debugPrint('ChatService WS message_views_updated DB error: $e');
        }
      }
      if (forwardsMap.isNotEmpty) {
        try {
          await targetDb.updateMessagesForwards(forwardsMap);
        } catch (e) {
          debugPrint('ChatService WS message_views_updated forwards DB error: $e');
        }
      }
      _realtimeController.add(ChatRealtimeUpdate(
        type: WebSocketEventType.messageViewsUpdated,
        chatId: chatId,
        data: Map<String, dynamic>.from(event.data),
      ));
      return;
    }

    if (event.type == WebSocketEventType.unreadBadgesUpdated ||
        rawType == 'unread_badges_updated') {
      if (chatId.isNotEmpty) {
        final mentionsCnt = _parseIntValue(event.data['unread_mentions_count']);
        final reactionsCnt =
            _parseIntValue(event.data['unread_reactions_count']);
        try {
          await targetDb.updateChatUnreadBadges(
            chatId,
            unreadMentionsCount: mentionsCnt,
            unreadReactionsCount: reactionsCnt,
          );
        } catch (e) {
          debugPrint('ChatService WS unread_badges_updated DB error: $e');
        }
      }
      _realtimeController.add(ChatRealtimeUpdate(
        type: WebSocketEventType.unreadBadgesUpdated,
        chatId: chatId,
        data: Map<String, dynamic>.from(event.data),
      ));
      return;
    }

    if (event.type == WebSocketEventType.forumTopicUpdated ||
        rawType == 'forum_topic_updated') {
      _realtimeController.add(ChatRealtimeUpdate(
        type: WebSocketEventType.forumTopicUpdated,
        chatId: chatId,
        data: Map<String, dynamic>.from(event.data),
      ));
      return;
    }

    if (event.type == WebSocketEventType.postCommentsUpdated ||
        rawType == 'post_comments_updated') {
      final messageId =
          (event.data['message_id'] ?? event.data['post_id'] ?? '').toString();
      final hasCount = event.data.containsKey('comments_count');
      final commentsCount =
          hasCount ? _parseIntValue(event.data['comments_count']) : null;
      String? recentRepliersJson;
      if (event.data.containsKey('recent_repliers')) {
        final parsed = RecentReplier.parseList(event.data['recent_repliers']);
        recentRepliersJson =
            jsonEncode(parsed.map((r) => r.toJson()).toList());
      }
      if (messageId.isNotEmpty) {
        try {
          await targetDb.updatePostCommentsMeta(
            messageId: messageId,
            commentsCount: commentsCount,
            recentRepliersJson: recentRepliersJson,
          );
        } catch (e) {
          debugPrint('ChatService WS post_comments_updated DB error: $e');
        }
      }
      _realtimeController.add(ChatRealtimeUpdate(
        type: WebSocketEventType.postCommentsUpdated,
        chatId: chatId,
        data: Map<String, dynamic>.from(event.data),
      ));
      return;
    }

    if (event.type == WebSocketEventType.chatSettingsUpdated ||
        rawType == 'chat_settings_updated') {
      if (chatId.isNotEmpty) {
        try {
          final existing = await targetDb.getChat(chatId);
          if (existing != null) {
            final perms = GroupDefaultPermissions.tryParse(
              event.data['default_permissions'] ??
                  event.data['chat_permissions'],
            );
            final reactions = ReactionSettings.fromChatJson(event.data);
            final hasLinked = event.data.containsKey('linked_chat_id');
            final hasAvatar = event.data.containsKey('avatar_url');
            final hasUsername = event.data.containsKey('username');
            await targetDb.updateChatSettings(
              chatId,
              name: event.data.containsKey('name')
                  ? event.data['name']?.toString()
                  : null,
              avatarUrl: hasAvatar ? event.data['avatar_url']?.toString() : null,
              updateAvatarUrl: hasAvatar,
              username: hasUsername ? event.data['username']?.toString() : null,
              updateUsername: hasUsername,
              isPublic: event.data.containsKey('is_public')
                  ? _parseBoolFlag(event.data['is_public'])
                  : null,
              showAuthorProfiles: event.data.containsKey('show_author_profiles')
                  ? _parseBoolFlag(event.data['show_author_profiles'])
                  : null,
              signMessages: event.data.containsKey('sign_messages')
                  ? _parseBoolFlag(event.data['sign_messages'])
                  : null,
              linkedChatId:
                  hasLinked ? event.data['linked_chat_id']?.toString() : null,
              updateLinkedChatId: hasLinked,
              myRole: event.data.containsKey('my_role')
                  ? _nonEmptyString(event.data['my_role'])
                  : null,
              hasActiveCall: event.data.containsKey('has_active_call')
                  ? _parseBoolFlag(event.data['has_active_call'])
                  : null,
              chatPermissionsJson:
                  perms != null ? jsonEncode(perms.toJson()) : null,
              reactionSettingsJson:
                  reactions != null ? jsonEncode(reactions.toJson()) : null,
              hasProtectedContent: event.data.containsKey('has_protected_content')
                  ? _parseBoolFlag(event.data['has_protected_content'])
                  : null,
              pinnedMessageIdsJson: event.data.containsKey('pinned_message_ids')
                  ? jsonEncode(_parseIntList(event.data['pinned_message_ids']))
                  : null,
              updatePinnedMessageIds:
                  event.data.containsKey('pinned_message_ids'),
              isForum: event.data.containsKey('is_forum')
                  ? _parseBoolFlag(event.data['is_forum'])
                  : null,
              participantsHidden: event.data.containsKey('participants_hidden')
                  ? _parseBoolFlag(event.data['participants_hidden'])
                  : null,
              hasAggressiveAntiSpamEnabled:
                  event.data.containsKey('has_aggressive_anti_spam_enabled')
                      ? _parseBoolFlag(
                          event.data['has_aggressive_anti_spam_enabled'],
                        )
                      : null,
              maxReactionsPerPost: event.data.containsKey('max_reactions_per_post')
                  ? _parseIntValue(
                      event.data['max_reactions_per_post'],
                      defaultValue: 11,
                    ).clamp(1, 11)
                  : null,
            );
          }
        } catch (e) {
          debugPrint('ChatService WS chat_settings_updated DB error: $e');
        }
      }
      _realtimeController.add(ChatRealtimeUpdate(
        type: WebSocketEventType.chatSettingsUpdated,
        chatId: chatId,
        data: Map<String, dynamic>.from(event.data),
      ));
      return;
    }

    if (event.type == WebSocketEventType.scheduledMessagesUpdated ||
        rawType == 'scheduled_messages_updated') {
      _realtimeController.add(ChatRealtimeUpdate(
        type: WebSocketEventType.scheduledMessagesUpdated,
        chatId: chatId,
        data: Map<String, dynamic>.from(event.data),
      ));
      return;
    }

    if (event.type == WebSocketEventType.joinRequestsUpdated ||
        rawType == 'join_requests_updated') {
      _realtimeController.add(ChatRealtimeUpdate(
        type: WebSocketEventType.joinRequestsUpdated,
        chatId: chatId,
        data: Map<String, dynamic>.from(event.data),
      ));
      return;
    }

    if (event.type == WebSocketEventType.memberUpdated ||
        rawType == 'member_updated') {
      final targetUserId = (event.data['user_id'] ?? '').toString().trim();
      final action = (event.data['action'] ?? '').toString().trim();
      final myUid = currentUserId ??
          WebSocketService().currentUserId ??
          await AuthService.getUserId();
      if (chatId.isNotEmpty &&
          myUid != null &&
          myUid.isNotEmpty &&
          targetUserId == myUid) {
        try {
          if (action == 'removed' || action == 'banned') {
            await targetDb.deleteChat(chatId);
            await targetDb.deleteMessagesForChat(chatId);
          } else if (event.data.containsKey('role')) {
            final newRole = _nonEmptyString(event.data['role']);
            if (newRole != null) {
              await targetDb.updateChatSettings(chatId, myRole: newRole);
            }
          }
        } catch (e) {
          debugPrint('ChatService WS member_updated DB error: $e');
        }
      }
      _realtimeController.add(ChatRealtimeUpdate(
        type: WebSocketEventType.memberUpdated,
        chatId: chatId,
        data: Map<String, dynamic>.from(event.data),
      ));
      return;
    }

    if (event.type == WebSocketEventType.chatDeleted ||
        rawType == 'chat_deleted') {
      if (chatId.isNotEmpty) {
        try {
          await targetDb.deleteChat(chatId);
          await targetDb.deleteMessagesForChat(chatId);
        } catch (e) {
          debugPrint('ChatService WS chat_deleted DB error: $e');
        }
      }
      _realtimeController.add(ChatRealtimeUpdate(
        type: WebSocketEventType.chatDeleted,
        chatId: chatId,
        data: Map<String, dynamic>.from(event.data),
      ));
    }
  }

  /// Join a public group or channel by chat ID (POST /api/chats/:chatId/join).
  /// Returns a map with `'success'`, `'already_member'`, and `'chat'` ([Chat] on success).
  static Future<Map<String, dynamic>> joinPublicChat(String chatId) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/join'),
        headers: headers,
      );

      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        final rawChat = data['chat'];
        final Chat? parsedChat = rawChat is Map
            ? Chat.fromJson(Map<String, dynamic>.from(rawChat))
            : null;
        if (parsedChat != null) {
          try {
            await AppDatabase().saveChat(parsedChat.toCompanion());
          } catch (_) {}
        }
        return {
          ...Map<String, dynamic>.from(data),
          if (parsedChat != null) 'chat': parsedChat,
        };
      } else {
        return {
          'success': false,
          'status_code': response.statusCode,
          'message': _extractErrorMessage(data, 'Не удалось вступить в чат'),
        };
      }
    } catch (e) {
      debugPrint('Join public chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Typed convenience wrapper around [joinPublicChat] returning the joined [Chat] or null.
  static Future<Chat?> joinPublicChatModel(String chatId) async {
    final res = await joinPublicChat(chatId);
    if (res['success'] == true && res['chat'] is Chat) {
      return res['chat'] as Chat;
    }
    return null;
  }

  /// Leaves a group or channel (`POST /api/chats/:id/leave`).
  static Future<bool> leaveChat(String chatId, {String? newOwnerId}) async {
    final res = await leaveChatDetailed(chatId, newOwnerId: newOwnerId);
    return res['success'] == true;
  }

  /// Leaves a group or channel (`POST /api/chats/:id/leave`) with structured error details.
  static Future<Map<String, dynamic>> leaveChatDetailed(
    String chatId, {
    String? newOwnerId,
  }) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final body = <String, dynamic>{};
      if (newOwnerId != null && newOwnerId.isNotEmpty) {
        body['new_owner_id'] = int.tryParse(newOwnerId) ?? newOwnerId;
      }
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/leave'),
        headers: headers,
        body: jsonEncode(body),
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        try {
          await AppDatabase().deleteChat(chatId);
          await AppDatabase().deleteMessagesForChat(chatId);
        } catch (_) {}
        return Map<String, dynamic>.from(data);
      }
      return {
        'success': false,
        'status_code': response.statusCode,
        'error': data is Map ? data['error']?.toString() : null,
        'message': _extractErrorMessage(data, 'Failed to leave chat'),
      };
    } catch (e) {
      debugPrint('Leave chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Records message views in a channel/group (`POST /api/chats/:id/messages/views`).
  static Future<void> recordMessageViews({
    required String chatId,
    required List<String> messageIds,
  }) async {
    final cleaned = messageIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (cleaned.isEmpty) return;

    try {
      final headers = await _authHeaders();
      if (headers == null) return;

      for (var i = 0; i < cleaned.length; i += 50) {
        final chunk = cleaned.sublist(
          i,
          i + 50 > cleaned.length ? cleaned.length : i + 50,
        );
        final response = await http.post(
          Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/views'),
          headers: headers,
          body: jsonEncode({'message_ids': chunk}),
        );
        if (response.statusCode == 200) {
          final data = _tryDecodeJson(response.body);
          if (data is Map && data['views'] is List) {
            final viewsMap = <String, int>{};
            for (final item in data['views'] as List) {
              if (item is Map) {
                final mid = (item['message_id'] ?? item['id'] ?? '').toString();
                final cnt = _parseIntValue(
                  item['views_count'],
                  defaultValue: -1,
                );
                if (mid.isNotEmpty && cnt >= 0) {
                  viewsMap[mid] = cnt;
                }
              }
            }
            if (viewsMap.isNotEmpty) {
              try {
                await AppDatabase().updateMessagesViews(viewsMap);
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Record message views error: $e');
    }
  }

  /// Fetches discussion thread comments for a channel post (`GET /api/chats/:id/messages/:messageId/comments`).
  static Future<PostCommentsResult> getPostComments({
    required String channelId,
    required String messageId,
    int limit = 50,
    String? beforeId,
  }) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return const PostCommentsResult(
          success: false,
          errorMessage: 'Not authenticated',
        );
      }

      var url =
          '${AppConfig.baseUrl}/api/chats/$channelId/messages/$messageId/comments?limit=$limit';
      if (beforeId != null && beforeId.isNotEmpty) {
        url += '&before_id=${Uri.encodeComponent(beforeId)}';
      }

      final response = await http.get(Uri.parse(url), headers: headers);
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        final result = PostCommentsResult.fromJson(
          Map<String, dynamic>.from(data),
        );
        if (result.comments.isNotEmpty) {
          try {
            await AppDatabase().saveMessages(
              result.comments
                  .map((m) => m.toCompanion(fallbackChatId: result.linkedChatId))
                  .toList(),
            );
          } catch (_) {}
        }
        return result;
      }
      return PostCommentsResult(
        success: false,
        errorMessage: _extractErrorMessage(data, 'Failed to load comments'),
      );
    } catch (e) {
      debugPrint('Get post comments error: $e');
      return PostCommentsResult(
        success: false,
        errorMessage: 'Network error: ${e.toString()}',
      );
    }
  }

  /// Posts a comment under a channel post (`POST /api/chats/:id/messages/:messageId/comments`).
  static Future<Message?> sendPostComment({
    required String channelId,
    required String messageId,
    required String content,
    String? localId,
    String? replyToMessageId,
    bool isQuote = false,
    String? quoteText,
    int quoteOffset = 0,
    int quoteLength = 0,
    List<MessageEntity>? entities,
    String? fileUrl,
    String? fileName,
    String messageType = 'text',
    bool hasMediaSpoiler = false,
    String? groupedId,
    String? sendAsChatId,
    String? sendAsMode,
    bool sendAsAnonymous = false,
    bool isSilent = false,
  }) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return null;

      final trimmedLocalId = localId?.trim();
      final body = <String, dynamic>{
        'content': content,
        'message_type': messageType,
        if (trimmedLocalId != null && trimmedLocalId.isNotEmpty) ...{
          'local_id': trimmedLocalId,
          'client_message_id': trimmedLocalId,
        },
        if (replyToMessageId != null && replyToMessageId.isNotEmpty)
          'reply_to_message_id': replyToMessageId,
        if (isQuote) 'is_quote': true,
        if (isQuote && quoteText != null && quoteText.isNotEmpty)
          'quote_text': quoteText,
        if (isQuote && quoteOffset > 0) 'quote_offset': quoteOffset,
        if (isQuote && quoteLength > 0) 'quote_length': quoteLength,
        if (entities != null && entities.isNotEmpty)
          'entities': entities.map((e) => e.toJson()).toList(),
        if (fileUrl != null && fileUrl.isNotEmpty) 'file_url': fileUrl,
        if (fileName != null && fileName.isNotEmpty) 'file_name': fileName,
        if (hasMediaSpoiler) 'has_media_spoiler': true,
        if (groupedId != null && groupedId.isNotEmpty) 'grouped_id': groupedId,
        if (isSilent) 'is_silent': true,
      };
      _applySendAsPayload(
        body,
        sendAsMode: sendAsMode,
        sendAsChatId: sendAsChatId,
        sendAsAnonymous: sendAsAnonymous,
      );

      final response = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/api/chats/$channelId/messages/$messageId/comments',
        ),
        headers: headers,
        body: jsonEncode(body),
      );

      final data = _tryDecodeJson(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data is Map &&
          data['success'] == true) {
        final rawMsg = data['comment'] ?? data['message'];
        if (rawMsg is Map) {
          final parsed = Message.fromJson(Map<String, dynamic>.from(rawMsg));
          final normalized = (trimmedLocalId != null && trimmedLocalId.isNotEmpty)
              ? parsed.copyWith(localId: trimmedLocalId)
              : parsed;
          try {
            await AppDatabase().saveMessage(normalized.toCompanion());
            if (data['comments_count'] != null) {
              await AppDatabase().updatePostCommentsMeta(
                messageId: messageId,
                commentsCount: _parseIntValue(data['comments_count']),
              );
            }
          } catch (_) {}
          return normalized;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Send post comment error: $e');
      return null;
    }
  }

  /// Links, creates, or unlinks a channel discussion group (`PUT /api/chats/:id/discussion-group`).
  static Future<Map<String, dynamic>> updateChannelDiscussionGroup({
    required String channelId,
    String? linkedChatId,
    bool createNew = false,
    String? newGroupName,
  }) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final body = <String, dynamic>{
        'linked_chat_id': linkedChatId ?? '',
        'create_new': createNew,
        if (newGroupName != null && newGroupName.isNotEmpty)
          'new_group_name': newGroupName,
      };

      final response = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$channelId/discussion-group'),
        headers: headers,
        body: jsonEncode(body),
      );

      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        final updatedLinkedId = _nonEmptyString(data['linked_chat_id']) ??
            LinkedChatSummary.tryParse(data['linked_chat'])?.id;
        try {
          await AppDatabase().updateChatLinkedChatId(
            channelId,
            updatedLinkedId,
          );
        } catch (_) {}
        return Map<String, dynamic>.from(data);
      }
      return {
        'success': false,
        'status_code': response.statusCode,
        'message': _extractErrorMessage(
          data,
          'Failed to update discussion group',
        ),
      };
    } catch (e) {
      debugPrint('Update channel discussion group error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Fetches settings for a group or channel (`GET /api/chats/:id/group-settings`).
  static Future<Map<String, dynamic>> getGroupSettings(String chatId) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/group-settings'),
        headers: headers,
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        return Map<String, dynamic>.from(data);
      }
      return {
        'success': false,
        'status_code': response.statusCode,
        'message': _extractErrorMessage(data, 'Failed to get group settings'),
      };
    } catch (e) {
      debugPrint('Get group settings error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Updates group or channel settings (`PUT /api/chats/:id/group-settings`).
  static Future<Map<String, dynamic>> updateGroupSettings(
    String chatId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/group-settings'),
        headers: headers,
        body: jsonEncode(payload),
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        try {
          final perms = GroupDefaultPermissions.tryParse(
            payload['default_permissions'],
          );
          final reactions = ReactionSettings.fromChatJson(payload);
          await AppDatabase().updateChatSettings(
            chatId,
            name: payload.containsKey('name')
                ? payload['name']?.toString()
                : null,
            avatarUrl: payload.containsKey('avatar_url')
                ? payload['avatar_url']?.toString()
                : null,
            updateAvatarUrl: payload.containsKey('avatar_url'),
            username: payload.containsKey('username')
                ? payload['username']?.toString()
                : null,
            updateUsername: payload.containsKey('username'),
            isPublic: payload.containsKey('is_public')
                ? _parseBoolFlag(payload['is_public'])
                : null,
            showAuthorProfiles: payload.containsKey('show_author_profiles')
                ? _parseBoolFlag(payload['show_author_profiles'])
                : null,
            signMessages: payload.containsKey('sign_messages')
                ? _parseBoolFlag(payload['sign_messages'])
                : null,
            chatPermissionsJson:
                perms != null ? jsonEncode(perms.toJson()) : null,
            reactionSettingsJson:
                reactions != null ? jsonEncode(reactions.toJson()) : null,
            hasProtectedContent: payload.containsKey('has_protected_content')
                ? _parseBoolFlag(payload['has_protected_content'])
                : null,
            isForum: payload.containsKey('is_forum')
                ? _parseBoolFlag(payload['is_forum'])
                : null,
            participantsHidden: payload.containsKey('participants_hidden')
                ? _parseBoolFlag(payload['participants_hidden'])
                : null,
            hasAggressiveAntiSpamEnabled:
                payload.containsKey('has_aggressive_anti_spam_enabled')
                    ? _parseBoolFlag(
                        payload['has_aggressive_anti_spam_enabled'],
                      )
                    : null,
            maxReactionsPerPost: payload.containsKey('max_reactions_per_post')
                ? _parseIntValue(
                    payload['max_reactions_per_post'],
                    defaultValue: 11,
                  ).clamp(1, 11)
                : null,
          );
        } catch (_) {}
        return Map<String, dynamic>.from(data);
      }
      return {
        'success': false,
        'status_code': response.statusCode,
        'message': _extractErrorMessage(data, 'Failed to update settings'),
      };
    } catch (e) {
      debugPrint('Update group settings error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Fetches members of a group or channel (`GET /api/chats/:id/members`).
  static Future<List<ChatParticipant>> getGroupMembers(String chatId) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return [];
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/members'),
        headers: headers,
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map && data['members'] is List) {
        return (data['members'] as List)
            .whereType<Map>()
            .map((m) => ChatParticipant.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get group members error: $e');
      return [];
    }
  }

  /// Updates a member's admin role, granular rights, custom title, and anonymity (`PUT /api/chats/:id/members/:userId/admin-rights`).
  static Future<bool> updateMemberAdminRights({
    required String chatId,
    required String userId,
    required String role,
    AdminRights? permissions,
    String? adminTitle,
    bool? isAnonymous,
  }) {
    return _sendBoolRequest(
      'PUT',
      '/api/chats/$chatId/members/$userId/admin-rights',
      body: {
        'role': role,
        if (permissions != null) 'admin_permissions': permissions.toJson(),
        if (adminTitle != null) 'admin_title': adminTitle,
        if (isAnonymous != null) 'is_anonymous': isAnonymous,
      },
    );
  }

  /// Updates granular restrictions for a group member (`PUT /api/chats/:id/members/:userId/restrictions`).
  static Future<bool> updateMemberRestrictions({
    required String chatId,
    required String userId,
    required MemberRestrictions restrictions,
    DateTime? restrictedUntil,
  }) {
    return _sendBoolRequest(
      'PUT',
      '/api/chats/$chatId/members/$userId/restrictions',
      body: {
        'member_restrictions': restrictions.toJson(),
        'restricted_until': restrictedUntil?.toUtc().toIso8601String(),
      },
    );
  }

  /// Bans a member from a group or channel (`POST /api/chats/:id/members/:userId/ban`).
  static Future<bool> banChatMember({
    required String chatId,
    required String userId,
  }) {
    return _sendBoolRequest('POST', '/api/chats/$chatId/members/$userId/ban');
  }

  /// Unbans a user from a group or channel (`DELETE /api/chats/:id/members/:userId/ban`).
  static Future<bool> unbanChatMember({
    required String chatId,
    required String userId,
  }) {
    return _sendBoolRequest(
      'DELETE',
      '/api/chats/$chatId/members/$userId/ban',
    );
  }

  /// Returns banned members of a group or channel (`GET /api/chats/:id/banned`).
  static Future<List<ChatParticipant>> getBannedChatMembers(
    String chatId,
  ) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return [];
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/banned'),
        headers: headers,
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map) {
        final rawList = data['banned'] ?? data['members'] ?? data['users'];
        if (rawList is List) {
          return rawList
              .whereType<Map>()
              .map((m) => ChatParticipant.fromJson(Map<String, dynamic>.from(m))
                  .copyWith(isBanned: true))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Get banned chat members error: $e');
      return [];
    }
  }

  /// Returns all invite links for a group or channel (`GET /api/chats/:id/invite-links`).
  static Future<List<InviteLinkItem>> getInviteLinks(String chatId) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return [];
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/invite-links'),
        headers: headers,
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map) {
        final rawList = data['links'] ?? data['invite_links'];
        if (rawList is List) {
          return rawList
              .whereType<Map>()
              .map((m) => InviteLinkItem.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Get invite links error: $e');
      return [];
    }
  }

  /// Creates a new invite link (`POST /api/chats/:id/invite-links`).
  static Future<InviteLinkItem?> createInviteLink({
    required String chatId,
    String? title,
    int maxUses = 0,
    DateTime? expiresAt,
    bool requiresApproval = false,
  }) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return null;

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/invite-links'),
        headers: headers,
        body: jsonEncode({
          if (title != null) 'title': title,
          'max_uses': maxUses,
          if (expiresAt != null)
            'expires_at': expiresAt.toUtc().toIso8601String(),
          if (requiresApproval) 'requires_approval': requiresApproval,
        }),
      );
      final data = _tryDecodeJson(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data is Map &&
          data['success'] != false) {
        final raw = data['invite_link'] is Map
            ? Map<String, dynamic>.from(data['invite_link'] as Map)
            : (data['link_item'] is Map
                ? Map<String, dynamic>.from(data['link_item'] as Map)
                : Map<String, dynamic>.from(data));
        final parsed = InviteLinkItem.fromJson(raw);
        if (parsed.link.isEmpty) return null;
        return parsed.copyWith(
          title: parsed.title.isEmpty && title != null ? title : parsed.title,
          maxUses: parsed.maxUses == 0 && maxUses > 0 ? maxUses : parsed.maxUses,
          expiresAt: parsed.expiresAt ?? expiresAt,
          requiresApproval: parsed.requiresApproval || requiresApproval,
        );
      }
      return null;
    } catch (e) {
      debugPrint('Create invite link error: $e');
      return null;
    }
  }

  /// Updates or revokes an invite link (`PATCH /api/chats/:id/invite-links/:linkId`).
  static Future<bool> updateInviteLink({
    required String chatId,
    required int linkId,
    String? title,
    int? maxUses,
    DateTime? expiresAt,
    bool? isRevoked,
    bool? requiresApproval,
  }) {
    return _sendBoolRequest(
      'PATCH',
      '/api/chats/$chatId/invite-links/$linkId',
      body: {
        if (title != null) 'title': title,
        if (maxUses != null) 'max_uses': maxUses,
        if (expiresAt != null) 'expires_at': expiresAt.toUtc().toIso8601String(),
        if (isRevoked != null) 'is_revoked': isRevoked,
        if (requiresApproval != null) 'requires_approval': requiresApproval,
      },
    );
  }

  /// Permanently deletes an invite link (`DELETE /api/chats/:id/invite-links/:linkId`).
  static Future<bool> deleteInviteLink({
    required String chatId,
    required int linkId,
  }) {
    return _sendBoolRequest(
      'DELETE',
      '/api/chats/$chatId/invite-links/$linkId',
    );
  }

  /// Lists pending invite-link join requests for admins (`GET /api/chats/:id/join-requests`).
  static Future<List<ChatJoinRequest>> getJoinRequests(String chatId) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return [];
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/join-requests'),
        headers: headers,
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map) {
        final rawList = data['join_requests'];
        if (rawList is List) {
          return rawList
              .whereType<Map>()
              .map((m) => ChatJoinRequest.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Get join requests error: $e');
      return [];
    }
  }

  /// Approves a pending join request (`POST /api/chats/:id/join-requests/:userId/approve`).
  static Future<bool> approveJoinRequest({
    required String chatId,
    required String userId,
  }) {
    return _sendBoolRequest(
      'POST',
      '/api/chats/$chatId/join-requests/$userId/approve',
    );
  }

  /// Declines a pending join request (`POST /api/chats/:id/join-requests/:userId/decline`).
  static Future<bool> declineJoinRequest({
    required String chatId,
    required String userId,
  }) {
    return _sendBoolRequest(
      'POST',
      '/api/chats/$chatId/join-requests/$userId/decline',
    );
  }

  /// Lists scheduled messages for a chat (`GET /api/chats/:id/scheduled`).
  static Future<List<ScheduledMessage>> getScheduledMessages(
    String chatId,
  ) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return [];
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/scheduled'),
        headers: headers,
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map) {
        final rawList = data['scheduled_messages'];
        if (rawList is List) {
          return rawList
              .whereType<Map>()
              .map((m) => ScheduledMessage.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Get scheduled messages error: $e');
      return [];
    }
  }

  /// Creates a scheduled message or send-when-online queue item (`POST /api/chats/:id/scheduled`).
  static Future<Map<String, dynamic>> createScheduledMessage({
    required String chatId,
    required String content,
    String messageType = 'text',
    DateTime? scheduleAt,
    bool sendWhenOnline = false,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    int? width,
    int? height,
    int duration = 0,
    bool isRound = false,
    bool hasMediaSpoiler = false,
    String? replyToMessageId,
    bool isQuote = false,
    String? quoteText,
    int quoteOffset = 0,
    int quoteLength = 0,
    List<MessageEntity>? entities,
    LinkPreviewOptions? linkPreviewOptions,
    bool invertMedia = false,
    Map<String, dynamic>? mediaPayload,
    String? groupedId,
    bool isSilent = false,
    bool sendAsAnonymous = false,
    String? sendAsChatId,
    String? sendAsMode,
    int? topicId,
  }) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      String effectiveMessageType = messageType;
      bool effectiveIsRound = isRound;
      if (effectiveMessageType == 'round') {
        effectiveMessageType = 'video';
        effectiveIsRound = true;
      }

      final body = <String, dynamic>{
        'content': content,
        'message_type': effectiveMessageType,
        if (fileUrl != null && fileUrl.isNotEmpty) 'file_url': fileUrl,
        if (fileName != null && fileName.isNotEmpty) 'file_name': fileName,
        if (fileSize != null && fileSize > 0) 'file_size': fileSize,
        if (width != null && width > 0) 'width': width,
        if (height != null && height > 0) 'height': height,
        if (duration > 0) 'duration': duration,
        if (effectiveIsRound) 'is_round': true,
        if (hasMediaSpoiler) 'has_media_spoiler': true,
        if (replyToMessageId != null && replyToMessageId.isNotEmpty)
          'reply_to_message_id': int.tryParse(replyToMessageId) ?? replyToMessageId,
        if (isQuote) 'is_quote': true,
        if (quoteText != null && quoteText.isNotEmpty) 'quote_text': quoteText,
        if (quoteOffset > 0) 'quote_offset': quoteOffset,
        if (quoteLength > 0) 'quote_length': quoteLength,
        if (entities != null && entities.isNotEmpty)
          'entities': entities.map((e) => e.toJson()).toList(),
        if (linkPreviewOptions != null)
          'link_preview_options': linkPreviewOptions.toJson(),
        if (invertMedia) 'invert_media': true,
        if (mediaPayload != null && mediaPayload.isNotEmpty)
          'media_payload': mediaPayload,
        if (groupedId != null && groupedId.isNotEmpty) 'grouped_id': groupedId,
        if (isSilent) 'is_silent': true,
        if (topicId != null && topicId > 0) 'topic_id': topicId,
        'send_when_online': sendWhenOnline,
        if (!sendWhenOnline && scheduleAt != null)
          'schedule_at': scheduleAt.toUtc().toIso8601String(),
      };
      _applySendAsPayload(
        body,
        sendAsMode: sendAsMode,
        sendAsChatId: sendAsChatId,
        sendAsAnonymous: sendAsAnonymous,
      );

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/scheduled'),
        headers: headers,
        body: jsonEncode(body),
      );
      final data = _tryDecodeJson(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data is Map &&
          data['success'] == true) {
        final raw = data['scheduled_message'];
        final parsed = raw is Map
            ? ScheduledMessage.fromJson(Map<String, dynamic>.from(raw))
            : null;
        return {
          'success': true,
          if (parsed != null) 'scheduled_message': parsed,
        };
      }
      return {
        'success': false,
        'status_code': response.statusCode,
        'message': _extractErrorMessage(data, 'Не удалось запланировать сообщение'),
      };
    } catch (e) {
      debugPrint('Create scheduled message error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Edits or reschedules a pending scheduled message (`PUT /api/chats/:id/scheduled/:schedId`).
  static Future<ScheduledMessage?> updateScheduledMessage({
    required String chatId,
    required String schedId,
    String? content,
    List<MessageEntity>? entities,
    bool? hasMediaSpoiler,
    bool? isSilent,
    DateTime? scheduleAt,
    bool? sendWhenOnline,
  }) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return null;
      final body = <String, dynamic>{
        if (content != null) 'content': content,
        if (entities != null)
          'entities': entities.map((e) => e.toJson()).toList(),
        if (hasMediaSpoiler != null) 'has_media_spoiler': hasMediaSpoiler,
        if (isSilent != null) 'is_silent': isSilent,
        if (sendWhenOnline != null) 'send_when_online': sendWhenOnline,
        if (scheduleAt != null)
          'schedule_at': scheduleAt.toUtc().toIso8601String(),
      };
      final response = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/scheduled/$schedId'),
        headers: headers,
        body: jsonEncode(body),
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true &&
          data['scheduled_message'] is Map) {
        return ScheduledMessage.fromJson(
          Map<String, dynamic>.from(data['scheduled_message'] as Map),
        );
      }
      return null;
    } catch (e) {
      debugPrint('Update scheduled message error: $e');
      return null;
    }
  }

  /// Sends a pending scheduled message immediately (`POST /api/chats/:id/scheduled/:schedId/send-now`).
  static Future<Message?> sendScheduledMessageNow({
    required String chatId,
    required String schedId,
  }) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return null;
      final response = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/api/chats/$chatId/scheduled/$schedId/send-now',
        ),
        headers: headers,
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true &&
          data['message'] is Map) {
        final parsed = Message.fromJson(
          Map<String, dynamic>.from(data['message'] as Map),
        );
        try {
          await AppDatabase().saveMessage(parsed.toCompanion(fallbackChatId: chatId));
          await AppDatabase().refreshChatLastMessageFromDb(chatId);
        } catch (_) {}
        return parsed;
      }
      return null;
    } catch (e) {
      debugPrint('Send scheduled message now error: $e');
      return null;
    }
  }

  /// Deletes a pending scheduled message (`DELETE /api/chats/:id/scheduled/:schedId`).
  static Future<bool> deleteScheduledMessage({
    required String chatId,
    required String schedId,
  }) {
    return _sendBoolRequest(
      'DELETE',
      '/api/chats/$chatId/scheduled/$schedId',
    );
  }

  /// Checks whether a chat currently has an active voice/video call (`GET /api/chats/:id/call`).
  static Future<Map<String, dynamic>?> getChatActiveCall(String chatId) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return null;

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/call'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = _tryDecodeJson(response.body);
        if (data is Map) {
          final rawCall = data['active_call'] ?? data['call'];
          if (rawCall is Map) {
            try {
              await AppDatabase().updateChatActiveCall(chatId, true);
            } catch (_) {}
            return Map<String, dynamic>.from(rawCall);
          }
          if (data['id'] != null) {
            try {
              await AppDatabase().updateChatActiveCall(chatId, true);
            } catch (_) {}
            return Map<String, dynamic>.from(data);
          }
          try {
            await AppDatabase().updateChatActiveCall(chatId, false);
          } catch (_) {}
        }
      }
      return null;
    } catch (e) {
      debugPrint('Get chat active call error: $e');
      return null;
    }
  }

  /// Marks a chat as manually unread on the server (`POST /api/chats/:id/mark-unread`).
  static Future<Map<String, dynamic>> markChatUnread(String chatId) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/mark-unread'),
        headers: headers,
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        return Map<String, dynamic>.from(data);
      }
      return {
        'success': false,
        'message': _extractErrorMessage(data, 'Failed to mark chat unread'),
      };
    } catch (e) {
      debugPrint('markChatUnread error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Clears manual unread marker on the server (`DELETE /api/chats/:id/mark-unread`).
  static Future<Map<String, dynamic>> unmarkChatUnread(String chatId) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/mark-unread'),
        headers: headers,
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        return Map<String, dynamic>.from(data);
      }
      return {
        'success': false,
        'message': _extractErrorMessage(data, 'Failed to unmark chat unread'),
      };
    } catch (e) {
      debugPrint('unmarkChatUnread error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Transfers ownership of a group or channel to another active member (`POST /api/chats/:id/transfer-ownership`).
  static Future<Map<String, dynamic>> transferChatOwnership({
    required String chatId,
    required String newOwnerId,
    String? password,
  }) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/transfer-ownership'),
        headers: headers,
        body: jsonEncode({
          'new_owner_id': int.tryParse(newOwnerId) ?? newOwnerId,
          if (password != null && password.isNotEmpty) 'password': password,
        }),
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        return Map<String, dynamic>.from(data);
      }
      return {
        'success': false,
        'error': data is Map ? data['error']?.toString() : null,
        'message': _extractErrorMessage(data, 'Failed to transfer ownership'),
      };
    } catch (e) {
      debugPrint('transferChatOwnership error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Merges incoming `media_payload` updates (such as neutral poll broadcasts or
  /// bot `reply_markup` edits) with existing local state so neutral broadcasts
  /// omitting `voted_option_ids` preserve the local user's voted options.
  static Map<String, dynamic>? mergeIncomingMediaPayload(
    Map<String, dynamic>? existing,
    Map<String, dynamic>? incoming, {
    dynamic replyMarkup,
  }) {
    if (incoming == null && replyMarkup == null) {
      return existing != null ? Map<String, dynamic>.from(existing) : null;
    }
    final merged = incoming != null
        ? Map<String, dynamic>.from(incoming)
        : (existing != null
            ? Map<String, dynamic>.from(existing)
            : <String, dynamic>{});

    if (replyMarkup != null) {
      merged['reply_markup'] = replyMarkup;
    }

    final isPollPayload =
        merged.containsKey('poll_id') || merged.containsKey('options');
    final hasExplicitVotes =
        incoming != null && incoming.containsKey('voted_option_ids');
    if (isPollPayload &&
        !hasExplicitVotes &&
        existing != null &&
        existing['voted_option_ids'] is List) {
      merged['voted_option_ids'] =
          List<dynamic>.from(existing['voted_option_ids'] as List);
    }
    if (incoming != null &&
        !merged.containsKey('reply_markup') &&
        existing != null &&
        existing['reply_markup'] != null &&
        isPollPayload) {
      merged['reply_markup'] = existing['reply_markup'];
    }
    return merged;
  }
}

/// Summary of messages and media preview for a single calendar day in a chat.
class ChatCalendarDayInfo {
  final String date; // YYYY-MM-DD in local timezone
  final int messageCount;
  final String firstMessageId;
  final String lastMessageId;
  final String? firstCreatedAt;
  final String? previewUrl;
  final String? previewBlurhash;

  const ChatCalendarDayInfo({
    required this.date,
    required this.messageCount,
    required this.firstMessageId,
    required this.lastMessageId,
    this.firstCreatedAt,
    this.previewUrl,
    this.previewBlurhash,
  });

  factory ChatCalendarDayInfo.fromJson(Map<String, dynamic> json) {
    final rawPreview = json['preview_url']?.toString();
    final rawBlurhash = json['preview_blurhash']?.toString();
    return ChatCalendarDayInfo(
      date: json['date']?.toString() ?? '',
      messageCount: _parseIntValue(json['message_count']),
      firstMessageId: json['first_message_id']?.toString() ?? '',
      lastMessageId: json['last_message_id']?.toString() ?? '',
      firstCreatedAt: json['first_created_at']?.toString(),
      previewUrl: (rawPreview != null && rawPreview.isNotEmpty) ? rawPreview : null,
      previewBlurhash:
          (rawBlurhash != null && rawBlurhash.isNotEmpty) ? rawBlurhash : null,
    );
  }
}

class _ParsedMessagesPayload {
  final bool success;
  final List<Message> messages;
  final bool hasMore;
  final bool hasMoreNewer;
  final Map<String, PeerCustomization> peerCustomizations;
  final dynamic errorCode;
  final dynamic errorBody;

  const _ParsedMessagesPayload({
    required this.success,
    this.messages = const [],
    this.hasMore = false,
    this.hasMoreNewer = false,
    this.peerCustomizations = const {},
    this.errorCode,
    this.errorBody,
  });
}

_ParsedMessagesPayload _parseMessagesFromDecoded(
  dynamic data,
  String chatId,
  int limit, {
  Map<String, PeerCustomization>? outPeerCustomizations,
}) {
  if (data is! Map || data['success'] != true) {
    return _ParsedMessagesPayload(
      success: false,
      errorCode: data is Map ? (data['error'] ?? data['code']) : null,
      errorBody: data,
    );
  }
  final messages = <Message>[];
  final rawList = data['messages'];
  if (rawList is List) {
    for (final msg in rawList) {
      if (msg is Map) {
        final map = Map<String, dynamic>.from(msg);
        if (map['chat_id'] == null || map['chat_id'].toString().isEmpty) {
          map['chat_id'] = chatId;
        }
        messages.add(
          Message.fromJson(
            map,
            outPeerCustomizations: outPeerCustomizations,
          ),
        );
      }
    }
  }
  return _ParsedMessagesPayload(
    success: true,
    messages: messages,
    hasMore: data['has_more'] ?? (messages.length >= limit),
    hasMoreNewer: data['has_more_newer'] ?? false,
    peerCustomizations: outPeerCustomizations ?? const {},
  );
}

_ParsedMessagesPayload _parseMessagesResponseBody(
  (String body, String chatId, int limit) args,
) {
  final data = jsonDecode(args.$1);
  final outPeers = <String, PeerCustomization>{};
  return _parseMessagesFromDecoded(
    data,
    args.$2,
    args.$3,
    outPeerCustomizations: outPeers,
  );
}
