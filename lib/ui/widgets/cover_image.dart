import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A cover/thumbnail image with a graceful placeholder + error state, used
/// throughout the browse/library grids.
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
    final placeholderColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    if (url == null || url!.isEmpty) {
      return Container(
        color: placeholderColor,
        alignment: Alignment.center,
        child: const Icon(Icons.menu_book_outlined, size: 32),
      );
    }
    return CachedNetworkImage(
      imageUrl: url!,
      httpHeaders: headers,
      fit: fit,
      placeholder: (context, _) => Container(color: placeholderColor),
      errorWidget: (context, _, __) => Container(
        color: placeholderColor,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, size: 32),
      ),
    );
  }
}
