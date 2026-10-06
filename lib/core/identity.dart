import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'packet.dart';

class Identity {
  final SimpleKeyPair signing, exchange;
  final Uint8List publicSigning, publicExchange, nodeId;
  Identity._(
    this.signing,
    this.exchange,
    this.publicSigning,
    this.publicExchange,
    this.nodeId,
  );
  static Future<Identity> create({String? saved}) async {
    final keys = saved == null
        ? null
        : jsonDecode(saved) as Map<String, dynamic>;
    final sign = keys == null
        ? await Ed25519().newKeyPair()
        : await Ed25519().newKeyPairFromSeed(
            base64Decode(keys['sign'] as String),
          );
    final exchange = keys == null
        ? await X25519().newKeyPair()
        : await X25519().newKeyPairFromSeed(
            base64Decode(keys['exchange'] as String),
          );
    final sp = Uint8List.fromList((await sign.extractPublicKey()).bytes);
    final xp = Uint8List.fromList((await exchange.extractPublicKey()).bytes);
    return Identity._(sign, exchange, sp, xp, await nodeIdFor(sp));
  }

  static Future<Uint8List> nodeIdFor(List<int> publicKey) async =>
      Uint8List.fromList((await Sha256().hash(publicKey)).bytes.sublist(0, 8));
  String get id => hex(nodeId);
  Future<String> export() async => jsonEncode({
    'sign': base64Encode(await signing.extractPrivateKeyBytes()),
    'exchange': base64Encode(await exchange.extractPrivateKeyBytes()),
  });
  Future<Packet> sign(Packet p) async => p.copy(
    signature: Uint8List.fromList(
      (await Ed25519().sign(
        p.encode(forSignature: true),
        keyPair: signing,
      )).bytes,
    ),
  );
  static Future<bool> verify(Packet p) => Ed25519().verify(
    p.encode(forSignature: true),
    signature: Signature(
      p.signature,
      publicKey: SimplePublicKey(p.signingKey, type: KeyPairType.ed25519),
    ),
  );
  Future<SecretKey> _key(Uint8List peer, Packet p) async {
    final shared = await X25519().sharedSecretKey(
      keyPair: exchange,
      remotePublicKey: SimplePublicKey(peer, type: KeyPairType.x25519),
    );
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: shared,
      nonce: p.id,
      info: utf8.encode('emergency-mesh-v1/private'),
    );
  }

  Future<Uint8List> encrypt(
    Uint8List clear,
    Uint8List recipientKey,
    Packet p,
  ) async {
    final box = await AesGcm.with256bits().encrypt(
      clear,
      secretKey: await _key(recipientKey, p),
      aad: [...p.id, ...p.recipient],
    );
    return Uint8List.fromList([
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Uint8List> decrypt(Packet p) async {
    if (p.payload.length < 28) {
      throw const FormatException('Truncated encrypted body');
    }
    final box = SecretBox(
      p.payload.sublist(12, p.payload.length - 16),
      nonce: p.payload.sublist(0, 12),
      mac: Mac(p.payload.sublist(p.payload.length - 16)),
    );
    return Uint8List.fromList(
      await AesGcm.with256bits().decrypt(
        box,
        secretKey: await _key(p.exchangeKey, p),
        aad: [...p.id, ...p.recipient],
      ),
    );
  }
}
