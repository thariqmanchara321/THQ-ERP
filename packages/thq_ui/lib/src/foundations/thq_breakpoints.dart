/// Shared responsive layout classes for THQ applications.
enum ThqLayoutClass { mobile, compact, desktop, wide }

abstract final class ThqBreakpoints {
  static const double mobile = 600;
  static const double compact = 900;
  static const double desktop = 1200;
  static const double wide = 1600;

  static ThqLayoutClass classify(double width) {
    if (width < mobile) return ThqLayoutClass.mobile;
    if (width < desktop) return ThqLayoutClass.compact;
    if (width < wide) return ThqLayoutClass.desktop;
    return ThqLayoutClass.wide;
  }

  static bool isMobile(double width) => classify(width) == ThqLayoutClass.mobile;

  static bool isDesktop(double width) {
    final layout = classify(width);
    return layout == ThqLayoutClass.desktop || layout == ThqLayoutClass.wide;
  }
}
