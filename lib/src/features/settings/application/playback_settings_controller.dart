import '../../../core/playback_settings.dart';
import 'serial_settings_controller.dart';

// ignore_for_file: slash_for_doc_comments

/** 播放设置持久化命令。 */
typedef SavePlaybackSettings = Future<void> Function(
  PlaybackSettings settings,
);

/**
 * 普通播放设置的一致性 owner。
 *
 * controller 只拥有 [PlaybackSettings] 与串行持久化顺序，不持有 `BuildContext`、Route、
 * 备份状态、缓存任务或平台资源。每次更新会立即发布给 UI；写入失败时，只有该更新仍是
 * 最新可见版本才回滚，防止旧请求覆盖用户随后完成的新修改。
 */
class PlaybackSettingsController
    extends SerialSettingsController<PlaybackSettings> {
  PlaybackSettingsController({
    required PlaybackSettings initialSettings,
    required super.save,
  }) : super(initialValue: initialSettings);

  /** 当前已接受的播放设置快照。 */
  PlaybackSettings get settings => value;
}
