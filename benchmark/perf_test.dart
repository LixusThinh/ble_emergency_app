// Performance probes for the hot paths. Not part of `flutter test`; run with
//   flutter test benchmark/perf_test.dart
// Numbers are desktop JIT timings: use them to compare versions, not as
// phone latencies.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ble_emergency_app/app/controller.dart';
import 'package:ble_emergency_app/core/crypto_worker.dart';
import 'package:ble_emergency_app/core/identity.dart';
import 'package:ble_emergency_app/core/packet.dart';
import 'package:ble_emergency_app/messaging/sqlite_store.dart';
import 'package:ble_emergency_app/messaging/store.dart';
import 'package:ble_emergency_app/routing/router.dart';
import 'package:ble_emergency_app/simulator/network.dart';
import 'package:ble_emergency_app/transport/fragments.dart';

final _results = <String>[];
void report(String name, num value, String unit) {
  final line =
      '${name.padRight(46)} ${value.toStringAsFixed(3).padLeft(10)} $unit';
  _results.add(line);
  // ignore: avoid_print
  print(line);
}

Future<double> timeMs(Future<void> Function() body, {int runs = 1}) async {
  final w = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    await body();
  }
  return w.elapsedMicroseconds / 1000 / runs;
}

Packet fake(MessageKind kind, int timestamp, {int payload = 120}) => Packet(
  kind: kind,
  maxHops: 6,
  timestamp: timestamp,
  id: randomBytes(16),
  signingKey: randomBytes(32),
  exchangeKey: randomBytes(32),
  recipient: Uint8List(8),
  payload: Uint8List(payload),
  signature: randomBytes(64),
);

