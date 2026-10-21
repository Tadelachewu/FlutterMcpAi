// Golden results produced by the original TypeScript engine (decimal.js) for the spec vectors plus
// thousands of random expressions. Every case must give the same result string or error code.
import 'dart:convert';
import 'dart:io';

import 'package:ai_scientific_calculator/calculator/evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dart engine matches the TypeScript engine on the golden corpus', () {
    final cases = (jsonDecode(File('test/fixtures/engine_parity.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    expect(cases.length, greaterThan(3000));
    final mismatches = <String>[];
    for (final c in cases) {
      final expr = c['expr'] as String;
      final unit = c['unit'] == 'degrees' ? AngleUnit.degrees : AngleUnit.radians;
      final outcome = tryEvaluateExpression(expr, angleUnit: unit);
      final actual = switch (outcome) {
        EvaluationSuccess(:final value) => value.result,
        EvaluationFailure(:final error) => error.code.wire,
      };
      final expected = (c['result'] ?? c['code']) as String;
      if (actual != expected) {
        mismatches.add('[${unit.shortLabel}] $expr → $actual (expected $expected)');
      }
    }
    expect(mismatches, isEmpty, reason: '${mismatches.length} of ${cases.length} cases differ');
  });
}
