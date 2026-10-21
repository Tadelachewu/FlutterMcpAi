import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'chat_models.dart';

/// Turns a byte stream of NDJSON into [ChatEvent]s. Lines may be split across chunks; blank,
/// malformed and unknown-type lines are skipped; a final line without "\n" is still parsed.
///
/// Built from a transformer rather than `async*` so that cancelling the subscription cancels the
/// byte stream immediately (an `async*` body parked in `await for` would wait for the next chunk).
Stream<ChatEvent> decodeChatEvents(Stream<List<int>> bytes) {
  var buffer = '';
  return bytes
      .transform(utf8.decoder)
      .transform(
        StreamTransformer<String, ChatEvent>.fromHandlers(
          handleData: (chunk, sink) {
            buffer += chunk;
            var newline = buffer.indexOf('\n');
            while (newline != -1) {
              final event = _parseLine(buffer.substring(0, newline));
              buffer = buffer.substring(newline + 1);
              if (event != null) sink.add(event);
              newline = buffer.indexOf('\n');
            }
          },
          handleDone: (sink) {
            final last = _parseLine(buffer);
            buffer = '';
            if (last != null) sink.add(last);
            sink.close();
          },
        ),
      );
}

ChatEvent? _parseLine(String line) {
  if (line.trim().isEmpty) return null;
  try {
    return ChatEvent.tryParse(jsonDecode(line));
  } on FormatException {
    return null;
  }
}

/// Creates the HTTP client for one request. Injected in tests.
typedef HttpClientFactory = http.Client Function();

http.Client defaultHttpClient() {
  // 10 s to connect; no read timeout, because the first model call can take minutes.
  final inner = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  return IOClient(inner);
}

/// Thin client for the backend. It never talks to the LLM or MCP directly.
class ChatApi {
  ChatApi({required String baseUrl, this.bearerToken, HttpClientFactory? clientFactory})
    : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
      _clientFactory = clientFactory ?? defaultHttpClient;

  final String baseUrl;
  final String? bearerToken;
  final HttpClientFactory _clientFactory;

  Map<String, String> get _authHeaders {
    final token = bearerToken?.trim() ?? '';
    return token.isEmpty ? const {} : {'Authorization': 'Bearer $token'};
  }

  /// Streams the events for one chat request. Cancelling the subscription closes the connection,
  /// which makes the server stop its work. Transport failures are reported as an [ErrorEvent].
  Stream<ChatEvent> send(List<ChatMessageInput> messages) {
    final client = _clientFactory();
    late final StreamController<ChatEvent> controller;
    StreamSubscription<ChatEvent>? upstream;
    var closed = false;

    void finish() {
      if (closed) return;
      closed = true;
      client.close();
      controller.close();
    }

    Future<void> run() async {
      try {
        final request = http.Request('POST', Uri.parse('$baseUrl/api/chat'))
          ..headers.addAll({
            'Content-Type': 'application/json',
            'Accept': 'application/x-ndjson',
            ..._authHeaders,
          })
          ..body = jsonEncode({'messages': messages.map((m) => m.toJson()).toList()});
        final response = await client.send(request);
        if (closed) return;
        if (response.statusCode != 200) {
          controller.add(await _errorFromResponse(response));
          finish();
          return;
        }
        upstream = decodeChatEvents(response.stream).listen(
          controller.add,
          onError: (Object error) {
            if (!closed) controller.add(_networkError(error));
            finish();
          },
          onDone: finish,
        );
      } catch (error) {
        if (!closed) controller.add(_networkError(error));
        finish();
      }
    }

    controller = StreamController<ChatEvent>(
      onListen: run,
      onPause: () => upstream?.pause(),
      onResume: () => upstream?.resume(),
      onCancel: () async {
        closed = true;
        // Closing the client aborts the connection, which tells the server to stop.
        client.close();
        await upstream?.cancel();
      },
    );
    return controller.stream;
  }

  Future<ErrorEvent> _errorFromResponse(http.StreamedResponse response) async {
    var code = 'http_${response.statusCode}';
    var message = 'Request failed (HTTP ${response.statusCode}).';
    try {
      final body = await response.stream.bytesToString();
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        if (json['code'] is String) code = json['code'] as String;
        // Chat errors use {type, code, message}; the health guard uses {error}.
        final text = json['message'] ?? json['error'];
        if (text is String && text.isNotEmpty) message = text;
      }
    } catch (_) {
      // Keep the generic message.
    }
    return ErrorEvent(code: code, message: message);
  }

  ErrorEvent _networkError(Object error) {
    final detail = switch (error) {
      TimeoutException() || SocketException() || http.ClientException() =>
        'Could not reach the server at $baseUrl. Is the backend running? '
            'On the Android emulator, run "adb reverse tcp:3000 tcp:3000".',
      _ => 'The connection to the server failed.',
    };
    return ErrorEvent(code: 'network', message: detail);
  }

  /// `GET /api/health` for the status pills.
  Future<HealthStatus> health() async {
    final client = _clientFactory();
    try {
      final response = await client
          .get(Uri.parse('$baseUrl/api/health'), headers: _authHeaders)
          // Long enough for a sleeping server (e.g. Render's free tier) to wake up.
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        throw HttpException('Health check failed (HTTP ${response.statusCode}).');
      }
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) throw const FormatException('Unexpected health response');
      return HealthStatus.fromJson(json);
    } finally {
      client.close();
    }
  }
}
