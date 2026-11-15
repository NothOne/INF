import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;

import '../chrome.dart';

/// How a style makes a panel that is typed in: solid in every style, because words being written
/// sit on something solid. The same hook `InfChrome.typingSheet` gives a sheet, so the route does
/// not have to know which style it is drawing.
typedef SurfaceCardSurface = Widget Function(
  BuildContext context, {
  required BorderRadius radius,
  required Widget child,
});

/// Opens [builder]'s panel out of [anchor]'s rectangle and back into it on the way out — the travel
/// a post's menu makes, for a surface that is typed in.
///
/// This is the comment box and the reply box. They used to rise from the foot of the screen, which
/// said nothing about where they came from; growing out of the thing that was tapped says it, and
/// leaves the post visible around the panel instead of sliding a slab over the page.
///
/// The panel rests against the bottom of the room it has, so the keyboard is what decides how high
/// it sits: the board coming up raises the panel rather than covering it.
///
/// Nothing takes the focus until the panel has landed. A panel that focused a field on its first
/// frame puts the keyboard up over the whole growth, and what the reader sees is a keyboard
/// arriving rather than a panel opening. Build the field with `autofocus: true` and it asks on the
/// frame after the travel, which is the order iOS uses.
Future<T?> showSurfaceCard<T>(
  BuildContext context, {
  required BuildContext anchor,
  required WidgetBuilder builder,
  double originRadius = 16,
  BorderRadius radius = const BorderRadius.all(Radius.circular(24)),
}) {
  final box = anchor.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return Future.value();
  return Navigator.of(anchor).push<T>(
    SurfaceCardRoute<T>(
      anchor: anchor,
      origin: box.localToGlobal(Offset.zero) & box.size,
      radius: radius,
      originRadius: originRadius,
      surface: InfChrome.of(context).typingSheet,
      builder: builder,
    ),
  );
}

/// The width a typed-in panel takes in a window of [room].
///
/// A phone gets the full width. The panel is the only thing on screen there, and a panel floating
/// 16 dp off both edges reads as a card that has not finished arriving — besides which the control
/// that opened it (a comment bar, a post) is full-width, so a narrower panel would have to *shrink*
/// as it grew, which is the opposite of opening. Only a window wide enough to look odd does the
/// panel keep a margin, and it stops growing well before it spans a tablet.
double panelWidthFor(Size room) {
  const maxWidth = 560.0;
  const edge = 16.0;
  const wideThreshold = 600.0;
  final usable = room.width > wideThreshold ? room.width - edge * 2 : room.width;
  return usable.clamp(240.0, maxWidth);
}

/// The route behind [showSurfaceCard].
class SurfaceCardRoute<T> extends PopupRoute<T> {
  SurfaceCardRoute({
    required this.anchor,
    required Rect origin,
    required this.builder,
    required this.surface,
    required this.radius,
    this.originRadius = 16,
  }) : _openedAt = origin;

  /// The control the panel came from.
  ///
  /// Kept as a context, not only as the rectangle it had at the tap, because that rectangle moves
  /// while the panel is open: a comment bar sits above the keyboard when the panel opens and back on
  /// the foot of the screen once the keys are gone. Returning to the old rectangle would carry the
  /// panel *up* off the bottom edge and stop it in the middle of the page, instead of folding it down
  /// into the bar it belongs to.
  final BuildContext anchor;

  /// Where [anchor] is now; where it was at the tap if it has left the tree.
  Rect get origin {
    final box = anchor.mounted ? anchor.findRenderObject() : null;
    if (box is RenderBox && box.hasSize) return box.localToGlobal(Offset.zero) & box.size;
    return _openedAt;
  }

  /// The rectangle [anchor] had when the panel opened.
  final Rect _openedAt;

  /// What the panel is made of, per style.
  final SurfaceCardSurface surface;

  /// The panel's own corner radius.
  final BorderRadius radius;

  /// The corner radius of [origin], so the growth starts from the tapped widget's own shape.
  final double originRadius;

  final WidgetBuilder builder;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.18);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => '关闭';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      _SurfaceCardPage<T>(route: this, animation: animation);
}

class _SurfaceCardPage<T> extends StatefulWidget {
  const _SurfaceCardPage({required this.route, required this.animation});

  final SurfaceCardRoute<T> route;
  final Animation<double> animation;

  @override
  State<_SurfaceCardPage<T>> createState() => _SurfaceCardPageState<T>();
}

class _SurfaceCardPageState<T> extends State<_SurfaceCardPage<T>> {
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          // The room the panel has above the keyboard. `constraints` is the whole overlay — the
          // keyboard does not shrink it — so taking the inset out here is what keeps the panel from
          // being laid out under the keys: at full height it rests against the bottom of the
          // *screen*, which is exactly where the keyboard is, and the field it exists for is
          // covered by it.
          final room = Size(
            constraints.maxWidth,
            (constraints.maxHeight - media.viewInsets.bottom).clamp(0.0, constraints.maxHeight),
          );
          return _TravellingPanel(
            origin: widget.route.origin,
            progress: widget.animation.value,
            originRadius: widget.route.originRadius,
            width: panelWidthFor(room),
            room: room,
            safe: media.padding,
            radius: widget.route.radius,
            surface: widget.route.surface,
            child: widget.route.builder(context),
          );
        },
      ),
    );
  }
}

