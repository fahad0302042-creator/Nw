import 'package:flutter_test/flutter_test.dart';
import 'package:kurayomi/domain/models/media.dart';
import 'package:kurayomi/extensions/extension.dart';

ExtensionInfo info(String version) => ExtensionInfo(
      id: 'en.test',
      name: 'Test',
      version: version,
      lang: 'en',
      type: MediaType.manga,
      codeUrl: 'https://r/code.js',
    );

void main() {
  group('ExtensionInfo.isNewerThan', () {
    test('compares numerically, not lexically', () {
      // The classic bug: '1.10.0' < '1.9.0' under string comparison.
      expect(info('1.10.0').isNewerThan('1.9.0'), isTrue);
      expect(info('1.9.0').isNewerThan('1.10.0'), isFalse);
    });

    test('handles unequal segment counts', () {
      expect(info('1.2.1').isNewerThan('1.2'), isTrue);
      expect(info('1.2').isNewerThan('1.2.0'), isFalse);
      expect(info('2').isNewerThan('1.9.9'), isTrue);
    });

    test('is false for identical versions, so no phantom updates appear', () {
      expect(info('1.0.0').isNewerThan('1.0.0'), isFalse);
    });

    test('survives suffixes without crashing', () {
      expect(info('1.2.3-beta.2').isNewerThan('1.2.3-beta.1'), isTrue);
      expect(info('nonsense').isNewerThan('1.0.0'), isFalse);
    });
  });

  group('ExtensionInfo JSON', () {
    test('round-trips through toJson/fromJson', () {
      final original = ExtensionInfo(
        id: 'en.x',
        name: 'X',
        version: '2.1.0',
        lang: 'es',
        type: MediaType.anime,
        codeUrl: 'https://r/x.js',
        iconUrl: 'https://r/x.png',
        nsfw: true,
        description: 'hello',
      );
      final restored = ExtensionInfo.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.version, original.version);
      expect(restored.type, MediaType.anime);
      expect(restored.nsfw, isTrue);
      expect(restored.codeUrl, original.codeUrl);
      expect(restored.iconUrl, original.iconUrl);
    });

    test('defaults a missing type to manga and version to 1.0.0', () {
      final e = ExtensionInfo.fromJson({'id': 'a', 'name': 'A', 'code': 'a.js'});
      expect(e.type, MediaType.manga);
      expect(e.version, '1.0.0');
      expect(e.lang, 'en');
    });
  });
}
