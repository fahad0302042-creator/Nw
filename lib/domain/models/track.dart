/// Tracking (AniList / MyAnimeList) domain model.
library;

enum TrackerId {
  anilist('AniList'),
  myanimelist('MyAnimeList');

  const TrackerId(this.label);
  final String label;

  static TrackerId? parse(String? v) {
    for (final t in TrackerId.values) {
      if (t.name == v) return t;
    }
    return null;
  }
}

/// Reading/watching status, mapped per service.
enum TrackStatus {
  reading('Reading'),
  planToRead('Plan to read'),
  completed('Completed'),
  onHold('On hold'),
  dropped('Dropped'),
  rereading('Rereading');

  const TrackStatus(this.label);
  final String label;

  static TrackStatus parse(String? v) => TrackStatus.values.firstWhere(
        (e) => e.name == v,
        orElse: () => TrackStatus.reading,
      );
}

/// A remote entry on a tracking service, linked to a local library item.
class TrackLink {
  const TrackLink({
    required this.tracker,
    required this.remoteId,
    required this.title,
    this.itemId,
    this.status = TrackStatus.reading,
    this.lastProgress = 0,
    this.totalUnits = 0,
    this.score = 0,
    this.remoteUrl,
    this.coverUrl,
    this.id,
  });

  final int? id;
  final int? itemId;

  final TrackerId tracker;

  /// Service-side media id.
  final String remoteId;
  final String title;

  final TrackStatus status;

  /// Chapters read / episodes watched, as last pushed.
  final int lastProgress;

  /// Total on the service, 0 when unknown/ongoing.
  final int totalUnits;

  /// 0..10 (normalised); 0 means unscored.
  final double score;

  final String? remoteUrl;
  final String? coverUrl;

  TrackLink copyWith({
    int? id,
    int? itemId,
    TrackStatus? status,
    int? lastProgress,
    int? totalUnits,
    double? score,
  }) =>
      TrackLink(
        id: id ?? this.id,
        itemId: itemId ?? this.itemId,
        tracker: tracker,
        remoteId: remoteId,
        title: title,
        status: status ?? this.status,
        lastProgress: lastProgress ?? this.lastProgress,
        totalUnits: totalUnits ?? this.totalUnits,
        score: score ?? this.score,
        remoteUrl: remoteUrl,
        coverUrl: coverUrl,
      );

  Map<String, Object?> toRow() => {
        'item_id': itemId,
        'tracker': tracker.name,
        'remote_id': remoteId,
        'title': title,
        'status': status.name,
        'last_progress': lastProgress,
        'total_units': totalUnits,
        'score': score,
        'remote_url': remoteUrl,
        'cover_url': coverUrl,
      };

  factory TrackLink.fromRow(Map<String, Object?> r) => TrackLink(
        id: r['id'] as int?,
        itemId: r['item_id'] as int?,
        tracker: TrackerId.parse('${r['tracker']}') ?? TrackerId.anilist,
        remoteId: '${r['remote_id']}',
        title: '${r['title']}',
        status: TrackStatus.parse(r['status'] as String?),
        lastProgress: (r['last_progress'] as int?) ?? 0,
        totalUnits: (r['total_units'] as int?) ?? 0,
        score: (r['score'] as num?)?.toDouble() ?? 0,
        remoteUrl: r['remote_url'] as String?,
        coverUrl: r['cover_url'] as String?,
      );
}

/// A candidate returned when searching a tracking service.
class TrackSearchResult {
  const TrackSearchResult({
    required this.remoteId,
    required this.title,
    this.coverUrl,
    this.totalUnits = 0,
    this.summary,
    this.remoteUrl,
  });

  final String remoteId;
  final String title;
  final String? coverUrl;
  final int totalUnits;
  final String? summary;
  final String? remoteUrl;
}
