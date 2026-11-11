import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light (default) / dark / system theme, remembered on this device.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.light);
  static final ThemeController instance = ThemeController._();

  static const _key = 'cafe_pos_theme_mode';

  /// True while the Super Admin is signed in: their (on-hold) screens keep the
  /// previous dark look, including every page they open.
  final ValueNotifier<bool> legacyAdmin = ValueNotifier(false);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = switch (prefs.getString(_key)) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };
    } catch (_) {
      value = ThemeMode.light;
    }
  }

  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }

  bool isDark(BuildContext context) =>
      value == ThemeMode.dark || (value == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);

  Future<void> toggle(BuildContext context) => set(isDark(context) ? ThemeMode.light : ThemeMode.dark);
}
