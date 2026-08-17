import 'package:flutter/material.dart';

// ignore_for_file: slash_for_doc_comments

/** 结果视图切换器的单个图标，只负责绘制，不单独承担点击命中。 */
class ResultViewToggleIcon extends StatelessWidget {
  const ResultViewToggleIcon({
    super.key,
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
