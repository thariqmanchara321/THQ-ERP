import 'package:flutter/material.dart';
import '../theme/thq_v7_theme.dart';

/// Native touch targets, shared navy/teal palette and compact mobile panels.
abstract final class ThqMobileTheme {
  static ThemeData client() => ThqV7Theme.mobile();
  static ThemeData pos() => ThqV7Theme.mobile();
}
