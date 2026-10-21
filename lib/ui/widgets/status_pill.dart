import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/chat_controller.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.ok, required this.label, this.tooltip, this.onTap});

  /// null while checking (grey), true for green, false for red.
  final bool? ok;
  final String label;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dot = ok == null
        ? Colors.grey
        : ok!
        ? Colors.green.shade500
        : Colors.red.shade400;
    final state = ok == null ? 'checking' : (ok! ? 'OK' : 'problem');
    final pill = Semantics(
      label: '$label, status $state',
      button: onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: scheme.outlineVariant),
            color: scheme.surfaceContainer,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// AI provider/model and MCP tool-count pills from `GET /api/health`. Tap to re-check.
class HealthPills extends ConsumerWidget {
  const HealthPills({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider);
    void refresh() => ref.invalidate(healthProvider);

    final (bool? aiOk, String aiLabel, String? aiTip) = switch (health) {
      AsyncData(:final value) => (
        value.aiOk,
        !value.reachable
            ? (value.isOpenRouter ? 'OpenRouter unreachable or key rejected' : 'Ollama offline')
            : value.modelAvailable
            ? '${value.providerName} · ${value.model}'
            : value.isOpenRouter
            ? '${value.model} not found or no tool support'
            : '${value.model} not installed',
        value.version == null ? null : 'Ollama ${value.version}',
      ),
      AsyncError() => (
        false,
        'Server unreachable',
        'Check API_BASE_URL in .env and that the server is running.',
      ),
      _ => (null, 'Checking AI model…', null),
    };
    final (bool? mcpOk, String mcpLabel, String? mcpTip) = switch (health) {
      AsyncData(:final value) => (
        value.mcpConnected,
        value.mcpConnected ? 'MCP · ${value.tools.length} tools' : 'MCP server error',
        value.mcpConnected ? value.tools.join(', ') : value.mcpError,
      ),
      AsyncError() => (false, 'MCP status unavailable', null),
      _ => (null, 'Checking MCP…', null),
    };

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        StatusPill(ok: aiOk, label: aiLabel, tooltip: aiTip, onTap: refresh),
        StatusPill(
          ok: mcpOk,
          label: mcpLabel,
          tooltip: (mcpTip?.isEmpty ?? true) ? null : mcpTip,
          onTap: refresh,
        ),
      ],
    );
  }
}
