import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_source_navigation_controller.dart';

void main() {
  LibrarySourceNavigationController createController() {
    return LibrarySourceNavigationController(
      normalizePath: (path) => path.trim(),
      pathKey: (path) => path.trim().toLowerCase(),
    );
  }

  test('初始来源为普通媒体库且没有本地路径', () {
    final controller = createController();

    expect(controller.mode, LibraryResultMode.library);
    expect(controller.localPath, isNull);
    expect(controller.canGoBack, isFalse);
  });

  test('标签动作只切回普通媒体库并保留旧的本地浏览历史', () {
    final controller = createController()
      ..showLocalRoot(r'D:\Media')
      ..openLocalFolder(r'D:\Media\Movies')
      ..showLibraryResults();

    expect(controller.mode, LibraryResultMode.library);
    expect(controller.localPath, r'D:\Media\Movies');
    expect(controller.canGoBack, isTrue);
  });

  test('媒体库主入口完整结束本地浏览会话', () {
    final controller = createController()
      ..showLocalRoot(r'D:\Media')
      ..openLocalFolder(r'D:\Media\Movies')
      ..resetToLibrary();

    expect(controller.mode, LibraryResultMode.library);
    expect(controller.localPath, isNull);
    expect(controller.canGoBack, isFalse);
  });

  test('最近播放和收藏来源都清空本地目录历史', () {
    final controller = createController()
      ..showLocalRoot(r'D:\Media')
      ..openLocalFolder(r'D:\Media\Movies')
      ..showRecent();

    expect(controller.mode, LibraryResultMode.recent);
    expect(controller.localPath, isNull);
    expect(controller.canGoBack, isFalse);

    controller
      ..showLocalRoot(r'E:\Clips')
      ..openLocalFolder(r'E:\Clips\Shorts')
      ..showFavorites();

    expect(controller.mode, LibraryResultMode.favorites);
    expect(controller.localPath, isNull);
    expect(controller.canGoBack, isFalse);
  });

  test('本地 root 与子目录形成确定的后进先出返回栈', () {
    final controller = createController()
      ..showLocalRoot(r'D:\Media')
      ..openLocalFolder(r'D:\Media\Movies')
      ..openLocalFolder(r'D:\Media\Movies\Drama');

    expect(controller.localPath, r'D:\Media\Movies\Drama');
    expect(controller.goBack(), isTrue);
    expect(controller.localPath, r'D:\Media\Movies');
    expect(controller.goBack(), isTrue);
    expect(controller.localPath, r'D:\Media');
    expect(controller.goBack(), isFalse);
    expect(controller.mode, LibraryResultMode.local);
  });

  test('移除当前 root 才退出本地浏览且路径比较忽略大小写', () {
    final controller = createController()..showLocalRoot(r'D:\Media');

    expect(controller.leaveRemovedRoot(r'E:\Other'), isFalse);
    expect(controller.mode, LibraryResultMode.local);
    expect(controller.leaveRemovedRoot(r'd:\media'), isTrue);
    expect(controller.mode, LibraryResultMode.library);
    expect(controller.localPath, isNull);
    expect(controller.canGoBack, isFalse);
  });
}
