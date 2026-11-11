import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/packet.dart';

const databaseName = 'emergency_mesh.db';

/// Bump this and add an entry to [_migrations] for every schema change.
/// Never edit a migration that has shipped: phones upgrade from any version.
const schemaVersion = 6;

typedef Migration = Future<void> Function(DatabaseExecutor db);

final Map<int, Migration> _migrations = {
  1: (db) async {
    // Schema shipped in 1.0.0; kept verbatim so fresh installs and upgrades
    // end in the same state.
    await db.execute(
      'CREATE TABLE packets (id TEXT PRIMARY KEY, bytes BLOB NOT NULL, created INTEGER NOT NULL, priority INTEGER NOT NULL, acked INTEGER NOT NULL DEFAULT 0)',
    );
    await db.execute(
      'CREATE TABLE messages (id TEXT PRIMARY KEY, bytes BLOB NOT NULL, sender TEXT NOT NULL, text TEXT NOT NULL, outgoing INTEGER NOT NULL, acked INTEGER NOT NULL DEFAULT 0, lat REAL, lon REAL, created INTEGER NOT NULL)',
    );
    await db.execute('CREATE INDEX packets_created ON packets(created)');
  },
  2: (db) async {
    // Contacts survive a restart, so names and private chats come back
    // before the other phone says hello again.
    await db.execute(
      'CREATE TABLE contacts (id TEXT PRIMARY KEY, name TEXT NOT NULL, exchange_key BLOB NOT NULL, last_seen INTEGER NOT NULL)',
    );
    await db.execute('CREATE INDEX contacts_seen ON contacts(last_seen)');
    await db.execute(
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    // The chat list reads messages newest first on every refresh.
    await db.execute('CREATE INDEX messages_created ON messages(created)');
    // pending(): WHERE acked = 0 ... ORDER BY priority, created.
    await db.execute(
      'CREATE INDEX packets_pending ON packets(acked, priority, created)',
    );
  },
  3: (db) async {
    // Which nearby phones took each of our own messages, so the UI can say
    // whether an SOS has left this phone at all.
    await db.execute(
      'CREATE TABLE handoffs (message_id TEXT NOT NULL, node TEXT NOT NULL, PRIMARY KEY (message_id, node)) WITHOUT ROWID',
    );
  },
  4: (db) async {
    // Every write to a message bumps its revision, so the UI reloads only
    // what changed since its last read instead of all 2000 messages.
    await db.execute(
      'ALTER TABLE messages ADD COLUMN rev INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('CREATE INDEX messages_rev ON messages(rev)');
  },
  5: (db) async {
    // Who signed each packet, so a full table drops from whoever holds the
    // most rather than from everyone alike; see [keepOrder].
    await db.execute(
      "ALTER TABLE packets ADD COLUMN origin TEXT NOT NULL DEFAULT ''",
    );
    final batch = db.batch();
    for (final r in await db.query('packets', columns: ['id', 'bytes'])) {
      String origin;
      try {
        origin = hex(Packet.decode(r['bytes'] as Uint8List).signingKey);
      } on Object {
        origin = '';
      }
      batch.update(
        'packets',
        {'origin': origin},
        where: 'id = ?',
        whereArgs: [r['id']],
      );
    }
    await batch.commit(noResult: true);
  },
  6: (db) async {
    // 2.0: SOS carry how accurate the position is and the street address the
    // sender looked it up as; a receiver that had to look it up itself keeps
    // its own answer apart, so the UI can say whose it is.
    await db.execute('ALTER TABLE messages ADD COLUMN accuracy REAL');
    await db.execute('ALTER TABLE messages ADD COLUMN address TEXT');
    await db.execute('ALTER TABLE messages ADD COLUMN looked_up_address TEXT');
  },
};

Future<void> _upgrade(DatabaseExecutor db, int from, int to) async {
  for (var v = from + 1; v <= to; v++) {
    final step = _migrations[v];
    if (step == null) {
      throw StateError('Thiếu migration lên phiên bản $v');
    }
    await step(db);
  }
}

/// The app database file and its key, set once at launch by
/// [useMeshDatabase]. Tests pass a file of their own instead.
String? _appFile, _appKey;

/// A key is 32 random bytes as 64 hex digits; it is pasted into a PRAGMA, so
/// nothing else is accepted.
final _hexKey = RegExp(r'^[0-9a-f]{64}$');

/// First 16 bytes of every unencrypted SQLite file.
const _plainHeader = 'SQLite format 3\x00';

/// Whether [file] is an unencrypted SQLite database.
Future<bool> isPlainDatabase(String file) async {
  final f = File(file);
  if (!await f.exists() || await f.length() < 16) {
    return false;
  }
  final raf = await f.open();
  try {
    return String.fromCharCodes(await raf.read(16)) == _plainHeader;
  } finally {
    await raf.close();
  }
}

Future<void> _moveAll(String from, String to) async {
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final f = File('$from$suffix');
    if (await f.exists()) {
      await f.rename('$to$suffix');
    }
  }
}

String _aside(String file) =>
    '$file.unreadable-${DateTime.now().millisecondsSinceEpoch}';

/// Makes [openMeshDatabase] use [file], encrypted with [key].
///
/// A database written before encryption (1.x) is encrypted in place first.
/// A copy of the plain file is kept until the encrypted one opens, so an
/// interrupted run starts over from that copy. A database [key] cannot open
/// (the key was lost with the Keystore, or [discard] says so) is moved aside,
/// not deleted, and a new one started: the app must open in an emergency.
/// Returns a notice for the user when that happened.
Future<String?> useMeshDatabase({
  required String file,
  required String key,
  bool discard = false,
  DatabaseFactory? factory,
}) async {
  if (!_hexKey.hasMatch(key)) {
    throw ArgumentError('Khóa database phải là 64 chữ số hex');
  }
  final f = factory ?? databaseFactoryFfi;
  final backup = File('$file.plain');
  String? notice;
  if (await backup.exists()) {
    // Encryption was interrupted: the copy is the last good database.
    await _moveAll(file, '$file.interrupted');
    await backup.rename(file);
  }
  if (discard && await File(file).exists()) {
    await _moveAll(file, _aside(file));
    notice = 'Mất khóa mã hóa nên đã tạo database mới; tin cũ không mở được.';
  }
  if (await isPlainDatabase(file)) {
    // DELETE mode folds the WAL into the main file, so the copy is complete
    // and rekey, which does not run in WAL mode, can.
    var db = await f.openDatabase(
      file,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.rawQuery('PRAGMA journal_mode = DELETE');
    await db.close();
    await File(file).copy(backup.path);
    db = await f.openDatabase(
      file,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.rawQuery("PRAGMA hexrekey = '$key'");
    await db.close();
  }
  if (await File(file).exists()) {
    try {
      final db = await f.openDatabase(
        file,
        options: OpenDatabaseOptions(
          singleInstance: false,
          onConfigure: (db) => db.rawQuery("PRAGMA hexkey = '$key'"),
        ),
      );
      try {
        await db.rawQuery('SELECT COUNT(*) FROM sqlite_master');
      } finally {
        await db.close();
      }
    } on DatabaseException catch (e) {
      if (!'$e'.contains('not a database')) {
        rethrow;
      }
      await _moveAll(file, _aside(file));
      notice =
          'Không mở được database bằng khóa đã lưu nên đã tạo database mới.';
    }
  }
  if (await backup.exists()) {
    await backup.delete();
  }
  _appFile = file;
  _appKey = key;
  return notice;
}

/// Opens a database and brings its schema to [version].
///
/// Without [file] it opens the app database set by [useMeshDatabase], with
/// its key. With [file] (tests) it opens that file, encrypted only if [key]
/// is given. Each call with [singleInstance] false gets its own connection,
/// so the settings connection outlives the message store being closed on
/// stop.
Future<Database> openMeshDatabase({
  DatabaseFactory? factory,
  String? file,
  String? key,
  int version = schemaVersion,
  bool singleInstance = true,
}) async {
  final location = file ?? _appFile;
  final secret = file == null ? _appKey : key;
  if (location == null) {
    throw StateError('Chưa gọi useMeshDatabase');
  }
  if (secret != null && !_hexKey.hasMatch(secret)) {
    throw ArgumentError('Khóa database phải là 64 chữ số hex');
  }
  return (factory ?? databaseFactoryFfi).openDatabase(
    location,
    options: OpenDatabaseOptions(
      version: version,
      singleInstance: singleInstance,
      onConfigure: (db) async {
        if (secret != null) {
          // Must come first: every page, the WAL's included, uses this key.
          await db.rawQuery("PRAGMA hexkey = '$secret'");
        }
        // WAL lets the UI read while the router writes, and allows the
        // settings and message connections to coexist.
        await db.rawQuery('PRAGMA journal_mode = WAL');
        // Both pragmas return a row, which Android only allows via rawQuery.
        await db.rawQuery('PRAGMA busy_timeout = 3000');
      },
      onCreate: (db, v) => _upgrade(db, 0, v),
      onUpgrade: (db, from, to) => _upgrade(db, from, to),
    ),
  );
}
