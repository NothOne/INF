import 'package:flutter/material.dart';

import 'chrome.dart';

/// Paper and ink: opaque surfaces, a hairline or a shadow where something sits above the page,
/// and no blur or translucency anywhere.
class ClassicChrome extends InfChrome {
  const ClassicChrome();

  @override
  bool get extendsBehindBars => false;

  @override
  bool get panelsCanFade => true;

  @override
  Widget? barBackground(BuildContext context) => null;

  /// One flat page colour. A wash at the top showed only behind the transparent bar and stopped
  /// where the opaque feed began, so the bar read as a tinted pane.
  @override
  Widget backdrop(BuildContext context, {required Widget child}) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface, child: child);

  @override
  bool get drawsActionSheet => false;

  @override
  Widget actionSheet(BuildContext context, {required Widget child}) => child;

  @override
  Widget edgePanel(BuildContext context, {required Widget child}) =>
      Material(color: Theme.of(context).colorScheme.surface, elevation: 8, child: child);

  @override
  Widget floatingPanel(BuildContext context, {required BorderRadius radius, required Widget child, double body = 0}) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: radius,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: scheme.brightness == Brightness.dark ? 0.32 : 0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget typingSheet(BuildContext context, {required BorderRadius radius, required Widget child}) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: radius,
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  @override
  Color fill(ColorScheme scheme, Color color, double alpha) => Color.alphaBlend(color.withValues(alpha: alpha), scheme.surface);
}
