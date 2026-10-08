import 'package:flutter/material.dart';

import 'thq_semantic_colors.dart';

/// Approved native palette from the THQ version 7 design reference.
abstract final class ThqPalette {
  static const background = Color(0xFF0A1725);
  static const sidebar = Color(0xFF0E2031);
  static const panel = Color(0xFF112438);
  static const raised = Color(0xFF172E43);
  static const border = Color(0xFF274057);
  static const text = Color(0xFFEDF5FA);
  static const muted = Color(0xFF9CB2C4);
  static const teal = Color(0xFF22D3B2);
  static const blue = Color(0xFF78B4FF);
  static const warning = Color(0xFFF4CA7B);
  static const error = Color(0xFFFF9A9E);
  static const ink = Color(0xFF08251F);
  static const selected = Color(0xFF123E40);
}

abstract final class ThqV7Theme {
  static ThemeData desktop() => build();
  static ThemeData mobile() => build(touch: true);

  /// Custom Design Studio palettes remain supported, including light themes.
  static ThemeData build({
    bool touch = false,
    Color primary = ThqPalette.teal,
    Color secondary = ThqPalette.blue,
    Color background = ThqPalette.background,
    Color surface = ThqPalette.panel,
    Color sidebar = ThqPalette.sidebar,
    Color border = ThqPalette.border,
    Color text = ThqPalette.text,
    Color muted = ThqPalette.muted,
    Color error = ThqPalette.error,
    Color success = ThqPalette.teal,
    Color warning = ThqPalette.warning,
    double radius = 14,
  }) {
    final dark = surface.computeLuminance() < .45;
    final brightness = dark ? Brightness.dark : Brightness.light;
    final raised = Color.alphaBlend(primary.withValues(alpha: .035), surface);
    final selected = Color.alphaBlend(primary.withValues(alpha: .13), surface);
    Color foreground(Color fill) {
      final luminance = fill.computeLuminance();
      final inkContrast =
          (luminance + .05) / (ThqPalette.ink.computeLuminance() + .05);
      final whiteContrast = 1.05 / (luminance + .05);
      return inkContrast >= whiteContrast
          ? ThqPalette.ink
          : const Color(0xFFFFFFFF);
    }

    final onPrimary = foreground(primary);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: onPrimary,
          primaryContainer: selected,
          onPrimaryContainer: text,
          secondary: secondary,
          onSecondary: foreground(secondary),
          secondaryContainer: selected,
          onSecondaryContainer: primary,
          tertiary: success,
          onTertiary: foreground(success),
          tertiaryContainer: selected,
          onTertiaryContainer: text,
          surface: surface,
          onSurface: text,
          onSurfaceVariant: muted,
          surfaceContainerLowest: background,
          surfaceContainerLow: sidebar,
          surfaceContainer: surface,
          surfaceContainerHigh: raised,
          surfaceContainerHighest: dark ? ThqPalette.raised : raised,
          error: error,
          onError: foreground(error),
          errorContainer: Color.alphaBlend(
            error.withValues(alpha: .12),
            surface,
          ),
          onErrorContainer: error,
          outline: border,
          outlineVariant: border,
          inverseSurface: text,
          onInverseSurface: surface,
          surfaceTint: Colors.transparent,
        );
    TextStyle type(
      double size, {
      FontWeight weight = FontWeight.w400,
      bool quiet = false,
    }) => TextStyle(
      fontSize: size,
      height: 1.3,
      fontWeight: weight,
      color: quiet ? muted : text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final typography = TextTheme(
      displayLarge: type(34, weight: FontWeight.w600),
      displayMedium: type(30, weight: FontWeight.w600),
      displaySmall: type(27, weight: FontWeight.w600),
      headlineLarge: type(25, weight: FontWeight.w600),
      headlineMedium: type(22, weight: FontWeight.w600),
      headlineSmall: type(20, weight: FontWeight.w600),
      titleLarge: type(17, weight: FontWeight.w600),
      titleMedium: type(14, weight: FontWeight.w500),
      titleSmall: type(12, weight: FontWeight.w500),
      bodyLarge: type(14),
      bodyMedium: type(13),
      bodySmall: type(11.5, quiet: true),
      labelLarge: type(13, weight: FontWeight.w600),
      labelMedium: type(12, weight: FontWeight.w500),
      labelSmall: type(11, weight: FontWeight.w500, quiet: true),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(9),
    );
    OutlineInputBorder input(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: color, width: width),
        );
    Widget press(
      BuildContext context,
      Set<WidgetState> states,
      Widget? child,
    ) => AnimatedScale(
      scale: states.contains(WidgetState.pressed) ? .98 : 1,
      duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      child: child ?? const SizedBox.shrink(),
    );
    ButtonStyle button({bool filled = false}) =>
        (filled ? FilledButton.styleFrom : OutlinedButton.styleFrom)(
          minimumSize: Size(touch ? 48 : 0, touch ? 48 : 36),
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: touch ? 12 : 8,
          ),
          shape: shape,
          textStyle: typography.labelLarge,
        ).copyWith(
          animationDuration: const Duration(milliseconds: 160),
          foregroundBuilder: press,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      dividerColor: border,
      textTheme: typography,
      visualDensity: touch ? VisualDensity.standard : VisualDensity.compact,
      extensions: [
        ThqSemanticColors(
          success: success,
          warning: warning,
          critical: error,
          info: secondary,
          successContainer: Color.alphaBlend(
            success.withValues(alpha: .11),
            surface,
          ),
          warningContainer: Color.alphaBlend(
            warning.withValues(alpha: .11),
            surface,
          ),
          criticalContainer: scheme.errorContainer,
          infoContainer: Color.alphaBlend(
            secondary.withValues(alpha: .11),
            surface,
          ),
          neutral: muted,
          neutralContainer: raised,
        ),
      ],
      iconTheme: IconThemeData(color: muted, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: touch ? 54 : 46,
        titleTextStyle: typography.titleMedium,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: touch ? 14 : 10,
        ),
        labelStyle: type(12, quiet: true),
        hintStyle: type(12, quiet: true),
        floatingLabelStyle: type(12).copyWith(color: primary),
        errorStyle: type(11).copyWith(color: error),
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: input(border),
        enabledBorder: input(border),
        disabledBorder: input(border),
        focusedBorder: input(primary, 1.5),
        errorBorder: input(error),
        focusedErrorBorder: input(error, 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(style: button(filled: true)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: Size(0, touch ? 48 : 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: shape,
        ).copyWith(foregroundBuilder: press),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: button().copyWith(
          foregroundColor: WidgetStatePropertyAll(text),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: Size(0, touch ? 44 : 34),
          shape: shape,
          textStyle: typography.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ).copyWith(foregroundBuilder: press),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: muted,
          minimumSize: Size.square(touch ? 48 : 36),
          padding: const EdgeInsets.all(8),
          shape: shape,
        ).copyWith(foregroundBuilder: press),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: raised,
        selectedColor: selected,
        checkmarkColor: primary,
        side: BorderSide(color: border),
        shape: shape,
        labelStyle: typography.labelMedium,
        secondaryLabelStyle: typography.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        iconTheme: IconThemeData(color: muted, size: 16),
      ),
      listTileTheme: ListTileThemeData(
        dense: !touch,
        textColor: text,
        iconColor: muted,
        selectedColor: primary,
        selectedTileColor: selected,
        minVerticalPadding: 4,
        horizontalTitleGap: 10,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: shape,
        titleTextStyle: typography.bodyMedium,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowHeight: 38,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 56,
        horizontalMargin: 12,
        columnSpacing: 16,
        dividerThickness: .7,
        headingTextStyle: typography.labelMedium?.copyWith(color: muted),
        dataTextStyle: typography.bodyMedium,
        headingRowColor: WidgetStatePropertyAll(raised),
        dataRowColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? selected
              : states.contains(WidgetState.hovered)
              ? raised
              : null,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
        titleTextStyle: typography.titleLarge,
        contentTextStyle: typography.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: raised,
        surfaceTintColor: Colors.transparent,
        textStyle: typography.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: typography.bodyMedium,
        menuStyle: MenuStyle(backgroundColor: WidgetStatePropertyAll(raised)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: sidebar,
        surfaceTintColor: Colors.transparent,
        height: 66,
        indicatorColor: selected,
        labelTextStyle: WidgetStatePropertyAll(typography.labelSmall),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? primary : muted,
            size: 21,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: sidebar,
        selectedItemColor: primary,
        unselectedItemColor: muted,
        elevation: 0,
        selectedLabelStyle: typography.labelSmall,
        unselectedLabelStyle: typography.labelSmall,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: sidebar,
        indicatorColor: selected,
        selectedIconTheme: IconThemeData(color: primary, size: 20),
        unselectedIconTheme: IconThemeData(color: muted, size: 20),
        selectedLabelTextStyle: typography.labelMedium?.copyWith(
          color: primary,
        ),
        unselectedLabelTextStyle: typography.labelMedium,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: sidebar,
        surfaceTintColor: Colors.transparent,
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: primary,
        labelColor: primary,
        unselectedLabelColor: muted,
        labelStyle: typography.labelLarge,
        unselectedLabelStyle: typography.labelMedium,
        dividerColor: border,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: .7, space: 1),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          color: raised,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: typography.bodySmall?.copyWith(color: text),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(5),
        thumbColor: WidgetStatePropertyAll(muted.withValues(alpha: .35)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: raised,
        contentTextStyle: typography.bodyMedium,
        actionTextColor: primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: .25),
        selectionHandleColor: primary,
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          ...const PageTransitionsTheme().builders,
          TargetPlatform.windows: const _ThqPageTransition(),
          TargetPlatform.linux: const _ThqPageTransition(),
          TargetPlatform.macOS: const _ThqPageTransition(),
          TargetPlatform.android: const _ThqPageTransition(),
          TargetPlatform.fuchsia: const _ThqPageTransition(),
        },
      ),
    );
  }
}

class _ThqPageTransition extends PageTransitionsBuilder {
  const _ThqPageTransition();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: curved.drive(
          Tween(begin: const Offset(0, .015), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }
}
