import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/avatar_editor_models.dart';
import 'package:theaver/screens/contacts/contact_edit_screen.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/contacts_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/services/websocket_service.dart';
import 'package:theaver/theme/app_theme.dart';
import 'package:theaver/utils/avatar_studio_renderer.dart';
import 'package:theaver/utils/image_utils.dart';
import 'package:theaver/utils/swipe_back_route.dart';
import 'package:theaver/widgets/avatar_editor/avatar_crop_canvas.dart';
import 'package:theaver/widgets/avatar_editor/avatar_emoji_constructor_view.dart';
import 'package:theaver/widgets/avatar_editor/avatar_rotation_dial.dart';
import 'package:theaver/widgets/avatar_editor/theav_avatar_editor_screen.dart';
import 'package:theaver/widgets/avatar_editor/theav_avatar_picker_sheet.dart';
import 'package:theaver/widgets/chat/suggested_photo_bubble_card.dart';
import 'package:theaver/widgets/profile/expandable_avatar.dart';
import 'package:theaver/widgets/profile/qr_code_dialog.dart';
import 'package:theaver/widgets/user/avatar_with_status.dart';

class _SyncAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _SyncAppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_SyncAppLocalizationsDelegate old) => false;
}

class _ForcedGlassProvider extends LiquidGlassProvider {
  _ForcedGlassProvider(this._forcedMode);

  final GlassMode _forcedMode;

  @override
  GlassMode get mode => _forcedMode;

  @override
  bool get enabled => _forcedMode != GlassMode.disabled;

  @override
  bool get isLite => _forcedMode == GlassMode.lite;

  @override
  bool get isFull => _forcedMode == GlassMode.full;

  @override
  bool get isSupported => true;
}

// 1x1 transparent PNG bytes for offline widget image requests.
final Uint8List _kDummyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWukAAAAASUVORK5CYII=',
);

class _FakeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpRequest();

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpRequest implements HttpClientRequest {
  final _FakeHeaders _headers = _FakeHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = false;

  @override
  bool bufferOutput = true;

  @override
  int contentLength = -1;

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async => _FakeHttpResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final _FakeHeaders _headers = _FakeHeaders();

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _kDummyPngBytes.length;

  @override
  HttpHeaders get headers => _headers;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => 'OK';

  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

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
    return Stream<List<int>>.fromIterable(<List<int>>[_kDummyPngBytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  String? value(String name) => null;

  @override
  void forEach(void Function(String name, List<String> values) action) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _expectNoTranslucentOpacityAboveGlass(WidgetTester tester) {
  final glassFinders = <Finder>[
    find.byType(LiquidGlassLens),
    find.byType(LiquidGlassMorph),
  ];

  for (final finder in glassFinders) {
    for (final element in finder.evaluate()) {
      if (element.widget is LiquidGlassLens) {
        bool insideMorph = false;
        element.visitAncestorElements((ancestor) {
          if (ancestor.widget is LiquidGlassMorph) {
            insideMorph = true;
            return false;
          }
          if (ancestor.widget is Scaffold || ancestor.widget is MaterialApp) {
            return false;
          }
          return true;
        });
        if (insideMorph) continue;
      }

      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is Scaffold || widget is MaterialApp) return false;
        if (widget is Opacity && widget.opacity < 1.0) {
          fail(
            'Forbidden translucent Opacity(${widget.opacity}) above glass $element',
          );
        }
        if (widget is FadeTransition) {
          fail('Forbidden FadeTransition above glass $element');
        }
        if (widget is ClipRRect) {
          fail('Forbidden ClipRRect above glass $element');
        }
        return true;
      });
    }
  }
}

