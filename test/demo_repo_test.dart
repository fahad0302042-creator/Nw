import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuroyomi/extensions/manifest.dart';

/// Validates the bundled demo repository without touching the network, so a
/// broken example never ships.
void main() {
  test('example_repo/index.json describes usable sources', () {
    final file = File('example_repo/index.json');
    expect(file.existsSync(), isTrue, reason: 'demo repo must exist');

    final decoded = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    final sources = decoded['sources'] as List<dynamic>;
    expect(sources, isNotEmpty);

    for (final raw in sources) {
      final manifest = SourceManifest.fromJson(
        (raw as Map).cast<String, dynamic>(),
      );
      expect(manifest.id, isNotEmpty);
      expect(manifest.baseUrl, startsWith('https://'));
      expect(manifest.supports('popular'), isTrue);
      expect(manifest.supports('details'), isTrue);
      expect(manifest.supports('chapters'), isTrue);
      if (manifest.isAnime) {
        expect(manifest.supports('video'), isTrue);
      } else {
        expect(manifest.supports('pages'), isTrue);
      }
    }
  });

  test('every referenced demo file exists', () {
    final dir = Directory('example_repo/demo');
    expect(dir.existsSync(), isTrue);

    final referenced = <String>{};
    for (final entity in dir.listSync().whereType<File>()) {
      final text = entity.readAsStringSync();
      for (final match
          in RegExp(r'"url"\s*:\s*"(demo/[^"]+)"').allMatches(text)) {
        referenced.add(match.group(1)!);
      }
    }

    for (final path in referenced) {
      expect(File('example_repo/$path').existsSync(), isTrue,
          reason: '$path is referenced but missing');
    }
  });
}
