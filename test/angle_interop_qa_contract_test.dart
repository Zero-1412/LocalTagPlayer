import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 约束新版 ANGLE 互操作实验只能通过显式环境变量启用。
 *
 * 该测试不执行 GPU 代码；它保护正式播放器的默认解码路径、MediaKit 插件 ABI，
 * 并防止后续维护把实验性的 D3D11VA 选项静默变成生产默认值。
 */
void main() {
  test('ANGLE 互操作实验保持显式开关且不注入画质滤镜', () {
    final cmake =
        File('windows/native_player/CMakeLists.txt').readAsStringSync();

    expect(cmake, contains('LOCAL_TAG_PLAYER_ANGLE_INTEROP_QA'));
    expect(
      cmake,
      contains('GetEnvironmentVariableA('),
    );
    expect(cmake, contains('"gpu-hwdec-interop", "d3d11va"'));
    expect(cmake, contains('ltp-angle-interop-qa: EGL vendor='));
    expect(cmake, contains('LOCAL_TAG_PLAYER_ANGLE_QA_ROOT'));
    expect(
      cmake,
      contains('set(LTP_ANGLE_RUNTIME_ROOT "\${LTP_NATIVE_DEPS}/angle")'),
    );
    expect(
      cmake,
      contains('"\${LTP_ANGLE_RUNTIME_ROOT}/libEGL.dll"'),
    );
    expect(
      cmake,
      contains('"\${LTP_ANGLE_RUNTIME_ROOT}/libGLESv2.dll"'),
    );
    expect(cmake, contains('LOCAL_TAG_PLAYER_MPV_QA_DLL'));
    expect(
      cmake,
      contains(
        'set(LTP_MPV_RUNTIME_DLL "\${LTP_NATIVE_DEPS}/mpv/libmpv-2.dll")',
      ),
    );
    expect(cmake, contains('"\${LTP_MPV_RUNTIME_DLL}"'));

    final qaPatchStart = cmake.indexOf('set(LTP_VIDEO_OUTPUT_INTEROP_PATCH');
    final qaPatchEnd = cmake.indexOf(
      'set(LTP_VIDEO_OUTPUT_ANGLE_LOG_MARKER',
      qaPatchStart,
    );
    expect(qaPatchStart, greaterThanOrEqualTo(0));
    expect(qaPatchEnd, greaterThan(qaPatchStart));
    final qaPatch = cmake.substring(qaPatchStart, qaPatchEnd);

    expect(qaPatch, isNot(contains('d3d11vpp=')));
    expect(qaPatch, isNot(contains('scaling-mode')));
    expect(qaPatch, isNot(contains('"vf"')));
  });

  test('HWND D3D11 探针固定非 copy 门禁且不启用增强滤镜', () {
    final probe = File('tool/run_mpv_hwnd_d3d11_probe.ps1').readAsStringSync();

    expect(probe, contains('"--wid=\$childHandle"'));
    expect(probe, contains('"--vo=gpu-next"'));
    expect(probe, contains('"--gpu-api=d3d11"'));
    expect(probe, contains('"--gpu-context=d3d11"'));
    expect(probe, contains('"--hwdec=d3d11va"'));
    expect(probe, contains('"hwdec-current"'));
    expect(probe, contains('"decoder-frame-drop-count"'));
    expect(probe, contains('"frame-drop-count"'));
    expect(probe, isNot(contains('scaling-mode')));
    expect(probe, isNot(contains('d3d11vpp')));
    expect(probe, isNot(contains('--vf=')));
  });
}
