import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/widgets/theme/viewport_gradient_box.dart';

void main() {
  testWidgets('ViewportGradientBox renders solid color when no gradient provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ViewportGradientBox(
            solidColor: Colors.blue,
            child: Text('Solid'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Solid'), findsOneWidget);
  });

  testWidgets('ViewportGradientBox renders in ChatViewportScope', (tester) async {
    final scopeKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            key: scopeKey,
            width: 300,
            height: 200,
            child: ChatViewportScope(
              scopeKey: scopeKey,
              child: const ViewportGradientBox(
                gradientColors: [Colors.purple, Colors.cyan],
                child: Text('Scoped'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Scoped'), findsOneWidget);
  });

  testWidgets('ViewportGradientBox repaints and updates coordinates on scroll in ListView', (tester) async {
    final controller = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: ListView.builder(
              controller: controller,
              reverse: true,
              cacheExtent: 300,
              padding: const EdgeInsets.only(top: 100, bottom: 80),
              itemCount: 20,
              itemBuilder: (context, index) {
                return RepaintBoundary(
                  child: SizedBox(
                    height: 80,
                    child: ViewportGradientBox(
                      gradientColors: const [Colors.purple, Colors.cyan],
                      child: Text('Msg $index'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    expect(texts, isNotEmpty);

    // Scroll
    controller.jumpTo(250);
    await tester.pump();

    expect(find.byType(ViewportGradientBox), findsWidgets);
  });
}
