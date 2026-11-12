import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ble_emergency_app/app/controller.dart';
import 'package:ble_emergency_app/core/identity.dart';
import 'package:ble_emergency_app/core/packet.dart';
import 'package:ble_emergency_app/location/geocoder.dart';
import 'package:ble_emergency_app/location/locator.dart';
import 'package:ble_emergency_app/messaging/schema.dart';
import 'package:ble_emergency_app/messaging/sqlite_store.dart';
import 'package:ble_emergency_app/messaging/store.dart';
import 'package:ble_emergency_app/routing/router.dart';
import 'package:ble_emergency_app/simulator/network.dart';
import 'package:ble_emergency_app/ui/location_card.dart';
import 'package:ble_emergency_app/ui/theme.dart';

class _Fake implements Geocoder {
  final FutureOr<String?> Function(double, double) answer;
  int calls = 0;
  _Fake(this.answer);
  @override
  Future<String?> lookup(double lat, double lon) async {
    calls++;
    return answer(lat, lon);
  }
}

void main() {
  group('MessageBody 2.0', () {
    test('round-trips address, accuracy and sender', () {
      final b = MessageBody.decode(
        MessageBody(
          'Bị mắc kẹt',
          latitude: 10.801603,
          longitude: 106.714778,
          accuracy: 7.5,
          sender: 'Thịnh',
          address: '475A Điện Biên Phủ, TP. Hồ Chí Minh',
        ).encode(),
      );
      expect(b.text, 'Bị mắc kẹt');
      expect(b.latitude, 10.801603);
      expect(b.longitude, 106.714778);
      expect(b.accuracy, 7.5);
      expect(b.sender, 'Thịnh');
      expect(b.address, '475A Điện Biên Phủ, TP. Hồ Chí Minh');
    });

    test('reads 1.x bodies unchanged', () {
      // flags=location|sender, lat, lon, len-prefixed name, text: 1.x layout.
      final name = utf8.encode('An'), text = utf8.encode('cứu');
      final b = Uint8List(1 + 16 + 1 + name.length + text.length);
      b[0] = 3;
      ByteData.sublistView(b)
        ..setFloat64(1, 10.5)
        ..setFloat64(9, 106.5);
      b[17] = name.length;
      b.setRange(18, 18 + name.length, name);
      b.setRange(18 + name.length, b.length, text);
      final d = MessageBody.decode(b);
      expect(
        (d.latitude, d.longitude, d.sender, d.text),
        (10.5, 106.5, 'An', 'cứu'),
      );
      expect(d.address, isNull);
      expect(d.accuracy, isNull);
    });

    test('an address without a position is not sent', () {
      final b = MessageBody('xin chào', address: 'đâu đó').encode();
      expect(b[0], 0);
      expect(MessageBody.decode(b).address, isNull);
    });

    test('rejects an address flag without a position', () {
      final b = Uint8List.fromList([4, 1, 65, 66]);
      expect(() => MessageBody.decode(b), throwsFormatException);
    });

    test('drops positions no map can show', () {
      final b = MessageBody(
        'x',
        latitude: double.nan,
        longitude: 1,
        address: 'giả',
        accuracy: 3,
      ).encode();
      final d = MessageBody.decode(b);
      expect(d.latitude, isNull);
      expect(d.address, isNull);
      expect(d.accuracy, isNull);
      final far = MessageBody.decode(
        MessageBody('x', latitude: 91, longitude: 1).encode(),
      );
      expect(far.hasLocation, isFalse);
    });

    test('caps the address at 255 bytes', () {
      expect(
        () => MessageBody(
          'x',
          latitude: 1,
          longitude: 1,
          address: 'ạ' * 100,
        ).encode(),
        throwsFormatException,
      );
    });
  });

  group('address formatting', () {
    test('builds a short Vietnamese address from Nominatim fields', () {
      final v = formatNominatim({
        'display_name': 'không dùng',
        'address': {
          'house_number': '475A',
          'road': 'Điện Biên Phủ',
          'quarter': 'Phường Thạnh Mỹ Tây',
          'city': 'Thành phố Hồ Chí Minh',
          'postcode': '72300',
          'country': 'Việt Nam',
        },
      });
      expect(
        v,
        '475A Điện Biên Phủ, Phường Thạnh Mỹ Tây, Thành phố Hồ Chí Minh',
      );
    });

    test('falls back to display_name without postcode and country', () {
      expect(
        formatNominatim({
          'display_name': 'Chợ Bến Thành, Lê Lợi, Hồ Chí Minh, 70000, Việt Nam',
          'address': {'country': 'Việt Nam'},
        }),
        'Chợ Bến Thành, Lê Lợi, Hồ Chí Minh',
      );
      expect(formatNominatim({'error': 'Unable to geocode'}), isNull);
      expect(formatNominatim('rác'), isNull);
    });

    test('cleanAddress trims, drops the country and fits a packet', () {
      expect(
        cleanAddress('  12  Lê Lợi,  Quận 1, Việt Nam '),
        '12 Lê Lợi, Quận 1',
      );
      expect(cleanAddress('   '), isNull);
      final long = List.filled(40, 'Đường Nguyễn Thị Minh Khai').join(', ');
      final cut = cleanAddress(long)!;
      expect(utf8.encode(cut).length, lessThanOrEqualTo(255));
      expect(cut, startsWith('Đường Nguyễn Thị Minh Khai'));
    });

    test('accuracy labels', () {
      expect(accuracyLabel(7.6), '± 8 m');
      expect(accuracyLabel(1500), '± 1,5 km');
      expect(accuracyLabel(null), isNull);
      expect(accuracyLabel(double.nan), isNull);
    });

    test('directions open Google Maps at the position', () {
      expect(
        directionsUri(10.8, 106.7).toString(),
        'https://www.google.com/maps/dir/?api=1&destination=10.8%2C106.7',
      );
    });
  });

  group('CachingGeocoder', () {
    test('falls through a failing source and caches the answer', () async {
      final down = _Fake((_, _) => throw const SocketException('offline'));
      final up = _Fake((_, _) => '12 Lê Lợi');
      final g = CachingGeocoder([down, up], spacing: Duration.zero);
      expect(await g.lookup(10.1234561, 106.1), '12 Lê Lợi');
      // Same place to about a metre: answered from the cache.
      expect(await g.lookup(10.1234564, 106.1), '12 Lê Lợi');
      expect(up.calls, 1);
    });

    test('gives up after its timeout and asks again later', () async {
      final slow = _Fake(
        (_, _) => Future.delayed(const Duration(seconds: 2), () => 'muộn'),
      );
      final g = CachingGeocoder(
        [slow],
        timeout: const Duration(milliseconds: 50),
        spacing: Duration.zero,
      );
      expect(await g.lookup(1, 1), isNull);
      expect(await g.lookup(1, 1), isNull);
      expect(slow.calls, 2);
    });

    test('spaces lookups out', () async {
      final g = CachingGeocoder([
        _Fake((lat, _) => 'nơi $lat'),
      ], spacing: const Duration(milliseconds: 120));
      final watch = Stopwatch()..start();
      final all = await Future.wait([g.lookup(1, 1), g.lookup(2, 2)]);
      expect(all, ['nơi 1.0', 'nơi 2.0']);
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(100));
    });
  });

  test('locateAndName keeps the fix when the lookup fails', () async {
    final place = await locateAndName(
      FixedLocator.hutech,
      _Fake((_, _) => throw StateError('offline')),
    );
    expect(place.fix.latitude, 10.801603);
    expect(place.address, isNull);
  });

  test('a relayed SOS arrives with the signed address and accuracy', () async {
    final net = SimNetwork();
    final routers = <MeshRouter>[];
    for (final n in ['A', 'B', 'C']) {
      final r = MeshRouter(
        identity: await Identity.create(),
        transport: net.node(n),
        store: MemoryStore(),
        name: n,
      );
      routers.add(r);
      await r.start();
    }
    addTearDown(() async {
      for (final r in routers) {
        await r.dispose();
      }
    });
    net.connect('A', 'B');
    net.connect('B', 'C');
    await net.drain(routers);
    await routers.first.publish(
      MessageKind.sos,
      MessageBody(
        'Nước ngập',
        latitude: 10.8,
        longitude: 106.7,
        accuracy: 6,
        address: '475A Điện Biên Phủ',
      ),
    );
    await net.drain(routers);
    final got = (await routers.last.store.messages()).single;
    expect(got.address, '475A Điện Biên Phủ');
    expect(got.accuracy, 6);
    expect(got.placeName, '475A Điện Biên Phủ');
    final mine = (await routers.first.store.messages()).single;
    expect(mine.address, '475A Điện Biên Phủ');
  });

  test('demo SOS carry the demo place', () async {
    final c = AppController();
    addTearDown(c.stop);
    await c.start(simulated: true);
    expect(await c.send(MessageKind.sos, 'cứu', gps: true), isTrue);
    final sos = c.messages.firstWhere((m) => m.packet.kind == MessageKind.sos);
    expect(sos.address, AppController.demoPlace.address);
    expect(sos.accuracy, 8);
  });

  group('SQLite v6', () {
    sqfliteFfiInit();
    late Directory dir;
    late String file;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mesh_v6_');
      file = path.join(dir.path, databaseName);
    });
    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Windows may still hold the WAL file.
      }
    });

    Future<Packet> sos(MessageBody body) async => MeshRouter(
      identity: await Identity.create(),
      transport: SimNetwork().node('x'),
      store: MemoryStore(),
      name: 'x',
    ).publish(MessageKind.sos, body);

    test('stores the address and the one looked up here', () async {
      final store = await SqliteStore.open(
        factory: databaseFactoryFfi,
        file: file,
      );
      addTearDown(store.close);
      final p = await sos(MessageBody('x', latitude: 1, longitude: 2));
      await store.save(
        StoredMessage(p, 'a', 'x', latitude: 1, longitude: 2, accuracy: 30),
      );
      final before = await store.changes(-1);
      await store.saveLookedUpAddress(p.messageId, 'Chợ Bến Thành');
      final after = await store.changes(before.revision);
      expect(after.messages.single.lookedUpAddress, 'Chợ Bến Thành');
      expect(after.messages.single.address, isNull);
      expect(after.messages.single.placeName, 'Chợ Bến Thành');
      expect(after.messages.single.accuracy, 30);
    });

    test('a v5 database upgrades and keeps its messages', () async {
      final old = await openMeshDatabase(
        factory: databaseFactoryFfi,
        file: file,
        version: 5,
        singleInstance: false,
      );
      final p = await sos(MessageBody('cũ', latitude: 1, longitude: 2));
      await old.insert('messages', {
        'id': p.messageId,
        'bytes': p.encode(),
        'sender': 'a',
        'text': 'cũ',
        'outgoing': 0,
        'lat': 1.0,
        'lon': 2.0,
        'created': p.timestamp,
        'rev': 1,
      });
      await old.close();
      final store = await SqliteStore.open(
        factory: databaseFactoryFfi,
        file: file,
      );
      addTearDown(store.close);
      expect(await store.db.getVersion(), schemaVersion);
      final m = (await store.messages()).single;
      expect(
        (m.text, m.latitude, m.address, m.lookedUpAddress),
        ('cũ', 1.0, null, null),
      );
    });
  });

  testWidgets('location card says whose address it shows', (t) async {
    final p = await MeshRouter(
      identity: await Identity.create(),
      transport: SimNetwork().node('x'),
      store: MemoryStore(),
      name: 'x',
    ).publish(MessageKind.sos, MessageBody('x', latitude: 10.8, longitude: 1));
    Future<void> show(StoredMessage m) => t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: LocationCard(m)),
      ),
    );
    final m = StoredMessage(p, 'a', 'x', latitude: 10.8, longitude: 1);
    await show(m);
    expect(find.text('10.800000, 1.000000'), findsOneWidget);
    expect(find.textContaining('sẽ tự tra'), findsOneWidget);
    m.lookedUpAddress = 'Chợ Bến Thành';
    await show(m);
    await t.pump();
    expect(find.text('Chợ Bến Thành'), findsOneWidget);
    expect(find.textContaining('do máy này tra'), findsOneWidget);
    expect(find.text('Chỉ đường'), findsOneWidget);
    expect(find.text('Sao chép'), findsOneWidget);
  });
}
