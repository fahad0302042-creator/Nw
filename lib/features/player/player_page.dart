import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/providers.dart';
import '../../data/download/download_storage.dart';
import '../../domain/models/media.dart';
import '../../domain/source/media_source.dart';
import '../common/widgets.dart';

/// The anime player.
///
/// media_kit is used rather than video_player because sources overwhelmingly
/// serve HLS (.m3u8) behind Referer-protected CDNs, which needs custom
/// headers and robust adaptive-streaming support.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.item,
    required this.units,
    required this.startIndex,
  });

  final MediaItem item;
  final List<MediaUnit> units;
  final int startIndex;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  late int _unitIndex = widget.startIndex;
  List<VideoStream> _streams = const [];
  int _streamIndex = 0;
  bool _loading = true;
  Object? _error;
  Timer? _progressTimer;

  MediaUnit get _unit => widget.units[_unitIndex];
  MediaSource? get _source => ref.read(sourceByIdProvider(widget.item.sourceId));

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Persist position periodically rather than on every tick.
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final id = _unit.id;
      if (id == null) return;
      final pos = _player.state.position.inMilliseconds;
      final dur = _player.state.duration.inMilliseconds;
      if (pos <= 0) return;
      // 90% watched counts as finished — matches Aniyomi's behaviour.
      final finished = dur > 0 && pos / dur > 0.9;
      ref
          .read(databaseProvider)
          .setProgress(id, progress: pos, read: finished ? true : null);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStreams());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _player.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadStreams() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // A downloaded episode plays with no network and no source lookup.
      final storage = await DownloadStorage.instance();
      final local = storage.localVideo(
          widget.item.sourceId, widget.item.title, _unit.name);
      if (local != null) {
        if (!mounted) return;
        setState(() {
          _streams = [VideoStream(url: local.path, quality: 'Downloaded')];
          _streamIndex = 0;
          _loading = false;
        });
        await _play(_streams.first,
            startAt: Duration(milliseconds: _unit.progress));
        return;
      }

      final streams = await _source!.videos(_unit);
      if (streams.isEmpty) throw StateError('No playable streams found');
      if (!mounted) return;
      setState(() {
        _streams = streams;
        _streamIndex = 0;
        _loading = false;
      });
      await _play(streams.first, startAt: Duration(milliseconds: _unit.progress));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _play(VideoStream s, {Duration startAt = Duration.zero}) async {
    await _player.open(
      Media(
        s.url,
        httpHeaders: {
          ...?_source?.mediaHeaders,
          ...?s.headers,
        },
        start: startAt,
      ),
    );
  }

  Future<void> _switchQuality(int index) async {
    final pos = _player.state.position;
    setState(() => _streamIndex = index);
    await _play(_streams[index], startAt: pos);
  }

  void _goToUnit(int index) {
    if (index < 0 || index >= widget.units.length) return;
    setState(() => _unitIndex = index);
    _loadStreams();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorView(error: _error!, onRetry: _loadStreams)
                : Stack(
                    children: [
                      Positioned.fill(
                        child: Video(
                          controller: _controller,
                          controls: AdaptiveVideoControls,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Text(
                                _unit.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            if (_streams.length > 1)
                              PopupMenuButton<int>(
                                icon: const Icon(Icons.high_quality_outlined,
                                    color: Colors.white),
                                initialValue: _streamIndex,
                                onSelected: _switchQuality,
                                itemBuilder: (_) => [
                                  for (var i = 0; i < _streams.length; i++)
                                    PopupMenuItem(
                                      value: i,
                                      child: Text(_streams[i].quality),
                                    ),
                                ],
                              ),
                            IconButton(
                              icon: const Icon(Icons.skip_next,
                                  color: Colors.white),
                              tooltip: 'Next episode',
                              onPressed: _unitIndex > 0
                                  ? () => _goToUnit(_unitIndex - 1)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
