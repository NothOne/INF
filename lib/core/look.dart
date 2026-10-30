import 'dart:ui';

import 'package:flutter/material.dart';

import 'chrome.dart';
import 'prefs.dart';

export 'chrome.dart';

/// The visual style as seen by widgets: read it with [InfLook.of] instead of the preference, so
/// a subtree can be previewed in another style by overriding the theme.
@immutable
class InfLook extends ThemeExtension<InfLook> {
  const InfLook(this.style, {this.blur = defaultBlur, this.clarity = defaultClarity});

  final VisualStyle style;

  /// How strongly glass blurs what is behind it, 0–1. Zero is sharp.
  final double blur;

  /// How much of what is behind glass shows through its tint, 0–1.
  final double clarity;

  static const defaultBlur = 0.6;
  static const defaultClarity = 0.4;

  bool get glass => style == VisualStyle.glass;

  /// 0 is sharp glass, 1 the heaviest frost. The default still lands on the previous sigma,
  /// so opening the clear end does not shift a setting the user has not touched.
  double get blurSigma {
    const knee = defaultBlur;
    const kneeSigma = 6 + 34 * knee;
    const maxSigma = 40.0;
    if (blur <= knee) return kneeSigma * (blur / knee);
    final t = (blur - knee) / (1 - knee);
    return kneeSigma + (maxSigma - kneeSigma) * t;
  }

  /// Opacity of the surface colour glass is tinted with. The thick end and the default stay
  /// put; the clear end goes further so “通透” is actually thin.
  double tintAlpha(Brightness brightness) {
    final dusk = brightness == Brightness.dark ? 0.06 : 0.0;
    const knee = defaultClarity;
    final thick = 0.90 - dusk;
    final atDefault = 0.90 - 0.55 * knee - dusk;
    final thin = (0.08 - dusk).clamp(0.02, 1.0);
    if (clarity <= knee) return thick + (atDefault - thick) * (clarity / knee);
    final t = (clarity - knee) / (1 - knee);
    return atDefault + (thin - atDefault) * t;
  }

  static const classic = InfLook(VisualStyle.classic);

  static InfLook of(BuildContext context) => Theme.of(context).extension<InfLook>() ?? classic;

  @override
  InfLook copyWith({VisualStyle? style, double? blur, double? clarity}) =>
      InfLook(style ?? this.style, blur: blur ?? this.blur, clarity: clarity ?? this.clarity);

  @override
  InfLook lerp(InfLook? other, double t) {
    if (other == null) return this;
    return InfLook(
      t < 0.5 ? style : other.style,
      blur: lerpDouble(blur, other.blur, t)!,
      clarity: lerpDouble(clarity, other.clarity, t)!,
    );
  }
}

