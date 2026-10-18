import 'package:flutter/material.dart';

import 'ui/home_page.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EmergencyApp());
}

class EmergencyApp extends StatelessWidget {
  const EmergencyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SOS Mesh',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: const HomePage(),
  );
}
