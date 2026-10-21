import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import 'chat_api.dart';
import 'chat_models.dart';

enum ToolState { running, ok, error, rejected }

class ToolActivity {
  const ToolActivity({
    required this.id,
    required this.name,
    required this.state,
    this.arguments,
    this.text,
  });

  final String id;
  final String name;
  final Map<String, dynamic>? arguments;
  final ToolState state;
  final String? text;

  ToolActivity copyWith({ToolState? state, String? text}) => ToolActivity(
    id: id,
    name: name,
    arguments: arguments,
    state: state ?? this.state,
    text: text ?? this.text,
  );
}

class UiMessage {
  const UiMessage({
    required this.id,
    required this.role,
    this.content = '',
    this.pending = false,
    this.status,
    this.tools = const [],
    this.toolsUsed = const [],
    this.verified = false,
    this.fallback = false,
    this.error,
    this.errorCode,
    this.slow = false,
  });

  final String id;
  final ChatRole role;
  final String content;
  final bool pending;

  /// Transient status line ("Thinking…", "Using trigonometry…").
  final String? status;
  final List<ToolActivity> tools;
  final List<String> toolsUsed;
  final bool verified;
  final bool fallback;
  final String? error;
  final String? errorCode;

  /// True after 15 s without any event while pending.
  final bool slow;

  bool get isUser => role == ChatRole.user;

  UiMessage copyWith({
    String? content,
    bool? pending,
    String? Function()? status,
    List<ToolActivity>? tools,
    List<String>? toolsUsed,
    bool? verified,
    bool? fallback,
    String? error,
    String? errorCode,
    bool? slow,
  }) => UiMessage(
    id: id,
    role: role,
    content: content ?? this.content,
    pending: pending ?? this.pending,
    status: status != null ? status() : this.status,
    tools: tools ?? this.tools,
    toolsUsed: toolsUsed ?? this.toolsUsed,
    verified: verified ?? this.verified,
    fallback: fallback ?? this.fallback,
    error: error ?? this.error,
    errorCode: errorCode ?? this.errorCode,
    slow: slow ?? this.slow,
  );

  /// Applies one stream event to this (assistant) message.
  UiMessage apply(ChatEvent event) => switch (event) {
    StatusEvent(:final message) => copyWith(status: () => message, slow: false),
    DeltaEvent(:final text) => copyWith(content: content + text, status: () => null, slow: false),
    DiscardDraftEvent() => copyWith(content: '', slow: false),
    ToolCallEvent(:final id, :final name, :final arguments) => copyWith(
      status: () => 'Using $name…',
      slow: false,
      tools: [
        ...tools,
        ToolActivity(id: id, name: name, arguments: arguments, state: ToolState.running),
      ],
    ),
    ToolResultEvent() => copyWith(tools: _withResult(event), slow: false),
    FinalEvent() => copyWith(
      content: event.content,
      pending: false,
      status: () => null,
      toolsUsed: event.toolsUsed,
      verified: event.verified,
      fallback: event.fallback,
      slow: false,
    ),
    ErrorEvent(:final code, :final message) => copyWith(
      pending: false,
      status: () => null,
      error: message,
      errorCode: code,
      slow: false,
    ),
  };

  List<ToolActivity> _withResult(ToolResultEvent event) {
    final state = !event.executed
        ? ToolState.rejected
        : event.ok
        ? ToolState.ok
        : ToolState.error;
    final exists = tools.any((t) => t.id == event.id);
    if (!exists) {
      return [
        ...tools,
        ToolActivity(id: event.id, name: event.name, state: state, text: event.text),
      ];
    }
    return [
      for (final t in tools) t.id == event.id ? t.copyWith(state: state, text: event.text) : t,
    ];
  }
}

class ChatState {
  const ChatState({this.messages = const [], this.busy = false});

  final List<UiMessage> messages;
  final bool busy;
}

/// Builds the backend client from the current settings. Overridden in tests with a fake.
final chatApiProvider = Provider<ChatApi>(
  (ref) => ChatApi(baseUrl: apiBaseUrl, bearerToken: apiToken),
);

