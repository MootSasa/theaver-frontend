/// Pure decision logic: should an incoming chat message produce a system
/// notification on this device? Kept free of Flutter/plugin dependencies so it
/// can be unit tested (see test/notifications/notification_decider_test.dart).
library;

/// Where the message event came from.
enum NotificationSource {
  /// Realtime WebSocket event (app process alive).
  websocket,

  /// FCM/HMS message delivered to the running app (foreground handler).
  push,
}

/// Why a notification was (not) shown — used for logging and tests.
enum NotificationDecision {
  show,
  skipOwnMessage,
  skipChatOpen,
  skipMuted,
  skipForegroundDisabled,
  skipPushWillRender,
  skipDuplicate,
  skipInvalid,
}

class NotificationContext {
  const NotificationContext({
    required this.source,
    required this.chatId,
    required this.isOwnMessage,
    required this.isChatOpen,
    required this.isAppInForeground,
    required this.isAllowedBySettings,
    required this.foregroundNotificationsEnabled,
    required this.pushAvailable,
    required this.isDuplicate,
    this.isDesktopOrWeb = false,
  });

  final NotificationSource source;
  final String chatId;
  final bool isOwnMessage;

  /// The chat is visible on screen (open in a route/tile while the app/window is focused).
  final bool isChatOpen;
  final bool isAppInForeground;

  /// Global/per-chat settings allow it (not muted, mentions-only satisfied, ...).
  final bool isAllowedBySettings;

  /// "Показывать уведомления, когда приложение открыто".
  final bool foregroundNotificationsEnabled;

  /// The device has a working push service, so the server sends a push while backgrounded.
  final bool pushAvailable;

  /// The message ID was already shown (by another source or isolate).
  final bool isDuplicate;

  /// Desktop and Web have no push service: the WebSocket is always the source.
  final bool isDesktopOrWeb;
}

NotificationDecision decideNotification(NotificationContext c) {
  if (c.chatId.isEmpty) return NotificationDecision.skipInvalid;
  if (c.isOwnMessage) return NotificationDecision.skipOwnMessage;
  if (c.isChatOpen && c.isAppInForeground) {
    return NotificationDecision.skipChatOpen;
  }
  if (!c.isAllowedBySettings) return NotificationDecision.skipMuted;
  if (c.isAppInForeground && !c.foregroundNotificationsEnabled) {
    return NotificationDecision.skipForegroundDisabled;
  }
  // In background the server sends a push that the OS renders itself; rendering
  // the WebSocket copy as well would duplicate it.
  if (c.source == NotificationSource.websocket &&
      !c.isAppInForeground &&
      c.pushAvailable &&
      !c.isDesktopOrWeb) {
    return NotificationDecision.skipPushWillRender;
  }
  if (c.isDuplicate) return NotificationDecision.skipDuplicate;
  return NotificationDecision.show;
}
