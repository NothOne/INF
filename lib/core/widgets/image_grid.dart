import 'package:flutter/material.dart';

import '../../core/image_prefetch.dart';
import '../../core/image_url.dart';
import '../../core/models.dart';
import 'smart_image.dart';

/// What a grid cell shows. A lone picture is drawn several times larger than a grid cell, so it
/// asks sinaimg for the 690px rendition instead of the 360px thumbnail — except for GIFs (other
/// sizes may be stills) and very long pictures (decoding them taller costs far more memory).
String thumbnailUrl(Media media, {required bool single}) {
  if (media.kind != MediaKind.image) return media.previewUrl.isEmpty ? media.url : media.previewUrl;
  if (!single || media.isLong) return media.previewUrl;
  final path = Uri.tryParse(media.url)?.path.toLowerCase() ?? '';
  if (path.endsWith('.gif')) return media.previewUrl;
  final sized = sinaimgSized(media.previewUrl, 'mw690');
  return sized == sanitizeImageUrl(media.previewUrl) ? media.previewUrl : sized;
}

/// The post's pictures. One picture is drawn at its own aspect ratio (bounded), two and four use two
/// columns, everything else three. Each cell carries a Hero tag so the viewer can grow out of it.
class StatusImageGrid extends StatelessWidget {
  const StatusImageGrid({
    super.key,
    required this.media,
    required this.statusId,
    required this.onOpen,
    this.enabled = true,
    this.heroEnabled = true,
  });

  final List<Media> media;
  final String statusId;
  final void Function(List<Media> media, int index, String? heroTag) onOpen;
  final bool enabled;
  final bool heroEnabled;

  String _tag(int index) => 'img-$statusId-$index';

  @override
  Widget build(BuildContext context) {
    final items = media.take(9).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    // A grid is built a little before it scrolls into view; that is the cue to fetch the full
    // pictures in the background.
    if (enabled) {
      ImagePrefetcher.instance.request([
        for (final item in items)
          if (item.kind == MediaKind.image) item.url,
      ]);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (items.length == 1) {
          final single = items.first;
          final ratio = single.kind == MediaKind.image && single.width > 0 && single.height > 0
              ? single.width / single.height
              : 1.4;
          final bounded = ratio.clamp(0.6, 1.78);
          final longest = constraints.maxWidth * 0.72;
          final width = ratio >= 1 ? longest : longest * bounded;
          final height = ratio >= 1 ? longest / bounded : longest;
          return Align(
            alignment: Alignment.centerLeft,
            child: _Cell(
              media: single,
              single: true,
              width: width,
              height: height,
              heroTag: (enabled && heroEnabled) ? _tag(0) : null,
              onTap: enabled ? () => onOpen(items, 0, _tag(0)) : null,
            ),
          );
        }
        final columns = items.length == 2 || items.length == 4 ? 2 : 3;
        const gap = 5.0;
        final cell = (constraints.maxWidth - gap * (columns - 1)) / columns;
        final rows = <Widget>[];
        for (var start = 0; start < items.length; start += columns) {
          final rowItems = items.sublist(start, start + columns > items.length ? items.length : start + columns);
          rows.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var offset = 0; offset < rowItems.length; offset++) ...[
                if (offset > 0) const SizedBox(width: gap),
                _Cell(
                  media: rowItems[offset],
                  width: cell,
                  height: cell,
                  heroTag: (enabled && heroEnabled) ? _tag(start + offset) : null,
                  onTap: enabled ? () => onOpen(items, start + offset, _tag(start + offset)) : null,
                ),
              ],
            ],
          ));
          if (start + columns < items.length) rows.add(const SizedBox(height: gap));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.media,
    required this.width,
    required this.height,
    required this.heroTag,
    required this.onTap,
    this.single = false,
  });

  final Media media;
  final bool single;
  final double width;
  final double height;
  final String? heroTag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = SmartImage(
      url: thumbnailUrl(media, single: single),
      placeholderUrl: single && media.kind == MediaKind.image ? media.previewUrl : null,
      width: width,
      height: height,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      placeholderColor: scheme.surfaceContainerHigh,
    );
    Widget cell = ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          image,
          if (media.kind == MediaKind.image && media.isLong)
            const Positioned(right: 5, bottom: 5, child: _Badge(text: '长图')),
          if (media.kind == MediaKind.video) ...[
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                ),
              ),
            ),
            if (media.durationMs > 0)
              Positioned(right: 5, bottom: 5, child: _Badge(text: _duration(media.durationMs))),
          ],
        ],
      ),
    );
    if (onTap != null) {
      cell = GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Starts decoding the full picture ~100ms before the tap is even recognised.
        onTapDown: media.kind == MediaKind.image
            ? (_) => precacheImage(weiboImageProvider(media.url), context, onError: (_, _) {})
            : null,
        onTap: onTap,
        child: cell,
      );
    }
    if (heroTag != null) {
      cell = Hero(
        tag: heroTag!,
        transitionOnUserGestures: true,
        child: Material(color: Colors.transparent, child: cell),
      );
    }
    return cell;
  }

  String _duration(int ms) {
    final seconds = ms ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, height: 1.2)),
    );
  }
}