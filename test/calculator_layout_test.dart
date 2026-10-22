// The display stays pinned at the top and every key stays fully on screen, on phones (portrait
// and landscape) and tablets, even with long expressions and errors.
import 'package:ai_scientific_calculator/app.dart';
import 'package:ai_scientific_calculator/chat/chat_controller.dart';
import 'package:ai_scientific_calculator/ui/widgets/keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_api.dart';

const sizes = {
  'small phone 360x640': Size(360, 640),
  'Pixel 9 412x923': Size(412, 923),
  'phone landscape 923x412': Size(923, 412),
  'small phone landscape 640x360': Size(640, 360),
  'tablet landscape 1280x800': Size(1280, 800),
  'tablet portrait 800x1280': Size(800, 1280),
};

Rect rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);

void main() {
  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('display and all keys are visible: $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(FakeChatApi())],
          child: const CalculatorApp(),
        ),
      );
      await tester.pumpAndSettle();

      final screen = Offset.zero & size;
      final display = find.byKey(const Key('display-expression'));
      final displayBefore = rectOf(tester, find.byType(KeyGrid).first);
      for (final key in [...scientificKeys, ...mainKeys]) {
        final finder = find.bySemanticsLabel(
          key.value == 'angle'
              ? RegExp('^Angle unit')
              : RegExp('^${RegExp.escape(key.semanticLabel)}\$'),
        );
        expect(finder, findsOneWidget, reason: key.semanticLabel);
        final rect = rectOf(tester, finder);
        expect(
          screen.contains(rect.topLeft) && screen.contains(rect.bottomRight - const Offset(1, 1)),
          isTrue,
          reason: '${key.semanticLabel} at $rect is off screen ($name)',
        );
        expect(rect.height, greaterThanOrEqualTo(28), reason: '${key.semanticLabel} too small');
      }
      expect(rectOf(tester, display).top, lessThan(size.height / 3));

      // A long expression and an error must not move or resize anything.
      final digit = find.bySemanticsLabel('7');
      final keyBefore = rectOf(tester, digit);
      for (var i = 0; i < 60; i++) {
        await tester.tap(digit);
      }
      await tester.tap(find.bySemanticsLabel('Divide'));
      await tester.tap(find.bySemanticsLabel('0'));
      await tester.tap(find.bySemanticsLabel('Equals'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('display-error')), findsOneWidget);
      expect(rectOf(tester, digit), keyBefore);
      expect(rectOf(tester, find.byType(KeyGrid).first), displayBefore);
    });
  }
}
