import 'decimal.dart';

const int displaySignificantDigits = 15;

/// Rounds to display precision and returns a clean string (no trailing zeros, no "-0").
String formatDecimal(Dec value) {
  final rounded = value.round(displaySignificantDigits);
  return rounded.isZero ? '0' : rounded.toString();
}

/// Pretty-prints an ASCII expression for display.
String prettyExpression(String expr) => expr
    .replaceAll('sqrt', '√')
    .replaceAll('cbrt', '∛')
    .replaceAll(RegExp(r'\bpi\b'), 'π')
    .replaceAll('*', '×')
    .replaceAll('/', '÷')
    .replaceAll('-', '−');
