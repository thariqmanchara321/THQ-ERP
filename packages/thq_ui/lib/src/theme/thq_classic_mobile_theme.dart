import 'package:flutter/material.dart';

import '../foundations/thq_tokens.dart';

/// Shared mobile visual system for THQ Client Mobile and THQ Mobile POS.
///
/// Keep transaction screens free to add domain-specific emphasis while all
/// common chrome, fields, cards, navigation and messages inherit this base.
abstract final class ThqClassicMobileTheme {
  static ThemeData client() => _build(
    primary: const Color(0xFF635BFF),
    secondary: const Color(0xFF8B5CF6),
    tertiary: const Color(0xFF0EA5E9),
  );

  static ThemeData pos() => _build(
    primary: const Color(0xFF1769E0),
    secondary: const Color(0xFF6252D9),
    tertiary: const Color(0xFF0F9D73),
  );

  static ThemeData _build({
    required Color primary,
    required Color secondary,
    required Color tertiary,
  }) {
    const background = Color(0xFFF4F6FA);
    const surface = Colors.white;
    const surfaceAlt = Color(0xFFF8F9FC);
    const border = Color(0xFFE4E8F0);
    const ink = Color(0xFF162033);
    const muted = Color(0xFF667085);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
          surface: surface,
        ).copyWith(
          primary: primary,
          secondary: secondary,
          tertiary: tertiary,
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: muted,
          outline: border,
          outlineVariant: const Color(0xFFEDF0F5),
          surfaceContainerLowest: surface,
          surfaceContainerLow: surfaceAlt,
          surfaceContainer: const Color(0xFFF0F3F8),
        );

    OutlineInputBorder inputBorder(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 22,
          height: 1.16,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          height: 1.2,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          fontSize: 14.5,
          height: 1.25,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(fontSize: 14, height: 1.45),
        bodyMedium: TextStyle(fontSize: 13, height: 1.4),
        bodySmall: TextStyle(fontSize: 11.5, height: 1.35),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        labelMedium: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: const TextStyle(color: Color(0xFF98A2B3)),
        labelStyle: const TextStyle(color: muted, fontWeight: FontWeight.w600),
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: inputBorder(border),
        enabledBorder: inputBorder(border),
        disabledBorder: inputBorder(const Color(0xFFEEF0F4)),
        focusedBorder: inputBorder(primary, width: 1.6),
        errorBorder: inputBorder(scheme.error),
        focusedErrorBorder: inputBorder(scheme.error, width: 1.6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, ThqTokens.controlTouch),
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, ThqTokens.controlTouch),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primary.withValues(alpha: 0.11),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(size: 22, color: selected ? primary : muted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? primary : muted,
          );
        }),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 3,
        backgroundColor: ink,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    );
  }
}
