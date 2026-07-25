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

  /** 远端正式版本查询及安装边界。 */
  final AppUpdateService service;

  /** 媒体库主页面；更新检查不改变其生命周期或状态。 */
  final Widget child;

  /** 测试可替换的外部 Release 页面入口。 */
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
        service: widget.service,
        launchExternalUrl: widget.launchExternalUrl,
      );
    } catch (_) {
      // 启动检查是辅助能力；错误只在用户主动检查时显式显示。
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/**
 * 展示版本、更新内容和应用内安装入口。
 *
 * [service] 独占下载、摘要校验和安装器启动；UI 只呈现进度和错误。
 */
Future<void> showAppUpdateDialog(
  BuildContext context, {
  required AppRelease release,
  required AppUpdateService service,
  Future<bool> Function(Uri url)? launchExternalUrl,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _AppUpdateDialog(
      release: release,
      service: service,
      launchExternalUrl: launchExternalUrl,
    ),
  );
}

/** 更新弹窗的下载状态只在当前 Route 内存中维护，不写用户设置。 */
class _AppUpdateDialog extends StatefulWidget {
  const _AppUpdateDialog({
    required this.release,
    required this.service,
    this.launchExternalUrl,
  });

  /** 待安装的正式发布。 */
  final AppRelease release;

  /** 下载、校验与安装器启动边界。 */
  final AppUpdateService service;

  /** 无可验证资产时使用的外部 Release 页面入口。 */
  final Future<bool> Function(Uri url)? launchExternalUrl;

  @override
  State<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<_AppUpdateDialog> {
  AppUpdateDownloadProgress? _progress;
  bool _running = false;
  String? _error;

  /** 下载可验证安装包并启动交互式安装器，失败时保留弹窗供用户重试。 */
  Future<void> _downloadAndLaunch() async {
    if (_running) {
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _progress = const AppUpdateDownloadProgress(
        receivedBytes: 0,
        totalBytes: -1,
      );
    });
    try {
      await widget.service.downloadAndLaunch(
        widget.release,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _running = false;
          // 不把临时路径、网络响应细节或平台异常直接暴露到界面。
          _error = '下载或校验安装包失败，请稍后重试';
        });
      }
    }
  }

  /** 无安装器或非 Windows 平台时明确打开 Release 页面作为降级路径。 */
  Future<void> _openReleasePage() async {
    final launcher = widget.launchExternalUrl ??
        (url) => launchUrl(url, mode: LaunchMode.externalApplication);
    await launcher(widget.release.pageUrl);
  }

  @override
  Widget build(BuildContext context) {
    final canInstall = widget.release.downloadUrl != null &&
        widget.release.downloadName != null &&
        widget.release.downloadSha256 != null;
    final progress = _progress;
    final percent = progress?.fraction;
    return AlertDialog(
      key: const ValueKey('app.update.dialog'),
      title: const Row(
        children: [
          Icon(Icons.system_update_alt_rounded),
          SizedBox(width: 10),
          Text('发现新版本'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.release.title,
              key: const ValueKey('app.update.title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            const Text('更新内容'),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.release.notes.isEmpty
                      ? '本次发布未提供更新说明。'
                      : widget.release.notes,
                  key: const ValueKey('app.update.notes'),
                ),
              ),
            ),
            if (_running || _error != null) ...[
              const SizedBox(height: 18),
              LinearProgressIndicator(
                key: const ValueKey('app.update.progress'),
                value: percent,
              ),
              const SizedBox(height: 8),
              Text(
                _error ??
                    (percent == null
                        ? '正在下载并校验安装包…'
                        : '正在下载 ${(percent * 100).toStringAsFixed(0)}%'),
                key: const ValueKey('app.update.status'),
                style: TextStyle(
                  color: _error == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('app.update.releasePage'),
          onPressed: _running ? null : _openReleasePage,
          child: const Text('查看发布页'),
        ),
        TextButton(
          key: const ValueKey('app.update.later'),
          onPressed: _running ? null : () => Navigator.of(context).pop(),
          child: const Text('稍后提醒'),
        ),
        FilledButton.icon(
          key: const ValueKey('app.update.download'),
          onPressed: _running
              ? null
              : canInstall
                  ? _downloadAndLaunch
                  : _openReleasePage,
          icon: _running
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(canInstall
                  ? Icons.download_for_offline_rounded
                  : Icons.open_in_new_rounded),
          label: Text(canInstall ? '下载并安装' : '打开下载页'),
        ),
      ],
    );
  }
}
