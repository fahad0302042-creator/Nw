import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/models/media.dart';
import '../../domain/source/media_source.dart';
import '../common/widgets.dart';
import '../details/details_page.dart';

enum _Mode { popular, latest, search }

/// Paginated browsing of a single source, with infinite scroll.
class SourcePage extends ConsumerStatefulWidget {
  const SourcePage({super.key, required this.sourceId});
  final String sourceId;

  @override
  ConsumerState<SourcePage> createState() => _SourcePageState();
}

class _SourcePageState extends ConsumerState<SourcePage> {
  final _scroll = ScrollController();
  final _searchCtl = TextEditingController();

  final List<MediaItem> _items = [];
  _Mode _mode = _Mode.popular;
  String _query = '';
  int _page = 1;
  bool _loading = false;
  bool _hasNext = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >=
          _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reset());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  MediaSource? get _source => ref.read(sourceByIdProvider(widget.sourceId));

  void _reset() {
    setState(() {
      _items.clear();
      _page = 1;
      _hasNext = true;
      _error = null;
    });
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext) return;
    final source = _source;
    if (source == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final page = switch (_mode) {
        _Mode.popular => await source.popular(_page),
        _Mode.latest => await source.latest(_page),
        _Mode.search => await source.search(_query, _page, const []),
      };
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasNext = page.hasNextPage && page.items.isNotEmpty;
        _page++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchMode(_Mode mode, {String query = ''}) {
    setState(() {
      _mode = mode;
      _query = query;
    });
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(sourceByIdProvider(widget.sourceId));
    if (source == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.extension_off_outlined,
          title: 'Source unavailable',
          message: 'The extension providing this source was removed.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(source.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchCtl,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search ${source.name}…',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchCtl.clear();
                              _switchMode(_Mode.popular);
                            },
                          ),
                  ),
                  onSubmitted: (v) => v.trim().isEmpty
                      ? _switchMode(_Mode.popular)
                      : _switchMode(_Mode.search, query: v.trim()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Popular'),
                      selected: _mode == _Mode.popular,
                      onSelected: (_) => _switchMode(_Mode.popular),
                    ),
                    const SizedBox(width: 8),
                    if (source.supportsLatest)
                      ChoiceChip(
                        label: const Text('Latest'),
                        selected: _mode == _Mode.latest,
                        onSelected: (_) => _switchMode(_Mode.latest),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _body(source),
    );
  }

  Widget _body(MediaSource source) {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _error != null) {
      return ErrorView(error: _error!, onRetry: _reset);
    }
    if (_items.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'No results',
      );
    }

    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      gridDelegate: kCoverGridDelegate,
      // One extra cell carries the loading / error footer.
      itemCount: _items.length + 1,
      itemBuilder: (_, i) {
        if (i == _items.length) {
          if (_loading) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (_error != null) {
            return Center(
              child: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadMore,
              ),
            );
          }
          return const SizedBox.shrink();
        }

        final item = _items[i];
        return MediaGridTile(
          item: item,
          headers: source.mediaHeaders,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DetailsPage(item: item)),
          ),
        );
      },
    );
  }
}
