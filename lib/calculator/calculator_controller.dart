import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'evaluator.dart';
import 'tokenizer.dart' show maxExpressionLength;

export 'evaluator.dart' show AngleUnit;

const int maxHistoryEntries = 50;

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.expression,
    required this.result,
    this.angleUnit,
  });

  final int id;
  final String expression;
  final String result;

  /// Set when the expression used trigonometry, so the unit matters.
  final AngleUnit? angleUnit;
}

class CalculatorState {
  const CalculatorState({
    this.expression = '',
    this.justEvaluated = false,
    this.error,
    this.lastEvaluated,
    this.history = const [],
    this.angleUnit = AngleUnit.degrees,
  });

  final String expression;
  final bool justEvaluated;
  final String? error;

  /// The expression shown above the result after "=".
  final String? lastEvaluated;
  final List<HistoryEntry> history;
  final AngleUnit angleUnit;

  static final RegExp _plainNumber = RegExp(r'^[+-]?[\d.]+(e[+-]?\d+)?$', caseSensitive: false);

  /// Live result shown under the expression, or null when there is nothing useful to preview.
  String? get preview {
    if (expression.isEmpty || justEvaluated || _plainNumber.hasMatch(expression)) return null;
    final outcome = tryEvaluateExpression(expression, angleUnit: angleUnit);
    return outcome is EvaluationSuccess ? outcome.value.result : null;
  }

  CalculatorState copyWith({
    String? expression,
    bool? justEvaluated,
    String? Function()? error,
    String? Function()? lastEvaluated,
    List<HistoryEntry>? history,
    AngleUnit? angleUnit,
  }) => CalculatorState(
    expression: expression ?? this.expression,
    justEvaluated: justEvaluated ?? this.justEvaluated,
    error: error != null ? error() : this.error,
    lastEvaluated: lastEvaluated != null ? lastEvaluated() : this.lastEvaluated,
    history: history ?? this.history,
    angleUnit: angleUnit ?? this.angleUnit,
  );
}

/// Keys that continue from the previous result instead of starting a new expression.
final RegExp _operatorStart = RegExp(r'^[+*/%^!,]');

/// A trailing function name with its "(" (e.g. "asin(") or a constant, removed as one unit by ⌫.
final RegExp _trailingName = RegExp(r'(?:[a-zA-Z][a-zA-Z0-9]*\(|pi)$');
final RegExp _usesAngles = RegExp(
  r'\b(?:a?(?:sin|cos|tan)|arc(?:sin|cos|tan))\(',
  caseSensitive: false,
);

final calculatorProvider = NotifierProvider<CalculatorController, CalculatorState>(
  CalculatorController.new,
);

class CalculatorController extends Notifier<CalculatorState> {
  int _nextId = 0;

  @override
  CalculatorState build() => const CalculatorState();

  void input(String value) {
    final current = state.expression;
    // After "=", typing a number or function starts fresh; typing an operator continues from the result.
    final base = state.justEvaluated && !_operatorStart.hasMatch(value) && value != '-'
        ? ''
        : current;
    final next = base + value;
    state = state.copyWith(
      expression: next.length > maxExpressionLength ? current : next,
      error: () => null,
      justEvaluated: false,
    );
  }

  void clear() {
    state = state.copyWith(
      expression: '',
      error: () => null,
      justEvaluated: false,
      lastEvaluated: () => null,
    );
  }

  void backspace() {
    final current = state.expression;
    final name = _trailingName.firstMatch(current);
    final next = name != null
        ? current.substring(0, current.length - name[0]!.length)
        : current.isEmpty
        ? current
        : current.substring(0, current.length - 1);
    state = state.copyWith(expression: next, error: () => null, justEvaluated: false);
  }

  void equals() {
    final expr = state.expression;
    if (expr.trim().isEmpty) return;
    final outcome = tryEvaluateExpression(expr, angleUnit: state.angleUnit);
    switch (outcome) {
      case EvaluationFailure(:final error):
        state = state.copyWith(error: () => error.message);
      case EvaluationSuccess(:final value):
        final entry = HistoryEntry(
          id: _nextId++,
          expression: expr,
          result: value.result,
          angleUnit: value.usesAngles ? state.angleUnit : null,
        );
        state = state.copyWith(
          history: [entry, ...state.history].take(maxHistoryEntries).toList(),
          lastEvaluated: () => expr,
          expression: value.result,
          justEvaluated: true,
          error: () => null,
        );
    }
  }

  void toggleAngleUnit() {
    state = state.copyWith(
      angleUnit: state.angleUnit == AngleUnit.degrees ? AngleUnit.radians : AngleUnit.degrees,
    );
  }

  void useHistoryEntry(HistoryEntry entry) {
    state = state.copyWith(
      expression: entry.result,
      justEvaluated: true,
      lastEvaluated: () => entry.expression,
      error: () => null,
    );
  }

  void clearHistory() => state = state.copyWith(history: const []);

  /// The chat prompt for "Explain with AI", or null when there is nothing to explain.
  String? explainPrompt() {
    final target = state.justEvaluated && state.lastEvaluated != null
        ? state.lastEvaluated!
        : state.expression;
    if (target.trim().isEmpty) return null;
    final suffix = _usesAngles.hasMatch(target)
        ? ' (angles in ${state.angleUnit == AngleUnit.degrees ? 'degrees' : 'radians'})'
        : '';
    return 'Calculate $target$suffix';
  }
}
