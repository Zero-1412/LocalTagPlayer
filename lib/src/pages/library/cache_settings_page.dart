import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/data_backup_settings.dart';
import '../../core/playback_settings.dart';
import '../../features/update/domain/app_update_service.dart';
import '../../features/settings/application/cache_diagnostics_controller.dart';
import '../../features/settings/application/cache_diagnostics_maintenance_controller.dart';
import '../../features/settings/application/playback_settings_controller.dart';
import '../../features/settings/presentation/cache_diagnostics_snapshot_view.dart';
import '../../features/settings/presentation/settings_workspace_theme.dart';
import '../../models/data_backup_models.dart';
import '../../models/video_item.dart';
import '../../services/library/library_application_facade.dart';
import '../../services/media/thumbnail_service.dart';
import '../../widgets/maintenance_feedback.dart';
import 'cache_settings_workspace.dart';

// ignore_for_file: slash_for_doc_comments

/** 返回快捷键冲突说明；null 表示可安全保存且不会覆盖其它动作。 */
@visibleForTesting
String? playerShortcutConflictMessage({
  required PlayerShortcutAction action,
  required String shortcut,
  required Map<PlayerShortcutAction, String> bindings,
}) {
  final reservedAction = PlaybackSettings.reservedShortcuts[shortcut];
  if (reservedAction != null) {
    return '与系统保留操作“$reservedAction”冲突，请按其它按键';
  }
  for (final entry in bindings.entries) {
    if (entry.key != action && entry.value == shortcut) {
      return '与“${PlaybackSettings.shortcutActionLabel(entry.key)}”冲突，请按其它按键';
    }
  }
  return null;
}

/**
 * 设置 Route 的状态与命令 owner。
 *
 * 页面持有普通设置、缓存诊断和维护 controller，并把只读快照与回调交给展示工作区。
 */
class CacheSettingsPage extends StatefulWidget {
  const CacheSettingsPage({
    super.key,
    required this.store,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onPlaybackSettingsChanged,
    required this.dataBackupSettings,
    required this.onDataBackupSettingsChanged,
    required this.onRunDataBackupNow,
    required this.onCheckDataBackupIntegrity,
    required this.onExportDataBackup,
    required this.updateService,
  });

  /** 缓存统计、失效记录清理和数据备份使用的媒体库 facade。 */
  final LibraryApplicationFacade store;

  /** 缓存统计与失败重试使用的缩略图服务。 */
  final ThumbnailService thumbnailService;

  /** 打开 Route 时的普通播放设置快照。 */
  final PlaybackSettings playbackSettings;

  /** 保存普通播放设置并同步外层 Route。 */
  final Future<void> Function(PlaybackSettings settings)
      onPlaybackSettingsChanged;

  /** 当前视频依赖备份开关。 */
  final DataBackupSettings dataBackupSettings;

  /** 保存开关并同步后台服务。 */
  final Future<void> Function(DataBackupSettings settings)
      onDataBackupSettingsChanged;

  /** 用户显式启动新一轮全量核对。 */
  final Future<void> Function() onRunDataBackupNow;

  /** 用户显式执行只读完整性检查。 */
  final Future<DataBackupIntegrityReport> Function() onCheckDataBackupIntegrity;

  /** 选择目标并写出便携备份；取消选择时返回 null。 */
  final Future<String?> Function() onExportDataBackup;

  /** 关于页使用的更新边界；测试可注入，正常运行由组合根或默认实现提供。 */
  final AppUpdateService updateService;