/// Blur plus a saturation lift, like iOS materials: plain blur over a colourful feed turns grey.
ImageFilter _glassFilter(double sigma, double strength) {
  final s = 1 + 0.6 * strength;
  final blur = sigma * strength;
  return ImageFilter.compose(
    outer: ColorFilter.matrix(<double>[
      0.2126 * (1 - s) + s, 0.7152 * (1 - s), 0.0722 * (1 - s), 0, 0,
      0.2126 * (1 - s), 0.7152 * (1 - s) + s, 0.0722 * (1 - s), 0, 0,
      0.2126 * (1 - s), 0.7152 * (1 - s), 0.0722 * (1 - s) + s, 0, 0,
      0, 0, 0, 1, 0,
    ]),
    inner: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
  );
}
/// A pane of frosted glass: whatever scrolls behind it is blurred, lifted and tinted, with a thin
/// bright rim along the edge that catches the light.
///
/// Glass comes in three depths. Chrome at rest (a bar with nothing under it) is a light milky
/// frost with a hairline, so it still reads as a pane over the page. Chrome that content passes
/// under frosts over fully. Floating controls (the tab bar, capsules over a list) are full glass
/// and [lifted] off the page by a soft shadow. A sheet raised to type in (the comment composer) is
/// not glass at all: words being written should sit on something solid.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.tint,
    this.rim = true,
    this.rimSides,
    this.strength = 1,
    this.lifted = false,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Overrides the default translucent surface colour.
  final Color? tint;
  final bool rim;

  /// Draw the rim only on these sides (for bars attached to a screen edge).
  final Border? rimSides;

  /// 0 is clear glass — nothing but the child — and 1 the full material; in between for fading
  /// it in. (An Opacity around the pane would cut the blur off from what is behind it.)
  final double strength;

  /// A soft shadow under the pane, for glass that floats over the page rather than edging it.
  final bool lifted;

  static Color rimOf(ColorScheme scheme) => scheme.brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.white.withValues(alpha: 0.75);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final look = InfLook.of(context);
    final k = strength.clamp(0.0, 1.0);
    final rimColor = rimOf(scheme);
    final tintColor = tint ?? scheme.surface.withValues(alpha: look.tintAlpha(scheme.brightness));
    final frosted = DecoratedBox(
      decoration: BoxDecoration(
        color: tintColor.withValues(alpha: tintColor.a * k),
      ),
      child: DecoratedBox(
        // The highlight sits behind the child. Painted on top, the white sheen
        // washes out icons and labels, worst on the small glyphs of a bar.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: (dark ? 0.06 : 0.22) * k),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0, 0.55],
          ),
        ),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            // A non-uniform border cannot be rounded; edge bars have square corners anyway.
            borderRadius: rimSides == null ? borderRadius : null,
            border: !rim
                ? null
                : rimSides ?? Border.all(color: rimColor.withValues(alpha: rimColor.a * k), width: dark ? 0.8 : 1),
          ),
          child: child,
        ),
      ),
    );
    // A zero-sigma BackdropFilter still allocates a save layer. That layer is what ghosts
    // text under Impeller, so sharp glass is only the tint.
    final sigma = look.blurSigma * k;
    final pane = ClipRRect(
      borderRadius: borderRadius,
      child: sigma < 0.5
          ? frosted
          : BackdropFilter(
              enabled: k > 0,
              filter: _glassFilter(look.blurSigma, k),
              child: frosted,
            ),
    );
    if (!lifted) return pane;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: (dark ? 0.34 : 0.08) * k),
            blurRadius: 22,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: pane,
    );
  }
}

/// The background of a top bar under glass: content scrolls up behind it. With nothing behind it
/// the bar rests as a light milky pane, a shade off the page with a hairline under it; it frosts
/// over once content scrolls under (as [AppBar] tracks its scrolled-under state).
class GlassBarBackground extends StatefulWidget {
  const GlassBarBackground({super.key});

  @override
  State<GlassBarBackground> createState() => _GlassBarBackgroundState();
}

class _GlassBarBackgroundState extends State<GlassBarBackground> {
  ScrollNotificationObserverState? _observer;
  bool _scrolledUnder = false;

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
    // Any depth: tabbed pages keep their lists inside a horizontal TabBarView.
    if (notification is! ScrollUpdateNotification || notification.metrics.axis != Axis.vertical) return;
    final under = notification.metrics.extentBefore > 0;
    if (under != _scrolledUnder) setState(() => _scrolledUnder = under);
  }

  /// How much of the material a bar keeps with nothing under it.
  static const _rest = 0.4;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final look = InfLook.of(context);
    final resting = Color.lerp(scheme.surface, scheme.surfaceContainer, 0.7)!.withValues(alpha: 0.72);
    final engaged = scheme.surface.withValues(alpha: look.tintAlpha(scheme.brightness));
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _scrolledUnder ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, t, child) {
        final k = lerpDouble(_rest, 1, t)!;
        final tint = Color.lerp(resting, engaged, t)!;
        return GlassSurface(
          strength: k,
          // GlassSurface scales the tint by the strength; this one is already the colour wanted.
          tint: tint.withValues(alpha: (tint.a / k).clamp(0.0, 1.0)),
          rimSides: Border(
            bottom: BorderSide(color: scheme.onSurface.withValues(alpha: lerpDouble(0.05, 0.08, t)!), width: 0.6),
          ),
          child: child!,
        );
      },
      child: const SizedBox.expand(),
    );
  }
}

/// A modal sheet as a pane of glass, with its own drag handle (the system one would sit on the
/// sheet's opaque material, outside the blur).
class GlassSheet extends StatelessWidget {
  const GlassSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alpha = InfLook.of(context).tintAlpha(scheme.brightness);
    return GlassSurface(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      // A sheet holds text over a dimmed page: more body than a bar.
      tint: scheme.surface.withValues(alpha: (alpha + 0.12).clamp(0.0, 0.95)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            child: Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// The AppBar background for the current style (see [InfChrome.barBackground]).
Widget? lookBarBackground(BuildContext context) => InfChrome.of(context).barBackground(context);
