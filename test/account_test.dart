import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ble_emergency_app/account/account_controller.dart';
import 'package:ble_emergency_app/account/backend.dart';
import 'package:ble_emergency_app/account/outbox.dart';
import 'package:ble_emergency_app/app/controller.dart';
import 'package:ble_emergency_app/app/settings.dart';
import 'package:ble_emergency_app/core/packet.dart';
import 'package:ble_emergency_app/main.dart';
import 'package:ble_emergency_app/messaging/schema.dart';
import 'package:ble_emergency_app/messaging/store.dart';
import 'package:ble_emergency_app/ui/auth_page.dart';

/// In-memory stand-in for Supabase with switches for the failure modes.
class FakeBackend implements AccountBackend {
  final passwords = <String, String>{'an@example.com': 'matkhau123'};
  final profiles = <String, Profile>{};
  final activity = <Map<String, dynamic>>[];
  final sos = <Map<String, dynamic>>[];
  final devices = <String>[];
  final _changes = StreamController<AccountUser?>.broadcast();
  bool offline = false, forbidden = false, confirmEmail = false;
  AccountUser? _user;

  void _check() {
    if (offline) {
      throw const AccountException('Không có kết nối Internet.');
    }
    if (forbidden) {
      throw const AccountException('bị khóa', forbidden: true);
    }
  }

  @override
  bool get available => true;
  @override
  AccountUser? get currentUser => _user;
  @override
  Stream<AccountUser?> get userChanges => _changes.stream;

  @override
  Future<AccountUser> signIn(String email, String password) async {
    _check();
    if (passwords[email] != password) {
      throw const AccountException('Sai email hoặc mật khẩu.');
    }
    _user = AccountUser('uid-$email', email);
    profiles.putIfAbsent(
      _user!.id,
      () => Profile(id: _user!.id, email: email, displayName: 'An'),
    );
    return _user!;
  }

  @override
  Future<SignUpOutcome> signUp(String email, String password, String n) async {
    _check();
    passwords[email] = password;
    profiles['uid-$email'] = Profile(
      id: 'uid-$email',
      email: email,
      displayName: n,
    );
    if (confirmEmail) {
      return SignUpOutcome.confirmEmail;
    }
    _user = AccountUser('uid-$email', email);
    return SignUpOutcome.signedIn;
  }

  @override
  Future<void> signOut() async => _user = null;
  @override
  Future<void> sendResetCode(String email) async => _check();
  @override
  Future<void> resetPassword(String e, String c, String p) async {
    _check();
    passwords[e] = p;
    _user = AccountUser('uid-$e', e);
  }

  @override
  Future<Profile> profile() async {
    _check();
    return profiles[_user!.id]!;
  }

  @override
  Future<Profile> saveProfile(Profile p) async {
    _check();
    return profiles[_user!.id] = p;
  }

  @override
  Future<String> registerDevice({
    required String installId,
    required String model,
    required String platform,
    required String appVersion,
  }) async {
    _check();
    devices.add(installId);
    return 'device-1';
  }

  @override
  Future<void> insertActivity(List<Map<String, dynamic>> rows) async {
    _check();
    activity.addAll(rows.map((r) => {...r, 'user_id': _user!.id}));
  }

  @override
  Future<void> insertSos(List<Map<String, dynamic>> rows) async {
    _check();
    for (final r in rows) {
      if (!sos.any((s) => s['message_id'] == r['message_id'])) {
        sos.add({...r, 'user_id': _user!.id});
      }
    }
  }

  @override
  Future<List<ActivityEntry>> myActivity({int limit = 50}) async => [
    for (final a in activity.reversed.take(limit))
      ActivityEntry(
        a['action'] as String,
        Map<String, dynamic>.from(a['details'] as Map),
        DateTime.now(),
      ),
  ];
}

Future<StoredMessage> _sos() async {
  final c = AppController();
  await c.start(simulated: true);
  await c.send(MessageKind.sos, 'cứu', gps: true);
  final m = c.messages.firstWhere((m) => m.packet.kind == MessageKind.sos);
  await c.stop();
  return m;
}

/// [m] as another phone stores it after receiving it over the mesh.
StoredMessage _heard(StoredMessage m) => StoredMessage(
  m.packet,
  'abcdef0123456789',
  m.text,
  latitude: m.latitude,
  longitude: m.longitude,
  accuracy: m.accuracy,
);

