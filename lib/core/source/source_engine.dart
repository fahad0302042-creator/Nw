import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../../models/catalog_item.dart';
import '../../models/chapter_entry.dart';
import '../../models/extension_manifest.dart';
import '../../models/list_endpoint.dart';
import '../../models/manga_detail.dart';
import '../../models/page_entry.dart';
import '../../models/pages_endpoint.dart';
import '../network/http_client.dart';
import '../parsing/path_resolver.dart';
import '../parsing/template.dart';
import '../parsing/url_utils.dart';
import 'field_extractor.dart';

/// Executes the declarative fetch/parse pipeline described by an
/// [ExtensionManifest] against the live network (or inline `static` data),
/// producing typed models the UI can render directly.
///
/// This is the heart of Tsundoku's extension system: every source, no
/// matter which real website it targets, is driven entirely by this one
/// engine plus the JSON manifest - no per-site Dart code is ever required.
class SourceEngine {
  const SourceEngine();

  Future<String> _fetchRaw(
    String url,
    Map<String, String> headers, {
    String method = 'GET',
    Map<String, String>? formBody,
  }) async {
    final options = Options(headers: headers, responseType: ResponseType.plain);
    final response = method == 'POST'
        ? await AppHttpClient.dio.post(url, data: formBody, options: options)
        : await AppHttpClient.dio.get(url, options: options);
    final data = response.data;
    if (data is String) return data;
    return jsonEncode(data);
  }

  Future<List<Map<String, dynamic>>> _fetchExtractedList(
    ExtensionManifest ext,
    ListEndpoint ep,
    Map<String, String> vars, {
    String query = '',
  }) async {
    if (ep.responseType == 'static') {
      return (ep.staticItems ?? [])
          .whereType<Map>()
          .map((raw) => extractFields(
                Map<String, dynamic>.from(raw),
                ep.fields,
                'json',
                ext.baseUrl,
              ))
          .toList();
    }

    var url = applyTemplate(ep.url ?? '', vars);
    url = url.replaceAll('{query}', Uri.encodeQueryComponent(query));
    final body = await _fetchRaw(
      url,
      ext.headers,
      method: ep.method,
      formBody: ep.formBody,
    );

    if (ep.responseType == 'html') {
      final doc = html_parser.parse(body);
      final elements = (ep.itemSelector == null || ep.itemSelector!.isEmpty)
          ? const []
          : doc.querySelectorAll(ep.itemSelector!);
      return elements
          .map((el) => extractFields(el, ep.fields, 'html', ext.baseUrl))
          .toList();
    }

    final decoded = jsonDecode(body);
    final list = ep.itemsPath != null ? resolveJsonPath(decoded, ep.itemsPath) : decoded;
    final rawItems = list is List ? list : const <dynamic>[];
    return rawItems
        .map((item) => extractFields(item, ep.fields, 'json', ext.baseUrl))
        .toList();
  }

  Future<List<CatalogItem>> fetchList(
    ExtensionManifest ext,
    ListEndpoint ep, {
    int page = 1,
    String query = '',
    Map<String, String> extraVars = const {},
  }) async {
    final vars = {'page': '$page', ...extraVars};
    final extracted = await _fetchExtractedList(ext, ep, vars, query: query);
    return extracted
        .map((e) => CatalogItem(
              url: (e['url'] ?? e['id'] ?? '').toString(),
              title: (e['title'] ?? '(untitled)').toString(),
              cover: e['cover']?.toString(),
              subtitle: e['subtitle']?.toString(),
              sourceId: ext.id,
            ))
        .where((c) => c.url.isNotEmpty)
        .toList();
  }

  Future<List<ChapterEntry>> fetchChapters(
    ExtensionManifest ext,
    ListEndpoint ep,
    String mangaUrl,
  ) async {
    final extracted = await _fetchExtractedList(ext, ep, {'url': mangaUrl, 'page': '1'});
    return extracted
        .map((e) => ChapterEntry(
              url: (e['url'] ?? e['id'] ?? '').toString(),
              title: (e['title'] ?? '').toString(),
              number: double.tryParse('${e['number'] ?? ''}'),
              dateUpload: (e['date'] ?? e['subtitle'])?.toString(),
              scanlator: e['scanlator']?.toString(),
            ))
        .where((c) => c.url.isNotEmpty)
        .toList();
  }

