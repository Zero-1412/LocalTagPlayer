// ignore_for_file: slash_for_doc_comments

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app/local_tag_player_app.dart';
import '../core/app_paths.dart';
import '../core/playback_settings.dart';
import '../features/update/data/github_release_update_service.dart';
import '../platform/database_provider.dart';
import '../platform/desktop_file_system_adapter.dart';
import '../platform/platform_interfaces.dart';
import '../services/library/library_application_facade.dart';
import '../services/library/library_load_diagnostics.dart';
import '../services/library/library_page_application_service.dart';
import '../services/library/library_scan_backend.dart';
import '../services/library/library_store.dart';
import '../services/library/library_stress_control.dart';
import '../services/media/external_media_tools.dart';
import '../services/media/media_probe_backend.dart';
import '../services/player/media_kit_initializer.dart';
import '../services/player/media_kit_player_backend.dart';
import '../services/player/player_backend_selection.dart';
import '../services/player/player_service.dart';
import '../services/player/windows_native_player_backend.dart';
import '../services/window/desktop_window_state_service.dart';
import 'local_tag_player_dependencies.dart';

/** 组合根内选择播放器具体实现，页面不读取环境变量或平台类型。 */
PlayerBackend _createPlayerBackend({
  required String hwdec,
  required bool enableHardwareAcceleration,
  required PlayerRendererPreference rendererPreference,
}) {
  final selection = resolvePlayerBackendSelection(
    isWindows: Platform.isWindows,
    hardwareDecodingEnabled: enableHardwareAcceleration,
    rendererPreference: rendererPreference,
    environmentOverride: Platform.environment['LOCAL_TAG_PLAYER_BACKEND'],
  );
  switch (selection) {
    case PlayerBackendSelection.windowsNativeMpv:
      return WindowsNativePlayerBackend(mode: 'mpv');
    case PlayerBackendSelection.windowsNativeHwnd:
      return WindowsNativePlayerBackend(mode: 'hwnd');
    case PlayerBackendSelection.windowsNativeStub:
      return WindowsNativePlayerBackend(mode: 'stub');
    case PlayerBackendSelection.mediaKit:
      break;
  }
  // 首帧后的统一预热通常已完成；这里保留幂等门禁，覆盖立即进入播放器和失败重试。
  defaultMediaKitInitializer.ensureInitialized();
  return MediaKitPlayerBackend(
    hwdec: hwdec,
    enableHardwareAcceleration: enableHardwareAcceleration,
  );
}

/**
 * 创建 Flutter 页面唯一可见的播放应用服务。
 *
 * 后端选择先在组合根完成，再由服务独占具体实例；页面不会接触 MediaKit、
 * Windows libmpv、D3D11 或 HWND 的构造和类型判断。
 */
PlayerService _createPlayerService({
  required String hwdec,
  required bool enableHardwareAcceleration,
  required PlayerRendererPreference rendererPreference,
}) =>
    PlayerService(
      backend: _createPlayerBackend(
        hwdec: hwdec,
        enableHardwareAcceleration: enableHardwareAcceleration,
        rendererPreference: rendererPreference,
      ),
    );

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
      queryRepository: repository,
      commandRepository: repository,
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
    playerServiceFactory: _createPlayerService,
    mediaProbeBackendFactory: mediaProbeBackendFactory,
    updateService: GitHubReleaseUpdateService(paths: paths),
  );
}

/** 初始化桌面基础设施并启动 Flutter 应用壳。 */
Future<void> bootstrapLocalTagPlayer() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final paths = AppPaths();
  final windowStateService = DesktopWindowStateService(paths);
  final dependencies = createLocalTagPlayerDependencies(
    appPaths: paths,
    registerBeforeWindowClose: windowStateService.registerBeforeClose,
  );
  await windowStateService.initialize();
  runApp(
    LocalTagPlayerApp(
      dependencies: dependencies,
      debugTextScaleFactor: debugTextScaleFactorFromEnvironment(),
    ),
  );
  // 窗口首帧可见后再预热 libmpv，同时避免首次悬停和首播冷启动。
  scheduleDefaultMediaKitWarmupAfterFirstFrame();
}

/**
 * 读取真实窗口无障碍验收使用的文字缩放倍率。
 *
 * 该入口只在 Debug 构建生效，并仅接受设计基线要求的 100%/125%/150%。
 */
double? debugTextScaleFactorFromEnvironment({
  Map<String, String>? environment,
}) {
  if (!kDebugMode) {
    return null;
  }
  final raw =
      (environment ?? Platform.environment)['LOCAL_TAG_PLAYER_QA_TEXT_SCALE']
          ?.trim();
  final parsed = double.tryParse(raw ?? '');
  if (parsed == 1 || parsed == 1.25 || parsed == 1.5) {
    return parsed;
  }
  return null;
}
