import 'package:flutter/material.dart';

import 'look.dart';
import 'prefs.dart' show VisualStyle;

import 'chrome_classic.dart';
import 'chrome_glass.dart';
import 'chrome_liquid.dart';

export 'chrome_classic.dart' show ClassicChrome;
export 'chrome_glass.dart' show GlassChrome;
export 'chrome_liquid.dart' show LiquidChrome;

/// The parts of a screen that belong to the visual style rather than to the page: bars, panels
/// and the fills of small surfaces. Each style is its own implementation, so a page asks for a
/// panel and never decides by itself whether something is see-through. Classic is all opaque;
/// only [GlassChrome] blurs or lets anything show through.
abstract class InfChrome {
  const InfChrome();

  static InfChrome of(BuildContext context) => forLook(InfLook.of(context));

  static InfChrome forLook(InfLook look) => switch (look.style) {
        VisualStyle.classic => const ClassicChrome(),
        VisualStyle.glass => const GlassChrome(),
        VisualStyle.liquid => const LiquidChrome(),
      };

  /// Whether page content runs up behind the top bar (and the bottom panels).
  bool get extendsBehindBars;

  /// Whether a panel may be faded out with an Opacity; otherwise it only slides.
  bool get panelsCanFade;

  /// The AppBar's `flexibleSpace`.
  Widget? barBackground(BuildContext context);

  /// The theme's back and close buttons; null keeps Material's.
  ActionIconThemeData? get actionIconTheme => null;

  /// A top bar's trailing buttons, with the gap after them.
  List<Widget> barActions(BuildContext context, List<Widget> actions) => [...actions, const SizedBox(width: 4)];

  /// Height of [barTabs], for the AppBar's `bottom`.
  static const barTabsHeight = 47.0;

  /// The row of tabs under a top bar's title.
  Widget barTabs(
    BuildContext context, {
    required TabController controller,
    required List<Widget> labels,
    EdgeInsetsGeometry? labelPadding,
  }) {
    return TabBar(
      controller: controller,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
      labelPadding: labelPadding,
      tabs: [for (final label in labels) Tab(height: barTabsHeight - 1, child: label)],
    );
  }

  /// What every page is laid on (see `PaperBackground`).
  Widget backdrop(BuildContext context, {required Widget child});

  /// Whether [actionSheet] draws the sheet itself, handle included; otherwise the modal's own
  /// material and drag handle are used.
  bool get drawsActionSheet;

  /// The body of an action or picker sheet.
  Widget actionSheet(BuildContext context, {required Widget child});

  /// A panel along the bottom edge that content scrolls under: the reply bar, the composer's
  /// toolbar, the chat input.
  Widget edgePanel(BuildContext context, {required Widget child});

  /// A control floating over the page, such as the tab bar. [body] thickens glass for small glyphs.
  Widget floatingPanel(BuildContext context, {required BorderRadius radius, required Widget child, double body = 0});

  /// A sheet raised to type in. Solid in every style: words being written sit on something solid.
  Widget typingSheet(BuildContext context, {required BorderRadius radius, required Widget child});

  /// [color] at [alpha] for a small surface (a quote box, a pill, a field). Classic flattens it
  /// onto the page colour, so nothing behind it ever shows through.
  Color fill(ColorScheme scheme, Color color, double alpha);

  /// A round button floating over the page, such as 发微博. [onPressed] gets the button's own
  /// context, which the page it opens grows out of.
  Widget floatingButton(
    BuildContext context, {
    required String tooltip,
    required Widget icon,
    required ValueChanged<BuildContext> onPressed,
  }) {
    return Builder(
      builder: (buttonContext) => FloatingActionButton(
        heroTag: null,
        elevation: 2,
        tooltip: tooltip,
        backgroundColor: floatingButtonTint(context),
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        onPressed: () => onPressed(buttonContext),
        child: icon,
      ),
    );
  }

  /// What [floatingButton] is filled with. The page it opens grows out of a disc of this colour, so
  /// the two have to agree.
  Color floatingButtonTint(BuildContext context) => Theme.of(context).colorScheme.primaryContainer;

  /// A small capsule floating over the page, such as the feed's “N 条新微博”. It lies on the
  /// primary colour, so [child] is drawn in `onPrimary`.
  Widget floatingCapsule(BuildContext context, {required Widget child, VoidCallback? onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      elevation: 3,
      shadowColor: Colors.black38,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: child,
      ),
    );
  }

  /// The transient message at the bottom of the page (see `showMessage`). Classic and glass keep
  /// the theme's inverse bar; liquid draws it as dark glass.
  SnackBar snackBar(BuildContext context, Widget content) => SnackBar(content: content);

  /// How sheets rise; null keeps the sheet's own motion.
  AnimationStyle? get sheetMotion => null;
}
