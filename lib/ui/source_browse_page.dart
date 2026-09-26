import 'package:flutter/material.dart';

import '../extensions/engine.dart';
import '../extensions/manifest.dart';
import '../models/media.dart';
import 'details_page.dart';
import 'widgets/media_grid.dart';

class SourceBrowsePage extends StatefulWidget {
  const SourceBrowsePage({super.key, required this.source});

  final SourceManifest source;

  @override
  State<SourceBrowsePage> createState() => _SourceBrowsePageState();
}

class _SourceBrowsePageState extends State<SourceBrowsePage> {
  late final SourceEngine _engine = SourceEngine(widget.source);
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();

  final List<MediaItem> _items = <MediaItem>[];
  String _endpoint = 'popular';
  String _query = '';
  int _page = 1;
  bool _loading = false;
  bool _hasNext = true;
  String? _error;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _endpoint = widget.source.supports('popular')
        ? 'popular'
        : widget.source.supports('latest')
            ? 'latest'
            : 'search';
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 1;
      _hasNext = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext) return;
    setState(() => _loading = true);
    try {
      final endpoint = _query.isNotEmpty ? 'search' : _endpoint;
      final result = await _engine.list(endpoint, page: _page, query: _query);
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _hasNext = result.hasNext && result.items.isNotEmpty;
        _page += 1;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _hasNext = false;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchEndpoint(String endpoint) {
    if (_endpoint == endpoint && _query.isEmpty) return;
    setState(() {
      _endpoint = endpoint;
      _query = '';
      _search.clear();
      _searching = false;
    });
    _reload();
  }

  void _submitSearch(String value) {
    setState(() => _query = value.trim());
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final tabs = <String>[
      if (source.supports('popular')) 'popular',
      if (source.supports('latest')) 'latest',
    ];

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search…',
                  border: InputBorder.none,
                ),
                onSubmitted: _submitSearch,
              )
            : Text(source.name),
        actions: <Widget>[
          if (source.supports('search'))
            IconButton(
              icon: Icon(_searching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() => _searching = !_searching);
                if (!_searching && _query.isNotEmpty) {
                  _query = '';
                  _search.clear();
                  _reload();
                }
              },
            ),
        ],
        bottom: tabs.length > 1 && _query.isEmpty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 12),
                    for (final tab in tabs)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 8),
                        child: ChoiceChip(
                          label: Text(tab == 'popular' ? 'Popular' : 'Latest'),
                          selected: _endpoint == tab,
                          onSelected: (_) => _switchEndpoint(tab),
                        ),
                      ),
                  ],
                ),
              )
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _error != null) {
      return StatusView(
        icon: Icons.cloud_off,
        title: 'Could not load this source',
        message: _error,
        action: FilledButton.tonal(
          onPressed: _reload,
          child: const Text('Retry'),
        ),
      );
    }
    if (_items.isEmpty) {
      return const StatusView(
        icon: Icons.search_off,
        title: 'Nothing found',
        message: 'Try a different search term.',
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          childAspectRatio: 0.52,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _items.length + (_loading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final item = _items[index];
          return MediaCard(
            item: item,
            headers: widget.source.headers,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DetailsPage(source: widget.source, item: item),
              ),
            ),
          );
        },
      ),
    );
  }
}
