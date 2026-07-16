import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/app_paths.dart';

// ignore_for_file: slash_for_doc_comments

/** 桌面窗口尺寸快照，只保存用户可感知的大小和最大化状态。 */
class DesktopWindowLayout {
  const DesktopWindowLayout({
    required this.width,
    required this.height,
    required this.maximized,
  });

  /** 上次非全屏窗口宽度。 */
  final double width;

  /** 上次非全屏窗口高度。 */
  final double height;

  /** 应用退出前是否处于最大化状态。 */
  final bool maximized;

  Map<String, Object?> toJson() => {
        'width': width,
        'height': height,
        'maximized': maximized,
      };

  static DesktopWindowLayout? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final width = (value['width'] as num?)?.toDouble();
    final height = (value['height'] as num?)?.toDouble();
    if (width == null || height == null || width < 900 || height < 600) {
      return null;
    }
    return DesktopWindowLayout(
      width: width,
      height: height,
      maximized: value['maximized'] == true,
    );
  }
}

/**
 * 桌面窗口状态边界。
 *
 * 页面只依赖 MediaQuery 做响应式布局；窗口读写集中在此服务，避免 Windows
 * 尺寸处理散落到播放器或媒体库 UI。高频 resize 使用延迟合并，避免持续写盘。
 */
class DesktopWindowStateService with WindowListener {
  DesktopWindowStateService(this._paths);

  /** 由组合根注入的窗口布局文件路径。 */
  final AppPaths _paths;

  Timer? _saveTimer;
  Size? _lastNormalSize;
  Future<void> Function()? _beforeClose;
  bool _closing = false;

  /** 注册应用级异步关闭动作；新媒体库实例会替换旧实例回调。 */
  void registerBeforeClose(Future<void> Function() handler) {
    _beforeClose = handler;
  }

  /** 初始化插件、恢复上次窗口大小并开始监听后续变化。 */
  Future<void> initialize() async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    await windowManager.ensureInitialized();
    final layout = await _load();
    final initialSize = Size(layout?.width ?? 1280, layout?.height ?? 720);
    _lastNormalSize = initialSize;
    final options = WindowOptions(
      size: initialSize,
      minimumSize: const Size(1000, 650),
      center: layout == null,
      title: 'local_tag_player',
    );
    // 桌面窗口默认会立即结束进程；拦截一次以等待备份 clean marker 和数据库关闭。
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      // Windows 只有在窗口已显示后才能可靠应用最大化状态。
      if (layout?.maximized == true) await windowManager.maximize();
      await windowManager.focus();
      // 首次启动也写入有效基线，后续即使用户只最大化也能恢复非最大化尺寸。
      _scheduleSave();
    });
  }

  Future<DesktopWindowLayout?> _load() async {
    try {
      final file = await _paths.windowLayoutFile();
      if (!await file.exists()) return null;
      return DesktopWindowLayout.fromJson(
          jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    try {
      // 全屏尺寸不是用户的普通窗口布局，退出全屏后再由 resize 事件保存恢复值。
      if (await windowManager.isFullScreen()) return;
      final maximized = await windowManager.isMaximized();
      if (!maximized) _lastNormalSize = await windowManager.getSize();
      final size = _lastNormalSize ?? await windowManager.getSize();
      final layout = DesktopWindowLayout(
        width: size.width,
        height: size.height,
        maximized: maximized,
      );
      final file = await _paths.windowLayoutFile();
      await file.writeAsString(jsonEncode(layout.toJson()), flush: true);
    } catch (_) {
      // 窗口状态属于体验增强，保存失败不能阻止应用退出或播放。
    }
  }

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMaximize() => _scheduleSave();

  @override
  void onWindowUnmaximize() => _scheduleSave();

  @override
  void onWindowClose() => unawaited(_handleWindowClose());

  /** 保存窗口状态并等待数据服务关闭，再显式销毁桌面窗口。 */
  Future<void> _handleWindowClose() async {
    if (_closing) {
      return;
    }
    _closing = true;
    _saveTimer?.cancel();
    try {
      await _save();
      await _beforeClose?.call();
    } finally {
      // clean marker 失败会在下次启动保守全量核对，但不能让窗口永久无法关闭。
      await windowManager.destroy();
    }
  }
}
