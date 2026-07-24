// ignore_for_file: slash_for_doc_comments

import '../../models/app_release.dart';

/**
 * 应用更新查询边界。
 *
 * 页面只依赖这一接口，GitHub API、包版本读取和网络超时留在具体实现中。
 */
abstract interface class AppUpdateService {
  /** 返回高于本地正式版本的 Release；已经最新时返回 null。 */
  Future<AppRelease?> checkForUpdate();
}

/**
 * 比较两个点分数字版本。
 *
 * 正式发布流程只接受 `X.Y.Z`，这里仍容忍段数不同，避免历史包无法升级。
 */
int compareAppVersions(String left, String right) {
  List<int> parse(String value) => value
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split('.')
      .map((part) => int.tryParse(part.split(RegExp(r'[-+]')).first) ?? 0)
      .toList(growable: false);

  final leftParts = parse(left);
  final rightParts = parse(right);
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < length; index += 1) {
    final leftPart = index < leftParts.length ? leftParts[index] : 0;
    final rightPart = index < rightParts.length ? rightParts[index] : 0;
    if (leftPart != rightPart) {
      return leftPart.compareTo(rightPart);
    }
  }
  return 0;
}
