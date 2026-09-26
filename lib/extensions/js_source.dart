import '../domain/models/media.dart';
import '../domain/source/media_source.dart';
import '../domain/source/source_filter.dart';
import 'js_runtime.dart';

/// A [MediaSource] whose behaviour lives in a JavaScript extension.
///
/// One JS bundle may register several sources (e.g. the same site in
/// multiple languages); [index] selects which one this Dart object proxies.
class JsSource implements MediaSource {
  JsSource({
    required this.host,
    required this.index,
    required this.id,
    required this.name,
    required this.lang,
    required this.baseUrl,
    required this.type,
    required this.supportsLatest,
    required this.extensionId,
  });

  final JsRuntimeHost host;
  final int index;
  final String extensionId;

  @override
  final String id;
  @override
  final String name;
  @override
  final String lang;
  @override
  final String baseUrl;
  @override
  final MediaType type;
  @override
  final bool supportsLatest;

  List<SourceFilter> _filters = const [];
  @override
  List<SourceFilter> get filters => _filters;

  @override
  Map<String, String> get mediaHeaders => {
        if (baseUrl.isNotEmpty) 'Referer': '$baseUrl/',
      };

  factory JsSource.fromManifest(
    Map<String, dynamic> m, {
    required JsRuntimeHost host,
    required String extensionId,
  }) {
    return JsSource(
      host: host,
      extensionId: extensionId,
      index: (m['index'] as num).toInt(),
      id: '${m['id']}',
      name: '${m['name']}',
      lang: '${m['lang'] ?? 'en'}',
      baseUrl: '${m['baseUrl'] ?? ''}',
      type: MediaTypeX.parse('${m['type']}'),
      supportsLatest: m['supportsLatest'] != false,
    );
  }

  Future<void> loadFilters() async {
    try {
      final raw = await host.callSource(index, 'getFilters', const []);
      if (raw is List) {
        _filters = raw
            .map((e) => SourceFilter.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      }
    } catch (_) {
      _filters = const [];
    }
  }

  MediaPage _toPage(Object? raw) {
    if (raw == null) return MediaPage.empty;
    final map = raw is List ? {'items': raw, 'hasNext': false} : (raw as Map);
    final items = (map['items'] as List? ?? const [])
        .map((e) => MediaItem.fromJson(
              (e as Map).cast<String, dynamic>(),
              sourceId: id,
              type: type,
            ))
        .where((e) => e.url.isNotEmpty)
        .toList();
    return MediaPage(
      items: items,
      hasNextPage: map['hasNext'] == true || map['hasNextPage'] == true,
    );
  }

  @override
  Future<MediaPage> popular(int page) async =>
      _toPage(await host.callSource(index, 'popular', [page]));

  @override
  Future<MediaPage> latest(int page) async =>
      _toPage(await host.callSource(index, 'latest', [page]));

  @override
  Future<MediaPage> search(String query, int page, List<FilterValue> f) async =>
      _toPage(await host.callSource(
        index,
        'search',
        [query, page, f.map((e) => e.toJson()).toList()],
      ));

  @override
  Future<MediaItem> details(MediaItem item) async {
    final raw = await host.callSource(index, 'details', [item.toJson()]);
    if (raw is! Map) return item.copyWith(initialized: true);
    final fresh = MediaItem.fromJson(
      raw.cast<String, dynamic>(),
      sourceId: id,
      type: type,
    );
    return item.mergeDetails(fresh);
  }

  @override
  Future<List<MediaUnit>> units(MediaItem item) async {
    // `chapters` / `episodes` are accepted as friendlier aliases of `units`.
    final method = switch (type) {
      MediaType.manga => 'chapters',
      MediaType.anime => 'episodes',
    };
    Object? raw;
    try {
      raw = await host.callSource(index, method, [item.toJson()]);
    } on ExtensionException {
      raw = await host.callSource(index, 'units', [item.toJson()]);
    }
    return (raw as List? ?? const [])
        .map((e) => MediaUnit.fromJson((e as Map).cast<String, dynamic>()))
        .where((e) => e.url.isNotEmpty)
        .toList();
  }

  @override
  Future<List<ReaderPage>> pages(MediaUnit unit) async {
    if (type != MediaType.manga) {
      throw UnsupportedError('$name is not a manga source');
    }
    final raw = await host.callSource(index, 'pages', [
      {'url': unit.url, 'name': unit.name}
    ]);
    final list = raw as List? ?? const [];
    return [
      for (var i = 0; i < list.length; i++) ReaderPage.fromJson(i, list[i]),
    ];
  }

  @override
  Future<List<VideoStream>> videos(MediaUnit unit) async {
    if (type != MediaType.anime) {
      throw UnsupportedError('$name is not an anime source');
    }
    final raw = await host.callSource(index, 'videos', [
      {'url': unit.url, 'name': unit.name}
    ]);
    return (raw as List? ?? const [])
        .map((e) => VideoStream.fromJson((e as Map).cast<String, dynamic>()))
        .where((e) => e.url.isNotEmpty)
        .toList();
  }
}
