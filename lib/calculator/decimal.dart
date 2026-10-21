/// Arbitrary-precision decimal floating point, modelled on decimal.js as configured by the web app:
/// arithmetic results are rounded to [Dec.precision] (34) significant digits with ROUND_HALF_EVEN,
/// number literals are kept exact, and [toString] switches to exponent notation at 1e21 / 1e-7.
///
/// A value is `mantissa * 10^exponent`; the mantissa never has trailing zeros (zero is `0 * 10^0`).
library;

enum Rounding {
  /// Banker's rounding (decimal.js ROUND_HALF_EVEN), used for arithmetic and display.
  halfEven,

  /// Half away from zero (decimal.js ROUND_HALF_UP).
  halfUp,

  /// Toward zero.
  down,
}

final BigInt _ten = BigInt.from(10);
final List<BigInt> _pow10Cache = [BigInt.one];

BigInt pow10(int n) {
  assert(n >= 0);
  if (n < 512) {
    while (_pow10Cache.length <= n) {
      _pow10Cache.add(_pow10Cache.last * _ten);
    }
    return _pow10Cache[n];
  }
  return _ten.pow(n);
}

int _digitCount(BigInt n) {
  if (n == BigInt.zero) return 1;
  final abs = n.abs();
  // bitLength * log10(2) is within one of the true digit count.
  var estimate = (abs.bitLength * 0.30102999566398120).floor();
  if (estimate < 1) estimate = 1;
  if (abs >= pow10(estimate)) return estimate + 1;
  if (estimate > 1 && abs < pow10(estimate - 1)) return estimate - 1;
  return estimate;
}

final RegExp _decimalPattern = RegExp(r'^([+-])?(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$');

class Dec implements Comparable<Dec> {
  Dec._(this.mantissa, this.exponent);

  /// Builds `mantissa * 10^exponent`, stripping trailing zeros.
  factory Dec.raw(BigInt mantissa, int exponent) {
    if (mantissa == BigInt.zero) return zero;
    var m = mantissa;
    var e = exponent;
    while (m.remainder(_ten) == BigInt.zero) {
      m = m ~/ _ten;
      e++;
    }
    return Dec._(m, e);
  }

  factory Dec.fromInt(int value) => Dec.raw(BigInt.from(value), 0);

  /// Parses a plain decimal literal such as `12`, `-3.5`, `.5` or `1e-5`. Exact; never rounds.
  factory Dec.parse(String text) {
    final match = _decimalPattern.firstMatch(text.trim());
    if (match == null) throw FormatException('Invalid decimal', text);
    final intPart = match.group(2) ?? '';
    final fracPart = match.group(3) ?? '';
    if (intPart.isEmpty && fracPart.isEmpty) throw FormatException('Invalid decimal', text);
    final expText = match.group(4);
    var exp = 0;
    if (expText != null) {
      final digits = expText.replaceFirst(RegExp(r'^[+-]'), '').replaceFirst(RegExp(r'^0+'), '');
      final negative = expText.startsWith('-');
      // Exponents this large overflow or flush to zero anyway; clamp so `int` never overflows.
      final magnitude = digits.length > 9 ? 1000000000 : int.parse(digits.isEmpty ? '0' : digits);
      exp = negative ? -magnitude : magnitude;
    }
    var mantissa = BigInt.parse('$intPart$fracPart');
    if (match.group(1) == '-') mantissa = -mantissa;
    return Dec.raw(mantissa, exp - fracPart.length);
  }

  /// Default significant digits for arithmetic (decimal128, as in the web app).
  static const int precision = 34;

  static final Dec zero = Dec._(BigInt.zero, 0);
  static final Dec one = Dec._(BigInt.one, 0);
  static final Dec two = Dec._(BigInt.two, 0);
  static final Dec half = Dec._(BigInt.from(5), -1);

  final BigInt mantissa;
  final int exponent;

  bool get isZero => mantissa == BigInt.zero;
  bool get isNegative => mantissa.isNegative;
  bool get isInteger => isZero || exponent >= 0;
  int get sign => mantissa.sign;

  /// Number of significant digits in the mantissa.
  int get digits => _digitCount(mantissa);

  /// Exponent of the most significant digit: value is in [10^adjusted, 10^(adjusted+1)).
  int get adjustedExponent => isZero ? 0 : exponent + digits - 1;

  Dec abs() => isNegative ? Dec._(-mantissa, exponent) : this;
  Dec operator -() => isZero ? this : Dec._(-mantissa, exponent);

  /// Multiplies by 10^n exactly.
  Dec shift(int n) => isZero ? this : Dec._(mantissa, exponent + n);

  /// Rounds to [significant] digits.
  Dec round(int significant, [Rounding mode = Rounding.halfEven]) =>
      _roundMantissa(mantissa, exponent, significant, mode);

