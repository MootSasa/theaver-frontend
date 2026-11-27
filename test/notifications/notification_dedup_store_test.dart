import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/services/notifications/notification_dedup_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('first registration is not a duplicate, second one is', () async {
    final store = NotificationDedupStore();
    final key = NotificationDedupStore.keyFor(kind: 'msg', chatId: '1', messageId: '10');
    expect(await store.checkAndMark(key), isFalse);
    expect(await store.checkAndMark(key), isTrue);
  });

  test('entries are shared between store instances (isolates) via prefs', () async {
    final key = NotificationDedupStore.keyFor(kind: 'msg', chatId: '1', messageId: '11');
    expect(await NotificationDedupStore().checkAndMark(key), isFalse);
    expect(await NotificationDedupStore().checkAndMark(key), isTrue);
  });

  test('entries expire after ttl', () async {
    final store = NotificationDedupStore(ttl: const Duration(minutes: 1));
    final key = NotificationDedupStore.keyFor(kind: 'msg', chatId: '1', messageId: '12');
    final t0 = DateTime(2026, 1, 1, 12);
    expect(await store.checkAndMark(key, now: t0), isFalse);
    expect(await NotificationDedupStore(ttl: const Duration(minutes: 1))
        .checkAndMark(key, now: t0.add(const Duration(minutes: 2))), isFalse);
  });

  test('capacity keeps only the newest entries', () {
    final entries = <String, int>{for (var i = 0; i < 10; i++) 'k$i': i};
    final serialized = NotificationDedupStore.serialize(entries, 3);
    expect(NotificationDedupStore.parse(serialized).keys, <String>['k7', 'k8', 'k9']);
  });

  test('key falls back to text hash without message id', () {
    final a = NotificationDedupStore.keyFor(kind: 'msg', chatId: '1', fallbackText: 'hi');
    final b = NotificationDedupStore.keyFor(kind: 'msg', chatId: '1', fallbackText: 'hi');
    final c = NotificationDedupStore.keyFor(kind: 'msg', chatId: '1', fallbackText: 'yo');
    expect(a, b);
    expect(a == c, isFalse);
  });
}
