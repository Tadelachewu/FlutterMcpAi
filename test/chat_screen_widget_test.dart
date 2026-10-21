import 'package:ai_scientific_calculator/chat/chat_controller.dart';
import 'package:ai_scientific_calculator/chat/chat_models.dart';
import 'package:ai_scientific_calculator/ui/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_api.dart';

Future<FakeChatApi> pumpChat(WidgetTester tester) async {
  // Wide enough that all quick-prompt chips are on screen (they scroll horizontally on phones).
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = FakeChatApi();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatApiProvider.overrideWithValue(api)],
      child: const MaterialApp(home: Scaffold(body: ChatScreen())),
    ),
  );
  await tester.pump();
  return api;
}

void main() {
  testWidgets('shows status pills, streaming text, tool activity and the verified badge', (
    tester,
  ) async {
    final api = await pumpChat(tester);
    expect(find.text('Ollama · qwen3:8b'), findsOneWidget);
    expect(find.text('MCP · 2 tools'), findsOneWidget);

    await tester.tap(find.text('What is sin of 30 degrees?'));
    await tester.pump();
    expect(find.text('Stop'), findsOneWidget);

    api.emit(
      const ToolCallEvent(
        id: 'c1',
        name: 'trigonometry',
        arguments: {'function': 'sin', 'angle': 30},
      ),
    );
    await tester.pump();
    expect(find.text('Tool activity (1)'), findsOneWidget);
    expect(find.text('Using trigonometry…'), findsOneWidget);

    api.emit(
      const ToolResultEvent(
        id: 'c1',
        name: 'trigonometry',
        ok: true,
        executed: true,
        text: 'sin(30°) = 0.5',
      ),
    );
    api.emit(const DeltaEvent('The answer is **0.5**'));
    await tester.pump();
    expect(find.textContaining('The answer is', findRichText: true), findsOneWidget);

    api.emit(
      const FinalEvent(
        content: 'The answer is **0.5**',
        toolsUsed: ['trigonometry'],
        verified: true,
        fallback: false,
      ),
    );
    await api.end();
    await tester.pump();
    expect(find.text('✓ Verified by MCP tool: trigonometry'), findsOneWidget);
    expect(find.text('→ sin(30°) = 0.5'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('Stop cancels and errors are shown', (tester) async {
    final api = await pumpChat(tester);
    await tester.enterText(find.byType(TextField), 'slow one');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(api.cancelled, isTrue);
    expect(find.text('Stopped.'), findsOneWidget);

    await tester.tap(find.text('What is 15% of 800?'));
    await tester.pump();
    api.emit(const ErrorEvent(code: 'busy', message: 'Another AI request is still running.'));
    await api.end();
    await tester.pumpAndSettle();
    expect(find.text('Another AI request is still running.'), findsOneWidget);
  });

  testWidgets('badges for unverified and fallback answers', (tester) async {
    final api = await pumpChat(tester);
    await tester.tap(find.text('What is 15% of 800?'));
    await tester.pump();
    api.emit(
      const FinalEvent(content: 'About 120', toolsUsed: [], verified: false, fallback: false),
    );
    await api.end();
    await tester.pump();
    expect(find.text('⚠ No calculator tool was used'), findsOneWidget);

    await tester.tap(find.text('Calculate (100 + 50) * 4'));
    await tester.pump();
    api.emit(
      const FinalEvent(
        content: '600',
        toolsUsed: ['calculate_expression'],
        verified: true,
        fallback: true,
      ),
    );
    await api.end();
    await tester.pumpAndSettle();
    expect(find.text('AI unavailable — computed directly via MCP'), findsOneWidget);
  });
}
