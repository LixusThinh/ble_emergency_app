import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../core/contact.dart';
import '../core/identity.dart';
import '../core/packet.dart';
import '../messaging/store.dart';
import '../transport/fragments.dart';
import '../transport/transport.dart';
import 'flood_guard.dart';

export '../core/contact.dart';
export 'flood_guard.dart';

class RouterStats {
  int received = 0, relayed = 0, duplicate = 0, rejected = 0, sentFrames = 0;

  /// Transmissions that failed; [MeshRouter.resync] offers them again.
  int failedSends = 0;

  /// Packets dropped because their sender was over its budget, and frames
  /// dropped because their link was muted; see [FloodGuard].
  int limited = 0, ignoredFrames = 0;
}

/// Packets waiting for one neighbouring phone: most urgent kind first, in
/// arrival order within a kind.
class _Outbox {
  final _lanes = List.generate(5, (_) => Queue<Packet>());
  final _queued = <String>{};

  /// False when [p] is already waiting and [dedup] is on.
  bool add(Packet p, {required bool dedup}) {
    if (!_queued.add(p.messageId) && dedup) {
      return false;
    }
    _lanes[p.priority].add(p);
    return true;
  }

  Packet? take() {
    for (final lane in _lanes) {
      if (lane.isNotEmpty) {
        final p = lane.removeFirst();
        _queued.remove(p.messageId);
        return p;
      }
    }
    return null;
  }
}

/// Signed flooding with dedup, TTL, ACK and store-and-forward.
///
/// Sending never blocks receiving: each neighbouring phone has its own outbox,
/// drained by its own task, so a long store-and-forward backlog to one phone
/// neither delays packets arriving from others nor keeps an SOS waiting behind
/// queued chat. A phone reached over two links (Android's central and
/// peripheral roles) is one neighbour and gets each packet once.
class MeshRouter {
  final Identity identity;
  final MeshTransport transport;
  final MessageStore store;
  final String name;
  final bool deduplicate;

  /// How often live neighbours are offered pending packets again after a
  /// failed send, so it does not wait for the next reconnect. Null disables
  /// the timer.
  final Duration? retryInterval;

  /// A link that has not said hello by then is synced as its own neighbour.
  final Duration helloTimeout;

  /// Signature check for received packets; a [CryptoWorker] keeps it off the
  /// UI isolate. Defaults to [Identity.verify] on the calling isolate.
  final Future<bool> Function(Packet) verify;

  /// Per-sender budgets and muting of links that send forgeries.
  final FloodGuard guard;
  final stats = RouterStats();
  final contacts = <String, Contact>{};
  final _updates = StreamController<void>.broadcast();
  final _assembler = Reassembler();

  /// Connected link ids, as the transport names them.
  final Set<String> _links = {};

  /// Link id to neighbour key: the node ID its hello proved, or `~link` for a
  /// link that never said hello.
  final Map<String, String> _peerNodes = {};
  final Map<String, Timer> _helloWait = {};

  /// Per neighbour: message ids it already has (we sent them or it sent us).
  final Map<String, Set<String>> _sent = {};
  final Map<String, _Outbox> _outboxes = {};
  final Set<String> _draining = {};

  /// Our own messages and the neighbours already recorded as holding them.
  final Map<String, Set<String>> _handedTo = {};
  final Set<Future<void>> _tasks = {};
  final Map<String, int> _contactSaved = {};
  late final String _signer = hex(identity.publicSigning);
  Future<void> _work = Future.value();
  StreamSubscription<TransportEvent>? _subscription;
  Timer? _retry;
  int _failuresRetried = 0;
  String? lastError;
  bool running = false;
  MeshRouter({
    required this.identity,
    required this.transport,
    required this.store,
    required this.name,
    this.deduplicate = true,
    this.retryInterval = const Duration(seconds: 30),
    this.helloTimeout = const Duration(seconds: 5),
    Future<bool> Function(Packet)? verifier,
    FloodGuard? guard,
  }) : verify = verifier ?? Identity.verify,
       guard = guard ?? FloodGuard();
  Stream<void> get updates => _updates.stream;

  /// Completes once received events are handled and outboxes are drained.
  Future<void> get idle async {
    while (true) {
      final work = _work;
      await work;
      if (_tasks.isNotEmpty) {
        await Future.wait(_tasks.toList());
      } else if (identical(work, _work)) {
        return;
      }
    }
  }

