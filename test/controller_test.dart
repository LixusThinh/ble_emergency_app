import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ble_emergency_app/app/controller.dart';
import 'package:ble_emergency_app/core/identity.dart';
import 'package:ble_emergency_app/core/packet.dart';
import 'package:ble_emergency_app/messaging/store.dart';

/// How the controller keeps its message list in step with the store.
void main() {
  test(
    'updates arriving during a read cost one more read, not one each',
    () async {
      final c = AppController();
      addTearDown(c.stop);
      await c.start(simulated: true);
      final before = c.refreshes;
      await Future.wait([for (var i = 0; i < 50; i++) c.refresh()]);
      expect(c.refreshes - before, 2);
    },
  );

  test('each read returns only the messages that changed', () async {
    final c = AppController();
    addTearDown(c.stop);
    await c.start(simulated: true);
    final loaded = c.loaded;
    for (var i = 0; i < 100; i++) {
      await c.router!.publish(MessageKind.chat, MessageBody('tin $i'));
    }
    await c.settled;
    // Each message is read when saved and again when the relay takes it
    // (its handoff count changes). Before, every update re-read the whole
    // list: about 200 reads of up to 100 rows.
    expect(c.loaded - loaded, lessThanOrEqualTo(2 * 100 + 10));
    expect(c.messages.where((m) => m.text.startsWith('tin ')), hasLength(100));
  });

  test('the merged list matches a full read of the store', () async {
    final c = AppController();
    addTearDown(c.stop);
    await c.start(simulated: true);
    await c.send(MessageKind.sos, 'cứu');
    final team = c.router!.contacts.values.firstWhere(
      (v) => v.name == 'Đội cứu hộ',
    );
    await c.send(MessageKind.privateChat, 'riêng', recipient: team);
    await c.settled;
    final full = await c.router!.store.messages();
    String row(StoredMessage m) =>
        '${m.packet.messageId} ${m.text} ${m.acknowledged} ${m.handoffs}';
    expect(c.messages.map(row), full.map(row));
    expect(
      c.messages.firstWhere((m) => m.text == 'riêng').acknowledged,
      isTrue,
    );
    expect(c.messages.firstWhere((m) => m.text == 'cứu').handoffs, 1);
  });

  test(
    'an incoming SOS raises one alert, however often the list reloads',
    () async {
      final c = AppController();
      addTearDown(c.stop);
      await c.start(simulated: true);
      final other = await Identity.create();
      final sos = await other.sign(
        Packet(
          kind: MessageKind.sos,
          maxHops: 6,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          id: randomBytes(16),
          signingKey: other.publicSigning,
          exchangeKey: other.publicExchange,
          recipient: Uint8List(8),
          payload: MessageBody('cứu').encode(),
          signature: Uint8List(64),
        ),
      );
      await c.router!.store.save(StoredMessage(sos, other.id, 'cứu'));
      await c.refresh();
      await c.refresh();
      expect(c.sosAlerts.map((m) => m.text), ['cứu']);
    },
  );
}
