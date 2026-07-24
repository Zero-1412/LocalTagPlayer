import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/layout_size.dart';
import '../../core/data_backup_settings.dart';
import '../../core/playback_settings.dart';
import '../../core/tag_rules.dart';
import '../../models/library_scan_models.dart';
import '../../models/data_backup_models.dart';
import '../../models/library_sort.dart';
import '../../models/media_details.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../platform/file_system_adapter.dart';
import '../../platform/platform_interfaces.dart';
import '../../services/library/library_application_facade.dart';
import '../../services/library/library_count_refresh_coordinator.dart';
import '../../services/library/library_load_diagnostics.dart';
import '../../services/library/library_page_application_service.dart';
import '../../services/library/library_scan_ui_diagnostics.dart';
import '../../services/library/library_scan_playback_gate.dart';
import '../../services/library/library_stress_control.dart';
import '../../services/media/media_details_service.dart';
import '../../services/media/thumbnail_service.dart';
import '../../services/player/playback_snapshot_write_queue.dart';
import '../../services/player/player_hardware_compatibility.dart';
import '../../services/player/player_memory_diagnostics.dart';
import '../../services/tags/tag_query_service.dart';
import '../../widgets/app_theme_tokens.dart';
import '../../widgets/design_system/app_interaction_surface.dart';
import '../../widgets/library/library_local_view.dart';
import '../../widgets/library/library_smoke_keys.dart';
import '../../widgets/library/library_tag_discovery_panel.dart';
import '../../widgets/library/library_video_results.dart';
import '../../widgets/library/library_widgets.dart';
import '../../widgets/player_shortcut_input.dart';
import '../player/player_delete_dialog.dart';
import '../player/player_hardware_decode_warning_dialog.dart';
import '../player/player_open_request_controller.dart';
import '../player/player_page.dart';
import '../tags/tag_manager_page.dart';
import 'library_page_helpers.dart';
import 'directory_manager_page.dart';
import 'missing_relink_page.dart';

/** 标签筛选默认保持折叠，把媒体结果宽度优先留给高频浏览。 */
const bool libraryTagDiscoveryPanelInitiallyOpen = false;

/** 计算筛选动作后的面板状态；只有真实标签选择要求自动收起。 */
bool libraryTagDiscoveryPanelOpenAfterMutation({
  required bool currentOpen,
  required bool collapseAfterMutation,
}) =>
    collapseAfterMutation ? false : currentOpen;

/**
 * 返回标签编辑器在指定层级应展示的完整名称候选。
 *
 * 候选直接来自规范化 `TagItem` 索引，因此包含尚未出现在兼容视频字段中的标签。候选可以
 * 来自 folder 等已有来源，但用户选中后仍由保存层建立独立 manual 关系；隐藏标签不展示，
 * 二级候选仍严格限制在 [parentTag] 下。
 */
Set<String> tagEditorCandidates(
  Iterable<TagItem> tags, {
  String? parentTag,
}) {
  return <String>{
    for (final tag in tags)
      if (!tag.isHidden &&
          (parentTag == null
              ? tag.parentId == null
              : tag.parentId != null &&
                  TagRules.sameTag(tag.parentId!, parentTag)))
        tag.name,
  };
}

/** 为页面切换提供统一的轻量淡入与横向位移动画。 */
Route<T> _smoothRoute<T>(
  Widget page, {
  String Function()? backShortcutProvider,
}) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (routeContext, __, ___) => backShortcutProvider == null
        ? page
        : AppRouteBackInputRegion(
            shortcutProvider: backShortcutProvider,
            onBack: () {
              unawaited(Navigator.of(routeContext).maybePop());
            },
            child: page,
          ),
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: appMotionCurve);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.018, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/** 播放器 Route 挂载期间排除媒体库语义，防止 Windows UIA 保留旧页面节点。 */
@visibleForTesting
bool libraryRouteShouldExcludeSemantics({required bool playerRouteActive}) {
  return playerRouteActive;
}

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

/** 把后台媒体解析快照转换为结果区的稳定短文案。 */
String libraryMediaImportProgressLabel(MediaDetailsProgress progress) {
  final percent = (progress.fraction * 100).floor();
  final parts = <String>[
    '媒体解析 ${progress.processed}/${progress.total}',
    '$percent%',
  ];
  if (progress.isPaused) {
    parts.add('已暂停');
    return parts.join(' · ');
  }
  final speed = progress.itemsPerSecond;
  if (speed != null && speed > 0) {
    parts.add(
        speed >= 10 ? '${speed.round()}个/秒' : '${speed.toStringAsFixed(1)}个/秒');
  }
  final remaining = progress.estimatedRemaining;
  if (remaining != null) {
    parts.add('剩余${_libraryImportDurationLabel(remaining)}');
  }
  return parts.join(' · ');
}

/** 把目录发现、指纹校验和提交进度压缩为结果区短文案。 */
String libraryScanProgressLabel(LibraryScanProgress? progress) {
  if (progress == null) {
    return '正在发现视频…';
  }
  if (progress.phase == LibraryScanPhase.discovering) {
    return progress.discovered == 0
        ? '正在发现视频…'
        : '正在发现视频 · 已找到 ${progress.discovered} 个';
  }
  final total = progress.total ?? progress.discovered;
  final percent = ((progress.fraction ?? 0) * 100).floor();
  final parts = <String>[
    progress.phase == LibraryScanPhase.fingerprinting
        ? '校验文件 ${progress.processed}/$total'
        : '提交索引 ${progress.processed}/$total',
    '$percent%',
  ];
  if (progress.isPaused) {
    parts.add('播放期间已暂停');
    return parts.join(' · ');
  }
  final speed = progress.itemsPerSecond;
  if (speed != null && speed > 0) {
    parts.add(
        speed >= 10 ? '${speed.round()}个/秒' : '${speed.toStringAsFixed(1)}个/秒');
  }
  final remaining = progress.estimatedRemaining;
  if (remaining != null && remaining > Duration.zero) {
    parts.add('剩余${_libraryImportDurationLabel(remaining)}');
  }
  return parts.join(' · ');
}

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
    return '当前用户数据已覆盖；另有 ${report.ambiguousFingerprints} 组重复指纹。自动恢复会安全跳过这些歧义文件，需要人工确认，不会静默合并。';
  }
  if (report.recoverableSnapshots > 0) {
    return '当前用户数据已覆盖，另保留 ${report.recoverableSnapshots} 条供未来重新扫描时恢复的归档快照。';
  }
  return '当前用户数据已完整覆盖，可作为稳定身份、收藏、播放状态和非文件夹标签的恢复来源。';
}

/** 把 ETA 压缩为适合当前筛选结果行的一到两个时间单位。 */
String _libraryImportDurationLabel(Duration duration) {
  final seconds = duration.inSeconds.clamp(1, 359999);
  if (seconds < 60) {
    return '$seconds秒';
  }
  final minutes = seconds ~/ 60;
  if (minutes < 60) {
    final remainder = seconds % 60;
    return remainder == 0 ? '$minutes分钟' : '$minutes分$remainder秒';
  }
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours小时' : '$hours小时$remainder分';
}

/**
 * LibraryPage 的派生显示和排序逻辑。
 *
 * 这里不持有状态、不触发数据库访问，只读取 `_LibraryPageState` 已有状态生成摘要、排序和队列标题，
 * 让页面主体专注生命周期、交互入口和布局组装。
 */
extension _LibraryPageDerivedState on _LibraryPageState {
  /**
   * 构建用于诊断和播放器队列标题的完整筛选表达式。
   */
  String _filterExpression({
    required LibraryApplicationFacade store,
    required int resultCount,
    required int totalCount,
  }) {
    final parts = <String>[];
    final keyword = _searchController.text.trim();
    if (keyword.isNotEmpty) {
      parts.add('keyword:"$keyword"');
    }
    final primaryTags = _selectedTags.toList()..sort();
    parts.addAll(primaryTags.map((tag) => 'legacy:$tag'));
    final childTags = _selectedChildTags.toList()..sort();
    if (childTags.isNotEmpty) {
      parts.add('child:(${childTags.join('|')})');
    }
    final groupsById = {
      for (final group in _tagGroupsForSidebar(store)) group.id: group
    };
    final selectedEntries = _selectedGroupTagIds.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in selectedEntries) {
      final tagLabels = [
        for (final id in entry.value)
          if (store.tagsById[id] != null) _tagLabel(store.tagsById[id]!),
      ]..sort();
      if (tagLabels.isEmpty) {
        continue;
      }
      final group = groupsById[entry.key];
      parts.add(
        '${group == null ? entry.key : _groupLabel(group)}:(${tagLabels.join('|')})',
      );
    }
    parts.addAll(_excludedTagItems(store).map((tag) => '-${_tagLabel(tag)}'));
    if (_showFavoritesOnly) {
      parts.add('favorite');
    }
    final expression =
        parts.isEmpty ? '\u5168\u90e8\u89c6\u9891' : parts.join(' AND ');
    return '$expression  |  $resultCount / $totalCount';
  }

  /**
   * 构建面向用户的短筛选摘要。
   */
  String _filterSummary({
    required LibraryApplicationFacade store,
    required int resultCount,
    required int totalCount,
  }) {
    final parts = <String>[];
    final hierarchyParts = <String>[];
    final keyword = _searchController.text.trim();
    hierarchyParts.addAll(_selectedTags.toList()..sort());
    hierarchyParts.addAll(_selectedChildTags.toList()..sort());
    final selectedItems = _selectedGroupTagItems(store);
    hierarchyParts.addAll([
      for (final tag in selectedItems)
        if (tag.groupId == 'folder.primary' || tag.groupId == 'folder.child')
          tag.displayName ?? tag.name,
    ]);
    if (hierarchyParts.isNotEmpty) {
      parts.add(hierarchyParts.toSet().join(' / '));
    }
    final otherLabels = [
      for (final tag in selectedItems)
        if (tag.groupId != 'folder.primary' && tag.groupId != 'folder.child')
          tag.displayName ?? tag.name,
    ]..sort();
    parts.addAll(otherLabels);
    if (keyword.isNotEmpty) {
      parts.add('关键词 $keyword');
    }
    final excludedCount = _excludedTagIds.length;
    if (excludedCount > 0) {
      parts.add('NOT $excludedCount');
    }
    if (_showFavoritesOnly) {
      parts.add('favorite');
    }
    final label = parts.isEmpty ? '全部视频' : parts.join(' + ');
    return '$label · $resultCount 个结果';
  }

  /**
   * 当前排序控件对应的视频比较器。
   */
  int _compareVideos(VideoItem a, VideoItem b) {
    return compareLibraryVideosForSort(
      a,
      b,
      sortMode: _sortMode,
      sortDirection: _sortDirection,
    );
  }

  /**
   * 切换排序字段，并只重排当前结果。
   *
   * 排序不改变筛选命中集合和标签计数，因此不能复用完整筛选刷新路径；
   * 否则大媒体库会在每次切换字段时额外触发 resultCounts 重算。
   */
  void _setSortMode(SortMode mode) {
    _applySortChange(sortMode: mode);
  }

  /**
   * 切换排序方向，并只重排当前结果。
   */
  void _toggleSortDirection() {
    _applySortChange(
      sortDirection: _sortDirection == SortDirection.descending
          ? SortDirection.ascending
          : SortDirection.descending,
    );
  }

  /**
   * 播放器过滤队列标题。
   */
  String _queueTitle({
    required LibraryApplicationFacade store,
    required int playlistLength,
  }) {
    return switch (_resultMode) {
      _LibraryResultMode.recent =>
        '\u6700\u8fd1\u64ad\u653e  |  $playlistLength / ${store.videos.length}',
      _LibraryResultMode.favorites =>
        '\u672c\u5730\u6536\u85cf  |  $playlistLength / ${store.videos.length}',
      _LibraryResultMode.local =>
        '${_localLibraryPath ?? '\u672c\u5730\u5a92\u4f53\u5e93'}  |  $playlistLength / ${store.videos.length}',
      _LibraryResultMode.library => _filterSummary(
          store: store,
          resultCount: playlistLength,
          totalCount: store.videos.length,
        ),
    };
  }
}

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
    if (confirmed != true || !mounted) {
      setState(() => _fieldRevision++);
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
 * 应用设置页，首页按功能类型导航，二级页承载对应的实际设置控件。
 */
/** 设置路由在维护页基线上收敛内容卡片几何，不影响其它维护页面。 */
@visibleForTesting
ThemeData settingsWorkspaceTheme(ThemeData base) {
  final workspace = maintenanceWorkspaceTheme(base);
  return workspace.copyWith(
    // DropdownButton 的弹出路由读取 canvasColor；显式保持深色抬升表面，
    // 避免深色文字主题落到默认浅色菜单上而失去可读性。
    canvasColor: librarySurfaceAlt,
    hoverColor: appAccentViolet.withValues(alpha: 0.10),
    focusColor: appAccentViolet.withValues(alpha: 0.16),
    highlightColor: appAccentViolet.withValues(alpha: 0.12),
    splashColor: appAccentViolet.withValues(alpha: 0.08),
    cardTheme: workspace.cardTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: libraryBorder),
      ),
    ),
  );
}

/**
 * 构建缓存诊断面板的 focused widget test 容器。
 *
 * 测试只注入不可变统计快照和动作回调，不创建真实缓存队列或后台任务。
 */
@visibleForTesting
Widget cacheDiagnosticsSmokeHarness({
  required CacheStats stats,
  bool cacheBusy = false,
  VoidCallback? onRetry,
  VoidCallback? onClear,
  TextScaler textScaler = TextScaler.noScaling,
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
          child: _CacheDiagnosticsPanel(
            stats: stats,
            cacheBusy: cacheBusy,
            onRetry: onRetry ?? () {},
            onClear: onClear ?? () {},
          ),
        ),
      ),
    ),
  );
}

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
  });

  final LibraryApplicationFacade store;

  final ThumbnailService thumbnailService;

  final PlaybackSettings playbackSettings;

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

  @override
  State<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

/** 设置页可进入的功能分区。 */
enum _SettingsSection {
  home,
  playback,
  videoQuality,
  playerInteraction,
  fileDeletion,
  dataBackup,
  cache,
}

/**
 * 设置首页的分组功能列表。
 *
 * 首页只负责导航，不承载开关、滑杆或下拉框，避免用户进入设置时面对过多控件。
 */
class SettingsLandingList extends StatelessWidget {
  const SettingsLandingList({
    super.key,
    required this.resumeBehavior,
    required this.confirmBeforeDeletingVideo,
    required this.moveDeletedFileToTrash,
    this.autoRemoveMissingOrUnreadableVideos = true,
    required this.onOpenPlayback,
    required this.onOpenVideoQuality,
    required this.onOpenPlayerInteraction,
    required this.onOpenFileDeletion,
    required this.onOpenDataBackup,
    required this.onOpenCache,
  });

  /** 首页直接展示的继续观看策略，避免用户必须先进入二级页才能发现当前行为。 */
  final PlaybackResumeBehavior resumeBehavior;

  /** 删除动作当前是否保留确认层。 */
  final bool confirmBeforeDeletingVideo;

  /** 删除动作当前是否同步把本地文件移入回收站。 */
  final bool moveDeletedFileToTrash;
  /** 扫描后是否自动清理缺失/不可读数据库记录。 */
  final bool autoRemoveMissingOrUnreadableVideos;

  /** 打开播放与解码二级页。 */
  final VoidCallback onOpenPlayback;

  /** 打开视频画质与增强二级页。 */
  final VoidCallback onOpenVideoQuality;

  /** 打开播放器交互二级页。 */
  final VoidCallback onOpenPlayerInteraction;

  /** 打开删除文件与回收站二级页。 */
  final VoidCallback onOpenFileDeletion;

  /** 打开视频数据备份二级页。 */
  final VoidCallback onOpenDataBackup;

  /** 打开缩略图缓存二级页。 */
  final VoidCallback onOpenCache;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('settings.home'),
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '按功能进入设置，当前播放与数据状态会保留在对应入口。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: libraryTextMuted,
              ),
        ),
        const SizedBox(height: 22),
        const _SettingsGroupTitle(title: '播放设置'),
        const SizedBox(height: 8),
        _SettingsNavigationGroup(
          children: [
            _SettingsNavigationTile(
              key: const ValueKey('settings.category.playback'),
              icon: Icons.play_circle_outline_rounded,
              title: '播放与解码',
              subtitle:
                  '继续观看：${PlaybackSettings.resumeLabelFor(resumeBehavior)} · 硬解与码流缓存',
              statusLabel: PlaybackSettings.resumeLabelFor(resumeBehavior),
              onTap: onOpenPlayback,
            ),
            _SettingsNavigationTile(
              key: const ValueKey('settings.category.videoQuality'),
              icon: Icons.auto_awesome_outlined,
              title: '视频画质与增强',
              subtitle: '画面比例、缩放与色彩 · 自动画质、暗部增强与 HDR 映射',
              onTap: onOpenVideoQuality,
            ),
            _SettingsNavigationTile(
              key: const ValueKey('settings.category.playerInteraction'),
              icon: Icons.tune_rounded,
              title: '播放器交互',
              subtitle: '全屏播放列表、播放器快捷键',
              onTap: onOpenPlayerInteraction,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SettingsGroupTitle(title: '数据与维护'),
        const SizedBox(height: 8),
        _SettingsNavigationGroup(
          children: [
            _SettingsNavigationTile(
              key: const ValueKey('settings.category.fileDeletion'),
              icon: Icons.delete_outline_rounded,
              title: '删除文件',
              subtitle: confirmBeforeDeletingVideo
                  ? '删除前提示 · ${moveDeletedFileToTrash ? '移入回收站' : '仅移除记录'} · ${autoRemoveMissingOrUnreadableVideos ? '自动清理无效记录' : '保留无效记录'}'
                  : '不再提示 · ${moveDeletedFileToTrash ? '移入回收站' : '仅移除记录'} · ${autoRemoveMissingOrUnreadableVideos ? '自动清理无效记录' : '保留无效记录'}',
              onTap: onOpenFileDeletion,
            ),
            _SettingsNavigationTile(
              key: const ValueKey('settings.category.dataBackup'),
              icon: Icons.backup_outlined,
              title: '视频数据备份',
              subtitle: '备份开关、同步状态、检查与导出',
              onTap: onOpenDataBackup,
            ),
            _SettingsNavigationTile(
              key: const ValueKey('settings.category.cache'),
              icon: Icons.image_outlined,
              title: '缩略图缓存',
              subtitle: '缓存状态与后台任务统计',
              onTap: onOpenCache,
            ),
          ],
        ),
      ],
    );
  }
}

/**
 * 播放与解码页中的原始码流缓存设置。
 *
 * 该开关只影响播放器会话的 demux 内存窗口，不复制媒体文件，也不触发缩略图或
 * 媒体详情缓存任务；因此与解码策略放在同一入口，而不是混入画质增强页面。
 */
class _PlaybackStreamCacheCard extends StatelessWidget {
  const _PlaybackStreamCacheCard({
    required this.settings,
    required this.onChanged,
  });

  /** 当前播放设置快照。 */
  final PlaybackSettings settings;

  /** 保存更新后的完整设置快照。 */
  final ValueChanged<PlaybackSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('settings.playback.streamCache.card'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SwitchListTile.adaptive(
          key: const ValueKey('settings.playbackQuality.streamCache'),
          contentPadding: EdgeInsets.zero,
          value: settings.highQualityStreamCacheEnabled,
          title: const Text('缓存原始高清码流'),
          subtitle: const Text(
            '为当前会话保留 96 MiB 前向、32 MiB 回看内存窗口；不复制源文件',
          ),
          onChanged: (value) => onChanged(
            settings.copyWith(highQualityStreamCacheEnabled: value),
          ),
        ),
      ),
    );
  }
}

/**
 * 第一阶段播放质量设置。
 *
 * 控件只保存播放会话参数，不在设置页启动解码、FFprobe 或媒体库重算；新播放器
 * 会话统一把这些值送入 PlayerBackend，避免设置操作阻塞 UI isolate。
 */
class _PlaybackQualitySettingsPanel extends StatelessWidget {
  const _PlaybackQualitySettingsPanel({
    required this.settings,
    required this.onChanged,
  });

  /** 当前播放设置快照。 */
  final PlaybackSettings settings;

