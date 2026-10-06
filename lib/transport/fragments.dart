import 'dart:typed_data';

import '../core/packet.dart';

class Fragmenter {
  static const headerSize = 12;
  static List<Uint8List> split(Uint8List packet, {required int mtu}) {
    final capacity = mtu.clamp(23, 512) - 3 - headerSize;
    final count = (packet.length / capacity).ceil();
    if (packet.length > Packet.headerSize + Packet.maxPayload + 64 ||
        count > 1024) {
      throw const FormatException('Packet too large');
    }
    final token = randomBytes(4);
    return List.generate(count, (index) {
      final start = index * capacity,
          end = (start + capacity).clamp(0, packet.length);
      final b = Uint8List(headerSize + end - start);
      b.setRange(0, 2, [0x46, 1]);
      b.setRange(2, 6, token);
      final d = ByteData.sublistView(b);
      d.setUint16(6, index);
      d.setUint16(8, count);
      d.setUint16(10, packet.length);
      b.setRange(headerSize, b.length, packet.sublist(start, end));
      return b;
    });
  }
}

class _Assembly {
  final int count, length;
  final DateTime started = DateTime.now();
  final Map<int, Uint8List> parts = {};
  _Assembly(this.count, this.length);
}

class Reassembler {
  final Map<String, _Assembly> _pending = {};
  Uint8List? add(String peer, Uint8List frame) {
    _pending.removeWhere(
      (_, a) => DateTime.now().difference(a.started).inSeconds > 30,
    );
    if (frame.length <= 12 || frame[0] != 0x46 || frame[1] != 1) {
      throw const FormatException('Invalid fragment');
    }
    final d = ByteData.sublistView(frame),
        index = ByteData.sublistView(frame).getUint16(6);
    final count = d.getUint16(8), length = d.getUint16(10);
    if (count < 1 ||
        count > 1024 ||
        index >= count ||
        length > Packet.headerSize + Packet.maxPayload + 64 ||
        length < Packet.headerSize + 64) {
      throw const FormatException('Invalid fragment bounds');
    }
    final key = '$peer:${hex(frame.sublist(2, 6))}';
    if (!_pending.containsKey(key) && _pending.length >= 64) {
      _pending.remove(_pending.keys.first);
    }
    final a = _pending.putIfAbsent(key, () => _Assembly(count, length));
    if (a.count != count || a.length != length) {
      _pending.remove(key);
      throw const FormatException('Inconsistent fragments');
    }
    a.parts[index] = frame.sublist(12);
    if (a.parts.values.fold<int>(0, (v, b) => v + b.length) > length) {
      _pending.remove(key);
      throw const FormatException('Oversized assembly');
    }
    if (a.parts.length != count) {
      return null;
    }
    _pending.remove(key);
    final result = Uint8List.fromList([
      for (var i = 0; i < count; i++) ...a.parts[i]!,
    ]);
    if (result.length != length) {
      throw const FormatException('Assembly length mismatch');
    }
    return result;
  }
}
