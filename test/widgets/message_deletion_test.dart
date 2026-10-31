import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/websocket_service.dart';
import 'package:theaver/widgets/chat/message_context_menu.dart';

class _TestAppLocalizations extends AppLocalizations {
  final Map<String, String> translations;
  _TestAppLocalizations(Locale locale, this.translations) : super(locale);

  @override
  String translate(String key, [Map<String, String>? params]) =>
      translations[key] ?? key;
}

class _TestAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  final Map<String, String> translations;
  const _TestAppLocalizationsDelegate([this.translations = const {}]);

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(
      _TestAppLocalizations(locale, translations),
    );
  }

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

final Map<String, String> _kRussianTranslations = {
  'chat_delete_message_title': 'Удалить сообщение',
  'chat_delete_message_confirm': 'Вы действительно хотите удалить это сообщение?',
  'chat_delete_for_everyone': 'Удалить для всех',
  'chat_delete_for_me': 'Удалить для меня',
  'chat_action_reply': 'Ответить',
  'chat_action_copy': 'Скопировать текст',
  'chat_action_pin': 'Закрепить',
  'chat_edit_message': 'Редактировать',
  'chat_action_delete': 'Удалить',
  'common_cancel': 'Отмена',
};

Widget createTestApp(Widget child, {Map<String, String>? translations}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LiquidGlassProvider()),
    ],
    child: MaterialApp(
      localizationsDelegates: [
        _TestAppLocalizationsDelegate(translations ?? _kRussianTranslations),
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  group('1.4 Localization keys verification for message deletion', () {
    final languages = ['ru', 'en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'pt', 'zh'];
    final requiredKeys = [
      'chat_delete_message_title',
      'chat_delete_message_confirm',
      'chat_delete_for_everyone',
      'chat_delete_for_me',
      'chat_action_reply',
      'chat_action_copy',
      'chat_action_pin',
      'chat_edit_message',
      'chat_action_delete',
    ];

    for (final lang in languages) {
      test('Language "$lang" contains all message deletion and context menu keys', () {
        final possiblePaths = [
          'assets/l10n/$lang.json',
          'frontend/assets/l10n/$lang.json',
          '../frontend/assets/l10n/$lang.json',
        ];

        File? file;
        for (final p in possiblePaths) {
          final f = File(p);
          if (f.existsSync()) {
            file = f;
            break;
          }
        }

        expect(file, isNotNull, reason: 'Localization file for $lang should exist');
        final content = file!.readAsStringSync();
        final jsonMap = jsonDecode(content) as Map<String, dynamic>;

        for (final key in requiredKeys) {
          expect(jsonMap.containsKey(key), isTrue,
              reason: 'Missing key "$key" in $lang.json');
          expect(jsonMap[key], isNotEmpty,
              reason: 'Key "$key" in $lang.json should not be empty');
        }
      });
    }
  });

  group('1.4 WebSocketEventType mapping for message deletion', () {
    test('Maps both message_deleted and delete_message to messageDeleted', () {
      final event1 = WebSocketEvent.fromJson({'type': 'message_deleted'});
      expect(event1.type, equals(WebSocketEventType.messageDeleted));

      final event2 = WebSocketEvent.fromJson({'type': 'delete_message'});
      expect(event2.type, equals(WebSocketEventType.messageDeleted));
    });
  });

  group('1.4 MessageContextMenu action callback tests', () {
    testWidgets('Renders localized Delete action and calls onDelete callback',
        (WidgetTester tester) async {
      bool deleteCalled = false;
      bool replyCalled = false;
      bool copyCalled = false;

      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => MessageContextMenu(
                        messageOffset: const Offset(50, 100),
                        messageSize: const Size(200, 50),
                        isMe: true,
                        onReply: () => replyCalled = true,
                        onCopy: () => copyCalled = true,
                        onPin: () {},
                        onEdit: () {},
                        onDelete: () => deleteCalled = true,
                        onReaction: (_) {},
                      ),
                    );
                  },
                  child: const Text('Open Menu'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open context menu
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      // Check that localized items appear
      expect(find.text('Ответить'), findsOneWidget);
      expect(find.text('Скопировать текст'), findsOneWidget);
      expect(find.text('Редактировать'), findsOneWidget);
      expect(find.text('Удалить'), findsOneWidget);

      // Tap Delete
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();

      expect(deleteCalled, isTrue);
      expect(replyCalled, isFalse);
      expect(copyCalled, isFalse);
    });
  });

  group('1.4 Message deletion confirmation dialog tests', () {
    testWidgets('Confirmation dialog presents localized title, text and triggers delete',
        (WidgetTester tester) async {
      bool confirmed = false;

      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await showDialog<bool>(
                      context: context,
                      builder: (dialogCtx) => AlertDialog(
                        title: Text(
                          AppLocalizations.of(dialogCtx)!.translate('chat_delete_message_title'),
                        ),
                        content: Text(
                          AppLocalizations.of(dialogCtx)!.translate('chat_delete_message_confirm'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(false),
                            child: Text(
                              AppLocalizations.of(dialogCtx)!.translate('common_cancel'),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(true),
                            child: Text(
                              AppLocalizations.of(dialogCtx)!.translate('chat_action_delete'),
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (result == true) {
                      confirmed = true;
                    }
                  },
                  child: const Text('Delete Message'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap delete trigger button
      await tester.tap(find.text('Delete Message'));
      await tester.pumpAndSettle();

      // Verify localized dialog texts
      expect(find.text('Удалить сообщение'), findsOneWidget);
      expect(find.text('Вы действительно хотите удалить это сообщение?'), findsOneWidget);
      expect(find.text('Отмена'), findsOneWidget);
      expect(find.text('Удалить'), findsOneWidget);

      // Confirm deletion
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();

      expect(confirmed, isTrue);
    });

    testWidgets('Cancelling deletion dialog does not trigger delete',
        (WidgetTester tester) async {
      bool confirmed = false;

      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await showDialog<bool>(
                      context: context,
                      builder: (dialogCtx) => AlertDialog(
                        title: Text(
                          AppLocalizations.of(dialogCtx)!.translate('chat_delete_message_title'),
                        ),
                        content: Text(
                          AppLocalizations.of(dialogCtx)!.translate('chat_delete_message_confirm'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(false),
                            child: Text(
                              AppLocalizations.of(dialogCtx)!.translate('common_cancel'),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(true),
                            child: Text(
                              AppLocalizations.of(dialogCtx)!.translate('chat_action_delete'),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (result == true) {
                      confirmed = true;
                    }
                  },
                  child: const Text('Delete Message'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete Message'));
      await tester.pumpAndSettle();

      // Tap Cancel
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();

      expect(confirmed, isFalse);
    });
  });
}
