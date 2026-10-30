import 'package:flutter/material.dart';

import 'look.dart';

/// Frosted glass, in the three depths [GlassSurface] describes: resting and engaged bars, edge
/// panels the content scrolls under, and floating controls lifted off the page.
class GlassChrome extends InfChrome {
  const GlassChrome();

  @override
  bool get extendsBehindBars => true;

  /// A blur inside a fading layer only sees that (empty) layer, so glass would turn clear for the
  /// length of the fade.
  @override
  bool get panelsCanFade => false;

  @override
  Widget? barBackground(BuildContext context) => const GlassBarBackground();

  @override
  Widget backdrop(BuildContext context, {required Widget child}) => _AmbientLight(child: child);

  @override
  bool get drawsActionSheet => true;

  @override
  Widget actionSheet(BuildContext context, {required Widget child}) => GlassSheet(child: child);

  @override
  Widget edgePanel(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      rimSides: Border(top: BorderSide(color: scheme.onSurface.withValues(alpha: 0.08), width: 0.6)),
      tint: scheme.surface.withValues(
        alpha: (InfLook.of(context).tintAlpha(scheme.brightness) + 0.12).clamp(0.0, 0.94),
      ),
      child: child,
    );
  }

  @override
  Widget floatingPanel(BuildContext context, {required BorderRadius radius, required Widget child, double body = 0}) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      borderRadius: radius,
      lifted: true,
      tint: body == 0
          ? null
          : scheme.surface.withValues(
              alpha: (InfLook.of(context).tintAlpha(scheme.brightness) + body).clamp(0.0, 0.92),
            ),
      child: child,
    );
  }

  @override
  Widget typingSheet(BuildContext context, {required BorderRadius radius, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45), width: 0.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  @override
  Color fill(ColorScheme scheme, Color color, double alpha) => color.withValues(alpha: alpha);
}

/// The backdrop glass is laid over: two faint pools of the accent colours behind the top bar,
/// which its frost picks up and the content scrolls over. Kept to the top so text never sits on
/// colour.
class _AmbientLight extends StatelessWidget {
  const _AmbientLight({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    RadialGradient pool(Alignment center, Color color, double alpha) => RadialGradient(
      center: center,
      radius: 1.1,
      colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
    );
    return ColoredBox(
      color: scheme.surface,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 260,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: pool(const Alignment(-0.9, -1.2), scheme.primary, dark ? 0.16 : 0.09),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: pool(const Alignment(1.0, -1.0), scheme.tertiary, dark ? 0.12 : 0.07),
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
