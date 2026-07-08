part of '../app.dart';

enum LayoutSize { compact, medium, expanded }

class LayoutBreakpoints {
  const LayoutBreakpoints._();

  static const double compactMaxWidth = 700;
  static const double mediumMaxWidth = 980;

  static LayoutSize fromWidth(double width) {
    if (width < compactMaxWidth) {
      return LayoutSize.compact;
    }
    if (width < mediumMaxWidth) {
      return LayoutSize.medium;
    }
    return LayoutSize.expanded;
  }
}
