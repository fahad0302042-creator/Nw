import 'catalog_item.dart';
import 'chapter_entry.dart';

/// Full detail page for a manga/anime title: metadata plus its chapter or
/// episode list.
class MangaDetail {
  final CatalogItem item;
  final String? description;
  final List<String> genres;
  final String? status;
  final String? author;
  final List<ChapterEntry> chapters;

  const MangaDetail({
    required this.item,
    this.description,
    this.genres = const [],
    this.status,
    this.author,
    this.chapters = const [],
  });
}
