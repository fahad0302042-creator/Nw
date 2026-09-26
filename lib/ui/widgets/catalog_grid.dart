import 'package:flutter/material.dart';

import '../../models/catalog_item.dart';
import 'cover_image.dart';

/// A responsive grid of manga/anime covers, used by the browse and library
/// screens.
class CatalogGrid extends StatelessWidget {
  const CatalogGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.headers,
    this.controller,
    this.footer,
  });

  final List<CatalogItem> items;
  final ValueChanged<CatalogItem> onTap;
  final Map<String, String>? headers;
  final ScrollController? controller;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: controller,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.62,
      ),
      itemCount: items.length + (footer != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return footer;
        }
        final item = items[index];
        return _CatalogTile(
          item: item,
          headers: headers,
          onTap: () => onTap(item),
        );
      },
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({required this.item, required this.onTap, this.headers});

  final CatalogItem item;
  final VoidCallback onTap;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CoverImage(url: item.cover, headers: headers),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