  /// Runs [task] in the background; [idle] waits for it.
  void _track(Future<void> task) {
    late final Future<void> tracked;
    tracked = task
        .catchError((Object e) {
          lastError = '$e';
          _notify();
        })
        .whenComplete(() => _tasks.remove(tracked));
    _tasks.add(tracked);
  }

  void _notify() {
    if (!_updates.isClosed) {
      _updates.add(null);
    }
  }

  Future<void> start() async {
    // Remembered contacts first, so names and private chats work before the
    // other phone says hello again.
    try {
      for (final c in await store.contacts()) {
        contacts.putIfAbsent(c.id, () => c);
      }
    } catch (e) {
      lastError = 'Không đọc được danh bạ đã lưu: $e';
    }
    _subscription = transport.events.listen((e) {
      _work = _work.then((_) => _event(e)).catchError((Object error) {
        lastError = '$error';
        _notify();
      });
    });
    try {
      await transport.start();
      running = true;
      final every = retryInterval;
      if (every != null) {
        _retry = Timer.periodic(every, (_) {
          // Only failures leave packets unoffered on a live link; skip the
          // full pending() read when nothing failed since the last retry.
          if (running && stats.failedSends != _failuresRetried) {
            _failuresRetried = stats.failedSends;
            _track(resync());
          }
        });
      }
      _notify();
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      rethrow;
    }
  }

  Future<void> _event(TransportEvent event) async {
    if (event is PeerConnected) {
      // Android re-announces a link after MTU exchange or when one of its two
      // GATT roles drops; only a new link needs hello and store-and-forward.
      final link = event.peer.id;
      if (_links.add(link)) {
        // Store-and-forward starts once the other side's hello says which
        // phone this link reaches; see [_identify].
        _helloWait[link] = Timer(helloTimeout, () => _identify(link, '~$link'));
        _track(_greet(event.peer));
      }
    } else if (event is PeerDisconnected) {
      final link = event.id;
      _links.remove(link);
      _helloWait.remove(link)?.cancel();
      guard.forget(link);
      final node = _peerNodes.remove(link);
      if (node != null && !_peerNodes.containsValue(node)) {
        // Last link to that phone. It may have lost packets by the time it is
        // back, so the next encounter syncs from scratch.
        _sent.remove(node);
        _outboxes.remove(node);
      }
    } else if (event is FrameReceived) {
      if (guard.muted(event.peerId)) {
        // Sent too many forgeries; not even reassembled.
        stats.ignoredFrames++;
        return;
      }
      final Packet packet;
      try {
        final raw = _assembler.add(event.peerId, event.bytes);
        if (raw == null) {
          return;
        }
        packet = Packet.decode(raw);
      } catch (_) {
        stats.rejected++;
        guard.bad(event.peerId);
        _notify();
        return;
      }
      try {
        await _receive(packet, event.peerId);
      } catch (e) {
        // A valid packet we failed to handle (storage, crypto) is this
        // phone's fault, not the sender's: surface it, don't count it rejected.
        lastError = 'Không xử lý được tin vừa nhận: $e';
      }
    } else if (event is TransportError) {
      lastError = event.message;
    }
    _notify();
  }

  /// Hello is link-local and regenerated per link, so it is never queued.
  Future<void> _greet(Peer peer) async {
    final hello = await _packet(
      MessageKind.hello,
      MessageBody(name).encode(),
      ttl: 1,
    );
    try {
      await _transmit(hello, peer);
    } catch (e) {
      stats.failedSends++;
      lastError = '$e';
      _notify();
    }
  }

