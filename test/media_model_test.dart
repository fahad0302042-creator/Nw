import 'package:flutter_test/flutter_test.dart';
import 'package:kurayomi/domain/models/media.dart';

void main() {
  group('MediaType', () {
    test('parses safely and defaults to manga', () {
      expect(MediaTypeX.parse('anime'), MediaType.anime);
      expect(MediaTypeX.parse('manga'), MediaType.manga);
      expect(MediaTypeX.parse('nonsense'), MediaType.manga);
      expect(MediaTypeX.parse(null), MediaType.manga);
    });

    test('uses the right word for the medium', () {
      expect(MediaType.manga.unitLabel, 'Chapter');
      expect(MediaType.anime.unitLabelPlural, 'Episodes');
    });
  });

  group('parseStatus', () {
    test('accepts the many spellings sources use', () {
      expect(parseStatus('Ongoing'), MediaStatus.ongoing);
      expect(parseStatus('RELEASING'), MediaStatus.ongoing);
      expect(parseStatus(1), MediaStatus.ongoing);
      expect(parseStatus('finished'), MediaStatus.completed);
      expect(parseStatus('canceled'), MediaStatus.cancelled);
      expect(parseStatus('cancelled'), MediaStatus.cancelled);
      expect(parseStatus(null), MediaStatus.unknown);
      expect(parseStatus('???'), MediaStatus.unknown);
    });
  });

  group('MediaItem.fromJson', () {
    test('reads the canonical shape', () {
      final item = MediaItem.fromJson({
        'url': '/series/1',
        'title': 'Alpha',
        'thumbnailUrl': 'https://c/1.jpg',
        'genres': ['Action', 'Drama'],
        'status': 'ongoing',
      }, sourceId: 'en.test', type: MediaType.manga);

      expect(item.url, '/series/1');
      expect(item.title, 'Alpha');
      expect(item.genres, ['Action', 'Drama']);
      expect(item.status, MediaStatus.ongoing);
      expect(item.key, 'en.test::/series/1');
    });

    test('accepts a comma-separated genre string, as many sources emit', () {
      final item = MediaItem.fromJson({
        'url': '/x',
        'title': 'X',
        'genre': 'Action, Romance ,  Comedy',
      }, sourceId: 's', type: MediaType.manga);
      expect(item.genres, ['Action', 'Romance', 'Comedy']);
    });

    test('tolerates a thin listing payload', () {
      final item = MediaItem.fromJson(
          {'url': '/x', 'title': 'X'}, sourceId: 's', type: MediaType.anime);
      expect(item.thumbnailUrl, isNull);
      expect(item.genres, isEmpty);
      expect(item.status, MediaStatus.unknown);
      expect(item.initialized, isFalse);
    });

    test('falls back to "cover" for the thumbnail key', () {
      final item = MediaItem.fromJson(
          {'url': '/x', 'title': 'X', 'cover': 'https://c.jpg'},
          sourceId: 's', type: MediaType.manga);
      expect(item.thumbnailUrl, 'https://c.jpg');
    });
  });

  group('mergeDetails', () {
    test('keeps local-only state and never regresses to null', () {
      const cached = MediaItem(
        id: 7,
        sourceId: 's',
        type: MediaType.manga,
        url: '/x',
        title: 'Cached title',
        thumbnailUrl: 'https://old.jpg',
        description: 'old description',
        inLibrary: true,
      );

      const fresh = MediaItem(
        sourceId: 's',
        type: MediaType.manga,
        url: '/x',
        title: 'Fresh title',
        description: 'new description',
      );

      final merged = cached.mergeDetails(fresh);

      expect(merged.id, 7, reason: 'local row id must survive');
      expect(merged.inLibrary, isTrue, reason: 'library membership is local');
      expect(merged.title, 'Fresh title');
      expect(merged.description, 'new description');
      expect(merged.thumbnailUrl, 'https://old.jpg',
          reason: 'a null from the source must not wipe a cached cover');
      expect(merged.initialized, isTrue);
    });
  });

  group('MediaUnit.fromJson', () {
    test('accepts name or title, and numeric strings', () {
      final u = MediaUnit.fromJson({
        'url': '/c/1',
        'title': 'Chapter 1',
        'number': '1.5',
        'dateUpload': 1711929600000,
      });
      expect(u.name, 'Chapter 1');
      expect(u.number, 1.5);
      expect(u.dateUpload, isNotNull);
    });

    test('defaults an unknown number to -1 rather than throwing', () {
      final u = MediaUnit.fromJson({'url': '/c', 'name': 'Oneshot'});
      expect(u.number, -1);
      expect(u.dateUpload, isNull);
    });
  });

  group('ReaderPage.fromJson', () {
    test('accepts a bare URL string', () {
      final p = ReaderPage.fromJson(0, 'https://cdn/1.jpg');
      expect(p.imageUrl, 'https://cdn/1.jpg');
      expect(p.headers, isNull);
    });

    test('accepts an object with custom headers', () {
      final p = ReaderPage.fromJson(2, {
        'url': 'https://cdn/3.jpg',
        'headers': {'Referer': 'https://site/'},
      });
      expect(p.index, 2);
      expect(p.headers!['Referer'], 'https://site/');
    });
  });

  group('VideoStream.fromJson', () {
    test('parses quality, headers and subtitles', () {
      final v = VideoStream.fromJson({
        'url': 'https://cdn/master.m3u8',
        'quality': '1080p',
        'headers': {'Referer': 'https://site/'},
        'subtitles': [
          {'url': 'https://cdn/en.vtt', 'label': 'English'}
        ],
      });
      expect(v.quality, '1080p');
      expect(v.headers!['Referer'], 'https://site/');
      expect(v.subtitles.single.label, 'English');
    });

    test('defaults quality when the source omits it', () {
      final v = VideoStream.fromJson({'url': 'https://cdn/a.mp4'});
      expect(v.quality, 'Default');
    });
  });
}
