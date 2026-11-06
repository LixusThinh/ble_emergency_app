import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'schema.dart';

/// Key/value preferences that live outside any one network session.
abstract interface class SettingsStore {
  Future<Map<String, String>> load();

  /// Stores [value] under [key]; null removes the key.
  Future<void> write(String key, String? value);
  Future<void> close();
}

class MemorySettingsStore implements SettingsStore {
  final Map<String, String> values;
  MemorySettingsStore([Map<String, String>? values]) : values = values ?? {};
  @override
  Future<Map<String, String>> load() async => Map.of(values);
  @override
  Future<void> write(String key, String? value) async {
    value == null ? values.remove(key) : values[key] = value;
  }

  @override
  Future<void> close() async {}
}

/// Settings in the `settings` table of the app database, on a connection of
/// their own that stays open while the message store opens and closes.
class SqliteSettingsStore implements SettingsStore {
  final Database db;
  SqliteSettingsStore._(this.db);
  static Future<SqliteSettingsStore> open({
    DatabaseFactory? factory,
    String? file,
    String? key,
  }) async => SqliteSettingsStore._(
    await openMeshDatabase(
      factory: factory,
      file: file,
      key: key,
      singleInstance: false,
    ),
  );

  @override
  Future<Map<String, String>> load() async => {
    for (final r in await db.query('settings'))
      r['key'] as String: r['value'] as String,
  };

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      await db.delete('settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert('settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  @override
  Future<void> close() => db.close();
}
