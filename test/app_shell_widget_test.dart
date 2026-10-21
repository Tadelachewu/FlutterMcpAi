// End-to-end UI test of the phone layout: the real HomeShell, the real ChatApi and NDJSON decoder,
// and a mock HTTP client replaying a response recorded from the backend.
import 'dart:convert';

import 'package:ai_scientific_calculator/app.dart';
import 'package:ai_scientific_calculator/chat/chat_api.dart';
import 'package:ai_scientific_calculator/chat/chat_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const recordedResponse = '''
{"type":"status","message":"Thinking…"}
{"type":"tool_call","id":"call-22c5","name":"percentage","arguments":{"value":800,"percent":15}}
{"type":"tool_result","id":"call-22c5","name":"percentage","ok":true,"executed":true,"text":"15% of 800 = 120","result":"120"}
{"type":"status","message":"Reading tool results…"}
{"type":"delta","text":"15% of 800 = 120"}
{"type":"final","content":"15% of 800 = 120","toolsUsed":["percentage"],"verified":true}
''';

const recordedHealth = {
  'ai': {
    'reachable': true,
    'modelAvailable': true,
    'provider': 'openrouter',
    'model': 'some-model',
  },
  'mcp': {
    'connected': true,
    'tools': ['calculate_expression', 'percentage'],
  },
};

void main() {
  testWidgets('phone layout: a recorded backend answer shows tools, text and the verified badge', (
    tester,
  ) async {
    // Pixel 9: 1080 × 2424 px at 2.625 dpr.
    tester.view.physicalSize = const Size(1080, 2424);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();

    final api = ChatApi(
      baseUrl: 'http://127.0.0.1:3000',
      clientFactory: () => MockClient.streaming((request, _) async {
        if (request.url.path == '/api/health') {
          return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(recordedHealth))), 200);
        }
        return http.StreamedResponse(Stream.value(utf8.encode(recordedResponse)), 200);
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CalculatorApp(),
      ),
    );
    await tester.tap(find.text('AI Chat'));
    await tester.pumpAndSettle();
    expect(find.text('OpenRouter · some-model'), findsOneWidget);

    await tester.tap(find.text('What is 15% of 800?'));
    // The mock HTTP stream completes on the real event loop, which fake time does not advance.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text('Tool activity (1)'), findsOneWidget);
    expect(find.text('→ 15% of 800 = 120'), findsOneWidget);
    expect(find.text('✓ Verified by MCP tool: percentage'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);

    // Screen readers must get the badge as its own node, not merged into the selectable answer.
    final badge = tester.getSemantics(find.text('✓ Verified by MCP tool: percentage'));
    expect(badge.label, '✓ Verified by MCP tool: percentage');
    expect(badge.value, isEmpty);
    final answer = tester.getSemantics(find.text('15% of 800 = 120', findRichText: true).first);
    expect(answer.label, isNot(contains('Verified')));
    expect(
      tester.getSemantics(find.text('Tool activity (1)')).label,
      contains('Tool activity (1)'),
    );
    semantics.dispose();
  });
}
