import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurayomi/extensions/extension_repository.dart';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('decodeBody', () {
    const json = '{"name":"Demo","extensions":[]}';

    test('passes plain UTF-8 through untouched', () {
      expect(ExtensionRepository.decodeBody(bytes(json)), json);
    });

    test('gunzips a body the HTTP stack did not unwrap', () {
      // This is the actual bug: a gzipped body reaching jsonDecode produced
      // a screenful of mojibake instead of an error.
      final gz = Uint8List.fromList(gzip.encode(utf8.encode(json)));
      expect(gz[0], 0x1f);
      expect(ExtensionRepository.decodeBody(gz), json);
    });

    test('handles a double-gzipped body', () {
      final once = gzip.encode(utf8.encode(json));
      final twice = Uint8List.fromList(gzip.encode(once));
      expect(ExtensionRepository.decodeBody(twice), json);
    });

    test('inflates a raw zlib body', () {
      final z = Uint8List.fromList(zlib.encode(utf8.encode(json)));
      expect(ExtensionRepository.decodeBody(z), json);
    });

    test('strips a UTF-8 BOM, which jsonDecode rejects', () {
      final withBom = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(json)]);
      final decoded = ExtensionRepository.decodeBody(withBom);
      expect(decoded, json);
      expect(() => jsonDecode(decoded), returnsNormally);
    });

    test('preserves non-latin text', () {
      const unicode = '{"name":"ワンピース"}';
      expect(ExtensionRepository.decodeBody(bytes(unicode)), unicode);
    });

    test('never throws on genuinely binary input', () {
      // Must degrade to replacement characters so the caller can produce a
      // readable diagnosis rather than crashing.
      final junk = Uint8List.fromList([0x00, 0xC3, 0x28, 0xA0, 0xA1, 0xFF]);
      expect(() => ExtensionRepository.decodeBody(junk), returnsNormally);
    });
  });
}
