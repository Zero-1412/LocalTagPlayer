// ignore_for_file: slash_for_doc_comments

import 'package:flutter/material.dart';

import '../../../widgets/app_theme_tokens.dart';
import '../domain/app_update_proxy_settings.dart';

/**
 * 应用更新专用的网络代理设置页。
 *
 * 页面只向更新代理服务提交读取与保存意图；代理不会传播到系统、媒体播放或媒体库链路。
 */
class UpdateProxySettingsPage extends StatefulWidget {
  const UpdateProxySettingsPage({
    super.key,
    required this.proxySettingsService,
  });

  /** 应用更新代理的读取与持久化边界。 */
  final AppUpdateProxySettingsService proxySettingsService;

  @override
  State<UpdateProxySettingsPage> createState() =>
      _UpdateProxySettingsPageState();
}

class _UpdateProxySettingsPageState extends State<UpdateProxySettingsPage> {
  final TextEditingController _addressController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /** 读取失败时保留直连默认值，并在当前页面提供可见反馈。 */
  Future<void> _loadSettings() async {
    try {
      final settings = await widget.proxySettingsService.loadProxySettings();
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _enabled = settings.enabled;
        _addressController.text = settings.address;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusIsError = true;
          _status = '代理设置读取失败，当前保持直连';
        });
      }
    }
  }

  /** 保存只更新应用更新客户端，绝不修改系统代理或其它业务网络链路。 */
  Future<void> _saveSettings() async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _status = '正在保存代理设置…';
      _statusIsError = false;
    });
    try {
      final settings = AppUpdateProxySettings(
        enabled: _enabled,
        address: _addressController.text,
      ).normalized();
      await widget.proxySettingsService.saveProxySettings(settings);
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _enabled = settings.enabled;
        _addressController.text = settings.address;
        _status =
            settings.enabled ? '代理已保存，将用于后续更新检查和安装包下载' : '已关闭更新代理，后续请求将使用直连';
      });
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _statusIsError = true;
          _status = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _statusIsError = true;
          _status = '代理设置保存失败，请稍后重试';
        });
      }
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('settings.updateProxy'),
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          key: const ValueKey('settings.updateProxy.card'),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '更新网络代理',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '仅用于 GitHub Releases 检查与安装包下载，不影响媒体播放、媒体库或系统代理。',
                  style: TextStyle(color: libraryTextMuted, height: 1.45),
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  key: const ValueKey('settings.updateProxy.enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('使用 HTTP 代理'),
                  subtitle: const Text('支持本机代理，例如 127.0.0.1:7890'),
                  value: _enabled,
                  onChanged: _loading || _saving
                      ? null
                      : (value) => setState(() => _enabled = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('settings.updateProxy.address'),
                  controller: _addressController,
                  enabled: !_loading && !_saving && _enabled,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '代理地址',
                    hintText: '127.0.0.1:7890',
                    helperText: '仅支持 HTTP 代理，不保存账号或密码',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _saveSettings(),
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  key: const ValueKey('settings.updateProxy.save'),
                  onPressed: _loading || _saving ? null : _saveSettings,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? '正在保存' : '保存代理设置'),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _status!,
                    key: const ValueKey('settings.updateProxy.status'),
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
