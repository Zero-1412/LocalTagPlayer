import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/data_backup_settings.dart';
import '../../../models/data_backup_models.dart';
import '../../../widgets/app_theme_tokens.dart';
import '../application/data_backup_controllers.dart';
import '../application/serial_settings_controller.dart';
import 'settings_landing_list.dart';
import 'settings_workspace_theme.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 把备份检查指标翻译为普通用户可执行的安全结论。
 *
 * 记录总数相同只代表数量一致；stale 表示当前用户依赖尚未同步，重复 fingerprint
 * 则只会让自动恢复保守跳过歧义文件，不能把两者混成同一种“损坏”。
 */
@visibleForTesting
String dataBackupIntegritySafetySummary(DataBackupIntegrityReport report) {
  if (!report.sqliteHealthy) {
    return '备份数据库检查异常，暂时不要依赖它执行恢复；请保留现有文件并重新备份。';
  }
  final invalid = report.invalidPayloads + report.missingFingerprints;
  if (invalid > 0) {
    return '有 $invalid 条快照无法安全恢复。现有数据未被修改，请重新备份后再次检查。';
  }
  final pending = report.missingCurrentSnapshots + report.staleCurrentSnapshots;
  if (pending > 0) {
    return '当前备份尚未覆盖最新用户数据（共 $pending 条）。请先执行“立即备份”，完成后重新检查。';
  }
  if (report.ambiguousFingerprints > 0) {
    return '当前用户数据已覆盖；另有 ${report.ambiguousFingerprints} 组重复指纹。'
        '自动恢复会安全跳过这些歧义文件，需要人工确认，不会静默合并。';
  }
  if (report.recoverableSnapshots > 0) {
    return '当前用户数据已覆盖，另保留 ${report.recoverableSnapshots} 条供未来重新扫描时恢复的归档快照。';
  }
  return '当前用户数据已完整覆盖，可作为稳定身份、收藏、播放状态和非文件夹标签的恢复来源。';
}

/**
 * 视频数据备份设置纵向切片。
 *
 * Widget 拥有设置一致性、状态订阅和维护命令 controller 的生命周期，只把数据库、
 * 文件选择和持久化命令作为回调注入。这样 Route 负责 Dialog/SnackBar，应用服务继续
 * 负责跨 Repository 与平台 adapter 的真实副作用。
 */
class DataBackupSettingsWorkspace extends StatefulWidget {
  const DataBackupSettingsWorkspace({
    super.key,
    required this.initialSettings,
    required this.initialStatus,
    required this.statuses,
    required this.onSettingsChanged,
    required this.onRunNow,
    required this.onCheckIntegrity,
    required this.onExport,
  });

  /** Route 打开时的设置快照。 */
  final DataBackupSettings initialSettings;

  /** 订阅建立前用于首帧展示的服务状态。 */
  final DataBackupStatus initialStatus;

  /** 备份应用服务发布的只读状态流。 */
  final Stream<DataBackupStatus> statuses;

  /** 保存完整设置并同步运行时备份服务的应用命令。 */
  final Future<void> Function(DataBackupSettings settings) onSettingsChanged;

  /** 启动现有全量核对的应用命令。 */
  final Future<void> Function() onRunNow;

  /** 执行现有只读完整性检查的应用命令。 */
  final Future<DataBackupIntegrityReport> Function() onCheckIntegrity;

  /** 通过平台 adapter 选择目标并导出；取消选择时返回 null。 */
  final Future<String?> Function() onExport;

  @override
  State<DataBackupSettingsWorkspace> createState() =>
      _DataBackupSettingsWorkspaceState();
}

