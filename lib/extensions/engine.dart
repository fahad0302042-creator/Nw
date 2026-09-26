import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import '../core/net.dart';
import '../core/urls.dart';
import '../models/media.dart';
import 'extractor.dart';
import 'manifest.dart';
import 'rule.dart';

class ExtensionError implements Exception {
  ExtensionError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Executes a [SourceManifest] against the network.
///
/// Nothing here is source specific: the manifest declares selectors/paths and
/// this class does the fetching, parsing and url resolution.
class SourceEngine {
  SourceEngine(this.source);

  final SourceManifest source;

  Map<String, String> get requestHeaders => source.headers;

  // ---------------------------------------------------------------- browsing

  /// Loads `popular`, `latest` or `search` listings.
  Future<PagedResult<MediaItem>> list(
    String endpoint, {
    int page = 1,
    String query = '',
  }) async {
    final spec = _require(endpoint);
    final vars = <String, String>{
      'page': '$page',
      'query': Uri.encodeQueryComponent(query),
      'rawQuery': query,
      'url': '',
    };
    final text = await _load(spec, vars);
    final mode = spec.parse ?? source.parse;

    final results = <MediaItem>[];
    var hasNext = false;

    if (mode == 'json') {
      final root = json.decode(text);
      final nodes = Extractor.jsonList(root, spec.items);
      for (final node in nodes) {
        final item = _mediaFromJson(node, spec);
        if (item != null) results.add(item);
      }
      hasNext = spec.next == null
          ? nodes.isNotEmpty
          : (Extractor.jsonValue(root, spec.next) ?? '').isNotEmpty;
    } else {
      final document = html_parser.parse(text);
      final nodes = Extractor.htmlList(document, spec.items);
      for (final node in nodes) {
        final item = _mediaFromHtml(node, spec);
        if (item != null) results.add(item);
      }
      hasNext = spec.next == null
          ? nodes.isNotEmpty
          : Extractor.htmlValue(document, spec.next) != null;
    }

    var out = results;
    if (spec.filter && query.trim().isNotEmpty) {
      final needle = query.toLowerCase();
      out = results
          .where((item) => item.title.toLowerCase().contains(needle))
          .toList();
      hasNext = false;
    }
    return PagedResult<MediaItem>(out, hasNext: hasNext);
  }

  MediaItem? _mediaFromHtml(dynamic node, NodeSpec spec) {
    final title = Extractor.htmlValue(node, spec.field('title'));
    final link = Extractor.htmlValue(node, spec.field('url'));
    if (title == null || title.isEmpty || link == null || link.isEmpty) {
      return null;
    }
    return MediaItem(
      sourceId: source.id,
      title: title,
      url: absolute(link),
      thumbnail: _absoluteOrNull(Extractor.htmlValue(node, spec.field('thumbnail'))),
      subtitle: Extractor.htmlValue(node, spec.field('subtitle')),
    );
  }

  MediaItem? _mediaFromJson(dynamic node, NodeSpec spec) {
    final title = Extractor.jsonValue(node, spec.field('title'));
    final link = Extractor.jsonValue(node, spec.field('url'));
    if (title == null || title.isEmpty || link == null || link.isEmpty) {
      return null;
    }
    return MediaItem(
      sourceId: source.id,
      title: title,
      url: absolute(link),
      thumbnail: _absoluteOrNull(Extractor.jsonValue(node, spec.field('thumbnail'))),
      subtitle: Extractor.jsonValue(node, spec.field('subtitle')),
    );
  }

  // ----------------------------------------------------------------- details

  Future<MediaDetails> details(String url) async {
    final spec = source.endpoints['details'];
    if (spec == null) return MediaDetails.empty;
    final text = await _load(spec, <String, String>{'url': url});
    final mode = spec.parse ?? source.parse;

    if (mode == 'json') {
      final root = json.decode(text);
      final node = spec.items == null ? root : Extractor.jsonNode(root, spec.items);
      return MediaDetails(
        title: Extractor.jsonValue(node, spec.field('title')),
        description: Extractor.jsonValue(node, spec.field('description')),
        author: Extractor.jsonValue(node, spec.field('author')),
        artist: Extractor.jsonValue(node, spec.field('artist')),
        status: Extractor.jsonValue(node, spec.field('status')),
        thumbnail: _absoluteOrNull(Extractor.jsonValue(node, spec.field('thumbnail'))),
        genres: Extractor.jsonValues(node, spec.field('genres')),
      );
    }

    final document = html_parser.parse(text);
    return MediaDetails(
      title: Extractor.htmlValue(document, spec.field('title')),
      description: Extractor.htmlValue(document, spec.field('description')),
      author: Extractor.htmlValue(document, spec.field('author')),
      artist: Extractor.htmlValue(document, spec.field('artist')),
      status: Extractor.htmlValue(document, spec.field('status')),
      thumbnail: _absoluteOrNull(Extractor.htmlValue(document, spec.field('thumbnail'))),
      genres: Extractor.htmlValues(document, spec.field('genres')),
    );
  }

  // ---------------------------------------------------------------- chapters

