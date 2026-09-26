import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../domain/models/media.dart';
import '../domain/source/media_source.dart';
import '../data/download/download_manager.dart';
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

/// The library, per medium. Invalidate after add/remove to refresh.
final libraryProvider =
    FutureProvider.family<List<MediaItem>, MediaType>((ref, type) async {
  ref.watch(extensionManagerProvider);
  return ref.watch(databaseProvider).library(type);
});

final historyProvider = FutureProvider<List<MediaItem>>(
  (ref) => ref.watch(databaseProvider).history(),
);
