import '../models/media.dart';
import 'source_filter.dart';

/// The contract every content source must satisfy.
///
/// Mirrors Tachiyomi/Aniyomi's `CatalogueSource` + `HttpSource` surface so
/// that porting an existing extension is a mechanical translation rather
/// than a redesign. Implemented by [JsSource] (a JavaScript extension) and
/// can also be implemented natively in Dart for built-in sources.
abstract class MediaSource {
  String get id;
  String get name;
  String get lang;
  String get baseUrl;
  MediaType get type;

  /// Whether this source exposes a "Latest" listing.
  bool get supportsLatest => true;

  /// Filters this source accepts in [search].
  List<SourceFilter> get filters => const [];

  Future<MediaPage> popular(int page);
  Future<MediaPage> latest(int page);
  Future<MediaPage> search(String query, int page, List<FilterValue> filters);

  /// Enrich an item with description, genres, status, etc.
  Future<MediaItem> details(MediaItem item);

  /// Chapters (manga) or episodes (anime), newest first.
  Future<List<MediaUnit>> units(MediaItem item);

  /// Manga only: the images of a chapter.
  Future<List<ReaderPage>> pages(MediaUnit unit) async =>
      throw UnsupportedError('$name is not a manga source');

  /// Anime only: the playable streams of an episode.
  Future<List<VideoStream>> videos(MediaUnit unit) async =>
      throw UnsupportedError('$name is not an anime source');

  /// Headers required to fetch images/streams from this source
  /// (Referer checks are extremely common).
  Map<String, String> get mediaHeaders => const {};
}
