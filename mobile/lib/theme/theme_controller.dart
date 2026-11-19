import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages and persists the application's ThemeMode (light, dark, or system).
class ThemeController extends ChangeNotifier {
  static const String themePreferenceKey = 'app_theme_mode';

  static ThemeController? _instance;
  static ThemeController get instance => _instance ??= ThemeController();

  final FlutterSecureStorage _storage;
  ThemeMode _themeMode = ThemeMode.system;
  bool _isInitialized = false;

  ThemeController({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  ThemeMode get themeMode => _themeMode;
  bool get isInitialized => _isInitialized;

  /// Loads saved theme mode from storage.
  Future<void> loadThemeMode() async {
    try {
      final savedMode = await _storage.read(key: themePreferenceKey);
      if (savedMode == 'light') {
        _themeMode = ThemeMode.light;
      } else if (savedMode == 'dark') {
        _themeMode = ThemeMode.dark;
      } else {
        _themeMode = ThemeMode.system;
      }
    } catch (_) {
      _themeMode = ThemeMode.system;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Updates and persists the selected ThemeMode immediately.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode && _isInitialized) return;
    _themeMode = mode;
    notifyListeners();

    if (mode == ThemeMode.light) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ));
    } else if (mode == ThemeMode.dark) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF111827),
        systemNavigationBarIconBrightness: Brightness.light,
      ));
    }

    try {
      String modeString = 'system';
      if (mode == ThemeMode.light) {
        modeString = 'light';
      } else if (mode == ThemeMode.dark) {
        modeString = 'dark';
      }
      await _storage.write(key: themePreferenceKey, value: modeString);
    } catch (_) {
      // Storage error handled silently without breaking UI
    }
  }
}
