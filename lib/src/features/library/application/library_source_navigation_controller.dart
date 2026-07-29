// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库主结果区当前展示的数据来源。
 *
 * 来源只决定页面展示哪一组已派生结果，不拥有筛选查询、视频集合或播放队列。
 */
enum LibraryResultMode {
  /** 全量媒体库结果，受搜索、标签和收藏筛选影响。 */
  library,

  /** 继续观看结果，只展示具有有效未完成进度的视频。 */
  recent,

  /** 本地收藏结果，只展示用户收藏的视频。 */
  favorites,

  /** 本地媒体库路径浏览，按文件系统层级展示文件夹和视频。 */
  local,
}

/**
 * 媒体库结果来源与本地目录返回栈的唯一状态 owner。
 *
 * controller 不持有 Widget、路由、平台文件系统或媒体数据。页面继续负责把一次来源切换与
 * 搜索、标签、临时选择的清理合并到同一个 `setState`，避免多次通知造成重复 rebuild。
 */
class LibrarySourceNavigationController {
  /**
   * 创建来源导航 owner。
   *
   * [normalizePath] 负责生成展示/浏览路径，[pathKey] 负责生成平台适配后的比较键；策略由页面
   * 从平台边界外注入，controller 本身不读取 `Platform` 或文件系统。
   */
  LibrarySourceNavigationController({
    required String Function(String path) normalizePath,
    required String Function(String path) pathKey,
  })  : _normalizePath = normalizePath,
        _pathKey = pathKey;

  /** 平台适配后的路径规范化策略。 */
  final String Function(String path) _normalizePath;

  /** 平台适配后的路径等价比较键策略。 */
  final String Function(String path) _pathKey;

  LibraryResultMode _mode = LibraryResultMode.library;
  String? _localPath;
  final List<String> _localBackStack = <String>[];

  /** 当前主结果区的数据来源。 */
  LibraryResultMode get mode => _mode;

  /** 当前本地媒体库浏览路径；非本地来源通常为空。 */
  String? get localPath => _localPath;

  /** 本地目录是否存在可返回的上一层历史。 */
  bool get canGoBack => _localBackStack.isNotEmpty;

  /**
   * 只把当前结果切回普通媒体库。
   *
   * 标签和搜索等高频动作沿用旧行为，不主动清空本地路径历史；完整“媒体库”入口应调用
   * [resetToLibrary]，明确重置本地浏览会话。
   */
  void showLibraryResults() {
    _mode = LibraryResultMode.library;
  }

  /** 回到完整媒体库入口，并结束当前本地目录浏览会话。 */
  void resetToLibrary() {
    _mode = LibraryResultMode.library;
    _clearLocalNavigation();
  }

  /** 切换到继续观看来源，并结束当前本地目录浏览会话。 */
  void showRecent() {
    _mode = LibraryResultMode.recent;
    _clearLocalNavigation();
  }

  /** 切换到收藏来源，并结束当前本地目录浏览会话。 */
  void showFavorites() {
    _mode = LibraryResultMode.favorites;
    _clearLocalNavigation();
  }

  /**
   * 从侧栏 root 入口开启新的本地目录浏览会话。
   *
   * root 会先规范化；历史栈必须清空，避免返回到另一个 root 的旧路径。
   */
  void showLocalRoot(String rootPath) {
    _mode = LibraryResultMode.local;
    _localPath = _normalizePath(rootPath);
    _localBackStack.clear();
  }

  /**
   * 从当前路径进入子文件夹。
   *
   * 当前有效路径先压入返回栈；该方法不访问磁盘，也不改变扫描 root 或视频索引。
   */
  void openLocalFolder(String folderPath) {
    final currentPath = _localPath;
    if (currentPath != null && currentPath.isNotEmpty) {
      _localBackStack.add(currentPath);
    }
    _mode = LibraryResultMode.local;
    _localPath = _normalizePath(folderPath);
  }

  /**
   * 返回本地目录上一层。
   *
   * 返回 true 表示状态确实发生变化，页面可据此决定是否调用 `setState`。
   */
  bool goBack() {
    if (_localBackStack.isEmpty) {
      return false;
    }
    _mode = LibraryResultMode.local;
    _localPath = _localBackStack.removeLast();
    return true;
  }

  /**
   * 当前正浏览被解除管理的 root 时回到媒体库。
   *
   * 比较沿用路径大小写归一规则；其它 root 或普通来源不受影响。
   */
  bool leaveRemovedRoot(String rootPath) {
    final currentPath = _localPath;
    if (currentPath == null || _pathKey(currentPath) != _pathKey(rootPath)) {
      return false;
    }
    resetToLibrary();
    return true;
  }

  /** 结束本地浏览会话并丢弃仅用于 UI 返回的临时历史。 */
  void _clearLocalNavigation() {
    _localPath = null;
    _localBackStack.clear();
  }
}
