/// Voice for the AI chat: speech-to-text for questions, text-to-speech for answers. Both use the
/// device's own speech services (no extra servers or keys). The interfaces let tests use fakes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Turns speech into text.
abstract interface class SpeechInput {
  /// Prepares the recognizer and asks for microphone permission. False if unavailable/denied.
  Future<bool> initialize();

  /// Listens until the user pauses. [onWords] gets partial text and then the final text;
  /// [onDone] is called when listening ends for any reason; [onError] for recognizer errors.
  Future<void> listen({
    required void Function(String words, bool isFinal) onWords,
    required void Function() onDone,
    required void Function(String error) onError,
  });

  Future<void> stop();
}

/// Reads text aloud.
abstract interface class SpeechOutput {
  Future<void> speak(String text);
  Future<void> stop();
}

class DeviceSpeechInput implements SpeechInput {
  final SpeechToText _stt = SpeechToText();
  void Function()? _onDone;
  void Function(String error)? _onError;

  @override
  Future<bool> initialize() async {
    try {
      return await _stt.initialize(
        onStatus: (status) {
          if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
            _onDone?.call();
          }
        },
        onError: (SpeechRecognitionError error) => _onError?.call(error.errorMsg),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> listen({
    required void Function(String words, bool isFinal) onWords,
    required void Function() onDone,
    required void Function(String error) onError,
  }) async {
    _onDone = onDone;
    _onError = onError;
    await _stt.listen(
      onResult: (result) => onWords(result.recognizedWords, result.finalResult),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Future<void> stop() => _stt.stop();
}

class DeviceSpeechOutput implements SpeechOutput {
  FlutterTts? _tts;

  @override
  Future<void> speak(String text) async {
    final tts = _tts ??= FlutterTts();
    await tts.stop();
    await tts.speak(text);
  }

  @override
  Future<void> stop() async => _tts?.stop();
}

final speechInputProvider = Provider<SpeechInput>((ref) => DeviceSpeechInput());
final speechOutputProvider = Provider<SpeechOutput>((ref) => DeviceSpeechOutput());

/// Sound mode: answers are read aloud and spoken questions are sent as soon as you stop talking.
final soundModeProvider = NotifierProvider<SoundModeController, bool>(SoundModeController.new);

class SoundModeController extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() {
    state = !state;
    if (!state) ref.read(speechOutputProvider).stop();
  }
}

class VoiceState {
  const VoiceState({this.listening = false, this.error});

  final bool listening;

  /// Last problem to show the user, e.g. no microphone permission.
  final String? error;
}

final voiceProvider = NotifierProvider<VoiceController, VoiceState>(VoiceController.new);

class VoiceController extends Notifier<VoiceState> {
  bool? _available;

  @override
  VoiceState build() => const VoiceState();

  /// Starts listening. [onWords] receives the text as it is recognized; isFinal marks the end.
  Future<void> start(void Function(String words, bool isFinal) onWords) async {
    if (state.listening) return;
    final input = ref.read(speechInputProvider);
    // Don't record the app's own voice.
    await ref.read(speechOutputProvider).stop();
    _available ??= await input.initialize();
    if (_available != true) {
      _available = null; // Let the user try again, e.g. after granting the permission.
      state = const VoiceState(
        error:
            'Speech recognition is not available. Allow microphone access for this app, '
            'and check that a speech service (such as the Google app) is installed.',
      );
      return;
    }
    state = const VoiceState(listening: true);
    var finished = false;
    var heard = false;
    await input.listen(
      onWords: (words, isFinal) {
        if (finished) return;
        if (words.trim().isNotEmpty) heard = true;
        if (isFinal) {
          finished = true;
          state = const VoiceState();
        }
        onWords(words, isFinal);
      },
      onDone: () {
        if (finished) return;
        finished = true;
        // Some recognizers end without an error when nothing was said.
        state = heard ? const VoiceState() : VoiceState(error: _describe('error_no_match'));
      },
      onError: (error) {
        finished = true;
        state = VoiceState(error: _describe(error));
      },
    );
  }

  Future<void> stop() async {
    await ref.read(speechInputProvider).stop();
    state = const VoiceState();
  }

  void clearError() => state = VoiceState(listening: state.listening);

  static String _describe(String code) => switch (code) {
    'error_no_match' || 'error_speech_timeout' => "Didn't catch that. Tap the mic and try again.",
    'error_permission' || 'error_insufficient_permissions' => 'Microphone permission was denied.',
    'error_network' || 'error_network_timeout' => 'Speech recognition needs a network connection.',
    _ => 'Speech recognition failed. Try again.',
  };
}

/// Plain text for reading aloud: drops Markdown markers so "**120**" is read as "120".
String speakableText(String markdown) => markdown
    .replaceAll(RegExp(r'[*_`#>]+'), '')
    .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
