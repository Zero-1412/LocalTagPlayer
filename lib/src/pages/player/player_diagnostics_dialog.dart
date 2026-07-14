import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'player_dialog_content.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

/**
 * 播放诊断采样结果。
 *
 * 该快照保存一次采样中的 mpv 状态、缓存状态和推断字段，供诊断弹窗比较连续样本。
 */
class PlaybackDiagnosticsSnapshot {
  const PlaybackDiagnosticsSnapshot({
    required this.lines,
    required this.sampledAt,
    required this.wasPlaying,
    required this.wasBuffering,
    required this.progressMs,
    required this.expectedMs,
    required this.smooth,
    required this.avSync,
    required this.mistimedFrames,
    required this.voDelayedFrames,
    required this.voDroppedFrames,
    required this.decoderDroppedFrames,
    required this.totalDroppedFrames,
    required this.cacheDuration,
    required this.cacheBufferingState,
    required this.hwdecCurrent,
    required this.videoCodec,
    required this.videoWidth,
    required this.videoHeight,
    required this.seekLatencyMs,
    required this.detailsQueued,
    required this.frameDurationMs,
    required this.videoStalled,
    required this.audioStalled,
  });

  /** 展示给用户的诊断文本行。 */
  final List<String> lines;

  /** 本次采样完成时间。 */
  final DateTime sampledAt;

  /** 采样开始时播放器是否处于播放状态。 */
  final bool wasPlaying;

  /** 采样开始时播放器是否处于缓冲状态。 */
  final bool wasBuffering;

  /** 采样窗口内播放位置推进毫秒数。 */
  final int progressMs;

  /** 当前状态下期望推进的毫秒数。 */
  final int expectedMs;

  /** 根据推进量推断播放是否流畅。 */
  final bool smooth;

  /** mpv 报告的 AV 同步偏移。 */
  final double? avSync;

  /** mpv 报告的时序异常帧计数。 */
  final int? mistimedFrames;

  /** mpv 报告的视频输出延迟帧计数。 */
  final int? voDelayedFrames;

  /** mpv 报告的视频输出丢帧计数。 */
  final int? voDroppedFrames;

  /** mpv 报告的解码丢帧计数。 */
  final int? decoderDroppedFrames;

  /** mpv 报告的总丢帧计数。 */
  final int? totalDroppedFrames;

  /** mpv demuxer 缓存时长。 */
  final double? cacheDuration;

  /** mpv 缓存填充状态。 */
  final double? cacheBufferingState;

  /** mpv 当前真正启用的硬件解码后端。 */
  final String? hwdecCurrent;

  /** 当前视频编码与分辨率，用于解释硬解后端拒绝高规格样本的原因。 */
  final String? videoCodec;
  final int? videoWidth;
  final int? videoHeight;

  /** 最近一次 seek 从请求到播放器返回的耗时。 */
  final int? seekLatencyMs;

  /** 当前媒体详情服务尚未执行的任务数量。 */
  final int detailsQueued;

  /** 根据 mpv 估算视频 FPS 换算的单帧预算。 */
  final double? frameDurationMs;

  /** 持续采样是否确认视频帧超过阈值未推进。 */
  final bool videoStalled;

  /** 持续采样是否确认音频播放头超过阈值未推进。 */
  final bool audioStalled;
}

/**
 * 播放诊断弹窗。
 *
 * 弹窗只负责定时采样与展示，不修改播放状态；采样能力仍由 `PlayerPageState`
 * 提供，以便复用当前播放器实例和缓存服务。
 */
class PlaybackDiagnosticsDialog extends StatefulWidget {
  const PlaybackDiagnosticsDialog({
    required this.playerPage,
    required this.title,
  });

  /** 拥有播放器实例的页面状态。 */
  final PlayerPageState playerPage;

  /** 弹窗标题。 */
  final String title;

  @override
  State<PlaybackDiagnosticsDialog> createState() =>
      PlaybackDiagnosticsDialogState();
}

/**
 * 播放诊断弹窗状态。
 *
 * 负责在播放中持续刷新采样，暂停时停止定时器，避免弹窗关闭后保留异步回调。
 */
class PlaybackDiagnosticsDialogState extends State<PlaybackDiagnosticsDialog> {
  /** 下一次刷新定时器，弹窗销毁时必须取消。 */
  Timer? _nextRefreshTimer;

  /** 播放状态订阅，播放恢复时触发立即采样。 */
  StreamSubscription<bool>? _playingSubscription;

  /** 当前诊断快照。 */
  PlaybackDiagnosticsSnapshot? _snapshot;

  /** 上一次诊断快照，用于计算丢帧增量。 */
  PlaybackDiagnosticsSnapshot? _previousSnapshot;

  /** 当前弹窗生命周期内的连续采样次数。 */
  var _sampleCount = 0;

  /** 是否正在执行采样，防止定时器重入。 */
  var _isSampling = false;

  /** 最近一次采样错误。 */
  String? _error;

  /** 当前弹窗内诊断摘要是否已经成功复制，用于提供模态层内可见反馈。 */
  var _copied = false;

