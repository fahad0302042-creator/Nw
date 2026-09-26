import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/source/source_manager.dart';
import '../../models/extension_manifest.dart';
import '../extensions/extensions_page.dart';
import '../widgets/state_views.dart';
import 'source_browse_page.dart';

class BrowseSourcesPage extends StatelessWidget {
  const BrowseSourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sourceManager = context.watch<SourceManager>();
    final manga = sourceManager.mangaSources;
    final anime = sourceManager.animeSources;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse'),
        actions: [
          IconButton(
            tooltip: 'Manage extensions',
            icon: const Icon(Icons.extension_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExtensionsPage()),
            ),
          ),
        ],
      ),
      body: sourceManager.installed.isEmpty
          ? EmptyState(
              icon: Icons.extension_outlined,
              title: 'No extensions installed',
              message:
                  'Install an extension to start browsing manga or anime sites.',
              action: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ExtensionsPage()),
                ),
                child: const Text('Manage extensions'),
              ),
            )
          : ListView(
              children: [
                if (manga.isNotEmpty) _SourceSection(title: 'Manga', sources: manga),
                if (anime.isNotEmpty) _SourceSection(title: 'Anime', sources: anime),
              ],
            ),
    );
  }
}

class _SourceSection extends StatelessWidget {
  const _SourceSection({required this.title, required this.sources});

  final String title;
  final List<ExtensionManifest> sources;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        ...sources.map(
          (source) => ListTile(
            leading: CircleAvatar(
              child: Text(source.name.isNotEmpty ? source.name[0].toUpperCase() : '?'),
            ),
            title: Text(source.name),
            subtitle: Text('${source.lang.toUpperCase()} \u00b7 v${source.version}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SourceBrowsePage(source: source)),
            ),
          ),
        ),
      ],
    );
  }
}
