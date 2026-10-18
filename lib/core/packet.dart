import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
Uint8List randomBytes(int length) => Uint8List.fromList(
  List.generate(length, (_) => Random.secure().nextInt(256)),
);

enum MessageKind { sos, safe, chat, privateChat, hello, ack }

/// Signed immutable envelope. Only hops is mutable in transit.
class Packet {
  static const headerSize = 104;
  static const maxPayload = 4096;
  final MessageKind kind;
  final int maxHops, hops, timestamp;
  final Uint8List id, signingKey, exchangeKey, recipient, payload, signature;
  Packet({
    required this.kind,
    required this.maxHops,
    this.hops = 0,
    required this.timestamp,
    required this.id,
    required this.signingKey,
    required this.exchangeKey,
    required this.recipient,
    required this.payload,
    required this.signature,
  });
  String get messageId => hex(id);
  bool get broadcast => recipient.every((b) => b == 0);
  bool get expired =>
      DateTime.now().millisecondsSinceEpoch - timestamp >
      const Duration(hours: 24).inMilliseconds;
  int get priority => switch (kind) {
    MessageKind.sos => 0,
    MessageKind.ack => 1,
    MessageKind.safe => 2,
    MessageKind.hello => 3,
    _ => 4,
  };
  Uint8List encode({bool forSignature = false}) {
    if (id.length != 16 ||
        signingKey.length != 32 ||
        exchangeKey.length != 32 ||
        recipient.length != 8 ||
        payload.length > maxPayload ||
        maxHops < 1 ||
        maxHops > 15 ||
        hops > maxHops) {
      throw const FormatException('Invalid packet fields');
    }
    final bytes = Uint8List(
      headerSize + payload.length + (forSignature ? 0 : 64),
    );
    final d = ByteData.sublistView(bytes);
    bytes.setRange(0, 3, [0x45, 0x4d, 1]);
    bytes[3] = kind.index;
    bytes[4] = maxHops;
    bytes[5] = forSignature ? 0 : hops;
    d.setInt64(6, timestamp);
    bytes.setRange(14, 30, id);
    bytes.setRange(30, 62, signingKey);
    bytes.setRange(62, 94, exchangeKey);
    bytes.setRange(94, 102, recipient);
    d.setUint16(102, payload.length);
    bytes.setRange(headerSize, headerSize + payload.length, payload);
    if (!forSignature) {
      if (signature.length != 64) {
        throw const FormatException('Invalid signature length');
      }
      bytes.setRange(headerSize + payload.length, bytes.length, signature);
    }
    return bytes;
  }

  factory Packet.decode(Uint8List b) {
    if (b.length < headerSize + 64 ||
        b[0] != 0x45 ||
        b[1] != 0x4d ||
        b[2] != 1 ||
        b[3] >= MessageKind.values.length ||
        b[4] < 1 ||
        b[4] > 15 ||
        b[5] > b[4]) {
      throw const FormatException('Malformed envelope');
    }
    final d = ByteData.sublistView(b),
        length = ByteData.sublistView(b).getUint16(102);
    if (length > maxPayload || b.length != headerSize + length + 64) {
      throw const FormatException('Malformed payload');
    }
    return Packet(
      kind: MessageKind.values[b[3]],
      maxHops: b[4],
      hops: b[5],
      timestamp: d.getInt64(6),
      id: b.sublist(14, 30),
      signingKey: b.sublist(30, 62),
      exchangeKey: b.sublist(62, 94),
      recipient: b.sublist(94, 102),
      payload: b.sublist(headerSize, headerSize + length),
      signature: b.sublist(headerSize + length),
    );
  }
  Packet copy({int? hops, Uint8List? signature, Uint8List? payload}) => Packet(
    kind: kind,
    maxHops: maxHops,
    hops: hops ?? this.hops,
    timestamp: timestamp,
    id: id,
    signingKey: signingKey,
    exchangeKey: exchangeKey,
    recipient: recipient,
    payload: payload ?? this.payload,
    signature: signature ?? this.signature,
  );
}

/// Binary application body: flags, optional lat/lon doubles, optional
/// length-prefixed sender name, UTF-8 text.
///
/// The sender name rides in signed bodies because hello is link-local: without
/// it, a node two or more hops away would only ever be shown by its ID.
class MessageBody {
  static const _location = 1, _sender = 2;
  final String text;
  final double? latitude, longitude;
  final String? sender;
  MessageBody(this.text, {this.latitude, this.longitude, this.sender});
  Uint8List encode() {
    final location = latitude != null && longitude != null;
    final t = utf8.encode(text);
    final s = sender == null || sender!.isEmpty ? null : utf8.encode(sender!);
    if (t.length > 2000) {
      throw const FormatException('Tin nhắn tối đa 2000 byte UTF-8');
    }
    if (s != null && s.length > 255) {
      throw const FormatException('Tên hiển thị tối đa 255 byte UTF-8');
    }
    final b = Uint8List(
      1 + (location ? 16 : 0) + (s == null ? 0 : 1 + s.length) + t.length,
    );
    b[0] = (location ? _location : 0) | (s == null ? 0 : _sender);
    var offset = 1;
    if (location) {
      ByteData.sublistView(b)
        ..setFloat64(1, latitude!)
        ..setFloat64(9, longitude!);
      offset = 17;
    }
    if (s != null) {
      b[offset] = s.length;
      b.setRange(offset + 1, offset + 1 + s.length, s);
      offset += 1 + s.length;
    }
    b.setRange(offset, b.length, t);
    return b;
  }

  factory MessageBody.decode(Uint8List b) {
    if (b.isEmpty || b[0] & ~(_location | _sender) != 0) {
      throw const FormatException('Invalid message body');
    }
    final location = b[0] & _location != 0;
    var offset = location ? 17 : 1;
    if (b.length < offset) {
      throw const FormatException('Invalid message body');
    }
    String? sender;
    if (b[0] & _sender != 0) {
      if (b.length < offset + 1 || b.length < offset + 1 + b[offset]) {
        throw const FormatException('Invalid message body');
      }
      sender = utf8.decode(b.sublist(offset + 1, offset + 1 + b[offset]));
      offset += 1 + b[offset];
    }
    final d = ByteData.sublistView(b);
    return MessageBody(
      utf8.decode(b.sublist(offset)),
      latitude: location ? d.getFloat64(1) : null,
      longitude: location ? d.getFloat64(9) : null,
      sender: sender,
    );
  }
}
