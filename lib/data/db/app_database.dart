import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/category.dart';
import '../../domain/models/media.dart';
import '../../domain/models/track.dart';

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
      version: 3,
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
        await _createDownloads(d);
        await _createCategories(d);
        await _createTracking(d);
        await _addUpdateColumns(d);
      },
      onUpgrade: (d, from, to) async {
        if (from < 2) await _createDownloads(d);
        if (from < 3) {
          await _createCategories(d);
          await _createTracking(d);
          await _addUpdateColumns(d);
        }
      },
    );
    return AppDatabase._(db);
  }

  static Future<void> _createDownloads(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS downloads (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id       TEXT NOT NULL,
        type            TEXT NOT NULL,
        item_url        TEXT NOT NULL,
        item_title      TEXT NOT NULL,
        unit_url        TEXT NOT NULL,
        unit_name       TEXT NOT NULL,
        status          TEXT NOT NULL,
        completed_parts INTEGER NOT NULL DEFAULT 0,
        total_parts     INTEGER NOT NULL DEFAULT 0,
        bytes           INTEGER NOT NULL DEFAULT 0,
        error           TEXT,
        UNIQUE(source_id, item_url, unit_url)
      )
    ''');
    await d.execute(
        'CREATE INDEX IF NOT EXISTS idx_downloads_status ON downloads(status)');
  }

  static Future<void> _createCategories(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // Many-to-many, like Mihon: a series can sit in several categories.
    await d.execute('''
      CREATE TABLE IF NOT EXISTS item_categories (
        item_id     INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
        category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
        PRIMARY KEY (item_id, category_id)
      )
    ''');
  }

  static Future<void> _createTracking(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS track_links (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id       INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
        tracker       TEXT NOT NULL,
        remote_id     TEXT NOT NULL,
        title         TEXT NOT NULL,
        status        TEXT NOT NULL,
        last_progress INTEGER NOT NULL DEFAULT 0,
        total_units   INTEGER NOT NULL DEFAULT 0,
        score         REAL NOT NULL DEFAULT 0,
        remote_url    TEXT,
        cover_url     TEXT,
        UNIQUE(item_id, tracker)
      )
    ''');
  }

  static Future<void> _addUpdateColumns(Database d) async {
    // ALTER TABLE ADD COLUMN is the only portable migration sqlite offers;
    // guard each one so a partially-applied upgrade can be re-run.
    for (final sql in [
      'ALTER TABLE items ADD COLUMN last_checked_at INTEGER',
      'ALTER TABLE items ADD COLUMN new_count INTEGER NOT NULL DEFAULT 0',
    ]) {
      try {
        await d.execute(sql);
      } catch (_) {/* column already present */}
    }
  }

  // ------------------------------------------------------------- categories

  Future<List<LibraryCategory>> categories() async {
    final rows = await db.query('categories', orderBy: 'sort_order ASC, id ASC');
    return rows.map(LibraryCategory.fromRow).toList();
  }

  Future<int> createCategory(String name) async {
    final rows = await db.rawQuery(
        'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next FROM categories');
    return db.insert('categories', {
      'name': name,
      'sort_order': (rows.first['next'] as num).toInt(),
    });
  }

  Future<void> renameCategory(int id, String name) =>
      db.update('categories', {'name': name}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteCategory(int id) =>
      db.delete('categories', where: 'id = ?', whereArgs: [id]);

  Future<void> reorderCategories(List<int> idsInOrder) async {
    final batch = db.batch();
    for (var i = 0; i < idsInOrder.length; i++) {
      batch.update('categories', {'sort_order': i},
          where: 'id = ?', whereArgs: [idsInOrder[i]]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<int>> categoriesForItem(int itemId) async {
    final rows = await db.query('item_categories',
        columns: ['category_id'], where: 'item_id = ?', whereArgs: [itemId]);
    return rows.map((r) => r['category_id'] as int).toList();
  }

  Future<void> setItemCategories(int itemId, List<int> categoryIds) async {
    final batch = db.batch();
    batch.delete('item_categories', where: 'item_id = ?', whereArgs: [itemId]);
    for (final id in categoryIds) {
      batch.insert('item_categories', {'item_id': itemId, 'category_id': id});
    }
    await batch.commit(noResult: true);
  }

  /// Library filtered to a category. [LibraryCategory.allId] returns
  /// everything; [LibraryCategory.uncategorizedId] returns items in no
  /// category at all.
  Future<List<MediaItem>> libraryInCategory(MediaType type, int categoryId) async {
    if (categoryId == LibraryCategory.allId) return library(type);

    final sql = categoryId == LibraryCategory.uncategorizedId
        ? '''
          SELECT i.* FROM items i
          WHERE i.in_library = 1 AND i.type = ?
            AND NOT EXISTS (SELECT 1 FROM item_categories c WHERE c.item_id = i.id)
          ORDER BY i.title COLLATE NOCASE ASC
        '''
        : '''
          SELECT i.* FROM items i
          JOIN item_categories c ON c.item_id = i.id
          WHERE i.in_library = 1 AND i.type = ? AND c.category_id = ?
          ORDER BY i.title COLLATE NOCASE ASC
        ''';

    final rows = await db.rawQuery(
      sql,
      categoryId == LibraryCategory.uncategorizedId
          ? [type.name]
          : [type.name, categoryId],
    );
    return rows.map(_itemFromRow).toList();
  }

  // --------------------------------------------------------------- tracking

  Future<List<TrackLink>> trackLinks(int itemId) async {
    final rows = await db
        .query('track_links', where: 'item_id = ?', whereArgs: [itemId]);
    return rows.map(TrackLink.fromRow).toList();
  }

  Future<int> upsertTrackLink(TrackLink link) async {
    final existing = await db.query('track_links',
        columns: ['id'],
        where: 'item_id = ? AND tracker = ?',
        whereArgs: [link.itemId, link.tracker.name],
        limit: 1);
    if (existing.isEmpty) return db.insert('track_links', link.toRow());
    final id = existing.first['id'] as int;
    await db.update('track_links', link.toRow(), where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<void> deleteTrackLink(int id) =>
      db.delete('track_links', where: 'id = ?', whereArgs: [id]);

  // ---------------------------------------------------------------- updates

  Future<void> markChecked(int itemId, int newCount) => db.update(
        'items',
        {
          'last_checked_at': DateTime.now().millisecondsSinceEpoch,
          'new_count': newCount,
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );

  Future<void> clearNewCount(int itemId) => db.update('items', {'new_count': 0},
      where: 'id = ?', whereArgs: [itemId]);

  Future<Map<int, int>> newCounts() async {
    final rows = await db.query('items',
        columns: ['id', 'new_count'], where: 'in_library = 1 AND new_count > 0');
    return {
      for (final r in rows) r['id'] as int: (r['new_count'] as int?) ?? 0,
    };
  }

  // -------------------------------------------------------------- downloads

  Future<List<Map<String, Object?>>> allDownloads() =>
      db.query('downloads', orderBy: 'id ASC');

  /// Insert or update by the (source, item, unit) identity, preserving the
  /// row id so an in-flight task keeps its queue position.
  Future<int> upsertDownload(Map<String, Object?> row) async {
    final existing = await db.query(
      'downloads',
      columns: ['id'],
      where: 'source_id = ? AND item_url = ? AND unit_url = ?',
      whereArgs: [row['source_id'], row['item_url'], row['unit_url']],
      limit: 1,
    );
    if (existing.isEmpty) {
      return db.insert('downloads', row);
    }
    final id = existing.first['id'] as int;
    await db.update('downloads', row, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<void> deleteDownload(int id) =>
      db.delete('downloads', where: 'id = ?', whereArgs: [id]);

  Future<void> clearDownloads() => db.delete('downloads');

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
  ///
  /// Returns how many units were genuinely new, which is what the library
  /// update check reports to the user.
  Future<int> syncUnits(int itemId, List<MediaUnit> fresh) async {
    final knownRows = await db.query('units',
        columns: ['url'], where: 'item_id = ?', whereArgs: [itemId]);
    final known = {for (final r in knownRows) '${r['url']}'};
    final newCount = fresh.where((u) => !known.contains(u.url)).length;

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
    return newCount;
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
