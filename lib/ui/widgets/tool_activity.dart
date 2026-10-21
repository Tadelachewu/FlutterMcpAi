import 'dart:convert';

import 'package:flutter/material.dart';

import '../../chat/chat_controller.dart';

String formatToolArguments(Map<String, dynamic>? args) {
  if (args == null) return '';
  return args.entries
      .map((e) => '${e.key}: ${e.value is String ? jsonEncode(e.value) : e.value}')
      .join(', ');
}

/// Collapsible list of the tool calls made for one answer.
class ToolActivityList extends StatelessWidget {
  const ToolActivityList({super.key, required this.tools});

  final List<ToolActivity> tools;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = tools.any((t) => t.state == ToolState.running);
    return Card(
      margin: EdgeInsets.zero,
      semanticContainer: false,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          leading: Icon(running ? Icons.sync : Icons.build_outlined, size: 18),
          title: Text('Tool activity (${tools.length})', style: theme.textTheme.labelLarge),
          children: [for (final tool in tools) _ToolRow(tool: tool)],
        ),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tool});

  final ToolActivity tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (IconData icon, Color color, String verb) = switch (tool.state) {
      ToolState.running => (Icons.hourglass_top, scheme.primary, 'Using'),
      ToolState.ok => (Icons.check_circle, Colors.green.shade500, 'Used'),
      ToolState.error => (Icons.error_outline, Colors.amber.shade700, 'Error from'),
      ToolState.rejected => (Icons.block, Colors.amber.shade700, 'Rejected (not executed):'),
    };
    const mono = ['monospace', 'Menlo', 'Consolas', 'Roboto Mono'];
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        color: color.withValues(alpha: 0.06),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$verb ',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: '${tool.name}(${formatToolArguments(tool.arguments)})',
                        style: const TextStyle(fontFamilyFallback: mono),
                      ),
                    ],
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                if (tool.text != null && tool.text!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '→ ${tool.text}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFamilyFallback: mono,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
