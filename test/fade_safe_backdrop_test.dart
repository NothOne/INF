import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/fade_safe_backdrop.dart';

void main() {
  test('a layer under a translucent opacity layer is inside a fade', () {
    final leaf = ContainerLayer();
    final fade = OpacityLayer(alpha: 128)..append(OffsetLayer()..append(leaf));
    ContainerLayer().append(fade);
    expect(insideFade(leaf), isTrue);
  });

  test('fully opaque or no opacity layer is not a fade', () {
    final leaf = ContainerLayer();
    OpacityLayer(alpha: 255).append(leaf);
    expect(insideFade(leaf), isFalse);
    expect(insideFade(ContainerLayer()), isFalse);
  });
}
