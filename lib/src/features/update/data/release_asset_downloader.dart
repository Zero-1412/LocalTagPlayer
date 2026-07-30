// ignore_for_file: slash_for_doc_comments

import 'dart:async';
import 'dart:io';

import '../domain/app_release.dart';

/**
 * 下载 GitHub Release 安装包，并在服务端支持 Range 时使用四段并行传输。
 *
 * 该下载器只负责把网络内容写入调用方指定的临时文件；SHA-256 校验、完整文件改名和
 * 安装器启动继续由 [GitHubReleaseUpdateService] 所在的更新服务边界负责。
 */
class ReleaseAssetDownloader {
  ReleaseAssetDownloader({
    required HttpClient httpClient,
    this.parallelConnections = 4,
    this.minimumParallelBytes = 4 * 1024 * 1024,
  }) : _httpClient = httpClient;

  /** 与 GitHub API 客户端共享的受控网络连接池。 */
  final HttpClient _httpClient;

  /** Range 可用时的连接数量；四连接兼顾吞吐和 CDN 稳定性。 */
  final int parallelConnections;

  /** 小文件不并行，避免重定向和分片合并成本超过传输收益。 */
  final int minimumParallelBytes;

  /**
   * 下载 [url] 到 [partialFile]。
   *
   * [userAgent] 用于 GitHub 与 CDN 请求标识；[onProgress] 接收聚合后的四段进度，
   * 回调频率会受限，避免网络分片在 UI 线程触发过量 rebuild。
   */
  Future<void> download({
    required Uri url,
    required File partialFile,
    required String userAgent,
    void Function(AppUpdateDownloadProgress progress)? onProgress,
  }) async {
    await _deleteIfExists(partialFile);
    final segmentFiles = List<File>.generate(
      parallelConnections,
      (index) => File('${partialFile.path}.segment-$index'),
      growable: false,
    );
    for (final segmentFile in segmentFiles) {
      await _deleteIfExists(segmentFile);
    }

    try {
      final probe = await _probe(url, userAgent);
      if (!probe.supportsRanges ||
          probe.totalBytes < minimumParallelBytes ||
          parallelConnections < 2) {
        await _downloadSingle(
          probe: probe,
          originalUrl: url,
          partialFile: partialFile,
          userAgent: userAgent,
          onProgress: onProgress,
        );
        return;
      }

      await _downloadParallel(
        originalUrl: url,
        rangeUrl: probe.rangeUrl,
        totalBytes: probe.totalBytes,
        partialFile: partialFile,
        segmentFiles: segmentFiles,
        userAgent: userAgent,
        onProgress: onProgress,
      );
    } catch (_) {
      await _deleteIfExists(partialFile);
      for (final segmentFile in segmentFiles) {
        await _deleteIfExists(segmentFile);
      }
      rethrow;
    }
  }

  /** 用 0-0 Range 探针同时确认总大小、Range 语义和最终 CDN 地址。 */
  Future<_RangeProbe> _probe(Uri url, String userAgent) async {
    final request = await _httpClient.getUrl(url).timeout(
          const Duration(seconds: 10),
        );
    request.headers
      ..set(HttpHeaders.userAgentHeader, userAgent)
      ..set(HttpHeaders.acceptEncodingHeader, 'identity')
      ..set(HttpHeaders.rangeHeader, 'bytes=0-0');
    final response = await request.close().timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode == HttpStatus.partialContent) {
      final contentRange =
          response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
      final match = RegExp(r'^bytes 0-0/([0-9]+)$').firstMatch(contentRange);
      if (match == null) {
        await _cancelResponse(response);
        throw const FormatException('安装包 Range 探针缺少有效 Content-Range');
      }
      final totalBytes = int.parse(match.group(1)!);
      final redirectLocation =
          response.redirects.isEmpty ? null : response.redirects.last.location;
      final rangeUrl = redirectLocation == null
          ? url
          : redirectLocation.hasScheme
              ? redirectLocation
              : url.resolveUri(redirectLocation);
      await response.timeout(const Duration(seconds: 30)).drain<void>();
      return _RangeProbe(
        supportsRanges: true,
        totalBytes: totalBytes,
        rangeUrl: rangeUrl,
      );
    }

