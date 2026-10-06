import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../transport/transport.dart';
import '../routing/router.dart';

/// Deterministic frame network. Uses the same packet/crypto/router as Android.
class SimNetwork {
  final transports = <String, SimTransport>{};
  final Queue<({String from, String to, Uint8List data})> _queue = Queue();
  int frames = 0, drops = 0;
  SimTransport node(String id) =>
      transports.putIfAbsent(id, () => SimTransport._(id, this));
  void connect(String a, String b, {int mtu = 185}) {
    final ta = node(a), tb = node(b);
    if (ta.links.containsKey(b)) {
      return;
    }
    ta.links[b] = Peer(b, mtu: mtu);
    tb.links[a] = Peer(a, mtu: mtu);
    ta._events.add(PeerConnected(ta.links[b]!));
    tb._events.add(PeerConnected(tb.links[a]!));
  }

  void disconnect(String a, String b) {
    node(a).links.remove(b);
    node(b).links.remove(a);
    node(a)._events.add(PeerDisconnected(b));
    node(b)._events.add(PeerDisconnected(a));
  }

  Future<void> drain(List<MeshRouter> routers, {int budget = 250000}) async {
    var delivered = 0;
    for (var round = 0; round < 1000; round++) {
      await Future<void>.delayed(Duration.zero);
      await Future.wait(routers.map((r) => r.idle));
      if (_queue.isEmpty) {
        return;
      }
      while (_queue.isNotEmpty) {
        if (++delivered > budget) {
          throw StateError(
            'Simulation frame budget exceeded ($budget); flooding storm',
          );
        }
        final f = _queue.removeFirst();
        frames++;
        if (node(f.from).links.containsKey(f.to)) {
          node(f.to)._events.add(FrameReceived(f.from, f.data));
        } else {
          drops++;
        }
      }
    }
    throw StateError('Simulation did not settle');
  }
}

class SimTransport implements MeshTransport {
  final String id;
  final SimNetwork network;
  final links = <String, Peer>{};
  final _events = StreamController<TransportEvent>.broadcast();
  SimTransport._(this.id, this.network);
  @override
  Stream<TransportEvent> get events => _events.stream;
  @override
  List<Peer> get peers => links.values.toList();
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {
    for (final p in links.keys.toList()) {
      network.disconnect(id, p);
    }
  }

  @override
  Future<void> send(String peerId, Uint8List frame) async {
    if (!links.containsKey(peerId)) {
      throw StateError('Peer disconnected');
    }
    network._queue.add((from: id, to: peerId, data: Uint8List.fromList(frame)));
  }
}
