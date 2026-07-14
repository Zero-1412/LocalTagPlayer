part of '../../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库顶部排序字段。
 *
 * 只描述 UI 可选字段；真正排序仍由 LibraryPage 根据当前视频集合执行，避免控件复制筛选或排序业务。
 */
enum SortMode { name, recent, type, size, folder, added }

/**
 * 媒体库顶部排序方向。
 */
enum SortDirection { descending, ascending }

/**
 * 媒体库排序偏好。
 *
 * 该偏好只影响媒体库、标签筛选、本地收藏和最近播放结果的展示顺序；
 * 不写入 SQLite，也不改变 `FilterQuery` 的筛选语义。
 */
class LibrarySortPreferences {
  const LibrarySortPreferences({
    this.mode = SortMode.recent,
    this.direction = SortDirection.descending,
  });

  /** 当前排序字段。 */
  final SortMode mode;

  /** 当前排序方向。 */
  final SortDirection direction;

  /** 从 JSON 恢复排序偏好，未知值回退到默认排序。 */
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
    );
  }

  /** 转成可持久化 JSON。 */
  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'direction': direction.name,
      };

  /** 读取上次媒体库排序偏好。 */
  static Future<LibrarySortPreferences> load() async {
    try {
      final file = await AppPaths.librarySortPreferencesFile();
      if (!await file.exists()) {
        return const LibrarySortPreferences();
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        return LibrarySortPreferences.fromJson(decoded);
      }
      if (decoded is Map) {
        return LibrarySortPreferences.fromJson(decoded.cast<String, Object?>());
      }
    } catch (_) {
      return const LibrarySortPreferences();
    }
    return const LibrarySortPreferences();
  }

  /** 保存当前媒体库排序偏好。 */
  Future<void> save() async {
    final file = await AppPaths.librarySortPreferencesFile();
    await file.writeAsString(jsonEncode(toJson()), flush: true);
  }
}

/**
 * 顶部排序控件。
 *
 * 字段选择使用贴合按钮底部的抽屉式 overlay，方向切换使用独立按钮，二者只通过回调把用户意图传回页面状态。
 */
class _TopSortControl extends StatefulWidget {
  const _TopSortControl({
    required this.sortMode,
    required this.sortDirection,
    required this.onChanged,
    required this.onDirectionToggle,
  });

  final SortMode sortMode;
  final SortDirection sortDirection;
  final ValueChanged<SortMode> onChanged;
  final VoidCallback onDirectionToggle;

  @override
  State<_TopSortControl> createState() => _TopSortControlState();
}

