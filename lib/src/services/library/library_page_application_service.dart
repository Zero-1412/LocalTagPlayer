import '../../core/app_paths.dart';
import '../../core/data_backup_settings.dart';
import '../../core/playback_settings.dart';
import '../../models/library_sort.dart';
import '../../models/media_details.dart';
import '../../models/video_item.dart';
import '../../platform/file_system_adapter.dart';
import '../../platform/platform_interfaces.dart';
import '../media/media_details_service.dart';
import '../media/thumbnail_service.dart';
import 'library_application_facade.dart';
import 'library_load_diagnostics.dart';
import 'library_stress_control.dart';

// ignore_for_file: slash_for_doc_comments

/** 组合根提供的媒体库 facade 加载入口。 */
typedef LibraryApplicationLoader = Future<LibraryApplicationFacade> Function({
  LibraryLoadDiagnostics? diagnostics,
  required bool dataBackupEnabled,
});

/** 媒体详情完成后的 Dart Repository 写回回调。 */
typedef MediaDetailsUpdatedCallback = Future<void> Function(
  VideoItem item,
  MediaDetails details,
  String? fingerprint,
);

/** 多条媒体详情完成后的 Dart Repository 批量写回回调。 */
typedef MediaDetailsBatchUpdatedCallback = Future<void> Function(
  List<MediaDetailsUpdate> updates,
);

/** 从应用私有路径读取媒体库排序偏好；损坏文件安全回退默认值。 */
Future<LibrarySortPreferences> loadLibrarySortPreferences(
  AppPaths paths,
) async {
  try {
    final file = await paths.librarySortPreferencesFile();
    if (!await file.exists()) {
      return const LibrarySortPreferences();
    }
    return LibrarySortPreferences.decode(await file.readAsString());
  } catch (_) {
    return const LibrarySortPreferences();
  }
}

/** 把媒体库排序偏好保存到独立设置文件，不写入 SQLite。 */
Future<void> saveLibrarySortPreferences(
  AppPaths paths,
  LibrarySortPreferences preferences,
) async {
  final file = await paths.librarySortPreferencesFile();
  await file.writeAsString(preferences.encode(), flush: true);
}

/** 媒体库页面首屏所需的不可变应用状态。 */
class LibraryPageStartupData {
  const LibraryPageStartupData({
    required this.store,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.sortPreferences,
    required this.dataBackupSettings,
  });

  /** 页面唯一业务入口。 */
  final LibraryApplicationFacade store;

  /** 页面与播放器共享的缩略图队列。 */
  final ThumbnailService thumbnailService;

  /** 已从应用私有路径恢复的播放设置。 */
  final PlaybackSettings playbackSettings;

  /** 已从应用私有路径恢复的排序偏好。 */
  final LibrarySortPreferences sortPreferences;

  /** 独立视频依赖备份设置。 */
  final DataBackupSettings dataBackupSettings;
}

/**
 * LibraryPage 使用的应用服务边界。
 *
 * 页面不得穿透该接口读取 AppPaths、FFmpegBackend 或 Repository 具体实现；这些选择
 * 只在组合根和本地实现中出现。SQLite 写入仍由 facade 背后的 Dart Repository 完成。
 */
abstract interface class LibraryPageApplicationService {
  /** 加载页面首屏所需的 facade、缩略图服务和用户偏好。 */
  Future<LibraryPageStartupData> load({LibraryLoadDiagnostics? diagnostics});

  /** 保存播放设置，不向页面暴露实际文件路径。 */
  Future<void> savePlaybackSettings(PlaybackSettings settings);

  /** 保存视频依赖备份开关，不向页面暴露实际文件路径。 */
  Future<void> saveDataBackupSettings(DataBackupSettings settings);

  /** 保存排序偏好，不向页面暴露实际文件路径。 */
  Future<void> saveSortPreferences(LibrarySortPreferences preferences);

  /** 为单次扫描或播放前预检创建独占 generation 的媒体详情服务。 */
  MediaDetailsService createMediaDetailsService({
    MediaDetailsUpdatedCallback? onUpdated,
    MediaDetailsBatchUpdatedCallback? onBatchUpdated,
    void Function(MediaDetailsProgress progress)? onProgress,
  });

  /** debug 专项压测允许操作的唯一 root；发布构建为 null。 */
  String? get stressRoot;

  /** 写入不包含用户标签或路径内容的启动诊断摘要。 */
  Future<void> writeStartupDiagnostics({
    required LibraryLoadDiagnostics diagnostics,
    required Duration totalElapsed,
    required String marker,
  });
}

/**
 * 本地桌面版媒体库页面应用服务。
 *
 * 该实现由 bootstrap composition root 创建，集中拥有路径、FFmpeg 和媒体探测工厂；
 * 页面只消费用例方法，不能重新选择平台实现。
 */