/** 管理备份设置切片的控制器生命周期与用户反馈。 */
class _DataBackupSettingsWorkspaceState
    extends State<DataBackupSettingsWorkspace> {
  late final SerialSettingsController<DataBackupSettings> _settingsController;
  late final DataBackupStatusController<DataBackupStatus> _statusController;
  late final DataBackupMaintenanceController<DataBackupIntegrityReport>
      _maintenanceController;

  DataBackupSettings get _settings => _settingsController.value;
  DataBackupStatus get _status => _statusController.status;

  @override
  void initState() {
    super.initState();
    _settingsController = SerialSettingsController<DataBackupSettings>(
      initialValue: widget.initialSettings,
      // 读取当前 widget，避免父级更新回调后继续持有旧闭包。
      save: (settings) => widget.onSettingsChanged(settings),
    )..addListener(_handleControllerChanged);
    _statusController = DataBackupStatusController<DataBackupStatus>(
      initialStatus: widget.initialStatus,
      statuses: widget.statuses,
    )..addListener(_handleControllerChanged);
    _maintenanceController =
        DataBackupMaintenanceController<DataBackupIntegrityReport>(
      runNow: () => widget.onRunNow(),
      checkIntegrity: () => widget.onCheckIntegrity(),
      export: () => widget.onExport(),
    )..addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _settingsController
      ..removeListener(_handleControllerChanged)
      ..dispose();
    _statusController
      ..removeListener(_handleControllerChanged)
      ..dispose();
    _maintenanceController
      ..removeListener(_handleControllerChanged)
      ..dispose();
    super.dispose();
  }

  /** controller 发布新快照时只重建当前备份切片。 */
  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /** 乐观切换备份开关；持久化失败时由串行 owner 回滚。 */
  Future<void> _changeEnabled(bool enabled) async {
    try {
      await _settingsController.update(
        _settings.copyWith(enabled: enabled),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存数据备份设置失败：$error')),
        );
      }
    }
  }

  /** 执行只读完整性检查并呈现可操作结论。 */
  Future<void> _checkIntegrity() async {
    try {
      final report = await _maintenanceController.checkIntegrity();
      if (report == null || !mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              Icon(
                report.isHealthy
                    ? Icons.verified_rounded
                    : Icons.warning_amber_rounded,
                color: report.isHealthy ? appAccent : const Color(0xffb26a00),
              ),
              const SizedBox(width: 10),
              Text(report.isHealthy ? '备份检查通过' : '备份检查发现差异'),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  dataBackupIntegritySafetySummary(report),
                  style: const TextStyle(color: libraryTextMuted, height: 1.5),
                ),
                const SizedBox(height: 16),
                _SettingsStatLine(
                  label: 'SQLite',
                  value: report.sqliteHealthy ? '正常' : '异常',
                ),
                _SettingsStatLine(
                  label: '备份记录 / 主库视频',
                  value: '${report.backupRecords} / ${report.currentVideos}',
                ),
                _SettingsStatLine(
                  label: '未覆盖当前视频',
                  value: _formatCount(report.missingCurrentSnapshots),
                ),
                _SettingsStatLine(
                  label: '内容待更新',
                  value: _formatCount(report.staleCurrentSnapshots),
                ),
                _SettingsStatLine(
                  label: '损坏 / 缺失指纹',
                  value:
                      '${report.invalidPayloads + report.missingFingerprints}',
                ),
                _SettingsStatLine(
                  label: '保留供未来恢复',
                  value: _formatCount(report.recoverableSnapshots),
                ),
                _SettingsStatLine(
                  label: '重复指纹组（自动跳过）',
                  value: _formatCount(report.ambiguousFingerprints),
                ),
              ],
            ),
          ),
          actions: [
            if (!report.isHealthy && _settings.enabled)
              TextButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(_runNow());
                },
                icon: const Icon(Icons.backup_rounded),
                label: const Text('立即备份'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份完整性检查失败：$error')),
        );
      }
    }
  }

  /** 启动现有全量备份并展示启动阶段错误。 */
  Future<void> _runNow() async {
    try {
      await _maintenanceController.runNow();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动视频数据备份失败：$error')),
        );
      }
    }
  }

  /** 导出便携 JSON；用户取消文件选择时不显示成功或错误。 */
  Future<void> _export() async {
    try {
      final outcome = await _maintenanceController.export();
      if (mounted && outcome?.path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('视频依赖备份已导出')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出视频依赖备份失败：$error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return _DataBackupSettingsPanel(
      enabled: _settings.enabled,
      maintenanceRunning: _maintenanceController.busy,
      statusLabel: _phaseLabel(status),
      progressLabel:
          status.total == 0 ? '0' : '${status.processed} / ${status.total}',
      pendingLabel: _formatCount(status.pending),
      lastCompletedLabel: _timeLabel(status.lastCompletedAt),
      progress: status.phase == DataBackupPhase.running && status.total > 0
          ? (status.processed / status.total).clamp(0, 1)
          : null,
      onEnabledChanged: (value) => unawaited(_changeEnabled(value)),
      onRunNow: () => unawaited(_runNow()),
      onCheckIntegrity: () => unawaited(_checkIntegrity()),
      onExport: () => unawaited(_export()),
    );
  }
}

/** 设置页阶段文案不展示路径或标签内容。 */
String _phaseLabel(DataBackupStatus status) => switch (status.phase) {
      DataBackupPhase.disabled => '已关闭',
      DataBackupPhase.idle => '后台任务空闲',
      DataBackupPhase.running => '后台备份中',
      DataBackupPhase.pausedForPlayback => '播放期间已暂停',
      DataBackupPhase.failed => '上次执行失败',
    };

/** 使用固定本地时间格式展示最近完成时间。 */
String _timeLabel(DateTime? value) {
  if (value == null) {
    return '尚未完成';
  }
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/** 用紧凑千分位展示备份统计，不依赖媒体库页面工具。 */
String _formatCount(int count) {
  final digits = count.toString();
  return digits.replaceAllMapped(
    RegExp(r'(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}

/**
 * 构建视频数据备份面板的 focused widget test 容器。
 *
 * 测试只注入可见状态和既有动作回调，不打开备份数据库、不选择导出路径。
 */
@visibleForTesting
Widget dataBackupSettingsSmokeHarness({
  bool enabled = true,
  bool maintenanceRunning = false,
  String statusLabel = '后台备份空闲',
  String progressLabel = '11163 / 11163',
  String pendingLabel = '0',
  String lastCompletedLabel = '刚刚',
  double? progress,
  TextScaler textScaler = TextScaler.noScaling,
  ValueChanged<bool>? onEnabledChanged,
  VoidCallback? onRunNow,
  VoidCallback? onCheckIntegrity,
  VoidCallback? onExport,
}) {
  return MaterialApp(
    theme: settingsWorkspaceTheme(ThemeData(useMaterial3: true)),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(1000, 900),
        textScaler: textScaler,
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _DataBackupSettingsPanel(
            enabled: enabled,
            maintenanceRunning: maintenanceRunning,
            statusLabel: statusLabel,
            progressLabel: progressLabel,
            pendingLabel: pendingLabel,
            lastCompletedLabel: lastCompletedLabel,
            progress: progress,
            onEnabledChanged: onEnabledChanged ?? (_) {},
            onRunNow: onRunNow ?? () {},
            onCheckIntegrity: onCheckIntegrity ?? () {},
            onExport: onExport ?? () {},
          ),
        ),
      ),
    ),
  );
}

/** 只呈现备份快照和命令入口，不直接读取数据库或平台资源。 */
class _DataBackupSettingsPanel extends StatelessWidget {
  const _DataBackupSettingsPanel({
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
class _SettingsStatLine extends StatelessWidget {
  const _SettingsStatLine({required this.label, required this.value});

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
