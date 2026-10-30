import 'package:flutter/material.dart';

import 'look.dart';

export 'chrome_classic.dart' show ClassicChrome;
export 'chrome_glass.dart' show GlassChrome;

/// The parts of a screen that belong to the visual style rather than to the page: bars, panels
/// and the fills of small surfaces. Each style is its own implementation, so a page asks for a
/// panel and never decides by itself whether something is see-through. Classic is all opaque;
/// only [GlassChrome] blurs or lets anything show through.
abstract class InfChrome {
  const InfChrome();

  static InfChrome of(BuildContext context) =>
      InfLook.of(context).glass ? const GlassChrome() : const ClassicChrome();

  static InfChrome forLook(InfLook look) => look.glass ? const GlassChrome() : const ClassicChrome();

  /// Whether page content runs up behind the top bar (and the bottom panels).
  bool get extendsBehindBars;

  /// Whether a panel may be faded out with an Opacity; otherwise it only slides.
  bool get panelsCanFade;

  /// The AppBar's `flexibleSpace`.
  Widget? barBackground(BuildContext context);

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
}
