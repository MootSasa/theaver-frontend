import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../config/app_config.dart';
import '../screens/chat/channel_screen.dart';
import '../screens/chat/group_chat_screen.dart';
import '../screens/chat/private_chat_screen.dart';
import '../widgets/message/video_message_widget.dart';
import 'deep_link_service.dart';
import 'media_cache_manager.dart';
import 'video_note_playback_service.dart';
import 'voice_playback_service.dart';

/// Single unified track item for voice messages and video notes («кружочки»).
class PlaybackTrack {
  final String messageId;
  final String chatId;
  final String chatType; // 'private', 'group', 'channel'
  final String mediaType; // 'voice', 'video_note'
  final String mediaUrl;
  final String? senderName;
  final String? chatTitle;
  final Duration? duration;
  final List<int>? waveform;

  const PlaybackTrack({
    required this.messageId,
    required this.chatId,
    required this.chatType,
    required this.mediaType,
    required this.mediaUrl,
    this.senderName,
    this.chatTitle,
    this.duration,
    this.waveform,
  });

  bool get isVoice => mediaType == 'voice';
  bool get isVideoNote => mediaType == 'video_note';
}

/// Central coordinator managing continuous cross-media autoplay,
/// persistent background queues, out-of-chat playback, and global navigation.
class MediaPlaybackCoordinator with ChangeNotifier {
  static final MediaPlaybackCoordinator _instance = MediaPlaybackCoordinator._internal();
  factory MediaPlaybackCoordinator() => _instance;
  static MediaPlaybackCoordinator get instance => _instance;

  static const String _kSpeedPrefKey = 'media_playback_speed';

  PlaybackTrack? _activeTrack;
  List<PlaybackTrack> _queue = [];
  double _playbackSpeed = 1.0;

  // Active chat in-screen scroll callback (non-null only when chat is mounted)
  void Function(String messageId)? onScrollToMessageRequested;
  // Callback registered by active chat to provide next track dynamically if queue is empty
  void Function(String currentMessageId)? onPlayNextRequested;
  // Callback registered by active chat to build playlist queue when starting playback
  List<PlaybackTrack> Function(String startMessageId)? onBuildPlaylistRequested;
  // Current active chatId opened in the viewport (to distinguish in-chat vs out-of-chat)
  String? currentForegroundChatId;

  MediaPlaybackCoordinator._internal() {
    _loadSavedSpeed();
    _bindServiceListeners();
  }

  PlaybackTrack? get activeTrack => _activeTrack;
  List<PlaybackTrack> get queue => List.unmodifiable(_queue);
  double get playbackSpeed => _playbackSpeed;
  bool get hasActiveMedia => _activeTrack != null;
  bool get isVoice => _activeTrack?.isVoice ?? false;
  bool get isVideoNote => _activeTrack?.isVideoNote ?? false;

