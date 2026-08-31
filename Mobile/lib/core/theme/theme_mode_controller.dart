import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'appearance.theme_mode';

final themeModeProvider = AsyncNotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final preferences = await SharedPreferences.getInstance();
    return _decode(preferences.getString(_themeModeKey));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final previous = state.value ?? ThemeMode.system;
    state = AsyncData(mode);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_themeModeKey, mode.name);
    } catch (error, stackTrace) {
      state = AsyncData(previous);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

ThemeMode _decode(String? value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.light,
};
