import 'package:flutter/gestures.dart';

/// Counts fingers on screen across the whole app. Long presses check it so that a two-finger
/// hold, which some systems claim for their own gestures, never opens one of ours as well.
class Touches {
  static final Set<int> _down = {};
  static bool _multiTouch = false;

  static void ensureInitialized() {
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  /// Whether the current touch (or the one that just ended) has used more than one finger.
  static bool get multiTouch => _multiTouch;

  static void _route(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (_down.isEmpty) _multiTouch = false;
      _down.add(event.pointer);
      if (_down.length > 1) _multiTouch = true;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _down.remove(event.pointer);
    }
  }
}
