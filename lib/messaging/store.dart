import '../core/contact.dart';
import '../core/packet.dart';

class StoredMessage {
  final Packet packet;
  final String senderId, text;
  final bool outgoing;
  bool acknowledged;
  final double? latitude, longitude;
  StoredMessage(
    this.packet,
    this.senderId,
    this.text, {
    this.outgoing = false,
    this.acknowledged = false,
    this.latitude,
    this.longitude,
  });
}

abstract interface class MessageStore {
  Future<bool> hasSeen(String id);
  Future<void> retain(Packet packet);
  Future<List<Packet>> pending();
  Future<void> save(StoredMessage message);
  Future<List<StoredMessage>> messages();

  /// Settles packet [id] when [senderId] is its private recipient, on the
  /// origin and on relays alike, so it leaves [pending].
  Future<void> acknowledge(String id, String senderId);

  /// Known nodes, most recently seen first.
  Future<List<Contact>> contacts();

  /// Inserts or updates [contact], seen at [seen] (epoch ms).
  Future<void> saveContact(Contact contact, int seen);
  Future<void> close();
}

/// Upper bound on remembered contacts; the least recently seen go first.
const maxContacts = 500;

class MemoryStore implements MessageStore {
  final Map<String, Packet> _packets = {};
  final Map<String, StoredMessage> _messages = {};
  final Set<String> _acked = {};
  final Map<String, (Contact, int)> _contacts = {};
  @override
  Future<bool> hasSeen(String id) async => _packets.containsKey(id);
  @override
  Future<void> retain(Packet p) async {
    _packets.removeWhere((_, p) => p.expired);
    if (_packets.length >= 5000) {
      _packets.remove(_packets.keys.first);
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
    _messages[m.packet.messageId] = m;
  }

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
    if (m != null && m.outgoing) {
      m.acknowledged = true;
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
