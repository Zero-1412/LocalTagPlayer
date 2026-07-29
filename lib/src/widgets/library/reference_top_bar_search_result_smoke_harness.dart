import 'package:flutter/material.dart';

import '../../core/layout_size.dart';
import '../../models/library_sort.dart';
import '../../models/platform_models.dart';
import 'library_widgets.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 顶部搜索到结果列表的 focused test 入口。
 *
 * 只验证输入链路驱动结果数量和可见列表；真实过滤仍由页面和查询边界负责。
 */
@visibleForTesting
class ReferenceTopBarSearchResultSmokeHarness extends StatefulWidget {
  const ReferenceTopBarSearchResultSmokeHarness({
    super.key,
    required this.items,
  });

  /** 用于 focused test 的可搜索标题列表。 */
  final List<String> items;

  @override
  State<ReferenceTopBarSearchResultSmokeHarness> createState() =>
      ReferenceTopBarSearchResultSmokeHarnessState();
}

class ReferenceTopBarSearchResultSmokeHarnessState
    extends State<ReferenceTopBarSearchResultSmokeHarness> {
  /** 模拟真实页面中的单一输入源。 */
  final _controller = TextEditingController();

  /** 验证 `Ctrl+K` 能把焦点转给真实 TextField。 */
  final _focusNode = FocusNode(debugLabel: 'search-result-smoke-field');

  var _keyword = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = _keyword.trim().toLowerCase();
    final filtered = token.isEmpty
        ? widget.items
        : widget.items
            .where((item) => item.toLowerCase().contains(token))
            .toList();
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ReferenceTopBar(
              controller: _controller,
              searchFocusNode: _focusNode,
              videoCount: filtered.length,
              keyword: _keyword,
              selectedTags: const <String>[],
              selectedChildTags: const <String>[],
              selectedGroupTags: const <TagItem>[],
              excludedTags: const <TagItem>[],
              defaultChipLabel: '\u5168\u90e8\u89c6\u9891',
              showFavoritesOnly: false,
              refreshing: false,
              progressLabel: null,
              progressValue: null,
              sortMode: SortMode.recent,
              sortDirection: SortDirection.descending,
              layoutSize: LayoutSize.expanded,
              hasActiveFilters: token.isNotEmpty,
              onSearchChanged: (value) => setState(() => _keyword = value),
              onSortChanged: (_) {},
              onSortDirectionToggle: () {},
              denseResultGrid: false,
              onResultViewChanged: (_) {},
              onOpenTagManager: () {},
              onOpenFilters: () {},
              onRemovePrimaryTag: (_) {},
              onRemoveChildTag: (_) {},
              onRemoveGroupTag: (_) {},
              onRemoveExcludedTag: (_) {},
              onClearKeyword: () {
                _controller.clear();
                setState(() => _keyword = '');
              },
              onClearFavoritesOnly: () {},
              onClearAll: null,
            ),
            Text('结果 ${filtered.length}/${widget.items.length}'),
            Expanded(
              child: ListView(
                children: [
                  for (final item in filtered) Text(item),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