void main() {
  sqfliteFfiInit();
  tearDownAll(() {
    // ignore: avoid_print
    print('\n=== summary ===\n${_results.join('\n')}');
  });

  test('cpu: hex, messageId, reassembly', () async {
    final id = randomBytes(16);
    report(
      'hex(16 bytes)',
      await timeMs(() async {
            for (var i = 0; i < 100000; i++) {
              hex(id);
            }
          }) /
          100,
      'µs/call',
    );
    final p = fake(MessageKind.chat, DateTime.now().millisecondsSinceEpoch);
    report(
      'Packet.messageId',
      await timeMs(() async {
            for (var i = 0; i < 100000; i++) {
              p.messageId;
            }
          }) /
          100,
      'µs/call',
    );
    final big = fake(
      MessageKind.chat,
      DateTime.now().millisecondsSinceEpoch,
      payload: Packet.maxPayload,
    ).encode();
    final frames = Fragmenter.split(big, mtu: 23);
    report(
      'reassemble 4 KB packet at MTU 23 (${frames.length} frames)',
      await timeMs(() async {
        final r = Reassembler();
        for (final f in frames) {
          r.add('peer', f);
        }
      }, runs: 20),
      'ms',
    );
  });

  test('cpu: Ed25519 sign and verify', () async {
    final id = await Identity.create();
    final p = fake(MessageKind.chat, DateTime.now().millisecondsSinceEpoch);
    late Packet signed;
    report(
      'sign',
      await timeMs(() async {
        signed = await id.sign(p);
      }, runs: 50),
      'ms',
    );
    report(
      'verify',
      await timeMs(() async {
        await Identity.verify(signed);
      }, runs: 50),
      'ms',
    );
  });

  test('ui isolate: free time while checking 200 signatures', () async {
    final id = await Identity.create();
    final packets = [
      for (var i = 0; i < 200; i++)
        await id.sign(
          fake(MessageKind.chat, DateTime.now().millisecondsSinceEpoch),
        ),
    ];
    // A 1 ms timer only fires when this isolate is free, like a frame would.
    Future<(double, double)> measure(
      Future<bool> Function(Packet) check,
    ) async {
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => ticks++,
      );
      final w = Stopwatch()..start();
      for (final p in packets) {
        expect(await check(p), isFalse); // fake() keys never match
      }
      final ms = w.elapsedMicroseconds / 1000;
      timer.cancel();
      return (ms, 100 * ticks / ms);
    }

    final (inlineMs, inlineFree) = await measure(Identity.verify);
    final worker = await CryptoWorker.spawn();
    final (workerMs, workerFree) = await measure(worker.verify);
    worker.close();
    report('verify 200 on the UI isolate: total', inlineMs, 'ms');
    report(
      'verify 200 on the UI isolate: UI free',
      inlineFree,
      '% of 1 ms ticks',
    );
    report('verify 200 on the worker: total', workerMs, 'ms');
    report('verify 200 on the worker: UI free', workerFree, '% of 1 ms ticks');
  });

  test('sqlite: retain, save, messages, pending', () async {
    final dir = await Directory.systemTemp.createTemp('perf_');
    final store = await SqliteStore.open(
      factory: databaseFactoryFfi,
      file: path.join(dir.path, 'perf.db'),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.db.transaction((t) async {
      for (var i = 0; i < maxPackets; i++) {
        final p = fake(MessageKind.chat, now - 100000 + i);
        await t.insert('packets', {
          'id': p.messageId,
          'bytes': p.encode(),
          'created': p.timestamp,
          'priority': p.priority,
        });
      }
      for (var i = 0; i < 2000; i++) {
        final p = fake(MessageKind.chat, now - 100000 + i);
        await t.insert('messages', {
          'id': p.messageId,
          'bytes': p.encode(),
          'sender': 'abcdef0123456789',
          'text': 'Tin nhắn thử số $i',
          'outgoing': 0,
          'created': p.timestamp,
        });
      }
    });
    report(
      'retain() into a full packet table',
      await timeMs(() async {
        await store.retain(fake(MessageKind.chat, now));
      }, runs: 200),
      'ms',
    );
    report(
      'save() into a full message table',
      await timeMs(() async {
        final p = fake(MessageKind.chat, now);
        await store.save(StoredMessage(p, 'abc', 'mới'));
      }, runs: 200),
      'ms',
    );
    report(
      'messages() with 2000 rows',
      await timeMs(() async {
        await store.messages();
      }, runs: 20),
      'ms',
    );
    report(
      'pending() with 5000 rows',
      await timeMs(() async {
        await store.pending();
      }, runs: 10),
      'ms',
    );
    await store.close();
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold the WAL file.
    }
  });

  test('controller: store reloads during a burst of 200 messages', () async {
    final c = AppController();
    await c.start(simulated: true);
    final before = c.refreshes, loadedBefore = c.loaded;
    final r = c.router!;
    final w = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      await r.publish(MessageKind.chat, MessageBody('dồn dập $i'));
    }
    await c.settled;
    report('store reloads for 200 updates', c.refreshes - before, 'reloads');
    report(
      'messages read from the store for 200 updates',
      c.loaded - loadedBefore,
      'rows',
    );
    report('burst handled in', w.elapsedMicroseconds / 1000, 'ms');
    expect(c.messages.length, greaterThanOrEqualTo(200));
    await c.stop();
  });

  test('router: 4 phones, two links each pair, 300 messages', () async {
    final net = SimNetwork(), rs = <MeshRouter>[];
    for (var i = 0; i < 4; i++) {
      final r = MeshRouter(
        identity: await Identity.create(),
        transport: net.node('$i'),
        store: MemoryStore(),
        name: 'N$i',
        retryInterval: null,
      );
      await r.start();
      rs.add(r);
    }
    for (var i = 0; i < 3; i++) {
      net.connectDual('$i', '${i + 1}');
    }
    await net.drain(rs);
    final w = Stopwatch()..start();
    for (var i = 0; i < 300; i++) {
      await rs[0].publish(MessageKind.chat, MessageBody('tin $i'));
    }
    await net.drain(rs);
    report(
      '300 messages across 3 hops (CPU)',
      w.elapsedMicroseconds / 1000,
      'ms',
    );
    expect(await rs[3].store.messages(), hasLength(300));
    for (final r in rs) {
      await r.dispose();
    }
  });
}
