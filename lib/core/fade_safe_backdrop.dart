import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Whether [layer] is drawn through a translucent [OpacityLayer], as a tab or a page is while it
/// fades, or through an [ImageFilterLayer], as a page is while it blurs in. A backdrop filter in
/// there samples that layer's own, still empty contents instead of what is on screen, and the
/// pane turns grey for as long as the fade runs.
bool insideFade(Layer layer) {
  for (Layer? parent = layer.parent; parent != null; parent = parent.parent) {
    if (parent is OpacityLayer && (parent.alpha ?? 255) < 255) return true;
    if (parent is ImageFilterLayer) return true;
  }
  return false;
}

/// A [BackdropFilter] that lets its child through unfiltered while it is [insideFade]. Decided
/// each time the layer is composited, so it needs no word from whatever animation is fading.
class FadeSafeBackdrop extends SingleChildRenderObjectWidget {
  const FadeSafeBackdrop({super.key, required this.filter, this.enabled = true, super.child});

  final ui.ImageFilter filter;
  final bool enabled;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderFadeSafeBackdrop()
    ..filter = filter
    ..enabled = enabled;

  @override
  void updateRenderObject(BuildContext context, RenderFadeSafeBackdrop renderObject) {
    renderObject
      ..filter = filter
      ..enabled = enabled;
  }
}

class RenderFadeSafeBackdrop extends RenderProxyBox {
  ui.ImageFilter? filter;
  bool enabled = true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final existing = layer;
    final backdrop = existing is _FadeSafeLayer ? existing : _FadeSafeLayer();
    backdrop.source = this;
    layer = backdrop;
    context.pushLayer(backdrop, super.paint, offset);
  }
}

class _FadeSafeLayer extends ContainerLayer {
  RenderFadeSafeBackdrop? source;

  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  void addToScene(ui.SceneBuilder builder) {
    final filter = source?.filter;
    if (filter == null || source?.enabled != true || insideFade(this)) {
      engineLayer = null;
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
