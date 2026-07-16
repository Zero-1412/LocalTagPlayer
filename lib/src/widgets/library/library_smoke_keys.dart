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
  static const searchField = ValueKey<String>('smoke.top.search-field');
  static const topSortFieldButton =
      ValueKey<String>('smoke.top.sort-field-button');
  static const topSortMenuPanel = ValueKey<String>('smoke.top.sort-menu-panel');
  static const topSortDirectionButton =
      ValueKey<String>('smoke.top.sort-direction-button');
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
  /** 视频更多菜单“删除”动作的稳定测试标识。 */
  static const videoMoreDelete = ValueKey<String>('smoke.video.more.delete');

  /** 视频网格卡片整体打开入口；卡片不再绘制独立播放按钮。 */
  static ValueKey<String> cardOpen(String path) =>
      ValueKey<String>('smoke.card.open:${TagRules.pathKey(path)}');

  /**
   * 视频网格缩略图左上角收藏按钮命中标识。
   */
  static ValueKey<String> cardFavorite(String path) =>
      ValueKey<String>('smoke.card.favorite:${TagRules.pathKey(path)}');

  /** 媒体库分页条稳定标识。 */
  static const paginationBar = ValueKey<String>('library.pagination.bar');

  /** 媒体库分页范围文本稳定标识。 */
  static const paginationLabel = ValueKey<String>('library.pagination.label');

  /** 媒体库首页按钮稳定标识。 */
  static const paginationFirst = ValueKey<String>('library.pagination.first');

  /** 媒体库上一页按钮稳定标识。 */
  static const paginationPrevious =
      ValueKey<String>('library.pagination.previous');

  /** 媒体库下一页按钮稳定标识。 */
  static const paginationNext = ValueKey<String>('library.pagination.next');

  /** 媒体库末页按钮稳定标识。 */
  static const paginationLast = ValueKey<String>('library.pagination.last');

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