  static Dec _roundMantissa(BigInt m, int e, int significant, Rounding mode) {
    if (m == BigInt.zero) return zero;
    final drop = _digitCount(m) - significant;
    if (drop <= 0) return Dec.raw(m, e);
    return Dec.raw(_divideRounded(m, pow10(drop), mode), e + drop);
  }

  /// Integer division of [m] by positive [divisor], rounded with [mode].
  static BigInt _divideRounded(BigInt m, BigInt divisor, Rounding mode) {
    var q = m ~/ divisor;
    final r = m.remainder(divisor);
    if (r == BigInt.zero || mode == Rounding.down) return q;
    final twice = r.abs() * BigInt.two;
    final cmp = twice.compareTo(divisor);
    final awayFromZero = cmp > 0 || (cmp == 0 && (mode == Rounding.halfUp || q.isOdd));
    if (awayFromZero) q += BigInt.from(m.sign);
    return q;
  }

  /// Rounds to [places] digits after the decimal point.
  Dec toDecimalPlaces(int places, [Rounding mode = Rounding.halfEven]) {
    if (isZero || exponent >= -places) return this;
    final drop = -places - exponent;
    return Dec.raw(_divideRounded(mantissa, pow10(drop), mode), -places);
  }

  Dec floor() {
    if (isInteger) return this;
    final divisor = pow10(-exponent);
    var q = mantissa ~/ divisor;
    if (isNegative) q -= BigInt.one;
    return Dec.raw(q, 0);
  }

  Dec ceil() {
    if (isInteger) return this;
    final divisor = pow10(-exponent);
    var q = mantissa ~/ divisor;
    if (!isNegative) q += BigInt.one;
    return Dec.raw(q, 0);
  }

  Dec truncate() => isInteger ? this : Dec.raw(mantissa ~/ pow10(-exponent), 0);

  /// Converts an integer-valued decimal to a BigInt.
  BigInt toBigInt() {
    final t = truncate();
    return t.isZero ? BigInt.zero : t.mantissa * pow10(t.exponent);
  }

  double toDouble() => double.parse(toString());

  // ---------------------------------------------------------------------------
  // Arithmetic. Every operation rounds to [p] significant digits (default 34).
  // ---------------------------------------------------------------------------

  Dec add(Dec other, [int p = precision]) {
    if (other.isZero) return round(p);
    if (isZero) return other.round(p);
    var a = this;
    var b = other;
    // If one operand is far below the other's rounding position it only acts as a sticky digit.
    final gap = a.adjustedExponent - b.adjustedExponent;
    if (gap > p + 2) {
      b = Dec._(BigInt.from(b.sign), a.adjustedExponent - p - 3);
    } else if (-gap > p + 2) {
      a = Dec._(BigInt.from(a.sign), b.adjustedExponent - p - 3);
    }
    final e = a.exponent < b.exponent ? a.exponent : b.exponent;
    final sum = a.mantissa * pow10(a.exponent - e) + b.mantissa * pow10(b.exponent - e);
    return _roundMantissa(sum, e, p, Rounding.halfEven);
  }

  Dec sub(Dec other, [int p = precision]) => add(-other, p);

  Dec mul(Dec other, [int p = precision]) {
    if (isZero || other.isZero) return zero;
    return _roundMantissa(
      mantissa * other.mantissa,
      exponent + other.exponent,
      p,
      Rounding.halfEven,
    );
  }

  /// Division; throws [UnsupportedError] on division by zero (callers check first).
  Dec div(Dec other, [int p = precision]) {
    if (other.isZero) throw UnsupportedError('Division by zero');
    if (isZero) return zero;
    final shiftBy = p + 2 + other.digits - digits;
    final k = shiftBy > 0 ? shiftBy : 0;
    final numerator = mantissa * pow10(k);
    var q = numerator ~/ other.mantissa;
    var e = exponent - other.exponent - k;
    if (numerator.remainder(other.mantissa) != BigInt.zero) {
      // Sticky digit so that half-way detection stays correct.
      q = q * _ten + BigInt.from(q.sign == 0 ? numerator.sign * other.mantissa.sign : q.sign);
      e -= 1;
    }
    return _roundMantissa(q, e, p, Rounding.halfEven);
  }

  /// Truncated remainder (sign follows the dividend, like JavaScript `%`). Exact.
  Dec mod(Dec other) {
    if (other.isZero) throw UnsupportedError('Modulo by zero');
    if (isZero) return zero;
    if (abs().compareTo(other.abs()) < 0) return this;
    final e = exponent < other.exponent ? exponent : other.exponent;
    final a = mantissa * pow10(exponent - e);
    final b = other.mantissa * pow10(other.exponent - e);
    return Dec.raw(a.remainder(b), e);
  }

