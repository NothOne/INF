import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';


/// Where the next page grows from, captured from the tapped widget just before navigating.
class ContainerOrigin {
  const ContainerOrigin({
    required this.rect,
    this.radius = 0,
    this.color,
    this.alignTop,
  });

  /// In global (screen) coordinates.
  final Rect rect;
  final double radius;

  /// What the origin is filled with, faded out as the page arrives (a button's colour, say).
  final Color? color;

  /// Where the origin's own content sits on the new page, from the top of the screen. When set,
  /// the page is shifted so that content stays exactly where it was and the page grows around
  /// it; when null, the page fades in inside the growing shape.
  final double? alignTop;

  static ContainerOrigin? _pending;
  static DateTime _capturedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Records [context]'s box as the origin of the next [pushInf].
  static void capture(BuildContext context, {double radius = 0, Color? color, double? alignTop}) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    _pending = ContainerOrigin(
      rect: box.localToGlobal(Offset.zero) & box.size,
      radius: radius,
      color: color,
      alignTop: alignTop,
    );
    _capturedAt = DateTime.now();
  }

  /// The origin captured by the tap that is navigating now, if any. A capture whose navigation
  /// never happened must not hijack a later, unrelated one.
  static ContainerOrigin? take() {
    final origin = _pending;
    _pending = null;
    if (origin == null || DateTime.now().difference(_capturedAt) > const Duration(milliseconds: 500)) {
      return null;
    }
    return origin;
  }
}

/// A page that grows out of the widget that opened it (Material's container transform), and
/// shrinks back into it — following the finger during the system back gesture.
class ContainerTransformRoute<T> extends PageRoute<T> {
  ContainerTransformRoute({required this.origin, required this.builder, super.settings});

  final ContainerOrigin origin;
  final WidgetBuilder builder;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 450);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 340);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      builder(context);

  // The back gesture is tracked here rather than as the navigator's user gesture. The routes
  // below read that navigator-wide flag too, and the stock page transition swaps its whole widget
  // tree on it, so the page underneath — which this transition never moves — was re-laid out
  // from scratch as the finger went down, and again once the pop finished.
  bool _gesture = false;

  @override
  bool get popGestureInProgress => _gesture;

  @override
  void handleStartBackGesture({double progress = 0.0}) {
    assert(isCurrent);
    controller?.value = progress;
    _gesture = true;
  }

  @override
  void handleUpdateBackGestureProgress({required double progress}) {
    if (!isCurrent) return;
    controller?.value = progress;
  }

  @override
  void handleCancelBackGesture() => _endGesture(pop: false);

  @override
  void handleCommitBackGesture() => _endGesture(pop: true);

  void _endGesture({required bool pop}) {
    final controller = this.controller!;
    if (isCurrent) {
      if (!pop) {
        if (!controller.isCompleted) controller.forward();
      } else {
        navigator?.pop();
        if (controller.isAnimating) controller.reverse(from: controller.upperBound);
      }
    }
    if (!controller.isAnimating) {
      _gesture = false;
      return;
    }
    // Still in progress until the page settles: the transition scales the rest of the shrink
    // from where the finger let go.
    late final AnimationStatusListener settle;
    settle = (status) {
      _gesture = false;
      controller.removeStatusListener(settle);
    };
    controller.addStatusListener(settle);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _BackGestureDriver(
      route: this,
      child: _ContainerTransition(route: this, animation: animation, child: child),
    );
  }
}

/// Hands the system back gesture's progress to the route, which drives its own animation with
/// it; the page then shrinks toward its origin under the finger and pops on release.
class _BackGestureDriver extends StatefulWidget {
  const _BackGestureDriver({required this.route, required this.child});

  final ContainerTransformRoute<dynamic> route;
  final Widget child;

  @override
  State<_BackGestureDriver> createState() => _BackGestureDriverState();
}

