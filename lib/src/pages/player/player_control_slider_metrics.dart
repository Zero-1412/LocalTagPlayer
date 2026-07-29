import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 计算播放器进度比例，并把尚未取得时长或越界的位置安全限制在 0 到 1。
 */
double playerProgressFraction(Duration position, Duration duration) {
  final total = duration.inMicroseconds;
  if (total <= 0) {
    return 0;
  }
  return (position.inMicroseconds / total).clamp(0.0, 1.0);
}

/**
 * 计算全屏主进度条焦点的视觉倍率。
 *
 * 普通窗口始终保持当前尺寸；全屏时按视口短边从 900 到 2160 逻辑像素平滑放大，
 * 并把上限限制为 1.25，避免高分辨率下过小或超宽屏下过度抢眼。
 */
double playerProgressThumbScale({
  required bool isFullscreen,
  required Size viewportSize,
}) {
  if (!isFullscreen) {
    return 1;
  }
  final shortestSide = math.min(viewportSize.width, viewportSize.height);
  final progress =
      ((shortestSide - 900) / (2160 - 900)).clamp(0.0, 1.0).toDouble();
  return 1 + progress * 0.25;
}

/** 悬停停止后按目标播放位置异步加载预览帧。 */
typedef PlayerProgressPreviewLoader = Future<File?> Function(Duration position);