  Dec operator +(Dec other) => add(other);
  Dec operator -(Dec other) => sub(other);
  Dec operator *(Dec other) => mul(other);
  Dec operator /(Dec other) => div(other);

  /// x^n for an integer n, by repeated squaring with [p] + 10 guard digits, then rounded to [p].
  Dec powInt(BigInt n, [int p = precision]) {
    if (n == BigInt.zero) return one;
    final work = p + 10;
    var base = this;
    var e = n.abs();
    var result = one;
    while (e > BigInt.zero) {
      if (e.isOdd) result = result.mul(base, work);
      e = e >> 1;
      if (e > BigInt.zero) base = base.mul(base, work);
    }
    if (n.isNegative) return one.div(result, p);
    return result.round(p);
  }

  /// Square root (this must be ≥ 0), correctly rounded to [p] digits.
  Dec sqrt([int p = precision]) {
    if (isZero) return zero;
    if (isNegative) throw UnsupportedError('Square root of a negative number');
    final target = 2 * (p + 2);
    var s = target - digits;
    if (s < 0) s = 0;
    if ((exponent - s).isOdd) s++;
    final n = mantissa * pow10(s);
    var r = _isqrt(n);
    var e = (exponent - s) ~/ 2;
    if (r * r != n) {
      r = r * _ten + BigInt.one;
      e -= 1;
    }
    return _roundMantissa(r, e, p, Rounding.halfEven);
  }

  /// Real cube root, correctly rounded to [p] digits. Exact for perfect cubes.
  Dec cbrt([int p = precision]) {
    if (isZero) return zero;
    final target = 3 * (p + 2);
    var s = target - digits;
    if (s < 0) s = 0;
    while ((exponent - s) % 3 != 0) {
      s++;
    }
    final n = mantissa.abs() * pow10(s);
    var r = _icbrt(n);
    var e = (exponent - s) ~/ 3;
    if (r * r * r != n) {
      r = r * _ten + BigInt.one;
      e -= 1;
    }
    final result = _roundMantissa(r, e, p, Rounding.halfEven);
    return isNegative ? -result : result;
  }

  static BigInt _isqrt(BigInt n) {
    if (n < BigInt.two) return n;
    var x = BigInt.one << ((n.bitLength + 1) >> 1);
    while (true) {
      final y = (x + n ~/ x) >> 1;
      if (y >= x) return x;
      x = y;
    }
  }

  static BigInt _icbrt(BigInt n) {
    if (n < BigInt.two) return n;
    final three = BigInt.from(3);
    var x = BigInt.one << ((n.bitLength + 2) ~/ 3 + 1);
    while (true) {
      final y = (BigInt.two * x + n ~/ (x * x)) ~/ three;
      if (y >= x) return x;
      x = y;
    }
  }

  // ---------------------------------------------------------------------------
  // Comparison
  // ---------------------------------------------------------------------------

  @override
  int compareTo(Dec other) {
    if (sign != other.sign) return sign.compareTo(other.sign);
    if (isZero) return 0;
    final magnitude = _compareMagnitude(other);
    return isNegative ? -magnitude : magnitude;
  }

  int _compareMagnitude(Dec other) {
    final adjA = adjustedExponent;
    final adjB = other.adjustedExponent;
    if (adjA != adjB) return adjA.compareTo(adjB);
    final e = exponent < other.exponent ? exponent : other.exponent;
    final a = mantissa.abs() * pow10(exponent - e);
    final b = other.mantissa.abs() * pow10(other.exponent - e);
    return a.compareTo(b);
  }

  bool operator <(Dec other) => compareTo(other) < 0;
  bool operator <=(Dec other) => compareTo(other) <= 0;
  bool operator >(Dec other) => compareTo(other) > 0;
  bool operator >=(Dec other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is Dec && other.mantissa == mantissa && other.exponent == exponent;

  @override
  int get hashCode => Object.hash(mantissa, exponent);

  /// decimal.js `toString()` with toExpPos 21 and toExpNeg -7.
  @override
  String toString() {
    if (isZero) return '0';
    final s = mantissa.abs().toString();
    final adj = exponent + s.length - 1;
    final prefix = isNegative ? '-' : '';
    if (adj >= 21 || adj <= -7) {
      final frac = s.length > 1 ? '.${s.substring(1)}' : '';
      return '$prefix${s[0]}${frac}e${adj >= 0 ? '+' : '-'}${adj.abs()}';
    }
    if (exponent >= 0) return '$prefix$s${'0' * exponent}';
    if (adj >= 0) return '$prefix${s.substring(0, adj + 1)}.${s.substring(adj + 1)}';
    return '${prefix}0.${'0' * (-adj - 1)}$s';
  }
}
