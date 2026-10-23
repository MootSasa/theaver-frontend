/// Callback for triggering emoji playback.
typedef EmojiPlayCallback = void Function();

/// Visibility check callback.
typedef EmojiVisibilityCheck = bool Function();

class _RegisteredEmojiPlayer {
  final EmojiVisibilityCheck isVisible;
  final EmojiPlayCallback play;

  _RegisteredEmojiPlayer({
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

  final Map<String, _RegisteredEmojiPlayer> _players = {};

  /// Registers a mounted emoji widget's playback and visibility callbacks.
  void registerPlayer({
    required String messageId,
    required EmojiVisibilityCheck isVisible,
    required EmojiPlayCallback play,
  }) {
    if (messageId.isEmpty) return;
    _players[messageId] = _RegisteredEmojiPlayer(
      isVisible: isVisible,
      play: play,
    );
  }

  /// Unregisters an unmounted emoji widget.
  void unregisterPlayer(String messageId) {
    if (messageId.isEmpty) return;
    _players.remove(messageId);
  }

  /// Triggers synchronized playback if and only if the emoji is currently visible on screen.
  ///
  /// Returns `true` if the emoji was visible and triggered, `false` otherwise.
  bool trigger(String messageId) {
    if (messageId.isEmpty) return false;

    final player = _players[messageId];
    if (player == null) {
      // Message is not in the widget tree (e.g. not loaded or far out of view)
      return false;
    }

    if (!player.isVisible()) {
      // Message widget is mounted but scrolled off-screen
      return false;
    }

    player.play();
    return true;
  }
}
