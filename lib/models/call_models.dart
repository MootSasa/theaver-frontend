/// Models for 1-on-1 calls, group voice/video calls, Stage channels,
/// and High-FPS screen sharing / streaming (up to 1440p @ 144 FPS / 4K @ 60 FPS).

enum StreamQualityPreset {
  p720_30,
  p1080_60,
  p1080_120,
  p1440_60,
  p1440_144,
  p4k_60,
  custom,
}

enum ViewerSubscriptionQuality {
  auto,
  high,
  medium,
  low,
  audioOnly;

  String get apiValue {
    switch (this) {
      case ViewerSubscriptionQuality.auto:
        return 'auto';
      case ViewerSubscriptionQuality.high:
        return 'high';
      case ViewerSubscriptionQuality.medium:
        return 'medium';
      case ViewerSubscriptionQuality.low:
        return 'low';
      case ViewerSubscriptionQuality.audioOnly:
        return 'audio_only';
    }
  }

  String get label {
    switch (this) {
      case ViewerSubscriptionQuality.auto:
        return 'Auto (Simulcast)';
      case ViewerSubscriptionQuality.high:
        return 'Source (Original FPS)';
      case ViewerSubscriptionQuality.medium:
        return 'Medium (720p 60fps)';
      case ViewerSubscriptionQuality.low:
        return 'Data Saver (480p 30fps)';
      case ViewerSubscriptionQuality.audioOnly:
        return 'Audio Only';
    }
  }

  static ViewerSubscriptionQuality fromString(String? raw) {
    switch (raw) {
      case 'high':
        return ViewerSubscriptionQuality.high;
      case 'medium':
        return ViewerSubscriptionQuality.medium;
      case 'low':
        return ViewerSubscriptionQuality.low;
      case 'audio_only':
        return ViewerSubscriptionQuality.audioOnly;
      default:
        return ViewerSubscriptionQuality.auto;
    }
  }
}

class StreamConfig {
  final int width;
  final int height;
  final int fps; // 30, 60, 120, 144
  final int bitrateKbps; // 1500 .. 25000
  final String codec; // 'VP9' | 'AV1' | 'H264'
  final String contentHint; // 'motion' | 'detail'
  final bool includeAudio;
  final bool enableServerRecording;
  final String sourceType; // 'screen' | 'window' | 'camera'
  final String? sourceId;
  final String? sourceName;

  const StreamConfig({
    this.width = 1920,
    this.height = 1080,
    this.fps = 60,
    this.bitrateKbps = 6000,
    this.codec = 'VP9',
    this.contentHint = 'motion',
    this.includeAudio = true,
    this.enableServerRecording = false,
    this.sourceType = 'screen',
    this.sourceId,
    this.sourceName,
  });

  String get resolutionLabel {
    if (height >= 2160) return '4K';
    if (height >= 1440) return '1440p';
    if (height >= 1080) return '1080p';
    return '720p';
  }

  String get badgeLabel => '$resolutionLabel ${fps}fps';

  StreamConfig copyWith({
    int? width,
    int? height,
    int? fps,
    int? bitrateKbps,
    String? codec,
    String? contentHint,
    bool? includeAudio,
    bool? enableServerRecording,
    String? sourceType,
    String? sourceId,
    String? sourceName,
  }) {
    return StreamConfig(
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      codec: codec ?? this.codec,
      contentHint: contentHint ?? this.contentHint,
      includeAudio: includeAudio ?? this.includeAudio,
      enableServerRecording:
          enableServerRecording ?? this.enableServerRecording,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
    );
  }

  Map<String, dynamic> toJson() => {
        'stream_type': sourceType == 'window' ? 'application' : sourceType,
        'source_type': sourceType,
        'width': width,
        'height': height,
        'resolution_width': width,
        'resolution_height': height,
        'fps': fps,
        'target_fps': fps,
        'max_bitrate_kbps': bitrateKbps,
        'bitrate_kbps': bitrateKbps,
        'codec': codec.toLowerCase(),
        'video_codec': codec.toLowerCase(),
        'degradation_preference':
            contentHint == 'motion' ? 'maintain-framerate' : 'maintain-resolution',
        'content_hint': contentHint,
        'has_system_audio': includeAudio,
      };
}