void main() {
  late FakeBackend backend;
  late AccountController account;
  setUp(() {
    backend = FakeBackend();
    account = AccountController(
      backend: backend,
      settings: AppSettings.memory(),
    );
  });

  test('guests leave no activity behind', () async {
    await account.record('app_open');
    expect((account.outbox as MemoryOutboxStore).events, isEmpty);
    expect(backend.activity, isEmpty);
  });

  test('signing in logs it, registers the phone once and uploads', () async {
    expect(await account.signIn('an@example.com', 'sai'), contains('Sai'));
    expect(account.signedIn, isFalse);
    expect(await account.signIn('an@example.com', 'matkhau123'), isNull);
    await account.record('mesh_start', {'mode': 'ble'});
    await account.flush();
    expect(backend.activity.map((a) => a['action']), ['sign_in', 'mesh_start']);
    expect(backend.activity.every((a) => a['device_id'] == 'device-1'), isTrue);
    expect(backend.devices, [account.settings.installId]);
    expect(account.pending, 0);
    expect(account.profile!.displayName, 'An');
    // The mesh name follows the account while the user has not set one.
    expect(account.settings.name, 'An');
  });

  test('offline events wait and go up in order once online', () async {
    await account.signIn('an@example.com', 'matkhau123');
    await account.flush();
    backend.offline = true;
    await account.record('mesh_start');
    await account.record('mesh_stop');
    await account.flush();
    expect(account.pending, 2);
    backend.offline = false;
    await account.flush();
    expect(backend.activity.map((a) => a['action']), [
      'sign_in',
      'mesh_start',
      'mesh_stop',
    ]);
    expect(account.pending, 0);
  });

  test('a refused account stops uploading and keeps its events', () async {
    await account.signIn('an@example.com', 'matkhau123');
    await account.flush();
    backend.forbidden = true;
    await account.record('app_open');
    await account.flush();
    expect(account.blocked, isTrue);
    expect(account.pending, 1);
  });

  test('SOS: sent and bridged reports, logs without the message', () async {
    await account.signIn('an@example.com', 'matkhau123');
    final mine = await _sos();
    final other = await _sos();
    await account.recordSos(mine, demo: true, senderName: 'Thịnh');
    // The same SOS heard back over the mesh is still one report.
    await account.recordSos(_heard(mine), demo: true);
    await account.recordSos(_heard(other), demo: false, senderName: 'Lạ');
    await account.flush();
    expect(backend.sos, hasLength(2));
    final r = backend.sos.first;
    final bridged = backend.sos.last;
    expect(bridged['relayed'], isTrue);
    expect(bridged['sender_name'], 'Lạ');
    expect(bridged['origin_mesh_id'], 'abcdef0123456789');
    expect(r['relayed'], isFalse);
    expect(r['demo'], isTrue);
    expect(r['address'], AppController.demoPlace.address);
    expect(r['accuracy'], 8);
    expect(r['body'], 'cứu');
    final logs = backend.activity.where(
      (a) => (a['action'] as String).startsWith('sos'),
    );
    expect(logs.map((a) => a['action']), [
      'sos_sent',
      'sos_received',
      'sos_received',
    ]);
    for (final l in logs) {
      // Logs say that it happened, not what it said or where.
      expect(l['details'].containsKey('body'), isFalse);
      expect(l['details'].containsKey('latitude'), isFalse);
    }
  });

  test("one account's events never go up under another", () async {
    await account.signIn('an@example.com', 'matkhau123');
    await account.flush();
    backend.offline = true;
    await account.record('mesh_start');
    await account.signOut();
    backend.offline = false;
    backend.passwords['binh@example.com'] = 'matkhau456';
    await account.signIn('binh@example.com', 'matkhau456');
    await account.flush();
    final binh = backend.activity.where(
      (a) => a['user_id'] == 'uid-binh@example.com',
    );
    expect(binh.map((a) => a['action']), ['sign_in']);
    // An's offline events (and the sign-out) still wait for An.
    expect(
      (account.outbox as MemoryOutboxStore).events.map(
        (e) => (e.userId, e.payload['action']),
      ),
      [
        ('uid-an@example.com', 'mesh_start'),
        ('uid-an@example.com', 'sign_out'),
      ],
    );
  });

  test('profile edits log which fields changed, not their values', () async {
    await account.signIn('an@example.com', 'matkhau123');
    await account.flush();
    expect(
      await account.saveProfile(
        account.profile!.copyWith(displayName: 'An Nguyễn', bloodType: 'O+'),
      ),
      isNull,
    );
    await account.flush();
    final log = backend.activity.last;
    expect(log['action'], 'profile_updated');
    expect(log['details']['fields'], ['display_name', 'blood_type']);
    expect('$log', isNot(contains('O+')));
    expect(account.settings.name, 'An Nguyễn');
  });

  test('sign-up that needs email confirmation does not sign in', () async {
    backend.confirmEmail = true;
    SignUpOutcome? outcome;
    expect(
      await account.signUp(
        'moi@example.com',
        'matkhau123',
        'Mới',
        onOutcome: (o) => outcome = o,
      ),
      isNull,
    );
    expect(outcome, SignUpOutcome.confirmEmail);
    expect(account.signedIn, isFalse);
  });

  test('password rules', () {
    expect(validatePassword('ngan1'), isNotNull);
    expect(validatePassword('chukhongso'), isNotNull);
    expect(validatePassword('12345678'), isNotNull);
    expect(validatePassword('matkhau123'), isNull);
    expect(validateEmail('a@b'), isNotNull);
    expect(validateEmail(' an@example.com '), isNull);
  });

  test('the mesh controller reports activity for the log', () async {
    final seen = <String>[];
    StoredMessage? sos;
    final c = AppController()
      ..onActivity = (action, details, m) {
        seen.add(action);
        sos ??= m;
      };
    await c.start(simulated: true);
    await c.send(MessageKind.sos, 'cứu', gps: true);
    await c.send(MessageKind.safe, 'Tôi an toàn');
    await c.stopNetwork();
    expect(seen, ['mesh_start', 'sos_sent', 'safe_sent', 'mesh_stop']);
    expect(sos!.address, AppController.demoPlace.address);
  });

  group('SqliteOutboxStore', () {
    sqfliteFfiInit();
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('outbox_'));
    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Windows may still hold the WAL file.
      }
    });

    test('keeps events per user, oldest first, and SOS over logs', () async {
      final db = await openMeshDatabase(
        factory: databaseFactoryFfi,
        file: path.join(dir.path, databaseName),
        singleInstance: false,
      );
      addTearDown(db.close);
      final store = SqliteOutboxStore(db);
      OutboxEvent e(String user, String kind, int n) =>
          OutboxEvent(userId: user, kind: kind, payload: {'n': n}, created: n);
      await store.add(e('a', 'sos', 0));
      for (var i = 1; i <= maxOutbox + 5; i++) {
        await store.add(e('a', 'log', i));
      }
      await store.add(e('b', 'log', 99));
      expect(await store.count('a') + await store.count('b'), maxOutbox);
      final first = await store.pending('a', limit: 2);
      expect(first.first.kind, 'sos');
      expect(first.first.payload['n'], 0);
      await store.remove(first.map((e) => e.id!));
      expect(await store.count('b'), 1);
      expect((await store.pending('b')).single.payload['n'], 99);
    });
  });

  testWidgets('first launch: welcome, then straight in without an account', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final settings = AppSettings.memory(onboarded: false);
    await t.pumpWidget(
      EmergencyApp(
        settings: settings,
        account: AccountController(backend: backend, settings: settings),
      ),
    );
    expect(find.text('Kết nối khi mọi thứ gián đoạn'), findsOneWidget);
    await t.tap(find.text('Tiếp tục'));
    await t.pumpAndSettle();
    await t.tap(find.text('Tiếp tục'));
    await t.pumpAndSettle();
    expect(find.text('Đăng nhập / Đăng ký'), findsOneWidget);
    await t.tap(find.text('Dùng ngay không cần tài khoản'));
    await t.pumpAndSettle();
    expect(settings.onboarded, isTrue);
    expect(find.text('SOS MESH'), findsOneWidget);
    expect(find.text('Chế độ khách • SOS vẫn đầy đủ'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('sign in from the account tab shows the profile', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final settings = AppSettings.memory();
    final a = AccountController(backend: backend, settings: settings);
    await t.pumpWidget(EmergencyApp(settings: settings, account: a));
    await t.tap(find.text('Tài khoản'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await t.pumpAndSettle();
    expect(find.text('Nhập email hợp lệ'), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('auth-email')),
      'an@example.com',
    );
    await t.enterText(find.byKey(const ValueKey('auth-password')), 'sai');
    await t.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await t.pumpAndSettle();
    expect(find.text('Sai email hoặc mật khẩu.'), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('auth-password')),
      'matkhau123',
    );
    await t.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await t.pumpAndSettle();
    expect(find.text('an@example.com'), findsOneWidget);
    expect(find.text('Thông tin khẩn cấp'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Đăng xuất'), 200);
    expect(find.text('Đăng xuất'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
