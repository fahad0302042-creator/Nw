import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku/core/source/source_engine.dart';
import 'package:tsundoku/models/extension_manifest.dart';
import 'package:tsundoku/models/list_endpoint.dart';
import 'package:tsundoku/models/pages_endpoint.dart';

void main() {
  const engine = SourceEngine();

  final manifest = ExtensionManifest.fromJson({
    'id': 'demo',
    'name': 'Demo',
    'lang': 'en',
    'version': '1.0.0',
    'type': 'manga',
    'baseUrl': 'https://example.com',
  });

  group('fetchList (static mode, no network)', () {
    test('maps static items through field specs', () async {
      final endpoint = ListEndpoint.fromJson({
        'responseType': 'static',
        'items': [
          {'id': '1', 'title': 'First', 'cover': 'https://example.com/1.jpg'},
          {'id': '2', 'title': 'Second', 'cover': 'https://example.com/2.jpg'},
        ],
        'fields': {
          'id': {'path': 'id'},
          'title': {'path': 'title'},
          'cover': {'path': 'cover'},
        },
      });

      final result = await engine.fetchList(manifest, endpoint);

      expect(result, hasLength(2));
      expect(result[0].url, '1');
      expect(result[0].title, 'First');
      expect(result[1].title, 'Second');
    });
  });

  group('fetchChapters (static mode, no network)', () {
    test('parses chapter number and title', () async {
      final endpoint = ListEndpoint.fromJson({
        'responseType': 'static',
        'items': [
          {'id': 'ch1', 'number': 1, 'title': 'Chapter 1'},
        ],
        'fields': {
          'id': {'path': 'id'},
          'number': {'path': 'number'},
          'title': {'path': 'title'},
        },
      });

      final result = await engine.fetchChapters(manifest, endpoint, 'manga-1');

      expect(result, hasLength(1));
      expect(result.first.url, 'ch1');
      expect(result.first.number, 1.0);
      expect(result.first.title, 'Chapter 1');
    });
  });

  group('fetchPages', () {
    test('static mode returns inline items', () async {
      final pages = PagesEndpoint.fromJson({
        'mode': 'simple',
        'responseType': 'static',
        'items': ['https://example.com/p1.jpg', 'https://example.com/p2.jpg'],
      });

      final result = await engine.fetchPages(manifest, pages, 'ch1');

      expect(result.map((p) => p.url), [
        'https://example.com/p1.jpg',
        'https://example.com/p2.jpg',
      ]);
    });

    test('echo mode returns the chapter url itself', () async {
      final pages = PagesEndpoint.fromJson({'mode': 'echo'});

      final result = await engine.fetchPages(
        manifest,
        pages,
        'https://cdn.example.com/video.mp4',
      );

      expect(result, hasLength(1));
      expect(result.first.url, 'https://cdn.example.com/video.mp4');
    });
  });
}
