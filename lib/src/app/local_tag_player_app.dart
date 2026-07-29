// ignore_for_file: slash_for_doc_comments

import 'package:flutter/material.dart';

import '../composition/local_tag_player_dependencies.dart';
import '../features/update/presentation/app_update_prompt.dart';
import '../pages/library/library_page.dart';
import '../widgets/app_theme_tokens.dart';

/**
 * Local Tag Player 的 Flutter 应用壳。
 *
 * 应用壳只负责主题、无障碍环境和首个页面的组装；平台实现、数据库、播放器和
 * 更新客户端均由 bootstrap 组合根创建后通过 [dependencies] 注入。
 */
class LocalTagPlayerApp extends StatelessWidget {
  const LocalTagPlayerApp({
    super.key,
    required this.dependencies,
    this.debugTextScaleFactor,
  });

  /** 由 bootstrap 组合根创建的稳定依赖图。 */
  final LocalTagPlayerDependencies dependencies;

  /** Debug 真实窗口验收专用文字缩放倍率；Release 启动链路始终传入空值。 */
  final double? debugTextScaleFactor;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '本地标签播放器',
      debugShowCheckedModeBanner: false,
      theme: buildLocalTagPlayerTheme(),
      builder: (context, child) {
        final systemMediaQuery = MediaQuery.of(context);
        final effectiveMediaQuery = debugTextScaleFactor == null
            ? systemMediaQuery
            : systemMediaQuery.copyWith(
                textScaler: TextScaler.linear(debugTextScaleFactor!),
              );
        final accessibility = AppAccessibilityData.fromMediaQuery(
          effectiveMediaQuery,
        );
        return MediaQuery(
          data: effectiveMediaQuery,
          child: AppAccessibilityScope(
            data: accessibility,
            child: Theme(
              data: buildLocalTagPlayerTheme(
                highContrast: accessibility.highContrast,
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      home: AppUpdatePrompt(
        service: dependencies.updateService,
        child: LibraryPage(
          applicationService: dependencies.libraryPageApplicationService,
          fileSystem: dependencies.fileSystem,
          playerServiceFactory: dependencies.playerServiceFactory,
          mediaProbeBackendFactory: dependencies.mediaProbeBackendFactory,
          updateService: dependencies.updateService,
        ),
      ),
    );
  }
}
