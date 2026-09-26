import 'package:flutter_test/flutter_test.dart';
import 'package:kurayomi/data/download/download_storage.dart';

void main() {
  group('sanitize', () {
    test('strips characters no filesystem accepts', () {
      expect(DownloadStorage.sanitize('One/Piece: Chapter <1>?'),
          'One_Piece_ Chapter _1__');
      expect(DownloadStorage.sanitize(r'a\b|c*d'), 'a_b_c_d');
    });

    test('drops trailing dots and spaces', () {
      // Some filesystems silently strip these, which would make the path we
      // recorded differ from the one on disk.
      expect(DownloadStorage.sanitize('Chapter 1.  '), 'Chapter 1');
      expect(DownloadStorage.sanitize('Volume 3...'), 'Volume 3');
    });

    test('collapses whitespace and never returns empty', () {
      expect(DownloadStorage.sanitize('a   \n  b'), 'a b');
      expect(DownloadStorage.sanitize('   '), 'untitled');
      expect(DownloadStorage.sanitize('...'), 'untitled');
    });

    test('caps the length to stay under the per-component limit', () {
      final long = 'x' * 400;
      expect(DownloadStorage.sanitize(long).length, lessThanOrEqualTo(120));
    });

    test('keeps non-latin titles intact', () {
      expect(DownloadStorage.sanitize('ワンピース'), 'ワンピース');
    });
  });

  group('extensionFor', () {
    test('reads the extension, ignoring query strings', () {
      expect(DownloadStorage.extensionFor('https://cdn/a/1.jpg?token=x'), '.jpg');
      expect(DownloadStorage.extensionFor('https://cdn/a/1.WEBP'), '.webp');
    });

    test('falls back when the URL has no usable extension', () {
      expect(DownloadStorage.extensionFor('https://cdn/image?id=5'), '.jpg');
      expect(
          DownloadStorage.extensionFor('https://cdn/stream', fallback: '.mp4'),
          '.mp4');
    });

    test('rejects an extension that is not a media type', () {
      // A .php endpoint serving an image must not produce "video.php".
      expect(DownloadStorage.extensionFor('https://cdn/img.php'), '.jpg');
    });
  });

  group('formatBytes', () {
    test('scales units and keeps the output short', () {
      expect(DownloadStorage.formatBytes(512), '512 B');
      expect(DownloadStorage.formatBytes(2048), '2.0 KB');
      expect(DownloadStorage.formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(DownloadStorage.formatBytes(1536 * 1024 * 1024), '1.5 GB');
      expect(DownloadStorage.formatBytes(20 * 1024 * 1024), '20 MB');
    });
  });
}
