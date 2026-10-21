/// Recursive-descent parser. Grammar (lowest to highest precedence):
///
/// ```text
/// expression := term (("+" | "-") term)*
/// term       := unary (("*" | "/" | "%") unary)*        % is modulo
/// unary      := ("-" | "+") unary | power
/// power      := postfix ("^" unary)?                      right-associative; -2^2 = -4
/// postfix    := primary "!"*                              factorial; -3! = -6, 2^3! = 64
/// primary    := NUMBER | CONSTANT | "(" expression ")" | FUNCTION "(" expression ("," expression)* ")"
/// ```
library;

import 'errors.dart';
import 'scientific.dart' show trigFunctions;
import 'tokenizer.dart';

const int maxNestingDepth = 32;

sealed class AstNode {
  const AstNode();
}

class NumberNode extends AstNode {
  const NumberNode(this.literal);
  final String literal;
}

class ConstantNode extends AstNode {
  const ConstantNode(this.name);
  final String name;
}

class UnaryNode extends AstNode {
  const UnaryNode(this.op, this.operand);
  final String op;
  final AstNode operand;
}

class BinaryNode extends AstNode {
  const BinaryNode(this.op, this.left, this.right);
  final String op;
  final AstNode left;
  final AstNode right;
}

class FactorialNode extends AstNode {
  const FactorialNode(this.operand);
  final AstNode operand;
}

class CallNode extends AstNode {
  const CallNode(this.fn, this.args);
  final String fn;
  final List<AstNode> args;
}

AstNode parse(String input) => _Parser(tokenize(input)).parse();

class _Parser {
  _Parser(this._tokens);

  final List<Token> _tokens;
  int _index = 0;
  int _depth = 0;

  AstNode parse() {
    final node = _expression();
    final extra = _peek();
    if (extra != null) {
      if (extra.type == TokenType.rparen) {
        throw CalculatorError(
          CalculatorErrorCode.mismatchedParentheses,
          'Unmatched ")" at position ${extra.pos + 1}.',
          extra.pos,
        );
      }
      if (extra.type == TokenType.comma) throw _commaError(extra.pos);
      throw CalculatorError(
        CalculatorErrorCode.unexpectedToken,
        'Missing operator before ${extra.describe()} at position ${extra.pos + 1}.',
        extra.pos,
      );
    }
    return node;
  }

  Token? _peek() => _index < _tokens.length ? _tokens[_index] : null;

  Token? _next() => _index < _tokens.length ? _tokens[_index++] : null;

  bool _isOp(Token? token, String ops) =>
      token != null && token.type == TokenType.op && ops.contains(token.value);

  CalculatorError _commaError(int pos) => CalculatorError(
    CalculatorErrorCode.unexpectedToken,
    'Unexpected "," at position ${pos + 1}. Commas only separate function arguments, e.g. '
    'log(8, 2); thousands separators are not supported.',
    pos,
  );

  void _enter() {
    if (++_depth > maxNestingDepth) {
      throw const CalculatorError(
        CalculatorErrorCode.tooComplex,
        'Expression is nested too deeply (max depth $maxNestingDepth).',
      );
    }
  }

  void _leave() => _depth--;

  AstNode _expression() {
    var left = _term();
    while (_isOp(_peek(), '+-')) {
      final op = _next()!.value;
      left = BinaryNode(op, left, _term());
    }
    return left;
  }

  AstNode _term() {
    var left = _unary();
    while (_isOp(_peek(), '*/%')) {
      final op = _next()!.value;
      left = BinaryNode(op, left, _unary());
    }
    return left;
  }

  AstNode _unary() {
    final token = _peek();
    if (_isOp(token, '+-')) {
      _next();
      _enter();
      final operand = _unary();
      _leave();
      return UnaryNode(token!.value, operand);
    }
    return _power();
  }

  AstNode _power() {
    final base = _postfix();
    if (_isOp(_peek(), '^')) {
      _next();
      _enter();
      final exponent = _unary();
      _leave();
      return BinaryNode('^', base, exponent);
    }
    return base;
  }

  AstNode _postfix() {
    var node = _primary();
    while (_peek()?.type == TokenType.bang) {
      _next();
      node = FactorialNode(node);
    }
    return node;
  }

