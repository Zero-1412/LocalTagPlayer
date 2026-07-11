part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 缺失视频管理页：展示保留的稳定条目，并提供经过 fingerprint 校验的单文件 relink。
 */
class MissingRelinkPage extends StatefulWidget {
  const MissingRelinkPage({super.key, required this.store});

  /** 当前媒体库；页面只更新被重新关联的单条记录及其 folder 标签索引。 */
  final LibraryStore store;

  @override
  State<MissingRelinkPage> createState() => _MissingRelinkPageState();
}

/** 维护正在处理的 videoId，防止同一条目被重复提交。 */
class _MissingRelinkPageState extends State<MissingRelinkPage> {
  final Set<String> _relinkingVideoIds = <String>{};
  var _changed = false;

  List<VideoItem> get _missingVideos => widget.store.videos.values
      .where((item) => item.isMissing)
      .toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  /** 选择新文件并请求 store 做稳定身份与 fingerprint 校验。 */
  Future<void> _relink(VideoItem item) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择与 ${item.title} 对应的新文件',
      type: FileType.custom,
      allowedExtensions: TagRules.videoExtensions
          .map((extension) => extension.substring(1))
          .toList(),
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) {
      return;
    }
    final videoId = item.videoId;
    setState(() => _relinkingVideoIds.add(videoId));
    try {
      await widget.store.relinkMissingVideo(item, path);
      if (!mounted) {
        return;
      }
      setState(() => _changed = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已重新关联：${item.title}')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _relinkingVideoIds.remove(videoId));
      }
    }
  }

  /** 返回媒体库时报告是否有单条索引发生变化。 */
  void _close() => Navigator.of(context).pop(_changed);

  @override
  Widget build(BuildContext context) {
    final missing = _missingVideos;
    return Scaffold(
      backgroundColor: _appBackground,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回媒体库',
          onPressed: _close,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text('缺失视频 · ${missing.length}'),
      ),
      body: missing.isEmpty
          ? const Center(
              child: _EmptyState(
                hasLibrary: true,
                message: '当前没有缺失视频',
              ),
            )
          : ListView.separated(
              key: const ValueKey('missingRelink.list'),
              padding: const EdgeInsets.all(24),
              itemCount: missing.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = missing[index];
                  final videoId = item.videoId;
                final busy = _relinkingVideoIds.contains(videoId);
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.link_off_rounded),
                    title: Text(item.title),
                    subtitle: Text(
                      item.path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: FilledButton.icon(
                      key: ValueKey('missingRelink.$videoId'),
                      onPressed: busy ? null : () => _relink(item),
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.find_in_page_outlined),
                      label: const Text('重新关联'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
