import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku/core/source/source_engine.dart';
import 'package:tsundoku/models/extension_manifest.dart';

/// Reads a bundled extension straight off disk (not via rootBundle, which
/// needs a real Flutter asset bundle) so these tests run fast under plain
/// `flutter test` with zero platform/network dependencies.
ExtensionManifest _loadManifest(String fileName) {
  final file = File('assets/extensions/$fileName');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return ExtensionManifest.fromJson(json);
}

void main() {
  const engine = SourceEngine();

  test('demo_manga.json: full offline browse -> chapters -> pages pipeline', () async {
    final ext = _loadManifest('demo_manga.json');
    expect(ext.isManga, isTrue);

    final popular = await engine.fetchList(ext, ext.popular!);
    expect(popular, isNotEmpty);

    final chapters = await engine.fetchChapters(ext, ext.chapters!, popular.first.url);
    expect(chapters, isNotEmpty);

    final pages = await engine.fetchPages(ext, ext.pages!, chapters.first.url);
    expect(pages, isNotEmpty);
    for (final page in pages) {
      expect(page.url, startsWith('http'));
    }
  });

  test('demo_anime.json: full offline browse -> episodes -> video pipeline', () async {
    final ext = _loadManifest('demo_anime.json');
    expect(ext.isAnime, isTrue);

    final popular = await engine.fetchList(ext, ext.popular!);
    expect(popular, isNotEmpty);

    final episodes = await engine.fetchChapters(ext, ext.chapters!, popular.first.url);
    expect(episodes, isNotEmpty);

    final videos = await engine.fetchPages(ext, ext.pages!, episodes.first.url);
    expect(videos, hasLength(1));
    expect(videos.first.url, episodes.first.url);
  });

  test('mangadex.json: manifest parses and declares all pipeline endpoints', () {
    final ext = _loadManifest('mangadex.json');
    expect(ext.isManga, isTrue);
    expect(ext.popular, isNotNull);
    expect(ext.latest, isNotNull);
    expect(ext.search, isNotNull);
    expect(ext.detail, isNotNull);
    expect(ext.chapters, isNotNull);
    expect(ext.pages, isNotNull);
    expect(ext.pages!.mode, 'compose');
  });
}
