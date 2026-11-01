import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

import 'look.dart';
import 'touches.dart';

/// The lens shader behind liquid glass. It needs Impeller; without it (or before it loads)
/// liquid glass is drawn with a blur and a painted rim instead, so nothing ever goes blank.
class LiquidShader {
  static ui.FragmentProgram? _program;

  /// Takes the lens path without a shader, so tests can lay out what devices composite.
  @visibleForTesting
  static bool debugForceShaded = false;

  static bool get available => debugForceShaded || (_program != null && ui.ImageFilter.isShaderFilterSupported);

  static Future<void> load() async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag');
    } catch (_) {
      _program = null;
    }
  }
}

/// Which edges of a pane bend what is behind them. A bar fixed to the top of the screen only
/// bends along its lower edge; the others are the screen's.
@immutable
class LiquidEdges {
  const LiquidEdges({this.top = true, this.right = true, this.bottom = true, this.left = true});

  static const all = LiquidEdges();
  static const bottomOnly = LiquidEdges(top: false, right: false, left: false);
  static const topOnly = LiquidEdges(right: false, bottom: false, left: false);
  static const exceptBottom = LiquidEdges(bottom: false);

  final bool top;
  final bool right;
  final bool bottom;
  final bool left;

  bool get isAll => top && right && bottom && left;

  @override
  bool operator ==(Object other) =>
      other is LiquidEdges && other.top == top && other.right == right && other.bottom == bottom && other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);
}

/// How a pane of liquid glass is cut: how wide its bending rim is and how hard it bends.
@immutable
class LiquidLens {
  const LiquidLens({
    this.bezel = 16,
    this.refraction = 1,
    this.dispersion = 0.22,
    this.highlight = 1,
    this.frost = 1,
    this.edges = LiquidEdges.all,
  });

  /// Width of the rim that bends, in logical pixels.
  final double bezel;

  /// Multiplies the user's 折射 setting.
  final double refraction;

  /// How far apart the colours split at the rim.
  final double dispersion;
  final double highlight;

  /// Multiplies the blur in the middle of the pane.
  final double frost;
  final LiquidEdges edges;

  LiquidLens scaled(double k) => LiquidLens(
        bezel: bezel,
        refraction: refraction * k,
        dispersion: dispersion * k,
        highlight: highlight * k,
        frost: frost,
        edges: edges,
      );

  @override
  bool operator ==(Object other) =>
      other is LiquidLens &&
      other.bezel == bezel &&
      other.refraction == refraction &&
      other.dispersion == dispersion &&
      other.highlight == highlight &&
      other.frost == frost &&
      other.edges == edges;

  @override
  int get hashCode => Object.hash(bezel, refraction, dispersion, highlight, frost, edges);
}

/// A pane of liquid glass. Like [GlassSurface] it blurs and tints what is behind it, but the
/// look lives in the rim: a lens that pulls in what lies just past the edge, a faint split of
/// colour, and a highlight on the lit side.
class LiquidSurface extends StatelessWidget {
  const LiquidSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.tint,
    this.lens = const LiquidLens(),
    this.lifted = false,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Overrides the default thin surface colour.
  final Color? tint;
  final LiquidLens lens;

  /// A soft shadow under the pane, for glass that floats over the page.
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final look = InfLook.of(context);
    final tintColor = tint ?? scheme.surface.withValues(alpha: look.liquidTintAlpha(scheme.brightness));
    final shaded = LiquidShader.available;
    final body = DecoratedBox(
      decoration: BoxDecoration(color: tintColor),
      child: CustomPaint(
        foregroundPainter: _RimPainter(
          radius: borderRadius,
          edges: lens.edges,
          dark: dark,
          // The shader draws its own highlight; painted, the rim is only there to keep the edge crisp.
          strength: shaded ? 0.45 : 1,
        ),
        child: child,
      ),
    );
    final Widget glass;
    if (shaded) {
      glass = _LiquidBackdrop(
        radius: borderRadius.topLeft.x,
        lens: lens,
        refraction: look.refraction,
        blurSigma: look.liquidBlurSigma * lens.frost,
        dark: dark,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        child: body,
      );
    } else {
      final sigma = look.liquidBlurSigma * lens.frost;
      glass = BackdropFilter(filter: _fallbackFilter(sigma), child: body);
    }
    final pane = ClipRRect(borderRadius: borderRadius, child: glass);
    if (!lifted) return pane;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.32 : 0.10),
            blurRadius: 24,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: pane,
    );
  }
}

