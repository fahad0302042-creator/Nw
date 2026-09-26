import 'package:flutter/material.dart';

import '../app.dart';
import '../models/media.dart';
import 'details_page.dart';
import 'widgets/media_grid.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = state.library;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        centerTitle: false,
      ),
      body: items.isEmpty
          ? const StatusView(
              icon: Icons.favorite_border,
              title: 'Your library is empty',
              message:
                  'Install an extension, browse a source and tap the heart on '
                  'anything you want to keep here.',
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 140,
                childAspectRatio: 0.52,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final MediaItem item = items[index];
                final source = state.sourceById(item.sourceId);
                return MediaCard(
                  item: item,
                  headers: source?.headers ?? const <String, String>{},
                  onTap: () {
                    if (source == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'The extension for this entry is not installed.',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DetailsPage(source: source, item: item),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
