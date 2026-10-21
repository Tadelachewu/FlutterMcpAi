import 'errors.dart';

const int maxExpressionLength = 500;
const int maxTokens = 250;
const int maxNumberLiteralLength = 64;

/// Supported functions with their (min, max) argument counts.
const Map<String, (int, int)> functionArity = {
  'sqrt': (1, 1),
  'cbrt': (1, 1),
  'root': (2, 2),
  'abs': (1, 1),
  'floor': (1, 1),
  'ceil': (1, 1),
  'round': (1, 1),
  'sin': (1, 1),
  'cos': (1, 1),
  'tan': (1, 1),
  'asin': (1, 1),
  'acos': (1, 1),
  'atan': (1, 1),
  'sinh': (1, 1),
  'cosh': (1, 1),
  'tanh': (1, 1),
  'asinh': (1, 1),
  'acosh': (1, 1),
  'atanh': (1, 1),
  'ln': (1, 1),
  'log': (1, 2),
  'log2': (1, 1),
  'exp': (1, 1),
  'nCr': (2, 2),
  'nPr': (2, 2),
};

/// Lower-case spelling → canonical function name. A fixed map, so names like "constructor" never match.
final Map<String, String> _functionLookup = {
  for (final name in functionArity.keys) name.toLowerCase(): name,
  'arcsin': 'asin',
  'arccos': 'acos',
  'arctan': 'atan',
  'log10': 'log',
};

const Map<String, String> _constantLookup = {'pi': 'pi', 'e': 'e'};

enum TokenType { number, op, lparen, rparen, comma, bang, func, constant }

class Token {
  const Token(this.type, this.pos, [this.value = '']);

  final TokenType type;
  final int pos;

  /// Literal text for numbers, the operator character, or the canonical function/constant name.
  final String value;

  String describe() => switch (type) {
    TokenType.number => 'number $value',
    TokenType.lparen => '"("',
    TokenType.rparen => '")"',
    TokenType.comma => '","',
    TokenType.bang => '"!"',
    _ => '"$value"',
  };
}

final RegExp _numberPattern = RegExp(r'(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?');
final RegExp _identifierPattern = RegExp(r'[a-zA-Z_][a-zA-Z0-9_]*');
final RegExp _whitespace = RegExp(r'\s');
final RegExp _exponentChar = RegExp(r'[eE]');

/// Maps display symbols and aliases to the ASCII grammar.
String normalizeExpression(String input) => input
    .replaceAll(RegExp('[×✕∗]'), '*')
    .replaceAll(RegExp('[÷∕]'), '/')
    .replaceAll(RegExp('[−–—]'), '-')
    .replaceAll('**', '^')
    .replaceAll('√', 'sqrt')
    .replaceAll('∛', 'cbrt')
    .replaceAll('π', 'pi');

List<Token> tokenize(String input) {
  if (input.length > maxExpressionLength) {
    throw const CalculatorError(
      CalculatorErrorCode.expressionTooLong,
      'Expression is too long (max $maxExpressionLength characters).',
    );
  }
  final src = normalizeExpression(input);
  final tokens = <Token>[];
  var i = 0;
  while (i < src.length) {
    final ch = src[i];
    if (_whitespace.hasMatch(ch)) {
      i++;
      continue;
    }
    final numberMatch = _numberPattern.matchAsPrefix(src, i);
    final identifierMatch = numberMatch == null ? _identifierPattern.matchAsPrefix(src, i) : null;
    if (numberMatch != null) {
      final literal = numberMatch[0]!;
      if (literal.length > maxNumberLiteralLength) {
        throw CalculatorError(CalculatorErrorCode.invalidNumber, 'Number literal is too long.', i);
      }
      tokens.add(Token(TokenType.number, i, literal));
      i += literal.length;
      // Reject things like "1.2.3" or "5e" that would otherwise silently split.
      if (i < src.length && (src[i] == '.' || _exponentChar.hasMatch(src[i]))) {
        throw CalculatorError(
          CalculatorErrorCode.invalidNumber,
          'Invalid number near position ${i + 1}.',
          i,
        );
      }
    } else if ('+-*/%^'.contains(ch)) {
      tokens.add(Token(TokenType.op, i, ch));
      i++;
    } else if (ch == '(') {
      tokens.add(Token(TokenType.lparen, i));
      i++;
    } else if (ch == ')') {
      tokens.add(Token(TokenType.rparen, i));
      i++;
    } else if (ch == ',') {
      tokens.add(Token(TokenType.comma, i));
      i++;
    } else if (ch == '!') {
      tokens.add(Token(TokenType.bang, i));
      i++;
    } else if (identifierMatch != null) {
      final name = identifierMatch[0]!;
      final lower = name.toLowerCase();
      final fn = _functionLookup[lower];
      final constant = _constantLookup[lower];
      if (fn != null) {
        tokens.add(Token(TokenType.func, i, fn));
      } else if (constant != null) {
        tokens.add(Token(TokenType.constant, i, constant));
      } else {
        final shown = name.length > 20 ? name.substring(0, 20) : name;
        throw CalculatorError(
          CalculatorErrorCode.invalidCharacter,
          'Unknown name "$shown" at position ${i + 1}. Supported: pi, e and the functions '
          '${functionArity.keys.join(', ')}.',
          i,
        );
      }
      i += name.length;
    } else {
      throw CalculatorError(
        CalculatorErrorCode.invalidCharacter,
        'Unsupported character "$ch" at position ${i + 1}. Allowed: numbers, + - * / % ^ ! ( ) , '
        'and named functions/constants.',
        i,
      );
    }
    if (tokens.length > maxTokens) {
      throw const CalculatorError(
        CalculatorErrorCode.tooComplex,
        'Expression is too complex (max $maxTokens tokens).',
      );
    }
  }
  if (tokens.isEmpty) {
    throw const CalculatorError(CalculatorErrorCode.emptyExpression, 'Expression is empty.');
  }
  return tokens;
}
