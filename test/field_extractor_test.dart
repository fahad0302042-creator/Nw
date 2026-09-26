import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tsundoku/core/source/field_extractor.dart';
import 'package:tsundoku/models/field_spec.dart';

void main() {
  group('extractFields (html)', () {
    test('reads text, attribute, list and template fields', () {
      final doc = html_parser.parse('''
        <div class="item">
          <a class="link" href="/manga/42"><img class="cover" src="cover.jpg"/>
          <span class="title">Cool Manga</span></a>
          <div class="genres"><span>Action</span><span>Comedy</span></div>
        </div>
      ''');
      final root = doc.querySelector('.item')!;

      final fields = {
        'url': const FieldSpec(selector: 'a.link', attr: 'href', absolute: true),
        'title': const FieldSpec(selector: '.title'),
        'cover': const FieldSpec(selector: '.cover', attr: 'src', absolute: true),
        'genres': const FieldSpec(selector: '.genres span', list: true),
        'combo': const FieldSpec(template: '{title} @ {url}'),
      };

      final extracted = extractFields(root, fields, 'html', 'https://example.com');

      expect(extracted['url'], 'https://example.com/manga/42');
      expect(extracted['title'], 'Cool Manga');
      expect(extracted['cover'], 'https://example.com/cover.jpg');
      expect(extracted['genres'], ['Action', 'Comedy']);
      expect(extracted['combo'], 'Cool Manga @ https://example.com/manga/42');
    });
  });

  group('extractFields (json)', () {
    test('reads paths, filtered relationships and list sub-paths', () {
      final item = {
        'id': 'abc123',
        'attributes': {
          'title': {'en': 'Great Story'}
        },
        'relationships': [
          {
            'type': 'cover_art',
            'attributes': {'fileName': 'x.png'}
          }
        ],
        'tags': [
          {'attributes': {'name': {'en': 'Action'}}},
          {'attributes': {'name': {'en': 'Drama'}}},
        ],
      };

      final fields = {
        'id': const FieldSpec(path: 'id'),
        'title': const FieldSpec(path: 'attributes.title.en'),
        'coverFile': const FieldSpec(path: 'relationships.type=cover_art.attributes.fileName'),
        'cover': const FieldSpec(template: 'https://cdn/{id}/{coverFile}.jpg'),
        'genres': const FieldSpec(list: true, path: 'tags', itemPath: 'attributes.name.en'),
      };

      final extracted = extractFields(item, fields, 'json', 'https://example.com');

      expect(extracted['id'], 'abc123');
      expect(extracted['title'], 'Great Story');
      expect(extracted['coverFile'], 'x.png');
      expect(extracted['cover'], 'https://cdn/abc123/x.png.jpg');
      expect(extracted['genres'], ['Action', 'Drama']);
    });
  });
}