  /** 保存完整设置快照，确保连续修改不会丢失其它字段。 */
  final ValueChanged<PlaybackSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('settings.playbackQuality.card'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '视频质量与渲染',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              '第一阶段能力默认以流畅播放为边界；高开销增强不在 UI 线程处理视频帧。',
              style: TextStyle(color: libraryTextMuted, height: 1.45),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<PlayerVideoAspectMode>(
              key: const ValueKey('settings.playbackQuality.aspect'),
              initialValue: settings.videoAspectMode,
              decoration: const InputDecoration(labelText: '画面比例'),
              items: [
                for (final mode in PlayerVideoAspectMode.values)
                  DropdownMenuItem(
                    value: mode,
                    child: Text(PlaybackSettings.videoAspectLabelFor(mode)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onChanged(settings.copyWith(videoAspectMode: value));
                }
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<PlayerVideoScaler>(
              key: const ValueKey('settings.playbackQuality.scaler'),
              initialValue: settings.videoScaler,
              decoration: const InputDecoration(labelText: '高质量缩放'),
              items: [
                for (final scaler in PlayerVideoScaler.values)
                  DropdownMenuItem(
                    value: scaler,
                    child: Text(PlaybackSettings.videoScalerLabelFor(scaler)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onChanged(settings.copyWith(videoScaler: value));
                }
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<PlayerVideoOutputRange>(
              key: const ValueKey('settings.playbackQuality.outputRange'),
              initialValue: settings.videoOutputRange,
              decoration: const InputDecoration(labelText: '输出色彩范围'),
              items: [
                for (final range in PlayerVideoOutputRange.values)
                  DropdownMenuItem(
                    value: range,
                    child:
                        Text(PlaybackSettings.videoOutputRangeLabelFor(range)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onChanged(settings.copyWith(videoOutputRange: value));
                }
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              key: const ValueKey(
                'settings.playbackQuality.automaticEnhancement',
              ),
              contentPadding: EdgeInsets.zero,
              value: settings.automaticQualityEnhancementEnabled,
              title: const Text('自动画质协调器'),
              subtitle: const Text(
                '根据 1080p / 4K 与软硬解基线，按实时余量动态启用去块、时空降噪和适度锐化',
              ),
              onChanged: (value) => onChanged(
                settings.copyWith(
                  automaticQualityEnhancementEnabled: value,
                ),
              ),
            ),
            const Divider(height: 20),
            SwitchListTile.adaptive(
              key: const ValueKey(
                'settings.playbackQuality.darkSceneEnhancement',
              ),
              contentPadding: EdgeInsets.zero,
              value: settings.darkSceneEnhancementEnabled,
              title: const Text('暗部细节增强'),
              subtitle: const Text(
                '仅对已确认的 SDR、1080p 及以下硬解视频启用保守暗部曲线；出现播放压力时当前会话自动回滚',
              ),
              onChanged: (value) => onChanged(
                settings.copyWith(darkSceneEnhancementEnabled: value),
              ),
            ),
            const Divider(height: 20),
            SwitchListTile.adaptive(
              key: const ValueKey(
                'settings.playbackQuality.hdrMappingExperiment',
              ),
              contentPadding: EdgeInsets.zero,
              value: settings.hdrDynamicToneMappingExperimentEnabled,
              title: const Text('HDR 动态映射'),
              subtitle: const Text(
                '仅对 HDR 视频在活动 GPU LUID 与 Compute 门槛通过后启用；播放压力会自动回滚，关闭即恢复自动映射',
              ),
              onChanged: (value) async {
                if (!value) {
                  onChanged(
                    settings.copyWith(
                      hdrDynamicToneMappingExperimentEnabled: false,
                    ),
                  );
                  return;
                }
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('开启 HDR 动态映射？'),
                    content: const Text(
                      '该功能会为通过能力门槛的 HDR 视频启用 Hable 映射与逐帧峰值 Compute。若出现掉帧、功耗升高或观感异常，可随时关闭并恢复 mpv 自动值。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        key: const ValueKey(
                          'settings.playbackQuality.hdrMappingConfirm',
                        ),
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('确认开启'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  onChanged(
                    settings.copyWith(
                      hdrDynamicToneMappingExperimentEnabled: true,
                    ),
                  );
                }
              },
            ),
            const Divider(height: 20),
            const _PlaybackCapabilityRow(
              icon: Icons.analytics_outlined,
              title: '视频质量信息解析',
              subtitle: 'FFprobe 缓存解析编码、分辨率、时长；播放诊断读取实时色彩参数',
              status: '已启用',
            ),
            const _PlaybackCapabilityRow(
              icon: Icons.monitor_heart_outlined,
              title: '解码与丢帧诊断',
              subtitle: '播放器诊断可核验实际硬解、缓存、解码/输出/总丢帧及色彩范围',
              status: '已启用',
            ),
          ],
        ),
      ),
    );
  }
}

/** 设置页中的只读能力状态行，避免尚未实现的能力伪装成可操作开关。 */
class _PlaybackCapabilityRow extends StatelessWidget {
  const _PlaybackCapabilityRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String status;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: appAccentViolet),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(
        status,
        style: const TextStyle(
          color: appAccentViolet,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/**
 * 删除文件二级设置页。
 *
 * 两个开关只修改确认与回收站偏好，不执行删除、扫描或数据库写入；真实删除仍由
 * 页面动作、稳定身份清理事务和 FileSystemAdapter 共同完成。
 */
class _DeleteFileSettingsPanel extends StatelessWidget {
  const _DeleteFileSettingsPanel({
    required this.confirmBeforeDeletingVideo,
    required this.moveDeletedFileToTrash,
    required this.autoRemoveMissingOrUnreadableVideos,
    required this.onConfirmChanged,
    required this.onMoveToTrashChanged,
    required this.onAutoRemoveMissingOrUnreadableChanged,
  });

  /** 是否在删除前展示影响范围确认。 */
  final bool confirmBeforeDeletingVideo;

  /** 是否在删除记录前把本地文件移入回收站。 */
  final bool moveDeletedFileToTrash;
  /** 是否自动清理缺失/不可读视频的数据库记录。 */
  final bool autoRemoveMissingOrUnreadableVideos;

  /** 确认层显示偏好回调。 */
  final ValueChanged<bool> onConfirmChanged;

  /** 回收站默认行为回调。 */
  final ValueChanged<bool> onMoveToTrashChanged;
  /** 清理运行期间为 null，阻止重复触发同一批删除。 */
  final ValueChanged<bool>? onAutoRemoveMissingOrUnreadableChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('settings.fileDeletion.card'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '删除文件',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              '统一控制媒体卡片、批量选择和播放器队列中的删除动作。',
              style: TextStyle(color: libraryTextMuted, height: 1.45),
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              key: const ValueKey(
                'settings.fileDeletion.autoRemoveMissingOrUnreadable',
              ),
              contentPadding: EdgeInsets.zero,
              value: autoRemoveMissingOrUnreadableVideos,
              title: const Text('自动移除缺失或不可读视频'),
              subtitle: const Text(
                '默认开启；开启后立即从数据库清理当前无效记录，不删除磁盘文件或文件夹',
              ),
              onChanged: onAutoRemoveMissingOrUnreadableChanged,
            ),
            const Divider(height: 20),
            SwitchListTile.adaptive(
              key: const ValueKey('settings.fileDeletion.confirm'),
              contentPadding: EdgeInsets.zero,
              value: confirmBeforeDeletingVideo,
              title: const Text('删除前显示提示框'),
              subtitle: const Text('显示删除影响范围，并允许本次临时修改回收站选择'),
              onChanged: onConfirmChanged,
            ),
            const Divider(height: 20),
            SwitchListTile.adaptive(
              key: const ValueKey('settings.fileDeletion.moveToTrash'),
              contentPadding: EdgeInsets.zero,
              value: moveDeletedFileToTrash,
              title: const Text('同步将本地文件移入回收站'),
              subtitle: const Text('关闭时只移除媒体库记录，本地文件可能在下次扫描时重新加入'),
              onChanged: onMoveToTrashChanged,
            ),
            if (!confirmBeforeDeletingVideo) ...[
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: playerDanger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(
                    color: playerDanger.withValues(alpha: 0.34),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: playerDanger,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          moveDeletedFileToTrash
                              ? '后续删除将不再提示，直接把本地文件移入回收站并移除媒体库记录。'
                              : '后续删除将不再提示，直接移除媒体库记录；本地文件会保留。',
                          style: const TextStyle(height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/** 设置首页同一语义分组中的导航入口容器。 */
class _SettingsNavigationGroup extends StatelessWidget {
  const _SettingsNavigationGroup({required this.children});

  /** 分组内按视觉阅读顺序排列的入口。 */
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: librarySurface,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.panel)),
        border: Border.fromBorderSide(BorderSide(color: libraryBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

/** 设置首页的功能分组标题。 */
class _SettingsGroupTitle extends StatelessWidget {
  const _SettingsGroupTitle({required this.title});

  /** 分组名称。 */
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: libraryTextMuted,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/** 设置首页中打开二级页的单个功能入口。 */
class _SettingsNavigationTile extends StatelessWidget {
  const _SettingsNavigationTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.statusLabel,
  });

  /** 功能类型图标。 */
  final IconData icon;

  /** 功能名称。 */
  final String title;

  /** 功能范围摘要。 */
  final String subtitle;

  /** 需要在设置首屏直接暴露的关键当前状态；普通入口保持为空。 */
  final String? statusLabel;

  /** 点击后进入对应二级页。 */
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppInteractionSurface(
      onTap: onTap,
      semanticLabel: '打开$title',
      backgroundColor: librarySurface,
      borderRadius: AppRadius.card,
      showBorder: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 460;
          return Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: appAccentViolet.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: SizedBox.square(
                  dimension: 42,
                  child: Icon(icon, color: appAccentViolet),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: libraryTextMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (statusLabel != null && !compact) ...[
                Chip(
                  key: const ValueKey('settings.resumeBehavior.summary'),
                  label: Text(statusLabel!),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                ),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.chevron_right_rounded, color: libraryTextMuted),
            ],
          );
        },
      ),
    );
  }
}

class _CacheSettingsPageState extends State<CacheSettingsPage> {
  /** 当前显示的设置首页或功能二级页。 */
  _SettingsSection _section = _SettingsSection.home;
  late PlaybackSettings _settings = widget.playbackSettings;
  late DataBackupSettings _dataBackupSettings = widget.dataBackupSettings;
  late DataBackupStatus _dataBackupStatus = widget.store.dataBackupStatus;
  StreamSubscription<DataBackupStatus>? _dataBackupSubscription;
  bool _backupMaintenanceRunning = false;
  /** 缓存诊断动作串行执行，避免重试、清理与统计刷新互相覆盖。 */
  bool _cacheActionRunning = false;
  /** 自动清理运行期间锁定开关，避免重复删除同一批稳定身份。 */
  bool _unavailableCleanupRunning = false;

  /** 快捷键录制冲突按动作就地展示，成功保存或恢复默认后清除。 */
  final Map<PlayerShortcutAction, String> _shortcutErrors = {};

  late Future<CacheStats> _statsFuture =
      widget.thumbnailService.statsFor(widget.store.videos.values);

  @override
  void initState() {
    super.initState();
    _dataBackupSubscription = widget.store.dataBackupStatusStream.listen(
      (status) {
        if (mounted) {
          setState(() => _dataBackupStatus = status);
        }
      },
    );
  }

  @override
  void dispose() {
    unawaited(_dataBackupSubscription?.cancel());
    super.dispose();
  }

  /** 切换备份开关并立即持久化；失败时恢复界面旧值。 */
  Future<void> _changeDataBackupEnabled(bool enabled) async {
    final previous = _dataBackupSettings;
    final next = previous.copyWith(enabled: enabled);
    setState(() => _dataBackupSettings = next);
    try {
      await widget.onDataBackupSettingsChanged(next);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _dataBackupSettings = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存数据备份设置失败：$error')),
      );
    }
  }

  /** 设置页阶段文案不展示路径或标签内容。 */
  String _dataBackupPhaseLabel(DataBackupStatus status) =>
      switch (status.phase) {
        DataBackupPhase.disabled => '已关闭',
        DataBackupPhase.idle => '后台任务空闲',
        DataBackupPhase.running => '后台备份中',
        DataBackupPhase.pausedForPlayback => '播放期间已暂停',
        DataBackupPhase.failed => '上次执行失败',
      };

  /** 使用固定本地时间格式展示最近完成时间。 */
  String _backupTimeLabel(DateTime? value) {
    if (value == null) {
      return '尚未完成';
    }
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  /** 执行只读完整性检查并用主题化弹窗呈现可操作结论。 */
  Future<void> _checkDataBackupIntegrity() async {
    if (_backupMaintenanceRunning) {
      return;
    }
    setState(() => _backupMaintenanceRunning = true);
    try {
      final report = await widget.onCheckDataBackupIntegrity();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
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
                  value: formatCount(report.missingCurrentSnapshots),
                ),
                _SettingsStatLine(
                  label: '内容待更新',
                  value: formatCount(report.staleCurrentSnapshots),
                ),
                _SettingsStatLine(
                  label: '损坏 / 缺失指纹',
                  value:
                      '${report.invalidPayloads + report.missingFingerprints}',
                ),
                _SettingsStatLine(
                  label: '保留供未来恢复',
                  value: formatCount(report.recoverableSnapshots),
                ),
                _SettingsStatLine(
                  label: '重复指纹组（自动跳过）',
                  value: formatCount(report.ambiguousFingerprints),
                ),
              ],
            ),
          ),
          actions: [
            if (!report.isHealthy && _dataBackupSettings.enabled)
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  unawaited(widget.onRunDataBackupNow());
                },
                icon: const Icon(Icons.backup_rounded),
                label: const Text('立即备份'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
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
    } finally {
      if (mounted) {
        setState(() => _backupMaintenanceRunning = false);
      }
    }
  }

  /** 导出便携 JSON；文件选择取消不视为错误。 */
  Future<void> _exportDataBackup() async {
    if (_backupMaintenanceRunning) {
      return;
    }
    setState(() => _backupMaintenanceRunning = true);
    try {
      final path = await widget.onExportDataBackup();
      if (mounted && path != null) {
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
    } finally {
      if (mounted) {
        setState(() => _backupMaintenanceRunning = false);
      }
    }
  }

  void _refreshStats() {
    setState(() {
      _statsFuture =
          widget.thumbnailService.statsFor(widget.store.videos.values);
    });
  }

  /** 定向重试当前统计快照中的失败项，并持久化已清理的旧失败标记。 */
  Future<void> _retryFailedThumbnails(CacheStats stats) async {
    if (_cacheActionRunning || stats.failures.isEmpty) {
      return;
    }
    final items = stats.failures.map((failure) => failure.item).toList();
    setState(() => _cacheActionRunning = true);
    try {
      final retried = await widget.thumbnailService.retryFailed(items);
      final updated = items
          .where((item) => item.thumbnailError == null)
          .toList(growable: false);
      if (updated.isNotEmpty) {
        await widget.store.upsertVideos(updated);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            retried == items.length
                ? '已重新排队 $retried 个失败缩略图'
                : '已重新排队 $retried 个；另有 ${items.length - retried} 个仍待处理',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重试失败项时出错：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _cacheActionRunning = false;
          _statsFuture = widget.thumbnailService.statsFor(
            widget.store.videos.values,
          );
        });
      }
    }
  }

  /** 清除当前失败标记但不删除视频或缓存文件，并通过 Repository 保存结果。 */
  Future<void> _clearThumbnailFailureMarkers(CacheStats stats) async {
    if (_cacheActionRunning || stats.failures.isEmpty) {
      return;
    }
    final items = stats.failures.map((failure) => failure.item).toList();
    setState(() => _cacheActionRunning = true);
    try {
      final cleared = widget.thumbnailService.clearFailures(items);
      await widget.store.upsertVideos(items);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清除 $cleared 条失败标记；视频和缓存文件未删除')),
        );
      }
    } catch (error) {
      // Repository 写入失败时恢复内存诊断原因，避免 UI 与持久化状态分裂。
      for (final failure in stats.failures) {
        failure.item.thumbnailError = failure.reason;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除失败标记时出错：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _cacheActionRunning = false;
          _statsFuture = widget.thumbnailService.statsFor(
            widget.store.videos.values,
          );
        });
      }
    }
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
    final previous = _settings;
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
      _settings = next;
      _shortcutErrors.remove(action);
    });
    unawaited(_saveCapturedShortcut(action, previous, next));
    return true;
  }

  /** 异步保存录制结果；写入失败且期间没有新改动时恢复旧绑定。 */
  Future<void> _saveCapturedShortcut(
    PlayerShortcutAction action,
    PlaybackSettings previous,
    PlaybackSettings next,
  ) async {
    try {
      await widget.onPlaybackSettingsChanged(next);
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (identical(_settings, next)) {
        setState(() {
          _settings = previous;
          _shortcutErrors[action] = '保存失败，请重新录入';
        });
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
    setState(() {
      _settings = next;
      _shortcutErrors.clear();
    });
    await widget.onPlaybackSettingsChanged(next);
  }

  /** 更新删除确认与回收站偏好，并立即写入现有设置文件。 */
  Future<void> _changeDeletePreferences({
    bool? confirmBeforeDeletingVideo,
    bool? moveDeletedFileToTrash,
    bool? autoRemoveMissingOrUnreadableVideos,
  }) async {
    final previous = _settings;
    final next = previous.copyWith(
      confirmBeforeDeletingVideo: confirmBeforeDeletingVideo,
      moveDeletedFileToTrash: moveDeletedFileToTrash,
      autoRemoveMissingOrUnreadableVideos:
          autoRemoveMissingOrUnreadableVideos,
    );
    setState(() => _settings = next);
    try {
      await widget.onPlaybackSettingsChanged(next);
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (identical(_settings, next)) {
        setState(() => _settings = previous);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存删除设置失败：$error')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              removed == 0
                  ? '没有需要清理的缺失或不可读记录'
                  : '已从数据库移除 $removed 条记录；磁盘文件未删除',
            ),
          ),
        );
      }
      return removed;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理缺失或不可读记录失败：$error')),
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
    final previous = _settings;
    final next = previous.copyWith(fullscreenQueueEdgeHoverEnabled: enabled);
    setState(() => _settings = next);
    try {
      await widget.onPlaybackSettingsChanged(next);
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (identical(_settings, next)) {
        setState(() => _settings = previous);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存全屏播放列表设置失败：$error')),
      );
    }
  }

  /** 当前层级的页面标题。 */
  String get _sectionTitle => switch (_section) {
        _SettingsSection.home => '设置',
        _SettingsSection.playback => '播放与解码',
        _SettingsSection.videoQuality => '视频画质与增强',
        _SettingsSection.playerInteraction => '播放器交互',
        _SettingsSection.fileDeletion => '删除文件',
        _SettingsSection.dataBackup => '视频数据备份',
        _SettingsSection.cache => '缩略图缓存',
      };

  /** 从设置首页进入指定功能二级页。 */
  void _openSection(_SettingsSection section) {
    setState(() => _section = section);
  }

  /** 二级页返回设置功能列表。 */
  void _returnToSettingsHome() {
    setState(() => _section = _SettingsSection.home);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: settingsWorkspaceTheme(Theme.of(context)),
      child: _buildSettingsWorkspace(context),
    );
  }

  /** 构建已由深色维护主题包裹的设置内容，避免额外嵌套导致大范围无意义缩进。 */
  Widget _buildSettingsWorkspace(BuildContext context) {
    return PopScope<void>(
      canPop: _section == _SettingsSection.home,
      onPopInvokedWithResult: (didPop, result) {
        // 系统返回键在二级页优先返回设置首页，不直接退出整个设置路由。
        if (!didPop && _section != _SettingsSection.home) {
          _returnToSettingsHome();
        }
      },
      child: Scaffold(
        backgroundColor: libraryBackground,
        appBar: AppBar(
          leading: _section == _SettingsSection.home
              ? null
              : BackButton(
                  key: const ValueKey('settings.section.back'),
                  onPressed: _returnToSettingsHome,
                ),
          title: Text(_sectionTitle),
          actions: [
            if (_section == _SettingsSection.cache)
              TextButton.icon(
                key: const ValueKey('settings.refreshCacheStats'),
                style: TextButton.styleFrom(foregroundColor: libraryText),
                onPressed: _refreshStats,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('刷新统计'),
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _section == _SettingsSection.home ? 760 : 920,
            ),
            child: _section == _SettingsSection.home
                ? SettingsLandingList(
                    resumeBehavior: _settings.resumeBehavior,
                    confirmBeforeDeletingVideo:
                        _settings.confirmBeforeDeletingVideo,
                    moveDeletedFileToTrash: _settings.moveDeletedFileToTrash,
                    autoRemoveMissingOrUnreadableVideos:
                        _settings.autoRemoveMissingOrUnreadableVideos,
                    onOpenPlayback: () =>
                        _openSection(_SettingsSection.playback),
                    onOpenVideoQuality: () =>
                        _openSection(_SettingsSection.videoQuality),
                    onOpenPlayerInteraction: () =>
                        _openSection(_SettingsSection.playerInteraction),
                    onOpenFileDeletion: () =>
                        _openSection(_SettingsSection.fileDeletion),
                    onOpenDataBackup: () =>
                        _openSection(_SettingsSection.dataBackup),
                    onOpenCache: () => _openSection(_SettingsSection.cache),
                  )
                : ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      if (_section == _SettingsSection.playback) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  '继续观看',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  '打开有未完成进度的视频时，默认执行以下操作。',
                                  style: TextStyle(color: libraryTextMuted),
                                ),
                                const SizedBox(height: 14),
                                DropdownButtonFormField<PlaybackResumeBehavior>(
                                  key:
                                      const ValueKey('settings.resumeBehavior'),
                                  initialValue: _settings.resumeBehavior,
                                  decoration: const InputDecoration(
                                    labelText: '默认打开行为',
                                  ),
                                  items: [
                                    for (final behavior
                                        in PlaybackResumeBehavior.values)
                                      DropdownMenuItem(
                                        value: behavior,
                                        child: Text(
                                          PlaybackSettings.resumeLabelFor(
                                            behavior,
                                          ),
                                        ),
                                      ),
                                  ],
                                  onChanged: (behavior) async {
                                    if (behavior == null) {
                                      return;
                                    }
                                    final next = _settings.copyWith(
                                      resumeBehavior: behavior,
                                    );
                                    setState(() => _settings = next);
                                    await widget
                                        .onPlaybackSettingsChanged(next);
                                  },
                                ),
                                const SizedBox(height: 22),
                                const Divider(height: 1),
                                const SizedBox(height: 20),
                                const Text(
                                  '播放解码',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                PlaybackDecoderDropdown(
                                  settings: _settings,
                                  onChanged: (settings) async {
                                    setState(() => _settings = settings);
                                    await widget
                                        .onPlaybackSettingsChanged(settings);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _PlaybackStreamCacheCard(
                          settings: _settings,
                          onChanged: (settings) {
                            setState(() => _settings = settings);
                            unawaited(
                              widget.onPlaybackSettingsChanged(settings),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_section == _SettingsSection.videoQuality) ...[
                        _PlaybackQualitySettingsPanel(
                          settings: _settings,
                          onChanged: (settings) {
                            setState(() => _settings = settings);
                            unawaited(
                              widget.onPlaybackSettingsChanged(settings),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_section == _SettingsSection.dataBackup) ...[
                        _DataBackupSettingsPanel(
                          enabled: _dataBackupSettings.enabled,
                          maintenanceRunning: _backupMaintenanceRunning,
                          statusLabel: _dataBackupPhaseLabel(_dataBackupStatus),
                          progressLabel: _dataBackupStatus.total == 0
                              ? '0'
                              : '${_dataBackupStatus.processed} / ${_dataBackupStatus.total}',
                          pendingLabel: formatCount(_dataBackupStatus.pending),
                          lastCompletedLabel: _backupTimeLabel(
                            _dataBackupStatus.lastCompletedAt,
                          ),
                          progress: _dataBackupStatus.phase ==
                                      DataBackupPhase.running &&
                                  _dataBackupStatus.total > 0
                              ? (_dataBackupStatus.processed /
                                      _dataBackupStatus.total)
                                  .clamp(0, 1)
                              : null,
                          onEnabledChanged: _changeDataBackupEnabled,
                          onRunNow: widget.onRunDataBackupNow,
                          onCheckIntegrity: _checkDataBackupIntegrity,
                          onExport: _exportDataBackup,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_section == _SettingsSection.fileDeletion) ...[
                        _DeleteFileSettingsPanel(
                          confirmBeforeDeletingVideo:
                              _settings.confirmBeforeDeletingVideo,
                          moveDeletedFileToTrash:
                              _settings.moveDeletedFileToTrash,
                          autoRemoveMissingOrUnreadableVideos:
                              _settings.autoRemoveMissingOrUnreadableVideos,
                          onConfirmChanged: (value) {
                            unawaited(_changeDeletePreferences(
                              confirmBeforeDeletingVideo: value,
                            ));
                          },
                          onMoveToTrashChanged: (value) {
                            unawaited(_changeDeletePreferences(
                              moveDeletedFileToTrash: value,
                            ));
                          },
                          onAutoRemoveMissingOrUnreadableChanged:
                              _unavailableCleanupRunning
                                  ? null
                                  : (value) {
                                      unawaited(_changeDeletePreferences(
                                        autoRemoveMissingOrUnreadableVideos:
                                            value,
                                      ));
                                    },
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_section == _SettingsSection.playerInteraction) ...[
                        Card(
                          key: const ValueKey('settings.fullscreenQueue.card'),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: SwitchListTile.adaptive(
                              key: const ValueKey(
                                'settings.fullscreenQueue.edgeHoverEnabled',
                              ),
                              contentPadding: EdgeInsets.zero,
                              value: _settings.fullscreenQueueEdgeHoverEnabled,
                              onChanged: (value) => unawaited(
                                _changeFullscreenQueueEdgeHoverEnabled(value),
                              ),
                              secondary: DecoratedBox(
                                decoration: BoxDecoration(
                                  color:
                                      appAccentViolet.withValues(alpha: 0.15),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.control),
                                ),
                                child: const SizedBox.square(
                                  dimension: 42,
                                  child: Icon(
                                    Icons.playlist_play_rounded,
                                    color: libraryAccent,
                                  ),
                                ),
                              ),
                              title: const Text(
                                '全屏边缘播放列表',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: const Padding(
                                padding: EdgeInsets.only(top: 5),
                                child: Text(
                                  '开启后将鼠标移到屏幕右侧边缘即可展开；触发范围与隐藏延迟使用流畅度验证后的默认值。',
                                  style: TextStyle(
                                    color: libraryTextMuted,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('播放器快捷键',
                                            style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800)),
                                        SizedBox(height: 6),
                                        Text('点击动作后直接按键；冲突时会就地提示，不会自动交换或覆盖。',
                                            style: TextStyle(
                                                color: libraryTextMuted)),
                                      ],
                                    ),
                                  ),
                                  TextButton.icon(
                                    key: const ValueKey(
                                        'settings.shortcuts.reset'),
                                    onPressed: _resetShortcuts,
                                    icon: const Icon(Icons.restart_alt_rounded),
                                    label: const Text('恢复默认'),
                                  ),
                                ]),
                                const SizedBox(height: 16),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    const spacing = 14.0;
                                    final fieldWidth = constraints.maxWidth >=
                                            680
                                        ? (constraints.maxWidth - spacing) / 2
                                        : constraints.maxWidth;
                                    return Wrap(
                                      spacing: spacing,
                                      runSpacing: 12,
                                      children: [
                                        for (final action
                                            in PlayerShortcutAction.values)
                                          SizedBox(
                                            width: fieldWidth,
                                            child: PlayerShortcutRecorder(
                                              action: action,
                                              shortcut:
                                                  _settings.shortcuts[action]!,
                                              errorText:
                                                  _shortcutErrors[action],
                                              onCaptured: (key) =>
                                                  _captureShortcut(action, key),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  '支持常用单键及 Ctrl / Alt / Shift 组合键。Esc 在全屏时始终优先退出全屏，避免失去安全出口。',
                                  style: TextStyle(
                                    color: libraryTextMuted,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_section == _SettingsSection.cache) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: FutureBuilder<CacheStats>(
                              future: _statsFuture,
                              builder: (context, snapshot) {
                                final stats = snapshot.data;
                                final cacheBusy = _cacheActionRunning ||
                                    (stats?.active ?? 0) > 0 ||
                                    (stats?.queued ?? 0) > 0 ||
                                    (stats?.pendingBackgroundRequests ?? 0) > 0;
                                if (stats == null) {
                                  return const _CacheDiagnosticsLoading();
                                }
                                return _CacheDiagnosticsPanel(
                                  stats: stats,
                                  cacheBusy: cacheBusy,
                                  onRetry: () => _retryFailedThumbnails(stats),
                                  onClear: () =>
                                      _clearThumbnailFailureMarkers(stats),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/** 构建播放画质设置 focused test 容器，不创建播放器或运行 Compute 基线。 */
@visibleForTesting
Widget playbackQualitySettingsSmokeHarness({
  PlaybackSettings settings = PlaybackSettings.defaults,
  ValueChanged<PlaybackSettings>? onChanged,
}) {
  return MaterialApp(
    theme: settingsWorkspaceTheme(ThemeData(useMaterial3: true)),
    home: MediaQuery(
      data: const MediaQueryData(size: Size(900, 900)),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _PlaybackQualitySettingsPanel(
            settings: settings,
            onChanged: onChanged ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

/** 构建删除文件设置的 focused test 容器，不触发真实删除或文件系统调用。 */
@visibleForTesting
Widget deleteFileSettingsSmokeHarness({
  bool confirmBeforeDeletingVideo = true,
  bool moveDeletedFileToTrash = false,
  bool autoRemoveMissingOrUnreadableVideos = true,
  TextScaler textScaler = TextScaler.noScaling,
  ValueChanged<bool>? onConfirmChanged,
  ValueChanged<bool>? onMoveToTrashChanged,
  ValueChanged<bool>? onAutoRemoveMissingOrUnreadableChanged,
}) {
  return MaterialApp(
    theme: settingsWorkspaceTheme(ThemeData(useMaterial3: true)),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(900, 720),
        textScaler: textScaler,
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _DeleteFileSettingsPanel(
            confirmBeforeDeletingVideo: confirmBeforeDeletingVideo,
            moveDeletedFileToTrash: moveDeletedFileToTrash,
            autoRemoveMissingOrUnreadableVideos:
                autoRemoveMissingOrUnreadableVideos,
            onConfirmChanged: onConfirmChanged ?? (_) {},
            onMoveToTrashChanged: onMoveToTrashChanged ?? (_) {},
            onAutoRemoveMissingOrUnreadableChanged:
                onAutoRemoveMissingOrUnreadableChanged ?? (_) {},
          ),
        ),
      ),
    ),
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

/**
 * 视频数据备份维护面板。
 *
 * 面板只重排已有开关、状态和动作，不读取数据库、不改变备份策略，也不在 build
 * 阶段触发检查或导出；所有业务仍通过调用方回调串行执行。
 */
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

  /** 是否允许后台备份与扫描恢复。 */
  final bool enabled;

  /** 检查或导出运行期间禁止重复提交维护动作。 */
  final bool maintenanceRunning;

  /** 当前备份阶段的用户可读描述。 */
  final String statusLabel;

  /** 当前全量核对进度。 */
  final String progressLabel;

  /** 等待写入独立备份库的数量。 */
  final String pendingLabel;

  /** 最近完整核对时间。 */
  final String lastCompletedLabel;

  /** 运行中才显示的 0–1 进度。 */
  final double? progress;

  /** 保存备份开关。 */
  final ValueChanged<bool> onEnabledChanged;

  /** 启动已有全量备份任务。 */
  final VoidCallback onRunNow;

  /** 执行已有只读完整性检查。 */
  final VoidCallback onCheckIntegrity;

  /** 执行已有便携备份导出。 */
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
            const _SettingsGroupTitle(title: '同步状态'),
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
                child: LinearProgressIndicator(
                  minHeight: 5,
                  value: progress,
                ),
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
                '保留稳定身份、收藏、播放状态及非文件夹标签。移除目录后仍可恢复；明确删除单个视频时会同步清理对应备份。\n不复制视频文件，也不改变 folder 标签来源。',
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

class _SettingsStatLine extends StatelessWidget {
  const _SettingsStatLine({required this.label, required this.value});

  /**
   * 统计项名称。
   */
  final String label;

  /**
   * 统计项展示值。
   */
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

/** 缓存统计读取期间保持与终态一致的结构占位，避免页面加载完成后整体跳位。 */
class _CacheDiagnosticsLoading extends StatelessWidget {
  const _CacheDiagnosticsLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '正在读取缩略图缓存统计',
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CacheDiagnosticsHeader(
            statusLabel: '读取统计中',
            statusColor: appAccentViolet,
          ),
          SizedBox(height: 18),
          Text(
            '正在校验有效 JPEG 与后台任务状态…',
            style: TextStyle(color: libraryTextMuted),
          ),
          SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
            child: LinearProgressIndicator(minHeight: 4),
          ),
        ],
      ),
    );
  }
}

/**
 * 缩略图缓存诊断终态面板。
 *
 * 面板只解释 [CacheStats] 并转发既有失败处理动作，不创建任务、不读磁盘，
 * 也不改变失败属于缺失子集的缓存语义。
 */
class _CacheDiagnosticsPanel extends StatelessWidget {
  const _CacheDiagnosticsPanel({
    required this.stats,
    required this.cacheBusy,
    required this.onRetry,
    required this.onClear,
  });

  /** 当前不可变缓存统计快照。 */
  final CacheStats stats;

  /** 缓存动作或既有后台队列正在运行时禁止重复提交。 */
  final bool cacheBusy;

  /** 定向重试当前失败项的既有回调。 */
  final VoidCallback onRetry;

  /** 只清除失败标记的既有回调。 */
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasFailures = stats.failures.isNotEmpty;
    final cachedRatio = stats.total == 0 ? 0.0 : stats.cached / stats.total;
    final statusLabel = hasFailures
        ? '${formatCount(stats.errors)} 个失败项'
        : stats.paused
            ? '后台任务已暂停'
            : cacheBusy
                ? '后台任务运行中'
                : '缓存服务空闲';
    final statusColor = hasFailures
        ? Colors.orangeAccent
        : cacheBusy || stats.paused
            ? appAccentViolet
            : const Color(0xff42d3a6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CacheDiagnosticsHeader(
          statusLabel: statusLabel,
          statusColor: statusColor,
        ),
        const SizedBox(height: 18),
        _CacheCoverageSummary(
          cached: stats.cached,
          total: stats.total,
          ratio: cachedRatio.clamp(0.0, 1.0).toDouble(),
        ),
        const SizedBox(height: 14),
        _CacheMetricGrid(stats: stats),
        const SizedBox(height: 14),
        _CacheTaskSummary(stats: stats),
        const SizedBox(height: 14),
        const _CacheFailureSemanticsNote(),
        if (hasFailures) ...[
          const SizedBox(height: 14),
          _CacheFailureDetails(failures: stats.failures),
        ],
        const SizedBox(height: 14),
        _CacheFailureActions(
          hasFailures: hasFailures,
          cacheBusy: cacheBusy,
          onRetry: onRetry,
          onClear: onClear,
        ),
      ],
    );
  }
}

/** 缓存页标题、用途说明与当前健康状态。 */
class _CacheDiagnosticsHeader extends StatelessWidget {
  const _CacheDiagnosticsHeader({
    required this.statusLabel,
    required this.statusColor,
  });

  /** 当前服务状态的简短文字。 */
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

/** 有效 JPEG 覆盖率摘要；进度只来源于当前快照，不触发缓存扫描。 */
class _CacheCoverageSummary extends StatelessWidget {
  const _CacheCoverageSummary({
    required this.cached,
    required this.total,
    required this.ratio,
  });

  /** 已验证有效的缓存数量。 */
  final int cached;

  /** 当前媒体库视频总数。 */
  final int total;

  /** 归一化后的有效缓存比例。 */
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('settings.cache.coverage'),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: libraryBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '有效缓存覆盖',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${formatCount(cached)} / ${formatCount(total)}',
                  style: const TextStyle(
                    color: libraryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius:
                  const BorderRadius.all(Radius.circular(AppRadius.capsule)),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                color: appAccentViolet,
                backgroundColor: libraryBorder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/** 总量、有效缓存、缺失和失败的响应式统计网格。 */
class _CacheMetricGrid extends StatelessWidget {
  const _CacheMetricGrid({required this.stats});

  /** 当前统计快照。 */
  final CacheStats stats;

  @override
  Widget build(BuildContext context) {
    final metrics = <({
      String keyName,
      String label,
      String value,
      IconData icon,
      Color color
    })>[
      (
        keyName: 'total',
        label: '总数',
        value: formatCount(stats.total),
        icon: Icons.video_library_outlined,
        color: libraryTextMuted,
      ),
      (
        keyName: 'cached',
        label: '已缓存',
        value: formatCount(stats.cached),
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xff42d3a6),
      ),
      (
        keyName: 'missing',
        label: '缺失',
        value: formatCount(stats.missing),
        icon: Icons.image_not_supported_outlined,
        color: appAccentViolet,
      ),
      (
        keyName: 'errors',
        label: '失败',
        value: formatCount(stats.errors),
        icon: Icons.error_outline_rounded,
        color: stats.errors == 0 ? libraryTextMuted : Colors.orangeAccent,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 420
                ? 2
                : 1;
        const spacing = 10.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: itemWidth,
                child: _CacheMetricCard(
                  key: ValueKey('settings.cache.metric.${metric.keyName}'),
                  label: metric.label,
                  value: metric.value,
                  icon: metric.icon,
                  color: metric.color,
                ),
              ),
          ],
        );
      },
    );
  }
}

/** 单个缓存指标卡片，保持文字缩放时的自然高度。 */
class _CacheMetricCard extends StatelessWidget {
  const _CacheMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  /** 指标名称。 */
  final String label;

  /** 已格式化的指标值。 */
  final String value;

  /** 指标语义图标。 */
  final IconData icon;

  /** 指标强调色，不作为唯一状态编码。 */
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: libraryBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: libraryTextMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: libraryText,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/** 后台并发、排队、请求和耗时保持在独立结构表面中。 */
class _CacheTaskSummary extends StatelessWidget {
  const _CacheTaskSummary({required this.stats});

  /** 当前任务统计快照。 */
  final CacheStats stats;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('settings.cache.taskSummary'),
      decoration: BoxDecoration(
        color: librarySurfaceAlt.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: libraryBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('后台任务', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                _CacheTaskValue(
                  label: '活动',
                  value: '${stats.active} / ${stats.maxConcurrent}',
                ),
                _CacheTaskValue(
                  label: '排队',
                  value: formatCount(stats.queued),
                ),
                _CacheTaskValue(
                  label: '后台请求',
                  value: formatCount(stats.pendingBackgroundRequests),
                ),
                _CacheTaskValue(
                  label: '平均耗时',
                  value: '${stats.averageMs} ms',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/** 后台任务摘要中的单个键值。 */
class _CacheTaskValue extends StatelessWidget {
  const _CacheTaskValue({required this.label, required this.value});

  /** 字段名称。 */
  final String label;

  /** 已格式化字段值。 */
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label  ',
            style: const TextStyle(
              color: libraryTextMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/** 明确失败与缺失的包含关系，避免用户误解统计口径。 */
class _CacheFailureSemanticsNote extends StatelessWidget {
  const _CacheFailureSemanticsNote();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('settings.cache.failureSemantics'),
      decoration: BoxDecoration(
        color: appAccentViolet.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: appAccentViolet.withValues(alpha: 0.24)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: appAccentViolet, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '失败属于缺失的可诊断子集：失败项当前没有有效 JPEG，因此会同时计入缺失；普通缺失可能只是尚未生成。',
                style: TextStyle(color: libraryTextMuted, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/** 可展开的失败文件与最近原因列表，最多展示现有的前 50 项。 */
class _CacheFailureDetails extends StatelessWidget {
  const _CacheFailureDetails({required this.failures});

  /** 当前缺少有效 JPEG 且保留失败原因的条目。 */
  final List<CacheFailureDetail> failures;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: librarySurfaceAlt.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: libraryBorder),
      ),
      child: ExpansionTile(
        key: const ValueKey('settings.cache.failureDetails'),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          '失败详情 · ${failures.length}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text('显示视频标题和最近一次缩略图失败原因'),
        children: [
          for (final failure in failures.take(50))
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.error_outline_rounded,
                color: Colors.orangeAccent,
              ),
              title: Text(
                failure.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                failure.reason,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (failures.length > 50)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '另有 ${failures.length - 50} 条，请处理当前失败项后刷新统计。',
                style: const TextStyle(color: libraryTextMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/** 失败处理区保留既有动作，并在没有失败时给出明确完成反馈。 */
class _CacheFailureActions extends StatelessWidget {
  const _CacheFailureActions({
    required this.hasFailures,
    required this.cacheBusy,
    required this.onRetry,
    required this.onClear,
  });

  /** 当前是否存在可定向处理的失败条目。 */
  final bool hasFailures;

  /** 既有队列忙碌时禁止重复提交。 */
  final bool cacheBusy;

  /** 重试回调。 */
  final VoidCallback onRetry;

  /** 清除失败标记回调。 */
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final actionsEnabled = hasFailures && !cacheBusy;
    final status = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          hasFailures
              ? Icons.build_circle_outlined
              : Icons.check_circle_outline_rounded,
          color: hasFailures ? Colors.orangeAccent : const Color(0xff42d3a6),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasFailures ? '失败处理' : '当前没有失败项',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                hasFailures
                    ? cacheBusy
                        ? '后台任务结束后可重试或清除诊断标记。'
                        : '重试复用现有优先队列；清除标记不会删除视频或有效缓存。'
                    : '无需重试或清理；普通缺失会在既有队列需要时生成。',
                style: const TextStyle(color: libraryTextMuted, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          key: const ValueKey('settings.cache.retryFailures'),
          onPressed: actionsEnabled ? onRetry : null,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重试失败项'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('settings.cache.clearFailures'),
          onPressed: actionsEnabled ? onClear : null,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('清除失败标记'),
        ),
      ],
    );
    return DecoratedBox(
      key: const ValueKey('settings.cache.failureActions'),
      decoration: BoxDecoration(
        color: librarySurfaceAlt.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: libraryBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 动作区优先保证说明可读，窄窗时按钮自然换到下一行。
            if (constraints.maxWidth < 780) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  status,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: status),
                const SizedBox(width: 14),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.applicationService,
    required this.fileSystem,
    required this.playerBackendFactory,
    required this.mediaProbeBackendFactory,
  });

  /** facade 加载、偏好持久化、缩略图与媒体详情创建的页面应用服务。 */
  final LibraryPageApplicationService applicationService;

  /** 目录选择、异步枚举、文件检查和删除的平台边界。 */
  final FileSystemAdapter fileSystem;

  /** 仅转交播放器页面的后端工厂。 */
  final PlayerBackendFactory playerBackendFactory;

  /** 仅转交播放器页面的媒体探测工厂。 */
  final MediaProbeBackendFactory mediaProbeBackendFactory;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

/**
 * 媒体库主结果区当前展示的数据来源。
 *
 * 这里只控制页面展示列表，不改变底层标签筛选语义；播放时仍把当前可见结果作为播放队列传入播放器。
 */
enum _LibraryResultMode {
  /** 全量媒体库结果，受搜索、标签和收藏筛选影响。 */
  library,

  /** 继续观看结果，只展示具有有效未完成进度的视频。 */
  recent,

  /** 本地收藏结果，只展示用户收藏的视频。 */
  favorites,

  /** 本地媒体库路径浏览，按文件系统层级展示文件夹和视频。 */
  local,
}

/**
 * 选择添加目录或文件时使用的媒体上下文起点。
 *
 * 当前正在浏览的本地目录优先，其次使用首个已管理 root；两者都不存在时返回 null，
 * 由平台选择器决定默认位置，避免回到与视频无关的系统“图片”目录。
 */
@visibleForTesting
String? preferredLibraryPickerDirectory({
  required String? currentPath,
  required List<String> roots,
}) {
  final current = currentPath?.trim();
  if (current != null && current.isNotEmpty) {
    return current;
  }
  return roots.isEmpty ? null : roots.first;
}

List<VideoItem> recentPlaybackClearTargets(
  Iterable<VideoItem> videos, {
  required Set<String> selectedPathKeys,
  required bool selectedOnly,
}) {
  return videos.where((item) {
    if (item.lastPlayedAt == null) {
      return false;
    }
    return !selectedOnly ||
        selectedPathKeys.contains(TagRules.pathKey(item.path));
  }).toList();
}

/**
 * 二次确认清空全部继续观看进度。
 *
 * 文案明确只清进度、不删除视频，并提前说明可撤销窗口，避免“清空全部”被理解为
 * 删除媒体文件或永久破坏标签、收藏。
 */
@visibleForTesting
Future<bool?> showClearAllRecentPlaybackConfirmation(
  BuildContext context, {
  required int count,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('清空全部观看进度？'),
      content: Text(
        '将清除 $count 条继续观看进度，不会删除视频文件、标签或收藏。清除后可在 10 秒内撤销。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('只清除进度'),
        ),
      ],
    ),
  );
}

/**
 * 清理继续观看前保存的完整播放状态。
 *
 * Undo 必须恢复原来的最近播放时间、精确位置、完成态和位置更新时间，不能依赖重新播放
 * 生成近似记录；[videoId] 只用于诊断和稳定识别，不以可变路径作为恢复身份。
 */
@visibleForTesting
class ContinueWatchingClearSnapshot {
  const ContinueWatchingClearSnapshot._({
    required this.item,
    required this.videoId,
    required this.lastPlayedAt,
    required this.playbackPosition,
    required this.playbackCompleted,
    required this.playbackPositionUpdatedAt,
  });

  /** 捕获一次清理动作之前的用户播放状态。 */
  factory ContinueWatchingClearSnapshot.capture(VideoItem item) =>
      ContinueWatchingClearSnapshot._(
        item: item,
        videoId: item.videoId,
        lastPlayedAt: item.lastPlayedAt,
        playbackPosition: item.playbackPosition,
        playbackCompleted: item.playbackCompleted,
        playbackPositionUpdatedAt: item.playbackPositionUpdatedAt,
      );

  /** 当前内存中的稳定视频对象；恢复时不替换对象，避免列表和播放器持有旧引用。 */
  final VideoItem item;

  /** 清理时的视频稳定身份。 */
  final String videoId;

  /** 清理前用于继续观看排序的最近播放时间。 */
  final DateTime? lastPlayedAt;

  /** 清理前的精确播放位置。 */
  final Duration playbackPosition;

  /** 清理前的播放完成态。 */
  final bool playbackCompleted;

  /** 清理前用于解决异步写入先后顺序的位置更新时间。 */
  final DateTime? playbackPositionUpdatedAt;

  /**
   * 仅当记录仍保持本次清理后的空状态时允许 Undo。
   *
   * 如果用户在 10 秒窗口内重新播放了视频，旧快照不得覆盖刚产生的新进度。
   */
  bool get canRestoreWithoutOverwritingNewPlayback =>
      item.videoId == videoId &&
      item.lastPlayedAt == null &&
      item.playbackPosition == Duration.zero &&
      !item.playbackCompleted &&
      item.playbackPositionUpdatedAt == null;

  /** 把捕获的精确播放状态恢复到原稳定视频对象。 */
  void restore() {
    item
      ..lastPlayedAt = lastPlayedAt
      ..playbackPosition = playbackPosition
      ..playbackCompleted = playbackCompleted
      ..playbackPositionUpdatedAt = playbackPositionUpdatedAt;
  }
}

class _LibraryPageState extends State<LibraryPage> {
  LibraryApplicationFacade? _store;
  PlaybackSnapshotWriteQueue? _playbackSnapshotQueue;
  ThumbnailService? _thumbnailService;
  MediaDetailsService? _libraryMediaDetailsService;
  PlaybackSettings _playbackSettings = PlaybackSettings.defaults;
  /** 当前自动清理任务；启动与扫描完成阶段共享，避免重复遍历大型媒体库。 */
  Future<int>? _unavailableCleanupFuture;
  DataBackupSettings _dataBackupSettings = DataBackupSettings.defaults;
  final _filterStateSource = FilterStateSource();
  final _countRefreshCoordinator = LibraryCountRefreshCoordinator();
  final _searchController = TextEditingController();
  /**
   * 主搜索框焦点节点。
   *
   * `Ctrl+K`、真实键盘输入和桌面自动化都必须落到同一个 EditableText，
   * 否则搜索文字不会进入 controller，也就不会触发 `onChanged` 筛选链路。
   */
  final _searchFocusNode = FocusNode(debugLabel: 'library-search-field');
  final _selectedTags = <String>{};
  final _selectedChildTags = <String>{};
  final _selectedGroupTagIds = <String, Set<String>>{};
  final _excludedTagIds = <String>{};
  FilterState? _filterState;

  Map<String, int> _visibleResultCounts = const <String, int>{};

  /**
   * 右侧标签发现面板使用的全库稳定计数。
   *
   * 当前筛选会改变视频结果，但标签面板中的其它标签数量不能因为当前筛选被压缩到 0，
   * 否则用户无法判断原始标签规模。
   */
  Map<String, int> _stableTagCounts = const <String, int>{};

  var _filterRevision = 0;
  var _playbackDataRevision = 0;
  var _suppressSearchControllerChange = false;
  var _searchControllerChangeQueued = false;
  var _lastObservedSearchText = '';

  /** 播放器内单条修改延后到返回媒体库时刷新可见结果，不刷新全库计数。 */
  var _playerScopedLibraryDataChanged = false;
  /** 播放器内 relink 会改变 folder 标签，需要在返回后低频刷新标签计数。 */
  var _playerScopedNeedsCountRefresh = false;
  /** 最近一次播放器的原生释放信号；专项压测必须等它完成再开始下一会话。 */
  Future<void> _latestPlayerRelease = Future<void>.value();
  /** 播放器 Route 存续期间只隐藏媒体库语义，不卸载列表或丢失筛选状态。 */
  var _playerRouteActive = false;
  /** 当前应用会话内保留播放器全屏偏好，媒体库和其他页面本身始终使用普通窗口状态。 */
  final _playerFullscreenSession = PlayerFullscreenSessionController();

  var _isRefreshingVideos = false;

  var _isRefreshingCounts = false;

  var _libraryDataRevision = 0;
  var _showFavoritesOnly = false;
  var _isScanning = false;
  /** 用户已请求取消扫描，但后端仍在退出当前系统调用。 */
  var _isCancellingScan = false;
  LibraryScanProgress? _scanProgress;
  /**
   * 当前目录导入的后台媒体信息解析进度。
   *
   * 扫描提交后视频列表立即可用；该状态只描述仍在后台补齐的媒体详情，不阻塞筛选、
   * 滚动或播放。全部成功或失败后自动清空并恢复正常结果摘要。
   */
  MediaDetailsProgress? _mediaImportProgress;
  /** debug 扫描帧采样器；发布构建始终为 null。 */
  LibraryScanUiDiagnostics? _activeScanUiDiagnostics;
  var _sortMode = SortMode.recent;
  var _sortDirection = SortDirection.descending;
  var _denseResultGrid = false;
  /** 主功能栏折叠态只影响当前页面布局，不写入媒体库数据或筛选状态。 */
  var _isMainSidebarCollapsed = false;
  var _isTagDiscoveryPanelOpen = libraryTagDiscoveryPanelInitiallyOpen;
  /**
   * expanded 结果滚动时的顶部信息区目标状态。
   *
   * 使用独立 notifier 只重建顶部动效边界，不让滚动方向变化触发整个媒体库页面重建。
   */
  final _libraryHeaderVisible = ValueNotifier<bool>(true);
  var _resultMode = _LibraryResultMode.library;
  Object? _recentVideoCacheKey;
  Object? _favoriteVideoCacheKey;
  Object? _localEntryCacheKey;
  Object? _tagGroupsCacheKey;
  List<VideoItem> _recentVideoCache = const <VideoItem>[];
  List<VideoItem> _favoriteVideoCache = const <VideoItem>[];
  List<LocalLibraryEntry> _localEntryCache = const <LocalLibraryEntry>[];
  final _localEntryCacheByKey = <Object, List<LocalLibraryEntry>>{};
  /** 正在后台枚举的本地路径缓存键，避免每次 build 重复发起目录读取。 */
  final _localEntryLoads = <Object>{};
  List<TagGroup> _tagGroupsCache = const <TagGroup>[];

  /** 当前页面共享的文件系统平台边界。 */
  FileSystemAdapter get _fileSystem => widget.fileSystem;

  /**
   * 最近播放清理时的临时选择集。
   *
   * 只保存 pathKey，不新增数据库字段；确认删除时把对应视频的 lastPlayedAt 清空。
   */
  final _selectedRecentPathKeys = <String>{};

  /**
   * 主媒体结果区是否处于多选模式。
   *
   * 该状态只改变工具栏和卡片点击语义，不写入数据库，也不改变当前筛选结果或播放队列。
   */
  var _librarySelectionMode = false;

  /**
   * 主媒体结果区已选择的稳定 videoId。
   *
   * 使用 videoId 而不是可变路径，保证同一会话内排序变化不会丢失选择；筛选或切换结果
   * 来源时统一退出多选，避免保留不可见选择。
   */
  final _selectedLibraryVideoIds = <String>{};

  /**
   * 本地媒体库当前浏览路径。
   *
   * 该路径来自已配置 root 或其子目录，只用于文件系统式浏览，不改变扫描和标签规则。
   */
  String? _localLibraryPath;

  /**
   * 本地媒体库文件夹浏览返回栈。
   *
   * 从侧栏 root 入口进入时清空；从文件夹项进入时记录上一级路径，让返回按钮和鼠标侧键能回到上一层。
   */
  final _localLibraryBackStack = <String>[];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalSearchShortcut);
    _searchController.addListener(_handleSearchControllerChanged);
    _load();
  }

  @override
  void dispose() {
    LibraryStressControl.unregister(this);
    unawaited(_playbackSnapshotQueue?.dispose());
    _libraryMediaDetailsService?.dispose();
    _activeScanUiDiagnostics?.abort();
    HardwareKeyboard.instance.removeHandler(_handleGlobalSearchShortcut);
    _searchController.removeListener(_handleSearchControllerChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _libraryHeaderVisible.dispose();
    _countRefreshCoordinator.dispose();
    super.dispose();
  }

  /**
   * 在媒体库页面处于最上层时稳定处理 Ctrl+K。
   *
   * Windows 真实窗口中焦点可能停在页面容器而不进入局部 Shortcuts 焦点链，
   * 因此页面生命周期内补充全局键盘处理；弹窗或播放器路由位于上层时不抢焦点。
   */
  bool _handleGlobalSearchShortcut(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyK ||
        !HardwareKeyboard.instance.isControlPressed ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    _focusSearchField();
    return true;
  }

  void _handleSearchControllerChanged() {
    if (_suppressSearchControllerChange) {
      return;
    }
    final keyword = _searchController.text;
    if (keyword == _lastObservedSearchText || _searchControllerChangeQueued) {
      return;
    }
    _lastObservedSearchText = keyword;
    _searchControllerChangeQueued = true;
    scheduleMicrotask(() {
      _searchControllerChangeQueued = false;
      if (!mounted || _searchController.text != _lastObservedSearchText) {
        return;
      }
      _mutateFilters(() {}, refreshCounts: false);
    });
  }

  void _setSearchTextSilently(String value) {
    if (_searchController.text == value) {
      _lastObservedSearchText = value;
      return;
    }
    _suppressSearchControllerChange = true;
    _searchController.text = value;
    _lastObservedSearchText = value;
    _suppressSearchControllerChange = false;
  }

  void _clearSearchSilently() => _setSearchTextSilently('');

  /**
   * 聚焦主搜索框并选中已有关键字。
   *
   * 该方法只处理焦点，不直接触发筛选；真实键盘或自动化输入随后写入
   * `TextEditingController`，再由统一的监听链路刷新结果。
   */
  void _focusSearchField() {
    _searchFocusNode.requestFocus();
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
    // Windows 全局快捷键可能与本帧的页面 Focus 重建竞争；下一帧再次确认焦点，
    // 让真实键盘和自动化输入稳定落到同一个 EditableText。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _searchFocusNode.requestFocus();
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
    });
  }

  Future<void> _load() async {
    final diagnostics = kDebugMode ? LibraryLoadDiagnostics() : null;
    final startupWatch = Stopwatch()..start();
    final startupData = await widget.applicationService.load(
      diagnostics: diagnostics,
    );
    final store = startupData.store;
    final thumbnailService = startupData.thumbnailService;
    final playbackSettings = startupData.playbackSettings;
    final dataBackupSettings = startupData.dataBackupSettings;
    final sortPreferences = startupData.sortPreferences;
    if (!mounted) {
      await store.close();
      return;
    }
    _playbackSnapshotQueue = PlaybackSnapshotWriteQueue(
      writer: (snapshot) async {
        snapshot.item
          ..playbackPosition = snapshot.position
          ..playbackDuration = snapshot.duration
          ..playbackCompleted = snapshot.completed
          ..playbackPositionUpdatedAt = snapshot.updatedAt
          ..lastPlayedAt = snapshot.updatedAt;
        await store.savePlaybackPosition(
          videoId: snapshot.item.videoId,
          position: snapshot.position,
          duration: snapshot.duration,
          completed: snapshot.completed,
          updatedAt: snapshot.updatedAt,
        );
      },
    );
    final firstFrameWatch = Stopwatch()..start();
    void applyHydratedState() => setState(() {
          _sortMode = sortPreferences.mode;
          _sortDirection = sortPreferences.direction;
          _denseResultGrid = sortPreferences.denseResultGrid;
          _store = store;
          _thumbnailService = thumbnailService;
          _playbackSettings = playbackSettings;
          _dataBackupSettings = dataBackupSettings;
          _lastObservedSearchText = _searchController.text;
          _filterState = _buildImmediateFilterState(store);
          _visibleResultCounts = _fallbackResultCounts(store);
          _stableTagCounts = const <String, int>{};
        });
    if (diagnostics == null) {
      applyHydratedState();
    } else {
      diagnostics.measureSync(
        'ui.hydrated_state_prepare',
        applyHydratedState,
      );
      unawaited(widget.applicationService.writeStartupDiagnostics(
        diagnostics: diagnostics,
        totalElapsed: startupWatch.elapsed,
        marker: 'hydrated_state_ready',
      ));
    }
    _registerLibraryStressControl(store, thumbnailService);
    // 首帧只消费 SQLite 已恢复的对象和持久化 usageCount；目录扫描与全库计数不得阻塞首屏。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _store != store) {
        return;
      }
      firstFrameWatch.stop();
      if (diagnostics != null) {
        diagnostics.record(
            'ui.first_frame_build_and_layout', firstFrameWatch.elapsed);
        unawaited(widget.applicationService.writeStartupDiagnostics(
          diagnostics: diagnostics,
          totalElapsed: startupWatch.elapsed,
          marker: 'first_frame_ready',
        ));
      }
      _scheduleFilterRefresh();
      _scheduleInitialStableTagCounts(store);
      unawaited(() async {
        if (playbackSettings.autoRemoveMissingOrUnreadableVideos) {
          await _cleanupMissingOrUnreadableVideos(store);
        }
        if (mounted && identical(_store, store)) {
          await _promptForNewVideos(store);
        }
      }());
    });
  }

  /** 串行清理无效数据库记录，完成后统一刷新筛选结果与标签计数。 */
  Future<int> _cleanupMissingOrUnreadableVideos(
    LibraryApplicationFacade store,
  ) {
    final active = _unavailableCleanupFuture;
    if (active != null) {
      return active;
    }
    final task = store.removeMissingOrUnreadableVideos();
    _unavailableCleanupFuture = task;
    return task.whenComplete(() {
      if (identical(_unavailableCleanupFuture, task)) {
        _unavailableCleanupFuture = null;
      }
      if (mounted && identical(_store, store)) {
        _markLibraryDataChanged();
      }
    });
  }

  /**
   * 为显式隔离 profile 注册真实窗口专项压测入口。
   *
   * 环境变量缺失时不注册；回调固定使用同一个 root，防止测试代码把任意路径
   * 传入生产页面。添加仍经过 `_scan`，移除仍经过 SQLite 单事务和 UI 差量刷新。
   */
  void _registerLibraryStressControl(
    LibraryApplicationFacade store,
    ThumbnailService thumbnailService,
  ) {
    final root = widget.applicationService.stressRoot;
    if (!kDebugMode || root == null || root.isEmpty) {
      return;
    }
    LibraryStressControl.register(
      owner: this,
      addRoot: () async {
        LibraryScanCommitResult? captured;
        await _scan((onProgress) async {
          final result = await store.addRootAndScanWithChanges(
            root,
            onProgress: onProgress,
          );
          captured = result;
          return result;
        });
        final result = captured;
        if (result == null || result.cancelled) {
          throw StateError('专项压测添加目录未完成');
        }
        return result;
      },
      removeRoot: () => _removeLibraryRootData(root),
      waitForPlayerRelease: () => _latestPlayerRelease,
      snapshot: () {
        final probes = _libraryMediaDetailsService;
        return LibraryStressSnapshot(
          videoCount: store.videos.length,
          visibleCount: _filterState?.filteredVideos.length ?? 0,
          roots: List<String>.unmodifiable(store.roots),
          thumbnailQueued: thumbnailService.queuedJobs,
          thumbnailActive: thumbnailService.activeJobs,
          probeQueued: probes?.queuedReads ?? 0,
          probeActive: probes?.activeReads ?? 0,
          probeCompleted: probes?.completedThisRun ?? 0,
          probeFailed: probes?.failedThisRun ?? 0,
        );
      },
    );
  }

  /** 在首帧之后的空闲窗口刷新稳定标签计数，过期页面结果会被丢弃。 */
  void _scheduleInitialStableTagCounts(LibraryApplicationFacade store) {
    _countRefreshCoordinator.schedule(
      query: const FilterQuery(),
      compute: store.resultCounts,
      isStillCurrent: (_) => mounted && _store == store,
      onComplete: (counts) {
        if (!mounted || _store != store) {
          return;
        }
        setState(() => _stableTagCounts = counts);
      },
    );
  }

  Future<void> _promptForNewVideos(LibraryApplicationFacade store) async {
    if (store.roots.isEmpty) {
      return;
    }
    final count = await store.countUntrackedVideos();
    if (!mounted || count == 0 || _store != store) {
      return;
    }
    final shouldScan = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('\u53d1\u73b0\u65b0\u589e\u89c6\u9891'),
        content: Text(
            '\u5f53\u524d\u76ee\u5f55\u53d1\u73b0 $count \u4e2a\u672a\u5165\u5e93\u89c6\u9891\uff0c\u662f\u5426\u73b0\u5728\u91cd\u65b0\u626b\u63cf\uff1f'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('\u7a0d\u540e'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('\u91cd\u65b0\u626b\u63cf'),
          ),
        ],
      ),
    );
    if (shouldScan == true && mounted && _store == store) {
      await _rescan();
    }
  }

  Future<void> _pickFolder() async {
    final store = _store;
    final paths = await _fileSystem.pickDirectories(
      dialogTitle: '\u9009\u62e9\u89c6\u9891\u76ee\u5f55',
      initialDirectory: preferredLibraryPickerDirectory(
        currentPath: _localLibraryPath,
        roots: store?.roots ?? const <String>[],
      ),
    );
    final path = paths.isEmpty ? null : paths.first;
    if (path == null || _store == null) {
      return;
    }
    await _scan(
      (onProgress) => _store!.addRootAndScanWithChanges(
        path,
        onProgress: onProgress,
      ),
    );
  }

  /**
   * 打开系统多文件选择器，并把所选视频的父目录交给统一扫描链路。
   *
   * 选择器只允许视频扩展名；文件不会被复制或移动，应用仅注册其所在目录并建立索引。
   */
  Future<void> _pickVideoFiles() async {
    final store = _store;
    final paths = await _fileSystem.pickFiles(
      dialogTitle: '选择要添加的视频文件',
      initialDirectory: preferredLibraryPickerDirectory(
        currentPath: _localLibraryPath,
        roots: store?.roots ?? const <String>[],
      ),
      allowedExtensions: TagRules.videoExtensions
          .map((extension) => extension.substring(1))
          .toList(),
    );
    await _importLibraryPaths(paths);
  }

  /**
   * 校验选择器或资源管理器拖入的路径，并以最少 root 数量触发一轮扫描。
   *
   * 已受现有 root 管理的文件只触发重新扫描；目录和视频文件之外的项目会被忽略。文件
   * stat 通过 [FileSystemAdapter] 异步执行，不在 build 或拖动悬停阶段访问磁盘。
   */
  Future<void> _importLibraryPaths(Iterable<String> rawPaths) async {
    final store = _store;
    if (store == null || _isScanning) {
      return;
    }
    final normalizedPaths = <String>[];
    final pathKeys = <String>{};
    for (final rawPath in rawPaths) {
      final normalized = _fileSystem.normalizePath(rawPath);
      if (normalized.trim().isNotEmpty &&
          pathKeys.add(TagRules.pathKey(normalized))) {
        normalizedPaths.add(normalized);
      }
    }
    final inspected = await Future.wait<LibraryImportPath?>(
      normalizedPaths.map((path) async {
        if (await _fileSystem.directoryExists(path)) {
          return (path: path, isDirectory: true);
        }
        if (TagRules.isVideoPath(path) && await _fileSystem.fileExists(path)) {
          return (path: path, isDirectory: false);
        }
        return null;
      }),
    );
    if (!mounted || _store != store) {
      return;
    }
    final imports = inspected.whereType<LibraryImportPath>().toList();
    if (imports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未发现可添加的视频文件或目录')),
      );
      return;
    }
    final newRoots = libraryImportRoots(
      imports: imports,
      existingRoots: store.roots,
    );
    await _scan(
      newRoots.isEmpty
          ? (onProgress) => store.scanWithChanges(onProgress: onProgress)
          : (onProgress) => store.addRootsAndScanWithChanges(
                newRoots,
                onProgress: onProgress,
              ),
    );
  }

  Future<void> _rescan() async {
    if (_store == null) {
      return;
    }
    await _scan(
      (onProgress) => _store!.scanWithChanges(onProgress: onProgress),
    );
  }

  Future<void> _scan(
    Future<LibraryScanCommitResult> Function(
      LibraryScanProgressCallback onProgress,
    ) action,
  ) async {
    if (_isScanning) {
      return;
    }
    // 新扫描优先使用磁盘；取消上一轮后台媒体探测，避免两类顺序读取互相争抢。
    _libraryMediaDetailsService?.dispose();
    _libraryMediaDetailsService = null;
    _activeScanUiDiagnostics?.abort();
    final diagnostics = kDebugMode ? LibraryScanUiDiagnostics() : null;
    diagnostics?.start();
    _activeScanUiDiagnostics = diagnostics;
    var diagnosticsWillFinish = false;
    setState(() {
      _isScanning = true;
      _isCancellingScan = false;
      _scanProgress = null;
      _mediaImportProgress = null;
    });
    try {
      final actionWatch = Stopwatch()..start();
      final result = await action((progress) {
        if (!mounted || !_isScanning) {
          return;
        }
        diagnostics?.recordProgress(progress);
        setState(() => _scanProgress = progress);
      });
      actionWatch.stop();
      diagnostics?.markScanComplete();
      diagnostics?.recordStage(
        'scan.backend_and_commit',
        actionWatch.elapsed,
        itemCount: result.changedVideos.length,
      );
      if (!mounted) {
        return;
      }
      if (result.cancelled) {
        return;
      }
      // 只为新增或内容变化项目进入缓存队列，避免每次扫描重新排队整个媒体库。
      _thumbnailService?.prefetchAll(result.probeCandidates);
      _startLibraryMediaProbes(result);
      diagnostics?.markPostApply();
      final applyWatch = Stopwatch()..start();
      _applyLibraryScanDelta(result);
      final store = _store;
      if (store != null &&
          _playbackSettings.autoRemoveMissingOrUnreadableVideos) {
        // 先反馈扫描完成，再异步串行清理；不可读探测不得阻塞 UI。
        unawaited(_cleanupMissingOrUnreadableVideos(store));
      }
      applyWatch.stop();
      diagnostics?.recordStage(
        'ui.delta_schedule',
        applyWatch.elapsed,
        itemCount: result.changedVideos.length,
      );
      if (diagnostics != null) {
        diagnosticsWillFinish = true;
        unawaited(diagnostics.finish(result).whenComplete(() {
          if (identical(_activeScanUiDiagnostics, diagnostics)) {
            _activeScanUiDiagnostics = null;
          }
        }));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('扫描完成：新增 ${result.addedCount}，修改 ${result.modifiedCount}，'
                    '移动 ${result.relinkedCount}，缺失 ${result.missingCount}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\u626b\u63cf\u5931\u8d25\uff1a$error')),
      );
    } finally {
      if (!diagnosticsWillFinish) {
        diagnostics?.abort();
        if (identical(_activeScanUiDiagnostics, diagnostics)) {
          _activeScanUiDiagnostics = null;
        }
      }
      if (mounted) {
        setState(() {
          _isScanning = false;
          _isCancellingScan = false;
          _scanProgress = null;
        });
      }
    }
  }

  /** 用户显式暂停/继续扫描；活动 sidecar 从当前候选位置恢复，不重新遍历目录。 */
  Future<void> _toggleScanPaused() async {
    final store = _store;
    final progress = _scanProgress;
    if (store == null || !_isScanning || progress == null) {
      return;
    }
    final paused = !progress.isPaused;
    setState(() => _scanProgress = progress.copyWith(isPaused: paused));
    await store.setScanPaused(paused);
  }

  /**
   * 请求取消当前扫描，并保留取消前已经存在的媒体库数据。
   *
   * UI 保持“正在取消”直到扫描 Future 真正退出，避免用户重复启动并发扫描。
   */
  Future<void> _cancelScan() async {
    final store = _store;
    if (store == null || !_isScanning || _isCancellingScan) {
      return;
    }
    setState(() => _isCancellingScan = true);
    try {
      await store.cancelActiveScan();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isCancellingScan = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取消扫描失败：$error')),
      );
    }
  }

  /**
   * 仅把本轮新增或内容变化项目送入串行媒体探测队列。
   *
   * 新扫描会先 dispose 旧服务并取消其 generation；回调还会校验 store 与 fingerprint，
   * 防止旧文件结果覆盖新内容。SQLite 写入继续由 Dart Repository 完成。
   */
  void _startLibraryMediaProbes(LibraryScanCommitResult result) {
    _libraryMediaDetailsService?.dispose();
    _libraryMediaDetailsService = null;
    final store = _store;
    if (store == null) {
      return;
    }
    final probeCandidatesById = <String, VideoItem>{
      for (final item in result.probeCandidates) item.videoId: item,
    };
    // 旧版媒体详情没有保存总时长。扫描完成后只把仍缺少可靠时长的活动视频
    // 合并进既有有限批次队列，卡片 build 不访问磁盘，完成后复用现有播放时长列。
    for (final item in store.videos.values) {
      if (!item.isMissing &&
          item.playbackDuration <= Duration.zero &&
          item.mediaDetails != null &&
          item.mediaDetailsError == null) {
        probeCandidatesById[item.videoId] = item;
      }
    }
    final probeCandidates = probeCandidatesById.values.toList(growable: false);
    if (probeCandidates.isEmpty) {
      return;
    }
    final service = _createLibraryMediaDetailsService(
      store,
      trackImportProgress: true,
    );
    _libraryMediaDetailsService = service;
    // 新增项和旧版缺时长项统一登记为有限批次；真实进入视口仍可提升同一路径任务，
    // 服务通过 videoId/路径去重，不扩大并发。
    service.prefetchAll(probeCandidates);
  }

  /** 创建媒体库详情会话；所有写回继续校验当前 Store、videoId 与 fingerprint。 */
  MediaDetailsService _createLibraryMediaDetailsService(
    LibraryApplicationFacade store, {
    bool trackImportProgress = false,
  }) {
    return widget.applicationService.createMediaDetailsService(
      onBatchUpdated: (updates) async {
        final validUpdates = <VideoItem>[];
        for (final update in updates) {
          final item = update.item;
          final current = store.videos[TagRules.pathKey(item.path)];
          if (_store != store ||
              current == null ||
              current.videoId != item.videoId ||
              current.mediaFingerprint != update.fingerprint) {
            continue;
          }
          // 探测完成可能晚于 root 移除或下一轮扫描；只更新 Store 中仍然有效的当前对象，
          // 禁止旧回调通过 upsert 把已删除记录重新插回 SQLite 和内存索引。
          current.mediaDetails = update.details;
          current.mediaDetailsError = item.mediaDetailsError;
          final duration = update.details.duration;
          if (duration != null && duration > Duration.zero) {
            // 总时长复用稳定 videoId 上已有的持久化列，不新增 schema 或路径绑定。
            current.playbackDuration = duration;
          }
          validUpdates.add(current);
        }
        await store.upsertVideos(validUpdates);
        if (!trackImportProgress &&
            validUpdates.isNotEmpty &&
            mounted &&
            _store == store) {
          // 可见项补齐总时长后只刷新现有视图，不提升媒体库 revision，也不重算筛选或标签计数。
          setState(() {});
        }
      },
      onProgress: trackImportProgress
          ? (progress) {
              if (!mounted || _store != store) {
                return;
              }
              setState(() {
                _mediaImportProgress = progress.isComplete ? null : progress;
              });
            }
          : null,
    );
  }

  /** 在不影响已显示列表的前提下暂停或继续当前后台媒体解析队列。 */
  void _toggleMediaImportPaused() {
    final service = _libraryMediaDetailsService;
    final progress = _mediaImportProgress;
    if (service == null || progress == null) {
      return;
    }
    if (progress.isPaused) {
      service.resume();
    } else {
      service.pause();
    }
  }

  /**
   * 把媒体库当前可视卡片的详情提升到扫描后台队列之前。
   *
   * Widget 只报告真实构建项；服务继续串行探测并丢弃过期代次，不在 UI 线程等待。
   */
  void _prioritizeVisibleLibraryItem(VideoItem item) {
    if (item.isMissing) {
      return;
    }
    final store = _store;
    if (store == null) {
      return;
    }
    var service = _libraryMediaDetailsService;
    if (service == null || service.isDisposed) {
      service = _createLibraryMediaDetailsService(store);
      _libraryMediaDetailsService = service;
    }
    unawaited(service.detailsFor(
      item,
      // 正常启动不会全量重扫；旧缓存缺时长时只提升真实可见项，继续复用有限批次队列。
      refreshIncomplete: item.playbackDuration <= Duration.zero,
      priority: true,
    ));
  }

  FilterState _computeFilterState(
    LibraryApplicationFacade store,
    FilterQuery query,
  ) {
    _filterStateSource.configure(
      engine: TagQueryService(
        videos: store.videos.values,
        tagContext: store.tagQueryContext,
      ),
      totalCount: store.videos.length,
      sourceKey: _libraryDataRevision,
      sortKey: (_sortMode, _sortDirection),
      compare: _compareVideos,
      sortVideos: (videos) => sortedLibraryVideos(
        videos,
        sortMode: _sortMode,
        sortDirection: _sortDirection,
      ),
    );
    return _filterStateSource.update(query);
  }

  /** 使用扫描差量替换已缓存结果中的变化视频。 */
  FilterState _computeFilterStateFromDelta(
    LibraryApplicationFacade store,
    FilterQuery query,
    Iterable<VideoItem> changedVideos,
  ) {
    final watch = Stopwatch()..start();
    _filterStateSource.configure(
      engine: TagQueryService(
        videos: store.videos.values,
        tagContext: store.tagQueryContext,
      ),
      totalCount: store.videos.length,
      sourceKey: _libraryDataRevision,
      sortKey: (_sortMode, _sortDirection),
      sortVideos: (videos) => sortedLibraryVideos(
        videos,
        sortMode: _sortMode,
        sortDirection: _sortDirection,
      ),
    );
    final state = _filterStateSource.applyVideoDelta(query, changedVideos);
    watch.stop();
    _activeScanUiDiagnostics?.recordStage(
      'ui.filter_delta_apply',
      watch.elapsed,
      itemCount: changedVideos.length,
    );
    return state;
  }

  FilterState _buildImmediateFilterState(LibraryApplicationFacade store) {
    return FilterState(
      query: _currentFilterQuery(),
      filteredVideos: sortedLibraryVideos(
        store.videos.values,
        sortMode: _sortMode,
        sortDirection: _sortDirection,
      ),
      resultCount: store.videos.length,
      totalCount: store.videos.length,
    );
  }

  Map<String, int> _fallbackResultCounts(LibraryApplicationFacade store) {
    return {
      for (final tag in store.allTagItems) tag.id: tag.usageCount,
    };
  }

  /**
   * 构建本地媒体库当前路径的直接子项。
   *
   * 文件夹从磁盘目录读取；视频只取已入库项目，确保播放、缩略图、收藏和更多操作继续复用现有 VideoItem 管线。
   */
  Future<List<LocalLibraryEntry>> _localLibraryEntries(
    LibraryApplicationFacade store,
  ) async {
    final currentPath = _localLibraryPath;
    if (currentPath == null || currentPath.isEmpty) {
      return const <LocalLibraryEntry>[];
    }
    if (!await _fileSystem.directoryExists(currentPath)) {
      return const <LocalLibraryEntry>[];
    }
    final folders = <LocalLibraryEntry>[];
    final videos = <VideoItem>[];
    final children = await _fileSystem.listFiles(
      currentPath,
      recursive: false,
    );
    children.sort((a, b) {
      final aIsDirectory = a.isDirectory;
      final bIsDirectory = b.isDirectory;
      if (aIsDirectory != bIsDirectory) {
        return aIsDirectory ? -1 : 1;
      }
      return p.basename(a.path).compareTo(p.basename(b.path));
    });
    for (final child in children) {
      if (child.isDirectory) {
        folders.add(LocalLibraryEntry.folder(child.path));
        continue;
      }
      if (TagRules.isVideoPath(child.path)) {
        final video = store.videos[TagRules.pathKey(child.path)];
        if (video != null) {
          videos.add(video);
        }
      }
    }
    return [
      ...folders,
      for (final video in sortedLibraryVideos(
        videos,
        sortMode: _sortMode,
        sortDirection: _sortDirection,
      ))
        LocalLibraryEntry.video(video),
    ];
  }

  /** 在现有 setState 中退出主媒体多选并清空临时选择。 */
  void _clearLibrarySelectionState() {
    _librarySelectionMode = false;
    _selectedLibraryVideoIds.clear();
  }

  /** 进入多选模式；首次进入不预选任何视频。 */
  void _enterLibrarySelectionMode() {
    setState(() {
      _librarySelectionMode = true;
      _selectedLibraryVideoIds.clear();
    });
  }

  /** 退出多选模式并恢复普通筛选工具栏和卡片播放语义。 */
  void _cancelLibrarySelectionMode() {
    setState(_clearLibrarySelectionState);
  }

  /** 切换单个视频的多选状态，卡片点击和圆形复选框共用该入口。 */
  void _toggleLibraryVideoSelection(VideoItem item) {
    setState(() {
      if (!_selectedLibraryVideoIds.remove(item.videoId)) {
        _selectedLibraryVideoIds.add(item.videoId);
      }
    });
  }

  /**
   * 对完整当前筛选结果执行全选或取消全选。
   *
   * 这里只更新稳定 id 集合；Sliver 仍只重建视口附近卡片，不会一次创建全部视频 Widget。
   */
  void _toggleAllLibraryVideoSelection(List<VideoItem> videos) {
    setState(() {
      if (videos.isNotEmpty &&
          _selectedLibraryVideoIds.length == videos.length) {
        _selectedLibraryVideoIds.clear();
        return;
      }
      _selectedLibraryVideoIds
        ..clear()
        ..addAll(videos.map((item) => item.videoId));
    });
  }

  /**
   * 修改筛选条件并刷新当前可见结果。
   *
   * 高频交互（标签点击、搜索输入）默认只刷新视频列表，标签计数这类重任务
   * 只在库结构变化、扫描、标签管理返回等低频路径显式开启，避免大媒体库下点击卡顿。
   */
  void _mutateFilters(
    VoidCallback mutation, {
    bool refreshCounts = false,
    bool collapseTagPanel = false,
  }) {
    setState(() {
      _clearLibrarySelectionState();
      _resultMode = _LibraryResultMode.library;
      mutation();
      _isTagDiscoveryPanelOpen = libraryTagDiscoveryPanelOpenAfterMutation(
        currentOpen: _isTagDiscoveryPanelOpen,
        collapseAfterMutation: collapseTagPanel,
      );
    });
    _scheduleFilterRefresh(refreshCounts: refreshCounts);
  }

  /**
   * 应用排序字段或方向变更。
   *
   * 排序只改变当前结果的展示顺序，不改变筛选条件、标签数量或收藏状态；
   * 这里直接重排内存中的 `FilterState`，避免切换排序时触发完整过滤和 resultCounts 统计。
   */
  void _applySortChange({
    SortMode? sortMode,
    SortDirection? sortDirection,
  }) {
    late final LibrarySortPreferences preferences;
    setState(() {
      _sortMode = sortMode ?? _sortMode;
      _sortDirection = sortDirection ?? _sortDirection;
      preferences = LibrarySortPreferences(
        mode: _sortMode,
        direction: _sortDirection,
        denseResultGrid: _denseResultGrid,
      );
      if (_resultMode != _LibraryResultMode.library || _filterState == null) {
        return;
      }
      final currentState = _filterState!;
      _filterState = FilterState(
        query: currentState.query,
        filteredVideos: sortedLibraryVideos(
          currentState.filteredVideos,
          sortMode: _sortMode,
          sortDirection: _sortDirection,
        ),
        resultCount: currentState.resultCount,
        totalCount: currentState.totalCount,
      );
    });
    unawaited(widget.applicationService.saveSortPreferences(preferences));
  }

  /**
   * 切换网格/列表并复用展示偏好文件持久化，不触发过滤、计数或缩略图全量刷新。
   */
  void _setResultView(bool dense) {
    if (_denseResultGrid == dense) {
      return;
    }
    setState(() => _denseResultGrid = dense);
    unawaited(widget.applicationService.saveSortPreferences(
      LibrarySortPreferences(
        mode: _sortMode,
        direction: _sortDirection,
        denseResultGrid: dense,
      ),
    ));
  }

  /**
   * 回到媒体库全量视图。
   *
   * 侧栏“媒体库”应像重置入口：清空搜索、一级/二级/分组/排除/收藏筛选，并展示全量视频，
   * 避免用户从最近播放或某个标签视图返回时仍被旧条件限制。
   */
  void _showAllLibraryVideos() {
    final store = _store;
    setState(() {
      _clearLibrarySelectionState();
      _resultMode = _LibraryResultMode.library;
      _localLibraryPath = null;
      _localLibraryBackStack.clear();
      _selectedRecentPathKeys.clear();
      _clearSearchSilently();
      _selectedTags.clear();
      _selectedChildTags.clear();
      _selectedGroupTagIds.clear();
      _excludedTagIds.clear();
      _showFavoritesOnly = false;
      if (store != null) {
        _filterState = _buildImmediateFilterState(store);
      }
    });
    _scheduleFilterRefresh();
  }

  /**
   * 切换到最近播放结果视图。
   *
   * 最近播放是主结果区的一种数据源，不再用弹窗承载；切换时清空筛选条件，让用户看到的列表只由播放记录决定。
   */
  void _showRecentPlaybackVideos() {
    setState(() {
      _clearLibrarySelectionState();
      _resultMode = _LibraryResultMode.recent;
      _localLibraryPath = null;
      _localLibraryBackStack.clear();
      _selectedRecentPathKeys.clear();
      _clearSearchSilently();
      _selectedTags.clear();
      _selectedChildTags.clear();
      _selectedGroupTagIds.clear();
      _excludedTagIds.clear();
      _showFavoritesOnly = false;
    });
  }

  /**
   * 切换到收藏结果视图。
   *
   * 该入口直接从当前内存视频集合筛选收藏项，同时保留 favoriteOnly 状态；
   * 后续再点击右侧标签时会切回普通媒体库筛选，但收藏条件仍会作为 AND 条件叠加。
   */
  void _showFavoriteVideos() {
    setState(() {
      _clearLibrarySelectionState();
      _resultMode = _LibraryResultMode.favorites;
      _localLibraryPath = null;
      _localLibraryBackStack.clear();
      _selectedRecentPathKeys.clear();
      _clearSearchSilently();
      _selectedTags.clear();
      _selectedChildTags.clear();
      _selectedGroupTagIds.clear();
      _excludedTagIds.clear();
      _showFavoritesOnly = true;
    });
  }

  /**
   * 打开本地媒体库路径。
   *
   * 只切换当前浏览路径和结果模式；实际文件扫描仍由添加目录/重新扫描负责。
   */
  void _showLocalLibraryPath(String rootPath) {
    setState(() {
      _clearLibrarySelectionState();
      _resultMode = _LibraryResultMode.local;
      _localLibraryPath = TagRules.normalizeRootPath(rootPath);
      _localLibraryBackStack.clear();
      _selectedRecentPathKeys.clear();
      _clearSearchSilently();
      _selectedTags.clear();
      _selectedChildTags.clear();
      _selectedGroupTagIds.clear();
      _excludedTagIds.clear();
      _showFavoritesOnly = false;
    });
  }

  /**
   * 从当前本地媒体库路径进入子文件夹。
   *
   * 该操作只改变 UI 浏览路径，不触发扫描，也不改变 root 配置或视频索引。
   */
  void _openLocalLibraryFolder(String folderPath) {
    final currentPath = _localLibraryPath;
    setState(() {
      if (currentPath != null && currentPath.isNotEmpty) {
        _localLibraryBackStack.add(currentPath);
      }
      _resultMode = _LibraryResultMode.local;
      _localLibraryPath = TagRules.normalizeRootPath(folderPath);
    });
  }

  /**
   * 回到本地媒体库上一个浏览路径。
   *
   * 返回按钮和鼠标侧键共用该方法，保证两种入口的历史栈行为一致。
   */
  void _goBackLocalLibraryPath() {
    if (_localLibraryBackStack.isEmpty) {
      return;
    }
    setState(() {
      _resultMode = _LibraryResultMode.local;
      _localLibraryPath = _localLibraryBackStack.removeLast();
    });
  }

  /**
   * 从侧栏解除一个 root 的媒体库管理状态。
   *
   * 本地文件、稳定视频身份、用户数据和可复用缓存保持不动；仍被其它重叠 root 覆盖的
   * 视频继续 active，仅不再受任何 root 覆盖的条目进入 detached 归档。
   */
  Future<void> _removeLocalLibraryRoot(String root) async {
    final store = _store;
    if (store == null) {
      return;
    }
    final confirmed = await _confirmRemoveRoot(root);
    if (confirmed != true || !mounted) {
      return;
    }
    await _removeLibraryRootData(root);
  }

  /**
   * 提交 root 解除管理并把 active 结果差量应用到当前媒体库。
   *
   * 系统确认弹窗和隔离压测共用此方法；Store 只切换 detached 状态，绝不删除 root
   * 下的本地媒体文件、稳定身份或用户维护数据。
   */
  Future<int> _removeLibraryRootData(String root) async {
    final store = _store;
    if (store == null) {
      return 0;
    }
    // root 移除会使大批 probe candidate 失效。先推进 generation 并丢弃排队回调，
    // 避免删除事务期间旧 FFmpeg 结果重新 upsert 已移除的视频。
    _libraryMediaDetailsService?.dispose();
    _libraryMediaDetailsService = null;
    final removedVideos = await store.removeRoot(root);
    if (!mounted) {
      return removedVideos.length;
    }
    setState(() {
      // 解除管理改变了 active 数据源；必须提升 revision，禁止 FilterStateSource 复用
      // 操作前的 11k 列表缓存，否则 SQLite 已完成但 UI 总量会长期停留在旧值。
      _libraryDataRevision += 1;
      _invalidateDerivedCaches();
      if (_localLibraryPath != null &&
          TagRules.pathKey(_localLibraryPath!) == TagRules.pathKey(root)) {
        _resultMode = _LibraryResultMode.library;
        _localLibraryPath = null;
        _localLibraryBackStack.clear();
      }
      _stableTagCounts = store.resultCounts(const FilterQuery());
    });
    _scheduleFilterRefresh(refreshCounts: true);
    // 缩略图与媒体详情均可在 root 重新加入时复用，解除管理不能把缓存当作垃圾清除。
    return removedVideos.length;
  }

  /**
   * 清理最近播放记录。
   *
   * 该动作清空继续观看状态，但不删除视频、收藏或标签。
   */
  Future<void> _clearRecentPlayback({required bool selectedOnly}) async {
    final store = _store;
    if (store == null) {
      return;
    }
    final targets = recentPlaybackClearTargets(
      store.videos.values,
      selectedPathKeys: _selectedRecentPathKeys,
      selectedOnly: selectedOnly,
    );
    if (targets.isEmpty) {
      return;
    }

    if (!selectedOnly) {
      final confirmed = await showClearAllRecentPlaybackConfirmation(
        context,
        count: targets.length,
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    await _clearRecentPlaybackTargets(targets);
  }

  /**
   * 批量清理播放状态并提供 10 秒精确 Undo。
   *
   * SQLite 使用既有批量视频行写入，避免逐条 await 放大交互等待；失败时先恢复内存
   * 快照，保证界面不会宣称已清理但数据库仍保留旧状态。
   */
  Future<void> _clearRecentPlaybackTargets(List<VideoItem> targets) async {
    final store = _store;
    if (store == null || targets.isEmpty) {
      return;
    }
    final snapshots = targets
        .map(ContinueWatchingClearSnapshot.capture)
        .toList(growable: false);
    for (final item in targets) {
      _resetContinueWatchingState(item);
    }
    try {
      await store.upsertPlaybackStates(targets);
    } catch (_) {
      for (final snapshot in snapshots) {
        snapshot.restore();
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('清除观看进度失败，原记录已保留')),
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(_selectedRecentPathKeys.clear);
    _markLibraryDataChanged();
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text('已清除 ${targets.length} 条观看进度，视频文件未删除'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => unawaited(_undoRecentPlaybackClear(snapshots)),
          ),
        ),
      );
  }

  /**
   * 清理单个最近播放记录。
   *
   * 单条删除不能依赖“先选中再批量删除”的状态刷新顺序，否则真实鼠标快速点击时会出现命中但未删除。
   */
  Future<void> _clearOneRecentPlayback(VideoItem item) async {
    await _clearRecentPlaybackTargets(<VideoItem>[item]);
  }

  /**
   * 恢复仍处于本次清理空状态的记录；已产生新播放进度的条目保持新值。
   */
  Future<void> _undoRecentPlaybackClear(
    List<ContinueWatchingClearSnapshot> snapshots,
  ) async {
    final store = _store;
    if (store == null) {
      return;
    }
    final restorable = snapshots
        .where((snapshot) => snapshot.canRestoreWithoutOverwritingNewPlayback)
        .toList(growable: false);
    if (restorable.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('记录已产生新的播放进度，未覆盖新状态')),
        );
      }
      return;
    }
    for (final snapshot in restorable) {
      snapshot.restore();
    }
    try {
      await store.upsertPlaybackStates(
        restorable.map((snapshot) => snapshot.item),
      );
    } catch (_) {
      // 数据库仍保持已清理状态时，内存必须同步回到相同状态，避免重启前后显示分裂。
      for (final snapshot in restorable) {
        _resetContinueWatchingState(snapshot.item);
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('撤销失败，请重试播放以重新生成进度')),
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    _markLibraryDataChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已恢复 ${restorable.length} 条观看进度')),
    );
  }

  /** 清空单条播放进度；保留媒体总时长、videoId 和其它用户维护数据。 */
  void _resetContinueWatchingState(VideoItem item) {
    item
      ..lastPlayedAt = null
      ..playbackPosition = Duration.zero
      ..playbackCompleted = false
      ..playbackPositionUpdatedAt = null;
  }

  /**
   * 切换最近播放清理选择状态。
   */
  void _toggleRecentSelection(VideoItem item) {
    final key = TagRules.pathKey(item.path);
    setState(() {
      if (!_selectedRecentPathKeys.remove(key)) {
        _selectedRecentPathKeys.add(key);
      }
    });
  }

  void _markLibraryDataChanged() {
    _libraryDataRevision += 1;
    _invalidateDerivedCaches();
    final store = _store;
    if (store != null) {
      // 数据变化后先回退到持久化 usageCount，精确计数由延后刷新任务更新。
      _stableTagCounts = const <String, int>{};
    }
    _scheduleFilterRefresh(refreshCounts: true);
  }

  /**
   * 把扫描层输出的不可变差量应用到当前界面。
   *
   * 主结果列表只重新评估变化的 stable `videoId`；路径或 folder 标签
   * 可能影响本地目录与侧边栏，因此只定向失效这两类派生缓存。
   */
  void _applyLibraryScanDelta(LibraryScanCommitResult result) {
    if (result.changedVideos.isEmpty) {
      // 零差量不得提升 revision 或失效 folder 侧边栏，否则每次点击重新扫描
      // 都会无意义地重算整个媒体库。
      return;
    }
    _libraryDataRevision += 1;
    _tagGroupsCacheKey = null;
    _localEntryCacheKey = null;
    _localEntryCacheByKey.clear();
    if (result.changedVideos.any((item) => item.lastPlayedAt != null)) {
      _recentVideoCacheKey = null;
    }
    if (result.changedVideos.any((item) => item.isFavorite)) {
      _favoriteVideoCacheKey = null;
    }
    _stableTagCounts = const <String, int>{};
    _scheduleFilterRefresh(
      refreshCounts: true,
      changedVideos: result.changedVideos,
    );
  }

  void _invalidateDerivedCaches() {
    _tagGroupsCacheKey = null;
    _localEntryCacheKey = null;
    _localEntryCacheByKey.clear();
    _recentVideoCacheKey = null;
    _favoriteVideoCacheKey = null;
  }

  /**
   * 播放器返回后只更新播放时间相关的可见状态。
   *
   * `lastPlayedAt` 不会改变标签、收藏、路径或筛选命中集合；因此不能复用
   * `_markLibraryDataChanged` 的全库标签计数与完整筛选刷新路径，否则从播放器
   * 返回主界面会在大媒体库上产生明显卡顿。
   */
  void _markPlaybackTimestampChanged(VideoItem item) {
    _playbackDataRevision += 1;
    if (_resultMode == _LibraryResultMode.library) {
      // 主媒体库默认排序使用添加时间，播放时间更新不再改变当前结果顺序。
      return;
    }

    // 最近播放、本地收藏和本地路径浏览只依赖当前内存对象重建轻量列表。
    if (_resultMode == _LibraryResultMode.recent ||
        (_resultMode == _LibraryResultMode.favorites && item.isFavorite) ||
        _resultMode == _LibraryResultMode.local) {
      setState(() {});
    }
  }

  List<VideoItem> _sortedRecentVideos(LibraryApplicationFacade store) {
    final key = (
      'recent',
      _libraryDataRevision,
      _playbackDataRevision,
      _sortMode,
      _sortDirection,
    );
    if (_recentVideoCacheKey == key) {
      return _recentVideoCache;
    }
    _recentVideoCacheKey = key;
    _recentVideoCache = sortedLibraryVideos(
      store.videos.values.where(videoIsContinueWatching),
      sortMode: _sortMode,
      sortDirection: _sortDirection,
    );
    return _recentVideoCache;
  }

  List<VideoItem> _sortedFavoriteVideos(LibraryApplicationFacade store) {
    final key = (
      'favorites',
      _libraryDataRevision,
      _sortMode,
      _sortDirection,
    );
    if (_favoriteVideoCacheKey == key) {
      return _favoriteVideoCache;
    }
    _favoriteVideoCacheKey = key;
    _favoriteVideoCache = sortedLibraryVideos(
      store.videos.values.where((item) => item.isFavorite),
      sortMode: _sortMode,
      sortDirection: _sortDirection,
    );
    return _favoriteVideoCache;
  }

  List<LocalLibraryEntry> _cachedLocalLibraryEntries(
    LibraryApplicationFacade store,
  ) {
    final key = (
      'local',
      _libraryDataRevision,
      _localLibraryPath,
      _sortMode,
      _sortDirection,
    );
    if (_localEntryCacheKey == key) {
      return _localEntryCache;
    }
    final cached = _localEntryCacheByKey[key];
    if (cached != null) {
      _localEntryCacheKey = key;
      _localEntryCache = cached;
      return cached;
    }
    if (_localEntryLoads.add(key)) {
      // 目录枚举放到异步平台边界，build 只消费缓存，避免大目录阻塞 UI 线程。
      unawaited(() async {
        try {
          final entries = await _localLibraryEntries(store);
          _localEntryCacheByKey[key] = entries;
          while (_localEntryCacheByKey.length > 24) {
            _localEntryCacheByKey.remove(_localEntryCacheByKey.keys.first);
          }
          if (mounted &&
              _store == store &&
              _resultMode == _LibraryResultMode.local) {
            final currentKey = (
              'local',
              _libraryDataRevision,
              _localLibraryPath,
              _sortMode,
              _sortDirection,
            );
            if (currentKey == key) {
              setState(() {
                _localEntryCacheKey = key;
                _localEntryCache = entries;
              });
            }
          }
        } finally {
          _localEntryLoads.remove(key);
        }
      }());
    }
    return const <LocalLibraryEntry>[];
  }

  void _scheduleFilterRefresh({
    bool refreshCounts = false,
    Iterable<VideoItem>? changedVideos,
  }) {
    final store = _store;
    if (store == null) {
      return;
    }
    final revision = ++_filterRevision;
    if (!refreshCounts) {
      _countRefreshCoordinator.cancelPending();
    }
    final query = _currentFilterQuery();
    Future<void>.delayed(Duration.zero, () {
      if (!mounted || revision != _filterRevision || _store != store) {
        return;
      }
      final nextState = changedVideos == null
          ? _computeFilterState(store, query)
          : _computeFilterStateFromDelta(store, query, changedVideos);
      if (!mounted || revision != _filterRevision || _store != store) {
        return;
      }
      setState(() {
        _filterState = nextState;
        _isRefreshingVideos = false;
      });
      // 真正的可见窗口由虚拟列表滚动停止后驱动；固定取结果前 36 条会在深度滚动时
      // 抢占错误项目，因此这里不再猜测可见范围。
      if (!refreshCounts) {
        return;
      }
      _countRefreshCoordinator.schedule(
        query: query,
        compute: store.resultCounts,
        isStillCurrent: (_) =>
            mounted && revision == _filterRevision && _store == store,
        onComplete: (nextCounts) {
          setState(() {
            _visibleResultCounts = nextCounts;
            _isRefreshingCounts = false;
          });
        },
      );
    });
  }

  FilterQuery _currentFilterQuery() {
    final store = _store;
    final parentTag = _activeChildParentTag;
    final selectedChildTag = _activeChildTagName;
    return FilterQuery(
      keyword: _searchController.text,
      primaryTagId: parentTag,
      childTagId: parentTag == null ? null : selectedChildTag,
      folderRoots: parentTag == null
          ? const <String>[]
          : store?.roots ?? const <String>[],
      selectedGroupTagIds: {
        for (final entry in _selectedGroupTagIds.entries)
          if (entry.value.isNotEmpty &&
              entry.key != 'folder.primary' &&
              entry.key != 'folder.child')
            entry.key: {...entry.value},
      },
      excludeTagIds: {..._excludedTagIds},
      favoriteOnly: _showFavoritesOnly,
    );
  }

  List<TagGroup> _tagGroupsForSidebar(LibraryApplicationFacade store) {
    final cacheKey = (
      _libraryDataRevision,
      store.tagsById.length,
      _rootsSignature(store.roots),
    );
    if (_tagGroupsCacheKey == cacheKey) {
      return _tagGroupsCache;
    }
    final rebuildWatch = Stopwatch()..start();
    final folderGroups = folderTagGroupsFromLibraryPaths(
      videos: store.videos.values,
      roots: store.roots,
      templates: store.tagGroups,
    );
    final folderGroupById = {for (final group in folderGroups) group.id: group};
    final itemsByGroup = <String, List<TagItem>>{};
    for (final tag in store.allTagItems.where((tag) => !tag.isHidden)) {
      final groupId = tag.groupId ?? 'manual';
      if (groupId == 'folder.primary' || groupId == 'folder.child') {
        continue;
      }
      (itemsByGroup[groupId] ??= <TagItem>[]).add(tag);
    }
    final groups = <TagGroup>[];
    final knownGroupIds = <String>{};
    for (final group in store.tagGroups) {
      knownGroupIds.add(group.id);
      final folderGroup = folderGroupById[group.id];
      if (folderGroup != null) {
        groups.add(folderGroup);
        continue;
      }
      final items = itemsByGroup[group.id] ?? const <TagItem>[];
      groups.add(_copyGroupWithItems(group, items));
    }
    for (final folderGroup in folderGroups) {
      if (!knownGroupIds.contains(folderGroup.id)) {
        groups.add(folderGroup);
        knownGroupIds.add(folderGroup.id);
      }
    }
    for (final entry in itemsByGroup.entries) {
      if (knownGroupIds.contains(entry.key)) {
        continue;
      }
      groups.add(
        TagGroup(
          id: entry.key,
          name: entry.key,
          displayName: entry.key,
          sortOrder: 999,
          items: _sortedTagItems(entry.value),
        ),
      );
    }
    groups.removeWhere((group) => group.items.isEmpty);
    groups.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) {
        return byOrder;
      }
      return _groupLabel(a).compareTo(_groupLabel(b));
    });
    _tagGroupsCacheKey = cacheKey;
    _tagGroupsCache = List<TagGroup>.unmodifiable(groups);
    rebuildWatch.stop();
    _activeScanUiDiagnostics?.recordStage(
      'ui.folder_sidebar_rebuild',
      rebuildWatch.elapsed,
      itemCount: store.videos.length,
    );
    return _tagGroupsCache;
  }

  String _rootsSignature(Iterable<String> roots) {
    final normalized = [
      for (final root in roots) TagRules.pathKey(root),
    ]..sort();
    return normalized.join('|');
  }

  TagGroup _copyGroupWithItems(TagGroup group, Iterable<TagItem> items) {
    return TagGroup(
      id: group.id,
      name: group.name,
      displayName: group.displayName,
      sortOrder: group.sortOrder,
      allowMultiSelect: group.allowMultiSelect,
      defaultLogic: group.defaultLogic,
      items: _sortedTagItems(items),
      excludedItems: group.excludedItems,
    );
  }

  List<TagItem> _sortedTagItems(Iterable<TagItem> items) {
    final sorted = items.toList();
    sorted.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) {
        return byOrder;
      }
      final byUsage = b.usageCount.compareTo(a.usageCount);
      if (byUsage != 0) {
        return byUsage;
      }
      return _tagLabel(a).compareTo(_tagLabel(b));
    });
    return sorted;
  }

  String _groupLabel(TagGroup group) => group.displayName ?? group.name;

  String _tagLabel(TagItem tag) => tag.displayName ?? tag.name;

  bool get _hasActiveFilters => !_currentFilterQuery().isEmpty;

  void _toggleGroupTag(TagItem tag) {
    final groupId = tag.groupId ?? 'manual';
    if (groupId == 'folder.child') {
      _toggleFolderChildTag(tag);
      return;
    }
    final selected = _selectedGroupTagIds[groupId] ?? <String>{};
    _mutateFilters(() {
      _removeEquivalentLegacySelection(tag);
      _excludedTagIds.remove(tag.id);
      if (selected.contains(tag.id)) {
        selected.remove(tag.id);
      } else {
        if (groupId == 'folder.primary' || groupId == 'folder.child') {
          selected.clear();
        }
        selected.add(tag.id);
      }
      if (groupId == 'folder.primary') {
        _selectedChildTags.clear();
        _selectedGroupTagIds.remove('folder.child');
      }
      if (selected.isEmpty) {
        _selectedGroupTagIds.remove(groupId);
      } else {
        _selectedGroupTagIds[groupId] = selected;
      }
    }, collapseTagPanel: true);
  }

  void _toggleFolderChildTag(TagItem child) {
    final store = _store;
    if (store == null) {
      return;
    }
    final primary = _folderPrimaryForChild(store, child);
    if (primary == null) {
      return;
    }
    _mutateFilters(() {
      _removeEquivalentLegacySelection(primary);
      _removeEquivalentLegacySelection(child);
      _excludedTagIds
        ..remove(primary.id)
        ..remove(child.id);
      _selectedTags.clear();
      _selectedChildTags.clear();
      _selectedGroupTagIds['folder.primary'] = <String>{primary.id};
      final selectedChildIds =
          _selectedGroupTagIds['folder.child'] ?? const <String>{};
      if (selectedChildIds.length == 1 && selectedChildIds.contains(child.id)) {
        _selectedGroupTagIds.remove('folder.child');
      } else {
        _selectedGroupTagIds['folder.child'] = <String>{child.id};
      }
    }, collapseTagPanel: true);
  }

  TagItem? _folderPrimaryForChild(
    LibraryApplicationFacade store,
    TagItem child,
  ) {
    final parent = child.parentId?.trim();
    if (parent == null || parent.isEmpty) {
      return null;
    }
    for (final group in _tagGroupsForSidebar(store)) {
      if (group.id != 'folder.primary') {
        continue;
      }
      for (final primary in group.items) {
        if (primary.id == parent || TagRules.sameTag(primary.name, parent)) {
          return primary;
        }
      }
    }
    return null;
  }

  void _selectFolderPrimaryChild(TagItem primary, TagItem? child) {
    _mutateFilters(() {
      _removeEquivalentLegacySelection(primary);
      if (child != null) {
        _removeEquivalentLegacySelection(child);
      }
      _excludedTagIds
        ..remove(primary.id)
        ..remove(child?.id);
      _selectedTags.clear();
      _selectedChildTags.clear();
      _selectedGroupTagIds['folder.primary'] = <String>{primary.id};
      if (child == null) {
        _selectedGroupTagIds.remove('folder.child');
        return;
      }
      final selectedChildIds =
          _selectedGroupTagIds['folder.child'] ?? const <String>{};
      if (selectedChildIds.length == 1 && selectedChildIds.contains(child.id)) {
        _selectedGroupTagIds.remove('folder.child');
      } else {
        _selectedGroupTagIds['folder.child'] = <String>{child.id};
      }
    }, collapseTagPanel: true);
  }

  void _toggleExcludedTag(TagItem tag) {
    _mutateFilters(() {
      for (final selected in _selectedGroupTagIds.values) {
        selected.remove(tag.id);
      }
      _selectedGroupTagIds.removeWhere((_, selected) => selected.isEmpty);
      if (!_excludedTagIds.remove(tag.id)) {
        _excludedTagIds.add(tag.id);
      }
    }, collapseTagPanel: true);
  }

  void _removeGroupTag(TagItem tag) {
    final groupId = tag.groupId ?? 'manual';
    _mutateFilters(() {
      _selectedGroupTagIds[groupId]?.remove(tag.id);
      _selectedGroupTagIds.removeWhere((_, selected) => selected.isEmpty);
    });
  }

  void _removeExcludedTag(TagItem tag) {
    _mutateFilters(() => _excludedTagIds.remove(tag.id));
  }

  void _clearAllFilters() {
    _mutateFilters(() {
      _clearSearchSilently();
      _selectedTags.clear();
      _selectedChildTags.clear();
      _selectedGroupTagIds.clear();
      _excludedTagIds.clear();
      _showFavoritesOnly = false;
    });
  }

  void _removeEquivalentLegacySelection(TagItem tag) {
    if (tag.parentId == null) {
      _selectedTags
          .removeWhere((selected) => TagRules.sameTag(selected, tag.name));
      if (_selectedTags.isEmpty) {
        _selectedChildTags.clear();
      }
      return;
    }
    if (_selectedTags
        .any((selected) => TagRules.sameTag(selected, tag.parentId!))) {
      _selectedChildTags
          .removeWhere((selected) => TagRules.sameTag(selected, tag.name));
    }
  }

  void _removeEquivalentGroupSelection({
    required String tagName,
    String? parentTag,
  }) {
    final store = _store;
    if (store == null) {
      return;
    }
    final removedIds = <String>{};
    for (final tag in store.allTagItems) {
      if (!TagRules.sameTag(tag.name, tagName)) {
        continue;
      }
      if (parentTag == null) {
        if (tag.parentId != null) {
          continue;
        }
      } else if (tag.parentId == null ||
          !TagRules.sameTag(tag.parentId!, parentTag)) {
        continue;
      }
      removedIds.add(tag.id);
    }
    if (removedIds.isEmpty) {
      return;
    }
    for (final selected in _selectedGroupTagIds.values) {
      selected.removeAll(removedIds);
    }
    _selectedGroupTagIds.removeWhere((_, selected) => selected.isEmpty);
    _excludedTagIds.removeAll(removedIds);
  }

  // ignore: unused_element
  void _showSaveSmartListTodo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '\u4fdd\u5b58\u5f53\u524d\u7b5b\u9009 / Smart List \u5c06\u5728\u540e\u7eed\u9636\u6bb5\u63a5\u5165\u6301\u4e45\u5316\u3002',
        ),
      ),
    );
  }

  // ignore: unused_element
  void _showSmartListDraftDialog() {
    final store = _store;
    if (store == null) {
      return;
    }
    final filterState = _filterState ?? _buildImmediateFilterState(store);
    final querySummary = _filterSummary(
      store: store,
      resultCount: filterState.resultCount,
      totalCount: filterState.totalCount,
    );
    final queryExpression = _filterExpression(
      store: store,
      resultCount: filterState.resultCount,
      totalCount: filterState.totalCount,
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SmartListDraftDialog(
        suggestedName: querySummary,
        querySummary: querySummary,
        queryExpression: queryExpression,
        resultCount: filterState.resultCount,
        totalCount: filterState.totalCount,
        onConfirmDraft: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Smart List \u6301\u4e45\u5316\u5c06\u5728\u540e\u7eed\u63a5\u5165\u3002',
              ),
            ),
          );
        },
      ),
    );
  }

  List<TagItem> _selectedGroupTagItems(LibraryApplicationFacade store) {
    final selectedIds =
        _selectedGroupTagIds.values.expand((ids) => ids).toSet();
    final folderTagsById = {
      for (final group in _tagGroupsForSidebar(store))
        for (final tag in group.items) tag.id: tag,
    };
    return [
      for (final id in selectedIds)
        if (folderTagsById[id] != null)
          folderTagsById[id]!
        else if (store.tagsById[id] != null)
          store.tagsById[id]!,
    ]..sort((a, b) => _tagLabel(a).compareTo(_tagLabel(b)));
  }

  List<TagItem> _excludedTagItems(LibraryApplicationFacade store) {
    return [
      for (final id in _excludedTagIds)
        if (store.tagsById[id] != null) store.tagsById[id]!,
    ]..sort((a, b) => _tagLabel(a).compareTo(_tagLabel(b)));
  }

  void _toggleSingleSelection(Set<String> target, String tag) {
    final wasSelected = target.contains(tag);
    target.clear();
    if (!wasSelected) {
      target.add(tag);
    }
  }

  String? get _activeChildParentTag {
    if (_selectedTags.length == 1) {
      return _selectedTags.first;
    }
    final store = _store;
    final selectedFolderIds =
        _selectedGroupTagIds['folder.primary'] ?? const <String>{};
    if (store == null || selectedFolderIds.length != 1) {
      return null;
    }
    return _folderDiscoveryTagById(store, selectedFolderIds.first)?.name ??
        store.tagQueryContext.findTag(selectedFolderIds.first)?.name;
  }

  String? get _activeChildTagName {
    if (_selectedChildTags.length == 1) {
      return _selectedChildTags.first;
    }
    final store = _store;
    final selectedChildIds =
        _selectedGroupTagIds['folder.child'] ?? const <String>{};
    if (store == null || selectedChildIds.length != 1) {
      return null;
    }
    return _folderDiscoveryTagById(store, selectedChildIds.first)?.name ??
        store.tagQueryContext.findTag(selectedChildIds.first)?.name;
  }

  /**
   * 从真实路径派生的 folder 标签候选中按 id 查找标签。
   *
   * 该查找用于把 UI 选中态转换回 `primaryTagId/childTagId`，避免历史 SQLite tag id
   * 与当前文件树 root 不一致时影响筛选结果。
   */
  TagItem? _folderDiscoveryTagById(
    LibraryApplicationFacade store,
    String tagId,
  ) {
    for (final group in _tagGroupsForSidebar(store)) {
      for (final tag in group.items) {
        if (tag.id == tagId) {
          return tag;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final thumbnailService = _thumbnailService;
    if (store == null || thumbnailService == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final filterState = _filterState ?? _buildImmediateFilterState(store);
    final filteredVideos = filterState.filteredVideos;
    final recentVideos = _sortedRecentVideos(store);
    final favoriteVideos = _sortedFavoriteVideos(store);
    final videos = switch (_resultMode) {
      _LibraryResultMode.recent => recentVideos,
      _LibraryResultMode.favorites => favoriteVideos,
      _LibraryResultMode.local => const <VideoItem>[],
      _LibraryResultMode.library => filteredVideos,
    };
    final localEntries = _resultMode == _LibraryResultMode.local
        ? _cachedLocalLibraryEntries(store)
        : const <LocalLibraryEntry>[];
    final localVideoCount =
        localEntries.where((entry) => !entry.isFolder).length;
    final displayResultCount = switch (_resultMode) {
      _LibraryResultMode.recent => videos.length,
      _LibraryResultMode.favorites => videos.length,
      _LibraryResultMode.local => localVideoCount,
      _LibraryResultMode.library => filterState.resultCount,
    };
    final resultCountLabel = _resultMode == _LibraryResultMode.local
        ? localLibraryEntrySummary(localEntries)
        : null;
    final defaultResultLabel = switch (_resultMode) {
      _LibraryResultMode.recent => '继续观看',
      _LibraryResultMode.favorites => '\u672c\u5730\u6536\u85cf',
      _LibraryResultMode.local => '\u672c\u5730\u5a92\u4f53\u5e93',
      _LibraryResultMode.library => '\u5168\u90e8\u89c6\u9891',
    };
    final tags = store.allTags.toList()..sort();
    final tagGroups = _tagGroupsForSidebar(store);
    final resultCounts = _visibleResultCounts.isEmpty
        ? _fallbackResultCounts(store)
        : _visibleResultCounts;
    final pathDerivedTagCounts = {
      for (final group in tagGroups)
        if (group.id == 'folder.primary' || group.id == 'folder.child')
          for (final tag in group.items) tag.id: tag.usageCount,
    };
    final stableTagCounts = {
      ...(_stableTagCounts.isEmpty
          ? _fallbackResultCounts(store)
          : _stableTagCounts),
      ...pathDerivedTagCounts,
    };
    final selectedGroupTags = _selectedGroupTagItems(store);
    final excludedTags = _excludedTagItems(store);
    final supportsLibrarySelection =
        (_resultMode == _LibraryResultMode.library ||
                _resultMode == _LibraryResultMode.favorites) &&
            videos.isNotEmpty;
    final allLibraryVideosSelected =
        videos.isNotEmpty && _selectedLibraryVideoIds.length == videos.length;
    final childParentTag = _activeChildParentTag;
    final childTags = childParentTag == null
        ? <String>[]
        : TagRules.sortedChildTags(store.childTagsFor(childParentTag))
            .where((tag) =>
                !TagRules.sameTag(tag, TagRules.defaultAlbumTag) &&
                !TagRules.sameTag(tag, childParentTag))
            .toList();
    final childTagItemsByParent = childTagItemsByParentId(
      tagGroups.expand((group) => group.items),
      store.tagQueryContext,
    );
    final favoriteCount =
        store.videos.values.where((item) => item.isFavorite).length;
    final missingCount =
        store.videos.values.where((item) => item.isMissing).length;
    Widget buildSidebar({required bool dense, double? width}) {
      return LibrarySidebar(
        roots: store.roots,
        tags: tags,
        tagGroups: tagGroups,
        resultCounts: resultCounts,
        selectedLocalLibraryPath: _localLibraryPath,
        childParentTag: childParentTag,
        childTags: childTags,
        selectedChildTags: _selectedChildTags,
        selectedGroupTagIds: _selectedGroupTagIds,
        excludedTagIds: _excludedTagIds,
        favoriteCount: favoriteCount,
        missingCount: missingCount,
        favoriteVideosSelected:
            _resultMode == _LibraryResultMode.favorites || _showFavoritesOnly,
        recentPlaybackSelected: _resultMode == _LibraryResultMode.recent,
        localLibrarySelected: _resultMode == _LibraryResultMode.local,
        selectedTags: _selectedTags,
        isScanning: _isScanning,
        dense: dense,
        collapsed: _isMainSidebarCollapsed,
        width: width,
        onToggleCollapsed: () => setState(
          () => _isMainSidebarCollapsed = !_isMainSidebarCollapsed,
        ),
        onPickFolder: _pickFolder,
        onShowAllLibrary: _showAllLibraryVideos,
        onRescan: _rescan,
        onRemoveLocalLibraryRoot: _removeLocalLibraryRoot,
        onFavoritesToggle: _showFavoriteVideos,
        onOpenRecentPlayback: _showRecentPlaybackVideos,
        onOpenLocalLibraryRoot: _showLocalLibraryPath,
        onOpenDirectoryManager: _openDirectoryManager,
        onOpenMissingRelink: _openMissingRelink,
        onOpenTagManager: () => _openTagManager(videos),
        onOpenSettings: _openSettings,
        onChildTagToggle: (tag) {
          _mutateFilters(() {
            _removeEquivalentGroupSelection(
              tagName: tag,
              parentTag: _activeChildParentTag,
            );
            _toggleSingleSelection(_selectedChildTags, tag);
          }, collapseTagPanel: true);
        },
        onClearChildTags: () => _mutateFilters(_selectedChildTags.clear),
        onGroupTagToggle: _toggleGroupTag,
        onGroupTagExcludeToggle: _toggleExcludedTag,
      );
    }

    Widget buildFilterPanel({required bool dense, double? panelWidth}) {
      return TagDiscoveryZone(
        tagGroups: tagGroups,
        resultCounts: stableTagCounts,
        favoriteTags: store.favoriteTags,
        selectedTags: _selectedTags,
        selectedChildTags: _selectedChildTags,
        selectedGroupTagIds: _selectedGroupTagIds,
        excludedTagIds: _excludedTagIds,
        childParentTag: childParentTag,
        childTags: childTags,
        childTagItemsByParent: childTagItemsByParent,
        favoriteCount: favoriteCount,
        showFavoritesOnly: _showFavoritesOnly,
        dense: dense,
        panelWidth: panelWidth,
        onFavoritesToggle: () => _mutateFilters(
          () => _showFavoritesOnly = !_showFavoritesOnly,
          collapseTagPanel: true,
        ),
        onTagToggle: (tag) {
          _mutateFilters(() {
            _removeEquivalentGroupSelection(tagName: tag);
            _toggleSingleSelection(_selectedTags, tag);
            _selectedChildTags.clear();
          }, collapseTagPanel: true);
        },
        onChildTagToggle: (tag) {
          _mutateFilters(() {
            _removeEquivalentGroupSelection(
              tagName: tag,
              parentTag: _activeChildParentTag,
            );
            _toggleSingleSelection(_selectedChildTags, tag);
          }, collapseTagPanel: true);
        },
        onGroupTagToggle: _toggleGroupTag,
        onFolderPrimaryChildSelected: _selectFolderPrimaryChild,
        onGroupTagExcludeToggle: _toggleExcludedTag,
        onCollapse: dense
            ? null
            : () => setState(() => _isTagDiscoveryPanelOpen = false),
      );
    }

    Widget buildMain(
      LayoutSize layoutSize, {
      Widget? topBar,
      required double gridColumnReferenceWidth,
    }) {
      return Column(
        children: [
          if (topBar != null) topBar,
          Expanded(
            child: LibraryImportDropRegion(
              enabled:
                  _resultMode == _LibraryResultMode.library && !_isScanning,
              onDropPaths: (paths) => unawaited(_importLibraryPaths(paths)),
              child: RepaintBoundary(
                child: switch (_resultMode) {
                  _LibraryResultMode.local => LocalLibraryView(
                      currentPath: _localLibraryPath,
                      entries: localEntries,
                      thumbnailService: thumbnailService,
                      playbackSettings: _playbackSettings,
                      dense: _denseResultGrid,
                      canGoBack: _localLibraryBackStack.isNotEmpty,
                      onBack: _goBackLocalLibraryPath,
                      onOpenFolder: _openLocalLibraryFolder,
                      onOpenVideo: _openVideo,
                      onRevealLocation: _revealVideoLocation,
                      onToggleFavorite: _toggleFavorite,
                      onDelete: _requestDeleteVideo,
                    ),
                  _LibraryResultMode.recent => videos.isEmpty
                      ? EmptyState(
                          hasLibrary: store.videos.isNotEmpty,
                          message: '当前没有未完成的观看记录',
                        )
                      : RecentPlaybackView(
                          videos: videos,
                          selectedPathKeys: _selectedRecentPathKeys,
                          thumbnailService: thumbnailService,
                          playbackSettings: _playbackSettings,
                          dense: _denseResultGrid,
                          onOpen: _openVideo,
                          onRevealLocation: _revealVideoLocation,
                          onToggleFavorite: _toggleFavorite,
                          onDeleteVideo: _requestDeleteVideo,
                          onToggleSelected: _toggleRecentSelection,
                          onSelectAll: () => setState(() {
                            _selectedRecentPathKeys
                              ..clear()
                              ..addAll(videos
                                  .map((item) => TagRules.pathKey(item.path)));
                          }),
                          onClearSelection: () =>
                              setState(_selectedRecentPathKeys.clear),
                          onDeleteOne: _clearOneRecentPlayback,
                          onDeleteSelected: () =>
                              _clearRecentPlayback(selectedOnly: true),
                          onDeleteAll: () =>
                              _clearRecentPlayback(selectedOnly: false),
                        ),
                  _ => videos.isEmpty
                      ? EmptyState(
                          hasLibrary: store.videos.isNotEmpty,
                          message: _resultMode == _LibraryResultMode.favorites
                              ? '\u8fd8\u6ca1\u6709\u6536\u85cf\u89c6\u9891'
                              : null,
                          onAddFiles:
                              _resultMode == _LibraryResultMode.library &&
                                      store.videos.isEmpty
                                  ? _pickVideoFiles
                                  : null,
                        )
                      : VideoGrid(
                          videos: videos,
                          thumbnailService: thumbnailService,
                          playbackSettings: _playbackSettings,
                          dense: _denseResultGrid,
                          columnReferenceWidth: gridColumnReferenceWidth,
                          onVisible: _prioritizeVisibleLibraryItem,
                          onOpen: _openVideo,
                          onRevealLocation: _revealVideoLocation,
                          onToggleFavorite: _toggleFavorite,
                          onDelete: _requestDeleteVideo,
                          selectionMode: _librarySelectionMode,
                          selectedVideoIds: _selectedLibraryVideoIds,
                          onToggleSelected: _toggleLibraryVideoSelection,
                          scrollChromeEnabled:
                              layoutSize == LayoutSize.expanded,
                          onHeaderVisibilityChanged: (visible) {
                            if (_libraryHeaderVisible.value != visible) {
                              _libraryHeaderVisible.value = visible;
                            }
                          },
                        ),
                },
              ),
            ),
          ),
        ],
      );
    }

    Widget buildTopBar(LayoutSize layoutSize) {
      return ReferenceTopBar(
        controller: _searchController,
        videoCount: displayResultCount,
        resultCountLabel: resultCountLabel,
        keyword: _searchController.text,
        searchFocusNode: _searchFocusNode,
        selectedTags: _selectedTags.toList()..sort(),
        selectedChildTags: _selectedChildTags.toList()..sort(),
        selectedGroupTags: selectedGroupTags,
        excludedTags: excludedTags,
        defaultChipLabel: defaultResultLabel,
        showFavoritesOnly: _showFavoritesOnly,
        refreshing: _isRefreshingVideos || _isRefreshingCounts,
        progressLabel: _resultMode != _LibraryResultMode.library
            ? null
            : _isScanning
                ? _isCancellingScan
                    ? '正在取消扫描…'
                    : libraryScanProgressLabel(_scanProgress)
                : _mediaImportProgress == null
                    ? null
                    : libraryMediaImportProgressLabel(
                        _mediaImportProgress!,
                      ),
        progressValue: _resultMode != _LibraryResultMode.library
            ? null
            : _isScanning
                ? _scanProgress?.fraction
                : _mediaImportProgress?.fraction,
        progressPaused: _isScanning
            ? (_scanProgress?.isPaused ?? false)
            : (_mediaImportProgress?.isPaused ?? false),
        onToggleProgressPaused: _resultMode != _LibraryResultMode.library
            ? null
            : _isScanning
                ? (_scanProgress == null ? null : _toggleScanPaused)
                : _mediaImportProgress == null
                    ? null
                    : _toggleMediaImportPaused,
        onCancelProgress: _resultMode == _LibraryResultMode.library &&
                _isScanning &&
                !_isCancellingScan
            ? _cancelScan
            : null,
        sortMode: _sortMode,
        sortDirection: _sortDirection,
        layoutSize: layoutSize,
        hasActiveFilters: _hasActiveFilters,
        onSearchChanged: (_) => _handleSearchControllerChanged(),
        onSortChanged: _setSortMode,
        onSortDirectionToggle: _toggleSortDirection,
        denseResultGrid: _denseResultGrid,
        onResultViewChanged: _setResultView,
        onOpenTagManager: () => _openTagManager(videos),
        tagPanelOpen: _isTagDiscoveryPanelOpen,
        onToggleTagPanel: layoutSize == LayoutSize.expanded
            ? () => setState(
                  () => _isTagDiscoveryPanelOpen = !_isTagDiscoveryPanelOpen,
                )
            : null,
        onRemovePrimaryTag: (tag) => _mutateFilters(() {
          _selectedTags.remove(tag);
          _selectedChildTags.clear();
        }),
        onRemoveChildTag: (tag) =>
            _mutateFilters(() => _selectedChildTags.remove(tag)),
        onRemoveGroupTag: _removeGroupTag,
        onRemoveExcludedTag: _removeExcludedTag,
        onClearKeyword: () => _mutateFilters(_clearSearchSilently),
        onClearFavoritesOnly: () =>
            _mutateFilters(() => _showFavoritesOnly = false),
        onClearAll: _hasActiveFilters ? _clearAllFilters : null,
        selectionMode: _librarySelectionMode,
        selectedCount: _selectedLibraryVideoIds.length,
        allSelected: allLibraryVideosSelected,
        onEnterSelectionMode:
            supportsLibrarySelection ? _enterLibrarySelectionMode : null,
        onToggleSelectAll: _librarySelectionMode
            ? () => _toggleAllLibraryVideoSelection(videos)
            : null,
        onDeleteSelected:
            _librarySelectionMode && _selectedLibraryVideoIds.isNotEmpty
                ? () => _requestDeleteSelectedVideos(videos)
                : null,
        onCancelSelectionMode:
            _librarySelectionMode ? _cancelLibrarySelectionMode : null,
        onOpenFilters: () {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: librarySurface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            builder: (_) => FractionallySizedBox(
              heightFactor: 0.92,
              child: buildFilterPanel(dense: true),
            ),
          );
        },
      );
    }

    Widget buildExpandedContent(
      MainLibraryLayoutSlots layoutSlots, {
      required double gridColumnReferenceWidth,
    }) {
      // 收起后完全释放右侧空间；恢复入口已经提升到页面标题区，避免保留突兀的竖排窄条。
      const collapsedFilterWidth = 0.0;
      final accessibility = AppAccessibilityScope.of(context);
      final panelDuration =
          accessibility.motionDuration(libraryPanelMotionDuration);
      return Column(
        children: [
          LibraryScrollResponsiveHeader(
            key: LibrarySmokeKeys.scrollResponsiveHeader,
            visibleListenable: _libraryHeaderVisible,
            child: buildTopBar(LayoutSize.expanded),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: buildMain(
                    LayoutSize.expanded,
                    gridColumnReferenceWidth: gridColumnReferenceWidth,
                  ),
                ),
                AnimatedContainer(
                  duration: panelDuration,
                  curve: libraryPanelMotionCurve,
                  width: _isTagDiscoveryPanelOpen
                      ? layoutSlots.filterPanelWidth
                      : collapsedFilterWidth,
                  // 外框只承担稳定分隔；面板和折叠入口各自表达层级，避免出现双重阴影。
                  decoration: _isTagDiscoveryPanelOpen
                      ? BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: libraryBorder.withValues(alpha: 0.72),
                            ),
                          ),
                        )
                      : null,
                  child: ClipRect(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final childWidth = _isTagDiscoveryPanelOpen
                            ? layoutSlots.filterPanelWidth
                            : collapsedFilterWidth;
                        return AnimatedSwitcher(
                          duration: panelDuration,
                          switchInCurve: libraryPanelMotionCurve,
                          switchOutCurve: libraryPanelMotionCurve,
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                            alignment: Alignment.centerRight,
                            clipBehavior: Clip.hardEdge,
                            children: [
                              ...previousChildren,
                              if (currentChild != null) currentChild,
                            ],
                          ),
                          transitionBuilder: (child, animation) {
                            final enteringPanel =
                                child.key == const ValueKey<bool>(true);
                            return LibraryPanelContentTransition(
                              animation: animation,
                              horizontalOffset: enteringPanel ? 0.14 : 0.55,
                              alignment: Alignment.centerRight,
                              child: child,
                            );
                          },
                          child: OverflowBox(
                            key: ValueKey<bool>(_isTagDiscoveryPanelOpen),
                            alignment: Alignment.centerRight,
                            minWidth: childWidth,
                            maxWidth: childWidth,
                            minHeight: constraints.maxHeight,
                            maxHeight: constraints.maxHeight,
                            child: SizedBox(
                              width: childWidth,
                              height: constraints.maxHeight,
                              child: _isTagDiscoveryPanelOpen
                                  ? buildFilterPanel(
                                      dense: false,
                                      panelWidth: layoutSlots.filterPanelWidth,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final page = Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            const FocusLibrarySearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          FocusLibrarySearchIntent: CallbackAction<FocusLibrarySearchIntent>(
            onInvoke: (_) {
              _focusSearchField();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Theme(
            data: libraryWorkspaceTheme(Theme.of(context)),
            child: Scaffold(
              backgroundColor: libraryBackground,
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final layoutSize =
                      LayoutBreakpoints.fromWidth(constraints.maxWidth);
                  final showMainSidebar = layoutSize != LayoutSize.compact;
                  final expandedSlots =
                      mainLibraryLayoutSlotsForWidth(constraints.maxWidth);
                  // 列数使用默认侧栏占位后的窗口基准宽度。左右侧栏开合不会改变该值，
                  // 因此只会让结果区里的卡片缩放；只有窗口尺寸改变才可能跨越列数断点。
                  final gridColumnReferenceWidth = math
                      .max(
                        1.0,
                        switch (layoutSize) {
                          LayoutSize.compact => constraints.maxWidth,
                          LayoutSize.medium => constraints.maxWidth - 248,
                          LayoutSize.expanded =>
                            constraints.maxWidth - expandedSlots.sidebarWidth,
                        },
                      )
                      .toDouble();
                  return Row(
                    children: [
                      if (showMainSidebar)
                        buildSidebar(
                          dense: layoutSize != LayoutSize.expanded,
                          width: _isMainSidebarCollapsed
                              ? 76
                              : layoutSize == LayoutSize.expanded
                                  ? expandedSlots.sidebarWidth
                                  : null,
                        ),
                      Expanded(
                        child: layoutSize == LayoutSize.expanded
                            ? buildExpandedContent(
                                expandedSlots,
                                gridColumnReferenceWidth:
                                    gridColumnReferenceWidth,
                              )
                            : buildMain(
                                layoutSize,
                                topBar: buildTopBar(layoutSize),
                                gridColumnReferenceWidth:
                                    gridColumnReferenceWidth,
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
    );
    return ExcludeSemantics(
      excluding: libraryRouteShouldExcludeSemantics(
        playerRouteActive: _playerRouteActive,
      ),
      child: page,
    );
  }

  Future<void> _openSettings() async {
    final store = _store;
    final thumbnailService = _thumbnailService;
    if (store == null || thumbnailService == null) {
      return;
    }
    await Navigator.of(context).push(
      _smoothRoute<void>(
        CacheSettingsPage(
          store: store,
          thumbnailService: thumbnailService,
          playbackSettings: _playbackSettings,
          dataBackupSettings: _dataBackupSettings,
          onPlaybackSettingsChanged: (settings) async {
            await widget.applicationService.savePlaybackSettings(settings);
            if (mounted) {
              setState(() => _playbackSettings = settings);
            }
          },
          onDataBackupSettingsChanged: (settings) async {
            final previous = _dataBackupSettings;
            await store.setDataBackupEnabled(settings.enabled);
            try {
              await widget.applicationService.saveDataBackupSettings(settings);
            } catch (_) {
              // 设置文件失败时恢复运行态，避免界面、当前服务与下次启动值分叉。
              await store.setDataBackupEnabled(previous.enabled);
              rethrow;
            }
            if (mounted) {
              setState(() => _dataBackupSettings = settings);
            }
          },
          onRunDataBackupNow: store.runDataBackupNow,
          onCheckDataBackupIntegrity: store.checkDataBackupIntegrity,
          onExportDataBackup: () async {
            final now = DateTime.now();
            String two(int value) => value.toString().padLeft(2, '0');
            final suggestedName = 'LocalTagPlayer-视频数据备份-'
                '${now.year}${two(now.month)}${two(now.day)}-'
                '${two(now.hour)}${two(now.minute)}.json';
            final path = await _fileSystem.pickSavePath(
              suggestedName: suggestedName,
              dialogTitle: '导出视频依赖备份',
              allowedExtensions: const <String>['json'],
            );
            if (path == null) {
              return null;
            }
            final bytes = await store.createDataBackupExport();
            await _fileSystem.writeBytes(path, bytes, flush: true);
            return path;
          },
        ),
        backShortcutProvider: () =>
            _playbackSettings.shortcuts[PlayerShortcutAction.navigateBack]!,
      ),
    );
    if (mounted) {
      _markLibraryDataChanged();
    }
  }

  Future<void> _openTagManager(List<VideoItem> currentResults) async {
    final store = _store;
    if (store == null) {
      return;
    }
    await Navigator.of(context).push(
      _smoothRoute<void>(
        TagManagerPage(
          store: store,
          currentResults: List<VideoItem>.of(currentResults),
        ),
        backShortcutProvider: () =>
            _playbackSettings.shortcuts[PlayerShortcutAction.navigateBack]!,
      ),
    );
    if (mounted) {
      setState(() {
        _invalidateDerivedCaches();
        _stableTagCounts = store.resultCounts(const FilterQuery());
      });
      _scheduleFilterRefresh(refreshCounts: true);
    }
  }

  Future<void> _openDirectoryManager() async {
    final store = _store;
    if (store == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      _smoothRoute<void>(
        DirectoryManagerPage(
          store: store,
          scanning: _isScanning,
          onAddDirectory: _pickFolder,
          onRescan: _rescan,
          onRemoveRoot: _removeLibraryRootData,
        ),
        backShortcutProvider: () =>
            _playbackSettings.shortcuts[PlayerShortcutAction.navigateBack]!,
      ),
    );
  }

  /**
   * 打开缺失视频管理页；返回后只在确有 relink 时刷新派生缓存与标签计数。
   */
  Future<void> _openMissingRelink() async {
    final store = _store;
    if (store == null) {
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      _smoothRoute<bool>(
        MissingRelinkPage(
          store: store,
          fileSystem: _fileSystem,
        ),
        backShortcutProvider: () =>
            _playbackSettings.shortcuts[PlayerShortcutAction.navigateBack]!,
      ),
    );
    if (changed == true && mounted) {
      setState(() {
        _invalidateDerivedCaches();
        _stableTagCounts = store.resultCounts(const FilterQuery());
      });
      _scheduleFilterRefresh(refreshCounts: true);
    }
  }

  /** 左侧 root 快捷移除继续复用原确认语义；目录管理页使用同等说明。 */
  Future<bool?> _confirmRemoveRoot(String root) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => maintenanceDialogSurface(
        context: context,
        child: AlertDialog(
          title: const Text('解除目录管理'),
          content: Text(
            '目录中的视频会从当前媒体库与播放队列隐藏，但不会删除本地文件。\n\n'
            '标签关系、收藏、播放进度、媒体详情和稳定视频身份都会保留；'
            '以后重新添加同一目录或匹配到相同文件时会自动恢复。\n\n$root',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffb84d5f),
              ),
              child: const Text('解除管理'),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _addLibraryTag() async {
    final controller = TextEditingController();
    final existingTags = _store?.allTagItems.toList() ?? const <TagItem>[];
    existingTags.sort((a, b) => _tagLabel(a).compareTo(_tagLabel(b)));
    final picked = await showDialog<String>(
      context: context,
      builder: (context) {
        var keyword = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            /**
             * 弹窗内搜索只影响候选展示，不改变真实标签数据。
             */
            final visibleTags = existingTags
                .where((tag) {
                  final label = _tagLabel(tag);
                  if (keyword.trim().isEmpty) {
                    return true;
                  }
                  final normalizedKeyword = keyword.toLowerCase();
                  return label.toLowerCase().contains(normalizedKeyword) ||
                      tag.name.toLowerCase().contains(normalizedKeyword);
                })
                .take(80)
                .toList();
            return AlertDialog(
              title: const Text(
                  '\u6dfb\u52a0\u5230\u6211\u7684\u6807\u7b7e\u5e93'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '\u641c\u7d22\u6216\u65b0\u5efa\u6807\u7b7e',
                        hintText:
                            '\u8f93\u5165\u6807\u7b7e\u540d\uff0c\u4e0b\u65b9\u4f1a\u5373\u65f6\u8fc7\u6ee4',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) =>
                          setDialogState(() => keyword = value),
                      onSubmitted: (value) =>
                          Navigator.of(context).pop(value.trim()),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: visibleTags.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Text(
                                    '\u6ca1\u6709\u5339\u914d\u7684\u5df2\u6709\u6807\u7b7e'),
                              ),
                            )
                          : ScrollConfiguration(
                              behavior: const DesktopDragScrollBehavior(),
                              child: SingleChildScrollView(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final tag in visibleTags)
                                      ActionChip(
                                        label: Text(_tagLabel(tag)),
                                        onPressed: () => Navigator.of(context)
                                            .pop(_tagLabel(tag)),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('\u53d6\u6d88'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(controller.text.trim()),
                  child: const Text('\u6dfb\u52a0'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    final tag = picked == null ? null : TagRules.normalizeTag(picked);
    if (tag == null || tag.isEmpty || _store == null) {
      return;
    }
    try {
      if (!_store!.allTagItems.any(
        (existing) =>
            (existing.groupId ?? 'manual') == 'manual' &&
            TagRules.sameTag(existing.name, tag),
      )) {
        await _store!.createManualTag(name: tag, groupId: 'manual');
      }
      if (!_store!.favoriteTags
          .any((existing) => TagRules.sameTag(existing, tag))) {
        await _store!.addFavoriteTag(tag);
        setState(() {
          _invalidateDerivedCaches();
          _stableTagCounts = _store!.resultCounts(const FilterQuery());
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('\u6dfb\u52a0\u6807\u7b7e\u5931\u8d25\uff1a$error')),
      );
    }
  }

  // ignore: unused_element
  Future<void> _removeLibraryTag(String tag) async {
    final store = _store;
    if (store == null) {
      return;
    }
    await store.removeFavoriteTag(tag);
    _mutateFilters(() {
      _invalidateDerivedCaches();
      _selectedTags.remove(tag);
      _selectedChildTags.clear();
      _stableTagCounts = store.resultCounts(const FilterQuery());
    });
  }

  Future<void> _openVideo(VideoItem item, List<VideoItem> playlist) async {
    final store = _store;
    if (store == null) {
      return;
    }
    final scanWasActive = _isScanning;
    final scanWasAlreadyPaused = _scanProgress?.isPaused ?? false;
    await const LibraryScanPlaybackGate().run<void>(
      scanActive: scanWasActive,
      scanAlreadyPaused: scanWasAlreadyPaused,
      setPaused: store.setScanPaused,
      onPauseChanged: (paused) {
        final progress = _scanProgress;
        if (mounted && _isScanning && progress != null) {
          setState(() => _scanProgress = progress.copyWith(isPaused: paused));
        }
      },
      // 在预检、缩略图预热和播放器解码开始前先让 sidecar 停在文件边界，避免
      // 机械盘随机 fingerprint 读取与当前视频顺序读取互相拖死。
      action: () => _openVideoAfterScanYield(item, playlist),
    );
  }

  /** 在扫描已让出磁盘后执行既有预检、队列预热和 filtered queue 播放链路。 */
  Future<void> _openVideoAfterScanYield(
    VideoItem item,
    List<VideoItem> playlist,
  ) async {
    final store = _store;
    if (store == null) {
      return;
    }
    var playbackDetails = item.mediaDetails;
    if (Platform.isWindows &&
        _playbackSettings.hardwareDecodingEnabled &&
        (playbackDetails?.videoCodec == null ||
            playbackDetails?.width == null ||
            playbackDetails?.height == null)) {
      playbackDetails = await _probeSelectedVideoBeforePlayback(item, store);
      if (!mounted) {
        return;
      }
      if (playbackDetails.videoCodec == null ||
          playbackDetails.width == null ||
          playbackDetails.height == null) {
        // 未知超规格媒体曾绕过兼容矩阵并在创建 8K 纹理时推高内存甚至崩溃。
        // 规格未确认前宁可让用户稍后重试，也不创建不可控的原生播放器会话。
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('尚未取得视频编码和分辨率，已暂缓播放；请等待解析完成后重试。'),
          ),
        );
        return;
      }
    }
    final compatibility = PlayerHardwareCompatibility.assess(
      details: playbackDetails,
      settings: _playbackSettings,
    );
    if (compatibility.status == HardwareDecodeCompatibilityStatus.unsupported) {
      // 兼容结论来自 hydration 缓存或当前点击项的单次预检；取消前不创建播放器或预热队列。
      debugPrint(
        'PLAYER_PREFLIGHT_BLOCKED video_id=${item.videoId} '
        'spec=${compatibility.specification}',
      );
      final confirmed = await showPlayerHardwareDecodeWarningDialog(
        context,
        compatibility,
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    final thumbnailService = _thumbnailService!;
    final activeChildTag =
        _selectedChildTags.isEmpty ? null : _selectedChildTags.first;
    final queueTitle = _queueTitle(
      store: store,
      playlistLength: playlist.length,
    );
    // 在路由切换前把当前项附近已经生成的缩略图提升到同步内存视图，播放器队列
    // 首帧可直接复用，不需要先绘制占位底色再等待异步 Future 完成。
    final initialIndex =
        playlist.indexWhere((video) => video.path == item.path);
    final warmStart = math.max(0, initialIndex - 2);
    final warmEnd = math.min(playlist.length, initialIndex + 7);
    await Future.wait(
      playlist
          .sublist(warmStart, warmEnd)
          .where((video) => !video.isMissing)
          .map(thumbnailService.thumbnailFor),
    );
    if (!mounted) {
      return;
    }
    final wasPaused = thumbnailService.isPaused;
    if (!wasPaused) {
      // 播放期间冻结后台补全，但允许实际可视的播放器队列项以单并发补齐缩略图。
      thumbnailService.pause(allowPriorityRequests: true);
    }
    _playerScopedLibraryDataChanged = false;
    _playerScopedNeedsCountRefresh = false;
    final playerDisposed = Completer<void>();
    _latestPlayerRelease = playerDisposed.future;
    // 备份只做 SQLite 小批次，但播放器仍优先；等待当前批次结束后再创建解码会话。
    await store.pauseDataBackupForPlayback();
    if (!mounted) {
      store.resumeDataBackupAfterPlayback();
      return;
    }
    setState(() => _playerRouteActive = true);
    // 先让媒体库提交 ExcludeSemantics，再压入不透明播放器 Route；否则底层 Route
    // 可能在本次 rebuild 前进入 offstage，让 Windows UIA 继续缓存旧页面节点。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      if (!wasPaused) {
        thumbnailService.resume();
      }
      store.resumeDataBackupAfterPlayback();
      return;
    }
    try {
      await Navigator.of(context).push(
        _smoothRoute<void>(
          PlayerPage(
            initialItem: item,
            playlist: List<VideoItem>.of(playlist),
            thumbnailService: thumbnailService,
            playbackSettings: _playbackSettings,
            onPlaybackSettingsChanged: (settings) async {
              // 播放器内先更新应用级快照，使下一次进入立即沿用，再写入持久化文件。
              if (mounted) {
                setState(() => _playbackSettings = settings);
              }
              await widget.applicationService.savePlaybackSettings(settings);
            },
            activeTags: _selectedTags.toList()..sort(),
            activeChildTag: activeChildTag,
            queueTitle: queueTitle,
            onDeleteVideo: _deleteVideoFromPlayer,
            onToggleFavorite: _toggleFavoriteFromPlayer,
            onRenameFile: _renameVideoFromPlayer,
            onEditManualTags: _editManualTagsFromPlayer,
            onRelinkMissing: _relinkMissingFromPlayer,
            onPlaybackProgressUpdated: _updatePlaybackProgress,
            onMediaDetailsUpdated: _updateMediaDetails,
            disposalCompleter: playerDisposed,
            fileSystem: _fileSystem,
            playerBackendFactory: widget.playerBackendFactory,
            mediaProbeBackendFactory: widget.mediaProbeBackendFactory,
            fullscreenSessionController: _playerFullscreenSession,
          ),
        ),
      );
    } finally {
      if (mounted) {
        // 反向 Route 已完成后立即恢复媒体库语义，不等待原生资源释放尾部。
        setState(() => _playerRouteActive = false);
      }
      // 路由返回不代表 media_kit 原生线程已释放；等待完成信号再恢复后台任务。
      await playerDisposed.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
      unawaited(_sampleMemoryAfterPlayerRelease());
      await _playbackSnapshotQueue?.flush();
      final snapshotError = _playbackSnapshotQueue?.takeLastError();
      if (snapshotError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('部分播放进度保存失败，请稍后重试')),
        );
      }
      if (!wasPaused) {
        thumbnailService.resume();
      }
      store.resumeDataBackupAfterPlayback();
    }
    if (mounted && _playerScopedLibraryDataChanged) {
      _invalidateDerivedCaches();
      _scheduleFilterRefresh(refreshCounts: _playerScopedNeedsCountRefresh);
      _playerScopedLibraryDataChanged = false;
      _playerScopedNeedsCountRefresh = false;
    }
  }

  /**
   * 为用户刚点击且详情未知的视频执行一次独立高优先级预检。
   *
   * 后台批量探测可能排在数千条记录之后，不能让未知 8K 媒体绕过播放前兼容矩阵。
   * 该服务只处理当前一项并在返回后取消代次；播放器页面和右侧队列仍只读缓存详情。
   */
  Future<MediaDetails> _probeSelectedVideoBeforePlayback(
    VideoItem item,
    LibraryApplicationFacade store,
  ) async {
    final service = widget.applicationService.createMediaDetailsService(
      onUpdated: (updated, details, fingerprint) async {
        final current = store.videos[TagRules.pathKey(updated.path)];
        if (_store != store ||
            current == null ||
            current.videoId != updated.videoId ||
            current.mediaFingerprint != fingerprint) {
          return;
        }
        current.mediaDetails = details;
        final duration = details.duration;
        if (duration != null && duration > Duration.zero) {
          current.playbackDuration = duration;
        }
        await store.upsertVideo(current);
      },
    );
    try {
      return await service.detailsFor(item, refreshIncomplete: true).timeout(
            const Duration(seconds: 5),
            onTimeout: () => const MediaDetails(),
          );
    } finally {
      service.dispose();
    }
  }

  /** 返回媒体库后分三次采样，观察原生纹理释放与 Flutter ImageCache 的衰减是否同步。 */
  Future<void> _sampleMemoryAfterPlayerRelease() async {
    await PlayerMemoryDiagnostics.logStage('library_after_release_0ms');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await PlayerMemoryDiagnostics.logStage('library_after_release_500ms');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await PlayerMemoryDiagnostics.logStage('library_after_release_2000ms');
  }

  /** 播放器内收藏只写当前视频，返回媒体库后再做一次无计数轻刷新。 */
  Future<void> _toggleFavoriteFromPlayer(VideoItem item) async {
    item.isFavorite = !item.isFavorite;
    await _store?.upsertVideo(item);
    _playerScopedLibraryDataChanged = true;
  }

  /** 将播放位置和最近播放时间写入稳定 videoId 对应的视频记录。 */
  Future<void> _updatePlaybackProgress(
    VideoItem item,
    Duration position,
    Duration duration,
    bool completed,
  ) async {
    item.playbackPosition = position;
    if (duration > Duration.zero) {
      // 播放内核偶发的临时 0 时长不能覆盖已经持久化的可靠总时长与完成判断。
      item.playbackDuration = duration;
      item.playbackCompleted = completed;
    }
    final updatedAt = DateTime.now();
    item.playbackPositionUpdatedAt = updatedAt;
    item.lastPlayedAt = updatedAt;
    _playbackSnapshotQueue?.enqueue(PlaybackSnapshot(
      item: item,
      position: item.playbackPosition,
      duration: item.playbackDuration,
      completed: item.playbackCompleted,
      updatedAt: updatedAt,
    ));
    if (mounted) {
      _markPlaybackTimestampChanged(item);
    }
  }

  /** 播放器错误面板复用 missing 管理页的安全 picker 与 fingerprint 校验。 */
  Future<bool> _relinkMissingFromPlayer(VideoItem item) async {
    final store = _store;
    if (store == null) {
      return false;
    }
    final changed = await pickAndRelinkMissingVideo(
      context,
      store: store,
      fileSystem: _fileSystem,
      item: item,
    );
    if (changed) {
      _playerScopedLibraryDataChanged = true;
      _playerScopedNeedsCountRefresh = true;
    }
    return changed;
  }

  /** 播放器内改名成功后延迟到 Route 返回再刷新媒体库，避免后台页面重建。 */
  Future<void> _renameVideoFromPlayer(
    VideoItem item,
    String newBaseName,
  ) async {
    await _renameVideoPath(item, newBaseName);
    _playerScopedLibraryDataChanged = true;
  }

  /**
   * 执行同目录文件重命名，并以同一 videoId 提交新的 mutable path。
   *
   * 文件系统先拒绝覆盖并完成物理改名；SQLite 提交失败时立即尝试恢复原名，避免磁盘与
   * 媒体库索引分叉。调用方只负责选择立即刷新或延迟到播放器 Route 返回后刷新。
   */
  Future<void> _renameVideoPath(
    VideoItem item,
    String newBaseName,
  ) async {
    final store = _store;
    if (store == null) {
      throw StateError('媒体库尚未就绪，请稍后重试');
    }
    final oldPath = item.path;
    final extension = p.extension(oldPath);
    final targetPath = _fileSystem.joinPath(<String>[
      _fileSystem.parentPath(oldPath),
      '$newBaseName$extension',
    ]);
    if (TagRules.pathKey(oldPath) == TagRules.pathKey(targetPath)) {
      if (_fileSystem.normalizePath(oldPath) ==
          _fileSystem.normalizePath(targetPath)) {
        return;
      }
      throw StateError('当前暂不支持仅修改文件名大小写，请换一个不同名称');
    }
    if (await _fileSystem.fileExists(targetPath)) {
      throw StateError('同名文件已存在，请换一个名称');
    }

    final renamedPath = await _fileSystem.renameFile(oldPath, targetPath);
    try {
      await store.renameVideoPath(item, renamedPath);
    } catch (error) {
      try {
        await _fileSystem.renameFile(renamedPath, oldPath);
      } catch (_) {
        // 回滚失败表示磁盘已改名但数据库仍指向旧路径，必须要求返回媒体库重新扫描修复。
        throw StateError('文件已改名，但媒体库更新失败；请返回媒体库后重新扫描');
      }
      rethrow;
    }
  }

  Future<void> _toggleFavorite(VideoItem item) async {
    setState(() => item.isFavorite = !item.isFavorite);
    await _store?.upsertVideo(item);
    if (mounted) {
      _markLibraryDataChanged();
    }
  }

  /** 通过共享文件系统平台边界定位视频；页面不拼接 Windows 或其它平台命令。 */
  Future<void> _revealVideoLocation(VideoItem item) async {
    try {
      await _fileSystem.revealInFileManager(item.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开文件位置，请确认文件仍然存在')),
        );
      }
    }
  }

  Future<void> _updateMediaDetails(
    VideoItem item,
    MediaDetails details,
    String? fingerprint,
  ) async {
    item.mediaDetails = details;
    final duration = details.duration;
    if (duration != null && duration > Duration.zero) {
      item.playbackDuration = duration;
    }
    item.mediaFingerprint = fingerprint ?? item.mediaFingerprint;
    await _store?.upsertVideo(item);
    if (mounted) {
      _markLibraryDataChanged();
    }
  }

  /** 执行播放器弹窗已经确认的删除选择，真实文件删除始终留在平台边界内。 */
  Future<void> _deleteVideoFromPlayer(
    VideoItem item,
    bool moveLocalFileToTrash,
  ) async {
    if (moveLocalFileToTrash) {
      await _fileSystem.moveFileToTrash(item.path);
    }
    await _store?.deleteVideo(item.path);
    try {
      await _thumbnailService?.deleteThumbnailFor(item);
    } catch (_) {
      // 视频记录已经提交删除，缓存清理失败不能把成功的业务动作误报为失败。
    }
    // 播放器路由仍在前台时不重建媒体库；返回后统一刷新可见结果和标签计数。
    _playerScopedLibraryDataChanged = true;
    _playerScopedNeedsCountRefresh = true;
  }

  /**
   * 处理媒体卡片删除动作，并把移入系统回收站保持为显式可选项。
   *
   * 数据库事务会一并删除标签关系、收藏、播放进度、媒体详情和稳定身份记录；选择仅移出
   * 媒体库时，仍位于受监控 root 的文件会在下次扫描时作为新条目重新出现。
   */
  Future<void> _requestDeleteVideo(VideoItem item) async {
    final decision = await _resolveSingleVideoDeleteDecision(item);
    if (decision == null || !mounted) {
      return;
    }
    try {
      await _deleteConfirmedLibraryVideo(
        item,
        decision.moveLocalFileToTrash,
      );
      if (mounted) {
        _markLibraryDataChanged();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message =
          error is FileSystemException ? error.message : '当前平台暂不支持移入回收站';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('移除失败：$message；媒体库记录未删除')),
      );
    }
  }

  /**
   * 执行已经由用户确认的单条媒体库删除。
   *
   * 该方法不刷新页面，便于批量删除在全部条目处理完后只触发一次筛选和计数更新。
   */
  Future<void> _deleteConfirmedLibraryVideo(
    VideoItem item,
    bool moveLocalFileToTrash,
  ) async {
    if (moveLocalFileToTrash) {
      await _fileSystem.moveFileToTrash(item.path);
    }
    await _store?.deleteVideo(item.path);
    try {
      await _thumbnailService?.deleteThumbnailFor(item);
    } catch (_) {
      // 缩略图是可重建缓存；数据库删除成功后不再因缓存异常误导用户重复删除。
    }
  }

  /**
   * 删除当前完整筛选结果中已选择的视频。
   *
   * 每条记录继续走与单条删除一致的平台边界；成功项立即从选择集移除，失败项保留选择，
   * 最后只刷新一次筛选和标签计数，避免大媒体库中每删一条都全量重算。
   */
  Future<void> _requestDeleteSelectedVideos(
    List<VideoItem> currentVideos,
  ) async {
    final targets = [
      for (final item in currentVideos)
        if (_selectedLibraryVideoIds.contains(item.videoId)) item,
    ];
    if (targets.isEmpty) {
      return;
    }
    final decision = await _resolveBatchVideoDeleteDecision(targets.length);
    if (decision == null || !mounted) {
      return;
    }

    final deletedIds = <String>{};
    final failedTitles = <String>[];
    for (final item in targets) {
      try {
        await _deleteConfirmedLibraryVideo(
          item,
          decision.moveLocalFileToTrash,
        );
        deletedIds.add(item.videoId);
      } catch (_) {
        failedTitles.add(item.title);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedLibraryVideoIds.removeAll(deletedIds);
      if (_selectedLibraryVideoIds.isEmpty) {
        _librarySelectionMode = false;
      }
    });
    if (deletedIds.isNotEmpty) {
      _markLibraryDataChanged();
    }
    if (failedTitles.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已删除 ${deletedIds.length} 个，${failedTitles.length} 个失败；失败项仍保持选中',
          ),
        ),
      );
    }
  }

  /** 单条删除按当前偏好决定直接执行或展示统一确认层。 */
  Future<VideoDeleteDecision?> _resolveSingleVideoDeleteDecision(
    VideoItem item,
  ) async {
    final settings = _playbackSettings;
    final immediate = videoDeleteDecisionWithoutPrompt(settings);
    if (immediate != null) {
      return immediate;
    }
    final decision = await showPlayerDeleteConfirmationDialog(
      context,
      item,
      initialMoveLocalFileToTrash: settings.moveDeletedFileToTrash,
    );
    return _rememberDeleteDecision(decision);
  }

  /** 批量删除与单条删除共享确认显示和回收站默认值。 */
  Future<VideoDeleteDecision?> _resolveBatchVideoDeleteDecision(
    int count,
  ) async {
    final settings = _playbackSettings;
    final immediate = videoDeleteDecisionWithoutPrompt(settings);
    if (immediate != null) {
      return immediate;
    }
    final decision = await showBatchVideoDeleteConfirmationDialog(
      context,
      count: count,
      initialMoveLocalFilesToTrash: settings.moveDeletedFileToTrash,
    );
    return _rememberDeleteDecision(decision);
  }

  /**
   * 只在用户确认删除后保存弹窗选择；设置写入失败时中止删除，避免界面记忆与
   * 后续真实文件动作分叉。
   */
  Future<VideoDeleteDecision?> _rememberDeleteDecision(
    VideoDeleteDecision? decision,
  ) async {
    if (decision == null || !mounted) {
      return null;
    }
    final next = _playbackSettings.copyWith(
      moveDeletedFileToTrash: decision.moveLocalFileToTrash,
      confirmBeforeDeletingVideo: !decision.dontAskAgain,
    );
    try {
      await widget.applicationService.savePlaybackSettings(next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存删除偏好失败：$error；本次未执行删除')),
        );
      }
      return null;
    }
    if (mounted) {
      setState(() => _playbackSettings = next);
    }
    return decision;
  }

  /**
   * 使用统一弹窗编辑视频在当前标签层级下的 manual 标签。
   *
   * [deferLibraryRefresh] 仅供播放器前台路由使用，保存后延迟到返回媒体库再刷新结果，
   * 避免隐藏页面在播放期间执行标签计数重算。
   */
  Future<void> _editTags(
    VideoItem item, {
    bool deferLibraryRefresh = false,
  }) async {
    final childParentTag = _activeChildParentTag;
    final editingChildTags = childParentTag != null;
    final updated = await showDialog<Set<String>>(
      context: context,
      builder: (_) => TagEditorDialog(
        title:
            editingChildTags ? '${item.title} / $childParentTag' : item.title,
        initialTags: editingChildTags
            ? (item.childTags[childParentTag] ?? const <String>{})
            : item.tags,
        existingTags: tagEditorCandidates(
          _store?.allTagItems ?? const <TagItem>[],
          parentTag: editingChildTags ? childParentTag : null,
        ),
        lockedTags: editingChildTags
            ? _folderChildTagsForItem(item, childParentTag)
            : _folderTagsForItem(item),
      ),
    );
    if (updated == null) {
      return;
    }
    setState(() {
      final normalized = _normalizeTagSet(updated);
      if (editingChildTags) {
        item.childTags[childParentTag] = {
          ..._folderChildTagsForItem(item, childParentTag),
          ...normalized,
        };
      } else {
        item.tags
          ..clear()
          ..addAll({
            ..._folderTagsForItem(item),
            ...normalized,
          });
      }
    });
    await _store?.replaceManualTags(item,
        parentTag: editingChildTags ? childParentTag : null);
    if (mounted && deferLibraryRefresh) {
      _playerScopedLibraryDataChanged = true;
    } else if (mounted) {
      _markLibraryDataChanged();
    }
  }

  /**
   * 播放器继续复用媒体库页面的统一标签编辑入口。
   *
   * 当前一级标签、folder 锁定项、manual 候选集合和保存语义全部由 [_editTags] 统一决定，
   * 防止播放器与批量维护入口随时间演化成不同的数据视图。
   */
  Future<void> _editManualTagsFromPlayer(VideoItem item) =>
      _editTags(item, deferLibraryRefresh: true);

  Set<String> _folderTagsForItem(VideoItem item) {
    final rootPath = item.rootPath;
    if (rootPath == null || rootPath.isEmpty) {
      return const <String>{};
    }
    return TagRules.parentTagsFor(rootPath, item.path);
  }

  Set<String> _folderChildTagsForItem(VideoItem item, String parentTag) {
    final rootPath = item.rootPath;
    if (rootPath == null || rootPath.isEmpty) {
      return const <String>{};
    }
    return TagRules.childTagsFor(rootPath, item.path)[parentTag] ??
        const <String>{};
  }

  Set<String> _normalizeTagSet(Iterable<String> tags) {
    final seen = <String>{};
    final normalized = <String>{};
    for (final raw in tags) {
      final tag = TagRules.normalizeTag(raw);
      if (tag.isEmpty) {
        continue;
      }
      if (seen.add(tag.toLowerCase())) {
        normalized.add(tag);
      }
    }
    return normalized;
  }
}
