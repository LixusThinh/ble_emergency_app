import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../messaging/settings_store.dart';

/// User preferences, loaded once at launch and written through on change.
class AppSettings extends ChangeNotifier {
  static const nameKey = 'display_name', themeKey = 'theme_mode';
  final SettingsStore _store;
  String _name;
  ThemeMode _themeMode;
  Future<void> _writes = Future.value();

  /// Last write failure, for tests and diagnostics; the UI keeps working on
  /// the in-memory value either way.
  Object? lastWriteError;

  /// Shown once when the app opens, e.g. that the database had to be reset.
  String? launchNotice;

  AppSettings._(this._store, this._name, this._themeMode);

  /// Settings that are never persisted (widget tests, storage failure).
  AppSettings.memory() : this._(MemorySettingsStore(), '', ThemeMode.system);

  static Future<AppSettings> load(SettingsStore store) async {
    final v = await store.load();
    return AppSettings._(
      store,
      v[nameKey] ?? '',
      ThemeMode.values.asNameMap()[v[themeKey]] ?? ThemeMode.system,
    );
  }

  /// Display name exactly as typed; may be empty.
  String get name => _name;
  set name(String value) {
    if (value == _name) {
      return;
    }
    _name = value;
    // No notify: only the text field shows the name before the network starts.
    _write(nameKey, value.trim().isEmpty ? null : value);
  }

  ThemeMode get themeMode => _themeMode;
  set themeMode(ThemeMode value) {
    if (value == _themeMode) {
      return;
    }
    _themeMode = value;
    notifyListeners();
    _write(themeKey, value == ThemeMode.system ? null : value.name);
  }

  /// Completes when every write queued so far has finished.
  Future<void> get saved => _writes;

  void _write(String key, String? value) {
    // Chained so a later value can never be overwritten by an earlier one.
    _writes = _writes.then((_) async {
      try {
        await _store.write(key, value);
      } catch (e) {
        lastWriteError = e;
        debugPrint('Không lưu được cài đặt $key: $e');
      }
    });
  }
}
