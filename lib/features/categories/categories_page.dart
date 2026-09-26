import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../common/widgets.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoriesProvider);
    final db = ref.watch(databaseProvider);

    Future<void> refresh() async {
      ref.invalidate(categoriesProvider);
      ref.invalidate(libraryProvider);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final name = await _prompt(context, 'New category');
          if (name == null || name.isEmpty) return;
          await db.createCategory(name);
          await refresh();
        },
        child: const Icon(Icons.add),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: refresh),
        data: (categories) {
          if (categories.isEmpty) {
            return const EmptyState(
              icon: Icons.label_outline,
              title: 'No categories',
              message:
                  'Create categories to group your library — Reading, On hold, '
                  'Favourites, whatever suits you.',
            );
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: categories.length,
            onReorder: (oldIndex, newIndex) async {
              final list = [...categories];
              if (newIndex > oldIndex) newIndex--;
              final moved = list.removeAt(oldIndex);
              list.insert(newIndex, moved);
              await db.reorderCategories([for (final c in list) c.id]);
              await refresh();
            },
            itemBuilder: (context, i) {
              final c = categories[i];
              return Column(
                key: ValueKey(c.id),
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.drag_handle),
                    title: Text(c.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () async {
                            final name = await _prompt(context, 'Rename',
                                initial: c.name);
                            if (name == null || name.isEmpty) return;
                            await db.renameCategory(c.id, name);
                            await refresh();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            await db.deleteCategory(c.id);
                            await refresh();
                          },
                        ),
                      ],
                    ),
                  ),
                  const Hairline(indent: 16),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static Future<String?> _prompt(BuildContext context, String title,
      {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Category name'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for assigning one title to categories.
class CategoryPickerSheet extends ConsumerStatefulWidget {
  const CategoryPickerSheet({super.key, required this.itemId});
  final int itemId;

  @override
  ConsumerState<CategoryPickerSheet> createState() =>
      _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends ConsumerState<CategoryPickerSheet> {
  Set<int> _selected = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = await ref.read(databaseProvider).categoriesForItem(widget.itemId);
    if (!mounted) return;
    setState(() {
      _selected = ids.toSet();
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(categoriesProvider);

    return SafeArea(
      child: async.when(
        loading: () => const SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => SizedBox(height: 160, child: ErrorView(error: e)),
        data: (categories) {
          if (categories.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: EmptyState(
                icon: Icons.label_outline,
                title: 'No categories yet',
                message: 'Create some in More → Categories.',
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text('Categories',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in categories)
                      CheckboxListTile(
                        dense: true,
                        title: Text(c.name),
                        value: _selected.contains(c.id),
                        onChanged: !_loaded
                            ? null
                            : (v) => setState(() => v == true
                                ? _selected.add(c.id)
                                : _selected.remove(c.id)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await ref
                          .read(databaseProvider)
                          .setItemCategories(widget.itemId, _selected.toList());
                      ref.invalidate(libraryProvider);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
