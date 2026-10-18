import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Available actions triggered when swiping left on a chat in the chat list.
enum ChatSwipeAction {
  pin,
  read,
  archive,
  mute,
  delete;

  String get label {
    switch (this) {
      case ChatSwipeAction.pin:
        return 'Закрепить';
      case ChatSwipeAction.read:
        return 'Прочитать';
      case ChatSwipeAction.archive:
        return 'Архивировать';
      case ChatSwipeAction.mute:
        return 'Без звука';
      case ChatSwipeAction.delete:
        return 'Удалить';
    }
  }

  Color get color {
    switch (this) {
      case ChatSwipeAction.pin:
        return const Color(0xFFF59E0B); // Amber / orange
      case ChatSwipeAction.read:
        return const Color(0xFF3B82F6); // Telegram blue
      case ChatSwipeAction.archive:
        return const Color(0xFF06B6D4); // Cyan / teal
      case ChatSwipeAction.mute:
        return const Color(0xFF8B5CF6); // Purple
      case ChatSwipeAction.delete:
        return const Color(0xFFEF4444); // Red
    }
  }

  /// Archive and mute are kept as TODO per user requirement
  bool get isImplemented {
    switch (this) {
      case ChatSwipeAction.archive:
      case ChatSwipeAction.mute:
        return false;
      default:
        return true;
    }
  }
}

/// Service managing the user's preferred swipe-left action on chats.
class ChatSwipeService extends ChangeNotifier {
  ChatSwipeService._internal();
  static final ChatSwipeService _instance = ChatSwipeService._internal();
  factory ChatSwipeService() => _instance;

  static const String _prefKey = 'chat_swipe_left_action';
  ChatSwipeAction _action = ChatSwipeAction.read;
  bool _initialized = false;

  ChatSwipeAction get action => _action;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(_prefKey);
    if (savedName != null) {
      try {
        _action = ChatSwipeAction.values.byName(savedName);
      } catch (_) {
        _action = ChatSwipeAction.read;
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setAction(ChatSwipeAction newAction) async {
    if (_action == newAction) return;
    _action = newAction;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, newAction.name);
  }
}
