import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// ignore_for_file: slash_for_doc_comments

/** 允许桌面鼠标与触控板拖拽滚动，同时保留 Material 默认设备。 */
class DesktopDragScrollBehavior extends MaterialScrollBehavior {
  const DesktopDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}
