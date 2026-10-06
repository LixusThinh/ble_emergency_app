import 'dart:typed_data';

class Peer {
  final String id;
  final int rssi, mtu;
  Peer(this.id, {this.rssi = -65, this.mtu = 23});
  String get signal => rssi > -60
      ? 'Mạnh'
      : rssi > -80
      ? 'Trung bình'
      : 'Yếu';
}

sealed class TransportEvent {}

class PeerConnected extends TransportEvent {
  final Peer peer;
  PeerConnected(this.peer);
}

class PeerDisconnected extends TransportEvent {
  final String id;
  PeerDisconnected(this.id);
}

class FrameReceived extends TransportEvent {
  final String peerId;
  final Uint8List bytes;
  FrameReceived(this.peerId, this.bytes);
}

class TransportError extends TransportEvent {
  final String message;
  TransportError(this.message);
}

abstract interface class MeshTransport {
  Stream<TransportEvent> get events;
  List<Peer> get peers;
  Future<void> start();
  Future<void> stop();
  Future<void> send(String peerId, Uint8List frame);
}
