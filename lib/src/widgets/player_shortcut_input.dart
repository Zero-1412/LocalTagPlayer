import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/playback_settings.dart';
import 'app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 把 Flutter 键盘事件归一为设置文件使用的稳定快捷键标识。
 *
 * 只记录 Control、Alt、Shift 与一个非修饰键；修饰键顺序固定，避免同一组合键
 * 因按下顺序不同产生多个持久化值。
 */
String? playerShortcutIdFromEvent(KeyEvent event) {
  final baseKey = _shortcutBaseKeyId(event.logicalKey);
  if (baseKey == null) {
    return null;
  }
  final keyboard = HardwareKeyboard.instance;
  final parts = <String>[
    if (keyboard.isControlPressed) 'Control',
    if (keyboard.isAltPressed) 'Alt',
    if (keyboard.isShiftPressed) 'Shift',
    baseKey,
  ];
  final shortcut = parts.join('+');
  return PlaybackSettings.isSupportedShortcut(shortcut) ? shortcut : null;
}

/** 把跨平台逻辑键转换为不依赖本地化显示文本的基础标识。 */
String? _shortcutBaseKeyId(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.space) return 'Space';
  if (key == LogicalKeyboardKey.escape) return 'Escape';
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    return 'Enter';
  }
  if (key == LogicalKeyboardKey.tab) return 'Tab';
  if (key == LogicalKeyboardKey.backspace) return 'Backspace';
  if (key == LogicalKeyboardKey.delete) return 'Delete';
  if (key == LogicalKeyboardKey.insert) return 'Insert';
  if (key == LogicalKeyboardKey.home) return 'Home';
  if (key == LogicalKeyboardKey.end) return 'End';
  if (key == LogicalKeyboardKey.pageUp) return 'PageUp';
  if (key == LogicalKeyboardKey.pageDown) return 'PageDown';
  if (key == LogicalKeyboardKey.arrowLeft) return 'ArrowLeft';
  if (key == LogicalKeyboardKey.arrowRight) return 'ArrowRight';
  if (key == LogicalKeyboardKey.arrowUp) return 'ArrowUp';
  if (key == LogicalKeyboardKey.arrowDown) return 'ArrowDown';
  if (key == LogicalKeyboardKey.bracketLeft) return 'BracketLeft';
  if (key == LogicalKeyboardKey.bracketRight) return 'BracketRight';
  if (key == LogicalKeyboardKey.minus) return 'Minus';
  if (key == LogicalKeyboardKey.equal) return 'Equal';
  if (key == LogicalKeyboardKey.comma) return 'Comma';
  if (key == LogicalKeyboardKey.period) return 'Period';
  if (key == LogicalKeyboardKey.slash) return 'Slash';
  if (key == LogicalKeyboardKey.semicolon) return 'Semicolon';
  if (key == LogicalKeyboardKey.quote) return 'Quote';
  if (key == LogicalKeyboardKey.backquote) return 'Backquote';

  final label = key.keyLabel.toUpperCase();
  if (RegExp(r'^[A-Z0-9]$').hasMatch(label) ||
      RegExp(r'^F(?:[1-9]|1[0-2])$').hasMatch(label)) {
    return label;
  }
  return null;
}

/**
 * 非主路由共用的返回输入层。
 *
 * 鼠标侧键和用户配置的键盘快捷键只调用 [onBack]，不直接理解页面内部返回栈；
 * 设置二级页可因此继续由自身 PopScope 决定是回首页还是退出路由。
 */
class AppRouteBackInputRegion extends StatefulWidget {
  const AppRouteBackInputRegion({
    super.key,
    required this.shortcutProvider,
    required this.onBack,
    required this.child,
  });

  /** 每次按键时读取最新返回快捷键，避免设置页修改后仍使用进入路由时的旧快照。 */
  final String Function() shortcutProvider;

  /** 当前页面拥有的返回动作。 */
  final VoidCallback onBack;

  /** 接受统一返回输入的非主页面。 */
  final Widget child;

  @override
  State<AppRouteBackInputRegion> createState() =>
      _AppRouteBackInputRegionState();
}

