import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' show GlassTheme, GlassThemeData, GlassThemeSettings, GlassThemeVariant;

import 'look.dart';

/// The `liquid_glass_widgets` theme for the 液态玻璃 sliders. Each slider at its middle gives the
/// library's own iOS 27 preset: [InfLook.refraction] thickens the lens, [InfLook.liquidClarity]
/// thins the body and its frost, [InfLook.liquidShine] brightens the rim. [tint] replaces the body
/// colour for glass that carries a colour of its own.
GlassThemeData liquidGlassTheme(InfLook look, {Color? tint}) {
  GlassThemeSettings tune(GlassThemeSettings base, double body) => base.copyWith(
        glassColor: tint ?? base.glassColor!.withValues(alpha: body),
        thickness: 12 + 40 * look.refraction,
        refractiveIndex: 1.1 + 0.28 * look.refraction,
        frost: 28 * (1 - look.liquidClarity),
        rimLight: base.rimLight! * 2 * look.liquidShine,
      );
  final clarity = look.liquidClarity;
  return GlassThemeData(
    light: GlassThemeVariant.light.copyWith(settings: tune(GlassThemeSettings.ios27Light, 0.85 - 0.64 * clarity)),
    dark: GlassThemeVariant.dark.copyWith(settings: tune(GlassThemeSettings.ios27Dark, 0.22 - 0.2 * clarity)),
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
