import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/widgets/chat/liquid_glass_input_field.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
  });

  Widget buildTestApp({
    required MarkdownTextEditingController controller,
    required FocusNode focusNode,
    VoidCallback? onSend,
    VoidCallback? onEditLastMessage,
    bool isEmojiPanelOpen = false,
    VoidCallback? onTapInputWhenEmojiOpen,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LiquidGlassProvider()),
        ChangeNotifierProvider(create: (_) => ProfileThemeProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: LiquidGlassInputField(
              enabled: true,
              controller: controller,
              focusNode: focusNode,
              hintText: 'Write a message...',
              onSend: onSend,
              onEditLastMessage: onEditLastMessage,
              isEmojiPanelOpen: isEmojiPanelOpen,
              onTapInputWhenEmojiOpen: onTapInputWhenEmojiOpen,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Enter sends message and Shift+Enter / Ctrl+Enter insert newline when sendByEnter is true', (tester) async {
    await SettingsService().setSendByEnter(true);
    final controller = MarkdownTextEditingController(text: 'Hello');
    final focusNode = FocusNode();
    int sendCount = 0;

    await tester.pumpWidget(
      buildTestApp(
        controller: controller,
        focusNode: focusNode,
        onSend: () => sendCount++,
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    // Press Enter -> should trigger onSend
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sendCount, 1);

    // Move cursor to end and press Shift+Enter -> should insert newline and not send
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(sendCount, 1);
    expect(controller.text, 'Hello\n');
  });

  testWidgets('Ctrl+Enter sends message and Enter inserts newline when sendByEnter is false', (tester) async {
    await SettingsService().setSendByEnter(false);
    final controller = MarkdownTextEditingController(text: 'Line 1');
    final focusNode = FocusNode();
    int sendCount = 0;

    await tester.pumpWidget(
      buildTestApp(
        controller: controller,
        focusNode: focusNode,
        onSend: () => sendCount++,
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    controller.selection = TextSelection.collapsed(offset: controller.text.length);

    // Press Enter -> should insert newline, NOT send
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sendCount, 0);
    expect(controller.text, 'Line 1\n');

    // Press Ctrl+Enter -> should trigger onSend
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(sendCount, 1);
  });

  testWidgets('ArrowUp in empty field triggers onEditLastMessage', (tester) async {
    final controller = MarkdownTextEditingController();
    final focusNode = FocusNode();
    int editLastCount = 0;

    await tester.pumpWidget(
      buildTestApp(
        controller: controller,
        focusNode: focusNode,
        onEditLastMessage: () => editLastCount++,
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    // Empty field -> ArrowUp triggers onEditLastMessage
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(editLastCount, 1);

    // Non-empty field -> ArrowUp does not trigger onEditLastMessage
    controller.text = 'Some draft';
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(editLastCount, 1);
  });

  testWidgets('Formatting hotkeys Ctrl+B and Ctrl+I apply entities to selection', (tester) async {
    final controller = MarkdownTextEditingController(text: 'bold text');
    final focusNode = FocusNode();

    await tester.pumpWidget(
      buildTestApp(
        controller: controller,
        focusNode: focusNode,
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(controller.entities.any((e) => e.type == 'bold' && e.offset == 0 && e.length == 4), isTrue);
  });

  testWidgets('Cursor remains enabled when emoji panel is open', (tester) async {
    final controller = MarkdownTextEditingController(text: 'Hello');
    final focusNode = FocusNode();

    await tester.pumpWidget(
      buildTestApp(
        controller: controller,
        focusNode: focusNode,
        isEmojiPanelOpen: true,
      ),
    );

    await tester.pump();
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.showCursor, isTrue);
  });
}