  Future<MangaDetail> fetchDetail(ExtensionManifest ext, CatalogItem item) async {
    String? title = item.title;
    String? cover = item.cover;
    String? description;
    List<String> genres = const [];
    String? status;
    String? author;

    final de = ext.detail;
    if (de != null) {
      final url = applyTemplate(de.url, {'url': item.url});
      final body = await _fetchRaw(url, ext.headers, method: de.method);
      Map<String, dynamic> extracted;
      if (de.responseType == 'html') {
        final doc = html_parser.parse(body);
        final scoped = (de.rootSelector == null || de.rootSelector!.isEmpty)
            ? doc.documentElement
            : doc.querySelector(de.rootSelector!);
        extracted = extractFields(scoped, de.fields, 'html', ext.baseUrl);
      } else {
        final decoded = jsonDecode(body);
        final scoped = de.rootPath != null ? resolveJsonPath(decoded, de.rootPath) : decoded;
        extracted = extractFields(scoped, de.fields, 'json', ext.baseUrl);
      }
      title = (extracted['title'] as String?) ?? title;
      cover = (extracted['cover'] as String?) ?? cover;
      description = extracted['description'] as String?;
      final genresValue = extracted['genres'];
      if (genresValue is List) genres = List<String>.from(genresValue);
      status = extracted['status'] as String?;
      author = extracted['author'] as String?;
    }

    var chapters = <ChapterEntry>[];
    if (ext.chapters != null) {
      chapters = await fetchChapters(ext, ext.chapters!, item.url);
    }

    return MangaDetail(
      item: CatalogItem(
        url: item.url,
        title: title ?? item.title,
        cover: cover,
        subtitle: item.subtitle,
        sourceId: ext.id,
      ),
      description: description,
      genres: genres,
      status: status,
      author: author,
      chapters: chapters,
    );
  }

  Future<List<PageEntry>> fetchPages(
    ExtensionManifest ext,
    PagesEndpoint pe,
    String chapterUrl, {
    Map<String, String> extraVars = const {},
  }) async {
    final vars = {'url': chapterUrl, 'chapterUrl': chapterUrl, ...extraVars};

    if (pe.mode == 'echo') {
      final url = applyTemplate(pe.urlTemplate ?? '{url}', vars);
      return url.isEmpty ? const [] : [PageEntry(url: url, headers: pe.resourceHeaders)];
    }

    if (pe.mode == 'compose') {
      final resolveUrl0 = applyTemplate(pe.resolveUrl ?? '', vars);
      final body = await _fetchRaw(resolveUrl0, ext.headers, method: pe.method);
      final decoded = jsonDecode(body);
      final resolvedVars = <String, dynamic>{};
      pe.vars?.forEach((name, path) {
        resolvedVars[name] = resolveJsonPath(decoded, path);
      });
      final loopValue = pe.loopVar != null ? resolvedVars[pe.loopVar] : null;
      final loopList = loopValue is List ? loopValue : const [];
      final stringVars = <String, String?>{
        for (final entry in resolvedVars.entries)
          entry.key: entry.value is List ? null : entry.value?.toString(),
      };
      return loopList
          .map((element) {
            final templateVars = {...stringVars, 'item': element?.toString()};
            final url = applyTemplate(pe.urlTemplate ?? '{item}', templateVars);
            return PageEntry(url: url, headers: pe.resourceHeaders);
          })
          .where((p) => p.url.isNotEmpty)
          .toList();
    }

    if (pe.responseType == 'static') {
      return (pe.staticItems ?? [])
          .map((item) {
            final raw = item is Map
                ? (pe.itemPath != null ? resolveJsonPathAsString(item, pe.itemPath) : null)
                : item?.toString();
            final resolved = resolveUrl(raw, ext.baseUrl);
            return PageEntry(url: resolved ?? '', headers: pe.resourceHeaders);
          })
          .where((p) => p.url.isNotEmpty)
          .toList();
    }

    final url = applyTemplate(pe.url ?? '', vars);
    final body = await _fetchRaw(url, ext.headers, method: pe.method);

    if (pe.responseType == 'html') {
      final doc = html_parser.parse(body);
      final elements = (pe.itemSelector == null || pe.itemSelector!.isEmpty)
          ? const []
          : doc.querySelectorAll(pe.itemSelector!);
      return elements
          .map((el) {
            final raw = el.attributes[pe.attr ?? 'src'];
            final resolved = resolveUrl(raw, ext.baseUrl);
            return PageEntry(url: resolved ?? '', headers: pe.resourceHeaders);
          })
          .where((p) => p.url.isNotEmpty)
          .toList();
    }

    var jsonStr = body;
    if (pe.responseType == 'regex_json') {
      final match = RegExp(pe.regex ?? '', dotAll: true).firstMatch(body);
      jsonStr = match != null ? (match.group(pe.regexGroup) ?? '[]') : '[]';
    }
    final decoded = jsonDecode(jsonStr);
    final list = pe.itemsPath != null ? resolveJsonPath(decoded, pe.itemsPath) : decoded;
    final rawItems = list is List ? list : const [];
    return rawItems
        .map((item) {
          final raw = pe.itemPath != null ? resolveJsonPathAsString(item, pe.itemPath) : item?.toString();
          final resolved = resolveUrl(raw, ext.baseUrl);
          return PageEntry(url: resolved ?? '', headers: pe.resourceHeaders);
        })
        .where((p) => p.url.isNotEmpty)
        .toList();
  }
}
