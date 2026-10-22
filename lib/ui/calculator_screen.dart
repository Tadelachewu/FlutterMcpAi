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
    final degrees = state.angleUnit == AngleUnit.degrees;

    final footer = _CalculatorFooter(
      historyCount: state.history.length,
      onHistory: () async {
        await showHistorySheet(context);
        if (mounted) _focusNode.requestFocus();
      },
      onExplain: state.expression.trim().isEmpty || chatBusy ? null : _explain,
    );

    // Nothing here scrolls: the display stays at the top and the keys share the remaining
    // height, so both are always fully visible.
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final short = constraints.maxHeight < 560;
            final sideBySide = short && constraints.maxWidth >= 480;
            final scientific = KeyGrid(
              keys: scientificKeys,
              spacing: short ? 4 : 6,
              semanticLabel: 'Scientific functions',
              onKey: _press,
              labelFor: (k) => k.value == 'angle' ? (degrees ? 'DEG' : 'RAD') : null,
              semanticLabelFor: (k) => k.value == 'angle'
                  ? 'Angle unit: ${degrees ? 'degrees' : 'radians'}. Double tap to switch.'
                  : null,
            );
            final main = KeyGrid(
              keys: mainKeys,
              spacing: short ? 5 : 8,
              semanticLabel: 'Calculator keypad',
              onKey: _press,
            );
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: sideBySide ? 1100 : 560),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, short ? 8 : 12, 12, short ? 8 : 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CalculatorDisplay(state: state, compact: short),
                      SizedBox(height: short ? 8 : 12),
                      Expanded(
                        child: sideBySide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(child: scientific),
                                        const SizedBox(height: 6),
                                        footer,
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: main),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Scientific rows are a bit lower than the main keys.
                                  Expanded(flex: 32, child: scientific),
                                  const SizedBox(height: 10),
                                  Expanded(flex: 50, child: main),
                                ],
                              ),
                      ),
                      if (!sideBySide) ...[const SizedBox(height: 8), footer],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// History and "Explain with AI" buttons on a solid strip, so they stay readable on the photo.
class _CalculatorFooter extends StatelessWidget {
  const _CalculatorFooter({
    required this.historyCount,
    required this.onHistory,
    required this.onExplain,
  });

  final int historyCount;
  final VoidCallback onHistory;
  final VoidCallback? onExplain;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Both buttons may shrink (narrow phones, large text) instead of overflowing.
          Flexible(
            child: TextButton.icon(
              onPressed: onHistory,
              icon: const Icon(Icons.history, size: 20),
              label: Text(
                historyCount == 0 ? 'History' : 'History ($historyCount)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Flexible(
            child: TextButton(
              onPressed: onExplain,
              child: const Text('Explain with AI →', overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }
}
