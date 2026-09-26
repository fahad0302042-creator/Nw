import 'package:flutter_test/flutter_test.dart';
import 'package:kurayomi/domain/models/download.dart';
import 'package:kurayomi/domain/models/media.dart';

DownloadTask task({
  DownloadStatus status = DownloadStatus.queued,
  int done = 0,
  int total = 0,
}) =>
    DownloadTask(
      sourceId: 'en.test',
      type: MediaType.manga,
      itemUrl: '/series/1',
      itemTitle: 'Alpha',
      unitUrl: '/series/1/c/1',
      unitName: 'Chapter 1',
      status: status,
      completedParts: done,
      totalParts: total,
    );

void main() {
  test('key matches the (source, item, unit) identity used elsewhere', () {
    expect(task().key, 'en.test::/series/1::/series/1/c/1');
  });

  group('progress', () {
    test('is null when the total is unknown, rather than a fake zero', () {
      expect(task(done: 5).progress, isNull);
    });

    test('is a fraction once the total is known', () {
      expect(task(done: 5, total: 20).progress, 0.25);
    });

    test('is 1 when completed, whatever the counters say', () {
      expect(task(status: DownloadStatus.completed).progress, 1);
    });

    test('never exceeds 1 if a server over-reports', () {
      expect(task(done: 30, total: 20).progress, 1.0);
    });
  });

  group('status helpers', () {
    test('active covers queued and downloading only', () {
      expect(DownloadStatus.queued.isActive, isTrue);
      expect(DownloadStatus.downloading.isActive, isTrue);
      expect(DownloadStatus.paused.isActive, isFalse);
      expect(DownloadStatus.failed.isActive, isFalse);
    });
  });

  group('row round-trip', () {
    test('survives toRow/fromRow', () {
      final original = task(
        status: DownloadStatus.downloading,
        done: 3,
        total: 12,
      ).copyWith(id: 9, bytes: 4096);

      final restored = DownloadTask.fromRow({
        'id': 9,
        ...original.toRow(),
      });

      expect(restored.id, 9);
      expect(restored.key, original.key);
      expect(restored.status, DownloadStatus.downloading);
      expect(restored.completedParts, 3);
      expect(restored.totalParts, 12);
      expect(restored.bytes, 4096);
      expect(restored.type, MediaType.manga);
    });

    test('an unknown status falls back to queued instead of throwing', () {
      final restored = DownloadTask.fromRow({
        ...task().toRow(),
        'status': 'from-a-future-version',
      });
      expect(restored.status, DownloadStatus.queued);
    });
  });

  test('copyWith can clear an error when retrying', () {
    final failed = task(status: DownloadStatus.failed).copyWith(error: 'boom');
    expect(failed.error, 'boom');
    final retried =
        failed.copyWith(status: DownloadStatus.queued, clearError: true);
    expect(retried.error, isNull);
  });
}
