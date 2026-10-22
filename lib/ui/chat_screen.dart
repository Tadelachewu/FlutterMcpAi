import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_controller.dart';
import '../chat/chat_models.dart';
import '../voice/voice.dart';
import 'widgets/badge.dart';
import 'widgets/status_pill.dart';
import 'widgets/tool_activity.dart';

const List<String> quickPrompts = [
  'What is 15% of 800?',
  'Calculate (100 + 50) * 4',
  'What is the square root of 144?',
  'What is sin of 30 degrees?',
  'How many ways to choose 5 cards from 52?',
];

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _inputFocus = FocusNode(debugLabel: 'chat-input');

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final value = text ?? _input.text;
    if (value.trim().isEmpty || ref.read(chatControllerProvider).busy) return;
    ref.read(speechOutputProvider).stop();
    ref.read(chatControllerProvider.notifier).send(value);
    if (text == null) _input.clear();
  }

  /// Mic button: dictate into the text box. In sound mode the question is sent when you stop.
  Future<void> _toggleMic() async {
    final voice = ref.read(voiceProvider.notifier);
    if (ref.read(voiceProvider).listening) {
      await voice.stop();
      return;
    }
    await voice.start((words, isFinal) {
      if (!mounted) return;
      _input.value = TextEditingValue(
        text: words,
        selection: TextSelection.collapsed(offset: words.length),
      );
      if (isFinal && ref.read(soundModeProvider) && words.trim().isNotEmpty) _send();
    });
  }

  /// In sound mode, reads the finished answer (or its error) aloud.
  void _speakFinished(ChatState? previous, ChatState next) {
    if (!ref.read(soundModeProvider) || previous == null || !previous.busy || next.busy) return;
    if (next.messages.isEmpty) return;
    final last = next.messages.last;
    if (last.isUser || last.errorCode == 'cancelled') return;
    final text = speakableText(last.error ?? last.content);
    if (text.isNotEmpty) ref.read(speechOutputProvider).speak(text);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    ref.listen(chatControllerProvider, (previous, next) {
      _scrollToEnd();
      _speakFinished(previous, next);
    });
    final voiceError = ref.watch(voiceProvider.select((v) => v.error));
    final listening = ref.watch(voiceProvider.select((v) => v.listening));
    final soundMode = ref.watch(soundModeProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
          child: Row(
            children: [
              const Expanded(child: HealthPills()),
              IconButton(
                tooltip: soundMode
                    ? 'Sound mode on: answers are read aloud. Tap to turn off.'
                    : 'Sound mode off. Tap to have answers read aloud.',
                isSelected: soundMode,
                onPressed: ref.read(soundModeProvider.notifier).toggle,
                icon: const Icon(Icons.volume_off_outlined),
                selectedIcon: const Icon(Icons.volume_up),
              ),
              IconButton(
                tooltip: 'Clear chat',
                onPressed: chat.messages.isEmpty || chat.busy
                    ? null
                    : ref.read(chatControllerProvider.notifier).clear,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: chat.messages.isEmpty
              ? const _EmptyChat()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: chat.messages.length,
                  itemBuilder: (context, i) {
                    final m = chat.messages[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      // Selectable text forms a text-field semantics node; without explicit
                      // containers it would absorb the badge and tool rows of the same message.
                      child: Semantics(
                        container: true,
                        explicitChildNodes: true,
                        child: m.isUser ? _UserBubble(message: m) : _AssistantMessage(message: m),
                      ),
                    );
                  },
                ),
        ),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: quickPrompts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => Center(
              child: ActionChip(
                label: Text(quickPrompts[i]),
                onPressed: chat.busy ? null : () => _send(quickPrompts[i]),
              ),
            ),
          ),
        ),
        // Shown next to the mic instead of a snackbar, which would cover the input row.
        if (voiceError != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.mic_off, size: 18, color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      voiceError,
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: ref.read(voiceProvider.notifier).clearError,
                  icon: Icon(Icons.close, color: theme.colorScheme.onErrorContainer),
                ),
              ],
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {const SingleActivator(LogicalKeyboardKey.enter): _send},
                    child: TextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: maxMessageChars,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: listening ? 'Listening…' : 'Ask a calculation question…',
                        counterText: '',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHigh,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  width: 48,
                  child: IconButton.filledTonal(
                    tooltip: listening ? 'Stop listening' : 'Speak your question',
                    onPressed: chat.busy ? null : _toggleMic,
                    style: listening
                        ? IconButton.styleFrom(
                            backgroundColor: theme.colorScheme.errorContainer,
                            foregroundColor: theme.colorScheme.onErrorContainer,
                          )
                        : null,
                    icon: Icon(listening ? Icons.mic : Icons.mic_none),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: chat.busy
                      ? FilledButton.tonalIcon(
                          onPressed: ref.read(chatControllerProvider.notifier).stop,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Stop'),
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.errorContainer,
                            foregroundColor: theme.colorScheme.onErrorContainer,
                          ),
                        )
                      : ListenableBuilder(
                          listenable: _input,
                          builder: (context, _) => FilledButton.icon(
                            onPressed: _input.text.trim().isEmpty ? null : _send,
                            icon: const Icon(Icons.send),
                            label: const Text('Send'),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(16),
        // Solid card so the text stays readable on the background photo.
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'Ask in plain language. The AI on the server picks a calculator tool, the server runs it '
          'through MCP, and the answer is based on the tool’s result.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final UiMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Semantics(
          container: true,
          label: 'You said',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: SelectableText(message.content, style: TextStyle(color: scheme.onPrimary)),
          ),
        ),
      ),
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({required this.message});

  final UiMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = message;
    final bubbleShape = const BorderRadius.only(
      topLeft: Radius.circular(16),
      topRight: Radius.circular(16),
      bottomLeft: Radius.circular(4),
      bottomRight: Radius.circular(16),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (m.tools.isNotEmpty) ...[ToolActivityList(tools: m.tools), const SizedBox(height: 8)],
        if ((m.content.isNotEmpty || m.pending) && m.error == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: bubbleShape,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Semantics(
              container: true,
              liveRegion: m.pending,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (m.content.isNotEmpty) MarkdownBody(data: m.content, selectable: true),
                  if (m.pending && (m.content.isEmpty || m.status != null))
                    Padding(
                      padding: EdgeInsets.only(top: m.content.isEmpty ? 0 : 8),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              m.status ?? 'Working…',
                              key: const Key('chat-status'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (m.pending && m.slow)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'The model may still be loading. The first request can take a few minutes.',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.tertiary),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (m.error != null)
          Semantics(
            container: true,
            liveRegion: true,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: bubbleShape),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    m.errorCode == 'cancelled' ? Icons.stop_circle_outlined : Icons.error_outline,
                    size: 18,
                    color: scheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(m.error!, style: TextStyle(color: scheme.onErrorContainer)),
                  ),
                ],
              ),
            ),
          ),
        if (!m.pending && m.error == null) ...[
          const SizedBox(height: 6),
          VerificationBadge(message: m),
        ],
      ],
    );
  }
}
