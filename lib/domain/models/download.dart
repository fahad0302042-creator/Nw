/// Download queue domain model.
library;

import 'media.dart';

enum DownloadStatus {
  queued,
  downloading,
  completed,
  failed,
  paused,
  cancelled;

  bool get isTerminal =>
      this == completed || this == cancelled;
  bool get isActive => this == queued || this == downloading;
}

/// One queued unit of work: a manga chapter or an anime episode.
///
/// Identity is `(sourceId, itemUrl, unitUrl)` — the same triple the library
/// uses — so a task survives restarts and can be matched back to its row
/// without holding object references.
class DownloadTask {
  const DownloadTask({
    required this.sourceId,
    required this.type,
    required this.itemUrl,
    required this.itemTitle,
    required this.unitUrl,
    required this.unitName,
    this.status = DownloadStatus.queued,
    this.completedParts = 0,
    this.totalParts = 0,
    this.bytes = 0,
    this.error,
    this.id,
  });

  final int? id;
  final String sourceId;
  final MediaType type;

  final String itemUrl;
  final String itemTitle;
  final String unitUrl;
  final String unitName;

  final DownloadStatus status;

  /// Pages fetched (manga) or HLS segments fetched (anime). For a
  /// progressive MP4 these are bytes-based and [totalParts] is the file size.
  final int completedParts;
  final int totalParts;

  /// Bytes written so far, for the storage read-out.
  final int bytes;

  final String? error;

  String get key => '$sourceId::$itemUrl::$unitUrl';

  /// 0..1, or null when the total is not yet known (the honest answer for a
  /// server that sends no Content-Length).
  double? get progress {
    if (status == DownloadStatus.completed) return 1;
    if (totalParts <= 0) return null;
    return (completedParts / totalParts).clamp(0.0, 1.0);
  }

  DownloadTask copyWith({
    int? id,
    DownloadStatus? status,
    int? completedParts,
    int? totalParts,
    int? bytes,
    String? error,
    bool clearError = false,
  }) =>
      DownloadTask(
        id: id ?? this.id,
        sourceId: sourceId,
        type: type,
        itemUrl: itemUrl,
        itemTitle: itemTitle,
        unitUrl: unitUrl,
        unitName: unitName,
        status: status ?? this.status,
        completedParts: completedParts ?? this.completedParts,
        totalParts: totalParts ?? this.totalParts,
        bytes: bytes ?? this.bytes,
        error: clearError ? null : (error ?? this.error),
      );

  Map<String, Object?> toRow() => {
        'source_id': sourceId,
        'type': type.name,
        'item_url': itemUrl,
        'item_title': itemTitle,
        'unit_url': unitUrl,
        'unit_name': unitName,
        'status': status.name,
        'completed_parts': completedParts,
        'total_parts': totalParts,
        'bytes': bytes,
        'error': error,
      };

  factory DownloadTask.fromRow(Map<String, Object?> r) => DownloadTask(
        id: r['id'] as int?,
        sourceId: '${r['source_id']}',
        type: MediaTypeX.parse('${r['type']}'),
        itemUrl: '${r['item_url']}',
        itemTitle: '${r['item_title']}',
        unitUrl: '${r['unit_url']}',
        unitName: '${r['unit_name']}',
        status: DownloadStatus.values.firstWhere(
          (e) => e.name == r['status'],
          orElse: () => DownloadStatus.queued,
        ),
        completedParts: (r['completed_parts'] as int?) ?? 0,
        totalParts: (r['total_parts'] as int?) ?? 0,
        bytes: (r['bytes'] as int?) ?? 0,
        error: r['error'] as String?,
      );
}
