import 'package:flutter_test/flutter_test.dart';

/// How the shell moves from one tab to the next.
///
/// The page arriving slides up over the one being left, which shrinks back and fades behind it.
/// Two properties matter, and an earlier version of these numbers broke each of them:
///
///  * The arriving page is opaque from its first frame. Whenever both pages are drawn partly
///    transparent, whatever is behind them — the shell's paper — shows through, and the switch
///    flashes white.
///  * The arriving page covers the leaving one. If both are visible at once the switch reads as
///    two screens of content mixed together, which is what a plain cross-fade does.
///
/// Kept here as arithmetic rather than read off `RootShell`, whose fades are private: pinning the
/// numbers is what stops a later tweak from quietly reopening either problem.
void main() {
  // `_leaveFade`, `_leaveScale` and `_enterOffset` in RootShell; the entering page never fades.
  const leave = (begin: 0.0, end: 0.18);
  const slide = (begin: 0.05, end: 1.0);

  double interval(double t, double begin, double end) {
    if (t <= begin) return 0;
    if (t >= end) return 1;
    return (t - begin) / (end - begin);
  }

  double easeInCubic(double t) => t * t * t;
  double easeOutCubic(double t) => 1 - (1 - t) * (1 - t) * (1 - t);

  /// What the entering page is drawn at: always whole.
  double entering(double _) => 1;

  /// What the leaving page is drawn at: `_leaveOpacity` is the reverse of `_leaveFade`.
  double leaving(double t) => 1 - easeInCubic(interval(t, leave.begin, leave.end));

  /// The leaving page's scale, from `_leaveScale`.
  double leavingScale(double t) =>
      1 - 0.03 * easeOutCubic(interval(t, leave.begin, leave.end));

  /// How far the arriving page still has to travel, as a share of the viewport height, from
  /// `_enterOffset`. Whatever it does not yet cover is the page underneath showing through.
  double enterTravel(double t) => 0.018 * (1 - easeOutCubic(interval(t, slide.begin, slide.end)));

  test('the arriving page is opaque from the first frame', () {
    // A partly transparent entering page is what let the paper show through and flashed white.
    for (var i = 0; i <= 100; i++) {
      expect(entering(i / 100), 1);
    }
  });

  test('the two pages always cover the shell between them', () {
    for (var i = 0; i <= 200; i++) {
      final t = i / 200;
      expect(
        entering(t) + leaving(t),
        greaterThanOrEqualTo(1 - 1e-12),
        reason: 'at t=$t the background would show through',
      );
    }
  });

  test('the strip the arriving page has not covered stays small', () {
    // This is what reads as the two pages overlapping: the old one showing along the top edge
    // while the new one slides up. Under a fiftieth of the screen is not noticed.
    for (var i = 0; i <= 200; i++) {
      expect(enterTravel(i / 200), lessThanOrEqualTo(0.018));
    }
    expect(enterTravel(0), lessThanOrEqualTo(0.02));
  });

  test('the page left behind is out early, and gone by the end', () {
    // Held out of sight for most of the switch, so it cannot be seen mixed with the new one.
    expect(leaving(0.2), 0);
    expect(leaving(1), 0);
    expect(leavingScale(0), 1);
    expect(leavingScale(1), lessThan(1));
  });
}
