import 'package:flutter/material.dart';

/// Network thumbnail with a neutral placeholder for loading, a missing URL,
/// or a failed fetch (Instagram CDN thumbnail links can expire until the
/// owner re-syncs).
class GalleryThumbnail extends StatelessWidget {
  const GalleryThumbnail({super.key, required this.url, this.fit = BoxFit.cover, this.iconColor});

  final String? url;
  final BoxFit fit;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.content_cut, color: iconColor ?? Theme.of(context).colorScheme.outline)),
    );
    if (url == null) return placeholder;
    return Image.network(
      url!,
      fit: fit,
      loadingBuilder: (context, child, progress) => progress == null ? child : placeholder,
      errorBuilder: (context, error, stack) => placeholder,
    );
  }
}