  Future<List<ChapterItem>> chapters(String url) async {
    final spec = _require('chapters');
    final text = await _load(spec, <String, String>{'url': url});
    final mode = spec.parse ?? source.parse;
    final out = <ChapterItem>[];

    if (mode == 'json') {
      final root = json.decode(text);
      for (final node in Extractor.jsonList(root, spec.items)) {
        final link = Extractor.jsonValue(node, spec.field('url'));
        if (link == null || link.isEmpty) continue;
        final name = Extractor.jsonValue(node, spec.field('name')) ??
            Extractor.jsonValue(node, spec.field('title')) ??
            'Chapter ${out.length + 1}';
        out.add(ChapterItem(
          name: name,
          url: absolute(link),
          date: Extractor.jsonValue(node, spec.field('date')),
          scanlator: Extractor.jsonValue(node, spec.field('scanlator')),
        ));
      }
    } else {
      final document = html_parser.parse(text);
      for (final node in Extractor.htmlList(document, spec.items)) {
        final link = Extractor.htmlValue(node, spec.field('url'));
        if (link == null || link.isEmpty) continue;
        final name = Extractor.htmlValue(node, spec.field('name')) ??
            Extractor.htmlValue(node, spec.field('title')) ??
            'Chapter ${out.length + 1}';
        out.add(ChapterItem(
          name: name,
          url: absolute(link),
          date: Extractor.htmlValue(node, spec.field('date')),
          scanlator: Extractor.htmlValue(node, spec.field('scanlator')),
        ));
      }
    }

    if (spec.reverse) {
      return out.reversed.toList();
    }
    return out;
  }

  // ------------------------------------------------------------------- pages

  /// Image urls for one manga chapter.
  Future<List<String>> pages(String url) async {
    final spec = _require('pages');
    final text = await _load(spec, <String, String>{'url': url});
    final mode = spec.parse ?? source.parse;
    final imageRule = spec.field('image') ?? spec.field('url');
    final out = <String>[];

    final isRaw = mode == 'raw' ||
        (spec.items == null && (imageRule?.regex?.isNotEmpty ?? false));

    if (isRaw) {
      final rule = imageRule!;
      final matches = RegExp(rule.regex!, dotAll: true).allMatches(text);
      for (final match in matches) {
        final value = rule.group <= match.groupCount
            ? match.group(rule.group)
            : match.group(0);
        if (value == null || value.isEmpty) continue;
        var cleaned = cleanExtractedUrl(value);
        if (rule.prefix != null) cleaned = '${rule.prefix}$cleaned';
        if (rule.suffix != null) cleaned = '$cleaned${rule.suffix}';
        out.add(absolute(cleaned));
      }
      return out;
    }

    if (mode == 'json') {
      final root = json.decode(text);
      for (final node in Extractor.jsonList(root, spec.items)) {
        final value = Extractor.jsonValue(node, imageRule ?? const Rule());
        if (value != null && value.isNotEmpty) {
          out.add(absolute(cleanExtractedUrl(value)));
        }
      }
    } else {
      final document = html_parser.parse(text);
      for (final node in Extractor.htmlList(document, spec.items)) {
        final value = Extractor.htmlValue(node, imageRule ?? const Rule(attr: 'src'));
        if (value != null && value.isNotEmpty) {
          out.add(absolute(cleanExtractedUrl(value)));
        }
      }
    }
    return out;
  }

  // ------------------------------------------------------------------ videos

  /// Playable streams for one anime episode.
  Future<List<VideoSource>> videos(String url) async {
    final spec = _require('video');
    final text = await _load(spec, <String, String>{'url': url});
    final mode = spec.parse ?? source.parse;
    final urlRule = spec.field('url') ?? spec.field('file');
    final out = <VideoSource>[];

    final isRaw = mode == 'raw' ||
        (spec.items == null && (urlRule?.regex?.isNotEmpty ?? false));

    if (isRaw) {
      final rule = urlRule!;
      for (final match in RegExp(rule.regex!, dotAll: true).allMatches(text)) {
        final value = rule.group <= match.groupCount
            ? match.group(rule.group)
            : match.group(0);
        if (value == null || value.isEmpty) continue;
        out.add(VideoSource(
          url: absolute(cleanExtractedUrl(value)),
          quality: 'Default',
          headers: source.headers,
        ));
      }
      return out;
    }

    if (mode == 'json') {
      final root = json.decode(text);
      for (final node in Extractor.jsonList(root, spec.items)) {
        final value = Extractor.jsonValue(node, urlRule ?? const Rule());
        if (value == null || value.isEmpty) continue;
        out.add(VideoSource(
          url: absolute(cleanExtractedUrl(value)),
          quality: Extractor.jsonValue(node, spec.field('quality')) ?? 'Default',
          headers: source.headers,
        ));
      }
    } else {
      final document = html_parser.parse(text);
      for (final node in Extractor.htmlList(document, spec.items)) {
        final value = Extractor.htmlValue(node, urlRule ?? const Rule(attr: 'src'));
        if (value == null || value.isEmpty) continue;
        out.add(VideoSource(
          url: absolute(cleanExtractedUrl(value)),
          quality: Extractor.htmlValue(node, spec.field('quality')) ?? 'Default',
          headers: source.headers,
        ));
      }
    }
    return out;
  }

  // ------------------------------------------------------------------ shared

  NodeSpec _require(String endpoint) {
    final spec = source.endpoints[endpoint];
    if (spec == null) {
      throw ExtensionError('"${source.name}" has no "$endpoint" endpoint.');
    }
    return spec;
  }

  Future<String> _load(NodeSpec spec, Map<String, String> vars) async {
    final filled = applyTemplate(spec.url.isEmpty ? '{url}' : spec.url, vars);
    final target = absolute(filled);
    if (target.isEmpty) {
      throw ExtensionError('"${source.name}" produced an empty request url.');
    }
    final headers = <String, String>{...source.headers, ...spec.headers};
    final body = spec.body == null ? null : applyTemplate(spec.body!, vars);
    return Net.fetch(target, headers: headers, method: spec.method, body: body);
  }

  String absolute(String url) => resolveUrl(source.baseUrl, url);

  String? _absoluteOrNull(String? url) {
    if (url == null || url.isEmpty) return null;
    return absolute(cleanExtractedUrl(url));
  }
}