ui.ImageFilter _fallbackFilter(double sigma) {
  const s = 1.35;
  return ui.ImageFilter.compose(
    outer: const ColorFilter.matrix(<double>[
      0.2126 * (1 - s) + s, 0.7152 * (1 - s), 0.0722 * (1 - s), 0, 0,
      0.2126 * (1 - s), 0.7152 * (1 - s) + s, 0.0722 * (1 - s), 0, 0,
      0.2126 * (1 - s), 0.7152 * (1 - s), 0.0722 * (1 - s) + s, 0, 0,
      0, 0, 0, 1, 0,
    ]),
    inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
  );
}

/// The rim of the pane: bright where the light comes from (the top left), fading round to a
/// faint line opposite. On edges that do not bend it is left out.
class _RimPainter extends CustomPainter {
  const _RimPainter({required this.radius, required this.edges, required this.dark, required this.strength});

  final BorderRadius radius;
  final LiquidEdges edges;
  final bool dark;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final lit = Colors.white.withValues(alpha: (dark ? 0.34 : 0.95) * strength);
    final shade = Colors.white.withValues(alpha: (dark ? 0.06 : 0.28) * strength);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = dark ? 0.9 : 1.1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [lit, shade, shade, lit.withValues(alpha: lit.a * 0.6)],
        stops: const [0, 0.42, 0.7, 1],
      ).createShader(rect);
    if (edges.isAll) {
      canvas.drawRRect(radius.toRRect(rect).deflate(0.5), paint);
      return;
    }
    final path = Path();
    if (edges.top) path..moveTo(0, 0.5)..lineTo(size.width, 0.5);
    if (edges.bottom) path..moveTo(0, size.height - 0.5)..lineTo(size.width, size.height - 0.5);
    if (edges.left) path..moveTo(0.5, 0)..lineTo(0.5, size.height);
    if (edges.right) path..moveTo(size.width - 0.5, 0)..lineTo(size.width - 0.5, size.height);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius || old.edges != edges || old.dark != dark || old.strength != strength;
}

class _LiquidBackdrop extends SingleChildRenderObjectWidget {
  const _LiquidBackdrop({
    required this.radius,
    required this.lens,
    required this.refraction,
    required this.blurSigma,
    required this.dark,
    required this.devicePixelRatio,
    super.child,
  });

  final double radius;
  final LiquidLens lens;
  final double refraction;
  final double blurSigma;
  final bool dark;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLiquidBackdrop()
    ..radius = radius
    ..lens = lens
    ..refraction = refraction
    ..blurSigma = blurSigma
    ..dark = dark
    ..devicePixelRatio = devicePixelRatio;

  @override
  void updateRenderObject(BuildContext context, _RenderLiquidBackdrop renderObject) {
    renderObject
      ..radius = radius
      ..lens = lens
      ..refraction = refraction
      ..blurSigma = blurSigma
      ..dark = dark
      ..devicePixelRatio = devicePixelRatio;
  }
}

/// Pushes the lens as a backdrop filter. The shader needs to know where on screen the pane is,
/// which changes without this object repainting (a list scrolling a repaint boundary, a route
/// sliding in), so the filter is rebuilt each time the layer is composited, not when painted.
class _RenderLiquidBackdrop extends RenderProxyBox {
  double radius = 0;
  LiquidLens lens = const LiquidLens();
  double refraction = InfLook.defaultRefraction;
  double blurSigma = 4;
  bool dark = false;
  double devicePixelRatio = 1;