class _TopSortControlState extends State<_TopSortControl>
    with SingleTickerProviderStateMixin {
  final _fieldKey = GlobalKey();
  late final AnimationController _menuController;
  late final Animation<double> _menuSize;
  OverlayEntry? _menuEntry;
  Size _fieldSize = Size.zero;
  Offset _fieldOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _menuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 110),
    );
    _menuSize = CurvedAnimation(
      parent: _menuController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _TopSortControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _menuEntry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _removeSortMenu(immediate: true);
    _menuController.dispose();
    super.dispose();
  }

  /**
   * 打开或关闭排序字段抽屉。
   *
   * overlay 使用按钮的全局坐标定位，避免 Flutter overlay 在不同测试宿主或桌面 DPI 下出现二次偏移。
   */
  void _toggleSortMenu() {
    if (_menuEntry != null) {
      _removeSortMenu();
      return;
    }
    final renderBox =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    _fieldSize = renderBox?.size ?? const Size(132, 48);
    _fieldOffset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    _menuEntry = OverlayEntry(builder: _buildSortMenuOverlay);
    Overlay.of(context).insert(_menuEntry!);
    _menuController.forward(from: 0);
  }

  /**
   * 收起排序字段抽屉。
   *
   * dispose 时使用 immediate，避免异步反向动画访问已经失效的 State。
   */
  Future<void> _removeSortMenu({bool immediate = false}) async {
    final entry = _menuEntry;
    if (entry == null) {
      return;
    }
    _menuEntry = null;
    if (!immediate && _menuController.isAnimating == false) {
      await _menuController.reverse();
    }
    entry.remove();
  }

  /**
   * 构建贴合字段按钮底部的排序字段抽屉。
   */
  Widget _buildSortMenuOverlay(BuildContext context) {
    final menuWidth = math.max(_fieldSize.width, 136.0);
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeSortMenu,
            ),
          ),
          Positioned(
            left: _fieldOffset.dx,
            top: _fieldOffset.dy + _fieldSize.height - 1,
            width: menuWidth,
            child: Material(
              color: Colors.transparent,
              child: AnimatedBuilder(
                animation: _menuSize,
                builder: (context, child) {
                  return ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: _menuSize.value,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  key: LibrarySmokeKeys.topSortMenuPanel,
                  width: menuWidth,
                  decoration: const BoxDecoration(
                    color: _appPanel,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(10),
                    ),
                    border: Border(
                      left: BorderSide(color: _appBorder),
                      right: BorderSide(color: _appBorder),
                      bottom: BorderSide(color: _appBorder),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x1f0f172a),
                        blurRadius: 14,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final mode in SortMode.values)
                        Semantics(
                          button: true,
                          selected: widget.sortMode == mode,
                          label: LibrarySmokeSemantics.sortMenuItem(mode),
                          child: InkWell(
                            key: LibrarySmokeKeys.topSortMenuItem(mode),
                            onTap: () {
                              widget.onChanged(mode);
                              _removeSortMenu();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 13,
                              ),
                              child: _SortMenuItem(
                                label: sortModeLabel(mode),
                                selected: widget.sortMode == mode,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final directionAscending = widget.sortDirection == SortDirection.ascending;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: _appPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _appBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: LibrarySmokeSemantics.sortFieldButton,
            value: sortModeLabel(widget.sortMode),
            child: Tooltip(
              message: '\u6392\u5e8f\u5b57\u6bb5',
              child: InkWell(
                key: LibrarySmokeKeys.topSortFieldButton,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(10),
                ),
                onTap: _toggleSortMenu,
                child: Padding(
                  key: _fieldKey,
                  padding: const EdgeInsets.only(left: 12, right: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort_rounded,
                          size: 18, color: _appAccentStrong),
                      const SizedBox(width: 7),
                      Text(
                        sortModeLabel(widget.sortMode),
                        style: const TextStyle(
                          color: _appText,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_more_rounded,
                          size: 18, color: _appTextMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(
            height: 26,
            child: VerticalDivider(width: 1, color: _appBorder),
          ),
          Semantics(
            key: LibrarySmokeKeys.topSortDirectionButton,
            button: true,
            label: LibrarySmokeSemantics.sortDirectionButton,
            value: directionAscending ? '\u6b63\u5e8f' : '\u5012\u5e8f',
            child: Tooltip(
              message: directionAscending
                  ? '\u5207\u6362\u4e3a\u5012\u5e8f'
                  : '\u5207\u6362\u4e3a\u6b63\u5e8f',
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(10),
                ),
                onTap: widget.onDirectionToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        directionAscending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 17,
                        color: _appAccentStrong,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        directionAscending ? '\u6b63\u5e8f' : '\u5012\u5e8f',
                        style: const TextStyle(
                          color: _appText,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortMenuItem extends StatelessWidget {
  const _SortMenuItem({
    required this.label,
    required this.selected,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          selected ? Icons.check_rounded : Icons.circle_outlined,
          size: 18,
          color: selected ? _appAccentViolet : _appTextMuted,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: _appText,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

@visibleForTesting
String sortModeLabel(SortMode mode) {
  return switch (mode) {
    SortMode.name => '\u540d\u79f0',
    SortMode.recent => '\u65e5\u671f',
    SortMode.type => '\u7c7b\u578b',
    SortMode.size => '\u5927\u5c0f',
    SortMode.folder => '\u76ee\u5f55',
    SortMode.added => '\u6dfb\u52a0\u65f6\u95f4',
  };
}
