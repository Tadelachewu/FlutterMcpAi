import 'decimal.dart';
import 'errors.dart';
import 'format.dart';
import 'parser.dart';
import 'scientific.dart';

export 'errors.dart';
export 'scientific.dart' show AngleUnit;

const int maxAbsExponent = 10000;
final Dec _maxAbsExponent = Dec.fromInt(maxAbsExponent);
final Dec _magnitudeLimit = Dec.fromInt(300);

class ExpressionResult {
  const ExpressionResult({
    required this.expression,
    required this.result,
    required this.usesAngles,
  });

  /// Normalized ASCII expression that was evaluated.
  final String expression;

  /// Result rounded to 15 significant digits.
  final String result;

  /// True when the expression uses a trigonometric function, so the angle unit matters.
  final bool usesAngles;
}

Dec decimalPower(Dec base, Dec exponent) {
  if (exponent.abs() > _maxAbsExponent) {
    throw const CalculatorError(
      CalculatorErrorCode.tooComplex,
      'Exponent is too large (max |exponent| is $maxAbsExponent).',
    );
  }
  if (base.isZero && exponent.isNegative) {
    throw const CalculatorError(
      CalculatorErrorCode.divisionByZero,
      'Zero cannot be raised to a negative power (division by zero).',
    );
  }
  if (base.isNegative && !exponent.isInteger) {
    throw const CalculatorError(
      CalculatorErrorCode.invalidOperation,
      'A negative number cannot be raised to a fractional power (complex results are not supported).',
    );
  }
  if (exponent.isZero) return Dec.one;
  if (base.isZero) return Dec.zero;
  // Cheap magnitude estimate before computing, to avoid huge intermediate values.
  if (log10Abs(base).mul(exponent) > _magnitudeLimit) {
    throw const CalculatorError(CalculatorErrorCode.overflow, overflowMessage);
  }
  if (exponent.isInteger) return assertInRange(base.powInt(exponent.toBigInt()));
  return assertInRange(realPower(base, exponent));
}

Dec decimalSqrt(Dec value) {
  if (value.isNegative) {
    throw const CalculatorError(
      CalculatorErrorCode.invalidOperation,
      'Cannot take the square root of a negative number (complex results are not supported).',
    );
  }
  return value.sqrt();
}

Dec _evaluateCall(String fn, List<Dec> args, AngleUnit angleUnit) {
  final x = args[0];
  final y = args.length > 1 ? args[1] : null;
  if (trigFunctions.contains(fn)) return decimalTrig(fn, x, angleUnit);
  if (hyperbolicFunctions.contains(fn)) return decimalHyperbolic(fn, x);
  return switch (fn) {
    'sqrt' => decimalSqrt(x),
    'cbrt' => decimalCbrt(x),
    'root' => decimalRoot(x, y!, decimalPower),
    'abs' || 'floor' || 'ceil' || 'round' => decimalRound(fn, x),
    'ln' => decimalLn(x),
    'log' => decimalLog(x, y),
    'log2' => decimalLog(x, Dec.two),
    'exp' => decimalExp(x),
    'nCr' => decimalCombinations(x, y!),
    'nPr' => decimalPermutations(x, y!),
    _ => throw CalculatorError(CalculatorErrorCode.invalidOperation, 'Unsupported function "$fn".'),
  };
}

Dec evaluateAst(AstNode node, {AngleUnit angleUnit = AngleUnit.radians}) {
  Dec eval(AstNode n) => evaluateAst(n, angleUnit: angleUnit);
  switch (node) {
    case NumberNode(:final literal):
      return assertInRange(Dec.parse(literal));
    case ConstantNode(:final name):
      return name == 'pi' ? decimalPi : decimalE;
    case UnaryNode(:final op, :final operand):
      final value = eval(operand);
      return op == '-' ? -value : value;
    case FactorialNode(:final operand):
      return decimalFactorial(eval(operand));
    case CallNode(:final fn, :final args):
      return assertInRange(_evaluateCall(fn, args.map(eval).toList(), angleUnit));
    case BinaryNode(:final op, :final left, :final right):
      final l = eval(left);
      final r = eval(right);
      switch (op) {
        case '+':
          return assertInRange(l + r);
        case '-':
          return assertInRange(l - r);
        case '*':
          return assertInRange(l * r);
        case '/':
          if (r.isZero) {
            throw const CalculatorError(
              CalculatorErrorCode.divisionByZero,
              'Division by zero is undefined.',
            );
          }
          return assertInRange(l / r);
        case '%':
          if (r.isZero) {
            throw const CalculatorError(
              CalculatorErrorCode.moduloByZero,
              'Modulo by zero is undefined.',
            );
          }
          // Truncated modulo: sign follows the dividend (same as JavaScript's %).
          return assertInRange(l.mod(r));
        default:
          return decimalPower(l, r);
      }
  }
}

/// Parses and evaluates an expression. Throws [CalculatorError] on any problem.
ExpressionResult evaluateExpression(String input, {AngleUnit angleUnit = AngleUnit.radians}) {
  final ast = parse(input);
  final value = evaluateAst(ast, angleUnit: angleUnit);
  return ExpressionResult(
    expression: stringifyAst(ast),
    result: formatDecimal(value),
    usesAngles: usesAngles(ast),
  );
}

/// Non-throwing variant for UI previews.
sealed class EvaluationOutcome {
  const EvaluationOutcome();
}

class EvaluationSuccess extends EvaluationOutcome {
  const EvaluationSuccess(this.value);
  final ExpressionResult value;
}

class EvaluationFailure extends EvaluationOutcome {
  const EvaluationFailure(this.error);
  final CalculatorError error;
}

EvaluationOutcome tryEvaluateExpression(String input, {AngleUnit angleUnit = AngleUnit.radians}) {
  try {
    return EvaluationSuccess(evaluateExpression(input, angleUnit: angleUnit));
  } on CalculatorError catch (error) {
    return EvaluationFailure(error);
  } catch (_) {
    return const EvaluationFailure(
      CalculatorError(CalculatorErrorCode.invalidInput, 'Could not evaluate expression.'),
    );
  }
}