  Future<void> _loadSavedSpeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_kSpeedPrefKey);
      if (saved != null && saved > 0) {
        _playbackSpeed = saved;
        VoicePlaybackService().setPlaybackSpeed(_playbackSpeed);
        VideoNotePlaybackService().setPlaybackSpeed(_playbackSpeed);
        notifyListeners();
      }
    } catch (_) {}
  }

  void _bindServiceListeners() {
    // When a voice note finishes, auto-advance via coordinator
    VoicePlaybackService().onPlayNextRequested = (finishedId) {
      onTrackCompleted(finishedId);
    };

    // When a video note finishes, auto-advance via coordinator
    VideoNotePlaybackService().onPlayNextRequested = (finishedId) {
      onTrackCompleted(finishedId);
    };
  }

  /// Sets global playback speed (1.0X, 1.5X, 2.0X) across all media notes and persists it.
  Future<void> cyclePlaybackSpeed() async {
    if (_playbackSpeed == 1.0) {
      _playbackSpeed = 1.5;
    } else if (_playbackSpeed == 1.5) {
      _playbackSpeed = 2.0;
    } else {
      _playbackSpeed = 1.0;
    }
    notifyListeners();

    VoicePlaybackService().setPlaybackSpeed(_playbackSpeed);
    VideoNotePlaybackService().setPlaybackSpeed(_playbackSpeed);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kSpeedPrefKey, _playbackSpeed);
    } catch (_) {}
  }

  /// Begins playing a track and registers the remaining playlist for continuous playback.
  Future<void> startPlayback({
    required PlaybackTrack track,
    List<PlaybackTrack>? remainingQueue,
  }) async {
    _activeTrack = track;
    if (remainingQueue != null) {
      _queue = List.from(remainingQueue);
    } else if (onBuildPlaylistRequested != null) {
      _queue = onBuildPlaylistRequested!(track.messageId);
    }
    notifyListeners();

    final resolvedUrl = AppConfig.resolveMediaUrl(track.mediaUrl) ?? track.mediaUrl;

    if (track.isVoice) {
      // 1. Voice playback
      VideoNotePlaybackService().stopActivePlayback();
      await VoicePlaybackService().playVoice(
        messageId: track.messageId,
        audioUrl: resolvedUrl,
        senderName: track.senderName,
        initialDuration: track.duration,
        chatId: track.chatId,
        chatType: track.chatType,
        chatTitle: track.chatTitle,
      );
    } else {
      // 2. Video note playback
      await VoicePlaybackService().stopVoice();
      final bool inForeground = currentForegroundChatId == track.chatId;
      final bool inView = inForeground && VideoNotePlaybackService().isMessageInView(track.messageId);

      final cached = VideoNoteControllerPool.get(resolvedUrl);
      if (cached != null && cached.value.isInitialized) {
        cached.seekTo(Duration.zero);
        cached.setLooping(false);
        cached.setVolume(1.0);
        cached.setPlaybackSpeed(_playbackSpeed);
        cached.play();

        VideoNotePlaybackService().setActivePlayback(
          messageId: track.messageId,
          videoUrl: resolvedUrl,
          controller: cached,
          senderName: track.senderName,
          chatId: track.chatId,
          chatType: track.chatType,
          chatTitle: track.chatTitle,
          initialInView: inView,
        );
      } else {
        final uri = Uri.tryParse(resolvedUrl);
        final isNetwork = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
        File? cachedDisk;
        if (isNetwork) {
          try {
            cachedDisk = await MediaCacheManager.instance.getCachedFile(resolvedUrl);
          } catch (_) {}
        }

        final VideoPlayerController ctrl;
        if (cachedDisk != null && await cachedDisk.exists()) {
          ctrl = VideoPlayerController.file(cachedDisk);
        } else if (isNetwork) {
          ctrl = VideoPlayerController.networkUrl(uri);
        } else {
          ctrl = VideoPlayerController.file(File(
            resolvedUrl.startsWith('file://')
                ? Uri.parse(resolvedUrl).toFilePath()
                : resolvedUrl,
          ));
        }

        try {
          await ctrl.initialize().timeout(const Duration(seconds: 10));
          ctrl.setLooping(false);
          ctrl.setVolume(1.0);
          ctrl.setPlaybackSpeed(_playbackSpeed);
          ctrl.play();

          VideoNoteControllerPool.put(resolvedUrl, ctrl);
          VideoNotePlaybackService().setActivePlayback(
            messageId: track.messageId,
            videoUrl: resolvedUrl,
            controller: ctrl,
            senderName: track.senderName,
            chatId: track.chatId,
            chatType: track.chatType,
            chatTitle: track.chatTitle,
            initialInView: inView,
          );
        } catch (e) {
          debugPrint('[MediaPlaybackCoordinator] Video note init error: $e');
          try {
            await ctrl.dispose();
          } catch (_) {}
          onTrackCompleted(track.messageId);
          return;
        }
      }
    }

    if (currentForegroundChatId == track.chatId) {
      onScrollToMessageRequested?.call(track.messageId);
    }
  }

  /// Automatically triggered when either a voice message or video note finishes.
  Future<void> onTrackCompleted(String finishedMessageId) async {
    if (_activeTrack == null || _activeTrack!.messageId != finishedMessageId) {
      return;
    }

    if (_queue.isNotEmpty) {
      final nextTrack = _queue.removeAt(0);
      debugPrint('[MediaPlaybackCoordinator] Advancing to next track: ${nextTrack.messageId} (${nextTrack.mediaType})');
      await startPlayback(track: nextTrack);
    } else if (onPlayNextRequested != null) {
      debugPrint('[MediaPlaybackCoordinator] Queue empty, requesting next from active chat...');
      onPlayNextRequested!(finishedMessageId);
    } else {
      debugPrint('[MediaPlaybackCoordinator] End of playback queue reached.');
      await stopAll();
    }
  }

  /// Toggles play / pause on the active media note.
  Future<void> togglePlayPause() async {
    if (_activeTrack == null) return;
    if (_activeTrack!.isVoice) {
      await VoicePlaybackService().togglePlayPause();
    } else {
      await VideoNotePlaybackService().togglePlayPause();
    }
  }

  /// Stops all media notes and clears active session and queue.
  Future<void> stopAll() async {
    _activeTrack = null;
    _queue.clear();
    await VoicePlaybackService().stopVoice();
    VideoNotePlaybackService().stopActivePlayback();
    notifyListeners();
  }

  /// Navigates to the originating chat and scrolls to the message.
  void navigateToActiveChat() {
    final track = _activeTrack;
    if (track == null) return;

    // 1. If chat is already in the foreground, simply scroll to message
    if (currentForegroundChatId == track.chatId && onScrollToMessageRequested != null) {
      onScrollToMessageRequested!(track.messageId);
      return;
    }

    // 2. Otherwise navigate to the target chat screen via root navigatorKey
    final nav = DeepLinkService().navigatorKey.currentState;
    if (nav == null) return;

    if (track.chatType == 'private') {
      nav.push(
        MaterialPageRoute(
          builder: (_) => PrivateChatScreen(
            chatId: track.chatId,
            otherUserName: track.chatTitle,
            initialMessageId: track.messageId,
          ),
        ),
      );
    } else if (track.chatType == 'group') {
      nav.push(
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(
            chatId: track.chatId,
            groupName: track.chatTitle,
            initialMessageId: track.messageId,
          ),
        ),
      );
    } else if (track.chatType == 'channel') {
      nav.push(
        MaterialPageRoute(
          builder: (_) => ChannelScreen(
            channelId: track.chatId,
            channelName: track.chatTitle,
            highlightMessageId: track.messageId,
          ),
        ),
      );
    }
  }
}
