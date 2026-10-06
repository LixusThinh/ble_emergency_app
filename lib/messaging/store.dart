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
  Future<void> acknowledge(String id, String senderId);
  Future<void> close();
}

class MemoryStore implements MessageStore {
  final Map<String, Packet> _packets = {};
  final Map<String, StoredMessage> _messages = {};
  final Set<String> _acked = {};
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
    final m = _messages[id];
    if (m != null &&
        m.outgoing &&
        !m.packet.broadcast &&
        hex(m.packet.recipient) == senderId) {
      m.acknowledged = true;
      _acked.add(id);
    }
  }

  @override
  Future<void> close() async {}
}
