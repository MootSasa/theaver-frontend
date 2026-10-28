import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'settings_service.dart';
import 'voice_playback_service.dart';

/// Manages proximity sensor monitoring, earpiece audio routing, and
/// Telegram-style "Raise to Listen" behavior for voice messages.
class ProximityAudioService {
  ProximityAudioService._internal() {
    _init();
  }
  static final ProximityAudioService instance = ProximityAudioService._internal();
  factory ProximityAudioService() => instance;

  static const MethodChannel _methodChannel =
      MethodChannel('app.theaver.messenger/proximity');
  static const EventChannel _eventChannel =
      EventChannel('app.theaver.messenger/proximity_events');

  StreamSubscription<dynamic>? _proximitySub;
  bool _isMonitoring = false;
  bool _isNear = false;
  bool _isEarpieceActive = false;
  bool _voiceListenerRegistered = false;

  final Map<String, Future<bool> Function()> _openChatCallbacks = {};
  String? _activeOpenChatId;

  bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get isNear => _isNear;
  bool get isEarpieceActive => _isEarpieceActive;

  void _init() {
    if (!isSupported) return;
    SettingsService().raiseToListenNotifier.addListener(_evaluateMonitoringState);
    Future.microtask(registerListeners);
  }

  void registerListeners() {
    if (!isSupported || _voiceListenerRegistered) return;
    _voiceListenerRegistered = true;
    VoicePlaybackService().addListener(_evaluateMonitoringState);
  }

  /// Registers an open chat screen so "Raise to Listen" can auto-start
  /// the first unlistened incoming voice message when the phone is raised to the ear.
  void registerOpenChat(
    String chatId, {
    required Future<bool> Function() onRaiseToListenFirstUnplayed,
  }) {
    if (!isSupported) return;
    _openChatCallbacks[chatId] = onRaiseToListenFirstUnplayed;
    _activeOpenChatId = chatId;
    _evaluateMonitoringState();
  }

  /// Unregisters an open chat screen when it is disposed or closed.
  void unregisterOpenChat(String chatId) {
    if (!isSupported) return;
    _openChatCallbacks.remove(chatId);
    if (_activeOpenChatId == chatId) {
      _activeOpenChatId =
          _openChatCallbacks.keys.isNotEmpty ? _openChatCallbacks.keys.last : null;
    }
    _evaluateMonitoringState();
  }

  void _evaluateMonitoringState() {
    if (!isSupported) return;
    final enabled = SettingsService().raiseToListen;
    final hasVoiceActive = VoicePlaybackService().hasActiveAudio;
    final hasOpenChat = _openChatCallbacks.isNotEmpty;

    final shouldMonitor = enabled && (hasVoiceActive || hasOpenChat);
    if (shouldMonitor && !_isMonitoring) {
      _startMonitoring();
    } else if (!shouldMonitor && _isMonitoring) {
      _stopMonitoring();
    }
  }

  Future<void> _startMonitoring() async {
    if (_isMonitoring || !isSupported) return;
    _isMonitoring = true;
    try {
      await _methodChannel.invokeMethod<bool>('startMonitoring');
      _proximitySub?.cancel();
      _proximitySub = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          final near = event == true;
          _onProximityChanged(near);
        },
        onError: (e) {
          debugPrint('[ProximityAudioService] event stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('[ProximityAudioService] startMonitoring error: $e');
      _isMonitoring = false;
    }
  }

  Future<void> _stopMonitoring() async {
    if (!_isMonitoring || !isSupported) return;
    _isMonitoring = false;
    _proximitySub?.cancel();
    _proximitySub = null;
    final wasNear = _isNear;
    _isNear = false;
    if (wasNear || _isEarpieceActive) {
      await setEarpieceMode(false);
    }
    try {
      await _methodChannel.invokeMethod<bool>('stopMonitoring');
    } catch (e) {
      debugPrint('[ProximityAudioService] stopMonitoring error: $e');
    }
  }

  Future<void> _onProximityChanged(bool near) async {
    if (_isNear == near) return;
    _isNear = near;

    if (!SettingsService().raiseToListen) {
      if (_isEarpieceActive) {
        await setEarpieceMode(false);
      }
      return;
    }

    final voiceService = VoicePlaybackService();

    if (near) {
      // Phone raised to ear
      if (voiceService.isPlaying) {
        // Mode A: Voice message is already playing -> switch output to earpiece
        await setEarpieceMode(true);
      } else if (voiceService.hasActiveAudio) {
        // Active paused voice message -> switch to earpiece and resume
        await setEarpieceMode(true);
        await voiceService.resumeVoice();
      } else if (_activeOpenChatId != null) {
        // Mode B ("Raise to Listen"): Auto-start first unlistened incoming voice message
        final callback = _openChatCallbacks[_activeOpenChatId!];
        if (callback != null) {
          await setEarpieceMode(true);
          final started = await callback();
          if (!started && !_isNear) {
            await setEarpieceMode(false);
          } else if (!started) {
            // Nothing unlistened to play -> restore normal audio routing
            await setEarpieceMode(false);
          }
        }
      }
    } else {
      // Phone moved away from ear -> pause active playback and restore speaker routing
      if (voiceService.isPlaying) {
        await voiceService.pauseVoice();
      }
      if (_isEarpieceActive) {
        await setEarpieceMode(false);
      }
    }
  }

  Future<void> setEarpieceMode(bool enabled) async {
    if (!isSupported) return;
    _isEarpieceActive = enabled;
    try {
      await _methodChannel.invokeMethod<bool>(
        'setEarpieceMode',
        {'enabled': enabled},
      );
    } catch (e) {
      debugPrint('[ProximityAudioService] setEarpieceMode($enabled) error: $e');
    }
  }
}
