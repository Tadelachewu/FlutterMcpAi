import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum KeyKind { digit, operator, function, action, equals, angle }

class KeyDef {
  const KeyDef(this.label, this.value, this.kind, this.semanticLabel, {this.span = 1});

  final String label;

  /// Text appended to the expression, or an action name (`clear`, `backspace`, `equals`, `angle`).
  final String value;
  final KeyKind kind;
  final String semanticLabel;
  final int span;
}

/// Scientific keys, 5 per row. "angle" toggles DEG/RAD.
const List<KeyDef> scientificKeys = [
  KeyDef('DEG', 'angle', KeyKind.angle, 'Toggle degrees or radians'),
  KeyDef('sin', 'sin(', KeyKind.function, 'Sine'),
  KeyDef('cos', 'cos(', KeyKind.function, 'Cosine'),
  KeyDef('tan', 'tan(', KeyKind.function, 'Tangent'),
  KeyDef('π', 'pi', KeyKind.function, 'Pi'),
  KeyDef('sin⁻¹', 'asin(', KeyKind.function, 'Inverse sine'),
  KeyDef('cos⁻¹', 'acos(', KeyKind.function, 'Inverse cosine'),
  KeyDef('tan⁻¹', 'atan(', KeyKind.function, 'Inverse tangent'),
  KeyDef('e', 'e', KeyKind.function, 'Euler number'),
  KeyDef('n!', '!', KeyKind.function, 'Factorial'),
  KeyDef('ln', 'ln(', KeyKind.function, 'Natural logarithm'),
  KeyDef('log', 'log(', KeyKind.function, 'Logarithm base 10, or log of x with base b'),
  KeyDef('eˣ', 'exp(', KeyKind.function, 'e to the power of'),
  KeyDef('10ˣ', '10^', KeyKind.function, '10 to the power of'),
  KeyDef('x²', '^2', KeyKind.function, 'Square'),
  KeyDef('∛', 'cbrt(', KeyKind.function, 'Cube root'),
  KeyDef('ʸ√x', 'root(', KeyKind.function, 'Nth root: root of x, n'),
  KeyDef('|x|', 'abs(', KeyKind.function, 'Absolute value'),
  KeyDef('nCr', 'nCr(', KeyKind.function, 'Combinations: n choose r'),
  KeyDef(',', ',', KeyKind.function, 'Argument separator'),
];

/// Main keypad, 5 columns; "0" and "=" span two.
const List<KeyDef> mainKeys = [
  KeyDef('AC', 'clear', KeyKind.action, 'Clear all'),
  KeyDef('⌫', 'backspace', KeyKind.action, 'Backspace'),
  KeyDef('(', '(', KeyKind.function, 'Open parenthesis'),
  KeyDef(')', ')', KeyKind.function, 'Close parenthesis'),
  KeyDef('÷', '/', KeyKind.operator, 'Divide'),
  KeyDef('7', '7', KeyKind.digit, '7'),
  KeyDef('8', '8', KeyKind.digit, '8'),
  KeyDef('9', '9', KeyKind.digit, '9'),
  KeyDef('xʸ', '^', KeyKind.function, 'Power'),
  KeyDef('×', '*', KeyKind.operator, 'Multiply'),
  KeyDef('4', '4', KeyKind.digit, '4'),
  KeyDef('5', '5', KeyKind.digit, '5'),
  KeyDef('6', '6', KeyKind.digit, '6'),
  KeyDef('mod', '%', KeyKind.function, 'Modulo'),
  KeyDef('−', '-', KeyKind.operator, 'Subtract or negative sign'),
  KeyDef('1', '1', KeyKind.digit, '1'),
  KeyDef('2', '2', KeyKind.digit, '2'),
  KeyDef('3', '3', KeyKind.digit, '3'),
  KeyDef('√', 'sqrt(', KeyKind.function, 'Square root'),
  KeyDef('+', '+', KeyKind.operator, 'Add'),
  KeyDef('0', '0', KeyKind.digit, '0', span: 2),
  KeyDef('.', '.', KeyKind.digit, 'Decimal point'),
  KeyDef('=', 'equals', KeyKind.equals, 'Equals', span: 2),
];

class CalcKey extends StatelessWidget {
  const CalcKey({
    super.key,
    required this.def,
    required this.onPressed,
    required this.height,
    this.label,
    this.semanticLabel,
  });

  final KeyDef def;
  final VoidCallback onPressed;
  final double height;

  /// Overrides for keys whose text depends on state (the DEG/RAD toggle).
  final String? label;
  final String? semanticLabel;

  (Color, Color) _colors(ColorScheme scheme) => switch (def.kind) {
    KeyKind.digit => (scheme.surfaceContainerHigh, scheme.onSurface),
    KeyKind.function => (scheme.surfaceContainerHighest, scheme.primary),
    KeyKind.operator => (scheme.primaryContainer, scheme.onPrimaryContainer),
    KeyKind.action => (scheme.errorContainer, scheme.onErrorContainer),
    KeyKind.equals => (scheme.primary, scheme.onPrimary),
    KeyKind.angle => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
  };

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors(Theme.of(context).colorScheme);
    final large =
        def.kind == KeyKind.digit || def.kind == KeyKind.operator || def.kind == KeyKind.equals;
    void press() {
      HapticFeedback.selectionClick();
      onPressed();
    }

    return Semantics(
      button: true,
      label: semanticLabel ?? def.semanticLabel,
      onTap: press,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: press,
            child: Center(
              child: Text(
                label ?? def.label,
                style: TextStyle(
                  color: foreground,
                  fontSize: large ? 24 : 16,
                  fontWeight: def.kind == KeyKind.equals ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays out [keys] in rows of [columns] units, honouring each key's span.
class KeyGrid extends StatelessWidget {
  const KeyGrid({
    super.key,
    required this.keys,
    required this.onKey,
    required this.keyHeight,
    required this.semanticLabel,
    this.columns = 5,
    this.spacing = 8,
    this.labelFor,
    this.semanticLabelFor,
  });

  final List<KeyDef> keys;
  final void Function(KeyDef key) onKey;
  final double keyHeight;
  final String semanticLabel;
  final int columns;
  final double spacing;
  final String? Function(KeyDef key)? labelFor;
  final String? Function(KeyDef key)? semanticLabelFor;

  @override
  Widget build(BuildContext context) {
    final rows = <List<KeyDef>>[];
    var current = <KeyDef>[];
    var used = 0;
    for (final key in keys) {
      if (used + key.span > columns) {
        rows.add(current);
        current = [];
        used = 0;
      }
      current.add(key);
      used += key.span;
    }
    if (current.isNotEmpty) rows.add(current);

    return Semantics(
      container: true,
      label: semanticLabel,
      child: Column(
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) SizedBox(height: spacing),
            Row(
              children: [
                for (var i = 0; i < rows[r].length; i++) ...[
                  if (i > 0) SizedBox(width: spacing),
                  Expanded(
                    flex: rows[r][i].span,
                    child: CalcKey(
                      def: rows[r][i],
                      height: keyHeight,
                      label: labelFor?.call(rows[r][i]),
                      semanticLabel: semanticLabelFor?.call(rows[r][i]),
                      onPressed: () => onKey(rows[r][i]),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
