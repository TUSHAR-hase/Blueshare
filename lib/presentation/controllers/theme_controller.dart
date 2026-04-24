import 'package:flutter/material.dart';

import '../../domain/repositories/settings_repository.dart';

class ThemeController extends ChangeNotifier {
  ThemeController(this._settingsRepository);

  final SettingsRepository _settingsRepository;
  ThemeMode _themeMode = ThemeMode.system;
  bool _initialized = false;

  ThemeMode get themeMode => _themeMode;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _themeMode = await _settingsRepository.loadThemeMode();
    _initialized = true;
    notifyListeners();
  }

  Future<void> toggle() async {
    _themeMode =
        _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await _settingsRepository.saveThemeMode(_themeMode);
    notifyListeners();
  }
}
