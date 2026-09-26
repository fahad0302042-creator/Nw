import 'rule.dart';

/// Describes one request + how to read the response.
class NodeSpec {
  const NodeSpec({
    this.url = '{url}',
    this.method = 'GET',
    this.body,
    this.parse,
    this.items,
    this.fields = const <String, Rule>{},
    this.next,
    this.headers = const <String, String>{},
    this.filter = false,
    this.reverse = false,
  });

  /// Request url template. Supports `{url}`, `{page}`, `{query}`.
  final String url;
  final String method;
  final String? body;

  /// `html`, `json` or `raw`. Falls back to the source level value.
  final String? parse;

  /// Selector (html) or dotted path (json) pointing at the list of nodes.
  final String? items;

  /// Named extraction rules, e.g. `title`, `url`, `thumbnail`, `image`.
  final Map<String, Rule> fields;

  /// When present and matching, another page exists.
  final Rule? next;

  final Map<String, String> headers;

  /// Filter results by the search query on the client (for static sources).
  final bool filter;

  /// Reverse the parsed list (chapter lists that come oldest first).
  final bool reverse;

  Rule? field(String name) => fields[name];

  factory NodeSpec.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'];
    final fields = <String, Rule>{};
    if (rawFields is Map) {
      rawFields.forEach((key, value) {
        final rule = Rule.maybe(value);
        if (rule != null) fields[key.toString()] = rule;
      });
    }
    // Allow fields to be declared inline as well, e.g. {"items": ".x", "title": "h3"}
    for (final key in const <String>[
      'title',
      'url',
      'thumbnail',
      'subtitle',
      'image',
      'name',
      'date',
      'scanlator',
      'description',
      'author',
      'artist',
      'status',
      'genres',
      'quality',
    ]) {
      if (!fields.containsKey(key) && json.containsKey(key)) {
        final rule = Rule.maybe(json[key]);
        if (rule != null) fields[key] = rule;
      }
    }

    return NodeSpec(
      url: (json['url'] ?? json['path'] ?? '{url}').toString(),
      method: (json['method'] ?? 'GET').toString(),
      body: json['body']?.toString(),
      parse: json['parse']?.toString(),
      items: json['items']?.toString() ?? json['list']?.toString(),
      fields: fields,
      next: Rule.maybe(json['next'] ?? json['nextPage']),
      headers: _stringMap(json['headers']),
      filter: json['filter'] == true,
      reverse: json['reverse'] == true,
    );
  }
}

/// A single installable source, i.e. one website.
class SourceManifest {
  const SourceManifest({
    required this.id,
    required this.name,
    required this.type,
    required this.baseUrl,
    this.lang = 'en',
    this.version = '1.0.0',
    this.icon,
    this.nsfw = false,
    this.headers = const <String, String>{},
    this.parse = 'html',
    this.endpoints = const <String, NodeSpec>{},
    this.repoUrl,
    this.raw = const <String, dynamic>{},
  });

  final String id;
  final String name;

  /// `manga` or `anime`.
  final String type;
  final String baseUrl;
  final String lang;
  final String version;
  final String? icon;
  final bool nsfw;
  final Map<String, String> headers;
  final String parse;
  final Map<String, NodeSpec> endpoints;
  final String? repoUrl;

  /// The original json, kept so installed sources can be persisted verbatim.
  final Map<String, dynamic> raw;

  bool get isAnime => type.toLowerCase() == 'anime';

  bool supports(String endpoint) => endpoints.containsKey(endpoint);

  Map<String, dynamic> toJson() {
    final out = Map<String, dynamic>.from(raw);
    if (repoUrl != null) out['repoUrl'] = repoUrl;
    return out;
  }

  static SourceManifest fromJson(Map<String, dynamic> json, {String? repoUrl}) {
    final rawEndpoints = json['endpoints'];
    final endpoints = <String, NodeSpec>{};
    if (rawEndpoints is Map) {
      rawEndpoints.forEach((key, value) {
        if (value is Map) {
          endpoints[key.toString()] =
              NodeSpec.fromJson(value.cast<String, dynamic>());
        }
      });
    }
    // Aliases so anime extensions can speak in "episodes".
    if (endpoints.containsKey('episodes') && !endpoints.containsKey('chapters')) {
      endpoints['chapters'] = endpoints['episodes']!;
    }
    if (endpoints.containsKey('images') && !endpoints.containsKey('pages')) {
      endpoints['pages'] = endpoints['images']!;
    }
    if (endpoints.containsKey('videos') && !endpoints.containsKey('video')) {
      endpoints['video'] = endpoints['videos']!;
    }

    final baseUrl = (json['baseUrl'] ?? json['base'] ?? '').toString();
    final name = (json['name'] ?? 'Unnamed source').toString();
    final id = (json['id'] ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'))
        .toString();

    return SourceManifest(
      id: id,
      name: name,
      type: (json['type'] ?? 'manga').toString(),
      baseUrl: baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl,
      lang: (json['lang'] ?? 'en').toString(),
      version: (json['version'] ?? '1.0.0').toString(),
      icon: json['icon']?.toString(),
      nsfw: json['nsfw'] == true,
      headers: _stringMap(json['headers']),
      parse: (json['parse'] ?? 'html').toString(),
      endpoints: endpoints,
      repoUrl: repoUrl ?? json['repoUrl']?.toString(),
      raw: Map<String, dynamic>.from(json),
    );
  }
}

/// A repository is just a json file listing sources.
class RepoInfo {
  const RepoInfo({required this.url, required this.name, this.sourceCount = 0});

  final String url;
  final String name;
  final int sourceCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'url': url,
        'name': name,
        'sourceCount': sourceCount,
      };

  static RepoInfo fromJson(Map<String, dynamic> json) => RepoInfo(
        url: (json['url'] ?? '').toString(),
        name: (json['name'] ?? 'Repository').toString(),
        sourceCount: (json['sourceCount'] as num?)?.toInt() ?? 0,
      );
}

Map<String, String> _stringMap(dynamic value) {
  final out = <String, String>{};
  if (value is Map) {
    value.forEach((key, val) => out[key.toString()] = val.toString());
  }
  return out;
}
