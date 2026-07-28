import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ignore_for_file: slash_for_doc_comments

class _FakeLibraryRepository implements LibraryRepository {
  @override
  final List<String> roots = <String>['root'];
  @override
  final Map<String, VideoItem> videos = <String, VideoItem>{};
  @override
  final List<String> favoriteTags = <String>[];
  @override
  final List<TagGroup> tagGroups = <TagGroup>[];
  @override
  final Map<String, TagItem> tagsById = <String, TagItem>{};
  @override
  final Map<String, Set<String>> videoTagIdsByPathKey = <String, Set<String>>{};

  @override
  TagQueryContext get tagQueryContext => const TagQueryContext();
  @override
  Iterable<TagItem> get allTagItems => tagsById.values;
  @override
  Set<String> get allTags => const <String>{};

  @override
  Future<void> addFavoriteTag(String tag) async => favoriteTags.add(tag);
  @override
  Future<void> removeFavoriteTag(String tag) async => favoriteTags.remove(tag);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTagRepository implements TagRepository {
  String? attachedVideoId;

  @override
  Future<void> attachTag({
    required String videoId,
    required String tagId,
    required TagSource source,
    bool locked = false,
  }) async {
    attachedVideoId = videoId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCacheRepository implements CacheRepository {
  @override
  Future<CacheStatus> thumbnailStatus(String videoId) async =>
      const CacheStatus(kind: CacheStatusKind.ready);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlaybackRepository implements PlaybackRepository {
  String? savedVideoId;

  @override
  Future<void> savePlaybackPosition({
    required String videoId,
    required Duration position,
    required Duration duration,
    required bool completed,
    required DateTime updatedAt,
  }) async {
    savedVideoId = videoId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Dart source uses independent libraries instead of part files', () {
    final violations = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => RegExp(
              r'^\s*part(?:\s+of)?\s+',
              multiLine: true,
            ).hasMatch(file.readAsStringSync()))
        .map((file) => file.path)
        .toList();

    expect(violations, isEmpty);
  });

  test('facade exposes read-only views and routes explicit repository commands',
      () async {
    final library = _FakeLibraryRepository();
    final tags = _FakeTagRepository();
    final cache = _FakeCacheRepository();
    final playback = _FakePlaybackRepository();
    final facade = LibraryApplicationFacade(
      libraryRepository: library,
      tagRepository: tags,
      cacheRepository: cache,
      playbackRepository: playback,
    );

    expect(() => facade.roots.add('other'), throwsUnsupportedError);
    expect(() => facade.favoriteTags.add('tag'), throwsUnsupportedError);
    await facade.addFavoriteTag('tag');
    expect(facade.favoriteTags, contains('tag'));

    await facade.attachTag(
      videoId: 'video-1',
      tagId: 'manual:tag',
      source: TagSource.manual,
    );
    await facade.savePlaybackPosition(
      videoId: 'video-1',
      position: const Duration(seconds: 1),
      duration: const Duration(seconds: 10),
      completed: false,
      updatedAt: DateTime(2026),
    );
    expect(tags.attachedVideoId, 'video-1');
    expect(playback.savedVideoId, 'video-1');
    expect(
        (await facade.thumbnailStatus('video-1')).kind, CacheStatusKind.ready);
  });

  test('sqflite provider owns factory and paths while Dart owns schema writes',
      () async {
    // Windows 使用仓库内固定 SQLite 动态库；macOS/Linux runner 使用系统 SQLite。
    if (Platform.isWindows) {
      DynamicLibrary.open(
        File('windows/tools/sqlite/sqlite3.dll').absolute.path,
      );
    }
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('ltp_db_provider_');
    addTearDown(() => directory.delete(recursive: true));
    final paths = AppPaths(dataDirectoryOverride: directory);
    final provider = SqfliteDatabaseProvider(
      paths: paths,
      factory: databaseFactoryFfi,
    );
    var schemaCalls = 0;
    final database = await provider.openLibraryDatabase(
      version: 1,
      createSchema: (database) async {
        schemaCalls++;
        await database.execute('CREATE TABLE contract_test (id INTEGER)');
      },
      maintainSchema: (database) async => schemaCalls++,
    );
    addTearDown(database.close);

    expect(schemaCalls, greaterThanOrEqualTo(2));
    expect(await (await paths.libraryDatabaseFile()).exists(), isTrue);
  });

  test('composition root selects concrete adapters without page globals', () {
    final dependencies = createLocalTagPlayerDependencies();
    expect(dependencies.fileSystem, isA<DesktopFileSystemAdapter>());
    if (Platform.isMacOS) {
      expect(dependencies.fileSystem, isA<MacOsFileSystemAdapter>());
    } else if (Platform.isLinux) {
      expect(dependencies.fileSystem, isA<LinuxFileSystemAdapter>());
    }
    expect(
      dependencies.libraryPageApplicationService,
      isA<LocalLibraryPageApplicationService>(),
    );
    expect(dependencies.paths, isA<AppPaths>());
  });

  test('LibraryPage depends on page services instead of the composition root',
      () {
    final source = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('local_tag_player_dependencies.dart')));
    expect(source, isNot(contains('LocalTagPlayerDependencies')));
    expect(source, contains('LibraryPageApplicationService'));
    expect(source, contains('PlayerServiceFactory'));
    expect(source, contains('MediaProbeBackendFactory'));
  });

