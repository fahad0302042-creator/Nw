import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/models/media.dart';
import '../../domain/source/media_source.dart';
import '../common/widgets.dart';
import 'extensions_page.dart';
import 'source_page.dart';

/// Lists every source provided by the installed extensions.
class BrowsePage extends ConsumerWidget {
  const BrowsePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(extensionManagerProvider);
    final sources = ref.watch(sourcesProvider(null));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse'),
        actions: [
          Badge(
            isLabelVisible: manager.updates.isNotEmpty,
            label: Text('${manager.updates.length}'),
            child: IconButton(
              icon: const Icon(Icons.extension_outlined),
              tooltip: 'Extensions',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExtensionsPage()),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: sources.isEmpty
          ? EmptyState(
              icon: Icons.extension_outlined,
              title: 'No sources installed',
              message:
                  'Add an extension repository, then install extensions to browse '
                  'manga and anime.',
              action: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExtensionsPage()),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Manage extensions'),
              ),
            )
          : ListView(
              children: [
                for (final type in MediaType.values)
                  ..._section(context, ref, type, sources),
              ],
            ),
    );
  }

  List<Widget> _section(
    BuildContext context,
    WidgetRef ref,
    MediaType type,
    List<MediaSource> all,
  ) {
    final group = all.where((s) => s.type == type).toList();
    if (group.isEmpty) return const [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          type.label,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      for (final s in group)
        ListTile(
          leading: CircleAvatar(
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(s.name),
          subtitle: Text(s.lang.toUpperCase()),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SourcePage(sourceId: s.id)),
          ),
        ),
    ];
  }
}
