import 'field_spec.dart';

/// Describes the endpoint used to fetch full manga/anime details (synopsis,
/// genres, status, author, cover) given the item's stored `url`/id.
class DetailEndpoint {
  /// URL template, supports `{url}`.
  final String url;
  final String method;
  final String responseType; // html | json

  /// Optional root scoping: a CSS selector (HTML) or dotted path (JSON) that
  /// the fields below are resolved relative to. Defaults to the whole
  /// document/response.
  final String? rootSelector;
  final String? rootPath;

  final Map<String, FieldSpec> fields;

  const DetailEndpoint({
    required this.url,
    this.method = 'GET',
    this.responseType = 'html',
    this.rootSelector,
    this.rootPath,
    this.fields = const {},
  });

  factory DetailEndpoint.fromJson(Map<String, dynamic> json) {
    final fieldsJson = Map<String, dynamic>.from(json['fields'] as Map? ?? {});
    return DetailEndpoint(
      url: json['url'] as String? ?? '{url}',
      method: (json['method'] as String? ?? 'GET').toUpperCase(),
      responseType: json['responseType'] as String? ?? 'html',
      rootSelector: json['rootSelector'] as String?,
      rootPath: json['rootPath'] as String?,
      fields: fieldsJson.map((k, v) => MapEntry(k, FieldSpec.fromJson(v))),
    );
  }
}
