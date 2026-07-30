import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/services/player/player_texture_output_size_coordinator.dart';

void main() {
  test('稳定档位覆盖目标并在降档边界保留滞回', () {
    expect(
      PlayerTextureOutputSizeCoordinator.selectStableOutputSize(
        fittedPhysicalTarget: const Size(435, 245),
        currentSize: const Size(1920, 1080),
      ),
      const Size(640, 360),
    );
    expect(
      PlayerTextureOutputSizeCoordinator.selectStableOutputSize(
        fittedPhysicalTarget: const Size(765, 430),
        currentSize: const Size(1920, 1080),
      ),
      const Size(960, 540),
    );
    expect(
      PlayerTextureOutputSizeCoordinator.selectStableOutputSize(
        fittedPhysicalTarget: const Size(1427, 803),
        currentSize: const Size(1920, 1080),
      ),
      const Size(1600, 900),
    );
    expect(
      PlayerTextureOutputSizeCoordinator.selectStableOutputSize(
        fittedPhysicalTarget: const Size(1545, 869),
        currentSize: const Size(1920, 1080),
      ),
      const Size(1920, 1080),
    );
    expect(
      PlayerTextureOutputSizeCoordinator.selectStableOutputSize(
        fittedPhysicalTarget: const Size(870, 489),
        currentSize: const Size(1920, 1080),
      ),
      const Size(1920, 1080),
      reason: '目标靠近 960 档上沿时应保留当前档，避免阈值抖动',
    );
  });

  testWidgets('高频目标只下发最后档位并等待实际 Texture 确认', (tester) async {
    final requests = <Size>[];
    final states = <PlayerTextureOutputSizeSnapshot>[];
    final coordinator = PlayerTextureOutputSizeCoordinator(
      enabled: true,
      debounce: const Duration(milliseconds: 50),
      minimumRequestInterval: Duration.zero,
      confirmationTimeout: const Duration(milliseconds: 500),
      requestSize: (size) async => requests.add(size),
      onStateChanged: states.add,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordActualTextureSize(const Size(1920, 1080));

    coordinator.observeFittedPhysicalTarget(const Size(435, 245));
    coordinator.observeFittedPhysicalTarget(const Size(765, 430));
    await tester.pump(const Duration(milliseconds: 49));
    expect(requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(requests, const <Size>[Size(960, 540)]);

    // MethodChannel Future 已返回但 rect 尚未确认时，新目标只能排队，不能重建第二次。
    coordinator.observeFittedPhysicalTarget(const Size(435, 245));
    await tester.pump(const Duration(milliseconds: 200));
    expect(requests, hasLength(1));
    coordinator.recordActualTextureSize(const Size(960, 540));
    await tester.pump(const Duration(milliseconds: 50));
    expect(requests, const <Size>[Size(960, 540), Size(640, 360)]);
    coordinator.recordActualTextureSize(const Size(640, 360));

    expect(coordinator.snapshot.failureCount, 0);
    expect(coordinator.snapshot.requestCount, 2);
    expect(
        states.any((snapshot) => snapshot.state == 'waiting-texture'), isTrue);
  });

  testWidgets('关闭协调器不会下发尺寸且 dispose 取消去抖', (tester) async {
    final requests = <Size>[];
    final disabled = PlayerTextureOutputSizeCoordinator(
      enabled: false,
      debounce: const Duration(milliseconds: 10),
      requestSize: (size) async => requests.add(size),
    );
    disabled.recordActualTextureSize(const Size(1920, 1080));
    disabled.observeFittedPhysicalTarget(const Size(435, 245));
    await tester.pump(const Duration(milliseconds: 20));
    expect(requests, isEmpty);
    expect(disabled.snapshot.state, 'disabled');
    disabled.dispose();

    final disposed = PlayerTextureOutputSizeCoordinator(
      enabled: true,
      debounce: const Duration(milliseconds: 10),
      requestSize: (size) async => requests.add(size),
    );
    disposed.recordActualTextureSize(const Size(1920, 1080));
    disposed.observeFittedPhysicalTarget(const Size(435, 245));
    disposed.dispose();
    await tester.pump(const Duration(milliseconds: 20));
    expect(requests, isEmpty);
  });
}
