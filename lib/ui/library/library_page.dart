import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/source/source_manager.dart';
import '../../core/storage/app_storage.dart';
import '../detail/detail_page.dart';
import '../widgets/catalog_grid.dart';
import '../widgets/state_views.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<AppStorage>();
    final sourceManager = context.watch<SourceManager>();
    final entries = storage.library;

    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: entries.isEmpty
          ? const EmptyState(
              icon: Icons.collections_bookmark_outlined,
              title: 'Your library is empty',
              message: 'Add manga or anime from Browse to see them here.',
            )
          : CatalogGrid(
              items: entries.map((e) => e.item).toList(),
              onTap: (item) {
                final source = sourceManager.byId(item.sourceId);
                if (source == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'The extension for this title is no longer installed.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DetailPage(source: source, item: item),
                  ),
                );
              },
            ),
    );
  }
}
