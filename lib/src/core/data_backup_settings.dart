import 'dart:convert';

import 'app_paths.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 视频依赖数据备份设置。
 *
 * 该设置独立于播放器解码配置；默认开启，旧版本没有设置文件时直接采用安全默认值。
 */
class DataBackupSettings {
  const DataBackupSettings({required this.enabled});

  /** 默认开启，保证升级用户不需要手工发现并启用数据保护。 */
  static const defaults = DataBackupSettings(enabled: true);

  /** 是否允许后台备份和扫描入库时的自动恢复。 */
  final bool enabled;

  DataBackupSettings copyWith({bool? enabled}) =>
      DataBackupSettings(enabled: enabled ?? this.enabled);

  Map<String, Object?> toJson() => <String, Object?>{'enabled': enabled};

  static DataBackupSettings fromJson(Map<String, Object?> json) {
    final value = json['enabled'];
    return DataBackupSettings(
      enabled: value is bool ? value : defaults.enabled,
    );
  }

  /** 损坏或缺失的设置文件不会阻塞媒体库启动。 */
  static Future<DataBackupSettings> load(AppPaths paths) async {
    try {
      final file = await paths.dataBackupSettingsFile();
      if (!await file.exists()) {
        return defaults;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        return fromJson(decoded);
      }
      if (decoded is Map) {
        return fromJson(decoded.cast<String, Object?>());
      }
    } catch (_) {
      return defaults;
    }
    return defaults;
  }

  /** 原子性由单文件 flush 保证；后台备份数据库拥有独立的事务游标。 */
  Future<void> save(AppPaths paths) async {
    final file = await paths.dataBackupSettingsFile();
    await file.writeAsString(jsonEncode(toJson()), flush: true);
  }
}
