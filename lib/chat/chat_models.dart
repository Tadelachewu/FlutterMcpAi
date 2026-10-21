/// Wire protocol for `POST /api/chat` (NDJSON stream of [ChatEvent]s) and `GET /api/health`.
library;

const int maxMessageChars = 2000;
const int maxRequestMessages = 20;
const int maxRequestBytes = 64 * 1024;

enum ChatRole { user, assistant }

class ChatMessageInput {
  const ChatMessageInput(this.role, this.content);

  final ChatRole role;
  final String content;

  Map<String, Object> toJson() => {'role': role.name, 'content': content};
}

/// One event of the response stream. Unknown event types are ignored by [ChatEvent.tryParse].
sealed class ChatEvent {
  const ChatEvent();

  /// Parses one decoded JSON object. Returns null for unknown types or malformed events.
  static ChatEvent? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    String str(String key) => json[key] is String ? json[key] as String : '';
    bool flag(String key) => json[key] == true;
    switch (json['type']) {
      case 'status':
        return StatusEvent(str('message'));
      case 'delta':
        return DeltaEvent(str('text'));
      case 'discard_draft':
        return const DiscardDraftEvent();
      case 'tool_call':
        final args = json['arguments'];
        return ToolCallEvent(
          id: str('id'),
          name: str('name'),
          arguments: args is Map<String, dynamic> ? args : const {},
        );
      case 'tool_result':
        return ToolResultEvent(
          id: str('id'),
          name: str('name'),
          ok: flag('ok'),
          executed: flag('executed'),
          text: str('text'),
          result: json['result'] is String ? json['result'] as String : null,
        );
      case 'final':
        final tools = json['toolsUsed'];
        return FinalEvent(
          content: str('content'),
          toolsUsed: tools is List ? tools.whereType<String>().toList() : const [],
          verified: flag('verified'),
          fallback: flag('fallback'),
        );
      case 'error':
        return ErrorEvent(code: str('code'), message: str('message'));
      default:
        return null;
    }
  }
}

class StatusEvent extends ChatEvent {
  const StatusEvent(this.message);
  final String message;
}

class DeltaEvent extends ChatEvent {
  const DeltaEvent(this.text);
  final String text;
}

class DiscardDraftEvent extends ChatEvent {
  const DiscardDraftEvent();
}

class ToolCallEvent extends ChatEvent {
  const ToolCallEvent({required this.id, required this.name, required this.arguments});
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class ToolResultEvent extends ChatEvent {
  const ToolResultEvent({
    required this.id,
    required this.name,
    required this.ok,
    required this.executed,
    required this.text,
    this.result,
  });
  final String id;
  final String name;
  final bool ok;

  /// False when the server rejected the call before it reached the MCP server.
  final bool executed;
  final String text;
  final String? result;
}

class FinalEvent extends ChatEvent {
  const FinalEvent({
    required this.content,
    required this.toolsUsed,
    required this.verified,
    required this.fallback,
  });
  final String content;
  final List<String> toolsUsed;
  final bool verified;

  /// True when the AI was unavailable and the server computed the expression directly via MCP.
  final bool fallback;
}

class ErrorEvent extends ChatEvent {
  const ErrorEvent({required this.code, required this.message});

  /// Server codes (`busy`, `timeout`, …) plus client-side `network`, `cancelled` and `http_<status>`.
  final String code;
  final String message;
}

class HealthStatus {
  const HealthStatus({
    required this.provider,
    required this.reachable,
    required this.modelAvailable,
    required this.model,
    required this.mcpConnected,
    required this.tools,
    this.version,
    this.mcpError,
  });

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    final ai = json['ai'] is Map<String, dynamic> ? json['ai'] as Map<String, dynamic> : const {};
    final mcp = json['mcp'] is Map<String, dynamic>
        ? json['mcp'] as Map<String, dynamic>
        : const {};
    return HealthStatus(
      provider: ai['provider'] is String ? ai['provider'] as String : 'ollama',
      reachable: ai['reachable'] == true,
      modelAvailable: ai['modelAvailable'] == true,
      model: ai['model'] is String ? ai['model'] as String : '',
      version: ai['version'] is String ? ai['version'] as String : null,
      mcpConnected: mcp['connected'] == true,
      tools: mcp['tools'] is List ? (mcp['tools'] as List).whereType<String>().toList() : const [],
      mcpError: mcp['error'] is String ? mcp['error'] as String : null,
    );
  }

  final String provider;
  final bool reachable;
  final bool modelAvailable;
  final String model;
  final String? version;
  final bool mcpConnected;
  final List<String> tools;
  final String? mcpError;

  bool get aiOk => reachable && modelAvailable;
  bool get isOpenRouter => provider == 'openrouter';
  String get providerName => isOpenRouter ? 'OpenRouter' : 'Ollama';
}
