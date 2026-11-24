import 'package:flutter/material.dart' show Color;

import 'call_models.dart';
import 'profile_customization.dart';
import '../services/peer_customization_cache.dart';

int _parseCommunityInt(dynamic raw, [int fallback = 0]) {
  if (raw == null) return fallback;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString().trim()) ?? fallback;
}

/// Bitmask permissions for Community roles and channel overwrites,
/// matching backend `permissions_community.go` 1-to-1.
class CommunityPermissions {
  static const int administrator = 1 << 0; // 1
  static const int viewChannel = 1 << 1; // 2
  static const int manageCommunity = 1 << 2; // 4
  static const int manageChannels = 1 << 3; // 8
  static const int manageRoles = 1 << 4; // 16
  static const int sendMessages = 1 << 5; // 32
  static const int connectVoice = 1 << 6; // 64
  static const int speakVoice = 1 << 7; // 128
  static const int video = 1 << 8; // 256
  static const int streamVideo = 1 << 9; // 512 (ScreenShare)
  static const int screenShareHd = 1 << 10; // 1024 (ScreenShareHD)
  static const int prioritySpeaker = 1 << 11; // 2048
  static const int muteMembers = 1 << 12; // 4096
  static const int deafenMembers = 1 << 13; // 8192
  static const int moveMembers = 1 << 14; // 16384
  static const int useSoundboard = 1 << 15; // 32768
  static const int manageStage = 1 << 16; // 65536
  static const int kickMembers = 1 << 17; // 131072
  static const int banMembers = 1 << 18; // 262144

  // Legacy aliases kept for compilation compatibility
  static const int manageMessages = manageChannels;

  static const int defaultEveryone = viewChannel |
      sendMessages |
      connectVoice |
      speakVoice |
      video |
      streamVideo |
      useSoundboard;

  static const List<({int bit, String title, String subtitle})> allFlags = [
    (
      bit: administrator,
      title: 'Администратор',
      subtitle: 'Полный доступ ко всем настройкам и каналам сообщества',
    ),
    (
      bit: viewChannel,
      title: 'Просмотр каналов',
      subtitle: 'Доступ к просмотру текстовых, голосовых каналов и трибун',
    ),
    (
      bit: manageCommunity,
      title: 'Управление сообществом',
      subtitle: 'Изменение названия, описания и аватара сообщества',
    ),
    (
      bit: manageChannels,
      title: 'Управление каналами и категориями',
      subtitle: 'Создание, редактирование и сортировка каналов',
    ),
    (
      bit: manageRoles,
      title: 'Управление ролями',
      subtitle: 'Создание и настройка прав ролей участников',
    ),
    (
      bit: sendMessages,
      title: 'Отправка сообщений',
      subtitle: 'Публикация сообщений в текстовых каналах',
    ),
    (
      bit: connectVoice,
      title: 'Подключение к голосовым каналам',
      subtitle: 'Вход в голосовые комнаты и трибуны',
    ),
    (
      bit: speakVoice,
      title: 'Голос в комнатах',
      subtitle: 'Разрешение говорить в голосовых каналах',
    ),
    (
      bit: video,
      title: 'Видеокамера в комнатах',
      subtitle: 'Разрешение включать камеру в голосовых каналах',
    ),
    (
      bit: streamVideo,
      title: 'Демонстрация экрана (Go Live)',
      subtitle: 'Трансляция экрана, окна или камеры в голосовых каналах',
    ),
    (
      bit: screenShareHd,
      title: 'Демонстрация экрана Ultra / HD (до 144 FPS)',
      subtitle: 'Трансляция в 1440p/4K при 120–144 FPS',
    ),
    (
      bit: prioritySpeaker,
      title: 'Приоритетный спикер',
      subtitle: 'Выделение голоса в голосовых комнатах',
    ),
    (
      bit: muteMembers,
      title: 'Модерация микрофонов (Mute)',
      subtitle: 'Отключение микрофона участников в голосовых комнатах',
    ),
    (
      bit: deafenMembers,
      title: 'Модерация звука (Deafen)',
      subtitle: 'Отключение звука участникам в голосовых комнатах',
    ),
    (
      bit: moveMembers,
      title: 'Перемещение и отключение участников',
      subtitle: 'Перемещение или отключение участников из голосовых комнат',
    ),
    (
      bit: useSoundboard,
      title: 'Использование саундборда',
      subtitle: 'Воспроизведение звуковых эффектов в голосовых каналах',
    ),
    (
      bit: manageStage,
      title: 'Управление трибуной (Stage)',
      subtitle: 'Назначение спикеров и управление эфиром на трибуне',
    ),
    (
      bit: kickMembers,
      title: 'Исключение участников (Kick)',
      subtitle: 'Удаление участников из сообщества',
    ),
    (
      bit: banMembers,
      title: 'Блокировка участников (Ban)',
      subtitle: 'Перманентная блокировка участников в сообществе',
    ),
  ];
}

