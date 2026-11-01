import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../image_url.dart';

/// Shares the in-memory cache with [SmartImage], so resolving it for a picture already on screen
/// costs nothing.
ImageProvider weiboImageProvider(String url, {int? cacheWidth}) => ResizeImage.resizeIfNeeded(
      cacheWidth,
      null,
      _provider(sanitizeImageUrl(url)),
    );

CachedNetworkImageProvider _provider(String url) {
  final identity = _identity(url);
  return CachedNetworkImageProvider(
    url,
    headers: weiboImageHeaders(url),
    cacheKey: identity == url ? null : identity,
  );
}

/// Whether [url] is already decoded in memory, i.e. would paint on the very first frame.
bool isImageInMemory(String url, {int? cacheWidth}) {
  if (url.isEmpty) return false;
  final provider = weiboImageProvider(url, cacheWidth: cacheWidth);
  return PaintingBinding.instance.imageCache.containsKey(provider);
}

/// Every Weibo picture goes through here: the right Referer (sinaimg rejects it otherwise), and a
/// load that never dims. Whatever is underneath (the smaller preview, or a flat placeholder)
/// stays fully opaque while the picture fades in over it, and is dropped once it is covered —
/// rather than both fading at once and letting the background show through for a moment.
class SmartImage extends StatefulWidget {
  const SmartImage({
    super.key,
    required this.url,
    this.placeholderUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.radius = 0,
    this.cacheWidth,
    this.placeholderColor,
  });

  final String? url;
  final String? placeholderUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final double radius;
  final int? cacheWidth;
  final Color? placeholderColor;

  @override
  State<SmartImage> createState() => _SmartImageState();
}

/// The picture an address shows. sinaimg signs avatars (`?KID=…&Expires=…&ssig=…`) anew in every
/// response; keyed by the full address, the same avatar would be fetched, decoded and faded in
/// again on every page and every refresh.
String _identity(String url) {
  final query = url.indexOf('?');
  if (query < 0) return url;
  final params = url.substring(query + 1);
  return params.contains('Expires=') || params.contains('ssig=') ? url.substring(0, query) : url;
}

class _SmartImageState extends State<SmartImage> {
  static const _fadeIn = Duration(milliseconds: 200);

  /// The picture is fully visible; nothing needs to be painted underneath any more.
  bool _covered = false;

  @override
  void didUpdateWidget(SmartImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_identity(sanitizeImageUrl(oldWidget.url)) != _identity(sanitizeImageUrl(widget.url))) _covered = false;
  }

  void _cover() {
    if (!mounted || _covered) return;
    setState(() => _covered = true);
  }

  Widget _flat(ColorScheme scheme, {bool icon = false}) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: widget.placeholderColor ?? scheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: icon
          ? Icon(Icons.image_outlined, size: 22, color: scheme.onSurfaceVariant.withValues(alpha: 0.45))
          : null,
    );
  }

  Widget _underlay(ColorScheme scheme, String clean, String preview) {
    final flat = _flat(scheme);
    if (preview.isEmpty || preview == clean) return flat;
    return Image(
      image: weiboImageProvider(preview),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) => frame == null ? flat : child,
      errorBuilder: (context, error, stack) => flat,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clean = sanitizeImageUrl(widget.url);
    final preview = sanitizeImageUrl(widget.placeholderUrl);
    final Widget image;
    if (clean.isEmpty) {
      image = preview.isEmpty ? _flat(scheme, icon: true) : _underlay(scheme, clean, preview);
    } else {
      final picture = Image(
        key: ValueKey(_identity(clean)),
        image: weiboImageProvider(clean, cacheWidth: widget.cacheWidth),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) {
          // A picture already shown keeps showing while the same one loads under a fresh address.
          if (_covered || (frame != null && sync)) {
            if (!_covered) WidgetsBinding.instance.addPostFrameCallback((_) => _cover());
            return child;
          }
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: _fadeIn,
            curve: Curves.easeOut,
            onEnd: _cover,
            child: child,
          );
        },
        errorBuilder: (context, error, stack) =>
            preview.isNotEmpty && preview != clean ? _underlay(scheme, clean, preview) : _flat(scheme, icon: true),
      );
      // Same Stack either way, so dropping the underlay does not rebuild the picture.
      image = Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.center,
        children: [
          if (!_covered) KeyedSubtree(key: const ValueKey('underlay'), child: _underlay(scheme, clean, preview)),
          picture,
        ],
      );
    }
    if (widget.radius <= 0) return image;
    return ClipRRect(borderRadius: BorderRadius.circular(widget.radius), child: image);
  }
}
