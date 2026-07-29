import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_view_preferences_controller.dart';

void main() {
  test('纯展示偏好只修改对应页面状态', () {
    final controller = LibraryViewPreferencesController(
      denseResultGrid: false,
      mainSidebarCollapsed: false,
      tagDiscoveryPanelOpen: true,
    );

    controller
      ..setDenseResultGrid(true)
      ..toggleMainSidebar()
      ..toggleTagDiscoveryPanel();

    expect(controller.denseResultGrid, isTrue);
    expect(controller.mainSidebarCollapsed, isTrue);
    expect(controller.tagDiscoveryPanelOpen, isFalse);
  });

  test('标签面板可由筛选复合动作显式收起', () {
    final controller = LibraryViewPreferencesController(
      denseResultGrid: false,
      mainSidebarCollapsed: false,
      tagDiscoveryPanelOpen: true,
    );

    controller.setTagDiscoveryPanelOpen(false);

    expect(controller.tagDiscoveryPanelOpen, isFalse);
    expect(controller.denseResultGrid, isFalse);
    expect(controller.mainSidebarCollapsed, isFalse);
  });
}
