import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/source/source_engine.dart';
import '../../core/storage/app_storage.dart';
import '../../models/catalog_item.dart';
import '../../models/chapter_entry.dart';
import '../../models/extension_manifest.dart';
import '../../models/page_entry.dart';
import '../widgets/state_views.dart';

/// A continuous vertical "webtoon style" reader. Chapters are listed newest
/// first (as returned by the source), so "next chapter" means the previous
/// index and vice versa - handled via [_chapters] order lookup rather than
/// assuming any particular sort.
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.source,
    required this.manga,
    required this.chapters,
    required this.initialChapter,
  });

  final ExtensionManifest source;
  final CatalogItem manga;
  final List<ChapterEntry> chapters;
  final ChapterEntry initialChapter;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _engine = const SourceEngine();
  late ChapterEntry _chapter;
  List<PageEntry> _pages = [];
  bool _loading = true;
  Object? _error;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _chapter = widget.initialChapter;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _pages = [];
    });
    try {
      final pages = await _engine.fetchPages(
        widget.source,
        widget.source.pages!,
        _chapter.url,
      );
      setState(() => _pages = pages);
      if (mounted) {
        await context.read<AppStorage>().markChapterRead(
              widget.source.id,
              widget.manga.url,
              _chapter.url,
            );
      }
    } catch (e) {
      setState(() => _error = e);
    } finally {
      setState(() => _loading = false);
    }
  }

  int get _currentIndex => widget.chapters.indexWhere((c) => c.url == _chapter.url);

  ChapterEntry? get _nextChapter {
    final i = _currentIndex;
    if (i < 0 || i == 0) return null;
    return widget.chapters[i - 1]; // list is newest-first; "next" = lower index
  }

  ChapterEntry? get _previousChapter {
    final i = _currentIndex;
    if (i < 0 || i >= widget.chapters.length - 1) return null;
    return widget.chapters[i + 1];
  }

  void _goTo(ChapterEntry chapter) {
    setState(() => _chapter = chapter);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _chromeVisible
          ? AppBar(
              title: Text(_chapter.title.isEmpty ? widget.manga.title : _chapter.title),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorStateView(error: _error!, onRetry: _load)
                : _pages.isEmpty
                    ? const EmptyState(
                        icon: Icons.image_not_supported_outlined,
                        title: 'No pages found',
                        message: 'This extension returned an empty page list.',
                      )
                    : GestureDetector(
                        onTap: () => setState(() => _chromeVisible = !_chromeVisible),
                        child: ListView.builder(
                          itemCount: _pages.length + 1,
                          itemBuilder: (context, index) {
                            if (index == _pages.length) {
                              return _ChapterNavFooter(
                                previous: _previousChapter,
                                next: _nextChapter,
                                onSelect: _goTo,
                              );
                            }
                            final page = _pages[index];
                            return InteractiveViewer(
                              maxScale: 4,
                              child: CachedNetworkImage(
                                imageUrl: page.url,
                                httpHeaders: page.headers,
                                fit: BoxFit.fitWidth,
                                width: double.infinity,
                                placeholder: (context, _) => const AspectRatio(
                                  aspectRatio: 0.7,
                                  child: Center(child: CircularProgressIndicator()),
                                ),
                                errorWidget: (context, _, __) => const AspectRatio(
                                  aspectRatio: 0.7,
                                  child: Center(
                                    child: Icon(Icons.broken_image_outlined, color: Colors.white54),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}

class _ChapterNavFooter extends StatelessWidget {
  const _ChapterNavFooter({
    required this.previous,
    required this.next,
    required this.onSelect,
  });

  final ChapterEntry? previous;
  final ChapterEntry? next;
  final ValueChanged<ChapterEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          const Text('End of chapter', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                onPressed: previous != null ? () => onSelect(previous!) : null,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Previous'),
              ),
              OutlinedButton.icon(
                onPressed: next != null ? () => onSelect(next!) : null,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
