import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/tag_rules.dart';
import '../../models/library_sort.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import 'library_sort_control.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 主界面 smoke test 使用的稳定命中标识。
 *
 * 该文件只承载测试/自动化定位 key，不放真实 UI 布局，避免大型主界面组件文件继续混入测试基础设施。
 */
class LibrarySmokeKeys {
  const LibrarySmokeKeys._();

  static const localPointerBackRegion =
      ValueKey<String>('smoke.local.pointer-back-region');
  static const localBackButton = ValueKey<String>('smoke.local.back-button');
  static const primaryTab = ValueKey<String>('smoke.tag.primary-tab');
  static const secondaryTab = ValueKey<String>('smoke.tag.secondary-tab');
  static const moreSecondaryTags =
      ValueKey<String>('smoke.tag.more-secondary-tags');
  static const listActionState = ValueKey<String>('smoke.list.action-state');
  static const collapsedTagRail = ValueKey<String>('smoke.tag.collapsed-rail');
  /** 展开状态下通过“标签筛选”标题收起右侧面板的入口。 */
  static const tagPanelCollapseHeader =
      ValueKey<String>('smoke.tag.panel-collapse-header');
  /** 主功能栏展开/折叠入口。 */
  static const sidebarCollapseToggle =
      ValueKey<String>('smoke.sidebar.collapse-toggle');
  /** 主功能栏实际宽度容器。 */
  static const sidebarSurface = ValueKey<String>('smoke.sidebar.surface');
  /** 左侧功能栏中的标签中心入口。 */
  static const sidebarTagCenter = ValueKey<String>('smoke.sidebar.tag-center');
  /** 媒体库筛选/多选双状态工具栏。 */
  static const libraryResultToolbar =
      ValueKey<String>('smoke.library.result-toolbar');
  /** 独立搜索输入表面，不承载已生效筛选状态。 */
  static const searchSurface = ValueKey<String>('smoke.top.search-surface');
  /** 搜索框右侧的低对比度筛选状态区域。 */
  static const filterStatusArea =
      ValueKey<String>('smoke.top.filter-status-area');
  /** 顶栏末端多选与视图切换操作区域。 */
  static const toolbarActions = ValueKey<String>('smoke.top.toolbar-actions');
  /** expanded 顶栏中搜索与紧凑动作共用的无外框操作行。 */
  static const headerActionLane =
      ValueKey<String>('smoke.top.header-action-lane');
  /** 排序控件之后展示的媒体库结果数量或后台进度状态。 */
  static const toolbarResultStatus =
      ValueKey<String>('smoke.top.toolbar-result-status');
  /** 多选模式下只替换搜索框右侧的状态区域。 */
  static const selectionStatusArea =
      ValueKey<String>('smoke.top.selection-status-area');
  /** 进入媒体库多选模式。 */
  static const libraryEnterSelection =
      ValueKey<String>('smoke.library.selection.enter');
  /** 多选模式全选切换。 */
  static const librarySelectAll =
      ValueKey<String>('smoke.library.selection.all');
  /** 多选模式删除已选视频。 */
  static const libraryDeleteSelected =
      ValueKey<String>('smoke.library.selection.delete');
  /** 退出媒体库多选模式。 */
  static const libraryCancelSelection =
      ValueKey<String>('smoke.library.selection.cancel');
  static const searchField = ValueKey<String>('smoke.top.search-field');
  /** 右侧状态区中承载筛选 chips 的限宽区域。 */
  static const searchFilterLane =
      ValueKey<String>('smoke.top.search-filter-lane');
  /** 独立搜索表面中的真实文本输入区域。 */
  static const searchInputLane =
      ValueKey<String>('smoke.top.search-input-lane');
  static const topSortFieldButton =
      ValueKey<String>('smoke.top.sort-field-button');
  static const topSortMenuPanel = ValueKey<String>('smoke.top.sort-menu-panel');
  static const topSortDirectionButton =
      ValueKey<String>('smoke.top.sort-direction-button');
  /** 网格/列表单体滑块的完整点击区域。 */
  static const resultViewToggle =
      ValueKey<String>('smoke.top.result-view-toggle');
  /** 网格/列表滑块中随状态平移的选中底块。 */
  static const resultViewToggleThumb =
      ValueKey<String>('smoke.top.result-view-toggle-thumb');
  /** 真实窗口扫描帧诊断的稳定入口。 */
  static const rescanButton = ValueKey<String>('smoke.sidebar.rescan');
  /** 空媒体库中央“添加视频”入口。 */
  static const emptyAddFiles =
      ValueKey<String>('smoke.library.empty-add-files');
  /** 媒体库结果区桌面拖放目标。 */
  static const importDropRegion = ValueKey<String>('smoke.library.drop-region');
  /** 文件进入拖放目标后显示的覆盖提示。 */
  static const importDropOverlay =
      ValueKey<String>('smoke.library.drop-overlay');

  static ValueKey<String> topSortMenuItem(SortMode mode) =>
      ValueKey<String>('smoke.top.sort-menu-item:${mode.name}');

  /**
   * 本地媒体库 root 项命中标识。
   *
   * key 使用 pathKey 保持 Windows 大小写不敏感路径在测试和运行时一致。
   */
  static ValueKey<String> localRoot(String path) =>
      ValueKey<String>('smoke.local.root:${TagRules.pathKey(path)}');

  /**
   * 本地媒体库文件夹项命中标识。
   */
  static ValueKey<String> localFolder(String path) =>
      ValueKey<String>('smoke.local.folder:${TagRules.pathKey(path)}');