    if (response.statusCode == HttpStatus.ok) {
      return _RangeProbe(
        supportsRanges: false,
        totalBytes: response.contentLength,
        rangeUrl: url,
        fullResponse: response,
      );
    }

    await _cancelResponse(response);
    throw HttpException(
      '安装包下载失败：HTTP ${response.statusCode}',
      uri: url,
    );
  }

  /** Range 不可用或文件很小时维持单流兼容路径。 */
  Future<void> _downloadSingle({
    required _RangeProbe probe,
    required Uri originalUrl,
    required File partialFile,
    required String userAgent,
    required void Function(AppUpdateDownloadProgress progress)? onProgress,
  }) async {
    final response =
        probe.fullResponse ?? await _openFullResponse(originalUrl, userAgent);
    if (response.statusCode != HttpStatus.ok) {
      await _cancelResponse(response);
      throw HttpException(
        '安装包下载失败：HTTP ${response.statusCode}',
        uri: originalUrl,
      );
    }

    final totalBytes = response.contentLength;
    final reporter = _DownloadProgressReporter(
      totalBytes: totalBytes,
      segmentCount: 1,
      onProgress: onProgress,
    );
    await _writeResponse(
      response: response,
      file: partialFile,
      expectedBytes: totalBytes,
      reporter: reporter,
      segmentIndex: 0,
    );
    reporter.complete();
  }

  /** 四段同时下载到独立临时文件，全部成功后再按字节顺序合并。 */
  Future<void> _downloadParallel({
    required Uri originalUrl,
    required Uri rangeUrl,
    required int totalBytes,
    required File partialFile,
    required List<File> segmentFiles,
    required String userAgent,
    required void Function(AppUpdateDownloadProgress progress)? onProgress,
  }) async {
    final reporter = _DownloadProgressReporter(
      totalBytes: totalBytes,
      segmentCount: parallelConnections,
      onProgress: onProgress,
    );
    final baseSegmentBytes = totalBytes ~/ parallelConnections;
    final tasks = <Future<void>>[];

    for (var index = 0; index < parallelConnections; index += 1) {
      final start = index * baseSegmentBytes;
      final end = index == parallelConnections - 1
          ? totalBytes - 1
          : start + baseSegmentBytes - 1;
      tasks.add(
        _downloadRangeWithRetry(
          originalUrl: originalUrl,
          rangeUrl: rangeUrl,
          start: start,
          end: end,
          file: segmentFiles[index],
          userAgent: userAgent,
          reporter: reporter,
          segmentIndex: index,
        ),
      );
    }

    // 不使用 eagerError，确保其它文件句柄结束后再统一清理临时分片。
    await Future.wait(tasks);
    final sink = partialFile.openWrite();
    try {
      for (final segmentFile in segmentFiles) {
        await sink.addStream(segmentFile.openRead());
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (await partialFile.length() != totalBytes) {
      throw const FileSystemException('并行安装包合并后大小不一致');
    }
    for (final segmentFile in segmentFiles) {
      await _deleteIfExists(segmentFile);
    }
    reporter.complete();
  }

  /** 单个 Range 遇到瞬时网络错误时重试一次，不放宽响应范围和长度校验。 */
  Future<void> _downloadRangeWithRetry({
    required Uri originalUrl,
    required Uri rangeUrl,
    required int start,
    required int end,
    required File file,
    required String userAgent,
    required _DownloadProgressReporter reporter,
    required int segmentIndex,
  }) async {
    for (var attempt = 0; attempt < 2; attempt += 1) {
      reporter.resetSegment(segmentIndex);
      await _deleteIfExists(file);
      try {
        final requestUrl = attempt == 0 ? rangeUrl : originalUrl;
        final request = await _httpClient.getUrl(requestUrl).timeout(
              const Duration(seconds: 10),
            );
        request.headers
          ..set(HttpHeaders.userAgentHeader, userAgent)
          ..set(HttpHeaders.acceptEncodingHeader, 'identity')
          ..set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
        final response = await request.close().timeout(
              const Duration(seconds: 15),
            );
        if (response.statusCode != HttpStatus.partialContent) {
          await _cancelResponse(response);
          throw HttpException(
            '安装包分段下载失败：HTTP ${response.statusCode}',
            uri: requestUrl,
          );
        }

        final contentRange =
            response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
        if (contentRange != 'bytes $start-$end/${reporter.totalBytes}') {
          await _cancelResponse(response);
          throw const FormatException('安装包分段响应范围不一致');
        }
        await _writeResponse(
          response: response,
          file: file,
          expectedBytes: end - start + 1,
          reporter: reporter,
          segmentIndex: segmentIndex,
        );
        return;
      } on Object catch (error) {
        final canRetry = attempt == 0 &&
            (error is SocketException ||
                error is TimeoutException ||
                error is HttpException);
        if (!canRetry) {
          rethrow;
        }
      }
    }
  }

  /** 打开无 Range 的完整响应，供兼容路径使用。 */
  Future<HttpClientResponse> _openFullResponse(
    Uri url,
    String userAgent,
  ) async {
    final request = await _httpClient.getUrl(url).timeout(
          const Duration(seconds: 10),
        );
    request.headers
      ..set(HttpHeaders.userAgentHeader, userAgent)
      ..set(HttpHeaders.acceptEncodingHeader, 'identity');
    return request.close().timeout(const Duration(seconds: 15));
  }

  /** 流式写入一个响应，并严格核对该响应的实际字节数。 */
  Future<void> _writeResponse({
    required HttpClientResponse response,
    required File file,
    required int expectedBytes,
    required _DownloadProgressReporter reporter,
    required int segmentIndex,
  }) async {
    var receivedBytes = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response.timeout(
        const Duration(seconds: 30),
      )) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        reporter.addBytes(segmentIndex, chunk.length);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (expectedBytes > 0 && receivedBytes != expectedBytes) {
      throw const FileSystemException('安装包下载不完整');
    }
  }
}

