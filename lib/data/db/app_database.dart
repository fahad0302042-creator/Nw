import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/media.dart';

/// Local persistence for library, chapters/episodes and history.
///
/// Manga and anime share the same tables, discriminated by `type`, which
/// keeps queries (and future features like global search or backup) uniform.
class AppDatabase {
  AppDatabase._(this.db);
  final Database db;

  static Future<AppDatabase> open() async {
    final path = p.join(await getDatabasesPath(), 'kurayomi.db');
    final db = await openDatabase(
      path,
      version: 1,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, _) async {
        await d.execute('''
          CREATE TABLE items (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            source_id     TEXT NOT NULL,
            type          TEXT NOT NULL,
            url           TEXT NOT NULL,
            title         TEXT NOT NULL,
            thumbnail_url TEXT,
            author        TEXT,
            artist        TEXT,
            description   TEXT,
            genres        TEXT,
            status        TEXT,
            in_library    INTEGER NOT NULL DEFAULT 0,
            added_at      INTEGER,
            last_seen_at  INTEGER,
            UNIQUE(source_id, url)
          )
        ''');
        await d.execute('''
          CREATE TABLE units (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id     INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            url         TEXT NOT NULL,
            name        TEXT NOT NULL,
            number      REAL,
            scanlator   TEXT,
            date_upload INTEGER,
            read        INTEGER NOT NULL DEFAULT 0,
            progress    INTEGER NOT NULL DEFAULT 0,
            fetched_at  INTEGER,
            UNIQUE(item_id, url)
          )
        ''');
        await d.execute(
            'CREATE INDEX idx_items_library ON items(in_library, type)');
        await d.execute('CREATE INDEX idx_units_item ON units(item_id)');
      },
    );
    return AppDatabase._(db);
  }

  // ------------------------------------------------------------------ items

  Future<int> upsertItem(MediaItem item, {bool? inLibrary}) async {
    final existing = await db.query(
      'items',
      columns: ['id', 'in_library'],
      where: 'source_id = ? AND url = ?',
      whereArgs: [item.sourceId, item.url],
      limit: 1,
    );

    final values = {
      'source_id': item.sourceId,
      'type': item.type.name,
      'url': item.url,
      'title': item.title,
      'thumbnail_url': item.thumbnailUrl,
      'author': item.author,
      'artist': item.artist,
      'description': item.description,
      'genres': item.genres.join('|'),
      'status': item.status.name,
      'last_seen_at': DateTime.now().millisecondsSinceEpoch,
    };

    if (existing.isEmpty) {
      values['in_library'] = (inLibrary ?? item.inLibrary) ? 1 : 0;
      values['added_at'] = DateTime.now().millisecondsSinceEpoch;
      return db.insert('items', values);
    }

    final id = existing.first['id'] as int;
    if (inLibrary != null) values['in_library'] = inLibrary ? 1 : 0;
    // Never overwrite good cached data with nulls from a thin listing payload.
    values.removeWhere((k, v) => v == null || v == '');
    await db.update('items', values, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<MediaItem?> findItem(String sourceId, String url) async {
    final rows = await db.query(
      'items',
      where: 'source_id = ? AND url = ?',
      whereArgs: [sourceId, url],
      limit: 1,
    );
    return rows.isEmpty ? null : _itemFromRow(rows.first);
  }

  Future<List<MediaItem>> library(MediaType type) async {
    final rows = await db.query(
      'items',
      where: 'in_library = 1 AND type = ?',
      whereArgs: [type.name],
      orderBy: 'title COLLATE NOCASE ASC',
    );
    return rows.map(_itemFromRow).toList();
  }

  Future<void> setInLibrary(int itemId, bool value) => db.update(
        'items',
        {
          'in_library': value ? 1 : 0,
          'added_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );

  Future<List<MediaItem>> history({int limit = 100}) async {
    final rows = await db.rawQuery('''
      SELECT i.* FROM items i
      WHERE EXISTS (SELECT 1 FROM units u WHERE u.item_id = i.id AND u.progress > 0)
      ORDER BY i.last_seen_at DESC LIMIT ?
    ''', [limit]);
    return rows.map(_itemFromRow).toList();
  }

  // ------------------------------------------------------------------ units

  /// Merges a freshly fetched unit list into the cache, preserving read
  /// state and progress for units we already know about.
  Future<void> syncUnits(int itemId, List<MediaUnit> fresh) async {
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final u in fresh) {
      batch.rawInsert('''
        INSERT INTO units (item_id, url, name, number, scanlator, date_upload, fetched_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(item_id, url) DO UPDATE SET
          name = excluded.name,
          number = excluded.number,
          scanlator = excluded.scanlator,
          date_upload = COALESCE(excluded.date_upload, units.date_upload)
      ''', [
        itemId,
        u.url,
        u.name,
        u.number,
        u.scanlator,
        u.dateUpload?.millisecondsSinceEpoch,
        now,
      ]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<MediaUnit>> units(int itemId) async {
    final rows = await db.query(
      'units',
      where: 'item_id = ?',
      whereArgs: [itemId],
      orderBy: 'number DESC, id DESC',
    );
    return rows.map(_unitFromRow).toList();
  }

  Future<void> setProgress(int unitId, {int? progress, bool? read}) => db.update(
        'units',
        {
          if (progress != null) 'progress': progress,
          if (read != null) 'read': read ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [unitId],
      );

  Future<void> markAllRead(int itemId, bool read) => db.update(
        'units',
        {'read': read ? 1 : 0},
        where: 'item_id = ?',
        whereArgs: [itemId],
      );

  Future<int> unreadCount(int itemId) async {
    final r = await db.rawQuery(
        'SELECT COUNT(*) c FROM units WHERE item_id = ? AND read = 0', [itemId]);
    return (r.first['c'] as num).toInt();
  }

  // ----------------------------------------------------------------- mapping

  MediaItem _itemFromRow(Map<String, Object?> r) => MediaItem(
        id: r['id'] as int?,
        sourceId: '${r['source_id']}',
        type: MediaTypeX.parse('${r['type']}'),
        url: '${r['url']}',
        title: '${r['title']}',
        thumbnailUrl: r['thumbnail_url'] as String?,
        author: r['author'] as String?,
        artist: r['artist'] as String?,
        description: r['description'] as String?,
        genres: '${r['genres'] ?? ''}'
            .split('|')
            .where((e) => e.isNotEmpty)
            .toList(),
        status: parseStatus(r['status']),
        initialized: (r['description'] as String?)?.isNotEmpty ?? false,
        inLibrary: (r['in_library'] as int? ?? 0) == 1,
      );

  MediaUnit _unitFromRow(Map<String, Object?> r) => MediaUnit(
        id: r['id'] as int?,
        itemId: r['item_id'] as int?,
        url: '${r['url']}',
        name: '${r['name']}',
        number: (r['number'] as num?)?.toDouble() ?? -1,
        scanlator: r['scanlator'] as String?,
        dateUpload: r['date_upload'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['date_upload'] as int),
        read: (r['read'] as int? ?? 0) == 1,
        progress: (r['progress'] as int? ?? 0),
      );
}
