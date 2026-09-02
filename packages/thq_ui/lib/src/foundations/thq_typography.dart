
import 'package:flutter/material.dart';

abstract final class ThqTypography {
  static TextTheme textTheme(Brightness brightness) {
    final primary = brightness == Brightness.dark
        ? const Color(0xFFE6EDF5)
        : const Color(0xFF2C2623);
    final secondary = brightness == Brightness.dark
        ? const Color(0xFFB9C4D1)
        : const Color(0xFF6D625C);

    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 30,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: TextStyle(fontSize: 14, height: 1.35, color: primary),
      bodyMedium: TextStyle(fontSize: 13, height: 1.35, color: primary),
      bodySmall: TextStyle(fontSize: 12, height: 1.3, color: secondary),
      labelLarge: TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: secondary,
      ),
    );
  }

  static TextStyle monetary(BuildContext context, {bool emphasized = false}) {
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return base.copyWith(
      fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }
}
