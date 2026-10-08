import 'package:flutter/material.dart';

/// Uses Flutter's dialog route, focus loop, theme capture and dismissal rules.
/// Only the finite entrance timing changes; system reduced motion wins.
Future<T?> showThqDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool fullscreenDialog = false,
  bool? requestFocus,
  AnimationStyle? animationStyle,
}) => showDialog<T>(
  context: context,
  builder: builder,
  barrierDismissible: barrierDismissible,
  barrierColor: barrierColor,
  barrierLabel: barrierLabel,
  useSafeArea: useSafeArea,
  useRootNavigator: useRootNavigator,
  routeSettings: routeSettings,
  anchorPoint: anchorPoint,
  traversalEdgeBehavior: traversalEdgeBehavior,
  fullscreenDialog: fullscreenDialog,
  requestFocus: requestFocus,
  animationStyle: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
      ? AnimationStyle.noAnimation
      : animationStyle ??
            const AnimationStyle(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
);
