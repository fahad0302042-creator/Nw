import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuroyomi/extensions/repo_service.dart';

void main() {
  group('RepoService.normalise', () {
    test('leaves a json file url untouched', () {
      expect(
        RepoService.normalise('https://example.com/repo/index.json'),
        'https://example.com/repo/index.json',
      );
    });

    test('leaves index.min.json untouched', () {
      expect(
        RepoService.normalise('https://example.com/repo/index.min.json'),
        'https://example.com/repo/index.min.json',
      );
    });

    test('does not glue index.json onto a non-json file', () {
      // Regression: ".../repo/index.pb" used to become
      // ".../repo/index.pb/index.json" and 404.
      expect(
        RepoService.normalise(
          'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb',
        ),
        'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb',
      );
    });

    test('appends index.json to a directory url', () {
      expect(
        RepoService.normalise('https://example.com/myrepo'),
        'https://example.com/myrepo/index.json',
      );
      expect(
        RepoService.normalise('https://example.com/myrepo/'),
        'https://example.com/myrepo/index.json',
      );
    });

    test('rewrites GitHub blob links to raw', () {
      expect(
        RepoService.normalise(
          'https://github.com/user/repo/blob/main/index.json',
        ),
        'https://raw.githubusercontent.com/user/repo/main/index.json',
      );
    });

    test('adds a missing scheme', () {
      expect(
        RepoService.normalise('example.com/repo/index.json'),
        'https://example.com/repo/index.json',
      );
    });
  });

  group('RepoService.looksLikeApkRepo', () {
    test('detects a Tachiyomi/Mihon style index', () {
      final index = json.decode('''
        [
          {
            "name": "Some Source",
            "pkg": "eu.kanade.tachiyomi.extension.en.somesource",
            "apk": "some-source-v1.4.0.apk",
            "lang": "en",
            "code": 30,
            "sources": [{"name": "Some Source", "lang": "en", "id": "123"}]
          }
        ]
      ''') as List<dynamic>;
      expect(RepoService.looksLikeApkRepo(index), isTrue);
    });

    test('does not flag a Kuroyomi repository', () {
      final index = json.decode('''
        [
          {
            "id": "demo",
            "name": "Demo",
            "type": "manga",
            "baseUrl": "https://example.com",
            "endpoints": {"popular": {"url": "p", "items": ".card"}}
          }
        ]
      ''') as List<dynamic>;
      expect(RepoService.looksLikeApkRepo(index), isFalse);
    });
  });
}