  static const _light = Offset(-0.5, -0.866);

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final existing = layer;
    final liquid = existing is _LiquidLayer ? existing : _LiquidLayer();
    liquid.source = this;
    layer = liquid;
    context.pushLayer(liquid, super.paint, offset);
  }

  ui.ImageFilter? filterNow() {
    final program = LiquidShader._program;
    if (program == null || !attached || !hasSize || size.isEmpty) return null;
    final transform = getTransformTo(null);
    final rect = MatrixUtils.transformRect(transform, Offset.zero & size);
    if (!rect.isFinite || rect.isEmpty) return null;
    final scale = rect.width / size.width;
    final dpr = devicePixelRatio;
    final pane = Rect.fromLTRB(rect.left * dpr, rect.top * dpr, rect.right * dpr, rect.bottom * dpr);
    const far = 20000.0;
    final edges = lens.edges;
    final shape = Rect.fromLTRB(
      edges.left ? pane.left : pane.left - far,
      edges.top ? pane.top : pane.top - far,
      edges.right ? pane.right : pane.right + far,
      edges.bottom ? pane.bottom : pane.bottom + far,
    );
    final px = dpr * scale;
    final bezel = math.min(lens.bezel * px, math.min(pane.width, pane.height) * 0.5);
    final bend = bezel * 0.85 * lens.refraction * (0.25 + 1.5 * refraction);
    final shader = program.fragmentShader();
    var i = 0;
    void put(double value) => shader.setFloat(i++, value);
    put(0);
    put(0);
    put(pane.left);
    put(pane.top);
    put(pane.width);
    put(pane.height);
    put(shape.left);
    put(shape.top);
    put(shape.width);
    put(shape.height);
    put(radius * px);
    put(bezel);
    put(bend);
    put((lens.dispersion * (0.4 + refraction)).clamp(0.0, 0.6));
    put(blurSigma * px * 0.9);
    put(1.3);
    put(lens.highlight * (dark ? 0.55 : 0.85));
    put(_light.dx);
    put(_light.dy);
    return ui.ImageFilter.shader(shader);
  }
}

class _LiquidLayer extends ContainerLayer {
  // Not `owner`: that is the layer tree's own and the layer will not attach if shadowed.
  _RenderLiquidBackdrop? source;

  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  void addToScene(ui.SceneBuilder builder) {
    final filter = source?.filterNow();
    if (filter == null) {
      addChildrenToScene(builder);
      return;
    }
    final old = engineLayer;
    engineLayer = builder.pushBackdropFilter(
      filter,
      oldLayer: old is ui.BackdropFilterEngineLayer ? old : null,
    );
    addChildrenToScene(builder);
    builder.pop();
  }
}

/// Liquid glass gives under the finger: it swells a little and leans towards the touch, then
/// springs back when let go. A [Listener], so it never takes a gesture from what it wraps.
class LiquidPress extends StatefulWidget {
  const LiquidPress({super.key, required this.child, this.amount = 1});

  final Widget child;
  final double amount;

  @override
  State<LiquidPress> createState() => _LiquidPressState();
}

class _LiquidPressState extends State<LiquidPress> with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController.unbounded(vsync: this);
  Offset _lean = Offset.zero;
  int _pointers = 0;

  static const _down = SpringDescription(mass: 1, stiffness: 700, damping: 36);
  static const _up = SpringDescription(mass: 1, stiffness: 360, damping: 14);

  void _spring(double target, SpringDescription spring) {
    _press.animateWith(SpringSimulation(spring, _press.value, target, _press.velocity));
  }

  void _aim(Offset local) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return;
    final size = box.size;
    _lean = Offset(
      ((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0),
      ((local.dy / size.height) * 2 - 1).clamp(-1.0, 1.0),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _pointers++;
        _aim(event.localPosition);
        _spring(1, _down);
      },
      onPointerMove: (event) => _aim(event.localPosition),
      onPointerUp: (_) {
        _pointers = math.max(0, _pointers - 1);
        if (_pointers == 0) _spring(0, _up);
      },
      onPointerCancel: (_) {
        _pointers = math.max(0, _pointers - 1);
        if (_pointers == 0) _spring(0, _up);
      },
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) {
          final t = _press.value * widget.amount;
          final box = context.findRenderObject();
          final width = box is RenderBox && box.hasSize ? box.size.width : 100.0;
          // Small panes swell more than wide ones, which would otherwise poke off the screen.
          final grow = (10 / math.max(width, 1)).clamp(0.012, 0.08);
          final transform = Matrix4.translationValues(_lean.dx * 2.5 * t, _lean.dy * 1.5 * t, 0)
            ..multiply(Matrix4.diagonal3Values(1 + grow * t, 1 + grow * 0.7 * t, 1));
          return Transform(transform: transform, alignment: Alignment.center, child: child);
        },
        child: widget.child,
      ),
    );
  }
}

