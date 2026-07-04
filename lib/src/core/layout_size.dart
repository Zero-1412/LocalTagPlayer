part of '../../main.dart';

enum LayoutSize { compact, medium, expanded }

class LayoutBreakpoints {
  const LayoutBreakpoints._();

  static const double compactMaxWidth = 700;
  static const double mediumMaxWidth = 1100;

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
