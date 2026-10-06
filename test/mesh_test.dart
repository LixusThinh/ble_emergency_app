import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ble_emergency_app/core/identity.dart';
import 'package:ble_emergency_app/core/packet.dart';
import 'package:ble_emergency_app/messaging/store.dart';
import 'package:ble_emergency_app/routing/router.dart';
import 'package:ble_emergency_app/simulator/network.dart';
import 'package:ble_emergency_app/transport/fragments.dart';

Future<({SimNetwork network, List<MeshRouter> routers})> fixture({
  int count = 3,
}) async {
  final network = SimNetwork(), routers = <MeshRouter>[];
  for (var i = 0; i < count; i++) {
    final router = MeshRouter(
      identity: await Identity.create(),
      transport: network.node('$i'),
      store: MemoryStore(),
      name: 'Node $i',
    );
    await router.start();
    routers.add(router);
  }
  addTearDown(() async {
    for (final r in routers) {
      await r.dispose();
    }
  });
  return (network: network, routers: routers);
}

void main() {
  test('binary signed envelope survives relay; tampering fails', () async {
    final f = await fixture();
    final p = await f.routers.first.publish(
      MessageKind.sos,
      MessageBody('Cần giúp', latitude: 10.2, longitude: 106.4),
    );
    final decoded = Packet.decode(p.copy(hops: 2).encode());
    expect(await Identity.verify(decoded), isTrue);
    expect(MessageBody.decode(decoded.payload).latitude, 10.2);
    final tampered = decoded.copy(payload: MessageBody('Giả SOS').encode());
    expect(await Identity.verify(tampered), isFalse);
    final broken = p.encode();
    broken[3] = 255;
    expect(() => Packet.decode(broken), throwsFormatException);
  });
  test('identity seeds restore same node and encryption keys', () async {
    final original = await Identity.create();
    final restored = await Identity.create(saved: await original.export());
    expect(restored.id, original.id);
    expect(restored.publicExchange, original.publicExchange);
  });
  test(
    'MTU 23 fragmentation reassembles reordered and repeated fragments',
    () async {
      final f = await fixture();
      final packet = await f.routers.first.publish(
        MessageKind.chat,
        MessageBody('Tin nhắn dài ' * 100),
      );
      final raw = packet.encode(),
          parts = Fragmenter.split(packet.encode(), mtu: 23),
          assembler = Reassembler();
      expect(parts.every((b) => b.length <= 20), isTrue);
      expect(assembler.add('A', parts.first), isNull);
      expect(assembler.add('A', parts.first), isNull);
      Uint8List? assembled;
      for (final part in parts.skip(1).toList().reversed) {
        assembled = assembler.add('A', part) ?? assembled;
      }
      expect(assembled, raw);
    },
  );
  test('fragment bounds and inconsistent lengths are rejected', () async {
    final f = await fixture();
    final p = await f.routers.first.publish(
      MessageKind.chat,
      MessageBody('hello'),
    );
    final parts = Fragmenter.split(p.encode(), mtu: 23),
        assembler = Reassembler();
    assembler.add('A', parts.first);
    final forged = Uint8List.fromList(parts[1]);
    ByteData.sublistView(forged).setUint16(10, p.encode().length + 1);
    expect(() => assembler.add('A', forged), throwsFormatException);
    expect(() => assembler.add('A', Uint8List(13)), throwsFormatException);
  });
  test('A-B-C multi-hop delivery and TTL one stops at B', () async {
    final f = await fixture();
    f.network.connect('0', '1', mtu: 23);
    f.network.connect('1', '2');
    await f.network.drain(f.routers);
    final two = await f.routers[0].publish(
      MessageKind.sos,
      MessageBody('SOS'),
      ttl: 2,
    );
    await f.network.drain(f.routers);
    final c = (await f.routers[2].store.messages()).singleWhere(
      (m) => m.packet.messageId == two.messageId,
    );
    expect(c.packet.hops, 2);
    final one = await f.routers[0].publish(
      MessageKind.chat,
      MessageBody('near'),
      ttl: 1,
    );
    await f.network.drain(f.routers);
    expect(
      (await f.routers[1].store.messages()).any(
        (m) => m.packet.messageId == one.messageId,
      ),
      isTrue,
    );
    expect(
      (await f.routers[2].store.messages()).any(
        (m) => m.packet.messageId == one.messageId,
      ),
      isFalse,
    );
  });
  test('triangle dedup terminates flooding and delivers one copy', () async {
    final f = await fixture();
    f.network.connect('0', '1');
    f.network.connect('1', '2');
    f.network.connect('2', '0');
    await f.network.drain(f.routers);
    final p = await f.routers[0].publish(
      MessageKind.chat,
      MessageBody('broadcast'),
    );
    await f.network.drain(f.routers, budget: 1000);
    for (final r in f.routers) {
      expect(
        (await r.store.messages())
            .where((m) => m.packet.messageId == p.messageId)
            .length,
        1,
      );
    }
    expect(
      f.routers.fold<int>(0, (n, r) => n + r.stats.duplicate),
      greaterThan(0),
    );
  });
  test('store-and-forward bridges disjoint encounters', () async {
    final f = await fixture();
    final p = await f.routers[0].publish(
      MessageKind.sos,
      MessageBody('offline SOS'),
    );
    f.network.connect('0', '1');
    await f.network.drain(f.routers);
    f.network.disconnect('0', '1');
    await f.network.drain(f.routers);
    f.network.connect('1', '2');
    await f.network.drain(f.routers);
    expect(
      (await f.routers[2].store.messages()).any(
        (m) => m.packet.messageId == p.messageId,
      ),
      isTrue,
    );
  });
  test(
    'private ciphertext relays via B; only C decrypts; ACK returns to A',
    () async {
      final f = await fixture();
      f.network.connect('0', '1');
      f.network.connect('1', '2');
      await f.network.drain(f.routers);
      final target = f.routers[2].identity;
      final contact = Contact(target.id, 'C', target.publicExchange);
      final p = await f.routers[0].publish(
        MessageKind.privateChat,
        MessageBody('bí mật'),
        recipient: contact,
      );
      await f.network.drain(f.routers);
      expect(
        (await f.routers[1].store.messages()).any(
          (m) => m.packet.messageId == p.messageId,
        ),
        isFalse,
      );
      expect(
        (await f.routers[2].store.messages())
            .singleWhere((m) => m.packet.messageId == p.messageId)
            .text,
        'bí mật',
      );
      expect(
        (await f.routers[0].store.messages())
            .singleWhere((m) => m.packet.messageId == p.messageId)
            .acknowledged,
        isTrue,
      );
      await expectLater(f.routers[1].identity.decrypt(p), throwsA(anything));
    },
  );
  test('ACK cannot acknowledge a different recipient or broadcast', () async {
    final f = await fixture();
    final target = f.routers[2].identity;
    final p = await f.routers[0].publish(
      MessageKind.privateChat,
      MessageBody('secret'),
      recipient: Contact(target.id, 'C', target.publicExchange),
    );
    await f.routers[0].store.acknowledge(p.messageId, f.routers[1].identity.id);
    expect((await f.routers[0].store.messages()).single.acknowledged, isFalse);
    expect(
      (await f.routers[0].store.pending()).any(
        (q) => q.messageId == p.messageId,
      ),
      isTrue,
    );
  });
  test('relay stops forwarding a private message once it is ACKed', () async {
    final f = await fixture(count: 4);
    f.network.connect('0', '1');
    f.network.connect('1', '2');
    await f.network.drain(f.routers);
    final target = f.routers[2].identity;
    final p = await f.routers[0].publish(
      MessageKind.privateChat,
      MessageBody('bí mật'),
      recipient: Contact(target.id, 'C', target.publicExchange),
    );
    await f.network.drain(f.routers);
    expect(
      (await f.routers[1].store.pending()).any(
        (q) => q.messageId == p.messageId,
      ),
      isFalse,
    );
    f.network.connect('1', '3');
    await f.network.drain(f.routers);
    expect(await f.routers[3].store.hasSeen(p.messageId), isFalse);
  });
  test('reconnects do not queue or resend old hellos', () async {
    final f = await fixture(count: 2);
    final a = f.routers[0];
    Future<int> connectFrames() async {
      final before = a.stats.sentFrames;
      f.network.connect('0', '1', mtu: 23);
      await f.network.drain(f.routers);
      return a.stats.sentFrames - before;
    }

    final first = await connectFrames();
    for (var i = 0; i < 5; i++) {
      f.network.disconnect('0', '1');
      await f.network.drain(f.routers);
      await connectFrames();
    }
    f.network.disconnect('0', '1');
    await f.network.drain(f.routers);
    expect(await connectFrames(), first);
    expect(
      (await a.store.pending()).any(
        (p) =>
            p.kind == MessageKind.hello &&
            hex(p.signingKey) == hex(a.identity.publicSigning),
      ),
      isFalse,
    );
  });
  test('MTU re-announcement does not resync but updates MTU', () async {
    final f = await fixture(count: 2);
    final a = f.routers[0];
    f.network.connect('0', '1', mtu: 23);
    await f.network.drain(f.routers);
    await a.publish(MessageKind.chat, MessageBody('trước'));
    await f.network.drain(f.routers);
    final before = a.stats.sentFrames;
    f.network.renegotiate('0', '1', mtu: 185);
    await f.network.drain(f.routers);
    expect(a.stats.sentFrames, before);
    final p = await a.publish(MessageKind.chat, MessageBody('sau'));
    await f.network.drain(f.routers);
    expect(
      a.stats.sentFrames - before,
      Fragmenter.split(p.copy(hops: 1).encode(), mtu: 185).length,
    );
    expect(await f.routers[1].store.hasSeen(p.messageId), isTrue);
  });
  test('forged packet is not stored or relayed', () async {
    final f = await fixture();
    f.network.connect('0', '1');
    f.network.connect('1', '2');
    await f.network.drain(f.routers);
    final p = await f.routers[0].publish(
      MessageKind.chat,
      MessageBody('original'),
      ttl: 1,
    );
    await f.network.drain(f.routers);
    final forged = p.copy(payload: MessageBody('forged').encode(), hops: 1);
    final raw = forged.encode();
    raw.setRange(14, 30, randomBytes(16));
    for (final frame in Fragmenter.split(raw, mtu: 185)) {
      await f.network.node('0').send('1', frame);
    }
    await f.network.drain(f.routers);
    expect(f.routers[1].stats.rejected, greaterThan(0));
    expect(
      (await f.routers[2].store.messages()).any((m) => m.text == 'forged'),
      isFalse,
    );
  });
  test('pending sync prioritizes SOS over older chat', () async {
    final f = await fixture();
    await f.routers[0].publish(MessageKind.chat, MessageBody('chat'));
    await f.routers[0].publish(MessageKind.sos, MessageBody('SOS'));
    expect((await f.routers[0].store.pending()).first.kind, MessageKind.sos);
  });
}