/// A top bar of liquid glass. Its lower edge bends what scrolls under it, more the further the
/// content has gone under, so the bar seems to gather the page as it passes.
class LiquidBarBackground extends StatefulWidget {
  const LiquidBarBackground({super.key});

  @override
  State<LiquidBarBackground> createState() => _LiquidBarBackgroundState();
}

class _LiquidBarBackgroundState extends State<LiquidBarBackground> {
  ScrollNotificationObserverState? _observer;
  double _depth = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer?.removeListener(_onScroll);
    _observer = ScrollNotificationObserver.maybeOf(context);
    _observer?.addListener(_onScroll);
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification || notification.metrics.axis != Axis.vertical) return;
    final depth = ((notification.metrics.extentBefore / 96).clamp(0.0, 1.0) * 10).round() / 10;
    if (depth != _depth) setState(() => _depth = depth);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final look = InfLook.of(context);
    final resting = Color.lerp(scheme.surface, scheme.surfaceContainer, 0.6)!.withValues(alpha: 0.70);
    final engaged = scheme.surface.withValues(alpha: look.liquidTintAlpha(scheme.brightness));
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _depth),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, t, child) => LiquidSurface(
        tint: Color.lerp(resting, engaged, t),
        lens: LiquidLens(
          bezel: 14,
          refraction: 0.2 + 0.8 * t,
          dispersion: 0.18 * t,
          highlight: 0.4 + 0.6 * t,
          edges: LiquidEdges.bottomOnly,
        ),
        child: child!,
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// A modal sheet as a pane of liquid glass. It grows out of where the finger last went down,
/// swelling slightly past its size before settling.
class LiquidSheet extends StatelessWidget {
  const LiquidSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final look = InfLook.of(context);
    final alpha = look.liquidTintAlpha(scheme.brightness);
    final sheet = LiquidSurface(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      // A sheet holds text over a dimmed page: more body than a bar.
      tint: scheme.surface.withValues(alpha: (alpha + 0.24).clamp(0.0, 0.94)),
      lens: const LiquidLens(bezel: 20, refraction: 0.7, highlight: 1.1, edges: LiquidEdges.exceptBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 44,
            child: Center(
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
    return LiquidEmergence(child: sheet);
  }
}

/// Scales a route's content in from the last touch, along the bottom edge so nothing lifts off
/// the screen: the springy part of a liquid sheet opening.
class LiquidEmergence extends StatelessWidget {
  const LiquidEmergence({super.key, required this.child});

  final Widget child;

  static final Curve _swell = Curves.easeOutBack;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) return child;
    var width = MediaQuery.sizeOf(context).width;
    var down = Touches.lastDown;
    // A sheet in a tablet's detail pane spans the pane, not the screen.
    final box = Navigator.maybeOf(context)?.context.findRenderObject();
    if (down != null && box is RenderBox && box.hasSize) {
      down = box.globalToLocal(down);
      width = box.size.width;
    }
    final x = down == null || width <= 0 ? 0.0 : ((down.dx / width) * 2 - 1).clamp(-0.8, 0.8);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        final forward = animation.status != AnimationStatus.reverse;
        final eased = forward ? _swell.transform(t) : t;
        final scale = 0.9 + 0.1 * eased;
        return Transform.scale(scale: scale, alignment: Alignment(x, 1), child: child);
      },
      child: child,
    );
  }
}

/// The selection of a tab bar as a drop of liquid glass under the tabs. It springs from tab to
/// tab, stretching along the way as it picks up speed, and can be dragged along the bar to
/// choose a tab.
class LiquidTabTrack extends StatefulWidget {
  const LiquidTabTrack({
    super.key,
    required this.count,
    required this.index,
    required this.onSelect,
    required this.child,
    this.axis = Axis.horizontal,
    this.inset = 5,
  });

