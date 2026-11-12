import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/services/notifications/notification_decider.dart';

NotificationContext ctx({
  NotificationSource source = NotificationSource.websocket,
  String chatId = '42',
  bool own = false,
  bool chatOpen = false,
  bool foreground = true,
  bool allowed = true,
  bool foregroundEnabled = true,
  bool push = true,
  bool duplicate = false,
  bool desktopOrWeb = false,
}) =>
    NotificationContext(
      source: source,
      chatId: chatId,
      isOwnMessage: own,
      isChatOpen: chatOpen,
      isAppInForeground: foreground,
      isAllowedBySettings: allowed,
      foregroundNotificationsEnabled: foregroundEnabled,
      pushAvailable: push,
      isDuplicate: duplicate,
      isDesktopOrWeb: desktopOrWeb,
    );

void main() {
  group('decideNotification', () {
    test('foreground WebSocket message in chat list is shown as system notification', () {
      expect(decideNotification(ctx()), NotificationDecision.show);
    });

    test('own messages are never shown', () {
      expect(decideNotification(ctx(own: true)), NotificationDecision.skipOwnMessage);
    });

    test('open chat in foreground is suppressed', () {
      expect(decideNotification(ctx(chatOpen: true)), NotificationDecision.skipChatOpen);
    });

    test('open chat in background (minimized window) is shown', () {
      expect(
        decideNotification(ctx(chatOpen: true, foreground: false, desktopOrWeb: true)),
        NotificationDecision.show,
      );
    });

    test('muted chat is suppressed', () {
      expect(decideNotification(ctx(allowed: false)), NotificationDecision.skipMuted);
    });

    test('foreground notifications toggle off suppresses only foreground', () {
      expect(decideNotification(ctx(foregroundEnabled: false)),
          NotificationDecision.skipForegroundDisabled);
      expect(
        decideNotification(ctx(foregroundEnabled: false, foreground: false, push: false)),
        NotificationDecision.show,
      );
    });

    test('mobile background WebSocket copy is skipped when push will render it', () {
      expect(decideNotification(ctx(foreground: false)), NotificationDecision.skipPushWillRender);
    });

    test('mobile background without push service renders from WebSocket (KeepAlive)', () {
      expect(decideNotification(ctx(foreground: false, push: false)), NotificationDecision.show);
    });

    test('desktop/web always render WebSocket messages in background', () {
      expect(decideNotification(ctx(foreground: false, desktopOrWeb: true)), NotificationDecision.show);
    });

    test('foreground push copy is shown unless already shown', () {
      expect(decideNotification(ctx(source: NotificationSource.push)), NotificationDecision.show);
      expect(decideNotification(ctx(source: NotificationSource.push, duplicate: true)),
          NotificationDecision.skipDuplicate);
    });

    test('empty chat id is invalid', () {
      expect(decideNotification(ctx(chatId: '')), NotificationDecision.skipInvalid);
    });
  });
}
