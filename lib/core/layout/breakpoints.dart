import 'package:flutter/widgets.dart';

/// Mobile < 600 ≤ tablet < 1024 ≤ desktop.
class Breakpoints {
  Breakpoints._();
  static const double tablet = 600;
  static const double desktop = 1024;
  static const double wide = 1440;
}

enum ScreenSize { mobile, tablet, desktop }

ScreenSize screenSizeFor(double width) {
  if (width >= Breakpoints.desktop) return ScreenSize.desktop;
  if (width >= Breakpoints.tablet) return ScreenSize.tablet;
  return ScreenSize.mobile;
}

extension ScreenSizeX on BuildContext {
  ScreenSize get screenSize => screenSizeFor(MediaQuery.sizeOf(this).width);
  bool get isMobile => screenSize == ScreenSize.mobile;
  bool get isTablet => screenSize == ScreenSize.tablet;
  bool get isDesktop => screenSize == ScreenSize.desktop;
}
