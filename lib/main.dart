import 'dart:async';

import 'package:flutter/material.dart';

import 'account/account_controller.dart';
import 'account/backend.dart';
import 'account/outbox.dart';
import 'account/supabase_backend.dart';
import 'app/settings.dart';
import 'app/storage.dart';
import 'messaging/settings_store.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';
import 'ui/welcome_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppSettings settings;
  OutboxStore outbox;
  try {
    final notice = await prepareAppDatabase();
    final store = await SqliteSettingsStore.open();
    settings = await AppSettings.load(store)
      ..launchNotice = notice;
    outbox = SqliteOutboxStore(store.db);
  } catch (e) {
    // The app must still open in an emergency; settings just won't persist.
    debugPrint('Không mở được cài đặt: $e');
    settings = AppSettings.memory(onboarded: false);
    outbox = MemoryOutboxStore();
  }
  // Never blocks on the network: an offline phone opens in guest mode or
  // with the session it saved last time.
  final backend = await connectBackend(BackendConfig.fromEnvironment, settings);
  final account = AccountController(
    backend: backend,
    settings: settings,
    outbox: outbox,
  );
  unawaited(account.start());
  runApp(EmergencyApp(settings: settings, account: account));
}

class EmergencyApp extends StatefulWidget {
  /// Null uses settings that are not persisted (tests).
  final AppSettings? settings;

  /// Null means no account server (tests, or a build without one).
  final AccountController? account;
  const EmergencyApp({super.key, this.settings, this.account});
  @override
  State<EmergencyApp> createState() => _EmergencyAppState();
}

class _EmergencyAppState extends State<EmergencyApp> {
  late final AppSettings settings = widget.settings ?? AppSettings.memory();
  late final AccountController account =
      widget.account ??
      AccountController(backend: const OfflineBackend(), settings: settings);
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => MaterialApp(
      title: 'SOS Mesh',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      home: settings.onboarded
          ? HomePage(settings: settings, account: account)
          : WelcomePage(
              account: account,
              onDone: () => settings.onboarded = true,
            ),
    ),
  );
}
