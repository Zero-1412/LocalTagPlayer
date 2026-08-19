import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 真实 PlayerPage 输入到桌面像素 QA 的匿名语义回执。
 *
 * 只有 Windows Debug 且两个显式环境变量齐全时才写入；正式运行、用户媒体路径、视频
 * ID、拖动目标时间与播放设置均不参与。外部 Win32 探针据此区分“实际完整 Slider 拖动”
 * 与底部隐藏点击条或其它控件的偶然命中，不能仅凭画面像素变动猜测输入来源。
 */
class PlayerInputQaEvidence {
  PlayerInputQaEvidence._();

  static const _enabledEnvironment = 'LOCAL_TAG_PLAYER_PLAYERPAGE_INPUT_QA';
  static const _outputEnvironment = 'LOCAL_TAG_PLAYER_PIXEL_OUTPUT';
  static const _segmentTraceEnvironment =
      'LOCAL_TAG_PLAYER_SEEK_SEGMENT_TRACE_QA';

  /** Debug-only 连续扫描分段采样开关；正式页面不因诊断读取属性。 */
  static bool get seekSegmentTraceEnabled =>
      kDebugMode &&
      Platform.isWindows &&
      Platform.environment[_segmentTraceEnvironment] == '1';

  static File? get _output {
    if (!kDebugMode ||
        !Platform.isWindows ||
        Platform.environment[_enabledEnvironment] != '1') {
      return null;
    }
    final directory = Platform.environment[_outputEnvironment]?.trim();
    if (directory == null || directory.isEmpty) return null;
    final root = Directory(directory);
    if (!root.existsSync()) return null;
    return File(
        '${root.path}${Platform.pathSeparator}player-input-events.jsonl');
  }

  /** 显式 QA 回执是否可写；仅供诊断观测点决定是否挂载，不改变正式输入路由。 */
  static bool get qaEnabled => _output != null;

  /** 完整 Slider 接到真实 PointerDown 后记录；不保存指针坐标或时间目标。 */
  static void progressSliderDragStarted() => _append('progress_slider_start');

  /** 完整 Slider 接到真实 PointerUp 并提交最终定位时记录。 */
  static void progressSliderDragCommitted() =>
      _append('progress_slider_committed');

  /** 两阶段 QA 已向原生后端提交快速关键帧请求；不记录位置或媒体身份。 */
  static void progressPreviewSeekSubmitted() =>
      _append('progress_preview_seek_submitted');

  /** 两阶段 QA 的精确落点与最终帧门禁均已完成。 */
  static void progressExactSeekConfirmed() =>
      _append('progress_exact_seek_confirmed');

  /** Debug-only 记录 PlayerPage FocusNode 的焦点状态，不记录控件、窗口或媒体信息。 */
  static void playerFocusStateChanged(bool hasFocus) {
    _append(
      'player_focus_state',
      fields: <String, Object?>{
        'hasFocus': hasFocus,
      },
    );
  }

  /** Debug-only 记录 Flutter HardwareKeyboard 全局路由是否收到键事件。 */
  static void playerGlobalKeyboardEventObserved({String phase = 'unknown'}) {
    final safePhase = const <String>{
      'down',
      'repeat',
      'up',
      'unknown',
    }.contains(phase)
        ? phase
        : 'unknown';
    _append(
      'player_global_keyboard_event',
      fields: <String, Object?>{
        'phase': safePhase,
      },
    );
  }

  /**
   * PlayerPage Focus 链实际收到可参与快捷键处理的物理键盘事件。
   *
   * action 只允许固定的播放器语义枚举，phase 只允许 down/repeat/up；不记录原始
   * 按键值、修饰键、媒体路径或位置目标。这样桌面侧车可以确认实体长按是否真的进入
   * Flutter 的 KeyRepeat 分支，而不是把一串 native WM_KEYDOWN 误读成连续扫描。
   */
  static void playerKeyboardEventReceived({
    String action = 'other',
    String phase = 'unknown',
  }) {
    final safeAction = const <String>{
      'forward',
      'backward',
      'other',
    }.contains(action)
        ? action
        : 'other';
    final safePhase = const <String>{
      'down',
      'repeat',
      'up',
      'unknown',
    }.contains(phase)
        ? phase
        : 'unknown';
    _append(
      'player_keyboard_event',
      fields: <String, Object?>{
        'action': safeAction,
        'phase': safePhase,
      },
    );
  }

  static void _append(
    String event, {
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    final output = _output;
    if (output == null) return;
    try {
      final payload = <String, Object?>{
        'event': event,
        ...fields,
        'utcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
      };
      output.writeAsStringSync(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // QA 回执不可影响正式手势和定位；不可写时由外部探针明确拒绝该测试样本。
    }
  }
}
