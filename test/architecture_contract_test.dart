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
    expect(
      pageSource,
      contains('nvidiaVideoEnhancementCapability:'),
    );
    expect(
      pageSource,
      contains('onNvidiaVideoEnhancementExperimentChanged:'),
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
      contains(
        "'player.settings.nvidiaVideoEnhancementExperiment'",
      ),
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

  test('motion interpolation runtime uses structured vf and local-only paths',
      () {
    final runnerBuild =
        File('windows/runner/CMakeLists.txt').readAsStringSync();
    final bridge =
        File('windows/runner/native_player_bridge.cpp').readAsStringSync();
    final runtime = File(
      'windows/runner/vapoursynth_motion_runtime.cpp',
    ).readAsStringSync();
    final boundary =
        File('lib/src/platform/platform_interfaces.dart').readAsStringSync();

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
      boundary,
      contains('abstract interface class PlayerMotionInterpolationBoundary'),
    );
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
}
