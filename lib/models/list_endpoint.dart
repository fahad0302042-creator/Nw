import 'field_spec.dart';

/// Describes an endpoint that returns a list of items: popular, latest,
/// search, or a manga/anime's chapter (episode) list.
class ListEndpoint {
  /// URL template. Supports `{page}` (1-based page number) and `{query}`
  /// (search mode) plus any extra vars passed by the caller (e.g. `{url}`
  /// for a chapter-list request scoped to one manga).
  final String? url;
  final String method;
  final Map<String, String>? formBody;

  /// `html`, `json`, or `static`.
  final String responseType;

  /// HTML mode: CSS selector matching each item's root element.
  final String? itemSelector;

  /// JSON mode: dotted path to the array of items (root array = `` or `$`).
  final String? itemsPath;

  /// `static` mode: the items are inlined directly in the manifest, no
  /// network request is made. Useful for demo/bundled sources.
  final List<dynamic>? staticItems;

  final Map<String, FieldSpec> fields;

  /// Whether `{page}` pagination is supported (affects "load more" UI).
  final bool paginated;

  const ListEndpoint({
    this.url,
    this.method = 'GET',
    this.formBody,
    this.responseType = 'html',
    this.itemSelector,
    this.itemsPath,
    this.staticItems,
    this.fields = const {},
    this.paginated = false,
  });

  factory ListEndpoint.fromJson(Map<String, dynamic> json) {
    final fieldsJson = Map<String, dynamic>.from(json['fields'] as Map? ?? {});
    return ListEndpoint(
      url: json['url'] as String?,
      method: (json['method'] as String? ?? 'GET').toUpperCase(),
      formBody: (json['formBody'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      responseType: json['responseType'] as String? ?? 'html',
      itemSelector: json['itemSelector'] as String?,
      itemsPath: json['itemsPath'] as String?,
      staticItems: json['items'] as List<dynamic>?,
      fields: fieldsJson.map(
        (k, v) => MapEntry(k, FieldSpec.fromJson(v)),
      ),
      paginated: (json['url'] as String? ?? '').contains('{page}'),
    );
  }
}
