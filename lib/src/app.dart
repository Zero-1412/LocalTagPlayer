// ignore_for_file: slash_for_doc_comments

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_paths.dart';
import 'core/layout_size.dart';
import 'core/playback_settings.dart';
import 'core/tag_rules.dart';
import 'models/library_scan_models.dart';
import 'models/media_details.dart';
import 'models/platform_models.dart';
import 'models/video_item.dart';
import 'platform/desktop_file_system_adapter.dart';
import 'platform/database_provider.dart';
import 'platform/file_system_adapter.dart';
import 'platform/platform_interfaces.dart';
import 'repositories/repository_interfaces.dart';
import 'services/library/library_application_facade.dart';
import 'services/library/library_count_refresh_coordinator.dart';
import 'services/library/library_load_diagnostics.dart';
import 'services/library/library_scan_backend.dart';
import 'services/library/library_scan_service.dart';
import 'services/library/library_video_persistence.dart';
import 'services/media/external_media_tools.dart';
import 'services/media/media_probe_backend.dart';
import 'services/media/media_details_service.dart';
import 'services/player/playback_snapshot_write_queue.dart';
import 'services/player/player_hardware_acceleration.dart';
import 'services/player/player_hardware_compatibility.dart';
import 'services/player/player_memory_diagnostics.dart';
import 'services/window/desktop_window_state_service.dart';

export 'core/tag_rules.dart';
export 'core/app_paths.dart';
export 'core/layout_size.dart';
export 'core/playback_settings.dart';
export 'models/external_media_tools_state.dart';
export 'models/media_details.dart';
export 'models/library_scan_models.dart';
export 'models/platform_models.dart';
export 'models/video_item.dart';
export 'platform/desktop_file_system_adapter.dart';
export 'platform/database_provider.dart';
export 'platform/file_system_adapter.dart';
export 'platform/platform_interfaces.dart';
export 'repositories/repository_interfaces.dart';
export 'services/library/library_application_facade.dart';
export 'services/library/library_count_refresh_coordinator.dart';
export 'services/library/library_load_diagnostics.dart';
export 'services/library/library_scan_backend.dart';
export 'services/library/library_scan_service.dart';
export 'services/library/library_video_persistence.dart';
export 'services/media/external_media_tools.dart';
export 'services/media/media_probe_backend.dart';
export 'services/media/media_details_service.dart';
export 'services/player/playback_snapshot_write_queue.dart';
export 'services/player/player_hardware_acceleration.dart';
export 'services/player/player_hardware_compatibility.dart';
export 'services/player/player_memory_diagnostics.dart';
export 'services/window/desktop_window_state_service.dart';

// 媒体库服务集中管理扫描、持久化、诊断与内存状态协调。
part 'services/library/library_metadata_persistence.dart';
part 'services/library/library_stress_control.dart';
part 'services/library/library_scan_ui_diagnostics.dart';
part 'services/library/library_card_ui_diagnostics.dart';
part 'services/library/library_scan_coordinator.dart';
part 'services/library/library_tag_persistence.dart';
part 'services/library/library_tag_maintenance.dart';
part 'services/library/library_store.dart';

// 细分服务目录只表达职责归属，不改变现有平台边界或业务调用顺序。
part 'services/media/thumbnail_service.dart';
part 'services/player/media_kit_player_backend.dart';
part 'services/player/windows_native_player_backend.dart';
part 'services/relink/bulk_path_relink_service.dart';
part 'services/tags/tag_query_service.dart';

// 页面和组件按用户工作流分组，避免不同功能在一级目录中继续混放。
part 'pages/library/library_page_helpers.dart';
part 'pages/library/library_page.dart';
part 'pages/library/missing_relink_page.dart';
part 'pages/tags/tag_manager_page.dart';
part 'pages/player/player_context_panel.dart';
part 'pages/player/player_dialog_content.dart';
part 'pages/player/player_delete_dialog.dart';
part 'pages/player/player_hardware_decode_warning_dialog.dart';
part 'pages/player/player_diagnostics_dialog.dart';
part 'pages/player/player_open_request_controller.dart';
part 'pages/player/player_resume_dialog.dart';
part 'pages/player/player_open_failure_panel.dart';
part 'pages/player/player_playback_mode.dart';
part 'pages/player/player_playback_controller.dart';
part 'pages/player/player_queue_sidebar.dart';
part 'pages/player/player_page.dart';
part 'widgets/library/library_smoke_keys.dart';
part 'widgets/library/library_sort_control.dart';
part 'widgets/library/library_tag_discovery_panel.dart';
part 'widgets/library/library_local_view.dart';
part 'widgets/library/library_video_results.dart';
part 'widgets/library/library_widgets.dart';

