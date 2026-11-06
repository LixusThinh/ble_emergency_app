import 'package:flutter/material.dart';

import 'app/settings.dart';
import 'app/storage.dart';
import 'messaging/settings_store.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppSettings settings;
  try {
    final notice = await prepareAppDatabase();
    settings = await AppSettings.load(await SqliteSettingsStore.open())
      ..launchNotice = notice;
  } catch (e) {
    // The app must still open in an emergency; settings just won't persist.
    debugPrint('Không mở được cài đặt: $e');
    settings = AppSettings.memory();
  }
  runApp(EmergencyApp(settings: settings));
}

class EmergencyApp extends StatefulWidget {
  /// Null uses settings that are not persisted (tests).
  final AppSettings? settings;
  const EmergencyApp({super.key, this.settings});
  @override
  State<EmergencyApp> createState() => _EmergencyAppState();
}

class _EmergencyAppState extends State<EmergencyApp> {
  late final AppSettings settings = widget.settings ?? AppSettings.memory();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => MaterialApp(
      title: 'SOS Mesh',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      home: HomePage(settings: settings),
    ),
  );
}
