import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../domain/models/media.dart';
import '../domain/source/media_source.dart';
import '../data/backup/backup_service.dart';
import '../data/download/download_manager.dart';
import '../data/library/library_updater.dart';
import '../data/track/token_store.dart';
import '../data/track/tracking_service.dart';
import '../domain/models/category.dart';
import '../extensions/extension_manager.dart';

/// Resolved during app bootstrap in main().
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final extensionManagerProvider = ChangeNotifierProvider<ExtensionManager>((ref) {
  final m = ExtensionManager();
  ref.onDispose(m.dispose);
  return m;
});

/// All loaded sources, optionally narrowed to one medium.
final sourcesProvider = Provider.family<List<MediaSource>, MediaType?>((ref, type) {
  final sources = ref.watch(extensionManagerProvider).sources;
  final filtered =
      type == null ? sources : sources.where((s) => s.type == type).toList();
  return filtered..sort((a, b) => a.name.compareTo(b.name));
});

final sourceByIdProvider = Provider.family<MediaSource?, String>(
  (ref, id) => ref.watch(extensionManagerProvider).sourceById(id),
);

final downloadManagerProvider = ChangeNotifierProvider<DownloadManager>((ref) {
  final manager = DownloadManager(
    db: ref.watch(databaseProvider),
    // Resolved lazily: an extension may be installed after the queue exists.
    resolveSource: (id) => ref.read(extensionManagerProvider).sourceById(id),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

final libraryUpdaterProvider = ChangeNotifierProvider<LibraryUpdater>((ref) {
  return LibraryUpdater(
    db: ref.watch(databaseProvider),
    resolveSource: (id) => ref.read(extensionManagerProvider).sourceById(id),
  );
});

/// Resolved during bootstrap, like the database.
final tokenStoreProvider = Provider<TokenStore>(
  (ref) => throw UnimplementedError('tokenStoreProvider must be overridden'),
);

final trackingServiceProvider = ChangeNotifierProvider<TrackingService>((ref) {
  return TrackingService(
    db: ref.watch(databaseProvider),
    tokens: ref.watch(tokenStoreProvider),
  );
});

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(
      db: ref.watch(databaseProvider),
      extensions: ref.watch(extensionManagerProvider),
    ));

final categoriesProvider = FutureProvider<List<LibraryCategory>>(
  (ref) => ref.watch(databaseProvider).categories(),
);

/// Which category the Library tab is showing.
final selectedCategoryProvider =
    StateProvider<int>((ref) => LibraryCategory.allId);

/// Per-item counts of chapters found by the last update check.
final newCountsProvider =
    FutureProvider<Map<int, int>>((ref) => ref.watch(databaseProvider).newCounts());

/// The library, per medium, respecting the selected category.
final libraryProvider =
    FutureProvider.family<List<MediaItem>, MediaType>((ref, type) async {
  ref.watch(extensionManagerProvider);
  final categoryId = ref.watch(selectedCategoryProvider);
  return ref.watch(databaseProvider).libraryInCategory(type, categoryId);
});

final historyProvider = FutureProvider<List<MediaItem>>(
  (ref) => ref.watch(databaseProvider).history(),
);
