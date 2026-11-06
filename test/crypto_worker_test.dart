import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ble_emergency_app/core/crypto_worker.dart';
import 'package:ble_emergency_app/core/identity.dart';
import 'package:ble_emergency_app/core/packet.dart';
import 'package:ble_emergency_app/messaging/store.dart';
import 'package:ble_emergency_app/routing/router.dart';
import 'package:ble_emergency_app/simulator/network.dart';
import 'package:ble_emergency_app/transport/fragments.dart';

void main() {
  late CryptoWorker worker;
  setUp(() async => worker = await CryptoWorker.spawn());
  tearDown(() => worker.close());

  Future<Packet> signed(Identity who, String text) => who.sign(
    Packet(
      kind: MessageKind.chat,
      maxHops: 6,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      id: randomBytes(16),
      signingKey: who.publicSigning,
      exchangeKey: who.publicExchange,
      recipient: Uint8List(8),
      payload: MessageBody(text).encode(),
      signature: Uint8List(64),
    ),
  );

  test('worker agrees with Identity.verify', () async {
    final a = await Identity.create(), b = await Identity.create();
    final good = await signed(a, 'thật');
    final tampered = good.copy(payload: MessageBody('giả').encode());
    final wrongKey = Packet.decode(
      Uint8List.fromList(good.encode()..setRange(30, 62, b.publicSigning)),
    );
    for (final p in [good, tampered, wrongKey]) {
      expect(await worker.verify(p), await Identity.verify(p));
    }
    expect(await worker.verify(good), isTrue);
    expect(await worker.verify(tampered), isFalse);
  });

  test('many checks in flight get their own answers', () async {
    final a = await Identity.create();
    final packets = [for (var i = 0; i < 40; i++) await signed(a, 'tin $i')];
    final mixed = [
      for (var i = 0; i < packets.length; i++)
        i.isEven
            ? packets[i]
            : packets[i].copy(payload: MessageBody('sửa $i').encode()),
    ];
    final answers = await Future.wait(mixed.map(worker.verify));
    expect(answers, [for (var i = 0; i < mixed.length; i++) i.isEven]);
  });

  test('a closed worker answers false instead of hanging', () async {
    final p = await signed(await Identity.create(), 'x');
    final inFlight = worker.verify(p);
    worker.close();
    expect(await inFlight, isFalse);
    expect(await worker.verify(p), isFalse);
  });

  test(
    'routers using the worker relay real packets and drop forged ones',
    () async {
      final network = SimNetwork(), list = <MeshRouter>[];
      for (var i = 0; i < 3; i++) {
        final r = MeshRouter(
          identity: await Identity.create(),
          transport: network.node('$i'),
          store: MemoryStore(),
          name: 'N$i',
          retryInterval: null,
          verifier: worker.verify,
        );
        await r.start();
        list.add(r);
      }
      addTearDown(() async {
        for (final r in list) {
          await r.dispose();
        }
      });
      network.connect('0', '1');
      network.connect('1', '2');
      await network.drain(list);
      final p = await list[0].publish(
        MessageKind.sos,
        MessageBody('qua 2 chặng'),
      );
      await network.drain(list);
      expect(await list[2].store.hasSeen(p.messageId), isTrue);

      final forged = p.copy(payload: MessageBody('giả').encode(), hops: 1);
      final raw = forged.encode()..setRange(14, 30, randomBytes(16));
      for (final frame in Fragmenter.split(raw, mtu: 185)) {
        await network.node('0').send('1', frame);
      }
      await network.drain(list);
      expect(list[1].stats.rejected, 1);
      expect(
        (await list[2].store.messages()).any((m) => m.text == 'giả'),
        isFalse,
      );
    },
  );
}
