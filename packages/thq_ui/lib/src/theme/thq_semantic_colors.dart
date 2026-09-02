import 'package:flutter/material.dart';

@immutable
class ThqSemanticColors extends ThemeExtension<ThqSemanticColors> {
  const ThqSemanticColors({
    required this.success,
    required this.warning,
    required this.critical,
    required this.info,
    required this.neutral,
    required this.successContainer,
    required this.warningContainer,
    required this.criticalContainer,
    required this.infoContainer,
    required this.neutralContainer,
  });

  final Color success;
  final Color warning;
  final Color critical;
  final Color info;
  final Color neutral;
  final Color successContainer;
  final Color warningContainer;
  final Color criticalContainer;
  final Color infoContainer;
  final Color neutralContainer;

  static const dark = ThqSemanticColors(
    success: Color(0xFF67C38B),
    warning: Color(0xFFD9B15F),
    critical: Color(0xFFE36A6A),
    info: Color(0xFF70C1B3),
    neutral: Color(0xFF9AA7B7),
    successContainer: Color(0xFF173A2A),
    warningContainer: Color(0xFF40351E),
    criticalContainer: Color(0xFF442323),
    infoContainer: Color(0xFF173A3A),
    neutralContainer: Color(0xFF252F3B),
  );

  static const light = ThqSemanticColors(
    success: Color(0xFF2E7D50),
    warning: Color(0xFF8A6719),
    critical: Color(0xFFB3261E),
    info: Color(0xFF356E69),
    neutral: Color(0xFF6D625C),
    successContainer: Color(0xFFDDF4E5),
    warningContainer: Color(0xFFFFF0C8),
    criticalContainer: Color(0xFFFFDAD6),
    infoContainer: Color(0xFFD6F1EE),
    neutralContainer: Color(0xFFEDE6E0),
  );

  @override
  ThqSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? critical,
    Color? info,
    Color? neutral,
    Color? successContainer,
    Color? warningContainer,
    Color? criticalContainer,
    Color? infoContainer,
    Color? neutralContainer,
  }) {
    return ThqSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      critical: critical ?? this.critical,
      info: info ?? this.info,
      neutral: neutral ?? this.neutral,
      successContainer: successContainer ?? this.successContainer,
      warningContainer: warningContainer ?? this.warningContainer,
      criticalContainer: criticalContainer ?? this.criticalContainer,
      infoContainer: infoContainer ?? this.infoContainer,
      neutralContainer: neutralContainer ?? this.neutralContainer,
    );
  }

  @override
  ThqSemanticColors lerp(covariant ThqSemanticColors? other, double t) {
    if (other == null) return this;
    return ThqSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      critical: Color.lerp(critical, other.critical, t)!,
      info: Color.lerp(info, other.info, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      criticalContainer: Color.lerp(criticalContainer, other.criticalContainer, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      neutralContainer: Color.lerp(neutralContainer, other.neutralContainer, t)!,
    );
  }
}

extension ThqSemanticColorsContext on BuildContext {
  ThqSemanticColors get thqSemanticColors =>
      Theme.of(this).extension<ThqSemanticColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? ThqSemanticColors.dark
          : ThqSemanticColors.light);
}
