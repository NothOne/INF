import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

/// Where a post's menu sits and how it travels, shared by all three styles so the gesture is the
/// same whichever material the menu is made of.
///
/// The menu is not anchored beside the card: it opens **at the middle of the screen**, from the
/// rectangle that was held, and goes back into it on the way out. A card sits anywhere in a long
/// list, so a menu pinned to it would hang off an edge or need to pick a side; the middle is the
/// same place every time, and the growth from the card is what shows where it came from.
@immutable
class StatusMenuGeometry {
  const StatusMenuGeometry._({
    required this.origin,
    required this.target,
  });

  /// A menu that opens at the middle of the screen, growing out of [origin].
  ///
  /// For a card held in a list: the card sits anywhere, so a menu pinned to it would hang off an
  /// edge or have to pick a side, while the middle is the same place every time and the growth
  /// from the card is what shows where it came from.
  factory StatusMenuGeometry.centred({
    required Rect origin,
    required Size screen,
    required EdgeInsets safe,
    required Size menu,
  }) {
    final width = math.min(menu.width, screen.width - 32);
    final left = (screen.width - width) / 2;
    final top = math.max(
      safe.top + 12,
      (screen.height - menu.height) / 2,
    );
    return StatusMenuGeometry._(
      origin: origin,
      target: Rect.fromLTWH(left, top, width, menu.height),
    );
  }

  /// A menu that opens beside [origin], against the screen edge that origin sits on.
  ///
  /// For a bar's `⋯`: the button is already where the finger is, and a menu in the middle of the
  /// screen would be a second place to look. It hangs under the button, its far edge lined up with
  /// the button's, and flips above or to the other side when there is no room.
  factory StatusMenuGeometry.anchored({
    required Rect origin,
    required Size screen,
    required EdgeInsets safe,
    required Size menu,
    double gap = 6,
  }) {
    final width = math.min(menu.width, screen.width - 32);
    final height = math.min(menu.height, screen.height - safe.top - safe.bottom - 24);

    // Right-aligned to a button near the right edge, left-aligned near the left one.
    final wantsEnd = origin.center.dx > screen.width / 2;
    var left = wantsEnd ? origin.right - width : origin.left;
    left = left.clamp(8.0, screen.width - width - 8);

    // Below the button, unless that runs off the bottom; then above it.
    final below = origin.bottom + gap;
    final fitsBelow = below + height <= screen.height - safe.bottom - 8;
    var top = fitsBelow ? below : origin.top - gap - height;
    top = top.clamp(safe.top + 8, screen.height - height - safe.bottom - 8);

    return StatusMenuGeometry._(
      origin: origin,
      target: Rect.fromLTWH(left, top, width, height),
    );
  }

  /// The held widget, in global coordinates: the menu grows out of and returns into this.
  final Rect origin;

  /// Where the menu rests.
  final Rect target;

  /// The menu's rectangle at [t], 0 at the held widget and 1 at rest.
  ///
  /// Interpolated as a rectangle so the growth reads as the card opening into the menu rather than
  /// a panel fading in over it. The corner radius travels with it: the menu is a rounded card, the
  /// widget it comes from may be a card of any shape.
  Rect rectAt(double t) => Rect.lerp(origin, target, _ease(t))!;

  double radiusAt(double t, {required double from, required double to}) =>
      lerpDouble(from, to, _ease(t))!;

  /// Rises to the target with a curve that starts slowly, so the card is seen to open before the
  /// menu arrives — the same reasoning as the container transform that opens a page.
  static double _ease(double t) => Curves.easeInOutCubicEmphasized.transform(t.clamp(0.0, 1.0));

  /// How far through its travel the menu is when it is drawn at [t], for a style that also fades
  /// or blurs: zero where the menu is invisible, one where it rests.
  ///
  /// It reaches full early. Glass draws through a layer of its own, and a partially transparent
  /// `Opacity` above it — which is what a slow fade puts there — reads an empty backdrop, so the
  /// panel comes out as a dark block for as long as the fade lasts. The growth from the widget held
  /// is what shows the menu arriving; the fade only has to keep the first couple of frames from
  /// popping.
  static double presence(double t) {
    final fade = (t / 0.18).clamp(0.0, 1.0);
    return fade * fade * (3 - 2 * fade);
  }
}
