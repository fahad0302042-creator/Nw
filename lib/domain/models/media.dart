/// Core domain models shared by manga and anime sources.
///
/// A deliberate design choice: manga and anime are modelled as the *same*
/// entity type (`MediaItem`) with a [MediaType] discriminator, and the
/// "unit of consumption" (`MediaUnit`) covers both a manga chapter and an
/// anime episode. This keeps library, history, downloads and tracking code
/// written exactly once instead of twice.
library;

enum MediaType { manga, anime }

extension MediaTypeX on MediaType {
  String get id => name;
  String get label => this == MediaType.manga ? 'Manga' : 'Anime';

  /// What a `MediaUnit` is called in this medium.
  String get unitLabel => this == MediaType.manga ? 'Chapter' : 'Episode';
  String get unitLabelPlural => this == MediaType.manga ? 'Chapters' : 'Episodes';

  static MediaType parse(String? v) =>
      v == 'anime' ? MediaType.anime : MediaType.manga;
}

enum MediaStatus { unknown, ongoing, completed, licensed, hiatus, cancelled }

MediaStatus parseStatus(Object? v) {
  final s = v?.toString().toLowerCase().trim();
  return switch (s) {
    'ongoing' || 'releasing' || '1' => MediaStatus.ongoing,
    'completed' || 'finished' || '2' => MediaStatus.completed,
    'licensed' || '3' => MediaStatus.licensed,
    'hiatus' || '6' => MediaStatus.hiatus,
    'cancelled' || 'canceled' || '5' => MediaStatus.cancelled,
    _ => MediaStatus.unknown,
  };
}

/// A manga series or an anime show.
class MediaItem {
  const MediaItem({
    required this.sourceId,
    required this.type,
    required this.url,
    required this.title,
    this.thumbnailUrl,
    this.author,
    this.artist,
    this.description,
    this.genres = const [],
    this.status = MediaStatus.unknown,
    this.initialized = false,
    this.inLibrary = false,
    this.id,
  });

  /// Local database row id (null until saved to the library).
  final int? id;

  /// Id of the extension source this item came from.
  final String sourceId;
  final MediaType type;

  /// Source-relative or absolute URL. Together with [sourceId] this is the
  /// stable identity of an item.
  final String url;

  final String title;
  final String? thumbnailUrl;
  final String? author;
  final String? artist;
  final String? description;
  final List<String> genres;
  final MediaStatus status;

  /// True once a full `details()` call has enriched this item.
  final bool initialized;
  final bool inLibrary;

  String get key => '$sourceId::$url';

  MediaItem copyWith({
    int? id,
    String? sourceId,
    MediaType? type,
    String? url,
    String? title,
    String? thumbnailUrl,
    String? author,
    String? artist,
    String? description,
    List<String>? genres,
    MediaStatus? status,
    bool? initialized,
    bool? inLibrary,
  }) {
    return MediaItem(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      type: type ?? this.type,
      url: url ?? this.url,
      title: title ?? this.title,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      author: author ?? this.author,
      artist: artist ?? this.artist,
      description: description ?? this.description,
      genres: genres ?? this.genres,
      status: status ?? this.status,
      initialized: initialized ?? this.initialized,
      inLibrary: inLibrary ?? this.inLibrary,
    );
  }

  /// Merge a freshly fetched detail payload over a cached/library copy,
  /// preserving local-only fields such as [id] and [inLibrary].
  MediaItem mergeDetails(MediaItem fresh) => copyWith(
        title: fresh.title.isNotEmpty ? fresh.title : title,
        thumbnailUrl: fresh.thumbnailUrl ?? thumbnailUrl,
        author: fresh.author ?? author,
        artist: fresh.artist ?? artist,
        description: fresh.description ?? description,
        genres: fresh.genres.isNotEmpty ? fresh.genres : genres,
        status: fresh.status != MediaStatus.unknown ? fresh.status : status,
        initialized: true,
      );

