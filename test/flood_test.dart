import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ble_emergency_app/core/identity.dart';
import 'package:ble_emergency_app/core/packet.dart';
import 'package:ble_emergency_app/messaging/schema.dart';
import 'package:ble_emergency_app/messaging/sqlite_store.dart';
import 'package:ble_emergency_app/messaging/store.dart';
import 'package:ble_emergency_app/routing/router.dart';
import 'package:ble_emergency_app/simulator/network.dart';
import 'package:ble_emergency_app/transport/fragments.dart';

/// Flood protection: per-sender budgets, muting links that send forgeries,
/// and a per-sender share of the packet store.
void main() {
  sqfliteFfiInit();
  var now = 0;
  int clock() => now;
  setUp(() => now = 1000000);

  group('FloodGuard', () {
    test('a sender gets its burst, then its rate', () {
      final g = FloodGuard(burst: 3, perMinute: 6, clock: clock);
      expect(g.allows('a', MessageKind.chat), isTrue);
      expect(
        [for (var i = 0; i < 4; i++) g.admit('a', MessageKind.chat)],
        [true, true, true, false],
      );
      expect(g.allows('a', MessageKind.chat), isFalse);
      // Others are not affected.
      expect(g.admit('b', MessageKind.chat), isTrue);
      now += 10000; // 6 per minute: one more after 10 s
      expect(g.admit('a', MessageKind.chat), isTrue);
      expect(g.admit('a', MessageKind.chat), isFalse);
      now += 3600000; // refills to the burst, not beyond
      expect(
        [for (var i = 0; i < 4; i++) g.admit('a', MessageKind.chat)],
        [true, true, true, false],
      );
    });

    test('allows() spends nothing', () {
      final g = FloodGuard(burst: 1, clock: clock);
      for (var i = 0; i < 5; i++) {
        expect(g.allows('a', MessageKind.chat), isTrue);
      }
      expect(g.admit('a', MessageKind.chat), isTrue);
      expect(g.allows('a', MessageKind.chat), isFalse);
    });

    test('SOS has a smaller budget of its own', () {
      final g = FloodGuard(burst: 5, sosBurst: 2, clock: clock);
      expect(
        [for (var i = 0; i < 3; i++) g.admit('a', MessageKind.sos)],
        [true, true, false],
      );
      // Spending SOS left chat untouched.
      expect(
        [for (var i = 0; i < 6; i++) g.admit('a', MessageKind.chat)],
        [true, true, true, true, true, false],
      );
    });

    test('only the most recently seen senders are tracked', () {
      final g = FloodGuard(burst: 1, maxTracked: 2, clock: clock);
      g.admit('a', MessageKind.chat);
      g.admit('b', MessageKind.chat);
      g.admit('c', MessageKind.chat);
      // 'a' was forgotten and starts with a full budget; 'c' was not.
      expect(g.allows('a', MessageKind.chat), isTrue);
      expect(g.allows('c', MessageKind.chat), isFalse);
    });

    test('a link sending forgeries is muted, then let back', () {
      final g = FloodGuard(
        badLimit: 3,
        badWindow: const Duration(minutes: 1),
        muteFor: const Duration(minutes: 5),
        clock: clock,
      );
      g.bad('x');
      g.bad('x');
      expect(g.muted('x'), isFalse);
      g.bad('x');
      expect(g.muted('x'), isTrue);
      expect(g.muted('y'), isFalse);
      now += const Duration(minutes: 5).inMilliseconds;
      expect(g.muted('x'), isFalse);
    });

    test('bad packets spread over time do not mute', () {
      final g = FloodGuard(badLimit: 3, clock: clock);
      for (var i = 0; i < 10; i++) {
        g.bad('x');
        now += 31000;
      }
      expect(g.muted('x'), isFalse);
    });
  });

  group('router', () {
    Future<List<MeshRouter>> routers(
      SimNetwork net,
      List<String> ids, {
      FloodGuard Function()? guard,
    }) async {
      final list = <MeshRouter>[];
      for (final id in ids) {
        final r = MeshRouter(
          identity: await Identity.create(),
          transport: net.node(id),
          store: MemoryStore(),
          name: id,
          retryInterval: null,
          guard: guard?.call(),
        );
        await r.start();
        list.add(r);
      }
      addTearDown(() async {
        for (final r in list) {
          await r.dispose();
        }
      });
      return list;
    }

    Future<int> stored(MeshRouter r, MeshRouter from) async =>
        (await r.store.messages())
            .where((m) => m.senderId == from.identity.id)
            .length;

    test('a flooding phone gets its budget through, others still do', () async {
      final net = SimNetwork();
      final [flooder, relay, honest, far] = await routers(net, [
        'f',
        'r',
        'h',
        'z',
      ], guard: () => FloodGuard(burst: 10, sosBurst: 3, clock: clock));
      net.connect('f', 'r');
      net.connect('h', 'r');
      net.connect('r', 'z');
      await net.drain([flooder, relay, honest, far]);
      for (var i = 0; i < 30; i++) {
        await flooder.publish(MessageKind.chat, MessageBody('rác $i'));
      }
      for (var i = 0; i < 8; i++) {
        await flooder.publish(MessageKind.sos, MessageBody('SOS giả $i'));
      }
      await net.drain([flooder, relay, honest, far]);
      // The relay kept and passed on only the budget: 3 SOS, and 9 chat
      // because the flooder's hello took one of its 10.
      expect(await stored(relay, flooder), 12);
      expect(await stored(far, flooder), 12);
      expect(relay.stats.limited, 26);
      final sos = await honest.publish(
        MessageKind.sos,
        MessageBody('SOS thật'),
      );
      await net.drain([flooder, relay, honest, far]);
      expect(
        (await far.store.messages()).any(
          (m) => m.packet.messageId == sos.messageId,
        ),
        isTrue,
      );
      // The budget refills: a minute later the flooder gets more through.
      now += 60000;
      await flooder.publish(MessageKind.chat, MessageBody('sau một phút'));
      await net.drain([flooder, relay, honest, far]);
      expect(await stored(relay, flooder), 13);
    });

    test('forged packets do not spend the real sender\'s budget, and the '
        'link sending them is muted', () async {
      final net = SimNetwork();
      final [victim, relay] = await routers(net, [
        'v',
        'r',
      ], guard: () => FloodGuard(burst: 6, badLimit: 10, clock: clock));
      final attacker = net.node('x');
      net.connect('v', 'r');
      net.connect('x', 'r');
      await net.drain([victim, relay]);
      // Packets claiming to come from the victim, with a broken signature.
      final real = await victim.publish(MessageKind.chat, MessageBody('thật'));
      await net.drain([victim, relay]);
      for (var i = 0; i < 40; i++) {
        final forged = Packet(
          kind: MessageKind.chat,
          maxHops: 6,
          hops: 1,
          timestamp: real.timestamp,
          id: randomBytes(16),
          signingKey: real.signingKey,
          exchangeKey: real.exchangeKey,
          recipient: real.recipient,
          payload: MessageBody('giả $i').encode(),
          signature: real.signature,
        );
        for (final f in Fragmenter.split(forged.encode(), mtu: 185)) {
          await attacker.send('r', f);
        }
      }
      await net.drain([victim, relay]);
      // 10 forgeries were checked and rejected, then the link was muted.
      expect(relay.stats.rejected, 10);
      expect(relay.stats.ignoredFrames, greaterThan(0));
      // The victim's budget was untouched: of its 6, the hello and the first
      // message took two, and 4 more still get through.
      for (var i = 0; i < 4; i++) {
        await victim.publish(MessageKind.chat, MessageBody('thật $i'));
      }
      await net.drain([victim, relay]);
      expect(await stored(relay, victim), 5);
      expect(relay.stats.limited, 0);
    });

    test('this phone\'s own messages are never limited', () async {
      final net = SimNetwork();
      final [a] = await routers(net, [
        'a',
      ], guard: () => FloodGuard(burst: 1, clock: clock));
      for (var i = 0; i < 5; i++) {
        await a.publish(MessageKind.sos, MessageBody('của mình $i'));
      }
      expect(await a.store.pending(), hasLength(5));
    });
  });

  group('store share', () {
    Packet packet(MessageKind kind, int timestamp, int sender) => Packet(
      kind: kind,
      maxHops: 6,
      timestamp: timestamp,
      id: randomBytes(16),
      signingKey: Uint8List(32)..[0] = sender,
      exchangeKey: Uint8List(32),
      recipient: Uint8List(8),
      payload: Uint8List(0),
      signature: Uint8List(64),
    );

    test('keepOrder takes every sender\'s best before anyone\'s second', () {
      final t = DateTime.now().millisecondsSinceEpoch;
      final a1 = packet(MessageKind.sos, t, 1),
          a2 = packet(MessageKind.sos, t - 1, 1),
          a3 = packet(MessageKind.chat, t, 1),
          b1 = packet(MessageKind.chat, t - 9, 2),
          c1 = packet(MessageKind.sos, t - 5, 3);
      final settled = packet(MessageKind.sos, t, 4);
      final order = keepOrder([
        a3,
        a2,
        settled,
        b1,
        a1,
        c1,
      ], (p) => p == settled);
      expect(order, [a1, c1, b1, a2, a3, settled]);
    });

    test(
      'memory: one sender flooding SOS does not push out another\'s',
      () async {
        final store = MemoryStore();
        final t = DateTime.now().millisecondsSinceEpoch;
        final mine = packet(MessageKind.sos, t - 3600000, 1);
        await store.retain(mine);
        for (var i = 0; i < maxPackets + 50; i++) {
          await store.retain(packet(MessageKind.sos, t - 1000 + i, 2));
        }
        final pending = await store.pending();
        expect(pending, hasLength(maxPackets));
        expect(pending.map((p) => p.messageId), contains(mine.messageId));
      },
    );

    test(
      'sqlite: a full table trims from the sender holding the most',
      () async {
        final dir = await Directory.systemTemp.createTemp('mesh_flood_');
        addTearDown(() async {
          try {
            await dir.delete(recursive: true);
          } on FileSystemException {
            // Windows may hold the WAL file briefly.
          }
        });
        final store = await SqliteStore.open(
          factory: databaseFactoryFfi,
          file: path.join(dir.path, databaseName),
        );
        addTearDown(store.close);
        final t = DateTime.now().millisecondsSinceEpoch;
        final mine = packet(MessageKind.sos, t - 3600000, 1);
        // Written directly, so the store counts the full table on the next
        // retain().
        await store.db.transaction((tx) async {
          for (var i = 0; i < maxPackets; i++) {
            final p = i == 0
                ? mine
                : packet(MessageKind.sos, t - 100000 + i, 2);
            await tx.insert('packets', {
              'id': p.messageId,
              'bytes': p.encode(),
              'created': p.timestamp,
              'priority': p.priority,
              'origin': hex(p.signingKey),
            });
          }
        });
        final last = packet(MessageKind.sos, t, 2);
        await store.retain(last);
        final rows = await store.db.query('packets', columns: ['id', 'origin']);
        expect(rows, hasLength(maxPackets - trimBatch + 1));
        final ids = rows.map((r) => r['id']).toSet();
        // Before: newest first, so the older SOS of the quiet sender went.
        expect(ids, contains(mine.messageId));
        expect(ids, contains(last.messageId));
      },
    );

    test('upgrading to v5 fills in each packet\'s sender', () async {
      final dir = await Directory.systemTemp.createTemp('mesh_v5_');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // Windows may hold the WAL file briefly.
        }
      });
      final file = path.join(dir.path, databaseName);
      final p = packet(MessageKind.chat, 1, 7);
      final v4 = await openMeshDatabase(
        factory: databaseFactoryFfi,
        file: file,
        version: 4,
      );
      await v4.insert('packets', {
        'id': p.messageId,
        'bytes': p.encode(),
        'created': p.timestamp,
        'priority': p.priority,
      });
      await v4.insert('packets', {
        'id': 'hong',
        'bytes': Uint8List(3),
        'created': 2,
        'priority': 4,
      });
      await v4.close();
      final store = await SqliteStore.open(
        factory: databaseFactoryFfi,
        file: file,
      );
      addTearDown(store.close);
      final origins = {
        for (final r in await store.db.query('packets')) r['id']: r['origin'],
      };
      expect(origins, {p.messageId: hex(p.signingKey), 'hong': ''});
    });
  });
}
