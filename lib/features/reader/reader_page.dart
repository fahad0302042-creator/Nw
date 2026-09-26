import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../core/providers.dart';
import '../../domain/models/media.dart';
import '../../domain/source/media_source.dart';
import '../common/widgets.dart';

enum ReadingMode { vertical, horizontalLtr, horizontalRtl }

/// The manga reader.
///
/// Supports webtoon-style continuous vertical scrolling and paged
/// horizontal modes (including right-to-left for Japanese manga), tap-to-
/// toggle chrome, pinch zoom, and automatic progress saving.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.item,
    required this.units,
    required this.startIndex,
  });

  final MediaItem item;
  final List<MediaUnit> units;
  final int startIndex;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  late int _unitIndex = widget.startIndex;
  late final PageController _pageCtl;
  final _scrollCtl = ScrollController();

  List<ReaderPage> _pages = const [];
  bool _loading = true;
  Object? _error;
  bool _chromeVisible = false;
  int _current = 0;
  ReadingMode _mode = ReadingMode.vertical;

  MediaUnit get _unit => widget.units[_unitIndex];
  MediaSource? get _source => ref.read(sourceByIdProvider(widget.item.sourceId));

  @override
  void initState() {
    super.initState();
    _pageCtl = PageController(initialPage: _unit.progress);
    _current = _unit.progress;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPages());
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  Future<void> _loadPages() async {
    setState(() {
      _loading = true;
      _error = null;
      _pages = const [];
    });
    try {
      final pages = await _source!.pages(_unit);
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _loading = false;
        _current = _unit.progress.clamp(0, pages.isEmpty ? 0 : pages.length - 1);
      });
      _preload();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  /// Warm the image cache a few pages ahead so scrolling stays smooth.
  void _preload() {
    final headers = _source?.mediaHeaders;
    for (var i = _current; i < _current + 3 && i < _pages.length; i++) {
      precacheImage(
        NetworkImage(_pages[i].imageUrl, headers: _pages[i].headers ?? headers),
        context,
      ).catchError((_) {});
    }
  }

  Future<void> _saveProgress(int page) async {
    final id = _unit.id;
    if (id == null) return;
    final finished = page >= _pages.length - 1;
    await ref
        .read(databaseProvider)
        .setProgress(id, progress: page, read: finished ? true : null);
  }

  void _onPageChanged(int page) {
    setState(() => _current = page);
    _saveProgress(page);
    _preload();
  }

  void _goToUnit(int index) {
    if (index < 0 || index >= widget.units.length) return;
    setState(() {
      _unitIndex = index;
      _current = 0;
    });
    if (_pageCtl.hasClients) _pageCtl.jumpToPage(0);
    if (_scrollCtl.hasClients) _scrollCtl.jumpTo(0);
    _loadPages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _content()),
          if (_chromeVisible) ..._chrome(),
        ],
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorView(error: _error!, onRetry: _loadPages);
    }
    if (_pages.isEmpty) {
      return const EmptyState(
        icon: Icons.image_not_supported_outlined,
        title: 'No pages returned',
        message: 'The source returned an empty page list for this chapter.',
      );
    }

    final headers = _source?.mediaHeaders;

    if (_mode == ReadingMode.vertical) {
      return GestureDetector(
        onTap: () => setState(() => _chromeVisible = !_chromeVisible),
        child: ListView.builder(
          controller: _scrollCtl,
          itemCount: _pages.length + 1,
          itemBuilder: (_, i) {
            if (i == _pages.length) return _endOfChapter();
            final p = _pages[i];
            return _VerticalPage(
              page: p,
              headers: p.headers ?? headers,
              onVisible: () {
                if (i != _current) _onPageChanged(i);
              },
            );
          },
        ),
      );
    }

    final rtl = _mode == ReadingMode.horizontalRtl;
    return PhotoViewGallery.builder(
      pageController: _pageCtl,
      reverse: rtl,
      itemCount: _pages.length,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      onPageChanged: _onPageChanged,
      loadingBuilder: (_, __) =>
          const Center(child: CircularProgressIndicator()),
      builder: (_, i) {
        final p = _pages[i];
        return PhotoViewGalleryPageOptions(
          imageProvider: NetworkImage(p.imageUrl, headers: p.headers ?? headers),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          onTapUp: (_, __, ___) =>
              setState(() => _chromeVisible = !_chromeVisible),
        );
      },
    );
  }

  Widget _endOfChapter() {
    final hasNext = _unitIndex > 0; // list is newest-first
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Text('End of chapter',
              style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 16),
          if (hasNext)
            FilledButton.icon(
              onPressed: () => _goToUnit(_unitIndex - 1),
              icon: const Icon(Icons.skip_next),
              label: Text(widget.units[_unitIndex - 1].name),
            )
          else
            const Text('You are all caught up.',
                style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }

  List<Widget> _chrome() {
    return [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          color: Colors.black87,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14)),
                    Text(_unit.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              PopupMenuButton<ReadingMode>(
                icon: const Icon(Icons.tune, color: Colors.white),
                initialValue: _mode,
                onSelected: (m) => setState(() => _mode = m),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: ReadingMode.vertical,
                      child: Text('Webtoon (vertical)')),
                  PopupMenuItem(
                      value: ReadingMode.horizontalLtr,
                      child: Text('Paged — left to right')),
                  PopupMenuItem(
                      value: ReadingMode.horizontalRtl,
                      child: Text('Paged — right to left')),
                ],
              ),
            ],
          ),
        ),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          color: Colors.black87,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 8,
            top: 8,
            left: 12,
            right: 12,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, color: Colors.white),
                onPressed: _unitIndex < widget.units.length - 1
                    ? () => _goToUnit(_unitIndex + 1)
                    : null,
              ),
              Expanded(
                child: Slider(
                  value: _pages.isEmpty
                      ? 0
                      : _current.clamp(0, _pages.length - 1).toDouble(),
                  max: _pages.isEmpty ? 1 : (_pages.length - 1).toDouble(),
                  divisions: _pages.length > 1 ? _pages.length - 1 : null,
                  label: '${_current + 1}',
                  onChanged: (v) {
                    final page = v.round();
                    setState(() => _current = page);
                    if (_mode != ReadingMode.vertical && _pageCtl.hasClients) {
                      _pageCtl.jumpToPage(page);
                    }
                  },
                ),
              ),
              Text('${_current + 1}/${_pages.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              IconButton(
                icon: const Icon(Icons.skip_next, color: Colors.white),
                onPressed:
                    _unitIndex > 0 ? () => _goToUnit(_unitIndex - 1) : null,
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

/// A single page in webtoon mode. Reports visibility so progress tracks
/// scrolling without a heavyweight visibility-detector dependency.
class _VerticalPage extends StatelessWidget {
  const _VerticalPage({
    required this.page,
    required this.headers,
    required this.onVisible,
  });

  final ReaderPage page;
  final Map<String, String>? headers;
  final VoidCallback onVisible;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (_) => false,
      child: Builder(builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null || !box.attached) return;
          final y = box.localToGlobal(Offset.zero).dy;
          final h = MediaQuery.of(context).size.height;
          if (y < h * 0.5 && y + box.size.height > h * 0.2) onVisible();
        });
        return Image.network(
          page.imageUrl,
          headers: headers,
          fit: BoxFit.fitWidth,
          width: double.infinity,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const SizedBox(
                  height: 420,
                  child: Center(child: CircularProgressIndicator()),
                ),
          errorBuilder: (_, __, ___) => SizedBox(
            height: 220,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined, color: Colors.white38),
                  const SizedBox(height: 8),
                  Text('Page ${page.index + 1} failed to load',
                      style: const TextStyle(color: Colors.white38)),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
