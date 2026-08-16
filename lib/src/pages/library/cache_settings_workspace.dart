import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/data_backup_settings.dart';
import '../../core/playback_settings.dart';
import '../../features/settings/presentation/cache_diagnostics_settings_card.dart';
import '../../features/settings/presentation/data_backup_settings_workspace.dart';
import '../../features/settings/presentation/delete_file_settings_panel.dart';
import '../../features/settings/presentation/playback_and_decoding_settings_card.dart';
import '../../features/settings/presentation/playback_quality_settings_panel.dart';
import '../../features/settings/presentation/playback_stream_cache_card.dart';
import '../../features/settings/presentation/player_interaction_settings_panels.dart';
import '../../features/settings/presentation/settings_landing_list.dart';
import '../../features/settings/presentation/settings_workspace_scaffold.dart';
import '../../models/data_backup_models.dart';
import '../../services/media/thumbnail_service.dart';
import '../../features/update/domain/app_update_proxy_settings.dart';
import '../../features/update/domain/app_update_service.dart';
import '../../features/update/presentation/about_settings_page.dart';
import '../../features/update/presentation/update_proxy_settings_page.dart';

// ignore_for_file: slash_for_doc_comments

/** 设置 Route 可进入的功能分区。 */
enum CacheSettingsSection {
  home,
  playback,
  videoQuality,
  playerInteraction,
  fileDeletion,
  dataBackup,
  cache,
  updateProxy,
  about,
}

/**
 * 设置 Route 的只读工作区装配。
 *
 * 组件只消费设置、诊断和备份快照并发出回调；持久化 controller、缓存维护命令、
 * 快捷键冲突校验和反馈仍由外层设置 Route 的 State owner 负责。
 */
class CacheSettingsWorkspace extends StatelessWidget {
  const CacheSettingsWorkspace({
    super.key,
    required this.section,
    required this.title,
    required this.settings,
    required this.shortcutErrors,
    required this.unavailableCleanupRunning,
    required this.cacheLoading,
    required this.cacheHasError,
    required this.cacheStats,
    required this.cacheActionRunning,
    required this.dataBackupSettings,
    required this.dataBackupStatus,
    required this.dataBackupStatuses,
    required this.updateService,
    required this.onOpenSection,
    required this.onBack,
    required this.onRefreshCache,
    required this.onPlaybackSettingsChanged,
    required this.onConfirmDeleteChanged,
    required this.onAutoCleanupChanged,
    required this.onFullscreenQueueChanged,
    required this.onResetShortcuts,
    required this.onShortcutCaptured,
    required this.onRetryFailures,
    required this.onClearFailures,
    required this.onGenerateMissing,
    required this.onDataBackupSettingsChanged,
    required this.onRunDataBackupNow,
    required this.onCheckDataBackupIntegrity,
    required this.onExportDataBackup,
  });

  /** 当前功能分区。 */
  final CacheSettingsSection section;
  /** 当前二级页标题。 */
  final String title;
  /** 普通播放设置的只读快照。 */
  final PlaybackSettings settings;
  /** 快捷键动作对应的就地错误快照。 */
  final Map<PlayerShortcutAction, String> shortcutErrors;
  /** 失效媒体清理是否占用命令通道。 */
  final bool unavailableCleanupRunning;
  /** 缓存统计是否正在读取。 */
  final bool cacheLoading;
  /** 缓存统计读取是否失败。 */
  final bool cacheHasError;
  /** 最近一次成功读取的缓存统计。 */
  final CacheStats? cacheStats;
  /** 缓存重试或清理命令是否正在执行。 */
  final bool cacheActionRunning;
  /** 数据备份开关的只读快照。 */
  final DataBackupSettings dataBackupSettings;
  /** 数据备份任务的当前状态。 */
  final DataBackupStatus dataBackupStatus;
  /** 数据备份任务后续状态流。 */
  final Stream<DataBackupStatus> dataBackupStatuses;
  /** 关于页与更新代理页共享的应用更新服务边界。 */
  final AppUpdateService updateService;
  /** 从设置首页进入指定分区。 */
  final ValueChanged<CacheSettingsSection> onOpenSection;
  /** 返回设置首页或关闭 Route。 */
  final VoidCallback onBack;
  /** 重新读取缓存统计。 */
  final VoidCallback onRefreshCache;
  /** 提交普通播放设置意图。 */
  final Future<void> Function(PlaybackSettings settings)
      onPlaybackSettingsChanged;
  /** 提交删除前确认开关意图。 */
  final ValueChanged<bool> onConfirmDeleteChanged;
  /** 提交自动清理失效记录意图；命令繁忙时为 null。 */
  final ValueChanged<bool>? onAutoCleanupChanged;
  /** 提交全屏队列开关意图。 */
  final ValueChanged<bool> onFullscreenQueueChanged;
  /** 恢复默认快捷键。 */
  final Future<void> Function() onResetShortcuts;
  /** 校验并提交一项录制快捷键。 */
  final bool Function(PlayerShortcutAction action, String key)
      onShortcutCaptured;
  /** 重试当前缓存失败快照。 */
  final ValueChanged<CacheStats> onRetryFailures;
  /** 清除当前缓存失败标记。 */
  final ValueChanged<CacheStats> onClearFailures;
  /** 启动当前媒体库的缺失缓存补全。 */
  final ValueChanged<CacheStats> onGenerateMissing;
  /** 提交数据备份设置意图。 */
  final Future<void> Function(DataBackupSettings settings)
      onDataBackupSettingsChanged;
  /** 立即执行一轮数据备份。 */
  final Future<void> Function() onRunDataBackupNow;
  /** 执行只读备份完整性检查。 */
  final Future<DataBackupIntegrityReport> Function() onCheckDataBackupIntegrity;
  /** 选择路径并导出便携备份。 */
  final Future<String?> Function() onExportDataBackup;

