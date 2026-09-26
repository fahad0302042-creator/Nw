import 'package:flutter/material.dart';

import '../app.dart';
import '../extensions/manifest.dart';
import 'source_browse_page.dart';
import 'widgets/media_grid.dart';

class BrowsePage extends StatelessWidget {
  const BrowsePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final sources = state.installed;

    return Scaffold(
      appBar: AppBar(title: const Text('Browse'), centerTitle: false),
      body: sources.isEmpty
          ? const StatusView(
              icon: Icons.extension_outlined,
              title: 'No sources installed',
              message:
                  'Go to the Extensions tab, add a repository url and install '
                  'the sources you want to read from.',
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sources.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final SourceManifest source = sources[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: source.isAnime
                        ? Colors.deepPurple.shade400
                        : Colors.teal.shade600,
                    child: Icon(
                      source.isAnime ? Icons.movie_outlined : Icons.menu_book_outlined,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(source.name),
                  subtitle: Text(
                    '${source.type} · ${source.lang.toUpperCase()} · v${source.version}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SourceBrowsePage(source: source),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
