import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme_controller.dart';
import '../../domain/models/media.dart';
import '../common/widgets.dart';
import '../details/details_page.dart';

/// Saved manga and anime, split into two tabs.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});
  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  String _query = '';

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Manga'), Tab(text: 'Anime')],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Filter library',
            onPressed: () async {
              final q = await showDialog<String>(
                context: context,
                builder: (_) => _FilterDialog(initial: _query),
              );
              if (q != null) setState(() => _query = q);
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _LibraryGrid(type: MediaType.manga, query: _query),
          _LibraryGrid(type: MediaType.anime, query: _query),
        ],
      ),
    );
  }
}

class _FilterDialog extends StatelessWidget {
  const _FilterDialog({required this.initial});
  final String initial;

  @override
  Widget build(BuildContext context) {
    final c = TextEditingController(text: initial);
    return AlertDialog(
      title: const Text('Filter library'),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Title contains…'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Clear'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, c.text),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _LibraryGrid extends ConsumerWidget {
  const _LibraryGrid({required this.type, required this.query});
  final MediaType type;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(libraryProvider(type));
    final appearance = ref.watch(appearanceProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(libraryProvider(type)),
      ),
      data: (all) {
        final items = query.isEmpty
            ? all
            : all
                .where((e) =>
                    e.title.toLowerCase().contains(query.toLowerCase()))
                .toList();

        if (items.isEmpty) {
          return EmptyState(
            icon: type == MediaType.manga
                ? Icons.menu_book_outlined
                : Icons.movie_outlined,
            title: 'Your ${type.label.toLowerCase()} library is empty',
            message:
                'Install an extension from Browse → Extensions, then add titles here.',
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(libraryProvider(type)),
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: coverGridDelegate(appearance.gridColumns),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final item = items[i];
              return MediaGridTile(
                item: item,
                showTitle: appearance.showTitles,
                headers: ref
                    .watch(sourceByIdProvider(item.sourceId))
                    ?.mediaHeaders,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DetailsPage(item: item)),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
