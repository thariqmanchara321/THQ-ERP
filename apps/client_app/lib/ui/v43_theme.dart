import 'package:flutter/material.dart';

class UiDesignProfile {
  final String key;
  final String name;
  final String appKey;
  final Map<String, dynamic> config;

  const UiDesignProfile({
    required this.key,
    required this.name,
    required this.appKey,
    required this.config,
  });

  factory UiDesignProfile.fromMap(Map<String, dynamic> map, String appKey) {
    final raw = map['config'];
    return UiDesignProfile(
      key: map['key']?.toString() ?? '${appKey}_aurora',
      name: map['name']?.toString() ?? 'Aurora',
      appKey: map['app_key']?.toString() ?? appKey,
      config: raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{},
    );
  }

  factory UiDesignProfile.fallback(String appKey) => UiDesignProfile(
    key: appKey == 'pos' ? 'pos_aurora_grid' : 'client_aurora',
    name: 'Aurora Lavender',
    appKey: appKey,
    config: <String, dynamic>{
      'primary': '#6C5CE7',
      'secondary': '#AFA4F5',
      'accent': '#7C6CF2',
      'background': '#F5F3FF',
      'surface': '#FFFFFF',
      'sidebar': '#FBFAFF',
      'border': '#E9E5F6',
      'success': '#22A06B',
      'warning': '#E6A700',
      'danger': '#E05252',
      'text_primary': '#211F27',
      'text_secondary': '#625E6A',
      'radius': appKey == 'pos' ? 10 : 12,
      'density': 'compact',
      'card_style': 'soft',
      'sidebar_style': 'floating',
      'gradient': true,
      if (appKey == 'pos') 'pos_layout': 'retail_grid',
      if (appKey == 'pos') 'pos_product_style': 'soft_cards',
      if (appKey == 'pos') 'pos_cart_width': 340,
    },
  );

  static Color parseColor(dynamic raw, Color fallback) {
    if (raw == null) return fallback;
    var value = raw.toString().trim().replaceAll('#', '');
    if (value.length == 6) value = 'FF$value';
    if (value.length != 8) return fallback;
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  Color get primary => parseColor(config['primary'], const Color(0xFF6C5CE7));
  Color get secondary =>
      parseColor(config['secondary'], const Color(0xFFAFA4F5));
  Color get accent => parseColor(config['accent'], const Color(0xFF7C6CF2));
  Color get background =>
      parseColor(config['background'], const Color(0xFFF5F3FF));
  Color get surface => parseColor(config['surface'], Colors.white);
  Color get sidebar => parseColor(config['sidebar'], const Color(0xFFFBFAFF));
  Color get border => parseColor(config['border'], const Color(0xFFE9E5F6));
  Color get success => parseColor(config['success'], const Color(0xFF22A06B));
  Color get warning => parseColor(config['warning'], const Color(0xFFE6A700));
  Color get danger => parseColor(config['danger'], const Color(0xFFE05252));
  Color get textPrimary =>
      parseColor(config['text_primary'], const Color(0xFF211F27));
  Color get textSecondary =>
      parseColor(config['text_secondary'], const Color(0xFF625E6A));
  double get radius => ((config['radius'] as num?)?.toDouble() ?? 18)
      .clamp(8.0, 28.0)
      .toDouble();
  bool get gradient => config['gradient'] == true;
  bool get compact => config['density']?.toString() == 'compact';
  String get cardStyle => config['card_style']?.toString() ?? 'soft';
  String get sidebarStyle => config['sidebar_style']?.toString() ?? 'floating';
  String get posLayout => config['pos_layout']?.toString() ?? 'retail_grid';
  String get posProductStyle =>
      config['pos_product_style']?.toString() ?? 'soft_cards';
  double get posCartWidth =>
      ((config['pos_cart_width'] as num?)?.toDouble() ?? 380)
          .clamp(320.0, 520.0)
          .toDouble();

  ThemeData theme() {
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
        floatingLabelStyle: TextStyle(color: primary),
        hintStyle: TextStyle(color: textSecondary),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        fillColor: surface,
        isDense: compact,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: compact ? 10 : 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r * 0.72),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r * 0.72),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r * 0.72),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(0, compact ? 36 : 42),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r * 0.72),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: Size(0, compact ? 36 : 40),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r * 0.72),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
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
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: sidebar,
        indicatorColor: Color.alphaBlend(
          primary.withValues(alpha: 0.14),
          surface,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r * 0.72),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r + 4),
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
        minVerticalPadding: compact ? 3 : 6,
        horizontalTitleGap: compact ? 8 : 12,
        contentPadding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
      ),
    );
  }
}

class UiDesignScope extends InheritedWidget {
  final UiDesignProfile profile;
  const UiDesignScope({super.key, required this.profile, required super.child});

  static UiDesignProfile of(BuildContext context, {String appKey = 'client'}) {
    return context
            .dependOnInheritedWidgetOfExactType<UiDesignScope>()
            ?.profile ??
        UiDesignProfile.fallback(appKey);
  }

  @override
  bool updateShouldNotify(UiDesignScope oldWidget) =>
      oldWidget.profile.config != profile.config ||
      oldWidget.profile.key != profile.key;
}

class V43Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? radius;
  final Color? color;
  const V43Surface({
    super.key,
    required this.child,
    this.padding,
    this.radius,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = UiDesignScope.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radius ?? p.radius),
        border: Border.all(color: p.border),
        boxShadow: p.cardStyle == 'soft'
            ? [
                BoxShadow(
                  color: p.primary.withValues(alpha: 0.055),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
      ),
      child: child,
    );
  }
}
