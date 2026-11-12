import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One line of a MessagingStyle conversation notification.
class NotificationHistoryEntry {
  const NotificationHistoryEntry({
    required this.text,
    required this.senderName,
    required this.timestampMs,
    this.senderKey = '',
    this.isOwn = false,
    this.messageId,
  });

  final String text;
  final String senderName;
  final String senderKey;
  final int timestampMs;
  final bool isOwn;
  final String? messageId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': text,
        's': senderName,
        'k': senderKey,
        'ts': timestampMs,
        if (isOwn) 'o': true,
        if (messageId != null) 'id': messageId,
      };

  static NotificationHistoryEntry? fromJson(dynamic json) {
    if (json is! Map) return null;
    final text = json['t']?.toString() ?? '';
    if (text.isEmpty) return null;
    return NotificationHistoryEntry(
      text: text,
      senderName: json['s']?.toString() ?? '',
      senderKey: json['k']?.toString() ?? '',
      timestampMs: json['ts'] is int ? json['ts'] as int : int.tryParse('${json['ts']}') ?? 0,
      isOwn: json['o'] == true,
      messageId: json['id']?.toString(),
    );
  }
}

/// Recent messages per chat for conversation-style notifications. Persisted in
/// SharedPreferences so the background isolate (inline reply) can rebuild the
/// same notification. Cleared when the chat notification is cancelled.
class NotificationHistoryStore {
  NotificationHistoryStore._();

  static const int maxEntries = 7;
  static const String _prefix = 'notif_history_v1_';
  static const String _indexKey = 'notif_history_v1_index';

  static Future<List<NotificationHistoryEntry>> read(String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return _decode(prefs.getString('$_prefix$chatId'));
    } catch (_) {
      return <NotificationHistoryEntry>[];
    }
  }

  /// Appends [entry] (deduplicated by message ID) and returns the updated list.
  static Future<List<NotificationHistoryEntry>> append(
      String chatId, NotificationHistoryEntry entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final list = _decode(prefs.getString('$_prefix$chatId'));
      if (entry.messageId != null &&
          list.any((e) => e.messageId == entry.messageId)) {
        return list;
      }
      list.add(entry);
      while (list.length > maxEntries) {
        list.removeAt(0);
      }
      await prefs.setString(
          '$_prefix$chatId', jsonEncode(list.map((e) => e.toJson()).toList()));
      final index = prefs.getStringList(_indexKey) ?? <String>[];
      if (!index.contains(chatId)) {
        index.add(chatId);
        await prefs.setStringList(_indexKey, index);
      }
      return list;
    } catch (_) {
      return <NotificationHistoryEntry>[entry];
    }
  }

  static Future<void> clear(String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$chatId');
      final index = prefs.getStringList(_indexKey) ?? <String>[];
      if (index.remove(chatId)) {
        await prefs.setStringList(_indexKey, index);
      }
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getStringList(_indexKey) ?? <String>[];
      for (final chatId in index) {
        await prefs.remove('$_prefix$chatId');
      }
      await prefs.remove(_indexKey);
    } catch (_) {}
  }

  /// Chats that currently have a conversation notification.
  static Future<List<String>> activeChats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getStringList(_indexKey) ?? <String>[];
    } catch (_) {
      return <String>[];
    }
  }

  static List<NotificationHistoryEntry> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <NotificationHistoryEntry>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <NotificationHistoryEntry>[];
      return decoded
          .map(NotificationHistoryEntry.fromJson)
          .whereType<NotificationHistoryEntry>()
          .toList();
    } catch (_) {
      return <NotificationHistoryEntry>[];
    }
  }
}
