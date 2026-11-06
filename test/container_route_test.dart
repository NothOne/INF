import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/container_route.dart';

void main() {
  test('the aligned page is invisible and sharp at the card, settled at the end', () {
    final start = containerAlignProfile(0);
    expect(start.opacity, 0);
    expect(start.blur, 0);
    expect(start.travel, 0);

    final end = containerAlignProfile(1);
    expect(end.opacity, 1);
    expect(end.blur, 0);
    expect(end.travel, 1);
  });

  test('the page is blurred wherever it is half dissolved into the card', () {
    for (var i = 0; i <= 100; i++) {
      final profile = containerAlignProfile(i / 100);
      if (profile.opacity > 0.15 && profile.opacity < 0.85) {
        expect(profile.blur, greaterThan(3), reason: 'sharp at t=${i / 100}, opacity ${profile.opacity}');
      }
    }
  });

  test('the page only gains opacity, and only starts moving once it is opaque', () {
    var previous = 0.0;
    for (var i = 0; i <= 100; i++) {
      final profile = containerAlignProfile(i / 100);
      expect(profile.opacity, greaterThanOrEqualTo(previous));
      previous = profile.opacity;
      if (profile.opacity < 1) expect(profile.travel, 0);
    }
  });

  test('out of range progress does not overshoot', () {
    expect(containerAlignProfile(-1).opacity, 0);
    expect(containerAlignProfile(-1).travel, 0);
    expect(containerAlignProfile(2).opacity, 1);
    expect(containerAlignProfile(2).travel, 1);
  });
}
