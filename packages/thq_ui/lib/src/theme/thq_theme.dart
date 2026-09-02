import 'package:flutter/material.dart';

import '../foundations/thq_tokens.dart';
import '../foundations/thq_typography.dart';
import 'thq_semantic_colors.dart';

abstract final class ThqTheme {
  // Aurora-compatible dark foundation used by the existing Client theme.
  static const _darkBackground = Color(0xFF11161D);
  static const _darkSurface = Color(0xFF171E27);
  static const _darkSurfaceAlt = Color(0xFF1D2632);
  static const _darkBorder = Color(0xFF2B3747);
  static const _accent = Color(0xFF70C1B3);

  // Existing warm-paper family retained as the light foundation.
  static const _lightBackground = Color(0xFFF3EFEB);
  static const _lightSurface = Color(0xFFFFFBF7);
  static const _lightSurfaceAlt = Color(0xFFF7F1EB);
  static const _lightBorder = Color(0xFFD9CEC3);
  static const _lightAccent = Color(0xFF8D6044);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? _darkBackground : _lightBackground;
    final surface = dark ? _darkSurface : _lightSurface;
    final surfaceAlt = dark ? _darkSurfaceAlt : _lightSurfaceAlt;
    final border = dark ? _darkBorder : _lightBorder;
    final accent = dark ? _accent : _lightAccent;
    final textTheme = ThqTypography.textTheme(brightness);
    final semantic = dark ? ThqSemanticColors.dark : ThqSemanticColors.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: surface,
    ).copyWith(
      primary: accent,
      surface: surface,
      error: semantic.critical,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
      borderSide: BorderSide(color: border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: border,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[semantic],
      visualDensity: VisualDensity.compact,
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ThqTokens.space12,
          vertical: ThqTokens.space10,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, ThqTokens.controlStandard),
          padding: const EdgeInsets.symmetric(horizontal: ThqTokens.space16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, ThqTokens.controlStandard),
          padding: const EdgeInsets.symmetric(horizontal: ThqTokens.space16),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, ThqTokens.controlStandard),
          padding: const EdgeInsets.symmetric(horizontal: ThqTokens.space12),
          textStyle: textTheme.labelLarge,
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowHeight: ThqTokens.tableHeader,
        dataRowMinHeight: ThqTokens.tableRowCompact,
        dataRowMaxHeight: ThqTokens.tableRowStandard,
        horizontalMargin: ThqTokens.space12,
        columnSpacing: ThqTokens.space16,
        dividerThickness: 0.6,
        headingTextStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThqTokens.radiusLarge),
          side: BorderSide(color: border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        showDuration: const Duration(seconds: 3),
        decoration: BoxDecoration(
          color: surfaceAlt,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
        ),
        textStyle: textTheme.bodySmall,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    );
  }
}
