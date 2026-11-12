import 'package:shared_preferences/shared_preferences.dart';

/// Cross-isolate de-duplication of shown notifications.
///
/// The same message can arrive via WebSocket and via push (FCM/HMS foreground
/// handler or the background isolate). Keys are kept in a bounded ring buffer in
/// SharedPreferences so the main and background isolates see each other's entries.
class NotificationDedupStore {
  NotificationDedupStore({this.capacity = 200, this.ttl = const Duration(minutes: 10)});

  static const String _prefsKey = 'notif_dedup_ring_v1';

  final int capacity;
  final Duration ttl;

  /// In-memory mirror for fast checks within one isolate.
  final Map<String, int> _memory = <String, int>{};

  /// Builds a dedup key. Message IDs are preferred; text is a fallback for
  /// payloads without an ID.
  static String keyFor({
    required String kind,
    required String chatId,
    String? messageId,
    String? fallbackText,
  }) {
    if (messageId != null && messageId.isNotEmpty) {
      return '$kind:$chatId:$messageId';
    }
    return '$kind:$chatId:t:${(fallbackText ?? '').hashCode}';
  }

  /// Returns true if [key] was already registered within [ttl]; otherwise
  /// registers it and returns false. Never throws.
  Future<bool> checkAndMark(String key, {DateTime? now}) async {
    final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final cutoff = ts - ttl.inMilliseconds;

    final mem = _memory[key];
    if (mem != null && mem >= cutoff) return true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final entries = parse(prefs.getStringList(_prefsKey) ?? const <String>[]);
      entries.removeWhere((_, t) => t < cutoff);
      if (entries.containsKey(key)) {
        _memory[key] = entries[key]!;
        return true;
      }
      entries[key] = ts;
      _memory[key] = ts;
      await prefs.setStringList(_prefsKey, serialize(entries, capacity));
    } catch (_) {
      _memory[key] = ts;
    }
    _memory.removeWhere((_, t) => t < cutoff);
    return false;
  }

  /// "key|timestamp" list -> map (insertion order preserved).
  static Map<String, int> parse(List<String> raw) {
    final result = <String, int>{};
    for (final item in raw) {
      final idx = item.lastIndexOf('|');
      if (idx <= 0) continue;
      final t = int.tryParse(item.substring(idx + 1));
      if (t == null) continue;
      result[item.substring(0, idx)] = t;
    }
    return result;
  }

  /// Keeps the newest [capacity] entries.
  static List<String> serialize(Map<String, int> entries, int capacity) {
    final sorted = entries.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final start = sorted.length > capacity ? sorted.length - capacity : 0;
    return sorted.sublist(start).map((e) => '${e.key}|${e.value}').toList();
  }
}
