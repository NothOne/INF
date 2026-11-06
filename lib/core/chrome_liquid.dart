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
      tint: scheme.surface.withValues(alpha: (alpha + 0.14).clamp(0.0, 0.94)),
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
  Widget floatingButton(
    BuildContext context, {
    required String tooltip,
    required Widget icon,
    required ValueChanged<BuildContext> onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Builder(
      builder: (buttonContext) => Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 56,
          height: 56,
          child: LiquidSurface(
            borderRadius: BorderRadius.circular(28),
            lifted: true,
            // A wash of the accent rather than a solid fill: enough colour to read as the action,
            // thin enough that the page still shows through.
            tint: floatingButtonTint(context),
            // A Material of its own, or the splash paints on the page's, under the tint.
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onPressed(buttonContext),
                child: Center(
                  child: IconTheme.merge(data: IconThemeData(color: scheme.onPrimaryContainer), child: icon),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Color floatingButtonTint(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.primary.withValues(alpha: scheme.brightness == Brightness.dark ? 0.42 : 0.34);
  }

  @override
  Widget floatingCapsule(BuildContext context, {required Widget child, VoidCallback? onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return LiquidPress(
      amount: 0.6,
      child: LiquidSurface(
        borderRadius: BorderRadius.circular(20),
        lifted: true,
        tint: scheme.primary.withValues(alpha: 0.75),
        lens: const LiquidLens(bezel: 12, refraction: 1.2, dispersion: 0.2, highlight: 1.1),
        // A Material of its own, or the splash paints on the page's, under the tint.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  SnackBar snackBar(BuildContext context, Widget content) {
    final dark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    // White text needs a dark body whatever lies behind it, so unlike other panes this one is not
    // the surface colour, and stays close to opaque.
    final tint = dark ? const Color(0xFF33343E) : const Color(0xFF2B2B33);
    return SnackBar(
      // The bar paints nothing; the pane inside does, so the page shows through at the rim.
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      content: LiquidSurface(
        borderRadius: BorderRadius.circular(16),
        // Not `lifted`: the SnackBar clips its child, so the shadow would be cut off at the edge.
        tint: tint.withValues(alpha: 0.78),
        lens: const LiquidLens(bezel: 12, refraction: 0.9, dispersion: 0.15, highlight: 1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white, fontSize: 14),
            child: content,
          ),
        ),
      ),
    );
  }

  @override
  AnimationStyle? get sheetMotion => const AnimationStyle(
        duration: Duration(milliseconds: 420),
        reverseDuration: Duration(milliseconds: 220),
        curve: Cubic(0.16, 1, 0.3, 1),
        reverseCurve: Curves.easeInCubic,
      );
}