  test('PlayerPage keeps hidden progress mounted before the full controls', () {
    final source = File(
      'lib/src/pages/player/player_page.dart',
    ).readAsStringSync();
    final hiddenLayerIndex = source.indexOf(
      "key: const ValueKey('player.controls.hiddenProgress')",
    );
    final hiddenWidgetIndex = source.indexOf(
      'child: PlayerHiddenProgressBar(',
      hiddenLayerIndex < 0 ? 0 : hiddenLayerIndex,
    );
    final fullControlsIndex = source.indexOf(
      "key: const ValueKey('player.controls.opacity')",
    );

    // 该保护专门捕获组件仍存在、孤立组件测试仍通过，但真实页面挂载被删除的事故。
    expect(hiddenLayerIndex, greaterThanOrEqualTo(0));
    expect(hiddenWidgetIndex, greaterThan(hiddenLayerIndex));
    expect(fullControlsIndex, greaterThan(hiddenWidgetIndex));
    expect(
      source.substring(hiddenLayerIndex, fullControlsIndex),
      contains('opacity: _controlsVisible ? 0 : 1'),
    );
  });

  test('PlayerPage gear keeps compression enhancement mounted and reachable',
      () {
    final pageSource = File(
      'lib/src/pages/player/player_page.dart',
    ).readAsStringSync();
    final panelSource = File(
      'lib/src/pages/player/player_settings_panel.dart',
    ).readAsStringSync();

    // 同时保护齿轮按钮、页面回调和三档入口，避免组件仍存在但从真实播放器孤立。
    expect(pageSource, contains("'player.settings'"));
    expect(pageSource, contains('_showControlSettingsDialog()'));
    expect(
      pageSource,
      contains('compressionEnhancementMode: _compressionEnhancementMode'),
    );
    expect(
      pageSource,
      contains('onCompressionEnhancementModeChanged:'),
    );
    expect(pageSource, isNot(contains('nvidiaVideoEnhancementCapability:')));
    expect(
      pageSource,
      isNot(contains('onNvidiaVideoEnhancementExperimentChanged:')),
    );
    expect(
      pageSource,
      isNot(contains('onNvidiaVideoHdrExperimentChanged:')),
    );
    expect(pageSource, contains('_setCompressionEnhancementMode'));
    expect(
      panelSource,
      contains("ValueKey('player.settings.compression.open')"),
    );
    expect(
      panelSource,
      contains("'player.settings.compression.\${mode.name}'"),
    );
    expect(
      panelSource,
      isNot(contains("'player.settings.nvidiaVideoEnhancementExperiment'")),
    );
    expect(
      panelSource,
      isNot(contains("'player.settings.nvidiaVideoHdrExperiment'")),
    );
  });

