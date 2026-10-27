import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/widgets/chat/swipe_to_reply_wrapper.dart';
import 'package:theaver/widgets/tiling/trackpad_swipe_back_indicator.dart';

void main() {
  Widget buildHarness({
    required VoidCallback onSwipeBack,
    required VoidCallback onReply,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TrackpadBackGestureWrapper(
          canTriggerBack: () => true,
          onTriggerBack: onSwipeBack,
          child: Center(
            child: SwipeToReplyWrapper(
              onReply: onReply,
              child: const SizedBox(
                key: ValueKey('message-bubble'),
                width: 300,
                height: 80,
                child: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Unfinished trackpad back gesture cancelled by leftward reverse motion does not trigger swipe-to-reply',
    (tester) async {
      int backCount = 0;
      int replyCount = 0;

      await tester.pumpWidget(
        buildHarness(
          onSwipeBack: () => backCount++,
          onReply: () => replyCount++,
        ),
      );

      final bubbleCenter =
          tester.getCenter(find.byKey(const ValueKey('message-bubble')));

      // Hover mouse over message bubble so it is registered as hovered target
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: bubbleCenter);
      await tester.pump();

      final trackpad = TestPointer(2, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(trackpad.panZoomStart(bubbleCenter));
      await tester.pump();

      // Pull right (back gesture direction, panDelta.dx > 0)
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(
          bubbleCenter,
          pan: const Offset(60, 0),
        ),
      );
      await tester.pump();

      // Now reverse left to cancel the back gesture, going past 0 into negative territory
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(
          bubbleCenter,
          pan: const Offset(-80, 0),
        ),
      );
      await tester.pump();

      await tester.sendEventToBinding(trackpad.panZoomEnd());
      await tester.pumpAndSettle();

      expect(backCount, 0, reason: 'Back gesture was reversed/cancelled');
      expect(
        replyCount,
        0,
        reason: 'Cancelling back gesture must never trigger swipe-to-reply',
      );
    },
  );

  testWidgets(
    'Unfinished trackpad swipe-to-reply cancelled by rightward reverse motion does not trigger back navigation',
    (tester) async {
      int backCount = 0;
      int replyCount = 0;

      await tester.pumpWidget(
        buildHarness(
          onSwipeBack: () => backCount++,
          onReply: () => replyCount++,
        ),
      );

      final bubbleCenter =
          tester.getCenter(find.byKey(const ValueKey('message-bubble')));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: bubbleCenter);
      await tester.pump();

      final trackpad = TestPointer(3, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(trackpad.panZoomStart(bubbleCenter));
      await tester.pump();

      // Pull left to start swipe-to-reply (panDelta.dx < 0)
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(
          bubbleCenter,
          pan: const Offset(-70, 0),
        ),
      );
      await tester.pump();

      // Reverse right to cancel swipe-to-reply, going well into positive dx
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(
          bubbleCenter,
          pan: const Offset(90, 0),
        ),
      );
      await tester.pump();

      await tester.sendEventToBinding(trackpad.panZoomEnd());
      await tester.pumpAndSettle();

      expect(replyCount, 0, reason: 'Reply gesture was reversed/cancelled');
      expect(
        backCount,
        0,
        reason: 'Cancelling reply gesture must never trigger back navigation',
      );
    },
  );

  testWidgets(
    'Completed trackpad swipe-to-reply triggers onReply and not onSwipeBack',
    (tester) async {
      int backCount = 0;
      int replyCount = 0;

      await tester.pumpWidget(
        buildHarness(
          onSwipeBack: () => backCount++,
          onReply: () => replyCount++,
        ),
      );

      final bubbleCenter =
          tester.getCenter(find.byKey(const ValueKey('message-bubble')));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: bubbleCenter);
      await tester.pump();

      final trackpad = TestPointer(4, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(trackpad.panZoomStart(bubbleCenter));
      await tester.pump();

      // Pull left past activationThreshold (56px / 0.8 = 70px+)
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(
          bubbleCenter,
          pan: const Offset(-85, 0),
        ),
      );
      await tester.pump();

      await tester.sendEventToBinding(trackpad.panZoomEnd());
      await tester.pumpAndSettle();

      expect(replyCount, 1);
      expect(backCount, 0);
    },
  );
}
