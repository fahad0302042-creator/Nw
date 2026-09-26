import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/models/media.dart';
import '../../domain/source/media_source.dart';
import '../common/widgets.dart';
import '../player/player_page.dart';
import '../reader/reader_page.dart';

/// Title details plus the chapter (manga) or episode (anime) list.
///
/// Strategy: show cached data from the database immediately, then refresh
/// from the source in the background so the screen is never blank.
class DetailsPage extends ConsumerStatefulWidget {
  const DetailsPage({super.key, required this.item});
  final MediaItem item;

  @override
  ConsumerState<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends ConsumerState<DetailsPage> {
  late MediaItem _item = widget.item;
  List<MediaUnit> _units = const [];
  bool _loading = true;
  Object? _error;
  bool _descExpanded = false;

  MediaSource? get _source => ref.read(sourceByIdProvider(_item.sourceId));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool forceRemote = false}) async {
    final db = ref.read(databaseProvider);
    setState(() {
      _loading = true;
      _error = null;
    });

    // 1. Cache first.
    final cached = await db.findItem(_item.sourceId, _item.url);
    if (cached != null && mounted) {
      final id = cached.id;
      setState(() => _item = cached);
      if (id != null) {
        final cachedUnits = await db.units(id);
        if (cachedUnits.isNotEmpty && mounted) {
          setState(() => _units = cachedUnits);
        }
      }
    }

    // 2. Then the network.
    final source = _source;
    if (source == null) {
      setState(() {
        _loading = false;
        _error = 'The extension for this source is not installed.';
      });
      return;
    }

    try {
      final detailed =
          _item.initialized && !forceRemote ? _item : await source.details(_item);
      final fresh = await source.units(detailed);

      final id = await db.upsertItem(detailed);
      await db.syncUnits(id, fresh);
      final merged = await db.units(id);

      if (!mounted) return;
      setState(() {
        _item = detailed.copyWith(id: id, inLibrary: _item.inLibrary);
        _units = merged.isEmpty ? fresh : merged;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleLibrary() async {
    final db = ref.read(databaseProvider);
    final id = _item.id ?? await db.upsertItem(_item);
    final next = !_item.inLibrary;
    await db.setInLibrary(id, next);
    if (!mounted) return;
    setState(() => _item = _item.copyWith(id: id, inLibrary: next));
    ref.invalidate(libraryProvider(_item.type));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next ? 'Added to library' : 'Removed from library'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _open(MediaUnit unit) {
    final source = _source;
    if (source == null) return;
    final index = _units.indexOf(unit);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _item.type == MediaType.manga
            ? ReaderScreen(item: _item, units: _units, startIndex: index)
            : PlayerScreen(item: _item, units: _units, startIndex: index),
      ),
    ).then((_) async {
      // Read state may have changed while reading/watching.
      final id = _item.id;
      if (id != null) {
        final refreshed = await ref.read(databaseProvider).units(id);
        if (mounted) setState(() => _units = refreshed);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final headers = _source?.mediaHeaders;
    final unreadNext = _units.where((u) => !u.read).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _load(forceRemote: true),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 280,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    CoverImage(url: _item.thumbnailUrl, headers: headers),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x99000000),
                            Color(0x33000000),
                            Color(0xFF0E0E12),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: _header(headers)),
            if (_loading && _units.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            if (_error != null && _units.isEmpty)
              SliverToBoxAdapter(
                child: ErrorView(error: _error!, onRetry: _load),
              ),
            SliverList.builder(
              itemCount: _units.length,
              itemBuilder: (_, i) => _unitTile(_units[i]),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
      floatingActionButton: unreadNext.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _open(unreadNext.last),
              icon: Icon(_item.type == MediaType.manga
                  ? Icons.menu_book
                  : Icons.play_arrow),
              label: Text(
                _units.any((u) => u.read)
                    ? 'Resume'
                    : (_item.type == MediaType.manga ? 'Read' : 'Watch'),
              ),
            ),
    );
  }

  Widget _header(Map<String, String>? headers) {
    final scheme = Theme.of(context).colorScheme;
    final desc = _item.description ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_item.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            [
              if (_item.author != null && _item.author!.isNotEmpty) _item.author,
              _item.status.name,
              _source?.name,
            ].whereType<String>().join(' · '),
            style: TextStyle(color: scheme.outline, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _toggleLibrary,
                icon: Icon(_item.inLibrary
                    ? Icons.favorite
                    : Icons.favorite_border),
                label: Text(_item.inLibrary ? 'In library' : 'Add'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Mark all read',
                icon: const Icon(Icons.done_all),
                onPressed: _item.id == null
                    ? null
                    : () async {
                        await ref
                            .read(databaseProvider)
                            .markAllRead(_item.id!, true);
                        final u =
                            await ref.read(databaseProvider).units(_item.id!);
                        if (mounted) setState(() => _units = u);
                      },
              ),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _descExpanded = !_descExpanded),
              child: Text(
                desc,
                maxLines: _descExpanded ? null : 4,
                overflow: _descExpanded ? null : TextOverflow.ellipsis,
                style: const TextStyle(height: 1.4, fontSize: 14),
              ),
            ),
          ],
          if (_item.genres.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final g in _item.genres)
                  Chip(
                    label: Text(g, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '${_units.length} ${_item.type.unitLabelPlural.toLowerCase()}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _unitTile(MediaUnit u) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [
      if (u.dateUpload != null)
        '${u.dateUpload!.day}/${u.dateUpload!.month}/${u.dateUpload!.year}',
      if (u.scanlator != null && u.scanlator!.isNotEmpty) u.scanlator,
      if (!u.read && u.progress > 0)
        _item.type == MediaType.manga
            ? 'Page ${u.progress + 1}'
            : 'Resume at ${Duration(milliseconds: u.progress).inMinutes}m',
    ].whereType<String>().join(' · ');

    return ListTile(
      dense: true,
      title: Text(
        u.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: u.read ? scheme.outline : scheme.onSurface,
          fontWeight: u.read ? FontWeight.normal : FontWeight.w500,
        ),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, style: TextStyle(color: scheme.outline, fontSize: 11)),
      trailing: IconButton(
        icon: Icon(
          u.read ? Icons.check_circle : Icons.circle_outlined,
          size: 20,
          color: u.read ? scheme.primary : scheme.outline,
        ),
        onPressed: u.id == null
            ? null
            : () async {
                await ref
                    .read(databaseProvider)
                    .setProgress(u.id!, read: !u.read);
                final refreshed =
                    await ref.read(databaseProvider).units(_item.id!);
                if (mounted) setState(() => _units = refreshed);
              },
      ),
      onTap: () => _open(u),
    );
  }
}