/** Range 能力探针结果；不支持时保留已经打开的完整响应，避免重复请求。 */
class _RangeProbe {
  const _RangeProbe({
    required this.supportsRanges,
    required this.totalBytes,
    required this.rangeUrl,
    this.fullResponse,
  });

  final bool supportsRanges;
  final int totalBytes;
  final Uri rangeUrl;
  final HttpClientResponse? fullResponse;
}

/** 聚合并节流多连接进度，避免四条网络流直接高频刷新弹窗。 */
class _DownloadProgressReporter {
  _DownloadProgressReporter({
    required this.totalBytes,
    required int segmentCount,
    required this.onProgress,
  }) : _segmentBytes = List<int>.filled(segmentCount, 0);

  final int totalBytes;
  final void Function(AppUpdateDownloadProgress progress)? onProgress;
  final List<int> _segmentBytes;
  final Stopwatch _stopwatch = Stopwatch()..start();
  int _lastReportMicroseconds = 0;

  int get _receivedBytes =>
      _segmentBytes.fold<int>(0, (total, value) => total + value);

  /** 增加一个分段的已收字节，并至多每 150 ms 发布一次进度。 */
  void addBytes(int segmentIndex, int bytes) {
    _segmentBytes[segmentIndex] += bytes;
    _report();
  }

  /** 重试分段前撤销该分段旧进度，避免百分比超过真实落盘大小。 */
  void resetSegment(int segmentIndex) {
    _segmentBytes[segmentIndex] = 0;
  }

  /** 全部分段写入并合并后强制发布一次最终 100% 快照。 */
  void complete() {
    _report(force: true);
  }

  void _report({bool force = false}) {
    final callback = onProgress;
    if (callback == null) {
      return;
    }
    final elapsedMicroseconds = _stopwatch.elapsedMicroseconds;
    if (!force && elapsedMicroseconds - _lastReportMicroseconds < 150000) {
      return;
    }
    _lastReportMicroseconds = elapsedMicroseconds;
    final receivedBytes = _receivedBytes;
    final elapsedSeconds = elapsedMicroseconds / Duration.microsecondsPerSecond;
    callback(
      AppUpdateDownloadProgress(
        receivedBytes: receivedBytes,
        totalBytes: totalBytes,
        bytesPerSecond: elapsedSeconds > 0 ? receivedBytes / elapsedSeconds : 0,
      ),
    );
  }
}

/** 取消不需要继续读取的响应，避免服务器忽略 Range 时下载整份安装包。 */
Future<void> _cancelResponse(HttpClientResponse response) async {
  final subscription = response.listen(null);
  await subscription.cancel();
}

/** 删除当前更新目录内的已知临时文件；不存在时保持幂等。 */
Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}
