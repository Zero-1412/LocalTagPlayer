import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_selection_controller.dart';

void main() {
  test('多选 controller 只保存 stable videoId 并保护只读视图', () {
    final controller = LibrarySelectionController()..enter();

    controller.toggle('video-2');
    controller.toggle('video-1');

    expect(controller.selectionMode, isTrue);
    expect(controller.selectedVideoIds, <String>{'video-1', 'video-2'});
    expect(
      () => controller.selectedVideoIds.add('video-3'),
      throwsUnsupportedError,
    );
  });

  test('全选只消费当前可见 stable id 且再次触发会清空', () {
    final controller = LibrarySelectionController()..enter();
    const visible = <String>['video-2', 'video-1'];

    controller.toggleAll(visible);
    expect(controller.selectedVideoIds, visible.toSet());

    controller.toggleAll(visible.reversed);
    expect(controller.selectedVideoIds, isEmpty);
    expect(controller.selectionMode, isTrue);
  });

  test('删除成功项后保留失败选择并在空集合时退出', () {
    final controller = LibrarySelectionController()
      ..enter()
      ..toggleAll(const <String>['video-1', 'video-2']);

    controller.removeAll(const <String>['video-1']);
    expect(controller.selectionMode, isTrue);
    expect(controller.selectedVideoIds, <String>{'video-2'});

    controller.removeAll(const <String>['video-2']);
    expect(controller.selectionMode, isFalse);
    expect(controller.selectedVideoIds, isEmpty);
  });
}