class _AppRouteBackInputRegionState extends State<AppRouteBackInputRegion> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    super.dispose();
  }

  /** 文本输入期间不抢占可打印键和编辑键。 */
  bool _focusIsEditable() {
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.widget is EditableText ||
        context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /** 快捷键录制器拥有焦点时由它独占下一次按键，返回层不得提前消费。 */
  bool _focusIsShortcutRecorder() =>
      FocusManager.instance.primaryFocus?.debugLabel ==
      PlayerShortcutRecorder.focusDebugLabel;

  /**
   * 在当前路由内处理返回键，避免子控件释放焦点后整个页面失去键盘返回能力。
   */
  bool _handleGlobalKey(KeyEvent event) {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        event is! KeyDownEvent ||
        _focusIsEditable() ||
        _focusIsShortcutRecorder()) {
      return false;
    }
    if (playerShortcutIdFromEvent(event) == widget.shortcutProvider()) {
      widget.onBack();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        // “鼠标返回”统一指桌面鼠标侧键，不拦截普通左键的页面点击。
        if (event.buttons == kBackMouseButton) {
          widget.onBack();
        }
      },
      child: widget.child,
    );
  }
}

/**
 * 点击后直接监听下一次有效键盘输入的 Apple 式快捷键录制框。
 *
 * 冲突判断由父级持有，组件只负责焦点、输入反馈与语义；[onCaptured] 返回 false
 * 时保持录制态，让用户无需重新点击即可改按其它按键。
 */
class PlayerShortcutRecorder extends StatefulWidget {
  const PlayerShortcutRecorder({
    super.key,
    required this.action,
    required this.shortcut,
    required this.onCaptured,
    this.errorText,
  });

  /** 供页面级返回处理器识别录制焦点，避免按键在两个层级被重复消费。 */
  static const focusDebugLabel = 'playerShortcutRecorder';

  /** 当前录制的播放器动作。 */
  final PlayerShortcutAction action;

  /** 已持久化的快捷键标识。 */
  final String shortcut;

  /** 校验并接收新绑定；返回 true 表示可以结束录制。 */
  final bool Function(String shortcut) onCaptured;

  /** 父级冲突校验产生的就地错误文案。 */
  final String? errorText;

  @override
  State<PlayerShortcutRecorder> createState() => _PlayerShortcutRecorderState();
}

class _PlayerShortcutRecorderState extends State<PlayerShortcutRecorder> {
  final FocusNode _focusNode = FocusNode(
    debugLabel: PlayerShortcutRecorder.focusDebugLabel,
  );
  bool _recording = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /** 进入录制态并请求真实键盘焦点。 */
  void _startRecording() {
    setState(() => _recording = true);
    _focusNode.requestFocus();
  }

  /** 修饰键按下时继续等待；有效组合通过父级校验后才结束录制。 */
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_recording || event is! KeyDownEvent) {
      return _recording ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    final shortcut = playerShortcutIdFromEvent(event);
    if (shortcut == null) {
      return KeyEventResult.handled;
    }
    if (widget.onCaptured(shortcut)) {
      setState(() => _recording = false);
      _focusNode.unfocus();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.errorText;
    final borderColor = error != null
        ? playerDanger
        : _recording
            ? appAccentViolet
            : libraryBorder;
    return Semantics(
      button: true,
      label: '${PlaybackSettings.shortcutActionLabel(widget.action)}，'
          '${PlaybackSettings.shortcutKeyLabel(widget.shortcut)}，点击后录制新快捷键',
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKey,
        onFocusChange: (focused) {
          if (!focused && _recording && mounted) {
            setState(() => _recording = false);
          }
        },
        child: InkWell(
          key: ValueKey('settings.shortcut.${widget.action.name}'),
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: _startRecording,
          child: AnimatedContainer(
            duration: AppMotion.hover,
            curve: AppMotion.standardCurve,
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 10),
            decoration: BoxDecoration(
              color: _recording
                  ? appAccentViolet.withValues(alpha: 0.10)
                  : librarySurfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(
                  color: borderColor, width: error != null ? 1.5 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        PlaybackSettings.shortcutActionLabel(widget.action),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: _recording
                            ? appAccentViolet.withValues(alpha: 0.20)
                            : librarySurface,
                        borderRadius: BorderRadius.circular(AppRadius.capsule),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: Text(
                          _recording
                              ? '请按键…'
                              : PlaybackSettings.shortcutKeyLabel(
                                  widget.shortcut,
                                ),
                          style: TextStyle(
                            color: _recording ? libraryAccent : libraryText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    error,
                    key: ValueKey(
                      'settings.shortcut.${widget.action.name}.error',
                    ),
                    style: const TextStyle(
                      color: playerDanger,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
