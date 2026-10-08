import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'video_note_playback_service.dart';
import 'media_cache_manager.dart';

/// Singleton service managing in-chat voice message playback, speed toggling, and auto-advance queue.
class VoicePlaybackService with ChangeNotifier {
  static final VoicePlaybackService _instance = VoicePlaybackService._internal();
  factory VoicePlaybackService() => _instance;

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;

  String? _activeMessageId;
  String? _activeAudioUrl;
  String? _activeSenderName;
  String? _activeChatId;
  String? _activeChatType;
  String? _activeChatTitle;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackSpeed = 1.0;

  void Function(String currentMessageId)? onPlayNextRequested;
  void Function(String messageId)? onScrollToMessageRequested;

  VoicePlaybackService._internal() {
    _initStreams();
  }

  String? get activeMessageId => _activeMessageId;
  String? get activeAudioUrl => _activeAudioUrl;
  String? get activeSenderName => _activeSenderName;
  String? get activeChatId => _activeChatId;
  String? get activeChatType => _activeChatType;
  String? get activeChatTitle => _activeChatTitle;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get playbackSpeed => _playbackSpeed;
  bool get hasActiveAudio => _activeMessageId != null;

  void _initStreams() {
    _stateSub = _player.playerStateStream.listen((state) {
      final playing = state.playing && state.processingState != ProcessingState.completed;
      final completed = state.processingState == ProcessingState.completed;

      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
      }

      if (completed) {
        final finishedId = _activeMessageId;
        _position = Duration.zero;
        _isPlaying = false;
        notifyListeners();

        if (finishedId != null) {
          debugPrint('[VoicePlaybackService] Voice note $finishedId completed, advancing...');
          if (onPlayNextRequested != null) {
            onPlayNextRequested!(finishedId);
          } else {
            stopVoice(finishedId);
          }
        }
      }
    });

    _posSub = _player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _durSub = _player.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });
  }

  /// Starts or resumes voice playback for a given message.
  Future<void> playVoice({
    required String messageId,
    required String audioUrl,
    String? senderName,
    Duration? initialDuration,
    String? chatId,
    String? chatType,
    String? chatTitle,
  }) async {
    // 1. Mute/stop any active round video note to prevent audio clash
    VideoNotePlaybackService().stopActivePlayback();

    if (_activeMessageId == messageId && _player.audioSource != null) {
      if (!_isPlaying) {
        await _player.play();
      }
      return;
    }

    _activeMessageId = messageId;
    _activeAudioUrl = audioUrl;
    if (senderName != null) _activeSenderName = senderName;
    if (chatId != null) _activeChatId = chatId;
    if (chatType != null) _activeChatType = chatType;
    if (chatTitle != null) _activeChatTitle = chatTitle;
    if (initialDuration != null) _duration = initialDuration;
    _position = Duration.zero;
    notifyListeners();

    try {
      String playPath = audioUrl;
      if (audioUrl.startsWith('http://') || audioUrl.startsWith('https://')) {
        final cached = await MediaCacheManager.instance.getCachedFile(audioUrl);
        if (cached != null && await cached.exists()) {
          playPath = cached.path;
        } else {
          // Play directly from URL immediately to prevent blocking playback.
          playPath = audioUrl;
          // Download in the background for future use.
          MediaCacheManager.instance.downloadMedia(audioUrl).catchError((_) => null);
        }
      }

      if (playPath.startsWith('http://') || playPath.startsWith('https://')) {
        await _player.setUrl(playPath);
      } else {
        final localFile = playPath.startsWith('file://')
            ? Uri.parse(playPath).toFilePath()
            : playPath;
        if (!await File(localFile).exists()) {
          debugPrint('[VoicePlaybackService] Local voice file not found: $localFile');
          stopVoice(messageId);
          return;
        }
        await _player.setFilePath(localFile);
      }
      await _player.setSpeed(_playbackSpeed);
      await _player.play();
    } catch (e) {
      debugPrint('[VoicePlaybackService] playVoice error: $e');
      stopVoice(messageId);
    }
  }

  /// Pauses the current voice note playback.
  Future<void> pauseVoice() async {
    if (_isPlaying) {
      await _player.pause();
    }
  }

  /// Resumes playback.
  Future<void> resumeVoice() async {
    if (_activeMessageId != null && !_isPlaying) {
      await _player.play();
    }
  }

  /// Toggles between play and pause.
  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pauseVoice();
    } else {
      await resumeVoice();
    }
  }

  /// Seeks to a specified position.
  Future<void> seekVoice(Duration targetPosition) async {
    _position = targetPosition;
    notifyListeners();
    try {
      await _player.seek(targetPosition);
    } catch (e) {
      debugPrint('[VoicePlaybackService] seekVoice error: $e');
    }
  }

  /// Cycles playback speed between 1.0X -> 1.5X -> 2.0X -> 1.0X.
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
      await _player.setSpeed(_playbackSpeed);
    } catch (_) {}
  }

  /// Sets an explicit playback speed.
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    notifyListeners();
    try {
      await _player.setSpeed(speed);
    } catch (_) {}
  }

  /// Stops voice playback and clears active message state.
  Future<void> stopVoice([String? messageId]) async {
    if (messageId != null && _activeMessageId != messageId) return;

    try {
      await _player.stop();
      await _player.seek(Duration.zero);
    } catch (_) {}

    _activeMessageId = null;
    _activeAudioUrl = null;
    _activeSenderName = null;
    _activeChatId = null;
    _activeChatType = null;
    _activeChatTitle = null;
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
  }

  /// Requests the active chat to scroll to the active voice message.
  void requestScrollToActive() {
    if (_activeMessageId != null) {
      onScrollToMessageRequested?.call(_activeMessageId!);
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
