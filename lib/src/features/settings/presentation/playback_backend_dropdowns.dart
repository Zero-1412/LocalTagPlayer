import 'package:flutter/material.dart';

import '../../../core/playback_settings.dart';

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
          '将硬件解码从 ${PlaybackSettings.labelFor(_settings.hwdec)} '
          '切换为 ${PlaybackSettings.labelFor(value)}。如果只是误触，请取消。',
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
          (option) => !PlaybackSettings.commonDecoderOptions.contains(option),
        )
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
