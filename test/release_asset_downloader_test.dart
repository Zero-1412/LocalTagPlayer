import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/update/data/release_asset_downloader.dart';
import 'package:local_tag_player/src/features/update/domain/app_release.dart';

void main() {
  test('Release 下载器在 Range 可用时使用四段并行并合并原始字节', () async {
    final payload = List<int>.generate(
      5 * 1024 * 1024,
      (index) => index % 251,
    );
    final requestedRanges = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range == null) {
        request.response
          ..statusCode = HttpStatus.ok
          ..contentLength = payload.length
          ..add(payload);
      } else {
        requestedRanges.add(range);
        final match = RegExp(r'^bytes=([0-9]+)-([0-9]+)$').firstMatch(range)!;
        final start = int.parse(match.group(1)!);
        final end = int.parse(match.group(2)!);
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${payload.length}',
          )
          ..contentLength = end - start + 1
          ..add(payload.sublist(start, end + 1));
      }
      await request.response.close();
    });
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('ltp-update-range-test-');
    final partialFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}setup.exe.part',
    );
    final progress = <AppUpdateDownloadProgress>[];
    final client = HttpClient();

    try {
      await ReleaseAssetDownloader(httpClient: client).download(
        url: Uri.parse('http://127.0.0.1:${server.port}/setup.exe'),
        partialFile: partialFile,
        userAgent: 'LocalTagPlayer/test',
        onProgress: progress.add,
      );

      expect(await partialFile.readAsBytes(), payload);
      expect(requestedRanges.first, 'bytes=0-0');
      expect(
        requestedRanges.where((range) => range != 'bytes=0-0'),
        hasLength(4),
      );
      expect(progress.last.receivedBytes, payload.length);
      expect(progress.last.totalBytes, payload.length);
      expect(progress.last.bytesPerSecond, greaterThan(0));
    } finally {
      client.close(force: true);
      await server.close(force: true);
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('Release 下载器在服务端忽略 Range 时回退单流', () async {
    final payload = List<int>.generate(
      128 * 1024,
      (index) => index % 239,
    );
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requestCount += 1;
      request.response
        ..statusCode = HttpStatus.ok
        ..contentLength = payload.length
        ..add(payload);
      await request.response.close();
    });
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('ltp-update-single-test-');
    final partialFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}setup.exe.part',
    );
    final client = HttpClient();

    try {
      await ReleaseAssetDownloader(httpClient: client).download(
        url: Uri.parse('http://127.0.0.1:${server.port}/setup.exe'),
        partialFile: partialFile,
        userAgent: 'LocalTagPlayer/test',
      );

      expect(await partialFile.readAsBytes(), payload);
      expect(requestCount, 1);
    } finally {
      client.close(force: true);
      await server.close(force: true);
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('Release 下载器对单个 Range 瞬时错误重试一次', () async {
    final payload = List<int>.generate(
      5 * 1024 * 1024,
      (index) => index % 233,
    );
    var failedOnce = false;
    var rangeRequestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader)!;
      final match = RegExp(r'^bytes=([0-9]+)-([0-9]+)$').firstMatch(range)!;
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2)!);
      if (range != 'bytes=0-0') {
        rangeRequestCount += 1;
      }
      if (range != 'bytes=0-0' && !failedOnce) {
        failedOnce = true;
        request.response.statusCode = HttpStatus.serviceUnavailable;
      } else {
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${payload.length}',
          )
          ..contentLength = end - start + 1
          ..add(payload.sublist(start, end + 1));
      }
      await request.response.close();
    });
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('ltp-update-retry-test-');
    final partialFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}setup.exe.part',
    );
    final client = HttpClient();

    try {
      await ReleaseAssetDownloader(httpClient: client).download(
        url: Uri.parse('http://127.0.0.1:${server.port}/setup.exe'),
        partialFile: partialFile,
        userAgent: 'LocalTagPlayer/test',
      );

      expect(await partialFile.readAsBytes(), payload);
      expect(failedOnce, isTrue);
      expect(rangeRequestCount, 5);
    } finally {
      client.close(force: true);
      await server.close(force: true);
      await temporaryDirectory.delete(recursive: true);
    }
  });
}
