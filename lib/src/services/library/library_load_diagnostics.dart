part of '../../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库启动阶段的一条耗时样本。
 *
 * [name] 使用稳定机器可读名称，便于真实大库基准跨版本比较；[itemCount] 只记录数量，
 * 不包含媒体路径、标题或用户标签内容。
 */
class LibraryLoadStageSample {
  const LibraryLoadStageSample({
    required this.name,
    required this.elapsed,
    this.itemCount,
  });

  /** 阶段稳定名称。 */
  final String name;

  /** 阶段独占耗时。 */
  final Duration elapsed;

  /** 阶段处理的行数、对象数或关系数。 */
  final int? itemCount;

  /** 转换为不包含用户媒体内容的基准摘要。 */
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'elapsedMs': double.parse(
          (elapsed.inMicroseconds / 1000).toStringAsFixed(3),
        ),
        if (itemCount != null) 'itemCount': itemCount,
      };
}

/**
 * 收集 SQLite hydration 与首屏列表生成的低开销分阶段诊断。
 *
 * 默认启动路径不创建本对象，因此不会常驻记录用户数据；真实大库基准显式传入后，
 * 每个阶段只保存耗时和数量。调用方应避免嵌套测量，以保证阶段可以直接计算占比。
 */
class LibraryLoadDiagnostics {
  /** 已完成的互斥阶段。 */
  final List<LibraryLoadStageSample> stages = <LibraryLoadStageSample>[];

  /** 记录由外部 Stopwatch 测得的阶段，供首帧 build/layout 等框架回调使用。 */
  void record(String name, Duration elapsed, {int? itemCount}) {
    stages.add(LibraryLoadStageSample(
      name: name,
      elapsed: elapsed,
      itemCount: itemCount,
    ));
  }

  /** 测量异步阶段，并在成功或失败时都记录已消耗时间。 */
  Future<T> measureAsync<T>(
    String name,
    Future<T> Function() action, {
    int? Function(T value)? itemCount,
  }) async {
    final watch = Stopwatch()..start();
    try {
      final value = await action();
      watch.stop();
      stages.add(LibraryLoadStageSample(
        name: name,
        elapsed: watch.elapsed,
        itemCount: itemCount?.call(value),
      ));
      return value;
    } catch (_) {
      watch.stop();
      stages.add(LibraryLoadStageSample(name: name, elapsed: watch.elapsed));
      rethrow;
    }
  }

  /** 测量同步对象构建、关系 hydration 或首屏列表计算。 */
  T measureSync<T>(
    String name,
    T Function() action, {
    int? Function(T value)? itemCount,
  }) {
    final watch = Stopwatch()..start();
    try {
      final value = action();
      watch.stop();
      stages.add(LibraryLoadStageSample(
        name: name,
        elapsed: watch.elapsed,
        itemCount: itemCount?.call(value),
      ));
      return value;
    } catch (_) {
      watch.stop();
      stages.add(LibraryLoadStageSample(name: name, elapsed: watch.elapsed));
      rethrow;
    }
  }

  /** 返回所有互斥阶段的累计耗时。 */
  Duration get measuredElapsed => stages.fold<Duration>(
        Duration.zero,
        (total, stage) => total + stage.elapsed,
      );

  /** 输出按阶段排列的安全基准数据。 */
  Map<String, Object?> toJson() => <String, Object?>{
        'measuredMs': double.parse(
          (measuredElapsed.inMicroseconds / 1000).toStringAsFixed(3),
        ),
        'stages': stages.map((stage) => stage.toJson()).toList(),
      };
}
