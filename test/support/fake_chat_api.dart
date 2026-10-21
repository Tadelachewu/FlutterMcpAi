import 'dart:async';

import 'package:ai_scientific_calculator/chat/chat_api.dart';
import 'package:ai_scientific_calculator/chat/chat_models.dart';

/// A ChatApi whose responses are driven by the test.
class FakeChatApi extends ChatApi {
  FakeChatApi({this.healthStatus}) : super(baseUrl: 'http://127.0.0.1:3000');

  final HealthStatus? healthStatus;
  final List<List<ChatMessageInput>> requests = [];
  StreamController<ChatEvent>? current;
  bool cancelled = false;

  @override
  Stream<ChatEvent> send(List<ChatMessageInput> messages) {
    requests.add(messages);
    cancelled = false;
    final controller = StreamController<ChatEvent>(onCancel: () => cancelled = true);
    current = controller;
    return controller.stream;
  }

  void emit(ChatEvent event) => current!.add(event);

  Future<void> end() => current!.close();

  @override
  Future<HealthStatus> health() async =>
      healthStatus ??
      const HealthStatus(
        provider: 'ollama',
        reachable: true,
        modelAvailable: true,
        model: 'qwen3:8b',
        mcpConnected: true,
        tools: ['arithmetic', 'trigonometry'],
      );
}
