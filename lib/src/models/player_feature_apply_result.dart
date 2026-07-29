// ignore_for_file: slash_for_doc_comments

/**
 * 一次可选播放增强属性提交的终态。
 *
 * 用户设置只表达请求；只有 [applied] 为 true 才表示后端属性已经逐项读回确认。
 * 结果不保存属性值或媒体路径，诊断只暴露稳定失败码和不一致属性名。
 */
class PlayerFeatureApplyResult {
  const PlayerFeatureApplyResult({
    required this.label,
    required this.requested,
    required this.supported,
    required this.applied,
    required this.requestedPropertyCount,
    required this.verifiedPropertyCount,
    required this.mismatchedProperties,
    required this.failureCode,
  });

  /** 尚未向当前媒体提交功能请求时使用的稳定初始状态。 */
  const PlayerFeatureApplyResult.notRequested(this.label)
      : requested = false,
        supported = true,
        applied = false,
        requestedPropertyCount = 0,
        verifiedPropertyCount = 0,
        mismatchedProperties = const <String>[],
        failureCode = null;

  /** 不支持对应属性边界时使用的显式终态。 */
  const PlayerFeatureApplyResult.unsupported(this.label)
      : requested = true,
        supported = false,
        applied = false,
        requestedPropertyCount = 0,
        verifiedPropertyCount = 0,
        mismatchedProperties = const <String>[],
        failureCode = 'property_unavailable';

  /** 用户已开启功能，但当前媒体或设备未通过运行门槛时使用的显式终态。 */
  const PlayerFeatureApplyResult.blocked(this.label)
      : requested = true,
        supported = true,
        applied = false,
        requestedPropertyCount = 0,
        verifiedPropertyCount = 0,
        mismatchedProperties = const <String>[],
        failureCode = 'capability_gate_not_met';

  /** 能力探测或属性协调自身失败、但不应把原始异常暴露到诊断时使用的终态。 */
  const PlayerFeatureApplyResult.failed(
    this.label, {
    this.failureCode = 'feature_apply_failed',
  })  : requested = true,
        supported = true,
        applied = false,
        requestedPropertyCount = 0,
        verifiedPropertyCount = 0,
        mismatchedProperties = const <String>[];

  /** 代码内固定的功能标签，不得包含媒体路径或用户输入。 */
  final String label;

  /** 当前会话是否已经提交过本功能的目标属性。 */
  final bool requested;

  /** 当前后端是否能读取至少一个受控属性。 */
  final bool supported;

  /** 所有目标属性是否已经读回确认。 */
  final bool applied;

  /** 本次目标属性数量。 */
  final int requestedPropertyCount;

  /** 与目标值一致的属性数量。 */
  final int verifiedPropertyCount;

  /** 最终仍未达到目标值的属性名，不包含属性值。 */
  final List<String> mismatchedProperties;

  /** 路径无关的稳定失败分类码。 */
  final String? failureCode;

  /** 面向诊断的终态说明，严格区分用户请求与后端确认。 */
  String get statusLabel {
    if (!requested) return '尚未请求';
    if (!supported) return '当前后端不支持';
    if (applied) return '属性已读回确认';
    if (failureCode == 'capability_gate_not_met') return '当前媒体或设备未通过能力门槛';
    return failureCode == null ? '未确认' : '应用失败：$failureCode';
  }
}
