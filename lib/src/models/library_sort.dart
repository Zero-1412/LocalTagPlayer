import 'dart:convert';

// ignore_for_file: slash_for_doc_comments

/** 媒体库可选排序字段。 */
enum SortMode { name, recent, type, size, folder, added }

/** 媒体库排序方向。 */
enum SortDirection { descending, ascending }

/**
 * 媒体库展示偏好值对象。
 *
 * 该模型只描述媒体库展示偏好，不执行文件写入，也不改变 `FilterQuery` 的筛选
 * 语义。新增字段必须提供默认值，保证旧偏好文件可继续读取。
 */
class LibrarySortPreferences {
  const LibrarySortPreferences({
    this.mode = SortMode.recent,
    this.direction = SortDirection.descending,
    this.denseResultGrid = false,
    this.mainSidebarCollapsed = true,
  });

  /** 当前排序字段。 */
  final SortMode mode;

  /** 当前排序方向。 */
  final SortDirection direction;

  /** 是否使用信息密度更高的列表模式；false 表示网格模式。 */
  final bool denseResultGrid;

  /** 主界面功能栏是否折叠；旧偏好文件缺少该字段时默认折叠。 */
  final bool mainSidebarCollapsed;

  /** 从 JSON 恢复偏好，未知值回退到默认排序。 */
  factory LibrarySortPreferences.fromJson(Map<String, Object?> json) {
    final modeName = json['mode']?.toString();
    final directionName = json['direction']?.toString();
    return LibrarySortPreferences(
      mode: SortMode.values.firstWhere(
        (value) => value.name == modeName,
        orElse: () => SortMode.recent,
      ),
      direction: SortDirection.values.firstWhere(
        (value) => value.name == directionName,
        orElse: () => SortDirection.descending,
      ),
      denseResultGrid: json['denseResultGrid'] == true,
      mainSidebarCollapsed: json['mainSidebarCollapsed'] != false,
    );
  }

  /** 转成可持久化 JSON。 */
  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'direction': direction.name,
        'denseResultGrid': denseResultGrid,
        'mainSidebarCollapsed': mainSidebarCollapsed,
      };

  /** 编码为页面应用服务持久化的 JSON 文本。 */
  String encode() => jsonEncode(toJson());

  /** 从页面应用服务读取的 JSON 文本恢复偏好。 */
  static LibrarySortPreferences decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is Map<String, Object?>) {
      return LibrarySortPreferences.fromJson(decoded);
    }
    if (decoded is Map) {
      return LibrarySortPreferences.fromJson(
        decoded.cast<String, Object?>(),
      );
    }
    return const LibrarySortPreferences();
  }
}