  @override
  State<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends State<CacheSettingsPage> {
  /** 当前显示的设置首页或功能二级页。 */
  CacheSettingsSection _section = CacheSettingsSection.home;
  /** 普通播放设置的唯一可写 owner；不包含备份或缓存任务状态。 */
  late final PlaybackSettingsController _playbackSettingsController;
  PlaybackSettings get _settings => _playbackSettingsController.settings;
  /** 缓存统计读取的 latest-only owner；不包含重试或清理命令。 */
  late final CacheDiagnosticsController<CacheStats> _cacheDiagnosticsController;
  /** 缓存重试/清理与 Repository 写入的互斥 owner。 */
  late final CacheDiagnosticsMaintenanceController<VideoItem>
      _cacheMaintenanceController;
  /** 自动清理运行期间锁定开关，避免重复删除同一批稳定身份。 */
  bool _unavailableCleanupRunning = false;

  /** 快捷键录制冲突按动作就地展示，成功保存或恢复默认后清除。 */
  final Map<PlayerShortcutAction, String> _shortcutErrors = {};

  @override
  void initState() {
    super.initState();
    _playbackSettingsController = PlaybackSettingsController(
      initialSettings: widget.playbackSettings,
      // 通过当前 widget 转发，避免父级重建并替换回调后继续调用旧闭包。
      save: (settings) => widget.onPlaybackSettingsChanged(settings),
    )..addListener(_handleSettingsStateChanged);
    _cacheDiagnosticsController = CacheDiagnosticsController<CacheStats>(
      load: () => widget.thumbnailService.statsFor(widget.store.videos.values),
    )..addListener(_handleSettingsStateChanged);
    unawaited(_cacheDiagnosticsController.refresh());
    _cacheMaintenanceController =
        CacheDiagnosticsMaintenanceController<VideoItem>(
      retryFailures: widget.thumbnailService.retryFailed,
      clearFailures: widget.thumbnailService.clearFailures,
      persistChanges: widget.store.upsertVideos,
      isFailureResolved: (item) => item.thumbnailError == null,
      restoreFailure: (item, reason) => item.thumbnailError = reason,
    )..addListener(_handleSettingsStateChanged);
  }

  @override
  void dispose() {
    _playbackSettingsController
      ..removeListener(_handleSettingsStateChanged)
      ..dispose();
    _cacheDiagnosticsController
      ..removeListener(_handleSettingsStateChanged)
      ..dispose();
    _cacheMaintenanceController
      ..removeListener(_handleSettingsStateChanged)
      ..dispose();
    super.dispose();
  }

  /** settings controller 发布快照时只重建当前设置 Route。 */
  void _handleSettingsStateChanged() {
    if (mounted) setState(() {});
  }

  void _refreshStats() {
    unawaited(_cacheDiagnosticsController.refresh());
  }

  /** 定向重试当前统计快照中的失败项，并持久化已清理的旧失败标记。 */
  Future<void> _retryFailedThumbnails(CacheStats stats) async {
    if (_cacheMaintenanceController.busy || stats.failures.isEmpty) {
      return;
    }
    try {
      final outcome = await _cacheMaintenanceController.retry(
        stats.failures.map(
          (failure) => CacheFailureCommandTarget<VideoItem>(
            item: failure.item,
            reason: failure.reason,
          ),
        ),
      );
      if (outcome == null || !mounted) {
        return;
      }
      showMaintenanceSnackBar(
        context,
        message: cacheRetryOutcomeLabel(outcome),
      );
    } catch (error) {
      if (mounted) {
        showMaintenanceSnackBar(
          context,
          message: '重试失败项时出错：$error',
        );
      }
    } finally {
      if (mounted) {
        unawaited(_cacheDiagnosticsController.refresh());
      }
    }
  }

  /** 清除当前失败标记但不删除视频或缓存文件，并通过 Repository 保存结果。 */
  Future<void> _clearThumbnailFailureMarkers(CacheStats stats) async {
    if (_cacheMaintenanceController.busy || stats.failures.isEmpty) {
      return;
    }
    try {
      final outcome = await _cacheMaintenanceController.clear(
        stats.failures.map(
          (failure) => CacheFailureCommandTarget<VideoItem>(
            item: failure.item,
            reason: failure.reason,
          ),
        ),
      );
      if (outcome == null || !mounted) {
        return;
      }
      showMaintenanceSnackBar(
        context,
        message: cacheClearOutcomeLabel(outcome),
      );
    } catch (error) {
      if (mounted) {
        showMaintenanceSnackBar(
          context,
          message: '清除失败标记时出错：$error',
        );
      }
    } finally {
      if (mounted) {
        unawaited(_cacheDiagnosticsController.refresh());
      }
    }
  }

  /** 用户显式启动缺失缓存补全；服务内部按候选窗口和资源预算持续推进。 */
  void _generateMissingThumbnails(CacheStats stats) {
    if (_cacheMaintenanceController.busy ||
        stats.missing <= 0 ||
        stats.backgroundGenerationActive ||
        stats.active > 0 ||
        stats.queued > 0 ||
        stats.pendingBackgroundRequests > 0) {
      return;
    }
    widget.thumbnailService.generateMissing(widget.store.videos.values);
    if (!mounted) {
      return;
    }
    showMaintenanceSnackBar(
      context,
      message: '已启动缺失缓存补全，将按后台限流分批处理',
    );
    unawaited(_cacheDiagnosticsController.refresh());
  }

  /**
   * 校验并保存录制到的快捷键。
   *
   * 冲突时不交换、不覆盖任何现有绑定，返回 false 让录制框保持焦点继续等待输入。
   */
  bool _captureShortcut(
    PlayerShortcutAction action,
    String key,
  ) {
    final shortcuts = Map<PlayerShortcutAction, String>.of(_settings.shortcuts);
    final conflictMessage = playerShortcutConflictMessage(
      action: action,
      shortcut: key,
      bindings: shortcuts,
    );
    if (conflictMessage != null) {
      setState(() {
        _shortcutErrors[action] = conflictMessage;
      });
      return false;
    }
    shortcuts[action] = key;
    final next = _settings.copyWith(shortcuts: Map.unmodifiable(shortcuts));
    setState(() {
      _shortcutErrors.remove(action);
    });
    unawaited(_saveCapturedShortcut(action, next));
    return true;
  }

  /** 异步保存录制结果；controller 只在该结果仍为最新版本时回滚。 */
  Future<void> _saveCapturedShortcut(
    PlayerShortcutAction action,
    PlaybackSettings next,
  ) async {
    final requestRevision = _playbackSettingsController.revision + 1;
    try {
      await _playbackSettingsController.update(next);
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (requestRevision == _playbackSettingsController.revision) {
        setState(() => _shortcutErrors[action] = '保存失败，请重新录入');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存快捷键失败：$error')),
      );
    }
  }

  /** 恢复项目默认快捷键，并立即持久化。 */
  Future<void> _resetShortcuts() async {
    final next = _settings.copyWith(
      shortcuts: PlaybackSettings.defaultShortcuts,
    );
    setState(_shortcutErrors.clear);
    await _playbackSettingsController.update(next);
  }

  /** 更新删除确认与回收站偏好，并立即写入现有设置文件。 */
  Future<void> _changeDeletePreferences({
    bool? confirmBeforeDeletingVideo,
    bool? autoRemoveMissingOrUnreadableVideos,
  }) async {
    final next = _settings.copyWith(
      confirmBeforeDeletingVideo: confirmBeforeDeletingVideo,
      autoRemoveMissingOrUnreadableVideos: autoRemoveMissingOrUnreadableVideos,
    );
    try {
      await _playbackSettingsController.update(next);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showMaintenanceSnackBar(
        context,
        message: '保存删除设置失败：$error',
      );
      return;
    }
    if (autoRemoveMissingOrUnreadableVideos == true) {
      await _removeMissingOrUnreadableVideos(showFeedback: true);
    }
  }

  /** 即时执行数据库清理；失败时保留已保存的开启状态，供后续扫描继续重试。 */
  Future<int> _removeMissingOrUnreadableVideos({
    required bool showFeedback,
  }) async {
    if (_unavailableCleanupRunning) {
      return 0;
    }
    setState(() => _unavailableCleanupRunning = true);
    try {
      final removed = await widget.store.removeMissingOrUnreadableVideos();
      if (mounted && showFeedback) {
        showMaintenanceSnackBar(
          context,
          message:
              removed == 0 ? '没有需要清理的缺失或不可读记录' : '已从数据库移除 $removed 条记录；磁盘文件未删除',
        );
      }
      return removed;
    } catch (error) {
      if (mounted) {
        showMaintenanceSnackBar(
          context,
          message: '清理缺失或不可读记录失败：$error',
        );
      }
      return 0;
    } finally {
      if (mounted) {
        setState(() => _unavailableCleanupRunning = false);
      }
    }
  }

  /** 切换全屏右缘自动队列并立即持久化；失败时恢复界面旧值。 */
  Future<void> _changeFullscreenQueueEdgeHoverEnabled(bool enabled) async {
    final next = _settings.copyWith(fullscreenQueueEdgeHoverEnabled: enabled);
    try {
      await _playbackSettingsController.update(next);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存全屏播放列表设置失败：$error')),
      );
    }
  }

