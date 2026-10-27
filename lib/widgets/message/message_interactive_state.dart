import 'package:flutter/material.dart';
import 'spoiler_text_widget.dart';

/// Per-message interactive UI state (revealed inline/block spoilers, particle clouds,
/// and expanded/collapsed blockquotes) shared between the in-list message widget
/// and the focused message widget rendered above the blur backdrop.
class MessageInteractiveEntry extends ChangeNotifier {
  /// Revealed inline spoiler range IDs per inline host key (`'inline_$rangeStart'`).
  final Map<String, Set<int>> _revealedInlineSpoilers = {};

  /// Shared particle cloud per inline host key so particles keep their exact
  /// positions, velocities, and phases when separating the message for blur.
  final Map<String, Map<int, List<List<SpoilerParticle>>>>
      _inlineSpoilerParticles = {};

  /// Shared cached line boxes per inline host key so the first frame of the
  /// separated message can paint spoiler dust even before paragraph inspection.
  final Map<String, Map<int, List<Rect>>> _inlineSpoilerRects = {};

  /// Revealed state for block/media [SpoilerTextWidget] per stateKey.
  final Map<String, bool> _revealedBlockSpoilers = {};

  /// Shared particle cloud for block/media [SpoilerTextWidget] per stateKey.
  final Map<String, List<List<SpoilerParticle>>> _blockSpoilerParticles = {};

  /// Expanded state and animation progress for [CollapsibleBlockquoteWidget] per stateKey.
  final Map<String, bool> _expandedBlockquotes = {};
  final Map<String, double> _blockquoteProgress = {};

  bool isInlineSpoilerRevealed(String hostKey, int spoilerId) {
    return _revealedInlineSpoilers[hostKey]?.contains(spoilerId) ?? false;
  }

  Set<int> getRevealedInlineSpoilers(String hostKey) {
    return _revealedInlineSpoilers[hostKey] ?? const <int>{};
  }

  void markInlineSpoilerRevealed(String hostKey, int spoilerId) {
    final set = _revealedInlineSpoilers.putIfAbsent(hostKey, () => <int>{});
    if (set.add(spoilerId)) {
      notifyListeners();
    }
  }

  Map<int, List<List<SpoilerParticle>>> getInlineParticles(String hostKey) {
    return _inlineSpoilerParticles.putIfAbsent(
      hostKey,
      () => <int, List<List<SpoilerParticle>>>{},
    );
  }

  Map<int, List<Rect>> getInlineCachedRects(String hostKey) {
    return _inlineSpoilerRects.putIfAbsent(
      hostKey,
      () => <int, List<Rect>>{},
    );
  }

  bool? getBlockSpoilerRevealed(String stateKey) =>
      _revealedBlockSpoilers[stateKey];

  void setBlockSpoilerRevealed(String stateKey, bool revealed) {
    if (_revealedBlockSpoilers[stateKey] != revealed) {
      _revealedBlockSpoilers[stateKey] = revealed;
      notifyListeners();
    }
  }

  List<List<SpoilerParticle>> getBlockParticles(String stateKey) {
    return _blockSpoilerParticles.putIfAbsent(
      stateKey,
      () => <List<SpoilerParticle>>[],
    );
  }

  bool? getBlockquoteExpanded(String stateKey) =>
      _expandedBlockquotes[stateKey];

  double? getBlockquoteProgress(String stateKey) =>
      _blockquoteProgress[stateKey];

  void setBlockquoteExpanded(
    String stateKey,
    bool expanded, {
    double? progress,
  }) {
    final bool changed = _expandedBlockquotes[stateKey] != expanded;
    _expandedBlockquotes[stateKey] = expanded;
    _blockquoteProgress[stateKey] = progress ?? (expanded ? 1.0 : 0.0);
    if (changed) {
      notifyListeners();
    }
  }

  void updateBlockquoteProgress(String stateKey, double progress) {
    _blockquoteProgress[stateKey] = progress;
  }
}

/// In-memory store of [MessageInteractiveEntry] keyed by message ID.
class MessageInteractiveStateStore {
  static final MessageInteractiveStateStore _instance =
      MessageInteractiveStateStore._internal();
  factory MessageInteractiveStateStore() => _instance;
  MessageInteractiveStateStore._internal();

  static const int _kMaxEntries = 500;
  final Map<String, MessageInteractiveEntry> _entries = {};

  MessageInteractiveEntry entryFor(String messageKey) {
    final existing = _entries.remove(messageKey);
    if (existing != null) {
      // Re-insert to maintain LRU order
      _entries[messageKey] = existing;
      return existing;
    }
    if (_entries.length >= _kMaxEntries) {
      final oldestKey = _entries.keys.first;
      _entries.remove(oldestKey)?.dispose();
    }
    final created = MessageInteractiveEntry();
    _entries[messageKey] = created;
    return created;
  }

  @visibleForTesting
  void clear() {
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
  }
}

/// Inherited scope that binds all interactive descendants inside a message
/// (spoilers, expandable quotes, etc.) to a shared [MessageInteractiveEntry].
class MessageInteractiveScope extends InheritedWidget {
  final String messageKey;
  final MessageInteractiveEntry entry;

  MessageInteractiveScope({
    Key? key,
    required this.messageKey,
    required Widget child,
  })  : entry = MessageInteractiveStateStore().entryFor(messageKey),
        super(key: key, child: child);

  static MessageInteractiveEntry? maybeOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<MessageInteractiveScope>();
    return scope?.entry;
  }

  @override
  bool updateShouldNotify(covariant MessageInteractiveScope oldWidget) {
    return oldWidget.messageKey != messageKey || oldWidget.entry != entry;
  }
}
