/// Scientific functions on [Dec]: trigonometry (degrees or radians), hyperbolic functions,
/// logarithms, exponentials, roots, rounding, factorial and combinatorics.
///
/// Transcendental functions are computed with series at [_work] significant digits and then rounded
/// to [Dec.precision] (34), matching decimal.js in the web app. Every public function validates its
/// domain and throws [CalculatorError] with a user-safe message.
library;

import 'decimal.dart';
import 'errors.dart';

enum AngleUnit {
  degrees,
  radians;

  String get shortLabel => this == degrees ? 'deg' : 'rad';
}

/// Working precision for series evaluation.
const int _work = 60;

/// Precision of the cached constants (π, ln 2, ln 10); argument reduction needs extra digits.
const int _constPrecision = 140;

const int _p = Dec.precision;

final Dec maxAbsResult = Dec.parse('1e300');
final Dec minAbsResult = Dec.parse('1e-300');
final Dec _epsilon = Dec.parse('1e-30');
final Dec _maxAngle = Dec.parse('1e15');
final Dec _maxExpArg = Dec.fromInt(700);
const int maxFactorial = 170;
final Dec _maxCombinatoricSteps = Dec.fromInt(100000);

// -----------------------------------------------------------------------------
// Range check shared by the evaluator
// -----------------------------------------------------------------------------

Dec assertInRange(Dec value) {
  if (value.abs() > maxAbsResult) {
    throw const CalculatorError(CalculatorErrorCode.overflow, overflowMessage);
  }
  if (!value.isZero && value.abs() < minAbsResult) return Dec.zero;
  return value;
}

// -----------------------------------------------------------------------------
// High-precision primitives (no domain checks)
// -----------------------------------------------------------------------------

/// Sum of z^(2k+1)/(2k+1) with alternating signs when [alternating] (atan) or not (atanh).
Dec _oddPowerSeries(Dec z, int p, {required bool alternating}) {
  if (z.isZero) return Dec.zero;
  final z2 = z.mul(z, p);
  final stop = z.adjustedExponent - p - 2;
  var power = z;
  var sum = z;
  for (var k = 1; ; k++) {
    power = power.mul(z2, p);
    if (power.isZero || power.adjustedExponent < stop) break;
    final term = power.div(Dec.fromInt(2 * k + 1), p);
    sum = alternating && k.isOdd ? sum.sub(term, p) : sum.add(term, p);
  }
  return sum;
}

Dec? _ln2Cache;
Dec? _ln10Cache;
Dec? _piCache;

/// ln 2 = 2·atanh(1/3).
Dec get _ln2 => _ln2Cache ??= _oddPowerSeries(
  Dec.one.div(Dec.fromInt(3), _constPrecision + 5),
  _constPrecision + 5,
  alternating: false,
).mul(Dec.two, _constPrecision);

/// ln 10 = 3·ln 2 + ln 1.25 = 3·ln 2 + 2·atanh(1/9).
Dec get _ln10 => _ln10Cache ??= _ln2
    .mul(Dec.fromInt(3), _constPrecision + 5)
    .add(
      _oddPowerSeries(
        Dec.one.div(Dec.fromInt(9), _constPrecision + 5),
        _constPrecision + 5,
        alternating: false,
      ).mul(Dec.two, _constPrecision + 5),
      _constPrecision,
    );

/// π = 16·atan(1/5) − 4·atan(1/239) (Machin).
Dec get _pi {
  final cached = _piCache;
  if (cached != null) return cached;
  const p = _constPrecision + 5;
  final a = _oddPowerSeries(Dec.one.div(Dec.fromInt(5), p), p, alternating: true);
  final b = _oddPowerSeries(Dec.one.div(Dec.fromInt(239), p), p, alternating: true);
  return _piCache = a.mul(Dec.fromInt(16), p).sub(b.mul(Dec.fromInt(4), p), _constPrecision);
}