class CallParticipant {
  final String userId;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final String role; // 'host' | 'speaker' | 'listener' | 'member'
  final String state; // 'ringing' | 'connected' | 'left'
  final bool isMuted;
  final bool isDeafened;
  final bool isVideoOn;
  final bool isScreenSharing;
  final bool isHandRaised;
  final bool isSpeaking;
  final bool serverMuted;
  final bool serverDeafened;
  final int volume; // 0..200

  const CallParticipant({
    required this.userId,
    required this.displayName,
    this.username = '',
    this.avatarUrl,
    this.role = 'speaker',
    this.state = 'connected',
    this.isMuted = false,
    this.isDeafened = false,
    this.isVideoOn = false,
    this.isScreenSharing = false,
    this.isHandRaised = false,
    this.isSpeaking = false,
    this.serverMuted = false,
    this.serverDeafened = false,
    this.volume = 100,
  });

  CallParticipant copyWith({
    String? userId,
    String? displayName,
    String? username,
    String? avatarUrl,
    String? role,
    String? state,
    bool? isMuted,
    bool? isDeafened,
    bool? isVideoOn,
    bool? isScreenSharing,
    bool? isHandRaised,
    bool? isSpeaking,
    bool? serverMuted,
    bool? serverDeafened,
    int? volume,
  }) {
    return CallParticipant(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      state: state ?? this.state,
      isMuted: isMuted ?? this.isMuted,
      isDeafened: isDeafened ?? this.isDeafened,
      isVideoOn: isVideoOn ?? this.isVideoOn,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      isHandRaised: isHandRaised ?? this.isHandRaised,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      serverMuted: serverMuted ?? this.serverMuted,
      serverDeafened: serverDeafened ?? this.serverDeafened,
      volume: volume ?? this.volume,
    );
  }

