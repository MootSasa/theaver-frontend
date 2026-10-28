import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'video_note_playback_service.dart';
import 'media_cache_manager.dart';
import 'proximity_audio_service.dart';

/// Singleton service managing in-chat voice message playback, speed toggling,
/// background audio session, proximity earpiece routing, and auto-advance queue.
class VoicePlaybackService with ChangeNotifier {
  static final VoicePlaybackService _instance = VoicePlaybackService._internal();
  factory VoicePlaybackService() => _instance;

  static const MethodChannel _mediaSessionChannel =
      MethodChannel('app.theaver.messenger/media_session');

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  bool _audioSessionConfigured = false;
  bool _wasInterruptedWhilePlaying = false;
  DateTime _lastMediaSessionPosUpdate = DateTime.fromMillisecondsSinceEpoch(0);

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
    _initMediaSessionChannel();
    unawaited(_ensureAudioSessionConfigured());
    // Ensure ProximityAudioService is initialized
    ProximityAudioService.instance;
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

  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _ensureAudioSessionConfigured() async {
    if (_audioSessionConfigured || kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ),
      );

      _interruptionSub?.cancel();
      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              if (_isPlaying) {
                _wasInterruptedWhilePlaying = true;
                pauseVoice();
              }
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
            case AudioInterruptionType.pause:
              if (_wasInterruptedWhilePlaying) {
                _wasInterruptedWhilePlaying = false;
                resumeVoice();
              }
              break;
            case AudioInterruptionType.unknown:
              _wasInterruptedWhilePlaying = false;
              break;
          }
        }
      });

      _becomingNoisySub?.cancel();
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        // Headphones unplugged -> pause immediately
        if (_isPlaying) {
          pauseVoice();
        }
      });

      _audioSessionConfigured = true;
    } catch (e) {
      debugPrint('[VoicePlaybackService] AudioSession init error: $e');
    }
  }

  void _initMediaSessionChannel() {
    if (!_isMobilePlatform) return;
    _mediaSessionChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPlay':
          await resumeVoice();
          break;
        case 'onPause':
          await pauseVoice();
          break;
        case 'onTogglePlayPause':
          await togglePlayPause();
          break;
        case 'onNext':
          if (_activeMessageId != null && onPlayNextRequested != null) {
            onPlayNextRequested!(_activeMessageId!);
          }
          break;
        case 'onSeek':
          final args = call.arguments as Map?;
          final posMs = args?['positionMs'] as int?;
          if (posMs != null && posMs >= 0) {
            await seekVoice(Duration(milliseconds: posMs));
          }
          break;
        case 'onStop':
          await stopVoice();
          break;
      }
    });
  }

  void _syncMediaSession({bool force = false}) {
    if (!_isMobilePlatform) return;
    if (_activeMessageId == null) {
      _mediaSessionChannel.invokeMethod('clearSession').catchError((_) {});
      return;
    }
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastMediaSessionPosUpdate) <
            const Duration(milliseconds: 900)) {
      return;
    }
    _lastMediaSessionPosUpdate = now;

    final title = (_activeSenderName != null && _activeSenderName!.isNotEmpty)
        ? _activeSenderName!
        : 'Голосовое сообщение';
    final artist = (_activeChatTitle != null && _activeChatTitle!.isNotEmpty)
        ? _activeChatTitle!
        : 'Theaver';

    _mediaSessionChannel.invokeMethod('updateMetadata', {
      'title': title,
      'artist': artist,
      'durationMs': _duration.inMilliseconds,
      'positionMs': _position.inMilliseconds,
      'isPlaying': _isPlaying,
      'speed': _playbackSpeed,
    }).catchError((_) {});
  }

  void _initStreams() {
    _stateSub = _player.playerStateStream.listen((state) {
      final playing = state.playing && state.processingState != ProcessingState.completed;
      final completed = state.processingState == ProcessingState.completed;

      if (_isPlaying != playing) {
        _isPlaying = playing;
        _syncMediaSession(force: true);
        notifyListeners();
      }

      if (completed) {
        final finishedId = _activeMessageId;
        _position = Duration.zero;
        _isPlaying = false;
        _syncMediaSession(force: true);
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
      _syncMediaSession(force: false);
      notifyListeners();
    });

    _durSub = _player.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        _syncMediaSession(force: true);
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
    await _ensureAudioSessionConfigured();

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
    _syncMediaSession(force: true);
    notifyListeners();

    try {
      if (!kIsWeb) {
        final session = await AudioSession.instance;
        await session.setActive(true);
      }

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
      _syncMediaSession(force: true);
    } catch (e) {
      debugPrint('[VoicePlaybackService] playVoice error: $e');
      stopVoice(messageId);
    }
  }

  /// Pauses the current voice note playback.
  Future<void> pauseVoice() async {
    _wasInterruptedWhilePlaying = false;
    if (_isPlaying) {
      await _player.pause();
      _syncMediaSession(force: true);
    }
  }

  /// Resumes playback.
  Future<void> resumeVoice() async {
    if (_activeMessageId != null && !_isPlaying) {
      await _player.play();
      _syncMediaSession(force: true);
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
    _syncMediaSession(force: true);
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
    _syncMediaSession(force: true);
    notifyListeners();

    try {
      await _player.setSpeed(_playbackSpeed);
    } catch (_) {}
  }

  /// Sets an explicit playback speed.
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    _syncMediaSession(force: true);
    notifyListeners();
    try {
      await _player.setSpeed(speed);
    } catch (_) {}
  }

  /// Stops voice playback and clears active message state.
  Future<void> stopVoice([String? messageId]) async {
    if (messageId != null && _activeMessageId != messageId) return;

    _activeMessageId = null;
    _activeAudioUrl = null;
    _activeSenderName = null;
    _activeChatId = null;
    _activeChatType = null;
    _activeChatTitle = null;
    _isPlaying = false;
    _wasInterruptedWhilePlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _syncMediaSession(force: true);

    if (ProximityAudioService.instance.isEarpieceActive &&
        !ProximityAudioService.instance.isNear) {
      unawaited(ProximityAudioService.instance.setEarpieceMode(false));
    }

    try {
      await _player.stop();
      await _player.seek(Duration.zero);
    } catch (_) {}

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
    _interruptionSub?.cancel();
    _becomingNoisySub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
