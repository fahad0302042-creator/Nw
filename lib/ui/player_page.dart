import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../app.dart';
import '../core/net.dart';
import '../extensions/engine.dart';
import '../extensions/manifest.dart';
import '../models/media.dart';
import 'widgets/media_grid.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.source,
    required this.item,
    required this.episodes,
    required this.index,
  });

  final SourceManifest source;
  final MediaItem item;
  final List<ChapterItem> episodes;
  final int index;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final SourceEngine _engine = SourceEngine(widget.source);
  late int _index = widget.index;

  VideoPlayerController? _controller;
  List<VideoSource> _sources = <VideoSource>[];
  int _selected = 0;
  bool _loading = true;
  bool _controlsVisible = true;
  String? _error;

  ChapterItem get _episode => widget.episodes[_index];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    _load();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sources = await _engine.videos(_episode.url);
      if (!mounted) return;
      if (sources.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No playable stream was found for this episode.';
        });
        return;
      }
      setState(() {
        _sources = sources;
        _selected = 0;
      });
      await _play(sources.first);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _play(VideoSource source) async {
    final old = _controller;
    old?.removeListener(_onTick);

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(source.url),
      httpHeaders: Net.buildHeaders(source.headers),
    );
    try {
      await controller.initialize();
      controller.addListener(_onTick);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
        _error = null;
      });
      await old?.dispose();
    } catch (error) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Playback failed: $error';
      });
    }
  }

  void _goToEpisode(int next) {
    if (next < 0 || next >= widget.episodes.length) return;
    setState(() => _index = next);
    AppScope.read(context).saveProgress(
      sourceId: widget.source.id,
      mediaUrl: widget.item.url,
      chapterUrl: widget.episodes[next].url,
      position: 0,
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _controlsVisible = !_controlsVisible),
                child: Center(child: _buildVideo(controller)),
              ),
            ),
            if (_controlsVisible) _buildControls(controller),
          ],
        ),
      ),
    );
  }

  Widget _buildVideo(VideoPlayerController? controller) {
    if (_loading) return const CircularProgressIndicator();
    if (_error != null) {
      return StatusView(
        icon: Icons.videocam_off_outlined,
        title: 'Cannot play this episode',
        message: _error,
        action: FilledButton.tonal(
          onPressed: _load,
          child: const Text('Retry'),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const CircularProgressIndicator();
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
  }

  Widget _buildControls(VideoPlayerController? controller) {
    final ready = controller != null && controller.value.isInitialized;
    return Column(
      children: <Widget>[
        Container(
          color: Colors.black54,
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  _episode.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              if (_sources.length > 1)
                PopupMenuButton<int>(
                  icon: const Icon(Icons.high_quality_outlined, color: Colors.white),
                  initialValue: _selected,
                  onSelected: (value) {
                    setState(() {
                      _selected = value;
                      _loading = true;
                    });
                    _play(_sources[value]);
                  },
                  itemBuilder: (context) => <PopupMenuEntry<int>>[
                    for (var i = 0; i < _sources.length; i++)
                      PopupMenuItem<int>(
                        value: i,
                        child: Text(_sources[i].quality),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const Spacer(),
        if (ready)
          Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                Row(
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.skip_previous, color: Colors.white),
                      onPressed: _index - 1 >= 0
                          ? () => _goToEpisode(_index - 1)
                          : null,
                    ),
                    IconButton(
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        controller.value.isPlaying
                            ? controller.pause()
                            : controller.play();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white),
                      onPressed: _index + 1 < widget.episodes.length
                          ? () => _goToEpisode(_index + 1)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_format(controller.value.position)} / '
                      '${_format(controller.value.duration)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
