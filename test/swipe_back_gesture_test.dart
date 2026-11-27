import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/animations/screen_transitions.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/chat_swipe_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/services/tiling_layout_controller.dart';
import 'package:theaver/theme/app_theme.dart';
import 'package:theaver/utils/swipe_back_route.dart';
import 'package:theaver/widgets/chat/chat_scaffold.dart';
import 'package:theaver/widgets/chat/liquid_glass_screen_morph_launcher.dart';
import 'package:theaver/widgets/chat/swipe_to_reply_wrapper.dart';
import 'package:theaver/widgets/chat/swipeable_chat_tile.dart';
import 'package:theaver/widgets/common/adaptive_switch.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
    TilingLayoutController.instance.closeAllChats();
  });

  group('Telegram-Grade Custom Full-Screen Back Swipe Gesture', () {
    testWidgets(
      '1. Jittery 120Hz/240Hz samples trigger rightward swipe-back reliably while leftward swipe triggers SwipeToReplyWrapper',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final navKey = GlobalKey<NavigatorState>();
        int replyCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            theme: AppTheme.dark(),
            home: const Scaffold(body: Center(child: Text('HomeRoot'))),
          ),
        );

        navKey.currentState!.push(
          SwipeBackPageRoute<void>(
            builder: (_) => Scaffold(
              body: Center(
                child: SwipeToReplyWrapper(
                  onReply: () => replyCount++,
                  child: Container(
                    key: const ValueKey<String>('message_row'),
                    width: double.infinity,
                    height: 72,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: const Text('ChatBubbleMessage'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('ChatBubbleMessage'), findsOneWidget);

        // Part A: Leftward swipe on the bubble triggers SwipeToReplyWrapper without popping.
        final bubbleCenter = tester.getCenter(
          find.byKey(const ValueKey<String>('message_row')),
        );
        final leftGesture = await tester.startGesture(
          bubbleCenter,
          kind: PointerDeviceKind.touch,
        );
        await leftGesture.moveBy(const Offset(0.0, 0.2));
        await tester.pump(const Duration(milliseconds: 4));
        await leftGesture.moveBy(const Offset(-14.0, 0.4));
        await tester.pump(const Duration(milliseconds: 8));
        await leftGesture.moveBy(const Offset(-95.0, 1.0));
        await tester.pump(const Duration(milliseconds: 16));
        await leftGesture.up();
        await tester.pumpAndSettle();

        expect(replyCount, 1);
        expect(find.text('ChatBubbleMessage'), findsOneWidget);

        // Part B: Jittery 120Hz/240Hz thumb-roll samples (0.0, 0.3) and (-0.2, 0.0)
        // followed by rightward movement on the exact same bubble trigger swipe-back.
        final rightGesture = await tester.startGesture(
          bubbleCenter,
          kind: PointerDeviceKind.touch,
        );
        await rightGesture.moveBy(const Offset(0.0, 0.3));
        await tester.pump(const Duration(milliseconds: 4));
        await rightGesture.moveBy(const Offset(-0.2, 0.0));
        await tester.pump(const Duration(milliseconds: 4));

        for (int i = 0; i < 10; i++) {
          await rightGesture.moveBy(const Offset(22.0, 1.0));
          await tester.pump(const Duration(milliseconds: 8));
        }

        // Verify live 1:1 tracking mid-drag before finger release.
        final midDragLeft = tester
            .getTopLeft(find.byKey(const ValueKey<String>('message_row')))
            .dx;
        expect(midDragLeft, greaterThan(140.0));

        await rightGesture.up();
        await tester.pumpAndSettle();

        expect(replyCount, 1);
        expect(find.text('ChatBubbleMessage'), findsNothing);
        expect(find.text('HomeRoot'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Plain MaterialPageRoute inherits interactive swipe-back, -0.28 parallax, and top-mounted scrim with zero Opacity/FadeTransition above LiquidGlassLens',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final navKey = GlobalKey<NavigatorState>();
        final glassProvider = _ForcedGlassProvider(GlassMode.full);

        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: glassProvider,
            child: MaterialApp(
              navigatorKey: navKey,
              theme: AppTheme.dark(),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Stack(
                    children: [
                      const Positioned(
                        left: 0,
                        top: 120,
                        child: SizedBox(
                          key: ValueKey<String>('underlying_probe'),
                          width: 100,
                          height: 40,
                        ),
                      ),
                      Positioned(
                        left: 24,
                        bottom: 32,
                        child: SizedBox(
                          width: 140,
                          height: 48,
                          child: LiquidGlassLens(
                            style: glassProvider.createStyle(
                              context: context,
                              cornerRadius: 24,
                            ),
                            child: const Center(child: Text('HomeGlassPill')),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          CustomPageTransitionsTheme.customTheme.builders[TargetPlatform.android],
          isA<TelegramSwipeBackPageTransitionsBuilder>(),
        );
        expect(
          CustomPageTransitionsTheme.customTheme.builders[TargetPlatform.iOS],
          isA<TelegramSwipeBackPageTransitionsBuilder>(),
        );

        // Push a plain MaterialPageRoute (not SwipeBackPageRoute).
        navKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              body: Center(
                child: SizedBox(
                  width: 160,
                  height: 48,
                  child: LiquidGlassLens(
                    style: glassProvider.createStyle(
                      context: context,
                      cornerRadius: 24,
                    ),
                    child: const Center(child: Text('PlainMaterialScreen')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('PlainMaterialScreen'), findsOneWidget);
        _expectNoTranslucentOpacityAboveGlass(tester);

        // Start interactive swipe-back to ~50% progress.
        final gesture = await tester.startGesture(
          const Offset(80, 400),
          kind: PointerDeviceKind.touch,
        );
        await gesture.moveBy(const Offset(18, 0));
        await tester.pump(const Duration(milliseconds: 8));
        await gesture.moveBy(const Offset(200, 0));
        await tester.pump(const Duration(milliseconds: 8));

        // Verify Liquid Glass safety mid-transition while scrim is translucent.
        _expectNoTranslucentOpacityAboveGlass(tester);

        // Verify underlying route -0.28 parallax (~ -0.28 * 400 * 0.50 = -56px).
        final underlyingDx = tester
            .getTopLeft(find.byKey(const ValueKey<String>('underlying_probe')))
            .dx;
        expect(underlyingDx, lessThan(-25.0));
        expect(underlyingDx, greaterThan(-112.0));

        // Verify scrim ColoredBox is mounted above the underlying route content.
        final scrimFinder = find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == SwipeBackPageRoute.kScrimColor,
        );
        expect(scrimFinder, findsWidgets);

        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.text('PlainMaterialScreen'), findsNothing);
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey<String>('underlying_probe')))
              .dx,
          closeTo(0.0, 0.5),
        );
      },
    );

    testWidgets(
      '3. Left-edge dx=6.0 on iOS and bottom-half dy=0.78*H with PopScope(canPop: false) + SwipeBackPopScope preserve custom return values, and ChatScaffold unfocuses open keyboard on swipe',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final navKey = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            theme: AppTheme.dark().copyWith(platform: TargetPlatform.iOS),
            home: const Scaffold(body: Center(child: Text('iOSHome'))),
          ),
        );

        Map<String, dynamic>? returnedResult;
        final routeFuture = navKey.currentState!.push<Map<String, dynamic>>(
          MaterialPageRoute<Map<String, dynamic>>(
            builder: (routeContext) => SwipeBackPopScope(
              onSwipeBackPop: () {
                Navigator.of(routeContext).pop(<String, dynamic>{
                  'saved': true,
                  'permissionsCount': 5,
                });
              },
              child: const PopScope(
                canPop: false,
                child: Scaffold(
                  body: Center(child: Text('ResultSettingsScreen')),
                ),
              ),
            ),
          ),
        );
        routeFuture.then((value) => returnedResult = value);
        await tester.pumpAndSettle();

        expect(find.text('ResultSettingsScreen'), findsOneWidget);

        // Swipe starting at dx = 6.0 (left bezel on iOS) and dy = 0.78 * 800 = 624.0 (bottom half).
        final gesture = await tester.startGesture(
          const Offset(6.0, 624.0),
          kind: PointerDeviceKind.touch,
        );
        await gesture.moveBy(const Offset(20.0, 0.0));
        await tester.pump(const Duration(milliseconds: 8));
        await gesture.moveBy(const Offset(200.0, 0.0));
        await tester.pump(const Duration(milliseconds: 8));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.text('ResultSettingsScreen'), findsNothing);
        expect(returnedResult, equals(<String, dynamic>{
          'saved': true,
          'permissionsCount': 5,
        }));

        // Also verify ChatScaffold with open keyboard unfocuses input and swipes back,
        // while swipeBackBlocked: true prevents swipe-back.
        final inputFocus = FocusNode();
        addTearDown(inputFocus.dispose);
        bool blockedMode = true;
        late StateSetter updateChatState;

        navKey.currentState!.push(
          SwipeBackPageRoute<void>(
            builder: (_) => StatefulBuilder(
              builder: (ctx, setLocalState) {
                updateChatState = setLocalState;
                return MediaQuery(
                  data: MediaQuery.of(ctx).copyWith(
                    viewInsets: const EdgeInsets.only(bottom: 300),
                  ),
                  child: ChatScaffold(
                    swipeBackBlocked: blockedMode,
                    body: Center(
                      child: TextField(
                        focusNode: inputFocus,
                        decoration: const InputDecoration(hintText: 'MsgInput'),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        inputFocus.requestFocus();
        await tester.pump();
        expect(inputFocus.hasFocus, isTrue);

        // While swipeBackBlocked == true (e.g. selection/recording), swipe does NOT pop.
        final blockedSwipe = await tester.startGesture(
          const Offset(40, 300),
          kind: PointerDeviceKind.touch,
        );
        await blockedSwipe.moveBy(const Offset(220, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await blockedSwipe.up();
        await tester.pumpAndSettle();
        expect(find.byType(ChatScaffold), findsOneWidget);

        // Once swipeBackBlocked == false, swiping with open keyboard unfocuses and pops.
        updateChatState(() => blockedMode = false);
        await tester.pump();

        final openKbSwipe = await tester.startGesture(
          const Offset(40, 300),
          kind: PointerDeviceKind.touch,
        );
        await openKbSwipe.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 8));
        await openKbSwipe.moveBy(const Offset(200, 0));
        await tester.pump(const Duration(milliseconds: 8));
        expect(inputFocus.hasFocus, isFalse);

        await openKbSwipe.up();
        await tester.pumpAndSettle();
        expect(find.byType(ChatScaffold), findsNothing);
      },
    );

    testWidgets(
      '4. PageView at page == 1 scrolls back to page == 0 without popping, then at page == 0 hands rightward swipe off to route swipe-back',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final navKey = GlobalKey<NavigatorState>();
        final pageController = PageController(initialPage: 1);
        addTearDown(pageController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            theme: AppTheme.dark(),
            home: const Scaffold(body: Center(child: Text('RootHome'))),
          ),
        );

        navKey.currentState!.push(
          SwipeBackPageRoute<void>(
            builder: (_) => Scaffold(
              body: PageView(
                controller: pageController,
                children: const [
                  Center(child: Text('CarouselPage0')),
                  Center(child: Text('CarouselPage1')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(pageController.page, closeTo(1.0, 0.01));
        expect(find.text('CarouselPage1'), findsOneWidget);

        // Swipe 1 (while on page == 1): scrolls PageView from page 1 -> page 0 without popping route.
        final swipeToPage0 = await tester.startGesture(
          const Offset(80, 400),
          kind: PointerDeviceKind.touch,
        );
        await swipeToPage0.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await swipeToPage0.moveBy(const Offset(260, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await swipeToPage0.up();
        await tester.pumpAndSettle();

        expect(find.text('CarouselPage0'), findsOneWidget);
        expect(pageController.page, closeTo(0.0, 0.01));

        // Swipe 2 (now at page == 0): hands rightward drag off to route swipe-back and pops!
        final swipePopRoute = await tester.startGesture(
          const Offset(80, 400),
          kind: PointerDeviceKind.touch,
        );
        await swipePopRoute.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await swipePopRoute.moveBy(const Offset(220, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await swipePopRoute.up();
        await tester.pumpAndSettle();

        expect(find.text('CarouselPage0'), findsNothing);
        expect(find.text('RootHome'), findsOneWidget);
      },
    );

    testWidgets(
      '5. Rapid consecutive back-swipes across 2 stacked routes both pop immediately with zero 620ms/220ms lockout',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final navKey = GlobalKey<NavigatorState>();
        final guardObserver = TilingBackGuardNavigatorObserver();

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            navigatorObservers: [guardObserver],
            theme: AppTheme.dark(),
            home: const Scaffold(body: Center(child: Text('BaseScreen'))),
          ),
        );

        navKey.currentState!.push(
          SwipeBackPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Center(child: Text('StackedScreen1'))),
          ),
        );
        await tester.pumpAndSettle();

        navKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Center(child: Text('StackedScreen2'))),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('StackedScreen2'), findsOneWidget);

        // First swipe-back pops StackedScreen2.
        final swipe1 = await tester.startGesture(
          const Offset(60, 400),
          kind: PointerDeviceKind.touch,
        );
        await swipe1.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 8));
        await swipe1.moveBy(const Offset(220, 0));
        await tester.pump(const Duration(milliseconds: 8));
        await swipe1.up();
        await tester.pumpAndSettle();

        expect(find.text('StackedScreen2'), findsNothing);
        expect(find.text('StackedScreen1'), findsOneWidget);
        expect(TilingLayoutController.instance.isPopTransitionActive, isFalse);

        // Immediately (0ms wall-clock delay) perform second swipe-back to pop StackedScreen1.
        final swipe2 = await tester.startGesture(
          const Offset(60, 400),
          kind: PointerDeviceKind.touch,
        );
        await swipe2.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 8));
        await swipe2.moveBy(const Offset(220, 0));
        await tester.pump(const Duration(milliseconds: 8));
        await swipe2.up();
        await tester.pumpAndSettle();

        expect(find.text('StackedScreen1'), findsNothing);
        expect(find.text('BaseScreen'), findsOneWidget);
      },
    );

    testWidgets(
      '6. HandOffSwipeBackPageRoute, SwipeableChatTile directional drag, SwipeBackBlocker, and TileViewportScope vertical split viewInsets work cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Part A: TileViewportScope.viewInsetsOf subtracts bottom neighbor space in vertical split.
        late EdgeInsets topTileInsetsWhen300;
        late EdgeInsets topTileInsetsWhen460;

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(800, 800),
                viewInsets: EdgeInsets.only(bottom: 300),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    width: 800,
                    height: 400,
                    child: TileViewportScope(
                      tileId: 'top_chat_tile',
                      isChatTile: true,
                      hasBottomNeighbor: true,
                      child: Builder(
                        builder: (ctx) {
                          topTileInsetsWhen300 =
                              TileViewportScope.viewInsetsOf(ctx);
                          return const SizedBox.expand();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(topTileInsetsWhen300.bottom, 0.0);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(800, 800),
                viewInsets: EdgeInsets.only(bottom: 460),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    width: 800,
                    height: 400,
                    child: TileViewportScope(
                      tileId: 'top_chat_tile',
                      isChatTile: true,
                      hasBottomNeighbor: true,
                      child: Builder(
                        builder: (ctx) {
                          topTileInsetsWhen460 =
                              TileViewportScope.viewInsetsOf(ctx);
                          return const SizedBox.expand();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(topTileInsetsWhen460.bottom, 60.0);

        // Part B: HandOffSwipeBackPageRoute keeps swipe-back mounted after 0ms push,
        // SwipeableChatTile without onRightSwipe yields rightward swipe to route pop,
        // and SwipeBackBlocker yields to custom horizontal controls.
        final navKey = GlobalKey<NavigatorState>();
        ChatSwipeAction? triggeredLeftAction;
        double customScrubberDelta = 0.0;

        final dummyChat = Chat(
          id: 'archived_1',
          chatType: 'private',
          name: 'Archived Peer',
          updatedAt: '2026-11-24T12:00:00Z',
          isArchived: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            theme: AppTheme.dark(),
            home: const Scaffold(body: Center(child: Text('MainList'))),
          ),
        );

        navKey.currentState!.push(
          HandOffSwipeBackPageRoute<void>(
            builder: (_) => Scaffold(
              body: Column(
                children: [
                  SwipeableChatTile(
                    chat: dummyChat,
                    overrideAction: ChatSwipeAction.archive,
                    onAction: (action) async {
                      triggeredLeftAction = action;
                    },
                    child: const SizedBox(
                      height: 72,
                      width: double.infinity,
                      child: Center(child: Text('ArchivedChatRow')),
                    ),
                  ),
                  SwipeBackBlocker(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (d) {
                        customScrubberDelta += d.delta.dx;
                      },
                      child: const SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: Center(child: Text('WaveformScrubber')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('ArchivedChatRow'), findsOneWidget);

        // Dragging right on SwipeBackBlocker moves custom scrubber without popping route.
        final scrubDrag = await tester.startGesture(
          tester.getCenter(find.text('WaveformScrubber')),
          kind: PointerDeviceKind.touch,
        );
        await scrubDrag.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 8));
        await scrubDrag.moveBy(const Offset(160, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await scrubDrag.up();
        await tester.pumpAndSettle();
        expect(customScrubberDelta, greaterThan(100.0));
        expect(find.text('ArchivedChatRow'), findsOneWidget);

        // Swiping left on SwipeableChatTile triggers unarchive action without popping.
        final rowCenter = tester.getCenter(find.text('ArchivedChatRow'));
        final leftRowDrag = await tester.startGesture(
          rowCenter,
          kind: PointerDeviceKind.touch,
        );
        await leftRowDrag.moveBy(const Offset(-20, 0));
        await tester.pump(const Duration(milliseconds: 8));
        await leftRowDrag.moveBy(const Offset(-140, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await leftRowDrag.up();
        await tester.pumpAndSettle();
        expect(triggeredLeftAction, ChatSwipeAction.archive);
        expect(find.text('ArchivedChatRow'), findsOneWidget);

        // Swiping right directly on SwipeableChatTile (with onRightSwipe == null)
        // yields to HandOffSwipeBackPageRoute and pops back to MainList!
        final rightRowDrag = await tester.startGesture(
          rowCenter,
          kind: PointerDeviceKind.touch,
        );
        await rightRowDrag.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 8));
        await rightRowDrag.moveBy(const Offset(210, 0));
        await tester.pump(const Duration(milliseconds: 8));
        await rightRowDrag.up();
        await tester.pumpAndSettle();

        expect(find.text('ArchivedChatRow'), findsNothing);
        expect(find.text('MainList'), findsOneWidget);
      },
    );

    testWidgets(
      '7. Liquid Glass pill tab bar, switch, and slider block route swipe-back while root-route SwipeableChatTile supports bidirectional swipes',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final navKey = GlobalKey<NavigatorState>();
        final glassProvider = _ForcedGlassProvider(GlassMode.full);
        final rootChat = Chat(
          id: 'root_chat_1',
          chatType: 'private',
          name: 'Root Peer',
          updatedAt: '2026-11-24T12:00:00Z',
        );
        final List<ChatSwipeAction> rootSwipeActions = <ChatSwipeAction>[];

        int selectedTab = 0;
        bool glassSwitchValue = false;
        double glassSliderValue = 0.2;

        await tester.pumpWidget(
          ChangeNotifierProvider<LiquidGlassProvider>.value(
            value: glassProvider,
            child: MaterialApp(
              navigatorKey: navKey,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: Center(
                  child: SwipeableChatTile(
                    chat: rootChat,
                    overrideAction: ChatSwipeAction.read,
                    onAction: (action) async {
                      rootSwipeActions.add(action);
                    },
                    child: const SizedBox(
                      key: ValueKey<String>('root_chat_row'),
                      height: 72,
                      width: double.infinity,
                      child: Center(child: Text('RootChatRow')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Issue 3A regression check: On root MainScreen (canPop == false),
        // BOTH rightward and leftward swipes on SwipeableChatTile trigger onAction.
        final rootRowCenter = tester.getCenter(
          find.byKey(const ValueKey<String>('root_chat_row')),
        );
        final rootRightDrag = await tester.startGesture(
          rootRowCenter,
          kind: PointerDeviceKind.touch,
        );
        await rootRightDrag.moveBy(const Offset(24, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await rootRightDrag.moveBy(const Offset(120, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await rootRightDrag.up();
        await tester.pumpAndSettle();

        final rootLeftDrag = await tester.startGesture(
          rootRowCenter,
          kind: PointerDeviceKind.touch,
        );
        await rootLeftDrag.moveBy(const Offset(-24, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await rootLeftDrag.moveBy(const Offset(-120, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await rootLeftDrag.up();
        await tester.pumpAndSettle();

        expect(rootSwipeActions, equals([
          ChatSwipeAction.read,
          ChatSwipeAction.read,
        ]));

        // Issue 1 regression check: Push a SwipeBackPageRoute containing
        // LiquidGlassTabBar.buildGlassPillBar (EmojiStickerPanel style),
        // LiquidGlassSwitch, and AdaptiveSwitch / LiquidGlassSlider.
        navKey.currentState!.push(
          SwipeBackPageRoute<void>(
            builder: (_) => StatefulBuilder(
              builder: (ctx, setLocalState) {
                final barStyle = glassProvider.createStyle(
                  context: ctx,
                  cornerRadius: 20,
                  refractionIndex: 1.1,
                  refractionWidth: 24,
                );
                final tabBar = LiquidGlassTabBar(
                  items: [
                    LiquidGlassTabBarItem(
                      label: 'Em',
                      iconBuilder: (_, __) => const SizedBox.shrink(),
                    ),
                    LiquidGlassTabBarItem(
                      label: 'St',
                      iconBuilder: (_, __) => const SizedBox.shrink(),
                    ),
                    LiquidGlassTabBarItem(
                      label: 'Gf',
                      iconBuilder: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                  selectedIndex: selectedTab,
                  onChanged: (idx) => setLocalState(() => selectedTab = idx),
                  width: 240,
                  height: 44,
                  alignment: Alignment.bottomCenter,
                  margin: const EdgeInsets.only(bottom: 24),
                  itemPadding: 3,
                  swell: null,
                  style: barStyle,
                  itemStyle: const LiquidGlassTabItemStyle(
                    iconSize: 0,
                    underGlassIconSize: 0,
                    iconLabelGap: 0,
                    labelFontSize: 13,
                  ),
                  pillStyle: const LiquidGlassTabPillStyle(
                    mode: LiquidGlassPillMode.both,
                    show: true,
                    animated: true,
                    growHeight: 7,
                  ),
                );

                return Scaffold(
                  key: const ValueKey<String>('glass_controls_scaffold'),
                  body: tabBar.buildGlassPillBar(
                    bottomInset: 0,
                    pixelRatio: 1.0,
                    useSync: true,
                    batch: false,
                    body: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          key: ValueKey<String>('unblocked_body_drag_zone'),
                          width: double.infinity,
                          height: 80,
                          child: Center(child: Text('UnblockedBodyZone')),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: LiquidGlassSwitch(
                            key: const ValueKey<String>('raw_lg_switch'),
                            value: glassSwitchValue,
                            onChanged: (v) =>
                                setLocalState(() => glassSwitchValue = v),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: AdaptiveSwitch(
                            key: const ValueKey<String>('adaptive_lg_switch'),
                            value: glassSwitchValue,
                            onChanged: (v) =>
                                setLocalState(() => glassSwitchValue = v),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: LiquidGlassSlider(
                            key: const ValueKey<String>('raw_lg_slider'),
                            value: glassSliderValue,
                            width: 240,
                            onChanged: (v) =>
                                setLocalState(() => glassSliderValue = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();
        _expectNoTranslucentOpacityAboveGlass(tester);

        // 1) Drag rightward across the LiquidGlassTabBar pill overlay.
        final overlayRect = tester.getRect(
          find.byKey(const ValueKey('lg-animated-nav-gesture-overlay')),
        );
        final pillDrag = await tester.startGesture(
          Offset(overlayRect.left + 20, overlayRect.center.dy),
          kind: PointerDeviceKind.touch,
        );
        await pillDrag.moveBy(const Offset(24, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await pillDrag.moveBy(const Offset(160, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester
              .getTopLeft(
                find.byKey(const ValueKey<String>('glass_controls_scaffold')),
              )
              .dx,
          0.0,
        );
        await pillDrag.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          find.byKey(const ValueKey<String>('glass_controls_scaffold')),
          findsOneWidget,
        );
        expect(selectedTab, greaterThan(0));

        // 2) Drag rightward across LiquidGlassSwitch.
        final switchRect = tester.getRect(
          find.byKey(const ValueKey<String>('raw_lg_switch')),
        );
        final switchDrag = await tester.startGesture(
          Offset(switchRect.left + 8, switchRect.center.dy),
          kind: PointerDeviceKind.touch,
        );
        await switchDrag.moveBy(const Offset(24, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await switchDrag.moveBy(const Offset(120, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester
              .getTopLeft(
                find.byKey(const ValueKey<String>('glass_controls_scaffold')),
              )
              .dx,
          0.0,
        );
        await switchDrag.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          find.byKey(const ValueKey<String>('glass_controls_scaffold')),
          findsOneWidget,
        );
        expect(glassSwitchValue, isTrue);

        // 3) Drag rightward across LiquidGlassSlider.
        final sliderRect = tester.getRect(
          find.byKey(const ValueKey<String>('raw_lg_slider')),
        );
        final sliderDrag = await tester.startGesture(
          Offset(sliderRect.left + 32, sliderRect.center.dy),
          kind: PointerDeviceKind.touch,
        );
        await sliderDrag.moveBy(const Offset(24, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await sliderDrag.moveBy(const Offset(120, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester
              .getTopLeft(
                find.byKey(const ValueKey<String>('glass_controls_scaffold')),
              )
              .dx,
          0.0,
        );
        await sliderDrag.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          find.byKey(const ValueKey<String>('glass_controls_scaffold')),
          findsOneWidget,
        );
        expect(glassSliderValue, greaterThan(0.3));

        // 4) Dragging rightward on the non-blocked body zone still pops the route cleanly.
        final bodyZone = tester.getCenter(
          find.byKey(const ValueKey<String>('unblocked_body_drag_zone')),
        );
        final bodyPopDrag = await tester.startGesture(
          bodyZone,
          kind: PointerDeviceKind.touch,
        );
        await bodyPopDrag.moveBy(const Offset(24, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await bodyPopDrag.moveBy(const Offset(220, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await bodyPopDrag.up();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('glass_controls_scaffold')),
          findsNothing,
        );
        expect(find.text('RootChatRow'), findsOneWidget);
      },
    );
  });
}
