import 'dart:typed_data';

/// A node this device has received a signed packet from.
class Contact {
  final String id, name;
  final Uint8List exchangeKey;
  Contact(this.id, this.name, this.exchangeKey);
}
