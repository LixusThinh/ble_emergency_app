import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/contact.dart';
import '../core/packet.dart';
import 'schema.dart';
import 'store.dart';

class SqliteStore implements MessageStore {
  final Database db;

  /// Row counts kept in memory so a write only trims when a table is full.
  /// Null means unknown; the next write counts again.
  int? _packets, _messages;
  int _expiredAt = 0;

  /// Highest `messages.rev` written; see [changes].
  int _revision;
  SqliteStore._(this.db, this._revision);

  /// Opens the app database; [factory], [file] and [key] are for tests.
  static Future<SqliteStore> open({
    DatabaseFactory? factory,
    String? file,
    String? key,
  }) async {
    final db = await openMeshDatabase(
      factory: factory,
      file: file,
      key: key,
      singleInstance: false,
    );
    return SqliteStore._(
      db,
      await _int(db, 'SELECT COALESCE(MAX(rev), 0) FROM messages'),
    );
  }

  static Future<int> _int(DatabaseExecutor t, String sql) async =>
      ((await t.rawQuery(sql)).first.values.first as int?) ?? 0;

  static int _cutoff() =>
      DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;

  static Future<int> _count(DatabaseExecutor t, String table) =>
      _int(t, 'SELECT COUNT(*) FROM $table');

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
    try {
      await db.transaction((t) async {
        var count = _packets ?? await _count(t, 'packets');
        final now = DateTime.now().millisecondsSinceEpoch;
        // Expired packets are already left out of pending(); deleting them
        // once a minute is enough.
        if (now - _expiredAt > 60000) {
          _expiredAt = now;
          count -= await t.delete(
            'packets',
            where: 'created < ?',
            whereArgs: [_cutoff()],
          );
        }
        if (count >= maxPackets) {
          // Keep the most useful rows, in [keepOrder]: `share` is each
          // packet's rank among its sender's packets.
          await t.rawDelete(
            'DELETE FROM packets WHERE id IN (SELECT id FROM (SELECT id, acked, priority, created, ROW_NUMBER() OVER (PARTITION BY origin ORDER BY acked ASC, priority ASC, created DESC) AS share FROM packets) ORDER BY acked ASC, share ASC, priority ASC, created DESC LIMIT -1 OFFSET ${maxPackets - trimBatch})',
          );
          count = await _count(t, 'packets');
        }
        await t.insert('packets', {
          'id': p.messageId,
          'bytes': p.encode(),
          'created': p.timestamp,
          'priority': p.priority,
          'origin': hex(p.signingKey),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        // An ignored duplicate overcounts by one; the next trim recounts.
        _packets = count + 1;
      });
    } catch (_) {
      _packets = null;
      rethrow;
    }
  }

  @override
  Future<List<Packet>> pending() async {
    final rows = await db.query(
      'packets',
      columns: ['bytes'],
      where: 'acked = 0 AND created >= ?',
      whereArgs: [_cutoff()],
      orderBy: 'priority ASC, created ASC',
    );
    return rows.map((r) => Packet.decode(r['bytes'] as Uint8List)).toList();
  }

  @override
  Future<void> save(StoredMessage m) async {
    try {
      var count = _messages ?? await _count(db, 'messages');
      await db.insert('messages', {
        'id': m.packet.messageId,
        'bytes': m.packet.encode(),
        'sender': m.senderId,
        'text': m.text,
        'outgoing': m.outgoing ? 1 : 0,
        'lat': m.latitude,
        'lon': m.longitude,
        'accuracy': m.accuracy,
        'address': m.address,
        'looked_up_address': m.lookedUpAddress,
        'created': m.packet.timestamp,
        'rev': ++_revision,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      count++;
      if (count > maxMessages + trimBatch) {
        await db.rawDelete(
          'DELETE FROM messages WHERE id IN (SELECT id FROM messages ORDER BY created DESC LIMIT -1 OFFSET $maxMessages)',
        );
        await db.rawDelete(
          'DELETE FROM handoffs WHERE message_id NOT IN (SELECT id FROM messages)',
        );
        count = await _count(db, 'messages');
      }
      _messages = count;
    } catch (_) {
      _messages = null;
      rethrow;
    }
  }

  @override
  Future<void> recordHandoff(String id, String node) async {
    await db.transaction((t) async {
      await t.insert('handoffs', {
        'message_id': id,
        'node': node,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await t.update(
        'messages',
        {'rev': ++_revision},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  @override
  Future<void> saveLookedUpAddress(String id, String address) async {
    await db.update(
      'messages',
      {'looked_up_address': address, 'rev': ++_revision},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static const _select =
      'SELECT m.*, (SELECT COUNT(*) FROM handoffs h WHERE h.message_id = m.id) AS handoffs FROM messages m';

  static StoredMessage _message(Map<String, Object?> r) => StoredMessage(
    Packet.decode(r['bytes'] as Uint8List),
    r['sender'] as String,
    r['text'] as String,
    outgoing: r['outgoing'] == 1,
    acknowledged: r['acked'] == 1,
    handoffs: r['handoffs'] as int,
    latitude: (r['lat'] as num?)?.toDouble(),
    longitude: (r['lon'] as num?)?.toDouble(),
    accuracy: (r['accuracy'] as num?)?.toDouble(),
    address: r['address'] as String?,
    lookedUpAddress: r['looked_up_address'] as String?,
  );

  @override
  Future<List<StoredMessage>> messages() async =>
      (await db.rawQuery('$_select ORDER BY m.created DESC LIMIT $maxMessages'))
          .map(_message)
          .toList();

  @override
  Future<MessageChanges> changes(int after) async {
    // Read the revision first: anything written while the query runs gets a
    // higher one and comes back next time (at worst twice, merged by id).
    final upTo = _revision;
    final rows = await db.rawQuery(
      '$_select WHERE m.rev > ? ORDER BY m.created DESC LIMIT $maxMessages',
      [after],
    );
    return (messages: rows.map(_message).toList(), revision: upTo);
  }

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
        {'acked': 1, 'rev': ++_revision},
        where: 'id = ? AND outgoing = 1 AND acked = 0',
        whereArgs: [id],
      );
      await t.update('packets', {'acked': 1}, where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<List<Contact>> contacts() async =>
      (await db.query('contacts', orderBy: 'last_seen DESC'))
          .map(
            (r) => Contact(
              r['id'] as String,
              r['name'] as String,
              r['exchange_key'] as Uint8List,
            ),
          )
          .toList();

  @override
  Future<void> saveContact(Contact contact, int seen) async {
    await db.transaction((t) async {
      await t.insert('contacts', {
        'id': contact.id,
        'name': contact.name,
        'exchange_key': contact.exchangeKey,
        'last_seen': seen,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await t.rawDelete(
        'DELETE FROM contacts WHERE id IN (SELECT id FROM contacts ORDER BY last_seen DESC LIMIT -1 OFFSET $maxContacts)',
      );
    });
  }

  @override
  Future<void> close() => db.close();
}
