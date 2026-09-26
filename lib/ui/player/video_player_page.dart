import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/source/source_engine.dart';
import '../../models/chapter_entry.dart';
import '../../models/extension_manifest.dart';
import '../../models/page_entry.dart';
import '../widgets/state_views.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.source, required this.episode});

  final ExtensionManifest source;
  final ChapterEntry episode;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  final _engine = const SourceEngine();
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  List<PageEntry> _links = [];
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
      final links = await _engine.fetchPages(
        widget.source,
        widget.source.pages!,
        widget.episode.url,
      );
      if (links.isEmpty) {
        throw Exception('No playable video links were returned by this extension.');
      }
      setState(() => _links = links);
      await _play(links.first);
    } catch (e) {
      setState(() => _error = e);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _play(PageEntry link) async {
    _chewieController?.dispose();
    await _videoController?.dispose();
    final videoController = VideoPlayerController.networkUrl(
      Uri.parse(link.url),
      httpHeaders: link.headers ?? const {},
    );
    await videoController.initialize();
    final chewieController = ChewieController(
      videoPlayerController: videoController,
      autoPlay: true,
      looping: false,
    );
    if (!mounted) return;
    setState(() {
      _videoController = videoController;
      _chewieController = chewieController;
    });
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.episode.title),
        actions: [
          if (_links.length > 1)
            PopupMenuButton<PageEntry>(
              icon: const Icon(Icons.tune),
              onSelected: _play,
              itemBuilder: (context) => _links
                  .map((l) => PopupMenuItem(value: l, child: Text(l.label ?? l.url)))
                  .toList(),
            ),
        ],
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
                ? ErrorStateView(error: _error!, onRetry: _load)
                : _chewieController != null
                    ? AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio == 0
                            ? 16 / 9
                            : _videoController!.value.aspectRatio,
                        child: Chewie(controller: _chewieController!),
                      )
                    : const Text('Unable to load video', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
