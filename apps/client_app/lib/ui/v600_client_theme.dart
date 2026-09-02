import 'package:flutter/material.dart';

import 'v43_theme.dart';

/// v6 Client visual overlay.
///
/// The tenant-selected [UiDesignProfile] still owns brand/accent colors.
/// This layer only normalizes density, geometry, typography and component
/// behavior so the Client has one coherent modern ERP visual language.
abstract final class ClientV600Theme {
  static ThemeData apply(ThemeData base, UiDesignProfile profile) {
    final scheme = base.colorScheme;
    final radius = profile.radius.clamp(8.0, 14.0).toDouble();
    final canvas = Color.alphaBlend(
      profile.primary.withValues(alpha: .025),
      profile.background,
    );

    final compactText = base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -.35,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        letterSpacing: -.25,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -.15,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 13),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 12),
      bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 10.5),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(fontSize: 10),
    );

    return base.copyWith(
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: canvas,
      textTheme: compactText,
      dividerColor: profile.border,
      dividerTheme: DividerThemeData(color: profile.border, thickness: 1),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: profile.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: compactText.titleMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
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
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          side: BorderSide(color: profile.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          textStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        dense: true,
        minVerticalPadding: 2,
        horizontalTitleGap: 8,
        contentPadding: const EdgeInsets.symmetric(horizontal: 9),
        titleTextStyle: compactText.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: BorderSide(color: profile.border),
        ),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        width: 380,
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      scrollbarTheme: base.scrollbarTheme.copyWith(
        thickness: const WidgetStatePropertyAll(5),
        radius: const Radius.circular(999),
      ),
      tooltipTheme: base.tooltipTheme.copyWith(
        waitDuration: const Duration(milliseconds: 350),
        showDuration: const Duration(seconds: 2),
      ),
    );
  }
}