// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库纯展示偏好的页面会话 owner。
 *
 * 网格密度、主功能侧栏和标签面板都只属于展示层。controller 不触发过滤、计数、
 * 排序、缩略图预取或磁盘写入，调用方负责把复合变更放进一次 `setState` 并在需要
 * 时显式保存偏好。
 */
class LibraryViewPreferencesController {
  LibraryViewPreferencesController({
    required bool denseResultGrid,
    bool mainSidebarCollapsed = true,
    required bool tagDiscoveryPanelOpen,
  })  : _denseResultGrid = denseResultGrid,
        _mainSidebarCollapsed = mainSidebarCollapsed,
        _tagDiscoveryPanelOpen = tagDiscoveryPanelOpen;

  var _denseResultGrid = false;
  var _mainSidebarCollapsed = false;
  var _tagDiscoveryPanelOpen = false;

  /** 是否使用信息密度更高的列表视图。 */
  bool get denseResultGrid => _denseResultGrid;

  /** 主功能侧栏是否折叠。 */
  bool get mainSidebarCollapsed => _mainSidebarCollapsed;

  /** expanded 布局中的标签发现面板是否展开。 */
  bool get tagDiscoveryPanelOpen => _tagDiscoveryPanelOpen;

  /** 应用启动恢复或用户切换后的结果视图。 */
  void setDenseResultGrid(bool value) {
    _denseResultGrid = value;
  }

  /** 切换主功能侧栏折叠态。 */
  void toggleMainSidebar() {
    _mainSidebarCollapsed = !_mainSidebarCollapsed;
  }

  /** 应用启动恢复或页面重建时恢复主功能侧栏状态。 */
  void setMainSidebarCollapsed(bool value) {
    _mainSidebarCollapsed = value;
  }

  /** 设置标签发现面板显隐。 */
  void setTagDiscoveryPanelOpen(bool value) {
    _tagDiscoveryPanelOpen = value;
  }

  /** 切换标签发现面板显隐。 */
  void toggleTagDiscoveryPanel() {
    _tagDiscoveryPanelOpen = !_tagDiscoveryPanelOpen;
  }
}
