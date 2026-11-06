import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ble_emergency_app/app/settings.dart';
import 'package:ble_emergency_app/core/identity.dart';
import 'package:ble_emergency_app/core/packet.dart';
import 'package:ble_emergency_app/messaging/schema.dart';
import 'package:ble_emergency_app/messaging/settings_store.dart';
import 'package:ble_emergency_app/messaging/sqlite_store.dart';
import 'package:ble_emergency_app/messaging/store.dart';
import 'package:ble_emergency_app/routing/router.dart';
import 'package:ble_emergency_app/simulator/network.dart';

/// Real SQLite through FFI, one fresh file per test.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory dir;
  late String file;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mesh_db_');
    file = path.join(dir.path, databaseName);
  });
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Windows may hold the WAL file briefly; the OS temp dir is cleaned anyway.
    }
  });

  Future<Set<String>> objects(Database db, String type) async => {
    for (final r in await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = ? AND name NOT LIKE 'sqlite_%'",
      [type],
    ))
      r['name'] as String,
  };

  Future<Packet> signed(String text) async {
    final id = await Identity.create();
    final r = MeshRouter(
      identity: id,
      transport: SimNetwork().node('x'),
      store: MemoryStore(),
      name: 'x',
    );
    return r.publish(MessageKind.sos, MessageBody(text));
  }

  test('fresh install creates the latest schema in WAL mode', () async {
    final db = await openMeshDatabase(factory: factory, file: file);
    addTearDown(db.close);
    expect(await db.getVersion(), schemaVersion);
    expect(await objects(db, 'table'), {
      'packets',
      'messages',
      'contacts',
      'settings',
      'handoffs',
    });
    expect(
      await objects(db, 'index'),
      containsAll([
        'packets_created',
        'packets_pending',
        'messages_created',
        'contacts_seen',
      ]),
    );
    final mode = await db.rawQuery('PRAGMA journal_mode');
    expect(mode.single.values.single.toString().toLowerCase(), 'wal');
  });

  test('upgrading a 1.0.0 database keeps its messages and packets', () async {
    // Build the database exactly as version 1 shipped it.
    final v1 = await openMeshDatabase(factory: factory, file: file, version: 1);
    final p = await signed('trước khi nâng cấp');
    await v1.insert('packets', {
      'id': p.messageId,
      'bytes': p.encode(),
      'created': p.timestamp,
      'priority': p.priority,
    });
    await v1.insert('messages', {
      'id': p.messageId,
      'bytes': p.encode(),
      'sender': 'abc',
      'text': 'trước khi nâng cấp',
      'outgoing': 0,
      'created': p.timestamp,
    });
    expect(await objects(v1, 'table'), {'packets', 'messages'});
    await v1.close();

    final store = await SqliteStore.open(factory: factory, file: file);
    addTearDown(store.close);
    expect(await store.db.getVersion(), schemaVersion);
    expect((await store.messages()).single.text, 'trước khi nâng cấp');
    expect((await store.pending()).single.messageId, p.messageId);
    expect(await store.hasSeen(p.messageId), isTrue);
    expect(await store.contacts(), isEmpty);
  });

  test('contacts persist across reopen, newest first, upsert by id', () async {
    final key = Uint8List.fromList(List.filled(32, 7));
    var store = await SqliteStore.open(factory: factory, file: file);
    await store.saveContact(Contact('a', 'An', key), 100);
    await store.saveContact(Contact('b', 'Bình', key), 200);
    await store.saveContact(Contact('a', 'An (đổi tên)', key), 300);
    await store.close();
    store = await SqliteStore.open(factory: factory, file: file);
    addTearDown(store.close);
    final list = await store.contacts();
    expect(list.map((c) => c.id), ['a', 'b']);
    expect(list.first.name, 'An (đổi tên)');
    expect(list.first.exchangeKey, key);
  });

  test('contacts are capped at maxContacts, oldest dropped', () async {
    final store = await SqliteStore.open(factory: factory, file: file);
    addTearDown(store.close);
    final key = Uint8List(32);
    await store.db.transaction((t) async {
      for (var i = 0; i < maxContacts; i++) {
        await t.insert('contacts', {
          'id': 'n$i',
          'name': 'N$i',
          'exchange_key': key,
          'last_seen': 1000 + i,
        });
      }
    });
    await store.saveContact(Contact('moi', 'Mới', key), 999999);
    final ids = (await store.contacts()).map((c) => c.id).toList();
    expect(ids.length, maxContacts);
    expect(ids.first, 'moi');
    expect(ids, isNot(contains('n0')));
  });

  test('settings survive reopen and coexist with the message store', () async {
    final messages = await SqliteStore.open(factory: factory, file: file);
    var settingsStore = await SqliteSettingsStore.open(
      factory: factory,
      file: file,
    );
    var settings = await AppSettings.load(settingsStore);
    expect(settings.name, '');
    expect(settings.themeMode, ThemeMode.system);
    settings
      ..name = 'Thịnh • Nhóm 1'
      ..themeMode = ThemeMode.dark;
    await settings.saved;
    // Closing the message store (network stop) must not close settings.
    await messages.close();
    settings.name = 'Thịnh';
    await settings.saved;
    expect(settings.lastWriteError, isNull);
    await settingsStore.close();

    settingsStore = await SqliteSettingsStore.open(
      factory: factory,
      file: file,
    );
    addTearDown(settingsStore.close);
    settings = await AppSettings.load(settingsStore);
    expect(settings.name, 'Thịnh');
    expect(settings.themeMode, ThemeMode.dark);
    settings
      ..name = '  '
      ..themeMode = ThemeMode.system;
    await settings.saved;
    expect(await settingsStore.load(), isEmpty);
  });

  test('router restores contacts saved by an earlier session', () async {
    final store = await SqliteStore.open(factory: factory, file: file);
    final network = SimNetwork();
    final a = MeshRouter(
      identity: await Identity.create(),
      transport: network.node('A'),
      store: store,
      name: 'A',
    );
    final b = MeshRouter(
      identity: await Identity.create(),
      transport: network.node('B'),
      store: MemoryStore(),
      name: 'Bình',
    );
    await a.start();
    await b.start();
    network.connect('A', 'B');
    await network.drain([a, b]);
    expect(a.contacts[b.identity.id]?.name, 'Bình');
    await a.dispose(); // closes the store, like stopping the network

    final reopened = await SqliteStore.open(factory: factory, file: file);
    final again = MeshRouter(
      identity: a.identity,
      transport: SimNetwork().node('A'),
      store: reopened,
      name: 'A',
    );
    await again.start();
    addTearDown(again.dispose);
    final restored = again.contacts[b.identity.id];
    expect(restored?.name, 'Bình');
    expect(restored?.exchangeKey, b.identity.publicExchange);
    await b.dispose();
  });

  test('handoffs count distinct phones and survive reopen', () async {
    var store = await SqliteStore.open(factory: factory, file: file);
    final p = await signed('ai nhận được?');
    await store.save(StoredMessage(p, 'me', 'ai nhận được?', outgoing: true));
    expect((await store.messages()).single.handoffs, 0);
    await store.recordHandoff(p.messageId, 'b');
    await store.recordHandoff(p.messageId, 'c');
    await store.recordHandoff(p.messageId, 'b');
    await store.close();
    store = await SqliteStore.open(factory: factory, file: file);
    addTearDown(store.close);
    expect((await store.messages()).single.handoffs, 2);
  });

  test('a full packet table drops settled, then chat, before SOS', () async {
    final store = await SqliteStore.open(factory: factory, file: file);
    addTearDown(store.close);
    final now = DateTime.now().millisecondsSinceEpoch;
    Map<String, Object> row(
      String id,
      MessageKind kind,
      int created, {
      bool acked = false,
    }) => {
      'id': id,
      'bytes': Uint8List(0),
      'created': created,
      'priority': kind == MessageKind.sos ? 0 : 4,
      'acked': acked ? 1 : 0,
    };
    await store.db.transaction((t) async {
      await t.insert('packets', row('sos-cu', MessageKind.sos, now - 7200000));
      await t.insert(
        'packets',
        row('da-xong', MessageKind.chat, now, acked: true),
      );
      for (var i = 0; i < maxPackets - 2; i++) {
        await t.insert('packets', row('chat$i', MessageKind.chat, now - i));
      }
    });
    final p = await signed('mới');
    await store.retain(p);
    final ids = {
      for (final r in await store.db.query('packets', columns: ['id']))
        r['id'] as String,
    };
    expect(ids, hasLength(maxPackets));
    expect(ids, containsAll(['sos-cu', p.messageId]));
    expect(ids, isNot(contains('da-xong')));
    await store.retain(await signed('mới nữa'));
    final after = await store.db.query('packets', columns: ['id']);
    expect(after.map((r) => r['id']), contains('sos-cu'));
    // The oldest chat goes once nothing settled is left.
    expect(after.map((r) => r['id']), isNot(contains('chat${maxPackets - 3}')));
  });
}
