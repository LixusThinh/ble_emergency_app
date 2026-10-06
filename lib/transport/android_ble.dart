import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'transport.dart';

class AndroidBleTransport implements MeshTransport {
  static const channel = MethodChannel('vn.emergency/ble');
  static const eventChannel = EventChannel('vn.emergency/ble_events');
  final _events = StreamController<TransportEvent>.broadcast();
  final _peers = <String, Peer>{};
  StreamSubscription<dynamic>? _native;
  @override
  Stream<TransportEvent> get events => _events.stream;
  @override
  List<Peer> get peers => _peers.values.toList();
  @override
  Future<void> start() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'BLE hiện hỗ trợ Android. Dùng mô phỏng trên nền tảng khác.',
      );
    }
    _native = eventChannel.receiveBroadcastStream().listen((dynamic value) {
      final e = Map<String, dynamic>.from(value as Map);
      switch (e['type']) {
        case 'peer':
          final p = Peer(
            e['id'] as String,
            rssi: (e['rssi'] as num?)?.toInt() ?? -65,
            mtu: (e['mtu'] as num?)?.toInt() ?? 23,
          );
          _peers[p.id] = p;
          _events.add(PeerConnected(p));
        case 'lost':
          _peers.remove(e['id']);
          _events.add(PeerDisconnected(e['id'] as String));
        case 'frame':
          _events.add(FrameReceived(e['id'] as String, e['data'] as Uint8List));
        case 'error':
          _events.add(TransportError(e['message'] as String));
      }
    }, onError: (Object e) => _events.add(TransportError('$e')));
    try {
      await channel.invokeMethod<void>('start');
    } catch (_) {
      await _native?.cancel();
      rethrow;
    }
  }

  @override
  Future<void> send(String peerId, Uint8List frame) =>
      channel.invokeMethod<void>('send', {'id': peerId, 'data': frame});
  @override
  Future<void> stop() async {
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('stop');
    }
    await _native?.cancel();
    _peers.clear();
  }

  static Future<String?> loadIdentity() =>
      channel.invokeMethod<String>('loadIdentity');
  static Future<void> saveIdentity(String value) =>
      channel.invokeMethod<void>('saveIdentity', {'value': value});
  static Future<Map<String, dynamic>?> location() async {
    final value = await channel.invokeMapMethod<String, dynamic>('location');
    return value;
  }
}
