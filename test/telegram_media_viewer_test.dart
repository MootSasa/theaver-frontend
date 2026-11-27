import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/theav_media_item.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/media_playback_coordinator.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/services/video_pip_service.dart';
import 'package:theaver/utils/swipe_back_route.dart';
import 'package:theaver/widgets/media_viewer/floating_video_pip_overlay.dart';
import 'package:theaver/widgets/media_viewer/theav_media_viewer.dart';
import 'package:theaver/widgets/media_viewer/theav_media_viewer_route.dart';
import 'package:theaver/widgets/profile/avatar_gallery_viewer.dart';
import 'package:theaver/widgets/tiling/trackpad_swipe_back_indicator.dart';
import 'package:video_player/video_player.dart';

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

class _FakeVideoPlayerController extends ValueNotifier<VideoPlayerValue>
    implements VideoPlayerController {
  _FakeVideoPlayerController()
      : super(
          const VideoPlayerValue(
            duration: Duration(seconds: 42),
            size: Size(1280, 720),
            isInitialized: true,
            isPlaying: true,
            volume: 1.0,
          ),
        );

  bool isDisposed = false;
  int playCount = 0;
  int pauseCount = 0;

  @override
  int get playerId => VideoPlayerController.kUninitializedPlayerId;

  @override
  String get dataSource => 'https://example.com/clip.mp4';

  @override
  DataSourceType get dataSourceType => DataSourceType.network;

  @override
  String get package => '';

  @override
  Map<String, String> get httpHeaders => const <String, String>{};

  @override
  Future<ClosedCaptionFile>? get closedCaptionFile => null;

  @override
  VideoFormat? get formatHint => null;

  @override
  VideoPlayerOptions? get videoPlayerOptions => null;

  @override
  VideoViewType get viewType => VideoViewType.textureView;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> play() async {
    playCount += 1;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    value = value.copyWith(position: position);
  }

  @override
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume);
  }

  @override
  Future<void> setLooping(bool looping) async {
    value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    value = value.copyWith(playbackSpeed: speed);
  }

  @override
  Future<void> setCaptionOffset(Duration offset) async {}

  @override
  Future<void> setClosedCaptionFile(
    Future<ClosedCaptionFile>? closedCaptionFile,
  ) async {}

  @override
  Future<Duration?> get position async => value.position;

  @override
  Future<List<VideoAudioTrack>> getAudioTracks() async =>
      const <VideoAudioTrack>[];

  @override
  bool isAudioTrackSupportAvailable() => false;

  @override
  Future<void> selectAudioTrack(String trackId) async {}

  @override
  Future<void> dispose() async {
    isDisposed = true;
    super.dispose();
  }
}

