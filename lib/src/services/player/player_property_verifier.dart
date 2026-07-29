import '../../models/player_feature_apply_result.dart';
import '../../platform/platform_interfaces.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 为非滤镜类 mpv 属性提供有界写入与读回确认。
 *
 * 本工具不创建第二个播放器，也不持有后端；调用方仍负责决定失败后的安全回退。
 */
class PlayerPropertyVerifier {
  const PlayerPropertyVerifier._();

  /**
   * 提交 [properties] 并在最多 200ms 内等待后端状态收敛。
   *
   * [label] 必须是代码内固定用途；单项写入失败不会跳过读回，因为批量边界可能已经
   * 接受其它属性。只有全部目标一致时才返回已应用。
   */
  static Future<PlayerFeatureApplyResult> apply({
    required PlayerRuntimeAccess backend,
    required String label,
    required Map<String, String> properties,
  }) async {
    if (properties.isEmpty) {
      return PlayerFeatureApplyResult(
        label: label,
        requested: true,
        supported: true,
        applied: true,
        requestedPropertyCount: 0,
        verifiedPropertyCount: 0,
        mismatchedProperties: const <String>[],
        failureCode: null,
      );
    }

    var writeFailed = false;
    try {
      final batch = backend is PlayerPropertyBatchBoundary
          ? backend as PlayerPropertyBatchBoundary
          : null;
      if (batch != null) {
        await batch.setProperties(properties);
      } else {
        for (final entry in properties.entries) {
          await backend.setProperty(entry.key, entry.value);
        }
      }
    } catch (_) {
      writeFailed = true;
    }

    const maximumAttempts = 5;
    var mismatches = properties.keys.toList(growable: false);
    var readableCount = 0;
    for (var attempt = 0; attempt < maximumAttempts; attempt++) {
      final currentMismatches = <String>[];
      readableCount = 0;
      for (final entry in properties.entries) {
        String? actual;
        try {
          actual = _normalize(await backend.getProperty(entry.key));
        } catch (_) {
          // 原生读回异常属于本次功能应用失败，不能让可选增强打断正式播放。
          actual = null;
        }
        if (actual != null) {
          readableCount++;
        }
        if (!_matches(entry.key, entry.value.trim(), actual)) {
          currentMismatches.add(entry.key);
        }
      }
      mismatches = currentMismatches;
      if (mismatches.isEmpty || attempt == maximumAttempts - 1) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final supported = readableCount > 0;
    return PlayerFeatureApplyResult(
      label: label,
      requested: true,
      supported: supported,
      applied: supported && mismatches.isEmpty,
      requestedPropertyCount: properties.length,
      verifiedPropertyCount: properties.length - mismatches.length,
      mismatchedProperties: List<String>.unmodifiable(mismatches),
      failureCode: !supported
          ? 'property_unavailable'
          : mismatches.isNotEmpty
              ? writeFailed
                  ? 'property_write_or_readback_failed'
                  : 'property_readback_mismatch'
              : null,
    );
  }

  /** 把后端占位文本转换为不可用状态，避免把占位值冒充真实属性。 */
  static String? _normalize(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty || value == 'empty') return '';
    if (value == 'unavailable') return null;
    return value;
  }

  /** 比较 mpv 数值与 `vf` 规范化读回，其它属性使用精确匹配。 */
  static bool _matches(String property, String expected, String? actual) {
    if (actual == null) return false;
    if (property == 'vf') {
      return _normalizeVideoFilter(expected) == _normalizeVideoFilter(actual);
    }
    final expectedNumber = double.tryParse(expected);
    final actualNumber = double.tryParse(actual);
    if (expectedNumber != null && actualNumber != null) {
      return (expectedNumber - actualNumber).abs() < 0.000001;
    }
    return expected == actual;
  }

  /** 把 libmpv 的长度前缀和方括号形式归一为同一滤镜图文本。 */
  static String _normalizeVideoFilter(String value) {
    if (value.startsWith('lavfi=[') && value.endsWith(']')) {
      return value.substring(7, value.length - 1);
    }
    final match = RegExp(r'^lavfi=graph=%\d+%(.*)$').firstMatch(value);
    return match?.group(1) ?? value;
  }
}
