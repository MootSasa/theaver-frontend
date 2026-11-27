import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/models/profile_customization.dart';
import 'package:theaver/services/account_manager.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/groups_channels_parity_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/services/tiling_layout_controller.dart';
import 'package:theaver/theme/app_theme.dart';
import 'package:theaver/widgets/chat/channel_bottom_capsule_bar.dart';
import 'package:theaver/widgets/chat/channel_post_card.dart';
import 'package:theaver/widgets/chat/chat_input_bar.dart';
import 'package:theaver/widgets/chat/chat_selection_header.dart';
import 'package:theaver/widgets/chat/groups_channels_parity_widgets.dart';
import 'package:theaver/widgets/chat/liquid_glass_input_field.dart';
import 'package:theaver/widgets/message/group_message_avatar_row.dart';
import 'package:theaver/widgets/tiling/tile_viewport_scope.dart';

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

void _expectNoTranslucentOpacityAboveGlass(WidgetTester tester) {
  final glassFinders = <Finder>[
    find.byType(LiquidGlassLens),
    find.byType(LiquidGlassMorph),
  ];

  for (final finder in glassFinders) {
    for (final element in finder.evaluate()) {
      // Skip internal measurement lenses owned by package:liquid_glass_easy's
      // LiquidGlassMorph; ancestors above LiquidGlassMorph are checked directly
      // when iterating find.byType(LiquidGlassMorph).
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

void _expectZeroLayoutExceptions(WidgetTester tester, String contextLabel) {
  final Object? err = tester.takeException();
  expect(
    err,
    isNull,
    reason: 'Unexpected layout/overflow exception during $contextLabel: $err',
  );
}

Widget _wrapTestApp({
  required Widget home,
  GlassMode glassMode = GlassMode.disabled,
  Locale locale = const Locale('ru'),
  double textScale = 1.0,
}) {
  return ChangeNotifierProvider<LiquidGlassProvider>.value(
    value: _ForcedGlassProvider(glassMode),
    child: MaterialApp(
      locale: locale,
      supportedLocales: const <Locale>[Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.dark(),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: home,
    ),
  );
}

class _RecordedHttpCall {
  final String method;
  final Uri uri;
  final Map<String, dynamic> body;

  const _RecordedHttpCall({
    required this.method,
    required this.uri,
    required this.body,
  });
}

class _MockSendAsHttpOverrides extends HttpOverrides {
  final List<_RecordedHttpCall> calls = <_RecordedHttpCall>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient(calls);
  }
}

class _MockHttpClient implements HttpClient {
  _MockHttpClient(this._calls);

  final List<_RecordedHttpCall> _calls;

  @override
  bool autoUncompress = true;

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  int? maxConnectionsPerHost;

  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    return _MockHttpClientRequest(method: method, uri: url, calls: _calls);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  _MockHttpClientRequest({
    required this.method,
    required this.uri,
    required List<_RecordedHttpCall> calls,
  }) : _calls = calls;

  @override
  final String method;

  @override
  final Uri uri;

  final List<_RecordedHttpCall> _calls;
  final BytesBuilder _buffer = BytesBuilder();
  final _MockHttpHeaders _headers = _MockHttpHeaders();

  @override
  Encoding encoding = utf8;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  int contentLength = -1;

  @override
  bool bufferOutput = true;

  @override
  HttpHeaders get headers => _headers;

  @override
  void add(List<int> data) {
    _buffer.add(data);
  }

  @override
  void write(Object? object) {
    if (object != null) {
      _buffer.add(encoding.encode(object.toString()));
    }
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _buffer.add(chunk);
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    final rawText = utf8.decode(_buffer.takeBytes(), allowMalformed: true);
    Map<String, dynamic> parsed = const <String, dynamic>{};
    if (rawText.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawText);
        if (decoded is Map) {
          parsed = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    _calls.add(_RecordedHttpCall(method: method, uri: uri, body: parsed));

    final payload = utf8.encode(jsonEncode(<String, dynamic>{'success': true}));
    return _MockHttpClientResponse(statusCode: 200, bodyBytes: payload);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _MockHttpClientResponse({
    required this.statusCode,
    required List<int> bodyBytes,
  }) : _bodyBytes = bodyBytes;

  @override
  final int statusCode;

  final List<int> _bodyBytes;
  final _MockHttpHeaders _headers = _MockHttpHeaders();

  @override
  int get contentLength => _bodyBytes.length;

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
    return Stream<List<int>>.fromIterable(<List<int>>[_bodyBytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = <String>[value.toString()];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values
        .putIfAbsent(name.toLowerCase(), () => <String>[])
        .add(value.toString());
  }

  @override
  String? value(String name) {
    final list = _values[name.toLowerCase()];
    return (list != null && list.isNotEmpty) ? list.first : null;
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'accounts': <String>[
        jsonEncode(<String, dynamic>{
          'userId': '1',
          'token': 'test_jwt_token',
          'username': 'tester',
          'displayName': 'Test User',
          'lastLogin': DateTime.utc(2026, 11, 24).toIso8601String(),
        }),
      ],
      'current_account_id': '1',
      'current_device_id': 'test_device_1',
    });
    await SettingsService().init();
    await AccountManager().init();
    TilingLayoutController.instance.closeAllChats();
  });

  group('1. ChannelPostCard Responsive Width & Metadata Overflow Matrix', () {
    testWidgets(
      'Renders with 0 RenderFlex overflows across 240, 280, 320, 375, 390, and 430 widths with share button, views, forwards, silent bell, edited label, and long signature',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.devicePixelRatio = 1.0;

        final postMessage = Message(
          id: '901',
          chatId: '700',
          senderId: '0',
          senderName: 'Theaver Official News',
          content:
              'Крупное обновление каналов и групп: встроенный колокольчик беззвучной публикации и выбор профиля отправки прямо в поле ввода.',
          messageType: 'text',
          isEdited: true,
          createdAt: '2026-11-24T12:00:00Z',
          viewsCount: 128450,
          forwardsCount: 4920,
          isSilent: true,
          commentsCount: 34,
          canComment: true,
          reactions: const <String, int>{'👍': 42, '🔥': 19},
          authorSignature:
              'Главный редактор международного отдела аналитики и расследований',
        );

        const widths = <double>[240, 280, 320, 375, 390, 430];

        for (final width in widths) {
          for (final textScale in <double>[1.0, if (width <= 320) 1.3]) {
            tester.view.physicalSize = Size(width, 840);

            await tester.pumpWidget(
              _wrapTestApp(
                textScale: textScale,
                home: Scaffold(
                  body: SizedBox(
                    width: width,
                    height: 840,
                    child: TileViewportScope(
                      tileId: 'tile_$width',
                      isChatTile: true,
                      child: SingleChildScrollView(
                        child: ChannelPostCard(
                          message: postMessage,
                          currentUserId: '1',
                          channelName: 'Theaver Official News',
                          signMessages: true,
                          showAuthorProfiles: false,
                          linkedChatId: '701',
                          hasProtectedContent: false,
                          isSelectionMode: false,
                          onShareTap: () {},
                          onCommentsTap: () {},
                          onReactionTap: (_) {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            _expectZeroLayoutExceptions(
              tester,
              'ChannelPostCard width=$width textScale=$textScale',
            );

            // Verify quick-share ("Переслать") icon button and silent bell are rendered inside viewport bounds.
            expect(find.byType(iconoir.ShareIos), findsOneWidget);
            expect(find.byType(iconoir.BellOff), findsOneWidget);
            final shareRect = tester.getRect(find.byType(iconoir.ShareIos));
            expect(
              shareRect.right,
              lessThanOrEqualTo(width + 0.5),
              reason: 'Share button must stay inside viewport at width=$width',
            );
          }
        }
      },
    );
  });

  group('2. ChatMessageSelectionHeader 2 -> 1 Transition & Narrow Widths', () {
    testWidgets(
      'Transitions 2 -> 1 selected messages with "Переслать" across 260dp, 290dp, and 390dp widths with 0 overflow and localized tooltips',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.devicePixelRatio = 1.0;

        for (final width in const <double>[260, 290, 390]) {
          tester.view.physicalSize = Size(width, 600);
          int selectedCount = 2;

          await tester.pumpWidget(
            StatefulBuilder(
              builder: (context, setState) {
                return _wrapTestApp(
                  locale: const Locale('ru'),
                  home: Scaffold(
                    body: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: width,
                        child: TileViewportScope(
                          tileId: 'sel_$width',
                          isChatTile: true,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: ChatMessageSelectionHeader(
                              selectedCount: selectedCount,
                              onCancel: () {},
                              onReply: selectedCount == 1 ? () {} : null,
                              onCopy: () {},
                              onPin: selectedCount == 1 ? () {} : null,
                              onForward: () {},
                              onDelete: () {},
                            ),
                          ),
                        ),
                      ),
                    ),
                    floatingActionButton: FloatingActionButton(
                      onPressed: () => setState(() => selectedCount = 1),
                      child: const Icon(Icons.exposure_minus_1),
                    ),
                  ),
                );
              },
            ),
          );
          await tester.pumpAndSettle();
          _expectZeroLayoutExceptions(
            tester,
            'ChatMessageSelectionHeader initial count=2 width=$width',
          );

          expect(
            find.byKey(const ValueKey<String>('msg_sel_action_forward')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey<String>('msg_sel_action_reply')),
            findsNothing,
          );

          // Trigger 2 -> 1 transition (expands action bar to Reply + Copy + Pin + Forward + Delete while rolling counter).
          await tester.tap(find.byType(FloatingActionButton));
          await tester.pump();
          _expectZeroLayoutExceptions(
            tester,
            'ChatMessageSelectionHeader 2->1 frame 0 width=$width',
          );
          await tester.pump(const Duration(milliseconds: 60));
          _expectZeroLayoutExceptions(
            tester,
            'ChatMessageSelectionHeader 2->1 mid-frame 60ms width=$width',
          );
          await tester.pump(const Duration(milliseconds: 120));
          _expectZeroLayoutExceptions(
            tester,
            'ChatMessageSelectionHeader 2->1 mid-frame 180ms width=$width',
          );
          await tester.pumpAndSettle();
          _expectZeroLayoutExceptions(
            tester,
            'ChatMessageSelectionHeader 2->1 settled width=$width',
          );

          // Verify all 5 action buttons and their localized Russian tooltips including "Переслать".
          expect(
            find.byKey(const ValueKey<String>('msg_sel_action_reply')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey<String>('msg_sel_action_copy')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey<String>('msg_sel_action_pin')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey<String>('msg_sel_action_forward')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey<String>('msg_sel_action_delete')),
            findsOneWidget,
          );

          expect(find.byTooltip('Ответить'), findsOneWidget);
          expect(find.byTooltip('Копировать'), findsOneWidget);
          expect(find.byTooltip('Закрепить'), findsOneWidget);
          expect(find.byTooltip('Переслать'), findsOneWidget);
          expect(find.byTooltip('Удалить'), findsOneWidget);
        }
      },
    );
  });

  group('3. SenderHeaderRow Narrow 200px Box & Cluster Persona Splitting', () {
    testWidgets(
      'SenderHeaderRow renders inside a narrow 200px box with badges and a 32-char custom adminTitle with 0 overflow',
      (tester) async {
        const String adminTitle32 = 'Старший модератор безопасности!!';
        expect(adminTitle32.length, 32);

        final customization = PeerCustomization(
          emojiStatus: const EmojiStatusData(type: 'unicode', emoji: '⚡'),
          badge: UserBadge.builtInDefaults.first,
          badgeIsDisplayed: true,
        );

        await tester.pumpWidget(
          _wrapTestApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  child: SenderHeaderRow(
                    senderName: 'Константин Константинопольский',
                    nameColor: const Color(0xFF64C4FF),
                    customization: customization,
                    isBot: true,
                    isVerified: true,
                    adminTitle: adminTitle32,
                    role: 'admin',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        _expectZeroLayoutExceptions(tester, 'SenderHeaderRow 200px box');

        final nameFinder = find.text('Константин Константинопольский');
        expect(nameFinder, findsOneWidget);
        final nameSize = tester.getSize(nameFinder);
        expect(nameSize.width, greaterThan(20.0));
        expect(nameSize.width, lessThanOrEqualTo(200.0));

        final titleFinder = find.text(adminTitle32);
        expect(titleFinder, findsOneWidget);
        final rowRect = tester.getRect(find.byType(SenderHeaderRow));
        expect(rowRect.width, lessThanOrEqualTo(200.0));
      },
    );

    test(
      'areMessagesInSameSenderCluster splits clusters when senderChatId or isFromAnonymousAdmin changes',
      () {
        Message buildMsg({
          required String id,
          String senderId = '7',
          String senderName = 'Alex',
          String? senderChatId,
          String? senderChatName,
          bool isFromAnonymousAdmin = false,
          String createdAt = '2026-11-24T12:00:00Z',
        }) {
          return Message(
            id: id,
            chatId: '42',
            senderId: senderId,
            senderName: senderName,
            content: 'Msg $id',
            messageType: 'text',
            isEdited: false,
            createdAt: createdAt,
            senderChatId: senderChatId,
            senderChatName: senderChatName,
            isFromAnonymousAdmin: isFromAnonymousAdmin,
          );
        }

        final personal1 = buildMsg(
          id: '1',
          createdAt: '2026-11-24T12:00:00Z',
        );
        final personal2 = buildMsg(
          id: '2',
          createdAt: '2026-11-24T12:01:00Z',
        );
        expect(areMessagesInSameSenderCluster(personal1, personal2), isTrue);

        // Same author switching from personal account -> Send-As Channel A must split cluster.
        final channelA1 = buildMsg(
          id: '3',
          senderChatId: '500',
          senderChatName: 'Tech Digest',
          createdAt: '2026-11-24T12:01:30Z',
        );
        final channelA2 = buildMsg(
          id: '4',
          senderChatId: '500',
          senderChatName: 'Tech Digest',
          createdAt: '2026-11-24T12:02:00Z',
        );
        final channelB = buildMsg(
          id: '5',
          senderChatId: '501',
          senderChatName: 'Design Weekly',
          createdAt: '2026-11-24T12:02:30Z',
        );
        expect(areMessagesInSameSenderCluster(personal2, channelA1), isFalse);
        expect(areMessagesInSameSenderCluster(channelA1, channelA2), isTrue);
        expect(areMessagesInSameSenderCluster(channelA2, channelB), isFalse);

        // Same author switching between personal, channel, and Group Anonymous must split cluster.
        final groupAnon1 = buildMsg(
          id: '6',
          isFromAnonymousAdmin: true,
          createdAt: '2026-11-24T12:03:00Z',
        );
        final groupAnon2 = buildMsg(
          id: '7',
          isFromAnonymousAdmin: true,
          createdAt: '2026-11-24T12:03:30Z',
        );
        expect(areMessagesInSameSenderCluster(personal2, groupAnon1), isFalse);
        expect(areMessagesInSameSenderCluster(channelA2, groupAnon1), isFalse);
        expect(areMessagesInSameSenderCluster(groupAnon1, groupAnon2), isTrue);
      },
    );
  });

  group('4. Inline Silent Broadcast Bell Inside LiquidGlassInputField', () {
    testWidgets(
      'Renders input_pill_silent_bell_button to the left of paperclip when empty, collapses on typing, restores on clear, with 0 translucent Opacity above LiquidGlassLens in GlassMode.full',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = TextEditingController();
        addTearDown(controller.dispose);
        bool isSilent = false;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return _wrapTestApp(
                glassMode: GlassMode.full,
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: ChannelBottomCapsuleBar(
                      channelId: '777',
                      channelName: 'News Channel',
                      isMember: true,
                      myRole: 'owner',
                      canPostInChannel: true,
                      controller: controller,
                      isSilentBroadcast: isSilent,
                      onToggleSilentBroadcast: (next) {
                        setState(() => isSilent = next);
                      },
                      onAttach: () {},
                      onEmoji: () {},
                      onSend: () {},
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        _expectZeroLayoutExceptions(tester, 'Silent bell initial render');
        _expectNoTranslucentOpacityAboveGlass(tester);

        // 1. Bell button is rendered inside LiquidGlassInputField to the LEFT of the paperclip.
        final bellFinder = find.byKey(
          const ValueKey('input_pill_silent_bell_button'),
        );
        final clipFinder = find.byKey(const ValueKey('attach_clip'));
        expect(bellFinder, findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(LiquidGlassInputField),
            matching: bellFinder,
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('silent_bell_on')), findsOneWidget);
        expect(clipFinder, findsOneWidget);
        expect(find.text('Публикация'), findsOneWidget);

        final bellRect = tester.getRect(bellFinder);
        final clipRect = tester.getRect(clipFinder);
        expect(
          bellRect.right,
          lessThanOrEqualTo(clipRect.left),
          reason:
              'Inline silent broadcast bell must sit immediately to the left of the paperclip',
        );

        // 2. Toggle silent mode -> bell switches to crossed-out state and hint updates to "Беззвучная публикация".
        await tester.tap(bellFinder);
        await tester.pump();
        _expectNoTranslucentOpacityAboveGlass(tester);
        await tester.pump(const Duration(milliseconds: 250));
        expect(isSilent, isTrue);
        expect(find.byKey(const ValueKey('silent_bell_off')), findsOneWidget);
        expect(find.text('Беззвучная публикация'), findsOneWidget);
        _expectNoTranslucentOpacityAboveGlass(tester);

        // Drain GlassToast timer if shown.
        await tester.pump(const Duration(seconds: 4));

        // 3. Typing text smoothly collapses the silent bell without putting translucent Opacity above glass.
        controller.text = 'Экстренный выпуск';
        await tester.pump();
        _expectNoTranslucentOpacityAboveGlass(tester);
        await tester.pump(const Duration(milliseconds: 75));
        _expectNoTranslucentOpacityAboveGlass(tester);
        await tester.pumpAndSettle();
        _expectZeroLayoutExceptions(tester, 'Silent bell collapsed on text');
        _expectNoTranslucentOpacityAboveGlass(tester);

        expect(bellFinder, findsNothing);
        expect(
          find.byKey(const ValueKey('input_pill_silent_bell_empty')),
          findsOneWidget,
        );

        // 4. Clearing text smoothly restores the silent bell to the left of the paperclip.
        controller.clear();
        await tester.pump();
        _expectNoTranslucentOpacityAboveGlass(tester);
        await tester.pump(const Duration(milliseconds: 75));
        _expectNoTranslucentOpacityAboveGlass(tester);
        await tester.pumpAndSettle();
        _expectZeroLayoutExceptions(tester, 'Silent bell restored on clear');
        _expectNoTranslucentOpacityAboveGlass(tester);

        expect(bellFinder, findsOneWidget);
        expect(find.byKey(const ValueKey('silent_bell_off')), findsOneWidget);
        final restoredBellRect = tester.getRect(bellFinder);
        final restoredClipRect = tester.getRect(clipFinder);
        expect(restoredBellRect.right, lessThanOrEqualTo(restoredClipRect.left));
      },
    );
  });

  group('5. InlineSendAsSelectorButton (36x36) & Floating SenderSelectPopup', () {
    testWidgets(
      'Renders 36x36 button inside left of LiquidGlassInputField, morphs to × and opens showSenderSelectPopup above bar without translucent Opacity above LiquidGlassLens, switching user / group / channel personas',
      (tester) async {
        final previousHttpOverrides = HttpOverrides.current;
        final mockHttp = _MockSendAsHttpOverrides();
        HttpOverrides.global = mockHttp;
        addTearDown(() {
          HttpOverrides.global = previousHttpOverrides;
        });

        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = TextEditingController();
        addTearDown(controller.dispose);

        const peers = <SendAsPeer>[
          SendAsPeer(
            peerType: 'user',
            id: '1',
            name: 'Алексей Смирнов',
            username: 'alex',
            isSelected: true,
          ),
          SendAsPeer(
            peerType: 'group',
            id: '42',
            chatId: '42',
            name: 'Разработка Theaver',
            memberCount: 1250,
          ),
          SendAsPeer(
            peerType: 'channel',
            id: '99',
            chatId: '99',
            name: 'Theaver Dev Blog',
            username: 'theaver_dev',
            isVerified: true,
            subscriberCount: 18400,
          ),
        ];

        String selectedMode = 'user';
        String? selectedChatId;

        SendAsPeer resolveActivePeer() {
          return peers.firstWhere(
            (p) => p.matchesSelection(
              selectedSendAsMode: selectedMode,
              selectedSendAsChatId: selectedChatId,
            ),
            orElse: () => peers.first,
          );
        }

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              final bool isAnon = selectedMode == 'group';
              return _wrapTestApp(
                glassMode: GlassMode.full,
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: ChatInputBar(
                        controller: controller,
                        isAnonymousAdmin: isAnon,
                        hintText: isAnon ? 'Написать анонимно...' : null,
                        sendAsLeadingWidget: InlineSendAsSelectorButton(
                          chatId: '42',
                          peers: peers,
                          selectedPeer: resolveActivePeer(),
                          onPeerSelected: (picked) {
                            setState(() {
                              selectedMode = picked.peerType;
                              selectedChatId = picked.isChannel
                                  ? (picked.chatId ?? picked.id)
                                  : null;
                            });
                          },
                        ),
                        onEmoji: () {},
                        onAttach: () {},
                        onSend: () {},
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        _expectZeroLayoutExceptions(tester, 'SendAs initial render');
        _expectNoTranslucentOpacityAboveGlass(tester);

        // 1. Verify 36x36 button sits inside left of LiquidGlassInputField before the emoji button.
        final sendAsBtnFinder = find.byKey(
          const ValueKey('send_as_inline_avatar_button'),
        );
        expect(sendAsBtnFinder, findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('input_pill_leading_identity')),
            matching: sendAsBtnFinder,
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(LiquidGlassInputField),
            matching: sendAsBtnFinder,
          ),
          findsOneWidget,
        );

        final btnSize = tester.getSize(sendAsBtnFinder);
        expect(btnSize, const Size(36.0, 36.0));

        final btnRect = tester.getRect(sendAsBtnFinder);
        final emojiRect = tester.getRect(find.byType(iconoir.Emoji));
        expect(
          btnRect.right,
          lessThanOrEqualTo(emojiRect.left + 2.0),
          reason:
              '36x36 Send-As avatar must sit inside the pill to the left of the emoji icon',
        );
        expect(find.text('Сообщение'), findsOneWidget);

        // 2. Tap button -> morphs toward × and opens floating SenderSelectPopup above the input bar.
        await tester.tap(sendAsBtnFinder);
        await tester.pump();
        _expectNoTranslucentOpacityAboveGlass(tester);

        // Mid-transition check (both popup scale-in and × morph active): ZERO translucent Opacity above glass!
        await tester.pump(const Duration(milliseconds: 80));
        _expectZeroLayoutExceptions(tester, 'SendAs popup mid-open 80ms');
        _expectNoTranslucentOpacityAboveGlass(tester);

        await tester.pumpAndSettle();
        _expectZeroLayoutExceptions(tester, 'SendAs popup settled');
        _expectNoTranslucentOpacityAboveGlass(tester);

        expect(
          find.byKey(const ValueKey('sender_select_popup_overlay')),
          findsOneWidget,
        );
        expect(find.text('Отправить сообщение от имени...'), findsOneWidget);
        expect(find.text('Личный аккаунт'), findsOneWidget);
        expect(find.text('Анонимный администратор'), findsOneWidget);

        // Morphing × CustomPaint is active inside the 36x36 button while popup is open.
        expect(
          find.descendant(
            of: sendAsBtnFinder,
            matching: find.byType(CustomPaint),
          ),
          findsWidgets,
        );

        // Popup card sits strictly above the input bar.
        final popupTitleRect = tester.getRect(
          find.text('Отправить сообщение от имени...'),
        );
        final channelRowRect = tester.getRect(
          find.byKey(const ValueKey('sender_select_peer_channel_99')),
        );
        final inputBarRect = tester.getRect(find.byType(LiquidGlassInputField));
        expect(popupTitleRect.top, lessThan(channelRowRect.top));
        expect(
          channelRowRect.bottom,
          lessThanOrEqualTo(inputBarRect.top),
          reason: 'SenderSelectPopup must float above the ChatInputBar pill',
        );

        // 3. Select 'group' (anonymous group admin) -> switches hint to "Написать анонимно..." without legacy external banner.
        await tester.tap(
          find.byKey(const ValueKey('sender_select_peer_group_42')),
        );
        await tester.pump();
        _expectNoTranslucentOpacityAboveGlass(tester);
        await tester.pumpAndSettle();
        _expectNoTranslucentOpacityAboveGlass(tester);

        expect(selectedMode, 'group');
        expect(selectedChatId, isNull);
        expect(find.text('Написать анонимно...'), findsOneWidget);
        // Legacy external banner ("От имени группы") must remain hidden when inline Send-As selector is present.
        expect(find.text('От имени группы'), findsNothing);
        expect(mockHttp.calls.last.body['send_as_mode'], 'group');
        expect(mockHttp.calls.last.body['send_as_chat_id'], isNull);

        // 4. Re-open popup and select 'channel' -> updates mode='channel', chatId='99'.
        await tester.tap(sendAsBtnFinder);
        await tester.pumpAndSettle();
        _expectNoTranslucentOpacityAboveGlass(tester);

        await tester.tap(
          find.byKey(const ValueKey('sender_select_peer_channel_99')),
        );
        await tester.pumpAndSettle();
        _expectNoTranslucentOpacityAboveGlass(tester);

        expect(selectedMode, 'channel');
        expect(selectedChatId, '99');
        expect(find.text('Сообщение'), findsOneWidget);
        expect(mockHttp.calls.last.body['send_as_mode'], 'channel');
        expect(mockHttp.calls.last.body['send_as_chat_id'], 99);

        // 5. Re-open popup and select 'user' -> restores personal account mode='user', chatId=null.
        await tester.tap(sendAsBtnFinder);
        await tester.pumpAndSettle();
        _expectNoTranslucentOpacityAboveGlass(tester);

        await tester.tap(
          find.byKey(const ValueKey('sender_select_peer_user_1')),
        );
        await tester.pumpAndSettle();
        _expectNoTranslucentOpacityAboveGlass(tester);

        expect(selectedMode, 'user');
        expect(selectedChatId, isNull);
        expect(mockHttp.calls.last.body['send_as_mode'], 'user');
        expect(mockHttp.calls.last.body['send_as_chat_id'], isNull);
      },
    );
  });
}
