import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/crypto_worker.dart';
import '../core/identity.dart';
import '../core/packet.dart';
import '../messaging/sqlite_store.dart';
import '../messaging/store.dart';
import '../routing/router.dart';
import '../simulator/network.dart';
import '../transport/android_ble.dart';
import 'settings.dart';

class AppController extends ChangeNotifier {
  MeshRouter? router;
  List<StoredMessage> messages = [];
  bool busy = false, demo = false;
  String? error;
  final AppSettings settings;
  AppController({AppSettings? settings})
    : settings = settings ?? AppSettings.memory();

  /// Name shown to other phones; falls back when the user left it empty.
  String get name =>
      settings.name.trim().isEmpty ? 'Người dùng' : settings.name.trim();

  /// Incoming SOS that arrived after the network started; the UI pops each one.
  final List<StoredMessage> sosAlerts = [];
  bool _primed = false;
  SimNetwork? _network;
  final List<MeshRouter> _demoRouters = [];
  StreamSubscription<void>? _updates;

  /// Spawned on the first BLE start and kept for the life of the app.
  CryptoWorker? _worker;
  bool _workerFailed = false;
  Future<CryptoWorker?> _cryptoWorker() async {
    if (_worker == null && !_workerFailed) {
      try {
        _worker = await CryptoWorker.spawn();
      } catch (e) {
        // Verifying on this isolate is slower but still correct.
        _workerFailed = true;
        debugPrint('Không tạo được isolate kiểm chữ ký: $e');
      }
    }
    return _worker;
  }

  /// [messages] by id, and the store revision they reflect.
  final Map<String, StoredMessage> _byId = {};
  int _revision = -1;

  /// The refresh running now, and whether another update arrived meanwhile.
  Future<void>? _refreshing;
  bool _refreshAgain = false;

  /// Store reads so far, and messages they returned; for the tests and the
  /// performance probe.
  @visibleForTesting
  int refreshes = 0, loaded = 0;

  @visibleForTesting
  Future<void> refresh() => _refresh();

  /// Completes when the router is idle and the list reflects it.
  @visibleForTesting
  Future<void> get settled async {
    await router?.idle;
    await _refreshing;
  }

  /// Brings [messages] up to date with the store.
  ///
  /// A burst of router updates costs one read for the update that starts it
  /// and at most one more for everything that arrives while it runs, and each
  /// read returns only messages that changed since the previous one.
  Future<void> _refresh() {
    final running = _refreshing;
    if (running != null) {
      _refreshAgain = true;
      return running;
    }
    late final Future<void> run;
    run = _refreshLoop().whenComplete(() {
      if (identical(_refreshing, run)) {
        _refreshing = null;
      }
    });
    return _refreshing = run;
  }

  Future<void> _refreshLoop() async {
    do {
      _refreshAgain = false;
      try {
        final current = router;
        if (current != null) {
          refreshes++;
          final changed = await current.store.changes(_revision);
          if (!identical(router, current)) {
            return; // Stopped or restarted while reading.
          }
          _revision = changed.revision;
          loaded += changed.messages.length;
          _merge(changed.messages);
          // Take the router's error once so a dismissed banner stays dismissed.
          error = current.lastError ?? error;
          current.lastError = null;
        }
      } catch (e) {
        error = '$e';
      }
      notifyListeners();
    } while (_refreshAgain);
  }

  void _merge(List<StoredMessage> changed) {
    if (changed.isEmpty) {
      return;
    }
    for (final m in changed) {
      final isNew = _byId[m.packet.messageId] == null;
      _byId[m.packet.messageId] = m;
      if (isNew && _primed && !m.outgoing && m.packet.kind == MessageKind.sos) {
        sosAlerts.add(m);
      }
    }
    final all = _byId.values.toList()
      ..sort((a, b) => b.packet.timestamp.compareTo(a.packet.timestamp));
    // Same cap as the store, so both drop the same oldest messages.
    for (final m in all.skip(maxMessages)) {
      _byId.remove(m.packet.messageId);
    }
    messages = all.length > maxMessages ? all.sublist(0, maxMessages) : all;
  }

  void dismissError() {
    error = null;
    notifyListeners();
  }

  Future<void> start({required bool simulated}) async {
    busy = true;
    error = null;
    String? warning;
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
        Identity identity;
        try {
          identity = await Identity.create(
            saved: await AndroidBleTransport.loadIdentity(),
          );
        } catch (_) {
          // Keystore key lost or saved seeds unreadable: start with a new ID
          // instead of leaving BLE unusable.
          identity = await Identity.create();
          warning = 'Không đọc được danh tính đã lưu nên đã tạo ID mới. Thiết bị khác sẽ thấy bạn như một người mới.';
        }
        await AndroidBleTransport.saveIdentity(await identity.export());
        router = MeshRouter(
          identity: identity,
          transport: AndroidBleTransport(),
          store: await SqliteStore.open(),
          name: name,
          verifier: (await _cryptoWorker())?.verify,
        );
        _updates = router!.updates.listen((_) {
          unawaited(_refresh());
        });
        await router!.start();
      }
      await _refresh();
      // Messages already stored before this start are history, not alerts.
      _primed = true;
      error = warning ?? error;
    } catch (e) {
      error = '$e';
      await stop();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Returns whether the message was published; [error] may still carry a
  /// warning (an SOS sent without GPS) when it was.
  Future<bool> send(
    MessageKind kind,
    String text, {
    Contact? recipient,
    bool gps = false,
  }) async {
    final r = router;
    if (r == null || !r.running) {
      error = 'Bật mạng BLE hoặc mô phỏng trước khi gửi';
      notifyListeners();
      return false;
    }
    var published = false;
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
      published = true;
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
    return published;
  }

  Future<void> stop() async {
    await _updates?.cancel();
    _updates = null;
    await _refreshing;
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
    _byId.clear();
    _revision = -1;
    _primed = false;
    sosAlerts.clear();
    notifyListeners();
  }
}
