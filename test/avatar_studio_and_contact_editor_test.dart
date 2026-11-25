import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/avatar_editor_models.dart';
import 'package:theaver/models/community_models.dart';
import 'package:theaver/screens/contacts/contact_edit_screen.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/contacts_service.dart';
import 'package:theaver/services/database/app_database.dart';
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
import 'package:theaver/widgets/chat/message_reply_info.dart';
import 'package:theaver/widgets/chat/suggested_photo_bubble_card.dart';
import 'package:theaver/widgets/community/community_members_panel.dart';
import 'package:theaver/widgets/message/group_message_avatar_row.dart';
import 'package:theaver/widgets/profile/avatar_gallery_viewer.dart';
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
    await AppDatabase.closeAll();
    AppDatabase.setActiveUser('1');
    AppDatabase.setTestingInstance(
      '1',
      AppDatabase.forTesting(NativeDatabase.memory(), userId: '1'),
    );
    AppDatabase.setTestingInstance(
      '2',
      AppDatabase.forTesting(NativeDatabase.memory(), userId: '2'),
    );
    AppDatabase.setTestingInstance(
      'default',
      AppDatabase.forTesting(NativeDatabase.memory(), userId: 'default'),
    );
    await ContactsService.clearCache(clearDisk: true);
    await ContactsService.init(userId: '1');
  });

  tearDown(() async {
    await AppDatabase.closeAll();
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

  group('6. App-Wide Custom Contact Name & Avatar Propagation', () {
    test('shouldResolveUserIdentity & resolvePeer* guard self, personas, bots, and keep customAvatarUrl on remote updates', () async {
      await ContactsService.applyRemoteContactEvent(
        WebSocketEventType.contactUpdated,
        <String, dynamic>{
          'user_id': '42',
          'contact_user_id': '42',
          'is_contact': true,
          'custom_first_name': 'Друг',
          'custom_last_name': 'СорокДва',
          'original_display_name': 'Public 42',
          'original_avatar_url': 'https://example.com/orig42.png',
          'custom_avatar_url': 'https://example.com/custom42.png#acrop=0.1000,0.2000,0.5000,0.5000',
        },
      );
      await ContactsService.applyRemoteContactEvent(
        WebSocketEventType.contactUpdated,
        <String, dynamic>{
          'user_id': '77',
          'contact_user_id': '77',
          'is_contact': true,
          'is_bot': true,
          'custom_first_name': 'FakeBotOverride',
          'custom_avatar_url': 'https://example.com/bot_custom.png',
        },
      );

      // Guardrails: skip self ('1'), empty, '0', 'local', 'chat:*', channel persona, anon admin, mirrored post, bots.
      expect(ContactsService.shouldResolveUserIdentity('1'), isFalse);
      expect(ContactsService.shouldResolveUserIdentity(''), isFalse);
      expect(ContactsService.shouldResolveUserIdentity('0'), isFalse);
      expect(ContactsService.shouldResolveUserIdentity('local'), isFalse);
      expect(ContactsService.shouldResolveUserIdentity('chat:42'), isFalse);
      expect(
        ContactsService.shouldResolveUserIdentity('42', senderChatId: '900'),
        isFalse,
      );
      expect(
        ContactsService.shouldResolveUserIdentity('42', isAnonymousAdmin: true),
        isFalse,
      );
      expect(
        ContactsService.shouldResolveUserIdentity('42', isMirroredChannelPost: true),
        isFalse,
      );
      expect(
        ContactsService.shouldResolveUserIdentity('42', isBot: true),
        isFalse,
      );
      expect(ContactsService.shouldResolveUserIdentity('77'), isFalse);
      expect(ContactsService.shouldResolveUserIdentity('42'), isTrue);

      expect(
        ContactsService.resolvePeerName('42', 'Public 42'),
        'Друг СорокДва',
      );
      expect(
        ContactsService.resolvePeerName('42', 'Мой Канал', senderChatId: '900'),
        'Мой Канал',
      );
      expect(
        ContactsService.resolvePeerName('42', 'Админ', isAnonymousAdmin: true),
        'Админ',
      );
      expect(
        ContactsService.resolvePeerAvatarUrl(
          '42',
          'https://example.com/orig42.png',
        ),
        'https://example.com/custom42.png#acrop=0.1000,0.2000,0.5000,0.5000',
      );
      expect(
        ContactsService.resolvePeerAvatarUrl(
          '77',
          'https://example.com/bot_orig.png',
        ),
        'https://example.com/bot_orig.png',
      );

      // Remote user_avatar_updated must NOT overwrite customAvatarUrl, while refreshing originalAvatarUrl underneath.
      ContactsService.applyRemoteUserAvatarUpdate('42', '');
      expect(
        ContactsService.getCached('42')?.customAvatarUrl,
        'https://example.com/custom42.png#acrop=0.1000,0.2000,0.5000,0.5000',
      );
      ContactsService.applyRemoteUserAvatarUpdate(
        '42',
        'https://example.com/new_pub42.png',
      );
      expect(
        ContactsService.getCached('42')?.originalAvatarUrl,
        'https://example.com/new_pub42.png',
      );
      expect(
        ContactsService.resolvePeerAvatarUrl('42', null),
        'https://example.com/custom42.png#acrop=0.1000,0.2000,0.5000,0.5000',
      );
    });

    testWidgets('SenderHeaderRow & AvatarWithStatus update live on revisionNotifier while skipping personas & resolveContactOverride:false', (tester) async {
      await tester.pumpWidget(
        _wrapTestApp(
          home: const Scaffold(
            body: Column(
              children: [
                SenderHeaderRow(
                  senderId: '42',
                  senderName: 'Исходный Пользователь',
                  nameColor: Colors.blue,
                ),
                SenderHeaderRow(
                  senderId: '42',
                  senderChatId: '500',
                  senderName: 'Имя Канала',
                  nameColor: Colors.green,
                ),
                SenderHeaderRow(
                  senderId: '42',
                  isFromAnonymousAdmin: true,
                  senderName: 'Анонимный Админ',
                  nameColor: Colors.orange,
                ),
                AvatarWithStatus(
                  key: ValueKey('auto_avatar'),
                  userId: '42',
                  avatarUrl: 'https://example.com/orig42.jpg',
                  name: 'Исходный Пользователь',
                  showDecoration: false,
                ),
                AvatarWithStatus(
                  key: ValueKey('orig_preview_avatar'),
                  userId: '42',
                  avatarUrl: 'https://example.com/orig42.jpg',
                  name: 'Исходный Пользователь',
                  showDecoration: false,
                  resolveContactOverride: false,
                ),
              ],
            ),
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(find.text('Исходный Пользователь'), findsOneWidget);
      expect(find.text('Имя Канала'), findsOneWidget);
      expect(find.text('Анонимный Админ'), findsOneWidget);

      await tester.runAsync(
        () => ContactsService.applyRemoteContactEvent(
          WebSocketEventType.contactUpdated,
          <String, dynamic>{
            'user_id': '42',
            'contact_user_id': '42',
            'is_contact': true,
            'custom_first_name': 'Личное Имя 42',
            'custom_avatar_url':
                'https://example.com/custom42_live.jpg#acrop=0.2000,0.2000,0.4000,0.4000',
          },
        ),
      );
      await _pumpFrames(tester);

      expect(find.text('Личное Имя 42'), findsOneWidget);
      expect(find.text('Исходный Пользователь'), findsNothing);
      // Channel & anon-admin headers must remain untouched.
      expect(find.text('Имя Канала'), findsOneWidget);
      expect(find.text('Анонимный Админ'), findsOneWidget);

      final CircleAvatar autoCircle = tester.widget<CircleAvatar>(
        find.descendant(
          of: find.byKey(const ValueKey('auto_avatar')),
          matching: find.byType(CircleAvatar),
        ),
      );
      final CircleAvatar previewCircle = tester.widget<CircleAvatar>(
        find.descendant(
          of: find.byKey(const ValueKey('orig_preview_avatar')),
          matching: find.byType(CircleAvatar),
        ),
      );
      expect(autoCircle.backgroundImage, isA<AvatarSubregionImageProvider>());
      expect(
        previewCircle.backgroundImage,
        isNot(isA<AvatarSubregionImageProvider>()),
      );
    });

    testWidgets('CommunityMembersPane renders custom contact name & #acrop avatar, sorts by resolved name, and searches both names', (tester) async {
      await tester.runAsync(
        () => ContactsService.applyRemoteContactEvent(
          WebSocketEventType.contactUpdated,
          <String, dynamic>{
            'user_id': '42',
            'contact_user_id': '42',
            'is_contact': true,
            'custom_first_name': 'Алиса Кастомная',
            'original_display_name': 'Zack',
            'custom_avatar_url':
                'https://example.com/custom_member42.jpg#acrop=0.1000,0.1000,0.5000,0.5000',
          },
        ),
      );

      const role = CommunityRole(
        id: 'r1',
        communityId: 'c1',
        name: 'Модераторы',
        isHoisted: true,
        position: 10,
      );
      final community = Community(
        id: 'c1',
        name: 'Тестовое сообщество',
        roles: [role],
        createdAt: DateTime(2026, 1, 1),
      );
      final members = [
        const CommunityMember(
          userId: '43',
          username: 'boris',
          displayName: 'Борис',
          isOnline: true,
          roleIds: ['r1'],
        ),
        const CommunityMember(
          userId: '42',
          username: 'zack',
          displayName: 'Zack',
          originalDisplayName: 'Zack',
          avatarUrl: 'https://example.com/orig_member42.jpg',
          isOnline: true,
          roleIds: ['r1'],
        ),
        const CommunityMember(
          userId: '77',
          username: 'helper_bot',
          displayName: 'Хелпер Бот',
          isOnline: true,
          isBot: true,
          roleIds: ['r1'],
        ),
      ];

      final sections = groupMembersByHoistedRoles(members, [role]);
      expect(sections.first.members.map((m) => m.userId).toList(), ['42', '43', '77']);

      await tester.pumpWidget(
        _wrapTestApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              height: 600,
              child: CommunityMembersPane(
                community: community,
                members: members,
              ),
            ),
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(find.text('Алиса Кастомная'), findsOneWidget);
      expect(find.text('Борис'), findsOneWidget);
      expect(find.text('Хелпер Бот'), findsOneWidget);
      expect(find.text('Zack'), findsNothing);

      // Resolved name 'Алиса Кастомная' must appear above 'Борис'.
      expect(
        tester.getTopLeft(find.text('Алиса Кастомная')).dy,
        lessThan(tester.getTopLeft(find.text('Борис')).dy),
      );

      // Search by custom contact name.
      await tester.enterText(find.byType(TextField), 'Алиса');
      await _pumpFrames(tester);
      expect(find.text('Алиса Кастомная'), findsOneWidget);
      expect(find.text('Борис'), findsNothing);

      // Search by original display name also matches the renamed contact.
      await tester.enterText(find.byType(TextField), 'Zack');
      await _pumpFrames(tester);
      expect(find.text('Алиса Кастомная'), findsOneWidget);
      expect(find.text('Борис'), findsNothing);
    });

    testWidgets('Message.fromJson & MessageReplyInfo.forwarded separate user forwards from same-ID channel forwards', (tester) async {
      await tester.runAsync(
        () => ContactsService.applyRemoteContactEvent(
          WebSocketEventType.contactUpdated,
          <String, dynamic>{
            'user_id': '42',
            'contact_user_id': '42',
            'is_contact': true,
            'custom_first_name': 'Друг 42',
            'custom_avatar_url': 'https://example.com/cust42.jpg',
          },
        ),
      );

      final userForwardMsg = Message.fromJson(<String, dynamic>{
        'id': 'm1',
        'chat_id': '100',
        'sender_id': '2',
        'sender_name': 'Peer',
        'content': 'From friend',
        'message_type': 'text',
        'is_edited': false,
        'created_at': '2026-11-25T00:00:00Z',
        'is_forward': true,
        'forwarded_from_user_id': '42',
        'forwarded_from_name': 'Raw User 42',
        'forwarded_from_avatar_url': 'https://example.com/orig42.jpg',
      });

      final channelForwardMsg = Message.fromJson(<String, dynamic>{
        'id': 'm2',
        'chat_id': '100',
        'sender_id': '2',
        'sender_name': 'Peer',
        'content': 'From channel',
        'message_type': 'text',
        'is_edited': false,
        'created_at': '2026-11-25T00:00:00Z',
        'is_forward': true,
        'forwarded_from_chat_id': '42',
        'forwarded_from_name': 'Канал Новости',
        'forwarded_from_avatar_url': 'https://example.com/chan42.jpg',
      });

      expect(userForwardMsg.isForwardedFromChat, isFalse);
      expect(userForwardMsg.forwardedFromUserId, '42');
      expect(userForwardMsg.forwardFromName, 'Друг 42');
      expect(userForwardMsg.forwardFromAvatarUrl, 'https://example.com/cust42.jpg');

      // Channel ID '42' collides numerically with contact '42', yet must NEVER be overridden!
      expect(channelForwardMsg.isForwardedFromChat, isTrue);
      expect(channelForwardMsg.forwardedFromChatId, '42');
      expect(channelForwardMsg.forwardedFromUserId, isNull);
      expect(channelForwardMsg.forwardFromName, 'Канал Новости');
      expect(channelForwardMsg.forwardFromAvatarUrl, 'https://example.com/chan42.jpg');

      await tester.pumpWidget(
        _wrapTestApp(
          home: Scaffold(
            body: Column(
              children: [
                MessageReplyInfo.forwarded(
                  authorName: userForwardMsg.forwardFromName!,
                  authorAvatarUrl: userForwardMsg.forwardFromAvatarUrl,
                  authorUserId: userForwardMsg.forwardedFromUserId,
                  content: userForwardMsg.content,
                ),
                MessageReplyInfo.forwarded(
                  authorName: channelForwardMsg.forwardFromName!,
                  authorAvatarUrl: channelForwardMsg.forwardFromAvatarUrl,
                  authorUserId: channelForwardMsg.forwardedFromUserId,
                  content: channelForwardMsg.content,
                ),
              ],
            ),
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(find.textContaining('Друг 42'), findsOneWidget);
      expect(find.textContaining('Канал Новости'), findsOneWidget);

      await tester.runAsync(
        () => ContactsService.applyRemoteContactEvent(
          WebSocketEventType.contactUpdated,
          <String, dynamic>{
            'user_id': '42',
            'contact_user_id': '42',
            'is_contact': true,
            'custom_first_name': 'Обновлённый 42',
            'custom_avatar_url': 'https://example.com/cust42_v2.jpg',
          },
        ),
      );
      await _pumpFrames(tester);

      expect(find.textContaining('Обновлённый 42'), findsOneWidget);
      expect(find.textContaining('Канал Новости'), findsOneWidget);
    });
  });

  group('7. Profile Square Header vs Fullscreen Aspect Ratio', () {
    testWidgets('ExpandableAvatar crops portrait photo to 1:1 square in header and opens full original aspect ratio in AvatarGalleryViewer', (tester) async {
      late Directory tmpDir;
      late String taggedUrl;
      await tester.runAsync(() async {
        tmpDir = Directory.systemTemp.createTempSync('theaver_portrait_expand_');
        final Uint8List pngBytes =
            await _createSyntheticPng(width: 120, height: 240);
        final File imgFile = File('${tmpDir.path}/portrait.png');
        await imgFile.writeAsBytes(pngBytes, flush: true);
        taggedUrl = '${imgFile.path}#acrop=0.2500,0.1000,0.5000,0.2500';
      });

      try {
        await tester.pumpWidget(
          _wrapTestApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: const MediaQueryData(size: Size(300, 600)),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topCenter,
                    child: ExpandableAvatar(
                      avatarUrls: <String>[taggedUrl],
                      expandFactor: 1.0,
                      displayName: 'Portrait',
                      onTap: () => AvatarGalleryViewer.open(
                        context,
                        avatarUrls: <String>[taggedUrl],
                        displayName: 'Portrait',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _pumpFrames(tester);

        expect(tester.getSize(find.byType(ExpandableAvatar)), const Size(300, 300));
        final Positioned innerPos = tester.widget<Positioned>(
          find.descendant(
            of: find.byType(ExpandableAvatar),
            matching: find.byWidgetPredicate(
              (w) => w is Positioned && w.width == 300.0 && w.height == 600.0,
            ),
          ),
        );
        expect(innerPos.width, closeTo(300.0, 0.5));
        expect(innerPos.height, closeTo(600.0, 0.5));

        // Open fullscreen viewer & step cleanly through Hero flight and image decode.
        await tester.tap(find.byType(ExpandableAvatar));
        for (int i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 45));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
        expect(find.byType(AvatarGalleryViewer), findsOneWidget);
        expect(find.byType(PhotoViewGallery), findsOneWidget);

        final PhotoView photoView =
            tester.widget<PhotoView>(find.byType(PhotoView));
        expect(photoView.initialScale, PhotoViewComputedScale.contained);

        // Close fullscreen viewer back to the square profile header cleanly.
        await tester.tap(find.byIcon(Icons.arrow_back));
        for (int i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 45));
        }
        expect(find.byType(AvatarGalleryViewer), findsNothing);
        expect(tester.takeException(), isNull);
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