const _appAccent = Color(0xff0f766e);
const _appAccentStrong = Color(0xff0b5d57);
const _appAccentViolet = Color(0xff6d5dfc);
const _appShell = Color(0xff111827);
const _appBackground = Color(0xfff4f7fb);
const _appSurface = Color(0xfffbfdfc);
const _appSurfaceAlt = Color(0xfff4f8f7);
const _appPanel = Color(0xffffffff);
const _appBorder = Color(0xffdce4ee);
const _appTextMuted = Color(0xff62706d);
const _appText = Color(0xff17202e);
const _appSoftShadow = [
  BoxShadow(
    color: Color(0x140f172a),
    blurRadius: 24,
    offset: Offset(0, 12),
  ),
];
const _motionDuration = Duration(milliseconds: 180);
const _motionCurve = Curves.easeOutCubic;
const _thumbnailWidth = 384;
const _thumbnailPlayerTimeout = Duration(seconds: 8);

/** 创建媒体库应用门面的组合根工厂。 */
typedef LibraryApplicationFactory = Future<LibraryApplicationFacade> Function({
  LibraryLoadDiagnostics? diagnostics,
});

/** 创建独立媒体探测会话后端的组合根工厂。 */
typedef MediaProbeBackendFactory = MediaProbeBackend Function();

/**
 * 应用启动时一次性选择的具体平台依赖。
 *
 * 页面只接收稳定接口或工厂；Windows/Rust/C++/media_kit 的选择不得再次散落到
 * Widget 生命周期中。
 */
class LocalTagPlayerDependencies {
  const LocalTagPlayerDependencies({
    required this.fileSystem,
    required this.paths,
    required this.libraryApplicationFactory,
    required this.playerBackendFactory,
    required this.mediaProbeBackendFactory,
    required this.ffmpegBackend,
    required this.libraryDebugOptions,
  });

  /** 文件选择、目录枚举、文件写入和删除的平台边界。 */
  final FileSystemAdapter fileSystem;

  /** 应用私有文件路径策略；页面只转交给负责持久化的应用服务。 */
  final AppPaths paths;

  /** Dart Repository 与应用门面的创建入口。 */
  final LibraryApplicationFactory libraryApplicationFactory;

  /** 每个播放路由独占的播放器后端工厂。 */
  final PlayerBackendFactory playerBackendFactory;

  /** 每个探测队列独占的媒体探测后端工厂。 */
  final MediaProbeBackendFactory mediaProbeBackendFactory;

  /** 缩略图与兼容媒体探测共享的实例级 FFmpeg 边界。 */
  final FFmpegBackend ffmpegBackend;

  /** 仅由组合根读取环境后生成的 debug 配置。 */
  final LibraryDebugOptions libraryDebugOptions;
}

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
  return LocalTagPlayerDependencies(
    fileSystem: Platform.isMacOS
        ? const MacOsFileSystemAdapter()
        : Platform.isLinux
            ? const LinuxFileSystemAdapter()
            : const DesktopFileSystemAdapter(),
    paths: paths,
    libraryApplicationFactory: ({diagnostics}) async {
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
    },
    playerBackendFactory: _createPlayerBackend,
    mediaProbeBackendFactory: () => createMediaProbeBackend(ffmpegBackend),
    ffmpegBackend: ffmpegBackend,
    libraryDebugOptions: LibraryDebugOptions(
      stressRoot: kDebugMode
          ? Platform.environment['LOCAL_TAG_PLAYER_LIBRARY_STRESS_ROOT']?.trim()
          : null,
      startupDiagnosticsPath: kDebugMode
          ? p.join(
              Directory.systemTemp.path,
              'local_tag_player_startup_diagnostics.json',
            )
          : null,
    ),
  );
}

Route<T> _smoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: _motionCurve);
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
        scaffoldBackgroundColor: _appBackground,
        cardTheme: const CardThemeData(
          elevation: 0,
          color: _appSurface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: _appBorder),
          ),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: _appSurface,
          foregroundColor: Color(0xff1d2725),
          centerTitle: false,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: _appSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: _appBorder),
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
          color: _appSurface,
          surfaceTintColor: Colors.transparent,
          textStyle: const TextStyle(color: _appText, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: _appBorder),
          ),
        ),
        menuTheme: MenuThemeData(
          style: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(_appSurface),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: _appBorder),
              ),
            ),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: _appSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: _appShell,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          behavior: SnackBarBehavior.floating,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _appAccent,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(0, 40),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _appAccentStrong,
            side: const BorderSide(color: _appBorder),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(0, 40),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: _appAccentStrong,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _appSurfaceAlt,
          selectedColor: const Color(0xffd7eeea),
          disabledColor: const Color(0xffe7ecea),
          side: const BorderSide(color: _appBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          labelStyle: const TextStyle(
              color: Color(0xff20302d), fontWeight: FontWeight.w600),
          secondaryLabelStyle: const TextStyle(
              color: _appAccentStrong, fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          showCheckmark: false,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: _appSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: _appBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: _appBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: _appAccent, width: 1.4),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            side: const WidgetStatePropertyAll(BorderSide(color: _appBorder)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? const Color(0xffd7eeea)
                  : _appSurface;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? _appAccentStrong
                  : _appTextMuted;
            }),
          ),
        ),
      ),
      home: LibraryPage(dependencies: dependencies),
    );
  }
}
