import 'dart:convert';

import '../core/net.dart';
import '../core/urls.dart';
import 'engine.dart';
import 'manifest.dart';

/// Loads extension repositories.
///
/// A repository is a single json file. Two shapes are accepted:
///
/// ```json
/// { "name": "My repo", "sources": [ { ...full manifest... } ] }
/// ```
/// ```json
/// { "name": "My repo", "sources": [ { "name": "X", "url": "sources/x.json" } ] }
/// ```
///
/// A bare array of sources works too.
class RepoService {
  const RepoService();

  Future<RepoResult> load(String repoUrl) async {
    final url = normalise(repoUrl);

    // index.pb is the protobuf flavour of the Tachiyomi/Mihon index; there is
    // nothing useful we could do with it even if it downloaded fine.
    if (url.toLowerCase().endsWith('.pb')) {
      throw ExtensionError(apkRepoMessage);
    }

    final text = await Net.fetch(url);
    final dynamic decoded;
    try {
      decoded = json.decode(text);
    } catch (_) {
      throw ExtensionError(
        'That url did not return valid JSON.\nMake sure you are using the raw '
        'file link (raw.githubusercontent.com), not the GitHub page.',
      );
    }

    String name = 'Repository';
    List<dynamic> rawSources;

    if (decoded is List) {
      rawSources = decoded;
    } else if (decoded is Map) {
      name = (decoded['name'] ?? 'Repository').toString();
      final list = decoded['sources'] ?? decoded['extensions'] ?? decoded['items'];
      if (list is! List) {
        throw ExtensionError('Repository json has no "sources" array.');
      }
      rawSources = list;
    } else {
      throw ExtensionError('Unsupported repository format.');
    }

    if (looksLikeApkRepo(rawSources)) {
      throw ExtensionError(apkRepoMessage);
    }

    final sources = <SourceManifest>[];
    for (final entry in rawSources) {
      if (entry is! Map) continue;
      final map = entry.cast<String, dynamic>();
      if (map.containsKey('endpoints')) {
        sources.add(SourceManifest.fromJson(map, repoUrl: url));
        continue;
      }
      // Indirect entry: fetch the referenced manifest file.
      final ref = map['url']?.toString() ?? map['file']?.toString();
      if (ref == null || ref.isEmpty) continue;
      try {
        final manifestUrl = resolveUrl(_parentOf(url), ref);
        final manifestText = await Net.fetch(manifestUrl);
        final manifestJson = json.decode(manifestText);
        if (manifestJson is Map) {
          sources.add(SourceManifest.fromJson(
            manifestJson.cast<String, dynamic>(),
            repoUrl: url,
          ));
        }
      } catch (_) {
        // A single broken source should not break the whole repo.
      }
    }

    if (sources.isEmpty) {
      throw ExtensionError(
        'No usable sources found in this repository.\n\n'
        'The file was valid JSON but no entry contained an "endpoints" block, '
        'which is what Kuroyomi extensions are made of. Check that this is a '
        'Kuroyomi format repository (see docs/EXTENSIONS.md).',
      );
    }

    return RepoResult(
      info: RepoInfo(url: url, name: name, sourceCount: sources.length),
      sources: sources,
    );
  }

  /// Makes common copy/paste mistakes work: GitHub blob links are rewritten to
  /// their raw equivalent, and a bare repo folder gets `/index.json`.
  static String normalise(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http')) url = 'https://$url';
    if (url.contains('github.com') && url.contains('/blob/')) {
      url = url
          .replaceFirst('github.com', 'raw.githubusercontent.com')
          .replaceFirst('/blob/', '/');
    }

    // Only append index.json when the url points at a directory. Previously
    // any url not ending in ".json" got "/index.json" glued on, which mangled
    // links such as ".../repo/index.pb" into ".../index.pb/index.json".
    final uri = Uri.tryParse(url);
    final segments =
        uri?.pathSegments.where((segment) => segment.isNotEmpty).toList() ??
            const <String>[];
    final last = segments.isEmpty ? '' : segments.last;
    final looksLikeFile = last.contains('.');
    if (!looksLikeFile) {
      url = url.endsWith('/') ? '${url}index.json' : '$url/index.json';
    }
    return url;
  }

  /// True when the payload is a Tachiyomi / Mihon style extension index.
  ///
  /// Those repositories list **compiled Android APKs**, which Kuroyomi cannot
  /// execute, so we detect them to show a useful message instead of a vague
  /// parse error.
  static bool looksLikeApkRepo(List<dynamic> entries) {
    for (final entry in entries.take(8)) {
      if (entry is! Map) continue;
      if (entry.containsKey('apk') ||
          entry.containsKey('pkg') ||
          entry.containsKey('class')) {
        return true;
      }
    }
    return false;
  }

  static const String apkRepoMessage =
      'This is a Tachiyomi / Mihon extension repository (Keiyoushi and friends).\n\n'
      'Those extensions are compiled Android APKs containing Kotlin code, so no '
      'other app can execute them — Kuroyomi uses declarative JSON extensions '
      'instead.\n\n'
      'Use a Kuroyomi format repository, or write one: see docs/EXTENSIONS.md '
      'in the project repo.';

  static String _parentOf(String url) {
    final index = url.lastIndexOf('/');
    if (index <= 0) return url;
    return url.substring(0, index);
  }
}

class RepoResult {
  const RepoResult({required this.info, required this.sources});

  final RepoInfo info;
  final List<SourceManifest> sources;
}
