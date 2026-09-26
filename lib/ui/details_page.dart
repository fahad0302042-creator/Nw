import 'package:flutter/material.dart';

import '../app.dart';
import '../extensions/engine.dart';
import '../extensions/manifest.dart';
import '../models/media.dart';
import 'player_page.dart';
import 'reader_page.dart';
import 'widgets/media_grid.dart';

class DetailsPage extends StatefulWidget {
  const DetailsPage({super.key, required this.source, required this.item});

  final SourceManifest source;
  final MediaItem item;

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  late final SourceEngine _engine = SourceEngine(widget.source);

  MediaDetails _details = MediaDetails.empty;
  List<ChapterItem> _chapters = <ChapterItem>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = await _engine.details(widget.item.url);
      List<ChapterItem> chapters = <ChapterItem>[];
      if (widget.source.supports('chapters')) {
        chapters = await _engine.chapters(widget.item.url);
      }
      if (!mounted) return;
      setState(() {
        _details = details;
        _chapters = chapters;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _open(int index) {
    final state = AppScope.read(context);
    // Remember where the user left off.
    state.saveProgress(
      sourceId: widget.source.id,
      mediaUrl: widget.item.url,
      chapterUrl: _chapters[index].url,
      position: state.progressFor(widget.source.id, _chapters[index].url),
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => widget.source.isAnime
            ? PlayerPage(
                source: widget.source,
                item: widget.item,
                episodes: _chapters,
                index: index,
              )
            : ReaderPage(
                source: widget.source,
                item: widget.item,
                chapters: _chapters,
                index: index,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final inLibrary = state.inLibrary(widget.item);
    final thumbnail = _details.thumbnail ?? widget.item.thumbnail;
    final isAnime = widget.source.isAnime;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              expandedHeight: 260,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CoverImage(url: thumbnail, headers: widget.source.headers),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.black54,
                            Colors.transparent,
                            Color(0xFF0E0E13),
                          ],
                          stops: <double>[0, 0.45, 1],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _details.title ?? widget.item.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      <String?>[
                        _details.author,
                        _details.status,
                        widget.source.name,
                      ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white60),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: _chapters.isEmpty ? null : () => _open(0),
                          icon: Icon(isAnime ? Icons.play_arrow : Icons.menu_book),
                          label: Text(isAnime ? 'Watch' : 'Read'),
                        ),
                        const SizedBox(width: 12),
                        IconButton.filledTonal(
                          onPressed: () => state.toggleLibrary(widget.item),
                          icon: Icon(
                            inLibrary ? Icons.favorite : Icons.favorite_border,
                          ),
                        ),
                      ],
                    ),
                    if ((_details.description ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      _Description(text: _details.description!),
                    ],
                    if (_details.genres.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: -6,
                        children: _details.genres
                            .take(20)
                            .map((genre) => Chip(
                                  label: Text(genre),
                                  visualDensity: VisualDensity.compact,
                                ))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      isAnime
                          ? '${_chapters.length} episodes'
                          : '${_chapters.length} chapters',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: StatusView(
                  icon: Icons.cloud_off,
                  title: 'Failed to load',
                  message: _error,
                  action: FilledButton.tonal(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: _chapters.length,
                itemBuilder: (context, index) {
                  final chapter = _chapters[index];
                  final read = state.isRead(widget.source.id, chapter.url);
                  return ListTile(
                    dense: true,
                    title: Text(
                      chapter.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: read ? Colors.white38 : null,
                      ),
                    ),
                    subtitle: chapter.date == null ? null : Text(chapter.date!),
                    trailing: read
                        ? const Icon(Icons.check, size: 16, color: Colors.white38)
                        : null,
                    onTap: () => _open(index),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _Description extends StatefulWidget {
  const _Description({required this.text});

  final String text;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Text(
        widget.text,
        maxLines: _expanded ? null : 4,
        overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: Colors.white70, height: 1.35),
      ),
    );
  }
}
