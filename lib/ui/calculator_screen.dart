import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../calculator/calculator_controller.dart';
import '../chat/chat_controller.dart';
import 'navigation.dart';
import 'widgets/display.dart';
import 'widgets/history.dart';
import 'widgets/keypad.dart';

class CalculatorScreen extends ConsumerStatefulWidget {
  const CalculatorScreen({super.key});

  @override
  ConsumerState<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends ConsumerState<CalculatorScreen> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'calculator');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  CalculatorController get _calc => ref.read(calculatorProvider.notifier);

  void _press(KeyDef key) {
    // Keep hardware-keyboard input going to the calculator after a tap.
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
    switch (key.value) {
      case 'angle':
        _calc.toggleAngleUnit();
      case 'clear':
        _calc.clear();
      case 'backspace':
        _calc.backspace();
      case 'equals':
        _calc.equals();
      default:
        _calc.input(key.value);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed || keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _calc.equals();
    } else if (key == LogicalKeyboardKey.backspace) {
      _calc.backspace();
    } else if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.delete) {
      _calc.clear();
    } else {
      final ch = event.character;
      if (ch == null || ch.length != 1) return KeyEventResult.ignored;
      if (RegExp(r'^[0-9.]$').hasMatch(ch) || '+-*/%^()!,'.contains(ch)) {
        _calc.input(ch);
      } else if (ch == 'x' || ch == 'X') {
        _calc.input('*');
      } else if (ch == 's' || ch == 'S') {
        _calc.input('sqrt(');
      } else if (ch == '=') {
        _calc.equals();
      } else {
        return KeyEventResult.ignored;
      }
    }
    return KeyEventResult.handled;
  }

  void _explain() {
    final prompt = _calc.explainPrompt();
    if (prompt == null) return;
    ref.read(chatControllerProvider.notifier).send(prompt);
    ref.read(homeTabProvider.notifier).show(HomeTab.chat);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(calculatorProvider);
    final chatBusy = ref.watch(chatControllerProvider.select((s) => s.busy));
    final theme = Theme.of(context);
    final degrees = state.angleUnit == AngleUnit.degrees;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              CalculatorDisplay(state: state),
              const SizedBox(height: 12),
              KeyGrid(
                keys: scientificKeys,
                keyHeight: 48,
                spacing: 6,
                semanticLabel: 'Scientific functions',
                onKey: _press,
                labelFor: (k) => k.value == 'angle' ? (degrees ? 'DEG' : 'RAD') : null,
                semanticLabelFor: (k) => k.value == 'angle'
                    ? 'Angle unit: ${degrees ? 'degrees' : 'radians'}. Double tap to switch.'
                    : null,
              ),
              const SizedBox(height: 10),
              KeyGrid(
                keys: mainKeys,
                keyHeight: 60,
                semanticLabel: 'Calculator keypad',
                onKey: _press,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Local, exact decimal math · no network needed',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: state.expression.trim().isEmpty || chatBusy ? null : _explain,
                    child: const Text('Explain with AI →'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              HistoryPanel(
                entries: state.history,
                onSelect: _calc.useHistoryEntry,
                onClear: _calc.clearHistory,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
