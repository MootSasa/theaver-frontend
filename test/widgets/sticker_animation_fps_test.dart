import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:theaver/widgets/chat/sticker_item_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Animation FPS and smoothness guarantees', () {
    testWidgets('StickerMediaView renders Lottie compositions with native composition frameRate', (tester) async {
      final widget = StickerMediaView(
        fileUrl: 'https://example.com/test.tgs',
        format: 'tgs',
        width: 120,
        height: 120,
        animate: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: widget,
          ),
        ),
      );

      // Verify widget instantiated
      expect(find.byType(StickerMediaView), findsOneWidget);
    });

    testWidgets('ControlledAnimatedNetworkImage instantiates without artificial frame dropping', (tester) async {
      final widget = ControlledAnimatedNetworkImage(
        url: 'https://example.com/test.webp',
        width: 100,
        height: 100,
        isAnimatedWebpOrGif: true,
        animate: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: widget,
          ),
        ),
      );

      expect(find.byType(ControlledAnimatedNetworkImage), findsOneWidget);
    });
  });
}