final healthProvider = FutureProvider.autoDispose<HealthStatus>((ref) {
  return ref.watch(chatApiProvider).health();
});

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(ChatController.new);

class ChatController extends Notifier<ChatState> {
  /// After this long without any event, the UI says the model may still be loading.
  static Duration slowThreshold = const Duration(seconds: 15);

  StreamSubscription<ChatEvent>? _subscription;
  Timer? _slowTimer;
  int _idCounter = 0;

  @override
  ChatState build() {
    ref.onDispose(() {
      _slowTimer?.cancel();
      _subscription?.cancel();
    });
    return const ChatState();
  }

  String _newId() => 'm${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  void _update(String id, UiMessage Function(UiMessage m) change) {
    state = ChatState(
      busy: state.busy,
      messages: [for (final m in state.messages) m.id == id ? change(m) : m],
    );
  }

  void _armSlowTimer(String id) {
    _slowTimer?.cancel();
    _slowTimer = Timer(slowThreshold, () {
      if (state.busy) _update(id, (m) => m.pending ? m.copyWith(slow: true) : m);
    });
  }

  /// Payload sent to the server: completed turns plus the new prompt, last 20, starting with a user.
  List<ChatMessageInput> _buildPayload(String content) {
    final history = state.messages
        .where((m) => !m.pending && m.error == null && m.content.trim().isNotEmpty)
        .map((m) => ChatMessageInput(m.role, _clip(m.content)));
    final all = [...history, ChatMessageInput(ChatRole.user, content)];
    var payload = all.length > maxRequestMessages
        ? all.sublist(all.length - maxRequestMessages)
        : all;
    while (payload.isNotEmpty && payload.first.role == ChatRole.assistant) {
      payload = payload.sublist(1);
    }
    return payload;
  }

  static String _clip(String text) =>
      text.length > maxMessageChars ? text.substring(0, maxMessageChars) : text;

  /// Sends a prompt. Ignored while another request is running or when the text is blank.
  Future<void> send(String text) async {
    final content = _clip(text.trim());
    if (content.isEmpty || state.busy) return;

    final payload = _buildPayload(content);
    final backend = ref.read(chatApiProvider);
    final assistantId = _newId();
    state = ChatState(
      busy: true,
      messages: [
        ...state.messages,
        UiMessage(id: _newId(), role: ChatRole.user, content: content),
        UiMessage(id: assistantId, role: ChatRole.assistant, pending: true, status: 'Connecting…'),
      ],
    );

    final done = Completer<void>();
    var finished = false;
    _armSlowTimer(assistantId);
    _subscription = backend
        .send(payload)
        .listen(
          (event) {
            _update(assistantId, (m) => m.apply(event));
            if (event is FinalEvent || event is ErrorEvent) finished = true;
            if (!finished) _armSlowTimer(assistantId);
          },
          onError: (Object _) {
            if (!finished) {
              finished = true;
              _update(
                assistantId,
                (m) =>
                    m.apply(const ErrorEvent(code: 'internal', message: 'The connection failed.')),
              );
            }
          },
          onDone: () {
            if (!finished) {
              _update(
                assistantId,
                (m) => m.apply(
                  const ErrorEvent(code: 'internal', message: 'The response ended unexpectedly.'),
                ),
              );
            }
            _finishRequest();
            if (!done.isCompleted) done.complete();
          },
        );
    _stopRequest = () {
      if (!finished) {
        finished = true;
        _update(
          assistantId,
          (m) => m.apply(const ErrorEvent(code: 'cancelled', message: 'Stopped.')),
        );
      }
      _finishRequest();
      if (!done.isCompleted) done.complete();
    };
    return done.future;
  }

  void Function()? _stopRequest;

  void _finishRequest() {
    _slowTimer?.cancel();
    _subscription = null;
    _stopRequest = null;
    state = ChatState(messages: state.messages);
  }

  /// Cancels the running request; closing the connection makes the server stop the work.
  Future<void> stop() async {
    final subscription = _subscription;
    final stopRequest = _stopRequest;
    if (subscription == null) return;
    stopRequest?.call();
    await subscription.cancel();
  }

  void clear() {
    if (state.busy) return;
    state = const ChatState();
  }
}
