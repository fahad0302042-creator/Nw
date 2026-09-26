import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:kuroyomi/core/urls.dart';
import 'package:kuroyomi/extensions/extractor.dart';
import 'package:kuroyomi/extensions/manifest.dart';
import 'package:kuroyomi/extensions/rule.dart';

void main() {
  group('resolveUrl', () {
    test('keeps absolute urls', () {
      expect(resolveUrl('https://a.com', 'https://b.com/x'), 'https://b.com/x');
    });

    test('expands protocol relative urls', () {
      expect(resolveUrl('https://a.com', '//cdn.b.com/x.jpg'),
          'https://cdn.b.com/x.jpg');
    });

    test('resolves root relative urls against the origin', () {
      expect(resolveUrl('https://a.com/manga/list', '/series/1'),
          'https://a.com/series/1');
    });

    test('appends relative urls to the base', () {
      expect(resolveUrl('https://a.com/repo', 'demo/x.json'),
          'https://a.com/repo/demo/x.json');
    });
  });

  test('applyTemplate replaces placeholders', () {
    expect(
      applyTemplate('/search?q={query}&page={page}', {'query': 'one', 'page': '2'}),
      '/search?q=one&page=2',
    );
  });

  test('cleanExtractedUrl unescapes javascript style urls', () {
    expect(cleanExtractedUrl(r'https:\/\/cdn.site\/a.jpg'),
        'https://cdn.site/a.jpg');
  });

  group('Rule', () {
    test('parses css shorthand with attribute', () {
      final rule = Rule.fromJson('img@data-src');
      expect(rule.sel, 'img');
      expect(rule.attrCandidates, <String>['data-src']);
    });

    test('parses attribute fallback list', () {
      final rule = Rule.fromJson({'sel': 'img', 'attr': 'data-src, src'});
      expect(rule.attrCandidates, <String>['data-src', 'src']);
    });

    test('applies regex, prefix and suffix', () {
      final rule = Rule.fromJson({
        'regex': r'id-(\d+)',
        'group': 1,
        'prefix': 'https://site/series/',
      });
      expect(rule.apply('page id-4287 end'), 'https://site/series/4287');
    });

    test('returns null when the regex does not match', () {
      final rule = Rule.fromJson({'regex': r'nope-(\d+)'});
      expect(rule.apply('nothing here'), isNull);
    });

    test('strips unwanted text', () {
      final rule = Rule.fromJson({'strip': r'Chapter\s*'});
      expect(rule.apply('Chapter 12'), '12');
    });
  });

  group('html extraction', () {
    const html = '''
      <html><body>
        <div class="grid">
          <div class="card">
            <a href="/series/one"><h3>First Title</h3></a>
            <img data-src="/covers/one.jpg" src="lazy.gif">
          </div>
          <div class="card">
            <a href="/series/two"><h3>Second Title</h3></a>
            <img src="/covers/two.jpg">
          </div>
        </div>
        <span class="genre">Action</span>
        <span class="genre">Comedy</span>
      </body></html>
    ''';

    test('reads a list of nodes and their fields', () {
      final document = html_parser.parse(html);
      final cards = Extractor.htmlList(document, '.card');
      expect(cards.length, 2);

      expect(Extractor.htmlValue(cards[0], Rule.fromJson('h3')), 'First Title');
      expect(Extractor.htmlValue(cards[0], Rule.fromJson('a@href')), '/series/one');
      expect(
        Extractor.htmlValue(cards[0], Rule.fromJson({'sel': 'img', 'attr': 'data-src,src'})),
        '/covers/one.jpg',
      );
      expect(
        Extractor.htmlValue(cards[1], Rule.fromJson({'sel': 'img', 'attr': 'data-src,src'})),
        '/covers/two.jpg',
      );
    });

    test('collects repeated values', () {
      final document = html_parser.parse(html);
      expect(
        Extractor.htmlValues(document, Rule.fromJson('.genre')),
        <String>['Action', 'Comedy'],
      );
    });
  });

  group('json extraction', () {
    final data = json.decode('''
      {
        "data": {
          "items": [
            {"title": "One", "slug": "one", "cover": {"url": "/a.jpg"}, "tags": ["x", "y"]},
            {"title": "Two", "slug": "two", "cover": {"url": "/b.jpg"}, "tags": []}
          ]
        }
      }
    ''');

    test('walks dotted paths', () {
      final items = Extractor.jsonList(data, 'data.items');
      expect(items.length, 2);
      expect(Extractor.jsonValue(items[0], Rule.fromJson({'path': 'title'})), 'One');
      expect(
        Extractor.jsonValue(items[0], Rule.fromJson({'path': 'cover.url'})),
        '/a.jpg',
      );
    });

    test('supports array indexes', () {
      expect(
        Extractor.jsonValue(data, Rule.fromJson({'path': 'data.items[1].title'})),
        'Two',
      );
    });

    test('reads string lists', () {
      final items = Extractor.jsonList(data, 'data.items');
      expect(
        Extractor.jsonValues(items[0], Rule.fromJson({'path': 'tags'})),
        <String>['x', 'y'],
      );
    });

    test('returns the node itself for an empty path', () {
      expect(Extractor.jsonValue('plain-string', const Rule()), 'plain-string');
    });
  });

  group('SourceManifest', () {
    test('parses a manifest and aliases anime endpoints', () {
      final manifest = SourceManifest.fromJson(<String, dynamic>{
        'id': 'demo',
        'name': 'Demo',
        'type': 'anime',
        'baseUrl': 'https://example.com/',
        'parse': 'json',
        'endpoints': <String, dynamic>{
          'popular': <String, dynamic>{'url': 'p.json', 'items': 'series'},
          'episodes': <String, dynamic>{'url': '{url}', 'items': 'episodes'},
        },
      });

      expect(manifest.isAnime, isTrue);
      expect(manifest.baseUrl, 'https://example.com');
      expect(manifest.supports('chapters'), isTrue, reason: 'episodes alias');
      expect(manifest.endpoints['popular']!.items, 'series');
    });

    test('round trips through json so installs can be persisted', () {
      final original = <String, dynamic>{
        'id': 'demo',
        'name': 'Demo',
        'type': 'manga',
        'baseUrl': 'https://example.com',
        'endpoints': <String, dynamic>{
          'popular': <String, dynamic>{'url': 'p', 'items': '.card'},
        },
      };
      final restored = SourceManifest.fromJson(
        json.decode(json.encode(SourceManifest.fromJson(original).toJson()))
            as Map<String, dynamic>,
      );
      expect(restored.id, 'demo');
      expect(restored.supports('popular'), isTrue);
    });

    test('accepts inline field shorthand', () {
      final spec = NodeSpec.fromJson(<String, dynamic>{
        'url': 'list',
        'items': '.card',
        'title': 'h3',
        'thumbnail': 'img@src',
      });
      expect(spec.field('title')!.sel, 'h3');
      expect(spec.field('thumbnail')!.attrCandidates, <String>['src']);
    });
  });
}
