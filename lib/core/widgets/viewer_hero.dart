import 'package:flutter/material.dart';

import '../models.dart';

/// The Hero tag of each picture the viewer shows, in the viewer's order (pictures only, videos
/// dropped). A tag ending in `-N` names the N-th of [media], so the others follow from it; a link
/// tag stands for that one picture alone.
List<String?> viewerHeroTags(String? tag, List<Media> media, int index) {
  final match = tag == null || tag.startsWith('link-img-') ? null : RegExp(r'^(.*)-(\d+)$').firstMatch(tag);
  return [
    for (var i = 0; i < media.length; i++)
      if (media[i].kind == MediaKind.image)
        match != null ? '${match.group(1)}-$i' : (i == index ? tag : null),
  ];
}

/// A picture the full-screen viewer grows out of and flies back to.
///
/// A Hero hides its source until the route that took it off is gone, so after a swipe in the
/// viewer the picture it opened from would stay blank behind the drag while another one flies
/// home. Instead the source stays drawn as its own placeholder, and only the picture the viewer
/// is on right now ([showing]) is hidden.
class ViewerHero extends StatelessWidget {
  const ViewerHero({super.key, required this.tag, required this.child, this.transitionOnUserGestures = false});

  /// The tag of the picture open in the viewer; null while none is.
  static final ValueNotifier<String?> showing = ValueNotifier<String?>(null);

  final String tag;
  final Widget child;
  final bool transitionOnUserGestures;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      transitionOnUserGestures: transitionOnUserGestures,
      placeholderBuilder: (context, size, child) => SizedBox.fromSize(size: size, child: child),
      child: ValueListenableBuilder<String?>(
        valueListenable: showing,
        builder: (context, open, child) => Opacity(opacity: open == tag ? 0 : 1, child: child),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}
