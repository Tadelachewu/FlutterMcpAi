import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/calculator_screen.dart';
import 'ui/chat_screen.dart';
import 'ui/navigation.dart';

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
    final wide = MediaQuery.sizeOf(context).width >= splitBreakpoint;
    final dark = ref.watch(themeModeProvider) == ThemeMode.dark;

    final appBar = AppBar(
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

    return Scaffold(
      appBar: appBar,
      body: IndexedStack(index: tab.index, children: const [CalculatorScreen(), ChatScreen()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.index,
        onDestinationSelected: (i) => ref.read(homeTabProvider.notifier).show(HomeTab.values[i]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calculate_outlined),
            selectedIcon: Icon(Icons.calculate),
            label: 'Calculator',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'AI Chat',
          ),
        ],
      ),
    );
  }
}