class CommunityCategory {
  final String id;
  final String communityId;
  final String name;
  final int position;
  final bool isPrivate;

  const CommunityCategory({
    required this.id,
    required this.communityId,
    required this.name,
    this.position = 0,
    this.isPrivate = false,
  });

  CommunityCategory copyWith({
    String? id,
    String? communityId,
    String? name,
    int? position,
    bool? isPrivate,
  }) {
    return CommunityCategory(
      id: id ?? this.id,
      communityId: communityId ?? this.communityId,
      name: name ?? this.name,
      position: position ?? this.position,
      isPrivate: isPrivate ?? this.isPrivate,
    );
  }

  factory CommunityCategory.fromJson(Map<String, dynamic> json) {
    return CommunityCategory(
      id: (json['id'] ?? '').toString(),
      communityId: (json['community_id'] ?? '').toString(),
      name: (json['name'] ?? 'Категория').toString(),
      position: _parseCommunityInt(json['position']),
      isPrivate: json['is_private'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'community_id': communityId,
        'name': name,
        'position': position,
        'is_private': isPrivate,
      };
}

class CommunityChannel {
  final String id; // Underlying chatId
  final String communityId;
  final String? categoryId;
  final String name;
  final String topic;
  final String channelType; // 'text' | 'voice' | 'stage' | 'announcement' | 'forum' | 'whiteboard'
  final int position;
  final int slowModeSeconds;
  final int voiceBitrateKbps;
  final int voiceUserLimit;
  final int unreadCount;
  final List<CallParticipant> activeVoiceParticipants;

  const CommunityChannel({
    required this.id,
    required this.communityId,
    this.categoryId,
    required this.name,
    this.topic = '',
    this.channelType = 'text',
    this.position = 0,
    this.slowModeSeconds = 0,
    this.voiceBitrateKbps = 64,
    this.voiceUserLimit = 0,
    this.unreadCount = 0,
    this.activeVoiceParticipants = const [],
  });

  bool get isVoice => channelType == 'voice';
  bool get isStage => channelType == 'stage';
  bool get isAudioRoom => isVoice || isStage;
  bool get isAnnouncement => channelType == 'announcement';
  bool get isWhiteboard => channelType == 'whiteboard';
  bool get isForum => channelType == 'forum';

  CommunityChannel copyWith({
    String? id,
    String? communityId,
    String? categoryId,
    bool clearCategory = false,
    String? name,
    String? topic,
    String? channelType,
    int? position,
    int? slowModeSeconds,
    int? voiceBitrateKbps,
    int? voiceUserLimit,
    int? unreadCount,
    List<CallParticipant>? activeVoiceParticipants,
  }) {
    return CommunityChannel(
      id: id ?? this.id,
      communityId: communityId ?? this.communityId,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      name: name ?? this.name,
      topic: topic ?? this.topic,
      channelType: channelType ?? this.channelType,
      position: position ?? this.position,
      slowModeSeconds: slowModeSeconds ?? this.slowModeSeconds,
      voiceBitrateKbps: voiceBitrateKbps ?? this.voiceBitrateKbps,
      voiceUserLimit: voiceUserLimit ?? this.voiceUserLimit,
      unreadCount: unreadCount ?? this.unreadCount,
      activeVoiceParticipants:
          activeVoiceParticipants ?? this.activeVoiceParticipants,
    );
  }

  factory CommunityChannel.fromJson(Map<String, dynamic> json) {
    final rawCat = json['category_id']?.toString().trim();
    final rawParticipants = json['active_participants'] ??
        json['voice_participants'] ??
        (json['active_call'] is Map
            ? (json['active_call'] as Map)['participants']
            : null);
    final voiceList = <CallParticipant>[];
    if (rawParticipants is List) {
      for (final p in rawParticipants) {
        if (p is Map) {
          voiceList.add(CallParticipant.fromJson(Map<String, dynamic>.from(p)));
        }
      }
    }

    return CommunityChannel(
      id: (json['id'] ?? json['chat_id'] ?? '').toString(),
      communityId: (json['community_id'] ?? '').toString(),
      categoryId: (rawCat != null && rawCat.isNotEmpty) ? rawCat : null,
      name: (json['name'] ?? json['title'] ?? 'general').toString(),
      topic: (json['topic'] ?? json['description'] ?? '').toString(),
      channelType: (json['channel_type'] ??
              json['channel_kind'] ??
              json['type'] ??
              'text')
          .toString(),
      position: _parseCommunityInt(json['position']),
      slowModeSeconds: _parseCommunityInt(json['slow_mode_seconds']),
      voiceBitrateKbps: _parseCommunityInt(json['voice_bitrate_kbps'], 64),
      voiceUserLimit: _parseCommunityInt(json['voice_user_limit']),
      unreadCount: _parseCommunityInt(json['unread_count']),
      activeVoiceParticipants: voiceList,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'community_id': communityId,
        if (categoryId != null) 'category_id': categoryId,
        'name': name,
        'topic': topic,
        'description': topic,
        'channel_type': channelType,
        'channel_kind': channelType,
        'position': position,
        'slow_mode_seconds': slowModeSeconds,
        'voice_bitrate_kbps': voiceBitrateKbps,
        'voice_user_limit': voiceUserLimit,
        'unread_count': unreadCount,
      };
}

class CommunityRole {
  final String id;
  final String communityId;
  final String name;
  final String colorHex;
  final int position;
  final int permissions;
  final bool isHoisted;
  final bool isMentionable;
  final bool isEveryone;

  const CommunityRole({
    required this.id,
    required this.communityId,
    required this.name,
    this.colorHex = '#5C6BC0',
    this.position = 0,
    this.permissions = 0,
    this.isHoisted = false,
    this.isMentionable = true,
    this.isEveryone = false,
  });

  Color? get parsedColor {
    final cleaned = colorHex.trim().replaceFirst('#', '').toLowerCase();
    if (cleaned.isEmpty || cleaned == '99aab5') return null;
    final hex = cleaned.length == 6 ? 'ff$cleaned' : cleaned;
    if (hex.length != 8) return null;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return null;
    return Color(value);
  }

  CommunityRole copyWith({
    String? name,
    String? colorHex,
    int? position,
    int? permissions,
    bool? isHoisted,
    bool? isMentionable,
    bool? isEveryone,
  }) {
    return CommunityRole(
      id: id,
      communityId: communityId,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      position: position ?? this.position,
      permissions: permissions ?? this.permissions,
      isHoisted: isHoisted ?? this.isHoisted,
      isMentionable: isMentionable ?? this.isMentionable,
      isEveryone: isEveryone ?? this.isEveryone,
    );
  }

  factory CommunityRole.fromJson(Map<String, dynamic> json) {
    final roleName = (json['name'] ?? 'Участник').toString();
    return CommunityRole(
      id: (json['id'] ?? '').toString(),
      communityId: (json['community_id'] ?? '').toString(),
      name: roleName,
      colorHex: (json['color'] ?? json['color_hex'] ?? '#5C6BC0').toString(),
      position: _parseCommunityInt(json['position']),
      permissions: _parseCommunityInt(json['permissions']),
      isHoisted: json['is_hoisted'] == true,
      isMentionable: json['is_mentionable'] != false,
      isEveryone: json['is_everyone'] == true || roleName == '@everyone',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'community_id': communityId,
        'name': name,
        'color': colorHex,
        'position': position,
        'permissions': permissions,
        'is_hoisted': isHoisted,
        'is_mentionable': isMentionable,
        'is_everyone': isEveryone,
      };
}

class CommunityMember {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool isOnline;
  final bool isBot;
  final bool isVerified;
  final List<String> roleIds;
  final PeerCustomization? peerCustomization;

  const CommunityMember({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.isOnline = false,
    this.isBot = false,
    this.isVerified = false,
    this.roleIds = const [],
    this.peerCustomization,
  });

  factory CommunityMember.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['role_ids'];
    final parsedRoles = <String>[];
    if (rawRoles is List) {
      for (final r in rawRoles) {
        if (r != null) parsedRoles.add(r.toString());
      }
    }
    final rawAvatar = json['avatar_url']?.toString().trim();
    final userId = (json['user_id'] ?? '').toString();
    final cust = PeerCustomization.fromJson(json);
    if (!cust.isEmpty && userId.isNotEmpty) {
      PeerCustomizationCache.instance.put(userId, cust);
    }
    return CommunityMember(
      userId: userId,
      username: (json['username'] ?? '').toString(),
      displayName: (json['display_name'] ?? json['username'] ?? 'User').toString(),
      avatarUrl: (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
      isOnline: json['is_online'] == true,
      isBot: json['is_bot'] == true,
      isVerified: json['is_verified'] == true,
      roleIds: parsedRoles,
      peerCustomization: cust.isEmpty ? null : cust,
    );
  }
}

class Community {
  final String id;
  final String name;
  final String description;
  final String? avatarUrl;
  final String? bannerUrl;
  final String ownerId;
  final int memberCount;
  final int onlineCount;
  final bool isMember;
  final bool isPublic;
  final int myPermissions;
  final List<CommunityCategory> categories;
  final List<CommunityChannel> channels;
  final List<CommunityRole> roles;
  final DateTime createdAt;

  const Community({
    required this.id,
    required this.name,
    this.description = '',
    this.avatarUrl,
    this.bannerUrl,
    this.ownerId = '',
    this.memberCount = 1,
    this.onlineCount = 1,
    this.isMember = true,
    this.isPublic = true,
    this.myPermissions = CommunityPermissions.defaultEveryone,
    this.categories = const [],
    this.channels = const [],
    this.roles = const [],
    required this.createdAt,
  });

  int get totalUnreadCount =>
      channels.fold<int>(0, (sum, ch) => sum + ch.unreadCount);

  int get activeVoiceCount => channels.fold<int>(
        0,
        (sum, ch) => sum + ch.activeVoiceParticipants.length,
      );

  bool get canManageCommunity =>
      isMember &&
      ((myPermissions & CommunityPermissions.administrator) != 0 ||
          (myPermissions & CommunityPermissions.manageCommunity) != 0 ||
          (myPermissions & CommunityPermissions.manageChannels) != 0 ||
          (myPermissions & CommunityPermissions.manageRoles) != 0);

  bool get canManageChannels =>
      isMember &&
      ((myPermissions & CommunityPermissions.administrator) != 0 ||
          (myPermissions & CommunityPermissions.manageCommunity) != 0 ||
          (myPermissions & CommunityPermissions.manageChannels) != 0);

  bool get canSendMessages =>
      isMember &&
      ((myPermissions & CommunityPermissions.administrator) != 0 ||
          (myPermissions & CommunityPermissions.sendMessages) != 0);

  Community copyWith({
    String? id,
    String? name,
    String? description,
    String? avatarUrl,
    String? bannerUrl,
    String? ownerId,
    int? memberCount,
    int? onlineCount,
    bool? isMember,
    bool? isPublic,
    int? myPermissions,
    List<CommunityCategory>? categories,
    List<CommunityChannel>? channels,
    List<CommunityRole>? roles,
    DateTime? createdAt,
  }) {
    return Community(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      ownerId: ownerId ?? this.ownerId,
      memberCount: memberCount ?? this.memberCount,
      onlineCount: onlineCount ?? this.onlineCount,
      isMember: isMember ?? this.isMember,
      isPublic: isPublic ?? this.isPublic,
      myPermissions: myPermissions ?? this.myPermissions,
      categories: categories ?? this.categories,
      channels: channels ?? this.channels,
      roles: roles ?? this.roles,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Community.fromJson(Map<String, dynamic> json) {
    final rawAvatar =
        (json['avatar_url'] ?? json['icon_url'])?.toString().trim();
    final rawBanner = json['banner_url']?.toString().trim();

    final cats = <CommunityCategory>[];
    if (json['categories'] is List) {
      for (final c in json['categories'] as List) {
        if (c is Map) {
          cats.add(CommunityCategory.fromJson(Map<String, dynamic>.from(c)));
        }
      }
    }

    final chans = <CommunityChannel>[];
    if (json['channels'] is List) {
      for (final ch in json['channels'] as List) {
        if (ch is Map) {
          chans.add(CommunityChannel.fromJson(Map<String, dynamic>.from(ch)));
        }
      }
    }

    final rList = <CommunityRole>[];
    if (json['roles'] is List) {
      for (final r in json['roles'] as List) {
        if (r is Map) {
          rList.add(CommunityRole.fromJson(Map<String, dynamic>.from(r)));
        }
      }
    }

    return Community(
      id: (json['id'] ?? json['community_id'] ?? '').toString(),
      name: (json['name'] ?? 'Сообщество').toString(),
      description: (json['description'] ?? '').toString(),
      avatarUrl:
          (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
      bannerUrl:
          (rawBanner != null && rawBanner.isNotEmpty) ? rawBanner : null,
      ownerId: (json['owner_id'] ?? '').toString(),
      memberCount: _parseCommunityInt(json['member_count'], 1),
      onlineCount: _parseCommunityInt(json['online_count'], 1),
      isMember: json['is_member'] is bool ? (json['is_member'] as bool) : true,
      isPublic: json['is_public'] is bool ? (json['is_public'] as bool) : true,
      myPermissions: _parseCommunityInt(
        json['my_permissions'],
        CommunityPermissions.defaultEveryone,
      ),
      categories: cats,
      channels: chans,
      roles: rList,
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (avatarUrl != null) 'icon_url': avatarUrl,
        if (bannerUrl != null) 'banner_url': bannerUrl,
        'owner_id': ownerId,
        'member_count': memberCount,
        'online_count': onlineCount,
        'is_member': isMember,
        'is_public': isPublic,
        'my_permissions': myPermissions,
        'categories': categories.map((c) => c.toJson()).toList(),
        'channels': channels.map((c) => c.toJson()).toList(),
        'roles': roles.map((r) => r.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
      };
}

enum PermissionOverwriteState { deny, inherit, allow }

class CommunityPermissionOverwrite {
  final String targetType; // 'role' | 'member'
  final String targetId;
  final int allowBits;
  final int denyBits;

  const CommunityPermissionOverwrite({
    required this.targetType,
    required this.targetId,
    this.allowBits = 0,
    this.denyBits = 0,
  });

  bool get isEmpty => allowBits == 0 && denyBits == 0;

  PermissionOverwriteState stateForBit(int bit) {
    if ((allowBits & bit) != 0) return PermissionOverwriteState.allow;
    if ((denyBits & bit) != 0) return PermissionOverwriteState.deny;
    return PermissionOverwriteState.inherit;
  }

  CommunityPermissionOverwrite withBitState(
    int bit,
    PermissionOverwriteState state,
  ) {
    var nextAllow = allowBits & ~bit;
    var nextDeny = denyBits & ~bit;
    if (state == PermissionOverwriteState.allow) {
      nextAllow |= bit;
    } else if (state == PermissionOverwriteState.deny) {
      nextDeny |= bit;
    }
    return CommunityPermissionOverwrite(
      targetType: targetType,
      targetId: targetId,
      allowBits: nextAllow,
      denyBits: nextDeny,
    );
  }

  factory CommunityPermissionOverwrite.fromJson(Map<String, dynamic> json) {
    return CommunityPermissionOverwrite(
      targetType: (json['target_type'] ?? 'role').toString(),
      targetId: (json['target_id'] ?? '').toString(),
      allowBits: _parseCommunityInt(json['allow_bits']),
      denyBits: _parseCommunityInt(json['deny_bits']),
    );
  }

  Map<String, dynamic> toJson() => {
        'target_type': targetType,
        'target_id': int.tryParse(targetId) ?? 0,
        'allow_bits': allowBits,
        'deny_bits': denyBits,
      };
}

class CommunityBan {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String reason;
  final String? bannedBy;
  final DateTime createdAt;

  const CommunityBan({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.reason = '',
    this.bannedBy,
    required this.createdAt,
  });

  factory CommunityBan.fromJson(Map<String, dynamic> json) {
    final rawAvatar = json['avatar_url']?.toString().trim();
    return CommunityBan(
      userId: (json['user_id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      displayName:
          (json['display_name'] ?? json['username'] ?? 'Пользователь').toString(),
      avatarUrl: (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
      reason: (json['reason'] ?? '').toString(),
      bannedBy: json['banned_by']?.toString(),
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}

class CommunityInvite {
  final String id;
  final String communityId;
  final String? creatorId;
  final String code;
  final int maxUses;
  final int uses;
  final DateTime? expiresAt;
  final DateTime createdAt;

  const CommunityInvite({
    required this.id,
    required this.communityId,
    this.creatorId,
    required this.code,
    this.maxUses = 0,
    this.uses = 0,
    this.expiresAt,
    required this.createdAt,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  factory CommunityInvite.fromJson(Map<String, dynamic> json) {
    return CommunityInvite(
      id: (json['id'] ?? '').toString(),
      communityId: (json['community_id'] ?? '').toString(),
      creatorId: json['creator_id']?.toString(),
      code: (json['code'] ?? json['invite_code'] ?? '').toString(),
      maxUses: _parseCommunityInt(json['max_uses']),
      uses: _parseCommunityInt(json['uses']),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}

class CommunityMemberSection {
  final String id;
  final String title;
  final Color? color;
  final List<CommunityMember> members;

  const CommunityMemberSection({
    required this.id,
    required this.title,
    this.color,
    required this.members,
  });
}

CommunityRole? highestColoredRoleForMember(
  CommunityMember member,
  List<CommunityRole> roles,
) {
  final matched = roles
      .where(
        (r) =>
            !r.isEveryone &&
            member.roleIds.contains(r.id) &&
            r.parsedColor != null,
      )
      .toList()
    ..sort((a, b) => b.position.compareTo(a.position));
  return matched.isNotEmpty ? matched.first : null;
}

CommunityRole? highestHoistedRoleForMember(
  CommunityMember member,
  List<CommunityRole> roles,
) {
  final matched = roles
      .where(
        (r) => !r.isEveryone && r.isHoisted && member.roleIds.contains(r.id),
      )
      .toList()
    ..sort((a, b) => b.position.compareTo(a.position));
  return matched.isNotEmpty ? matched.first : null;
}

List<CommunityMemberSection> groupMembersByHoistedRoles(
  List<CommunityMember> members,
  List<CommunityRole> roles,
) {
  final hoistedRoles = roles
      .where((r) => !r.isEveryone && r.isHoisted)
      .toList()
    ..sort((a, b) => b.position.compareTo(a.position));

  final Map<String, List<CommunityMember>> roleBuckets = {
    for (final r in hoistedRoles) r.id: <CommunityMember>[],
  };
  final List<CommunityMember> onlineGeneral = [];
  final List<CommunityMember> offline = [];

  final sorted = List<CommunityMember>.from(members)
    ..sort((a, b) {
      final aName = a.displayName.isNotEmpty ? a.displayName : a.username;
      final bName = b.displayName.isNotEmpty ? b.displayName : b.username;
      return aName.toLowerCase().compareTo(bName.toLowerCase());
    });

  for (final member in sorted) {
    if (!member.isOnline) {
      offline.add(member);
      continue;
    }
    final topHoisted = highestHoistedRoleForMember(member, hoistedRoles);
    if (topHoisted != null && roleBuckets.containsKey(topHoisted.id)) {
      roleBuckets[topHoisted.id]!.add(member);
    } else {
      onlineGeneral.add(member);
    }
  }

  final sections = <CommunityMemberSection>[];
  for (final role in hoistedRoles) {
    final bucket = roleBuckets[role.id];
    if (bucket != null && bucket.isNotEmpty) {
      sections.add(
        CommunityMemberSection(
          id: 'role_${role.id}',
          title: role.name,
          color: role.parsedColor,
          members: bucket,
        ),
      );
    }
  }
  if (onlineGeneral.isNotEmpty) {
    sections.add(
      CommunityMemberSection(
        id: 'online',
        title: 'В сети',
        members: onlineGeneral,
      ),
    );
  }
  if (offline.isNotEmpty) {
    sections.add(
      CommunityMemberSection(
        id: 'offline',
        title: 'Не в сети',
        members: offline,
      ),
    );
  }
  return sections;
}
