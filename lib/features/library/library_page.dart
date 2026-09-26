import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/theme_controller.dart';
import '../../domain/models/category.dart';
import '../../domain/models/media.dart';
import '../common/widgets.dart';
import '../details/details_page.dart';

/// Saved manga and anime, split by medium and filtered by category.
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

  Future<void> _runUpdate() async {
    final updater = ref.read(libraryUpdaterProvider);
    if (updater.isRunning) {
      updater.cancel();
      return;
    }
    final result = await updater.run();
    ref.invalidate(libraryProvider);
    ref.invalidate(newCountsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.summary)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final updater = ref.watch(libraryUpdaterProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final selected = ref.watch(selectedCategoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          tabs: const [Tab(text: 'Manga'), Tab(text: 'Anime')],
        ),
        actions: [
          IconButton(
            icon: Icon(updater.isRunning ? Icons.close : Icons.refresh),
            tooltip: updater.isRunning ? 'Stop update' : 'Check for new chapters',
            onPressed: _runUpdate,
          ),
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
      body: Column(
        children: [
          if (updater.isRunning) _UpdateBar(),
          if (categories.isNotEmpty)
            _CategoryStrip(
              categories: categories,
              selected: selected,
              onSelect: (id) =>
                  ref.read(selectedCategoryProvider.notifier).state = id,
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _LibraryGrid(type: MediaType.manga, query: _query),
                _LibraryGrid(type: MediaType.anime, query: _query),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updater = ref.watch(libraryUpdaterProvider);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      color: scheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  updater.currentTitle ?? 'Checking for updates…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              ),
              Text('${updater.done}/${updater.total}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: updater.progress,
              minHeight: 3,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<LibraryCategory> categories;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final all = [
      LibraryCategory.all,
      ...categories,
      LibraryCategory.uncategorized,
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final c = all[i];
          return ChoiceChip(
            label: Text(c.name),
            selected: selected == c.id,
            onSelected: (_) => onSelect(c.id),
          );
        },
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
    final newCounts = ref.watch(newCountsProvider).valueOrNull ?? const {};

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
            title: 'Nothing here',
            message: ref.watch(selectedCategoryProvider) ==
                    LibraryCategory.allId
                ? 'Install an extension from Browse → Extensions, then add '
                    'titles to your library.'
                : 'No titles in this category yet.',
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(libraryProvider(type));
            ref.invalidate(newCountsProvider);
          },
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            gridDelegate: coverGridDelegate(appearance.gridColumns),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final item = items[i];
              final unread = newCounts[item.id] ?? 0;
              return MediaGridTile(
                item: item,
                showTitle: appearance.showTitles,
                badge: unread > 0 ? '$unread' : null,
                headers:
                    ref.watch(sourceByIdProvider(item.sourceId))?.mediaHeaders,
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