/// Natural logarithm of x > 0.
Dec _ln(Dec x, int p) {
  final w = p + 10;
  var f = x;
  var k = 0;
  // Values near 1 are reduced only by powers of two, so ln(1 ± tiny) keeps full relative precision.
  if (f < Dec.half || f >= Dec.two) {
    k = f.adjustedExponent;
    f = f.shift(-k);
  }
  var j = 0;
  final upper = Dec.parse('1.5');
  final lower = Dec.parse('0.75');
  while (f > upper) {
    f = f.mul(Dec.half, w);
    j++;
  }
  while (f < lower) {
    f = f.mul(Dec.two, w);
    j--;
  }
  final z = f.sub(Dec.one, w).div(f.add(Dec.one, w), w);
  var result = _oddPowerSeries(z, w, alternating: false).mul(Dec.two, w);
  if (j != 0) result = result.add(_ln2.mul(Dec.fromInt(j), w), w);
  if (k != 0) result = result.add(_ln10.mul(Dec.fromInt(k), w), w);
  return result.round(p);
}

/// e^x. Arguments below −1000 return 0 (far below the 1e-300 flush threshold).
Dec _exp(Dec x, int p) {
  if (x.isZero) return Dec.one;
  if (x < Dec.fromInt(-1000)) return Dec.zero;
  final w = p + 15;
  final n = x.div(_ln2, w).toDecimalPlaces(0, Rounding.halfUp).toBigInt();
  var r = x.sub(_ln2.mul(Dec.raw(n, 0), _constPrecision), w);
  const halvings = 10;
  r = r.mul(Dec.one.div(Dec.fromInt(1 << halvings), w), w);
  var term = Dec.one;
  var sum = Dec.one;
  for (var k = 1; ; k++) {
    term = term.mul(r, w).div(Dec.fromInt(k), w);
    if (term.isZero || term.adjustedExponent < -w - 2) break;
    sum = sum.add(term, w);
  }
  for (var i = 0; i < halvings; i++) {
    sum = sum.mul(sum, w);
  }
  if (n != BigInt.zero) sum = sum.mul(Dec.two.powInt(n, w), w);
  return sum.round(p);
}

/// Taylor series for sin (odd: true) or cos (odd: false), for small |r|.
Dec _sinCosSeries(Dec r, int p, {required bool odd}) {
  final r2 = r.mul(r, p);
  var term = odd ? r : Dec.one;
  var sum = term;
  final stop = (odd ? r.adjustedExponent : 0) - p - 2;
  for (var k = 1; ; k++) {
    final a = odd ? 2 * k : 2 * k - 1;
    term = -term.mul(r2, p).div(Dec.fromInt(a * (a + 1)), p);
    if (term.isZero || term.adjustedExponent < stop) break;
    sum = sum.add(term, p);
  }
  return sum;
}

/// Returns (sin x, cos x) for x in radians, |x| ≤ 1e15.
(Dec, Dec) _sinCos(Dec x, int p) {
  final w = p + 10;
  if (x.isZero) return (Dec.zero, Dec.one);
  final halfPi = _pi.mul(Dec.half, _constPrecision);
  final q = x.div(halfPi, w).toDecimalPlaces(0, Rounding.halfUp).toBigInt();
  final r = q == BigInt.zero
      ? x
      : x.sub(halfPi.mul(Dec.raw(q, 0), _constPrecision + 20), _constPrecision);
  final s = _sinCosSeries(r, w, odd: true);
  final c = _sinCosSeries(r, w, odd: false);
  final quadrant = (q % BigInt.from(4)).toInt();
  final (sin, cos) = switch (quadrant) {
    0 => (s, c),
    1 => (c, -s),
    2 => (-s, -c),
    _ => (-c, s),
  };
  return (sin.round(p), cos.round(p));
}