  @override
  Widget build(BuildContext context) {
    final isHome = section == CacheSettingsSection.home;
    final proxySettingsService = updateService is AppUpdateProxySettingsService
        ? updateService as AppUpdateProxySettingsService
        : null;
    return SettingsWorkspaceScaffold(
      isHome: isHome,
      title: title,
      showRefreshAction: section == CacheSettingsSection.cache,
      onBack: onBack,
      onRefresh: onRefreshCache,
      child: isHome
          ? SettingsLandingList(
              resumeBehavior: settings.resumeBehavior,
              rendererPreference: settings.rendererPreference,
              confirmBeforeDeletingVideo: settings.confirmBeforeDeletingVideo,
              autoRemoveMissingOrUnreadableVideos:
                  settings.autoRemoveMissingOrUnreadableVideos,
              onOpenPlayback: () =>
                  onOpenSection(CacheSettingsSection.playback),
              onOpenVideoQuality: () =>
                  onOpenSection(CacheSettingsSection.videoQuality),
              onOpenPlayerInteraction: () =>
                  onOpenSection(CacheSettingsSection.playerInteraction),
              onOpenFileDeletion: () =>
                  onOpenSection(CacheSettingsSection.fileDeletion),
              onOpenDataBackup: () =>
                  onOpenSection(CacheSettingsSection.dataBackup),
              onOpenCache: () => onOpenSection(CacheSettingsSection.cache),
              onOpenUpdateProxy: () =>
                  onOpenSection(CacheSettingsSection.updateProxy),
              onOpenAbout: () => onOpenSection(CacheSettingsSection.about),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (section == CacheSettingsSection.playback) ...[
                  PlaybackAndDecodingSettingsCard(
                    settings: settings,
                    onChanged: onPlaybackSettingsChanged,
                  ),
                  const SizedBox(height: 16),
                  PlaybackStreamCacheCard(
                    settings: settings,
                    onChanged: (value) {
                      unawaited(onPlaybackSettingsChanged(value));
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                if (section == CacheSettingsSection.videoQuality) ...[
                  PlaybackQualitySettingsPanel(
                    settings: settings,
                    onChanged: (value) {
                      unawaited(onPlaybackSettingsChanged(value));
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                if (section == CacheSettingsSection.dataBackup) ...[
                  DataBackupSettingsWorkspace(
                    initialSettings: dataBackupSettings,
                    initialStatus: dataBackupStatus,
                    statuses: dataBackupStatuses,
                    onSettingsChanged: onDataBackupSettingsChanged,
                    onRunNow: onRunDataBackupNow,
                    onCheckIntegrity: onCheckDataBackupIntegrity,
                    onExport: onExportDataBackup,
                  ),
                  const SizedBox(height: 16),
                ],
                if (section == CacheSettingsSection.fileDeletion) ...[
                  DeleteFileSettingsPanel(
                    confirmBeforeDeletingVideo:
                        settings.confirmBeforeDeletingVideo,
                    autoRemoveMissingOrUnreadableVideos:
                        settings.autoRemoveMissingOrUnreadableVideos,
                    onConfirmChanged: onConfirmDeleteChanged,
                    onAutoRemoveMissingOrUnreadableChanged:
                        unavailableCleanupRunning ? null : onAutoCleanupChanged,
                  ),
                  const SizedBox(height: 16),
                ],
                if (section == CacheSettingsSection.playerInteraction) ...[
                  FullscreenQueueSettingsCard(
                    enabled: settings.fullscreenQueueEdgeHoverEnabled,
                    onChanged: onFullscreenQueueChanged,
                  ),
                  const SizedBox(height: 16),
                  PlayerShortcutsSettingsCard(
                    shortcuts: settings.shortcuts,
                    errors: shortcutErrors,
                    onReset: onResetShortcuts,
                    onCaptured: onShortcutCaptured,
                  ),
                  const SizedBox(height: 16),
                ],
                if (section == CacheSettingsSection.cache)
                  CacheDiagnosticsSettingsCard(
                    loading: cacheLoading,
                    hasError: cacheHasError,
                    stats: cacheStats,
                    cacheActionRunning: cacheActionRunning,
                    onRetry: onRefreshCache,
                    onRetryFailures: onRetryFailures,
                    onClearFailures: onClearFailures,
                    onGenerateMissing: onGenerateMissing,
                  ),
                if (section == CacheSettingsSection.updateProxy)
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height - 120,
                    child: proxySettingsService == null
                        ? const Center(child: Text('当前更新服务不支持代理设置'))
                        : UpdateProxySettingsPage(
                            proxySettingsService: proxySettingsService,
                          ),
                  ),
                if (section == CacheSettingsSection.about)
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height - 120,
                    child: AboutSettingsPage(updateService: updateService),
                  ),
              ],
            ),
    );
  }
}
