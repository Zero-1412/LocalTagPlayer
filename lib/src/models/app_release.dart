// ignore_for_file: slash_for_doc_comments

/**
 * GitHub 正式发布中供应用更新提示使用的最小信息。
 *
 * 更新检测只消费公开 Release 元数据，不接触媒体库、用户数据或播放状态。
 */
class AppRelease {
  const AppRelease({
    required this.version,
    required this.title,
    required this.notes,
    required this.pageUrl,
    this.downloadUrl,
  });

  /** 去掉 `v` 前缀后的远端语义版本号。 */
  final String version;

  /** 发布页标题；为空时由服务回退为版本号。 */
  final String title;

  /** GitHub Release 正文，作为更新内容展示。 */
  final String notes;

  /** 浏览器中的正式 Release 页面。 */
  final Uri pageUrl;

  /** 当前平台安装包直链；找不到匹配资产时保持为空并打开发布页。 */
  final Uri? downloadUrl;
}
