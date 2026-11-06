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

  /// Two links between one pair, as two Android phones form when each one's
  /// central reaches the other's peripheral: link ids `b/1` and `b/2` on a,
  /// `a/1` and `a/2` on b.
  void connectDual(String a, String b, {int mtu = 185}) {
    final ta = node(a), tb = node(b);
    for (final n in [1, 2]) {
      ta.links['$b/$n'] = Peer('$b/$n', mtu: mtu);
      tb.links['$a/$n'] = Peer('$a/$n', mtu: mtu);
      ta._events.add(PeerConnected(ta.links['$b/$n']!));
      tb._events.add(PeerConnected(tb.links['$a/$n']!));
    }
  }

  /// Drops one link; with [connectDual] links name it as `b/1` or `b/2`.
  void disconnectLink(String a, String link) {
    final (b, suffix) = _split(link);
    node(a).links.remove(link);
    node(b).links.remove('$a$suffix');
    node(a)._events.add(PeerDisconnected(link));
    node(b)._events.add(PeerDisconnected('$a$suffix'));
  }

  static (String, String) _split(String link) {
    final slash = link.indexOf('/');
    return slash < 0
        ? (link, '')
        : (link.substring(0, slash), link.substring(slash));
  }

  /// Re-announces an existing link, as Android does after an MTU exchange.
  void renegotiate(String a, String b, {required int mtu}) {
    final ta = node(a), tb = node(b);
    if (!ta.links.containsKey(b)) {
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
        final (to, suffix) = _split(f.to);
        if (node(f.from).links.containsKey(f.to)) {
          node(to)._events.add(FrameReceived('${f.from}$suffix', f.data));
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

  /// The next this many sends fail, as a busy or flaky BLE link does.
  int failSends = 0;
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
      network.disconnectLink(id, p);
    }
  }

  @override
  Future<void> send(String peerId, Uint8List frame) async {
    if (!links.containsKey(peerId)) {
      throw StateError('Peer disconnected');
    }
    if (failSends > 0) {
      failSends--;
      throw StateError('BLE đang bận');
    }
    network._queue.add((from: id, to: peerId, data: Uint8List.fromList(frame)));
  }
}
