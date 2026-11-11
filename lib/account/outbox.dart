import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A log row or SOS report recorded on the phone, waiting to be uploaded.
class OutboxEvent {
  final int? id;
  final String userId;

  /// `log` goes to activity_logs, `sos` to sos_reports.
  final String kind;
  final Map<String, dynamic> payload;
  final int created;
  const OutboxEvent({
    this.id,
    required this.userId,
    required this.kind,
    required this.payload,
    required this.created,
  });
}

abstract interface class OutboxStore {
  Future<void> add(OutboxEvent e);

  /// Oldest first, for [userId] only.
  Future<List<OutboxEvent>> pending(String userId, {int limit = 50});
  Future<void> remove(Iterable<int> ids);
  Future<int> count(String userId);
}

/// At most this many events wait; past it the oldest logs go first, SOS
/// reports last.
const maxOutbox = 1000;

class MemoryOutboxStore implements OutboxStore {
  final List<OutboxEvent> events = [];
  int _next = 1;
  @override
  Future<void> add(OutboxEvent e) async {
    events.add(
      OutboxEvent(
        id: _next++,
        userId: e.userId,
        kind: e.kind,
        payload: e.payload,
        created: e.created,
      ),
    );
    while (events.length > maxOutbox) {
      final log = events.indexWhere((e) => e.kind == 'log');
      events.removeAt(log < 0 ? 0 : log);
    }
  }

  @override
  Future<List<OutboxEvent>> pending(String userId, {int limit = 50}) async =>
      events.where((e) => e.userId == userId).take(limit).toList();
  @override
  Future<void> remove(Iterable<int> ids) async {
    final drop = ids.toSet();
    events.removeWhere((e) => drop.contains(e.id));
  }

  @override
  Future<int> count(String userId) async =>
      events.where((e) => e.userId == userId).length;
}

/// The `outbox_events` table, on the settings connection.
class SqliteOutboxStore implements OutboxStore {
  final Database db;
  SqliteOutboxStore(this.db);
  @override
  Future<void> add(OutboxEvent e) async {
    await db.transaction((t) async {
      await t.insert('outbox_events', {
        'user_id': e.userId,
        'kind': e.kind,
        'payload': jsonEncode(e.payload),
        'created': e.created,
      });
      await t.rawDelete(
        "DELETE FROM outbox_events WHERE id IN (SELECT id FROM outbox_events ORDER BY kind = 'sos' DESC, id DESC LIMIT -1 OFFSET $maxOutbox)",
      );
    });
  }

  @override
  Future<List<OutboxEvent>> pending(String userId, {int limit = 50}) async => [
    for (final r in await db.query(
      'outbox_events',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id',
      limit: limit,
    ))
      OutboxEvent(
        id: r['id'] as int,
        userId: r['user_id'] as String,
        kind: r['kind'] as String,
        payload: Map<String, dynamic>.from(
          jsonDecode(r['payload'] as String) as Map,
        ),
        created: r['created'] as int,
      ),
  ];

  @override
  Future<void> remove(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) {
      return;
    }
    await db.delete(
      'outbox_events',
      where: 'id IN (${List.filled(list.length, '?').join(',')})',
      whereArgs: list,
    );
  }

  @override
  Future<int> count(String userId) async {
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM outbox_events WHERE user_id = ?',
      [userId],
    );
    return (r.first['n'] as int?) ?? 0;
  }
}