  test('Windows build patches media texture callbacks to stable descriptors',
      () {
    final nativeBuild =
        File('windows/native_player/CMakeLists.txt').readAsStringSync();
    final windowsBuild = File('windows/CMakeLists.txt').readAsStringSync();
    final generatedPatchStart =
        nativeBuild.indexOf('set(LTP_VIDEO_OUTPUT_GPU_PATCH');
    final generatedPatchEnd = nativeBuild.indexOf(
      r'file(WRITE "${LTP_PATCHED_MEDIA_KIT_VIDEO_OUTPUT_SOURCE}"',
    );
    expect(generatedPatchStart, greaterThanOrEqualTo(0));
    expect(generatedPatchEnd, greaterThan(generatedPatchStart));
    final generatedPatch =
        nativeBuild.substring(generatedPatchStart, generatedPatchEnd);

    // RegisterTexture 允许同步取帧；回调必须绑定自己的描述符，不能读取尚未入表或已切换的全局 ID。
    expect(generatedPatch, contains('[&, texture_descriptor]'));
    expect(generatedPatch, contains('return texture_descriptor'));
    expect(generatedPatch, contains('[&, pixel_buffer_descriptor]'));
    expect(generatedPatch, contains('return pixel_buffer_descriptor'));
    expect(
      windowsBuild,
      contains('LTP_PATCHED_MEDIA_KIT_VIDEO_OUTPUT_SOURCE'),
    );
    expect(
      windowsBuild,
      contains('(angle_surface_manager|video_output)\\\\.cc'),
    );
  });

  test('local video enhancement prototype is explicit and never installed', () {
    final nativeBuild =
        File('windows/native_player/CMakeLists.txt').readAsStringSync();
    final runnerBuild =
        File('windows/runner/CMakeLists.txt').readAsStringSync();
    final bridge =
        File('windows/runner/native_player_bridge.cpp').readAsStringSync();
    final host = File(
      'windows/runner/local_video_enhancement_plugin.cpp',
    ).readAsStringSync();
    final api = File(
      'windows/native_player/local_video_enhancement_plugin_api.h',
    ).readAsStringSync();

    // 原型只能通过绝对路径显式加载；标准构建不启用、不安装探针，也不引用厂商 SDK。
    expect(
      host,
      contains('LOCAL_TAG_PLAYER_VIDEO_PLUGIN_PATH'),
    );
    expect(host, contains('plugin-path-must-be-absolute'));
    expect(host, contains('LoadLibraryExW'));
    expect(api, contains('kLtpLocalVideoPluginAbiVersion = 1'));
    expect(
      nativeBuild,
      contains('option(LTP_BUILD_LOCAL_VIDEO_PLUGIN_PROBE'),
    );
    expect(
      nativeBuild,
      contains('"Build the local D3D11 video enhancement probe DLL" OFF'),
    );
    expect(nativeBuild, isNot(contains('install(TARGETS ltp_local_video')));
    expect(runnerBuild, contains('local_video_enhancement_plugin.cpp'));
    final prototypeSource =
        '$nativeBuild$runnerBuild$bridge$host$api'.toLowerCase();
    expect(prototypeSource, isNot(contains('#include <nvvfx')));
    expect(prototypeSource, isNot(contains('nvvfx.dll')));
    expect(prototypeSource, isNot(contains('maxine')));

    // 共享纹理必须在工作线程复制和处理；插件失败前已有宿主备份可恢复。
    final renderStart = bridge.indexOf('void NativePlayerBridge::RenderFrame');
    final enqueueStart = bridge.indexOf('void NativePlayerBridge::Enqueue');
    final renderBody = bridge.substring(renderStart, enqueueStart);
    expect(renderBody, contains('surface_manager_->Read()'));
    expect(renderBody, contains('video_enhancement_plugin_.ProcessFrame'));
    expect(
      renderBody.indexOf('surface_manager_->Read()'),
      lessThan(renderBody.indexOf('video_enhancement_plugin_.ProcessFrame')),
    );
    expect(host, contains('CopyResource(backup_texture_.Get(), texture)'));
    expect(host, contains('CopyResource(texture, backup_texture_.Get())'));
  });

