import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/calculator_screen.dart';
import 'ui/chat_screen.dart';
import 'ui/navigation.dart';
import 'ui/widgets/curved_nav_bar.dart';

const Color _seed = Color(0xFF0EA5E9);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    // Transparent so the background image (see AppBackground) shows behind every screen.
    scaffoldBackgroundColor: Colors.transparent,
    visualDensity: VisualDensity.standard,
  );
}

class CalculatorApp extends ConsumerWidget {
  const CalculatorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'AI Scientific Calculator',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      builder: (context, child) => AppBackground(child: child!),
      home: const HomeShell(),
    );
  }
}

/// The app_icon1.png photo behind all screens, under a tint that keeps text and keys readable.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  static const String image = 'assets/icon/app_icon1.png';

  /// How much of the theme's background color covers the photo (0 = photo only, 1 = no photo).
  static const double tint = 0.78;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF0B1220) : Theme.of(context).colorScheme.surface;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: base),
        Image.asset(
          image,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
          gaplessPlayback: true,
        ),
        ColoredBox(color: base.withValues(alpha: tint)),
        child,
      ],
    );
  }
}

/// Side-by-side on wide screens (tablets, desktop), tabs on phones.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const double splitBreakpoint = 900;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(homeTabProvider);
    final size = MediaQuery.sizeOf(context);
    // Side by side only when there is room for both panes at full height (tablets, desktop).
    final wide = size.width >= splitBreakpoint && size.height >= 600;
    // Phones in landscape: a side rail and a lower app bar leave more height for the keypad.
    final landscape = !wide && size.width > size.height;
    // Small phones: slightly lower bars so the keypad keeps comfortable key sizes.
    final shortScreen = size.height < 720;
    final dark = ref.watch(themeModeProvider) == ThemeMode.dark;

    final appBar = AppBar(
      toolbarHeight: landscape ? 44 : (shortScreen ? 52 : null),
      title: const Text('AI Scientific Calculator'),
      actions: [
        IconButton(
          tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
          icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          onPressed: ref.read(themeModeProvider.notifier).toggle,
        ),
      ],
    );

    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: const Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 460, child: CalculatorScreen()),
            VerticalDivider(width: 1),
            Expanded(child: ChatScreen()),
          ],
        ),
      );
    }

    final pages = IndexedStack(
      index: tab.index,
      children: const [CalculatorScreen(), ChatScreen()],
    );
    void select(int i) => ref.read(homeTabProvider.notifier).show(HomeTab.values[i]);

    if (landscape) {
      return Scaffold(
        appBar: appBar,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: tab.index,
                onDestinationSelected: select,
                labelType: NavigationRailLabelType.all,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.calculate_outlined),
                    selectedIcon: Icon(Icons.calculate),
                    label: Text('Calculator'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.chat_bubble_outline),
                    selectedIcon: Icon(Icons.chat_bubble),
                    label: Text('AI Chat'),
                  ),
                ],
              ),
              Expanded(child: pages),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: pages,
      bottomNavigationBar: CurvedNavBar(
        compact: shortScreen,
        selectedIndex: tab.index,
        onSelected: select,
        items: const [
          CurvedNavItem(
            icon: Icons.calculate_outlined,
            selectedIcon: Icons.calculate,
            label: 'Calculator',
          ),
          CurvedNavItem(
            icon: Icons.chat_bubble_outline,
            selectedIcon: Icons.chat_bubble,
            label: 'AI Chat',
          ),
        ],
      ),
    );
  }
}
