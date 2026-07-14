import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/app_paths.dart';

// ignore_for_file: slash_for_doc_comments

/** SQLite 建库与连接维护回调。 */
typedef DatabaseSchemaCallback = Future<void> Function(Database database);

/**
 * 媒体库数据库平台边界。
 *
 * 实现只负责选择数据库文件、factory 与连接选项；schema、stable identity 和所有写入语义
 * 继续由 Dart repository 单写拥有。
 */
abstract interface class DatabaseProvider {
  /** 旧版 JSON 文件，仅供 Dart repository 做一次性兼容导入。 */
  Future<File> legacyLibraryFile();

  /** 打开媒体库 SQLite，并在同一 Dart isolate 中执行 schema 回调。 */
  Future<Database> openLibraryDatabase({
    required int version,
    required DatabaseSchemaCallback createSchema,
    required DatabaseSchemaCallback maintainSchema,
  });
}

/** 使用 sqflite factory 的桌面数据库实现。 */
class SqfliteDatabaseProvider implements DatabaseProvider {
  const SqfliteDatabaseProvider({
    required this.paths,
    required this.factory,
  });

  /** 由组合根注入的路径策略。 */
  final AppPaths paths;

  /** 由组合根完成初始化的 sqflite factory。 */
  final DatabaseFactory factory;

  @override
  Future<File> legacyLibraryFile() => paths.legacyLibraryFile();

  @override
  Future<Database> openLibraryDatabase({
    required int version,
    required DatabaseSchemaCallback createSchema,
    required DatabaseSchemaCallback maintainSchema,
  }) async {
    final file = await paths.libraryDatabaseFile();
    return factory.openDatabase(
      file.path,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (database, _) => createSchema(database),
        onOpen: (database) async {
          await maintainSchema(database);
          await database.execute('PRAGMA foreign_keys=ON');
          await database.execute('PRAGMA journal_mode=WAL');
          await database.execute('PRAGMA synchronous=NORMAL');
          await database.execute('PRAGMA temp_store=MEMORY');
          await database.execute('PRAGMA cache_size=-20000');
        },
      ),
    );
  }
}
