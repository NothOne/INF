import 'package:flutter/material.dart';

import 'smart_image.dart';

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    this.url,
    this.size = 40,
    this.verified = false,
    this.heroTag,
  });

  final String? url;
  final double size;
  final bool verified;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget avatar = ClipOval(
      child: SmartImage(
        url: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholderColor: scheme.surfaceContainerHigh,
        // One decode for every small size, so the same avatar is already in memory on the next page.
        cacheWidth: size <= 64 ? 192 : (size * 3).round(),
      ),
    );
    if (heroTag != null) {
      avatar = Hero(tag: heroTag!, child: Material(color: Colors.transparent, child: avatar));
    }
    if (!verified) return SizedBox(width: size, height: size, child: avatar);
    final badge = size * 0.38;
    return SizedBox(
      width: size + badge * 0.12,
      height: size + badge * 0.12,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -badge * 0.08,
            bottom: -badge * 0.08,
            child: Container(
              width: badge + 2,
              height: badge + 2,
              decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(
                Icons.verified_rounded,
                size: badge,
                color: scheme.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
