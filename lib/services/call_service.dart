import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/call_models.dart';
import 'auth_service.dart';

/// REST client for Theaver Calls, Group Voice/Stage Rooms, and High-FPS Streams.
class CallService {
  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Starts or joins a call in [chatId] (`POST /api/calls/start`).
  static Future<CallSession?> startCall({
    required String chatId,
    String callType = 'voice', // 'voice' | 'video' | 'group' | 'stage'
    bool isVideo = false,
    String? title,
    bool forceTransfer = false,
  }) async {
    try {
      final numericChatId =
          int.tryParse(chatId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (numericChatId <= 0) return null;

      final apiCallType = callType == 'group'
          ? (isVideo ? 'video' : 'voice')
          : callType;

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/calls/start'),
        headers: await _headers(),
        body: jsonEncode({
          'chat_id': numericChatId,
          'call_type': apiCallType,
          'video_enabled': isVideo,
          'is_video': isVideo,
          'force_transfer': forceTransfer,
          if (title != null && title.isNotEmpty) 'title': title,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          if (data['active_on_other_device'] == true) {
            return CallSession(
              id: (data['call_id'] ?? '').toString(),
              chatId: (data['chat_id'] as num?)?.toString() ?? chatId,
              initiatorId: '',
              callType: 'conflict',
              status: 'active_on_other_device',
              isVideo: isVideo,
              title: data['existing_device_id']?.toString() ?? '',
              startedAt: DateTime.now(),
              participants: const [],
            );
          }
          final callMap = data['call'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(data['call'] as Map)
              : Map<String, dynamic>.from(data);
          if (data['ice_servers'] != null) callMap['ice_servers'] = data['ice_servers'];
          if (data['livekit_url'] != null) callMap['livekit_url'] = data['livekit_url'];
          if (data['livekit_token'] != null) callMap['livekit_token'] = data['livekit_token'];
          if (data['room_name'] != null) callMap['room_name'] = data['room_name'];
          final parsed = CallSession.fromJson(callMap);
          return callType == 'group'
              ? parsed.copyWith(callType: 'group')
              : parsed;
        }
      }
    } catch (e) {
      debugPrint('[CallService] startCall error: $e');
    }
    return null;
  }

  /// Fetches the active call in [chatId] (`GET /api/chats/:id/call`).
  static Future<CallSession?> getActiveCallForChat(String chatId) async {
    try {
      final numericChatId =
          int.tryParse(chatId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (numericChatId <= 0) return null;
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$numericChatId/call'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final callMap = data['active_call'] ?? data['call'];
          if (callMap is Map<String, dynamic>) {
            return CallSession.fromJson(callMap);
          }
          if (data['id'] != null) {
            return CallSession.fromJson(data);
          }
        }
      }
    } catch (e) {
      debugPrint('[CallService] getActiveCallForChat error: $e');
    }
    return null;
  }

  /// Fetches details of a call (`GET /api/calls/:callId`).
  static Future<CallSession?> getCall(String callId) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/calls/$callId'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final callMap = data['call'] is Map<String, dynamic>
              ? data['call'] as Map<String, dynamic>
              : data;
          return CallSession.fromJson(callMap);
        }
      }
    } catch (e) {
      debugPrint('[CallService] getCall error: $e');
    }
    return null;
  }

  /// Accepts an incoming call (`POST /api/calls/:callId/accept`).
  static Future<CallSession?> acceptCall(
    String callId, {
    bool isVideo = false,
    bool forceTransfer = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/calls/$callId/accept'),
        headers: await _headers(),
        body: jsonEncode({
          'video_enabled': isVideo,
          'force_transfer': forceTransfer,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          if (data['active_on_other_device'] == true) {
            return CallSession(
              id: callId,
              chatId: (data['chat_id'] as num?)?.toString() ?? '',
              initiatorId: '',
              callType: 'conflict',
              status: 'active_on_other_device',
              isVideo: isVideo,
              title: data['existing_device_id']?.toString() ?? '',
              startedAt: DateTime.now(),
              participants: const [],
            );
          }
          final callMap = data['call'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(data['call'] as Map)
              : Map<String, dynamic>.from(data);
          if (data['ice_servers'] != null) callMap['ice_servers'] = data['ice_servers'];
          if (data['livekit_url'] != null) callMap['livekit_url'] = data['livekit_url'];
          if (data['livekit_token'] != null) callMap['livekit_token'] = data['livekit_token'];
          if (data['room_name'] != null) callMap['room_name'] = data['room_name'];
          return CallSession.fromJson(callMap);
        }
      }
    } catch (e) {
      debugPrint('[CallService] acceptCall error: $e');
    }
    return null;
  }

  /// Transfers an active call from another device to this device (`POST /api/calls/:callId/transfer`).
  static Future<CallSession?> transferCall(String callId) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/calls/$callId/transfer'),
        headers: await _headers(),
        body: jsonEncode({}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final callMap = data['call'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(data['call'] as Map)
              : Map<String, dynamic>.from(data);
          if (data['ice_servers'] != null) callMap['ice_servers'] = data['ice_servers'];
          if (data['livekit_url'] != null) callMap['livekit_url'] = data['livekit_url'];
          if (data['livekit_token'] != null) callMap['livekit_token'] = data['livekit_token'];
          if (data['room_name'] != null) callMap['room_name'] = data['room_name'];
          return CallSession.fromJson(callMap);
        }
      }
    } catch (e) {
      debugPrint('[CallService] transferCall error: $e');
    }
    return null;
  }

  /// Fetches dynamic TURN / STUN ICE servers from backend (`GET /api/calls/ice-servers`).
  static Future<List<Map<String, dynamic>>?> getIceServers() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/calls/ice-servers'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['ice_servers'] is List) {
          return (data['ice_servers'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[CallService] getIceServers error: $e');
    }
    return null;
  }

  /// Declines an incoming call (`POST /api/calls/:callId/decline`).
  static Future<bool> declineCall(String callId) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/calls/$callId/decline'),
        headers: await _headers(),
        body: jsonEncode({'reason': 'declined'}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CallService] declineCall error: $e');
      return false;
    }
  }

  /// Leaves or ends a call (`POST /api/calls/:callId/leave`).
  static Future<bool> leaveCall(String callId) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/calls/$callId/leave'),
        headers: await _headers(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CallService] leaveCall error: $e');
      return false;
    }
  }

  /// Updates local participant state (`POST /api/calls/:callId/state`).
  static Future<bool> updateState(
    String callId, {
    bool? isMuted,
    bool? isDeafened,
    bool? isVideoOn,
    bool? isScreenSharing,
    bool? isHandRaised,
    bool? isSpeaking,
    String? stageRole,
  }) async {
    try {
      final effectiveStageRole = stageRole ??
          (isHandRaised != null
              ? (isHandRaised ? 'hand_raised' : 'listener')
              : null);
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/calls/$callId/state'),
        headers: await _headers(),
        body: jsonEncode({
          if (isMuted != null) 'self_mute': isMuted,
          if (isMuted != null) 'is_muted': isMuted,
          if (isDeafened != null) 'self_deaf': isDeafened,
          if (isDeafened != null) 'is_deafened': isDeafened,
          if (isVideoOn != null) 'is_video_on': isVideoOn,
          if (isScreenSharing != null) 'is_screen_sharing': isScreenSharing,
          if (effectiveStageRole != null) 'stage_role': effectiveStageRole,
          if (isHandRaised != null) 'is_hand_raised': isHandRaised,
          if (isSpeaking != null) 'is_speaking': isSpeaking,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CallService] updateState error: $e');
      return false;
    }
  }

  /// Moderates a participant (`POST /api/calls/:callId/participants/:userId/moderate`).
  static Future<bool> moderateParticipant(
    String callId,
    String targetUserId, {
    required String action, // 'mute' | 'unmute' | 'deafen' | 'undeafen' | 'kick' | 'promote_speaker' | 'demote_listener'
  }) async {
    try {
      final payload = <String, dynamic>{'action': action};
      switch (action) {
        case 'mute':
          payload['server_mute'] = true;
          break;
        case 'unmute':
          payload['server_mute'] = false;
          break;
        case 'deafen':
          payload['server_deaf'] = true;
          break;
        case 'undeafen':
          payload['server_deaf'] = false;
          break;
        case 'kick':
          payload['kick'] = true;
          break;
        case 'promote_speaker':
          payload['stage_role'] = 'speaker';
          break;
        case 'demote_listener':
          payload['stage_role'] = 'listener';
          break;
      }

      final response = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/api/calls/$callId/participants/$targetUserId/moderate',
        ),
        headers: await _headers(),
        body: jsonEncode(payload),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CallService] moderateParticipant error: $e');
      return false;
    }
  }

  /// Starts a screen share / stream (`POST /api/calls/:callId/streams/start`).
  static Future<CallStream?> startStream(
    String callId,
    StreamConfig config,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/calls/$callId/streams/start'),
        headers: await _headers(),
        body: jsonEncode(config.toJson()),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final streamMap = data['stream'] is Map<String, dynamic>
              ? data['stream'] as Map<String, dynamic>
              : data;
          return CallStream.fromJson(streamMap);
        }
      }
    } catch (e) {
      debugPrint('[CallService] startStream error: $e');
    }
    return null;
  }

  /// Updates an active stream's quality (`PATCH /api/calls/:callId/streams/:streamId/quality`).
  static Future<CallStream?> updateStreamQuality(
    String callId,
    String streamId,
    StreamConfig config,
  ) async {
    try {
      final response = await http.patch(
        Uri.parse(
          '${AppConfig.baseUrl}/api/calls/$callId/streams/$streamId/quality',
        ),
        headers: await _headers(),
        body: jsonEncode(config.toJson()),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          if (data['stream'] is Map<String, dynamic>) {
            return CallStream.fromJson(data['stream'] as Map<String, dynamic>);
          }
          if (data['encoding_config'] is Map<String, dynamic>) {
            final enc = data['encoding_config'] as Map<String, dynamic>;
            return CallStream(
              id: streamId,
              callId: callId,
              streamerId: (data['streamer_id'] ?? '').toString(),
              sourceType: config.sourceType,
              resolutionWidth: (enc['width'] as num?)?.toInt() ?? config.width,
              resolutionHeight:
                  (enc['height'] as num?)?.toInt() ?? config.height,
              fps: (enc['target_fps'] as num?)?.toInt() ?? config.fps,
              bitrateKbps: (enc['max_bitrate_kbps'] as num?)?.toInt() ??
                  config.bitrateKbps,
              codec: (enc['video_codec'] ?? config.codec)
                  .toString()
                  .toUpperCase(),
              contentHint: config.contentHint,
              hasSystemAudio: config.includeAudio,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[CallService] updateStreamQuality error: $e');
    }
    return null;
  }

  /// Stops an active stream (`POST /api/calls/:callId/streams/:streamId/stop`).
  static Future<bool> stopStream(String callId, String streamId) async {
    try {
      final response = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/api/calls/$callId/streams/$streamId/stop',
        ),
        headers: await _headers(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CallService] stopStream error: $e');
      return false;
    }
  }

  /// Subscribes or changes viewer simulcast layer (`POST /api/calls/:callId/streams/:streamId/subscription`).
  static Future<bool> setStreamSubscription(
    String callId,
    String streamId,
    ViewerSubscriptionQuality quality, {
    int? maxFps,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/api/calls/$callId/streams/$streamId/subscription',
        ),
        headers: await _headers(),
        body: jsonEncode({
          'quality_mode': quality.apiValue,
          'quality': quality.apiValue,
          if (maxFps != null) 'max_fps': maxFps,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CallService] setStreamSubscription error: $e');
      return false;
    }
  }

  /// Starts server-side call recording (`POST /api/calls/:callId/recordings/start`).
  static Future<String?> startRecording(
    String callId, {
    StreamConfig? config,
  }) async {
    try {
      final body = config != null
          ? jsonEncode({
              'video_codec': config.codec.toLowerCase(),
              'max_height': config.height,
              'max_fps': config.fps,
              'video_bitrate_kbps': config.bitrateKbps,
            })
          : null;
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/calls/$callId/recordings/start'),
        headers: await _headers(),
        body: body,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return (data['recording_id'] ?? data['id'])?.toString();
        }
      }
    } catch (e) {
      debugPrint('[CallService] startRecording error: $e');
    }
    return null;
  }

  /// Stops server-side call recording (`POST /api/calls/:callId/recordings/stop`).
  static Future<bool> stopRecording(String callId) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/calls/$callId/recordings/stop'),
        headers: await _headers(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CallService] stopRecording error: $e');
      return false;
    }
  }

  /// Plays a soundboard clip in the call (`POST /api/calls/:callId/soundboard/:soundId/play`).
  static Future<bool> playSoundboard(String callId, String soundId) async {
    try {
      final response = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/api/calls/$callId/soundboard/$soundId/play',
        ),
        headers: await _headers(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CallService] playSoundboard error: $e');
      return false;
    }
  }

  /// Sends a floating reaction in the call (`POST /api/calls/:callId/reaction`).
  static Future<bool> sendReaction(String callId, String emoji) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/calls/$callId/reaction'),
        headers: await _headers(),
        body: jsonEncode({'emoji': emoji}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CallService] sendReaction error: $e');
      return false;
    }
  }

  /// Relays a WebRTC signaling message (`offer`, `answer`, `ice_candidate`, `renegotiate`)
  /// to call participants via `POST /api/calls/:callId/signal` with automatic fallback
  /// to `POST /api/calls/:callId/reaction` (`__webrtc_signal__:<base64>`) if `/signal` is not yet deployed.
  static Future<bool> sendSignal(
    String callId,
    Map<String, dynamic> signalPayload,
  ) async {
    if (callId.isEmpty || callId.startsWith('local_')) return false;
    try {
      final headers = await _headers();
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/calls/$callId/signal'),
        headers: headers,
        body: jsonEncode(signalPayload),
      );
      if (response.statusCode == 200) {
        return true;
      }
      if (response.statusCode == 404 || response.statusCode == 405) {
        final encoded = base64Encode(utf8.encode(jsonEncode(signalPayload)));
        final fallback = await http.post(
          Uri.parse('${AppConfig.baseUrl}/api/calls/$callId/reaction'),
          headers: headers,
          body: jsonEncode({'emoji': '__webrtc_signal__:$encoded'}),
        );
        return fallback.statusCode == 200;
      }
    } catch (e) {
      debugPrint('[CallService] sendSignal error: $e');
    }
    return false;
  }

  /// Fetches recent call history (`GET /api/calls/history`).
  static Future<List<CallSession>> getCallHistory({int limit = 30}) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/calls/history?limit=$limit'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['calls'] is List) {
          return (data['calls'] as List)
              .whereType<Map<String, dynamic>>()
              .map(CallSession.fromJson)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[CallService] getCallHistory error: $e');
    }
    return const [];
  }
}
