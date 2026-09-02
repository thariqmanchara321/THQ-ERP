import 'package:flutter/material.dart';

/// Shared measurements for all THQ ERP applications.
abstract final class ThqTokens {
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space10 = 10;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space40 = 40;

  static const double radiusSmall = 6;
  static const double radiusMedium = 10;
  static const double radiusLarge = 14;
  static const double radiusXLarge = 18;
  static const double radiusPill = 999;

  static const double controlCompact = 36;
  static const double controlStandard = 40;
  static const double controlTouch = 48;

  static const double iconSmall = 16;
  static const double iconMedium = 20;
  static const double iconLarge = 24;

  static const double tableRowCompact = 40;
  static const double tableRowStandard = 48;
  static const double tableHeader = 42;

  static const Duration motionFast = Duration(milliseconds: 120);
  static const Duration motionStandard = Duration(milliseconds: 180);
  static const Duration motionSlow = Duration(milliseconds: 240);

  static const EdgeInsets pagePadding = EdgeInsets.all(space16);
  static const EdgeInsets sectionPadding = EdgeInsets.all(space16);
  static const EdgeInsets compactPadding = EdgeInsets.symmetric(
    horizontal: space12,
    vertical: space8,
  );
}
