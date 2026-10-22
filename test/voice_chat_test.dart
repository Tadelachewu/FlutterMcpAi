import 'package:ai_scientific_calculator/chat/chat_controller.dart';
import 'package:ai_scientific_calculator/chat/chat_models.dart';
import 'package:ai_scientific_calculator/ui/chat_screen.dart';
import 'package:ai_scientific_calculator/voice/voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_api.dart';

class FakeSpeechInput implements SpeechInput {
  FakeSpeechInput({this.available = true});

  final bool available;
  int initializeCalls = 0;
  bool stopped = false;
  void Function(String, bool)? _onWords;
  void Function()? _onDone;
  void Function(String)? _onError;

  bool get listening => _onWords != null;

  @override
  Future<bool> initialize() async {
    initializeCalls++;
    return available;
  }

  @override
  Future<void> listen({
    required void Function(String words, bool isFinal) onWords,
    required void Function() onDone,
    required void Function(String error) onError,
  }) async {
    _onWords = onWords;
    _onDone = onDone;
    _onError = onError;
  }

  void say(String words, {bool isFinal = false}) {
    _onWords!(words, isFinal);
    if (isFinal) _finish();
  }

  void fail(String code) {
    _onError!(code);
    _finish();
  }

  void _finish() {
    _onDone!();
    _onWords = null;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    if (listening) _finish();
  }
}

class FakeSpeechOutput implements SpeechOutput {
  final List<String> spoken = [];
  int stops = 0;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stops++;
}

void main() {
  late FakeChatApi api;
  late FakeSpeechInput input;
  late FakeSpeechOutput output;

  Future<void> pumpChat(WidgetTester tester, {bool micAvailable = true}) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api = FakeChatApi();
    input = FakeSpeechInput(available: micAvailable);
    output = FakeSpeechOutput();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatApiProvider.overrideWithValue(api),
          speechInputProvider.overrideWithValue(input),
          speechOutputProvider.overrideWithValue(output),
        ],
        child: const MaterialApp(home: Scaffold(body: ChatScreen())),
      ),
    );
    await tester.pump();
  }

  Future<void> tapTooltip(WidgetTester tester, Pattern tooltip) async {
    await tester.tap(find.byWidgetPredicate((w) => w is Tooltip && w.message!.contains(tooltip)));
    await tester.pump();
  }

  String inputText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('sound mode: a spoken question is sent and the answer is read aloud', (tester) async {
    await pumpChat(tester);
    await tapTooltip(tester, 'Sound mode off');
    expect(find.byIcon(Icons.volume_up), findsOneWidget);

    await tapTooltip(tester, 'Speak your question');
    expect(input.listening, isTrue);
    expect(find.text('Listening…'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);

    input.say('What is 15%');
    await tester.pump();
    expect(inputText(tester), 'What is 15%');
    expect(api.requests, isEmpty);

    input.say('What is 15% of 800?', isFinal: true);
    await tester.pump();
    expect(api.requests.single.single.content, 'What is 15% of 800?');
    expect(inputText(tester), isEmpty);

    api.emit(
      const FinalEvent(
        content: '15% of 800 = **120**',
        toolsUsed: ['percentage'],
        verified: true,
        fallback: false,
      ),
    );
    await api.end();
    await tester.pumpAndSettle();
    expect(output.spoken, ['15% of 800 = 120']);
  });

  testWidgets('sound mode off: speech only fills the text box', (tester) async {
    await pumpChat(tester);
    await tapTooltip(tester, 'Speak your question');
    input.say('square root of 144', isFinal: true);
    await tester.pump();
    expect(inputText(tester), 'square root of 144');
    expect(api.requests, isEmpty);

    await tester.tap(find.text('Send'));
    await tester.pump();
    api.emit(const FinalEvent(content: '12', toolsUsed: [], verified: false, fallback: false));
    await api.end();
    await tester.pumpAndSettle();
    expect(output.spoken, isEmpty);
  });

  testWidgets('errors are read aloud in sound mode, Stop is not', (tester) async {
    await pumpChat(tester);
    await tapTooltip(tester, 'Sound mode off');
    await tester.tap(find.text('What is 15% of 800?'));
    await tester.pump();
    api.emit(const ErrorEvent(code: 'busy', message: 'Another AI request is still running.'));
    await api.end();
    await tester.pumpAndSettle();
    expect(output.spoken, ['Another AI request is still running.']);

    await tester.tap(find.widgetWithText(ActionChip, 'What is 15% of 800?'));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(output.spoken, hasLength(1));
  });

  testWidgets('tapping the mic again stops listening', (tester) async {
    await pumpChat(tester);
    await tapTooltip(tester, 'Speak your question');
    await tapTooltip(tester, 'Stop listening');
    expect(input.stopped, isTrue);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });

  testWidgets('explains when speech recognition is unavailable, and can retry', (tester) async {
    await pumpChat(tester, micAvailable: false);
    await tapTooltip(tester, 'Speak your question');
    await tester.pump();
    expect(find.textContaining('Allow microphone access'), findsOneWidget);
    // The notice doesn't cover the mic, so the user can retry right away.
    await tapTooltip(tester, 'Speak your question');
    expect(input.initializeCalls, 2);
    await tapTooltip(tester, 'Dismiss');
    expect(find.textContaining('Allow microphone access'), findsNothing);
  });

  testWidgets('listening that ends without any words says so', (tester) async {
    await pumpChat(tester);
    await tapTooltip(tester, 'Speak your question');
    await input.stop();
    await tester.pump();
    expect(find.textContaining("Didn't catch that"), findsOneWidget);
  });

  testWidgets('recognizer errors are shown', (tester) async {
    await pumpChat(tester);
    await tapTooltip(tester, 'Speak your question');
    input.fail('error_no_match');
    await tester.pump();
    expect(find.textContaining("Didn't catch that"), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });

  testWidgets('turning sound mode off stops speech', (tester) async {
    await pumpChat(tester);
    await tapTooltip(tester, 'Sound mode off');
    await tapTooltip(tester, 'Sound mode on');
    expect(output.stops, greaterThan(0));
  });

  test('speakableText drops Markdown', () {
    expect(speakableText('15% of 800 = **120**'), '15% of 800 = 120');
    expect(speakableText('# Result\n`x` = [12](http://a)'), 'Result x = 12');
  });
}
