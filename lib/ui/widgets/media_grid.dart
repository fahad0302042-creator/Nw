import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/net.dart';
import '../../models/media.dart';

/// Cover artwork with graceful fallbacks (sources often block hotlinking).
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.url,
    this.headers = const <String, String>{},
    this.fit = BoxFit.cover,
  });

  final String? url;
  final Map<String, String> headers;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final target = url;
    if (target == null || target.isEmpty) return const _CoverFallback();
    return CachedNetworkImage(
      imageUrl: target,
      httpHeaders: Net.buildHeaders(headers),
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (context, _) => const _CoverFallback(loading: true),
      errorWidget: (context, _, __) => const _CoverFallback(),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white10,
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.image_not_supported_outlined, color: Colors.white24),
    );
  }
}

class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.onTap,
    this.headers = const <String, String>{},
  });

  final MediaItem item;
  final VoidCallback onTap;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: CoverImage(url: item.thumbnail, headers: headers),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.2),
          ),
        ],
      ),
    );
  }
}

/// Shared empty / error / loading placeholder.
class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white54),
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
