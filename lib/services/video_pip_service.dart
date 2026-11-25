import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/theav_media_item.dart';
import 'media_playback_coordinator.dart';

/// Singleton managing the in-app floating video Picture-in-Picture (PiP) player.
///
/// Adopts the live [VideoPlayerController] directly from [TheavMediaViewer] (or
/// hands it back when returning to fullscreen) so playback continues at the exact
/// timestamp without re-buffering or recreating native decoder surfaces.
class VideoPipService extends ChangeNotifier {
  VideoPipService._internal();

  static final VideoPipService instance = VideoPipService._internal();
  factory VideoPipService() => instance;

  VideoPlayerController? _controller;
  TheavMediaItem? _item;
  List<TheavMediaItem> _playlist = const <TheavMediaItem>[];
  int _itemIndex = 0;
  TheavMediaViewerConfig? _viewerConfig;
  Offset? _floatingPosition;
  double _widthScale = 1.0;

  VideoPlayerController? get controller => _controller;
  TheavMediaItem? get item => _item;
  List<TheavMediaItem> get playlist => _playlist;
  int get itemIndex => _itemIndex;
  TheavMediaViewerConfig? get viewerConfig => _viewerConfig;
  bool get isActive => _controller != null && _item != null;
  bool get isPlaying => _controller?.value.isPlaying ?? false;
  bool get isMuted => (_controller?.value.volume ?? 1.0) <= 0.01;
  Offset? get floatingPosition => _floatingPosition;
  double get widthScale => _widthScale;

  double get aspectRatio {
    final c = _controller;
    if (c != null && c.value.isInitialized && c.value.aspectRatio > 0.1) {
      return c.value.aspectRatio.clamp(0.45, 2.4);
    }
    return (_item?.aspectRatio ?? (16.0 / 9.0)).clamp(0.45, 2.4);
  }

  /// Adopts [controller] for floating PiP display. Any previous PiP controller
  /// is disposed cleanly unless it is the exact same instance.
  Future<void> enterPip({
    required VideoPlayerController controller,
    required TheavMediaItem item,
    List<TheavMediaItem> playlist = const <TheavMediaItem>[],
    int itemIndex = 0,
    TheavMediaViewerConfig? viewerConfig,
  }) async {
    final prev = _controller;
    if (prev != null && !identical(prev, controller)) {
      try {
        await prev.pause();
      } catch (_) {}
      try {
        await prev.dispose();
      } catch (_) {}
    }

    _controller = controller;
    _item = item;
    _playlist = playlist.isNotEmpty
        ? List<TheavMediaItem>.unmodifiable(playlist)
        : <TheavMediaItem>[item];
    _itemIndex = playlist.isNotEmpty
        ? itemIndex.clamp(0, playlist.length - 1)
        : 0;
    _viewerConfig = viewerConfig;

    if (controller.value.volume > 0.01) {
      await MediaPlaybackCoordinator.instance.stopAll(stopVideoPip: false);
    }
    if (!controller.value.isPlaying) {
      try {
        await controller.play();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Detaches and returns the live [VideoPlayerController] if it matches
  /// [itemId] (or any active session when [itemId] is null) so fullscreen
  /// playback resumes instantaneously without disposing the decoder.
  VideoPlayerController? takeControllerForFullscreen(String? itemId) {
    final ctrl = _controller;
    final activeItem = _item;
    if (ctrl == null || activeItem == null) return null;
    if (itemId != null && itemId.isNotEmpty && activeItem.id != itemId) {
      return null;
    }
    _controller = null;
    _item = null;
    _playlist = const <TheavMediaItem>[];
    _itemIndex = 0;
    _viewerConfig = null;
    notifyListeners();
    return ctrl;
  }

  Future<void> togglePlayPause() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      await ctrl.pause();
    } else {
      if (ctrl.value.volume > 0.01) {
        await MediaPlaybackCoordinator.instance.stopAll(stopVideoPip: false);
      }
      if (ctrl.value.isInitialized &&
          ctrl.value.duration > Duration.zero &&
          ctrl.value.position >= ctrl.value.duration - const Duration(milliseconds: 250)) {
        await ctrl.seekTo(Duration.zero);
      }
      await ctrl.play();
    }
    notifyListeners();
  }

  Future<void> toggleMute() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    final bool currentlyMuted = ctrl.value.volume <= 0.01;
    if (currentlyMuted) {
      await MediaPlaybackCoordinator.instance.stopAll(stopVideoPip: false);
      await ctrl.setVolume(1.0);
    } else {
      await ctrl.setVolume(0.0);
    }
    notifyListeners();
  }

  Future<void> seekRelative(Duration delta) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final total = ctrl.value.duration;
    if (total <= Duration.zero) return;
    final nextMs = (ctrl.value.position + delta)
        .inMilliseconds
        .clamp(0, total.inMilliseconds);
    await ctrl.seekTo(Duration(milliseconds: nextMs));
  }

  Future<void> pause() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      try {
        await ctrl.pause();
      } catch (_) {}
      notifyListeners();
    }
  }

  void updatePosition(Offset position) {
    _floatingPosition = position;
  }

  void updateWidthScale(double scale) {
    final clamped = scale.clamp(0.75, 1.55);
    if ((clamped - _widthScale).abs() > 0.01) {
      _widthScale = clamped;
      notifyListeners();
    }
  }

  Future<void> close({bool disposeController = true}) async {
    final ctrl = _controller;
    final hadSession = ctrl != null || _item != null;
    _controller = null;
    _item = null;
    _playlist = const <TheavMediaItem>[];
    _itemIndex = 0;
    _viewerConfig = null;
    _floatingPosition = null;
    _widthScale = 1.0;

    if (ctrl != null && disposeController) {
      try {
        await ctrl.pause();
      } catch (_) {}
      try {
        await ctrl.dispose();
      } catch (_) {}
    }

    if (hadSession) {
      notifyListeners();
    }
  }
}
