/// Plain data models shared between the extension engine and the UI.

class MediaItem {
  const MediaItem({
    required this.sourceId,
    required this.title,
    required this.url,
    this.thumbnail,
    this.subtitle,
  });

  final String sourceId;
  final String title;
  final String url;
  final String? thumbnail;
  final String? subtitle;

  String get key => '$sourceId|$url';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sourceId': sourceId,
        'title': title,
        'url': url,
        'thumbnail': thumbnail,
        'subtitle': subtitle,
      };

  static MediaItem fromJson(Map<String, dynamic> json) => MediaItem(
        sourceId: (json['sourceId'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
        thumbnail: json['thumbnail'] as String?,
        subtitle: json['subtitle'] as String?,
      );
}

class MediaDetails {
  const MediaDetails({
    this.title,
    this.description,
    this.author,
    this.artist,
    this.status,
    this.thumbnail,
    this.genres = const <String>[],
  });

  final String? title;
  final String? description;
  final String? author;
  final String? artist;
  final String? status;
  final String? thumbnail;
  final List<String> genres;

  static const MediaDetails empty = MediaDetails();
}

class ChapterItem {
  const ChapterItem({
    required this.name,
    required this.url,
    this.date,
    this.scanlator,
  });

  final String name;
  final String url;
  final String? date;
  final String? scanlator;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'url': url,
        'date': date,
        'scanlator': scanlator,
      };

  static ChapterItem fromJson(Map<String, dynamic> json) => ChapterItem(
        name: (json['name'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
        date: json['date'] as String?,
        scanlator: json['scanlator'] as String?,
      );
}

class VideoSource {
  const VideoSource({
    required this.url,
    this.quality = 'Default',
    this.headers = const <String, String>{},
  });

  final String url;
  final String quality;
  final Map<String, String> headers;
}

class PagedResult<T> {
  const PagedResult(this.items, {this.hasNext = false});

  final List<T> items;
  final bool hasNext;
}
