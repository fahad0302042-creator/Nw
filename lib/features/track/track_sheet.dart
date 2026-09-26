import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/track/tracker.dart';
import '../../domain/models/media.dart';
import '../../domain/models/track.dart';
import '../common/widgets.dart';

/// Search a tracking service and link the result to a library item.
class TrackSearchSheet extends ConsumerStatefulWidget {
  const TrackSearchSheet({
    super.key,
    required this.tracker,
    required this.item,
    required this.itemId,
  });

  final Tracker tracker;
  final MediaItem item;
  final int itemId;

  @override
  ConsumerState<TrackSearchSheet> createState() => _TrackSearchSheetState();
}

class _TrackSearchSheetState extends ConsumerState<TrackSearchSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.item.title);
  List<TrackSearchResult> _results = const [];
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results =
          await widget.tracker.search(_controller.text.trim(), widget.item.type);
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _link(TrackSearchResult r) async {
    final service = ref.read(trackingServiceProvider);
    try {
      // Prefer the user's existing remote entry so we never overwrite
      // progress they already have on the service.
      final remote =
          await widget.tracker.fetch(r.remoteId, widget.item.type);
      final link = remote ??
          TrackLink(
            tracker: widget.tracker.id,
            remoteId: r.remoteId,
            title: r.title,
            totalUnits: r.totalUnits,
            remoteUrl: r.remoteUrl,
            coverUrl: r.coverUrl,
          );
      await service.link(widget.itemId, link);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Text('Link on ${widget.tracker.name}',
                  style: Theme.of(context).textTheme.titleMedium),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search title',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: _search,
                    ),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const Hairline(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? ErrorView(error: _error!, onRetry: _search)
                        : _results.isEmpty
                            ? const EmptyState(
                                icon: Icons.search_off, title: 'No matches')
                            : ListView.separated(
                                itemCount: _results.length,
                                separatorBuilder: (_, __) =>
                                    const Hairline(indent: 16),
                                itemBuilder: (_, i) {
                                  final r = _results[i];
                                  return ListTile(
                                    leading: SizedBox(
                                      width: 40,
                                      height: 56,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: CoverImage(url: r.coverUrl),
                                      ),
                                    ),
                                    title: Text(r.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                      r.totalUnits > 0
                                          ? '${r.totalUnits} ${widget.item.type.unitLabelPlural.toLowerCase()}'
                                          : 'Ongoing / unknown length',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    onTap: () => _link(r),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tracking strip shown on a title's detail page.
class TrackSection extends ConsumerWidget {
  const TrackSection({
    super.key,
    required this.item,
    required this.itemId,
    required this.links,
    required this.onChanged,
  });

  final MediaItem item;
  final int itemId;
  final List<TrackLink> links;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(trackingServiceProvider);
    if (!service.anyLoggedIn) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('TRACKING', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final tracker in service.loggedIn)
          Builder(builder: (context) {
            final link = links.where((l) => l.tracker == tracker.id).firstOrNull;

            if (link == null) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.add_link, color: scheme.outline),
                title: Text('Link on ${tracker.name}'),
                onTap: () async {
                  final done = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => TrackSearchSheet(
                      tracker: tracker,
                      item: item,
                      itemId: itemId,
                    ),
                  );
                  if (done == true) await onChanged();
                },
              );
            }

            return ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(Icons.check_circle, color: scheme.primary),
              title: Text(link.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${tracker.name} · ${link.status.label} · '
                '${link.lastProgress}${link.totalUnits > 0 ? '/${link.totalUnits}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.link_off, size: 20),
                tooltip: 'Unlink',
                onPressed: () async {
                  await service.unlink(link);
                  await onChanged();
                },
              ),
            );
          }),
      ],
    );
  }
}
