import '../core/app_paths.dart';
import '../platform/file_system_adapter.dart';
import '../platform/platform_interfaces.dart';
import '../services/library/library_application_facade.dart';
import '../services/library/library_load_diagnostics.dart';
import '../services/library/library_stress_control.dart';

// ignore_for_file: slash_for_doc_comments

/** 创建媒体库应用门面的组合根工厂。 */
typedef LibraryApplicationFactory = Future<LibraryApplicationFacade> Function({
  LibraryLoadDiagnostics? diagnostics,
});

/**
 * 应用启动时一次性选择的平台依赖图。
 *
 * 页面只接收稳定接口或工厂；平台、播放器和媒体工具的具体实现必须由组合根选择。
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

  /** 应用私有文件路径策略。 */
  final AppPaths paths;

  /** Dart Repository 与应用门面的创建入口。 */
  final LibraryApplicationFactory libraryApplicationFactory;

  /** 每个播放路由独占的播放器后端工厂。 */
  final PlayerBackendFactory playerBackendFactory;

  /** 每个探测队列独占的媒体探测后端工厂。 */
  final MediaProbeBackendFactory mediaProbeBackendFactory;

  /** 缩略图与兼容媒体探测共享的 FFmpeg 边界。 */
  final FFmpegBackend ffmpegBackend;

  /** 仅由组合根读取环境后生成的调试配置。 */
  final LibraryDebugOptions libraryDebugOptions;
}
