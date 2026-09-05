import 'dart:async';

// ignore_for_file: slash_for_doc_comments

/**
 * 显式 QA 会话的有界时序记录器。默认关闭，不持有 UI callback、timer 或用户文本。
 * 数值字段只传递代次、数量；导出由隔离测试负责，不在业务路径写文件。
 */
class LibraryPerformanceTrace {
  static final Object _parentKey = Object();
  static Stopwatch? _clock;
  static int _session = 0, _nextId = 0, _limit = 0, _dropped = 0;
  static int _wallStartUs = 0;
  static final List<Map<String, Object?>> _events = [];

  static bool get enabled => _clock != null;

  /** 新会话使旧异步 span 失效；容量用尽只计丢弃数，不改变业务结果。 */
  static void start({int maxEvents = 20000}) {
    if (maxEvents < 1) throw ArgumentError.value(maxEvents);
    _session++;
    _nextId = _dropped = 0;
    _limit = maxEvents;
    _events.clear();
    _wallStartUs = DateTime.now().microsecondsSinceEpoch;
    _clock = Stopwatch()..start();
  }

  static void stop() {
    _clock = null;
    _session++;
  }

  static LibraryPerformanceSpan? begin(String operation,
      {Map<String, num> fields = const {}}) {
    final clock = _clock;
    if (clock == null) return null;
    final parent = Zone.current[_parentKey] as LibraryPerformanceSpan?;
    // 旧异步链即使在新会话中创建子 span，也不能混入新会话或复用已重置的关联 ID。
    if (parent != null && parent._session != _session) return null;
    return LibraryPerformanceSpan._(_session, ++_nextId, parent?.id, operation,
        clock.elapsedMicroseconds, Map<String, num>.unmodifiable(fields));
  }

  /** Zone 仅传递观测关联 ID，不拦截异常或改变候选、事务的执行顺序。 */
  static T within<T>(LibraryPerformanceSpan? span, T Function() action) =>
      span == null
          ? action()
          : runZoned(action, zoneValues: {_parentKey: span});

  static Future<T> measure<T>(String operation, Future<T> Function() action,
      {Map<String, num> fields = const {}}) {
    final span = begin(operation, fields: fields);
    if (span == null) return action();
    return within(span, () async {
      try {
        final result = await action();
        span.finish('total');
        return result;
      } catch (_) {
        span.finish('total', outcome: 'error');
        rethrow;
      }
    });
  }

  static Map<String, Object?> snapshot() => {
        'wallStartUs': _wallStartUs,
        'dropped': _dropped,
        'events': [for (final event in _events) Map<String, Object?>.of(event)],
      };
}

/** 单个操作的连续分段；旧请求只落数值记录，绝不调用页面诊断或结果回调。 */
class LibraryPerformanceSpan {
  LibraryPerformanceSpan._(this._session, this.id, this.parentId,
      this.operation, this._startUs, this.fields);
  final int _session, id;
  final int? parentId;
  final String operation;
  final Map<String, num> fields;
  int _startUs;
  bool _finished = false;

  void step(String stage, {String outcome = 'ok'}) {
    final clock = LibraryPerformanceTrace._clock;
    if (_finished ||
        clock == null ||
        _session != LibraryPerformanceTrace._session) {
      return;
    }
    final endUs = clock.elapsedMicroseconds;
    if (LibraryPerformanceTrace._events.length <
        LibraryPerformanceTrace._limit) {
      LibraryPerformanceTrace._events.add({
        'id': id,
        'parentId': parentId,
        'operation': operation,
        'stage': stage,
        'startUs': _startUs,
        'endUs': endUs,
        'outcome': outcome,
        'fields': fields,
      });
    } else {
      LibraryPerformanceTrace._dropped++;
    }
    _startUs = endUs;
  }

  void finish(String stage, {String outcome = 'ok'}) {
    step(stage, outcome: outcome);
    _finished = true;
  }
}
