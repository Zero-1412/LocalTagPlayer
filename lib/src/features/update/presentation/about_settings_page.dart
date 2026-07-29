// ignore_for_file: slash_for_doc_comments

import 'package:flutter/material.dart';

import '../../../widgets/app_theme_tokens.dart';
import '../domain/app_release.dart';
import '../domain/app_update_service.dart';
import 'app_update_prompt.dart';

/**
 * 设置中的关于页面。
 *
 * 页面只读取包版本并主动调用更新接口，不接触媒体库、播放状态或本地用户数据。
 */
class AboutSettingsPage extends StatefulWidget {
  const AboutSettingsPage({
    super.key,
    required this.updateService,
  });

  /** 当前版本读取、正式 Release 查询和安装器执行边界。 */
  final AppUpdateService updateService;

  @override
  State<AboutSettingsPage> createState() => _AboutSettingsPageState();
}

class _AboutSettingsPageState extends State<AboutSettingsPage> {
  late final Future<AppVersionInfo> _versionFuture =
      widget.updateService.currentVersion();
  bool _checking = false;
  String? _status;
  bool _statusIsError = false;

  /** 主动检查必须向用户返回“最新、可更新或失败”三种明确结果。 */
  Future<void> _checkForUpdate() async {
    if (_checking) {
      return;
    }
    setState(() {
      _checking = true;
      _status = '正在检查最新正式版本…';
      _statusIsError = false;
    });
    try {
      final release = await widget.updateService.checkForUpdate();
      if (!mounted) {
        return;
      }
      if (release == null) {
        setState(() {
          _checking = false;
          _status = '当前已是最新正式版本';
        });
        return;
      }
      setState(() {
        _checking = false;
        _status = '发现新版本 ${release.version}';
      });
      await showAppUpdateDialog(
        context,
        release: release,
        service: widget.updateService,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _checking = false;
          _statusIsError = true;
          _status = '检查更新失败，请确认网络连接后重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('settings.about'),
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.video_library_rounded,
                  key: ValueKey('settings.about.logo'),
                  size: 54,
                  color: appAccent,
                ),
                const SizedBox(height: 16),
                FutureBuilder<AppVersionInfo>(
                  future: _versionFuture,
                  builder: (context, snapshot) {
                    final version = snapshot.data;
                    return Column(
                      children: [
                        Text(
                          'Local Tag Player',
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          version == null
                              ? '正在读取版本信息…'
                              : '版本 ${version.version}'
                                  '${version.buildNumber.isEmpty ? '' : ' (${version.buildNumber})'}',
                          key: const ValueKey('settings.about.version'),
                          style: const TextStyle(color: libraryTextMuted),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                const Divider(height: 1),
                const SizedBox(height: 20),
                const Text(
                  'Tag 驱动的本地视频发现播放器',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: libraryTextMuted, height: 1.5),
                ),
                const SizedBox(height: 6),
                const Text(
                  '更新渠道：GitHub Releases 正式版',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: libraryTextMuted),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  key: const ValueKey('settings.about.checkUpdate'),
                  onPressed: _checking ? null : _checkForUpdate,
                  icon: _checking
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update_alt_rounded),
                  label: Text(_checking ? '正在检查' : '检查更新'),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _status!,
                    key: const ValueKey('settings.about.updateStatus'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusIsError
                          ? Theme.of(context).colorScheme.error
                          : libraryTextMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
