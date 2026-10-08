import 'package:flutter/material.dart';

import '../theme/thq_v7_theme.dart';
import '../theme/thq_appearance.dart';
import '../theme/thq_classic_mobile_theme.dart';

/// Native touch targets, shared navy/teal palette and compact mobile panels.
abstract final class ThqMobileTheme {
  static ThemeData client({ThqAppearance appearance = ThqAppearance.v7}) =>
      appearance == ThqAppearance.classic
      ? ThqClassicMobileTheme.client()
      : ThqV7Theme.mobile();
  static ThemeData pos({ThqAppearance appearance = ThqAppearance.v7}) =>
      appearance == ThqAppearance.classic
      ? ThqClassicMobileTheme.pos()
      : ThqV7Theme.mobile();
}