/// Arctangent in radians.
Dec _atan(Dec x, int p) {
  if (x.isZero) return Dec.zero;
  final w = p + 10;
  final negative = x.isNegative;
  var a = x.abs();
  Dec result;
  if (a > Dec.one) {
    result = _pi.mul(Dec.half, w).sub(_atan(Dec.one.div(a, w), w), w);
  } else {
    // atan(a) = 2·atan(a / (1 + sqrt(1 + a²))), applied 4 times so the series converges fast.
    const halvings = 4;
    for (var i = 0; i < halvings; i++) {
      a = a.div(Dec.one.add(Dec.one.add(a.mul(a, w), w).sqrt(w), w), w);
    }
    result = _oddPowerSeries(a, w, alternating: true).mul(Dec.fromInt(1 << halvings), w);
  }
  result = result.round(p);
  return negative ? -result : result;
}

/// Arcsine in radians, |x| ≤ 1.
Dec _asin(Dec x, int p) {
  final w = p + 10;
  if (x.abs() == Dec.one) {
    final halfPi = _pi.mul(Dec.half, p);
    return x.isNegative ? -halfPi : halfPi;
  }
  final denominator = Dec.one.sub(x, w).mul(Dec.one.add(x, w), w).sqrt(w);
  return _atan(x.div(denominator, w), p);
}

/// Arccosine in radians, |x| ≤ 1: 2·atan(sqrt((1 − x) / (1 + x))).
Dec _acos(Dec x, int p) {
  final w = p + 10;
  if (x == -Dec.one) return _pi.round(p);
  final ratio = Dec.one.sub(x, w).div(Dec.one.add(x, w), w);
  return _atan(ratio.sqrt(w), w).mul(Dec.two, p);
}

/// sinh with full relative precision near zero.
Dec _sinh(Dec x, int p) {
  final w = p + 10;
  if (x.isZero) return Dec.zero;
  if (x.abs() < Dec.one) {
    final x2 = x.mul(x, w);
    var term = x;
    var sum = x;
    for (var k = 1; ; k++) {
      term = term.mul(x2, w).div(Dec.fromInt((2 * k) * (2 * k + 1)), w);
      if (term.adjustedExponent < x.adjustedExponent - w - 2) break;
      sum = sum.add(term, w);
    }
    return sum.round(p);
  }
  final ex = _exp(x, w);
  return ex.sub(Dec.one.div(ex, w), w).mul(Dec.half, p);
}

Dec _cosh(Dec x, int p) {
  final w = p + 10;
  final ex = _exp(x, w);
  return ex.add(Dec.one.div(ex, w), w).mul(Dec.half, p);
}

// -----------------------------------------------------------------------------
// Constants (34 significant digits, like decimal.js `Decimal.acos(-1)` / `Decimal.exp(1)`)
// -----------------------------------------------------------------------------

final Dec decimalPi = _pi.round(_p);
final Dec decimalE = _exp(Dec.one, _p);

// -----------------------------------------------------------------------------
// Domain-checked functions used by the evaluator
// -----------------------------------------------------------------------------

const Set<String> trigFunctions = {'sin', 'cos', 'tan', 'asin', 'acos', 'atan'};
const Set<String> hyperbolicFunctions = {'sinh', 'cosh', 'tanh', 'asinh', 'acosh', 'atanh'};

/// Results this close to zero are rounding noise (e.g. sin(pi) ≈ 1e-34) and are snapped to 0.
Dec _snap(Dec x) => x.abs() < _epsilon ? Dec.zero : x;

Never _invalid(String message) =>
    throw CalculatorError(CalculatorErrorCode.invalidOperation, message);

void _requireInteger(Dec x, String what) {
  if (!x.isInteger) _invalid('$what must be a whole number.');
}

/// log10 of |x| (x ≠ 0) to 34 digits; used for the power magnitude estimate.
Dec log10Abs(Dec x) => _ln(x.abs(), _work).div(_ln10, _p);

