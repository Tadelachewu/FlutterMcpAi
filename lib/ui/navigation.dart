import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum HomeTab { calculator, chat }

final homeTabProvider = NotifierProvider<HomeTabController, HomeTab>(HomeTabController.new);

class HomeTabController extends Notifier<HomeTab> {
  @override
  HomeTab build() => HomeTab.calculator;

  void show(HomeTab tab) => state = tab;
}

/// Dark by default; the app bar button switches to the light theme for this session.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void toggle() => state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}
