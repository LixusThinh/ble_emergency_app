import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ble_emergency_app/core/identity.dart';
import 'package:ble_emergency_app/core/packet.dart';
import 'package:ble_emergency_app/messaging/store.dart';
import 'package:ble_emergency_app/routing/router.dart';
import 'package:ble_emergency_app/simulator/network.dart';
import 'package:ble_emergency_app/transport/fragments.dart';
import 'package:ble_emergency_app/transport/transport.dart';

/// Router behaviour added in the backend upgrade: one outbox per phone,
/// dual-link dedup, retries, eviction order, handoff counts, error reporting.
void main() {
  Future<List<MeshRouter>> routers(
    SimNetwork network,
    int count, {
    Duration? retryInterval,
  }) async {
    final list = <MeshRouter>[];
    for (var i = 0; i < count; i++) {
      final r = MeshRouter(
        identity: await Identity.create(),
        transport: network.node('$i'),
        store: MemoryStore(),
        name: 'Node $i',
        retryInterval: retryInterval,
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

  int framesOf(Packet p, {int mtu = 185}) =>
      Fragmenter.split(p.copy(hops: 1).encode(), mtu: mtu).length;

  Future<bool> has(MeshRouter r, Packet p) async =>
      (await r.store.messages()).any((m) => m.packet.messageId == p.messageId);

  test('two links to one phone carry each packet once', () async {
    final network = SimNetwork();
    final [a, b] = await routers(network, 2);
    for (var i = 0; i < 3; i++) {
      await a.publish(MessageKind.chat, MessageBody('trước khi gặp $i'));
    }
    network.connectDual('0', '1');
    await network.drain([a, b]);
    expect(await b.store.messages(), hasLength(3));
    expect(a.directPeers, hasLength(1));
    // Before the fix every packet crossed both links and echoed back.
    expect(a.stats.duplicate + b.stats.duplicate, 0);

    final before = network.frames;
    final p = await a.publish(MessageKind.chat, MessageBody('sau khi gặp'));
    await network.drain([a, b]);
    expect(network.frames - before, framesOf(p));
    expect((await a.store.messages()).first.handoffs, 1);

    // Losing one of the two links does not lose the phone.
    network.disconnectLink('0', '1/1');
    await network.drain([a, b]);
    final q = await a.publish(MessageKind.sos, MessageBody('còn một đường'));
    await network.drain([a, b]);
    expect(await has(b, q), isTrue);
  });

  test('a failed send is retried while the link stays up', () async {
    final network = SimNetwork();
    final [a, b] = await routers(network, 2);
    network.connect('0', '1');
    await network.drain([a, b]);
    network.node('0').failSends = 1;
    final p = await a.publish(MessageKind.sos, MessageBody('lần đầu lỗi'));
    await network.drain([a, b]);
    expect(await has(b, p), isFalse);
    expect(a.stats.failedSends, 1);
    await a.resync();
    await network.drain([a, b]);
    expect(await has(b, p), isTrue);
  });

  test('the retry timer resends without a reconnect', () async {
    final network = SimNetwork();
    final [a, b] = await routers(
      network,
      2,
      retryInterval: const Duration(milliseconds: 20),
    );
    network.connect('0', '1');
    await network.drain([a, b]);
    network.node('0').failSends = 1;
    final p = await a.publish(MessageKind.sos, MessageBody('tự gửi lại'));
    await network.drain([a, b]);
    // The timer may already have fired during the drain; either way only
    // the timer can deliver it, since nothing calls resync here.
    expect(a.stats.failedSends, 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await network.drain([a, b]);
    expect(await has(b, p), isTrue);
  });

  test('resync never sends a packet back to the phone it came from', () async {
    final network = SimNetwork();
    final list = await routers(network, 3);
    network.connect('0', '1');
    network.connect('1', '2');
    await network.drain(list);
    await list[0].publish(MessageKind.chat, MessageBody('một lần thôi'));
    await network.drain(list);
    final before = network.frames;
    for (final r in list) {
      await r.resync();
    }
    await network.drain(list);
    expect(network.frames, before);
  });

  test('handoffs count distinct phones that took our message', () async {
    final network = SimNetwork();
    final list = await routers(network, 3);
    final a = list[0];
    final p = await a.publish(MessageKind.sos, MessageBody('có ai nhận?'));
    expect((await a.store.messages()).single.handoffs, 0);
    network.connect('0', '1');
    network.connect('0', '2');
    await network.drain(list);
    expect((await a.store.messages()).single.handoffs, 2);
    // Relays do not count other people's messages.
    expect(
      (await list[1].store.messages())
          .singleWhere((m) => m.packet.messageId == p.messageId)
          .handoffs,
      0,
    );
  });

  test('an SOS is not held up by a long backlog to another phone', () async {
    final t = GatedTransport();
    final b = MeshRouter(
      identity: await Identity.create(),
      transport: t,
      store: MemoryStore(),
      name: 'B',
      retryInterval: null,
    );
    await b.start();
    addTearDown(() async {
      t.open();
      await b.dispose();
    });
    for (var i = 0; i < 20; i++) {
      await b.publish(MessageKind.chat, MessageBody('tồn đọng $i'));
    }
    final c = await Identity.create(), d = await Identity.create();
    // D's link is slow: nothing sent to it completes until the gate opens.
    t.gate('d');
    t.link('d');
    t.deliver('d', await signed(d, MessageKind.hello, 'D', ttl: 1));
    t.link('c');
    t.deliver('c', await signed(c, MessageKind.hello, 'C', ttl: 1));
    final sos = await signed(c, MessageKind.sos, 'cứu với');
    t.deliver('c', sos);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Received and shown while D's backlog is still stuck.
    expect(await has(b, sos), isTrue);

    t.open();
    await b.idle;
    final toD = t.packetsTo('d').where((p) => p.kind != MessageKind.hello);
    expect(toD, hasLength(21));
    // Only the chat already in flight goes before the SOS.
    expect(
      toD.toList().indexWhere((p) => p.messageId == sos.messageId),
      lessThanOrEqualTo(1),
    );
  });

  test('a link that never says hello is synced after a timeout', () async {
    final t = GatedTransport();
    final r = MeshRouter(
      identity: await Identity.create(),
      transport: t,
      store: MemoryStore(),
      name: 'R',
      retryInterval: null,
      helloTimeout: const Duration(milliseconds: 20),
    );
    await r.start();
    addTearDown(r.dispose);
    final p = await r.publish(MessageKind.sos, MessageBody('ai cũng được'));
    t.link('x');
    await r.idle;
    expect(t.packetsTo('x').map((v) => v.kind), [MessageKind.hello]);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await r.idle;
    expect(t.packetsTo('x').map((v) => v.messageId), contains(p.messageId));
    expect(r.nodeForPeer('x'), isNull);
    // Unverified neighbours do not count as handoffs.
    expect((await r.store.messages()).single.handoffs, 0);
  });

  test('a storage failure is reported, not counted as rejected', () async {
    final network = SimNetwork();
    final a = MeshRouter(
      identity: await Identity.create(),
      transport: network.node('0'),
      store: MemoryStore(),
      name: 'A',
      retryInterval: null,
    );
    final b = MeshRouter(
      identity: await Identity.create(),
      transport: network.node('1'),
      store: BrokenStore(),
      name: 'B',
      retryInterval: null,
    );
    await a.start();
    await b.start();
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
    });
    network.connect('0', '1');
    await network.drain([a, b]);
    await a.publish(MessageKind.chat, MessageBody('xin chào'));
    await network.drain([a, b]);
    expect(b.stats.rejected, 0);
    expect(b.lastError, contains('ổ đĩa đầy'));
  });

  test('a full packet store drops chat before an older SOS', () async {
    final store = MemoryStore();
    final now = DateTime.now().millisecondsSinceEpoch;
    final sos = unsigned(MessageKind.sos, now - 3600000);
    await store.retain(sos);
    for (var i = 0; i < maxPackets; i++) {
      await store.retain(unsigned(MessageKind.chat, now - 1000 + i));
    }
    final pending = await store.pending();
    expect(pending, hasLength(maxPackets));
    expect(pending.first.messageId, sos.messageId);
  });
}

Packet unsigned(MessageKind kind, int timestamp) => Packet(
  kind: kind,
  maxHops: 6,
  timestamp: timestamp,
  id: randomBytes(16),
  signingKey: Uint8List(32),
  exchangeKey: Uint8List(32),
  recipient: Uint8List(8),
  payload: Uint8List(0),
  signature: Uint8List(64),
);

/// A packet from [who] as it arrives after one hop.
Future<Packet> signed(
  Identity who,
  MessageKind kind,
  String text, {
  int ttl = 6,
}) async => (await who.sign(
  Packet(
    kind: kind,
    maxHops: ttl,
    timestamp: DateTime.now().millisecondsSinceEpoch,
    id: randomBytes(16),
    signingKey: who.publicSigning,
    exchangeKey: who.publicExchange,
    recipient: Uint8List(8),
    payload: MessageBody(text).encode(),
    signature: Uint8List(64),
  ),
)).copy(hops: 1);

class BrokenStore extends MemoryStore {
  @override
  Future<void> save(StoredMessage m) async {
    if (!m.outgoing) {
      throw StateError('ổ đĩa đầy');
    }
    await super.save(m);
  }
}

/// Transport driven by hand; sends to a gated link wait until [open].
class GatedTransport implements MeshTransport {
  final links = <String, Peer>{};
  final sent = <({String to, Uint8List data})>[];
  final _gates = <String, Completer<void>>{};
  final _events = StreamController<TransportEvent>.broadcast();
  @override
  Stream<TransportEvent> get events => _events.stream;
  @override
  List<Peer> get peers => links.values.toList();
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> send(String peerId, Uint8List frame) async {
    final gate = _gates[peerId];
    if (gate != null) {
      await gate.future;
    }
    sent.add((to: peerId, data: frame));
  }

  void gate(String link) => _gates[link] = Completer<void>();
  void open() {
    for (final g in _gates.values) {
      if (!g.isCompleted) {
        g.complete();
      }
    }
    _gates.clear();
  }

  void link(String id) {
    links[id] = Peer(id, mtu: 185);
    _events.add(PeerConnected(links[id]!));
  }

  void deliver(String from, Packet p) {
    for (final frame in Fragmenter.split(p.encode(), mtu: 185)) {
      _events.add(FrameReceived(from, frame));
    }
  }

  /// Packets sent to [link], in the order their last frame went out.
  List<Packet> packetsTo(String link) {
    final assembler = Reassembler();
    return [
      for (final f in sent.where((f) => f.to == link))
        if (assembler.add(link, f.data) case final raw?) Packet.decode(raw),
    ];
  }
}
