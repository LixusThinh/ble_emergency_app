import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ble_emergency_app/app/controller.dart';
import 'package:ble_emergency_app/core/packet.dart';
import 'package:ble_emergency_app/main.dart';

void main() {
  testWidgets('Vietnamese dashboard and demo entry fit a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const EmergencyApp());
    expect(find.text('SOS MESH'), findsOneWidget);
    expect(find.text('Bật mạng Bluetooth'), findsOneWidget);
    expect(find.text('Thử mô phỏng 3 thiết bị'), findsOneWidget);
    await tester.tap(find.text('Tin nhắn'));
    await tester.pumpAndSettle();
    expect(find.text('Tin nhắn sẽ xuất hiện ở đây.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('dismissed router error does not come back on the next send', () async {
    final c = AppController();
    addTearDown(c.stop);
    expect(await c.send(MessageKind.chat, 'chưa bật mạng'), isFalse);
    await c.start(simulated: true);
    c.router!.lastError = 'Peer disconnected';
    expect(await c.send(MessageKind.chat, 'một'), isTrue);
    expect(c.error, 'Peer disconnected');
    c.error = null;
    expect(await c.send(MessageKind.chat, 'hai'), isTrue);
    expect(c.error, isNull);
  });
}