  factory MediaItem.fromJson(
    Map<String, dynamic> j, {
    required String sourceId,
    required MediaType type,
  }) {
    return MediaItem(
      sourceId: sourceId,
      type: type,
      url: (j['url'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      thumbnailUrl: j['thumbnailUrl']?.toString() ?? j['cover']?.toString(),
      author: j['author']?.toString(),
      artist: j['artist']?.toString(),
      description: j['description']?.toString(),
      genres: (j['genres'] as List?)?.map((e) => e.toString()).toList() ??
          (j['genre'] is String
              ? (j['genre'] as String)
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList()
              : const []),
      status: parseStatus(j['status']),
      initialized: j['initialized'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'author': author,
        'artist': artist,
        'description': description,
        'genres': genres,
        'status': status.name,
      };
}

/// A manga chapter or an anime episode.
class MediaUnit {
  const MediaUnit({
    required this.url,
    required this.name,
    this.number = -1,
    this.scanlator,
    this.dateUpload,
    this.read = false,
    this.progress = 0,
    this.id,
    this.itemId,
  });

  final int? id;
  final int? itemId;

  final String url;
  final String name;

  /// Chapter/episode number. -1 when unknown.
  final double number;

  /// Scanlation group (manga) or fansub/dub group (anime).
  final String? scanlator;
  final DateTime? dateUpload;

  final bool read;

  /// Last page index (manga) or playback position in ms (anime).
  final int progress;

  MediaUnit copyWith({
    int? id,
    int? itemId,
    bool? read,
    int? progress,
  }) =>
      MediaUnit(
        id: id ?? this.id,
        itemId: itemId ?? this.itemId,
        url: url,
        name: name,
        number: number,
        scanlator: scanlator,
        dateUpload: dateUpload,
        read: read ?? this.read,
        progress: progress ?? this.progress,
      );

  factory MediaUnit.fromJson(Map<String, dynamic> j) {
    final raw = j['dateUpload'];
    return MediaUnit(
      url: (j['url'] ?? '').toString(),
      name: (j['name'] ?? j['title'] ?? '').toString(),
      number: double.tryParse('${j['number'] ?? j['chapterNumber'] ?? -1}') ?? -1,
      scanlator: j['scanlator']?.toString(),
      dateUpload: raw is num
          ? DateTime.fromMillisecondsSinceEpoch(raw.toInt())
          : null,
    );
  }
}

/// One image in a manga chapter.
class ReaderPage {
  const ReaderPage({required this.index, required this.imageUrl, this.headers});
  final int index;
  final String imageUrl;
  final Map<String, String>? headers;

  factory ReaderPage.fromJson(int index, Object? j) {
    if (j is String) return ReaderPage(index: index, imageUrl: j);
    final m = (j as Map).cast<String, dynamic>();
    return ReaderPage(
      index: index,
      imageUrl: (m['imageUrl'] ?? m['url'] ?? '').toString(),
      headers: (m['headers'] as Map?)?.map((k, v) => MapEntry('$k', '$v')),
    );
  }
}

/// One playable stream for an anime episode.
class VideoStream {
  const VideoStream({
    required this.url,
    required this.quality,
    this.headers,
    this.subtitles = const [],
  });

  final String url;
  final String quality;
  final Map<String, String>? headers;
  final List<SubtitleTrack> subtitles;

  factory VideoStream.fromJson(Map<String, dynamic> j) => VideoStream(
        url: (j['url'] ?? '').toString(),
        quality: (j['quality'] ?? 'Default').toString(),
        headers: (j['headers'] as Map?)?.map((k, v) => MapEntry('$k', '$v')),
        subtitles: (j['subtitles'] as List? ?? const [])
            .map((e) => SubtitleTrack.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class SubtitleTrack {
  const SubtitleTrack({required this.url, required this.label});
  final String url;
  final String label;

  factory SubtitleTrack.fromJson(Map<String, dynamic> j) => SubtitleTrack(
        url: (j['url'] ?? '').toString(),
        label: (j['label'] ?? j['lang'] ?? 'Subtitle').toString(),
      );
}

/// A page of browse/search results.
class MediaPage {
  const MediaPage({required this.items, required this.hasNextPage});
  final List<MediaItem> items;
  final bool hasNextPage;

  static const empty = MediaPage(items: [], hasNextPage: false);
}
