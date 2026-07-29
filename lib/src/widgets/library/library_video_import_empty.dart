import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';
import 'library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

class LibraryImportDropRegion extends StatefulWidget {
  const LibraryImportDropRegion({
    super.key,
    required this.enabled,
    required this.onDropPaths,
    required this.child,
  });

  /** 当前是否允许接收桌面拖放；扫描期间关闭以避免并发扫描。 */
  final bool enabled;

  /** 用户释放文件后收到的原始本地路径。 */
  final ValueChanged<List<String>> onDropPaths;

  /** 原媒体库结果内容。 */
  final Widget child;

  @override
  State<LibraryImportDropRegion> createState() =>
      _LibraryImportDropRegionState();
}

class _LibraryImportDropRegionState extends State<LibraryImportDropRegion> {
  /** 文件是否正在结果区上方悬停，仅用于绘制反馈，不参与业务筛选。 */
  var _dragging = false;

  /** 更新拖放悬停态；禁用后不保留过期覆盖层。 */
  void _setDragging(bool value) {
    final next = widget.enabled && value;
    if (_dragging == next) {
      return;
    }
    setState(() => _dragging = next);
  }

  @override
  void didUpdateWidget(covariant LibraryImportDropRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _dragging) {
      _dragging = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      key: LibrarySmokeKeys.importDropRegion,
      enable: widget.enabled,
      onDragEntered: (_) => _setDragging(true),
      onDragExited: (_) => _setDragging(false),
      onDragDone: (details) {
        _setDragging(false);
        final paths = <String>[
          for (final item in details.files)
            if (item.path.trim().isNotEmpty) item.path,
        ];
        if (paths.isNotEmpty) {
          widget.onDropPaths(paths);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          IgnorePointer(
            child: AnimatedOpacity(
              key: LibrarySmokeKeys.importDropOverlay,
              opacity: _dragging ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: appAccentViolet.withValues(alpha: 0.12),
                  border: Border.all(color: appAccentViolet, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: librarySurface,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      boxShadow: appSoftShadow,
                    ),
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.file_download_outlined,
                              size: 42, color: appAccentViolet),
                          SizedBox(height: 10),
                          Text(
                            '释放以添加视频或目录',
                            style: TextStyle(
                              color: libraryText,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
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

/** 媒体库、筛选结果和维护页面共用的空状态。 */
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.hasLibrary,
    this.message,
    this.onAddFiles,
  });

  final bool hasLibrary;

  final String? message;

  /** 仅在全库没有视频时提供的多文件选择入口。 */
  final VoidCallback? onAddFiles;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onAddFiles != null) ...[
            Semantics(
              button: true,
              label: '添加视频文件',
              child: Material(
                key: LibrarySmokeKeys.emptyAddFiles,
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: onAddFiles,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      // 使用媒体库的次级深色表面，避免空状态入口重新形成突兀的浅色孤岛。
                      color: librarySurfaceAlt,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0x596d5dfc),
                        width: 1.25,
                      ),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x126d5dfc),
                          blurRadius: 18,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 48,
                      color: Color(0xff756ae8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '添加视频文件',
              style: TextStyle(
                color: libraryText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              '选择视频文件，或将文件 / 文件夹拖到媒体库区域',
              textAlign: TextAlign.center,
              style: TextStyle(color: libraryTextMuted, height: 1.4),
            ),
          ] else ...[
            Icon(
              hasLibrary
                  ? Icons.filter_alt_off_outlined
                  : Icons.video_library_outlined,
              size: 54,
              color: Colors.black38,
            ),
            const SizedBox(height: 12),
            Text(message ??
                (hasLibrary
                    ? '\u6ca1\u6709\u5339\u914d\u7684\u89c6\u9891'
                    : '\u6dfb\u52a0\u89c6\u9891\u76ee\u5f55\u540e\u5f00\u59cb\u626b\u63cf')),
          ],
        ],
      ),
    );
  }
}