  @override
  void initState() {
    super.initState();
    _playingSubscription =
        widget.playerPage.playerBackend.playingChanges.listen((playing) {
      if (playing && !_isSampling) {
        _scheduleRefresh(Duration.zero);
      } else if (!playing) {
        _nextRefreshTimer?.cancel();
      }
    });
    _scheduleRefresh(Duration.zero);
  }

  @override
  void dispose() {
    _nextRefreshTimer?.cancel();
    unawaited(_playingSubscription?.cancel());
    super.dispose();
  }

  /**
   * 安排下一次诊断采样。
   *
   * 每次安排前先取消旧 timer，确保弹窗只保留一个待执行异步任务。
   */
  void _scheduleRefresh(Duration delay) {
    _nextRefreshTimer?.cancel();
    _nextRefreshTimer = Timer(delay, () {
      unawaited(_refresh());
    });
  }

  /**
   * 执行一次诊断采样并根据播放状态决定是否继续刷新。
   */
  Future<void> _refresh() async {
    if (_isSampling || !mounted) {
      return;
    }
    setState(() {
      _isSampling = true;
      _error = null;
    });
    try {
      final snapshot = await widget.playerPage.buildDiagnosticsSnapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _previousSnapshot = _snapshot;
        _snapshot = snapshot;
        _sampleCount++;
        _isSampling = false;
      });
      if (snapshot.wasPlaying) {
        _scheduleRefresh(const Duration(milliseconds: 250));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isSampling = false;
      });
      _scheduleRefresh(const Duration(seconds: 2));
    }
  }

  /**
   * 根据连续样本生成面向用户的诊断提示。
   */
  List<String> _analysisLines() {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return const ['诊断状态: 正在采集第一组样本'];
    }

    final reasons = <String>[];
    if (!snapshot.wasPlaying) {
      reasons.add('视频已暂停，诊断已停在最后一组样本');
    }
    if (snapshot.wasBuffering) {
      reasons.add('播放器正在缓冲，优先检查磁盘读取、文件源或缓存状态');
    }
    if (!snapshot.smooth && snapshot.wasPlaying && !snapshot.wasBuffering) {
      reasons.add('播放位置推进不足，可能存在渲染阻塞、解码跟不上或 UI 线程压力');
    }
    if (snapshot.videoStalled && !snapshot.audioStalled) {
      reasons.add('视频帧已停滞但音频播放头仍推进，确认存在画面冻结、声音继续');
    }
    if (snapshot.audioStalled && !snapshot.videoStalled) {
      reasons.add('音频播放头已停滞但视频帧仍推进，确认存在音频链路停顿');
    }
    if (snapshot.videoStalled && snapshot.audioStalled) {
      reasons.add('视频帧与音频播放头同时停滞，确认播放器整体停止推进');
    }
    if (snapshot.hwdecCurrent == 'no') {
      final resolution =
          snapshot.videoWidth == null || snapshot.videoHeight == null
              ? null
              : '${snapshot.videoWidth}x${snapshot.videoHeight}';
      reasons.add(
        resolution == null
            ? '实际硬解未启用，当前视频正在占用 CPU 软件解码'
            : '实际硬解未启用：${snapshot.videoCodec ?? '未知编码'} $resolution 已回退到 CPU 软件解码',
      );
    } else if (snapshot.hwdecCurrent == null) {
      reasons.add('暂时无法读取实际硬解状态，请在视频开始推进后再次采样');
    }
    if (snapshot.seekLatencyMs != null && snapshot.seekLatencyMs! > 500) {
      reasons.add('最近 seek 耗时 ${snapshot.seekLatencyMs} ms，随机拖动响应偏慢');
    }
    if (snapshot.detailsQueued > 0) {
      reasons.add('媒体详情仍有 ${snapshot.detailsQueued} 项排队，可能与播放争抢磁盘');
    }
    final decoderDelta = _delta(
        snapshot.decoderDroppedFrames, _previousSnapshot?.decoderDroppedFrames);
    if (decoderDelta != null && decoderDelta > 0) {
      reasons.add('解码丢帧增加 $decoderDelta，可能是 HEVC 解码压力或硬解回退');
    }
    final voDelta =
        _delta(snapshot.voDroppedFrames, _previousSnapshot?.voDroppedFrames);
    if (voDelta != null && voDelta > 0) {
      reasons.add('视频输出丢帧增加 $voDelta，可能是渲染/显示同步压力');
    }
    final delayedDelta =
        _delta(snapshot.voDelayedFrames, _previousSnapshot?.voDelayedFrames);
    if (delayedDelta != null && delayedDelta > 0) {
      reasons.add('视频输出延迟帧增加 $delayedDelta，显示链路可能跟不上');
    }
    final mistimedDelta =
        _delta(snapshot.mistimedFrames, _previousSnapshot?.mistimedFrames);
    if (mistimedDelta != null && mistimedDelta > 0) {
      reasons.add('时序异常帧增加 $mistimedDelta，可能是刷新率/同步策略不稳定');
    }
    final avSync = snapshot.avSync?.abs();
    if (avSync != null && avSync > 0.08) {
      reasons.add('AV 偏移 ${snapshot.avSync!.toStringAsFixed(3)} 秒，音画同步正在明显修正');
    }
    if (snapshot.cacheDuration != null && snapshot.cacheDuration! < 3) {
      reasons.add('缓存时长低于 3 秒，可能存在读盘或解复用供给不足');
    }
    if (snapshot.cacheBufferingState != null &&
        snapshot.cacheBufferingState! < 100) {
      reasons.add('缓存状态未满，播放器可能正在等待数据');
    }
    if (reasons.isEmpty) {
      reasons.add('未发现明显丢帧、缓冲或音画同步异常');
    }

    return <String>[
      '诊断状态: ${snapshot.wasPlaying ? '播放中持续采集' : '暂停，停止采集'}',
      '连续采样: $_sampleCount',
      '最近采样: ${_formatSampleTime(snapshot.sampledAt)}',
      '异常提示: ${reasons.join('；')}',
      '',
    ];
  }

  /**
   * 计算两个累计计数器的差值。
   */
  int? _delta(int? current, int? previous) {
    if (current == null || previous == null) {
      return null;
    }
    return current - previous;
  }

  /**
   * 格式化采样时间，只展示本地时分秒。
   */
  String _formatSampleTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  /**
   * 复制当前诊断摘要。
   *
   * `buildDiagnosticsSnapshot` 不写入本地路径，按钮文案也明确这一隐私边界；
   * 文件名用于定位当前媒体问题，但不会携带目录结构。
   */
  Future<void> _copySummary(List<String> lines) async {
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final analysisLines = _analysisLines();
    final detailLines = <String>[
      if (_error != null) '诊断错误: $_error',
      ...?_snapshot?.lines,
    ];
    final copyLines = <String>[...analysisLines, ...detailLines];
    final snapshot = _snapshot;
    return AlertDialog(
      key: const ValueKey('player.diagnostics.dialog'),
      title: Row(
        children: [
          const Icon(Icons.monitor_heart_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.title)),
          if (_isSampling)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: math.min(600, MediaQuery.sizeOf(context).height * 0.72),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PlayerDialogSectionCard(
                title: '实时状态',
                icon: Icons.speed_rounded,
                trailing: _DiagnosticsStatusBadge(
                  label: snapshot == null
                      ? '采集中'
                      : snapshot.wasPlaying
                          ? snapshot.smooth
                              ? '播放流畅'
                              : '需要关注'
                          : '已暂停',
                  healthy: snapshot?.smooth == true &&
                      snapshot?.wasBuffering == false,
                ),
                child: Column(
                  children: [
                    PlayerDialogInfoRow(
                      label: '连续采样',
                      value: '$_sampleCount 次',
                    ),
                    PlayerDialogInfoRow(
                      label: '播放推进',
                      value: snapshot == null
                          ? '等待首个样本'
                          : '${snapshot.progressMs} ms / 期望 ${snapshot.expectedMs} ms',
                    ),
                    PlayerDialogInfoRow(
                      label: '缓冲状态',
                      value: snapshot == null
                          ? '读取中'
                          : snapshot.wasBuffering
                              ? '正在缓冲'
                              : '正常',
                    ),
                    PlayerDialogInfoRow(
                      label: '最近采样',
                      value: snapshot == null
                          ? '—'
                          : _formatSampleTime(snapshot.sampledAt),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PlayerDialogSectionCard(
                title: '分析结论',
                icon: Icons.fact_check_outlined,
                child: SelectionArea(
                  child: Text(
                    analysisLines.where((line) => line.isNotEmpty).join('\n'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.55,
                        ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                PlayerDialogSectionCard(
                  title: '采样错误',
                  icon: Icons.warning_amber_rounded,
                  child: SelectableText(_error!),
                ),
              ],
              if (_snapshot != null) ...[
                const SizedBox(height: 12),
                PlayerDialogSectionCard(
                  title: '详细指标',
                  icon: Icons.data_object_rounded,
                  child: SelectionArea(
                    child: Text(
                      _snapshot!.lines.join('\n'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.5,
                            fontFamily: 'Consolas',
                          ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _snapshot == null
              ? null
              : () {
                  unawaited(_copySummary(copyLines));
                },
          icon: Icon(
            _copied ? Icons.check_rounded : Icons.copy_all_outlined,
          ),
          label: Text(
            _copied ? '已复制（不含路径）' : '复制诊断摘要（不含路径）',
          ),
        ),
        FilledButton.tonal(
          key: const ValueKey('player.diagnostics.close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/** 播放诊断卡片右上角的轻量状态徽标。 */
class _DiagnosticsStatusBadge extends StatelessWidget {
  const _DiagnosticsStatusBadge({
    required this.label,
    required this.healthy,
  });

  /** 面向用户的简短状态。 */
  final String label;

  /** 是否使用正常状态配色。 */
  final bool healthy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = healthy ? colors.tertiary : colors.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}
