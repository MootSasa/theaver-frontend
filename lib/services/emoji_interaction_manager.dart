/// Callback for triggering emoji playback.
typedef EmojiPlayCallback = void Function();

/// Visibility check callback.
typedef EmojiVisibilityCheck = bool Function();

class _RegisteredEmojiPlayer {
  final Object? owner;
  final EmojiVisibilityCheck isVisible;
  final EmojiPlayCallback play;

  _RegisteredEmojiPlayer({
    this.owner,
    required this.isVisible,
    required this.play,
  });
}

/// Service that coordinates synchronized real-time emoji playback across clients.
///
/// Ensures that animations, effects, and haptic feedback ONLY execute if
/// the target emoji message is currently visible on the user's screen.
class EmojiInteractionManager {
  static final EmojiInteractionManager instance = EmojiInteractionManager._internal();
  EmojiInteractionManager._internal();

  final Map<String, List<_RegisteredEmojiPlayer>> _players = {};

  /// Registers a mounted emoji widget's playback and visibility callbacks.
  void registerPlayer({
    required String messageId,
    required EmojiVisibilityCheck isVisible,
    required EmojiPlayCallback play,
    Object? owner,
  }) {
    if (messageId.isEmpty) return;
    final list = _players.putIfAbsent(messageId, () => <_RegisteredEmojiPlayer>[]);
    if (owner != null) {
      list.removeWhere((p) => identical(p.owner, owner));
    } else {
      list.clear();
    }
    list.add(_RegisteredEmojiPlayer(
      owner: owner,
      isVisible: isVisible,
      play: play,
    ));
  }

  /// Unregisters an unmounted emoji widget.
  void unregisterPlayer(String messageId, {Object? owner}) {
    if (messageId.isEmpty) return;
    if (owner == null) {
      _players.remove(messageId);
      return;
    }
    final list = _players[messageId];
    if (list == null) return;
    list.removeWhere((p) => identical(p.owner, owner));
    if (list.isEmpty) {
      _players.remove(messageId);
    }
  }

  /// Triggers synchronized playback if and only if the emoji is currently visible on screen.
  ///
  /// Returns `true` if the emoji was visible and triggered, `false` otherwise.
  bool trigger(String messageId) {
    if (messageId.isEmpty) return false;

    final list = _players[messageId];
    if (list == null || list.isEmpty) {
      // Message is not in the widget tree (e.g. not loaded or far out of view)
      return false;
    }

    bool triggeredAny = false;
    for (final player in List<_RegisteredEmojiPlayer>.of(list)) {
      if (player.isVisible()) {
        player.play();
        triggeredAny = true;
      }
    }
    return triggeredAny;
  }
}
