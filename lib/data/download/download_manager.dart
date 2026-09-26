import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/download.dart';
import '../../domain/models/media.dart';
import '../../domain/source/media_source.dart';
import '../db/app_database.dart';
import '../net/app_http_client.dart';
import 'download_storage.dart';
import 'hls.dart';

/// Runs the download queue.
///
/// Design notes:
/// * The queue is persisted, so an app killed mid-download resumes instead
///   of forgetting what you asked for.
/// * Exactly [maxConcurrentTasks] units download at once; within a chapter,
///   pages are fetched [pagesInParallel] at a time. Sources rate-limit
///   aggressively, and a 50-way parallel fetch is the fastest route to a
///   temporary IP ban.
/// * Every partial file is written to `.part` and renamed on success, and
///   the unit folder only gets its `.complete` marker at the very end.
/// * `notifyListeners` is throttled — a byte-level progress callback would
///   otherwise rebuild the UI thousands of times a second.
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.db,
    required this.resolveSource,
    this.maxConcurrentTasks = 2,
    this.pagesInParallel = 3,
  });

  final AppDatabase db;

  /// Indirection so the manager does not depend on Riverpod.
  final MediaSource? Function(String sourceId) resolveSource;

  final int maxConcurrentTasks;
  final int pagesInParallel;

  final Map<String, DownloadTask> _tasks = {};
  final Map<String, CancelToken> _cancelTokens = {};

  bool _paused = false;
  bool _pumping = false;
  int _running = 0;

  Timer? _notifyThrottle;
  bool _notifyPending = false;

  bool get isPaused => _paused;

  List<DownloadTask> get tasks {
    final list = _tasks.values.toList();
    // Active first, then queued, then finished — the order people expect.
    int rank(DownloadTask t) => switch (t.status) {
          DownloadStatus.downloading => 0,
          DownloadStatus.queued => 1,
          DownloadStatus.paused => 2,
          DownloadStatus.failed => 3,
          DownloadStatus.completed => 4,
          DownloadStatus.cancelled => 5,
        };
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : (a.id ?? 0).compareTo(b.id ?? 0);
    });
    return list;
  }

  List<DownloadTask> get activeTasks =>
      tasks.where((t) => t.status.isActive).toList();

  int get activeCount => activeTasks.length;

  DownloadTask? taskFor(String sourceId, String itemUrl, String unitUrl) =>
      _tasks['$sourceId::$itemUrl::$unitUrl'];

  // --------------------------------------------------------------- lifecycle

  Future<void> init() async {
    for (final row in await db.allDownloads()) {
      final task = DownloadTask.fromRow(row);
      // Anything caught mid-flight by a kill is re-queued, not lost.
      _tasks[task.key] = task.status == DownloadStatus.downloading
          ? task.copyWith(status: DownloadStatus.queued)
          : task;
    }
    notifyListeners();
    unawaited(_pump());
  }

  void _scheduleNotify() {
    _notifyPending = true;
    _notifyThrottle ??= Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!_notifyPending) return;
      _notifyPending = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _notifyThrottle?.cancel();
    for (final t in _cancelTokens.values) {
      t.cancel('manager disposed');
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ queue

  /// Adds units to the queue, skipping ones already downloaded or queued.
  Future<int> enqueue({
    required MediaItem item,
    required List<MediaUnit> units,
  }) async {
    final storage = await DownloadStorage.instance();
    var added = 0;

    for (final unit in units) {
      final key = '${item.sourceId}::${item.url}::${unit.url}';
      final existing = _tasks[key];
      if (existing != null && existing.status != DownloadStatus.failed &&
          existing.status != DownloadStatus.cancelled) {
        continue;
      }
      if (storage.hasLocalCopy(
          item.type, item.sourceId, item.title, unit.name)) {
        continue;
      }

      var task = DownloadTask(
        sourceId: item.sourceId,
        type: item.type,
        itemUrl: item.url,
        itemTitle: item.title,
        unitUrl: unit.url,
        unitName: unit.name,
      );
      final id = await db.upsertDownload(task.toRow());
      task = task.copyWith(id: id);
      _tasks[key] = task;
      added++;
    }

    if (added > 0) {
      notifyListeners();
      unawaited(_pump());
    }
    return added;
  }

  Future<void> cancel(DownloadTask task) async {
    _cancelTokens[task.key]?.cancel('cancelled by user');
    _cancelTokens.remove(task.key);
    _tasks.remove(task.key);
    if (task.id != null) await db.deleteDownload(task.id!);
    notifyListeners();
    unawaited(_pump());
  }

  Future<void> retry(DownloadTask task) async {
    await _update(task.copyWith(
      status: DownloadStatus.queued,
      completedParts: 0,
      clearError: true,
    ));
    unawaited(_pump());
  }

  void pauseAll() {
    _paused = true;
    for (final t in _cancelTokens.values) {
      t.cancel('paused');
    }
    _cancelTokens.clear();
    for (final task in _tasks.values.toList()) {
      if (task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.queued) {
        _tasks[task.key] = task.copyWith(status: DownloadStatus.paused);
        unawaited(db.upsertDownload(_tasks[task.key]!.toRow()));
      }
    }
    notifyListeners();
  }

  void resumeAll() {
    _paused = false;
    for (final task in _tasks.values.toList()) {
      if (task.status == DownloadStatus.paused) {
        _tasks[task.key] = task.copyWith(status: DownloadStatus.queued);
        unawaited(db.upsertDownload(_tasks[task.key]!.toRow()));
      }
    }
    notifyListeners();
    unawaited(_pump());
  }

  Future<void> clearFinished() async {
    for (final task in _tasks.values.toList()) {
      if (task.status == DownloadStatus.completed ||
          task.status == DownloadStatus.cancelled) {
        _tasks.remove(task.key);
        if (task.id != null) await db.deleteDownload(task.id!);
      }
    }
    notifyListeners();
  }

  /// Removes the files for a unit and forgets its task.
  Future<void> deleteDownloaded(DownloadTask task) async {
    final storage = await DownloadStorage.instance();
    await storage.deleteUnit(task.sourceId, task.itemTitle, task.unitName);
    _tasks.remove(task.key);
    if (task.id != null) await db.deleteDownload(task.id!);
    notifyListeners();
  }

  Future<void> deleteEverything() async {
    for (final t in _cancelTokens.values) {
      t.cancel('storage cleared');
    }
    _cancelTokens.clear();
    final storage = await DownloadStorage.instance();
    await storage.deleteAll();
    _tasks.clear();
    await db.clearDownloads();
    notifyListeners();
  }

  // ----------------------------------------------------------------- engine

  Future<void> _update(DownloadTask task, {bool throttle = false}) async {
    _tasks[task.key] = task;
    if (task.id != null) await db.upsertDownload(task.toRow());
    if (throttle) {
      _scheduleNotify();
    } else {
      notifyListeners();
    }
  }

  /// Starts work until the concurrency limit is reached. Re-entrant safe.
  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (!_paused && _running < maxConcurrentTasks) {
        final next = _tasks.values
            .where((t) => t.status == DownloadStatus.queued)
            .fold<DownloadTask?>(
                null,
                (best, t) =>
                    best == null || (t.id ?? 0) < (best.id ?? 0) ? t : best);
        if (next == null) break;

        _running++;
        unawaited(_run(next).whenComplete(() {
          _running--;
          unawaited(_pump());
        }));
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _run(DownloadTask task) async {
    final source = resolveSource(task.sourceId);
    if (source == null) {
      await _update(task.copyWith(
        status: DownloadStatus.failed,
        error: 'Extension for this source is not installed',
      ));
      return;
    }

    final cancelToken = CancelToken();
    _cancelTokens[task.key] = cancelToken;
    await _update(task.copyWith(status: DownloadStatus.downloading));

    try {
      final storage = await DownloadStorage.instance();
      final dir =
          storage.unitDir(task.sourceId, task.itemTitle, task.unitName);
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final unit = MediaUnit(url: task.unitUrl, name: task.unitName);

      if (task.type == MediaType.manga) {
        await _downloadChapter(task, source, unit, dir, cancelToken);
      } else {
        await _downloadEpisode(task, source, unit, dir, cancelToken);
      }

      await storage.markComplete(dir);
      await _update(_tasks[task.key]!.copyWith(
        status: DownloadStatus.completed,
        clearError: true,
      ));
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        final current = _tasks[task.key];
        // A pause already set the right status; a cancel removed the task.
        if (current != null && current.status == DownloadStatus.downloading) {
          await _update(current.copyWith(status: DownloadStatus.paused));
        }
      } else {
        await _fail(task, e.message ?? e.toString());
      }
    } catch (e) {
      await _fail(task, '$e');
    } finally {
      _cancelTokens.remove(task.key);
    }
  }

  Future<void> _fail(DownloadTask task, String message) async {
    final current = _tasks[task.key] ?? task;
    await _update(current.copyWith(
      status: DownloadStatus.failed,
      error: message,
    ));
  }

  // ------------------------------------------------------------------ manga

  Future<void> _downloadChapter(
    DownloadTask task,
    MediaSource source,
    MediaUnit unit,
    Directory dir,
    CancelToken cancelToken,
  ) async {
    final pages = await source.pages(unit);
    if (pages.isEmpty) {
      throw StateError('The source returned no pages for this chapter');
    }

    await _update(
      _tasks[task.key]!.copyWith(totalParts: pages.length, completedParts: 0),
    );

    final client = await AppHttpClient.instance();
    final headers = source.mediaHeaders;
    var done = 0;
    var bytes = 0;

    // Fixed-size worker pool over a shared cursor: simple, and it keeps the
    // concurrency constant instead of spiking at chunk boundaries.
    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        if (cancelToken.isCancelled) return;
        final index = cursor++;
        if (index >= pages.length) return;

        final page = pages[index];
        final ext = DownloadStorage.extensionFor(page.imageUrl);
        final target =
            File(p.join(dir.path, '${(index + 1).toString().padLeft(3, '0')}$ext'));

        // Resume support: an existing non-empty file is trusted.
        if (target.existsSync() && await target.length() > 0) {
          bytes += await target.length();
        } else {
          final written = await _downloadFile(
            client: client,
            url: page.imageUrl,
            target: target,
            headers: {...headers, ...?page.headers},
            cancelToken: cancelToken,
          );
          bytes += written;
        }

        done++;
        await _update(
          _tasks[task.key]!.copyWith(completedParts: done, bytes: bytes),
          throttle: true,
        );
      }
    }

    await Future.wait(
      List.generate(pagesInParallel.clamp(1, pages.length), (_) => worker()),
    );

    if (cancelToken.isCancelled) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: ''),
        reason: 'cancelled',
      );
    }
  }

  // ------------------------------------------------------------------ anime

  Future<void> _downloadEpisode(
    DownloadTask task,
    MediaSource source,
    MediaUnit unit,
    Directory dir,
    CancelToken cancelToken,
  ) async {
    final streams = await source.videos(unit);
    if (streams.isEmpty) {
      throw StateError('The source returned no streams for this episode');
    }

    final stream = streams.first; // sources return best-first
    final client = await AppHttpClient.instance();
    final headers = {...source.mediaHeaders, ...?stream.headers};

    if (!Hls.looksLikeHls(stream.url)) {
      final ext = DownloadStorage.extensionFor(stream.url, fallback: '.mp4');
      final target = File(p.join(dir.path, 'video$ext'));
      final written = await _downloadFile(
        client: client,
        url: stream.url,
        target: target,
        headers: headers,
        cancelToken: cancelToken,
        onProgress: (received, total) async {
          await _update(
            _tasks[task.key]!.copyWith(
              completedParts: received,
              totalParts: total > 0 ? total : 0,
              bytes: received,
            ),
            throttle: true,
          );
        },
      );
      await _update(
        _tasks[task.key]!.copyWith(bytes: written, completedParts: written),
      );
      return;
    }

    await _downloadHls(task, client, stream.url, headers, dir, cancelToken);
  }

  Future<void> _downloadHls(
    DownloadTask task,
    AppHttpClient client,
    String url,
    Map<String, String> headers,
    Directory dir,
    CancelToken cancelToken,
  ) async {
    Future<HlsPlaylist> fetch(String u) async {
      final res = await client.request(u, headers: headers);
      return Hls.parse(res.data ?? '', res.realUri.toString());
    }

    var playlist = await fetch(url);
    var mediaUrl = url;

    if (playlist.isMaster) {
      final best = Hls.bestVariant(playlist);
      if (best == null) {
        throw UnsupportedStreamException('The HLS master playlist is empty');
      }
      mediaUrl = best.url;
      playlist = await fetch(mediaUrl);
    }

    if (playlist.encrypted) {
      // Better an honest refusal now than an unplayable file discovered
      // offline later.
      throw UnsupportedStreamException(
        'This episode uses encrypted HLS, which cannot be saved offline.',
      );
    }
    if (playlist.segments.isEmpty) {
      throw UnsupportedStreamException('The HLS playlist contains no segments');
    }

    final target = File(p.join(dir.path, 'video.ts'));
    final part = File('${target.path}.part');
    if (part.existsSync()) await part.delete();
    final sink = part.openWrite();

    var bytes = 0;
    try {
      // Segments must be concatenated in order, so this stays sequential.
      final all = [
        if (playlist.initSegment != null) playlist.initSegment!,
        ...playlist.segments,
      ];

      await _update(_tasks[task.key]!
          .copyWith(totalParts: all.length, completedParts: 0));

      for (var i = 0; i < all.length; i++) {
        if (cancelToken.isCancelled) {
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: all[i]),
            reason: 'cancelled',
          );
        }
        final res = await client.dio.get<List<int>>(
          all[i],
          options: Options(
            responseType: ResponseType.bytes,
            headers: {...headers, 'User-Agent': client.cookies.userAgentFor(all[i])},
          ),
          cancelToken: cancelToken,
        );
        final data = res.data ?? const <int>[];
        sink.add(data);
        bytes += data.length;

        await _update(
          _tasks[task.key]!.copyWith(completedParts: i + 1, bytes: bytes),
          throttle: true,
        );
      }
    } finally {
      await sink.close();
    }

    await part.rename(target.path);
  }

  // ------------------------------------------------------------------ shared

  /// Downloads to `<target>.part` and renames on success, so a killed app
  /// never leaves a file that looks complete but is truncated.
  Future<int> _downloadFile({
    required AppHttpClient client,
    required String url,
    required File target,
    required Map<String, String> headers,
    required CancelToken cancelToken,
    Future<void> Function(int received, int total)? onProgress,
  }) async {
    final part = File('${target.path}.part');
    if (part.existsSync()) await part.delete();

    await client.dio.download(
      url,
      part.path,
      cancelToken: cancelToken,
      options: Options(headers: {
        ...headers,
        'User-Agent': client.cookies.userAgentFor(url),
        if (client.cookies.cookieHeader(url) != null)
          'Cookie': client.cookies.cookieHeader(url)!,
      }),
      onReceiveProgress: onProgress == null
          ? null
          : (received, total) => unawaited(onProgress(received, total)),
    );

    final length = await part.length();
    if (length == 0) {
      await part.delete();
      throw StateError('Downloaded an empty file from $url');
    }
    await part.rename(target.path);
    return length;
  }
}