Widget _wrapTestApp({
  required Widget home,
  GlassMode glassMode = GlassMode.disabled,
  Locale locale = const Locale('ru'),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProfileThemeProvider>.value(
        value: ProfileThemeProvider(),
      ),
      ChangeNotifierProvider<LiquidGlassProvider>.value(
        value: _ForcedGlassProvider(glassMode),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: const <Locale>[Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        _SyncAppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.dark(),
      home: home,
    ),
  );
}

Future<Uint8List> _createSyntheticPng({int width = 120, int height = 80}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF2563EB),
  );
  final ui.Picture pic = recorder.endRecording();
  final ui.Image img = await pic.toImage(width, height);
  final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

Future<Uint8List> _createSplitPng({int width = 240, int height = 120}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width * 0.5, height.toDouble()),
    Paint()..color = const Color(0xFF2563EB),
  );
  canvas.drawRect(
    Rect.fromLTWH(width * 0.5, 0, width * 0.5, height.toDouble()),
    Paint()..color = const Color(0xFFEF4444),
  );
  final ui.Picture pic = recorder.endRecording();
  final ui.Image img = await pic.toImage(width, height);
  final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

Future<Uint8List> _createCornerBadgePng({int size = 240}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = const Color(0xFFFF0000),
  );
  canvas.drawRect(
    Rect.fromLTWH(size * 0.70, size * 0.70, size * 0.25, size * 0.25),
    Paint()..color = const Color(0xFF00FF00),
  );
  final ui.Picture pic = recorder.endRecording();
  final ui.Image img = await pic.toImage(size, size);
  pic.dispose();
  try {
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    img.dispose();
  }
}

