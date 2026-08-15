import 'package:flutter_test/flutter_test.dart';

import 'package:local_tag_player/src/models/video_item.dart';
import 'package:local_tag_player/src/services/library/video_similarity_service.dart';

void main() {
  test('groups only valid videos with the same fingerprint', () {
    final report = VideoSimilarityReport.fromVideos([
      _video('zeta', '/library/zeta.mp4', fingerprint: 'v2:10:abc'),
      _video('alpha', '/library/alpha.mp4', fingerprint: 'v2:10:abc'),
      _video('unique', '/library/unique.mp4', fingerprint: 'v2:11:def'),
    ]);

    expect(report.indexedVideoCount, 3);
    expect(report.unindexedVideoCount, 0);
    expect(report.missingVideoCount, 0);
    expect(report.duplicateGroupCount, 1);
    expect(report.duplicateVideoCount, 2);
    expect(report.duplicateExtraCount, 1);
    expect(report.groups.single.videos.map((item) => item.title),
        ['alpha', 'zeta']);
  });

  test('does not compare missing or unindexed records', () {
    final report = VideoSimilarityReport.fromVideos([
      _video('missing', '/gone/missing.mp4',
          fingerprint: 'same', isMissing: true),
      _video('not-indexed', '/library/not-indexed.mp4'),
      _video('indexed', '/library/indexed.mp4', fingerprint: 'same'),
    ]);

    expect(report.groups, isEmpty);
    expect(report.indexedVideoCount, 1);
    expect(report.unindexedVideoCount, 1);
    expect(report.missingVideoCount, 1);
  });

  test('trims fingerprints and uses videoId as the final stable tie breaker',
      () {
    final first = _video('same', '/library/same-a.mp4', fingerprint: '  same ');
    final second = _video('same', '/library/same-b.mp4', fingerprint: 'same');
    final report = VideoSimilarityReport.fromVideos([second, first]);

    expect(report.groups.single.fingerprint, 'same');
    expect(report.groups.single.videos.map((item) => item.path), [
      '/library/same-a.mp4',
      '/library/same-b.mp4',
    ]);
  });
}

VideoItem _video(
  String title,
  String path, {
  String? fingerprint,
  bool isMissing = false,
}) {
  return VideoItem(
    videoId: path,
    path: path,
    title: title,
    folder: '/library',
    tags: <String>{},
    addedAt: DateTime(2024),
    mediaFingerprint: fingerprint,
    isMissing: isMissing,
  );
}
