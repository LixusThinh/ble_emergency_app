import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app/settings.dart';
import '../messaging/store.dart';
import 'backend.dart';
import 'outbox.dart';

/// Shown in the app and sent with each device registration.
const appVersion = '2.0.0';

/// Account state for the UI, and the activity log: events are written to
/// the phone first and uploaded whenever the user is signed in and online,
/// so nothing is lost to a dead network and nothing waits on it.
class AccountController extends ChangeNotifier {
  final AccountBackend backend;
  final OutboxStore outbox;
  final AppSettings settings;
  AccountController({
    required this.backend,
    required this.settings,
    OutboxStore? outbox,
  }) : outbox = outbox ?? MemoryOutboxStore();

  AccountUser? user;
  Profile? profile;
  bool busy = false;

  /// Set when the server refused this account (banned); uploads stop.
  bool blocked = false;

  /// Events recorded but not uploaded yet, for the account screen.
  int pending = 0;
  StreamSubscription<AccountUser?>? _changes;
  String? _deviceId;
  Future<void>? _flushing;
  bool _flushAgain = false;

  bool get available => backend.available;
  bool get signedIn => user != null;

  /// Picks up a session saved by an earlier launch.
  Future<void> start() async {
    user = backend.currentUser;
    _changes = backend.userChanges.listen((u) {
      if (u?.id != user?.id) {
        user = u;
        profile = null;
        _deviceId = null;
        blocked = false;
        notifyListeners();
        if (u != null) {
          unawaited(_afterSignIn());
        }
      }
    });
    if (user != null) {
      await record('app_open');
      unawaited(_afterSignIn());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _afterSignIn() async {
    await refreshProfile();
    await flush();
  }

  /// Runs [action] with [busy] set; returns its error message, or null.
  Future<String?> _run(Future<void> Function() action) async {
    busy = true;
    notifyListeners();
    try {
      await action();
      return null;
    } on AccountException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> signIn(String email, String password) => _run(() async {
    user = await backend.signIn(email, password);
    blocked = false;
    await record('sign_in', {'method': 'password'});
    await _afterSignIn();
  });

  /// Returns the error, or null; [onOutcome] says whether to confirm email.
  Future<String?> signUp(
    String email,
    String password,
    String displayName, {
    void Function(SignUpOutcome)? onOutcome,
  }) => _run(() async {
    final outcome = await backend.signUp(email, password, displayName);
    if (outcome == SignUpOutcome.signedIn) {
      user = backend.currentUser;
      await record('sign_up');
      await _afterSignIn();
    }
    onOutcome?.call(outcome);
  });

  Future<String?> signOut() => _run(() async {
    await record('sign_out');
    // Best effort: what cannot go now waits for the next sign-in.
    await flush().timeout(const Duration(seconds: 4), onTimeout: () {});
    await backend.signOut();
    user = null;
    profile = null;
    _deviceId = null;
    pending = 0;
  });

  Future<String?> sendResetCode(String email) =>
      _run(() => backend.sendResetCode(email));

  Future<String?> resetPassword(String email, String code, String password) =>
      _run(() async {
        await backend.resetPassword(email, code, password);
        user = backend.currentUser;
        await record('sign_in', {'method': 'reset_code'});
        await _afterSignIn();
      });

  Future<void> refreshProfile() async {
    if (user == null) {
      return;
    }
    try {
      profile = await backend.profile();
      blocked = profile!.banned;
      // The mesh name follows the account until the user picks another.
      if (settings.name.trim().isEmpty && profile!.displayName.isNotEmpty) {
        settings.name = profile!.displayName;
      }
    } on AccountException {
      // Offline: keep what we had.
    }
    notifyListeners();
  }

  Future<String?> saveProfile(Profile next) => _run(() async {
    final before = profile;
    profile = await backend.saveProfile(next);
    if (before != null && settings.name.trim() == before.displayName.trim()) {
      settings.name = profile!.displayName;
    }
    final a = before?.toUpdate() ?? const {}, b = next.toUpdate();
    // Which fields changed, never their values.
    await record('profile_updated', {
      'fields': [
        for (final k in b.keys)
          if (a[k] != b[k]) k,
      ],
    });
  });

  Future<List<ActivityEntry>> history() => backend.myActivity();

  /// Logs [action] for the signed-in user; does nothing for guests.
  Future<void> record(
    String action, [
    Map<String, Object?> details = const {},
  ]) => _enqueue('log', {
    'action': action,
    'details': details,
    'client_time': DateTime.now().toUtc().toIso8601String(),
  });

  /// Files an SOS report: one this phone sent, or one it received over the
  /// mesh (then the server learns of someone who may have no Internet).
  Future<void> recordSos(
    StoredMessage m, {
    required bool demo,
    String? senderName,
  }) async {
    final relayed = !m.outgoing;
    await record(relayed ? 'sos_received' : 'sos_sent', {
      'message_id': m.packet.messageId,
      'has_location': m.hasLocation,
      if (m.accuracy != null) 'accuracy_m': m.accuracy!.round(),
      'has_address': m.placeName != null,
      if (relayed) 'hops': m.packet.hops,
      if (demo) 'demo': true,
    });
    await _enqueue('sos', {
      'message_id': m.packet.messageId,
      'relayed': relayed,
      'demo': demo,
      'origin_mesh_id': m.senderId,
      'sender_name': ?senderName,
      'hops': m.packet.hops,
      'body': m.text,
      'latitude': m.latitude,
      'longitude': m.longitude,
      'accuracy': m.accuracy,
      'address': m.placeName,
      'sent_at': DateTime.fromMillisecondsSinceEpoch(m.packet.timestamp)
          .toUtc()
          .toIso8601String(),
    });
  }

  Future<void> _enqueue(String kind, Map<String, dynamic> payload) async {
    final u = user;
    if (u == null || !backend.available) {
      return;
    }
    try {
      await outbox.add(
        OutboxEvent(
          userId: u.id,
          kind: kind,
          payload: payload,
          created: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      debugPrint('Không ghi được nhật ký: $e');
      return;
    }
    unawaited(flush());
  }

  /// Uploads waiting events, 50 at a time, until none are left or the
  /// network fails. Safe to call any time; concurrent calls share one run.
  Future<void> flush() {
    final running = _flushing;
    if (running != null) {
      _flushAgain = true;
      return running;
    }
    late final Future<void> run;
    run = _flushLoop().whenComplete(() {
      if (identical(_flushing, run)) {
        _flushing = null;
      }
    });
    return _flushing = run;
  }

  Future<void> _flushLoop() async {
    do {
      _flushAgain = false;
      final u = user;
      if (u == null || !backend.available || blocked) {
        return;
      }
      try {
        _deviceId ??= await backend.registerDevice(
          installId: settings.installId,
          model: Platform.operatingSystemVersion,
          platform: Platform.operatingSystem,
          appVersion: appVersion,
        );
        while (true) {
          final batch = await outbox.pending(u.id);
          if (batch.isEmpty || user?.id != u.id) {
            break;
          }
          final logs = [
            for (final e in batch)
              if (e.kind == 'log') {...e.payload, 'device_id': _deviceId},
          ];
          final sos = [
            for (final e in batch)
              if (e.kind == 'sos') {...e.payload, 'device_id': _deviceId},
          ];
          if (sos.isNotEmpty) {
            await backend.insertSos(sos);
          }
          if (logs.isNotEmpty) {
            await backend.insertActivity(logs);
          }
          await outbox.remove(batch.map((e) => e.id!));
        }
      } on AccountException catch (e) {
        if (e.forbidden) {
          blocked = true;
        }
        _flushAgain = false;
      } catch (e) {
        debugPrint('Không đẩy được nhật ký: $e');
        _flushAgain = false;
      }
      try {
        pending = await outbox.count(u.id);
      } catch (_) {}
      notifyListeners();
    } while (_flushAgain);
  }
}