Future<ui.Image> _resolveProviderImage(ImageProvider provider) {
  final Completer<ui.Image> completer = Completer<ui.Image>();
  final ImageStream stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (ImageInfo info, bool _) {
      if (!completer.isCompleted) {
        completer.complete(info.image.clone());
      }
      stream.removeListener(listener);
    },
    onError: (Object err, StackTrace? st) {
      if (!completer.isCompleted) {
        completer.completeError(err, st);
      }
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HttpOverrides.global = _FakeHttpOverrides();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ContactsService.clearCache(clearDisk: true);
    await ContactsService.init(userId: '1');
  });

  group('1. AvatarStudio Models & Offscreen Rendering', () {
    test('AvatarShapeMask circle vs squircle preserves exact 0.30 community ratio', () {
      const rect = Rect.fromLTWH(0, 0, 100, 100);
      final circleRRect = AvatarShapeMask.circle.shapeRRect(rect);
      final squircleRRect = AvatarShapeMask.squircle.shapeRRect(rect);
      expect(circleRRect.tlRadiusX, 50.0);
      expect(squircleRRect.tlRadiusX, 30.0);
      expect(
        AvatarShapeMask.squircle.borderRadiusForSize(80),
        BorderRadius.circular(24.0),
      );
    });

    test('AvatarColorAdjustments generates 20-element matrix and preset filters differ from identity', () {
      const identity = AvatarColorAdjustments();
      expect(identity.isIdentity, isTrue);
      expect(identity.toColorMatrix().length, 20);

      final mono = AvatarFilterPreset.presets.firstWhere((p) => p.id == 'mono');
      expect(mono.adjustments.isIdentity, isFalse);
      expect(mono.adjustments.saturation, -1.0);
      expect(mono.adjustments.toColorMatrix().length, 20);
    });

    test('AvatarStudioGeometry computes 1:1 and original aspect crop rects & renders edited PNG/JPEG output', () async {
      final sourceBytes = await _createSyntheticPng(width: 240, height: 120);
      const originalState = AvatarStudioState(
        aspectMode: AvatarCropAspectMode.original,
        fineAngleDegrees: 10.0,
        flipHorizontal: true,
        adjustments: AvatarColorAdjustments(contrast: 0.25, vignette: 0.2),
      );
      final normRect = AvatarStudioGeometry.effectiveCropNormRect(
        originalState,
        const Size(240, 120),
      );
      expect(normRect.width, closeTo(1.0, 1e-3));
      expect(normRect.height, closeTo(0.5, 1e-3));

      final rendered = await AvatarStudioRenderer.renderEditedAvatar(
        sourceBytes: sourceBytes,
        sourceFileName: 'sample.png',
        state: const AvatarStudioState(
          aspectMode: AvatarCropAspectMode.square1x1,
          quarterTurns: 1,
        ),
        maxDimension: 512,
      );
      expect(rendered.bytes, isNotEmpty);
      expect(rendered.width, rendered.height);
      expect(rendered.width, lessThanOrEqualTo(512));
    });

    test('AvatarStudioRenderer.renderEmojiConstructorAvatar exports square 256x256 PNG', () async {
      const cfg = AvatarEmojiConstructorConfig(
        emoji: null,
        monogramText: 'TH',
        foregroundScale: 0.72,
        isRadial: true,
      );
      final output = await AvatarStudioRenderer.renderEmojiConstructorAvatar(
        config: cfg,
        size: 256,
      );
      expect(output.bytes, isNotEmpty);
      expect(output.width, 256);
      expect(output.height, 256);
    });
  });

  group('2. TheavAvatarEditorScreen & AvatarEmojiConstructorView (Glass & Matte)', () {
    testWidgets('Editor wraps canvas & dial in SwipeBackBlocker, supports tabs/aspect/undo, and has 0 forbidden opacity/clip wrappers above Glass', (tester) async {
      final Uint8List pngBytes = (await tester.runAsync(
        () => _createSyntheticPng(width: 180, height: 180),
      ))!;

      await tester.pumpWidget(
        _wrapTestApp(
          glassMode: GlassMode.full,
          home: TheavAvatarEditorScreen(
            initialBytes: pngBytes,
            fileName: 'avatar.png',
            maskShape: AvatarShapeMask.squircle,
            ctaMode: AvatarEditorCtaMode.setPhoto,
            subjectName: 'Сообщество',
          ),
        ),
      );

      for (int i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 25));
        if (find.byType(AvatarCropCanvas).evaluate().isNotEmpty) {
          break;
        }
      }
      await _pumpFrames(tester);

      expect(find.byType(AvatarCropCanvas), findsOneWidget);
      expect(find.byType(AvatarRotationDial), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AvatarCropCanvas),
          matching: find.byType(SwipeBackBlocker),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AvatarRotationDial),
          matching: find.byType(SwipeBackBlocker),
        ),
        findsOneWidget,
      );
      _expectNoTranslucentOpacityAboveGlass(tester);
      expect(
        find.byKey(const ValueKey<String>('avatar_editor_mini_circle_slider')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('avatar_mini_circle_resize_handle')),
        findsOneWidget,
      );

      // Verify aspect modes render cleanly (default is Оригинал; switch to 1:1 and Свободно).
      await tester.tap(find.text('1:1'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Оригинал'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Свободно'));
      await _pumpFrames(tester);

      // Switch to Color adjust tab and select Monochrome preset.
      await tester.tapAt(tester.getCenter(find.text('Коррекция').first));
      await _pumpFrames(tester);
      expect(find.text('Ч/Б'), findsOneWidget);

      // Switch to Stickers and Markup tabs.
      await tester.tapAt(tester.getCenter(find.text('Стикеры').first));
      await _pumpFrames(tester);
      await tester.tapAt(tester.getCenter(find.text('Рисунок').first));
      await _pumpFrames(tester);
      expect(find.text('Перо'), findsOneWidget);
      _expectNoTranslucentOpacityAboveGlass(tester);
    });

    testWidgets('TheavAvatarPickerSheet shows Constructor tab & AvatarEmojiConstructorView builds cleanly in GlassMode.full', (tester) async {
      await tester.pumpWidget(
        _wrapTestApp(
          glassMode: GlassMode.full,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    TheavAvatarPickerSheet.pickAndEdit(
                      context: ctx,
                      maskShape: AvatarShapeMask.squircle,
                      ctaMode: AvatarEditorCtaMode.done,
                      startInConstructor: true,
                      canDeleteCurrent: true,
                    );
                  },
                  child: const Text('Open Picker'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await _pumpFrames(tester);

      expect(find.byType(AvatarEmojiConstructorView), findsOneWidget);
      expect(find.text('Галерея'), findsOneWidget);
      expect(find.text('Конструктор'), findsWidgets);
      expect(find.text('Монограмма'), findsOneWidget);
      _expectNoTranslucentOpacityAboveGlass(tester);
    });
  });

  group('3. ContactEditScreen & SuggestedPhotoBubbleCard', () {
    testWidgets('ContactEditScreen renders Telegram-style layout for New Contact vs Edit Contact with custom photo reset preview', (tester) async {
      // Case A: Non-contact viewer ("Новый контакт", no custom photo).
      await tester.pumpWidget(
        _wrapTestApp(
          glassMode: GlassMode.full,
          home: const ContactEditScreen(
            key: ValueKey<String>('contact_edit_case_a'),
            userId: '42',
            isContact: false,
            username: 'alex_dev',
            originalDisplayName: 'Алексей',
            originalAvatarUrl: 'https://example.com/orig.png',
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(find.text('Новый контакт'), findsOneWidget);
      expect(find.text('Заметку видите только Вы.'), findsOneWidget);
      expect(find.text('Предложить фото для Алексей'), findsOneWidget);
      expect(find.text('Установить фото для Алексей'), findsOneWidget);
      expect(find.text('Вернуть исходное фото'), findsNothing);
      expect(find.text('Удалить контакт'), findsNothing);
      _expectNoTranslucentOpacityAboveGlass(tester);

      // Case B: Existing contact WITH custom photo -> shows reset row + real avatar preview + Delete Contact.
      await tester.pumpWidget(
        _wrapTestApp(
          glassMode: GlassMode.disabled,
          home: const ContactEditScreen(
            key: ValueKey<String>('contact_edit_case_b'),
            userId: '42',
            isContact: true,
            initialFirstName: 'Лёша',
            initialLastName: 'Работа',
            initialNote: 'Коллега по бэкенду',
            originalDisplayName: 'Алексей',
            originalAvatarUrl: 'https://example.com/orig.png',
            customAvatarUrl: 'https://example.com/custom.png',
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(find.text('Изменить контакт'), findsOneWidget);
      expect(find.text('Коллега по бэкенду'), findsOneWidget);
      expect(find.text('Вернуть исходное фото'), findsOneWidget);
      expect(find.text('Удалить контакт'), findsOneWidget);
      // 1 main 64dp header avatar + 1 small 28dp original avatar thumbnail on reset row.
      expect(find.byType(AvatarWithStatus), findsNWidgets(2));
    });

    testWidgets('SuggestedPhotoBubbleCard distinguishes sender vs recipient messages cleanly', (tester) async {
      final incomingSuggest = Message(
        id: '701',
        chatId: 'dm-1',
        senderId: '42',
        senderName: 'Мария',
        content: 'Предложено фото профиля',
        messageType: 'system',
        isEdited: false,
        createdAt: '2026-11-24T18:00:00Z',
        mediaPayload: const <String, dynamic>{
          'system_action': 'suggest_profile_photo',
          'photo_url': 'https://example.com/suggested.png',
          'suggester_id': '42',
          'suggester_name': 'Мария',
          'target_user_id': '1',
        },
      );

      final outgoingSuggest = Message(
        id: '702',
        chatId: 'dm-1',
        senderId: '1',
        senderName: 'Вы',
        content: 'Предложено фото профиля',
        messageType: 'system',
        isEdited: false,
        createdAt: '2026-11-24T18:05:00Z',
        isOwn: true,
        mediaPayload: const <String, dynamic>{
          'system_action': 'suggest_profile_photo',
          'photo_url': 'https://example.com/suggested2.png',
          'suggester_id': '1',
          'suggester_name': 'Вы',
          'target_user_id': '42',
        },
      );

      await tester.pumpWidget(
        _wrapTestApp(
          home: Scaffold(
            body: ListView(
              children: [
                SuggestedPhotoBubbleCard(
                  message: incomingSuggest,
                  currentUserId: '1',
                ),
                SuggestedPhotoBubbleCard(
                  message: outgoingSuggest,
                  currentUserId: '1',
                ),
              ],
            ),
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(
        find.text('Мария предлагает фото для вашего профиля'),
        findsOneWidget,
      );
      expect(find.text('Вы предложили фото профиля'), findsOneWidget);
      expect(find.text('Посмотреть фото'), findsNWidgets(2));
    });
  });

  group('4. ContactsService Per-Account Isolation & Override Events', () {
    test('isolates contacts and non-contact custom photo/note overrides across account switches', () async {
      await ContactsService.applyRemoteContactEvent(
        WebSocketEventType.contactUpdated,
        <String, dynamic>{
          'user_id': '99',
          'contact_user_id': '99',
          'is_contact': false,
          'original_display_name': 'Иван',
          'note': 'Личная заметка',
          'custom_avatar_url': 'https://example.com/custom99.png',
        },
      );

      // Override-only row must resolve name/avatar without polluting saved contactsNotifier!
      expect(ContactsService.isContactSync('99'), isFalse);
      expect(ContactsService.getSavedContacts(), isEmpty);
      expect(
        ContactsService.resolveAvatarUrl('99', 'https://example.com/public99.png'),
        'https://example.com/custom99.png',
      );
      expect(ContactsService.getCached('99')?.note, 'Личная заметка');

      await ContactsService.switchAccount('2');
      expect(ContactsService.getCached('99'), isNull);
      expect(
        ContactsService.resolveAvatarUrl('99', 'https://example.com/public99.png'),
        'https://example.com/public99.png',
      );

      await ContactsService.switchAccount('1');
      expect(ContactsService.getCached('99')?.note, 'Личная заметка');
      expect(
        ContactsService.resolveAvatarUrl('99', null),
        'https://example.com/custom99.png',
      );

      await ContactsService.applyRemoteContactEvent(
        WebSocketEventType.contactDeleted,
        <String, dynamic>{'contact_user_id': '99'},
      );
      expect(ContactsService.getCached('99'), isNull);
    });
  });

  group('5. Dual-Level Avatar Framing (#acrop=...)', () {
    test('AvatarCropSpec & getValidAvatarUrl preserve #acrop=... across normalization and strip clean URLs', () {
      const url = 'https://cdn.example.com/avatars/u/photo.jpg#acrop=0.5500,0.1000,0.4000,0.8000';
      final split = AvatarCropSpec.split(url);
      expect(split.cleanUrl, 'https://cdn.example.com/avatars/u/photo.jpg');
      expect(split.crop, isNotNull);
      expect(split.crop!.imageAspectRatio, closeTo(2.0, 1e-4));
      expect(stripAvatarCropFragment(url), 'https://cdn.example.com/avatars/u/photo.jpg');

      final rel = getValidAvatarUrl('/avatars/1/pic.jpg#acrop=0.25,0.1,0.4,0.3');
      expect(rel, isNotNull);
      expect(rel!, endsWith('/avatars/1/pic.jpg#acrop=0.2500,0.1000,0.4000,0.3000'));

      final badSplit = AvatarCropSpec.split('https://cdn.example.com/avatars/u/photo.jpg#acrop=0.9,0.9,0.5,0.5');
      expect(badSplit.crop, isNull);
    });

    test('AvatarSubregionImageProvider renders cropped coral square while avatarFullImageProvider preserves full 240x120 image', () async {
      final Uint8List splitBytes = await _createSplitPng(width: 240, height: 120);
      final Directory tmpDir = Directory.systemTemp.createTempSync('theaver_acrop_test_');
      try {
        final File imgFile = File('${tmpDir.path}/split.png');
        await imgFile.writeAsBytes(splitBytes, flush: true);
        final String taggedUrl = '${imgFile.path}#acrop=0.5500,0.1000,0.4000,0.8000';

        final ImageProvider? miniProvider =
            avatarImageProvider(taggedUrl, maxDecodeDimension: 120);
        final ImageProvider? fullProvider = avatarFullImageProvider(taggedUrl);
        expect(miniProvider, isA<AvatarSubregionImageProvider>());
        expect(fullProvider, isNotNull);

        final ui.Image miniImg = await _resolveProviderImage(miniProvider!);
        final ui.Image fullImg = await _resolveProviderImage(fullProvider!);
        try {
          expect(miniImg.width, miniImg.height);
          expect(fullImg.width, 240);
          expect(fullImg.height, 120);

          final ByteData? rgba =
              await miniImg.toByteData(format: ui.ImageByteFormat.rawRgba);
          expect(rgba, isNotNull);
          final int cx = miniImg.width ~/ 2;
          final int cy = miniImg.height ~/ 2;
          final int offset = (cy * miniImg.width + cx) * 4;
          final int r = rgba!.getUint8(offset);
          final int b = rgba.getUint8(offset + 2);
          // Sampled strictly from the right coral half (#EF4444), not the left blue half (#2563EB).
          expect(r, greaterThan(200));
          expect(b, lessThan(80));
        } finally {
          miniImg.dispose();
          fullImg.dispose();
        }
      } finally {
        if (await tmpDir.exists()) {
          await tmpDir.delete(recursive: true);
        }
      }
    });

    test('AvatarStudioRenderer preserves big outer photo and emits miniCrop + previewBytes when circle is shrunk', () async {
      final Uint8List splitBytes = await _createSplitPng(width: 240, height: 120);
      final rendered = await AvatarStudioRenderer.renderEditedAvatar(
        sourceBytes: splitBytes,
        sourceFileName: 'wide.png',
        state: const AvatarStudioState(
          aspectMode: AvatarCropAspectMode.original,
          miniCenterNorm: Offset(0.75, 0.35),
          miniSizeFrac: 0.40,
        ),
        maxDimension: 480,
      );
      try {
        expect(rendered.width, greaterThan(rendered.height));
        expect(rendered.miniCrop, isNotNull);
        expect(rendered.miniCrop!.imageAspectRatio, closeTo(2.0, 0.03));
        expect(rendered.miniCrop!.nw, closeTo(0.20, 0.02));
        expect(rendered.miniCrop!.nh, closeTo(0.40, 0.02));
        expect(rendered.previewBytes, isNotNull);
        expect(rendered.previewBytes!, isNotEmpty);
      } finally {
        if (rendered.file != null && await rendered.file!.exists()) {
          await rendered.file!.delete();
        }
      }
    });

    testWidgets('ExpandableAvatar renders #acrop=... seamlessly across expandFactor 0.0, 0.5, and 1.0', (tester) async {
      const taggedUrl =
          'https://example.com/full.jpg#acrop=0.2500,0.1000,0.4000,0.3000';
      for (final double factor in <double>[0.0, 0.5, 1.0]) {
        await tester.pumpWidget(
          _wrapTestApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 800,
                child: Center(
                  child: ExpandableAvatar(
                    avatarUrls: const <String>[taggedUrl],
                    expandFactor: factor,
                    displayName: 'Test',
                  ),
                ),
              ),
            ),
          ),
        );
        await _pumpFrames(tester);
        expect(tester.takeException(), isNull);
      }
    });

    test('AvatarSubregionImageProvider supports value equality and synchronous obtainKey', () {
      const cropA = AvatarCropSpec(nx: 0.25, ny: 0.15, nw: 0.40, nh: 0.40);
      const cropB = AvatarCropSpec(nx: 0.25, ny: 0.15, nw: 0.40, nh: 0.40);
      final ImageProvider base = MemoryImage(_kDummyPngBytes);
      final p1 = AvatarSubregionImageProvider(
        baseProvider: base,
        crop: cropA,
        targetDimension: 256,
      );
      final p2 = AvatarSubregionImageProvider(
        baseProvider: base,
        crop: cropB,
        targetDimension: 256,
      );
      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
      expect(
        p1.obtainKey(ImageConfiguration.empty),
        isA<SynchronousFuture<AvatarSubregionImageKey>>(),
      );
    });

    test('preferAvatarUrlWithCrop restores missing #acrop fragment from matching candidate URL', () {
      const bareUrl = 'https://cdn.example.com/avatars/u/pic.jpg';
      const taggedUrl =
          'https://cdn.example.com/avatars/u/pic.jpg#acrop=0.7000,0.7000,0.2500,0.2500';
      const otherTagged =
          'https://cdn.example.com/avatars/u/other.jpg#acrop=0.1000,0.1000,0.2000,0.2000';

      expect(
        preferAvatarUrlWithCrop(bareUrl, <String?>[otherTagged, taggedUrl]),
        taggedUrl,
      );
      expect(
        preferAvatarUrlWithCrop(bareUrl, <String?>[otherTagged]),
        bareUrl,
      );
    });

    testWidgets('QrCodeDialog renders the miniature #acrop circle rather than cropping the center of the outer photo', (tester) async {
      late Directory tmpDir;
      late String taggedUrl;
      await tester.runAsync(() async {
        tmpDir = Directory.systemTemp.createTempSync('theaver_qr_acrop_test_');
        final Uint8List pngBytes = await _createCornerBadgePng(size: 240);
        final File imgFile = File('${tmpDir.path}/qr_corner.png');
        await imgFile.writeAsBytes(pngBytes, flush: true);
        taggedUrl = '${imgFile.path}#acrop=0.7000,0.7000,0.2500,0.2500';
      });

      try {
        final GlobalKey boundaryKey = GlobalKey();
        await tester.pumpWidget(
          _wrapTestApp(
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: QrCodeDialog(
                    userId: '777',
                    displayName: 'Test User',
                    username: 'test_user',
                    avatarUrl: taggedUrl,
                  ),
                ),
              ),
            ),
          ),
        );

        for (int i = 0; i < 12; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
        expect(tester.takeException(), isNull);

        final Finder qrFinder = find.byType(PrettyQrView);
        expect(qrFinder, findsOneWidget);

        final RenderRepaintBoundary boundary =
            boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final Offset qrCenterGlobal = tester.getCenter(qrFinder);
        final Offset localCenter = boundary.globalToLocal(qrCenterGlobal);

        final int px = localCenter.dx.round();
        final int py = localCenter.dy.round();

        late ByteData? rgba;
        await tester.runAsync(() async {
          final ui.Image snapshot = await boundary.toImage(pixelRatio: 1.0);
          try {
            rgba = await snapshot.toByteData(format: ui.ImageByteFormat.rawRgba);
          } finally {
            snapshot.dispose();
          }
        });

        expect(rgba, isNotNull);
        final int width = boundary.size.width.round();
        final int offset = (py * width + px) * 4;
        final int r = rgba!.getUint8(offset);
        final int g = rgba!.getUint8(offset + 1);
        final int b = rgba!.getUint8(offset + 2);
        // Center of QR code must sample the green miniature circle (#00FF00), not the red center (#FF0000).
        expect(g, greaterThan(180), reason: 'rgba=($r,$g,$b) at ($px,$py) size=${boundary.size}');
        expect(r, lessThan(80), reason: 'rgba=($r,$g,$b) at ($px,$py) size=${boundary.size}');
        expect(b, lessThan(80), reason: 'rgba=($r,$g,$b) at ($px,$py) size=${boundary.size}');
      } finally {
        await tester.runAsync(() async {
          if (await tmpDir.exists()) {
            await tmpDir.delete(recursive: true);
          }
        });
      }
    });
  });
}
