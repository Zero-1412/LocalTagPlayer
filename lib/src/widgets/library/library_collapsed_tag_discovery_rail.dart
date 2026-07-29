import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';
import 'library_smoke_keys.dart';
import 'library_tag_discovery_rows.dart';

// ignore_for_file: slash_for_doc_comments

class CollapsedTagDiscoveryRail extends StatelessWidget {
  const CollapsedTagDiscoveryRail({super.key, required this.onExpand});

  /**
   * 恢复右侧标签筛选面板的回调。
   */
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: LibrarySmokeKeys.collapsedTagRail,
      button: true,
      label: '\u5c55\u5f00\u6807\u7b7e\u7b5b\u9009',
      hint: '\u6062\u590d\u53f3\u4fa7\u6807\u7b7e\u7b5b\u9009\u9762\u677f',
      onTap: onExpand,
      child: Tooltip(
        message: '\u5c55\u5f00\u6807\u7b7e\u7b5b\u9009',
        child: Container(
          width: collapsedTagDiscoveryRailWidth,
          margin: collapsedTagDiscoveryRailMargin,
          decoration: BoxDecoration(
            color: librarySurface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: libraryBorder),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: onExpand,
              child: const ExcludeSemantics(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.filter_alt_outlined,
                      color: appAccentViolet,
                      size: 22,
                    ),
                    SizedBox(height: 8),
                    RotatedBox(
                      quarterTurns: 1,
                      child: Text(
                        '\u6807\u7b7e\u7b5b\u9009',
                        style: TextStyle(
                          color: libraryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/**
 * 为 widget smoke test 暴露收起窄条，不把私有实现泄漏到业务入口。
 */
@visibleForTesting
Widget collapsedTagDiscoveryRailSmokeHarness({
  required VoidCallback onExpand,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: CollapsedTagDiscoveryRail(
          onExpand: onExpand,
        ),
      ),
    ),
  );
}
