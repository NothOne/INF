import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
/// The panel rests flush against the bottom of the room above the keyboard, with square bottom
/// corners by default so it meets the keyboard and the screen edge cleanly.
///
/// Nothing takes the focus until the panel has landed. Build the field with `autofocus: true` and
/// it asks on the frame after the travel, which is the order iOS uses.
Future<T?> showSurfaceCard<T>(
  BuildContext context, {
  required BuildContext anchor,
  required WidgetBuilder builder,
  double originRadius = 16,
  BorderRadius radius = const BorderRadius.vertical(top: Radius.circular(20)),
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
/// A phone gets the full width. Only a window wide enough to look odd does the panel keep a margin,
/// and it stops growing well before it spans a tablet.
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

class _SurfaceCardPage<T> extends StatelessWidget {
  const _SurfaceCardPage({required this.route, required this.animation});

  final SurfaceCardRoute<T> route;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final room = Size(
            constraints.maxWidth,
            (constraints.maxHeight - media.viewInsets.bottom).clamp(0.0, constraints.maxHeight),
          );
          final width = panelWidthFor(room);
          // Measured and positioned synchronously in one layout pass so switching between the soft
          // keyboard and the emoji panel never suffers a 1-frame height lag.
          return _SurfaceCardStage(
            child: _SurfaceCardWindow(
              key: const ValueKey('surface-card-window'),
              origin: route.origin,
              progress: animation.value,
              width: width,
              room: room,
              safe: media.padding,
              radius: route.radius,
              child: route.surface(context, radius: route.radius, child: route.builder(context)),
            ),
          );
        },
      ),
    );
  }
}

class _SurfaceCardStage extends SingleChildRenderObjectWidget {
  const _SurfaceCardStage({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSurfaceCardStage();
}

class _RenderSurfaceCardStage extends RenderShiftedBox {
  _RenderSurfaceCardStage() : super(null);

  @override
  void performLayout() {
    size = constraints.biggest;
    final child = this.child;
    if (child == null) return;
    child.layout(BoxConstraints.loose(size), parentUsesSize: true);
    final offset = child is _RenderSurfaceCardWindow ? child.windowTopLeft : Offset.zero;
    (child.parentData! as BoxParentData).offset = offset;
  }
}

class _SurfaceCardWindow extends SingleChildRenderObjectWidget {
  const _SurfaceCardWindow({
    super.key,
    required this.origin,
    required this.progress,
    required this.width,
    required this.room,
    required this.safe,
    required this.radius,
    required super.child,
  });

  final Rect origin;
  final double progress;
  final double width;
  final Size room;
  final EdgeInsets safe;
  final BorderRadius radius;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSurfaceCardWindow(
        origin: origin,
        progress: progress,
        width: width,
        room: room,
        safe: safe,
        radius: radius,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderSurfaceCardWindow renderObject) {
    renderObject
      ..origin = origin
      ..progress = progress
      ..width = width
      ..room = room
      ..safe = safe
      ..radius = radius;
  }
}

class _RenderSurfaceCardWindow extends RenderShiftedBox {
  _RenderSurfaceCardWindow({
    required this._origin,
    required this._progress,
    required this._width,
    required this._room,
    required this._safe,
    required this._radius,
  }) : super(null);

  Rect _origin;
  set origin(Rect value) {
    if (_origin == value) return;
    _origin = value;
    markNeedsLayout();
  }

  double _progress;
  set progress(double value) {
    if (_progress == value) return;
    _progress = value;
    markNeedsLayout();
  }

  double _width;
  set width(double value) {
    if (_width == value) return;
    _width = value;
    markNeedsLayout();
  }

  Size _room;
  set room(Size value) {
    if (_room == value) return;
    _room = value;
    markNeedsLayout();
  }

  EdgeInsets _safe;
  set safe(EdgeInsets value) {
    if (_safe == value) return;
    _safe = value;
    markNeedsLayout();
  }

  BorderRadius _radius;
  set radius(BorderRadius value) {
    if (_radius == value) return;
    _radius = value;
    markNeedsPaint();
  }

  Offset windowTopLeft = Offset.zero;
  final LayerHandle<ClipRRectLayer> _clipHandle = LayerHandle<ClipRRectLayer>();

  static double _ease(double t) => Curves.easeInOutCubicEmphasized.transform(t.clamp(0.0, 1.0));

  Rect _rest(double height) {
    final left = (_room.width - _width) / 2;
    final available = (_room.height - _safe.top - 8).clamp(0.0, _room.height);
    final fitted = math.min(height, available);
    return Rect.fromLTWH(left, _room.height - fitted, _width, fitted);
  }

  Rect _start(Rect target) => Rect.fromCenter(
        center: _origin.center,
        width: math.min(_origin.width, target.width),
        height: math.min(_origin.height, target.height),
      );

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = Size.zero;
      windowTopLeft = Offset.zero;
      return;
    }
    child.layout(
      BoxConstraints(minWidth: _width, maxWidth: _width, minHeight: 0, maxHeight: double.infinity),
      parentUsesSize: true,
    );
    final target = _rest(child.size.height);
    final at = Rect.lerp(_start(target), target, _ease(_progress))!;
    size = Size(at.width.clamp(0.0, constraints.maxWidth), at.height.clamp(0.0, constraints.maxHeight));
    windowTopLeft = at.topLeft;
    // Bottom-anchored inside the clip window so the field, toolbar, and emoji board stay visible
    // whenever the clip is shorter than the child's full height.
    (child.parentData! as BoxParentData).offset = Offset(0, size.height - child.size.height);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty) {
      _clipHandle.layer = null;
      return;
    }
    final bounds = Offset.zero & size;
    _clipHandle.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      bounds,
      _radius.toRRect(bounds),
      super.paint,
      clipBehavior: Clip.antiAlias,
      oldLayer: _clipHandle.layer,
    );
  }

  @override
  void dispose() {
    _clipHandle.layer = null;
    super.dispose();
  }
}