Dec _forwardTrig(String fn, Dec x, AngleUnit unit) {
  if (x.abs() > _maxAngle) {
    throw const CalculatorError(
      CalculatorErrorCode.tooComplex,
      'The angle is too large (max |angle| is 1e15).',
    );
  }
  Dec radians;
  if (unit == AngleUnit.degrees) {
    final reduced = x.mod(Dec.fromInt(360));
    if (reduced.mod(Dec.fromInt(90)).isZero) {
      final quarter = ((reduced.div(Dec.fromInt(90)).toBigInt().toInt() % 4) + 4) % 4;
      if (fn == 'sin') return Dec.fromInt(const [0, 1, 0, -1][quarter]);
      if (fn == 'cos') return Dec.fromInt(const [1, 0, -1, 0][quarter]);
      if (quarter.isOdd) _invalid('tan($x°) is undefined.');
      return Dec.zero;
    }
    radians = reduced.mul(decimalPi).div(Dec.fromInt(180));
  } else {
    radians = x;
  }
  final (sin, cos) = _sinCos(radians, _p);
  if (fn == 'sin') return _snap(sin);
  if (fn == 'cos') return _snap(cos);
  if (cos.abs() < _epsilon) _invalid('tan is undefined at this angle (an odd multiple of π/2).');
  return _snap(sin.div(cos));
}

Dec decimalTrig(String fn, Dec x, AngleUnit unit) {
  if (fn == 'sin' || fn == 'cos' || fn == 'tan') return _forwardTrig(fn, x, unit);
  if ((fn == 'asin' || fn == 'acos') && x.abs() > Dec.one) {
    _invalid('$fn is only defined for values between -1 and 1.');
  }
  final radians = switch (fn) {
    'asin' => _asin(x, _p),
    'acos' => _acos(x, _p),
    _ => _atan(x, _p),
  };
  return _snap(unit == AngleUnit.degrees ? radians.mul(Dec.fromInt(180)).div(decimalPi) : radians);
}

Dec decimalHyperbolic(String fn, Dec x) {
  switch (fn) {
    case 'sinh':
    case 'cosh':
      if (x.abs() > _maxExpArg) {
        throw const CalculatorError(CalculatorErrorCode.overflow, overflowMessage);
      }
      return assertInRange(fn == 'sinh' ? _sinh(x, _p) : _cosh(x, _p));
    case 'tanh':
      // Beyond |x| = 50, 1 − |tanh x| < 1e-43, which rounds to exactly ±1 at 34 digits.
      if (x.abs() > Dec.fromInt(50)) return x.isNegative ? -Dec.one : Dec.one;
      return _sinh(x, _work).div(_cosh(x, _work), _p);
    case 'asinh':
      if (x.isZero) return Dec.zero;
      if (x.abs() < Dec.parse('0.1')) {
        // asinh(x) = atanh(x / sqrt(1 + x²)) keeps relative precision for small x.
        final t = x.div(Dec.one.add(x.mul(x, _work), _work).sqrt(_work), _work);
        return _oddPowerSeries(t, _work, alternating: false).round(_p);
      }
      final a = x.abs();
      final value = _ln(a.add(a.mul(a, _work).add(Dec.one, _work).sqrt(_work), _work), _p);
      return x.isNegative ? -value : value;
    case 'acosh':
      if (x < Dec.one) _invalid('acosh is only defined for values ≥ 1.');
      return _ln(x.add(x.mul(x, _work).sub(Dec.one, _work).sqrt(_work), _work), _p);
    case 'atanh':
      if (x.abs() >= Dec.one) {
        _invalid('atanh is only defined for values strictly between -1 and 1.');
      }
      if (x.abs() < Dec.half) return _oddPowerSeries(x, _work, alternating: false).round(_p);
      return _ln(Dec.one.add(x, _work).div(Dec.one.sub(x, _work), _work), _work).mul(Dec.half, _p);
  }
  _invalid('Unsupported function "$fn".');
}

Dec decimalLn(Dec x) {
  if (x <= Dec.zero) _invalid('The logarithm is only defined for positive numbers.');
  return _ln(x, _p);
}

