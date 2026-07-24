// ignore_for_file: slash_for_doc_comments

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_release.dart';
import '../services/update/app_update_service.dart';

/**
 * 在应用首帧后执行一次非阻塞更新检查，并展示正式 Release 内容。
 *
 * 网络失败不会打扰本地使用；组件销毁后不会继续打开弹窗。
 */
class AppUpdatePrompt extends StatefulWidget {
  const AppUpdatePrompt({
    super.key,
    required this.service,
    required this.child,
    this.launchExternalUrl,
  });

  /** 远端正式版本查询边界。 */
  final AppUpdateService service;

  /** 媒体库主页面；更新检查不会改变其生命周期或状态。 */
  final Widget child;

  /** 测试可替换的外部浏览器入口。 */
  final Future<bool> Function(Uri url)? launchExternalUrl;

  @override
  State<AppUpdatePrompt> createState() => _AppUpdatePromptState();
}

class _AppUpdatePromptState extends State<AppUpdatePrompt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_check());
    });
  }

  /** 查询失败时保持静默，保证离线环境和 GitHub 限流不阻塞本地应用。 */
  Future<void> _check() async {
    try {
      final release = await widget.service.checkForUpdate();
      if (!mounted || release == null) {
        return;
      }
      await showAppUpdateDialog(
        context,
        release: release,
        launchExternalUrl: widget.launchExternalUrl,
      );
    } catch (_) {
      // 更新提醒是辅助能力；失败时不覆盖媒体库错误反馈，也不制造启动噪音。
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/** 展示版本、更新内容和安全的外部下载入口。 */
Future<void> showAppUpdateDialog(
  BuildContext context, {
  required AppRelease release,
  Future<bool> Function(Uri url)? launchExternalUrl,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('app.update.dialog'),
      title: const Row(
        children: [
          Icon(Icons.system_update_alt_rounded),
          SizedBox(width: 10),
          Text('发现新版本'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              release.title,
              key: const ValueKey('app.update.title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            const Text('更新内容'),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  release.notes.isEmpty ? '本次发布未提供更新说明。' : release.notes,
                  key: const ValueKey('app.update.notes'),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('app.update.later'),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('稍后提醒'),
        ),
        FilledButton.icon(
          key: const ValueKey('app.update.download'),
          onPressed: () async {
            final target = release.downloadUrl ?? release.pageUrl;
            final launcher = launchExternalUrl ??
                (url) => launchUrl(url, mode: LaunchMode.externalApplication);
            final opened = await launcher(target);
            if (dialogContext.mounted && opened) {
              Navigator.of(dialogContext).pop();
            }
          },
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(release.downloadUrl == null ? '查看发布页' : '下载更新'),
        ),
      ],
    ),
  );
}
