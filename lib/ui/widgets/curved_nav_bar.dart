import 'package:flutter/material.dart';

class CurvedNavItem {
  const CurvedNavItem({required this.icon, required this.selectedIcon, required this.label});

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Bottom navigation bar with a curved dip under the selected tab, whose icon floats in a circle
/// above the bar. The dip and circle slide to the newly selected tab. Every tab keeps its label
/// and is a labelled button for screen readers.
class CurvedNavBar extends StatelessWidget {
  const CurvedNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.compact = false,
  });

  final List<CurvedNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Lower bar for short screens, so the calculator keeps room for its keys.
  final bool compact;

  /// How far the floating circle rises above the bar.
  static const double rise = 28;
  static const double bubbleSize = 52;

  double get barHeight => compact ? 56 : 64;

  /// Total height including the raised circle (without the device's bottom inset).
  double get height => rise + barHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final selected = items[selectedIndex];

    return TweenAnimationBuilder<double>(
      tween: Tween(end: selectedIndex.toDouble()),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, position, _) => LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / items.length;
          final centerX = itemWidth * (position + 0.5);
          return SizedBox(
            height: height + bottomInset,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  top: rise,
                  child: CustomPaint(
                    painter: _CurvedBarPainter(
                      centerX: centerX,
                      color: scheme.surfaceContainer,
                      shadow: scheme.shadow,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: rise,
                  height: barHeight,
                  child: Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _NavItem(
                            item: items[i],
                            index: i,
                            count: items.length,
                            selected: i == selectedIndex,
                            // Fades the icon out as the circle arrives over this tab.
                            iconOpacity: (position - i).abs().clamp(0.0, 1.0),
                            onTap: () => onSelected(i),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: centerX - bubbleSize / 2,
                  top: rise - bubbleSize / 2,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: Material(
                        color: scheme.primary,
                        shape: const CircleBorder(),
                        elevation: 6,
                        shadowColor: scheme.shadow,
                        child: SizedBox.square(
                          dimension: bubbleSize,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              selected.selectedIcon,
                              key: ValueKey(selectedIndex),
                              color: scheme.onPrimary,
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.index,
    required this.count,
    required this.selected,
    required this.iconOpacity,
    required this.onTap,
  });

  final CurvedNavItem item;
  final int index;
  final int count;
  final bool selected;
  final double iconOpacity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${item.label}, tab ${index + 1} of $count',
      onTap: onTap,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Opacity(
              opacity: iconOpacity,
              child: Icon(item.icon, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// The bar's shape: flat top with a smooth dip centred at [centerX].
class _CurvedBarPainter extends CustomPainter {
  _CurvedBarPainter({required this.centerX, required this.color, required this.shadow});

  final double centerX;
  final Color color;
  final Color shadow;

  static const double depth = 30;
  static const double halfWidth = 50;

  @override
  void paint(Canvas canvas, Size size) {
    final x = centerX;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(x - halfWidth, 0)
      ..cubicTo(x - halfWidth * 0.55, 0, x - halfWidth * 0.62, depth, x, depth)
      ..cubicTo(x + halfWidth * 0.62, depth, x + halfWidth * 0.55, 0, x + halfWidth, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawShadow(path, shadow, 6, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CurvedBarPainter old) =>
      old.centerX != centerX || old.color != color || old.shadow != shadow;
}
