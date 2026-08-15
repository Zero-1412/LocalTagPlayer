import 'package:flutter/material.dart';

import 'library_desktop_scroll_behavior.dart';

// ignore_for_file: slash_for_doc_comments

/** 主功能栏专用的无可见滚动条行为，继续保留桌面拖拽设备。 */
class LibrarySidebarScrollBehavior extends DesktopDragScrollBehavior {
  const LibrarySidebarScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
