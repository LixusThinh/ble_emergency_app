import '../core/contact.dart';
import '../core/packet.dart';

class StoredMessage {
  final Packet packet;
  final String senderId, text;
  final bool outgoing;
  bool acknowledged;

  /// Distinct nearby phones this phone handed an outgoing message to.
  int handoffs;
  final double? latitude, longitude;

  /// Metres the position is good to, as the sender measured it.
  final double? accuracy;

  /// Street address the sender's phone looked the position up as (signed).
  final String? address;

  /// Address this phone looked the position up as, when the sender could
  /// not (it had no Internet).
  String? lookedUpAddress;
  StoredMessage(
    this.packet,
    this.senderId,
    this.text, {
    this.outgoing = false,
    this.acknowledged = false,
    this.handoffs = 0,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.address,
    this.lookedUpAddress,
  });

  bool get hasLocation => latitude != null && longitude != null;

  /// The address to show: the sender's own, else the one looked up here.
  String? get placeName => address ?? lookedUpAddress;
}

/// Messages written or changed since a revision, newest first, and the
/// revision to ask from next time.
typedef MessageChanges = ({List<StoredMessage> messages, int revision});

abstract interface class MessageStore {
  Future<bool> hasSeen(String id);
  Future<void> retain(Packet packet);
  Future<List<Packet>> pending();
  Future<void> save(StoredMessage message);

  /// The newest [maxMessages] messages, newest first.
  Future<List<StoredMessage>> messages();

  /// Messages saved, acknowledged or handed off after revision [after];
  /// pass -1 for everything.
  Future<MessageChanges> changes(int after);

  /// Settles packet [id] when [senderId] is its private recipient, on the
  /// origin and on relays alike, so it leaves [pending].
  Future<void> acknowledge(String id, String senderId);

  /// Known nodes, most recently seen first.
  Future<List<Contact>> contacts();

  /// Inserts or updates [contact], seen at [seen] (epoch ms).
  Future<void> saveContact(Contact contact, int seen);

  /// Records that neighbour [node] received our message [id]; counted once
  /// per node in [StoredMessage.handoffs].
  Future<void> recordHandoff(String id, String node);

  /// Stores the address this phone found for message [id]'s position.
  Future<void> saveLookedUpAddress(String id, String address);
  Future<void> close();
}

/// Messages kept for the UI; older ones are dropped.
const maxMessages = 2000;

/// Upper bound on remembered contacts; the least recently seen go first.
const maxContacts = 500;

/// Upper bound on retained packets. When full, packets are dropped in the
/// reverse of [keepOrder]: settled (ACKed) ones first, then from whichever
/// sender holds the most, so one sender flooding the mesh pushes out its own
/// packets and not someone else's SOS.
const maxPackets = 5000;

/// Rows removed at once when a SQLite table is full. Sorting the table to
/// find the rows to drop is the expensive part, so it is paid once per batch
/// instead of on every insert.
const trimBatch = 100;

/// [packets] from most to least worth keeping, the order both stores trim in:
/// unsettled before settled, then each sender's share (everyone's best
/// packet before anyone's second best), then the more urgent kind, then the
/// newest. A sender's best packet is its most urgent and newest.
List<Packet> keepOrder(
  Iterable<Packet> packets,
  bool Function(Packet) settled,
) {
  int byValue(Packet a, Packet b) {
    final s = (settled(a) ? 1 : 0) - (settled(b) ? 1 : 0);
    if (s != 0) {
      return s;
    }
    final k = a.priority - b.priority;
    return k != 0 ? k : b.timestamp - a.timestamp;
  }

  final bySender = <String, List<Packet>>{};
  for (final p in packets) {
    bySender.putIfAbsent(hex(p.signingKey), () => []).add(p);
  }
  final share = <String, int>{};
  for (final list in bySender.values) {
    list.sort(byValue);
    for (var i = 0; i < list.length; i++) {
      share[list[i].messageId] = i;
    }
  }
  return packets.toList()..sort((a, b) {
    final s = (settled(a) ? 1 : 0) - (settled(b) ? 1 : 0);
    if (s != 0) {
      return s;
    }
    final r = share[a.messageId]! - share[b.messageId]!;
    return r != 0 ? r : byValue(a, b);
  });
}

