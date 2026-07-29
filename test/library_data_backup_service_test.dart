import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/models/data_backup_models.dart';
import 'package:local_tag_player/src/services/library/library_data_backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ignore_for_file: slash_for_doc_comments

void main() {
  DynamicLibrary.open(
    File(
      'windows${Platform.pathSeparator}tools${Platform.pathSeparator}sqlite${Platform.pathSeparator}sqlite3.dll',
    ).absolute.path,
  );
  sqfliteFfiInit();

  test('主库已提交后的备份入队失败只发布诊断状态', () async {
    final directory = await Directory.systemTemp.createTemp(
      'local_tag_player_backup_test_',
    );
    final source = await databaseFactoryFfi.openDatabase(
      '${directory.path}${Platform.pathSeparator}source.db',
    );
    final backup = await databaseFactoryFfi.openDatabase(
      '${directory.path}${Platform.pathSeparator}backup.db',
    );
    final service = await LibraryDataBackupService.create(
      sourceDatabase: source,
      backupDatabase: backup,
      enabled: true,
    );

    // 模拟主库已经成功、独立备份库随后不可写；该错误不能反向触发业务模型回滚。
    await backup.close();
    await service.enqueueVideoBestEffort('video-1');

    expect(service.status.phase, DataBackupPhase.failed);
    expect(service.status.error, isNotEmpty);

    await source.close();
    await directory.delete(recursive: true);
  });
}