Dec decimalLog(Dec x, [Dec? base]) {
  final b = base ?? Dec.fromInt(10);
  if (x <= Dec.zero) _invalid('The logarithm is only defined for positive numbers.');
  if (b <= Dec.zero || b == Dec.one) {
    _invalid('The logarithm base must be positive and not equal to 1.');
  }
  // Exact powers of ten give exact results, as with decimal.js.
  if (b == Dec.fromInt(10) && x.mantissa == BigInt.one) return Dec.fromInt(x.exponent);
  if (b == Dec.fromInt(10)) return _ln(x, _work).div(_ln10, _p);
  return _ln(x, _work).div(_ln(b, _work), _p);
}

Dec decimalExp(Dec x) {
  if (x > _maxExpArg) throw const CalculatorError(CalculatorErrorCode.overflow, overflowMessage);
  if (x < -_maxExpArg) return Dec.zero;
  return assertInRange(_exp(x, _p));
}

/// x^y for real y via exp(y·ln x); x must be > 0.
Dec realPower(Dec x, Dec y) => _exp(y.mul(_ln(x, _work), _work), _p);

Dec decimalCbrt(Dec x) => x.cbrt();

/// n-th root; negative x is allowed only for odd integer n.
Dec decimalRoot(Dec x, Dec n, Dec Function(Dec base, Dec exponent) power) {
  if (n.isZero) _invalid('The 0th root is undefined.');
  if (x.isNegative) {
    if (!n.isInteger || n.mod(Dec.two).isZero) {
      _invalid('An even or fractional root of a negative number is not a real number.');
    }
    return -power(x.abs(), Dec.one.div(n));
  }
  return power(x, Dec.one.div(n));
}

Dec decimalRound(String fn, Dec x) => switch (fn) {
  'floor' => x.floor(),
  'ceil' => x.ceil(),
  // Half away from zero, as people expect: round(2.5) = 3, round(-2.5) = -3.
  'round' => x.toDecimalPlaces(0, Rounding.halfUp),
  _ => x.abs(),
};

Dec decimalFactorial(Dec n) {
  _requireInteger(n, 'The factorial argument');
  if (n.isNegative) _invalid('The factorial is only defined for non-negative whole numbers.');
  if (n > Dec.fromInt(maxFactorial)) {
    throw const CalculatorError(CalculatorErrorCode.overflow, overflowMessage);
  }
  var result = Dec.one;
  final count = n.toBigInt().toInt();
  for (var i = 2; i <= count; i++) {
    result = result.mul(Dec.fromInt(i));
  }
  return assertInRange(result);
}

void _checkCombinatoricArgs(String name, Dec n, Dec r) {
  _requireInteger(n, '$name: n');
  _requireInteger(r, '$name: r');
  if (n.isNegative || r.isNegative) _invalid('$name needs non-negative n and r.');
  if (r > n) _invalid('$name needs r ≤ n.');
}

/// Permutations: n! / (n − r)!
Dec decimalPermutations(Dec n, Dec r) {
  _checkCombinatoricArgs('nPr', n, r);
  if (r > _maxCombinatoricSteps) {
    throw const CalculatorError(CalculatorErrorCode.overflow, overflowMessage);
  }
  var result = Dec.one;
  final steps = r.toBigInt().toInt();
  for (var i = 0; i < steps; i++) {
    result = assertInRange(result.mul(n.sub(Dec.fromInt(i))));
  }
  return result;
}

/// Combinations: n! / (r! (n − r)!)
Dec decimalCombinations(Dec n, Dec r) {
  _checkCombinatoricArgs('nCr', n, r);
  final nMinusR = n.sub(r);
  final k = r < nMinusR ? r : nMinusR;
  if (k > _maxCombinatoricSteps) {
    throw const CalculatorError(
      CalculatorErrorCode.tooComplex,
      'The combination is too large to compute.',
    );
  }
  var result = Dec.one;
  final steps = k.toBigInt().toInt();
  final base = n.sub(k);
  for (var i = 1; i <= steps; i++) {
    result = assertInRange(result.mul(base.add(Dec.fromInt(i))).div(Dec.fromInt(i)));
  }
  return result.toDecimalPlaces(0, Rounding.halfUp);
}
