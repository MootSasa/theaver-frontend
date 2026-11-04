import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:window_manager/window_manager.dart';
import '../models/call_models.dart';
import '../screens/call/group_call_screen.dart';
import '../screens/call/video_call_screen.dart';
import '../screens/call/voice_call_screen.dart';
import 'account_manager.dart';
import 'auth_service.dart';
import 'call_service.dart';
import 'deep_link_service.dart';
import 'notification_service.dart';
import 'websocket_service.dart';

class FloatingCallReaction {
  final String id;
  final String userId;
  final String emoji;
  final DateTime createdAt;

  FloatingCallReaction({
    required this.id,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });
}

/// Global ChangeNotifier managing active 1-on-1, Group, or Community Voice/Stage calls,
/// real multi-peer WebRTC (`RTCPeerConnection`) audio/video/screen-share tracks,
/// High-FPS screen sharing (up to 144 FPS), Top Banner (active + incoming), and Draggable PiP.
class CallStateProvider extends ChangeNotifier {
  Map<String, dynamic> _rtcConfiguration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.cloudflare.com:3478',
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
        ],
      },
    ],
    'sdpSemantics': 'unified-plan',
    'ContinualGatheringPolicy': 'gather_continually',
  };

  void updateIceServers(List<Map<String, dynamic>>? servers) {
    if (servers == null || servers.isEmpty) return;
    _rtcConfiguration = {
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
      'ContinualGatheringPolicy': 'gather_continually',
    };
  }

  // Multi-device active call banner state (for banner in ChatsScreen)
  String? _otherDeviceActiveCallId;
  String? get otherDeviceActiveCallId => _otherDeviceActiveCallId;
  String? _otherDeviceActiveChatTitle;
  String? get otherDeviceActiveChatTitle => _otherDeviceActiveChatTitle;
  String? _otherDeviceActiveChatId;
  String? get otherDeviceActiveChatId => _otherDeviceActiveChatId;

  // High-Fidelity Audio Mode
  bool _highFidelityAudio = true;
  bool get highFidelityAudio => _highFidelityAudio;
  void toggleHighFidelityAudio() {
    _highFidelityAudio = !_highFidelityAudio;
    notifyListeners();
  }

  // Soundboard audio player
  AudioPlayer? _soundboardPlayer;
  Future<void> _playSoundboardClip(String soundUrl) async {
    try {
      _soundboardPlayer ??= AudioPlayer();
      await _soundboardPlayer!.setUrl(soundUrl);
      await _soundboardPlayer!.play();
    } catch (e) {
      debugPrint('[CallStateProvider] soundboard play error: $e');
    }
  }

  /// Transfers the active call on other device to this device via global banner.
  Future<bool> transferActiveCallFromBanner() async {
    final callId = _otherDeviceActiveCallId;
    if (callId == null || callId.isEmpty) return false;
    final chatTitle = _otherDeviceActiveChatTitle;
    final success = await transferCallToThisDevice(callId, chatTitle: chatTitle);
    if (success) {
      _otherDeviceActiveCallId = null;
      _otherDeviceActiveChatId = null;
      _otherDeviceActiveChatTitle = null;
      notifyListeners();
    }
    return success;
  }

  CallSession? _activeCall;
  CallSession? _incomingCall;
  String? _currentUserId;
  StreamSubscription<WebSocketEvent>? _wsSubscription;

  bool _isMinimized = false;
  bool _isMuted = false;
  bool _isDeafened = false;
  bool _isSpeakerOn = true;
  bool _isVideoOn = false;
  bool _isScreenSharing = false;
  bool _previewOwnScreenShare = false;
  bool _isHandRaised = false;
  bool _isRecording = false;

  Duration _elapsed = Duration.zero;
  Timer? _timer;
  Timer? _ringingTimeoutTimer;

  StreamConfig _streamConfig = const StreamConfig();
  CallStream? _activeLocalStreamInfo;
  CallStream? _focusedStream;
  ViewerSubscriptionQuality _viewerQuality = ViewerSubscriptionQuality.auto;

  MediaStream? _localUserStream;
  MediaStream? _localCameraStream;
  MediaStream? _localDisplayStream;
  bool _isTogglingVideo = false;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer screenShareRenderer = RTCVideoRenderer();
  bool _renderersInitialized = false;
  Future<void>? _rendererInitFuture;

  /// Active WebRTC peer connections keyed by remote userId.
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, Future<RTCPeerConnection>> _peerConnectionFutures = {};
  final Map<String, Future<void>> _peerSignalingQueues = {};
  final Map<String, Timer> _iceRestartTimers = {};
  final Map<String, DateTime> _recentSignalSignatures = {};
  final Map<String, RTCVideoRenderer> _participantRenderers = {};
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  final Set<String> _makingOfferForPeer = {};
  final Map<String, DateTime> _lastOfferSentAt = {};
  final Map<String, MediaStream> _remotePrimaryStreams = {};
  final Map<String, MediaStream> _remoteDisplayStreams = {};
  final Map<String, int> _participantRotations = {};
  final Map<String, RTCVideoRenderer> _streamRenderers = {};

  bool _isFrontCamera = true;
  bool get isFrontCamera => _isFrontCamera;

  String? _conflictCallId;
  String? get conflictCallId => _conflictCallId;
  void clearConflictCall() {
    _conflictCallId = null;
    notifyListeners();
  }

  Future<RTCVideoRenderer> ensureStreamRenderer(String streamerId) async {
    final existing = _streamRenderers[streamerId];
    if (existing != null) {
      if (existing.srcObject == null) {
        if (streamerId == _currentUserId || streamerId == 'local') {
          existing.srcObject = _localDisplayStream;
        } else {
          existing.srcObject = _remoteDisplayStreams[streamerId] ??
              (_remotePrimaryStreams[streamerId]?.getVideoTracks().isNotEmpty == true
                  ? _remotePrimaryStreams[streamerId]
                  : null);
        }
      }
      return existing;
    }
    final r = RTCVideoRenderer();
    await r.initialize();
    _streamRenderers[streamerId] = r;
    if (streamerId == _currentUserId || streamerId == 'local') {
      r.srcObject = _localDisplayStream;
    } else {
      r.srcObject = _remoteDisplayStreams[streamerId] ??
          (_remotePrimaryStreams[streamerId]?.getVideoTracks().isNotEmpty == true
              ? _remotePrimaryStreams[streamerId]
              : null);
    }
    return r;
  }

  RTCVideoRenderer? rendererForStream(String streamerId) {
    if (streamerId == _currentUserId || streamerId == 'local') {
      if (!_previewOwnScreenShare) return null;
    }
    final r = _streamRenderers[streamerId];
    if (r != null && r.srcObject == null) {
      final s = _remoteDisplayStreams[streamerId] ??
          (_remotePrimaryStreams[streamerId]?.getVideoTracks().isNotEmpty == true
              ? _remotePrimaryStreams[streamerId]
              : null);
      if (s != null) {
        r.srcObject = s;
      }
    }
    return r;
  }

  final List<FloatingCallReaction> _reactions = [];

  CallStateProvider() {
    _initProvider();
  }

  Future<void> _initProvider() async {
    unawaited(ensureRenderersInitialized());
    _currentUserId = await AuthService.getUserId();
    NotificationService().registerCallActionHandler(_handleNotificationCallAction);
    _wsSubscription = WebSocketService().eventStream.listen((event) {
      if (event.type == WebSocketEventType.emojiInteraction &&
          event.data['action']?.toString() == '__webrtc_call__') {
        final senderId = event.data['user_id']?.toString() ?? '';
        if (senderId.isNotEmpty && senderId == _currentUserId) return;
        final rawEmoji = event.data['emoji']?.toString() ?? '';
        if (rawEmoji.isEmpty) return;
        try {
          final decodedJson = utf8.decode(base64Decode(rawEmoji));
          final envelope = jsonDecode(decodedJson);
          if (envelope is Map<String, dynamic>) {
            final evType = (envelope['event'] ?? '').toString();
            final payload = envelope['payload'] is Map
                ? Map<String, dynamic>.from(envelope['payload'] as Map)
                : <String, dynamic>{};
            if (senderId.isNotEmpty) {
              payload.putIfAbsent('from_user_id', () => senderId);
              payload.putIfAbsent('user_id', () => senderId);
            }
            if (evType.isNotEmpty) {
              handleWsEvent(evType, payload);
            }
          }
        } catch (e) {
          debugPrint('[CallStateProvider] relay decode error: $e');
        }
        return;
      }

      final rawType = event.rawType.isNotEmpty
          ? event.rawType
          : (event.data['__raw_type'] ?? event.data['type'] ?? '').toString();
      if (rawType.startsWith('call.') || rawType.startsWith('call_')) {
        handleWsEvent(rawType, event.data);
      }
    });
  }

  Future<void> _handleNotificationCallAction(
    String action,
    Map<String, dynamic> data,
  ) async {
    final callId = (data['call_id'] ?? '').toString();
    final chatId = (data['chat_id'] ?? '').toString();
    final callerId = (data['caller_id'] ?? '').toString();
    final callerName = (data['caller_name'] ?? data['chat_title'] ?? 'Звонок').toString();
    final callerAvatar = data['caller_avatar']?.toString();
    final isVideo =
        data['is_video'] == true || data['is_video'] == 'true' || data['call_type'] == 'video';
    final isGroup =
        data['is_group'] == true || data['is_group'] == 'true' || data['chat_type'] == 'group';

    if (action == 'callback_missed_call') {
      if (chatId.isNotEmpty) {
        final session = await startOrJoinCall(
          chatId: chatId,
          chatTitle: callerName,
          callType: isGroup ? 'group' : (isVideo ? 'video' : 'voice'),
          isVideo: isVideo,
        );
        if (session != null) {
          _openCallScreenForSession(session);
        }
      }
      return;
    }

    if (_incomingCall == null && _activeCall == null && (callId.isNotEmpty || chatId.isNotEmpty)) {
      _incomingCall = CallSession(
        id: callId.isNotEmpty ? callId : 'local_${DateTime.now().millisecondsSinceEpoch}',
        chatId: chatId,
        initiatorId: callerId,
        callType: isGroup ? 'group' : (isVideo ? 'video' : 'voice'),
        status: 'ringing',
        isVideo: isVideo,
        title: callerName,
        startedAt: DateTime.now(),
        participants: [
          if (callerId.isNotEmpty)
            CallParticipant(
              userId: callerId,
              displayName: callerName,
              username: callerName,
              avatarUrl: callerAvatar,
              role: 'host',
              state: 'connected',
              isVideoOn: isVideo,
            ),
        ],
      );
      notifyListeners();
    }

    if (action == 'decline_call') {
      if (_incomingCall != null) {
        await declineIncomingCall();
      } else if (callId.isNotEmpty && !callId.startsWith('local_')) {
        await CallService.declineCall(callId);
      }
      return;
    }

    if (action == 'accept_call') {
      final session = await acceptIncomingCall(isVideo: isVideo);
      if (session != null) {
        _openCallScreenForSession(session);
      }
      return;
    }

    // 'open_call' or 'incoming_push': ensure incoming banner is visible
    notifyListeners();
  }

  void _openCallScreenForSession(CallSession call) {
    final nav = DeepLinkService().navigatorKey.currentState;
    if (nav == null) return;
    _isMinimized = false;
    notifyListeners();
    if (call.callType == 'group' || call.callType == 'stage') {
      nav.push(
        MaterialPageRoute(
          builder: (_) => GroupCallScreen(
            callId: call.id,
            chatId: call.chatId,
            userId: _currentUserId ?? 'local',
            title: call.title,
            isStage: call.callType == 'stage',
          ),
        ),
      );
    } else if (call.isVideo || _isVideoOn) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => VideoCallScreen(
            callId: call.id,
            chatId: call.chatId,
            isCaller: false,
            peerName: call.title,
          ),
        ),
      );
    } else {
      nav.push(
        MaterialPageRoute(
          builder: (_) => VoiceCallScreen(
            callId: call.id,
            chatId: call.chatId,
            isCaller: false,
            peerName: call.title,
          ),
        ),
      );
    }
  }

  void _broadcastWebRtcCallRelay(
    String chatId,
    String eventType,
    Map<String, dynamic> payload,
  ) {
    if (chatId.isEmpty) return;
    try {
      final envelope = <String, dynamic>{
        'event': eventType,
        'chat_id': chatId,
        'sender_id': _currentUserId ?? 'local',
        'payload': payload,
      };
      final encoded = base64Encode(utf8.encode(jsonEncode(envelope)));
      WebSocketService().sendEmojiInteraction(
        chatId,
        messageId: eventType,
        emoji: encoded,
        action: '__webrtc_call__',
      );
    } catch (e) {
      debugPrint('[CallStateProvider] _broadcastWebRtcCallRelay error: $e');
    }
  }

  Future<void> _sendCallSignal(
    CallSession call,
    Map<String, dynamic> signalPayload,
  ) async {
    if (!call.id.startsWith('local_')) {
      final sent = await CallService.sendSignal(call.id, signalPayload);
      if (sent) return;
    }
    _broadcastWebRtcCallRelay(call.chatId, 'call_signal', {
      'call_id': call.id,
      'chat_id': call.chatId,
      ...signalPayload,
    });
  }

  void _startRingingTimeout() {
    _ringingTimeoutTimer?.cancel();
    _ringingTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (_activeCall?.status == 'ringing') {
        leaveCall();
      }
    });
  }

  CallSession? get activeCall => _activeCall;
  CallSession? get incomingCall => _incomingCall;
  String? get currentUserId => _currentUserId;
  bool get hasActiveCall => _activeCall != null;
  bool get hasIncomingCall => _incomingCall != null && _activeCall == null;
  bool get isMinimized => _isMinimized;
  bool get isMuted => _isMuted;
  bool get isDeafened => _isDeafened;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isVideoOn => _isVideoOn;
  bool get isTogglingVideo => _isTogglingVideo;
  bool get isScreenSharing => _isScreenSharing;
  bool get previewOwnScreenShare => _previewOwnScreenShare;

  /// True when the active/focused screen share belongs to the current user.
  bool get isSelfScreenShare {
    if (!_isScreenSharing) return false;
    final s = focusedStream;
    if (s == null) return true;
    return s.streamerId == _currentUserId || s.streamerId == 'local';
  }

  void setPreviewOwnScreenShare(bool value) {
    if (_previewOwnScreenShare == value) return;
    _previewOwnScreenShare = value;
    if (isSelfScreenShare && _renderersInitialized) {
      screenShareRenderer.srcObject = value ? _localDisplayStream : null;
    }
    notifyListeners();
  }

  bool get isHandRaised => _isHandRaised;
  bool get isRecording => _isRecording;
  Duration get elapsed => _elapsed;
  StreamConfig get streamConfig => _streamConfig;
  CallStream? get activeLocalStreamInfo => _activeLocalStreamInfo;
  CallStream? get focusedStream =>
      _focusedStream ??
      (_activeCall != null && _activeCall!.streams.isNotEmpty
          ? _activeCall!.streams.first
          : _activeLocalStreamInfo);
  ViewerSubscriptionQuality get viewerQuality => _viewerQuality;
  List<FloatingCallReaction> get reactions => List.unmodifiable(_reactions);

  bool get renderersInitialized => _renderersInitialized;
  bool get hasLocalVideoStream =>
      _renderersInitialized &&
      _isVideoOn &&
      localRenderer.srcObject != null &&
      localRenderer.srcObject!.getVideoTracks().isNotEmpty;
  bool get hasRemoteVideoStream =>
      _renderersInitialized &&
      remoteRenderer.srcObject != null &&
      remoteRenderer.srcObject!.getVideoTracks().isNotEmpty;
  int getParticipantRotation(String userId) =>
      _participantRotations[userId] ?? 0;

  void rotateParticipant(String userId) {
    final current = getParticipantRotation(userId);
    _participantRotations[userId] = (current + 90) % 360;
    notifyListeners();
  }

  void setParticipantRotation(String userId, int degrees) {
    _participantRotations[userId] = degrees % 360;
    notifyListeners();
  }

  bool get hasScreenShareStream {
    if (!_renderersInitialized) return false;
    if (isSelfScreenShare) {
      if (_previewOwnScreenShare &&
          screenShareRenderer.srcObject != null &&
          screenShareRenderer.srcObject!.getVideoTracks().isNotEmpty) {
        return true;
      }
    }
    final stream = focusedStream;
    if (stream != null) {
      final target = _remoteDisplayStreams[stream.streamerId] ??
          (_remotePrimaryStreams[stream.streamerId]?.getVideoTracks().isNotEmpty == true
              ? _remotePrimaryStreams[stream.streamerId]
              : _participantRenderers[stream.streamerId]?.srcObject);
      if (target != null && target.getVideoTracks().isNotEmpty) {
        screenShareRenderer.srcObject = target;
        return true;
      }
    }
    if (_remoteDisplayStreams.values.any((s) => s.getVideoTracks().isNotEmpty)) {
      final firstWithVideo = _remoteDisplayStreams.values.firstWhere(
        (s) => s.getVideoTracks().isNotEmpty,
      );
      screenShareRenderer.srcObject = firstWithVideo;
      return true;
    }
    if (screenShareRenderer.srcObject != null &&
        screenShareRenderer.srcObject!.getVideoTracks().isNotEmpty) {
      return true;
    }
    return false;
  }

  bool get shouldShowPip =>
      _activeCall != null &&
      _isMinimized &&
      (_isVideoOn ||
          _isScreenSharing ||
          _activeCall!.isVideo ||
          _activeCall!.streams.isNotEmpty ||
          hasRemoteVideoStream ||
          hasScreenShareStream);

  String get formattedDuration {
    if (_activeCall?.status == 'ringing') {
      return 'Вызов...';
    }
    final hours = _elapsed.inHours;
    final minutes = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  /// Returns the [RTCVideoRenderer] for a given participant [userId] (or [localRenderer] for self).
  RTCVideoRenderer? rendererForParticipant(String userId) {
    if (userId.isEmpty || !_renderersInitialized) return null;
    if (userId == _currentUserId || userId == 'local') {
      return hasLocalVideoStream ? localRenderer : null;
    }
    final r = _participantRenderers[userId];
    if (r != null) {
      try {
        final src = r.srcObject;
        if (src != null && src.getVideoTracks().isNotEmpty) return r;
      } catch (_) {}
    }
    return null;
  }

  static final AndroidAudioConfiguration _mediaAudioConfig =
      AndroidAudioConfiguration(
        manageAudioFocus: true,
        androidAudioMode: AndroidAudioMode.normal,
        androidAudioFocusMode: AndroidAudioFocusMode.gainTransientMayDuck,
        androidAudioStreamType: AndroidAudioStreamType.music,
        androidAudioAttributesUsageType: AndroidAudioAttributesUsageType.media,
        androidAudioAttributesContentType:
            AndroidAudioAttributesContentType.movie,
      );

  Future<void> _configureCallAudioSession() async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      try {
        await Helper.setAndroidAudioConfiguration(_mediaAudioConfig);
      } catch (_) {}
      try {
        if (_isSpeakerOn) {
          await Helper.setSpeakerphoneOnButPreferBluetooth();
        } else {
          await Helper.setSpeakerphoneOn(false);
        }
      } catch (_) {}
    } else if (Platform.isIOS) {
      try {
        await Helper.setSpeakerphoneOn(_isSpeakerOn);
      } catch (_) {}
    }
  }

  Future<void> ensureRenderersInitialized() async {
    if (_renderersInitialized) return;
    if (_rendererInitFuture != null) {
      await _rendererInitFuture;
      return;
    }
    final completer = Completer<void>();
    _rendererInitFuture = completer.future;
    try {
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await WebRTC.initialize(
            options: {
              'androidAudioConfiguration': _mediaAudioConfig.toMap(),
            },
          );
          await Helper.setAndroidAudioConfiguration(_mediaAudioConfig);
        } catch (_) {}
      }
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      await screenShareRenderer.initialize();
      _renderersInitialized = true;
    } catch (e) {
      debugPrint('[CallStateProvider] renderer init error: $e');
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
      _rendererInitFuture = null;
    }
  }

  Future<RTCVideoRenderer> _ensureParticipantRenderer(String userId) async {
    final existing = _participantRenderers[userId];
    if (existing != null) return existing;
    final renderer = RTCVideoRenderer();
    try {
      await renderer.initialize();
      _participantRenderers[userId] = renderer;
    } catch (e) {
      debugPrint('[CallStateProvider] participant renderer init error: $e');
    }
    return renderer;
  }

  /// Requests OS permissions for microphone, camera (if video), bluetooth, and notifications
  /// BEFORE calling flutter_webrtc's getUserMedia so Android never triggers the deprecated
  /// RequestPermissionsFragment crash.
  Future<void> _ensureCallPermissions({required bool video}) async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final permissionsToRequest = <Permission>[
        Permission.microphone,
        if (video) Permission.camera,
        if (Platform.isAndroid) Permission.bluetoothConnect,
        if (Platform.isAndroid) Permission.notification,
      ];
      await permissionsToRequest.request();
    } catch (e) {
      debugPrint('[CallStateProvider] permission request warning: $e');
    }
  }

  /// Starts or joins a call in [chatId].
  Future<CallSession?> startOrJoinCall({
    required String chatId,
    required String chatTitle,
    String callType = 'voice',
    String? communityId,
    bool isVideo = false,
  }) async {
    await ensureRenderersInitialized();
    _currentUserId = await AuthService.getUserId() ?? _currentUserId ?? 'local';

    // If we already have an active call in the same chat/callId, do not restart it.
    if (_activeCall != null &&
        (_activeCall!.chatId == chatId || _activeCall!.id == chatId)) {
      _isMinimized = false;
      if (isVideo && !_isVideoOn) {
        await toggleVideo();
      }
      notifyListeners();
      return _activeCall;
    }

    // If there is an incoming call matching this chat or callId, accept it.
    if (_incomingCall != null &&
        (_incomingCall!.chatId == chatId || _incomingCall!.id == chatId)) {
      return acceptIncomingCall(isVideo: isVideo);
    }

    _isMuted = false;
    _isDeafened = false;
    _isVideoOn = isVideo;
    _isScreenSharing = false;
    _isMinimized = false;

    await _ensureCallPermissions(video: isVideo);
    await _configureCallAudioSession();
    await NotificationService().startCallForegroundService(
      title: chatTitle.isNotEmpty ? chatTitle : 'Активный звонок',
      isVideo: isVideo,
      isScreenShare: false,
    );
    await _acquireUserMedia(audio: true, video: isVideo);

    CallSession? session;
    // Check if chatId is actually a UUID callId (e.g. joining an existing call directly)
    final isUuidCallId = chatId.contains('-') && int.tryParse(chatId) == null;
    if (isUuidCallId) {
      session = await CallService.acceptCall(chatId, isVideo: isVideo);
    } else {
      session = await CallService.startCall(
        chatId: chatId,
        callType: callType,
        isVideo: isVideo,
        title: chatTitle,
      );
    }

    if (session != null && session.isActiveOnOtherDevice) {
      _conflictCallId = session.id;
      notifyListeners();
      return null;
    }

    final currentUserId = _currentUserId ?? 'local';
    final currentUsername =
        AccountManager().currentAccount?.displayName ??
        AccountManager().currentAccount?.username ??
        'You';
    final currentAvatar = AccountManager().currentAccount?.avatarUrl;

    final isOneOnOne = callType == 'voice' || callType == 'video';
    final initialStatus = isOneOnOne ? 'ringing' : 'active';

    session ??= CallSession(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      chatId: chatId,
      initiatorId: currentUserId,
      callType: callType,
      status: initialStatus,
      isVideo: isVideo,
      title: chatTitle,
      startedAt: DateTime.now(),
      participants: [
        CallParticipant(
          userId: currentUserId,
          displayName: currentUsername,
          username: currentUsername,
          avatarUrl: currentAvatar,
          role: 'host',
          state: 'connected',
          isMuted: false,
          isVideoOn: isVideo,
        ),
      ],
    );

    if (session.participants.isEmpty) {
      session = session.copyWith(
        title: session.title.isNotEmpty ? session.title : chatTitle,
        participants: [
          CallParticipant(
            userId: currentUserId,
            displayName: currentUsername,
            username: currentUsername,
            avatarUrl: currentAvatar,
            role: 'host',
            state: 'connected',
            isMuted: false,
            isVideoOn: isVideo,
          ),
        ],
      );
    } else if (session.title.isEmpty) {
      session = session.copyWith(title: chatTitle);
    }

    // For 1-on-1 calls initiated by us, keep status as 'ringing' until a remote participant is connected
    if (isOneOnOne && !isUuidCallId) {
      final hasRemoteConnected = session.participants.any(
        (p) =>
            p.userId.isNotEmpty &&
            p.userId != currentUserId &&
            p.userId != 'local' &&
            p.state == 'connected',
      );
      if (!hasRemoteConnected && session.status != 'ringing') {
        session = session.copyWith(status: 'ringing');
      }
    }

    _activeCall = session;
    if (session.iceServers != null) {
      updateIceServers(session.iceServers);
    }
    if (session.status == 'ringing') {
      _timer?.cancel();
      _timer = null;
      _elapsed = Duration.zero;
      _startRingingTimeout();
    } else {
      _ringingTimeoutTimer?.cancel();
      _startTimer(session.startedAt);
    }

    if (session.streams.isNotEmpty) {
      _focusedStream = session.streams.first;
      for (final s in session.streams) {
        unawaited(ensureStreamRenderer(s.streamerId));
      }
    }
    notifyListeners();

    // Relay incoming call notification over WebSocket only in offline/local fallback mode
    // (for server-backed calls, POST /calls already broadcasts call.incoming + FCM push).
    if (session.id.startsWith('local_')) {
      _broadcastWebRtcCallRelay(session.chatId, 'call_incoming', {
        'call': session.copyWith(title: currentUsername).toJson(),
        'caller_id': currentUserId,
        'caller_name': currentUsername,
        'video_enabled': isVideo,
      });
    }

    final shouldInitiateOffers = isOneOnOne && !isUuidCallId;
    await _syncPeerConnections(initiateOffers: shouldInitiateOffers);

    // Fallback: if remote peers haven't sent an offer within 1200ms, initiate offer from our side
    Future.delayed(const Duration(milliseconds: 1200), () async {
      if (_activeCall?.id != session?.id) return;
      for (final entry in _peerConnections.entries) {
        final peerId = entry.key;
        final pc = entry.value;
        try {
          final remoteDesc = await pc.getRemoteDescription();
          if (remoteDesc == null &&
              pc.signalingState == RTCSignalingState.RTCSignalingStateStable) {
            await _createAndSendOffer(peerId, pc);
          }
        } catch (_) {}
      }
    });

    return session;
  }

  /// Transfers an ongoing call from another device to this device.
  Future<bool> transferCallToThisDevice(
    String callId, {
    String? chatTitle,
    bool isVideo = false,
  }) async {
    try {
      _conflictCallId = null;
      await ensureRenderersInitialized();
      await _ensureCallPermissions(video: isVideo);
      await _configureCallAudioSession();
      await NotificationService().startCallForegroundService(
        title: chatTitle != null && chatTitle.isNotEmpty ? chatTitle : 'Активный звонок',
        isVideo: isVideo,
        isScreenShare: false,
      );
      await _acquireUserMedia(audio: true, video: isVideo);

      final session = await CallService.acceptCall(
        callId,
        isVideo: isVideo,
        forceTransfer: true,
      );
      if (session != null && !session.isActiveOnOtherDevice) {
        _activeCall = session;
        if (session.iceServers != null) {
          updateIceServers(session.iceServers);
        }
        _ringingTimeoutTimer?.cancel();
        _startTimer(session.startedAt);
        if (session.streams.isNotEmpty) {
          _focusedStream = session.streams.first;
          for (final s in session.streams) {
            unawaited(ensureStreamRenderer(s.streamerId));
          }
        }
        await _syncPeerConnections(initiateOffers: false);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('[CallStateProvider] transferCallToThisDevice error: $e');
    }
    notifyListeners();
    return false;
  }

  /// Accepts the currently ringing [_incomingCall].
  Future<CallSession?> acceptIncomingCall({bool? isVideo}) async {
    final incoming = _incomingCall;
    if (incoming == null) return _activeCall;

    _ringingTimeoutTimer?.cancel();
    unawaited(
      NotificationService().cancelIncomingCallNotification(
        callId: incoming.id,
        chatId: incoming.chatId,
      ),
    );
    await ensureRenderersInitialized();
    _currentUserId = await AuthService.getUserId() ?? _currentUserId ?? 'local';

    final useVideo = isVideo ?? incoming.isVideo;
    _incomingCall = null;
    _isMuted = false;
    _isDeafened = false;
    _isVideoOn = useVideo;
    _isScreenSharing = false;
    _isMinimized = false;

    await _ensureCallPermissions(video: useVideo);
    await _configureCallAudioSession();
    await NotificationService().startCallForegroundService(
      title: incoming.title.isNotEmpty ? incoming.title : 'Активный звонок',
      isVideo: useVideo,
      isScreenShare: false,
    );
    await _acquireUserMedia(audio: true, video: useVideo);

    final currentUserId = _currentUserId ?? 'local';
    final currentUsername =
        AccountManager().currentAccount?.displayName ??
        AccountManager().currentAccount?.username ??
        'You';
    final currentAvatar = AccountManager().currentAccount?.avatarUrl;
    final myParticipant = CallParticipant(
      userId: currentUserId,
      displayName: currentUsername,
      username: currentUsername,
      avatarUrl: currentAvatar,
      role: 'speaker',
      state: 'connected',
      isMuted: false,
      isVideoOn: _isVideoOn,
    );

    final initialParticipants = <CallParticipant>[
      ...incoming.participants
          .where((p) => p.userId != currentUserId)
          .map((p) => p.state == 'ringing' ? p.copyWith(state: 'connected') : p),
      myParticipant,
    ];

    final now = DateTime.now();
    var session = incoming.copyWith(
      status: 'active',
      startedAt: now,
      participants: initialParticipants,
      title: incoming.title,
    );

    // Set _activeCall and initialize RTCPeerConnections with local audio/video tracks
    // BEFORE calling CallService.acceptCall so we are ready the instant caller's SDP offer arrives.
    _activeCall = session;
    _startTimer(now);
    notifyListeners();
    await _syncPeerConnections(initiateOffers: false);

    if (!incoming.id.startsWith('local_')) {
      final accepted = await CallService.acceptCall(
        incoming.id,
        isVideo: _isVideoOn,
      );
      if (accepted != null && _activeCall?.id == incoming.id) {
        final mergedParticipants = <CallParticipant>[
          ...accepted.participants
              .where((p) => p.userId != currentUserId)
              .map(
                (p) => p.state == 'ringing' ? p.copyWith(state: 'connected') : p,
              ),
          myParticipant,
        ];
        session = accepted.copyWith(
          status: 'active',
          startedAt: now,
          participants: mergedParticipants,
          title: accepted.title.isNotEmpty ? accepted.title : incoming.title,
        );
        _activeCall = session;
        if (session.streams.isNotEmpty) {
          _focusedStream = session.streams.first;
          for (final s in session.streams) {
            unawaited(ensureStreamRenderer(s.streamerId));
          }
        }
        notifyListeners();
        await _syncPeerConnections(initiateOffers: false);
      }
    } else {
      _broadcastWebRtcCallRelay(session.chatId, 'call_accepted', {
        'call_id': session.id,
        'chat_id': session.chatId,
        'user_id': currentUserId,
        'accepted_by': currentUserId,
        'participant': myParticipant.toJson(),
        'call': session.toJson(),
      });
    }

    // Fallback: if caller hasn't sent an offer within 850ms, initiate offer from our side
    Future.delayed(const Duration(milliseconds: 850), () async {
      if (_activeCall?.id != session.id) return;
      for (final entry in _peerConnections.entries) {
        final peerId = entry.key;
        final pc = entry.value;
        try {
          final remoteDesc = await pc.getRemoteDescription();
          if (remoteDesc == null &&
              pc.signalingState == RTCSignalingState.RTCSignalingStateStable) {
            await _createAndSendOffer(peerId, pc);
          }
        } catch (_) {}
      }
    });

    return session;
  }

  /// Declines the currently ringing [_incomingCall].
  Future<void> declineIncomingCall() async {
    final incoming = _incomingCall;
    if (incoming == null) return;
    _incomingCall = null;
    notifyListeners();
    unawaited(
      NotificationService().cancelIncomingCallNotification(
        callId: incoming.id,
        chatId: incoming.chatId,
      ),
    );
    _broadcastWebRtcCallRelay(incoming.chatId, 'call_ended', {
      'call_id': incoming.id,
      'chat_id': incoming.chatId,
      'reason': 'declined',
    });
    if (!incoming.id.startsWith('local_')) {
      await CallService.declineCall(incoming.id);
    }
  }

  Future<void> _acquireUserMedia({
    required bool audio,
    required bool video,
  }) async {
    await ensureRenderersInitialized();
    await _configureCallAudioSession();

    // 1. Acquire microphone audio stream if not already active
    if (audio &&
        (_localUserStream == null ||
            _localUserStream!.getAudioTracks().isEmpty)) {
      try {
        final audioConstraints = _highFidelityAudio
            ? <String, dynamic>{
                'echoCancellation': true,
                'noiseSuppression': true,
                'autoGainControl': true,
                'sampleRate': 48000,
                'channelCount': 2,
              }
            : <String, dynamic>{
                'echoCancellation': true,
                'noiseSuppression': true,
                'autoGainControl': true,
              };
        final audioStream = await navigator.mediaDevices.getUserMedia({
          'audio': audioConstraints,
          'video': false,
        });
        _localUserStream = audioStream;
        for (final t in audioStream.getAudioTracks()) {
          t.enabled = !_isMuted;
        }
      } catch (e) {
        debugPrint('[CallStateProvider] getUserMedia(audio) error: $e');
      }
    }

    // 2. Acquire camera video stream separately if requested
    if (video) {
      await _acquireCameraVideoStream();
    } else {
      _isVideoOn = false;
    }

    await _configureCallAudioSession();
    notifyListeners();
  }

  Future<bool> _acquireCameraVideoStream() async {
    await ensureRenderersInitialized();
    try {
      final existingVideoTracks =
          _localCameraStream?.getVideoTracks() ?? const [];
      if (existingVideoTracks.isNotEmpty) {
        for (final t in existingVideoTracks) {
          t.enabled = true;
        }
        if (_renderersInitialized) {
          localRenderer.srcObject = _localCameraStream;
        }
        _isVideoOn = true;
        return true;
      }

      final videoStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
        },
      });
      final tracks = videoStream.getVideoTracks();
      if (tracks.isEmpty) {
        _isVideoOn = false;
        return false;
      }
      for (final t in tracks) {
        t.enabled = true;
      }
      _localCameraStream = videoStream;
      if (_renderersInitialized) {
        localRenderer.srcObject = videoStream;
      }
      _isVideoOn = true;
      return true;
    } catch (e) {
      debugPrint('[CallStateProvider] _acquireCameraVideoStream error: $e');
      _isVideoOn = false;
      return false;
    }
  }

  // ===========================================================================
  // Multi-Peer WebRTC Connection & Signaling Management
  // ===========================================================================

  bool _isPolitePeer(String remotePeerId) {
    final myId = _currentUserId ?? '';
    final myInt = int.tryParse(myId);
    final peerInt = int.tryParse(remotePeerId);
    if (myInt != null && peerInt != null) {
      return myInt < peerInt;
    }
    return myId.compareTo(remotePeerId) < 0;
  }

  Future<void> _syncPeerConnections({
    bool initiateOffers = false,
    String? forceOfferToPeerId,
  }) async {
    final call = _activeCall;
    if (call == null) return;
    _currentUserId ??= await AuthService.getUserId();
    final myId = _currentUserId;
    if (myId == null || myId.isEmpty) return;

    final connectedRemotePeers = call.participants
        .where(
          (p) =>
              p.userId.isNotEmpty &&
              p.userId != myId &&
              p.userId != 'local' &&
              p.state == 'connected',
        )
        .map((p) => p.userId)
        .toSet();

    // Remove peer connections for participants who left
    final stalePeers = _peerConnections.keys
        .where((peerId) => !connectedRemotePeers.contains(peerId))
        .toList();
    for (final peerId in stalePeers) {
      await _closePeerConnection(peerId);
    }

    // Create/sync peer connections for connected remote participants
    for (final peerId in connectedRemotePeers) {
      final pc = await _getOrCreatePeerConnection(peerId);
      await _attachLocalTracksToPeer(pc);

      final lastSent = _lastOfferSentAt[peerId];
      final recentlySentOffer =
          lastSent != null &&
          DateTime.now().difference(lastSent).inMilliseconds < 1500;

      final isPeerStreaming = call.streams.any((s) => s.streamerId == peerId);
      final shouldOffer =
          (forceOfferToPeerId == peerId && !recentlySentOffer) ||
          (initiateOffers &&
              !_isPolitePeer(peerId) &&
              !recentlySentOffer &&
              (!isPeerStreaming || _isScreenSharing));
      if (shouldOffer) {
        await _createAndSendOffer(peerId, pc);
      }
    }
  }

  Future<RTCPeerConnection> _getOrCreatePeerConnection(String peerId) {
    final existing = _peerConnections[peerId];
    if (existing != null) return Future.value(existing);

    final inflight = _peerConnectionFutures[peerId];
    if (inflight != null) return inflight;

    final future = _createPeerConnectionInternal(peerId);
    _peerConnectionFutures[peerId] = future;
    future.whenComplete(() {
      if (_peerConnectionFutures[peerId] == future) {
        _peerConnectionFutures.remove(peerId);
      }
    });
    return future;
  }

  Future<RTCPeerConnection> _createPeerConnectionInternal(String peerId) async {
    await ensureRenderersInitialized();
    await _ensureParticipantRenderer(peerId);

    final existing = _peerConnections[peerId];
    if (existing != null) return existing;

    final pc = await createPeerConnection(_rtcConfiguration);
    _peerConnections[peerId] = pc;

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      final call = _activeCall;
      if (call == null || candidate.candidate == null) return;
      _sendCallSignal(call, {
        'type': 'ice_candidate',
        'target_user_id': peerId,
        'from_user_id': _currentUserId,
        'candidate': candidate.candidate,
        'sdp_mid': candidate.sdpMid,
        'sdp_m_line_index': candidate.sdpMLineIndex,
      });
    };

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _handleRemoteStream(peerId, event.streams.first, event.track);
      } else {
        // Construct or reuse stream wrapper if track arrives without stream
        _handleRemoteTrackOnly(peerId, event.track);
      }
    };

    pc.onAddStream = (MediaStream stream) {
      _handleRemoteStream(peerId, stream, null);
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('[CallStateProvider] ICE state ($peerId): $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _iceRestartTimers.remove(peerId)?.cancel();
        unawaited(_configureCallAudioSession());
        notifyListeners();
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _scheduleIceRestart(
          peerId,
          pc,
          delay: const Duration(milliseconds: 1800),
        );
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _scheduleIceRestart(peerId, pc, delay: Duration.zero);
      }
    };

    await _attachLocalTracksToPeer(pc);
    return pc;
  }

  void _scheduleIceRestart(
    String peerId,
    RTCPeerConnection pc, {
    required Duration delay,
  }) {
    _iceRestartTimers.remove(peerId)?.cancel();
    _iceRestartTimers[peerId] = Timer(delay, () async {
      _iceRestartTimers.remove(peerId);
      if (_activeCall == null || _peerConnections[peerId] != pc) return;
      final iceState = pc.iceConnectionState;
      if (iceState != RTCIceConnectionState.RTCIceConnectionStateDisconnected &&
          iceState != RTCIceConnectionState.RTCIceConnectionStateFailed) {
        return;
      }
      debugPrint('[CallStateProvider] Triggering ICE restart for $peerId');
      await _createAndSendOffer(
        peerId,
        pc,
        forceRenegotiation: true,
        iceRestart: true,
      );
    });
  }

  Future<void> _attachLocalTracksToPeer(RTCPeerConnection pc) async {
    try {
      final senders = await pc.getSenders();
      final existingTrackIds = senders
          .map((s) => s.track?.id)
          .whereType<String>()
          .toSet();

      final userStream = _localUserStream;
      if (userStream != null) {
        for (final track in userStream.getTracks()) {
          if (!existingTrackIds.contains(track.id)) {
            await pc.addTrack(track, userStream);
          }
        }
      }

      final cameraStream = _localCameraStream;
      if (cameraStream != null && _isVideoOn) {
        for (final track in cameraStream.getVideoTracks()) {
          if (!existingTrackIds.contains(track.id)) {
            RTCRtpSender? reusableVideoSender;
            for (final s in senders) {
              final st = s.track;
              if (st != null &&
                  st.kind == 'video' &&
                  (_localDisplayStream == null ||
                      !_localDisplayStream!
                          .getVideoTracks()
                          .any((dt) => dt.id == st.id))) {
                reusableVideoSender = s;
                break;
              }
            }
            if (reusableVideoSender != null) {
              await reusableVideoSender.replaceTrack(track);
            } else {
              await pc.addTrack(track, cameraStream);
            }
          }
        }
      }

      final displayStream = _localDisplayStream;
      if (displayStream != null && _isScreenSharing) {
        for (final track in displayStream.getTracks()) {
          if (!existingTrackIds.contains(track.id)) {
            final sender = await pc.addTrack(track, displayStream);
            if (track.kind == 'video') {
              await _applySenderEncodingParameters(sender, _streamConfig);
            }
          } else {
            for (final sender in senders) {
              if (sender.track?.id == track.id && track.kind == 'video') {
                await _applySenderEncodingParameters(sender, _streamConfig);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[CallStateProvider] _attachLocalTracksToPeer error: $e');
    }
  }

  Future<void> _applySenderEncodingParameters(
    RTCRtpSender sender,
    StreamConfig config,
  ) async {
    try {
      final params = sender.parameters;
      if (params.encodings != null && params.encodings!.isNotEmpty) {
        for (final encoding in params.encodings!) {
          encoding.maxBitrate = config.bitrateKbps * 1000;
          encoding.maxFramerate = config.fps;

          double scale = 1.0;
          final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
          if (isMobile) {
            // Target longest edge for mobile screens (portrait or landscape):
            // 720p -> 1280, 1080p -> 1920, 1440p -> 2560
            final targetMax = config.height >= 1440
                ? 2560.0
                : (config.height >= 1080 ? 1920.0 : 1280.0);
            scale = 2400.0 / targetMax;
            if (scale < 1.0) scale = 1.0;
          } else {
            if (config.height > 0) {
              scale = 1080.0 / config.height;
              if (scale < 1.0) scale = 1.0;
            }
          }
          if (scale > 4.0) scale = 4.0;
          encoding.scaleResolutionDownBy = scale;
        }
        params.degradationPreference =
            RTCDegradationPreference.MAINTAIN_RESOLUTION;
        await sender.setParameters(params);
      }
    } catch (e) {
      debugPrint('[CallStateProvider] setParameters error: $e');
    }
  }

  /// Munges SDP to prioritize the chosen video codec (H264, VP8, VP9, AV1)
  /// and injects bitrate limits (b=AS, b=TIAS).
  String _applySdpCodecAndBitrate(String sdp, StreamConfig config) {
    try {
      final lines = sdp.split('\r\n');
      final newLines = <String>[];
      final targetCodec = config.codec.toUpperCase().trim();

      // Find payload types matching targetCodec
      final preferredPayloadTypes = <String>[];
      final rtpmapRegex =
          RegExp(r'^a=rtpmap:(\d+)\s+([A-Za-z0-9_-]+)/', caseSensitive: false);

      for (final line in lines) {
        final match = rtpmapRegex.firstMatch(line);
        if (match != null) {
          final pt = match.group(1)!;
          final codecName = match.group(2)!.toUpperCase();
          if (codecName == targetCodec ||
              (targetCodec == 'H264' && codecName == 'H264') ||
              (targetCodec == 'VP8' && codecName == 'VP8') ||
              (targetCodec == 'VP9' && codecName == 'VP9') ||
              (targetCodec == 'AV1' &&
                  (codecName == 'AV1' || codecName == 'AV1X'))) {
            preferredPayloadTypes.add(pt);
          }
        }
      }

      bool inVideoSection = false;
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.startsWith('m=video ')) {
          inVideoSection = true;
          final parts = line.split(' ');
          if (parts.length > 3 && preferredPayloadTypes.isNotEmpty) {
            final header = parts.sublist(0, 3);
            final existingPts = parts.sublist(3);
            final reordered = <String>[];

            for (final pt in preferredPayloadTypes) {
              if (existingPts.contains(pt)) reordered.add(pt);
            }
            for (final pt in existingPts) {
              if (!reordered.contains(pt)) reordered.add(pt);
            }
            newLines.add('${header.join(' ')} ${reordered.join(' ')}');
            if (config.bitrateKbps > 0) {
              newLines.add('b=AS:${config.bitrateKbps}');
              newLines.add('b=TIAS:${config.bitrateKbps * 1000}');
            }
            continue;
          }
        } else if (line.startsWith('m=')) {
          inVideoSection = false;
        }

        if (inVideoSection &&
            (line.startsWith('b=AS:') || line.startsWith('b=TIAS:'))) {
          continue;
        }

        newLines.add(line);
      }

      return newLines.join('\r\n');
    } catch (e) {
      debugPrint('[CallStateProvider] _applySdpCodecAndBitrate error: $e');
      return sdp;
    }
  }

  void _handleRemoteStream(
    String peerId,
    MediaStream stream,
    MediaStreamTrack? track,
  ) async {
    await ensureRenderersInitialized();
    for (final audioTrack in stream.getAudioTracks()) {
      audioTrack.enabled = !_isDeafened;
      try {
        await Helper.setVolume(_isDeafened ? 0.0 : 1.0, audioTrack);
      } catch (_) {}
    }
    if (track != null && track.kind == 'audio') {
      track.enabled = !_isDeafened;
      try {
        await Helper.setVolume(_isDeafened ? 0.0 : 1.0, track);
      } catch (_) {}
    }

    if (track != null && !stream.getTracks().any((t) => t.id == track.id)) {
      try {
        await stream.addTrack(track);
      } catch (_) {}
    }

    var effectiveStream = stream;
    if (track?.kind == 'video' && effectiveStream.getVideoTracks().isEmpty) {
      try {
        final newStream =
            await createLocalMediaStream('remote_${peerId}_${track!.id}');
        await newStream.addTrack(track);
        effectiveStream = newStream;
      } catch (_) {}
    }

    if (effectiveStream.getVideoTracks().isNotEmpty || track?.kind == 'video') {
      final participantRenderer = await _ensureParticipantRenderer(peerId);
      final peer = _activeCall?.participants
          .where((p) => p.userId == peerId)
          .firstOrNull;
      final primaryStream = _remotePrimaryStreams[peerId];
      final activeStreams = _activeCall?.streams ?? const <CallStream>[];
      final hasActiveStreamRecord =
          activeStreams.any((s) => s.streamerId == peerId);
      final isPeerScreenSharing =
          (peer?.isScreenSharing ?? false) || hasActiveStreamRecord;

      final isSecondaryDisplayStream = primaryStream != null &&
          primaryStream.getVideoTracks().isNotEmpty &&
          primaryStream.id != effectiveStream.id;
      final isScreenShareOnly =
          isPeerScreenSharing && !(peer?.isVideoOn ?? false);
      final isDisplayStream = isPeerScreenSharing &&
          (hasActiveStreamRecord ||
              isSecondaryDisplayStream ||
              isScreenShareOnly ||
              (!(_activeCall?.isVideo ?? false)));

      if (isDisplayStream) {
        _remoteDisplayStreams[peerId] = effectiveStream;
        final sRenderer = await ensureStreamRenderer(peerId);
        sRenderer.srcObject = effectiveStream;
        if (_renderersInitialized) {
          final focused = focusedStream;
          if (focused == null || focused.streamerId == peerId) {
            screenShareRenderer.srcObject = effectiveStream;
          }
        }
        participantRenderer.srcObject ??= effectiveStream;
      } else {
        _remotePrimaryStreams[peerId] = effectiveStream;
        participantRenderer.srcObject = effectiveStream;
        if (_renderersInitialized) {
          remoteRenderer.srcObject = effectiveStream;
          if (isPeerScreenSharing) {
            _remoteDisplayStreams[peerId] = effectiveStream;
            final sRenderer = await ensureStreamRenderer(peerId);
            sRenderer.srcObject = effectiveStream;
            final focused = focusedStream;
            if (focused == null || focused.streamerId == peerId) {
              screenShareRenderer.srcObject ??= effectiveStream;
            }
          }
        }
      }
    } else {
      // Voice-only stream: store and attach to remoteRenderer if no video stream is active
      // so WebRTC audio playout starts immediately even without video/screen-share!
      _remotePrimaryStreams[peerId] = effectiveStream;
      if (_renderersInitialized &&
          (remoteRenderer.srcObject == null ||
              remoteRenderer.srcObject!.getVideoTracks().isEmpty)) {
        remoteRenderer.srcObject = effectiveStream;
      }
    }
    unawaited(_configureCallAudioSession());
    notifyListeners();
  }

  void _handleRemoteTrackOnly(String peerId, MediaStreamTrack track) async {
    if (track.kind == 'audio') {
      track.enabled = !_isDeafened;
      Helper.setVolume(_isDeafened ? 0.0 : 1.0, track).catchError((_) {});
      unawaited(_configureCallAudioSession());
    } else if (track.kind == 'video') {
      try {
        final newStream =
            await createLocalMediaStream('remote_${peerId}_${track.id}');
        await newStream.addTrack(track);
        _handleRemoteStream(peerId, newStream, track);
      } catch (e) {
        debugPrint('[CallStateProvider] _handleRemoteTrackOnly video error: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _createAndSendOffer(
    String peerId,
    RTCPeerConnection pc, {
    bool forceRenegotiation = false,
    bool iceRestart = false,
  }) async {
    final call = _activeCall;
    if (call == null) return;
    if (_makingOfferForPeer.contains(peerId)) return;
    if (!forceRenegotiation &&
        pc.signalingState != null &&
        pc.signalingState != RTCSignalingState.RTCSignalingStateStable) {
      return;
    }

    _makingOfferForPeer.add(peerId);
    _lastOfferSentAt[peerId] = DateTime.now();
    try {
      final constraints = <String, dynamic>{
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 1,
        if (iceRestart) 'iceRestart': true,
      };
      final offer = await pc.createOffer(constraints);
      var sdp = offer.sdp ?? '';
      if (_isScreenSharing && sdp.isNotEmpty) {
        sdp = _applySdpCodecAndBitrate(sdp, _streamConfig);
      }
      final mungedOffer = RTCSessionDescription(sdp, offer.type);
      RTCSessionDescription offerToSet = mungedOffer;
      try {
        await pc.setLocalDescription(mungedOffer);
      } catch (e) {
        debugPrint(
            '[CallStateProvider] setLocalDescription failed with munged SDP, falling back to original offer: $e');
        offerToSet = offer;
        await pc.setLocalDescription(offer);
      }
      try {
        final senders = await pc.getSenders();
        for (final s in senders) {
          if (s.track?.kind == 'video') {
            await _applySenderEncodingParameters(s, _streamConfig);
          }
        }
      } catch (_) {}
      final activeDesc = await pc.getLocalDescription() ?? offerToSet;
      await _sendCallSignal(call, {
        'type': 'offer',
        'target_user_id': peerId,
        'from_user_id': _currentUserId,
        'sdp': activeDesc.sdp,
        'sdp_type': activeDesc.type,
      });
    } catch (e) {
      debugPrint('[CallStateProvider] _createAndSendOffer ($peerId) error: $e');
    } finally {
      _makingOfferForPeer.remove(peerId);
    }
  }

  Future<void> _renegotiateAllPeers() async {
    for (final entry in _peerConnections.entries) {
      await _attachLocalTracksToPeer(entry.value);
      await _createAndSendOffer(
        entry.key,
        entry.value,
        forceRenegotiation: true,
      );
    }
  }

  Future<void> _handleSignalingPayload(Map<String, dynamic> rawSignal) async {
    final call = _activeCall;
    if (call == null) return;
    _currentUserId ??= await AuthService.getUserId();
    final myId = _currentUserId;

    final signal = rawSignal['signal'] is Map<String, dynamic>
        ? rawSignal['signal'] as Map<String, dynamic>
        : (rawSignal['signal'] is Map
            ? Map<String, dynamic>.from(rawSignal['signal'] as Map)
            : rawSignal);

    final fromUserId =
        (signal['from_user_id'] ??
                rawSignal['from_user_id'] ??
                rawSignal['user_id'] ??
                '')
            .toString();
    if (fromUserId.isEmpty || fromUserId == myId) return;

    final targetUserId =
        (signal['target_user_id'] ?? rawSignal['target_user_id'] ?? '')
            .toString();
    if (targetUserId.isNotEmpty && targetUserId != myId) {
      return;
    }

    final signalType =
        (signal['signal_type'] ?? signal['type'] ?? '').toString();
    if (signalType.isEmpty) return;

    // Deduplicate identical signals arriving within 3s (e.g., direct WS + relay fallback)
    final now = DateTime.now();
    _recentSignalSignatures.removeWhere(
      (_, ts) => now.difference(ts).inMilliseconds > 3000,
    );
    final sigPayload = signalType == 'ice_candidate'
        ? (signal['candidate'] ?? '').toString()
        : (signal['sdp'] ?? '').toString();
    final sigKey = '$fromUserId:$signalType:${sigPayload.hashCode}';
    if (_recentSignalSignatures.containsKey(sigKey)) {
      return;
    }
    _recentSignalSignatures[sigKey] = now;

    // Serialize signaling operations per peer so offer/answer/candidates never race
    final prev = _peerSignalingQueues[fromUserId] ?? Future.value();
    final next = prev.catchError((_) {}).then((_) async {
      await _processPeerSignal(fromUserId, signalType, signal);
    });
    _peerSignalingQueues[fromUserId] = next;
    await next;
  }

  Future<void> _processPeerSignal(
    String fromUserId,
    String signalType,
    Map<String, dynamic> signal,
  ) async {
    final call = _activeCall;
    if (call == null) return;
    final myId = _currentUserId;
    var pc = await _getOrCreatePeerConnection(fromUserId);

    try {
      if (signalType == 'offer') {
        final sdp = (signal['sdp'] ?? '').toString();
        if (sdp.isEmpty) return;

        final isMakingOffer = _makingOfferForPeer.contains(fromUserId);
        final signalingState = pc.signalingState;
        final offerCollision =
            isMakingOffer ||
            (signalingState != null &&
                signalingState != RTCSignalingState.RTCSignalingStateStable);

        if (offerCollision) {
          if (!_isPolitePeer(fromUserId)) {
            // Impolite peer ignores colliding offer
            return;
          }
          // Polite peer yields: re-create peer connection cleanly without throwing rollback on Android
          await _closePeerConnection(fromUserId);
          pc = await _getOrCreatePeerConnection(fromUserId);
        }

        await _attachLocalTracksToPeer(pc);
        await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
        await _flushPendingCandidates(fromUserId, pc);

        final answer = await pc.createAnswer({
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': 1,
        });
        final answerSdp = answer.sdp ?? '';
        final localAnswer = RTCSessionDescription(answerSdp, answer.type);
        await pc.setLocalDescription(localAnswer);
        try {
          final senders = await pc.getSenders();
          for (final s in senders) {
            if (s.track?.kind == 'video') {
              await _applySenderEncodingParameters(s, _streamConfig);
            }
          }
        } catch (_) {}
        await _sendCallSignal(call, {
          'type': 'answer',
          'target_user_id': fromUserId,
          'from_user_id': myId,
          'sdp': localAnswer.sdp,
          'sdp_type': localAnswer.type,
        });

        // If we are sharing screen or camera, renegotiate as offerer so that
        // our preferred codecs (VP9/H264/AV1) and display tracks are fully established!
        if (_isScreenSharing || _isVideoOn) {
          Future.delayed(const Duration(milliseconds: 250), () async {
            if (_activeCall?.id == call.id && _peerConnections[fromUserId] == pc) {
              if (pc.signalingState == RTCSignalingState.RTCSignalingStateStable) {
                await _attachLocalTracksToPeer(pc);
                await _createAndSendOffer(fromUserId, pc, forceRenegotiation: true);
              }
            }
          });
        }
      } else if (signalType == 'answer') {
        final sdp = (signal['sdp'] ?? '').toString();
        if (sdp.isEmpty) return;
        if (pc.signalingState == RTCSignalingState.RTCSignalingStateStable) {
          await _flushPendingCandidates(fromUserId, pc);
          return;
        }
        await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
        await _flushPendingCandidates(fromUserId, pc);
        try {
          final senders = await pc.getSenders();
          for (final s in senders) {
            if (s.track?.kind == 'video') {
              await _applySenderEncodingParameters(s, _streamConfig);
            }
          }
        } catch (_) {}
      } else if (signalType == 'ice_candidate') {
        final candidateStr = (signal['candidate'] ?? '').toString();
        if (candidateStr.isEmpty) return;
        final sdpMid = signal['sdp_mid']?.toString();
        final sdpMLineIndex = signal['sdp_m_line_index'] is int
            ? signal['sdp_m_line_index'] as int
            : int.tryParse((signal['sdp_m_line_index'] ?? '0').toString()) ?? 0;
        final candidate = RTCIceCandidate(candidateStr, sdpMid, sdpMLineIndex);

        final remoteDesc = await pc.getRemoteDescription();
        if (remoteDesc == null) {
          _pendingCandidates.putIfAbsent(fromUserId, () => []).add(candidate);
        } else {
          await pc.addCandidate(candidate);
        }
      }
    } catch (e) {
      debugPrint('[CallStateProvider] signaling ($signalType) error: $e');
    }
  }

  Future<void> _flushPendingCandidates(
    String peerId,
    RTCPeerConnection pc,
  ) async {
    final list = _pendingCandidates.remove(peerId);
    if (list == null || list.isEmpty) return;
    for (final c in list) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
  }

  Future<void> _closePeerConnection(String peerId) async {
    _iceRestartTimers.remove(peerId)?.cancel();
    _peerConnectionFutures.remove(peerId);
    _peerSignalingQueues.remove(peerId);
    _pendingCandidates.remove(peerId);
    _makingOfferForPeer.remove(peerId);
    _lastOfferSentAt.remove(peerId);
    _remotePrimaryStreams.remove(peerId);
    _remoteDisplayStreams.remove(peerId);
    final pc = _peerConnections.remove(peerId);
    if (pc != null) {
      try {
        await pc.close();
        await pc.dispose();
      } catch (_) {}
    }
    final renderer = _participantRenderers.remove(peerId);
    if (renderer != null) {
      try {
        renderer.srcObject = null;
        await renderer.dispose();
      } catch (_) {}
    }
  }

  Future<void> _closeAllPeerConnections() async {
    for (final t in _iceRestartTimers.values) {
      t.cancel();
    }
    _iceRestartTimers.clear();
    _peerConnectionFutures.clear();
    _peerSignalingQueues.clear();
    _recentSignalSignatures.clear();
    final keys = _peerConnections.keys.toList();
    for (final peerId in keys) {
      await _closePeerConnection(peerId);
    }
    _pendingCandidates.clear();
    _makingOfferForPeer.clear();
    _lastOfferSentAt.clear();
    _remotePrimaryStreams.clear();
  }

  // ===========================================================================
  // Call Controls (Mute, Deafen, Speaker, Camera, Screen Share, Recording)
  // ===========================================================================

  void setMinimized(bool value) {
    if (_isMinimized == value) return;
    _isMinimized = value;
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    final tracks = _localUserStream?.getAudioTracks() ?? const [];
    for (final t in tracks) {
      t.enabled = !_isMuted;
    }
    _updateLocalParticipant(isMuted: _isMuted);
    notifyListeners();
    final call = _activeCall;
    if (call != null) {
      if (!call.id.startsWith('local_')) {
        await CallService.updateState(call.id, isMuted: _isMuted);
      }
      _broadcastLocalStateToChat(call);
    }
  }

  Future<void> toggleDeafen() async {
    _isDeafened = !_isDeafened;
    if (_isDeafened && !_isMuted) {
      _isMuted = true;
      for (final t in _localUserStream?.getAudioTracks() ?? const []) {
        t.enabled = false;
      }
    }
    for (final stream in _remotePrimaryStreams.values) {
      for (final t in stream.getAudioTracks()) {
        t.enabled = !_isDeafened;
      }
    }
    _updateLocalParticipant(isMuted: _isMuted, isDeafened: _isDeafened);
    notifyListeners();
    final call = _activeCall;
    if (call != null) {
      if (!call.id.startsWith('local_')) {
        await CallService.updateState(
          call.id,
          isMuted: _isMuted,
          isDeafened: _isDeafened,
        );
      }
      _broadcastLocalStateToChat(call);
    }
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    unawaited(_configureCallAudioSession());
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    if (_isTogglingVideo) return;
    _isTogglingVideo = true;
    try {
      final targetVideoState = !_isVideoOn;
      if (targetVideoState) {
        await _ensureCallPermissions(video: true);
        final callTitle = _activeCall?.title ?? 'Активный звонок';
        await NotificationService().startCallForegroundService(
          title: callTitle,
          isVideo: true,
          isScreenShare: _isScreenSharing,
        );
        final existingTracks =
            _localCameraStream?.getVideoTracks() ?? const [];
        final hadTracks = existingTracks.isNotEmpty;
        final ok = await _acquireCameraVideoStream();
        if (ok) {
          _isVideoOn = true;
          if (!hadTracks) {
            await _renegotiateAllPeers();
          } else {
            for (final pc in _peerConnections.values) {
              await _attachLocalTracksToPeer(pc);
            }
          }
        } else {
          _isVideoOn = false;
        }
      } else {
        _isVideoOn = false;
        final videoTracks = _localCameraStream?.getVideoTracks() ?? const [];
        for (final t in videoTracks) {
          t.enabled = false;
        }
        if (_renderersInitialized) {
          localRenderer.srcObject = null;
        }
      }
      _updateLocalParticipant(isVideoOn: _isVideoOn);
      notifyListeners();
      final call = _activeCall;
      if (call != null) {
        if (!call.id.startsWith('local_')) {
          await CallService.updateState(call.id, isVideoOn: _isVideoOn);
        }
        _broadcastLocalStateToChat(call);
      }
    } finally {
      _isTogglingVideo = false;
      notifyListeners();
    }
  }

  Future<void> switchCamera() async {
    if (_isTogglingVideo) return;
    final videoTracks = _localCameraStream?.getVideoTracks() ?? const [];
    if (videoTracks.isNotEmpty) {
      try {
        await Helper.switchCamera(videoTracks.first);
        _isFrontCamera = !_isFrontCamera;
        notifyListeners();
      } catch (e) {
        debugPrint('[CallStateProvider] switchCamera error: $e');
      }
    }
  }

  Future<void> toggleHandRaise() async {
    _isHandRaised = !_isHandRaised;
    _updateLocalParticipant(isHandRaised: _isHandRaised);
    notifyListeners();
    final call = _activeCall;
    if (call != null) {
      if (!call.id.startsWith('local_')) {
        await CallService.updateState(call.id, isHandRaised: _isHandRaised);
      }
      _broadcastLocalStateToChat(call);
    }
  }

  void _broadcastLocalStateToChat(CallSession call) {
    final myId = _currentUserId ?? 'local';
    _broadcastWebRtcCallRelay(
      call.chatId,
      'call_participant_updated',
      {
        'call_id': call.id,
        'chat_id': call.chatId,
        'user_id': myId,
        'is_muted': _isMuted,
        'is_deafened': _isDeafened,
        'is_video_on': _isVideoOn,
        'is_screen_sharing': _isScreenSharing,
        'is_hand_raised': _isHandRaised,
      },
    );
  }

  /// Starts High-FPS Screen Sharing (up to 1440p @ 144 FPS / 4K @ 60 FPS),
  /// publishes the display stream to all WebRTC peers, and notifies `/api/calls/:callId/streams/start`.
  Future<bool> startScreenShare(StreamConfig config) async {
    final call = _activeCall;
    if (call == null) return false;
    await ensureRenderersInitialized();

    _streamConfig = config;
    MediaStream? displayStream;
    try {
      if (!kIsWeb && Platform.isAndroid) {
        // 1. Ensure CallForegroundService is running before requesting screen capture
        await NotificationService().startCallForegroundService(
          title: call.title.isNotEmpty ? call.title : 'Активный звонок',
          isVideo: _isVideoOn,
          isScreenShare: false,
        );
        // 2. Request Android MediaProjection consent; MainActivity.onActivityResult
        // synchronously promotes CallForegroundService to FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION.
        final hasPermission = await Helper.requestCapturePermission();
        if (!hasPermission) {
          return false;
        }
        await NotificationService().promoteCallToMediaProjection();

        final androidConstraints = <String, dynamic>{
          'video': true,
          'audio': false,
        };
        displayStream =
            await navigator.mediaDevices.getDisplayMedia(androidConstraints);
      } else if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        // Desktop C++ flutter_webrtc requires desktopCapturer.getSources() to populate
        // its internal sources_ list and mandatory.frameRate to be a double!
        DesktopCapturerSource? selectedSource;
        try {
          final sources = await desktopCapturer.getSources(
            types: [SourceType.Screen, SourceType.Window],
          );
          if (sources.isNotEmpty) {
            if (config.sourceId != null && config.sourceId!.isNotEmpty) {
              selectedSource = sources
                  .where((s) => s.id == config.sourceId)
                  .firstOrNull;
            }
            if (selectedSource == null) {
              if (config.sourceType == 'window') {
                selectedSource = sources
                        .where((s) => s.type == SourceType.Window)
                        .firstOrNull ??
                    sources.first;
              } else {
                selectedSource = sources
                        .where((s) => s.type == SourceType.Screen)
                        .firstOrNull ??
                    sources.first;
              }
            }
          }
        } catch (e) {
          debugPrint('[CallStateProvider] desktopCapturer.getSources error: $e');
        }

        final desktopConstraints = <String, dynamic>{
          'video': {
            if (selectedSource != null)
              'deviceId': {'exact': selectedSource.id},
            'mandatory': {
              'frameRate': config.fps.toDouble(),
            },
          },
          'audio': false,
        };
        displayStream =
            await navigator.mediaDevices.getDisplayMedia(desktopConstraints);
      } else {
        // Web
        final webConstraints = <String, dynamic>{
          'video': {
            'width': {'ideal': config.width, 'max': config.width},
            'height': {'ideal': config.height, 'max': config.height},
            'frameRate': {'ideal': config.fps, 'max': config.fps},
          },
          'audio': config.includeAudio,
        };
        displayStream =
            await navigator.mediaDevices.getDisplayMedia(webConstraints);
      }

      _localDisplayStream = displayStream;
      _previewOwnScreenShare = false;
      if (_renderersInitialized) {
        screenShareRenderer.srcObject = null;
      }
      final videoTracks = displayStream.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        videoTracks.first.onEnded = () {
          stopScreenShare();
        };
      }
    } catch (e) {
      debugPrint('[CallStateProvider] getDisplayMedia error: $e');
      return false;
    }

    _isScreenSharing = true;
    _updateLocalParticipant(isScreenSharing: true);

    CallStream? createdStream;
    if (!call.id.startsWith('local_')) {
      createdStream = await CallService.startStream(call.id, config);
      await CallService.updateState(call.id, isScreenSharing: true);
      if (config.enableServerRecording && !_isRecording) {
        await toggleRecording();
      }
    }

    final currentUserId =
        _currentUserId ?? await AuthService.getUserId() ?? 'local';
    final currentUsername =
        AccountManager().currentAccount?.displayName ??
        AccountManager().currentAccount?.username ??
        'You';

    createdStream ??= CallStream(
      id: 'stream_${DateTime.now().millisecondsSinceEpoch}',
      callId: call.id,
      streamerId: currentUserId,
      streamerName: currentUsername,
      sourceType: config.sourceType,
      resolutionWidth: config.width,
      resolutionHeight: config.height,
      fps: config.fps,
      bitrateKbps: config.bitrateKbps,
      codec: config.codec,
      contentHint: config.contentHint,
      hasSystemAudio: config.includeAudio,
      viewerCount: call.participants.length,
    );

    _activeLocalStreamInfo = createdStream;
    _focusedStream = createdStream;
    final updatedStreams = [
      ...call.streams.where((s) => s.id != createdStream!.id),
      createdStream,
    ];
    _activeCall = call.copyWith(streams: updatedStreams);
    notifyListeners();

    _broadcastLocalStateToChat(_activeCall!);
    _broadcastWebRtcCallRelay(
      call.chatId,
      'call_stream_started',
      {
        'call_id': call.id,
        'chat_id': call.chatId,
        'stream': createdStream.toJson(),
      },
    );

    await _renegotiateAllPeers();
    return true;
  }

  /// Dynamically updates the active screen share quality (`PATCH /api/calls/:callId/streams/:streamId/quality`).
  Future<void> updateScreenShareQuality(StreamConfig config) async {
    _streamConfig = config;
    final call = _activeCall;
    final localStreamInfo = _activeLocalStreamInfo;
    if (call == null || localStreamInfo == null) {
      notifyListeners();
      return;
    }

    // Apply updated encoding parameters to active WebRTC video senders
    for (final pc in _peerConnections.values) {
      try {
        final senders = await pc.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            await _applySenderEncodingParameters(sender, config);
          }
        }
      } catch (_) {}
    }

    if (config.enableServerRecording != _isRecording) {
      await toggleRecording(config: config);
    }

    CallStream? updated;
    if (!call.id.startsWith('local_')) {
      updated = await CallService.updateStreamQuality(
        call.id,
        localStreamInfo.id,
        config,
      );
    }
    updated ??= localStreamInfo.copyWith(
      resolutionWidth: config.width,
      resolutionHeight: config.height,
      fps: config.fps,
      bitrateKbps: config.bitrateKbps,
      codec: config.codec,
      contentHint: config.contentHint,
      hasSystemAudio: config.includeAudio,
    );

    _activeLocalStreamInfo = updated;
    _focusedStream = updated;
    final updatedList = call.streams
        .map((s) => s.id == updated!.id ? updated : s)
        .toList();
    _activeCall = call.copyWith(streams: updatedList);

    _broadcastWebRtcCallRelay(
      call.chatId,
      'call_stream_quality_updated',
      {
        'call_id': call.id,
        'chat_id': call.chatId,
        'stream': updated.toJson(),
      },
    );

    notifyListeners();

    // Renegotiate with peers so SDP munging applies new codec, resolution, and bitrate immediately
    await _renegotiateAllPeers();
  }

  /// Stops screen sharing.
  Future<void> stopScreenShare() async {
    final call = _activeCall;
    final localStreamInfo = _activeLocalStreamInfo;
    final displayStream = _localDisplayStream;
    _isScreenSharing = false;
    _previewOwnScreenShare = false;
    _activeLocalStreamInfo = null;
    _localDisplayStream = null;
    if (_renderersInitialized) {
      screenShareRenderer.srcObject = null;
    }

    if (call != null) {
      unawaited(
        NotificationService().startCallForegroundService(
          title: call.title.isNotEmpty ? call.title : 'Активный звонок',
          isVideo: _isVideoOn,
          isScreenShare: false,
        ),
      );
    }

    if (displayStream != null) {
      final displayTrackIds = displayStream
          .getTracks()
          .map((t) => t.id)
          .whereType<String>()
          .toSet();
      for (final pc in _peerConnections.values) {
        try {
          final senders = await pc.getSenders();
          for (final s in senders) {
            if (s.track?.id != null && displayTrackIds.contains(s.track!.id)) {
              await pc.removeTrack(s);
            }
          }
        } catch (_) {}
      }
      try {
        for (final t in displayStream.getTracks()) {
          t.stop();
        }
        await displayStream.dispose();
      } catch (_) {}
    }

    _updateLocalParticipant(isScreenSharing: false);

    if (call != null) {
      final myId = _currentUserId;
      final remaining = call.streams.where((s) {
        if (localStreamInfo != null && s.id == localStreamInfo.id) return false;
        if (myId != null && myId.isNotEmpty && s.streamerId == myId) return false;
        if (s.streamerId == 'local') return false;
        return true;
      }).toList();
      _activeCall = _activeCall?.copyWith(streams: remaining);
      if (_focusedStream != null &&
          !remaining.any((s) => s.id == _focusedStream!.id)) {
        _focusedStream = remaining.isNotEmpty ? remaining.first : null;
      }
      if (!call.id.startsWith('local_')) {
        await CallService.stopStream(call.id, localStreamInfo?.id ?? 'mine');
        await CallService.updateState(call.id, isScreenSharing: false);
      }
      if (_activeCall != null) {
        _broadcastLocalStateToChat(_activeCall!);
      }
      _broadcastWebRtcCallRelay(call.chatId, 'call_stream_stopped', {
        'call_id': call.id,
        'chat_id': call.chatId,
        'stream_id': localStreamInfo?.id ?? 'mine',
        'streamer_id': _currentUserId ?? 'local',
      });
    }
    notifyListeners();
    await _renegotiateAllPeers();
  }

  /// Changes viewer simulcast subscription quality (`Auto` / `High` / `Medium` / `Low` / `Audio Only`).
  Future<void> setViewerQuality(ViewerSubscriptionQuality quality) async {
    _viewerQuality = quality;
    notifyListeners();
    final call = _activeCall;
    final stream = focusedStream;
    if (call != null && stream != null && !call.id.startsWith('local_')) {
      await CallService.setStreamSubscription(call.id, stream.id, quality);
    }
  }

  void setFocusedStream(CallStream? stream) {
    _focusedStream = stream;
    if (_renderersInitialized) {
      if (stream == null) {
        screenShareRenderer.srcObject = null;
      } else if (stream.streamerId == _currentUserId || stream.streamerId == 'local') {
        screenShareRenderer.srcObject = _previewOwnScreenShare ? _localDisplayStream : null;
      } else {
        screenShareRenderer.srcObject = _remoteDisplayStreams[stream.streamerId] ??
            (_remotePrimaryStreams[stream.streamerId]?.getVideoTracks().isNotEmpty == true
                ? _remotePrimaryStreams[stream.streamerId]
                : null);
      }
    }
    notifyListeners();
  }

  Future<void> toggleRecording({StreamConfig? config}) async {
    final call = _activeCall;
    if (call == null) return;
    if (_isRecording) {
      _isRecording = false;
      notifyListeners();
      if (!call.id.startsWith('local_')) {
        await CallService.stopRecording(call.id);
      }
    } else {
      _isRecording = true;
      notifyListeners();
      if (!call.id.startsWith('local_')) {
        await CallService.startRecording(
          call.id,
          config: config ?? _streamConfig,
        );
      }
    }
  }

  Future<void> sendReaction(String emoji) async {
    final call = _activeCall;
    if (call == null) return;
    final userId = _currentUserId ?? await AuthService.getUserId() ?? 'local';
    _addFloatingReaction(userId, emoji);
    if (!call.id.startsWith('local_')) {
      await CallService.sendReaction(call.id, emoji);
    }
  }

  void _addFloatingReaction(String userId, String emoji) {
    final item = FloatingCallReaction(
      id: '${DateTime.now().microsecondsSinceEpoch}_$userId',
      userId: userId,
      emoji: emoji,
      createdAt: DateTime.now(),
    );
    _reactions.add(item);
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 2800), () {
      _reactions.removeWhere((r) => r.id == item.id);
      notifyListeners();
    });
  }

  void setParticipantVolume(String userId, int volume) {
    final call = _activeCall;
    if (call == null) return;
    final updated = call.participants
        .map((p) => p.userId == userId ? p.copyWith(volume: volume) : p)
        .toList();
    _activeCall = call.copyWith(participants: updated);
    notifyListeners();
  }

  Future<void> moderateParticipant(String userId, String action) async {
    final call = _activeCall;
    if (call == null) return;
    if (!call.id.startsWith('local_')) {
      await CallService.moderateParticipant(call.id, userId, action: action);
    }
    if (action == 'kick') {
      _activeCall = call.copyWith(
        participants:
            call.participants.where((p) => p.userId != userId).toList(),
      );
      await _closePeerConnection(userId);
    } else if (action == 'mute') {
      _activeCall = call.copyWith(
        participants: call.participants
            .map(
              (p) => p.userId == userId
                  ? p.copyWith(isMuted: true, serverMuted: true)
                  : p,
            )
            .toList(),
      );
    } else if (action == 'promote_speaker') {
      _activeCall = call.copyWith(
        participants: call.participants
            .map(
              (p) => p.userId == userId
                  ? p.copyWith(role: 'speaker', isHandRaised: false)
                  : p,
            )
            .toList(),
      );
    }
    notifyListeners();
  }

  /// Leaves and cleans up the active call.
  Future<void> leaveCall({bool notifyServer = true}) async {
    final call = _activeCall;
    final wasScreenSharing = _isScreenSharing;
    final localStreamId = _activeLocalStreamInfo?.id;
    _ringingTimeoutTimer?.cancel();
    _ringingTimeoutTimer = null;
    _timer?.cancel();
    _timer = null;
    _elapsed = Duration.zero;
    _activeCall = null;
    _activeLocalStreamInfo = null;
    _focusedStream = null;
    _isMinimized = false;
    _isScreenSharing = false;
    _previewOwnScreenShare = false;
    _isVideoOn = false;
    _isRecording = false;
    _reactions.clear();
    _remoteDisplayStreams.clear();
    _participantRotations.clear();

    unawaited(NotificationService().stopCallForegroundService());
    if (call != null) {
      unawaited(
        NotificationService().cancelIncomingCallNotification(
          callId: call.id,
          chatId: call.chatId,
        ),
      );
    }

    await _closeAllPeerConnections();

    try {
      for (final t in _localCameraStream?.getTracks() ?? const []) {
        t.stop();
      }
      await _localCameraStream?.dispose();
    } catch (_) {}
    _localCameraStream = null;

    try {
      for (final t in _localUserStream?.getTracks() ?? const []) {
        t.stop();
      }
      await _localUserStream?.dispose();
    } catch (_) {}
    _localUserStream = null;

    try {
      for (final t in _localDisplayStream?.getTracks() ?? const []) {
        t.stop();
      }
      await _localDisplayStream?.dispose();
    } catch (_) {}
    _localDisplayStream = null;

    if (_renderersInitialized) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
      screenShareRenderer.srcObject = null;
    }
    for (final r in _streamRenderers.values) {
      r.srcObject = null;
      r.dispose();
    }
    _streamRenderers.clear();
    notifyListeners();

    if (notifyServer && call != null) {
      if (!call.id.startsWith('local_')) {
        if (wasScreenSharing) {
          await CallService.stopStream(call.id, localStreamId ?? 'mine');
        }
        await CallService.leaveCall(call.id);
      }
      final isOneOnOne = !call.isGroupOrCommunity &&
          call.callType != 'group' &&
          call.callType != 'stage';
      _broadcastWebRtcCallRelay(
        call.chatId,
        isOneOnOne ? 'call_ended' : 'call_participant_left',
        {
          'call_id': call.id,
          'chat_id': call.chatId,
          'user_id': _currentUserId ?? 'local',
        },
      );
    }
  }

  CallSession _mergeUpdatedCallSession(CallSession current, CallSession incoming) {
    final myId = _currentUserId;
    final preservedCallType = current.isGroupOrCommunity
        ? (current.callType == 'stage' ? 'stage' : 'group')
        : incoming.callType;

    final filteredStreams = _isScreenSharing
        ? incoming.streams
        : incoming.streams
            .where((s) =>
                (myId == null || s.streamerId != myId) &&
                s.streamerId != 'local')
            .toList();

    final List<CallStream> mergedStreams;
    if (incoming.streams.isNotEmpty) {
      mergedStreams = filteredStreams;
    } else if (current.streams.isNotEmpty) {
      final connectedUserIds = incoming.participants
          .where((p) => p.state == 'connected')
          .map((p) => p.userId)
          .toSet();
      mergedStreams = current.streams
          .where((s) => connectedUserIds.contains(s.streamerId))
          .toList();
    } else {
      mergedStreams = const [];
    }

    final syncedParticipants = incoming.participants.map((p) {
      if (p.userId == myId || p.userId == 'local') {
        return p.copyWith(
          isScreenSharing: _isScreenSharing,
          isVideoOn: _isVideoOn,
          isMuted: _isMuted,
          isDeafened: _isDeafened,
        );
      }
      final hasStream = mergedStreams.any((s) => s.streamerId == p.userId);
      if (hasStream && !p.isScreenSharing) {
        return p.copyWith(isScreenSharing: true);
      }
      return p;
    }).toList();

    return incoming.copyWith(
      callType: preservedCallType,
      communityId: incoming.communityId ?? current.communityId,
      maxParticipants: incoming.maxParticipants > current.maxParticipants
          ? incoming.maxParticipants
          : current.maxParticipants,
      title: incoming.title.isNotEmpty ? incoming.title : current.title,
      participants: syncedParticipants,
      streams: mergedStreams,
    );
  }

  Future<void> _notifyDeviceIfBackgroundOrUnfocused(
    CallSession session, {
    required String callerId,
    required String callerName,
    String? callerAvatar,
  }) async {
    final displayCaller = callerName.isNotEmpty
        ? callerName
        : (session.title.isNotEmpty ? session.title : 'Входящий звонок');
    final avatar = callerAvatar ??
        session.participants
            .where((p) => p.userId == callerId)
            .firstOrNull
            ?.avatarUrl;

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      bool isFocused = true;
      try {
        isFocused = await windowManager.isFocused();
      } catch (_) {}
      if (!isFocused || !NotificationService().isAppInForeground) {
        await NotificationService().showCallNotification(
          callId: session.id,
          chatId: session.chatId,
          callerId: callerId,
          callerName: displayCaller,
          callerAvatar: avatar,
          isVideo: session.isVideo,
          isGroup: session.callType == 'group' || session.callType == 'stage',
          chatTitle: session.title,
        );
      }
      return;
    }

    if (!NotificationService().isAppInForeground) {
      await NotificationService().showCallNotification(
        callId: session.id,
        chatId: session.chatId,
        callerId: callerId,
        callerName: displayCaller,
        callerAvatar: avatar,
        isVideo: session.isVideo,
        isGroup: session.callType == 'group' || session.callType == 'stage',
        chatTitle: session.title,
      );
    }
  }

  void _startTimer(DateTime startedAt) {
    _timer?.cancel();
    _elapsed = DateTime.now().difference(startedAt);
    if (_elapsed.isNegative) _elapsed = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  void _updateLocalParticipant({
    bool? isMuted,
    bool? isDeafened,
    bool? isVideoOn,
    bool? isScreenSharing,
    bool? isHandRaised,
  }) {
    final call = _activeCall;
    if (call == null || call.participants.isEmpty) return;
    final myId = _currentUserId;
    final list = call.participants.map((p) {
      if (p.userId == myId || p.userId == 'local') {
        return p.copyWith(
          isMuted: isMuted,
          isDeafened: isDeafened,
          isVideoOn: isVideoOn,
          isScreenSharing: isScreenSharing,
          isHandRaised: isHandRaised,
        );
      }
      return p;
    }).toList();
    _activeCall = call.copyWith(participants: list);
  }

  // ===========================================================================
  // Real-Time WebSocket Call & Signaling Event Dispatcher
  // ===========================================================================

  void handleWsEvent(String type, Map<String, dynamic> payload) {
    final normalizedType = type.replaceAll('.', '_');

    switch (normalizedType) {
      case 'call_incoming':
      case 'call_started':
        final callMap = payload['call'] is Map<String, dynamic>
            ? payload['call'] as Map<String, dynamic>
            : (payload['call'] is Map
                ? Map<String, dynamic>.from(payload['call'] as Map)
                : payload);
        var session = CallSession.fromJson(callMap);
        final callerId = (payload['caller_id'] ?? session.initiatorId).toString();
        final callerName = (payload['caller_name'] ?? '').toString();
        if (session.title.isEmpty && callerName.isNotEmpty) {
          session = session.copyWith(title: callerName);
        }
        if (payload['video_enabled'] == true && !session.isVideo) {
          session = session.copyWith(isVideo: true);
        }

        if (_activeCall != null &&
            (_activeCall!.id == session.id ||
                (_activeCall!.chatId == session.chatId &&
                    _activeCall!.id.startsWith('local_')))) {
          _activeCall = _mergeUpdatedCallSession(_activeCall!, session);
          notifyListeners();
          _syncPeerConnections();
        } else if (_activeCall == null &&
            callerId != _currentUserId &&
            (normalizedType == 'call_incoming' ||
                (normalizedType == 'call_started' &&
                    session.status == 'ringing'))) {
          final isDuplicateIncoming = _incomingCall != null &&
              (_incomingCall!.id == session.id ||
                  (_incomingCall!.chatId == session.chatId &&
                      session.chatId.isNotEmpty));
          _incomingCall = session;
          notifyListeners();
          if (!isDuplicateIncoming) {
            unawaited(
              _notifyDeviceIfBackgroundOrUnfocused(
                session,
                callerId: callerId,
                callerName: callerName,
                callerAvatar: payload['caller_avatar']?.toString(),
              ),
            );
          }
        }
        break;

      case 'call_accepted':
      case 'call_participant_joined':
        final callId = (payload['call_id'] ?? '').toString();
        final chatId = (payload['chat_id'] ?? '').toString();
        final joinedUserId =
            (payload['user_id'] ?? payload['accepted_by'] ?? '').toString();
        if (_activeCall == null) {
          break;
        }
        if (callId.isNotEmpty &&
            _activeCall!.id != callId &&
            !(_activeCall!.chatId == chatId && chatId.isNotEmpty)) {
          break;
        }
        final wasRinging = _activeCall!.status == 'ringing';
        _ringingTimeoutTimer?.cancel();
        _ringingTimeoutTimer = null;

        if (payload['call'] is Map) {
          final updatedSession = CallSession.fromJson(
            Map<String, dynamic>.from(payload['call'] as Map),
          );
          _activeCall = _mergeUpdatedCallSession(
            _activeCall!,
            updatedSession.copyWith(status: 'active'),
          );
          if (_activeCall!.streams.isNotEmpty) {
            if (_focusedStream == null || !_activeCall!.streams.any((s) => s.id == _focusedStream!.id)) {
              _focusedStream = _activeCall!.streams.first;
            }
            for (final s in _activeCall!.streams) {
              unawaited(ensureStreamRenderer(s.streamerId));
            }
          }
        } else if (payload['participant'] is Map) {
          final p = CallParticipant.fromJson(
            Map<String, dynamic>.from(payload['participant'] as Map),
          );
          final list = [
            ..._activeCall!.participants.where((x) => x.userId != p.userId),
            p,
          ];
          _activeCall = _activeCall!.copyWith(
            status: 'active',
            participants: list,
          );
        } else {
          _activeCall = _activeCall!.copyWith(status: 'active');
        }

        if (wasRinging || _timer == null) {
          _startTimer(DateTime.now());
        }
        notifyListeners();
        if (joinedUserId.isNotEmpty && joinedUserId != _currentUserId) {
          _syncPeerConnections(forceOfferToPeerId: joinedUserId);
        } else {
          _syncPeerConnections(initiateOffers: true);
        }
        break;

      case 'call_participant_left':
        final call = _activeCall;
        if (call == null) break;
        final callId = (payload['call_id'] ?? '').toString();
        if (callId.isNotEmpty && call.id != callId && call.chatId != payload['chat_id']?.toString()) break;
        final userId = (payload['user_id'] ?? payload['from_user_id'] ?? '').toString();
        if (userId.isNotEmpty) {
          _closePeerConnection(userId);
        }
        if (payload['call'] is Map) {
          final updatedSession = CallSession.fromJson(
            Map<String, dynamic>.from(payload['call'] as Map),
          );
          _activeCall = _mergeUpdatedCallSession(call, updatedSession);
        } else {
          final remainingStreams =
              call.streams.where((s) => s.streamerId != userId).toList();
          _activeCall = call.copyWith(
            participants:
                call.participants.where((p) => p.userId != userId).toList(),
            streams: remainingStreams,
          );
        }
        if (_focusedStream != null &&
            !_activeCall!.streams.any((s) => s.id == _focusedStream!.id)) {
          _focusedStream =
              _activeCall!.streams.isNotEmpty ? _activeCall!.streams.first : null;
        }
        notifyListeners();
        break;

      case 'call_participant_updated':
      case 'call_state_changed':
        final call = _activeCall;
        if (call == null) break;
        final callId = (payload['call_id'] ?? '').toString();
        if (callId.isNotEmpty && call.id != callId && call.chatId != payload['chat_id']?.toString()) break;

        if (payload['call'] is Map) {
          final updatedSession = CallSession.fromJson(
            Map<String, dynamic>.from(payload['call'] as Map),
          );
          _activeCall = _mergeUpdatedCallSession(call, updatedSession);
        } else {
          final userId = (payload['user_id'] ?? '').toString();
          final isSharing = payload['is_screen_sharing'] as bool?;
          final updated = call.participants.map((p) {
            if (p.userId != userId) return p;
            final selfMute =
                (payload['self_mute'] ?? payload['is_muted']) as bool?;
            final srvMute = payload['server_mute'] as bool?;
            final selfDeaf =
                (payload['self_deaf'] ?? payload['is_deafened']) as bool?;
            final srvDeaf = payload['server_deaf'] as bool?;
            return p.copyWith(
              isMuted: (srvMute ?? p.serverMuted) || (selfMute ?? p.isMuted),
              isDeafened:
                  (srvDeaf ?? p.serverDeafened) || (selfDeaf ?? p.isDeafened),
              serverMuted: srvMute,
              serverDeafened: srvDeaf,
              isVideoOn: payload['is_video_on'] as bool?,
              isScreenSharing: isSharing,
              isHandRaised: payload['is_hand_raised'] as bool?,
              isSpeaking: payload['is_speaking'] as bool?,
              role: payload['stage_role']?.toString(),
            );
          }).toList();
          final updatedStreams = (isSharing == false && userId.isNotEmpty)
              ? call.streams.where((s) => s.streamerId != userId).toList()
              : call.streams;
          _activeCall = call.copyWith(
            participants: updated,
            streams: updatedStreams,
          );
        }
        if (_focusedStream != null &&
            !_activeCall!.streams.any((s) => s.id == _focusedStream!.id)) {
          _focusedStream =
              _activeCall!.streams.isNotEmpty ? _activeCall!.streams.first : null;
        }
        notifyListeners();
        break;

      case 'call_stream_started':
      case 'call_stream_quality_updated':
      case 'call_stream_quality_changed':
        final call = _activeCall;
        if (call == null) break;
        final sMap = payload['stream'] is Map<String, dynamic>
            ? payload['stream'] as Map<String, dynamic>
            : (payload['stream'] is Map
                ? Map<String, dynamic>.from(payload['stream'] as Map)
                : payload);
        final stream = CallStream.fromJson(sMap);
        final list = [
          ...call.streams.where(
              (s) => s.id != stream.id && s.streamerId != stream.streamerId),
          stream,
        ];
        final updatedParticipants = call.participants
            .map((p) => p.userId == stream.streamerId
                ? p.copyWith(isScreenSharing: true)
                : p)
            .toList();
        _activeCall = call.copyWith(
          streams: list,
          participants: updatedParticipants,
        );
        _focusedStream ??= stream;
        unawaited(ensureStreamRenderer(stream.streamerId));

        // Immediately link renderer to this streamer's video stream if already received
        if (stream.streamerId == _currentUserId) {
          if (_previewOwnScreenShare && _renderersInitialized) {
            screenShareRenderer.srcObject = _localDisplayStream;
          }
        } else {
          final existingStream = _remoteDisplayStreams[stream.streamerId] ??
              (_remotePrimaryStreams[stream.streamerId]
                          ?.getVideoTracks()
                          .isNotEmpty ==
                      true
                  ? _remotePrimaryStreams[stream.streamerId]
                  : _participantRenderers[stream.streamerId]?.srcObject);
          if (existingStream != null) {
            final sRenderer = _streamRenderers[stream.streamerId];
            if (sRenderer != null) sRenderer.srcObject = existingStream;
            if (_renderersInitialized) {
              screenShareRenderer.srcObject = existingStream;
            }
          }
        }
        notifyListeners();
        break;

      case 'call.stream_stopped':
      case 'call_stream_stopped':
      case 'call.stream_ended':
      case 'call_stream_ended':
        final call = _activeCall;
        if (call == null) break;
        final streamId =
            (payload['stream_id'] ?? payload['id'] ?? '').toString();
        final streamerId =
            (payload['streamer_id'] ?? payload['from_user_id'] ?? '').toString();
        final list = call.streams.where((s) {
          if (streamId.isNotEmpty && streamId != 'mine' && s.id == streamId) {
            return false;
          }
          if (streamerId.isNotEmpty && s.streamerId == streamerId) {
            return false;
          }
          return true;
        }).toList();
        final updatedParticipants = streamerId.isNotEmpty
            ? call.participants
                .map((p) => p.userId == streamerId
                    ? p.copyWith(isScreenSharing: false)
                    : p)
                .toList()
            : call.participants;
        _activeCall = call.copyWith(
          streams: list,
          participants: updatedParticipants,
        );
        if (streamerId.isNotEmpty) {
          _remoteDisplayStreams.remove(streamerId);
          _streamRenderers[streamerId]?.srcObject = null;
          _streamRenderers.remove(streamerId)?.dispose();
        }
        if (_focusedStream != null &&
            !list.any((s) => s.id == _focusedStream!.id)) {
          _focusedStream = list.isNotEmpty ? list.first : null;
        }
        if (list.isEmpty && !_isScreenSharing && _renderersInitialized) {
          screenShareRenderer.srcObject = null;
        } else if (_focusedStream != null &&
            _focusedStream!.streamerId != _currentUserId &&
            _renderersInitialized) {
          final nextStream =
              _remoteDisplayStreams[_focusedStream!.streamerId] ??
                  _participantRenderers[_focusedStream!.streamerId]?.srcObject;
          if (nextStream != null) {
            screenShareRenderer.srcObject = nextStream;
          }
        }
        notifyListeners();
        break;

      case 'call_signal':
        _handleSignalingPayload(payload);
        break;

      case 'call_reaction':
        final emoji = (payload['emoji'] ?? '👍').toString();
        final userId = (payload['user_id'] ?? '').toString();
        // Check if this is a fallback WebRTC signaling frame
        if (emoji.startsWith('__webrtc_signal__:')) {
          try {
            final encoded = emoji.substring('__webrtc_signal__:'.length);
            final decodedJson = utf8.decode(base64Decode(encoded));
            final signalMap =
                jsonDecode(decodedJson) as Map<String, dynamic>;
            signalMap.putIfAbsent('from_user_id', () => userId);
            _handleSignalingPayload(signalMap);
          } catch (e) {
            debugPrint('[CallStateProvider] decode signal fallback error: $e');
          }
          break;
        }
        if (userId != _currentUserId) {
          _addFloatingReaction(userId, emoji);
        }
        break;

      case 'call.transferred_elsewhere':
      case 'call_transferred_elsewhere':
        final callId = (payload['call_id'] ?? '').toString();
        if (_activeCall != null && (_activeCall!.id == callId || callId.isEmpty)) {
          debugPrint('[CallStateProvider] Call transferred to another device, terminating locally.');
          leaveCall(notifyServer: false);
        }
        break;

      case 'call.user_active_call_state':
        final callId = (payload['call_id'] ?? '').toString();
        final chatId = (payload['chat_id'] ?? '').toString();
        final title = (payload['title'] ?? '').toString();
        final status = (payload['status'] ?? '').toString();
        if (status == 'active' && (_activeCall == null || _activeCall!.id != callId)) {
          _otherDeviceActiveCallId = callId;
          _otherDeviceActiveChatId = chatId;
          _otherDeviceActiveChatTitle = title;
        } else if (status == 'ended' || (_activeCall != null && _activeCall!.id == callId)) {
          _otherDeviceActiveCallId = null;
          _otherDeviceActiveChatId = null;
          _otherDeviceActiveChatTitle = null;
        }
        notifyListeners();
        break;

      case 'call.peer_device_transferred':
        final callId = (payload['call_id'] ?? '').toString();
        final peerUserId = (payload['user_id'] ?? '').toString();
        if (_activeCall != null && (_activeCall!.id == callId || callId.isEmpty)) {
          debugPrint('[CallStateProvider] Peer $peerUserId transferred device, renegotiating WebRTC...');
          if (peerUserId.isNotEmpty) {
            _closePeerConnection(peerUserId);
            unawaited(_syncPeerConnections(initiateOffers: true));
          }
        }
        break;

      case 'call.soundboard_played':
        final soundUrl = (payload['file_url'] ?? payload['sound_url'] ?? '').toString();
        if (soundUrl.isNotEmpty) {
          unawaited(_playSoundboardClip(soundUrl));
        }
        break;

      case 'call_answered_elsewhere':
        final callId = (payload['call_id'] ?? '').toString();
        unawaited(
          NotificationService().cancelIncomingCallNotification(callId: callId),
        );
        if (_incomingCall?.id == callId) {
          _incomingCall = null;
          notifyListeners();
        }
        break;

      case 'call_ended':
        final callId = (payload['call_id'] ?? payload['id'] ?? '').toString();
        final chatId = (payload['chat_id'] ?? '').toString();
        final reason = (payload['reason'] ?? '').toString();
        final fromPeerId =
            (payload['from_user_id'] ?? payload['user_id'] ?? '').toString();
        unawaited(
          NotificationService().cancelIncomingCallNotification(
            callId: callId,
            chatId: chatId,
          ),
        );
        if (_activeCall != null &&
            (_activeCall!.id == callId ||
                (chatId.isNotEmpty && _activeCall!.chatId == chatId))) {
          // If this is a group or community call and a peer sent a client-side relay
          // (no server end reason), only remove that peer instead of ending the call!
          if (_activeCall!.isGroupOrCommunity &&
              reason.isEmpty &&
              fromPeerId.isNotEmpty) {
            _closePeerConnection(fromPeerId);
            final remainingStreams = _activeCall!.streams
                .where((s) => s.streamerId != fromPeerId)
                .toList();
            _activeCall = _activeCall!.copyWith(
              participants: _activeCall!.participants
                  .where((p) => p.userId != fromPeerId)
                  .toList(),
              streams: remainingStreams,
            );
            notifyListeners();
            break;
          }
          leaveCall(notifyServer: false);
        }
        if (_incomingCall != null &&
            (_incomingCall!.id == callId ||
                (chatId.isNotEmpty && _incomingCall!.chatId == chatId))) {
          final missedSession = _incomingCall!;
          _incomingCall = null;
          notifyListeners();
          if (reason != 'declined' &&
              reason != 'answered_elsewhere' &&
              missedSession.initiatorId != _currentUserId) {
            final callerPeer = missedSession.participants
                .where((p) => p.userId == missedSession.initiatorId)
                .firstOrNull;
            final callerName = callerPeer?.displayName.isNotEmpty == true
                ? callerPeer!.displayName
                : (missedSession.title.isNotEmpty
                    ? missedSession.title
                    : 'Собеседник');
            unawaited(
              NotificationService().showMissedCallNotification(
                callId: missedSession.id,
                chatId: missedSession.chatId,
                callerName: callerName,
                isVideo: missedSession.isVideo,
                isGroup:
                    missedSession.callType == 'group' ||
                    missedSession.callType == 'stage',
              ),
            );
          }
        }
        break;
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _ringingTimeoutTimer?.cancel();
    _timer?.cancel();
    _closeAllPeerConnections();
    if (_renderersInitialized) {
      localRenderer.dispose();
      remoteRenderer.dispose();
      screenShareRenderer.dispose();
    }
    super.dispose();
  }
}
