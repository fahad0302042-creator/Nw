import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/source/source_engine.dart';
import '../../core/storage/app_storage.dart';
import '../../models/catalog_item.dart';
import '../../models/chapter_entry.dart';
import '../../models/extension_manifest.dart';
import '../../models/library_entry.dart';
import '../../models/manga_detail.dart';
import '../player/video_player_page.dart';
import '../reader/reader_page.dart';
import '../widgets/cover_image.dart';
import '../widgets/state_views.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.source, required this.item});

  final ExtensionManifest source;
  final CatalogItem item;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final _engine = const SourceEngine();
  MangaDetail? _detail;
  bool _loading = true;
  Object? _error;

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
      final detail = await _engine.fetchDetail(widget.source, widget.item);
      setState(() => _detail = detail);
    } catch (e) {
      setState(() => _error = e);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<AppStorage>();
    final inLibrary = storage.isInLibrary(widget.source.id, widget.item.url);
    final isAnime = widget.source.isAnime;

    return Scaffold(
      appBar: AppBar(title: Text(widget.item.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (inLibrary) {
            await storage.removeFromLibrary(widget.source.id, widget.item.url);
          } else {
            await storage.addToLibrary(
              LibraryEntry(
                item: _detail?.item ?? widget.item,
                type: widget.source.type,
                addedAt: DateTime.now().millisecondsSinceEpoch,
              ),
            );
          }
        },
        icon: Icon(inLibrary ? Icons.bookmark : Icons.bookmark_border),
        label: Text(inLibrary ? 'In library' : 'Add to library'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorStateView(error: _error!, onRetry: _load)
              : _buildContent(context, isAnime),
    );
  }

  Widget _buildContent(BuildContext context, bool isAnime) {
    final detail = _detail!;
    final storage = context.watch<AppStorage>();
    final readUrls = storage.readChapterUrls(widget.source.id, widget.item.url);

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CoverImage(
                    url: detail.item.cover,
                    headers: widget.source.headers,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(detail.item.title, style: Theme.of(context).textTheme.titleLarge),
                    if (detail.author != null) ...[
                      const SizedBox(height: 4),
                      Text(detail.author!, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                    if (detail.status != null) ...[
                      const SizedBox(height: 4),
                      Chip(
                        label: Text(detail.status!),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (detail.genres.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 6,
              runSpacing: -8,
              children: detail.genres
                  .map((g) => Chip(label: Text(g), visualDensity: VisualDensity.compact))
                  .toList(),
            ),
          ),
        if (detail.description != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(detail.description!),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            isAnime ? '${detail.chapters.length} episodes' : '${detail.chapters.length} chapters',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (detail.chapters.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No chapters/episodes found for this title.'),
          ),
        ...detail.chapters.map((chapter) => _ChapterTile(
              chapter: chapter,
              read: readUrls.contains(chapter.url),
              isAnime: isAnime,
              onTap: () => _openChapter(chapter, isAnime),
            )),
      ],
    );
  }

  Future<void> _openChapter(ChapterEntry chapter, bool isAnime) async {
    await context.read<AppStorage>().markChapterRead(
          widget.source.id,
          widget.item.url,
          chapter.url,
        );
    if (!mounted) return;
    if (isAnime) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerPage(source: widget.source, episode: chapter),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReaderPage(
            source: widget.source,
            manga: widget.item,
            chapters: _detail!.chapters,
            initialChapter: chapter,
          ),
        ),
      );
    }
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.chapter,
    required this.read,
    required this.isAnime,
    required this.onTap,
  });

  final ChapterEntry chapter;
  final bool read;
  final bool isAnime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dimColor = read ? Theme.of(context).colorScheme.outline : null;
    return ListTile(
      leading: Icon(isAnime ? Icons.play_circle_outline : Icons.menu_book_outlined),
      title: Text(chapter.title.isEmpty ? chapter.url : chapter.title, style: TextStyle(color: dimColor)),
      subtitle: chapter.dateUpload != null ? Text(chapter.dateUpload!, style: TextStyle(color: dimColor)) : null,
      trailing: chapter.scanlator != null ? Text(chapter.scanlator!, style: TextStyle(color: dimColor)) : null,
      onTap: onTap,
    );
  }
}
