import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_scientific_calculator/chat/chat_api.dart';
import 'package:ai_scientific_calculator/chat/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Stream<List<int>> chunks(List<String> parts) =>
    Stream.fromIterable(parts.map((p) => utf8.encode(p)));

void main() {
  group('decodeChatEvents (NDJSON)', () {
    test('parses events split across chunks', () async {
      final events = await decodeChatEvents(
        chunks([
          '{"type":"status","mess',
          'age":"Thinking…"}\n{"type":"delta","text":"Hel',
          'lo"}\n',
          '{"type":"delta","text":" world"}\n{"type":"final","content":"Hello world","toolsUsed":["arithmetic"],"verified":true}\n',
        ]),
      ).toList();
      expect(events, hasLength(4));
      expect((events[0] as StatusEvent).message, 'Thinking…');
      expect((events[1] as DeltaEvent).text, 'Hello');
      expect((events[2] as DeltaEvent).text, ' world');
      final last = events[3] as FinalEvent;
      expect(last.verified, isTrue);
      expect(last.fallback, isFalse);
      expect(last.toolsUsed, ['arithmetic']);
    });

    test('handles a multi-byte character split between chunks', () async {
      final bytes = utf8.encode('{"type":"delta","text":"π ≈ 3.14"}\n');
      final splitAt = bytes.indexOf(0xCF) + 1; // inside the 2-byte "π"
      final events = await decodeChatEvents(
        Stream.fromIterable([bytes.sublist(0, splitAt), bytes.sublist(splitAt)]),
      ).toList();
      expect((events.single as DeltaEvent).text, 'π ≈ 3.14');
    });

    test('skips malformed, blank and unknown lines; parses a last line without newline', () async {
      final events = await decodeChatEvents(
        chunks([
          'not json\n',
          '\n',
          '{"type":"future_event","x":1}\n',
          '[1,2,3]\n',
          '{"type":"discard_draft"}\n',
          '{"type":"error","code":"timeout","message":"The model took too long."}',
        ]),
      ).toList();
      expect(events, hasLength(2));
      expect(events[0], isA<DiscardDraftEvent>());
      final error = events[1] as ErrorEvent;
      expect(error.code, 'timeout');
      expect(error.message, 'The model took too long.');
    });

    test('parses tool_call and tool_result', () async {
      final events = await decodeChatEvents(
        chunks([
          '{"type":"tool_call","id":"c1","name":"trigonometry","arguments":{"function":"sin","angle":30}}\n'
              '{"type":"tool_result","id":"c1","name":"trigonometry","ok":true,"executed":false,"text":"sin(30°) = 0.5","result":"0.5"}\n',
        ]),
      ).toList();
      final call = events[0] as ToolCallEvent;
      expect(call.arguments, {'function': 'sin', 'angle': 30});
      final result = events[1] as ToolResultEvent;
      expect(result.executed, isFalse);
      expect(result.result, '0.5');
    });
  });

  group('ChatApi', () {
    test('posts JSON with the conversation and streams events', () async {
      late http.BaseRequest seen;
      String? body;
      final api = ChatApi(
        baseUrl: 'http://127.0.0.1:3000/',
        bearerToken: 'secret',
        clientFactory: () => MockClient.streaming((request, bodyStream) async {
          seen = request;
          body = await bodyStream.bytesToString();
          return http.StreamedResponse(
            chunks(['{"type":"final","content":"4","toolsUsed":[],"verified":false}\n']),
            200,
            headers: {'content-type': 'application/x-ndjson'},
          );
        }),
      );
      final events = await api.send(const [ChatMessageInput(ChatRole.user, '2+2?')]).toList();
      expect(seen.url.toString(), 'http://127.0.0.1:3000/api/chat');
      expect(seen.method, 'POST');
      expect(seen.headers['Content-Type'], startsWith('application/json'));
      expect(seen.headers['Authorization'], 'Bearer secret');
      expect(seen.headers.containsKey('Origin'), isFalse);
      expect(jsonDecode(body!), {
        'messages': [
          {'role': 'user', 'content': '2+2?'},
        ],
      });
      expect(events.single, isA<FinalEvent>());
    });

    test('turns a non-200 JSON error into an ErrorEvent', () async {
      final api = ChatApi(
        baseUrl: 'http://127.0.0.1:3000',
        clientFactory: () => MockClient(
          (_) async => http.Response(
            '{"type":"error","code":"busy","message":"Another AI request is still running."}',
            429,
          ),
        ),
      );
      final event =
          (await api.send(const [ChatMessageInput(ChatRole.user, 'hi')]).single) as ErrorEvent;
      expect(event.code, 'busy');
      expect(event.message, 'Another AI request is still running.');
    });

    test('reports an unreachable server as a network error', () async {
      final api = ChatApi(
        baseUrl: 'http://127.0.0.1:3000',
        clientFactory: () => MockClient((_) async => throw const SocketException('refused')),
      );
      final event =
          (await api.send(const [ChatMessageInput(ChatRole.user, 'hi')]).single) as ErrorEvent;
      expect(event.code, 'network');
      expect(event.message, contains('Could not reach the server'));
    });

    test('cancelling the subscription closes the response stream', () async {
      final upstream = StreamController<List<int>>();
      final cancelled = Completer<void>();
      upstream.onCancel = () => cancelled.complete();
      final api = ChatApi(
        baseUrl: 'http://127.0.0.1:3000',
        clientFactory: () =>
            MockClient.streaming((_, _) async => http.StreamedResponse(upstream.stream, 200)),
      );
      final received = <ChatEvent>[];
      final sub = api.send(const [ChatMessageInput(ChatRole.user, 'hi')]).listen(received.add);
      upstream.add(utf8.encode('{"type":"status","message":"Thinking…"}\n'));
      await pumpEventQueue();
      expect(received.single, isA<StatusEvent>());
      await sub.cancel();
      await cancelled.future.timeout(const Duration(seconds: 1));
    });

    test('health parses the status payload', () async {
      final api = ChatApi(
        baseUrl: 'http://127.0.0.1:3000',
        clientFactory: () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'ai': {
                'provider': 'ollama',
                'reachable': true,
                'modelAvailable': true,
                'model': 'qwen3:8b',
                'version': '0.12.0',
              },
              'mcp': {
                'connected': true,
                'tools': ['arithmetic', 'trigonometry'],
              },
            }),
            200,
          ),
        ),
      );
      final health = await api.health();
      expect(health.aiOk, isTrue);
      expect(health.providerName, 'Ollama');
      expect(health.tools, hasLength(2));
    });
  });
}
