import 'package:flutter/material.dart';

/// Brand colours that stay the same in light and dark mode.
const teal = Color(0xff0a7c7e),
    tealDark = Color(0xff075a5c),
    red = Color(0xffd62828);

/// Colours that change with the theme. Read them with `context.palette`.
@immutable
class Palette extends ThemeExtension<Palette> {
  final Color ink, muted, line, canvas, surface;
  final Color accent, accentSoft, danger, dangerSoft, warn, warnSoft, info;

  /// Background of the user's own chat bubble; text on it is white.
  final Color bubbleOut;
  const Palette({
    required this.ink,
    required this.muted,
    required this.line,
    required this.canvas,
    required this.surface,
    required this.accent,
    required this.accentSoft,
    required this.danger,
    required this.dangerSoft,
    required this.warn,
    required this.warnSoft,
    required this.info,
    required this.bubbleOut,
  });

  static const light = Palette(
    ink: Color(0xff102a35),
    muted: Color(0xff5f747c),
    line: Color(0xffe2e9ea),
    canvas: Color(0xfff4f7f7),
    surface: Colors.white,
    accent: teal,
    accentSoft: Color(0xffe0f2f1),
    danger: red,
    dangerSoft: Color(0xfffdecec),
    warn: Color(0xff9a6412),
    warnSoft: Color(0xfffff4e0),
    info: Color(0xff3b5bdb),
    bubbleOut: teal,
  );

  static const dark = Palette(
    ink: Color(0xffe4eef0),
    muted: Color(0xff94a9b0),
    line: Color(0xff243840),
    canvas: Color(0xff0b1619),
    surface: Color(0xff13232a),
    accent: Color(0xff3cbcb8),
    accentSoft: Color(0xff123b3d),
    danger: Color(0xffff6b6b),
    dangerSoft: Color(0xff3b1a1c),
    warn: Color(0xffe8b45a),
    warnSoft: Color(0xff33280f),
    info: Color(0xff8ea2ff),
    bubbleOut: Color(0xff0e6668),
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) {
    if (other == null) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette(
      ink: mix(ink, other.ink),
      muted: mix(muted, other.muted),
      line: mix(line, other.line),
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      accent: mix(accent, other.accent),
      accentSoft: mix(accentSoft, other.accentSoft),
      danger: mix(danger, other.danger),
      dangerSoft: mix(dangerSoft, other.dangerSoft),
      warn: mix(warn, other.warn),
      warnSoft: mix(warnSoft, other.warnSoft),
      info: mix(info, other.info),
      bubbleOut: mix(bubbleOut, other.bubbleOut),
    );
  }
}

extension PaletteOf on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
}

ThemeData buildTheme([Brightness brightness = Brightness.light]) {
  final dark = brightness == Brightness.dark;
  final p = dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: teal,
    brightness: brightness,
    primary: p.accent,
    onPrimary: dark ? const Color(0xff00201f) : Colors.white,
    error: p.danger,
    surface: p.surface,
    onSurface: p.ink,
  );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
  const label = TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Roboto',
    colorScheme: scheme,
    extensions: [p],
    scaffoldBackgroundColor: p.canvas,
    dividerColor: p.line,
    textTheme:
        (dark ? Typography.whiteMountainView : Typography.blackMountainView)
            .apply(bodyColor: p.ink, displayColor: p.ink),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border(p.line),
      enabledBorder: border(p.line),
      focusedBorder: border(p.accent, 1.5),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.line),
      ),
    ),
    listTileTheme: ListTileThemeData(
      subtitleTextStyle: TextStyle(color: p.muted, fontSize: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: rounded,
        textStyle: label.copyWith(fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: rounded,
        foregroundColor: p.ink,
        backgroundColor: p.surface,
        side: BorderSide(color: p.line),
        textStyle: label.copyWith(fontSize: 14),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.accentSoft,
      side: BorderSide(color: p.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: TextStyle(
        fontFamily: 'Roboto',
        color: p.ink,
        fontWeight: FontWeight.w600,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.accentSoft,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? p.accent : p.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? p.accent : p.muted,
        ),
      ),
    ),
  );
}
