import 'dart:convert';

// ignore_for_file: slash_for_doc_comments

/** 媒体库可选排序字段。 */
enum SortMode { name, recent, type, size, folder, added }

/** 媒体库排序方向。 */
enum SortDirection { descending, ascending }

/**
 * 媒体库展示偏好值对象。
 *
 * 该模型只描述排序与网格/列表选择，不执行文件写入，也不改变 `FilterQuery` 的
 * 筛选语义。新增字段必须提供默认值，保证旧偏好文件可继续读取。
 */
class LibrarySortPreferences {
  const LibrarySortPreferences({
    this.mode = SortMode.recent,
    this.direction = SortDirection.descending,
    this.denseResultGrid = false,
  });

  /** 当前排序字段。 */
  final SortMode mode;

  /** 当前排序方向。 */
  final SortDirection direction;

  /** 是否使用信息密度更高的列表模式；false 表示网格模式。 */
  final bool denseResultGrid;

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
    );
  }

  /** 转成可持久化 JSON。 */
  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'direction': direction.name,
        'denseResultGrid': denseResultGrid,
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
