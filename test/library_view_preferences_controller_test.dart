import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_view_preferences_controller.dart';
import 'package:local_tag_player/src/models/library_sort.dart';

void main() {
  test('主功能侧栏默认折叠且旧偏好缺字段时保持折叠', () {
    final controller = LibraryViewPreferencesController(
      denseResultGrid: false,
      tagDiscoveryPanelOpen: false,
    );

    expect(controller.mainSidebarCollapsed, isTrue);
    controller.setMainSidebarCollapsed(false);
    expect(controller.mainSidebarCollapsed, isFalse);

    final legacy = LibrarySortPreferences.decode(
      '{"mode":"recent","direction":"descending","denseResultGrid":false}',
    );
    expect(legacy.mainSidebarCollapsed, isTrue);
  });

  test('主功能侧栏状态可以在展示偏好中往返保存', () {
    const preferences = LibrarySortPreferences(
      mainSidebarCollapsed: false,
    );

    final restored = LibrarySortPreferences.decode(preferences.encode());
    expect(restored.mainSidebarCollapsed, isFalse);
  });

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
