import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'voice_playback_service.dart';

/// Global/chat playback coordination service for video notes («кружочки»).
/// Features:
/// - Single active playing video note at any time (with sound).
/// - Continuous playback queue: invokes [onPlayNextRequested] when current note finishes.
/// - Floating picture-in-picture (PiP): manages floating state & draggable coordinates
///   when the active video note scrolls out of the chat viewport.
class VideoNotePlaybackService with ChangeNotifier {
  static final VideoNotePlaybackService _instance = VideoNotePlaybackService._internal();
  factory VideoNotePlaybackService() => _instance;
  VideoNotePlaybackService._internal();

  String? _activeMessageId;
  String? _activeVideoUrl;
  String? _activeSenderName;
  String? _activeChatId;
  String? _activeChatType;
  String? _activeChatTitle;
  VideoPlayerController? _activeController;
  bool _isFloating = false;
  bool _isInView = true;
  Offset? _floatingPosition;
  final Set<String> _visibleMessageIds = <String>{};
  double _playbackSpeed = 1.0;
  
  // Callback registered by the active chat screen to advance to next video note
  void Function(String currentMessageId)? onPlayNextRequested;
  // Callback registered to scroll to the active message in chat
  void Function(String messageId)? onScrollToMessageRequested;

  String? get activeMessageId => _activeMessageId;
  String? get activeVideoUrl => _activeVideoUrl;
  String? get activeSenderName => _activeSenderName;
  String? get activeChatId => _activeChatId;
  String? get activeChatType => _activeChatType;
  String? get activeChatTitle => _activeChatTitle;
  VideoPlayerController? get activeController => _activeController;
  bool get isFloating => _isFloating && _activeController != null;
  bool get isInView => _isInView;
  Offset? get floatingPosition => _floatingPosition;
  double get playbackSpeed => _playbackSpeed;
  bool get hasActiveVideo => _activeMessageId != null && _activeController != null;
  bool isMessageInView(String messageId) => _visibleMessageIds.contains(messageId);

  void updateFloatingPosition(Offset newPos) {
    _floatingPosition = newPos;
    notifyListeners();
  }

  void setActivePlayback({
    required String messageId,
    required String videoUrl,
    required VideoPlayerController controller,
    String? senderName,
    String? chatId,
    String? chatType,
    String? chatTitle,
    bool? initialInView,
  }) {
    // 1. Mute/stop any active voice note to prevent audio clash
    VoicePlaybackService().stopVoice();

    if (_activeController != null && _activeController != controller) {
      _activeController!.removeListener(_onControllerTick);
      try {
        _activeController!.setVolume(0.0);
      } catch (_) {}
    }
    _activeMessageId = messageId;
    _activeVideoUrl = videoUrl;
    _activeController = controller;
    _activeController!.addListener(_onControllerTick);
    if (senderName != null) _activeSenderName = senderName;
    if (chatId != null) _activeChatId = chatId;
    if (chatType != null) _activeChatType = chatType;
    if (chatTitle != null) _activeChatTitle = chatTitle;

    try {
      controller.setPlaybackSpeed(_playbackSpeed);
    } catch (_) {}

    final bool inView;
    if (initialInView != null) {
      inView = initialInView;
    } else if (_isFloating) {
      // Preserve floating mode when advancing unless next note is explicitly visible on screen
      inView = _visibleMessageIds.contains(messageId);
    } else {
      inView = _visibleMessageIds.isEmpty ? true : _visibleMessageIds.contains(messageId);
    }
    _isInView = inView;
    _isFloating = !inView;
    notifyListeners();
  }

  Future<void> cyclePlaybackSpeed() async {
    if (_playbackSpeed == 1.0) {
      _playbackSpeed = 1.5;
    } else if (_playbackSpeed == 1.5) {
      _playbackSpeed = 2.0;
    } else {
      _playbackSpeed = 1.0;
    }
    notifyListeners();

    try {
      await _activeController?.setPlaybackSpeed(_playbackSpeed);
    } catch (_) {}
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    notifyListeners();
    try {
      await _activeController?.setPlaybackSpeed(speed);
    } catch (_) {}
  }

  Future<void> togglePlayPause() async {
    final ctrl = _activeController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      await ctrl.pause();
    } else {
      await ctrl.play();
    }
    notifyListeners();
  }

  void _onControllerTick() {
    final ctrl = _activeController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    
    final position = ctrl.value.position;
    final duration = ctrl.value.duration;
    final isFinished = (duration.inMilliseconds > 0) &&
        (position >= duration || (!ctrl.value.isPlaying && position >= duration - const Duration(milliseconds: 150)));
        
    if (isFinished && _activeMessageId != null) {
      final finishedId = _activeMessageId!;
      _activeController?.removeListener(_onControllerTick);
      onVideoCompleted(finishedId);
    }
  }

  void stopActivePlayback([String? messageId]) {
    if (messageId != null && _activeMessageId != messageId) return;
    if (_activeController != null) {
      _activeController!.removeListener(_onControllerTick);
      try {
        _activeController!.setVolume(0.0);
        _activeController!.pause();
        _activeController!.seekTo(Duration.zero);
      } catch (_) {}
    }
    _activeMessageId = null;
    _activeVideoUrl = null;
    _activeSenderName = null;
    _activeChatId = null;
    _activeChatType = null;
    _activeChatTitle = null;
    _activeController = null;
    _isFloating = false;
    _isInView = true;
    _floatingPosition = null;
    notifyListeners();
  }

  void clearVisibility() {
    _visibleMessageIds.clear();
  }

  void setInView(String messageId, bool inView) {
    if (inView) {
      _visibleMessageIds.add(messageId);
    } else {
      _visibleMessageIds.remove(messageId);
    }

    if (_activeMessageId == messageId) {
      if (_isInView != inView) {
        _isInView = inView;
        _isFloating = !inView && _activeController != null;
        notifyListeners();
      }
    }
  }

  void onVideoCompleted(String messageId) {
    if (_activeMessageId != messageId) return;
    debugPrint('[VideoNotePlaybackService] Video note $messageId completed, advancing...');
    if (onPlayNextRequested != null) {
      onPlayNextRequested!(messageId);
    } else {
      stopActivePlayback(messageId);
    }
  }

  void requestScrollToActive() {
    if (_activeMessageId != null && onScrollToMessageRequested != null) {
      onScrollToMessageRequested!(_activeMessageId!);
    }
  }
}
