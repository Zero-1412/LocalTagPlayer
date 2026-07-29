import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/player/application/player_shortcut_gate_controller.dart';

void main() {
  test('嵌套暂停只有全部结束后才允许快捷键', () {
    final gate = PlayerShortcutGateController();
    gate.beginSuspension();
    gate.beginSuspension();
    gate.endSuspension();
    expect(gate.isExplicitlySuspended, isTrue);
    gate.endSuspension();
    gate.endSuspension();
    expect(gate.isExplicitlySuspended, isFalse);
  });

  test('manual 标签编辑独立阻止快捷键和焦点恢复', () {
    final gate = PlayerShortcutGateController();
    gate.setManualTagEditorOpen(true);
    expect(
      gate.canHandle(
        settingsOpen: false,
        focusEditable: false,
        focusOnDifferentRoute: false,
        blockingOverlay: false,
      ),
      isFalse,
    );
    expect(
      gate.canRestoreFocus(
        settingsOpen: false,
        focusOnDifferentRoute: false,
      ),
      isFalse,
    );
  });

  test('输入焦点、其它 Route 和 Overlay 任一存在都会拒绝命令', () {
    final gate = PlayerShortcutGateController();
    bool canHandle({
      bool editable = false,
      bool differentRoute = false,
      bool overlay = false,
    }) =>
        gate.canHandle(
          settingsOpen: false,
          focusEditable: editable,
          focusOnDifferentRoute: differentRoute,
          blockingOverlay: overlay,
        );

    expect(canHandle(editable: true), isFalse);
    expect(canHandle(differentRoute: true), isFalse);
    expect(canHandle(overlay: true), isFalse);
    expect(canHandle(), isTrue);
  });

  test('焦点恢复只依赖显式暂停、设置和 Route 资格', () {
    final gate = PlayerShortcutGateController();
    expect(
      gate.canRestoreFocus(
        settingsOpen: false,
        focusOnDifferentRoute: false,
      ),
      isTrue,
    );
    expect(
      gate.canRestoreFocus(
        settingsOpen: true,
        focusOnDifferentRoute: false,
      ),
      isFalse,
    );
    expect(
      gate.canRestoreFocus(
        settingsOpen: false,
        focusOnDifferentRoute: true,
      ),
      isFalse,
    );
  });
}
