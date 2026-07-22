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

/** 从实际创建视频纹理的 D3D11 设备查询活动适配器 LUID。 */
Future<PlayerGpuActiveAdapter> queryWindowsActiveGpuAdapter({
  required String backend,
}) async {
  if (!Platform.isWindows) return const PlayerGpuActiveAdapter.unsupported();
  try {
    final value = await windowsNativePlayerChannel
        .invokeMapMethod<Object?, Object?>('activeGpuAdapter', {
      'backend': backend,
    });
    if (value == null) {
      return const PlayerGpuActiveAdapter(
        probeStatus: 'unavailable',
        detectionSource: 'empty-platform-response',
        errorCode: 'empty-platform-response',
      );
    }
    return PlayerGpuActiveAdapter.fromPlatformMap(value);
  } catch (_) {
    return const PlayerGpuActiveAdapter(
      probeStatus: 'unavailable',
      detectionSource: 'platform-channel-failed',
      errorCode: 'platform-channel-failed',
    );
  }
}

/**
 * 显式运行绑定 LUID 的 1080p/4K Compute 帧预算。
 *
 * 原生层在后台执行；Dart 仅轮询非阻塞快照，正常播放不会调用此函数。
 */
Future<PlayerGpuComputeFrameBudget> benchmarkWindowsGpuComputeFrameBudget(
  String adapterLuid,
) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    final value = await windowsNativePlayerChannel
        .invokeMapMethod<Object?, Object?>('computeFrameBudget', {
      'adapterLuid': adapterLuid,
    });
    if (value == null) {
      return PlayerGpuComputeFrameBudget(
        probeStatus: 'failed',
        adapterLuid: adapterLuid,
        detectionSource: 'empty-platform-response',
        targetFrameRate: 0,
        computeSliceRatio: 0,
        samples: const <PlayerGpuComputeResolutionBudget>[],
        errorCode: 'empty-platform-response',
      );
    }
    final budget = PlayerGpuComputeFrameBudget.fromPlatformMap(value);
    if (budget.probeStatus != 'probing') return budget;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return PlayerGpuComputeFrameBudget(
    probeStatus: 'failed',
    adapterLuid: adapterLuid,
    detectionSource: 'd3d11-timestamp-query-hdr-compute-kernel',
    targetFrameRate: 60,
    computeSliceRatio: 0.25,
    samples: const <PlayerGpuComputeResolutionBudget>[],
    errorCode: 'probe-timeout',
  );
}