  test('Windows MPV 状态由事件唤醒与属性观察驱动', () {
    final bridge =
        File('windows/runner/native_player_bridge.cpp').readAsStringSync();

    expect(bridge, contains('mpv_set_wakeup_callback('));
    expect(bridge, contains('mpv_observe_property('));
    expect(bridge, contains('MPV_EVENT_PROPERTY_CHANGE'));
    expect(bridge, contains('condition_.wait(lock'));
    expect(bridge, contains('kMaxEventsPerBatch = 128'));
    expect(bridge, contains('event_batch_yield_count_'));
    expect(
      bridge,
      contains('native_hwnd_enabled_ ? "v" : "warn"'),
      reason: 'Texture 会话不需要为不可用的 NVIDIA 门禁持续接收 verbose 日志',
    );
    expect(
      bridge,
      isNot(contains('condition_.wait_for(lock')),
      reason: '原生工作线程不得恢复为固定 50ms 全属性扫描',
    );
    expect(
      bridge,
      isNot(contains('void NativePlayerBridge::SamplePlayerState()')),
      reason: '状态读取必须消费 libmpv 合并事件，而不是周期性读取全部属性',
    );
  });

  test('生产增强配置复用 MediaKit 的同一个 NativePlayer', () {
    final selection = File(
      'lib/src/services/player/player_backend_selection.dart',
    ).readAsStringSync();
    final backend = File(
      'lib/src/services/player/media_kit_player_backend.dart',
    ).readAsStringSync();

    expect(
      selection,
      contains('return PlayerBackendSelection.mediaKitLibmpvEnhanced;'),
    );
    expect(
      selection,
      contains("normalizedOverride == 'windows-native-mpv'"),
      reason: '自研 Texture 只能由显式 QA 环境变量进入',
    );
    expect(backend, contains('platform is NativePlayer'));
    expect(backend, contains('PlayerPropertyBatchBoundary'));
    expect(backend, contains('waitForInitialization: waitForInitialization'));
    expect(
      backend,
      isNot(contains('(platform as dynamic)')),
      reason: '高级属性必须走 media_kit 公开的类型化 NativePlayer 边界',
    );
    expect(
      File(
        'integration_test/media_kit_libmpv_facade_test.dart',
      ).existsSync(),
      isTrue,
      reason: '必须用真实 MediaKit Texture 会话证明同实例高级属性可用',
    );
  });

  test('NVIDIA automatic policy and fixed-frame visual gate stay explicit', () {
    final panel = File(
      'lib/src/pages/player/player_settings_panel.dart',
    ).readAsStringSync();
    final page = File(
      'lib/src/pages/player/player_page.dart',
    ).readAsStringSync();
    final autoPolicy = File(
      'lib/src/services/player/player_nvidia_video_auto_policy.dart',
    ).readAsStringSync();
    final backendSelection = File(
      'lib/src/services/player/player_backend_selection.dart',
    ).readAsStringSync();
    final nativeBridge = File(
      'windows/runner/native_player_bridge.cpp',
    ).readAsStringSync();
    final nativeBackend = File(
      'lib/src/services/player/windows_native_player_backend.dart',
    ).readAsStringSync();
    final abRunner = File('tool/run_nvidia_scaling_ab.ps1').readAsStringSync();
    final baselineGate = File(
      'integration_test/player_fixed_quality_baseline_test.dart',
    ).readAsStringSync();
    final roadmap = File('ROADMAP.md').readAsStringSync();

    // 手动开关已经获授权删除；自动策略仍必须保留驱动诊断、门禁与回滚。
    expect(panel, isNot(contains('NVIDIA RTX 视频超分')));
    expect(panel, isNot(contains('NVIDIA RTX Video HDR')));
    expect(page, contains('NVIDIA RTX 视频超分:'));
    expect(page, contains('NVIDIA RTX Video HDR:'));
    expect(page, contains('_applyAutomaticNvidiaVideoEnhancement'));
    expect(page, contains('NVIDIA 自动策略:'));
    expect(autoPolicy, contains('PlayerNvidiaVideoAutoPolicy'));
    expect(autoPolicy, contains('output.hdrSignalActive'));
    expect(nativeBridge, contains('video-params/w'));
    expect(nativeBridge, contains('video-params/h'));
    expect(nativeBackend, contains("'video-params/w'"));
    expect(nativeBackend, contains("'video-params/h'"));
    expect(
      backendSelection,
      contains(
        'rendererPreference != PlayerRendererPreference.mediaKit',
      ),
    );
    expect(
      backendSelection,
      contains('return PlayerBackendSelection.mediaKitLibmpvEnhanced;'),
    );
    expect(
      backendSelection,
      contains("normalizedOverride == 'windows-native-mpv'"),
      reason: '自研 MPV Texture 只允许显式 QA 覆盖，不能恢复为生产默认后端',
    );
    expect(
      backendSelection,
      contains("normalizedOverride == 'windows-native-hwnd'"),
    );
    expect(page, contains('_suspendCpuEnhancementsForNvidia'));
    expect(page, contains('_restoreCpuEnhancementsAfterNvidia'));
    expect(page, contains('NVIDIA 滤镜互斥处理:'));
    expect(baselineGate, contains("'playerBackend':"));
    expect(baselineGate, contains("'rendererPreference':"));

    // 肉眼 A/B 必须锁定同一媒体时间和最终窗口尺寸，不能退回 mpv 内部截图。
    expect(abRunner, contains('fixedFrameSecond = 12'));
    expect(abRunner, contains('PW_RENDERFULLCONTENT'));
    expect(abRunner, contains('sameWindowDimensions'));
    expect(abRunner, contains('allVisualCaptureGatesPassed'));

    // NVOFA 与 patched libmpv 只保留长期研究，不得重新成为自动发布门禁。
    expect(roadmap, contains('NVOFA 插帧降级为独立长期研究'));
    expect(roadmap, contains('非自动后续'));
  });

