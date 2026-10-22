import 'package:flutter/material.dart';

import '../../calculator/calculator_controller.dart';
import '../../calculator/format.dart';

const List<String> _mono = ['monospace', 'Menlo', 'Consolas', 'Roboto Mono'];

/// The calculator screen's display. Its height never changes, so the keypad below it never
/// moves: long expressions scroll sideways (newest characters stay visible) and long error
/// messages are cut at two lines (the full text is in the tooltip and for screen readers).
class CalculatorDisplay extends StatelessWidget {
  const CalculatorDisplay({super.key, required this.state, this.compact = false});

  final CalculatorState state;

  /// Smaller version for short screens (phones in landscape).
  final bool compact;

  static double heightFor({required bool compact}) => compact ? 92 : 132;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shown = state.expression.isEmpty ? '0' : prettyExpression(state.expression);
    final previous = state.justEvaluated && state.lastEvaluated != null
        ? '${prettyExpression(state.lastEvaluated!)} ='
        : '';
    final preview = state.error == null ? state.preview : null;
    final fontSize = switch (shown.length) {
      > 16 => compact ? 22.0 : 28.0,
      > 10 => compact ? 26.0 : 34.0,
      _ => compact ? 30.0 : 42.0,
    };

    return Container(
      height: heightFor(compact: compact),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 6 : 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ExcludeSemantics(
            child: Text(
              previous,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFamilyFallback: _mono,
              ),
            ),
          ),
          Semantics(
            liveRegion: true,
            label: 'Calculator display',
            value: shown,
            excludeSemantics: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Text(
                shown,
                key: const Key('display-expression'),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                  fontFamilyFallback: _mono,
                ),
              ),
            ),
          ),
          SizedBox(
            height: compact ? 18 : 32,
            child: Align(
              alignment: Alignment.centerRight,
              child: state.error != null
                  ? Tooltip(
                      message: state.error!,
                      triggerMode: TooltipTriggerMode.longPress,
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          state.error!,
                          key: const Key('display-error'),
                          textAlign: TextAlign.right,
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                            height: 1.2,
                          ),
                        ),
                      ),
                    )
                  : Text(
                      preview == null ? '' : '= $preview',
                      key: const Key('display-preview'),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (compact ? theme.textTheme.bodyMedium : theme.textTheme.titleMedium)
                          ?.copyWith(color: scheme.onSurfaceVariant, fontFamilyFallback: _mono),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
