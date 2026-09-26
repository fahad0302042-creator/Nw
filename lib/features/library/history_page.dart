import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../common/widgets.dart';
import '../details/details_page.dart';

/// Recently opened titles, newest first.
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(historyProvider)),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.history,
              title: 'Nothing here yet',
              message: 'Titles you read or watch will show up here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(historyProvider),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final item = items[i];
                return ListTile(
                  leading: SizedBox(
                    width: 44,
                    height: 62,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CoverImage(
                        url: item.thumbnailUrl,
                        headers: ref
                            .watch(sourceByIdProvider(item.sourceId))
                            ?.mediaHeaders,
                      ),
                    ),
                  ),
                  title: Text(item.title, maxLines: 2),
                  subtitle: Text(item.type.label),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DetailsPage(item: item)),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
