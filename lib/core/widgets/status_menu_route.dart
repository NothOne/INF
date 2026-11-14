import 'package:flutter/material.dart';

import '../chrome.dart';
import '../haptics.dart';
import '../models.dart';
import 'status_actions.dart';
import 'status_menu_geometry.dart';

/// Where a menu rests once it has opened.
enum StatusMenuPlacement {
  /// The middle of the screen. For a card held in a list.
  centred,

  /// Beside the widget it came from. For a page bar's `⋯`.
  anchored,
}

/// Opens a menu of [actions] out of [anchor]'s rectangle. The styles draw the panel; the travel, the
/// rows and the dismissal are the same everywhere.
///
/// Resolves to the `returns` of the row that was picked, for a menu that asks a question; null when
/// it was dismissed without one.
Future<Object?> showGlassActions(
  BuildContext context, {
  required List<StatusAction> actions,
  required BuildContext anchor,
  double originRadius = 16,
  StatusMenuPlacement placement = StatusMenuPlacement.centred,
}) {
  final box = anchor.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return Future.value();
  final origin = box.localToGlobal(Offset.zero) & box.size;
  final chrome = InfChrome.of(context);
  return Navigator.of(anchor).push<Object?>(
    StatusMenuRoute<Object?>(
      origin: origin,
      actions: actions,
      surface: chrome.statusMenuSurface,
      radius: chrome.statusMenuRadius,
      originRadius: originRadius,
      placement: placement,
    ),
  );
}

/// [showGlassActions] for a post, whose rows are [statusActions].
Future<void> showStatusMenu(
  BuildContext context,
  Status status, {
  required BuildContext anchor,
  VoidCallback? onLongImage,
  double originRadius = 16,
  StatusMenuPlacement placement = StatusMenuPlacement.centred,
}) {
  return showGlassActions(
    context,
    actions: statusActions(context, status, onLongImage: onLongImage),
    anchor: anchor,
    originRadius: originRadius,
    placement: placement,
  );
}

/// How a style draws the menu's surface for a given size and shape. The route owns the travel and
/// the dismissal; the style owns what the panel is made of, so each of the three looks like itself
/// while all of them open, hold and close the same way.
typedef StatusMenuSurface = Widget Function(
  BuildContext context,
  Widget child,
  BorderRadius radius,
);

/// A post's menu: it opens out of the widget that was held, waits for a tap, and goes back into it.
///
/// Two placements, one behaviour:
///
///  * [StatusMenuPlacement.centred] — for a card held in a list. The menu opens in the middle of
///    the screen; the card can be anywhere, so that is the one place it always fits.
///  * [StatusMenuPlacement.anchored] — for a bar's `⋯`. The menu hangs under the button, against
///    the same edge, so it is read where the finger already is.
///
/// No row runs on the way out. A finger that lifts after a long press only ends the press — the
/// menu stays, and choosing is a separate tap, which is what a menu of eight rows needs: sliding to
/// a row and letting go picked the wrong one too often, on a list this long, with the card moving
/// under the finger as it lifts.
class StatusMenuRoute<T> extends PopupRoute<T> {
  StatusMenuRoute({
    required this.origin,
    required this.actions,
    required this.surface,
    required this.radius,
    this.originRadius = 16,
    this.placement = StatusMenuPlacement.centred,
    this.onDismissed,
  });

  /// The widget that was held, in global coordinates: the menu grows from here and returns to it.
  final Rect origin;

  final List<StatusAction> actions;

  /// The style's own material for the panel.
  final StatusMenuSurface surface;

  /// The corner radius the menu itself is drawn with.
  final double radius;

  /// The corner radius of [origin], so the growth starts from the held widget's own shape.
  final double originRadius;

  /// Where the menu rests: the middle of the screen, or beside [origin].
  final StatusMenuPlacement placement;

  final ValueChanged<bool>? onDismissed;

