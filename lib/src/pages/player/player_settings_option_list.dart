import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 二级设置中的导航行，右侧同时展示当前已经生效的全局值。 */
class PlayerSettingsNavigationRow extends StatelessWidget {
  const PlayerSettingsNavigationRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  /** 设置名称。 */
  final String label;

  /** 当前生效值。 */
  final String value;

  /** 进入下一层列表的回调。 */
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: playerText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: playerTextMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 21,
                color: playerTextMuted,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/**
 * 单一设置项的三级选择列表。
 *
 * 选项数量很小，使用固定行高直接构建；选择只重绘浮层与视频表面，不触发
 * filtered queue、媒体详情或缩略图队列重算。
 */
class PlayerSettingsOptionList<T> extends StatelessWidget {
  const PlayerSettingsOptionList({
    super.key,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.keyFor,
    required this.onSelected,
    this.iconFor,
  });

  /** 当前列表允许选择的稳定值。 */
  final List<T> values;

  /** 当前已经生效的值。 */
  final T selected;

  /** 将设置值转换为用户可读文案。 */
  final String Function(T value) labelFor;

  /** 为 focused test 和自动化点击提供稳定键。 */
  final Key Function(T value) keyFor;

  /** 用户选择新值后的回调。 */
  final ValueChanged<T> onSelected;

  /** 可选的辅助图标映射；倍速列表无需图标。 */
  final IconData Function(T value)? iconFor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in values)
            _PlayerSettingsOptionRow(
              key: keyFor(value),
              label: labelFor(value),
              icon: iconFor?.call(value),
              selected: value == selected,
              onTap: () => onSelected(value),
            ),
        ],
      ),
    );
  }
}

/** 三级列表的单个选项；勾选标记明确表示当前真实生效状态。 */
class _PlayerSettingsOptionRow extends StatelessWidget {
  const _PlayerSettingsOptionRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  /** 选项文案。 */
  final String label;

  /** 是否为当前全局值。 */
  final bool selected;

  /** 点击选择回调。 */
  final VoidCallback onTap;

  /** 可选的比例模式图标。 */
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? playerText : playerTextMuted;
    return Material(
      color: selected
          ? appAccentViolet.withValues(alpha: 0.20)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 12),
              if (icon != null) ...[
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  size: 19,
                  color: appAccentViolet,
                ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}
