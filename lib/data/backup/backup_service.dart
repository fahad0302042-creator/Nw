import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/category.dart';
import '../../domain/models/media.dart';
import '../../domain/models/track.dart';
import '../db/app_database.dart';
import '../track/token_store.dart';
import '../../extensions/extension_manager.dart';

/// Exports and restores everything that cannot be re-downloaded: the
/// library, read state, categories, tracker links, and which extensions and
/// repositories you had.
///
/// Deliberately *not* included: cover images, downloaded chapters and
/// cookies. They are large, re-fetchable, or device-specific, and a backup
/// people are afraid to share is a backup they never make.
class BackupService {
  BackupService({required this.db, required this.extensions});

  final AppDatabase db;
  final ExtensionManager extensions;

  static const formatVersion = 1;

  // ----------------------------------------------------------------- export

  Future<Map<String, dynamic>> buildBackup() async {
    final tokens = await TokenStore.instance();
    final categories = await db.categories();

    final items = <Map<String, dynamic>>[];
    for (final type in MediaType.values) {
      for (final item in await db.library(type)) {
        final id = item.id;
        if (id == null) continue;

        final units = await db.units(id);
        items.add({
          'sourceId': item.sourceId,
          'type': item.type.name,
          'url': item.url,
          'title': item.title,
          'thumbnailUrl': item.thumbnailUrl,
          'author': item.author,
          'artist': item.artist,
          'description': item.description,
          'genres': item.genres,
          'status': item.status.name,
          'categories': await db.categoriesForItem(id),
          // Only units with state worth preserving — a full chapter dump
          // would bloat the file for data the source re-supplies anyway.
          'units': [
            for (final u in units)
              if (u.read || u.progress > 0)
                {
                  'url': u.url,
                  'name': u.name,
                  'number': u.number,
                  'read': u.read,
                  'progress': u.progress,
                }
          ],
          'tracks': [
            for (final t in await db.trackLinks(id))
              {
                'tracker': t.tracker.name,
                'remoteId': t.remoteId,
                'title': t.title,
                'status': t.status.name,
                'lastProgress': t.lastProgress,
                'totalUnits': t.totalUnits,
                'score': t.score,
                'remoteUrl': t.remoteUrl,
                'coverUrl': t.coverUrl,
              }
          ],
        });
      }
    }

    return {
      'format': formatVersion,
      'app': 'Kurayomi',
      'createdAt': DateTime.now().toIso8601String(),
      'categories': [
        for (final c in categories)
          {'id': c.id, 'name': c.name, 'sortOrder': c.sortOrder}
      ],
      'items': items,
      'repositories': extensions.repoUrls,
      'extensions': [for (final e in extensions.installed) e.toJson()],
      'trackerClientIds': tokens.exportSettings(),
    };
  }

