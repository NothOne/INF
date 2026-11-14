import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show
        AdaptiveLiquidGlassLayer,
        GlassAdaptiveScope,
        GlassAdaptiveScopeData,
        GlassQuality,
        GlassQualityChangeReason,
        GlassTheme,
        GlassThemeData,
        GlassThemeSettings,
        GlassThemeVariant;
import 'look.dart';
import 'prefs.dart' show LiquidTier;

/// The `liquid_glass_widgets` theme for the 液态玻璃 sliders. Each slider at its middle gives the
/// library's own iOS 27 preset: [InfLook.refraction] thickens the lens, [InfLook.liquidClarity]
/// thins the body and its frost, [InfLook.liquidShine] brightens the rim. [tint] replaces the body
/// colour for glass that carries a colour of its own.
///
/// The tier only changes the rim's ceiling: standard keeps the light shader's soft edge, ultra
/// spends the brighter one iOS 27 measures on its controls. Everything else the shaders share
/// stays at the slider's value, so switching tiers never moves a slider the user set.
GlassThemeData liquidGlassTheme(InfLook look, {Color? tint}) {
  GlassThemeSettings tune(GlassThemeSettings base, double body) => base.copyWith(
        glassColor: tint ?? base.glassColor!.withValues(alpha: body),
        thickness: 12 + 40 * look.refraction,
        refractiveIndex: 1.1 + 0.28 * look.refraction,
        frost: 28 * (1 - look.liquidClarity),
        rimLight: base.rimLight! * (look.liquidUltra ? 2.4 : 2) * look.liquidShine,
      );
  final clarity = look.liquidClarity;
  return GlassThemeData(
    light: GlassThemeVariant.light.copyWith(
      settings: tune(GlassThemeSettings.ios27Light, 0.85 - 0.64 * clarity),
    ),
    dark: GlassThemeVariant.dark.copyWith(
      settings: tune(GlassThemeSettings.ios27Dark, 0.22 - 0.2 * clarity),
    ),
  );
}

/// [liquidGlassTheme] for the look in the surrounding theme, so a preview with a look of its own
/// follows its own sliders.
class LiquidGlassTheme extends StatelessWidget {
  const LiquidGlassTheme({super.key, this.tint, required this.child});

  final Color? tint;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      GlassTheme(data: liquidGlassTheme(InfLook.of(context), tint: tint), child: child);
}

/// The quality a glass surface asks for on [look]'s tier.
///
/// [InfGlassQuality]'s ceiling can only hold a surface *down*, so it makes standard reach every
/// widget without a word at its call site, but it cannot lift one: a [GlassButton] defaults to
/// [GlassQuality.standard] and would stay there on ultra. The few surfaces that should draw the
/// full bevel on ultra say so with this.
GlassQuality glassQualityOf(InfLook look) =>
    look.liquidUltra ? GlassQuality.premium : GlassQuality.standard;

/// Whether the glass here is drawing at [GlassQuality.premium] right now.
///
/// This decides whether two glass surfaces may be merged: a merged member gives up its own layer
/// and draws into the one [GlassMerge] provides. It asks the same question
/// [AdaptiveLiquidGlassLayer] asks before it builds that layer — the adaptive scope's ceiling and
/// a runtime shader — so the two cannot disagree about whether the layer exists.
bool glassIsPremium(BuildContext context) {
  if (!ImageFilter.isShaderFilterSupported) return false;
  final adaptive = GlassAdaptiveScopeData.maybeOf(context)?.effectiveQuality;
  return (adaptive ?? glassQualityOf(InfLook.of(context))) == GlassQuality.premium;
}

/// Draws its children's glass as one surface that flows together under a finger, as iOS 26's
/// `GlassEffectContainer` does: neighbours closer than [blend] grow a neck into each other when
/// what they carry swells under the touch, and draw as separate controls at rest.
///
/// Only wrap children that were built for it — each with [GlassQuality.premium] and
/// `useOwnLayer: false`, so it gives its own layer up to this one. Ask [glassIsPremium] once at the
/// call site and use that same answer for both, rather than asking again in here: a merged member
/// and this layer have to agree, and a member without a layer has nothing to fall back on when
/// this one is not there.
class GlassMerge extends StatelessWidget {
  const GlassMerge({super.key, required this.child, this.blend = 14});

  final Widget child;

  /// How far apart, in dp, two surfaces begin to bulge toward each other. A fused field closes
  /// over a gap of about half of it, so 14 bridges at 7: a row of controls 10 apart still reads as
  /// a row at rest, and the 4 dp a press swells each one closes the rest.
  final double blend;

  @override
  Widget build(BuildContext context) => AdaptiveLiquidGlassLayer(
        quality: GlassQuality.premium,
        blendAmount: blend,
        child: child,
      );
}

/// Caps every glass surface below at the tier's quality, and on [LiquidTier.ultra] steps down a
/// level by itself when this device cannot keep the frames up.
///
/// The cap is what makes one tier reach widgets that never say `quality:` themselves: every glass
/// widget resolves its quality through `GlassThemeHelpers.resolveQuality`, whose last step compares
/// the result against this scope's ceiling, so standard needs no call site changed. Ultra starts at
/// [GlassQuality.premium] and steps itself down to standard when raster frames stay over budget —
/// the frost goes first, its cost being out of all proportion to how much of it shows. The step
/// down is then *offered* through [onDowngraded] rather than applied silently: a page that stutters
/// once should not quietly lose a look the user chose.
class InfGlassQuality extends StatefulWidget {
  const InfGlassQuality({super.key, required this.look, this.onDowngraded, required this.child});

