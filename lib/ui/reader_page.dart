import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../core/net.dart';
import '../extensions/engine.dart';
import '../extensions/manifest.dart';
import '../models/media.dart';
import 'widgets/media_grid.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.source,
    required this.item,
    required this.chapters,
    required this.index,
  });

  final SourceManifest source;
  final MediaItem item;
  final List<ChapterItem> chapters;
  final int index;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final SourceEngine _engine = SourceEngine(widget.source);
  late int _index = widget.index;

  final ScrollController _scroll = ScrollController();
  PageController? _pageController;

  List<String> _pages = <String>[];
  bool _loading = true;
  bool _chromeVisible = true;
  String? _error;
  int _current = 0;
  bool _webtoon = true;
  bool _rtl = false;

  ChapterItem get _chapter => widget.chapters[_index];

  @override
  void initState() {
    super.initState();
    final state = AppScope.read(context);
    _webtoon = state.webtoonMode;
    _rtl = state.rightToLeft;
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _pageController?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _pages = <String>[];
      _current = 0;
    });
    try {
      final pages = await _engine.pages(_chapter.url);
      if (!mounted) return;
      if (pages.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'This chapter returned no images.';
        });
        return;
      }
      final state = AppScope.read(context);
      final saved = state.progressFor(widget.source.id, _chapter.url);
      final start = saved > 0 && saved < pages.length ? saved : 0;
      setState(() {
        _pages = pages;
        _loading = false;
        _current = start;
      });
      _pageController?.dispose();
      _pageController = PageController(initialPage: start);
      _saveProgress(start);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _saveProgress(int page) {
    AppScope.read(context).saveProgress(
      sourceId: widget.source.id,
      mediaUrl: widget.item.url,
      chapterUrl: _chapter.url,
      position: page,
    );
  }

  void _goToChapter(int next) {
    if (next < 0 || next >= widget.chapters.length) return;
    setState(() => _index = next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _buildContent()),
          if (_chromeVisible) _buildTopBar(),
          if (_chromeVisible && _pages.isNotEmpty) _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return StatusView(
        icon: Icons.broken_image_outlined,
        title: 'Could not open chapter',
        message: _error,
        action: FilledButton.tonal(
          onPressed: _load,
          child: const Text('Retry'),
        ),
      );
    }

    if (_webtoon) {
      return GestureDetector(
        onTap: () => setState(() => _chromeVisible = !_chromeVisible),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollEndNotification && _pages.isNotEmpty) {
              final position = notification.metrics;
              if (position.maxScrollExtent > 0) {
                final ratio = position.pixels / position.maxScrollExtent;
                final page = (ratio * (_pages.length - 1)).round();
                if (page != _current) {
                  _current = page;
                  _saveProgress(page);
                }
              }
            }
            return false;
          },
          child: ListView.builder(
            controller: _scroll,
            itemCount: _pages.length,
            itemBuilder: (context, index) => _ReaderImage(
              url: _pages[index],
              headers: widget.source.headers,
              index: index,
            ),
          ),
        ),
      );
    }

    return PageView.builder(
      controller: _pageController,
      reverse: _rtl,
      itemCount: _pages.length,
      onPageChanged: (page) {
        _current = page;
        _saveProgress(page);
      },
      itemBuilder: (context, index) => GestureDetector(
        onTap: () => setState(() => _chromeVisible = !_chromeVisible),
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: _ReaderImage(
              url: _pages[index],
              headers: widget.source.headers,
              index: index,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black87,
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  Text(
                    _chapter.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: _webtoon ? 'Webtoon (continuous)' : 'Paged',
              icon: Icon(
                _webtoon ? Icons.view_day_outlined : Icons.auto_stories_outlined,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() => _webtoon = !_webtoon);
                AppScope.read(context).setSetting('webtoon', _webtoon);
              },
            ),
            if (!_webtoon)
              IconButton(
                tooltip: _rtl ? 'Right to left' : 'Left to right',
                icon: Icon(
                  _rtl ? Icons.swap_horiz : Icons.arrow_forward,
                  color: Colors.white,
                ),
                onPressed: () {
                  setState(() => _rtl = !_rtl);
                  AppScope.read(context).setSetting('rtl', _rtl);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black87,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 6,
          top: 6,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            TextButton.icon(
              onPressed: _index + 1 < widget.chapters.length
                  ? () => _goToChapter(_index + 1)
                  : null,
              icon: const Icon(Icons.skip_previous),
              label: const Text('Prev'),
            ),
            Text(
              '${_current + 1} / ${_pages.length}',
              style: const TextStyle(color: Colors.white70),
            ),
            TextButton.icon(
              onPressed: _index - 1 >= 0 ? () => _goToChapter(_index - 1) : null,
              icon: const Icon(Icons.skip_next),
              label: const Text('Next'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderImage extends StatelessWidget {
  const _ReaderImage({
    required this.url,
    required this.headers,
    required this.index,
    this.fit = BoxFit.fitWidth,
  });

  final String url;
  final Map<String, String> headers;
  final int index;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: Net.buildHeaders(headers),
      fit: fit,
      width: double.infinity,
      placeholder: (context, _) => Container(
        height: 420,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 10),
            Text(
              'Page ${index + 1}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
      errorWidget: (context, _, __) => Container(
        height: 240,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.broken_image_outlined, color: Colors.white24),
            const SizedBox(height: 8),
            Text(
              'Page ${index + 1} failed to load',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
