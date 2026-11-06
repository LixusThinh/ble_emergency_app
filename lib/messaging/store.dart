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
  StoredMessage(
    this.packet,
    this.senderId,
    this.text, {
    this.outgoing = false,
    this.acknowledged = false,
    this.handoffs = 0,
    this.latitude,
    this.longitude,
  });
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
  Future<void> close();
}

/// Messages kept for the UI; older ones are dropped.
const maxMessages = 2000;

/// Upper bound on remembered contacts; the least recently seen go first.
const maxContacts = 500;

/// Upper bound on retained packets. When full, settled (ACKed) packets go
/// first, then the least urgent kind, then the oldest, so a flood of chat
/// cannot push an SOS out of store-and-forward.
const maxPackets = 5000;

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
      // Same order as SqliteStore: acked, then priority, then age.
      (bool, int, int) rank(Packet v) =>
          (_acked.contains(v.messageId), v.priority, -v.timestamp);
      bool before((bool, int, int) a, (bool, int, int) b) =>
          a.$1 != b.$1 ? a.$1 : (a.$2 != b.$2 ? a.$2 > b.$2 : a.$3 > b.$3);
      final victim = _packets.values.reduce(
        (a, b) => before(rank(b), rank(a)) ? b : a,
      );
      _packets.remove(victim.messageId);
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