class _BackGestureDriverState extends State<_BackGestureDriver>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Only the part of the gesture that pulls the page back; the edge swipe itself travels the
  /// whole screen width.
  static const double _reach = 0.55;

  /// Keeps a frame scheduled at every vsync while the finger is down. Progress arrives over a
  /// platform channel just after a vsync, and a frame requested from there is only drawn a vsync
  /// later, so on its own the page followed the finger at half the display rate.
  late final Ticker _pacer = createTicker((_) {});

  double _progress(PredictiveBackEvent event) => 1 - (event.progress / _reach).clamp(0.0, 1.0) * 0.6;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pacer.dispose();
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final route = widget.route;
    if (backEvent.isButtonEvent || !route.isCurrent || !route.popGestureEnabled) return false;
    route.handleStartBackGesture(progress: _progress(backEvent));
    if (!_pacer.isActive) _pacer.start();
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    widget.route.handleUpdateBackGestureProgress(progress: _progress(backEvent));
  }

  @override
  void handleCancelBackGesture() {
    _pacer.stop();
    widget.route.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    _pacer.stop();
    widget.route.handleCommitBackGesture();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ContainerTransition extends StatefulWidget {
  const _ContainerTransition({required this.route, required this.animation, required this.child});

  final ContainerTransformRoute<dynamic> route;
  final Animation<double> animation;
  final Widget child;

  @override
  State<_ContainerTransition> createState() => _ContainerTransitionState();
}

class _ContainerTransitionState extends State<_ContainerTransition> {
  /// Where the finger left the page; a committed back gesture restarts the route's animation
  /// from fully open, so the shrink is scaled down from this instead of jumping back first.
  double _released = 1;

  /// Starts slowly, so the origin is seen to grow before the page rushes in; a decelerating
  /// curve would make it pop.
  static const _curve = Curves.easeInOutCubicEmphasized;

  double _progress() {
    final animation = widget.animation;
    final value = animation.value;
    final reversing = animation.status == AnimationStatus.reverse;
    if (widget.route.popGestureInProgress) {
      if (!reversing) {
        // The finger, not a curve, decides where the page is.
        _released = value;
        return value;
      }
      return _released * _curve.flipped.transform(value);
    }
    _released = 1;
    return reversing ? _curve.flipped.transform(value) : _curve.transform(value);
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final animation = widget.animation;
    final origin = route.origin;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // One widget shape at every stage, including at rest: a change of shape would rebuild the
    // page from scratch.
    return AnimatedBuilder(
      animation: animation,
      child: RepaintBoundary(child: widget.child),
      builder: (context, page) {
        final settled = animation.isCompleted;
        final t = settled ? 1.0 : _progress();
        final screen = Offset.zero & MediaQuery.sizeOf(context);
        final rect = Rect.lerp(origin.rect, screen, t)!;
        final radius = lerpDouble(origin.radius, route.popGestureInProgress ? 22 : 0, t)!;
        final aligned = origin.alignTop != null;
        // Aligned, the page's copy of the origin covers the original roughly (the page may show
        // more of it), so a fade that is short in clock time — not in [t], whose curve lingers at
        // the ends — swaps them; the copy holds still over the original meanwhile, or both
        // would show, offset. Otherwise the page arrives later and slower.
        const hold = 0.05;
        final travel = ((t - hold) / (1 - hold)).clamp(0.0, 1.0);
        final dy = aligned ? lerpDouble(origin.rect.top - origin.alignTop!, 0, travel)! : 0.0;
        final pageOpacity = aligned
            ? ((settled ? 1.0 : animation.value) / 0.1).clamp(0.0, 1.0)
            : Curves.easeOut.transform(((t - 0.18) / 0.5).clamp(0.0, 1.0));
        final fill = origin.color;
        final fillOpacity = fill == null ? 0.0 : 1 - Curves.easeIn.transform((t / 0.45).clamp(0.0, 1.0));
        final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: (dark ? 0.32 : 0.14) * t)),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _ShadowPainter(shape, alpha: (dark ? 0.45 : 0.16) * (1 - (t - 0.85).clamp(0.0, 0.15) / 0.15)),
              ),
            ),
            Positioned.fill(
              child: ClipRRect(
                clipper: _ShapeClipper(shape),
                clipBehavior: settled ? Clip.none : Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fromRect(
                      rect: rect,
                      child: ColoredBox(color: (fill ?? Colors.transparent).withValues(alpha: fillOpacity)),
                    ),
                    Opacity(
                      opacity: pageOpacity,
                      child: Transform.translate(offset: Offset(0, dy), child: page),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ShapeClipper extends CustomClipper<RRect> {
  _ShapeClipper(this.shape);

  final RRect shape;

  @override
  RRect getClip(Size size) => shape;

  @override
  bool shouldReclip(_ShapeClipper oldClipper) => oldClipper.shape != shape;
}

class _ShadowPainter extends CustomPainter {
  _ShadowPainter(this.shape, {required this.alpha});

  final RRect shape;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0) return;
    canvas.drawRRect(
      shape.shift(const Offset(0, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
  }

  @override
  bool shouldRepaint(_ShadowPainter oldDelegate) => oldDelegate.shape != shape || oldDelegate.alpha != alpha;
}
