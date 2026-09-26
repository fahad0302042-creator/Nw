/// User-defined library categories.
library;

class LibraryCategory {
  const LibraryCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  final int id;
  final String name;
  final int sortOrder;

  /// Pseudo-category shown first; not stored in the database.
  static const allId = -1;
  static const all = LibraryCategory(id: allId, name: 'All', sortOrder: -1);

  /// Pseudo-category for items in the library but in no category.
  static const uncategorizedId = -2;
  static const uncategorized =
      LibraryCategory(id: uncategorizedId, name: 'Uncategorized', sortOrder: 9999);

  bool get isVirtual => id < 0;

  factory LibraryCategory.fromRow(Map<String, Object?> r) => LibraryCategory(
        id: r['id'] as int,
        name: '${r['name']}',
        sortOrder: (r['sort_order'] as int?) ?? 0,
      );

  Map<String, Object?> toRow() => {'name': name, 'sort_order': sortOrder};
}
