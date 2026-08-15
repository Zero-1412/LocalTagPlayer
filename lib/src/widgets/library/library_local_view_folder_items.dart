import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_theme_tokens.dart';
import 'library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments

/** 本地目录网格中的文件夹卡片，继续使用统一 smoke key 和可达点击入口。 */
class LocalFolderCard extends StatelessWidget {
  const LocalFolderCard({super.key, required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: LibrarySmokeSemantics.localFolder(path),
      value: path,
      child: Material(
        key: LibrarySmokeKeys.localFolder(path),
        color: appPanel,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              border: Border.all(color: appBorder),
              borderRadius: BorderRadius.circular(8),
              boxShadow: appSoftShadow,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.folder_rounded,
                    size: 58, color: appAccentViolet),
                const SizedBox(height: 16),
                Text(
                  p.basename(path),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: appText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/** 本地目录列表中的文件夹行，保持与卡片相同的 folder 语义和导航回调。 */
class LocalFolderRow extends StatelessWidget {
  const LocalFolderRow({super.key, required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: LibrarySmokeSemantics.localFolder(path),
      value: path,
      child: Material(
        key: LibrarySmokeKeys.localFolder(path),
        color: appPanel,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: appBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_rounded,
                    color: appAccentViolet, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    p.basename(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: appText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: appTextMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
