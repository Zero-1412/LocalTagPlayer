// ignore_for_file: slash_for_doc_comments

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/app_paths.dart';
import 'composition/local_tag_player_dependencies.dart';
import 'platform/desktop_file_system_adapter.dart';
import 'platform/database_provider.dart';
import 'platform/platform_interfaces.dart';
import 'services/library/library_application_facade.dart';
import 'services/library/library_load_diagnostics.dart';
import 'services/library/library_page_application_service.dart';
import 'services/library/library_stress_control.dart';
import 'services/library/library_scan_backend.dart';
import 'services/library/library_store.dart';
import 'services/media/external_media_tools.dart';
import 'services/media/media_probe_backend.dart';
import 'services/player/media_kit_player_backend.dart';
import 'services/player/windows_native_player_backend.dart';
import 'services/window/desktop_window_state_service.dart';
import 'pages/library/library_page.dart';
import 'widgets/app_theme_tokens.dart';

export 'core/tag_rules.dart';
export 'composition/local_tag_player_dependencies.dart';
export 'core/app_paths.dart';
export 'core/data_backup_settings.dart';
export 'core/layout_size.dart';
export 'core/playback_settings.dart';
export 'models/external_media_tools_state.dart';
export 'models/data_backup_models.dart';
export 'models/media_details.dart';
export 'models/library_scan_models.dart';
export 'models/library_sort.dart';
export 'models/platform_models.dart';
export 'models/video_item.dart';
export 'platform/desktop_file_system_adapter.dart';
export 'platform/database_provider.dart';
export 'platform/file_system_adapter.dart';
export 'platform/platform_interfaces.dart';
export 'repositories/repository_interfaces.dart';
export 'services/library/library_application_facade.dart';
export 'services/library/library_card_ui_diagnostics.dart';
export 'services/library/library_collection_rules.dart';
export 'services/library/library_count_refresh_coordinator.dart';
export 'services/library/library_data_backup_service.dart';
export 'services/library/library_load_diagnostics.dart';
export 'services/library/library_page_application_service.dart';
export 'services/library/library_scan_ui_diagnostics.dart';
export 'services/library/library_stress_control.dart';
export 'services/library/library_metadata_persistence.dart';
export 'services/library/library_scan_backend.dart';
export 'services/library/library_scan_service.dart';
export 'services/library/library_scan_coordinator.dart';
export 'services/library/library_store_access.dart';
export 'services/library/library_store.dart';
export 'services/library/library_tag_maintenance.dart';
export 'services/library/library_video_persistence.dart';
export 'services/library/library_tag_persistence.dart';
export 'services/media/external_media_tools.dart';
export 'services/media/media_probe_backend.dart';
export 'services/media/thumbnail_service.dart';
export 'services/media/media_details_service.dart';
export 'services/player/playback_snapshot_write_queue.dart';
export 'services/player/player_hardware_acceleration.dart';
export 'services/player/media_kit_player_backend.dart';
export 'services/player/player_hardware_compatibility.dart';
export 'services/player/player_memory_diagnostics.dart';
export 'services/player/windows_native_player_backend.dart';
export 'services/relink/bulk_path_relink_service.dart';
export 'services/tags/tag_query_service.dart';
export 'services/window/desktop_window_state_service.dart';
export 'pages/player/player_context_panel.dart';
export 'pages/player/player_control_slider.dart';
export 'pages/player/player_delete_dialog.dart';
export 'pages/player/player_diagnostics_dialog.dart';
export 'pages/player/player_dialog_content.dart';
export 'pages/player/player_hardware_decode_warning_dialog.dart';
export 'pages/player/player_open_failure_panel.dart';
export 'pages/player/player_open_request_controller.dart';
export 'pages/player/player_playback_controller.dart';
export 'pages/player/player_playback_mode.dart';
export 'pages/player/player_settings_panel.dart';
export 'pages/player/player_video_aspect_mode.dart';
export 'pages/player/player_resume_dialog.dart';
export 'pages/player/player_queue_sidebar.dart';
export 'pages/player/player_page.dart';
export 'pages/library/library_page.dart';
export 'pages/library/library_page_helpers.dart';
export 'pages/library/missing_relink_page.dart';
export 'pages/tags/tag_manager_page.dart';
export 'widgets/app_theme_tokens.dart';
export 'widgets/design_system/app_interaction_surface.dart';
export 'widgets/library/library_smoke_keys.dart';
export 'widgets/library/library_sort_control.dart';
export 'widgets/library/library_local_view.dart';
export 'widgets/library/library_tag_discovery_panel.dart';
export 'widgets/library/library_video_results.dart';
export 'widgets/library/library_widgets.dart';

// 媒体库服务集中管理扫描、持久化、诊断与内存状态协调。

// 细分服务目录只表达职责归属，不改变现有平台边界或业务调用顺序。

// 页面和组件按用户工作流分组，避免不同功能在一级目录中继续混放。

