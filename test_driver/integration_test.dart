import 'package:integration_test/integration_test_driver.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 接收桌面端集成测试结果，使同一测试可通过 `flutter drive --profile`
 * 建立 Windows Profile 回归基线。
 */
Future<void> main() => integrationDriver();
