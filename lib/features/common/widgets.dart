import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/models/media.dart';

/// Cover art with source-specific headers (Referer is often mandatory).
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.url,
    this.headers,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final Map<String, String>? headers;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const _CoverPlaceholder();
    return CachedNetworkImage(
      imageUrl: url!,
      httpHeaders: headers,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => const _CoverPlaceholder(),
      errorWidget: (_, __, ___) => const _CoverPlaceholder(broken: true),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({this.broken = false});
  final bool broken;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        broken ? Icons.broken_image_outlined : Icons.image_outlined,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

/// The standard cover grid tile used by library, browse and search.
class MediaGridTile extends StatelessWidget {
  const MediaGridTile({
    super.key,
    required this.item,
    required this.onTap,
    this.headers,
    this.badge,
    this.showTitle = true,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final Map<String, String>? headers;
  final String? badge;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CoverImage(url: item.thumbnailUrl, headers: headers),
            if (showTitle) ...[
              // Scrim so white covers don't swallow the title.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xD9000000)],
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 7,
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
            if (badge != null)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Grid geometry for cover art. [columns] of 0 means "adapt to the screen",
/// which is what most phones want; a fixed count is available in settings.
SliverGridDelegate coverGridDelegate(int columns) {
  const ratio = 0.68; // standard manga/anime cover aspect
  const spacing = 8.0;
  if (columns > 0) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      childAspectRatio: ratio,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
    );
  }
  return const SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 140,
    childAspectRatio: ratio,
    crossAxisSpacing: spacing,
    mainAxisSpacing: spacing,
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
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
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: scheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.outline),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      message: '$error',
      action: onRetry == null
          ? null
          : FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
    );
  }
}
