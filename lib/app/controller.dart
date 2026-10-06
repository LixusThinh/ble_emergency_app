import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/identity.dart';
import '../core/packet.dart';
import '../messaging/sqlite_store.dart';
import '../messaging/store.dart';
import '../routing/router.dart';
import '../simulator/network.dart';
import '../transport/android_ble.dart';

class AppController extends ChangeNotifier {
  MeshRouter? router;
  List<StoredMessage> messages = [];
  bool busy = false, demo = false;
  String? error;
  String name = 'Người dùng';
  SimNetwork? _network;
  final List<MeshRouter> _demoRouters = [];
  StreamSubscription<void>? _updates;
  Future<void> _refreshWork = Future.value();
  Future<void> _refresh() {
    _refreshWork = _refreshWork
        .then((_) async {
          final current = router;
          if (current != null) {
            messages = await current.store.messages();
            error = current.lastError ?? error;
          }
          notifyListeners();
        })
        .catchError((Object e) {
          error = '$e';
          notifyListeners();
        });
    return _refreshWork;
  }

  Future<void> start({required bool simulated}) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await stop();
      demo = simulated;
      if (simulated) {
        _network = SimNetwork();
        for (final label in ['Bạn', 'Trạm tiếp sức', 'Đội cứu hộ']) {
          final r = MeshRouter(
            identity: await Identity.create(),
            transport: _network!.node(label),
            store: MemoryStore(),
            name: label,
          );
          _demoRouters.add(r);
          await r.start();
        }
        router = _demoRouters.first;
        _updates = router!.updates.listen((_) {
          unawaited(_refresh());
        });
        _network!.connect('Bạn', 'Trạm tiếp sức', mtu: 23);
        _network!.connect('Trạm tiếp sức', 'Đội cứu hộ', mtu: 185);
        await _network!.drain(_demoRouters);
        await _demoRouters.last.publish(
          MessageKind.chat,
          MessageBody(
            'Đội cứu hộ đã vào mạng. Tin nhắn này đi qua trạm tiếp sức đến bạn.',
          ),
        );
        await _network!.drain(_demoRouters);
      } else {
        if (!Platform.isAndroid) {
          throw UnsupportedError('Chế độ BLE cần điện thoại Android');
        }
        final identity = await Identity.create(
          saved: await AndroidBleTransport.loadIdentity(),
        );
        await AndroidBleTransport.saveIdentity(await identity.export());
        router = MeshRouter(
          identity: identity,
          transport: AndroidBleTransport(),
          store: await SqliteStore.open(),
          name: name.trim().isEmpty ? 'Người dùng' : name.trim(),
        );
        _updates = router!.updates.listen((_) {
          unawaited(_refresh());
        });
        await router!.start();
      }
      await _refresh();
    } catch (e) {
      error = '$e';
      await stop();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> send(
    MessageKind kind,
    String text, {
    Contact? recipient,
    bool gps = false,
  }) async {
    final r = router;
    if (r == null || !r.running) {
      error = 'Bật mạng BLE hoặc mô phỏng trước khi gửi';
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      double? lat, lon;
      if (gps && !demo) {
        try {
          final location = await AndroidBleTransport.location();
          lat = (location?['latitude'] as num?)?.toDouble();
          lon = (location?['longitude'] as num?)?.toDouble();
        } catch (_) {
          error =
              'SOS đã gửi không kèm GPS: chưa có vị trí hoặc chưa cấp quyền.';
        }
      }
      await r.publish(
        kind,
        MessageBody(text, latitude: lat, longitude: lon),
        recipient: recipient,
      );
      if (demo) {
        await _network!.drain(_demoRouters);
        if (kind == MessageKind.sos) {
          await _demoRouters.last.publish(
            MessageKind.chat,
            MessageBody(
              'Đội cứu hộ đã nhận SOS của bạn qua 2 chặng. Đây là phản hồi mô phỏng.',
            ),
          );
          await _network!.drain(_demoRouters);
        }
      }
      await _refresh();
    } catch (e) {
      error = '$e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _updates?.cancel();
    _updates = null;
    await _refreshWork;
    final current = router;
    router = null;
    if (_demoRouters.isNotEmpty) {
      for (final r in _demoRouters) {
        await r.dispose();
      }
      _demoRouters.clear();
    } else {
      await current?.dispose();
    }
    _network = null;
    messages = [];
    notifyListeners();
  }
}
