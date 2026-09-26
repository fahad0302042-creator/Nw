import 'package:flutter_test/flutter_test.dart';
import 'package:kurayomi/data/download/hls.dart';

void main() {
  group('looksLikeHls', () {
    test('recognises playlists, including with query strings', () {
      expect(Hls.looksLikeHls('https://cdn/master.m3u8'), isTrue);
      expect(Hls.looksLikeHls('https://cdn/master.m3u8?token=abc'), isTrue);
      expect(Hls.looksLikeHls('https://cdn/video.mp4'), isFalse);
    });
  });

  group('parse', () {
    test('reads a master playlist and resolves relative URIs', () {
      const body = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
360/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2400000,RESOLUTION=1280x720
720/index.m3u8
''';
      final p = Hls.parse(body, 'https://cdn.test/video/master.m3u8');

      expect(p.isMaster, isTrue);
      expect(p.variants.length, 2);
      expect(p.variants.first.url, 'https://cdn.test/video/360/index.m3u8');
      expect(p.variants.last.resolution, '1280x720');

      final best = Hls.bestVariant(p)!;
      expect(best.bandwidth, 2400000);
      expect(best.url, 'https://cdn.test/video/720/index.m3u8');
    });

    test('reads a media playlist in order', () {
      const body = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
seg0.ts
#EXTINF:10.0,
seg1.ts
#EXT-X-ENDLIST
''';
      final p = Hls.parse(body, 'https://cdn.test/v/index.m3u8');

      expect(p.isMaster, isFalse);
      expect(p.segments, [
        'https://cdn.test/v/seg0.ts',
        'https://cdn.test/v/seg1.ts',
      ]);
      expect(p.encrypted, isFalse);
    });

    test('flags encrypted playlists so we refuse them up front', () {
      const body = '''
#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="key.bin"
#EXTINF:10.0,
seg0.ts
''';
      expect(Hls.parse(body, 'https://cdn.test/v/i.m3u8').encrypted, isTrue);
    });

    test('METHOD=NONE is not encryption', () {
      const body = '''
#EXTM3U
#EXT-X-KEY:METHOD=NONE
#EXTINF:10.0,
seg0.ts
''';
      final p = Hls.parse(body, 'https://cdn.test/v/i.m3u8');
      expect(p.encrypted, isFalse);
      expect(p.segments.length, 1);
    });

    test('captures the fMP4 init segment', () {
      const body = '''
#EXTM3U
#EXT-X-MAP:URI="init.mp4"
#EXTINF:6.0,
seg0.m4s
''';
      final p = Hls.parse(body, 'https://cdn.test/v/i.m3u8');
      expect(p.initSegment, 'https://cdn.test/v/init.mp4');
      expect(p.segments, ['https://cdn.test/v/seg0.m4s']);
    });

    test('handles absolute segment URIs and CRLF line endings', () {
      const body = '#EXTM3U\r\n#EXTINF:10.0,\r\nhttps://other.test/a.ts\r\n';
      final p = Hls.parse(body, 'https://cdn.test/v/i.m3u8');
      expect(p.segments, ['https://other.test/a.ts']);
    });
  });
}