  /// Writes a backup into the app's cache and returns the file, ready to be
  /// shared or copied out.
  Future<File> writeBackup() async {
    final data = await buildBackup();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File(p.join(dir.path, 'kurayomi-backup-$stamp.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    return file;
  }

  // ---------------------------------------------------------------- restore

  /// Validates a decoded backup, returning a human-readable problem or null.
  static String? validate(Map<String, dynamic> data) {
    if (data['app'] != 'Kurayomi') return 'Not a Kurayomi backup file.';
    final format = data['format'];
    if (format is! int) return 'Backup is missing a format version.';
    if (format > formatVersion) {
      return 'This backup was made by a newer version of the app '
          '(format $format, this build understands $formatVersion).';
    }
    if (data['items'] is! List) return 'Backup contains no library data.';
    return null;
  }

  Future<RestoreSummary> restore(
    Map<String, dynamic> data, {
    bool mergeWithExisting = true,
  }) async {
    final problem = validate(data);
    if (problem != null) throw FormatException(problem);

    var itemsRestored = 0;
    var unitsRestored = 0;
    var tracksRestored = 0;

    // Categories first: items reference them by their original ids, so keep
    // a map from backup id -> freshly created id.
    final categoryMap = <int, int>{};
    final existing = {for (final c in await db.categories()) c.name: c.id};

    for (final raw in (data['categories'] as List? ?? const [])) {
      final c = (raw as Map).cast<String, dynamic>();
      final name = '${c['name']}';
      final oldId = (c['id'] as num?)?.toInt();
      final newId = existing[name] ?? await db.createCategory(name);
      if (oldId != null) categoryMap[oldId] = newId;
    }

    for (final raw in (data['items'] as List)) {
      final j = (raw as Map).cast<String, dynamic>();
      final type = MediaTypeX.parse('${j['type']}');

      final item = MediaItem(
        sourceId: '${j['sourceId']}',
        type: type,
        url: '${j['url']}',
        title: '${j['title']}',
        thumbnailUrl: j['thumbnailUrl'] as String?,
        author: j['author'] as String?,
        artist: j['artist'] as String?,
        description: j['description'] as String?,
        genres:
            (j['genres'] as List? ?? const []).map((e) => '$e').toList(),
        status: parseStatus(j['status']),
      );

      final itemId = await db.upsertItem(item, inLibrary: true);
      itemsRestored++;

      final units = [
        for (final u in (j['units'] as List? ?? const []))
          MediaUnit(
            url: '${(u as Map)['url']}',
            name: '${u['name']}',
            number: (u['number'] as num?)?.toDouble() ?? -1,
          )
      ];
      if (units.isNotEmpty) {
        await db.syncUnits(itemId, units);
        // Re-apply read state now the rows exist.
        final stored = {for (final u in await db.units(itemId)) u.url: u};
        for (final u in (j['units'] as List)) {
          final m = (u as Map).cast<String, dynamic>();
          final row = stored['${m['url']}'];
          if (row?.id == null) continue;
          await db.setProgress(
            row!.id!,
            read: m['read'] == true,
            progress: (m['progress'] as num?)?.toInt() ?? 0,
          );
          unitsRestored++;
        }
      }

      final cats = [
        for (final c in (j['categories'] as List? ?? const []))
          if (categoryMap[(c as num).toInt()] != null)
            categoryMap[c.toInt()]!
      ];
      if (cats.isNotEmpty) await db.setItemCategories(itemId, cats);

      for (final t in (j['tracks'] as List? ?? const [])) {
        final m = (t as Map).cast<String, dynamic>();
        final tracker = TrackerId.parse('${m['tracker']}');
        if (tracker == null) continue;
        await db.upsertTrackLink(TrackLink(
          itemId: itemId,
          tracker: tracker,
          remoteId: '${m['remoteId']}',
          title: '${m['title']}',
          status: TrackStatus.parse(m['status'] as String?),
          lastProgress: (m['lastProgress'] as num?)?.toInt() ?? 0,
          totalUnits: (m['totalUnits'] as num?)?.toInt() ?? 0,
          score: (m['score'] as num?)?.toDouble() ?? 0,
          remoteUrl: m['remoteUrl'] as String?,
          coverUrl: m['coverUrl'] as String?,
        ));
        tracksRestored++;
      }
    }

    // Repositories are restored, but extensions are NOT auto-installed:
    // that would mean silently downloading and executing code on restore.
    var reposRestored = 0;
    for (final url in (data['repositories'] as List? ?? const [])) {
      try {
        await extensions.addRepo('$url');
        reposRestored++;
      } catch (_) {/* dead repo — keep going */}
    }

    if (data['trackerClientIds'] is Map) {
      final tokens = await TokenStore.instance();
      await tokens.importSettings(
          (data['trackerClientIds'] as Map).cast<String, dynamic>());
    }

    return RestoreSummary(
      items: itemsRestored,
      units: unitsRestored,
      tracks: tracksRestored,
      repositories: reposRestored,
      extensionsListed: (data['extensions'] as List? ?? const []).length,
    );
  }
}

class RestoreSummary {
  const RestoreSummary({
    required this.items,
    required this.units,
    required this.tracks,
    required this.repositories,
    required this.extensionsListed,
  });

  final int items;
  final int units;
  final int tracks;
  final int repositories;
  final int extensionsListed;

  @override
  String toString() =>
      '$items titles, $units read markers, $tracks tracker links, '
      '$repositories repositories';
}
