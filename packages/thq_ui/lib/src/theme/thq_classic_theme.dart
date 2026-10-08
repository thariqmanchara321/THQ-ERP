import 'package:flutter/material.dart';

import 'thq_design_profile.dart';
import 'thq_classic_desktop_overlay.dart';

/// Original pre-V7 desktop styles from Git checkpoint 0c668648.
/// Only presentation is restored; all current transaction code stays active.
abstract final class ThqClassicTheme {
  static ThemeData desktop(UiDesignProfile profile) {
    final base = _base(profile);
    if (profile.appKey == 'pos') {
      return ThqClassicPosOverlay.apply(
        base.copyWith(
          canvasColor: profile.surface,
          dropdownMenuTheme: DropdownMenuThemeData(
            textStyle: TextStyle(
              color: profile.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            menuStyle: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(profile.surface),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
            ),
          ),
          segmentedButtonTheme: SegmentedButtonThemeData(
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? base.colorScheme.onPrimary
                    : profile.textPrimary,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? profile.primary
                    : profile.surface,
              ),
              side: WidgetStatePropertyAll(BorderSide(color: profile.border)),
            ),
          ),
          popupMenuTheme: base.popupMenuTheme.copyWith(
            textStyle: TextStyle(color: profile.textPrimary),
          ),
        ),
        profile,
      );
    }
    if (profile.appKey == 'admin') return base;
    return ThqClassicClientOverlay.apply(base, profile);
  }

  static ThemeData _base(UiDesignProfile profile) {
    final primary = profile.primary;
    final secondary = profile.secondary;
    final accent = profile.accent;
    final surface = profile.surface;
    final sidebar = profile.sidebar;
    final danger = profile.danger;
    final border = profile.border;
    final textPrimary = profile.textPrimary;
    final textSecondary = profile.textSecondary;
    final background = profile.background;
    final radius = profile.radius;
    final compact = profile.compact;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: primary,
          secondary: secondary,
          tertiary: accent,
          surface: surface,
          error: danger,
          outline: border,
          outlineVariant: border,
          onSurface: textPrimary,
          onSurfaceVariant: textSecondary,
          surfaceContainerLowest: surface,
          surfaceContainerLow: Color.alphaBlend(
            primary.withValues(alpha: 0.025),
            surface,
          ),
          surfaceContainer: Color.alphaBlend(
            primary.withValues(alpha: 0.045),
            surface,
          ),
          surfaceContainerHigh: Color.alphaBlend(
            primary.withValues(alpha: 0.07),
            surface,
          ),
          surfaceContainerHighest: Color.alphaBlend(
            primary.withValues(alpha: 0.10),
            surface,
          ),
        );
    final r = radius;
    return ThemeData(
      useMaterial3: true,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: null,
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: textPrimary,
        ),
        displayMedium: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          color: textPrimary,
        ),
        displaySmall: TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w800,
          color: textPrimary,
        ),
        headlineLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          color: textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: 14, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 12.5, color: textPrimary),
        bodySmall: TextStyle(fontSize: 10.5, color: textSecondary),
        labelLarge: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        labelMedium: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        labelSmall: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      dividerColor: border,
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        labelStyle: TextStyle(color: textSecondary),
        floatingLabelStyle: TextStyle(
          color: primary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(color: textSecondary),
        errorStyle: TextStyle(
          color: danger,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        fillColor: surface,
        isDense: compact,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: compact ? 10 : 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r * 0.72),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r * 0.72),
          borderSide: BorderSide(color: border),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r * 0.72),
          borderSide: BorderSide(color: border.withValues(alpha: 0.72)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r * 0.72),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r * 0.72),
          borderSide: BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r * 0.72),
          borderSide: BorderSide(color: danger, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(0, compact ? 38 : 42),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r * 0.72),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: Size(0, compact ? 38 : 42),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r * 0.72),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: Size(0, compact ? 34 : 38),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r * 0.60),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: Color.alphaBlend(
          primary.withValues(alpha: 0.14),
          surface,
        ),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r * 0.60),
        ),
        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
        secondaryLabelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textSecondary),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: border, width: 1.2),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return border.withValues(alpha: 0.55);
          }
          if (states.contains(WidgetState.selected)) return primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return textSecondary.withValues(alpha: 0.45);
          }
          if (states.contains(WidgetState.selected)) return primary;
          return textSecondary;
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return textSecondary.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return surface;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return border.withValues(alpha: 0.55);
          }
          if (states.contains(WidgetState.selected)) {
            return primary.withValues(alpha: 0.92);
          }
          return border;
        }),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r * 0.72),
          side: BorderSide(color: border),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(999),
        thickness: const WidgetStatePropertyAll(6),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return textSecondary.withValues(alpha: 0.70);
          }
          return textSecondary.withValues(alpha: 0.38);
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: sidebar,
        indicatorColor: Color.alphaBlend(
          primary.withValues(alpha: 0.14),
          surface,
        ),
        selectedIconTheme: IconThemeData(color: primary, size: 21),
        unselectedIconTheme: IconThemeData(color: textSecondary, size: 20),
        selectedLabelTextStyle: TextStyle(
          color: primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textSecondary,
          minimumSize: Size.square(compact ? 34 : 38),
          padding: const EdgeInsets.all(7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r * 0.58),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        showDuration: const Duration(seconds: 3),
        decoration: BoxDecoration(
          color: textPrimary,
          borderRadius: BorderRadius.circular(r * 0.50),
        ),
        textStyle: TextStyle(
          color: surface,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shadowColor: textPrimary.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r + 2),
          side: BorderSide(color: border),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        dataTextStyle: TextStyle(color: textPrimary),
        headingRowColor: WidgetStatePropertyAll(
          Color.alphaBlend(primary.withValues(alpha: 0.035), surface),
        ),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Color.alphaBlend(primary.withValues(alpha: 0.10), surface);
          }
          if (states.contains(WidgetState.hovered)) {
            return Color.alphaBlend(primary.withValues(alpha: 0.035), surface);
          }
          return null;
        }),
        dividerThickness: 0.8,
        headingRowHeight: compact ? 38 : 44,
        dataRowMinHeight: compact ? 38 : 44,
        dataRowMaxHeight: compact ? 46 : 54,
        horizontalMargin: compact ? 10 : 14,
        columnSpacing: compact ? 14 : 20,
      ),
      listTileTheme: ListTileThemeData(
        dense: compact,
        textColor: textPrimary,
        iconColor: textSecondary,
        selectedColor: primary,
        selectedTileColor: Color.alphaBlend(
          primary.withValues(alpha: 0.075),
          surface,
        ),
        minVerticalPadding: compact ? 3 : 6,
        horizontalTitleGap: compact ? 8 : 12,
        contentPadding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r * 0.60),
        ),
      ),
    );
  }
}