/// The panel at its place along the travel: measured once, then drawn between [origin] and the foot
/// of [room].
///
/// The measuring is a single layout pass: the child is laid out at the width it will have, its
/// height is read, and that height is what places it. A comment box grows and shrinks as the emoji
/// board opens, so a height guessed before the layout would leave it hanging off the top of the
/// screen on one size and floating above the keyboard on another.
///
/// While the height is still unknown the panel is drawn at [origin], where it belongs at
/// `progress == 0` anyway, so the first frame cannot be seen to be wrong.
class _TravellingPanel extends StatefulWidget {
  const _TravellingPanel({
    required this.origin,
    required this.progress,
    required this.originRadius,
    required this.width,
    required this.room,
    required this.safe,
    required this.radius,
    required this.surface,
    required this.child,
  });

  final Rect origin;
  final double progress;
  final double originRadius;
  final double width;

  /// The room the panel has, with the keyboard taken out of it.
  final Size room;

  final EdgeInsets safe;
  final BorderRadius radius;
  final SurfaceCardSurface surface;
  final Widget child;

  @override
  State<_TravellingPanel> createState() => _TravellingPanelState();
}

class _TravellingPanelState extends State<_TravellingPanel> {
  /// The panel's laid-out height, written from the layout pass and read by the next placement.
  double? _height;

  @override
  Widget build(BuildContext context) {
    final height = _height;
    // Until the height is known the panel is measured: it sits at the origin, where it belongs at
    // the start of the growth anyway, so the first frame cannot be seen to be wrong.
    if (height == null) {
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: widget.width,
          child: _Measured(
            onHeight: _recordHeight,
            child: widget.surface(context, radius: widget.radius, child: widget.child),
          ),
        ),
      );
    }

    final target = _rest(height);
    final at = Rect.lerp(_start(target), target, _ease(widget.progress))!;
    return Stack(
      children: [
        Positioned.fromRect(
          rect: at,
          // The panel is laid out at its resting size and revealed through a window that grows into
          // it: the corner radius belongs to the window, and the words stay where they end up
          // instead of reflowing on every frame of the growth.
          //
          // The `ClipRect` is what bounds it. `OverflowBox` below is handed the resting size in both
          // directions, so without a clip the panel would draw at full size from the first frame
          // and only its top-left corner would move — the sliding-in-place that these tests exist
          // to catch.
          child: ClipRRect(
            key: const ValueKey('surface-card-window'),
            borderRadius: widget.radius,
            clipBehavior: Clip.antiAlias,
            child: OverflowBox(
              // Anchored at the bottom: the panel's foot is what the reader is working with (the
              // field, the row of buttons, the board), so when the panel is taller than the room it
              // has, the part that goes is the top — the quoted line — not the board.
              alignment: Alignment.bottomCenter,
              minWidth: widget.width,
              maxWidth: widget.width,
              // No height limit, so the panel is laid out at its natural height and the clip above
              // decides how much of it shows. A fixed height here would hold the panel at whatever
              // it measured the first time, and a board opening under it would have nowhere to
              // appear — that is what left the emoji picker with no room to draw in.
              minHeight: 0,
              maxHeight: double.infinity,
              // Measured on every layout, not only the first: the board changes the panel's height
              // while the panel is already open.
              child: _Measured(
                onHeight: _recordHeight,
                child: widget.surface(context, radius: widget.radius, child: widget.child),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The largest rectangle at the tapped control that is no bigger than the panel, centred on it.
  Rect _start(Rect target) => Rect.fromCenter(
        center: widget.origin.center,
        width: math.min(widget.origin.width, target.width),
        height: math.min(widget.origin.height, target.height),
      );

  /// The same curve the page transform that opens a post uses: slow at the start, so the widget is
  /// seen to open before the panel arrives.
  static double _ease(double t) => Curves.easeInOutCubicEmphasized.transform(t.clamp(0.0, 1.0));

  void _recordHeight(double value) {
    if (value == _height) return;
    // Written from inside layout, and the placement it feeds belongs to the next frame: calling
    // back into `setState` here would be a rebuild during layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _height = value);
    });
  }

  /// Where the panel rests: centred across the room, its foot on the bottom of it.
  ///
  /// The panel's foot is the bottom of the room, and the room already excludes the keyboard. The
  /// board is what keeps the field still when the keys go away: it is exactly as tall as they were,
  /// so the panel's foot follows the room down and its top — the field — stays on its line (see
  /// `EmojiKeyboard.boardHeight`).
  ///
  /// When the panel is taller than the room it has, it is cut to the room rather than pushed up past
  /// the top edge, which would have put its foot — the board — off the bottom of the screen.
  Rect _rest(double height) {
    final left = (widget.room.width - widget.width) / 2;
    final available = (widget.room.height - widget.safe.top - 8).clamp(0.0, widget.room.height);
    final fitted = math.min(height, available);
    return Rect.fromLTWH(left, widget.room.height - fitted, widget.width, fitted);
  }
}

/// Reports the child's laid-out height once, so the panel can be placed without guessing.
///
/// Its own size follows the constraints it is given: it is here to read the child, not to set the
/// panel's size, and a reporter that sized itself past its box would fail layout.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasured(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onHeight);

  ValueChanged<double> onHeight;

  /// Last value handed out, so an unchanged height does not schedule a rebuild every frame.
  double? _reported;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    // Height unbounded: the point is the panel's natural height, whatever box it is being measured
    // in. The width stays what it will have, so nothing wraps differently from the real thing.
    child.layout(
      BoxConstraints(minWidth: constraints.maxWidth, maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
    size = constraints.constrain(Size(constraints.maxWidth, child.size.height));
    if (child.size.height != _reported) {
      _reported = child.size.height;
      onHeight(child.size.height);
    }
  }
}