  final InfLook look;

  /// Called once per session, when ultra steps itself down because the device could not keep up.
  /// Whoever shows the question is expected to turn it into a choice; a device that never had the
  /// capability (no Impeller, web) does not reach here, as that is not something the user can fix.
  final VoidCallback? onDowngraded;

  final Widget child;

  /// Whether [reason] means "this device is too slow right now", as opposed to "this build can
  /// never draw premium glass". The static probe's verdict is not something a user can act on, so
  /// telling them about it would only nag on every cold start; a warm-up or thermal verdict is.
  static bool isSlowDevice(GlassQualityChangeReason reason) => switch (reason) {
        GlassQualityChangeReason.warmupComplete ||
        GlassQualityChangeReason.thermalDegradation =>
          true,
        GlassQualityChangeReason.staticProbe ||
        GlassQualityChangeReason.restoredFromCache ||
        GlassQualityChangeReason.thermalRecovery =>
          false,
      };

  @override
  State<InfGlassQuality> createState() => _InfGlassQualityState();
}

class _InfGlassQualityState extends State<InfGlassQuality> {
  /// Bumped to rebuild the scope when the user asks for the premium glass back after a step down.
  int _generation = 0;

  /// Set once the question has been put this run, so it cannot come back. The scope restarts with
  /// [_generation] every time ultra steps down (frost first, then the tier), and each of those is
  /// another diagnostic — without this, a device that cannot keep up asked again on every step.
  bool _asked = false;

  /// The frame budget the glass is measured against. Ultra's cost is fixed per frame, so the
  /// honest budget is the one this device can actually reach, not the panel's ceiling: on a
  /// HarmonyOS tablet the engine reports 60 whatever the screen can do (`UpdateDisplayRefreshRate`
  /// reads the current vsync period and snaps it to a set that only ever holds 60), and ultra draws
  /// its frame in ~15.7 ms there — a steady 60 fps. An 8 ms budget called that "too slow" and
  /// stepped down a look the reader chose, on a device drawing it as fast as the platform allows.
  int _budgetMs() {
    final rate = View.of(context).display.refreshRate;
    if (rate <= 0) return 16;
    // Floor, so a 120 Hz frame gets the 8 ms it actually has rather than 8.33 rounded up.
    return (1000 / rate).floor().clamp(8, 33);
  }

  void _askAboutDowngrade() {
    if (_asked) return;
    _asked = true;
    widget.onDowngraded?.call();
    // A new scope so the glass tries the tier again; the question itself is not asked twice.
    setState(() => _generation++);
  }

  @override
  Widget build(BuildContext context) {
    final ultra = widget.look.liquidUltra;
    return GlassAdaptiveScope(
      // A new key restarts the adapter, which is how the premium glass comes back if the step down
      // is turned down: the scope steps itself down on its own diagnostics, and only a fresh
      // adapter can be told to try premium again.
      key: ValueKey<int>(_generation),
      minQuality: ultra ? GlassQuality.standard : GlassQuality.minimal,
      maxQuality: ultra ? GlassQuality.premium : GlassQuality.standard,
      initialQuality: ultra ? GlassQuality.premium : GlassQuality.standard,
      targetFrameMs: _budgetMs(),
      // Ultra may step back up once the device recovers (after thermal throttling, say).
      allowStepUp: true,
      frostStep: true,
      onDiagnostic: (diagnostic) {
        // Only a step away from ultra's own glass is worth a question. Standard has nowhere lower
        // to offer, and asking there would offer the tier the reader is already on.
        if (!ultra) return;
        if (diagnostic.to == GlassQuality.premium) return;
        if (!InfGlassQuality.isSlowDevice(diagnostic.reason)) return;
        _askAboutDowngrade();
      },
      child: widget.child,
    );
  }
}

/// Holds the glass inside it at [GlassQuality.standard] while [active], for a change that redraws
/// the glass every frame and cannot wait for it.
///
/// Premium glass draws through its own compositing layer, which reads the backdrop again on each
/// frame; a tab cross-fade puts that layer inside a translucent one, and the two do not agree
/// frame by frame — the shell's bar and the strip under a page's title flicker for as long as the
/// fade runs. Standard quality paints inside the page's own layer instead, so it fades as one
/// piece. Measured on a vivo V2419A: the flicker stops entirely once the device steps ultra down
/// to standard, which is what this does for the length of the switch only.
class GlassDuring extends StatelessWidget {
  const GlassDuring({super.key, required this.active, required this.child});

  /// Whether the glass below should be held at standard right now.
  final bool active;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return GlassAdaptiveScope(
      minQuality: GlassQuality.standard,
      maxQuality: GlassQuality.standard,
      initialQuality: GlassQuality.standard,
      // No measuring, no stepping: this cap is the reason the scope exists here.
      allowStepUp: false,
      child: child,
    );
  }
}
