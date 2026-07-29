import 'package:flutter/material.dart';

import '../../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 缓存诊断页的只读标题与健康状态叶节点。
 *
 * 该组件只渲染调用方传入的状态快照，不读取磁盘、不创建缓存任务，也不拥有刷新、重试或
 * 清理命令；状态所有权和生命周期由外部只读 controller 管理。
 */
class CacheDiagnosticsHeader extends StatelessWidget {
  const CacheDiagnosticsHeader({
    super.key,
    required this.statusLabel,
    required this.statusColor,
  });

  /** 当前缓存服务状态的简短文字。 */
  final String statusLabel;

  /** 状态图标与角标的非唯一颜色编码。 */
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final title = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.image_outlined, color: statusColor, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '缩略图缓存',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              Text(
                '查看有效缓存覆盖、后台任务和可恢复失败，不会主动启动生成。',
                style: TextStyle(color: libraryTextMuted, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
    final badge = _CacheStatusBadge(
      label: statusLabel,
      color: statusColor,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // 窄窗或大文字下把状态移到下一行，避免压缩标题说明。
        if (constraints.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: badge),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 12),
            badge,
          ],
        );
      },
    );
  }
}

/** 同时使用图标和文字表达缓存状态，避免只依赖颜色。 */
class _CacheStatusBadge extends StatelessWidget {
  const _CacheStatusBadge({required this.label, required this.color});

  /** 状态文字。 */
  final String label;

  /** 状态强调色。 */
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(AppRadius.capsule),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
