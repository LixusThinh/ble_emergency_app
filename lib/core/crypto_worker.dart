import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'packet.dart';

/// Verifies packet signatures on a background isolate.
///
/// Ed25519 in pure Dart costs about 3 ms per packet. On the UI isolate a
/// store-and-forward sync of a few hundred packets would freeze the screen
/// for a second or more; here the UI keeps drawing while the worker checks.
class CryptoWorker {
  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _responses;
  final Map<int, Completer<bool>> _waiting = {};
  int _next = 0;
  bool _closed = false;

  CryptoWorker._(this._isolate, this._requests, this._responses) {
    _responses.listen((dynamic message) {
      final reply = message as List<Object?>;
      _waiting.remove(reply[0] as int)?.complete(reply[1] as bool);
    });
  }

  static Future<CryptoWorker> spawn() async {
    final setup = ReceivePort();
    final isolate = await Isolate.spawn(_main, setup.sendPort);
    final requests = await setup.first as SendPort;
    final responses = ReceivePort();
    requests.send(responses.sendPort);
    return CryptoWorker._(isolate, requests, responses);
  }

  /// Same answer as [Identity.verify], computed off this isolate.
  Future<bool> verify(Packet p) {
    if (_closed) {
      return Future.value(false);
    }
    final id = _next++;
    final done = Completer<bool>();
    _waiting[id] = done;
    _requests.send([
      id,
      p.encode(forSignature: true),
      p.signature,
      p.signingKey,
    ]);
    return done.future;
  }

  void close() {
    _closed = true;
    _isolate.kill(priority: Isolate.immediate);
    _responses.close();
    for (final waiting in _waiting.values) {
      waiting.complete(false);
    }
    _waiting.clear();
  }

  static Future<void> _main(SendPort setup) async {
    final inbox = ReceivePort();
    setup.send(inbox.sendPort);
    SendPort? replies;
    final ed25519 = Ed25519();
    await for (final dynamic message in inbox) {
      if (message is SendPort) {
        replies = message;
        continue;
      }
      final m = message as List<Object?>;
      var ok = false;
      try {
        ok = await ed25519.verify(
          m[1] as Uint8List,
          signature: Signature(
            m[2] as Uint8List,
            publicKey: SimplePublicKey(
              m[3] as Uint8List,
              type: KeyPairType.ed25519,
            ),
          ),
        );
      } catch (_) {
        ok = false;
      }
      replies?.send([m[0], ok]);
    }
  }
}
