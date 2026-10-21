import 'package:ai_scientific_calculator/chat/chat_controller.dart';
import 'package:ai_scientific_calculator/chat/chat_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_api.dart';

void main() {
  late FakeChatApi api;
  late ProviderContainer container;

  ChatController controller() => container.read(chatControllerProvider.notifier);
  ChatState state() => container.read(chatControllerProvider);
  UiMessage last() => state().messages.last;

  setUp(() {
    api = FakeChatApi();
    container = ProviderContainer(overrides: [chatApiProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
  });

  test('streams a verified answer with tool activity', () async {
    final done = controller().send('What is sin of 30 degrees?');
    expect(state().busy, isTrue);
    expect(last().status, 'Connecting…');

    api.emit(const StatusEvent('Thinking…'));
    api.emit(const DeltaEvent('Let me '));
    await pumpEventQueue();
    expect(last().status, isNull);
    expect(last().content, 'Let me ');

    api.emit(const DiscardDraftEvent());
    api.emit(const ToolCallEvent(id: 'c1', name: 'trigonometry', arguments: {'angle': 30}));
    await pumpEventQueue();
    expect(last().content, isEmpty);
    expect(last().tools.single.state, ToolState.running);
    expect(last().status, 'Using trigonometry…');

    api.emit(
      const ToolResultEvent(
        id: 'c1',
        name: 'trigonometry',
        ok: true,
        executed: true,
        text: 'sin(30°) = 0.5',
        result: '0.5',
      ),
    );
    api.emit(const DeltaEvent('sin(30°) = **0.5**'));
    api.emit(
      const FinalEvent(
        content: 'sin(30°) = **0.5**',
        toolsUsed: ['trigonometry'],
        verified: true,
        fallback: false,
      ),
    );
    await api.end();
    await done;

    expect(state().busy, isFalse);
    final m = last();
    expect(m.pending, isFalse);
    expect(m.verified, isTrue);
    expect(m.content, 'sin(30°) = **0.5**');
    expect(m.tools.single.state, ToolState.ok);
    expect(m.tools.single.text, 'sin(30°) = 0.5');
    expect(api.requests.single.single.content, 'What is sin of 30 degrees?');
  });

  test('marks rejected and failed tool calls', () async {
    final done = controller().send('x');
    api.emit(const ToolCallEvent(id: 'a', name: 'arithmetic', arguments: {}));
    api.emit(
      const ToolResultEvent(
        id: 'a',
        name: 'arithmetic',
        ok: false,
        executed: false,
        text: 'bad args',
      ),
    );
    api.emit(
      const ToolResultEvent(id: 'b', name: 'logarithm', ok: false, executed: true, text: 'ln(0)'),
    );
    api.emit(const FinalEvent(content: 'Sorry', toolsUsed: [], verified: false, fallback: false));
    await api.end();
    await done;
    expect(last().tools.map((t) => t.state), [ToolState.rejected, ToolState.error]);
  });

  test('sends completed turns only, trimmed to 20 and starting with a user message', () async {
    for (var i = 0; i < 12; i++) {
      final done = controller().send('question $i');
      if (i == 3) {
        api.emit(const ErrorEvent(code: 'timeout', message: 'The model took too long.'));
      } else {
        api.emit(
          FinalEvent(content: 'answer $i', toolsUsed: const [], verified: false, fallback: false),
        );
      }
      await api.end();
      await done;
    }
    final done = controller().send('final question');
    final payload = api.requests.last;
    expect(payload.length, lessThanOrEqualTo(maxRequestMessages));
    expect(payload.first.role, ChatRole.user);
    expect(payload.last.content, 'final question');
    expect(payload.last.role, ChatRole.user);
    // The errored turn's assistant reply is never sent back.
    expect(payload.where((m) => m.content == 'answer 3'), isEmpty);
    api.emit(const FinalEvent(content: 'ok', toolsUsed: [], verified: false, fallback: false));
    await api.end();
    await done;
  });

  test('stop cancels the request and shows Stopped.', () async {
    final done = controller().send('slow question');
    api.emit(const StatusEvent('Thinking…'));
    await pumpEventQueue();
    await controller().stop();
    await done;
    expect(api.cancelled, isTrue);
    expect(state().busy, isFalse);
    expect(last().error, 'Stopped.');
    expect(last().errorCode, 'cancelled');
  });

  test('shows server errors such as busy', () async {
    final done = controller().send('hi');
    api.emit(const ErrorEvent(code: 'busy', message: 'Another AI request is still running.'));
    await api.end();
    await done;
    expect(last().error, 'Another AI request is still running.');
    expect(last().errorCode, 'busy');
    expect(state().busy, isFalse);
  });

  test('a stream that ends without a final event is reported', () async {
    final done = controller().send('hi');
    api.emit(const DeltaEvent('partial'));
    await api.end();
    await done;
    expect(last().error, 'The response ended unexpectedly.');
  });

  test('ignores sends while busy and blank prompts', () async {
    final done = controller().send('first');
    await controller().send('second');
    await controller().send('   ');
    expect(api.requests, hasLength(1));
    api.emit(const FinalEvent(content: 'ok', toolsUsed: [], verified: false, fallback: false));
    await api.end();
    await done;
  });

  test('flags a slow response after the threshold without events', () async {
    final previous = ChatController.slowThreshold;
    ChatController.slowThreshold = const Duration(milliseconds: 30);
    addTearDown(() => ChatController.slowThreshold = previous);

    final done = controller().send('hi');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(last().slow, isTrue);
    api.emit(const StatusEvent('Thinking…'));
    await pumpEventQueue();
    expect(last().slow, isFalse);
    api.emit(const FinalEvent(content: 'ok', toolsUsed: [], verified: false, fallback: false));
    await api.end();
    await done;
  });

  test('clear empties the conversation when idle', () async {
    final done = controller().send('hi');
    controller().clear();
    expect(state().messages, isNotEmpty);
    api.emit(const FinalEvent(content: 'ok', toolsUsed: [], verified: false, fallback: false));
    await api.end();
    await done;
    controller().clear();
    expect(state().messages, isEmpty);
  });
}