class MemoryStore implements MessageStore {
  final Map<String, Packet> _packets = {};
  final Map<String, StoredMessage> _messages = {};
  final Set<String> _acked = {};
  final Map<String, (Contact, int)> _contacts = {};
  final Map<String, Set<String>> _handoffs = {};
  final Map<String, int> _revs = {};
  int _revision = 0;
  @override
  Future<bool> hasSeen(String id) async => _packets.containsKey(id);
  @override
  Future<void> retain(Packet p) async {
    if (_packets.containsKey(p.messageId)) {
      return;
    }
    _packets.removeWhere((_, p) => p.expired);
    if (_packets.length >= maxPackets) {
      final order = keepOrder(
        _packets.values,
        (v) => _acked.contains(v.messageId),
      );
      _packets.remove(order.last.messageId);
    }
    _packets[p.messageId] = p;
  }

  @override
  Future<List<Packet>> pending() async =>
      _packets.values
          .where((p) => !p.expired && !_acked.contains(p.messageId))
          .toList()
        ..sort((a, b) => a.priority.compareTo(b.priority));
  @override
  Future<void> save(StoredMessage m) async {
    final id = m.packet.messageId;
    if (_messages.containsKey(id)) {
      return;
    }
    _messages[id] = m..handoffs = _handoffs[id]?.length ?? 0;
    _revs[id] = ++_revision;
    if (_messages.length > maxMessages) {
      final oldest = _messages.values.reduce(
        (a, b) => a.packet.timestamp <= b.packet.timestamp ? a : b,
      );
      _messages.remove(oldest.packet.messageId);
      _revs.remove(oldest.packet.messageId);
    }
  }

  @override
  Future<void> recordHandoff(String id, String node) async {
    final nodes = _handoffs.putIfAbsent(id, () => {})..add(node);
    final m = _messages[id];
    if (m != null) {
      m.handoffs = nodes.length;
      _revs[id] = ++_revision;
    }
  }

  @override
  Future<void> saveLookedUpAddress(String id, String address) async {
    final m = _messages[id];
    if (m != null) {
      m.lookedUpAddress = address;
      _revs[id] = ++_revision;
    }
  }

  @override
  Future<MessageChanges> changes(int after) async => (
    messages: [
      for (final MapEntry(:key, :value) in _revs.entries)
        if (value > after) _messages[key]!,
    ]..sort((a, b) => b.packet.timestamp.compareTo(a.packet.timestamp)),
    revision: _revision,
  );

  @override
  Future<List<StoredMessage>> messages() async =>
      _messages.values.toList()
        ..sort((a, b) => b.packet.timestamp.compareTo(a.packet.timestamp));
  @override
  Future<void> acknowledge(String id, String senderId) async {
    final m = _messages[id], p = _packets[id] ?? m?.packet;
    if (p == null || p.broadcast || hex(p.recipient) != senderId) {
      return;
    }
    _acked.add(id);
    if (m != null && m.outgoing && !m.acknowledged) {
      m.acknowledged = true;
      _revs[id] = ++_revision;
    }
  }

  @override
  Future<List<Contact>> contacts() async =>
      (_contacts.values.toList()..sort((a, b) => b.$2.compareTo(a.$2)))
          .map((e) => e.$1)
          .toList();
  @override
  Future<void> saveContact(Contact contact, int seen) async {
    _contacts[contact.id] = (contact, seen);
    if (_contacts.length > maxContacts) {
      final oldest = _contacts.entries.reduce(
        (a, b) => a.value.$2 <= b.value.$2 ? a : b,
      );
      _contacts.remove(oldest.key);
    }
  }

  @override
  Future<void> close() async {}
}
