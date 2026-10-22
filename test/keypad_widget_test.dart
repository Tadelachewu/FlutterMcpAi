import 'package:ai_scientific_calculator/chat/chat_controller.dart';
import 'package:ai_scientific_calculator/ui/calculator_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_api.dart';

Future<FakeChatApi> pumpCalculator(WidgetTester tester) async {
  tester.view.physicalSize = const Size(500, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = FakeChatApi();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatApiProvider.overrideWithValue(api)],
      child: const MaterialApp(home: Scaffold(body: CalculatorScreen())),
    ),
  );
  return api;
}

Future<void> tapKeys(WidgetTester tester, List<String> semanticLabels) async {
  for (final label in semanticLabels) {
    await tester.tap(find.bySemanticsLabel(label));
    await tester.pump();
  }
}

Future<void> openHistory(WidgetTester tester) async {
  await tester.tap(find.textContaining('History'));
  await tester.pumpAndSettle();
}

Future<void> closeSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

String displayText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('display-expression'))).data!;

String previewText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('display-preview'))).data!;

void main() {
  testWidgets('computes 125 × 24 with a live preview and keeps the expression after =', (
    tester,
  ) async {
    await pumpCalculator(tester);
    expect(displayText(tester), '0');
    await tapKeys(tester, ['1', '2', '5', 'Multiply', '2', '4']);
    expect(displayText(tester), '125×24');
    expect(previewText(tester), '= 3000');

    await tapKeys(tester, ['Equals']);
    expect(displayText(tester), '3000');
    expect(find.text('125×24 ='), findsOneWidget);
    expect(find.text('History (1)'), findsOneWidget);
    await openHistory(tester);
    expect(find.text('= 3000'), findsOneWidget); // history entry
  });

  testWidgets('after =, digits start fresh and operators continue', (tester) async {
    await pumpCalculator(tester);
    await tapKeys(tester, ['2', 'Add', '3', 'Equals']);
    expect(displayText(tester), '5');
    await tapKeys(tester, ['Multiply', '2', 'Equals']);
    expect(displayText(tester), '10');
    await tapKeys(tester, ['7']);
    expect(displayText(tester), '7');
  });

  testWidgets('backspace removes a whole function name and pi', (tester) async {
    await pumpCalculator(tester);
    await tapKeys(tester, ['Inverse sine', 'Pi']);
    expect(displayText(tester), 'asin(π');
    await tapKeys(tester, ['Backspace']);
    expect(displayText(tester), 'asin(');
    await tapKeys(tester, ['Backspace']);
    expect(displayText(tester), '0');
  });

  testWidgets('DEG/RAD toggle changes trig results and tags history', (tester) async {
    await pumpCalculator(tester);
    expect(find.text('DEG'), findsOneWidget);
    await tapKeys(tester, ['Sine', '3', '0', 'Close parenthesis']);
    expect(previewText(tester), '= 0.5');
    await tapKeys(tester, ['Equals']);
    await openHistory(tester);
    expect(find.text('sin(30)  deg', findRichText: true), findsOneWidget);
    await closeSheet(tester);

    await tester.tap(find.bySemanticsLabel(RegExp('Angle unit: degrees')));
    await tester.pump();
    expect(find.text('RAD'), findsOneWidget);
    await tapKeys(tester, ['Sine', '0', 'Close parenthesis', 'Equals']);
    await openHistory(tester);
    expect(find.text('sin(0)  rad', findRichText: true), findsOneWidget);
  });

  testWidgets('shows errors in the display and AC clears them', (tester) async {
    await pumpCalculator(tester);
    await tapKeys(tester, ['1', 'Divide', '0', 'Equals']);
    expect(find.byKey(const Key('display-error')), findsOneWidget);
    expect(find.text('Division by zero is undefined.'), findsOneWidget);
    final color = tester.widget<Text>(find.byKey(const Key('display-error'))).style!.color;
    expect(color, Theme.of(tester.element(find.byType(CalculatorScreen))).colorScheme.error);
    await tapKeys(tester, ['Clear all']);
    expect(find.byKey(const Key('display-error')), findsNothing);
    expect(displayText(tester), '0');
  });

  testWidgets('tapping a history entry reuses its result', (tester) async {
    await pumpCalculator(tester);
    await tapKeys(tester, ['6', 'Multiply', '7', 'Equals', 'Clear all']);
    expect(displayText(tester), '0');
    await openHistory(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^6\*7 equals 42')));
    await tester.pumpAndSettle();
    // The sheet closes and the result is back in the display.
    expect(find.byType(BottomSheet), findsNothing);
    expect(displayText(tester), '42');
  });

  testWidgets('hardware keyboard input', (tester) async {
    await pumpCalculator(tester);
    await tester.pump();
    for (final (key, ch) in [
      (LogicalKeyboardKey.digit2, '2'),
      (LogicalKeyboardKey.digit6, '^'), // Shift+6 on a US layout
      (LogicalKeyboardKey.digit1, '1'),
      (LogicalKeyboardKey.digit0, '0'),
    ]) {
      await tester.sendKeyDownEvent(key, character: ch);
      await tester.sendKeyUpEvent(key);
    }
    await tester.pump();
    expect(displayText(tester), '2^10');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(displayText(tester), '1024');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(displayText(tester), '0');
  });

  testWidgets('every key has a semantic label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCalculator(tester);
    for (final label in [
      'Inverse sine',
      'Inverse cosine',
      'Nth root: root of x, n',
      'Combinations: n choose r',
      'Square root',
      'Subtract or negative sign',
      'Decimal point',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    handle.dispose();
  });

  testWidgets('Explain with AI sends a Calculate prompt with the angle unit', (tester) async {
    final api = await pumpCalculator(tester);
    await tapKeys(tester, ['Sine', '3', '0', 'Close parenthesis', 'Equals']);
    await tester.tap(find.text('Explain with AI →'));
    await tester.pump();
    expect(api.requests.single.single.content, 'Calculate sin(30) (angles in degrees)');
    await api.end();
    await tester.pump();
  });
}
