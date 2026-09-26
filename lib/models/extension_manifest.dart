import 'detail_endpoint.dart';
import 'list_endpoint.dart';
import 'pages_endpoint.dart';

/// A fully parsed extension / source manifest.
///
/// This is the declarative, no-code format Tsundoku uses instead of
/// compiled extensions: an extension is just a JSON file describing how to
/// scrape/query one website. See `docs/EXTENSION_SPEC.md`.
class ExtensionManifest {
  final String id;
  final String name;
  final String lang;
  final String version;

  /// `manga` or `anime`.
  final String type;
  final String baseUrl;
  final String? icon;
  final String? description;
  final bool nsfw;
  final Map<String, String> headers;

  final ListEndpoint? popular;
  final ListEndpoint? latest;
  final ListEndpoint? search;
  final DetailEndpoint? detail;

  /// Chapter list (manga) or episode list (anime) - same shape.
  final ListEndpoint? chapters;

  /// Page image list (manga) or video link list (anime) - same shape.
  final PagesEndpoint? pages;

  /// The raw JSON this manifest was parsed from, kept around so it can be
  /// re-serialized to local storage without loss.
  final Map<String, dynamic> raw;

  const ExtensionManifest({
    required this.id,
    required this.name,
    required this.lang,
    required this.version,
    required this.type,
    required this.baseUrl,
    this.icon,
    this.description,
    this.nsfw = false,
    this.headers = const {},
    this.popular,
    this.latest,
    this.search,
    this.detail,
    this.chapters,
    this.pages,
    this.raw = const {},
  });

  bool get isManga => type == 'manga';
  bool get isAnime => type == 'anime';

  factory ExtensionManifest.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? asMap(String key) {
      final value = json[key];
      if (value == null) return null;
      return Map<String, dynamic>.from(value as Map);
    }

    return ExtensionManifest(
      id: json['id'] as String,
      name: json['name'] as String,
      lang: json['lang'] as String? ?? 'en',
      version: json['version']?.toString() ?? '1.0.0',
      type: json['type'] as String? ?? 'manga',
      baseUrl: json['baseUrl'] as String? ?? '',
      icon: json['icon'] as String?,
      description: json['description'] as String?,
      nsfw: json['nsfw'] as bool? ?? false,
      headers: (json['headers'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ) ??
          const {},
      popular: asMap('popular') != null ? ListEndpoint.fromJson(asMap('popular')!) : null,
      latest: asMap('latest') != null ? ListEndpoint.fromJson(asMap('latest')!) : null,
      search: asMap('search') != null ? ListEndpoint.fromJson(asMap('search')!) : null,
      detail: asMap('detail') != null ? DetailEndpoint.fromJson(asMap('detail')!) : null,
      chapters: asMap('chapters') != null ? ListEndpoint.fromJson(asMap('chapters')!) : null,
      pages: asMap('pages') != null ? PagesEndpoint.fromJson(asMap('pages')!) : null,
      raw: json,
    );
  }

  Map<String, dynamic> toJson() => raw;
}
