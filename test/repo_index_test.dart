import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurayomi/extensions/extension_repository.dart';

const indexUrl = 'https://example.com/repo/index.json';

RepoIndex parse(Object json) =>
    ExtensionRepository.parseIndex(jsonEncode(json), indexUrl);

void main() {
  group('valid Kurayomi repositories', () {
    test('parses an object with an extensions list', () {
      final repo = parse({
        'name': 'Demo',
        'extensions': [
          {
            'id': 'en.example',
            'name': 'Example',
            'version': '1.0.0',
            'lang': 'en',
            'type': 'manga',
            'code': 'src/en.example/index.js',
          }
        ],
      });

      expect(repo.name, 'Demo');
      expect(repo.extensions.length, 1);
      expect(repo.extensions.first.codeUrl,
          'https://example.com/repo/src/en.example/index.js');
    });

    test('accepts a bare array and names it after the host', () {
      final repo = parse([
        {'id': 'a', 'name': 'A', 'code': 'a.js'}
      ]);
      expect(repo.name, 'example.com');
      expect(repo.extensions.single.codeUrl, 'https://example.com/repo/a.js');
    });

    test('resolves an absolute code URL unchanged', () {
      final repo = parse({
        'extensions': [
          {'id': 'a', 'name': 'A', 'code': 'https://cdn.test/a.js'}
        ]
      });
      expect(repo.extensions.single.codeUrl, 'https://cdn.test/a.js');
    });

    test('an empty repository is allowed', () {
      expect(parse({'name': 'Empty', 'extensions': []}).extensions, isEmpty);
    });
  });

  group('Mihon / Tachiyomi / Keiyoushi repositories', () {
    // The real shape: note "code" is an integer version code, not a path.
    List<Map<String, Object>> keiyoushiEntries() => [
          for (var i = 0; i < 4; i++)
            {
              'name': 'Tachiyomi: Source $i',
              'pkg': 'eu.kanade.tachiyomi.extension.en.source$i',
              'apk': 'tachiyomi-en.source$i-v1.4.$i.apk',
              'lang': 'en',
              'code': 84,
              'version': '1.4.$i',
              'nsfw': 0,
              'sources': [
                {'name': 'Source $i', 'lang': 'en', 'id': '$i'}
              ],
            }
        ];

    test('are refused with an explanation, not imported as junk', () {
      // Without this check the integer "code" resolves to a plausible URL
      // and hundreds of broken extensions get imported silently.
      expect(
        () => parse(keiyoushiEntries()),
        throwsA(isA<RepoException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('Mihon'),
            contains('compiled Android'),
            contains('4 entries'),
          ),
        )),
      );
    });

    test('the refusal points at the JavaScript format instead', () {
      try {
        parse(keiyoushiEntries());
        fail('should have thrown');
      } on RepoException catch (e) {
        expect(e.message, contains('EXTENSIONS.md'));
      }
    });
  });

  group('malformed input', () {
    test('rejects JSON without an extensions list', () {
      expect(() => parse({'name': 'Nope'}),
          throwsA(isA<RepoException>().having((e) => e.message, 'message',
              contains('no "extensions" list'))));
    });

    test('rejects a JSON scalar', () {
      expect(() => ExtensionRepository.parseIndex('42', indexUrl),
          throwsA(isA<RepoException>()));
    });

    test('rejects entries that all lack a string code path', () {
      expect(
        () => parse({
          'extensions': [
            {'id': 'a', 'name': 'A'},
            {'id': 'b', 'name': 'B', 'code': ''},
          ]
        }),
        throwsA(isA<RepoException>().having((e) => e.message, 'message',
            contains('none had a JavaScript "code" path'))),
      );
    });

    test('an HTML body explains itself instead of dumping bytes', () {
      expect(
        () => ExtensionRepository.parseIndex(
            '<!DOCTYPE html><html><body>hi</body></html>',
            'https://github.com/a/b'),
        throwsA(isA<RepoException>().having(
          (e) => e.message,
          'message',
          allOf(contains('web page'), contains('Raw')),
        )),
      );
    });

    test('a ZIP/APK body says so', () {
      expect(
        () => ExtensionRepository.parseIndex('PK\u0003\u0004binary', indexUrl),
        throwsA(isA<RepoException>()
            .having((e) => e.message, 'message', contains('ZIP or APK'))),
      );
    });

    test('binary noise is described, never echoed', () {
      final junk = String.fromCharCodes([0xFFFD, 0x01, 0x02, 0xFFFD, 0x03,
        0x04, 0xFFFD, 0x05, 0xFFFD, 0x06]);
      try {
        ExtensionRepository.parseIndex(junk, indexUrl);
        fail('should have thrown');
      } on RepoException catch (e) {
        expect(e.message, contains('binary data'));
        expect(e.message, isNot(contains('\u0001')));
      }
    });
  });
}
