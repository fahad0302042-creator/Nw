/// A lightweight manga/anime entry as shown in a browse grid (popular,
/// latest, search results) or in the user's library.
class CatalogItem {
  /// Opaque identifier used to fetch detail/chapters later. For HTML
  /// sources this is usually the manga's absolute URL; for JSON APIs it may
  /// just be an id.
  final String url;
  final String title;
  final String? cover;
  final String? subtitle;
  final String sourceId;

  const CatalogItem({
    required this.url,
    required this.title,
    required this.sourceId,
    this.cover,
    this.subtitle,
  });

  String get key => '$sourceId::$url';

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'cover': cover,
        'subtitle': subtitle,
        'sourceId': sourceId,
      };

  factory CatalogItem.fromJson(Map<String, dynamic> json) => CatalogItem(
        url: json['url'] as String,
        title: json['title'] as String? ?? '(untitled)',
        cover: json['cover'] as String?,
        subtitle: json['subtitle'] as String?,
        sourceId: json['sourceId'] as String? ?? '',
      );
}