/** 组合根内选择播放器具体实现，页面不再读取环境变量或平台类型。 */
PlayerBackend _createPlayerBackend({
  required String hwdec,
  required bool enableHardwareAcceleration,
}) {
  if (Platform.isWindows &&
      Platform.environment['LOCAL_TAG_PLAYER_BACKEND'] ==
          'windows-native-mpv') {
    return WindowsNativePlayerBackend(mode: 'mpv');
  }
  if (Platform.isWindows &&
      Platform.environment['LOCAL_TAG_PLAYER_BACKEND'] ==
          'windows-native-stub') {
    return WindowsNativePlayerBackend(mode: 'stub');
  }
  return MediaKitPlayerBackend(
    hwdec: hwdec,
    enableHardwareAcceleration: enableHardwareAcceleration,
  );
}

/**
 * 创建当前平台的完整依赖图，确保具体实现只在组合根出现一次。
 *
 * [appPaths] 允许 bootstrap 与窗口服务共享同一路径策略；
 * [registerBeforeWindowClose] 把异步 Store 关闭动作交给桌面窗口边界等待。
 */
LocalTagPlayerDependencies createLocalTagPlayerDependencies({
  AppPaths? appPaths,
  void Function(Future<void> Function())? registerBeforeWindowClose,
}) {
  final paths = appPaths ?? AppPaths();
  final databaseProvider = SqfliteDatabaseProvider(
    paths: paths,
    factory: databaseFactoryFfi,
  );
  final ffmpegBackend = DesktopFFmpegBackend();
  final fileSystem = Platform.isMacOS
      ? const MacOsFileSystemAdapter()
      : Platform.isLinux
          ? const LinuxFileSystemAdapter()
          : const DesktopFileSystemAdapter();
  MediaProbeBackend mediaProbeBackendFactory() =>
      createMediaProbeBackend(ffmpegBackend);
  final libraryDebugOptions = LibraryDebugOptions(
    stressRoot: kDebugMode
        ? Platform.environment['LOCAL_TAG_PLAYER_LIBRARY_STRESS_ROOT']?.trim()
        : null,
    startupDiagnosticsPath: kDebugMode
        ? p.join(
            Directory.systemTemp.path,
            'local_tag_player_startup_diagnostics.json',
          )
        : null,
  );
  Future<LibraryApplicationFacade> libraryLoader({
    LibraryLoadDiagnostics? diagnostics,
    required bool dataBackupEnabled,
  }) async {
    final repository = await LibraryStore.load(
      diagnostics: diagnostics,
      scanBackend: createLibraryScanBackend(),
      databaseProvider: databaseProvider,
      dataBackupEnabled: dataBackupEnabled,
    );
    return LibraryApplicationFacade(
      libraryRepository: repository,
      tagRepository: repository,
      cacheRepository: repository,
      playbackRepository: repository,
    );
  }

  return LocalTagPlayerDependencies(
    fileSystem: fileSystem,
    paths: paths,
    libraryPageApplicationService: LocalLibraryPageApplicationService(
      paths: paths,
      fileSystem: fileSystem,
      libraryLoader: libraryLoader,
      ffmpegBackend: ffmpegBackend,
      mediaProbeBackendFactory: mediaProbeBackendFactory,
      debugOptions: libraryDebugOptions,
      registerBeforeWindowClose: registerBeforeWindowClose,
    ),
    playerBackendFactory: _createPlayerBackend,
    mediaProbeBackendFactory: mediaProbeBackendFactory,
  );
}

Future<void> bootstrapLocalTagPlayer() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  sqfliteFfiInit();
  final paths = AppPaths();
  final windowStateService = DesktopWindowStateService(paths);
  final dependencies = createLocalTagPlayerDependencies(
    appPaths: paths,
    registerBeforeWindowClose: windowStateService.registerBeforeClose,
  );
  await windowStateService.initialize();
  runApp(LocalTagPlayerApp(dependencies: dependencies));
}

class LocalTagPlayerApp extends StatelessWidget {
  const LocalTagPlayerApp({super.key, required this.dependencies});

  /** 由 bootstrap 组合根创建的稳定依赖图。 */
  final LocalTagPlayerDependencies dependencies;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '\u672c\u5730\u6807\u7b7e\u64ad\u653e\u5668',
      debugShowCheckedModeBanner: false,
      theme: buildLocalTagPlayerTheme(),
      builder: (context, child) {
        final accessibility = AppAccessibilityData.fromMediaQuery(
          MediaQuery.of(context),
        );
        return AppAccessibilityScope(
          data: accessibility,
          child: Theme(
            data: buildLocalTagPlayerTheme(
              highContrast: accessibility.highContrast,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: LibraryPage(
        applicationService: dependencies.libraryPageApplicationService,
        fileSystem: dependencies.fileSystem,
        playerBackendFactory: dependencies.playerBackendFactory,
        mediaProbeBackendFactory: dependencies.mediaProbeBackendFactory,
      ),
    );
  }
}