  /// Wide enough for a long label beside its icon, and never wider than the screen allows.
  static const menuWidth = 268.0;

  /// One row's height, used to size the panel before it is laid out.
  static const rowHeight = 46.0;

  /// The divider's height, where a group starts.
  static const groupGap = 9.0;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.12);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => '关闭菜单';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  /// The height the panel is expected to take, used only to place it near the middle of the screen.
  /// The panel then takes its own height; this never constrains it.
  double get _estimatedHeight {
    // The rows' own height, the group gaps, and the padding above and below them.
    var height = 16.0;
    for (final action in actions) {
      height += rowHeight + (action.detail == null ? 0 : 16) + (action.startsGroup ? groupGap : 0);
    }
    return height;
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final media = MediaQuery.of(context);
    final menu = Size(menuWidth, _estimatedHeight);
    final geometry = switch (placement) {
      StatusMenuPlacement.centred => StatusMenuGeometry.centred(
          origin: origin,
          screen: media.size,
          safe: media.padding,
          menu: menu,
        ),
      StatusMenuPlacement.anchored => StatusMenuGeometry.anchored(
          origin: origin,
          screen: media.size,
          safe: media.padding,
          menu: menu,
        ),
    };
    return _StatusMenuPage(
      route: this,
      animation: animation,
      geometry: geometry,
    );
  }

  @override
  bool didPop(T? result) {
    onDismissed?.call(true);
    return super.didPop(result);
  }
}

class _StatusMenuPage extends StatelessWidget {
  const _StatusMenuPage({
    required this.route,
    required this.animation,
    required this.geometry,
  });

  final StatusMenuRoute<dynamic> route;
  final Animation<double> animation;
  final StatusMenuGeometry geometry;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        final rect = geometry.rectAt(t);
        final radius = geometry.radiusAt(t, from: route.originRadius, to: route.radius);
        return Stack(
          children: [
            // The panel is laid out at the width the travel reaches and its own height; only the
            // top-left corner follows the travel, so the rows are never squeezed into a height
            // guessed for them.
            //
            // No `Opacity` above this. A glass surface draws through a compositing layer of its
            // own, and an `OpacityLayer` above it samples an empty backdrop: the panel comes out as
            // a black block, most of it below the middle, for as long as the fade lasts. The growth
            // from the widget held already carries the arrival, and the surface itself is opaque
            // from its first frame, so nothing needs fading.
            Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              child: route.surface(
                context,
                _rows(context),
                BorderRadius.circular(radius),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _rows(BuildContext context) {
    final children = <Widget>[];
    for (final action in route.actions) {
      if (action.startsGroup) children.add(const SizedBox(height: StatusMenuRoute.groupGap));
      children.add(
        _ActionRow(
          action: action,
          onTap: () {
            Haptic.selection.play();
            // A row that only reports itself hands its value back as the route's result, so the
            // caller decides what happens next; one that does something runs after the menu has
            // gone, so whatever it opens is not left behind a panel still on screen.
            if (action.returns != null) {
              route.navigator?.pop(action.returns);
              return;
            }
            route.navigator?.pop();
            WidgetsBinding.instance.addPostFrameCallback((_) => action.run?.call());
          },
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.onTap});

  final StatusAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = action.destructive ? scheme.error : scheme.onSurface;
    final detail = action.detail;
    // Its own `Material`, not the panel's. A row is an `InkWell`, which needs one above it to
    // paint its splash on, and not every style's surface provides one — the glass panel is a
    // `GlassContainer`, so a row on it threw "No Material widget found" the moment it was tapped.
    // Transparent, so the glass underneath still shows through.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: StatusMenuRoute.rowHeight + (detail == null ? 0 : 16),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(action.icon, size: 20, color: ink),
              const SizedBox(width: 14),
              Expanded(
                child: detail == null
                    ? Text(
                        action.label,
                        maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ink),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ink),
                        ),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}
