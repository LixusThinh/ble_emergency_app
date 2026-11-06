import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ble_emergency_app/app/controller.dart';
import 'package:ble_emergency_app/core/packet.dart';
import 'package:ble_emergency_app/main.dart';
import 'package:ble_emergency_app/ui/sos_dialog.dart';
import 'package:ble_emergency_app/ui/theme.dart';
import 'package:ble_emergency_app/ui/widgets.dart';

void main() {
  group('composeSos', () {
    test('falls back when nothing is chosen', () {
      expect(composeSos([], '  '), sosFallback);
    });
    test('joins tags and note into one sentence list', () {
      expect(
        composeSos(['Bị thương', 'Cần thuốc'], 'tầng 3'),
        'Bị thương. Cần thuốc. tầng 3.',
      );
    });
    test('keeps the note punctuation', () {
      expect(composeSos([], 'Mau lên!'), 'Mau lên!');
    });
  });

  test('dayLabel names today, yesterday and older days', () {
    final now = DateTime(2026, 11, 6, 9);
    expect(dayLabel(DateTime(2026, 11, 6), now: now), 'Hôm nay');
    expect(dayLabel(DateTime(2026, 11, 5), now: now), 'Hôm qua');
    expect(dayLabel(DateTime(2026, 10, 1), now: now), '01/10/2026');
  });

  test('conversation filter separates public and private messages', () async {
    final c = AppController();
    addTearDown(c.stop);
    await c.start(simulated: true);
    final rescue = c.router!.contacts.values.firstWhere(
      (v) => v.name == 'Đội cứu hộ',
    );
    expect(await c.send(MessageKind.chat, 'chung'), isTrue);
    expect(
      await c.send(MessageKind.privateChat, 'riêng', recipient: rescue),
      isTrue,
    );
    final public = c.messages.where((m) => inConversation(m, null));
    final private = c.messages.where((m) => inConversation(m, rescue.id));
    expect(public.map((m) => m.text), contains('chung'));
    expect(public.map((m) => m.text), isNot(contains('riêng')));
    expect(private.map((m) => m.text), ['riêng']);
    expect(
      c.messages.where((m) => inConversation(m, 'khong-ton-tai')),
      isEmpty,
    );
  });

  testWidgets('dark theme builds every tab without errors', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(const EmergencyApp());
    final ctx = tester.element(find.text('SOS MESH'));
    expect(Theme.of(ctx).brightness, Brightness.dark);
    expect(ctx.palette.canvas, Palette.dark.canvas);
    for (final label in ['Tin nhắn', 'Thiết bị', 'Đánh giá', 'Khẩn cấp']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('SOS dialog previews and returns the composed text', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showDialog<String>(
              context: context,
              builder: (_) => const SosDialog(),
            ),
            child: const Text('mở'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    expect(find.text(sosFallback), findsOneWidget);
    await tester.tap(find.text('Bị mắc kẹt'));
    await tester.pump();
    expect(find.text('Bị mắc kẹt.'), findsOneWidget);
    await tester.tap(find.text('Gửi SOS'));
    await tester.pumpAndSettle();
    expect(result, 'Bị mắc kẹt.');
  });

  testWidgets('status chip in the header opens the device tab', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const EmergencyApp());
    await tester.tap(find.text('Ngoại tuyến'));
    await tester.pumpAndSettle();
    expect(find.text('Thiết bị trong mạng'), findsOneWidget);
    expect(find.text('Đến tab Khẩn cấp'), findsOneWidget);
  });
}