  test('Windows debug package gate rebuilds the production entrypoint', () {
    final verifier =
        File('tool/verify_windows_debug_package.ps1').readAsStringSync();
    final buildIndex = verifier.indexOf('flutter build windows --debug');
    final launchIndex = verifier.indexOf('Start-Process');

    // integration_test 会复用 Debug 目录；交付门禁必须先恢复正式 main.dart 再双击。
    expect(buildIndex, greaterThanOrEqualTo(0));
    expect(launchIndex, greaterThan(buildIndex));
    expect(verifier, contains('local_tag_player.exe'));
    expect(verifier, contains(r'$process.MainWindowHandle -ne 0'));
    expect(verifier, contains(r'$process.HasExited'));
    expect(verifier, contains('CloseMainWindow'));
  });

  test('motion interpolation runtime uses structured vf and local-only paths',
      () {
    final runnerBuild =
        File('windows/runner/CMakeLists.txt').readAsStringSync();
    final bridge =
        File('windows/runner/native_player_bridge.cpp').readAsStringSync();
    final bridgeHeader =
        File('windows/runner/native_player_bridge.h').readAsStringSync();
    final nvofaDriver = File(
      'windows/runner/nvidia_optical_flow_driver_probe.cpp',
    ).readAsStringSync();
    final nvofaExecute = File(
      'windows/nvidia_optical_flow_probe/nvofa_cuda_execute_probe.cpp',
    ).readAsStringSync();
    final d3d11AdapterSelector = File(
      'windows/runner/d3d11_adapter_selector.cpp',
    ).readAsStringSync();
    final nvofaScript =
        File('tool/run_nvofa_execute_probe.ps1').readAsStringSync();
    final nvofaInterpolation = File(
      'windows/nvidia_optical_flow_probe/nvofa_vapoursynth_plugin.cpp',
    ).readAsStringSync();
    final nvofaD3d11Warp = File(
      'windows/nvidia_optical_flow_probe/d3d11_midpoint_warper.cpp',
    ).readAsStringSync();
    final nvofaD3d11WarpProbe = File(
      'windows/nvidia_optical_flow_probe/'
      'd3d11_midpoint_warper_probe.cpp',
    ).readAsStringSync();
    final nvofaInterpolationScript = File(
      'tool/vapoursynth_nvofa_interpolation.vpy',
    ).readAsStringSync();
    final nvofaInterpolationProbe = File(
      'tool/run_nvofa_vapoursynth_interpolation_probe.ps1',
    ).readAsStringSync();
    final nvofaMotionAb = File(
      'tool/run_nvofa_motion_ab.ps1',
    ).readAsStringSync();
    final nvofaMotionStress = File(
      'tool/generate_nvofa_motion_stress_samples.ps1',
    ).readAsStringSync();
    final nativeBuild =
        File('windows/native_player/CMakeLists.txt').readAsStringSync();
    final runtime = File(
      'windows/runner/vapoursynth_motion_runtime.cpp',
    ).readAsStringSync();
    final boundary =
        File('lib/src/platform/platform_interfaces.dart').readAsStringSync();
    final flutterBackend = File(
      'lib/src/services/player/windows_native_player_backend.dart',
    ).readAsStringSync();

    // 本机原型不分发第三方运行时；只有两个绝对路径环境变量能开启探测。
    expect(runnerBuild, contains('vapoursynth_motion_runtime.cpp'));
    expect(
      runtime,
      contains('LOCAL_TAG_PLAYER_VAPOURSYNTH_RUNTIME_DIR'),
    );
    expect(
      runtime,
      contains('LOCAL_TAG_PLAYER_MOTION_INTERPOLATION_SCRIPT_PATH'),
    );
    expect(runtime, contains('runtime-and-script-paths-must-be-absolute'));
    expect(runtime, contains('LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR'));
    expect(runtime, contains('getVSScriptAPI'));

    // `vf` 必须按结构化节点保留现有压缩增强；禁止把 Windows 路径拼成滤镜字符串。
    expect(runtime, contains('MPV_FORMAT_NODE_ARRAY'));
    expect(runtime, contains('MPV_FORMAT_NODE_MAP'));
    expect(runtime, contains('mpv_get_property(player, "vf"'));
    expect(runtime, contains('mpv_set_property(player, "vf"'));
    expect(runtime, contains('ltp-motion-interpolation'));
    expect(runtime, isNot(contains('mpv_set_property_string(player, "vf"')));
    expect(
      bridge,
      contains('ReapplyAfterFilterGraphChange(player_)'),
    );
    expect(
      bridge,
      contains('windows-native-mpv-selected-d3d11-adapter'),
    );
    expect(bridge, contains('"d3d11-adapter"'));
    expect(
      bridge,
      contains('SelectNvidiaD3D11Adapter()'),
    );
    // 直接采样 D3D11VA 解码表面可能触发驱动问题，只允许显式 QA 请求，产品默认关闭。
    expect(
      bridge,
      contains('LOCAL_TAG_PLAYER_D3D11VA_ZERO_COPY_QA'),
    );
    expect(bridge, contains('IsQaEnvironmentEnabled('));
    expect(bridge, contains('"d3d11va-zero-copy", "yes"'));
    expect(bridgeHeader, contains('d3d11va_zero_copy_ = "no"'));
    expect(
      boundary,
      contains('abstract interface class PlayerMotionInterpolationBoundary'),
    );
    // 平台命令返回不等于滤镜已经生效；Flutter 边界必须等待原生状态确认。
    expect(flutterBackend, contains("'motion-interpolation'"));
    expect(
      flutterBackend,
      contains('const Duration(milliseconds: 50)'),
    );
    expect(
      flutterBackend,
      contains('PlayerMotionInterpolationStatus.requested'),
    );
    expect(
      flutterBackend,
      contains('PlayerMotionInterpolationStatus.active'),
    );

    // NVOFA 只从 System32 探测官方驱动入口，不把驱动存在冒充 FRUC 已安装。
    expect(nvofaDriver, contains('LOAD_LIBRARY_SEARCH_SYSTEM32'));
    expect(nvofaDriver, contains('NvOFGetMaxSupportedApiVersion'));
    expect(nvofaDriver, contains('NvOFAPICreateInstanceD3D11'));
    expect(
      bridge,
      contains('native-nvofa-driver-state'),
    );
    expect(
      bridge,
      contains('ProbeNvidiaOpticalFlowDriver()'),
    );

    // 真实硬件执行证据必须保持为显式、零分发的隔离目标，不能悄悄进入正式应用。
    expect(nativeBuild, contains('LTP_BUILD_NVOFA_EXECUTE_PROBE'));
    expect(
      nativeBuild,
      contains('ltp_nvofa_cuda_execute_probe EXCLUDE_FROM_ALL'),
    );
    expect(
      nativeBuild,
      isNot(contains('install(TARGETS ltp_nvofa_cuda_execute_probe')),
    );
    expect(nvofaExecute, contains('NvOFAPICreateInstanceCuda'));
    expect(nvofaExecute, contains('nvOFExecute'));
    expect(nvofaExecute, contains('validate-nonzero-flow'));
    expect(nvofaExecute, contains('cuDeviceGetLuid'));
    expect(nvofaExecute, contains('luid-match=passed'));
    expect(nvofaExecute, contains('LOAD_LIBRARY_SEARCH_SYSTEM32'));
    expect(
      d3d11AdapterSelector,
      contains('DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE'),
    );
    expect(
      d3d11AdapterSelector,
      contains('duplicate-nvidia-adapter-description'),
    );
    expect(
      d3d11AdapterSelector,
      contains('LOCAL_TAG_PLAYER_NVIDIA_ADAPTER_LUID'),
    );
    expect(
      nvofaScript,
      contains('edb50da3cf849840d680249aa6dbef248ebce2ca'),
    );
    expect(nvofaScript, contains('Get-FileHash'));

    // 生成中间帧的本机插件仍是显式 QA 目标：不进入默认构建、不安装、不分发。
    expect(nativeBuild, contains('LTP_BUILD_NVOFA_VAPOURSYNTH_PLUGIN'));
    expect(
      nativeBuild,
      contains('ltp_nvofa_vapoursynth_plugin MODULE EXCLUDE_FROM_ALL'),
    );
    expect(
      nativeBuild,
      isNot(contains('install(TARGETS ltp_nvofa_vapoursynth_plugin')),
    );
    expect(
      runtime,
      contains('LOCAL_TAG_PLAYER_NVOFA_VS_PLUGIN_PATH'),
    );
    expect(runtime, contains('const_cast<char*>("user-data")'));
    expect(nvofaInterpolation, contains('nvOFExecute'));
    expect(
      nvofaInterpolation,
      contains('input_, reference_, &flow->forward,'),
    );
    expect(
      nvofaInterpolation,
      contains('reference_, input_, &flow->backward,'),
    );
    expect(nvofaInterpolation, contains('cuDeviceGetLuid'));
    expect(
      nvofaInterpolation,
      contains('match-cuda-device-by-d3d11-luid'),
    );
    expect(nvofaInterpolation, contains('adapter_luid:data'));
    expect(nvofaInterpolation, contains('LTPNVOFAInterpolated'));
    expect(nvofaInterpolation, contains('LTPNVOFAAdapterMatched'));
    expect(nvofaInterpolation, contains('LTPNVOFAD3D11Warp'));
    expect(
      nvofaInterpolation,
      contains('LTPNVOFAConsistencyProtected'),
    );
    expect(nvofaInterpolation, contains('LTPNVOFASceneCut'));
    expect(nvofaInterpolation, contains('enableOutputCost = NV_OF_TRUE'));
    expect(nvofaInterpolation, contains('NV_OF_BUFFER_FORMAT_UINT8'));
    expect(
      nvofaInterpolation,
      isNot(contains('concurrency::parallel_for')),
    );
    expect(nvofaD3d11Warp, contains('D3DCompile'));
    expect(nvofaD3d11Warp, contains('"cs_5_0"'));
    expect(nvofaD3d11Warp, contains('context_->Dispatch'));
    expect(nvofaD3d11Warp, contains('DXGI_FORMAT_R16G16_SINT'));
    expect(nvofaD3d11Warp, contains('DXGI_FORMAT_R8_UINT'));
    expect(nvofaD3d11Warp, contains('DXGI_FORMAT_R32_FLOAT'));
    expect(
      nvofaD3d11Warp,
      contains('DXGI_FORMAT_R32G32B32A32_FLOAT'),
    );
    expect(nvofaD3d11Warp, contains('FlowConfidence'));
    expect(nvofaD3d11Warp, contains('ResolveForward'));
    expect(nvofaD3d11Warp, contains('ResolveBackward'));
    expect(nvofaD3d11Warp, contains('WarpCandidate'));
    expect(nvofaD3d11Warp, contains('kHoleFillShader'));
    expect(
      nvofaD3d11WarpProbe,
      contains('d3d11-warp-occlusion=passed'),
    );
    expect(nvofaD3d11WarpProbe, contains('vector-infill='));
    expect(nvofaD3d11WarpProbe, contains('image-hole-fill='));
    expect(
      nativeBuild,
      contains('ltp_d3d11_midpoint_warper_probe EXCLUDE_FROM_ALL'),
    );
    expect(
      nativeBuild,
      isNot(contains('install(TARGETS ltp_d3d11_midpoint_warper_probe')),
    );
    expect(
      nvofaInterpolationScript,
      contains('plugin_path, adapter_luid = user_data.rsplit("|", 1)'),
    );
    expect(nvofaInterpolationScript, contains('video_out.set_output()'));
    expect(
      nvofaInterpolationProbe,
      contains('expect-active-performance'),
    );
    expect(nvofaInterpolationProbe, contains('d3d11-warp=passed'));
    expect(
      nvofaInterpolationProbe,
      contains('consistency-protected=passed'),
    );
    expect(
      nvofaInterpolationProbe,
      contains('image-hole-fill=201'),
    );
    expect(nvofaMotionAb, contains('plugin-sha256.txt'));
    expect(nvofaMotionAb, contains('pluginSha256 = \$pluginHash'));
    expect(nvofaMotionAb, contains('CaseManifest'));
    expect(nvofaMotionAb, contains('allRuntimeGatesPassed'));
    expect(nvofaMotionAb, contains('productEnablement'));
    expect(nvofaMotionAb, contains('D3D11VaZeroCopyQa'));
    expect(nvofaMotionAb, contains('d3d11vaZeroCopyGatePassed'));
    // 连续压力样本必须覆盖五类已知风险，且只生成到本机 QA 目录。
    expect(nvofaMotionStress, contains('"fast-pan"'));
    expect(nvofaMotionStress, contains('"fine-fence"'));
    expect(nvofaMotionStress, contains('"subtitles"'));
    expect(nvofaMotionStress, contains('"motion-blur"'));
    expect(nvofaMotionStress, contains('"scene-cut"'));
    expect(nvofaMotionStress, contains('.local/qa/nvofa-motion-stress'));
  });

