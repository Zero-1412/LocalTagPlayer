import '../core/app_paths.dart';
import '../features/update/domain/app_update_service.dart';
import '../platform/file_system_adapter.dart';
import '../platform/platform_interfaces.dart';
import '../services/library/library_page_application_service.dart';
import '../services/player/player_service.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 应用启动时一次性选择的平台依赖图。
 *
 * 页面只接收稳定接口或工厂；平台、播放器和媒体工具的具体实现必须由组合根选择。
 */
class LocalTagPlayerDependencies {
  const LocalTagPlayerDependencies({
    required this.fileSystem,
    required this.paths,
    required this.libraryPageApplicationService,
    required this.playerServiceFactory,
    required this.mediaProbeBackendFactory,
    required this.updateService,
  });

  /** 文件选择、目录枚举、文件写入和删除的平台边界。 */
  final FileSystemAdapter fileSystem;

  /** 应用私有文件路径策略。 */
  final AppPaths paths;

  /** 媒体库页面专用的应用用例边界。 */
  final LibraryPageApplicationService libraryPageApplicationService;

  /** 每个播放路由独占的应用层播放服务工厂。 */
  final PlayerServiceFactory playerServiceFactory;

  /** 每个探测队列独占的媒体探测后端工厂。 */
  final MediaProbeBackendFactory mediaProbeBackendFactory;

  /** 版本读取、正式更新查询和安装器校验执行边界。 */
  final AppUpdateService updateService;
}