class LocalLibraryPageApplicationService
    implements LibraryPageApplicationService {
  /**
   * 创建桌面媒体库用例服务。
   *
   * [registerBeforeWindowClose] 由桌面组合根注入，用于在窗口销毁前等待当前
   * Repository 关闭；测试或没有桌面窗口生命周期的宿主可省略。
   */
  const LocalLibraryPageApplicationService({
    required AppPaths paths,
    required FileSystemAdapter fileSystem,
    required LibraryApplicationLoader libraryLoader,
    required FFmpegBackend ffmpegBackend,
    required MediaProbeBackendFactory mediaProbeBackendFactory,
    required LibraryDebugOptions debugOptions,
    void Function(Future<void> Function())? registerBeforeWindowClose,
  })  : _paths = paths,
        _fileSystem = fileSystem,
        _libraryLoader = libraryLoader,
        _ffmpegBackend = ffmpegBackend,
        _mediaProbeBackendFactory = mediaProbeBackendFactory,
        _registerBeforeWindowClose = registerBeforeWindowClose,
        _debugOptions = debugOptions;

  final AppPaths _paths;
  final FileSystemAdapter _fileSystem;
  final LibraryApplicationLoader _libraryLoader;
  final FFmpegBackend _ffmpegBackend;
  final MediaProbeBackendFactory _mediaProbeBackendFactory;
  /** 桌面组合根注入的异步关闭注册器；测试和非桌面宿主可为空。 */
  final void Function(Future<void> Function())? _registerBeforeWindowClose;
  final LibraryDebugOptions _debugOptions;

  @override
  Future<LibraryPageStartupData> load({
    LibraryLoadDiagnostics? diagnostics,
  }) async {
    final dataBackupSettings = diagnostics == null
        ? await DataBackupSettings.load(_paths)
        : await diagnostics.measureAsync(
            'startup.data_backup_settings_load',
            () => DataBackupSettings.load(_paths),
          );
    final store = await _libraryLoader(
      diagnostics: diagnostics,
      dataBackupEnabled: dataBackupSettings.enabled,
    );
    try {
      final thumbnailService = diagnostics == null
          ? await ThumbnailService.create(_paths, _ffmpegBackend)
          : await diagnostics.measureAsync(
              'startup.thumbnail_service_create',
              () => ThumbnailService.create(_paths, _ffmpegBackend),
            );
      final playbackSettings = diagnostics == null
          ? await PlaybackSettings.load(_paths)
          : await diagnostics.measureAsync(
              'startup.playback_settings_load',
              () => PlaybackSettings.load(_paths),
            );
      final sortPreferences = diagnostics == null
          ? await loadLibrarySortPreferences(_paths)
          : await diagnostics.measureAsync(
              'startup.sort_preferences_load',
              () => loadLibrarySortPreferences(_paths),
            );
      final startupData = LibraryPageStartupData(
        store: store,
        thumbnailService: thumbnailService,
        playbackSettings: playbackSettings,
        sortPreferences: sortPreferences,
        dataBackupSettings: dataBackupSettings,
      );
      // 只在首屏依赖全部成功后接管窗口关闭，避免注册一个初始化失败的 Store。
      _registerBeforeWindowClose?.call(store.close);
      return startupData;
    } catch (_) {
      // 首屏任一依赖加载失败时关闭已创建的 facade，避免数据库句柄泄漏。
      await store.close();
      rethrow;
    }
  }

  @override
  Future<void> savePlaybackSettings(PlaybackSettings settings) =>
      settings.save(_paths);

  @override
  Future<void> saveDataBackupSettings(DataBackupSettings settings) =>
      settings.save(_paths);

  @override
  Future<void> saveSortPreferences(
    LibrarySortPreferences preferences,
  ) =>
      saveLibrarySortPreferences(_paths, preferences);

  @override
  MediaDetailsService createMediaDetailsService({
    MediaDetailsUpdatedCallback? onUpdated,
    MediaDetailsBatchUpdatedCallback? onBatchUpdated,
    void Function(MediaDetailsProgress progress)? onProgress,
  }) {
    return MediaDetailsService(
      probeBackend: _mediaProbeBackendFactory(),
      onUpdated: onUpdated,
      onBatchUpdated: onBatchUpdated,
      onProgress: onProgress,
    );
  }

  @override
  String? get stressRoot => _debugOptions.stressRoot;

  @override
  Future<void> writeStartupDiagnostics({
    required LibraryLoadDiagnostics diagnostics,
    required Duration totalElapsed,
    required String marker,
  }) {
    return _debugOptions.writeStartupDiagnostics(
      fileSystem: _fileSystem,
      diagnostics: diagnostics,
      totalElapsed: totalElapsed,
      marker: marker,
    );
  }
}
