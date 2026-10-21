/// Error codes raised by the calculator engine. Mirrors the web app's `CalculatorErrorCode`.
enum CalculatorErrorCode {
  emptyExpression('EMPTY_EXPRESSION'),
  expressionTooLong('EXPRESSION_TOO_LONG'),
  invalidCharacter('INVALID_CHARACTER'),
  invalidNumber('INVALID_NUMBER'),
  unexpectedToken('UNEXPECTED_TOKEN'),
  unexpectedEnd('UNEXPECTED_END'),
  mismatchedParentheses('MISMATCHED_PARENTHESES'),
  tooComplex('TOO_COMPLEX'),
  divisionByZero('DIVISION_BY_ZERO'),
  moduloByZero('MODULO_BY_ZERO'),
  invalidOperation('INVALID_OPERATION'),
  overflow('OVERFLOW'),
  invalidInput('INVALID_INPUT');

  const CalculatorErrorCode(this.wire);

  /// The SCREAMING_SNAKE_CASE name used by the web app.
  final String wire;
}

/// Error raised for any user-facing calculation problem. Messages are safe to show to users.
class CalculatorError implements Exception {
  const CalculatorError(this.code, this.message, [this.position]);

  final CalculatorErrorCode code;
  final String message;

  /// Character offset in the (normalized) source expression, when applicable.
  final int? position;

  @override
  String toString() => 'CalculatorError(${code.wire}): $message';
}

const String overflowMessage = 'The result is too large (limit is ±1e300).';
