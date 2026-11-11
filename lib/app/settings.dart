import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../core/packet.dart';
import '../messaging/settings_store.dart';

/// User preferences, loaded once at launch and written through on change.
class AppSettings extends ChangeNotifier {
  static const nameKey = 'display_name',
      themeKey = 'theme_mode',
      onboardedKey = 'onboarded',
      installKey = 'install_id';
  final SettingsStore _store;
  final Map<String, String> _values;
  Future<void> _writes = Future.value();

  /// Last write failure, for tests and diagnostics; the UI keeps working on
  /// the in-memory value either way.
  Object? lastWriteError;

  /// Shown once when the app opens, e.g. that the database had to be reset.
  String? launchNotice;

  AppSettings._(this._store, this._values);

  /// Settings that are never persisted (widget tests, storage failure).
  /// [onboarded] false shows the welcome screens first.
  AppSettings.memory({bool onboarded = true})
    : this._(MemorySettingsStore(), {if (onboarded) onboardedKey: '1'});

  static Future<AppSettings> load(SettingsStore store) async =>
      AppSettings._(store, await store.load());

  /// Display name exactly as typed; may be empty.
  String get name => _values[nameKey] ?? '';
  set name(String value) {
    if (value == name) {
      return;
    }
    // No notify: only the text field shows the name before the network starts.
    _set(nameKey, value.trim().isEmpty ? null : value);
  }

  ThemeMode get themeMode =>
      ThemeMode.values.asNameMap()[_values[themeKey]] ?? ThemeMode.system;
  set themeMode(ThemeMode value) {
    if (value == themeMode) {
      return;
    }
    _set(themeKey, value == ThemeMode.system ? null : value.name);
    notifyListeners();
  }

  /// Whether the welcome screens have been seen (or skipped).
  bool get onboarded => _values[onboardedKey] == '1';
  set onboarded(bool value) {
    if (value == onboarded) {
      return;
    }
    _set(onboardedKey, value ? '1' : null);
    notifyListeners();
  }

  /// Random id of this installation, made on first use. Tells the server
  /// which phone a log came from without revealing the mesh identity.
  String get installId {
    final known = _values[installKey];
    if (known != null) {
      return known;
    }
    final id = hex(randomBytes(8));
    _set(installKey, id);
    return id;
  }

  /// A raw value, for stores that keep their own format (the login session).
  String? value(String key) => _values[key];

  /// Stores [value] under [key]; null removes it. Completes once written.
  Future<void> setValue(String key, String? value) {
    _set(key, value);
    return _writes;
  }

  /// Completes when every write queued so far has finished.
  Future<void> get saved => _writes;

  void _set(String key, String? value) {
    value == null ? _values.remove(key) : _values[key] = value;
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
