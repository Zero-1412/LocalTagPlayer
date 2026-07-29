import 'dart:collection';

// ignore_for_file: slash_for_doc_comments

/**
 * 主媒体结果区多选状态的唯一 owner。
 *
 * controller 只保存 stable `videoId`，不持有 `VideoItem`、可变路径、筛选结果、Widget 或
 * 删除命令。页面继续用一次复合 `setState` 协调结果来源切换，避免 controller 通知与页面
 * 状态写入形成两次 rebuild。
 */
class LibrarySelectionController {
  /** 内部可写 stable id 集合。 */
  final Set<String> _selectedVideoIds = <String>{};

  /** 复用同一个只读视图，避免 build 高频读取时反复复制大型选择集。 */
  late final Set<String> _readOnlySelectedVideoIds =
      UnmodifiableSetView<String>(_selectedVideoIds);

  var _selectionMode = false;

  /** 当前是否处于多选模式。 */
  bool get selectionMode => _selectionMode;

  /** 当前选择的稳定视频身份只读视图。 */
  Set<String> get selectedVideoIds => _readOnlySelectedVideoIds;

  /** 进入多选模式；旧的临时选择不能跨模式会话残留。 */
  void enter() {
    _selectionMode = true;
    _selectedVideoIds.clear();
  }

  /** 退出多选模式并清空临时选择。 */
  void clear() {
    _selectionMode = false;
    _selectedVideoIds.clear();
  }

  /** 按 stable `videoId` 切换单项选择。 */
  void toggle(String videoId) {
    if (!_selectedVideoIds.remove(videoId)) {
      _selectedVideoIds.add(videoId);
    }
  }

  /**
   * 对当前可见结果执行全选或取消全选。
   *
   * 调用方传入已经接受的结果快照顺序；controller 只复制 stable id，不保留列表引用。
   */
  void toggleAll(Iterable<String> visibleVideoIds) {
    final visible = visibleVideoIds.toSet();
    final allSelected = visible.isNotEmpty &&
        visible.length == _selectedVideoIds.length &&
        _selectedVideoIds.containsAll(visible);
    _selectedVideoIds
      ..clear()
      ..addAll(allSelected ? const <String>{} : visible);
  }

  /** 删除成功后移除对应选择；没有剩余项时自动退出多选模式。 */
  void removeAll(Iterable<String> videoIds) {
    _selectedVideoIds.removeAll(videoIds);
    if (_selectedVideoIds.isEmpty) {
      _selectionMode = false;
    }
  }
}
