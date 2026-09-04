import 'package:flutter/material.dart';

import 'v43_theme.dart';

/// THQ ERP v6 POS visual overlay.
///
/// Tenant Design Studio colours remain authoritative. This layer only
/// standardizes POS density, geometry and transient UI so billing stays fast,
/// readable and compact without changing any business logic.
abstract final class PosV600Theme {
  static ThemeData apply(ThemeData base, UiDesignProfile profile) {
    final scheme = base.colorScheme;
    final radius = profile.radius.clamp(8.0, 13.0).toDouble();
    final canvas = Color.alphaBlend(
      profile.primary.withValues(alpha: .022),
      profile.background,
    );

    final text = base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w900,
        letterSpacing: -.35,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        letterSpacing: -.25,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 14),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 13),
      bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 11.5),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(fontSize: 11),
    );

    return base.copyWith(
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: canvas,
      textTheme: text,
      dividerColor: profile.border,
      dividerTheme: DividerThemeData(
        color: profile.border,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        toolbarHeight: 46,
        backgroundColor: profile.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: profile.border),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        isDense: true,
        filled: true,
        fillColor: profile.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: profile.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: profile.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: profile.primary, width: 1.35),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          side: BorderSide(color: profile.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(34, 34),
          maximumSize: const Size(38, 38),
          padding: const EdgeInsets.all(7),
        ),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        dense: true,
        minVerticalPadding: 2,
        horizontalTitleGap: 8,
        contentPadding: const EdgeInsets.symmetric(horizontal: 9),
        titleTextStyle: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      chipTheme: base.chipTheme.copyWith(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        labelStyle: const TextStyle(fontSize: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: BorderSide(color: profile.border),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      scrollbarTheme: base.scrollbarTheme.copyWith(
        thickness: const WidgetStatePropertyAll(5),
        radius: const Radius.circular(999),
      ),
      tooltipTheme: base.tooltipTheme.copyWith(
        waitDuration: const Duration(milliseconds: 300),
        showDuration: const Duration(seconds: 2),
      ),
    );
  }
}
