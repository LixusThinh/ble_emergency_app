import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

const databaseName = 'emergency_mesh.db';

/// Bump this and add an entry to [_migrations] for every schema change.
/// Never edit a migration that has shipped: phones upgrade from any version.
const schemaVersion = 4;

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

/// Opens the app database and brings its schema to [version].
///
/// [factory] and [file] let tests use an FFI database on the desktop.
/// Each call with [singleInstance] false gets its own connection, so the
/// settings connection outlives the message store being closed on stop.
Future<Database> openMeshDatabase({
  DatabaseFactory? factory,
  String? file,
  int version = schemaVersion,
  bool singleInstance = true,
}) async {
  final f = factory ?? databaseFactory;
  final location = file ?? path.join(await f.getDatabasesPath(), databaseName);
  return f.openDatabase(
    location,
    options: OpenDatabaseOptions(
      version: version,
      singleInstance: singleInstance,
      onConfigure: (db) async {
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
