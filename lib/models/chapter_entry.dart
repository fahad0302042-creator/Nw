/// A chapter (manga) or episode (anime) entry belonging to one title.
class ChapterEntry {
  final String url;
  final String title;
  final double? number;
  final String? dateUpload;
  final String? scanlator;

  const ChapterEntry({
    required this.url,
    required this.title,
    this.number,
    this.dateUpload,
    this.scanlator,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'number': number,
        'dateUpload': dateUpload,
        'scanlator': scanlator,
      };

  factory ChapterEntry.fromJson(Map<String, dynamic> json) => ChapterEntry(
        url: json['url'] as String,
        title: json['title'] as String? ?? '',
        number: (json['number'] as num?)?.toDouble(),
        dateUpload: json['dateUpload'] as String?,
        scanlator: json['scanlator'] as String?,
      );
}
