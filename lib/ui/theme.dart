import 'package:flutter/material.dart';

const ink = Color(0xff102a35),
    muted = Color(0xff5f747c),
    line = Color(0xffe2e9ea),
    canvas = Color(0xfff4f7f7),
    teal = Color(0xff0a7c7e),
    tealDark = Color(0xff075a5c),
    tealSoft = Color(0xffe0f2f1),
    red = Color(0xffd62828),
    redSoft = Color(0xfffdecec),
    amber = Color(0xff9a6412),
    amberSoft = Color(0xfffff4e0);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: teal,
    primary: teal,
    error: red,
    surface: Colors.white,
  );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    dividerColor: line,
    textTheme: Typography.blackMountainView.apply(
      bodyColor: ink,
      displayColor: ink,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: teal, width: 1.5),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: rounded,
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: rounded,
        foregroundColor: ink,
        backgroundColor: Colors.white,
        side: const BorderSide(color: line),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: tealSoft,
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: const TextStyle(
        fontFamily: 'Roboto',
        color: ink,
        fontWeight: FontWeight.w600,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: tealSoft,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? teal : muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? teal : muted,
        ),
      ),
    ),
  );
}
