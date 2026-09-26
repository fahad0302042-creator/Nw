import 'package:flutter/material.dart';

import '../../core/source/source_engine.dart';
import '../../models/catalog_item.dart';
import '../../models/extension_manifest.dart';
import '../../models/list_endpoint.dart';
import '../detail/detail_page.dart';
import '../widgets/catalog_grid.dart';
import '../widgets/state_views.dart';

class SourceBrowsePage extends StatefulWidget {
  const SourceBrowsePage({super.key, required this.source});

  final ExtensionManifest source;

  @override
  State<SourceBrowsePage> createState() => _SourceBrowsePageState();
}

class _SourceBrowsePageState extends State<SourceBrowsePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final List<_TabSpec> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      if (widget.source.popular != null)
        _TabSpec('Popular', widget.source.popular!),
      if (widget.source.latest != null) _TabSpec('Latest', widget.source.latest!),
      if (widget.source.search != null) _TabSpec('Search', widget.source.search!),
    ];
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.source.name)),
        body: const EmptyState(
          icon: Icons.error_outline,
          title: 'This extension has no browse endpoints configured',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source.name),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs
            .map(
              (t) => t.label == 'Search'
                  ? _SearchTab(source: widget.source, endpoint: t.endpoint)
                  : _ListTab(source: widget.source, endpoint: t.endpoint),
            )
            .toList(),
      ),
    );
  }
}

class _TabSpec {
  final String label;
  final ListEndpoint endpoint;
  _TabSpec(this.label, this.endpoint);
}

class _ListTab extends StatefulWidget {
  const _ListTab({required this.source, required this.endpoint});

  final ExtensionManifest source;
  final ListEndpoint endpoint;

  @override
  State<_ListTab> createState() => _ListTabState();
}

class _ListTabState extends State<_ListTab>
    with AutomaticKeepAliveClientMixin {
  final _engine = const SourceEngine();
  final List<CatalogItem> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _loadedOnce = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = more ? _page + 1 : 1;
      final results = await _engine.fetchList(widget.source, widget.endpoint, page: page);
      setState(() {
        if (more) {
          _items.addAll(results);
        } else {
          _items
            ..clear()
            ..addAll(results);
        }
        _page = page;
        _loadedOnce = true;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null && _items.isEmpty) {
      return ErrorStateView(error: _error!, onRetry: () => _load());
    }
    if (_loadedOnce && _items.isEmpty) {
      return const EmptyState(icon: Icons.inbox_outlined, title: 'Nothing found');
    }
    if (!_loadedOnce) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: CatalogGrid(
        items: _items,
        headers: widget.source.headers,
        onTap: (item) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetailPage(source: widget.source, item: item),
          ),
        ),
        footer: widget.endpoint.paginated
            ? Center(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      )
                    : TextButton(
                        onPressed: () => _load(more: true),
                        child: const Text('Load more'),
                      ),
              )
            : null,
      ),
    );
  }
}

class _SearchTab extends StatefulWidget {
  const _SearchTab({required this.source, required this.endpoint});

  final ExtensionManifest source;
  final ListEndpoint endpoint;

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab>
    with AutomaticKeepAliveClientMixin {
  final _engine = const SourceEngine();
  final _controller = TextEditingController();
  List<CatalogItem> _items = [];
  bool _loading = false;
  bool _searched = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final results = await _engine.fetchList(widget.source, widget.endpoint, query: query);
      setState(() => _items = results);
    } catch (e) {
      setState(() => _error = e);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Search ${widget.source.name}',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _search,
              ),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorStateView(error: _error!, onRetry: _search)
                  : !_searched
                      ? const EmptyState(
                          icon: Icons.search,
                          title: 'Search for a title',
                        )
                      : _items.isEmpty
                          ? const EmptyState(
                              icon: Icons.inbox_outlined,
                              title: 'No results',
                            )
                          : CatalogGrid(
                              items: _items,
                              headers: widget.source.headers,
                              onTap: (item) => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      DetailPage(source: widget.source, item: item),
                                ),
                              ),
                            ),
        ),
      ],
    );
  }
}
