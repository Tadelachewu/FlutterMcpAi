import 'package:ai_scientific_calculator/calculator/decimal.dart';
import 'package:ai_scientific_calculator/calculator/evaluator.dart';
import 'package:ai_scientific_calculator/calculator/format.dart';
import 'package:flutter_test/flutter_test.dart';

String calc(String expr, [AngleUnit unit = AngleUnit.radians]) =>
    evaluateExpression(expr, angleUnit: unit).result;

CalculatorErrorCode errorCode(String expr, [AngleUnit unit = AngleUnit.radians]) {
  final outcome = tryEvaluateExpression(expr, angleUnit: unit);
  if (outcome is EvaluationFailure) return outcome.error.code;
  fail('Expected "$expr" to fail, got ${(outcome as EvaluationSuccess).value.result}');
}

void expectResults(Map<String, String> cases, [AngleUnit unit = AngleUnit.radians]) {
  cases.forEach((expr, expected) {
    expect(calc(expr, unit), expected, reason: expr);
  });
}

void main() {
  group('arithmetic', () {
    test('basic vectors', () {
      expectResults({
        '125 * 24': '3000',
        '(100 + 50) * 4': '600',
        '0.1 + 0.2': '0.3',
        '1/3': '0.333333333333333',
        '2 ^ 3 ^ 2': '512',
        '-2 ^ 2': '-4',
        '(-2) ^ 2': '4',
        '-7 % 3': '-1',
        'sqrt(2)': '1.4142135623731',
      });
    });

    test('limits', () {
      expect(errorCode('10 ^ 400'), CalculatorErrorCode.overflow);
      expect(errorCode('2 ^ 100000'), CalculatorErrorCode.tooComplex);
    });

    test('aliases and formatting', () {
      expectResults({
        '6 × 7': '42',
        '8 ÷ 2': '4',
        '5 − 7': '-2',
        '2 ** 10': '1024',
        '√(16)': '4',
        '∛(27)': '3',
        'π': '3.14159265358979',
        '10^25': '1e+25',
        '10^-8': '1e-8',
        '0.000001': '0.000001',
        '1 - 1': '0',
        '-0': '0',
        '.5 + .5': '1',
        '1e5': '100000',
        '2^-1': '0.5',
        '7 % -3': '1',
        '5.5 % 2': '1.5',
        '1e-301': '0',
        'round(2.5)': '3',
        'round(-2.5)': '-3',
        '2^0.5': '1.4142135623731',
      });
    });
  });

  group('degrees', () {
    test('trig vectors', () {
      expectResults({
        'sin(30)': '0.5',
        'cos(60)': '0.5',
        'tan(45)': '1',
        'sin(270)': '-1',
        'asin(0.5)': '30',
        'atan(1)': '45',
        'sin(30)^2+cos(30)^2': '1',
        'sin(180)': '0',
        'cos(90)': '0',
        'cos(-90)': '0',
        'sin(-450)': '-1',
        'acos(0.5)': '60',
        'acos(-1)': '180',
      }, AngleUnit.degrees);
    });
  });

  group('radians', () {
    test('trig and hyperbolic vectors', () {
      expectResults({
        'sin(pi)': '0',
        'cos(pi)': '-1',
        'sin(pi/6)': '0.5',
        'atan(1)': '0.785398163397448',
        'tanh(1)': '0.761594155955765',
        'sin(1)': '0.841470984807897',
        'cos(1)': '0.54030230586814',
        'tan(1)': '1.5574077246549',
        'asin(1)': '1.5707963267949',
        'acos(0)': '1.5707963267949',
        'sinh(1)': '1.1752011936438',
        'cosh(1)': '1.54308063481524',
        'asinh(1)': '0.881373587019543',
        'acosh(2)': '1.31695789692482',
        'atanh(0.5)': '0.549306144334055',
      });
    });
  });

  group('constants and logarithms', () {
    test('vectors', () {
      expectResults({
        'pi': '3.14159265358979',
        'e': '2.71828182845905',
        'ln(e)': '1',
        'log(1000)': '3',
        'log10(0.01)': '-2',
        'log(8,2)': '3',
        'log2(1024)': '10',
        'ln(2)': '0.693147180559945',
        'ln(0.5)': '-0.693147180559945',
        'exp(1)': '2.71828182845905',
        'exp(-1000)': '0',
      });
    });
  });

  group('factorial and combinatorics', () {
    test('vectors', () {
      expectResults({
        '5!': '120',
        '0!': '1',
        '-3!': '-6',
        '2^3!': '64',
        '(2+3)!': '120',
        '3!!': '720',
        'nCr(52,5)': '2598960',
        'nPr(5,2)': '20',
      });
    });
  });

  group('roots and rounding', () {
    test('vectors', () {
      expectResults({
        'cbrt(-27)': '-3',
        'root(16,4)': '2',
        'root(-8,3)': '-2',
        'abs(-4.5)': '4.5',
        'floor(-2.5)': '-3',
        'ceil(2.1)': '3',
      });
    });
  });

  group('errors', () {
    test('domain errors', () {
      expect(errorCode('tan(90)', AngleUnit.degrees), CalculatorErrorCode.invalidOperation);
      for (final expr in [
        'asin(2)',
        'ln(0)',
        'log(8,1)',
        '2.5!',
        'root(-16,2)',
        'nCr(2,5)',
        'sqrt(-4)',
        '(-8)^0.5',
        'acosh(0.5)',
        'atanh(1)',
        'root(4, 0)',
        '(-1)!',
      ]) {
        expect(errorCode(expr), CalculatorErrorCode.invalidOperation, reason: expr);
      }
      expect(errorCode('171!'), CalculatorErrorCode.overflow);
      expect(errorCode('exp(1000)'), CalculatorErrorCode.overflow);
      expect(errorCode('1/0'), CalculatorErrorCode.divisionByZero);
      expect(errorCode('0^-1'), CalculatorErrorCode.divisionByZero);
      expect(errorCode('5 % 0'), CalculatorErrorCode.moduloByZero);
      expect(errorCode('1e301'), CalculatorErrorCode.overflow);
      expect(errorCode('sin(1e16)'), CalculatorErrorCode.tooComplex);
    });

    test('syntax errors', () {
      final expected = {
        '1,000': CalculatorErrorCode.unexpectedToken,
        '2(3)': CalculatorErrorCode.unexpectedToken,
        '2pi': CalculatorErrorCode.unexpectedToken,
        'sin 30': CalculatorErrorCode.unexpectedToken,
        '(2+3': CalculatorErrorCode.mismatchedParentheses,
        '2+3)': CalculatorErrorCode.mismatchedParentheses,
        '()': CalculatorErrorCode.unexpectedToken,
        '1.2.3': CalculatorErrorCode.invalidNumber,
        '5e': CalculatorErrorCode.invalidNumber,
        'alert(1)': CalculatorErrorCode.invalidCharacter,
        'constructor': CalculatorErrorCode.invalidCharacter,
        '2 + x': CalculatorErrorCode.invalidCharacter,
        '': CalculatorErrorCode.emptyExpression,
        '   ': CalculatorErrorCode.emptyExpression,
        '2 +': CalculatorErrorCode.unexpectedEnd,
        '2 \$ 3': CalculatorErrorCode.invalidCharacter,
        'log(1,2,3)': CalculatorErrorCode.unexpectedToken,
      };
      expected.forEach((expr, code) {
        expect(errorCode(expr), code, reason: expr);
      });
    });

    test('size limits', () {
      expect(errorCode('1+' * 251), CalculatorErrorCode.expressionTooLong);
      expect(errorCode(List.filled(130, '1').join('+')), CalculatorErrorCode.tooComplex);
      expect(errorCode('${'(' * 33}1${')' * 33}'), CalculatorErrorCode.tooComplex);
      expect(calc('${'(' * 31}1${')' * 31}'), '1');
    });

    test('errors carry a position where relevant', () {
      final outcome = tryEvaluateExpression('2 + x') as EvaluationFailure;
      expect(outcome.error.position, 4);
      expect(outcome.error.message, contains('position 5'));
    });

    test('tan(90°) message says undefined', () {
      final outcome = tryEvaluateExpression('tan(90)', angleUnit: AngleUnit.degrees);
      expect((outcome as EvaluationFailure).error.message, 'tan(90°) is undefined.');
    });
  });

  test('huge tanh arguments return quickly (decimal.js hangs on these)', () {
    final watch = Stopwatch()..start();
    expect(calc('tanh(1e20 * 278)'), '1');
    expect(calc('tanh(-1e9)'), '-1');
    expect(calc('sin(1e15) + cos(1e15) + exp(-699) + 0.5^9999.5'), isNotEmpty);
    expect(watch.elapsedMilliseconds, lessThan(2000));
  });

  group('helpers', () {
    test('usesAngles flag', () {
      expect(evaluateExpression('sin(30)+1').usesAngles, isTrue);
      expect(evaluateExpression('sinh(1)').usesAngles, isFalse);
    });

    test('prettyExpression', () {
      expect(prettyExpression('sqrt(2)*pi/3-1'), '√(2)×π÷3−1');
      expect(prettyExpression('cbrt(8)'), '∛(8)');
    });

    test('Dec toString matches decimal.js', () {
      expect(Dec.parse('123.4500').toString(), '123.45');
      expect(Dec.parse('1e21').toString(), '1e+21');
      expect(Dec.parse('1.5e-7').toString(), '1.5e-7');
      expect(Dec.parse('-0.00012').toString(), '-0.00012');
      expect(Dec.one.div(Dec.fromInt(3)).toString(), '0.3333333333333333333333333333333333');
    });
  });
}
