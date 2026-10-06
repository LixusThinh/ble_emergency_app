import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../core/packet.dart';
import 'store.dart';

class SqliteStore implements MessageStore {
  final Database db;
  SqliteStore._(this.db);
  static Future<SqliteStore> open() async {
    final db = await openDatabase(
      path.join(await getDatabasesPath(), 'emergency_mesh.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE packets (id TEXT PRIMARY KEY, bytes BLOB NOT NULL, created INTEGER NOT NULL, priority INTEGER NOT NULL, acked INTEGER NOT NULL DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE messages (id TEXT PRIMARY KEY, bytes BLOB NOT NULL, sender TEXT NOT NULL, text TEXT NOT NULL, outgoing INTEGER NOT NULL, acked INTEGER NOT NULL DEFAULT 0, lat REAL, lon REAL, created INTEGER NOT NULL)',
        );
        await db.execute('CREATE INDEX packets_created ON packets(created)');
      },
    );
    return SqliteStore._(db);
  }

  @override
  Future<bool> hasSeen(String id) async => (await db.query(
    'packets',
    columns: ['id'],
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  )).isNotEmpty;
  @override
  Future<void> retain(Packet p) async {
    await db.transaction((t) async {
      await t.delete(
        'packets',
        where: 'created < ?',
        whereArgs: [
          DateTime.now()
              .subtract(const Duration(hours: 24))
              .millisecondsSinceEpoch,
        ],
      );
      await t.rawDelete(
        'DELETE FROM packets WHERE id IN (SELECT id FROM packets ORDER BY created DESC LIMIT -1 OFFSET 4999)',
      );
      await t.insert('packets', {
        'id': p.messageId,
        'bytes': p.encode(),
        'created': p.timestamp,
        'priority': p.priority,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  @override
  Future<List<Packet>> pending() async {
    final rows = await db.query(
      'packets',
      where: 'acked = 0 AND created >= ?',
      whereArgs: [
        DateTime.now()
            .subtract(const Duration(hours: 24))
            .millisecondsSinceEpoch,
      ],
      orderBy: 'priority ASC, created ASC',
    );
    return rows.map((r) => Packet.decode(r['bytes'] as Uint8List)).toList();
  }

  @override
  Future<void> save(StoredMessage m) async {
    await db.insert('messages', {
      'id': m.packet.messageId,
      'bytes': m.packet.encode(),
      'sender': m.senderId,
      'text': m.text,
      'outgoing': m.outgoing ? 1 : 0,
      'lat': m.latitude,
      'lon': m.longitude,
      'created': m.packet.timestamp,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.rawDelete(
      'DELETE FROM messages WHERE id IN (SELECT id FROM messages ORDER BY created DESC LIMIT -1 OFFSET 2000)',
    );
  }

  @override
  Future<List<StoredMessage>> messages() async =>
      (await db.query('messages', orderBy: 'created DESC'))
          .map(
            (r) => StoredMessage(
              Packet.decode(r['bytes'] as Uint8List),
              r['sender'] as String,
              r['text'] as String,
              outgoing: r['outgoing'] == 1,
              acknowledged: r['acked'] == 1,
              latitude: (r['lat'] as num?)?.toDouble(),
              longitude: (r['lon'] as num?)?.toDouble(),
            ),
          )
          .toList();
  @override
  Future<void> acknowledge(String id, String senderId) async {
    final rows = await db.rawQuery(
      'SELECT bytes FROM packets WHERE id = ? UNION ALL SELECT bytes FROM messages WHERE id = ? LIMIT 1',
      [id, id],
    );
    if (rows.isEmpty) {
      return;
    }
    final p = Packet.decode(rows.first['bytes'] as Uint8List);
    if (p.broadcast || hex(p.recipient) != senderId) {
      return;
    }
    await db.transaction((t) async {
      await t.update(
        'messages',
        {'acked': 1},
        where: 'id = ? AND outgoing = 1',
        whereArgs: [id],
      );
      await t.update('packets', {'acked': 1}, where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<void> close() => db.close();
}
