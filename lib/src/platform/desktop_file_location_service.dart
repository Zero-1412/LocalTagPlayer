part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 桌面系统文件管理器定位边界。
 *
 * 播放器 UI 只传入媒体路径；Windows/macOS/Linux 的命令差异全部留在本平台层。
 */
class DesktopFileLocationService {
  const DesktopFileLocationService();

  /** 在系统文件管理器中打开并尽量选中指定文件。 */
  Future<void> reveal(String path) async {
    final file = File(path).absolute;
    if (!await file.exists()) {
      throw FileSystemException('文件不存在', file.path);
    }
    if (Platform.isWindows) {
      await Process.start('explorer.exe', <String>['/select,${file.path}']);
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('open', <String>['-R', file.path]);
      return;
    }
    if (Platform.isLinux) {
      await Process.start('xdg-open', <String>[file.parent.path]);
      return;
    }
    throw UnsupportedError('当前平台不支持打开文件位置');
  }
}