  /**
   * 右侧一级折叠行命中标识。
   */
  static ValueKey<String> primaryRow(String tagId) =>
      ValueKey<String>('smoke.tag.primary-row:$tagId');

  /**
   * 右侧一级展开卡片标题行命中标识。
   */
  static ValueKey<String> primaryHeader(String tagId) =>
      ValueKey<String>('smoke.tag.primary-header:$tagId');

  /**
   * 右侧一级卡片内“展开全部 / 收起”命中标识。
   */
  static ValueKey<String> childExpandButton(String tagId) =>
      ValueKey<String>('smoke.tag.child-expand:$tagId');

  /**
   * 列表行整行命中标识。
   */
  static ValueKey<String> videoListRow(String path) =>
      ValueKey<String>('smoke.list.row:${TagRules.pathKey(path)}');

  /**
   * 列表行播放按钮命中标识。
   */
  static ValueKey<String> listPlay(String path) =>
      ValueKey<String>('smoke.list.play:${TagRules.pathKey(path)}');

  /**
   * 列表行收藏按钮命中标识。
   */
  static ValueKey<String> listFavorite(String path) =>
      ValueKey<String>('smoke.list.favorite:${TagRules.pathKey(path)}');

  /**
   * 列表行更多按钮命中标识。
   */
  static ValueKey<String> listMore(String path) =>
      ValueKey<String>('smoke.list.more:${TagRules.pathKey(path)}');
  static const videoMoreEditTags =
      ValueKey<String>('smoke.video.more.edit-tags');
  /** 视频更多菜单“打开位置”动作的稳定测试标识。 */
  static const videoMoreRevealLocation =
      ValueKey<String>('smoke.video.more.reveal-location');
  /** 视频更多菜单“删除”动作的稳定测试标识。 */
  static const videoMoreDelete = ValueKey<String>('smoke.video.more.delete');

  /** 视频网格卡片整体打开入口；卡片不再绘制独立播放按钮。 */
  static ValueKey<String> cardOpen(String path) =>
      ValueKey<String>('smoke.card.open:${TagRules.pathKey(path)}');

  /** 视频网格卡片标题右侧“更多”按钮命中标识。 */
  static ValueKey<String> cardMore(String path) =>
      ValueKey<String>('smoke.card.more:${TagRules.pathKey(path)}');

  /**
   * 视频网格缩略图左上角收藏按钮命中标识。
   */
  static ValueKey<String> cardFavorite(String path) =>
      ValueKey<String>('smoke.card.favorite:${TagRules.pathKey(path)}');

  /** 多选模式下替换收藏红心的圆形复选框。 */
  static ValueKey<String> cardSelection(String path) =>
      ValueKey<String>('smoke.card.selection:${TagRules.pathKey(path)}');

  /** 仅缩略图参与 hover 动画的稳定测试入口。 */
  static ValueKey<String> cardThumbnailSurface(String path) => ValueKey<String>(
        'smoke.card.thumbnail-surface:${TagRules.pathKey(path)}',
      );

  /** 缩略图内部 hover 缩放动画的稳定测试入口。 */
  static ValueKey<String> cardThumbnailZoom(String path) => ValueKey<String>(
        'smoke.card.thumbnail-zoom:${TagRules.pathKey(path)}',
      );

  /** 动态预览透明度动画的稳定测试入口。 */
  static ValueKey<String> cardHoverPreview(String path) => ValueKey<String>(
        'smoke.card.hover-preview:${TagRules.pathKey(path)}',
      );

  /** 动态预览期间隐藏时长角标的稳定测试入口。 */
  static ValueKey<String> cardDuration(String path) => ValueKey<String>(
        'smoke.card.duration:${TagRules.pathKey(path)}',
      );

  /** 媒体库增量滚动结果稳定标识。 */
  static const incrementalResults =
      ValueKey<String>('library.incremental.results');

  /**
   * 右侧标签 chip 命中标识。
   */
  static ValueKey<String> tagChip(String tagId) =>
      ValueKey<String>('smoke.tag.chip:$tagId');

  /**
   * 右侧标签筛选后结果项标识。
   */
  static ValueKey<String> tagResult(String title) =>
      ValueKey<String>('smoke.tag.result:$title');
}

/**
 * 真实窗口 QA 辅助树使用的稳定语义标签。
 *
 * 这些 label 是自动化协议，不是用户可见文案；修改时必须同步更新
 * `scripts/qa/main_window_stress_semantic.mjs`，否则压测会重新退化为坐标命中。
 */
class LibrarySmokeSemantics {
  const LibrarySmokeSemantics._();

  static const sortFieldButton = 'qa.sort.field.button';
  static const sortDirectionButton = 'qa.sort.direction.button';

  static String sortMenuItem(SortMode mode) =>
      'qa.sort.field.${mode.name}.${sortModeLabel(mode)}';

  static String localRoot(String path) =>
      'qa.local.root.${p.basename(path).isEmpty ? path : p.basename(path)}';

  static String localFolder(String path) =>
      'qa.local.folder.${p.basename(path).isEmpty ? path : p.basename(path)}';

  static String primaryTag(TagItem tag) =>
      'qa.tag.primary.${tag.displayName ?? tag.name}';

  static String childTag(TagItem primary, TagItem tag) =>
      'qa.tag.child.${primary.displayName ?? primary.name}.${tag.displayName ?? tag.name}';

  static String genericTag(TagItem tag) =>
      'qa.tag.${tag.displayName ?? tag.name}';

  static String videoPlay(VideoItem item) => 'qa.video.play.${item.title}';

  static String videoFavorite(VideoItem item) =>
      'qa.video.favorite.${item.title}';

  static String videoMore(VideoItem item) => 'qa.video.more.${item.title}';
}
