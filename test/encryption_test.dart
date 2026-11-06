import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ble_emergency_app/core/identity.dart';
import 'package:ble_emergency_app/core/packet.dart';
import 'package:ble_emergency_app/messaging/schema.dart';
import 'package:ble_emergency_app/messaging/settings_store.dart';
import 'package:ble_emergency_app/messaging/sqlite_store.dart';
import 'package:ble_emergency_app/messaging/store.dart';
import 'package:ble_emergency_app/routing/router.dart';
import 'package:ble_emergency_app/simulator/network.dart';

/// The same SQLite3 Multiple Ciphers build the phone uses, through FFI.
void main() {
  sqfliteFfiInit();
  const key =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  const otherKey =
      'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';
  const secret = 'Tôi ở tầng 3, nhà số 12 — SOS';
  late Directory dir;
  late String file;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mesh_enc_');
    file = path.join(dir.path, databaseName);
  });
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Windows may hold the WAL file briefly.
    }
  });

  Future<Packet> signed(String text) async => MeshRouter(
    identity: await Identity.create(),
    transport: SimNetwork().node('x'),
    store: MemoryStore(),
    name: 'x',
  ).publish(MessageKind.sos, MessageBody(text));

  Future<void> write(String text, {String? key}) async {
    final store = await SqliteStore.open(file: file, key: key);
    await store.save(StoredMessage(await signed(text), 'abc', text));
    await store.close();
  }

  /// Every file SQLite keeps for [file], as text, to look for leaks.
  String raw() => [
    for (final suffix in ['', '-wal'])
      if (File('$file$suffix').existsSync())
        latin1.decode(File('$file$suffix').readAsBytesSync()),
  ].join();
  String utf8Raw() => [
    for (final suffix in ['', '-wal'])
      if (File('$file$suffix').existsSync())
        utf8.decode(
          File('$file$suffix').readAsBytesSync(),
          allowMalformed: true,
        ),
  ].join();

  test('an encrypted database reads only with its key', () async {
    await write(secret, key: key);
    expect(await isPlainDatabase(file), isFalse);
    expect(utf8Raw(), isNot(contains(secret)));
    expect(raw(), isNot(contains('CREATE TABLE')));
    await expectLater(
      SqliteStore.open(file: file),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      SqliteStore.open(file: file, key: otherKey),
      throwsA(isA<DatabaseException>()),
    );
    final store = await SqliteStore.open(file: file, key: key);
    addTearDown(store.close);
    expect((await store.messages()).single.text, secret);
  });

  test('a test database without a key stays plain (control)', () async {
    await write(secret);
    expect(await isPlainDatabase(file), isTrue);
    expect(utf8Raw(), contains(secret));
  });

  test('an unencrypted database from an older version is encrypted in '
      'place and keeps its data', () async {
    await write(secret);
    final settings = await SqliteSettingsStore.open(file: file);
    await settings.write('display_name', 'An');
    await settings.close();
    expect(await useMeshDatabase(file: file, key: key), isNull);
    expect(await isPlainDatabase(file), isFalse);
    expect(utf8Raw(), isNot(contains(secret)));
    expect(File('$file.plain').existsSync(), isFalse);
    final store = await SqliteStore.open();
    addTearDown(store.close);
    expect(await store.db.getVersion(), schemaVersion);
    expect((await store.messages()).single.text, secret);
    final reopened = await SqliteSettingsStore.open();
    addTearDown(reopened.close);
    expect((await reopened.load())['display_name'], 'An');
    // Running it again on the encrypted file changes nothing.
    expect(await useMeshDatabase(file: file, key: key), isNull);
    expect((await store.messages()).single.text, secret);
  });

  test('an interrupted encryption starts over from the plain copy', () async {
    await write(secret);
    await File(file).copy('$file.plain');
    // The run was killed while rewriting pages.
    File(file).writeAsBytesSync(List.filled(8192, 0x5a));
    expect(await useMeshDatabase(file: file, key: key), isNull);
    expect(await isPlainDatabase(file), isFalse);
    expect(File('$file.plain').existsSync(), isFalse);
    final store = await SqliteStore.open();
    addTearDown(store.close);
    expect((await store.messages()).single.text, secret);
  });

  test('a database the key cannot open is set aside, not deleted', () async {
    await write(secret, key: key);
    final notice = await useMeshDatabase(file: file, key: otherKey);
    expect(notice, isNotNull);
    final aside = dir
        .listSync()
        .whereType<File>()
        .where((f) => path.basename(f.path).contains('.unreadable-'))
        .toList();
    expect(aside, isNotEmpty);
    // The old file still opens with the old key.
    final old = await SqliteStore.open(
      file: aside.firstWhere((f) => RegExp(r'-\d+$').hasMatch(f.path)).path,
      key: key,
    );
    expect((await old.messages()).single.text, secret);
    await old.close();
    // The app starts on a new, empty, encrypted database.
    final store = await SqliteStore.open();
    addTearDown(store.close);
    expect(await store.messages(), isEmpty);
    expect(await isPlainDatabase(file), isFalse);
  });

  test('a lost Keystore key starts a new database and says so', () async {
    await write(secret, key: key);
    final notice = await useMeshDatabase(
      file: file,
      key: otherKey,
      discard: true,
    );
    expect(notice, contains('database mới'));
    final store = await SqliteStore.open();
    addTearDown(store.close);
    expect(await store.messages(), isEmpty);
  });

  test('keys that are not 64 hex digits are refused', () async {
    for (final bad in ["x'; DROP TABLE messages; --", key.substring(1), '']) {
      expect(() => useMeshDatabase(file: file, key: bad), throwsArgumentError);
      expect(() => openMeshDatabase(file: file, key: bad), throwsArgumentError);
    }
  });
}