  test('desktop startup centers size-only persisted window layouts', () {
    final source = File(
      'lib/src/services/window/desktop_window_state_service.dart',
    ).readAsStringSync();

    // 窗口快照没有坐标时不能要求插件按缺失的位置恢复，否则独立 EXE 可能保持隐藏。
    expect(source, contains('center: true'));
    expect(source, isNot(contains('center: layout == null')));
  });

  test('player stress fullscreen uses the production state machine directly',
      () {
    final playerSource =
        File('lib/src/pages/player/player_page.dart').readAsStringSync();
    final stressSource = File(
      'integration_test/player_real_library_stress_test.dart',
    ).readAsStringSync();

    // 控制条可见性属于动画状态，长跑门禁必须稳定覆盖真正的窗口与纹理切换路径。
    expect(
      playerSource,
      contains('toggleWindowFullscreenForStressTest'),
    );
    expect(
      stressSource,
      contains('.toggleWindowFullscreenForStressTest()'),
    );
    final roundTripStart =
        stressSource.indexOf('Future<void> _toggleFullscreenRoundTrip');
    final helperStart = stressSource
        .indexOf('Future<void> _toggleFullscreenThroughPlayerState');
    expect(roundTripStart, greaterThanOrEqualTo(0));
    expect(helperStart, greaterThan(roundTripStart));
    expect(
      stressSource.substring(roundTripStart, helperStart),
      isNot(contains("find.byKey(const ValueKey('player.fullscreen.toggle'))")),
    );
  });

  test('双后端稳定性矩阵覆盖四类场景并保留跨平台原生门禁', () {
    final integrationSource = File(
      'integration_test/player_backend_stability_matrix_test.dart',
    ).readAsStringSync();
    final runnerSource = File(
      'tool/run_player_backend_stability_matrix.ps1',
    ).readAsStringSync();

    expect(integrationSource, contains('_runFullscreenScenario'));
    expect(integrationSource, contains('_runDpiScenario'));
    expect(integrationSource, contains('_runRapidSwitchScenario'));
    expect(integrationSource, contains('_runLongPlayScenario'));
    expect(
      integrationSource,
      contains('jumpToQueueIndexForStabilityTest'),
      reason: '快速切换必须走 PlayerPage 的 latest-request 正式链路',
    );
    expect(runnerSource, contains("@('mediaKit', 'mpv')"));
    expect(
      runnerSource,
      contains('pending-physical-cross-dpi'),
      reason: '模拟 metrics 不能冒充真实跨显示器 DPI 已通过',
    );
    expect(
      runnerSource,
      contains("mpv = 'blocked-native-backend-not-implemented'"),
      reason: 'macOS/Linux 未实现各自原生后端前必须保持 MPV 门禁',
    );
  });
}
