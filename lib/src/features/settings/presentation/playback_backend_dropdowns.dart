import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/playback_settings.dart';
import '../../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放硬件解码设置控件，负责把高影响解码切换收口到确认弹窗之后。
 */
class PlaybackDecoderDropdown extends StatefulWidget {
  const PlaybackDecoderDropdown({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  /** 当前已确认并可传给播放器的播放设置。 */
  final PlaybackSettings settings;

  /** 用户确认切换后回传新的播放设置，由外层负责持久化。 */
  final Future<void> Function(PlaybackSettings settings) onChanged;

  @override
  State<PlaybackDecoderDropdown> createState() =>
      _PlaybackDecoderDropdownState();
}

class _PlaybackDecoderDropdownState extends State<PlaybackDecoderDropdown> {
  late PlaybackSettings _settings = widget.settings;
  /** 具体后端默认折叠；当前已使用高级值时自动展开，避免隐藏真实配置。 */
  late bool _showAdvanced =
      !PlaybackSettings.commonDecoderOptions.contains(widget.settings.hwdec);

  /** 下拉框重建版本，用于取消确认后清理 `FormField` 的内部临时选中态。 */
  var _fieldRevision = 0;

  @override
  void didUpdateWidget(covariant PlaybackDecoderDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.hwdec != widget.settings.hwdec ||
        oldWidget.settings.resumeBehavior != widget.settings.resumeBehavior) {
      // 解码控件必须同步保留外层刚修改的继续观看策略，避免随后切换解码时用旧副本覆盖它。
      _settings = widget.settings;
    }
  }

  /**
   * 只在用户确认后写入解码设置，取消时恢复下拉框显示的旧值。
   */
  Future<void> _changeDecoder(String value) async {
    if (value == _settings.hwdec) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换播放解码'),
        content: Text(
          '将硬件解码从 ${PlaybackSettings.labelFor(_settings.hwdec)} 切换为 ${PlaybackSettings.labelFor(value)}。如果只是误触，请取消。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认切换'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) {
        setState(() => _fieldRevision++);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final next = _settings.copyWith(hwdec: value);
    setState(() {
      _settings = next;
      _fieldRevision++;
    });
    await widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final commonValue =
        PlaybackSettings.commonDecoderOptions.contains(_settings.hwdec)
            ? _settings.hwdec
            : null;
    final advancedOptions = PlaybackSettings.decoderOptions
        .where(
            (option) => !PlaybackSettings.commonDecoderOptions.contains(option))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          // 取消确认弹窗时设置值可能不变，revision 让表单字段丢弃内部临时选中态。
          key: ValueKey('common:${_settings.hwdec}:$_fieldRevision'),
          initialValue: commonValue,
          hint: Text(
            commonValue == null ? '当前使用高级后端' : '选择播放解码策略',
          ),
          decoration: const InputDecoration(
            labelText: '播放解码策略',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final option in PlaybackSettings.commonDecoderOptions)
              DropdownMenuItem(
                value: option,
                child: Text(PlaybackSettings.commonLabelFor(option)),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              _changeDecoder(value);
            }
          },
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          initiallyExpanded: _showAdvanced,
          onExpansionChanged: (expanded) => _showAdvanced = expanded,
          tilePadding: EdgeInsets.zero,
          title: const Text(
            '高级选项',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text('仅在排查特定显卡或驱动兼容问题时选择具体后端'),
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('advanced:${_settings.hwdec}:$_fieldRevision'),
              initialValue: advancedOptions.contains(_settings.hwdec)
                  ? _settings.hwdec
                  : null,
              decoration: const InputDecoration(
                labelText: '具体解码后端',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final option in advancedOptions)
                  DropdownMenuItem(
                    value: option,
                    child: Text(PlaybackSettings.labelFor(option)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  _changeDecoder(value);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

/**
 * Windows 播放渲染器选择控件。
 *
 * 高影响切换必须先确认，并在保存成功后提供撤销。该控件只保存下一次播放器 Route
 * 使用的偏好，不热拆当前播放器、D3D11 设备或 child HWND。
 */
class PlaybackRendererDropdown extends StatefulWidget {
  const PlaybackRendererDropdown({
    super.key,
    required this.settings,
    required this.onChanged,
    this.windowsNativeRendererAvailable,
  });

  /** 当前完整播放设置，撤销时只恢复渲染器字段。 */
  final PlaybackSettings settings;

  /** 保存确认后的完整播放设置。 */
  final Future<void> Function(PlaybackSettings settings) onChanged;

  /** 测试可覆盖的平台能力；正常运行由桌面平台边界提供。 */
  final bool? windowsNativeRendererAvailable;

  @override
  State<PlaybackRendererDropdown> createState() =>
      _PlaybackRendererDropdownState();
}

class _PlaybackRendererDropdownState extends State<PlaybackRendererDropdown> {
  late PlaybackSettings _settings = widget.settings;
  var _fieldRevision = 0;

  @override
  void didUpdateWidget(covariant PlaybackRendererDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.settings, widget.settings)) {
      _settings = widget.settings;
    }
  }

  /** 确认、保存渲染器偏好；失败或取消时恢复下拉框的已生效值。 */
  Future<void> _changeRenderer(PlayerRendererPreference value) async {
    if (value == _settings.rendererPreference) {
      return;
    }
    final previousPreference = _settings.rendererPreference;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换播放渲染器'),
        content: Text(
          '将渲染器从 ${PlaybackSettings.rendererLabelFor(previousPreference)}'
          ' 切换为 ${PlaybackSettings.rendererLabelFor(value)}。\n\n'
          '两种配置共用 MediaKit Texture；增强配置通过同一个 libmpv 实例'
          '应用高级画质。如果画质滤镜不适合当前设备，可随时切回兼容配置。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认切换'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final next = _settings.copyWith(rendererPreference: value);
    setState(() {
      _settings = next;
      _fieldRevision++;
    });
    try {
      await widget.onChanged(next);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _settings = _settings.copyWith(rendererPreference: previousPreference);
        _fieldRevision++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存渲染器设置失败：$error')),
      );
      return;
    }
    if (!mounted) return;
    // Snackbar 会跨设置 Route 保留；提前捕获持久化回调与恢复快照，避免用户离开
    // 设置页后点击“撤销”时访问已销毁 State.widget。
    final undoSettings = next.copyWith(rendererPreference: previousPreference);
    final saveSettings = widget.onChanged;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        // 切换结果只提供短暂撤销窗口，不能永久占用媒体库底部并要求用户手动关闭。
        duration: const Duration(seconds: 4),
        content: const Text('渲染器已保存，将在下次进入播放器时生效'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => unawaited(
            _undoRendererChange(
              undoSettings: undoSettings,
              saveSettings: saveSettings,
            ),
          ),
        ),
      ),
    );
    // 无障碍模式会让带操作按钮的 Snackbar 跳过系统超时；产品要求该提示始终
    // 自动收起，因此只关闭本控制器，不能误伤之后出现的其它错误提示。
    unawaited(
      Future.any<bool>(<Future<bool>>[
        Future<void>.delayed(const Duration(seconds: 4)).then((_) => true),
        controller.closed.then((_) => false),
      ]).then((shouldClose) {
        if (shouldClose) {
          controller.close();
        }
      }),
    );
  }

  /** 即使设置 Route 已退出，也使用预先捕获的回调恢复渲染器偏好。 */
  Future<void> _undoRendererChange({
    required PlaybackSettings undoSettings,
    required Future<void> Function(PlaybackSettings settings) saveSettings,
  }) async {
    final beforeUndo = _settings;
    if (mounted) {
      setState(() {
        _settings = undoSettings;
        _fieldRevision++;
      });
    }
    try {
      await saveSettings(undoSettings);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _settings = beforeUndo;
        _fieldRevision++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('撤销渲染器设置失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = _settings.rendererPreference;
    final helper = PlaybackSettings.rendererDescriptionFor(selection);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<PlayerRendererPreference>(
          key: ValueKey('renderer:${selection.name}:$_fieldRevision'),
          initialValue: selection,
          decoration: const InputDecoration(
            labelText: '播放渲染器',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final option in const <PlayerRendererPreference>[
              PlayerRendererPreference.mediaKit,
              PlayerRendererPreference.windowsLibmpv,
            ])
              DropdownMenuItem(
                value: option,
                child: Text(PlaybackSettings.rendererLabelFor(option)),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              unawaited(_changeRenderer(value));
            }
          },
        ),
        const SizedBox(height: 8),
        Text(
          helper,
          key: const ValueKey('settings.renderer.helper'),
          style: const TextStyle(color: libraryTextMuted, height: 1.4),
        ),
        const SizedBox(height: 6),
        Text(
          PlaybackSettings.rendererFeaturesFor(selection),
          key: const ValueKey('settings.renderer.features'),
          style: const TextStyle(color: libraryTextMuted, height: 1.4),
        ),
      ],
    );
  }
}
