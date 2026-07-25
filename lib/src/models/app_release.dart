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
    this.downloadName,
    this.downloadSha256,
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

  /** 当前平台安装包的公开文件名；仅用于安全的临时下载目标。 */
  final String? downloadName;

  /** GitHub 资产元数据提供的 SHA-256；缺失时不得直接执行安装包。 */
  final String? downloadSha256;
}

/**
 * 应用当前安装版本的只读信息。
 *
 * 关于页通过更新服务读取这些字段，避免 UI 直接依赖平台包信息插件。
 */
class AppVersionInfo {
  const AppVersionInfo({
    required this.appName,
    required this.version,
    required this.buildNumber,
  });

  /** 面向用户展示的应用名称。 */
  final String appName;

  /** 语义版本号，不包含构建号。 */
  final String version;

  /** 平台构建号。 */
  final String buildNumber;
}

/** 安装包下载过程中的不可变进度快照。 */
class AppUpdateDownloadProgress {
  const AppUpdateDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  /** 已写入临时文件的字节数。 */
  final int receivedBytes;

  /** 服务端声明的总字节数；未知时为 -1。 */
  final int totalBytes;

  /** 总大小可用时返回 0 到 1 的进度，否则返回 null。 */
  double? get fraction =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : null;
}
