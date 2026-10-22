import 'package:flutter/material.dart';

import '../../chat/chat_controller.dart';

/// The text for the verification badge of a completed answer.
({String text, bool ok}) verificationLabel(UiMessage message) {
  if (message.fallback) return (text: 'AI unavailable — computed directly via MCP', ok: false);
  if (message.verified) {
    return (text: '✓ Verified by MCP tool: ${message.toolsUsed.toSet().join(', ')}', ok: true);
  }
  if (message.tools.isNotEmpty || message.toolsUsed.isNotEmpty) {
    return (text: '⚠ The MCP tool returned an error', ok: false);
  }
  return (text: '⚠ No calculator tool was used', ok: false);
}

class VerificationBadge extends StatelessWidget {
  const VerificationBadge({super.key, required this.message});

  final UiMessage message;

  @override
  Widget build(BuildContext context) {
    final label = verificationLabel(message);
    final color = label.ok ? Colors.green.shade500 : Colors.amber.shade700;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          // Tint over a solid base, so the text stays readable on the background photo.
          color: Color.alphaBlend(
            color.withValues(alpha: 0.14),
            Theme.of(context).colorScheme.surfaceContainerHigh,
          ),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          label.text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
        ),
      ),
    );
  }
}
