part of '../app.dart';

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
