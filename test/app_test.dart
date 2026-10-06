import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
