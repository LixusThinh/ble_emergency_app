import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

final _hexDigits = [
  for (var i = 0; i < 256; i++) i.toRadixString(16).padLeft(2, '0'),
];

/// Lower-case hex; message and node ids go through this on every packet.
String hex(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(_hexDigits[b & 0xff]);
  }
  return out.toString();
}

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

  /// Cached: the router keys dedup sets, outboxes and stores by it.
  late final String messageId = hex(id);
  late final bool broadcast = recipient.every((b) => b == 0);
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

/// Binary application body: flags, optional lat/lon doubles and their
/// accuracy, optional length-prefixed sender name and street address, UTF-8
/// text.
///
/// The sender name rides in signed bodies because hello is link-local: without
/// it, a node two or more hops away would only ever be shown by its ID. The
/// address is what the sender's phone looked the coordinates up as; it is
/// signed too, so relays cannot move an SOS somewhere else.
class MessageBody {
  static const _location = 1, _sender = 2, _address = 4, _accuracy = 8;
  static const _known = _location | _sender | _address | _accuracy;
  final String text;
  final double? latitude, longitude;

  /// Radius in metres the position is good to; needs a location.
  final double? accuracy;
  final String? sender, address;
  MessageBody(
    this.text, {
    this.latitude,
    this.longitude,
    this.accuracy,
    this.sender,
    this.address,
  });

  bool get hasLocation => latitude != null && longitude != null;

  /// [address] as [encode] sends it: trimmed, and only with a location.
  String? get placeName {
    final a = address?.trim();
    return hasLocation && a != null && a.isNotEmpty ? a : null;
  }

  static Uint8List? _short(String? value, String what) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final b = utf8.encode(value.trim());
    if (b.length > 255) {
      throw FormatException('$what tối đa 255 byte UTF-8');
    }
    return b;
  }

  Uint8List encode() {
    final location = hasLocation;
    final t = utf8.encode(text);
    if (t.length > 2000) {
      throw const FormatException('Tin nhắn tối đa 2000 byte UTF-8');
    }
    final s = _short(sender, 'Tên hiển thị');
    final a = location ? _short(address, 'Địa chỉ') : null;
    final acc = location && accuracy != null && accuracy! >= 0;
    final b = Uint8List(
      1 +
          (location ? 16 : 0) +
          (acc ? 4 : 0) +
          (s == null ? 0 : 1 + s.length) +
          (a == null ? 0 : 1 + a.length) +
          t.length,
    );
    final d = ByteData.sublistView(b);
    b[0] =
        (location ? _location : 0) |
        (s == null ? 0 : _sender) |
        (a == null ? 0 : _address) |
        (acc ? _accuracy : 0);
    var offset = 1;
    if (location) {
      d
        ..setFloat64(1, latitude!)
        ..setFloat64(9, longitude!);
      offset = 17;
    }
    if (acc) {
      d.setFloat32(offset, accuracy!);
      offset += 4;
    }
    for (final field in [s, a]) {
      if (field != null) {
        b[offset] = field.length;
        b.setRange(offset + 1, offset + 1 + field.length, field);
        offset += 1 + field.length;
      }
    }
    b.setRange(offset, b.length, t);
    return b;
  }

  factory MessageBody.decode(Uint8List b) {
    const bad = FormatException('Invalid message body');
    if (b.isEmpty || b[0] & ~_known != 0) {
      throw bad;
    }
    final flags = b[0];
    final location = flags & _location != 0;
    // Accuracy and address only describe a location.
    if (!location && flags & (_address | _accuracy) != 0) {
      throw bad;
    }
    final d = ByteData.sublistView(b);
    var offset = location ? 17 : 1;
    double? accuracy;
    if (flags & _accuracy != 0) {
      if (b.length < offset + 4) {
        throw bad;
      }
      final v = d.getFloat32(offset);
      accuracy = v.isFinite && v >= 0 ? v : null;
      offset += 4;
    }
    if (b.length < offset) {
      throw bad;
    }
    String? field(int flag) {
      if (flags & flag == 0) {
        return null;
      }
      if (b.length < offset + 1 || b.length < offset + 1 + b[offset]) {
        throw bad;
      }
      final v = utf8.decode(b.sublist(offset + 1, offset + 1 + b[offset]));
      offset += 1 + b[offset];
      return v;
    }

    final sender = field(_sender);
    final address = field(_address);
    // A position no map can show (NaN, out of range) is dropped, not trusted.
    final lat = location ? d.getFloat64(1) : double.nan,
        lon = location ? d.getFloat64(9) : double.nan;
    final valid = lat.abs() <= 90 && lon.abs() <= 180;
    return MessageBody(
      utf8.decode(b.sublist(offset)),
      latitude: valid ? lat : null,
      longitude: valid ? lon : null,
      accuracy: valid ? accuracy : null,
      sender: sender,
      address: valid ? address : null,
    );
  }
}
