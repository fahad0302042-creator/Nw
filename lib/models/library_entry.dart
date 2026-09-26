import 'catalog_item.dart';

/// A title the user has saved to their library.
class LibraryEntry {
  final CatalogItem item;
  final String type; // manga | anime
  final int addedAt;

  const LibraryEntry({
    required this.item,
    required this.type,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        ...item.toJson(),
        'type': type,
        'addedAt': addedAt,
      };

  factory LibraryEntry.fromJson(Map<String, dynamic> json) => LibraryEntry(
        item: CatalogItem.fromJson(json),
        type: json['type'] as String? ?? 'manga',
        addedAt: json['addedAt'] as int? ?? 0,
      );
}
