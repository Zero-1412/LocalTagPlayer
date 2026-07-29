import 'package:flutter/material.dart';

import '../../../widgets/app_theme_tokens.dart';
import 'settings_landing_list.dart';

// ignore_for_file: slash_for_doc_comments

/** 只呈现备份快照和命令入口，不直接读取数据库或平台资源。 */
class DataBackupSettingsPanel extends StatelessWidget {
  const DataBackupSettingsPanel({
    super.key,
    required this.enabled,
    required this.maintenanceRunning,
    required this.statusLabel,
    required this.progressLabel,
    required this.pendingLabel,
    required this.lastCompletedLabel,
    required this.progress,
    required this.onEnabledChanged,
    required this.onRunNow,
    required this.onCheckIntegrity,
    required this.onExport,
  });

  final bool enabled;
  final bool maintenanceRunning;
  final String statusLabel;
  final String progressLabel;
  final String pendingLabel;
  final String lastCompletedLabel;
  final double? progress;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onRunNow;
  final VoidCallback onCheckIntegrity;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('settings.dataBackup.card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              key: const ValueKey('settings.dataBackup.toggle'),
              contentPadding: EdgeInsets.zero,
              value: enabled,
              onChanged: onEnabledChanged,
              secondary: DecoratedBox(
                decoration: BoxDecoration(
                  color: appAccentViolet.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: const SizedBox.square(
                  dimension: 42,
                  child: Icon(Icons.shield_outlined, color: libraryAccent),
                ),
              ),
              title: const Text(
                '视频数据备份',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              subtitle: const Padding(
                padding: EdgeInsets.only(top: 5),
                child: Text(
                  '独立保存视频身份与用户维护数据，主媒体库仍是唯一业务写入源。',
                  style: TextStyle(color: libraryTextMuted, height: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const _DataBackupScopeSummary(),
            const SizedBox(height: 20),
            const SettingsGroupTitle(title: '同步状态'),
            const SizedBox(height: 10),
            _DataBackupMetricGrid(
              statusLabel: statusLabel,
              progressLabel: progressLabel,
              pendingLabel: pendingLabel,
              lastCompletedLabel: lastCompletedLabel,
            ),
            if (progress != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.capsule),
                child: LinearProgressIndicator(minHeight: 5, value: progress),
              ),
            ],
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),
            const Text(
              '维护动作',
              style: TextStyle(
                color: libraryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              '完整性检查只读取并报告差异；导出不包含本地路径或视频文件。',
              style: TextStyle(color: libraryTextMuted, height: 1.4),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  key: const ValueKey('settings.dataBackup.runNow'),
                  onPressed: enabled && !maintenanceRunning ? onRunNow : null,
                  icon: const Icon(Icons.backup_rounded),
                  label: const Text('立即备份'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('settings.dataBackup.checkIntegrity'),
                  onPressed: maintenanceRunning ? null : onCheckIntegrity,
                  icon: const Icon(Icons.verified_user_rounded),
                  label: const Text('检查完整性'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('settings.dataBackup.export'),
                  onPressed: maintenanceRunning ? null : onExport,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('导出备份'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/** 明确备份覆盖范围与不包含项，避免用户把它误认为媒体文件副本。 */
class _DataBackupScopeSummary extends StatelessWidget {
  const _DataBackupScopeSummary();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: librarySurfaceAlt.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: libraryBorder),
      ),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_reset_rounded, color: libraryAccent, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '保留稳定身份、收藏、播放状态及非文件夹标签。移除目录后仍可恢复；'
                '明确删除单个视频时会同步清理对应备份。\n'
                '不复制视频文件，也不改变 folder 标签来源。',
                style: TextStyle(color: libraryTextMuted, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/** 按可用宽度在 4/2/1 列间重排备份状态，不压缩文字。 */
class _DataBackupMetricGrid extends StatelessWidget {
  const _DataBackupMetricGrid({
    required this.statusLabel,
    required this.progressLabel,
    required this.pendingLabel,
    required this.lastCompletedLabel,
  });

  final String statusLabel;
  final String progressLabel;
  final String pendingLabel;
  final String lastCompletedLabel;

  @override
  Widget build(BuildContext context) {
    final metrics = <(String, String)>[
      ('状态', statusLabel),
      ('本轮进度', progressLabel),
      ('等待同步', pendingLabel),
      ('最近完成', lastCompletedLabel),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 4
            : constraints.maxWidth >= 460
                ? 2
                : 1;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _DataBackupMetric(
                  label: metric.$1,
                  value: metric.$2,
                ),
              ),
          ],
        );
      },
    );
  }
}

/** 单个备份状态指标；纵向排版允许 150% 文字自然换行。 */
class _DataBackupMetric extends StatelessWidget {
  const _DataBackupMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: libraryBackground.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: libraryTextMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                color: libraryText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/** 完整性弹窗中的只读统计行。 */
class DataBackupSettingsStatLine extends StatelessWidget {
  const DataBackupSettingsStatLine({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: libraryTextMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: libraryText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