  /// Binds [link] to neighbour [node] and offers that neighbour everything
  /// pending.
  void _identify(String link, String node) {
    _helloWait.remove(link)?.cancel();
    final previous = _peerNodes[link];
    if (!_links.contains(link) || previous == node) {
      return;
    }
    _peerNodes[link] = node;
    if (previous != null && !_peerNodes.containsValue(previous)) {
      // A link first synced without hello turned out to be [node].
      final known = _sent.remove(previous);
      if (known != null) {
        _sent.putIfAbsent(node, () => {}).addAll(known);
      }
      _outboxes.remove(previous);
    }
    if (running) {
      _track(_offerPending([node]));
    }
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

  /// Signs, stores and queues a message. Returns once it is stored; sending
  /// happens in the background (see [idle]).
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
      MessageBody(
        body.text,
        latitude: body.latitude,
        longitude: body.longitude,
        accuracy: body.accuracy,
        address: body.address,
        sender: name,
      ).encode(),
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
        accuracy: body.accuracy,
        address: body.placeName,
      ),
    );
    _broadcast(p);
    _notify();
    return p;
  }

  Future<void> _receive(Packet p, String via) async {
    // Dedup is checked before expensive signature verification; cache contains verified packets only.
    if (deduplicate && await store.hasSeen(p.messageId)) {
      stats.duplicate++;
      _has(_peerNodes[via], p.messageId);
      return;
    }
    // A clock off by a few hours on a relay can make honest packets look
    // expired, so these do not count against the link.
    if (p.expired ||
        p.timestamp > DateTime.now().millisecondsSinceEpoch + 300000 ||
        p.hops < 1) {
      stats.rejected++;
      return;
    }
    final origin = hex(p.signingKey);
    // Checked before the 3 ms signature check, but only spent after it, so
    // forged packets cannot use up a real sender's budget.
    if (origin != _signer && !guard.allows(origin, p.kind)) {
      stats.limited++;
      return;
    }
    if (!await verify(p)) {
      stats.rejected++;
      guard.bad(via);
      return;
    }
    final sender = hex(await Identity.nodeIdFor(p.signingKey));
    if (sender == identity.id) {
      return;
    }
    guard.admit(origin, p.kind);
    final previous = contacts[sender];
    var contactName = previous?.name ?? 'Thiết bị ${sender.substring(0, 6)}';
    if (p.kind == MessageKind.hello) {
      contactName = MessageBody.decode(p.payload).text;
    }
    await _remember(sender, contactName, p.exchangeKey);
    await store.retain(p);
    stats.received++;
    if (p.kind == MessageKind.hello && p.hops == 1) {
      _identify(via, sender);
    }
    final from = _peerNodes[via];
    _has(from, p.messageId);
    final forMe = !p.broadcast && hex(p.recipient) == identity.id;
    // Relay before reading the body: a signed packet whose body this node
    // cannot decode is still forwarded to nodes that may understand it.
    if (p.kind != MessageKind.hello && !forMe && p.hops < p.maxHops) {
      _broadcast(p, except: from);
      stats.relayed++;
    }
    if (p.kind == MessageKind.ack && p.payload.length == 16) {
      // Relays also settle the original so they stop forwarding it.
      await store.acknowledge(hex(p.payload), sender);
    } else if (p.kind != MessageKind.hello &&
        p.kind != MessageKind.ack &&
        (p.broadcast || forMe)) {
      final MessageBody body;
      try {
        body = MessageBody.decode(
          p.kind == MessageKind.privateChat
              ? await identity.decrypt(p)
              : p.payload,
        );
      } catch (_) {
        // Signed and already relayed, but unreadable on this phone.
        stats.rejected++;
        return;
      }
      if (body.sender != null && body.sender!.trim().isNotEmpty) {
        await _remember(sender, body.sender!.trim(), p.exchangeKey);
      }
      await store.save(
        StoredMessage(
          p,
          sender,
          body.text,
          latitude: body.latitude,
          longitude: body.longitude,
          accuracy: body.accuracy,
          address: body.address,
        ),
      );
      if (forMe) {
        final ack = await _packet(
          MessageKind.ack,
          p.id,
          recipient: contacts[sender],
        );
        await store.retain(ack);
        _broadcast(ack);
      }
    }
  }

  /// Notes that neighbour [node] already holds [id], so it is not sent back.
  void _has(String? node, String id) {
    if (node == null || !deduplicate) {
      return;
    }
    final known = _sent.putIfAbsent(node, () => <String>{});
    if (known.length >= maxPackets) {
      known.remove(known.first);
    }
    known.add(id);
  }

  /// Updates the in-memory contact and persists it when it is new, its name
  /// or key changed, or its last-seen time is more than a minute stale.
  Future<void> _remember(String id, String name, Uint8List key) async {
    final previous = contacts[id];
    final contact = Contact(id, name, key);
    contacts[id] = contact;
    final now = DateTime.now().millisecondsSinceEpoch;
    final changed =
        previous == null ||
        previous.name != name ||
        hex(previous.exchangeKey) != hex(key);
    if (changed || now - (_contactSaved[id] ?? 0) > 60000) {
      _contactSaved[id] = now;
      await store.saveContact(contact, now);
    }
  }

  /// Neighbours with at least one live, identified link.
  Set<String> get _neighbours => {for (final link in _links) ?_peerNodes[link]};

  /// Offers every live neighbour all pending packets again. Packets a
  /// neighbour already has are skipped, so this is cheap on a quiet mesh. It
  /// runs every [retryInterval]; public for tests.
  Future<void> resync() => _offerPending(_neighbours);

  Future<void> _offerPending(Iterable<String> nodes) async {
    final targets = nodes.toList();
    if (targets.isEmpty) {
      return;
    }
    final pending = await store.pending();
    for (final node in targets) {
      for (final p in pending) {
        if (p.kind != MessageKind.hello) {
          _enqueue(p, node);
        }
      }
    }
  }

  void _broadcast(Packet p, {String? except}) {
    for (final node in _neighbours) {
      if (node != except) {
        _enqueue(p, node);
      }
    }
  }

  void _enqueue(Packet p, String node) {
    if (p.hops >= p.maxHops || p.expired) {
      return;
    }
    if (deduplicate && (_sent[node]?.contains(p.messageId) ?? false)) {
      return;
    }
    final outbox = _outboxes.putIfAbsent(node, _Outbox.new);
    if (outbox.add(p, dedup: deduplicate) && _draining.add(node)) {
      _track(_drain(node));
    }
  }

  /// Sends [node]'s outbox one packet at a time over its strongest link.
  Future<void> _drain(String node) async {
    try {
      while (running) {
        final p = _outboxes[node]?.take();
        if (p == null) {
          return;
        }
        if (deduplicate && (_sent[node]?.contains(p.messageId) ?? false)) {
          continue;
        }
        final link = _linkTo(node);
        if (link == null) {
          _outboxes.remove(node);
          return;
        }
        try {
          await _transmit(p, link);
        } catch (_) {
          // Usually the link is going down; otherwise resync offers it again.
          stats.failedSends++;
          return;
        }
        _has(node, p.messageId);
        if (hex(p.signingKey) == _signer &&
            p.kind != MessageKind.ack &&
            !node.startsWith('~')) {
          await _handoff(p.messageId, node);
        }
      }
    } finally {
      _draining.remove(node);
    }
  }

  Peer? _linkTo(String node) {
    Peer? best;
    for (final peer in transport.peers) {
      if (_peerNodes[peer.id] == node &&
          (best == null || peer.rssi > best.rssi)) {
        best = peer;
      }
    }
    return best;
  }

  Future<void> _transmit(Packet p, Peer peer) async {
    final raw = p.copy(hops: p.hops + 1).encode();
    for (final frame in Fragmenter.split(raw, mtu: peer.mtu)) {
      await transport.send(peer.id, frame);
      stats.sentFrames++;
    }
  }

  Future<void> _handoff(String id, String node) async {
    if (_handedTo.length >= 2000 && !_handedTo.containsKey(id)) {
      _handedTo.remove(_handedTo.keys.first);
    }
    if (!_handedTo.putIfAbsent(id, () => {}).add(node)) {
      return;
    }
    await store.recordHandoff(id, node);
    _notify();
  }

  /// Node ID proven by the hello on link [peerId], if any.
  String? nodeForPeer(String peerId) {
    final node = _peerNodes[peerId];
    return node == null || node.startsWith('~') ? null : node;
  }

  /// Two phones usually link twice (each one's central role reaches the
  /// other's peripheral, under different addresses); hello shows both links
  /// belong to one node, so list each node once with its strongest link.
  List<Peer> get directPeers {
    final byNode = <String, Peer>{};
    for (final p in transport.peers) {
      final key = _peerNodes[p.id] ?? p.id;
      final seen = byNode[key];
      if (seen == null || p.rssi > seen.rssi) {
        byNode[key] = p;
      }
    }
    return byNode.values.toList();
  }

  Future<void> stop() async {
    running = false;
    _retry?.cancel();
    _retry = null;
    for (final t in _helloWait.values) {
      t.cancel();
    }
    _helloWait.clear();
    await transport.stop();
    await _subscription?.cancel();
    await idle;
    _links.clear();
    _peerNodes.clear();
    _sent.clear();
    _outboxes.clear();
    _notify();
  }

  Future<void> dispose() async {
    await stop();
    await _updates.close();
    await store.close();
  }
}
