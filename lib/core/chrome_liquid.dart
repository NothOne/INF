import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassButton, GlassContainer, GlassSheet, LiquidRoundedSuperellipse;

import 'liquid_glass.dart';
import 'look.dart' hide GlassSheet;

/// Liquid glass, drawn by `liquid_glass_widgets`: floating controls and sheets are its glass, under
/// the theme the sliders set (see [liquidGlassTheme]). Top bars, edge panels and the page behind
/// are the plain page colour: no frost, no veil, nothing tinted for glass to pick up.
class LiquidChrome extends GlassChrome {
  const LiquidChrome();

  /// Plain page colour, except on ultra, where the bar frosts over the list as it scrolls up
  /// behind it. Nothing is drawn at rest, so at the top of a page it is still the page.
  @override
  Widget? barBackground(BuildContext context) =>
      InfLook.of(context).liquidUltra ? const _LiquidBarFrost() : ColoredBox(color: Theme.of(context).colorScheme.surface);

  @override
  Widget backdrop(BuildContext context, {required Widget child}) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface, child: child);

  @override
  ActionIconThemeData get actionIconTheme => ActionIconThemeData(
        backButtonIconBuilder: (context) => const _BarRoundButton(icon: Icons.arrow_back_rounded, tooltip: '返回'),
        closeButtonIconBuilder: (context) => const _BarRoundButton(icon: Icons.close_rounded, tooltip: '关闭'),
      );

  /// The buttons share one glass capsule, as iOS 26 groups a bar's trailing items.
  @override
  List<Widget> barActions(BuildContext context, List<Widget> actions) {
    if (actions.isEmpty) return const [SizedBox(width: 4)];
    final quality = glassQualityOf(InfLook.of(context));
    return [
      Center(
        child: GlassContainer(
          useOwnLayer: true,
          quality: quality,
          height: _barControl,
          shape: const LiquidRoundedSuperellipse(borderRadius: _barControl / 2),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: IconButtonTheme(
            data: IconButtonThemeData(
              style: IconButton.styleFrom(
                minimumSize: const Size.square(_barControl),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                iconSize: 21,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
        ),
      ),
      const SizedBox(width: 10),
    ];
  }

  /// The tabs lie on a glass capsule, the chosen one on a tinted pill.
  @override
  Widget barTabs(
    BuildContext context, {
    required TabController controller,
    required List<Widget> labels,
    EdgeInsetsGeometry? labelPadding,
  }) {
    const height = 38.0;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 3, 12, InfChrome.barTabsHeight - height - 3),
      child: GlassContainer(
        useOwnLayer: true,
        quality: glassQualityOf(InfLook.of(context)),
        height: height,
        shape: const LiquidRoundedSuperellipse(borderRadius: height / 2),
        child: TabBar(
          controller: controller,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.all(3),
          indicator: ShapeDecoration(shape: const StadiumBorder(), color: scheme.primary.withValues(alpha: 0.14)),
          // A custom indicator would otherwise jump from one tab to the next; its own decoration
          // does not carry a position animation the way Material's default bar does.
          indicatorAnimation: TabIndicatorAnimation.elastic,
          dividerHeight: 0,
          splashBorderRadius: BorderRadius.circular(height / 2),
          labelPadding: labelPadding,
          tabs: [for (final label in labels) Tab(height: height, child: label)],
        ),
      ),
    );
  }

  @override
  Widget actionSheet(BuildContext context, {required Widget child}) => GlassSheet(child: child);

  @override
  Widget edgePanel(BuildContext context, {required Widget child}) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface, child: child);

  @override
  Widget floatingPanel(BuildContext context, {required BorderRadius radius, required Widget child, double body = 0}) =>
      GlassContainer(
        useOwnLayer: true,
        quality: glassQualityOf(InfLook.of(context)),
        shape: LiquidRoundedSuperellipse(borderRadius: radius.topLeft.x),
        child: child,
      );

  /// Glass with the accent as its icon, as iOS 26 draws a compose button: the colour marks the
  /// action without flooding a disc of it over the page. The tint carries only enough of it to keep
  /// the button findable at the clear end of 通透度.
  @override
  Widget floatingButton(
    BuildContext context, {
    required String tooltip,
    required Widget icon,
    required ValueChanged<BuildContext> onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return LiquidGlassTheme(
      tint: floatingButtonTint(context),
      child: Builder(
        builder: (buttonContext) => Tooltip(
          message: tooltip,
          child: GlassButton(
            useOwnLayer: true,
            quality: glassQualityOf(InfLook.of(context)),
            icon: icon,
            iconSize: 26,
            iconColor: scheme.primary,
            onTap: () => onPressed(buttonContext),
          ),
        ),
      ),
    );
  }

  /// The faint wash under the compose button's glass: the accent at a fifth, enough to tell it from
  /// the page behind it, nowhere near a filled button.
  @override
  Color floatingButtonTint(BuildContext context) =>
      Theme.of(context).colorScheme.primary.withValues(alpha: 0.32 - 0.22 * InfLook.of(context).liquidClarity);

  /// What [floatingCapsule]'s content is drawn in: on the glass, so it is the accent rather than
  /// white — the colour marks the action and the capsule stays clear.
  @override
  Color floatingCapsuleInk(BuildContext context) => Theme.of(context).colorScheme.primary;

  /// 通透度 thins the colour as it thins every other glass, so the sliders show on this button too:
  /// 0.32 at the solid end, 0.10 at the clear one.
  @override
  Widget floatingCapsule(BuildContext context, {required Widget child, VoidCallback? onTap}) {
    return GlassButton.custom(
      useOwnLayer: true,
      quality: glassQualityOf(InfLook.of(context)),
      shape: const LiquidRoundedSuperellipse(borderRadius: 20),
      enabled: onTap != null,
      onTap: onTap ?? () {},
      child: child,
    );
  }

  @override
  SnackBar snackBar(BuildContext context, Widget content) {
    final dark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    // White text needs a dark body whatever lies behind it.
    final tint = dark ? const Color(0xFF33343E) : const Color(0xFF2B2B33);
    return SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      content: LiquidGlassTheme(
        tint: tint.withValues(alpha: 0.78),
        child: GlassContainer(
          useOwnLayer: true,
          quality: glassQualityOf(InfLook.of(context)),
          shape: const LiquidRoundedSuperellipse(borderRadius: 16),
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

  /// Glass, thick enough to read a list of words over whatever it covers: the `menu` style the
  /// package measures for iOS 27's own menus, on the tier this look is set to.
  ///
  /// No `backerColor`: it is painted as an opaque pad under the glass, and the panel's shape changes
  /// every frame as it opens, so the pad is re-clipped each of those frames and shows through as a
  /// black block while the menu travels. The frost and the tint already carry the words — see
  /// `liquidGlassTheme` — and those cost nothing extra.
  @override
  Widget statusMenuSurface(BuildContext context, Widget child, BorderRadius radius) {
    return GlassContainer(
      useOwnLayer: true,
      quality: glassQualityOf(InfLook.of(context)),
      shape: LiquidRoundedSuperellipse(borderRadius: radius.topLeft.x),
      padding: EdgeInsets.zero,
      child: child,
    );
  }
}

/// Height of the glass controls in a top bar.
const _barControl = 40.0;

/// The top bar's frost on ultra: nothing at the top of a page, then a thin pane that grows as
/// content scrolls up under the bar.
///
/// It goes through [GlassSurface] rather than the package's `ProgressiveBlur` for one reason: that
/// widget falls back to a bare [BackdropFilter] when the engine has no shader filters, and a
/// backdrop filter inside the shell's fade turns grey — the exact defect `FadeSafeBackdrop` exists
/// to avoid (DEVLOG 2026-11-01). [GlassSurface] carries that guard, so the bar keeps its colour
/// through every tab and page fade on every backend.
class _LiquidBarFrost extends StatefulWidget {
  const _LiquidBarFrost();

  @override
  State<_LiquidBarFrost> createState() => _LiquidBarFrostState();
}

class _LiquidBarFrostState extends State<_LiquidBarFrost> {
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final look = InfLook.of(context);
    // Glass reads as glass by agreeing with what is behind it: a milky pane over a pale page, a
    // smoked one in dark mode, both as thin as the 通透度 slider says.
    final engaged = scheme.surface.withValues(alpha: look.tintAlpha(scheme.brightness));
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _scrolledUnder ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, t, _) => GlassSurface(
        // Nothing under the bar, nothing to frost: the page shows through untouched.
        strength: t,
        tint: engaged,
        rimSides: Border(
          bottom: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06 * t), width: 0.6),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// The back or close button of a top bar: a glass disc that pops the route. It stands in for the
/// icon of Material's button, and takes the tap itself so the glass can give under the finger.
class _BarRoundButton extends StatelessWidget {
  const _BarRoundButton({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) => GlassButton(
        useOwnLayer: true,
        quality: glassQualityOf(InfLook.of(context)),
        label: tooltip,
        width: _barControl,
        height: _barControl,
        iconSize: 21,
        iconColor: Theme.of(context).colorScheme.onSurface,
        icon: Icon(icon),
        onTap: () => Navigator.maybePop(context),
      );
}
