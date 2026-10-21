import 'package:flutter/material.dart';

import '../../calculator/calculator_controller.dart';
import '../../calculator/format.dart';

class HistoryPanel extends StatelessWidget {
  const HistoryPanel({
    super.key,
    required this.entries,
    required this.onSelect,
    required this.onClear,
  });

  final List<HistoryEntry> entries;
  final void Function(HistoryEntry entry) onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      // Keep each entry a separate, tappable node for screen readers.
      semanticContainer: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('History', style: theme.textTheme.titleSmall),
                  ),
                ),
                if (entries.isNotEmpty)
                  TextButton(onPressed: onClear, child: const Text('Clear history')),
                if (entries.isEmpty) const SizedBox(height: 48),
              ],
            ),
          ),
          const Divider(height: 1),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No calculations yet.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          else
            for (final entry in entries)
              Semantics(
                button: true,
                label:
                    '${entry.expression} equals ${entry.result}'
                    '${entry.angleUnit == null ? '' : ', ${entry.angleUnit == AngleUnit.degrees ? 'degrees' : 'radians'}'}'
                    '. Use this result.',
                excludeSemantics: true,
                onTap: () => onSelect(entry),
                child: InkWell(
                  onTap: () => onSelect(entry),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: prettyExpression(entry.expression),
                                children: [
                                  if (entry.angleUnit != null)
                                    TextSpan(
                                      text: '  ${entry.angleUnit!.shortLabel}',
                                      style: TextStyle(fontSize: 11, color: scheme.tertiary),
                                    ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text('= ${entry.result}', style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