  AstNode _primary() {
    final token = _next();
    if (token == null) {
      throw const CalculatorError(
        CalculatorErrorCode.unexpectedEnd,
        'Expression ends unexpectedly; a number or "(" is missing.',
      );
    }
    switch (token.type) {
      case TokenType.number:
        return NumberNode(token.value);
      case TokenType.constant:
        return ConstantNode(token.value);
      case TokenType.lparen:
        return _parenthesized(token.pos);
      case TokenType.func:
        final open = _next();
        if (open?.type != TokenType.lparen) {
          throw CalculatorError(
            CalculatorErrorCode.unexpectedToken,
            '"${token.value}" must be followed by "(" (position ${token.pos + 1}), e.g. ${token.value}(2).',
            token.pos,
          );
        }
        final args = _argumentList(open!.pos);
        final (min, max) = functionArity[token.value]!;
        if (args.length < min || args.length > max) {
          final expected = min == max ? '$min' : '$min or $max';
          throw CalculatorError(
            CalculatorErrorCode.unexpectedToken,
            '"${token.value}" takes $expected argument${max == 1 ? '' : 's'}, but got ${args.length}.',
            token.pos,
          );
        }
        return CallNode(token.value, args);
      case TokenType.comma:
        throw _commaError(token.pos);
      default:
        throw CalculatorError(
          CalculatorErrorCode.unexpectedToken,
          'Unexpected ${token.describe()} at position ${token.pos + 1}.',
          token.pos,
        );
    }
  }

  AstNode _parenthesized(int openPos) {
    _enter();
    if (_peek()?.type == TokenType.rparen) {
      throw CalculatorError(
        CalculatorErrorCode.unexpectedToken,
        'Empty parentheses at position ${openPos + 1}.',
        openPos,
      );
    }
    final inner = _expression();
    final close = _next();
    if (close?.type == TokenType.comma) throw _commaError(close!.pos);
    if (close?.type != TokenType.rparen) {
      throw CalculatorError(
        CalculatorErrorCode.mismatchedParentheses,
        'Missing ")" for "(" at position ${openPos + 1}.',
        openPos,
      );
    }
    _leave();
    return inner;
  }

  List<AstNode> _argumentList(int openPos) {
    _enter();
    if (_peek()?.type == TokenType.rparen) {
      throw CalculatorError(
        CalculatorErrorCode.unexpectedToken,
        'Empty parentheses at position ${openPos + 1}.',
        openPos,
      );
    }
    final args = [_expression()];
    while (_peek()?.type == TokenType.comma) {
      _next();
      args.add(_expression());
    }
    final close = _next();
    if (close?.type != TokenType.rparen) {
      throw CalculatorError(
        CalculatorErrorCode.mismatchedParentheses,
        'Missing ")" for "(" at position ${openPos + 1}.',
        openPos,
      );
    }
    _leave();
    return args;
  }
}

const Map<String, int> _precedence = {'+': 1, '-': 1, '*': 2, '/': 2, '%': 2, '^': 4};

/// Serializes an AST back to a canonical, fully explicit ASCII expression.
String stringifyAst(AstNode node, [int parentPrecedence = 0]) {
  switch (node) {
    case NumberNode(:final literal):
      return literal;
    case ConstantNode(:final name):
      return name;
    case CallNode(:final fn, :final args):
      return '$fn(${args.map(stringifyAst).join(', ')})';
    case FactorialNode(:final operand):
      return '${stringifyAst(operand, 5)}!';
    case UnaryNode(:final op, :final operand):
      final text = '$op${stringifyAst(operand, 3)}';
      return parentPrecedence > 3 ? '($text)' : text;
    case BinaryNode(:final op, :final left, :final right):
      final p = _precedence[op]!;
      final l = stringifyAst(left, op == '^' ? p + 1 : p);
      final r = stringifyAst(right, op == '^' ? p - 1 : p + 1);
      final text = '$l $op $r';
      return p < parentPrecedence ? '($text)' : text;
  }
}

/// True if the AST contains sin/cos/tan/asin/acos/atan (so the angle unit affects the result).
bool usesAngles(AstNode node) => switch (node) {
  CallNode(:final fn, :final args) => trigFunctions.contains(fn) || args.any(usesAngles),
  UnaryNode(:final operand) || FactorialNode(:final operand) => usesAngles(operand),
  BinaryNode(:final left, :final right) => usesAngles(left) || usesAngles(right),
  _ => false,
};
