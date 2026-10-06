import 'dart:async';
import 'dart:typed_data';

import '../core/identity.dart';
import '../core/packet.dart';
import '../messaging/store.dart';
import '../transport/fragments.dart';
import '../transport/transport.dart';

class Contact {
  final String id, name;
  final Uint8List exchangeKey;
  Contact(this.id, this.name, this.exchangeKey);
}

class RouterStats {
  int received = 0, relayed = 0, duplicate = 0, rejected = 0, sentFrames = 0;
}

class MeshRouter {
  final Identity identity;
  final MeshTransport transport;
  final MessageStore store;
  final String name;
  final bool deduplicate;
  final stats = RouterStats();
  final contacts = <String, Contact>{};
  final _updates = StreamController<void>.broadcast();
  final _assembler = Reassembler();
  final Map<String, Set<String>> _sent = {};
  final Map<String, String> _peerNodes = {};
  Future<void> _work = Future.value();
  StreamSubscription<TransportEvent>? _subscription;
  String? lastError;
  bool running = false;
  MeshRouter({
    required this.identity,
    required this.transport,
    required this.store,
    required this.name,
    this.deduplicate = true,
  });
  Stream<void> get updates => _updates.stream;
  Future<void> get idle => _work;
  void _notify() {
    if (!_updates.isClosed) {
      _updates.add(null);
    }
  }

  Future<void> start() async {
    _subscription = transport.events.listen((e) {
      _work = _work.then((_) => _event(e)).catchError((Object error) {
        lastError = '$error';
        _notify();
      });
    });
    try {
      await transport.start();
      running = true;
      _notify();
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      rethrow;
    }
  }

  Future<void> _event(TransportEvent event) async {
    if (event is PeerConnected) {
      _sent.remove(event.peer.id);
      final hello = await _packet(
        MessageKind.hello,
        MessageBody(name).encode(),
        ttl: 1,
      );
      await store.retain(hello);
      await _send(hello, event.peer);
      await sync(event.peer);
    } else if (event is PeerDisconnected) {
      _sent.remove(event.id);
      _peerNodes.remove(event.id);
    } else if (event is FrameReceived) {
      try {
        final raw = _assembler.add(event.peerId, event.bytes);
        if (raw != null) {
          await _receive(Packet.decode(raw), event.peerId);
        } else {
          return;
        }
      } catch (_) {
        stats.rejected++;
      }
    } else if (event is TransportError) {
      lastError = event.message;
    }
    _notify();
  }

  Future<Packet> _packet(
    MessageKind kind,
    Uint8List body, {
    Contact? recipient,
    int ttl = 6,
  }) async {
    final p = Packet(
      kind: kind,
      maxHops: ttl,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      id: randomBytes(16),
      signingKey: identity.publicSigning,
      exchangeKey: identity.publicExchange,
      recipient: recipient == null ? Uint8List(8) : _decodeHex(recipient.id),
      payload: body,
      signature: Uint8List(64),
    );
    return identity.sign(
      kind == MessageKind.privateChat
          ? p.copy(
              payload: await identity.encrypt(body, recipient!.exchangeKey, p),
            )
          : p,
    );
  }

  static Uint8List _decodeHex(String s) => Uint8List.fromList([
    for (var i = 0; i < s.length; i += 2)
      int.parse(s.substring(i, i + 2), radix: 16),
  ]);
  Future<Packet> publish(
    MessageKind kind,
    MessageBody body, {
    Contact? recipient,
    int ttl = 6,
  }) async {
    if (kind == MessageKind.privateChat && recipient == null) {
      throw ArgumentError('Chọn người nhận');
    }
    final p = await _packet(
      kind,
      body.encode(),
      recipient: recipient,
      ttl: ttl,
    );
    await store.retain(p);
    await store.save(
      StoredMessage(
        p,
        identity.id,
        body.text,
        outgoing: true,
        latitude: body.latitude,
        longitude: body.longitude,
      ),
    );
    await _broadcast(p);
    _notify();
    return p;
  }

  Future<void> _receive(Packet p, String via) async {
    // Dedup is checked before expensive signature verification; cache contains verified packets only.
    if (deduplicate && await store.hasSeen(p.messageId)) {
      stats.duplicate++;
      return;
    }
    if (p.expired ||
        p.timestamp > DateTime.now().millisecondsSinceEpoch + 300000 ||
        p.hops < 1 ||
        !await Identity.verify(p)) {
      stats.rejected++;
      return;
    }
    final sender = hex(await Identity.nodeIdFor(p.signingKey));
    if (sender == identity.id) {
      return;
    }
    final previous = contacts[sender];
    var contactName = previous?.name ?? 'Thiết bị ${sender.substring(0, 6)}';
    if (p.kind == MessageKind.hello) {
      contactName = MessageBody.decode(p.payload).text;
      if (p.hops == 1) {
        _peerNodes[via] = sender;
      }
    }
    contacts[sender] = Contact(sender, contactName, p.exchangeKey);
    await store.retain(p);
    stats.received++;
    final forMe = !p.broadcast && hex(p.recipient) == identity.id;
    if (p.kind == MessageKind.ack && forMe && p.payload.length == 16) {
      await store.acknowledge(hex(p.payload), sender);
    } else if (p.kind != MessageKind.hello &&
        p.kind != MessageKind.ack &&
        (p.broadcast || forMe)) {
      final clear = p.kind == MessageKind.privateChat
          ? await identity.decrypt(p)
          : p.payload;
      final body = MessageBody.decode(clear);
      await store.save(
        StoredMessage(
          p,
          sender,
          body.text,
          latitude: body.latitude,
          longitude: body.longitude,
        ),
      );
      if (forMe) {
        final ack = await _packet(
          MessageKind.ack,
          p.id,
          recipient: contacts[sender],
        );
        await store.retain(ack);
        await _broadcast(ack);
      }
    }
    if (p.kind != MessageKind.hello && !forMe && p.hops < p.maxHops) {
      await _broadcast(p, except: via);
      stats.relayed++;
    }
  }

  Future<void> sync(Peer peer) async {
    for (final p in await store.pending()) {
      if (p.hops < p.maxHops && (p.kind != MessageKind.hello || p.hops == 0)) {
        try {
          await _send(p, peer);
        } catch (e) {
          lastError = '$e';
          break;
        }
      }
    }
  }

  Future<void> _broadcast(Packet p, {String? except}) async {
    for (final peer in transport.peers.where((p) => p.id != except)) {
      try {
        await _send(p, peer);
      } catch (e) {
        lastError = '$e';
      }
    }
  }

  Future<void> _send(Packet p, Peer peer) async {
    if (p.hops >= p.maxHops || p.expired) {
      return;
    }
    final sent = _sent.putIfAbsent(peer.id, () => <String>{});
    if (deduplicate && sent.contains(p.messageId)) {
      return;
    }
    final raw = p.copy(hops: p.hops + 1).encode();
    for (final frame in Fragmenter.split(raw, mtu: peer.mtu)) {
      await transport.send(peer.id, frame);
      stats.sentFrames++;
    }
    if (sent.length >= 5000) {
      sent.remove(sent.first);
    }
    sent.add(p.messageId);
  }

  String? nodeForPeer(String peerId) => _peerNodes[peerId];
  Future<void> stop() async {
    running = false;
    await transport.stop();
    await _subscription?.cancel();
    await idle;
    _notify();
  }

  Future<void> dispose() async {
    await stop();
    await _updates.close();
    await store.close();
  }
}