  /** 当前层级的页面标题。 */
  String get _sectionTitle => switch (_section) {
        CacheSettingsSection.home => '设置',
        CacheSettingsSection.playback => '播放与解码',
        CacheSettingsSection.videoQuality => '视频画质与增强',
        CacheSettingsSection.playerInteraction => '播放器交互',
        CacheSettingsSection.fileDeletion => '删除文件',
        CacheSettingsSection.dataBackup => '视频数据备份',
        CacheSettingsSection.cache => '缩略图缓存',
        CacheSettingsSection.updateProxy => '网络代理',
        CacheSettingsSection.about => '关于',
      };

  /** 从设置首页进入指定功能二级页。 */
  void _openSection(CacheSettingsSection section) {
    setState(() => _section = section);
  }

  /** 二级页返回设置功能列表。 */
  void _returnToSettingsHome() {
    setState(() => _section = CacheSettingsSection.home);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: settingsWorkspaceTheme(Theme.of(context)),
      child: CacheSettingsWorkspace(
        section: _section,
        title: _sectionTitle,
        settings: _settings,
        shortcutErrors: _shortcutErrors,
        unavailableCleanupRunning: _unavailableCleanupRunning,
        cacheLoading: _cacheDiagnosticsController.loading,
        cacheHasError: _cacheDiagnosticsController.error != null,
        cacheStats: _cacheDiagnosticsController.stats,
        cacheActionRunning: _cacheMaintenanceController.busy,
        dataBackupSettings: widget.dataBackupSettings,
        dataBackupStatus: widget.store.dataBackupStatus,
        dataBackupStatuses: widget.store.dataBackupStatusStream,
        updateService: widget.updateService,
        onOpenSection: _openSection,
        onBack: _returnToSettingsHome,
        onRefreshCache: _refreshStats,
        onPlaybackSettingsChanged: _playbackSettingsController.update,
        onConfirmDeleteChanged: (value) {
          unawaited(_changeDeletePreferences(
            confirmBeforeDeletingVideo: value,
          ));
        },
        onAutoCleanupChanged: (value) {
          unawaited(_changeDeletePreferences(
            autoRemoveMissingOrUnreadableVideos: value,
          ));
        },
        onFullscreenQueueChanged: (value) {
          unawaited(_changeFullscreenQueueEdgeHoverEnabled(value));
        },
        onResetShortcuts: _resetShortcuts,
        onShortcutCaptured: _captureShortcut,
        onRetryFailures: (stats) {
          unawaited(_retryFailedThumbnails(stats));
        },
        onClearFailures: (stats) {
          unawaited(_clearThumbnailFailureMarkers(stats));
        },
        onGenerateMissing: _generateMissingThumbnails,
        onDataBackupSettingsChanged: widget.onDataBackupSettingsChanged,
        onRunDataBackupNow: widget.onRunDataBackupNow,
        onCheckDataBackupIntegrity: widget.onCheckDataBackupIntegrity,
        onExportDataBackup: widget.onExportDataBackup,
      ),
    );
  }
}
