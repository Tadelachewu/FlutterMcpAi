import 'package:ai_scientific_calculator/app.dart';
import 'package:ai_scientific_calculator/chat/chat_controller.dart';
import 'package:ai_scientific_calculator/ui/calculator_screen.dart';
import 'package:ai_scientific_calculator/ui/chat_screen.dart';
import 'package:ai_scientific_calculator/ui/widgets/curved_nav_bar.dart';

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_api.dart';

void main() {
  testWidgets('curved bottom bar switches tabs and is accessible', (tester) async {
    tester.view.physicalSize = const Size(412, 923);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(FakeChatApi())],
        child: const CalculatorApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CurvedNavBar), findsOneWidget);
    final calcTab = tester.getSemantics(find.bySemanticsLabel('Calculator, tab 1 of 2'));
    expect(calcTab.flagsCollection.isSelected, Tristate.isTrue);
    expect(find.byType(CalculatorScreen), findsOneWidget);

    await tester.tap(find.text('AI Chat'));
    await tester.pumpAndSettle();
    final chatTab = tester.getSemantics(find.bySemanticsLabel('AI Chat, tab 2 of 2'));
    expect(chatTab.flagsCollection.isSelected, Tristate.isTrue);
    // IndexedStack keeps both pages; the chat page is now the visible one.
    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 1);
    expect(find.byType(ChatScreen, skipOffstage: true), findsOneWidget);

    // The bar sits at the bottom of the screen, and its tabs are large enough to tap.
    final bar = tester.getRect(find.byType(CurvedNavBar));
    expect(bar.bottom, 923);
    expect(
      tester.getSize(find.bySemanticsLabel('Calculator, tab 1 of 2')).height,
      greaterThanOrEqualTo(48),
    );
    semantics.dispose();
  });
}
