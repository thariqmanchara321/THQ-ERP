import 'package:flutter/material.dart';

import 'thq_v7_theme.dart';

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
    final key = map['key']?.toString() ?? '${appKey}_thq_v7';
    final config = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    // Upgrade the old standard preset locally. Saved custom presets and their
    // color choices remain available through the existing Design Studio.
    final standard = key == 'client_aurora' || key == 'pos_aurora_grid';
    final overrides = map['overrides'] is Map
        ? Map<String, dynamic>.from(map['overrides'] as Map)
        : <String, dynamic>{};
    return UiDesignProfile(
      key: key,
      name: standard
          ? 'THQ V7 Navy & Teal'
          : map['name']?.toString() ?? 'THQ V7',
      appKey: map['app_key']?.toString() ?? appKey,
      config: standard
          ? {...config, ...defaultConfig, ...overrides}
          : {...defaultConfig, ...config},
    );
  }

  static const defaultConfig = <String, dynamic>{
    'design_system': 'thq_v7',
    'primary': '#22D3B2',
    'secondary': '#78B4FF',
    'accent': '#22D3B2',
    'background': '#0A1725',
    'surface': '#112438',
    'sidebar': '#0E2031',
    'border': '#274057',
    'success': '#22D3B2',
    'warning': '#F4CA7B',
    'danger': '#FF9A9E',
    'text_primary': '#EDF5FA',
    'text_secondary': '#9CB2C4',
    'radius': 14,
    'density': 'compact',
    'card_style': 'bordered',
    'sidebar_style': 'solid',
    'gradient': false,
    'pos_layout': 'retail_grid',
    'pos_product_style': 'solid_tiles',
    'pos_cart_width': 294,
  };

  factory UiDesignProfile.fallback(String appKey) => UiDesignProfile(
    key: '${appKey}_thq_v7',
    name: 'THQ V7 Navy & Teal',
    appKey: appKey,
    config: defaultConfig,
  );

  static Color parseColor(dynamic raw, Color fallback) {
    if (raw == null) return fallback;
    var value = raw.toString().trim().replaceAll('#', '');
    if (value.length == 6) value = 'FF$value';
    if (value.length != 8) return fallback;
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  Color get primary => parseColor(config['primary'], ThqPalette.teal);
  Color get secondary => parseColor(config['secondary'], ThqPalette.blue);
  Color get accent => parseColor(config['accent'], ThqPalette.teal);
  Color get background =>
      parseColor(config['background'], ThqPalette.background);
  Color get surface => parseColor(config['surface'], ThqPalette.panel);
  Color get sidebar => parseColor(config['sidebar'], ThqPalette.sidebar);
  Color get border => parseColor(config['border'], ThqPalette.border);
  Color get success => parseColor(config['success'], ThqPalette.teal);
  Color get warning => parseColor(config['warning'], ThqPalette.warning);
  Color get danger => parseColor(config['danger'], ThqPalette.error);
  Color get textPrimary => parseColor(config['text_primary'], ThqPalette.text);
  Color get textSecondary =>
      parseColor(config['text_secondary'], ThqPalette.muted);
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
      ((config['pos_cart_width'] as num?)?.toDouble() ?? 294)
          .clamp(294.0, 520.0)
          .toDouble();

  ThemeData theme() => ThqV7Theme.build(
    primary: primary,
    secondary: secondary,
    background: background,
    surface: surface,
    sidebar: sidebar,
    border: border,
    text: textPrimary,
    muted: textSecondary,
    error: danger,
    success: success,
    warning: warning,
    radius: radius,
  );
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
