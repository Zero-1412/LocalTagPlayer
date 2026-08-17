import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';
import 'library_reference_icon_button.dart';
import 'library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

/**
 * 媒体结果网格/列表视图切换器。
 *
 * 本组件只维护短暂的滑块视觉进度；最终视图状态仍由页面 owner 持有和持久化。
 */
@visibleForTesting
class ResultViewToggle extends StatefulWidget {
  const ResultViewToggle({
    super.key,
    required this.dense,
    required this.onChanged,
  });

  /** true 表示使用紧凑列表，false 表示使用卡片网格。 */
  final bool dense;

  /** 请求切换结果视图；整个滑块每次点击只翻转一次当前状态。 */
  final ValueChanged<bool> onChanged;

  @override
  State<ResultViewToggle> createState() => _ResultViewToggleState();
}

/**
 * 网格/列表滑块状态。
 *
 * 滑块先在独立动画控制器中完成连续位移，再提交会触发结果区重布局的视图状态；
 * 快速重复点击会从当前进度反向运行，避免重型网格/列表切换阻塞滑块首帧。
 */
class _ResultViewToggleState extends State<ResultViewToggle>
    with SingleTickerProviderStateMixin {
  static const _slideDuration = Duration(milliseconds: 180);
  late final AnimationController _controller;
  late bool _visualDense;
  var _transitionVersion = 0;

  @override
  void initState() {
    super.initState();
    _visualDense = widget.dense;
    _controller = AnimationController(
      vsync: this,
      value: widget.dense ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant ResultViewToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dense == widget.dense || widget.dense == _visualDense) {
      return;
    }
    // 外部状态变化时同步视觉目标，但不反向触发页面回调。
    _transitionVersion += 1;
    setState(() => _visualDense = widget.dense);
    _animateTo(widget.dense);
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  /** 根据剩余距离计算时长，让快速反向保持与正向一致的移动速度。 */
  Duration _remainingDuration(double target) {
    final distance = (_controller.value - target).abs();
    return Duration(
      milliseconds:
          math.max(1, (_slideDuration.inMilliseconds * distance).round()),
    );
  }

  /** 从当前进度平滑移动到目标，不重置动画端点。 */
  TickerFuture _animateTo(bool dense) {
    final target = dense ? 1.0 : 0.0;
    return _controller.animateTo(
      target,
      duration: _remainingDuration(target),
      curve: Curves.easeOutCubic,
    );
  }

  /** 响应整块控件点击；动画稳定后才提交较重的结果视图切换。 */
  Future<void> _toggle() async {
    final targetDense = !_visualDense;
    final version = ++_transitionVersion;
    setState(() => _visualDense = targetDense);
    try {
      await _animateTo(targetDense).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted ||
        version != _transitionVersion ||
        _visualDense != targetDense) {
      return;
    }
    if (widget.dense != targetDense) {
      widget.onChanged(targetDense);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    final tooltip = _visualDense ? '切换为网格视图' : '切换为列表视图';
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: LibrarySmokeKeys.resultViewToggle,
            borderRadius: BorderRadius.circular(10),
            excludeFromSemantics: true,
            onTap: _toggle,
            child: Ink(
              width: 72,
              height: libraryTopBarControlHeight,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: librarySurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: libraryBorder),
              ),
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final progress = _controller.value;
                    // 选中端只增加一层低对比度色洗；高对比度仍依赖图标和位置表达状态。
                    return Stack(
                      children: [
                        Transform.translate(
                          offset: Offset(32 * progress, 0),
                          child: Container(
                            key: LibrarySmokeKeys.resultViewToggleThumb,
                            width: 30,
                            height: 32,
                            decoration: BoxDecoration(
                              color: accessibility.highContrast || !_visualDense
                                  ? librarySurfaceAlt
                                  : appAccentViolet.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _TopViewIcon(
                                icon: Icons.grid_view_rounded,
                                color: Color.lerp(
                                  appAccentViolet,
                                  libraryTextMuted,
                                  progress,
                                )!,
                              ),
                              _TopViewIcon(
                                icon: Icons.view_list_rounded,
                                color: Color.lerp(
                                  libraryTextMuted,
                                  appAccentViolet,
                                  progress,
                                )!,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/** 滑块内只负责绘制状态的图标，不单独承担点击命中。 */
class _TopViewIcon extends StatelessWidget {
  const _TopViewIcon({
    required this.icon,
    required this.color,
  });

  /** 当前布局类型对应的图标。 */
  final IconData icon;

  /** 颜色直接跟随滑块控制器插值，避免额外隐式动画相互抢帧。 */
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 32,
      child: Center(
        child: Icon(
          icon,
          size: 18,
          color: color,
        ),
      ),
    );
  }
}
