import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/media.dart';

/// Owns the on-disk layout of downloaded content.
///
///   <appDocs>/downloads/<sourceId>/<title>/<unit>/
///        001.jpg 002.jpg ...        (manga)
///        video.mp4 | video.ts       (anime)
///        .complete                  (written last; see below)
///
/// A download is only considered usable once the `.complete` marker exists.
/// Without it, an app killed mid-download would leave a half-populated
/// folder that looks identical to a finished one, and the reader would
/// silently show a truncated chapter.
class DownloadStorage {
  DownloadStorage._(this.root);

  final Directory root;

  static DownloadStorage? _instance;

  static Future<DownloadStorage> instance() async {
    if (_instance != null) return _instance!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'downloads'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _instance = DownloadStorage._(dir);
  }

  static const _completeMarker = '.complete';

  /// Makes an arbitrary title safe for every filesystem Android might use
  /// (including FAT32 on removable storage, which is the strictest).
  static String sanitize(String input) {
    var s = input
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Trailing dots and spaces are silently dropped by some filesystems,
    // which would make the path we store differ from the path on disk.
    s = s.replaceAll(RegExp(r'[. ]+$'), '');

    if (s.isEmpty) s = 'untitled';

    // Keep well clear of the 255-byte per-component limit once UTF-8
    // encoded, without cutting a multi-byte character in half.
    const maxBytes = 120;
    while (s.codeUnits.length > maxBytes) {
      s = s.substring(0, s.length - 1);
    }
    return s.trim();
  }

  Directory itemDir(String sourceId, String itemTitle) => Directory(
        p.join(root.path, sanitize(sourceId), sanitize(itemTitle)),
      );

  Directory unitDir(String sourceId, String itemTitle, String unitName) =>
      Directory(p.join(itemDir(sourceId, itemTitle).path, sanitize(unitName)));

  File markerFile(Directory unit) => File(p.join(unit.path, _completeMarker));

  bool isComplete(String sourceId, String itemTitle, String unitName) =>
      markerFile(unitDir(sourceId, itemTitle, unitName)).existsSync();

  Future<void> markComplete(Directory unit) async =>
      markerFile(unit).writeAsString(DateTime.now().toIso8601String());

  /// Downloaded manga pages in reading order, or an empty list if this
  /// chapter is not fully downloaded.
  List<File> localPages(String sourceId, String itemTitle, String unitName) {
    final dir = unitDir(sourceId, itemTitle, unitName);
    if (!markerFile(dir).existsSync()) return const [];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => !p.basename(f.path).startsWith('.'))
        .toList()
      // Zero-padded names sort lexicographically, but compare numerically
      // anyway so a future change to the naming cannot silently shuffle pages.
      ..sort((a, b) {
        int n(File f) =>
            int.tryParse(RegExp(r'\d+').firstMatch(p.basename(f.path))?.group(0) ?? '') ??
            0;
        final byNumber = n(a).compareTo(n(b));
        return byNumber != 0 ? byNumber : a.path.compareTo(b.path);
      });
    return files;
  }

  /// The downloaded video for an episode, if present.
  File? localVideo(String sourceId, String itemTitle, String unitName) {
    final dir = unitDir(sourceId, itemTitle, unitName);
    if (!markerFile(dir).existsSync()) return null;
    for (final name in ['video.mp4', 'video.ts', 'video.mkv', 'video.webm']) {
      final f = File(p.join(dir.path, name));
      if (f.existsSync()) return f;
    }
    return null;
  }

  bool hasLocalCopy(
    MediaType type,
    String sourceId,
    String itemTitle,
    String unitName,
  ) =>
      type == MediaType.manga
          ? localPages(sourceId, itemTitle, unitName).isNotEmpty
          : localVideo(sourceId, itemTitle, unitName) != null;

  Future<void> deleteUnit(
      String sourceId, String itemTitle, String unitName) async {
    final dir = unitDir(sourceId, itemTitle, unitName);
    if (dir.existsSync()) await dir.delete(recursive: true);

    // Tidy up an item folder that has become empty.
    final parent = itemDir(sourceId, itemTitle);
    if (parent.existsSync() && parent.listSync().isEmpty) {
      await parent.delete();
    }
  }

  Future<void> deleteAll() async {
    if (root.existsSync()) await root.delete(recursive: true);
    root.createSync(recursive: true);
  }

  /// Total bytes on disk. Walks the tree, so call it off the hot path.
  Future<int> totalBytes() async {
    if (!root.existsSync()) return 0;
    var total = 0;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {/* deleted mid-walk */}
      }
    }
    return total;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }

  /// Picks a file extension from a URL, ignoring query strings.
  static String extensionFor(String url, {String fallback = '.jpg'}) {
    try {
      final path = Uri.parse(url).path;
      final ext = p.extension(path).toLowerCase();
      const allowed = {
        '.jpg', '.jpeg', '.png', '.webp', '.gif', '.avif', '.bmp',
        '.mp4', '.ts', '.mkv', '.webm', '.m4s',
      };
      if (allowed.contains(ext)) return ext;
    } catch (_) {}
    return fallback;
  }
}
