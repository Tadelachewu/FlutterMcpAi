import 'package:flutter/material.dart';

import '../../calculator/calculator_controller.dart';
import '../../calculator/format.dart';

class CalculatorDisplay extends StatelessWidget {
  const CalculatorDisplay({super.key, required this.state});

  final CalculatorState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shown = state.expression.isEmpty ? '0' : prettyExpression(state.expression);
    final previous = state.justEvaluated && state.lastEvaluated != null
        ? '${prettyExpression(state.lastEvaluated!)} ='
        : '';
    final preview = state.error == null ? state.preview : null;
    final fontSize = shown.length > 24
        ? 24.0
        : shown.length > 14
        ? 30.0
        : 40.0;
    const mono = ['monospace', 'Menlo', 'Consolas', 'Roboto Mono'];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              height: 20,
              child: Text(
                previous,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFamilyFallback: mono,
                ),
              ),
            ),
          ),
          Semantics(
            liveRegion: true,
            label: 'Calculator display',
            value: state.expression.isEmpty ? '0' : shown,
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  shown,
                  key: const Key('display-expression'),
                  textAlign: TextAlign.right,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                    fontFamilyFallback: mono,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 22),
            child: state.error != null
                ? Semantics(
                    liveRegion: true,
                    child: Text(
                      state.error!,
                      key: const Key('display-error'),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  )
                : Text(
                    preview == null ? '' : '= $preview',
                    key: const Key('display-preview'),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFamilyFallback: mono,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
