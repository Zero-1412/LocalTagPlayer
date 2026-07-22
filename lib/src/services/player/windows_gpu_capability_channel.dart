import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../models/player_gpu_capabilities.dart';

// ignore_for_file: slash_for_doc_comments

/** Windows 原生播放器与只读显卡探测共用的方法通道。 */
const windowsNativePlayerChannel =
    MethodChannel('local_tag_player/native_player');

/**
 * 查询 Windows 原生显卡矩阵。
 *
 * 原生层在后台初始化 DXGI/Vulkan 探针；返回 `probing` 时短暂让出事件循环后重试，
 * 避免把驱动初始化阻塞放到 Flutter 平台线程。
 */
Future<PlayerGpuCapabilityMatrix> queryWindowsGpuCapabilities() async {
  if (!Platform.isWindows) {
    return const PlayerGpuCapabilityMatrix.unsupported();
  }
  for (var attempt = 0; attempt < 30; attempt++) {
    try {
      final value = await windowsNativePlayerChannel
          .invokeMapMethod<Object?, Object?>('gpuCapabilities');
      if (value == null) {
        return const PlayerGpuCapabilityMatrix(
          platformSupported: true,
          probeStatus: 'failed',
          detectionSource: 'dxgi-d3d11-vulkan-loader',
          vulkanLoaderAvailable: false,
          vulkanInstanceAvailable: false,
          adapters: <PlayerGpuAdapterCapabilities>[],
          errorCode: 'empty-platform-response',
        );
      }
      final matrix = PlayerGpuCapabilityMatrix.fromPlatformMap(value);
      if (matrix.probeStatus != 'probing') return matrix;
    } catch (_) {
      return const PlayerGpuCapabilityMatrix(
        platformSupported: true,
        probeStatus: 'failed',
        detectionSource: 'dxgi-d3d11-vulkan-loader',
        vulkanLoaderAvailable: false,
        vulkanInstanceAvailable: false,
        adapters: <PlayerGpuAdapterCapabilities>[],
        errorCode: 'platform-channel-failed',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return const PlayerGpuCapabilityMatrix(
    platformSupported: true,
    probeStatus: 'failed',
    detectionSource: 'dxgi-d3d11-vulkan-loader',
    vulkanLoaderAvailable: false,
    vulkanInstanceAvailable: false,
    adapters: <PlayerGpuAdapterCapabilities>[],
    errorCode: 'probe-timeout',
  );
}
