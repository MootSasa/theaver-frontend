import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/widgets/message/message_bubble.dart';
import 'package:theaver/widgets/message/fullscreen_photo_viewer.dart';
import 'package:theaver/widgets/message/document_message_widget.dart';
import 'package:theaver/l10n/app_localizations.dart';

/// 1x1 transparent PNG for mock HTTP image responses
final Uint8List kTransparentImageBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _TestHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _TestHttpClientRequest();
}

class _TestHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _TestHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _TestHttpClientResponse();
}

class _TestHttpHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _TestHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => kTransparentImageBytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([kTransparentImageBytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _TestHttpClient();
}

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
  Future<AppLocalizations> load(Locale locale) async {
    return _TestAppLocalizations(locale, translations);
  }

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

Widget createTestApp(Widget child, {Map<String, String>? translations}) {
  return MaterialApp(
    localizationsDelegates: [
      _TestAppLocalizationsDelegate(translations ??
          {
            'chat_photo': 'Photo',
            'chat_video': 'Video',
            'chat_file': 'File',
            'chat_download': 'Download',
            'chat_open_file': 'Open File',
            'chat_file_not_found': 'File not found',
            'chat_edited': 'edited',
          }),
    ],
    home: Scaffold(
      body: child,
    ),
  );
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  group('Media Localization Tests', () {
    test('All 10 localization files contain all media bubble keys', () {
      final languages = ['ru', 'en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'pt', 'zh'];
      final requiredKeys = [
        'chat_photo',
        'chat_video',
        'chat_file',
        'chat_download',
        'chat_open_file',
        'chat_file_not_found',
      ];

      for (final lang in languages) {
        final file = File('assets/l10n/$lang.json');
        expect(file.existsSync(), isTrue, reason: 'File $lang.json must exist');

        final content = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        for (final key in requiredKeys) {
          expect(
            content.containsKey(key),
            isTrue,
            reason: 'Language $lang must contain key $key',
          );
          expect(
            (content[key] as String).isNotEmpty,
            isTrue,
            reason: 'Key $key in language $lang must not be empty',
          );
        }
      }
    });
  });

  group('DocumentMessageWidget Tests', () {
    testWidgets('Renders file name, formatted size, and action button', (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          const DocumentMessageWidget(
            fileUrl: 'https://example.com/docs/annual_report.pdf',
            fileName: 'annual_report.pdf',
            fileSize: 1024 * 1024 * 2.5, // 2.50 MB
          ),
        ),
      );
      await tester.pump();

      expect(find.text('annual_report.pdf'), findsOneWidget);
      expect(find.text('2.50 MB'), findsOneWidget);
      expect(find.byType(iconoir.Page), findsOneWidget);
      expect(find.byType(iconoir.Download), findsOneWidget);
    });
  });

  group('FullscreenPhotoViewer Tests', () {
    testWidgets('Renders image viewer and close button', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FullscreenPhotoViewer(
                        url: 'https://storage.theaver.app/files/photo.jpg',
                        tag: 'test_tag',
                      ),
                    ),
                  );
                },
                child: const Text('Open Viewer'),
              );
            },
          ),
        ),
      );

      // Tap button to open viewer
      await tester.tap(find.text('Open Viewer'));
      await tester.pumpAndSettle();

      expect(find.byType(FullscreenPhotoViewer), findsOneWidget);
      expect(find.byType(iconoir.Xmark), findsOneWidget);

      // Tap close button
      await tester.tap(find.byType(iconoir.Xmark));
      await tester.pumpAndSettle();

      expect(find.byType(FullscreenPhotoViewer), findsNothing);
    });
  });

  group('MessageBubble Media Integration Tests', () {
    testWidgets('Renders image bubble and allows tap to open viewer', (WidgetTester tester) async {
      final message = Message(
        id: 'msg-img-1',
        chatId: 'chat-1',
        senderId: 'user-1',
        content: '',
        messageType: 'photo',
        isEdited: false,
        createdAt: '2026-09-04T12:00:00Z',
        senderName: 'Alice',
        fileUrl: 'https://storage.theaver.app/files/sunset.jpg',
        fileName: 'sunset.jpg',
      );

      await tester.pumpWidget(
        createTestApp(
          MessageBubble(
            message: message,
            isMe: false,
            currentUserId: 'user-2',
            formatTime: (_) => '12:00',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should find Hero widget for photo
      expect(find.byType(Hero), findsOneWidget);
      // Floating metadata timestamp should be visible
      expect(find.text('12:00'), findsOneWidget);

      // Tap the photo Hero widget to trigger fullscreen viewer
      await tester.tap(find.byType(Hero));
      await tester.pumpAndSettle();

      // Fullscreen viewer opened
      expect(find.byType(FullscreenPhotoViewer), findsOneWidget);
    });

    testWidgets('Renders image with caption in same bubble', (WidgetTester tester) async {
      final message = Message(
        id: 'msg-img-2',
        chatId: 'chat-1',
        senderId: 'user-1',
        content: 'Check out this awesome view!',
        messageType: 'photo',
        isEdited: false,
        createdAt: '2026-09-04T12:05:00Z',
        senderName: 'Alice',
        fileUrl: 'https://storage.theaver.app/files/mountain.jpg',
        fileName: 'mountain.jpg',
      );

      await tester.pumpWidget(
        createTestApp(
          MessageBubble(
            message: message,
            isMe: true,
            currentUserId: 'user-1',
            formatTime: (_) => '12:05',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both image Hero and caption text rendered in the same bubble
      expect(find.byType(Hero), findsOneWidget);
      expect(find.text('Check out this awesome view!'), findsOneWidget);
      expect(find.text('12:05'), findsOneWidget);
    });

    testWidgets('Renders document message inside MessageBubble', (WidgetTester tester) async {
      final message = Message(
        id: 'msg-doc-1',
        chatId: 'chat-1',
        senderId: 'user-1',
        content: 'Project Specification.pdf',
        messageType: 'document',
        isEdited: false,
        createdAt: '2026-09-04T12:10:00Z',
        senderName: 'Bob',
        fileUrl: 'https://storage.theaver.app/files/Project_Specification.pdf',
        fileName: 'Project Specification.pdf',
      );

      await tester.pumpWidget(
        createTestApp(
          MessageBubble(
            message: message,
            isMe: false,
            currentUserId: 'user-2',
            formatTime: (_) => '12:10',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should render DocumentMessageWidget
      expect(find.byType(DocumentMessageWidget), findsOneWidget);
      expect(find.text('Project Specification.pdf'), findsOneWidget);
      expect(find.text('12:10'), findsOneWidget);
    });

    testWidgets('Renders audio player pill inside MessageBubble', (WidgetTester tester) async {
      final message = Message(
        id: 'msg-audio-1',
        chatId: 'chat-1',
        senderId: 'user-1',
        content: 'Voice note',
        messageType: 'audio',
        isEdited: false,
        createdAt: '2026-09-04T12:15:00Z',
        senderName: 'Charlie',
        fileUrl: 'https://storage.theaver.app/files/audio_record.mp3',
        fileName: 'audio_record.mp3',
      );

      await tester.pumpWidget(
        createTestApp(
          MessageBubble(
            message: message,
            isMe: false,
            currentUserId: 'user-2',
            formatTime: (_) => '12:15',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should render MusicNote icon and audio file name
      expect(find.byType(iconoir.MusicNote), findsOneWidget);
      expect(find.text('audio_record.mp3'), findsOneWidget);
      expect(find.text('12:15'), findsOneWidget);
    });
  });
}