  final int count;
  final int index;
  final ValueChanged<int> onSelect;
  final Widget child;
  final Axis axis;
  final double inset;

  @override
  State<LiquidTabTrack> createState() => _LiquidTabTrackState();
}

class _LiquidTabTrackState extends State<LiquidTabTrack> with SingleTickerProviderStateMixin {
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.index.toDouble(),
  );
  bool _dragging = false;
  double _dragSpeed = 0;

  static const _spring = SpringDescription(mass: 1, stiffness: 340, damping: 24);

  @override
  void didUpdateWidget(LiquidTabTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index && !_dragging) _springTo(widget.index.toDouble());
  }

  void _springTo(double target, [double? velocity]) {
    _position.animateWith(SpringSimulation(_spring, _position.value, target, velocity ?? _position.velocity));
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  bool get _horizontal => widget.axis == Axis.horizontal;

  void _dragStart(DragStartDetails details) {
    _position.stop();
    setState(() {
      _dragging = true;
      _dragSpeed = 0;
    });
  }

  void _dragUpdate(DragUpdateDetails details, double extent) {
    final delta = (_horizontal ? details.delta.dx : details.delta.dy) / extent;
    _dragSpeed = _dragSpeed * 0.6 + delta * 60 * 0.4;
    _position.value = (_position.value + delta).clamp(-0.15, widget.count - 0.85);
  }

  void _dragEnd(DragEndDetails details, double extent) {
    final velocity = (details.primaryVelocity ?? 0) / extent;
    final projected = _position.value + velocity * 0.12;
    final target = projected.round().clamp(0, widget.count - 1);
    setState(() {
      _dragging = false;
      _dragSpeed = 0;
    });
    _springTo(target.toDouble(), velocity);
    if (target != widget.index) widget.onSelect(target);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final main = _horizontal ? constraints.maxWidth : constraints.maxHeight;
        final cross = _horizontal ? constraints.maxHeight : constraints.maxWidth;
        final extent = main / widget.count;
        final drop = AnimatedBuilder(
          animation: _position,
          builder: (context, _) {
            final speed = _dragging ? _dragSpeed : _position.velocity;
            final stretch = (speed.abs() / 9).clamp(0.0, 0.42) + (_dragging ? 0.06 : 0);
            final along = (extent - widget.inset * 2) * (1 + stretch);
            final across = (cross - widget.inset * 2) * (1 - stretch * 0.3);
            final center = (_position.value + 0.5) * extent;
            final radius = BorderRadius.circular(across / 2);
            final pane = LiquidSurface(
              borderRadius: radius,
              tint: scheme.primary.withValues(alpha: scheme.brightness == Brightness.dark ? 0.16 : 0.10),
              lens: const LiquidLens(bezel: 12, refraction: 1.5, dispersion: 0.35, highlight: 1.2, frost: 0.3),
              child: const SizedBox.expand(),
            );
            return Stack(
              children: [
                _horizontal
                    ? Positioned(
                        left: center - along / 2,
                        top: (cross - across) / 2,
                        width: along,
                        height: across,
                        child: pane,
                      )
                    : Positioned(
                        top: center - along / 2,
                        left: (cross - across) / 2,
                        width: across,
                        height: along,
                        child: pane,
                      ),
              ],
            );
          },
        );
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _horizontal ? _dragStart : null,
          onHorizontalDragUpdate: _horizontal ? (d) => _dragUpdate(d, extent) : null,
          onHorizontalDragEnd: _horizontal ? (d) => _dragEnd(d, extent) : null,
          onVerticalDragStart: _horizontal ? null : _dragStart,
          onVerticalDragUpdate: _horizontal ? null : (d) => _dragUpdate(d, extent),
          onVerticalDragEnd: _horizontal ? null : (d) => _dragEnd(d, extent),
          child: Stack(children: [Positioned.fill(child: drop), widget.child]),
        );
      },
    );
  }
}