  factory CallParticipant.fromJson(Map<String, dynamic> json) {
    final rawAvatar = json['avatar_url']?.toString().trim();
    final rawStageRole = (json['stage_role'] ?? json['role'] ?? 'speaker').toString();
    final handRaised = rawStageRole == 'hand_raised' ||
        json['is_hand_raised'] == true ||
        json['hand_raised'] == true;
    final normalizedRole =
        rawStageRole == 'hand_raised' ? 'listener' : rawStageRole;
    return CallParticipant(
      userId: (json['user_id'] ?? json['id'] ?? '').toString(),
      displayName: (json['display_name'] ??
              json['name'] ??
              json['username'] ??
              'Participant')
          .toString(),
      username: (json['username'] ?? '').toString(),
      avatarUrl: (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
      role: normalizedRole,
      state: (json['state'] ?? 'connected').toString(),
      isMuted: json['self_mute'] == true ||
          json['is_muted'] == true ||
          json['muted'] == true,
      isDeafened: json['self_deaf'] == true ||
          json['is_deafened'] == true ||
          json['deafened'] == true,
      isVideoOn: json['is_video_on'] == true || json['video_enabled'] == true,
      isScreenSharing:
          json['is_screen_sharing'] == true || json['screen_sharing'] == true,
      isHandRaised: handRaised,
      isSpeaking: json['is_speaking'] == true,
      serverMuted:
          json['server_mute'] == true || json['server_muted'] == true,
      serverDeafened:
          json['server_deaf'] == true || json['server_muted'] == true,
      volume: (json['volume'] as num?)?.toInt() ?? 100,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'display_name': displayName,
        'username': username,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'role': role,
        'stage_role': isHandRaised ? 'hand_raised' : role,
        'state': state,
        'is_muted': isMuted,
        'self_mute': isMuted,
        'is_deafened': isDeafened,
        'self_deaf': isDeafened,
        'is_video_on': isVideoOn,
        'is_screen_sharing': isScreenSharing,
        'is_hand_raised': isHandRaised,
        'is_speaking': isSpeaking,
        'server_mute': serverMuted,
        'server_deaf': serverDeafened,
        'volume': volume,
      };
}

class CallStream {
  final String id;
  final String callId;
  final String streamerId;
  final String streamerName;
  final String sourceType; // 'screen' | 'window' | 'camera' | 'rtmp'
  final int resolutionWidth;
  final int resolutionHeight;
  final int fps;
  final int bitrateKbps;
  final String codec; // 'VP9' | 'AV1' | 'H264'
  final String contentHint; // 'motion' | 'detail'
  final bool hasSystemAudio;
  final String? thumbnailUrl;
  final int viewerCount;

  const CallStream({
    required this.id,
    required this.callId,
    required this.streamerId,
    this.streamerName = 'Streamer',
    this.sourceType = 'screen',
    this.resolutionWidth = 1920,
    this.resolutionHeight = 1080,
    this.fps = 60,
    this.bitrateKbps = 6000,
    this.codec = 'VP9',
    this.contentHint = 'motion',
    this.hasSystemAudio = true,
    this.thumbnailUrl,
    this.viewerCount = 0,
  });

  String get resolutionLabel {
    if (resolutionHeight >= 2160) return '4K';
    if (resolutionHeight >= 1440) return '1440p';
    if (resolutionHeight >= 1080) return '1080p';
    return '720p';
  }

  String get qualityBadge => '$resolutionLabel ${fps}fps';

  CallStream copyWith({
    String? id,
    String? callId,
    String? streamerId,
    String? streamerName,
    String? sourceType,
    int? resolutionWidth,
    int? resolutionHeight,
    int? fps,
    int? bitrateKbps,
    String? codec,
    String? contentHint,
    bool? hasSystemAudio,
    String? thumbnailUrl,
    int? viewerCount,
  }) {
    return CallStream(
      id: id ?? this.id,
      callId: callId ?? this.callId,
      streamerId: streamerId ?? this.streamerId,
      streamerName: streamerName ?? this.streamerName,
      sourceType: sourceType ?? this.sourceType,
      resolutionWidth: resolutionWidth ?? this.resolutionWidth,
      resolutionHeight: resolutionHeight ?? this.resolutionHeight,
      fps: fps ?? this.fps,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      codec: codec ?? this.codec,
      contentHint: contentHint ?? this.contentHint,
      hasSystemAudio: hasSystemAudio ?? this.hasSystemAudio,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      viewerCount: viewerCount ?? this.viewerCount,
    );
  }

  factory CallStream.fromJson(Map<String, dynamic> json) {
    final rawThumb = json['thumbnail_url']?.toString().trim();
    final enc = json['encoding_config'] is Map<String, dynamic>
        ? json['encoding_config'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final degPref = (json['degradation_preference'] ??
            enc['degradation_preference'] ??
            json['content_hint'] ??
            'motion')
        .toString();
    return CallStream(
      id: (json['id'] ?? json['stream_id'] ?? '').toString(),
      callId: (json['call_id'] ?? '').toString(),
      streamerId: (json['streamer_id'] ?? json['user_id'] ?? '').toString(),
      streamerName:
          (json['streamer_name'] ?? json['display_name'] ?? 'Streamer')
              .toString(),
      sourceType:
          (json['stream_type'] ?? json['source_type'] ?? 'screen').toString(),
      resolutionWidth: (json['width'] as num?)?.toInt() ??
          (enc['width'] as num?)?.toInt() ??
          (json['resolution_width'] as num?)?.toInt() ??
          1920,
      resolutionHeight: (json['height'] as num?)?.toInt() ??
          (enc['height'] as num?)?.toInt() ??
          (json['resolution_height'] as num?)?.toInt() ??
          1080,
      fps: (json['target_fps'] as num?)?.toInt() ??
          (enc['target_fps'] as num?)?.toInt() ??
          (json['fps'] as num?)?.toInt() ??
          60,
      bitrateKbps: (json['max_bitrate_kbps'] as num?)?.toInt() ??
          (enc['max_bitrate_kbps'] as num?)?.toInt() ??
          (json['bitrate_kbps'] as num?)?.toInt() ??
          6000,
      codec: (json['video_codec'] ?? enc['video_codec'] ?? json['codec'] ?? 'VP9')
          .toString()
          .toUpperCase(),
      contentHint: degPref.contains('resolution') ? 'detail' : 'motion',
      hasSystemAudio: json['has_system_audio'] != false,
      thumbnailUrl:
          (rawThumb != null && rawThumb.isNotEmpty) ? rawThumb : null,
      viewerCount: (json['viewer_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'call_id': callId,
        'streamer_id': streamerId,
        'streamer_name': streamerName,
        'source_type': sourceType,
        'resolution_width': resolutionWidth,
        'resolution_height': resolutionHeight,
        'fps': fps,
        'bitrate_kbps': bitrateKbps,
        'codec': codec,
        'content_hint': contentHint,
        'has_system_audio': hasSystemAudio,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
        'viewer_count': viewerCount,
      };
}

class CallSession {
  final String id;
  final String chatId;
  final String? communityId;
  final String initiatorId;
  final String callType; // 'voice' | 'video' | 'group' | 'stage'
  final String status; // 'ringing' | 'active' | 'ended'
  final bool isVideo;
  final String title;
  final int maxParticipants;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<CallParticipant> participants;
  final List<CallStream> streams;
  final String? activeRecordingId;
  final List<Map<String, dynamic>>? iceServers;
  final String? livekitUrl;
  final String? livekitToken;
  final String? roomName;

  const CallSession({
    required this.id,
    required this.chatId,
    this.communityId,
    this.initiatorId = '',
    this.callType = 'voice',
    this.status = 'active',
    this.isVideo = false,
    this.title = '',
    this.maxParticipants = 2,
    required this.startedAt,
    this.endedAt,
    this.participants = const [],
    this.streams = const [],
    this.activeRecordingId,
    this.iceServers,
    this.livekitUrl,
    this.livekitToken,
    this.roomName,
  });

  bool get isActiveOnOtherDevice => status == 'active_on_other_device';

  bool get isGroupOrCommunity =>
      callType == 'group' ||
      callType == 'stage' ||
      (communityId != null &&
          communityId!.isNotEmpty &&
          communityId != '0' &&
          communityId != 'null') ||
      maxParticipants > 2;

  CallSession copyWith({
    String? id,
    String? chatId,
    String? communityId,
    String? initiatorId,
    String? callType,
    String? status,
    bool? isVideo,
    String? title,
    int? maxParticipants,
    DateTime? startedAt,
    DateTime? endedAt,
    List<CallParticipant>? participants,
    List<CallStream>? streams,
    String? activeRecordingId,
    List<Map<String, dynamic>>? iceServers,
    String? livekitUrl,
    String? livekitToken,
    String? roomName,
  }) {
    return CallSession(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      communityId: communityId ?? this.communityId,
      initiatorId: initiatorId ?? this.initiatorId,
      callType: callType ?? this.callType,
      status: status ?? this.status,
      isVideo: isVideo ?? this.isVideo,
      title: title ?? this.title,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      participants: participants ?? this.participants,
      streams: streams ?? this.streams,
      activeRecordingId: activeRecordingId ?? this.activeRecordingId,
      iceServers: iceServers ?? this.iceServers,
      livekitUrl: livekitUrl ?? this.livekitUrl,
      livekitToken: livekitToken ?? this.livekitToken,
      roomName: roomName ?? this.roomName,
    );
  }

  factory CallSession.fromJson(Map<String, dynamic> json) {
    final rawParticipants = json['participants'];
    final participantsList = <CallParticipant>[];
    if (rawParticipants is List) {
      for (final p in rawParticipants) {
        if (p is Map) {
          participantsList
              .add(CallParticipant.fromJson(Map<String, dynamic>.from(p)));
        }
      }
    }

    final rawStreams = json['streams'];
    final streamsList = <CallStream>[];
    if (rawStreams is List) {
      for (final s in rawStreams) {
        if (s is Map) {
          streamsList.add(CallStream.fromJson(Map<String, dynamic>.from(s)));
        }
      }
    }

    final commIdRaw = json['community_id']?.toString();
    final commId =
        (commIdRaw != null && commIdRaw.isNotEmpty && commIdRaw != '0' && commIdRaw != 'null')
            ? commIdRaw
            : null;
    final maxParts = (json['max_participants'] as num?)?.toInt() ??
        (commId != null ? 50 : 2);

    var cType = (json['call_type'] ?? json['type'] ?? 'voice').toString();
    final isVid = json['is_video'] == true ||
        json['video_enabled'] == true ||
        cType == 'video';
    if (cType == 'voice' && (commId != null || maxParts > 2)) {
      cType = 'group';
    }

    List<Map<String, dynamic>>? parsedIceServers;
    if (json['ice_servers'] is List) {
      parsedIceServers = (json['ice_servers'] as List)
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }

    return CallSession(
      id: (json['id'] ?? json['call_id'] ?? '').toString(),
      chatId: (json['chat_id'] ?? '').toString(),
      communityId: commId,
      initiatorId: (json['initiator_id'] ?? json['creator_id'] ?? '').toString(),
      callType: cType,
      status: (json['status'] ?? 'active').toString(),
      isVideo: isVid,
      title: (json['title'] ?? json['chat_name'] ?? '').toString(),
      maxParticipants: maxParts,
      startedAt: json['started_at'] != null
          ? (DateTime.tryParse(json['started_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      endedAt: json['ended_at'] != null
          ? DateTime.tryParse(json['ended_at'].toString())
          : null,
      participants: participantsList,
      streams: streamsList,
      activeRecordingId: json['active_recording_id']?.toString() ??
          (json['is_recorded'] == true ? 'active' : null),
      iceServers: parsedIceServers,
      livekitUrl: json['livekit_url']?.toString(),
      livekitToken: json['livekit_token']?.toString(),
      roomName: json['room_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'call_id': id,
        'chat_id': chatId,
        if (communityId != null) 'community_id': communityId,
        'initiator_id': initiatorId,
        'call_type': callType,
        'status': status,
        'is_video': isVideo,
        'video_enabled': isVideo,
        'title': title,
        'max_participants': maxParticipants,
        'started_at': startedAt.toIso8601String(),
        if (endedAt != null) 'ended_at': endedAt!.toIso8601String(),
        'participants': participants.map((p) => p.toJson()).toList(),
        'streams': streams.map((s) => s.toJson()).toList(),
        if (activeRecordingId != null)
          'active_recording_id': activeRecordingId,
      };
}

class SoundboardItem {
  final String id;
  final String communityId;
  final String name;
  final String emoji;
  final String audioUrl;
  final double volume;
  final int durationMs;

  const SoundboardItem({
    required this.id,
    this.communityId = '',
    required this.name,
    this.emoji = '🔊',
    this.audioUrl = '',
    this.volume = 1.0,
    this.durationMs = 1500,
  });

  factory SoundboardItem.fromJson(Map<String, dynamic> json) {
    return SoundboardItem(
      id: (json['id'] ?? json['sound_id'] ?? '').toString(),
      communityId: (json['community_id'] ?? '').toString(),
      name: (json['name'] ?? 'Sound').toString(),
      emoji: (json['emoji'] ?? '🔊').toString(),
      audioUrl: (json['file_url'] ?? json['audio_url'] ?? '').toString(),
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 1500,
    );
  }
}
