import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ble_emergency_app/main.dart';
import 'package:ble_emergency_app/core/identity.dart';
import 'package:ble_emergency_app/core/packet.dart';
import 'package:ble_emergency_app/messaging/sqlite_store.dart';
import 'package:ble_emergency_app/routing/router.dart';
import 'package:ble_emergency_app/simulator/network.dart';
import 'package:ble_emergency_app/transport/android_ble.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final captureKey = GlobalKey();
  final screenshots = <Map<String, dynamic>>[];
  Future<void> capture(String name) async {
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary
        .toImage(pixelRatio: 1.5)
        .timeout(const Duration(seconds: 20));
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    screenshots.add({
      'screenshotName': name,
      'bytes': bytes!.buffer.asUint8List().toList(),
    });
    binding.reportData = {'screenshots': screenshots};
    image.dispose();
  }

  Future<void> settle(WidgetTester tester) async {
    // Offstage EditableText/engine animations can keep scheduling frames on an
    // emulator. Wait for UI conditions rather than for all animation tickers.
    await tester.pump(const Duration(milliseconds: 400));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
  }

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100; i++) {
      await settle(tester);
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }
    fail('UI condition timed out: $finder');
  }

  testWidgets('Android keystore, SQLite restart and complete demo UI flow', (
    tester,
  ) async {
    // Native persistence is exercised independently from BLE hardware support.
    final identity = await Identity.create(
      saved: await AndroidBleTransport.loadIdentity(),
    );
    await AndroidBleTransport.saveIdentity(await identity.export());
    expect(
      (await Identity.create(saved: await AndroidBleTransport.loadIdentity()))
          .id,
      identity.id,
    );
    var store = await SqliteStore.open();
    final r = MeshRouter(
      identity: identity,
      transport: SimNetwork().node('test'),
      store: store,
      name: 'SQLite test',
    );
    final p = await r.publish(
      MessageKind.sos,
      MessageBody('SQLite persistence test'),
    );
    await store.close();
    store = await SqliteStore.open();
    expect(await store.hasSeen(p.messageId), isTrue);
    expect(
      (await store.pending()).any((v) => v.messageId == p.messageId),
      isTrue,
    );
    expect(
      (await store.messages()).any((v) => v.packet.messageId == p.messageId),
      isTrue,
    );
    await store.db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [p.messageId],
    );
    await store.db.delete('packets', where: 'id = ?', whereArgs: [p.messageId]);
    await store.close();
    await tester.pumpWidget(
      RepaintBoundary(key: captureKey, child: const EmergencyApp()),
    );
    await settle(tester);
    await capture('01-dashboard');
    await tester.tap(find.text('Thử mô phỏng 3 thiết bị'));
    await waitFor(tester, find.text('Mạng thử nghiệm A → B → C'));
    expect(find.text('Mạng thử nghiệm A → B → C'), findsOneWidget);
    for (var i = 0; i < 100; i++) {
      await settle(tester);
      if (tester
              .widget<ElevatedButton>(find.byType(ElevatedButton))
              .onPressed !=
          null) {
        break;
      }
    }
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.byIcon(Icons.sos));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.sos));
    await waitFor(tester, find.text('Gửi SOS'));
    await tester.tap(find.text('Gửi SOS'));
    await settle(tester);
    await tester.tap(find.text('Tin nhắn'));
    await waitFor(tester, find.text('Tôi cần hỗ trợ khẩn cấp.'));
    expect(find.text('Tôi cần hỗ trợ khẩn cấp.'), findsOneWidget);
    await capture('02-messages');
    await tester.tap(find.text('Thiết bị'));
    await settle(tester);
    await capture('03-peers');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.lock_outline).first);
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Tin riêng kiểm thử');
    await tester.tap(find.byTooltip('Gửi tin nhắn'));
    await waitFor(tester, find.text('Người nhận đã xác nhận'));
    expect(find.text('Tin riêng kiểm thử'), findsOneWidget);
    expect(find.text('Người nhận đã xác nhận'), findsOneWidget);
    await capture('04-private-ack');
    await tester.tap(find.text('Đánh giá'));
    await settle(tester);
    await tester.drag(find.byType(Slider).first, const Offset(-180, 0));
    await settle(tester);
    expect(find.text('10 thiết bị ảo'), findsOneWidget);
    await tester.tap(find.text('Chạy đánh giá'));
    await waitFor(tester, find.text('TỶ LỆ NHẬN SOS'));
    expect(find.text('TỶ LỆ NHẬN SOS'), findsOneWidget);
    await capture('05-simulator');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
