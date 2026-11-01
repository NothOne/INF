import 'package:flutter/material.dart';

import 'liquid_glass.dart';
import 'look.dart';

/// Liquid glass: the same places as [GlassChrome], but each pane is a lens. How hard it bends
/// follows how much text sits on it: floating controls bend fully, bars along one edge, and
/// sheets and panels mostly just catch the light.
class LiquidChrome extends GlassChrome {
  const LiquidChrome();

  @override
  Widget? barBackground(BuildContext context) => const LiquidBarBackground();

  @override
  Widget actionSheet(BuildContext context, {required Widget child}) => LiquidSheet(child: child);

  @override
  Widget edgePanel(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    final alpha = InfLook.of(context).liquidTintAlpha(scheme.brightness);
    return LiquidSurface(
      tint: scheme.surface.withValues(alpha: (alpha + 0.22).clamp(0.0, 0.94)),
      lens: const LiquidLens(bezel: 14, refraction: 0.6, dispersion: 0.12, edges: LiquidEdges.topOnly),
      child: child,
    );
  }

  @override
  Widget floatingPanel(BuildContext context, {required BorderRadius radius, required Widget child, double body = 0}) {
    final scheme = Theme.of(context).colorScheme;
    final alpha = InfLook.of(context).liquidTintAlpha(scheme.brightness);
    return LiquidPress(
      child: LiquidSurface(
        borderRadius: radius,
        lifted: true,
        tint: body == 0 ? null : scheme.surface.withValues(alpha: (alpha + body).clamp(0.0, 0.92)),
        child: child,
      ),
    );
  }

  @override
  Widget pressable(BuildContext context, {required Widget child}) => LiquidPress(child: child);

  @override
  AnimationStyle? get sheetMotion => const AnimationStyle(
        duration: Duration(milliseconds: 420),
        reverseDuration: Duration(milliseconds: 220),
        curve: Cubic(0.16, 1, 0.3, 1),
        reverseCurve: Curves.easeInCubic,
      );
}