Future<Uint8List> _createSyntheticPng({
  int width = 120,
  int height = 80,
  Color color = const Color(0xFF1E88E5),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final img = await picture.toImage(width, height);
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  picture.dispose();
  return byteData!.buffer.asUint8List();
}

Widget _wrapApp({
  required Widget home,
  GlassMode glassMode = GlassMode.full,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LiquidGlassProvider>(
        create: (_) => _ForcedGlassProvider(glassMode),
      ),
      ChangeNotifierProvider<ProfileThemeProvider>(
        create: (_) => ProfileThemeProvider(),
      ),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      theme: ThemeData.dark(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: ThemeMode.dark,
      localizationsDelegates: const [
        _SyncAppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru'), Locale('en')],
      locale: const Locale('ru'),
      home: home,
    ),
  );
}

void main() {
  group('Telegram-Style 120 FPS Media Viewer & PiP Suite', () {
    test('buildChatMediaTimeline flattens photos, videos, GIFs & albums in chronological order and skips excluded types', () {
      // Simulate reversed chat feed (index 0 = newest).
      final messages = <Message>[
        Message(
          id: 'm_view_once',
          chatId: 'c1',
          senderId: 'u1',
          content: '',
          messageType: 'image',
          isEdited: false,
          createdAt: '2026-11-25T12:10:00Z',
          senderName: 'Alice',
          fileUrl: 'https://cdn.example/once.jpg',
          isViewOnce: true,
        ),
        Message(
          id: 'm_gif',
          chatId: 'c1',
          senderId: 'u1',
          content: '',
          messageType: 'gif',
          isEdited: false,
          createdAt: '2026-11-25T12:09:00Z',
          senderName: 'Alice',
          fileUrl: 'https://cdn.example/funny.gif',
        ),
        Message(
          id: 'm_album_2',
          chatId: 'c1',
          senderId: 'u1',
          content: '',
          messageType: 'video',
          isEdited: false,
          createdAt: '2026-11-25T12:08:00Z',
          senderName: 'Alice',
          fileUrl: 'https://cdn.example/album2.mp4',
          groupedId: 'grp_1',
        ),
        Message(
          id: 'm_album_1',
          chatId: 'c1',
          senderId: 'u1',
          content: 'Shared album caption!',
          messageType: 'image',
          isEdited: false,
          createdAt: '2026-11-25T12:07:00Z',
          senderName: 'Alice',
          fileUrl: 'https://cdn.example/album1.jpg',
          groupedId: 'grp_1',
        ),
        Message(
          id: 'm_round',
          chatId: 'c1',
          senderId: 'u1',
          content: '',
          messageType: 'video',
          isEdited: false,
          createdAt: '2026-11-25T12:06:00Z',
          senderName: 'Alice',
          fileUrl: 'https://cdn.example/round.mp4',
          isRound: true,
        ),
        Message(
          id: 'm_doc',
          chatId: 'c1',
          senderId: 'u1',
          content: 'spec.pdf',
          messageType: 'document',
          isEdited: false,
          createdAt: '2026-11-25T12:05:00Z',
          senderName: 'Alice',
          fileUrl: 'https://cdn.example/spec.pdf',
        ),
        Message(
          id: 'm_photo_oldest',
          chatId: 'c1',
          senderId: 'u1',
          content: 'First sunrise',
          messageType: 'image',
          isEdited: false,
          createdAt: '2026-11-25T12:00:00Z',
          senderName: 'Alice',
          fileUrl: 'https://cdn.example/first.jpg',
        ),
      ];

      final timeline = buildChatMediaTimeline(
        messages,
        isReversed: true,
        hasProtectedContent: true,
      );

      expect(
        timeline.map((e) => e.id).toList(),
        <String>['m_photo_oldest', 'm_album_1', 'm_album_2', 'm_gif'],
      );
      expect(timeline[0].kind, TheavMediaKind.photo);
      expect(timeline[1].kind, TheavMediaKind.photo);
      expect(timeline[2].kind, TheavMediaKind.video);
      expect(timeline[2].caption, 'Shared album caption!');
      expect(timeline[3].kind, TheavMediaKind.gif);
      expect(timeline.every((e) => e.hasProtectedContent), isTrue);
    });

    testWidgets('TheavMediaViewer culls underlying route at rest via dynamic opaque, flips non-opaque during 2D drag, and mounts zero LiquidGlassLens or BackdropFilter', (tester) async {
      final pngBytes = (await tester.runAsync(() => _createSyntheticPng()))!;
      late BuildContext hostContext;
      final observer = _CaptureRouteObserver();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LiquidGlassProvider>(
              create: (_) => _ForcedGlassProvider(GlassMode.full),
            ),
            ChangeNotifierProvider<ProfileThemeProvider>(
              create: (_) => ProfileThemeProvider(),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            darkTheme: ThemeData.dark(useMaterial3: true),
            themeMode: ThemeMode.dark,
            navigatorObservers: [observer],
            localizationsDelegates: const [
              _SyncAppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ru'), Locale('en')],
            locale: const Locale('ru'),
            home: Builder(
              builder: (ctx) {
                hostContext = ctx;
                return const Scaffold(
                  body: Center(child: Text('HostScreen')),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final items = <TheavMediaItem>[
        TheavMediaItem(
          id: 'item_0',
          kind: TheavMediaKind.photo,
          url: 'mem://0',
          memoryBytes: pngBytes,
          heroTag: 'h_0',
          caption: 'A quiet landscape photograph.',
        ),
        TheavMediaItem(
          id: 'item_1',
          kind: TheavMediaKind.photo,
          url: 'mem://1',
          memoryBytes: pngBytes,
          heroTag: 'h_1',
        ),
      ];

      TheavMediaViewer.open<void>(hostContext, items: items);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TheavMediaViewer), findsOneWidget);
      expect(find.byType(LiquidGlassLens), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('1 из 2'), findsOneWidget);

      final viewerRoute = observer.lastPushedRoute as TheavMediaViewerRoute;
      expect(viewerRoute.overlayEntries.last.opaque, isTrue);

      // Start vertical drag -> underlying route must immediately become visible.
      final gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(12, 48));
      await tester.pump();
      expect(viewerRoute.overlayEntries.last.opaque, isFalse);

      // Release below dismiss threshold -> snaps back and re-culls underlying route.
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      expect(find.byType(TheavMediaViewer), findsOneWidget);
      expect(viewerRoute.overlayEntries.last.opaque, isTrue);

      // Wait past kDoubleTapTimeout, then drag beyond dismiss threshold -> viewer pops cleanly.
      await tester.pump(const Duration(milliseconds: 350));
      final dismissGesture = await tester.startGesture(const Offset(200, 260));
      for (int step = 0; step < 5; step++) {
        await dismissGesture.moveBy(const Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await dismissGesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(TheavMediaViewer), findsNothing);
    });

    testWidgets('AvatarGalleryViewer causes ZERO host rebuilds during swiping and syncs index once on close', (tester) async {
      final pngA = (await tester.runAsync(
        () => _createSyntheticPng(color: const Color(0xFFE53935)),
      ))!;
      final pngB = (await tester.runAsync(
        () => _createSyntheticPng(color: const Color(0xFF43A047)),
      ))!;
      final pngC = (await tester.runAsync(
        () => _createSyntheticPng(color: const Color(0xFF1E88E5)),
      ))!;

      final tmpDir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('avatar_swipe_test_'),
      ))!;
      try {
        final paths = (await tester.runAsync(() async {
          final fA = File('${tmpDir.path}/a.png')..writeAsBytesSync(pngA);
          final fB = File('${tmpDir.path}/b.png')..writeAsBytesSync(pngB);
          final fC = File('${tmpDir.path}/c.png')..writeAsBytesSync(pngC);
          return <String>[fA.path, fB.path, fC.path];
        }))!;

        int hostBuildCount = 0;
        int syncedCloseIndex = -1;
        late BuildContext hostContext;

        await tester.pumpWidget(
          _wrapApp(
            home: StatefulBuilder(
              builder: (ctx, setState) {
                hostContext = ctx;
                hostBuildCount += 1;
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        AvatarGalleryViewer.open(
                          hostContext,
                          avatarUrls: paths,
                          initialIndex: 0,
                          displayName: 'Test User',
                          firstIsCustomAvatar: true,
                          customAvatarBadgeText: 'Персональное фото',
                          onBeforeCloseSyncIndex: (idx) {
                            syncedCloseIndex = idx;
                            setState(() {});
                          },
                        );
                      },
                      child: const Text('Open'),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final buildsBeforeOpen = hostBuildCount;

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Персональное фото'), findsOneWidget);
        expect(find.text('1 из 3'), findsOneWidget);

        // Swipe across avatars 0 -> 1 -> 2
        await tester.fling(find.byType(PageView), const Offset(-450, 0), 1200);
        await tester.pumpAndSettle();
        expect(find.text('2 из 3'), findsOneWidget);

        await tester.fling(find.byType(PageView), const Offset(-450, 0), 1200);
        await tester.pumpAndSettle();
        expect(find.text('3 из 3'), findsOneWidget);

        // Zero host rebuilds during swiping inside viewer!
        expect(hostBuildCount, buildsBeforeOpen);

        // Close viewer -> onBeforeCloseSyncIndex fires once with final index 2
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(syncedCloseIndex, 2);
        expect(hostBuildCount, buildsBeforeOpen + 1);
      } finally {
        await tester.runAsync(() async {
          if (await tmpDir.exists()) {
            await tmpDir.delete(recursive: true);
          }
        });
      }
    });

    testWidgets('Filmstrip jump, HUD single-tap toggle, expandable caption, and protected content enforcement work cleanly', (tester) async {
      final pngBytes = (await tester.runAsync(() => _createSyntheticPng()))!;
      late BuildContext hostContext;

      await tester.pumpWidget(
        _wrapApp(
          home: Builder(
            builder: (ctx) {
              hostContext = ctx;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final items = <TheavMediaItem>[
        TheavMediaItem(
          id: 'p0',
          kind: TheavMediaKind.photo,
          url: 'mem://p0',
          memoryBytes: pngBytes,
          heroTag: 'hp0',
          hasProtectedContent: true,
          caption:
              'Long protected caption line one with detailed description that exceeds ninety characters so the more button appears naturally in the bottom area.',
        ),
        TheavMediaItem(
          id: 'p1',
          kind: TheavMediaKind.photo,
          url: 'mem://p1',
          memoryBytes: pngBytes,
          heroTag: 'hp1',
          hasProtectedContent: true,
        ),
      ];

      TheavMediaViewer.open<void>(hostContext, items: items);
      await tester.pumpAndSettle();

      // Lock icon rendered & quick save download icon hidden when protected
      expect(find.byType(iconoir.Lock), findsOneWidget);
      expect(find.byType(iconoir.Download), findsNothing);
      expect(find.text('1 из 2'), findsOneWidget);
      expect(find.text('ещё'), findsOneWidget);

      // Expand long caption
      await tester.tap(find.text('ещё'));
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsOneWidget);

      // Single tap toggles HUD visibility off & back on (wait past kDoubleTapTimeout = 300ms)
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final hudIgnoreAfterHide = tester.widget<IgnorePointer>(
        find.byKey(const ValueKey<String>('theav_media_hud_ignore_pointer')),
      );
      expect(hudIgnoreAfterHide.ignoring, isTrue);

      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final hudIgnoreAfterShow = tester.widget<IgnorePointer>(
        find.byKey(const ValueKey<String>('theav_media_hud_ignore_pointer')),
      );
      expect(hudIgnoreAfterShow.ignoring, isFalse);

      // Tap second filmstrip thumbnail -> jumps to page 2
      await tester.tap(find.byType(AnimatedContainer).last);
      await tester.pumpAndSettle();
      expect(find.text('2 из 2'), findsOneWidget);

      // Overflow menu hides Save & Share when hasProtectedContent == true
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Сохранить в галерею'), findsNothing);
      expect(find.text('Сохранить в загрузки'), findsNothing);
      expect(find.text('Поделиться'), findsNothing);
    });

    testWidgets('VideoPipService adopts controller without disposal, stops on MediaPlaybackCoordinator.stopAll, and restores cleanly to fullscreen', (tester) async {
      final fakeCtrl = _FakeVideoPlayerController();
      const item = TheavMediaItem(
        id: 'vid_1',
        kind: TheavMediaKind.video,
        url: 'https://example.com/clip.mp4',
        heroTag: 'h_vid_1',
        width: 1280,
        height: 720,
      );

      await tester.pumpWidget(
        _wrapApp(
          home: const Stack(
            children: [
              Scaffold(body: Center(child: Text('Chat'))),
              FloatingVideoPipOverlay(),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Before entering PiP: zero PiP UI mounted, zero blur
      expect(find.byType(VideoPlayer), findsNothing);

      await VideoPipService.instance.enterPip(
        controller: fakeCtrl,
        item: item,
      );
      await tester.pump();

      expect(VideoPipService.instance.isActive, isTrue);
      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(find.byType(LiquidGlassLens), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);

      // MediaPlaybackCoordinator.stopAll() pauses active PiP video without disposing
      await MediaPlaybackCoordinator.instance.stopAll();
      await tester.pump();
      expect(fakeCtrl.pauseCount, greaterThanOrEqualTo(1));
      expect(fakeCtrl.isDisposed, isFalse);

      // Handing back to fullscreen detaches without disposing
      final handedBack =
          VideoPipService.instance.takeControllerForFullscreen('vid_1');
      await tester.pump();
      expect(identical(handedBack, fakeCtrl), isTrue);
      expect(fakeCtrl.isDisposed, isFalse);
      expect(VideoPipService.instance.isActive, isFalse);
      expect(find.byType(VideoPlayer), findsNothing);

      await fakeCtrl.dispose();
    });

    testWidgets(
      'Diagonal horizontal photo swipes and ancestor SwipeBackPageRoute / TrackpadBackGestureWrapper never hijack PageView photo paging',
      (tester) async {
        final pngBytes = (await tester.runAsync(() => _createSyntheticPng()))!;
        var trackpadBackCount = 0;
        var innerRoutePopped = false;
        late BuildContext innerContext;

        await tester.pumpWidget(
          _wrapApp(
            home: TrackpadBackGestureWrapper(
              onTriggerBack: () => trackpadBackCount++,
              child: Builder(
                builder: (rootCtx) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(rootCtx)
                            .push<void>(
                              SwipeBackPageRoute<void>(
                                builder: (ctx) {
                                  innerContext = ctx;
                                  return const Scaffold(
                                    body: SizedBox.expand(),
                                  );
                                },
                              ),
                            )
                            .then((_) {
                              innerRoutePopped = true;
                            });
                      },
                      child: const Text('Open inner route'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(TrackpadBackGestureWrapper.isBlockedByModal, isFalse);

        await tester.tap(find.text('Open inner route'));
        await tester.pumpAndSettle();

        final items = <TheavMediaItem>[
          TheavMediaItem(
            id: 'diag_0',
            kind: TheavMediaKind.photo,
            url: 'mem://diag_0',
            memoryBytes: pngBytes,
            heroTag: 'h_diag_0',
          ),
          TheavMediaItem(
            id: 'diag_1',
            kind: TheavMediaKind.photo,
            url: 'mem://diag_1',
            memoryBytes: pngBytes,
            heroTag: 'h_diag_1',
          ),
          TheavMediaItem(
            id: 'diag_2',
            kind: TheavMediaKind.photo,
            url: 'mem://diag_2',
            memoryBytes: pngBytes,
            heroTag: 'h_diag_2',
          ),
        ];

        TheavMediaViewer.open<void>(innerContext, items: items);
        await tester.pumpAndSettle();

        expect(TrackpadBackGestureWrapper.isBlockedByModal, isTrue);
        expect(find.text('1 из 3'), findsOneWidget);

        final viewerRoute =
            ModalRoute.of(tester.element(find.byType(TheavMediaViewer)))
                as TheavMediaViewerRoute<dynamic>;
        expect(viewerRoute.overlayEntries.last.opaque, isTrue);

        // Diagonal left swipe (accumulates 30px dy > touchSlop while staying
        // predominantly horizontal) must advance PageView to page 2 without
        // triggering 2D pull-to-dismiss.
        final leftGesture = await tester.startGesture(const Offset(700, 300));
        for (var i = 0; i < 5; i++) {
          await leftGesture.moveBy(
            const Offset(-90, 6),
            timeStamp: Duration(milliseconds: 16 * (i + 1)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        await leftGesture.up(timeStamp: const Duration(milliseconds: 96));
        await tester.pumpAndSettle();

        expect(find.text('2 из 3'), findsOneWidget);
        expect(viewerRoute.overlayEntries.last.opaque, isTrue);

        // Trackpad two-finger swipe while viewer is open must stay blocked.
        final panZoomPointer = TestPointer(2, PointerDeviceKind.trackpad);
        await tester.sendEventToBinding(
          panZoomPointer.panZoomStart(const Offset(240, 300)),
        );
        await tester.sendEventToBinding(
          panZoomPointer.panZoomUpdate(
            const Offset(240, 300),
            pan: const Offset(220, 0),
          ),
        );
        await tester.sendEventToBinding(panZoomPointer.panZoomEnd());
        await tester.pumpAndSettle();

        expect(trackpadBackCount, 0);
        expect(find.text('2 из 3'), findsOneWidget);

        // Diagonal right swipe starting from left edge must return to page 1
        // without triggering ancestor SwipeBackPageRoute or popping viewer.
        final rightGesture = await tester.startGesture(const Offset(24, 300));
        for (var i = 0; i < 5; i++) {
          await rightGesture.moveBy(
            const Offset(90, -6),
            timeStamp: Duration(milliseconds: 16 * (i + 1)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        await rightGesture.up(timeStamp: const Duration(milliseconds: 96));
        await tester.pumpAndSettle();

        expect(find.text('1 из 3'), findsOneWidget);
        expect(find.byType(TheavMediaViewer), findsOneWidget);
        expect(innerRoutePopped, isFalse);

        // Closing the viewer clears the modal trackpad blocker cleanly.
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        expect(find.byType(TheavMediaViewer), findsNothing);
        expect(TrackpadBackGestureWrapper.isBlockedByModal, isFalse);
      },
    );
  });
}

class _CaptureRouteObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
    super.didPush(route, previousRoute);
  }
}
