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
export 'core/layout_size.dart';
export 'core/playback_settings.dart';
export 'models/external_media_tools_state.dart';
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

/** 创建当前平台的完整依赖图，确保具体实现只在组合根出现一次。 */
LocalTagPlayerDependencies createLocalTagPlayerDependencies() {
  final paths = AppPaths();
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
  }) async {
    final repository = await LibraryStore.load(
      diagnostics: diagnostics,
      scanBackend: createLibraryScanBackend(),
      databaseProvider: databaseProvider,
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
    ),
    playerBackendFactory: _createPlayerBackend,
    mediaProbeBackendFactory: mediaProbeBackendFactory,
  );
}

Future<void> bootstrapLocalTagPlayer() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  sqfliteFfiInit();
  final dependencies = createLocalTagPlayerDependencies();
  await DesktopWindowStateService(dependencies.paths).initialize();
  runApp(LocalTagPlayerApp(dependencies: dependencies));
}

class LocalTagPlayerApp extends StatelessWidget {
  const LocalTagPlayerApp({super.key, required this.dependencies});

  /** 由 bootstrap 组合根创建的稳定依赖图。 */
  final LocalTagPlayerDependencies dependencies;
  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff2f6f73),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: '\u672c\u5730\u6807\u7b7e\u64ad\u653e\u5668',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        fontFamilyFallback: const [
          'Microsoft YaHei',
          'Microsoft YaHei UI',
          'SimHei',
          'Segoe UI',
        ],
        useMaterial3: true,
        scaffoldBackgroundColor: appBackground,
        cardTheme: const CardThemeData(
          elevation: 0,
          color: appSurface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: appBorder),
          ),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: appSurface,
          foregroundColor: Color(0xff1d2725),
          centerTitle: false,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: appSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: appBorder),
          ),
          titleTextStyle: const TextStyle(
            color: Color(0xff1d2725),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: appSurface,
          surfaceTintColor: Colors.transparent,
          textStyle: const TextStyle(color: appText, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: appBorder),
          ),
        ),
        menuTheme: MenuThemeData(
          style: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(appSurface),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: appBorder),
              ),
            ),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: appSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: appShell,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          behavior: SnackBarBehavior.floating,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: appAccent,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(0, 40),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: appAccentStrong,
            side: const BorderSide(color: appBorder),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(0, 40),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: appAccentStrong,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: appSurfaceAlt,
          selectedColor: const Color(0xffd7eeea),
          disabledColor: const Color(0xffe7ecea),
          side: const BorderSide(color: appBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          labelStyle: const TextStyle(
              color: Color(0xff20302d), fontWeight: FontWeight.w600),
          secondaryLabelStyle: const TextStyle(
              color: appAccentStrong, fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          showCheckmark: false,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: appSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: appBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: appBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: appAccent, width: 1.4),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            side: const WidgetStatePropertyAll(BorderSide(color: appBorder)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? const Color(0xffd7eeea)
                  : appSurface;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? appAccentStrong
                  : appTextMuted;
            }),
          ),
        ),
      ),
      home: LibraryPage(
        applicationService: dependencies.libraryPageApplicationService,
        fileSystem: dependencies.fileSystem,
        playerBackendFactory: dependencies.playerBackendFactory,
        mediaProbeBackendFactory: dependencies.mediaProbeBackendFactory,
      ),
    );
  }
}
